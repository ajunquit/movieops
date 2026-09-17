#Requires -Version 7.0

<#
.SYNOPSIS
Verifies stable Terraform automation identities before ADOP-3 pipelines.

.DESCRIPTION
Resolves the GitHub Actions and Azure DevOps service principals, runs Terraform
fmt/init/validate/plan without apply, and proves that both Key Vault role
assignments are present without deleting the GitHub assignment.

.EXAMPLE
./scripts/azure-devops/08-stabilize-terraform-identities/verify-terraform-identities.ps1
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$GitHubApplicationDisplayName = 'github-movieops-terraform',

    [Parameter()]
    [string]$AzureDevOpsApplicationDisplayName = 'azure-devops-movieops-wif',

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$ExpectedGitHubObjectId = '36edcd2d-3ad8-4aa7-ad5e-e5998f17da2f',

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$ExpectedAzureDevOpsObjectId = '4fbfb3ed-ea64-4c58-85b2-eec87d5f21fb',

    [Parameter()]
    [string]$EnvironmentPath = 'terraform/environments/azure/dev'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:TF_IN_AUTOMATION = 'true'

$RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$TerraformRoot = Join-Path $RepositoryRoot 'terraform'
$EnvironmentFullPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot $EnvironmentPath))
$Results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][string]$Control,
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Evidence
    )

    $Results.Add([pscustomobject]@{
            Status   = if ($Passed) { 'PASS' } else { 'FAIL' }
            Control  = $Control
            Evidence = $Evidence
        })
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Operation,
        [Parameter()][int[]]$AllowedExitCodes = @(0)
    )

    $output = @(& $Command @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -notin $AllowedExitCodes) {
        throw "$Operation failed with exit code $exitCode.`n$($output -join [Environment]::NewLine)"
    }
    foreach ($line in $output) {
        Write-Host $line
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

function Get-ServicePrincipal {
    param([Parameter(Mandatory)][string]$ApplicationDisplayName)

    $appsJson = & az ad app list `
        --display-name $ApplicationDisplayName `
        --query '[].{id:id,appId:appId,displayName:displayName,keyCredentials:keyCredentials,passwordCredentials:passwordCredentials}' `
        --output json `
        --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        throw "App Registration lookup failed for '$ApplicationDisplayName'."
    }
    $apps = @($appsJson | ConvertFrom-Json)
    if ($apps.Count -ne 1) {
        throw "Expected one App Registration '$ApplicationDisplayName'; found $($apps.Count)."
    }
    if (@($apps[0].keyCredentials).Count + @($apps[0].passwordCredentials).Count -ne 0) {
        throw "App Registration '$ApplicationDisplayName' has long-lived credentials."
    }

    $principalsJson = & az ad sp list `
        --filter "appId eq '$($apps[0].appId)'" `
        --query '[].{id:id,appId:appId,displayName:displayName,accountEnabled:accountEnabled}' `
        --output json `
        --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        throw "Service principal lookup failed for '$ApplicationDisplayName'."
    }
    $principals = @($principalsJson | ConvertFrom-Json)
    if ($principals.Count -ne 1) {
        throw "Expected one service principal for '$ApplicationDisplayName'; found $($principals.Count)."
    }
    return $principals[0]
}

foreach ($command in @('az', 'terraform')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command '$command' was not found in PATH."
    }
}
if (-not (Test-Path -LiteralPath $EnvironmentFullPath -PathType Container)) {
    throw "Terraform environment was not found: $EnvironmentFullPath"
}

$githubPrincipal = Get-ServicePrincipal -ApplicationDisplayName $GitHubApplicationDisplayName
$azureDevOpsPrincipal = Get-ServicePrincipal -ApplicationDisplayName $AzureDevOpsApplicationDisplayName
Add-Result `
    -Control 'GitHub Actions service principal' `
    -Passed ($githubPrincipal.id -eq $ExpectedGitHubObjectId -and [bool]$githubPrincipal.accountEnabled) `
    -Evidence "objectId=$($githubPrincipal.id); enabled=$($githubPrincipal.accountEnabled)"
Add-Result `
    -Control 'Azure DevOps service principal' `
    -Passed ($azureDevOpsPrincipal.id -eq $ExpectedAzureDevOpsObjectId -and [bool]$azureDevOpsPrincipal.accountEnabled) `
    -Evidence "objectId=$($azureDevOpsPrincipal.id); enabled=$($azureDevOpsPrincipal.accountEnabled)"

$mainFile = Join-Path $EnvironmentFullPath 'main.tf'
$dynamicObjectIdReferences = @(Select-String -LiteralPath $mainFile -Pattern 'data\.azurerm_client_config\.current\.object_id')
Add-Result `
    -Control 'Terraform is runner-independent' `
    -Passed ($dynamicObjectIdReferences.Count -eq 0) `
    -Evidence "dynamicObjectIdReferences=$($dynamicObjectIdReferences.Count)"

Write-Host '--- terraform fmt'
[void](Invoke-NativeCommand `
        -Command 'terraform' `
        -Arguments @('fmt', '-check', '-recursive', $TerraformRoot) `
        -Operation 'Terraform format check')
Add-Result -Control 'Terraform formatting' -Passed $true -Evidence 'fmt -check passed'

Write-Host '--- terraform init'
[void](Invoke-NativeCommand `
        -Command 'terraform' `
        -Arguments @("-chdir=$EnvironmentFullPath", 'init', '-reconfigure', '-input=false', '-no-color') `
        -Operation 'Terraform initialization')

Write-Host '--- terraform validate'
[void](Invoke-NativeCommand `
        -Command 'terraform' `
        -Arguments @("-chdir=$EnvironmentFullPath", 'validate', '-no-color') `
        -Operation 'Terraform validation')
Add-Result -Control 'Terraform validation' -Passed $true -Evidence 'init + validate passed'

$planPath = Join-Path ([System.IO.Path]::GetTempPath()) "movieops-adop3-$([guid]::NewGuid().ToString('N')).tfplan"
try {
    Write-Host '--- terraform plan (no refresh, no apply)'
    $planResult = Invoke-NativeCommand `
        -Command 'terraform' `
        -Arguments @("-chdir=$EnvironmentFullPath", 'plan', '-refresh=false', '-lock=false', '-input=false', '-no-color', '-detailed-exitcode', "-out=$planPath") `
        -Operation 'Terraform identity plan' `
        -AllowedExitCodes @(0, 2)
    Add-Result `
        -Control 'Terraform plan generated' `
        -Passed $true `
        -Evidence "detailedExitCode=$($planResult.ExitCode); apply=false"

    $planJsonRaw = & terraform "-chdir=$EnvironmentFullPath" show -json $planPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Terraform plan JSON rendering failed.'
    }
    $plan = $planJsonRaw | ConvertFrom-Json -Depth 100
    $identityChanges = @($plan.resource_changes | Where-Object {
            $_.type -eq 'azurerm_role_assignment' -and
            $_.name -eq 'automation_secrets_officer'
        })

    $expected = @{
        github_actions = $ExpectedGitHubObjectId
        azure_devops   = $ExpectedAzureDevOpsObjectId
    }
    foreach ($key in $expected.Keys) {
        $match = @($identityChanges | Where-Object { $_.index -eq $key })
        $principalMatches = $match.Count -eq 1 -and $match[0].change.after.principal_id -eq $expected[$key]
        $actions = if ($match.Count -eq 1) { @($match[0].change.actions) } else { @() }
        $deletesPrincipal = $actions -contains 'delete'
        Add-Result `
            -Control "Stable Key Vault identity: $key" `
            -Passed ($principalMatches -and -not $deletesPrincipal) `
            -Evidence "matches=$($match.Count); objectId=$($expected[$key]); actions=$($actions -join ',')"
    }
}
finally {
    if (Test-Path -LiteralPath $planPath) {
        Remove-Item -LiteralPath $planPath -Force
    }
}

Write-Host ''
foreach ($result in $Results) {
    $color = if ($result.Status -eq 'PASS') { 'Green' } else { 'Red' }
    Write-Host "[$($result.Status)] $($result.Control) :: $($result.Evidence)" -ForegroundColor $color
}
$failures = @($Results | Where-Object { $_.Status -eq 'FAIL' })
Write-Host "Controls: $($Results.Count); PASS: $($Results.Count - $failures.Count); FAIL: $($failures.Count)"
if ($failures.Count -gt 0) {
    throw "ADOP-3 identity gate failed $($failures.Count) control(s)."
}
Write-Host '[VERIFIED] Terraform automation identities are stable. Genesis pipeline work may begin.' -ForegroundColor Green
