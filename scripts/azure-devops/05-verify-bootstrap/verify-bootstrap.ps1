#Requires -Version 7.0

<#
.SYNOPSIS
Performs a read-only audit of the MovieOps Azure DevOps bootstrap.

.DESCRIPTION
Verifies the Azure DevOps Project, Azure and GitHub service connections,
Microsoft Entra workload identity, Azure RBAC, Environments and checks,
diagnostic pipeline evidence, pipeline-scoped authorization, and project
retention. The script never creates, updates, deletes, queues, or approves
anything.

.EXAMPLE
./scripts/azure-devops/05-verify-bootstrap/verify-bootstrap.ps1
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidatePattern('^https://dev\.azure\.com/[A-Za-z0-9-]+/?$')]
    [string]$OrganizationUrl = 'https://dev.azure.com/ajunquit',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectName = 'MovieOps',

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId = 'b7fdb48a-4bf0-4c7b-9708-3d875a551936',

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$TenantId = '71747eda-0e30-46d9-a3dd-09adb3a83ff3',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ApplicationDisplayName = 'azure-devops-movieops-wif',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$AzureServiceConnectionName = 'sc-movieops-azure-wif',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$GitHubRepository = 'ajunquit/movieops',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DiagnosticPipelineName = 'MovieOps-Diagnostic',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DiagnosticYamlPath = 'azure-pipelines/diagnostic.yml',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$EnvironmentNames = @('dev', 'staging', 'production'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ProductionEnvironment = 'production',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ProductionApprover = 'ajunquit@hotmail.com',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$AllowedBranches = 'refs/heads/main',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$RequiredSubscriptionRoles = @(
        'Contributor',
        'Role Based Access Control Administrator'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$OrganizationUrl = $OrganizationUrl.TrimEnd('/')
$SubscriptionScope = "/subscriptions/$SubscriptionId"
$FederatedCredentialName = 'azure-devops-movieops-service-connection'
$FederatedAudience = 'api://AzureADTokenExchange'
$BranchCheckTypeId = 'fe1de3ee-a436-41b4-bb20-f6eb4cb879a7'
$BranchDefinitionId = '86b05a0c-73e6-4f7d-b3cf-e38f3b39a75b'
$ApprovalCheckTypeId = '8c6f20a7-a545-4486-9777-f762fafe0d4d'
$Results = [System.Collections.Generic.List[object]]::new()

function Invoke-AzCommand {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Operation,
        [Parameter()][switch]$ParseJson
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
        [Parameter(Mandatory)][string]$Area,
        [Parameter(Mandatory)][string]$Resource,
        [Parameter(Mandatory)][string[]]$RouteParameters,
        [Parameter()][string[]]$QueryParameters = @(),
        [Parameter(Mandatory)][string]$ApiVersion
    )

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
        '--http-method', 'GET',
        '--output', 'json',
        '--only-show-errors'
    )

    return Invoke-AzCommand `
        -Arguments $arguments `
        -Operation "Azure DevOps API GET $Area/$Resource" `
        -ParseJson
}

function Add-AuditResult {
    param(
        [Parameter(Mandatory)][string]$Control,
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Evidence
    )

    $status = if ($Passed) { 'PASS' } else { 'FAIL' }
    $Results.Add([pscustomobject]@{
            Status   = $status
            Control  = $Control
            Evidence = $Evidence
        })

    $color = if ($Passed) { 'Green' } else { 'Red' }
    Write-Host "[$status] $Control — $Evidence" -ForegroundColor $color
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Required command 'az' was not found in PATH."
}

Write-Host 'MovieOps Azure DevOps bootstrap audit (read-only)'

$account = Invoke-AzCommand `
    -Arguments @('account', 'show', '--output', 'json', '--only-show-errors') `
    -Operation 'Azure CLI session lookup' `
    -ParseJson
$accountMatches = $account.id -eq $SubscriptionId -and $account.tenantId -eq $TenantId
Add-AuditResult `
    -Control 'Azure target boundary' `
    -Passed $accountMatches `
    -Evidence "subscription=$($account.id); tenant=$($account.tenantId); user=$($account.user.name)"

$project = Invoke-AzCommand `
    -Arguments @('devops', 'project', 'show', '--organization', $OrganizationUrl, '--project', $ProjectName, '--output', 'json', '--only-show-errors') `
    -Operation 'Azure DevOps project lookup' `
    -ParseJson
$ProjectId = $project.id
$projectCompliant =
    $project.state -eq 'wellFormed' -and
    $project.visibility -eq 'private' -and
    $project.capabilities.versioncontrol.sourceControlType -eq 'Git' -and
    $project.capabilities.processTemplate.templateName -eq 'Basic'
Add-AuditResult `
    -Control 'Private Git/Basic Project' `
    -Passed $projectCompliant `
    -Evidence "name=$($project.name); id=$ProjectId; state=$($project.state); visibility=$($project.visibility)"

$endpoints = @(Invoke-AzCommand `
        -Arguments @('devops', 'service-endpoint', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--output', 'json', '--only-show-errors') `
        -Operation 'Service connection lookup' `
        -ParseJson)

$azureEndpoints = @($endpoints | Where-Object { $_.name -eq $AzureServiceConnectionName })
$azureEndpointReady = $azureEndpoints.Count -eq 1
if ($azureEndpointReady) {
    $azureEndpoint = $azureEndpoints[0]
    $azureEndpointReady =
        $azureEndpoint.type -eq 'AzureRM' -and
        $azureEndpoint.authorization.scheme -eq 'WorkloadIdentityFederation' -and
        [bool]$azureEndpoint.isReady -and
        -not [bool]$azureEndpoint.isShared -and
        $azureEndpoint.data.subscriptionId -eq $SubscriptionId -and
        $azureEndpoint.authorization.parameters.tenantid -eq $TenantId
    $azureEndpointEvidence = "id=$($azureEndpoint.id); scheme=$($azureEndpoint.authorization.scheme); ready=$($azureEndpoint.isReady); shared=$($azureEndpoint.isShared)"
}
else {
    $azureEndpointEvidence = "matches=$($azureEndpoints.Count)"
}
Add-AuditResult -Control 'Azure WIF service connection' -Passed $azureEndpointReady -Evidence $azureEndpointEvidence

$githubEndpoints = @($endpoints | Where-Object {
        $_.type -eq 'GitHub' -and
        $_.authorization.scheme -eq 'InstallationToken' -and
        [bool]$_.isReady
    })
$githubEndpointCompliant = $githubEndpoints.Count -eq 1 -and -not [bool]$githubEndpoints[0].isShared
$githubEvidence = if ($githubEndpoints.Count -eq 1) {
    "name=$($githubEndpoints[0].name); id=$($githubEndpoints[0].id); scheme=$($githubEndpoints[0].authorization.scheme)"
}
else {
    "ready GitHub App matches=$($githubEndpoints.Count)"
}
Add-AuditResult -Control 'GitHub App service connection' -Passed $githubEndpointCompliant -Evidence $githubEvidence

if ($azureEndpoints.Count -eq 1) {
    $azureEndpoint = Invoke-AzCommand `
        -Arguments @('devops', 'service-endpoint', 'show', '--organization', $OrganizationUrl, '--project', $ProjectName, '--id', $azureEndpoints[0].id, '--output', 'json', '--only-show-errors') `
        -Operation 'Azure WIF service connection detail lookup' `
        -ParseJson
    $ApplicationId = $azureEndpoint.authorization.parameters.serviceprincipalid

    $applications = @(Invoke-AzCommand `
            -Arguments @('ad', 'app', 'list', '--display-name', $ApplicationDisplayName, '--output', 'json', '--only-show-errors') `
            -Operation 'Microsoft Entra application lookup' `
            -ParseJson)
    $applicationCompliant = $applications.Count -eq 1 -and $applications[0].appId -eq $ApplicationId
    Add-AuditResult `
        -Control 'Dedicated Entra application' `
        -Passed $applicationCompliant `
        -Evidence "displayName=$ApplicationDisplayName; matches=$($applications.Count); expectedAppId=$ApplicationId"

    if ($applicationCompliant) {
        $application = Invoke-AzCommand `
            -Arguments @('ad', 'app', 'show', '--id', $ApplicationId, '--output', 'json', '--only-show-errors') `
            -Operation 'Microsoft Entra application detail lookup' `
            -ParseJson
        $passwordCount = @($application.passwordCredentials).Count
        $certificateCount = @($application.keyCredentials).Count
        Add-AuditResult `
            -Control 'No long-lived application credentials' `
            -Passed ($passwordCount -eq 0 -and $certificateCount -eq 0) `
            -Evidence "passwords=$passwordCount; certificates=$certificateCount"

        $servicePrincipal = Invoke-AzCommand `
            -Arguments @('ad', 'sp', 'show', '--id', $ApplicationId, '--output', 'json', '--only-show-errors') `
            -Operation 'Service Principal lookup' `
            -ParseJson
        $servicePrincipalCompliant = $servicePrincipal.appId -eq $ApplicationId -and $servicePrincipal.accountEnabled
        Add-AuditResult `
            -Control 'Service Principal' `
            -Passed $servicePrincipalCompliant `
            -Evidence "objectId=$($servicePrincipal.id); appId=$($servicePrincipal.appId); enabled=$($servicePrincipal.accountEnabled)"

        $federatedCredentials = @(Invoke-AzCommand `
                -Arguments @('ad', 'app', 'federated-credential', 'list', '--id', $ApplicationId, '--output', 'json', '--only-show-errors') `
                -Operation 'Federated credential lookup' `
                -ParseJson | Where-Object { $_.name -eq $FederatedCredentialName })
        $federatedCompliant =
            $federatedCredentials.Count -eq 1 -and
            $federatedCredentials[0].issuer -eq $azureEndpoint.authorization.parameters.workloadIdentityFederationIssuer -and
            $federatedCredentials[0].subject -eq $azureEndpoint.authorization.parameters.workloadIdentityFederationSubject -and
            @($federatedCredentials[0].audiences).Count -eq 1 -and
            $federatedCredentials[0].audiences[0] -eq $FederatedAudience
        Add-AuditResult `
            -Control 'Federated credential issuer/subject/audience' `
            -Passed $federatedCompliant `
            -Evidence "name=$FederatedCredentialName; matches=$($federatedCredentials.Count)"

        $roleAssignments = @(Invoke-AzCommand `
                -Arguments @('role', 'assignment', 'list', '--assignee-object-id', $servicePrincipal.id, '--scope', $SubscriptionScope, '--output', 'json', '--only-show-errors') `
                -Operation 'Azure RBAC lookup' `
                -ParseJson | Where-Object { $_.scope -eq $SubscriptionScope })
        foreach ($role in $RequiredSubscriptionRoles) {
            $roleMatches = @($roleAssignments | Where-Object { $_.roleDefinitionName -eq $role })
            Add-AuditResult `
                -Control "Subscription RBAC: $role" `
                -Passed ($roleMatches.Count -eq 1) `
                -Evidence "scope=$SubscriptionScope; matches=$($roleMatches.Count)"
        }
    }
}

$approver = Invoke-AzCommand `
    -Arguments @('devops', 'user', 'show', '--organization', $OrganizationUrl, '--user', $ProductionApprover, '--output', 'json', '--only-show-errors') `
    -Operation 'Production approver lookup' `
    -ParseJson
$ApproverId = $approver.id

$environmentResponse = Invoke-AzureDevOpsApi `
    -Area 'distributedtask' `
    -Resource 'environments' `
    -RouteParameters @("project=$ProjectId") `
    -ApiVersion '7.1'
$environments = @($environmentResponse.value)

foreach ($environmentName in $EnvironmentNames) {
    $environmentMatches = @($environments | Where-Object { $_.name -eq $environmentName })
    Add-AuditResult `
        -Control "Environment: $environmentName" `
        -Passed ($environmentMatches.Count -eq 1) `
        -Evidence "matches=$($environmentMatches.Count)"

    if ($environmentMatches.Count -ne 1) {
        continue
    }

    $environment = $environmentMatches[0]
    $checkResponse = Invoke-AzureDevOpsApi `
        -Area 'pipelineschecks' `
        -Resource 'configurations' `
        -RouteParameters @("project=$ProjectId") `
        -QueryParameters @('resourceType=environment', "resourceId=$($environment.id)", '$expand=settings') `
        -ApiVersion '7.1-preview'
    $checks = @($checkResponse.value)
    $branchChecks = @($checks | Where-Object {
            $_.type.id -eq $BranchCheckTypeId -and
            $_.settings.definitionRef.id -eq $BranchDefinitionId
        })
    $branchCompliant =
        $branchChecks.Count -eq 1 -and
        $branchChecks[0].settings.inputs.allowedBranches -eq $AllowedBranches -and
        ([string]$branchChecks[0].settings.inputs.ensureProtectionOfBranch).ToLowerInvariant() -eq 'false'
    Add-AuditResult `
        -Control "Branch control: $environmentName" `
        -Passed $branchCompliant `
        -Evidence "allowed=$AllowedBranches; matches=$($branchChecks.Count)"

    if ($environmentName -eq $ProductionEnvironment) {
        $approvals = @($checks | Where-Object { $_.type.id -eq $ApprovalCheckTypeId })
        $approvalCompliant =
            $approvals.Count -eq 1 -and
            @($approvals[0].settings.approvers).Count -eq 1 -and
            $approvals[0].settings.approvers[0].id -eq $ApproverId -and
            [int]$approvals[0].settings.minRequiredApprovers -eq 1 -and
            [bool]$approvals[0].settings.requesterCannotBeApprover
        Add-AuditResult `
            -Control 'Production approval' `
            -Passed $approvalCompliant `
            -Evidence "approver=$ProductionApprover; matches=$($approvals.Count); requesterCannotApprove=true"
    }
}

$pipelines = @(Invoke-AzCommand `
        -Arguments @('pipelines', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--name', $DiagnosticPipelineName, '--output', 'json', '--only-show-errors') `
        -Operation 'Diagnostic pipeline lookup' `
        -ParseJson | Where-Object { $_.name -eq $DiagnosticPipelineName })
$pipelineCompliant = $pipelines.Count -eq 1
if ($pipelineCompliant) {
    $pipeline = Invoke-AzCommand `
        -Arguments @('pipelines', 'show', '--organization', $OrganizationUrl, '--project', $ProjectName, '--id', [string]$pipelines[0].id, '--output', 'json', '--only-show-errors') `
        -Operation 'Diagnostic pipeline detail lookup' `
        -ParseJson
    $pipelineCompliant =
        $pipeline.repository.type -eq 'GitHub' -and
        $pipeline.repository.name -eq $GitHubRepository -and
        $pipeline.process.yamlFilename.TrimStart('/') -eq $DiagnosticYamlPath.TrimStart('/')
    $pipelineEvidence = "id=$($pipeline.id); repo=$($pipeline.repository.name); yaml=$($pipeline.process.yamlFilename)"
}
else {
    $pipelineEvidence = "matches=$($pipelines.Count)"
}
Add-AuditResult -Control 'Diagnostic pipeline definition' -Passed $pipelineCompliant -Evidence $pipelineEvidence

if ($pipelines.Count -eq 1) {
    $pipelineId = [int]$pipelines[0].id
    $runs = @(Invoke-AzCommand `
            -Arguments @('pipelines', 'runs', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--pipeline-ids', [string]$pipelineId, '--top', '20', '--output', 'json', '--only-show-errors') `
            -Operation 'Diagnostic pipeline run lookup' `
            -ParseJson)
    $successfulRuns = @($runs | Where-Object {
            $_.status -eq 'completed' -and
            $_.result -eq 'succeeded' -and
            $_.sourceBranch -eq 'refs/heads/main'
        } | Sort-Object finishTime -Descending)
    $runEvidence = if ($successfulRuns.Count -gt 0) {
        "run=$($successfulRuns[0].id); commit=$($successfulRuns[0].sourceVersion); branch=$($successfulRuns[0].sourceBranch)"
    }
    else {
        'no successful main run found'
    }
    Add-AuditResult `
        -Control 'Diagnostic run evidence' `
        -Passed ($successfulRuns.Count -gt 0) `
        -Evidence $runEvidence

    if ($azureEndpoints.Count -eq 1) {
        $permissions = Invoke-AzureDevOpsApi `
            -Area 'pipelinepermissions' `
            -Resource 'pipelinePermissions' `
            -RouteParameters @("project=$ProjectId", 'resourceType=endpoint', "resourceId=$($azureEndpoints[0].id)") `
            -ApiVersion '7.1-preview'
        $pipelinePermissions = @($permissions.pipelines | Where-Object {
                [int]$_.id -eq $pipelineId -and [bool]$_.authorized
            })
        $allPipelinesProperty = $permissions.PSObject.Properties['allPipelines']
        $globalAuthorized =
            $null -ne $allPipelinesProperty -and
            $null -ne $allPipelinesProperty.Value -and
            [bool]$allPipelinesProperty.Value.authorized
        Add-AuditResult `
            -Control 'Pipeline-scoped WIF authorization' `
            -Passed ($pipelinePermissions.Count -eq 1 -and -not $globalAuthorized) `
            -Evidence "pipelineId=$pipelineId; specificMatches=$($pipelinePermissions.Count); global=$globalAuthorized"
    }
}

$retention = Invoke-AzureDevOpsApi `
    -Area 'build' `
    -Resource 'retention' `
    -RouteParameters @("project=$ProjectId") `
    -ApiVersion '7.1'
$retentionCompliant =
    [int]$retention.purgeRuns.value -eq 30 -and
    [int]$retention.purgeArtifacts.value -eq 30 -and
    [int]$retention.purgePullRequestRuns.value -eq 14 -and
    [int]$retention.retainRunsPerProtectedBranch.value -eq 3
Add-AuditResult `
    -Control 'Project retention policy' `
    -Passed $retentionCompliant `
    -Evidence "runs=$($retention.purgeRuns.value); artifacts=$($retention.purgeArtifacts.value); PR=$($retention.purgePullRequestRuns.value); recent=$($retention.retainRunsPerProtectedBranch.value)"

$passCount = @($Results | Where-Object { $_.Status -eq 'PASS' }).Count
$failures = @($Results | Where-Object { $_.Status -eq 'FAIL' })

Write-Host ''
Write-Host 'Audit summary:'
$Results | Format-Table Status, Control, Evidence -Wrap -AutoSize
Write-Host "Controls: $($Results.Count); passed: $passCount; failed: $($failures.Count)."

if ($failures.Count -gt 0) {
    $failedControls = ($failures.Control -join ', ')
    throw "Bootstrap verification failed: $failedControls"
}

Write-Host '[VERIFIED] ADOP-1 bootstrap audit completed with zero failures.' -ForegroundColor Green
Write-Host '[VERIFIED] This script performed read-only operations only.' -ForegroundColor Green
