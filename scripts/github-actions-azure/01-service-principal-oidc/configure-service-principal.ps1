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
    [string[]]$Environments = @('dev', 'staging', 'production'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Roles = @('Contributor', 'Role Based Access Control Administrator')
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
$accountJson = & az account show --query '{id:id,name:name}' --output json --only-show-errors
Assert-LastExitCode 'Azure CLI session check'
$account = $accountJson | ConvertFrom-Json
$null = & gh auth status 2>&1
Assert-LastExitCode 'GitHub CLI session check'

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) {
    $SubscriptionId = [string]$account.id
}
$scope = "/subscriptions/$SubscriptionId"
Write-Host "Subscription: $($account.name) ($SubscriptionId)"

# --- 1. App Registration: create-if-missing, secretless-if-existing ---
$applicationJson = & az ad app list `
    --display-name $ApplicationDisplayName `
    --query '[].{id:id,appId:appId,displayName:displayName,keyCredentials:keyCredentials,passwordCredentials:passwordCredentials}' `
    --output json `
    --only-show-errors
Assert-LastExitCode "Lookup of App Registration '$ApplicationDisplayName'"
$applications = @($applicationJson | ConvertFrom-Json)

if ($applications.Count -gt 1) {
    throw "More than one App Registration is named '$ApplicationDisplayName'."
}

if ($applications.Count -eq 0) {
    if (-not $PSCmdlet.ShouldProcess($ApplicationDisplayName, 'Create App Registration (single-tenant, no credentials)')) {
        throw "App Registration '$ApplicationDisplayName' does not exist and creation was skipped; cannot continue."
    }
    $createdJson = & az ad app create `
        --display-name $ApplicationDisplayName `
        --sign-in-audience AzureADMyOrg `
        --output json `
        --only-show-errors
    Assert-LastExitCode "Creation of App Registration '$ApplicationDisplayName'"
    $application = $createdJson | ConvertFrom-Json
    Write-Host "[CREATED] App Registration '$ApplicationDisplayName' ($($application.appId))."
}
else {
    $application = $applications[0]
    $credentialCount = @($application.keyCredentials).Count + @($application.passwordCredentials).Count
    if ($credentialCount -ne 0) {
        throw "App Registration '$ApplicationDisplayName' has $credentialCount long-lived credential(s); expected zero for an OIDC-only identity."
    }
    Write-Host "[EXISTS] App Registration '$ApplicationDisplayName' ($($application.appId))."
}

# --- 2. Service principal: create-if-missing ---
$servicePrincipalJson = & az ad sp list `
    --filter "appId eq '$($application.appId)'" `
    --query '[].{id:id,appId:appId}' `
    --output json `
    --only-show-errors
Assert-LastExitCode 'Service principal lookup'
$servicePrincipals = @($servicePrincipalJson | ConvertFrom-Json)

if ($servicePrincipals.Count -gt 1) {
    throw "More than one service principal exists for appId '$($application.appId)'."
}

$servicePrincipal = $null
if ($servicePrincipals.Count -eq 0) {
    if ($PSCmdlet.ShouldProcess($application.appId, 'Create service principal')) {
        $spCreatedJson = & az ad sp create --id $application.appId --output json --only-show-errors
        Assert-LastExitCode 'Service principal creation'
        $servicePrincipal = $spCreatedJson | ConvertFrom-Json
        Write-Host "[CREATED] Service principal ($($servicePrincipal.id))."
    }
    else {
        $skippedChange = $true
    }
}
else {
    $servicePrincipal = $servicePrincipals[0]
    Write-Host "[EXISTS] Service principal ($($servicePrincipal.id))."
}

# --- 3. Federated credentials, one per GitHub Environment ---
$oidcConfigurationJson = & gh api "repos/$Repository/actions/oidc/customization/sub"
Assert-LastExitCode "Lookup of GitHub OIDC configuration for '$Repository'"
$oidcConfiguration = $oidcConfigurationJson | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($oidcConfiguration.sub_claim_prefix)) {
    throw "GitHub did not return an OIDC subject prefix for '$Repository'."
}
$subjectPrefix = [string]$oidcConfiguration.sub_claim_prefix
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
        Write-Host "[EXISTS] $credentialName trusts '$expectedSubject'."
        continue
    }

    $action = if ($current.Count -eq 1) { 'Update' } else { 'Create' }
    if (-not $PSCmdlet.ShouldProcess($credentialName, "$action subject '$expectedSubject'")) {
        $skippedChange = $true
        continue
    }

    $parameters = @{
        issuer      = $issuer
        subject     = $expectedSubject
        audiences   = @($audience)
        description = "GitHub Actions - MovieOps $environment"
    }
    if ($current.Count -eq 0) {
        $parameters.name = $credentialName
    }

    $payload = $parameters | ConvertTo-Json -Compress
    $payloadPath = Join-Path ([System.IO.Path]::GetTempPath()) "movieops-oidc-$([guid]::NewGuid()).json"
    try {
        Set-Content -LiteralPath $payloadPath -Value $payload -Encoding utf8NoBOM
        if ($current.Count -eq 1) {
            $null = & az ad app federated-credential update `
                --id $application.id `
                --federated-credential-id $credentialName `
                --parameters $payloadPath `
                --output none `
                --only-show-errors
            Assert-LastExitCode "Update of '$credentialName'"
            Write-Host "[UPDATED] $credentialName"
        }
        else {
            $null = & az ad app federated-credential create `
                --id $application.id `
                --parameters $payloadPath `
                --output none `
                --only-show-errors
            Assert-LastExitCode "Creation of '$credentialName'"
            Write-Host "[CREATED] $credentialName"
        }
    }
    finally {
        if (Test-Path -LiteralPath $payloadPath) {
            Remove-Item -LiteralPath $payloadPath -Force
        }
    }
}

# --- 4. Subscription role assignments ---
if ($null -ne $servicePrincipal) {
    $assignmentsJson = & az role assignment list `
        --assignee $application.appId `
        --scope $scope `
        --query '[].{role:roleDefinitionName,scope:scope}' `
        --output json `
        --only-show-errors
    Assert-LastExitCode 'Role assignment lookup'
    $assignments = @($assignmentsJson | ConvertFrom-Json)

    foreach ($role in $Roles) {
        $existing = @($assignments | Where-Object { $_.role -ceq $role -and $_.scope -ceq $scope })

        if ($existing.Count -ge 1) {
            Write-Host "[EXISTS] '$role' already assigned at the subscription scope."
            continue
        }

        if ($PSCmdlet.ShouldProcess($scope, "Assign role '$role' to $ApplicationDisplayName")) {
            $null = & az role assignment create `
                --assignee-object-id $servicePrincipal.id `
                --assignee-principal-type ServicePrincipal `
                --role $role `
                --scope $scope `
                --output none `
                --only-show-errors
            Assert-LastExitCode "Assignment of role '$role'"
            Write-Host "[CREATED] '$role' assigned at the subscription scope."
        }
        else {
            $skippedChange = $true
        }
    }
}
else {
    $skippedChange = $true
}

if ($skippedChange) {
    Write-Host 'Some changes were skipped; final state verification was not performed.'
    return
}

# --- Final verification ---
$verifiedCredsJson = & az ad app federated-credential list `
    --id $application.id `
    --query '[].{name:name,issuer:issuer,subject:subject,audiences:audiences}' `
    --output json `
    --only-show-errors
Assert-LastExitCode 'Final federated credential verification'
$verifiedCreds = @($verifiedCredsJson | ConvertFrom-Json)

foreach ($environment in $Environments) {
    $credentialName = "github-environment-$environment"
    $expectedSubject = "${subjectPrefix}:environment:${environment}"
    $verified = @($verifiedCreds | Where-Object { $_.name -eq $credentialName })

    if ($verified.Count -ne 1 -or $verified[0].subject -cne $expectedSubject) {
        throw "Verification failed for '$credentialName'. Expected subject '$expectedSubject'."
    }
}

$verifiedRolesJson = & az role assignment list `
    --assignee $application.appId `
    --scope $scope `
    --query '[].{role:roleDefinitionName,scope:scope}' `
    --output json `
    --only-show-errors
Assert-LastExitCode 'Final role assignment verification'
$verifiedRoles = @($verifiedRolesJson | ConvertFrom-Json)

foreach ($role in $Roles) {
    if (-not ($verifiedRoles | Where-Object { $_.role -ceq $role })) {
        throw "Verification failed: role '$role' is not assigned at '$scope'."
    }
}

Write-Host "`n[VERIFIED] Service principal bootstrap for '$ApplicationDisplayName' completed."
Write-Host "App ID: $($application.appId)"
$verifiedCreds |
    Where-Object { $_.name -in ($Environments | ForEach-Object { "github-environment-$_" }) } |
    Sort-Object name |
    Format-Table name, subject -AutoSize
$verifiedRoles |
    Where-Object { $_.role -in $Roles } |
    Sort-Object role |
    Format-Table role, scope -AutoSize
