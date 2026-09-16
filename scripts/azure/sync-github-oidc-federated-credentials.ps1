[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApplicationDisplayName = 'github-movieops-terraform',

    [Parameter()]
    [ValidatePattern('^[^/]+/[^/]+$')]
    [string]$Repository = 'ajunquit/movieops',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Environments = @('dev', 'staging', 'production')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issuer = 'https://token.actions.githubusercontent.com'
$audience = 'api://AzureADTokenExchange'
$skippedChange = $false

function Assert-LastExitCode {
    param([Parameter(Mandatory)][string]$Operation)

    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed with exit code $LASTEXITCODE."
    }
}

foreach ($command in @('az', 'gh')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command '$command' was not found in PATH."
    }
}

Write-Host 'Checking Azure CLI and GitHub CLI sessions...'
$null = & az account show --output none --only-show-errors
Assert-LastExitCode 'Azure CLI session check'
$null = & gh auth status 2>&1
Assert-LastExitCode 'GitHub CLI session check'

$applicationJson = & az ad app list `
    --display-name $ApplicationDisplayName `
    --query '[].{id:id,appId:appId,displayName:displayName}' `
    --output json `
    --only-show-errors
Assert-LastExitCode "Lookup of App Registration '$ApplicationDisplayName'"

$applications = @($applicationJson | ConvertFrom-Json)
if ($applications.Count -ne 1) {
    throw "Expected exactly one App Registration named '$ApplicationDisplayName'; found $($applications.Count)."
}

$application = $applications[0]

$oidcConfigurationJson = & gh api "repos/$Repository/actions/oidc/customization/sub"
Assert-LastExitCode "Lookup of GitHub OIDC configuration for '$Repository'"
$oidcConfiguration = $oidcConfigurationJson | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($oidcConfiguration.sub_claim_prefix)) {
    throw "GitHub did not return an OIDC subject prefix for '$Repository'."
}

$subjectPrefix = [string]$oidcConfiguration.sub_claim_prefix
Write-Host "App Registration: $($application.displayName) ($($application.appId))"
Write-Host "GitHub OIDC prefix: $subjectPrefix"
Write-Host "Immutable subjects enabled: $($oidcConfiguration.use_immutable_subject)"

$credentialsJson = & az ad app federated-credential list `
    --id $application.id `
    --output json `
    --only-show-errors
Assert-LastExitCode 'Federated credential lookup'
$credentials = @($credentialsJson | ConvertFrom-Json)

foreach ($environment in $Environments) {
    $credentialName = "github-environment-$environment"
    $expectedSubject = "${subjectPrefix}:environment:${environment}"
    $description = "GitHub Actions - MovieOps $environment"
    $current = @($credentials | Where-Object { $_.name -eq $credentialName })

    if ($current.Count -gt 1) {
        throw "More than one federated credential is named '$credentialName'."
    }

    $isCurrent = $current.Count -eq 1 -and
        $current[0].issuer -ceq $issuer -and
        $current[0].subject -ceq $expectedSubject -and
        @($current[0].audiences).Count -eq 1 -and
        @($current[0].audiences)[0] -ceq $audience

    if ($isCurrent) {
        Write-Host "[OK] $credentialName already trusts '$expectedSubject'."
        continue
    }

    $parameters = @{
        issuer      = $issuer
        subject     = $expectedSubject
        audiences   = @($audience)
        description = $description
    }

    if ($current.Count -eq 1) {
        if ($PSCmdlet.ShouldProcess($credentialName, "Update subject to '$expectedSubject'")) {
            $payload = $parameters | ConvertTo-Json -Compress
            $payloadPath = Join-Path ([System.IO.Path]::GetTempPath()) "movieops-oidc-$([guid]::NewGuid()).json"
            try {
                Set-Content -LiteralPath $payloadPath -Value $payload -Encoding utf8NoBOM
                $null = & az ad app federated-credential update `
                    --id $application.id `
                    --federated-credential-id $credentialName `
                    --parameters $payloadPath `
                    --output none `
                    --only-show-errors
                Assert-LastExitCode "Update of '$credentialName'"
            }
            finally {
                if (Test-Path -LiteralPath $payloadPath) {
                    Remove-Item -LiteralPath $payloadPath -Force
                }
            }
            Write-Host "[UPDATED] $credentialName"
        }
        else {
            $skippedChange = $true
        }
    }
    else {
        $parameters.name = $credentialName
        if ($PSCmdlet.ShouldProcess($credentialName, "Create with subject '$expectedSubject'")) {
            $payload = $parameters | ConvertTo-Json -Compress
            $payloadPath = Join-Path ([System.IO.Path]::GetTempPath()) "movieops-oidc-$([guid]::NewGuid()).json"
            try {
                Set-Content -LiteralPath $payloadPath -Value $payload -Encoding utf8NoBOM
                $null = & az ad app federated-credential create `
                    --id $application.id `
                    --parameters $payloadPath `
                    --output none `
                    --only-show-errors
                Assert-LastExitCode "Creation of '$credentialName'"
            }
            finally {
                if (Test-Path -LiteralPath $payloadPath) {
                    Remove-Item -LiteralPath $payloadPath -Force
                }
            }
            Write-Host "[CREATED] $credentialName"
        }
        else {
            $skippedChange = $true
        }
    }
}

if ($skippedChange) {
    Write-Host 'Some changes were skipped; final state verification was not performed.'
    return
}

$verifiedJson = & az ad app federated-credential list `
    --id $application.id `
    --query '[].{name:name,issuer:issuer,subject:subject,audiences:audiences}' `
    --output json `
    --only-show-errors
Assert-LastExitCode 'Final federated credential verification'
$verifiedCredentials = @($verifiedJson | ConvertFrom-Json)

foreach ($environment in $Environments) {
    $credentialName = "github-environment-$environment"
    $expectedSubject = "${subjectPrefix}:environment:${environment}"
    $verified = @($verifiedCredentials | Where-Object { $_.name -eq $credentialName })

    if ($verified.Count -ne 1 -or $verified[0].subject -cne $expectedSubject) {
        throw "Verification failed for '$credentialName'. Expected subject '$expectedSubject'."
    }
}

Write-Host "`nFederated credentials verified:"
$verifiedCredentials |
    Where-Object { $_.name -in ($Environments | ForEach-Object { "github-environment-$_" }) } |
    Sort-Object name |
    Format-Table name, subject -AutoSize
