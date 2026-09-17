#Requires -Version 7.0

<#
.SYNOPSIS
Registers and verifies the MovieOps CI pipeline in Azure DevOps.

.DESCRIPTION
Creates or validates MovieOps-CI from the GitHub repository and the versioned
Azure Pipelines YAML. The script deliberately keeps the Azure WIF service
connection unauthorized because CI does not deploy or mutate Azure resources.

.EXAMPLE
./scripts/azure-devops/06-configure-ci/configure-ci.ps1 -WhatIf

.EXAMPLE
./scripts/azure-devops/06-configure-ci/configure-ci.ps1
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
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$GitHubRepository = 'ajunquit/movieops',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Branch = 'main',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PipelineName = 'MovieOps-CI',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$YamlPath = 'azure-pipelines/ci.yml',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$AzureServiceConnectionName = 'sc-movieops-azure-wif',

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$GitHubServiceConnectionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$OrganizationUrl = $OrganizationUrl.TrimEnd('/')
$PipelinePermissionsApiVersion = '7.1-preview'
$PipelineDescription = 'MovieOps CI parity: tests, coverage, security, quality gate, and immutable image artifact.'
$RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$RequiredPipelineFiles = @(
    $YamlPath,
    'azure-pipelines/templates/backend-ci.yml',
    'azure-pipelines/templates/frontend-ci.yml',
    'azure-pipelines/templates/security-scan.yml',
    'azure-pipelines/templates/docker-build.yml'
)

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

function Invoke-GitCommand {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Operation
    )

    $output = @(& git -C $RepositoryRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $details = $output -join [Environment]::NewLine
        throw "$Operation failed with exit code $LASTEXITCODE.`n$details"
    }
    return $output
}

function Invoke-PipelinePermissionsApi {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'PATCH')][string]$Method,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$ResourceId,
        [Parameter()][object]$Body
    )

    $arguments = @(
        'devops', 'invoke',
        '--organization', $OrganizationUrl,
        '--area', 'pipelinepermissions',
        '--resource', 'pipelinePermissions',
        '--route-parameters',
        "project=$ProjectId",
        'resourceType=endpoint',
        "resourceId=$ResourceId",
        '--api-version', $PipelinePermissionsApiVersion,
        '--http-method', $Method,
        '--output', 'json',
        '--only-show-errors'
    )

    $temporaryFile = $null
    try {
        if ($PSBoundParameters.ContainsKey('Body')) {
            $temporaryFile = [System.IO.Path]::GetTempFileName()
            $json = $Body | ConvertTo-Json -Depth 10 -Compress
            [System.IO.File]::WriteAllText(
                $temporaryFile,
                $json,
                [System.Text.UTF8Encoding]::new($false)
            )
            $arguments += @('--in-file', $temporaryFile)
        }

        return Invoke-AzCommand `
            -Arguments $arguments `
            -Operation "Azure DevOps pipeline permission $Method" `
            -ParseJson
    }
    finally {
        if ($temporaryFile -and (Test-Path -LiteralPath $temporaryFile)) {
            Remove-Item -LiteralPath $temporaryFile -Force
        }
    }
}

function Assert-PipelineFilesPublishedToMain {
    $status = @(Invoke-GitCommand `
            -Arguments (@('status', '--porcelain', '--') + $RequiredPipelineFiles) `
            -Operation 'Pipeline files git status check')
    if ($status.Count -gt 0) {
        throw 'CI pipeline files have uncommitted changes. Commit and push this step before registering the pipeline.'
    }

    $currentBranch = (Invoke-GitCommand `
            -Arguments @('branch', '--show-current') `
            -Operation 'Current Git branch lookup' | Select-Object -First 1).Trim()
    if ($currentBranch -ne $Branch) {
        throw "Current branch is '$currentBranch', expected '$Branch'. Merge this step into '$Branch' and update the local checkout first."
    }

    $headSha = (Invoke-GitCommand `
            -Arguments @('rev-parse', 'HEAD') `
            -Operation 'Local HEAD lookup' | Select-Object -First 1).Trim()
    $remoteLine = (Invoke-GitCommand `
            -Arguments @('ls-remote', 'origin', "refs/heads/$Branch") `
            -Operation "Remote '$Branch' lookup" | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($remoteLine)) {
        throw "Remote branch 'origin/$Branch' does not exist."
    }
    $remoteSha = ($remoteLine -split '\s+')[0]
    if ($headSha -ne $remoteSha) {
        throw "Local HEAD '$headSha' does not match origin/$Branch '$remoteSha'. Push or synchronize before continuing."
    }

    Write-Host "[VERIFIED] CI YAML and templates are published on origin/$Branch ($headSha)."
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Required command 'az' was not found in PATH."
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Required command 'git' was not found in PATH."
}

foreach ($pipelineFile in $RequiredPipelineFiles) {
    $fullPath = Join-Path $RepositoryRoot $pipelineFile
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Required pipeline file was not found: $fullPath"
    }
    Write-Host "[VERIFIED] Local pipeline file: $pipelineFile."
}

$project = Invoke-AzCommand `
    -Arguments @('devops', 'project', 'show', '--organization', $OrganizationUrl, '--project', $ProjectName, '--output', 'json', '--only-show-errors') `
    -Operation 'Azure DevOps project lookup' `
    -ParseJson
if ($project.state -ne 'wellFormed') {
    throw "Project '$ProjectName' is in state '$($project.state)', expected 'wellFormed'."
}
$ProjectId = $project.id
Write-Host "[VERIFIED] Azure DevOps project: $ProjectName ($ProjectId)."

$endpoints = @(Invoke-AzCommand `
        -Arguments @('devops', 'service-endpoint', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--output', 'json', '--only-show-errors') `
        -Operation 'Azure DevOps service connection lookup' `
        -ParseJson)

$githubEndpoints = @($endpoints | Where-Object {
        $_.type -eq 'github' -and
        $_.authorization.scheme -eq 'InstallationToken' -and
        $_.isReady
    })
if ($GitHubServiceConnectionId) {
    $githubEndpoints = @($githubEndpoints | Where-Object { $_.id -eq $GitHubServiceConnectionId })
}
if ($githubEndpoints.Count -ne 1) {
    $detail = if ($githubEndpoints.Count -eq 0) { 'none' } else { ($githubEndpoints.id -join ', ') }
    throw "Expected exactly one ready GitHub App connection; found: $detail. Use -GitHubServiceConnectionId when necessary."
}
$githubEndpoint = $githubEndpoints[0]
Write-Host "[VERIFIED] GitHub App service connection: $($githubEndpoint.name) ($($githubEndpoint.id))."

$azureEndpoints = @($endpoints | Where-Object { $_.name -eq $AzureServiceConnectionName })
if ($azureEndpoints.Count -ne 1) {
    throw "Expected exactly one Azure service connection '$AzureServiceConnectionName'; found $($azureEndpoints.Count)."
}
$azureEndpoint = $azureEndpoints[0]
if ($azureEndpoint.type -ne 'azurerm' -or
    $azureEndpoint.authorization.scheme -ne 'WorkloadIdentityFederation' -or
    -not $azureEndpoint.isReady) {
    throw "Azure service connection '$AzureServiceConnectionName' is not a ready WIF connection."
}
Write-Host "[VERIFIED] Azure WIF connection exists and must remain unauthorized for CI."

$pipelines = @(Invoke-AzCommand `
        -Arguments @('pipelines', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--output', 'json', '--only-show-errors') `
        -Operation 'Azure Pipeline lookup' `
        -ParseJson)
$pipelineMatches = @($pipelines | Where-Object { $_.name -eq $PipelineName })
if ($pipelineMatches.Count -gt 1) {
    throw "Found $($pipelineMatches.Count) pipelines named '$PipelineName'. Resolve the ambiguity before rerunning."
}

$pipeline = $null
if ($pipelineMatches.Count -eq 0) {
    if ($WhatIfPreference) {
        Write-Host "[PLAN] Commit and publish the CI YAML/templates to origin/$Branch."
        Write-Host "[PLAN] Create pipeline '$PipelineName' from '${GitHubRepository}:$YamlPath' without an initial run."
        Write-Host "[PLAN] Keep '$AzureServiceConnectionName' unauthorized for '$PipelineName'."
        Write-Host '[VERIFIED] Preview completed. No Azure DevOps resource was changed.'
        return
    }

    Assert-PipelineFilesPublishedToMain
    if ($PSCmdlet.ShouldProcess($ProjectName, "Create Azure Pipeline '$PipelineName'")) {
        $pipeline = Invoke-AzCommand `
            -Arguments @(
                'pipelines', 'create',
                '--organization', $OrganizationUrl,
                '--project', $ProjectName,
                '--name', $PipelineName,
                '--description', $PipelineDescription,
                '--repository', $GitHubRepository,
                '--repository-type', 'github',
                '--service-connection', $githubEndpoint.id,
                '--branch', $Branch,
                '--yaml-path', $YamlPath,
                '--skip-run', 'true',
                '--output', 'json',
                '--only-show-errors'
            ) `
            -Operation "Create Azure Pipeline '$PipelineName'" `
            -ParseJson
        Write-Host "[CREATED] Pipeline '$PipelineName' ($($pipeline.id)); first run skipped."
    }
}
else {
    $pipeline = Invoke-AzCommand `
        -Arguments @('pipelines', 'show', '--organization', $OrganizationUrl, '--project', $ProjectName, '--id', [string]$pipelineMatches[0].id, '--output', 'json', '--only-show-errors') `
        -Operation "Azure Pipeline '$PipelineName' lookup" `
        -ParseJson

    if ($pipeline.repository.type -ne 'GitHub' -or $pipeline.repository.name -ne $GitHubRepository) {
        throw "Existing pipeline '$PipelineName' points to '$($pipeline.repository.type):$($pipeline.repository.name)', not 'GitHub:$GitHubRepository'."
    }
    if ($pipeline.process.yamlFilename.TrimStart('/') -ne $YamlPath.TrimStart('/')) {
        throw "Existing pipeline '$PipelineName' uses '$($pipeline.process.yamlFilename)', expected '$YamlPath'."
    }
    Write-Host "[EXISTS] Pipeline '$PipelineName' ($($pipeline.id)) uses the expected repository and YAML."
}

if ($null -eq $pipeline -or $null -eq $pipeline.id) {
    throw "Pipeline '$PipelineName' was not resolved; least-privilege verification cannot continue."
}

$permissions = Invoke-PipelinePermissionsApi `
    -Method GET `
    -ProjectId $ProjectId `
    -ResourceId $azureEndpoint.id
$allPipelinesProperty = $permissions.PSObject.Properties['allPipelines']
if ($null -ne $allPipelinesProperty -and
    $null -ne $allPipelinesProperty.Value -and
    [bool]$allPipelinesProperty.Value.authorized) {
    throw "'$AzureServiceConnectionName' is authorized for all pipelines. Disable global access before continuing."
}

$ciPermission = @($permissions.pipelines | Where-Object {
        [int]$_.id -eq [int]$pipeline.id -and [bool]$_.authorized
    })
if ($ciPermission.Count -gt 0) {
    $permissionBody = @{
        pipelines = @(
            @{
                id         = [int]$pipeline.id
                authorized = $false
            }
        )
    }
    if ($PSCmdlet.ShouldProcess($PipelineName, "Revoke Azure service connection '$AzureServiceConnectionName'")) {
        [void](Invoke-PipelinePermissionsApi `
                -Method PATCH `
                -ProjectId $ProjectId `
                -ResourceId $azureEndpoint.id `
                -Body $permissionBody)
        Write-Host "[UPDATED] Revoked '$AzureServiceConnectionName' from '$PipelineName'."
    }
}
else {
    Write-Host "[EXISTS] '$PipelineName' has no authorization for '$AzureServiceConnectionName'."
}

if ($WhatIfPreference) {
    Write-Host '[VERIFIED] Preview completed. No Azure DevOps resource was changed.'
    return
}

$finalPermissions = Invoke-PipelinePermissionsApi `
    -Method GET `
    -ProjectId $ProjectId `
    -ResourceId $azureEndpoint.id
$finalCiPermission = @($finalPermissions.pipelines | Where-Object {
        [int]$_.id -eq [int]$pipeline.id -and [bool]$_.authorized
    })
if ($finalCiPermission.Count -gt 0) {
    throw "Final verification failed: '$AzureServiceConnectionName' remains authorized for '$PipelineName'."
}

Write-Host "[VERIFIED] Pipeline '$PipelineName' is registered with GitHub App authentication."
Write-Host '[VERIFIED] Push/PR triggers are controlled by the versioned YAML.'
Write-Host "[VERIFIED] '$AzureServiceConnectionName' is not authorized for CI."
Write-Host '[MANUAL ACTION REQUIRED] Run MovieOps-CI on main, then validate one healthy and one intentionally broken PR.' -ForegroundColor Yellow
