[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateSet('00', '01', '03')]
    [string]$StopAfterStep,

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
    [string[]]$Roles = @('Contributor', 'Role Based Access Control Administrator'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TfStateResourceGroupName = 'rg-movieops-tfstate',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TfStateLocation = 'eastus2',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TfStateStorageAccountName = 'stmovieopstfstate',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TfStateContainerName = 'tfstate',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TfStateSku = 'Standard_LRS'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$summary = [System.Collections.Generic.List[object]]::new()

function Add-StepResult {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][string]$Status,
        [string]$Detail = ''
    )
    $summary.Add([pscustomobject]@{ Step = $Step; Status = $Status; Detail = $Detail })
}

function Write-StepSummary {
    Write-Host "`n=== Bootstrap summary ===" -ForegroundColor Cyan
    $summary | Format-Table Step, Status, Detail -AutoSize
}

function Invoke-Step {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][hashtable]$Parameters
    )

    Write-Host "`n=== STEP $Step : $ScriptPath ===" -ForegroundColor Cyan
    & $ScriptPath @Parameters
}

$tfStateParams = @{
    ResourceGroupName  = $TfStateResourceGroupName
    Location           = $TfStateLocation
    StorageAccountName = $TfStateStorageAccountName
    ContainerName      = $TfStateContainerName
    Sku                = $TfStateSku
}

$servicePrincipalParams = @{
    ApplicationDisplayName = $ApplicationDisplayName
    Repository             = $Repository
    Environments           = $Environments
    Roles                  = $Roles
}
if ($PSBoundParameters.ContainsKey('SubscriptionId')) {
    $servicePrincipalParams['SubscriptionId'] = $SubscriptionId
}

$verifyParams = @{
    ApplicationDisplayName    = $ApplicationDisplayName
    Repository                = $Repository
    Environments               = $Environments
    Roles                      = $Roles
    TfStateResourceGroupName  = $TfStateResourceGroupName
    TfStateStorageAccountName = $TfStateStorageAccountName
    TfStateContainerName      = $TfStateContainerName
}
if ($PSBoundParameters.ContainsKey('SubscriptionId')) {
    $verifyParams['SubscriptionId'] = $SubscriptionId
}

if ($WhatIfPreference) {
    $tfStateParams['WhatIf'] = $true
    $servicePrincipalParams['WhatIf'] = $true
}

try {
    Invoke-Step -Step '00' -ScriptPath (Join-Path $root '00-bootstrap-terraform-state/bootstrap-terraform-state.ps1') -Parameters $tfStateParams
    Add-StepResult -Step '00' -Status $(if ($WhatIfPreference) { 'PREVIEWED' } else { 'COMPLETED' })
}
catch {
    Add-StepResult -Step '00' -Status 'FAILED' -Detail $_.Exception.Message
    Write-StepSummary
    throw
}

if ($StopAfterStep -eq '00') {
    Add-StepResult -Step '01' -Status 'STOPPED'
    Write-StepSummary
    return
}

try {
    Invoke-Step -Step '01' -ScriptPath (Join-Path $root '01-service-principal-oidc/configure-service-principal.ps1') -Parameters $servicePrincipalParams
    Add-StepResult -Step '01' -Status $(if ($WhatIfPreference) { 'PREVIEWED' } else { 'COMPLETED' })
}
catch {
    Add-StepResult -Step '01' -Status 'FAILED' -Detail $_.Exception.Message
    Write-StepSummary
    throw
}

if ($StopAfterStep -eq '01') {
    Add-StepResult -Step '03' -Status 'STOPPED'
    Write-StepSummary
    return
}

if ($WhatIfPreference) {
    Add-StepResult -Step '03' -Status 'STOPPED' -Detail 'Skipped: cannot audit simulated state.'
    Write-StepSummary
    Write-Host "`n[VERIFIED] Preview of steps 00-01 completed without organic failures."
    return
}

try {
    Invoke-Step -Step '03' -ScriptPath (Join-Path $root '03-verify-bootstrap/verify-bootstrap.ps1') -Parameters $verifyParams
    Add-StepResult -Step '03' -Status 'COMPLETED'
}
catch {
    Add-StepResult -Step '03' -Status 'FAILED' -Detail $_.Exception.Message
    Write-StepSummary
    throw
}

Write-StepSummary
Write-Host "`n[VERIFIED] Full github-actions-azure bootstrap completed successfully."
