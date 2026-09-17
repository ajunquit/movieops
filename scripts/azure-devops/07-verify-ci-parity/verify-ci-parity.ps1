#Requires -Version 7.0

<#
.SYNOPSIS
Performs the read-only ADOP-2 CI parity audit.

.DESCRIPTION
Verifies the latest successful main run, immutable artifact, Azure least
privilege, infrastructure independence, and healthy/broken PR outcomes in both
Azure Pipelines and GitHub Actions.

.EXAMPLE
./scripts/azure-devops/07-verify-ci-parity/verify-ci-parity.ps1
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidatePattern('^https://dev\.azure\.com/[A-Za-z0-9-]+/?$')]
    [string]$OrganizationUrl = 'https://dev.azure.com/ajunquit',

    [Parameter()]
    [string]$ProjectName = 'MovieOps',

    [Parameter()]
    [string]$PipelineName = 'MovieOps-CI',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$GitHubRepository = 'ajunquit/movieops',

    [Parameter()]
    [ValidateRange(1, 2147483647)]
    [int]$HealthyPullRequestNumber = 31,

    [Parameter()]
    [ValidateRange(1, 2147483647)]
    [int]$BrokenPullRequestNumber = 9,

    [Parameter()]
    [string]$AzureServiceConnectionName = 'sc-movieops-azure-wif',

    [Parameter()]
    [string]$DisposableResourceGroup = 'rg-movieops-dev',

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId = 'b7fdb48a-4bf0-4c7b-9708-3d875a551936'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OrganizationUrl = $OrganizationUrl.TrimEnd('/')
$Checks = [System.Collections.Generic.List[object]]::new()

function Invoke-NativeJson {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Operation
    )

    $output = @(& $Command @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed with exit code $LASTEXITCODE.`n$($output -join [Environment]::NewLine)"
    }
    $json = $output -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($json)) {
        throw "$Operation returned an empty response."
    }
    return $json | ConvertFrom-Json
}

function Add-Check {
    param(
        [Parameter(Mandatory)][string]$Control,
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Evidence
    )

    $Checks.Add([pscustomobject]@{
            Status   = if ($Passed) { 'PASS' } else { 'FAIL' }
            Control  = $Control
            Evidence = $Evidence
        })
}

function Add-Waiting {
    param(
        [Parameter(Mandatory)][string]$Control,
        [Parameter(Mandatory)][string]$Evidence
    )

    $Checks.Add([pscustomobject]@{
            Status   = 'WAITING'
            Control  = $Control
            Evidence = $Evidence
        })
}

function Get-RunArtifacts {
    param([Parameter(Mandatory)][int]$RunId)

    return @(Invoke-NativeJson `
            -Command 'az' `
            -Arguments @('pipelines', 'runs', 'artifact', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--run-id', [string]$RunId, '--output', 'json', '--only-show-errors') `
            -Operation "Artifact lookup for run $RunId")
}

function Test-RunMatchesPullRequest {
    param(
        [Parameter(Mandatory)][object]$Run,
        [Parameter(Mandatory)][int]$PullRequestNumber
    )

    if ($Run.sourceBranch -match "^refs/pull/$PullRequestNumber/") {
        return $true
    }
    $triggerInfoProperty = $Run.PSObject.Properties['triggerInfo']
    if ($null -eq $triggerInfoProperty -or $null -eq $triggerInfoProperty.Value) {
        return $false
    }
    foreach ($name in @('pr.number', 'prNumber', 'pullRequestId')) {
        $property = $triggerInfoProperty.Value.PSObject.Properties[$name]
        if ($null -ne $property -and [string]$property.Value -eq [string]$PullRequestNumber) {
            return $true
        }
    }
    return $false
}

function Test-PullRequestOutcome {
    param(
        [Parameter(Mandatory)][int]$Number,
        [Parameter(Mandatory)][ValidateSet('succeeded', 'failed')][string]$ExpectedResult,
        [Parameter(Mandatory)][object[]]$PipelineRuns
    )

    $pr = Invoke-NativeJson `
        -Command 'gh' `
        -Arguments @('pr', 'view', [string]$Number, '--repo', $GitHubRepository, '--json', 'number,state,baseRefName,headRefName,headRefOid,statusCheckRollup') `
        -Operation "GitHub PR #$Number lookup"

    $githubCiChecks = @($pr.statusCheckRollup | Where-Object { $_.workflowName -eq 'CI' })
    $githubFailures = @($githubCiChecks | Where-Object { $_.conclusion -eq 'FAILURE' })
    $githubPending = @($githubCiChecks | Where-Object { $_.status -ne 'COMPLETED' })
    if ($githubPending.Count -gt 0) {
        Add-Waiting `
            -Control "GitHub Actions PR #$Number is $ExpectedResult" `
            -Evidence "branch=$($pr.headRefName); pending=$($githubPending.Count)"
    }
    else {
        $githubPassed = if ($ExpectedResult -eq 'succeeded') {
            $githubCiChecks.Count -gt 0 -and $githubFailures.Count -eq 0
        }
        else {
            $githubFailures.Count -gt 0
        }
        Add-Check `
            -Control "GitHub Actions PR #$Number is $ExpectedResult" `
            -Passed $githubPassed `
            -Evidence "branch=$($pr.headRefName); checks=$($githubCiChecks.Count); failures=$($githubFailures.Count)"
    }

    $matchingRuns = @($PipelineRuns | Where-Object {
            $_.reason -eq 'pullRequest' -and
            $_.status -eq 'completed' -and
            (Test-RunMatchesPullRequest -Run $_ -PullRequestNumber $Number)
        } | Sort-Object finishTime -Descending)
    if ($matchingRuns.Count -eq 0) {
        $activeRuns = @($PipelineRuns | Where-Object {
                $_.reason -eq 'pullRequest' -and
                $_.status -ne 'completed' -and
                (Test-RunMatchesPullRequest -Run $_ -PullRequestNumber $Number)
            } | Sort-Object queueTime -Descending)
        $evidence = if ($activeRuns.Count -gt 0) {
            "run=$($activeRuns[0].id); status=$($activeRuns[0].status)"
        }
        else {
            'No PR run found. Rebase or update the PR.'
        }
        Add-Waiting -Control "Azure Pipelines PR #$Number is $ExpectedResult" -Evidence $evidence
        return
    }

    $run = $matchingRuns[0]
    $azurePassed = $run.result -eq $ExpectedResult
    Add-Check `
        -Control "Azure Pipelines PR #$Number is $ExpectedResult" `
        -Passed $azurePassed `
        -Evidence "run=$($run.id); result=$($run.result); commit=$($run.sourceVersion)"

    $artifacts = @(Get-RunArtifacts -RunId $run.id)
    $imageArtifacts = @($artifacts | Where-Object { $_.name -eq 'movieops-images' })
    Add-Check `
        -Control "PR #$Number does not publish movieops-images" `
        -Passed ($imageArtifacts.Count -eq 0) `
        -Evidence "run=$($run.id); matches=$($imageArtifacts.Count)"
}

foreach ($command in @('az', 'gh')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command '$command' was not found in PATH."
    }
}

$project = Invoke-NativeJson `
    -Command 'az' `
    -Arguments @('devops', 'project', 'show', '--organization', $OrganizationUrl, '--project', $ProjectName, '--output', 'json', '--only-show-errors') `
    -Operation 'Azure DevOps project lookup'
$pipelines = @(Invoke-NativeJson `
        -Command 'az' `
        -Arguments @('pipelines', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--name', $PipelineName, '--output', 'json', '--only-show-errors') `
        -Operation 'CI pipeline lookup' | Where-Object { $_.name -eq $PipelineName })
if ($pipelines.Count -ne 1) {
    throw "Expected exactly one pipeline '$PipelineName'; found $($pipelines.Count)."
}
$pipeline = $pipelines[0]
Add-Check -Control 'MovieOps-CI registration' -Passed $true -Evidence "pipeline=$($pipeline.id)"

$runs = @(Invoke-NativeJson `
        -Command 'az' `
        -Arguments @('pipelines', 'runs', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--pipeline-ids', [string]$pipeline.id, '--top', '100', '--output', 'json', '--only-show-errors') `
        -Operation 'CI run history lookup')
$mainRuns = @($runs | Where-Object {
        $_.sourceBranch -eq 'refs/heads/main' -and
        $_.status -eq 'completed' -and
        $_.result -eq 'succeeded'
    } | Sort-Object finishTime -Descending)
if ($mainRuns.Count -eq 0) {
    Add-Check -Control 'Successful main run' -Passed $false -Evidence 'No succeeded run found.'
}
else {
    $mainRun = $mainRuns[0]
    Add-Check -Control 'Successful main run' -Passed $true -Evidence "run=$($mainRun.id); commit=$($mainRun.sourceVersion)"
    $mainArtifacts = @(Get-RunArtifacts -RunId $mainRun.id)
    Add-Check -Control 'Immutable image artifact' -Passed (@($mainArtifacts | Where-Object { $_.name -eq 'movieops-images' }).Count -eq 1) -Evidence "run=$($mainRun.id)"
    Add-Check -Control 'Published code coverage' -Passed (@($mainArtifacts | Where-Object { $_.name -like 'Code Coverage Report_*' }).Count -ge 1) -Evidence "run=$($mainRun.id)"
}

$resourceGroupExists = (& az group exists --name $DisposableResourceGroup --subscription $SubscriptionId --output tsv --only-show-errors).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'Azure Resource Group existence lookup failed.'
}
Add-Check -Control 'CI independent from dev infrastructure' -Passed ($resourceGroupExists -eq 'false') -Evidence "$DisposableResourceGroup exists=$resourceGroupExists"

$endpoints = @(Invoke-NativeJson `
        -Command 'az' `
        -Arguments @('devops', 'service-endpoint', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--output', 'json', '--only-show-errors') `
        -Operation 'Service connection lookup')
$azureEndpoints = @($endpoints | Where-Object { $_.name -eq $AzureServiceConnectionName })
if ($azureEndpoints.Count -ne 1) {
    throw "Expected one Azure connection '$AzureServiceConnectionName'."
}
$permissions = Invoke-NativeJson `
    -Command 'az' `
    -Arguments @('devops', 'invoke', '--organization', $OrganizationUrl, '--area', 'pipelinepermissions', '--resource', 'pipelinePermissions', '--route-parameters', "project=$($project.id)", 'resourceType=endpoint', "resourceId=$($azureEndpoints[0].id)", '--api-version', '7.1-preview', '--http-method', 'GET', '--output', 'json', '--only-show-errors') `
    -Operation 'CI least-privilege lookup'
$authorizedCi = @($permissions.pipelines | Where-Object { [int]$_.id -eq [int]$pipeline.id -and [bool]$_.authorized })
Add-Check -Control 'CI has no Azure WIF authorization' -Passed ($authorizedCi.Count -eq 0) -Evidence "matches=$($authorizedCi.Count)"

Test-PullRequestOutcome -Number $HealthyPullRequestNumber -ExpectedResult succeeded -PipelineRuns $runs
Test-PullRequestOutcome -Number $BrokenPullRequestNumber -ExpectedResult failed -PipelineRuns $runs

Write-Host ''
foreach ($check in $Checks) {
    $color = switch ($check.Status) {
        'PASS' { 'Green' }
        'WAITING' { 'Yellow' }
        default { 'Red' }
    }
    Write-Host "[$($check.Status)] $($check.Control) :: $($check.Evidence)" -ForegroundColor $color
}
$failures = @($Checks | Where-Object { $_.Status -eq 'FAIL' })
$waiting = @($Checks | Where-Object { $_.Status -eq 'WAITING' })
$passed = @($Checks | Where-Object { $_.Status -eq 'PASS' })
Write-Host "Controls: $($Checks.Count); PASS: $($passed.Count); WAITING: $($waiting.Count); FAIL: $($failures.Count)"
if ($failures.Count -gt 0) {
    throw "ADOP-2 audit failed $($failures.Count) control(s)."
}
if ($waiting.Count -gt 0) {
    Write-Host '[WAITING] ADOP-2 audit is not complete. Wait for the listed runs and execute this script again.' -ForegroundColor Yellow
    return
}
Write-Host '[VERIFIED] ADOP-2 CI parity audit completed successfully.' -ForegroundColor Green
