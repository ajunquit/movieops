[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName = 'rg-movieops-tfstate',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Location = 'eastus2',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$StorageAccountName = 'stmovieopstfstate',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ContainerName = 'tfstate',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Sku = 'Standard_LRS'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skippedChange = $false

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
$accountJson = & az account show --query '{id:id,name:name}' --output json --only-show-errors
Assert-LastExitCode 'Azure CLI session check'
$account = $accountJson | ConvertFrom-Json
Write-Host "Subscription: $($account.name) ($($account.id))"

# --- Resource group ---
$null = & az group show --name $ResourceGroupName --output none --only-show-errors 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[EXISTS] Resource group '$ResourceGroupName'."
}
elseif ($PSCmdlet.ShouldProcess($ResourceGroupName, "Create resource group in '$Location'")) {
    $null = & az group create --name $ResourceGroupName --location $Location --output none --only-show-errors
    Assert-LastExitCode "Creation of resource group '$ResourceGroupName'"
    Write-Host "[CREATED] Resource group '$ResourceGroupName' in '$Location'."
}
else {
    $skippedChange = $true
}

# --- Storage account ---
if (-not $skippedChange) {
    $saJson = & az storage account show --name $StorageAccountName --resource-group $ResourceGroupName --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -eq 0) {
        $storageAccount = $saJson | ConvertFrom-Json
        $compliant = $storageAccount.sku.name -eq $Sku -and
            $storageAccount.kind -eq 'StorageV2' -and
            $storageAccount.minimumTlsVersion -eq 'TLS1_2' -and
            $storageAccount.allowBlobPublicAccess -eq $false -and
            $storageAccount.enableHttpsTrafficOnly -eq $true

        if (-not $compliant) {
            throw "Storage account '$StorageAccountName' exists but does not meet the required baseline (sku/kind/TLS/public access/HTTPS-only). Review manually; this script does not silently correct drift on the state backend."
        }
        Write-Host "[EXISTS] Storage account '$StorageAccountName' (sku=$Sku, TLS1.2, no public blob access)."
    }
    elseif ($PSCmdlet.ShouldProcess($StorageAccountName, "Create storage account in '$ResourceGroupName'")) {
        $null = & az storage account create `
            --name $StorageAccountName `
            --resource-group $ResourceGroupName `
            --location $Location `
            --sku $Sku `
            --kind StorageV2 `
            --min-tls-version TLS1_2 `
            --allow-blob-public-access false `
            --https-only true `
            --output none `
            --only-show-errors
        Assert-LastExitCode "Creation of storage account '$StorageAccountName'"
        Write-Host "[CREATED] Storage account '$StorageAccountName'."
    }
    else {
        $skippedChange = $true
    }
}

# --- Blob container ---
if (-not $skippedChange) {
    $null = & az storage container show --name $ContainerName --account-name $StorageAccountName --output none --only-show-errors 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[EXISTS] Blob container '$ContainerName'."
    }
    elseif ($PSCmdlet.ShouldProcess($ContainerName, "Create blob container on '$StorageAccountName'")) {
        $null = & az storage container create --name $ContainerName --account-name $StorageAccountName --output none --only-show-errors
        Assert-LastExitCode "Creation of blob container '$ContainerName'"
        Write-Host "[CREATED] Blob container '$ContainerName'."
    }
    else {
        $skippedChange = $true
    }
}

if ($skippedChange) {
    Write-Host 'Some changes were skipped; final state verification was not performed.'
    return
}

# --- Final verification ---
$verifiedRg = & az group show --name $ResourceGroupName --query 'name' --output tsv --only-show-errors
Assert-LastExitCode 'Final resource group verification'

$verifiedSaJson = & az storage account show --name $StorageAccountName --resource-group $ResourceGroupName --output json --only-show-errors
Assert-LastExitCode 'Final storage account verification'
$verifiedSa = $verifiedSaJson | ConvertFrom-Json

$null = & az storage container show --name $ContainerName --account-name $StorageAccountName --output none --only-show-errors
Assert-LastExitCode 'Final blob container verification'

if ($verifiedSa.sku.name -ne $Sku -or $verifiedSa.minimumTlsVersion -ne 'TLS1_2' -or $verifiedSa.allowBlobPublicAccess -ne $false) {
    throw "Verification failed: storage account '$StorageAccountName' does not meet the required baseline."
}

Write-Host "`n[VERIFIED] Terraform remote state bootstrap completed."
Write-Host "Resource group : $verifiedRg"
Write-Host "Storage account: $($verifiedSa.name) (sku=$($verifiedSa.sku.name), TLS=$($verifiedSa.minimumTlsVersion))"
Write-Host "Container      : $ContainerName"
