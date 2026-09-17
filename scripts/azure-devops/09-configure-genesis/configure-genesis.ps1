#Requires -Version 7.0

<#
.SYNOPSIS
Registers MovieOps-Genesis and grants its exclusive Azure WIF permission.

.DESCRIPTION
Creates or verifies the manual Azure Pipeline backed by
azure-pipelines/genesis.yml. The Azure WIF service connection is authorized
only for this pipeline. The script never runs Genesis or creates infrastructure.

.EXAMPLE
./scripts/azure-devops/09-configure-genesis/configure-genesis.ps1 -WhatIf

.EXAMPLE
./scripts/azure-devops/09-configure-genesis/configure-genesis.ps1
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidatePattern('^https://dev\.azure\.com/[A-Za-z0-9-]+/?$')]
    [string]$OrganizationUrl = 'https://dev.azure.com/ajunquit',

    [Parameter()]
    [string]$ProjectName = 'MovieOps',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$GitHubRepository = 'ajunquit/movieops',

    [Parameter()]
    [string]$Branch = 'main',

    [Parameter()]
    [string]$PipelineName = 'MovieOps-Genesis',

    [Parameter()]
    [string]$YamlPath = 'azure-pipelines/genesis.yml',

    [Parameter()]
    [string]$AzureServiceConnectionName = 'sc-movieops-azure-wif',

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$GitHubServiceConnectionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OrganizationUrl = $OrganizationUrl.TrimEnd('/')
$PipelinePermissionsApiVersion = '7.1-preview'
$PipelineDescription = 'Manual Terraform Genesis for MovieOps with typed confirmation, saved plan, WIF, and idempotence verification.'
$RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$RequiredPublishedPaths = @(
    $YamlPath,
    'terraform/environments/azure/dev/main.tf',
    'terraform/environments/azure/dev/variables.tf',
    'terraform/modules/azure/secrets/main.tf',
    'terraform/modules/azure/secrets/variables.tf'
)

function Invoke-AzCommand {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Operation,
        [Parameter()][switch]$ParseJson
    )

    $output = @(& az @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed with exit code $LASTEXITCODE.`n$($output -join [Environment]::NewLine)"
    }
    if (-not $ParseJson) {
        return $output
    }
    $json = $output -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($json)) {
        throw "$Operation returned an empty response; JSON was expected."
    }
    return $json | ConvertFrom-Json
}

function Invoke-GitCommand {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Operation
    )

    $output = @(& git -C $RepositoryRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed with exit code $LASTEXITCODE.`n$($output -join [Environment]::NewLine)"
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
            [System.IO.File]::WriteAllText(
                $temporaryFile,
                ($Body | ConvertTo-Json -Depth 10 -Compress),
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

function Assert-FilesPublishedToMain {
    $status = @(Invoke-GitCommand `
            -Arguments (@('status', '--porcelain', '--') + $RequiredPublishedPaths) `
            -Operation 'Genesis files git status check')
    if ($status.Count -gt 0) {
        throw 'Genesis YAML or Terraform identity files have uncommitted changes. Commit and push before registration.'
    }

    $currentBranch = (Invoke-GitCommand -Arguments @('branch', '--show-current') -Operation 'Current branch lookup' | Select-Object -First 1).Trim()
    if ($currentBranch -ne $Branch) {
        throw "Current branch is '$currentBranch', expected '$Branch'."
    }
    $headSha = (Invoke-GitCommand -Arguments @('rev-parse', 'HEAD') -Operation 'Local HEAD lookup' | Select-Object -First 1).Trim()
    $remoteLine = (Invoke-GitCommand -Arguments @('ls-remote', 'origin', "refs/heads/$Branch") -Operation 'Remote branch lookup' | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($remoteLine)) {
        throw "Remote branch 'origin/$Branch' does not exist."
    }
    $remoteSha = ($remoteLine -split '\s+')[0]
    if ($headSha -ne $remoteSha) {
        throw "Local HEAD '$headSha' does not match origin/$Branch '$remoteSha'. Push or synchronize before continuing."
    }
    Write-Host "[VERIFIED] Genesis and Terraform files are published on origin/$Branch ($headSha)."
}

function Get-AuthorizedPipelines {
    param(
        [Parameter(Mandatory)][object]$Permissions
    )

    $pipelinesProperty = $Permissions.PSObject.Properties['pipelines']
    if ($null -eq $pipelinesProperty -or $null -eq $pipelinesProperty.Value) {
        return @()
    }
    return @($pipelinesProperty.Value | Where-Object { [bool]$_.authorized })
}

foreach ($command in @('az', 'git')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command '$command' was not found in PATH."
    }
}
foreach ($path in $RequiredPublishedPaths) {
    $fullPath = Join-Path $RepositoryRoot $path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Required file was not found: $fullPath"
    }
    Write-Host "[VERIFIED] Local file: $path."
}

$project = Invoke-AzCommand `
    -Arguments @('devops', 'project', 'show', '--organization', $OrganizationUrl, '--project', $ProjectName, '--output', 'json', '--only-show-errors') `
    -Operation 'Azure DevOps project lookup' `
    -ParseJson
if ($project.state -ne 'wellFormed') {
    throw "Project '$ProjectName' is not wellFormed."
}
Write-Host "[VERIFIED] Azure DevOps project: $ProjectName ($($project.id))."

$endpoints = @(Invoke-AzCommand `
        -Arguments @('devops', 'service-endpoint', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--output', 'json', '--only-show-errors') `
        -Operation 'Service connection lookup' `
        -ParseJson)
$azureEndpoints = @($endpoints | Where-Object { $_.name -eq $AzureServiceConnectionName })
if ($azureEndpoints.Count -ne 1) {
    throw "Expected one Azure service connection '$AzureServiceConnectionName'; found $($azureEndpoints.Count)."
}
$azureEndpoint = $azureEndpoints[0]
if ($azureEndpoint.type -ne 'azurerm' -or $azureEndpoint.authorization.scheme -ne 'WorkloadIdentityFederation' -or -not $azureEndpoint.isReady) {
    throw "Azure service connection '$AzureServiceConnectionName' is not a ready WIF connection."
}
Write-Host "[VERIFIED] Azure WIF service connection: $AzureServiceConnectionName ($($azureEndpoint.id))."

$githubEndpoints = @($endpoints | Where-Object {
        $_.type -eq 'github' -and $_.authorization.scheme -eq 'InstallationToken' -and $_.isReady
    })
if ($GitHubServiceConnectionId) {
    $githubEndpoints = @($githubEndpoints | Where-Object { $_.id -eq $GitHubServiceConnectionId })
}
if ($githubEndpoints.Count -ne 1) {
    throw "Expected one ready GitHub App connection; found $($githubEndpoints.Count)."
}
$githubEndpoint = $githubEndpoints[0]
Write-Host "[VERIFIED] GitHub App service connection: $($githubEndpoint.name) ($($githubEndpoint.id))."

$pipelines = @(Invoke-AzCommand `
        -Arguments @('pipelines', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--output', 'json', '--only-show-errors') `
        -Operation 'Pipeline lookup' `
        -ParseJson)
$pipelineMatches = @($pipelines | Where-Object { $_.name -eq $PipelineName })
if ($pipelineMatches.Count -gt 1) {
    throw "Found multiple pipelines named '$PipelineName'."
}

$pipeline = $null
if ($pipelineMatches.Count -eq 0) {
    if ($WhatIfPreference) {
        Write-Host "[PLAN] Commit and publish Genesis/Terraform files to origin/$Branch."
        Write-Host "[PLAN] Create manual pipeline '$PipelineName' from '${GitHubRepository}:$YamlPath'."
        Write-Host "[PLAN] Authorize '$AzureServiceConnectionName' only for '$PipelineName'."
        Write-Host '[VERIFIED] Preview completed. No Azure DevOps resource was changed.'
        return
    }
    Assert-FilesPublishedToMain
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
            -Operation "Create pipeline '$PipelineName'" `
            -ParseJson
        Write-Host "[CREATED] Pipeline '$PipelineName' ($($pipeline.id)); first run skipped."
    }
}
else {
    $pipeline = Invoke-AzCommand `
        -Arguments @('pipelines', 'show', '--organization', $OrganizationUrl, '--project', $ProjectName, '--id', [string]$pipelineMatches[0].id, '--output', 'json', '--only-show-errors') `
        -Operation "Pipeline '$PipelineName' lookup" `
        -ParseJson
    if ($pipeline.repository.type -ne 'GitHub' -or $pipeline.repository.name -ne $GitHubRepository) {
        throw "Pipeline '$PipelineName' uses an unexpected repository."
    }
    if ($pipeline.process.yamlFilename.TrimStart('/') -ne $YamlPath.TrimStart('/')) {
        throw "Pipeline '$PipelineName' uses '$($pipeline.process.yamlFilename)', expected '$YamlPath'."
    }
    Write-Host "[EXISTS] Pipeline '$PipelineName' ($($pipeline.id)) uses the expected repository and YAML."
}

if ($null -eq $pipeline -or $null -eq $pipeline.id) {
    throw "Pipeline '$PipelineName' was not resolved."
}

$permissions = Invoke-PipelinePermissionsApi -Method GET -ProjectId $project.id -ResourceId $azureEndpoint.id
$allPipelinesProperty = $permissions.PSObject.Properties['allPipelines']
if ($null -ne $allPipelinesProperty -and $null -ne $allPipelinesProperty.Value -and [bool]$allPipelinesProperty.Value.authorized) {
    throw "'$AzureServiceConnectionName' is authorized globally. Disable global access before continuing."
}
$authorizedPipelines = @(Get-AuthorizedPipelines -Permissions $permissions)
$pipelinePermission = @($authorizedPipelines | Where-Object { [int]$_.id -eq [int]$pipeline.id })
if ($pipelinePermission.Count -eq 1) {
    Write-Host "[EXISTS] '$AzureServiceConnectionName' is authorized for '$PipelineName'."
}
else {
    $body = @{ pipelines = @(@{ id = [int]$pipeline.id; authorized = $true }) }
    if ($PSCmdlet.ShouldProcess($PipelineName, "Authorize Azure service connection '$AzureServiceConnectionName'")) {
        [void](Invoke-PipelinePermissionsApi -Method PATCH -ProjectId $project.id -ResourceId $azureEndpoint.id -Body $body)
        Write-Host "[UPDATED] '$AzureServiceConnectionName' authorized only for '$PipelineName'."
    }
}

if ($WhatIfPreference) {
    Write-Host '[VERIFIED] Preview completed. No Azure DevOps resource was changed.'
    return
}

$finalPermissions = Invoke-PipelinePermissionsApi -Method GET -ProjectId $project.id -ResourceId $azureEndpoint.id
$finalAuthorizedPipelines = @(Get-AuthorizedPipelines -Permissions $finalPermissions)
$finalPermission = @($finalAuthorizedPipelines | Where-Object { [int]$_.id -eq [int]$pipeline.id })
if ($finalPermission.Count -ne 1) {
    throw "Final verification failed: WIF is not authorized for '$PipelineName'."
}
$finalAllProperty = $finalPermissions.PSObject.Properties['allPipelines']
if ($null -ne $finalAllProperty -and $null -ne $finalAllProperty.Value -and [bool]$finalAllProperty.Value.authorized) {
    throw 'Final verification failed: WIF is authorized for all pipelines.'
}

Write-Host "[VERIFIED] Pipeline '$PipelineName' is registered without an automatic run."
Write-Host '[VERIFIED] Azure WIF permission is pipeline-scoped; global access remains disabled.'
Write-Host "[MANUAL ACTION REQUIRED] Run '$PipelineName' with environment=dev and confirm=dev." -ForegroundColor Yellow
