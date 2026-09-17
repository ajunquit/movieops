[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Environment = 'dev',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$VaultName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PrincipalObjectId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Role = 'Key Vault Secrets Officer'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-LastExitCode {
    param([Parameter(Mandatory)][string]$Operation)

    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed with exit code $LASTEXITCODE."
    }
}

if (-not (Get-Command 'az' -ErrorAction SilentlyContinue)) {
    throw "Required command 'az' was not found in PATH."
}

Write-Host 'Checking Azure CLI session...'
$null = & az account show --output none --only-show-errors
Assert-LastExitCode 'Azure CLI session check'

if (-not $PSBoundParameters.ContainsKey('ResourceGroupName')) {
    $ResourceGroupName = "rg-movieops-$Environment"
}

if (-not $PSBoundParameters.ContainsKey('PrincipalObjectId')) {
    $PrincipalObjectId = & az ad signed-in-user show --query 'id' --output tsv --only-show-errors
    Assert-LastExitCode 'Lookup of the signed-in user'
}

if (-not $PSBoundParameters.ContainsKey('VaultName')) {
    $vaultsJson = & az keyvault list `
        --resource-group $ResourceGroupName `
        --query '[].{name:name,id:id}' `
        --output json `
        --only-show-errors
    Assert-LastExitCode "Key Vault lookup in '$ResourceGroupName'"

    $vaults = @($vaultsJson | ConvertFrom-Json)
    if ($vaults.Count -ne 1) {
        throw "Expected exactly one Key Vault in '$ResourceGroupName'; found $($vaults.Count). Pass -VaultName explicitly."
    }

    $VaultName = [string]$vaults[0].name
}

$vaultIdJson = & az keyvault show `
    --name $VaultName `
    --resource-group $ResourceGroupName `
    --query 'id' `
    --output tsv `
    --only-show-errors
Assert-LastExitCode "Lookup of Key Vault '$VaultName'"
$scope = [string]$vaultIdJson

Write-Host "Key Vault: $VaultName"
Write-Host "Principal: $PrincipalObjectId"
Write-Host "Role:      $Role"

$assignmentsJson = & az role assignment list `
    --assignee $PrincipalObjectId `
    --scope $scope `
    --query '[].{role:roleDefinitionName,scope:scope}' `
    --output json `
    --only-show-errors
Assert-LastExitCode 'Role assignment lookup'
$assignments = @($assignmentsJson | ConvertFrom-Json)

if ($assignments | Where-Object { $_.role -ceq $Role -and $_.scope -ceq $scope }) {
    Write-Host "[EXISTS] '$Role' already assigned on '$VaultName'."
    return
}

if (-not $PSCmdlet.ShouldProcess($VaultName, "Assign role '$Role' to $PrincipalObjectId")) {
    Write-Host 'Change skipped; final state verification was not performed.'
    return
}

$null = & az role assignment create `
    --assignee-object-id $PrincipalObjectId `
    --role $Role `
    --scope $scope `
    --output none `
    --only-show-errors
Assert-LastExitCode "Assignment of role '$Role'"
Write-Host "[CREATED] '$Role' assigned on '$VaultName'."

$verifiedJson = & az role assignment list `
    --assignee $PrincipalObjectId `
    --scope $scope `
    --query '[].roleDefinitionName' `
    --output json `
    --only-show-errors
Assert-LastExitCode 'Final role assignment verification'

if (-not (@($verifiedJson | ConvertFrom-Json) -ccontains $Role)) {
    throw "Verification failed: role '$Role' is not assigned on '$VaultName'."
}

Write-Host "Verified: '$Role' on '$VaultName'."
