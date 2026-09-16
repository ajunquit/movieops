[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApplicationDisplayName = 'github-movieops-terraform',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Roles = @('Contributor', 'Role Based Access Control Administrator')
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

if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) {
    $SubscriptionId = [string]$account.id
}

$scope = "/subscriptions/$SubscriptionId"

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

$servicePrincipalJson = & az ad sp show `
    --id $application.appId `
    --query '{id:id,appId:appId}' `
    --output json `
    --only-show-errors
Assert-LastExitCode "Lookup of the service principal for '$($application.appId)'"
$servicePrincipal = $servicePrincipalJson | ConvertFrom-Json

Write-Host "Subscription:      $($account.name) ($SubscriptionId)"
Write-Host "App Registration:  $($application.displayName) ($($application.appId))"
Write-Host "Service principal: $($servicePrincipal.id)"

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
        Write-Host "[OK] '$role' is already assigned at the subscription scope."
        continue
    }

    if ($PSCmdlet.ShouldProcess($scope, "Assign role '$role' to $($application.displayName)")) {
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

if ($skippedChange) {
    Write-Host 'Some changes were skipped; final state verification was not performed.'
    return
}

$verifiedJson = & az role assignment list `
    --assignee $application.appId `
    --scope $scope `
    --query '[].{role:roleDefinitionName,scope:scope}' `
    --output json `
    --only-show-errors
Assert-LastExitCode 'Final role assignment verification'
$verified = @($verifiedJson | ConvertFrom-Json)

foreach ($role in $Roles) {
    if (-not ($verified | Where-Object { $_.role -ceq $role })) {
        throw "Verification failed: role '$role' is not assigned at '$scope'."
    }
}

Write-Host "`nSubscription roles verified:"
$verified |
    Where-Object { $_.role -in $Roles } |
    Sort-Object role |
    Format-Table role, scope -AutoSize
