#Requires -Version 7.0

<#
.SYNOPSIS
Creates Azure DevOps Environments and their deployment checks.

.DESCRIPTION
Creates or verifies the dev, staging, and production Environments in the
MovieOps Azure DevOps Project. It configures branch control on every
Environment and a human approval on production by using public Azure DevOps
REST APIs and the operator's Azure CLI session.

The script is idempotent. It creates missing resources, updates only the
MovieOps checks managed by this step, and fails closed on ambiguous state.

.EXAMPLE
./scripts/azure-devops/02-configure-environments/configure-environments.ps1 -WhatIf

.EXAMPLE
./scripts/azure-devops/02-configure-environments/configure-environments.ps1

.EXAMPLE
./scripts/azure-devops/02-configure-environments/configure-environments.ps1 `
  -ProductionApprover 'another.user@contoso.com' `
  -VerifyBranchProtection
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidatePattern('^https://dev\.azure\.com/[A-Za-z0-9-]+/?$')]
    [string]$OrganizationUrl = 'https://dev.azure.com/ajunquit',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectName = 'MovieOps',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceConnectionName = 'sc-movieops-azure-wif',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Environments = @('dev', 'staging', 'production'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ProductionEnvironment = 'production',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ProductionApprover = 'ajunquit@hotmail.com',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$AllowedBranches = @('refs/heads/main'),

    [Parameter()]
    [switch]$VerifyBranchProtection,

    [Parameter()]
    [ValidateRange(1, 43200)]
    [int]$BranchCheckTimeoutMinutes = 1440,

    [Parameter()]
    [ValidateRange(1, 43200)]
    [int]$ApprovalTimeoutMinutes = 43200,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApprovalInstructions = 'Validar evidencia, artefacto y plan de despliegue antes de aprobar production.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$OrganizationUrl = $OrganizationUrl.TrimEnd('/')
$EnvironmentApiVersion = '7.1'
$ChecksApiVersion = '7.1-preview'
$BranchCheckTypeId = 'fe1de3ee-a436-41b4-bb20-f6eb4cb879a7'
$BranchDefinitionId = '86b05a0c-73e6-4f7d-b3cf-e38f3b39a75b'
$ApprovalCheckTypeId = '8c6f20a7-a545-4486-9777-f762fafe0d4d'
$AllowedBranchesValue = ($AllowedBranches | Sort-Object -Unique) -join ','

function Invoke-AzCommand {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$Operation,

        [Parameter()]
        [switch]$ParseJson
    )

    $output = @(& az @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $details = $output -join [Environment]::NewLine
        throw "$Operation failed with exit code $LASTEXITCODE.`n$details"
    }

    if (-not $ParseJson) {
        return $output
    }

    $json = $output -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($json)) {
        throw "$Operation returned an empty response; JSON was expected."
    }

    try {
        return $json | ConvertFrom-Json
    }
    catch {
        throw "$Operation returned invalid JSON.`n$json"
    }
}

function Invoke-AzureDevOpsApi {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Area,

        [Parameter(Mandatory)]
        [string]$Resource,

        [Parameter(Mandatory)]
        [string[]]$RouteParameters,

        [Parameter()]
        [string[]]$QueryParameters = @(),

        [Parameter(Mandatory)]
        [string]$ApiVersion,

        [Parameter()]
        [object]$Body
    )

    $temporaryFile = $null
    try {
        $arguments = @(
            'devops', 'invoke',
            '--organization', $OrganizationUrl,
            '--area', $Area,
            '--resource', $Resource,
            '--route-parameters'
        ) + $RouteParameters

        if ($QueryParameters.Count -gt 0) {
            $arguments += '--query-parameters'
            $arguments += $QueryParameters
        }

        $arguments += @(
            '--api-version', $ApiVersion,
            '--http-method', $Method,
            '--output', 'json',
            '--only-show-errors'
        )

        if ($PSBoundParameters.ContainsKey('Body')) {
            $temporaryFile = [System.IO.Path]::GetTempFileName()
            $json = $Body | ConvertTo-Json -Depth 20 -Compress
            [System.IO.File]::WriteAllText(
                $temporaryFile,
                $json,
                [System.Text.UTF8Encoding]::new($false)
            )
            $arguments += @('--in-file', $temporaryFile)
        }

        return Invoke-AzCommand `
            -Arguments $arguments `
            -Operation "Azure DevOps API $Method $Area/$Resource" `
            -ParseJson
    }
    finally {
        if ($temporaryFile -and (Test-Path -LiteralPath $temporaryFile)) {
            Remove-Item -LiteralPath $temporaryFile -Force
        }
    }
}

function Get-EnvironmentList {
    $response = Invoke-AzureDevOpsApi `
        -Method GET `
        -Area 'distributedtask' `
        -Resource 'environments' `
        -RouteParameters @("project=$ProjectId") `
        -ApiVersion $EnvironmentApiVersion
    return @($response.value)
}

function Get-EnvironmentChecks {
    param([Parameter(Mandatory)][string]$EnvironmentId)

    $response = Invoke-AzureDevOpsApi `
        -Method GET `
        -Area 'pipelineschecks' `
        -Resource 'configurations' `
        -RouteParameters @("project=$ProjectId") `
        -QueryParameters @('resourceType=environment', "resourceId=$EnvironmentId", '$expand=settings') `
        -ApiVersion $ChecksApiVersion
    return @($response.value)
}

function New-BranchCheckBody {
    param(
        [Parameter(Mandatory)][string]$EnvironmentId,
        [Parameter(Mandatory)][string]$EnvironmentName
    )

    $inputs = [ordered]@{
        allowedBranches          = $AllowedBranchesValue
        ensureProtectionOfBranch = $VerifyBranchProtection.IsPresent.ToString().ToLowerInvariant()
    }

    if ($VerifyBranchProtection) {
        $inputs.allowUnknownStatusBranch = 'false'
    }

    return [ordered]@{
        type     = @{ id = $BranchCheckTypeId; name = 'Task Check' }
        settings = [ordered]@{
            displayName   = 'MovieOps branch control'
            definitionRef = [ordered]@{
                id      = $BranchDefinitionId
                name    = 'evaluatebranchProtection'
                version = '0.0.1'
            }
            inputs        = $inputs
        }
        resource = @{ type = 'environment'; id = $EnvironmentId; name = $EnvironmentName }
        timeout  = $BranchCheckTimeoutMinutes
    }
}

function New-ApprovalCheckBody {
    param(
        [Parameter(Mandatory)][string]$EnvironmentId,
        [Parameter(Mandatory)][string]$EnvironmentName
    )

    return [ordered]@{
        type     = @{ id = $ApprovalCheckTypeId; name = 'Approval' }
        settings = [ordered]@{
            approvers                 = @(@{ id = $ApproverId })
            instructions              = $ApprovalInstructions
            minRequiredApprovers      = 1
            requesterCannotBeApprover = $true
        }
        resource = @{ type = 'environment'; id = $EnvironmentId; name = $EnvironmentName }
        timeout  = $ApprovalTimeoutMinutes
    }
}

function Test-BranchCheckCompliant {
    param([Parameter(Mandatory)][object]$Check)

    $expectedProtection = $VerifyBranchProtection.IsPresent.ToString().ToLowerInvariant()
    $isCompliant =
        $Check.settings.displayName -eq 'MovieOps branch control' -and
        $Check.settings.inputs.allowedBranches -eq $AllowedBranchesValue -and
        ([string]$Check.settings.inputs.ensureProtectionOfBranch).ToLowerInvariant() -eq $expectedProtection -and
        [int]$Check.timeout -eq $BranchCheckTimeoutMinutes

    if ($VerifyBranchProtection) {
        $isCompliant = $isCompliant -and
            ([string]$Check.settings.inputs.allowUnknownStatusBranch).ToLowerInvariant() -eq 'false'
    }

    return $isCompliant
}

function Test-ApprovalCheckCompliant {
    param([Parameter(Mandatory)][object]$Check)

    $approverIds = @($Check.settings.approvers | ForEach-Object { $_.id })
    return (
        $approverIds.Count -eq 1 -and
        $approverIds[0] -eq $ApproverId -and
        $Check.settings.instructions -eq $ApprovalInstructions -and
        [int]$Check.settings.minRequiredApprovers -eq 1 -and
        [bool]$Check.settings.requesterCannotBeApprover -and
        [int]$Check.timeout -eq $ApprovalTimeoutMinutes
    )
}

function Set-ManagedCheck {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$ExistingChecks,
        [Parameter(Mandatory)][string]$EnvironmentId,
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][ValidateSet('Branch', 'Approval')][string]$Kind
    )

    if ($Kind -eq 'Branch') {
        $matches = @($ExistingChecks | Where-Object {
                $_.type.id -eq $BranchCheckTypeId -and
                $_.settings.definitionRef.id -eq $BranchDefinitionId
            })
        $body = New-BranchCheckBody -EnvironmentId $EnvironmentId -EnvironmentName $EnvironmentName
        $complianceTest = { param($candidate) Test-BranchCheckCompliant -Check $candidate }
        $label = "branch control on '$EnvironmentName'"
    }
    else {
        $matches = @($ExistingChecks | Where-Object { $_.type.id -eq $ApprovalCheckTypeId })
        $body = New-ApprovalCheckBody -EnvironmentId $EnvironmentId -EnvironmentName $EnvironmentName
        $complianceTest = { param($candidate) Test-ApprovalCheckCompliant -Check $candidate }
        $label = "production approval on '$EnvironmentName'"
    }

    if ($matches.Count -gt 1) {
        throw "Found $($matches.Count) matching checks for $label. Resolve the ambiguity in Azure DevOps before rerunning."
    }

    if ($matches.Count -eq 0) {
        if ($PSCmdlet.ShouldProcess($EnvironmentName, "Create $label")) {
            $created = Invoke-AzureDevOpsApi `
                -Method POST `
                -Area 'pipelineschecks' `
                -Resource 'configurations' `
                -RouteParameters @("project=$ProjectId") `
                -ApiVersion $ChecksApiVersion `
                -Body $body
            Write-Host "[CREATED] $label (check $($created.id))."
        }
        return
    }

    $existing = $matches[0]
    if (& $complianceTest $existing) {
        Write-Host "[EXISTS] Compliant $label (check $($existing.id))."
        return
    }

    if ($PSCmdlet.ShouldProcess($EnvironmentName, "Update $label")) {
        $body.id = $existing.id
        $body.version = $existing.version
        $updated = Invoke-AzureDevOpsApi `
            -Method PATCH `
            -Area 'pipelineschecks' `
            -Resource 'configurations' `
            -RouteParameters @("project=$ProjectId", "id=$($existing.id)") `
            -ApiVersion $ChecksApiVersion `
            -Body $body
        Write-Host "[UPDATED] $label (check $($updated.id))."
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Required command 'az' was not found in PATH. Install Azure CLI before running this script."
}

if (@($Environments | Sort-Object -Unique).Count -ne $Environments.Count) {
    throw 'Environment names must be unique.'
}
if ($ProductionEnvironment -notin $Environments) {
    throw "ProductionEnvironment '$ProductionEnvironment' must be included in Environments."
}
foreach ($branch in $AllowedBranches) {
    if ($branch -notmatch '^refs/heads/.+') {
        throw "Branch '$branch' is not fully qualified. Use refs/heads/<branch>."
    }
}

Write-Host 'Checking Azure DevOps project and step 01 gate...'
$project = Invoke-AzCommand `
    -Arguments @('devops', 'project', 'show', '--organization', $OrganizationUrl, '--project', $ProjectName, '--output', 'json', '--only-show-errors') `
    -Operation 'Azure DevOps project lookup' `
    -ParseJson

if ($project.state -ne 'wellFormed') {
    throw "Project '$ProjectName' is in state '$($project.state)', expected 'wellFormed'."
}
$ProjectId = $project.id
Write-Host "[VERIFIED] Azure DevOps project: $ProjectName ($ProjectId)."

$serviceConnections = @(Invoke-AzCommand `
        -Arguments @('devops', 'service-endpoint', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--output', 'json', '--only-show-errors') `
        -Operation 'Azure DevOps service connection lookup' `
        -ParseJson | Where-Object { $_.name -eq $ServiceConnectionName })

if ($serviceConnections.Count -ne 1) {
    throw "Expected exactly one service connection '$ServiceConnectionName'; found $($serviceConnections.Count). Complete step 01 first."
}
$serviceConnection = $serviceConnections[0]
if ($serviceConnection.type -ne 'azurerm' -or
    $serviceConnection.authorization.scheme -ne 'WorkloadIdentityFederation' -or
    -not $serviceConnection.isReady) {
    throw "Service connection '$ServiceConnectionName' is not a ready AzureRM Workload Identity Federation connection."
}
Write-Host "[VERIFIED] WIF service connection: $ServiceConnectionName ($($serviceConnection.id))."

$approver = Invoke-AzCommand `
    -Arguments @('devops', 'user', 'show', '--organization', $OrganizationUrl, '--user', $ProductionApprover, '--output', 'json', '--only-show-errors') `
    -Operation "Azure DevOps approver lookup for '$ProductionApprover'" `
    -ParseJson

if ($approver.accessLevel.status -ne 'active') {
    throw "Approver '$ProductionApprover' is not an active Azure DevOps user."
}
$ApproverId = $approver.id
Write-Host "[VERIFIED] Production approver: $ProductionApprover ($ApproverId)."

$existingEnvironments = @(Get-EnvironmentList)
$resolvedEnvironments = @{}
$previewHasMissingEnvironment = $false

foreach ($environmentName in $Environments) {
        $matches = @($existingEnvironments | Where-Object { $_.name -eq $environmentName })
        if ($matches.Count -gt 1) {
            throw "Found $($matches.Count) Environments named '$environmentName'. Resolve the ambiguity before rerunning."
        }

        if ($matches.Count -eq 1) {
            $resolvedEnvironments[$environmentName] = $matches[0]
            Write-Host "[EXISTS] Environment '$environmentName' ($($matches[0].id))."
            continue
        }

        if ($PSCmdlet.ShouldProcess($ProjectName, "Create Azure DevOps Environment '$environmentName'")) {
            $body = @{
                name        = $environmentName
                description = "MovieOps deployment environment: $environmentName"
            }
            $created = Invoke-AzureDevOpsApi `
                -Method POST `
                -Area 'distributedtask' `
                -Resource 'environments' `
                -RouteParameters @("project=$ProjectId") `
                -ApiVersion $EnvironmentApiVersion `
                -Body $body
            $resolvedEnvironments[$environmentName] = $created
            Write-Host "[CREATED] Environment '$environmentName' ($($created.id))."
        }
        else {
            $previewHasMissingEnvironment = $true
        }
    }

    if ($previewHasMissingEnvironment) {
        foreach ($environmentName in $Environments) {
            Write-Host "[PLAN] Ensure branch control '$AllowedBranchesValue' on '$environmentName'."
        }
        Write-Host "[PLAN] Ensure approval by '$ProductionApprover' on '$ProductionEnvironment'; requester cannot approve."
        Write-Host '[VERIFIED] Preview completed. No Azure DevOps resource was changed.'
        return
    }

    foreach ($environmentName in $Environments) {
        $environment = $resolvedEnvironments[$environmentName]
        $checks = @(Get-EnvironmentChecks -EnvironmentId ([string]$environment.id))
        Set-ManagedCheck `
            -ExistingChecks $checks `
            -EnvironmentId ([string]$environment.id) `
            -EnvironmentName $environmentName `
            -Kind Branch

        if ($environmentName -eq $ProductionEnvironment) {
            $checks = @(Get-EnvironmentChecks -EnvironmentId ([string]$environment.id))
            Set-ManagedCheck `
                -ExistingChecks $checks `
                -EnvironmentId ([string]$environment.id) `
                -EnvironmentName $environmentName `
                -Kind Approval
        }
    }

    if ($WhatIfPreference) {
        Write-Host '[VERIFIED] Preview completed. No Azure DevOps resource was changed.'
        return
    }

    $finalEnvironments = @(Get-EnvironmentList)
    foreach ($environmentName in $Environments) {
        $environment = @($finalEnvironments | Where-Object { $_.name -eq $environmentName })
        if ($environment.Count -ne 1) {
            throw "Final verification failed for Environment '$environmentName'."
        }

        $checks = @(Get-EnvironmentChecks -EnvironmentId ([string]$environment[0].id))
        $branchChecks = @($checks | Where-Object {
                $_.type.id -eq $BranchCheckTypeId -and
                $_.settings.definitionRef.id -eq $BranchDefinitionId
            })
        if ($branchChecks.Count -ne 1 -or -not (Test-BranchCheckCompliant -Check $branchChecks[0])) {
            throw "Final verification failed for branch control on '$environmentName'."
        }

        if ($environmentName -eq $ProductionEnvironment) {
            $approvalChecks = @($checks | Where-Object { $_.type.id -eq $ApprovalCheckTypeId })
            if ($approvalChecks.Count -ne 1 -or -not (Test-ApprovalCheckCompliant -Check $approvalChecks[0])) {
                throw "Final verification failed for approval on '$environmentName'."
            }
        }

        Write-Host "[VERIFIED] Environment '$environmentName': branch control configured."
    }

Write-Host "[VERIFIED] Production approval: $ProductionApprover; requester self-approval disabled."
Write-Host '[VERIFIED] Azure DevOps Environment bootstrap completed.'
