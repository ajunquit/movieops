[CmdletBinding()]
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
    [string]$TfStateResourceGroupName = 'rg-movieops-tfstate',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TfStateStorageAccountName = 'stmovieopstfstate',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TfStateContainerName = 'tfstate',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Roles = @('Contributor', 'Role Based Access Control Administrator')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][string]$Control,
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Evidence
    )

    $results.Add([pscustomobject]@{
        Control  = $Control
        Status   = if ($Passed) { 'PASS' } else { 'FAIL' }
        Evidence = $Evidence
    })
    $prefix = if ($Passed) { '[PASS]' } else { '[FAIL]' }
    Write-Host "$prefix $Control — $Evidence"
}

foreach ($command in @('az', 'gh')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command '$command' was not found in PATH."
    }
}

$accountJson = & az account show --query '{id:id,name:name,user:user.name}' --output json --only-show-errors
if ($LASTEXITCODE -ne 0) {
    throw 'Azure CLI session check failed.'
}
$account = $accountJson | ConvertFrom-Json
if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) {
    $SubscriptionId = [string]$account.id
}
$scope = "/subscriptions/$SubscriptionId"

Add-Result -Control 'Azure target boundary' -Passed ($account.id -eq $SubscriptionId) `
    -Evidence "user=$($account.user); subscription=$($account.name) ($SubscriptionId)"

# --- Terraform remote state bootstrap (step 00) ---
$null = & az group show --name $TfStateResourceGroupName --output none --only-show-errors 2>$null
Add-Result -Control 'Terraform state resource group' -Passed ($LASTEXITCODE -eq 0) -Evidence $TfStateResourceGroupName

$saJson = & az storage account show --name $TfStateStorageAccountName --resource-group $TfStateResourceGroupName --output json --only-show-errors 2>$null
$saOk = $false
$storageAccount = $null
if ($LASTEXITCODE -eq 0) {
    $storageAccount = $saJson | ConvertFrom-Json
    $saOk = $storageAccount.sku.name -eq 'Standard_LRS' -and
        $storageAccount.allowBlobPublicAccess -eq $false -and
        $storageAccount.minimumTlsVersion -eq 'TLS1_2'
}
$saEvidence = if ($storageAccount) {
    "$TfStateStorageAccountName; sku=$($storageAccount.sku.name); publicAccess=$($storageAccount.allowBlobPublicAccess); tls=$($storageAccount.minimumTlsVersion)"
}
else {
    "$TfStateStorageAccountName not found"
}
Add-Result -Control 'Terraform state storage account baseline' -Passed $saOk -Evidence $saEvidence

$null = & az storage container show --name $TfStateContainerName --account-name $TfStateStorageAccountName --output none --only-show-errors 2>$null
Add-Result -Control 'Terraform state container' -Passed ($LASTEXITCODE -eq 0) -Evidence $TfStateContainerName

# --- App Registration / secretless identity (step 01) ---
$appsJson = & az ad app list `
    --display-name $ApplicationDisplayName `
    --query '[].{id:id,appId:appId,keyCredentials:keyCredentials,passwordCredentials:passwordCredentials}' `
    --output json `
    --only-show-errors
$apps = @($appsJson | ConvertFrom-Json)
$appOk = $apps.Count -eq 1
$application = if ($appOk) { $apps[0] } else { $null }
Add-Result -Control 'GitHub Actions App Registration' -Passed $appOk -Evidence "$ApplicationDisplayName; matches=$($apps.Count)"

if ($appOk) {
    $credentialCount = @($application.keyCredentials).Count + @($application.passwordCredentials).Count
    Add-Result -Control 'Secretless identity' -Passed ($credentialCount -eq 0) -Evidence "long-lived credentials=$credentialCount"
}
else {
    Add-Result -Control 'Secretless identity' -Passed $false -Evidence 'App Registration not found'
}

if ($appOk) {
    $spsJson = & az ad sp list --filter "appId eq '$($application.appId)'" --query '[].id' --output json --only-show-errors
    $sps = @($spsJson | ConvertFrom-Json)
    Add-Result -Control 'Service principal' -Passed ($sps.Count -eq 1) -Evidence "matches=$($sps.Count)"
}
else {
    Add-Result -Control 'Service principal' -Passed $false -Evidence 'App Registration not found'
}

if ($appOk) {
    $oidcConfigJson = & gh api "repos/$Repository/actions/oidc/customization/sub" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $oidcConfig = $oidcConfigJson | ConvertFrom-Json
        $subjectPrefix = [string]$oidcConfig.sub_claim_prefix
        $credsJson = & az ad app federated-credential list --id $application.id --output json --only-show-errors
        $creds = @($credsJson | ConvertFrom-Json)

        foreach ($environment in $Environments) {
            $expectedSubject = "${subjectPrefix}:environment:${environment}"
            $match = @($creds | Where-Object {
                $_.name -eq "github-environment-$environment" -and
                $_.subject -ceq $expectedSubject -and
                $_.issuer -ceq 'https://token.actions.githubusercontent.com'
            })
            Add-Result -Control "Federated credential — $environment" -Passed ($match.Count -eq 1) -Evidence "subject=$expectedSubject"
        }
    }
    else {
        Add-Result -Control 'GitHub OIDC subject lookup' -Passed $false -Evidence "gh api failed for '$Repository'"
    }

    $assignmentsJson = & az role assignment list `
        --assignee $application.appId `
        --scope $scope `
        --query '[].roleDefinitionName' `
        --output json `
        --only-show-errors
    $assignedRoles = @($assignmentsJson | ConvertFrom-Json)
    foreach ($role in $Roles) {
        Add-Result -Control "Subscription role — $role" -Passed ($assignedRoles -ccontains $role) -Evidence "scope=$scope"
    }
}
else {
    foreach ($environment in $Environments) {
        Add-Result -Control "Federated credential — $environment" -Passed $false -Evidence 'App Registration not found'
    }
    foreach ($role in $Roles) {
        Add-Result -Control "Subscription role — $role" -Passed $false -Evidence 'App Registration not found'
    }
}

$failed = @($results | Where-Object { $_.Status -eq 'FAIL' })
Write-Host ''
$results | Format-Table Control, Status, Evidence -AutoSize
Write-Host "`nControls: $($results.Count); passed: $($results.Count - $failed.Count); failed: $($failed.Count)."

if ($failed.Count -gt 0) {
    throw "$($failed.Count) control(s) failed. Review the table above."
}

Write-Host '[VERIFIED] Azure (GitHub Actions track) bootstrap audit completed with zero failures.'
Write-Host '[VERIFIED] This script performed read-only operations only.'
