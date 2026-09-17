#Requires -Version 7.0

<#
.SYNOPSIS
Configures and verifies MovieOps project-level pipeline retention.

.DESCRIPTION
Uses the public Azure DevOps Build Retention API to converge run, artifact,
pull-request run, and recent-run retention settings for the MovieOps Project.
The script validates the server-advertised minimum and maximum for every value
before applying changes.

.EXAMPLE
./scripts/azure-devops/04-configure-retention/configure-retention.ps1 -WhatIf

.EXAMPLE
./scripts/azure-devops/04-configure-retention/configure-retention.ps1
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
    [ValidateRange(1, 10000)]
    [int]$RunRetentionDays = 30,

    [Parameter()]
    [ValidateRange(1, 10000)]
    [int]$ArtifactRetentionDays = 30,

    [Parameter()]
    [ValidateRange(1, 10000)]
    [int]$PullRequestRunRetentionDays = 14,

    [Parameter()]
    [ValidateRange(0, 10000)]
    [int]$RecentRunsPerPipeline = 3,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DiagnosticPipelineName = 'MovieOps-Diagnostic'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$OrganizationUrl = $OrganizationUrl.TrimEnd('/')
$ApiVersion = '7.1'

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

function Invoke-RetentionApi {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'PATCH')][string]$Method,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter()][object]$Body
    )

    $arguments = @(
        'devops', 'invoke',
        '--organization', $OrganizationUrl,
        '--area', 'build',
        '--resource', 'retention',
        '--route-parameters', "project=$ProjectId",
        '--api-version', $ApiVersion,
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
            -Operation "Azure DevOps Build Retention API $Method" `
            -ParseJson
    }
    finally {
        if ($temporaryFile -and (Test-Path -LiteralPath $temporaryFile)) {
            Remove-Item -LiteralPath $temporaryFile -Force
        }
    }
}

function Get-RetentionRows {
    param([Parameter(Mandatory)][object]$Settings)

    return @(
        [pscustomobject]@{
            Key     = 'runRetention'
            Name    = 'Runs and logs'
            Desired = $RunRetentionDays
            Current = [int]$Settings.purgeRuns.value
            Min     = [int]$Settings.purgeRuns.min
            Max     = [int]$Settings.purgeRuns.max
        },
        [pscustomobject]@{
            Key     = 'artifactsRetention'
            Name    = 'Artifacts, symbols and attachments'
            Desired = $ArtifactRetentionDays
            Current = [int]$Settings.purgeArtifacts.value
            Min     = [int]$Settings.purgeArtifacts.min
            Max     = [int]$Settings.purgeArtifacts.max
        },
        [pscustomobject]@{
            Key     = 'pullRequestRunRetention'
            Name    = 'Pull Request runs'
            Desired = $PullRequestRunRetentionDays
            Current = [int]$Settings.purgePullRequestRuns.value
            Min     = [int]$Settings.purgePullRequestRuns.min
            Max     = [int]$Settings.purgePullRequestRuns.max
        },
        [pscustomobject]@{
            Key     = 'retainRunsPerProtectedBranch'
            Name    = 'Recent runs per pipeline'
            Desired = $RecentRunsPerPipeline
            Current = [int]$Settings.retainRunsPerProtectedBranch.value
            Min     = [int]$Settings.retainRunsPerProtectedBranch.min
            Max     = [int]$Settings.retainRunsPerProtectedBranch.max
        }
    )
}

function Assert-DesiredValuesWithinServerLimits {
    param([Parameter(Mandatory)][object[]]$Rows)

    foreach ($row in $Rows) {
        if ($row.Desired -lt $row.Min -or $row.Desired -gt $row.Max) {
            throw "Desired value for '$($row.Name)' is $($row.Desired), outside the server range $($row.Min)-$($row.Max)."
        }
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Required command 'az' was not found in PATH."
}
if ($ArtifactRetentionDays -gt $RunRetentionDays) {
    throw 'ArtifactRetentionDays cannot exceed RunRetentionDays because artifacts cannot outlive their run.'
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

$diagnosticPipelines = @(Invoke-AzCommand `
        -Arguments @('pipelines', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--name', $DiagnosticPipelineName, '--output', 'json', '--only-show-errors') `
        -Operation "Diagnostic pipeline '$DiagnosticPipelineName' lookup" `
        -ParseJson | Where-Object { $_.name -eq $DiagnosticPipelineName })
if ($diagnosticPipelines.Count -ne 1) {
    throw "Expected exactly one pipeline '$DiagnosticPipelineName'; found $($diagnosticPipelines.Count). Complete step 03 first."
}
$diagnosticRuns = @(Invoke-AzCommand `
        -Arguments @('pipelines', 'runs', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--pipeline-ids', [string]$diagnosticPipelines[0].id, '--top', '20', '--output', 'json', '--only-show-errors') `
        -Operation "Diagnostic pipeline '$DiagnosticPipelineName' run lookup" `
        -ParseJson)
$successfulMainRuns = @($diagnosticRuns | Where-Object {
        $_.status -eq 'completed' -and
        $_.result -eq 'succeeded' -and
        $_.sourceBranch -eq 'refs/heads/main'
    })
if ($successfulMainRuns.Count -eq 0) {
    throw "Pipeline '$DiagnosticPipelineName' has no successful run on refs/heads/main. Complete the step 03 gate first."
}
$latestSuccessfulRun = $successfulMainRuns | Sort-Object finishTime -Descending | Select-Object -First 1
Write-Host "[VERIFIED] Diagnostic gate: run $($latestSuccessfulRun.id) succeeded on refs/heads/main."

$currentSettings = Invoke-RetentionApi -Method GET -ProjectId $ProjectId
$rows = @(Get-RetentionRows -Settings $currentSettings)
Assert-DesiredValuesWithinServerLimits -Rows $rows

Write-Host 'Current and desired project retention:'
$rows | Select-Object Name, Current, Desired, Min, Max | Format-Table -AutoSize

$drift = @($rows | Where-Object { $_.Current -ne $_.Desired })
if ($drift.Count -eq 0) {
    Write-Host '[EXISTS] Project retention settings are already compliant.'
}
else {
    foreach ($item in $drift) {
        Write-Host "[PLAN] Update '$($item.Name)' from $($item.Current) to $($item.Desired)."
    }

    $body = [ordered]@{
        runRetention                 = @{ value = $RunRetentionDays }
        artifactsRetention           = @{ value = $ArtifactRetentionDays }
        pullRequestRunRetention      = @{ value = $PullRequestRunRetentionDays }
        retainRunsPerProtectedBranch = @{ value = $RecentRunsPerPipeline }
    }

    if ($PSCmdlet.ShouldProcess($ProjectName, 'Update project-level pipeline retention settings')) {
        [void](Invoke-RetentionApi -Method PATCH -ProjectId $ProjectId -Body $body)
        Write-Host '[UPDATED] Project-level pipeline retention settings.'
    }
}

if ($WhatIfPreference) {
    Write-Host '[VERIFIED] Preview completed. No Azure DevOps resource was changed.'
    return
}

$finalSettings = Invoke-RetentionApi -Method GET -ProjectId $ProjectId
$finalRows = @(Get-RetentionRows -Settings $finalSettings)
$remainingDrift = @($finalRows | Where-Object { $_.Current -ne $_.Desired })
if ($remainingDrift.Count -gt 0) {
    $details = ($remainingDrift | ForEach-Object {
            "$($_.Name): current=$($_.Current), desired=$($_.Desired)"
        }) -join '; '
    throw "Final retention verification failed. $details"
}

Write-Host '[VERIFIED] Runs and logs retention: 30 days.'
Write-Host '[VERIFIED] Artifact retention: 30 days.'
Write-Host '[VERIFIED] Pull Request run retention: 14 days.'
Write-Host '[VERIFIED] Recent runs retained per pipeline: 3.'
Write-Host '[VERIFIED] Project-level retention bootstrap completed.'

