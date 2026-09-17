#Requires -Version 7.0

<#
.SYNOPSIS
Registers the MovieOps diagnostic Azure Pipeline and grants least privilege.

.DESCRIPTION
Validates the manual Azure Pipelines GitHub App gate, creates or verifies the
MovieOps-Diagnostic YAML pipeline, and authorizes the Azure WIF service
connection only for that pipeline. The first run remains a deliberate operator
action.

The GitHub App installation cannot be scripted because it requires interactive
repository-owner consent. OAuth and PAT GitHub connections are rejected.

.EXAMPLE
./scripts/azure-devops/03-configure-pipelines/configure-pipelines.ps1 -WhatIf

.EXAMPLE
./scripts/azure-devops/03-configure-pipelines/configure-pipelines.ps1

.EXAMPLE
./scripts/azure-devops/03-configure-pipelines/configure-pipelines.ps1 `
  -GitHubServiceConnectionId '00000000-0000-0000-0000-000000000000'
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
    [string]$PipelineName = 'MovieOps-Diagnostic',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$YamlPath = 'azure-pipelines/diagnostic.yml',

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
$PipelineDescription = 'Read-only validation of GitHub checkout and Azure WIF access for MovieOps.'
$RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$YamlFullPath = Join-Path $RepositoryRoot $YamlPath

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

function Assert-YamlPublishedToMain {
    $status = @(Invoke-GitCommand `
            -Arguments @('status', '--porcelain', '--', $YamlPath) `
            -Operation "Git status check for '$YamlPath'")
    if ($status.Count -gt 0) {
        throw "'$YamlPath' has uncommitted changes. Commit and push this step before registering the pipeline."
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

    Write-Host "[VERIFIED] YAML is committed and published on origin/$Branch ($headSha)."
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Required command 'az' was not found in PATH."
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Required command 'git' was not found in PATH."
}
if (-not (Test-Path -LiteralPath $YamlFullPath -PathType Leaf)) {
    throw "Pipeline YAML was not found: $YamlFullPath"
}
Write-Host "[VERIFIED] Local pipeline YAML: $YamlPath."

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
Write-Host "[VERIFIED] Azure WIF service connection: $AzureServiceConnectionName ($($azureEndpoint.id))."

$githubEndpoints = @($endpoints | Where-Object {
        $_.type -eq 'github' -and
        $_.authorization.scheme -eq 'InstallationToken' -and
        $_.isReady
    })

if ($GitHubServiceConnectionId) {
    $githubEndpoints = @($githubEndpoints | Where-Object { $_.id -eq $GitHubServiceConnectionId })
}

if ($githubEndpoints.Count -eq 0) {
    Write-Host '[MANUAL ACTION REQUIRED] Install/authorize the Azure Pipelines GitHub App.' -ForegroundColor Yellow
    Write-Host "[MANUAL ACTION REQUIRED] Limit repository access to '$GitHubRepository'." -ForegroundColor Yellow
    Write-Host "[MANUAL ACTION REQUIRED] Associate it with '$OrganizationUrl' / '$ProjectName'." -ForegroundColor Yellow
    Write-Host '[MANUAL ACTION REQUIRED] Do not use OAuth or a GitHub PAT.' -ForegroundColor Yellow
    if ($WhatIfPreference) {
        Write-Host '[VERIFIED] Preview stopped at the expected manual consent gate. No resource was changed.'
        return
    }
    throw "No ready GitHub service connection using authorization scheme 'InstallationToken' was found."
}
if ($githubEndpoints.Count -gt 1) {
    $ids = ($githubEndpoints | ForEach-Object { "$($_.name)=$($_.id)" }) -join ', '
    throw "Multiple GitHub App connections were found: $ids. Rerun with -GitHubServiceConnectionId."
}
$githubEndpoint = $githubEndpoints[0]
Write-Host "[VERIFIED] GitHub App service connection: $($githubEndpoint.name) ($($githubEndpoint.id))."

$pipelines = @(Invoke-AzCommand `
        -Arguments @('pipelines', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--output', 'json', '--only-show-errors') `
        -Operation 'Azure Pipeline lookup' `
        -ParseJson)
$pipelineMatches = @($pipelines | Where-Object { $_.name -eq $PipelineName })
if ($pipelineMatches.Count -gt 1) {
    throw "Found $($pipelineMatches.Count) pipelines named '$PipelineName'. Resolve the ambiguity before rerunning."
}

if ($pipelineMatches.Count -eq 0) {
    if ($WhatIfPreference) {
        Write-Host "[PLAN] Commit and publish '$YamlPath' to origin/$Branch before application."
        Write-Host "[PLAN] Create pipeline '$PipelineName' from '${GitHubRepository}:$YamlPath'."
        Write-Host "[PLAN] Authorize '$AzureServiceConnectionName' only for '$PipelineName'."
        Write-Host '[VERIFIED] Preview completed. No Azure DevOps resource was changed.'
        return
    }

    Assert-YamlPublishedToMain
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
    Write-Host "[EXISTS] Pipeline '$PipelineName' ($($pipeline.id)) is bound to the expected repository and YAML."
}

if ($null -eq $pipeline -or $null -eq $pipeline.id) {
    throw "Pipeline '$PipelineName' was not resolved; authorization cannot continue."
}

$permissions = Invoke-PipelinePermissionsApi `
    -Method GET `
    -ProjectId $ProjectId `
    -ResourceId $azureEndpoint.id
$pipelinePermission = @($permissions.pipelines | Where-Object { [int]$_.id -eq [int]$pipeline.id })

if ($pipelinePermission.Count -eq 1 -and [bool]$pipelinePermission[0].authorized) {
    Write-Host "[EXISTS] '$AzureServiceConnectionName' is authorized for '$PipelineName'."
}
else {
    $permissionBody = @{
        pipelines = @(
            @{
                id         = [int]$pipeline.id
                authorized = $true
            }
        )
    }
    if ($PSCmdlet.ShouldProcess($PipelineName, "Authorize Azure service connection '$AzureServiceConnectionName'")) {
        [void](Invoke-PipelinePermissionsApi `
                -Method PATCH `
                -ProjectId $ProjectId `
                -ResourceId $azureEndpoint.id `
                -Body $permissionBody)
        Write-Host "[UPDATED] '$AzureServiceConnectionName' authorized only for '$PipelineName'."
    }
}

if ($WhatIfPreference) {
    Write-Host '[VERIFIED] Preview completed. No Azure DevOps resource was changed.'
    return
}

$finalPermissions = Invoke-PipelinePermissionsApi `
    -Method GET `
    -ProjectId $ProjectId `
    -ResourceId $azureEndpoint.id
$finalPipelinePermission = @($finalPermissions.pipelines | Where-Object {
        [int]$_.id -eq [int]$pipeline.id -and [bool]$_.authorized
    })
if ($finalPipelinePermission.Count -ne 1) {
    throw "Final verification failed: '$AzureServiceConnectionName' is not authorized for '$PipelineName'."
}
$allPipelinesProperty = $finalPermissions.PSObject.Properties['allPipelines']
$allPipelinesAuthorization = if ($null -ne $allPipelinesProperty) {
    $allPipelinesProperty.Value
}
else {
    $null
}
if ($null -ne $allPipelinesAuthorization -and [bool]$allPipelinesAuthorization.authorized) {
    throw "Final verification failed: '$AzureServiceConnectionName' is authorized for all pipelines."
}

Write-Host "[VERIFIED] Pipeline '$PipelineName' is registered without an automatic first run."
Write-Host "[VERIFIED] Azure connection authorization is pipeline-scoped; global access remains disabled."
Write-Host '[MANUAL ACTION REQUIRED] Run MovieOps-Diagnostic from Azure DevOps and share its complete log.' -ForegroundColor Yellow
