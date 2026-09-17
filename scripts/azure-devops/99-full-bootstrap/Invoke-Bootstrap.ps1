#Requires -Version 7.0

<#
.SYNOPSIS
Orchestrates the complete MovieOps Azure DevOps bootstrap.

.DESCRIPTION
Runs the validated steps 00 through 05 in order. Every child script remains
the owner of its resource and idempotency rules. The orchestrator stops cleanly
at the GitHub App consent gate or when the diagnostic pipeline still needs its
first successful manual run. Rerunning resumes by safely revalidating previous
steps.

.EXAMPLE
./scripts/azure-devops/99-full-bootstrap/Invoke-Bootstrap.ps1 -WhatIf

.EXAMPLE
./scripts/azure-devops/99-full-bootstrap/Invoke-Bootstrap.ps1

.EXAMPLE
./scripts/azure-devops/99-full-bootstrap/Invoke-Bootstrap.ps1 -StopAfterStep 02
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
    [ValidateNotNullOrEmpty()]
    [string]$ProductionApprover = 'ajunquit@hotmail.com',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DiagnosticPipelineName = 'MovieOps-Diagnostic',

    [Parameter()]
    [ValidateSet('00', '01', '02', '03', '04', '05')]
    [string]$StopAfterStep
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$OrganizationUrl = $OrganizationUrl.TrimEnd('/')
$AzureDevOpsScriptsRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$StepResults = [System.Collections.Generic.List[object]]::new()

$StepScripts = [ordered]@{
    '00' = Join-Path $AzureDevOpsScriptsRoot '00-bootstrap-project/bootstrap-project.ps1'
    '01' = Join-Path $AzureDevOpsScriptsRoot '01-service-connection-wif/configure-service-connection.ps1'
    '02' = Join-Path $AzureDevOpsScriptsRoot '02-configure-environments/configure-environments.ps1'
    '03' = Join-Path $AzureDevOpsScriptsRoot '03-configure-pipelines/configure-pipelines.ps1'
    '04' = Join-Path $AzureDevOpsScriptsRoot '04-configure-retention/configure-retention.ps1'
    '05' = Join-Path $AzureDevOpsScriptsRoot '05-verify-bootstrap/verify-bootstrap.ps1'
}

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

function Add-StepResult {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('COMPLETED', 'PREVIEWED', 'WAITING', 'FAILED', 'STOPPED')][string]$Status,
        [Parameter(Mandatory)][string]$Details,
        [Parameter()][double]$Seconds = 0
    )

    $StepResults.Add([pscustomobject]@{
            Step    = $Step
            Name    = $Name
            Status  = $Status
            Seconds = [math]::Round($Seconds, 1)
            Details = $Details
        })
}

function Show-Summary {
    Write-Host ''
    Write-Host 'Full bootstrap summary:'
    $StepResults | Format-Table Step, Name, Status, Seconds, Details -Wrap -AutoSize
}

function Invoke-BootstrapStep {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][hashtable]$Parameters,
        [Parameter()][switch]$ReadOnly
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "Step $Step script was not found: $ScriptPath"
    }

    Write-Host ''
    Write-Host "========== STEP $Step — $Name ==========" -ForegroundColor Cyan
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        if ($ReadOnly) {
            & $ScriptPath @Parameters
        }
        else {
            $childParameters = @{} + $Parameters
            $childParameters.WhatIf = [bool]$WhatIfPreference
            $childParameters.Confirm = $false
            & $ScriptPath @childParameters
        }

        if (-not $?) {
            throw "Step $Step returned an unsuccessful status."
        }

        $stopwatch.Stop()
        $status = if ($WhatIfPreference -and -not $ReadOnly) { 'PREVIEWED' } else { 'COMPLETED' }
        Add-StepResult -Step $Step -Name $Name -Status $status -Details 'Child script completed.' -Seconds $stopwatch.Elapsed.TotalSeconds
    }
    catch {
        $stopwatch.Stop()
        Add-StepResult -Step $Step -Name $Name -Status 'FAILED' -Details $_.Exception.Message -Seconds $stopwatch.Elapsed.TotalSeconds
        Show-Summary
        throw
    }
}

function Test-StopRequested {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][string]$NextAction
    )

    if ($StopAfterStep -eq $Step) {
        Add-StepResult -Step '--' -Name 'Operator stop' -Status 'STOPPED' -Details $NextAction
        Show-Summary
        return $true
    }
    return $false
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Required command 'az' was not found in PATH."
}

Write-Host 'MovieOps Azure DevOps full bootstrap'
Write-Host "Organization: $OrganizationUrl"
Write-Host "Project:      $ProjectName"
Write-Host "Repository:   $GitHubRepository"
Write-Host "Mode:         $(if ($WhatIfPreference) { 'PREVIEW' } else { 'APPLY/VERIFY' })"

Invoke-BootstrapStep `
    -Step '00' `
    -Name 'Project bootstrap' `
    -ScriptPath $StepScripts['00'] `
    -Parameters @{
        OrganizationUrl = $OrganizationUrl
        ProjectName     = $ProjectName
    }
if (Test-StopRequested -Step '00' -NextAction 'Rerun without -StopAfterStep to continue with WIF.') { return }

Invoke-BootstrapStep `
    -Step '01' `
    -Name 'Azure WIF service connection' `
    -ScriptPath $StepScripts['01'] `
    -Parameters @{
        OrganizationUrl            = $OrganizationUrl
        ProjectName                = $ProjectName
        ApplicationDisplayName     = $ApplicationDisplayName
        ServiceConnectionName      = $AzureServiceConnectionName
        SubscriptionId             = $SubscriptionId
        TenantId                   = $TenantId
    }
if (Test-StopRequested -Step '01' -NextAction 'Rerun without -StopAfterStep to continue with Environments.') { return }

Invoke-BootstrapStep `
    -Step '02' `
    -Name 'Environments and checks' `
    -ScriptPath $StepScripts['02'] `
    -Parameters @{
        OrganizationUrl       = $OrganizationUrl
        ProjectName           = $ProjectName
        ServiceConnectionName = $AzureServiceConnectionName
        ProductionApprover    = $ProductionApprover
    }
if (Test-StopRequested -Step '02' -NextAction 'Complete the GitHub App gate or rerun to continue with pipelines.') { return }

$endpoints = @(Invoke-AzCommand `
        -Arguments @('devops', 'service-endpoint', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--output', 'json', '--only-show-errors') `
        -Operation 'GitHub App gate lookup' `
        -ParseJson)
$githubAppEndpoints = @($endpoints | Where-Object {
        $_.type -eq 'GitHub' -and
        $_.authorization.scheme -eq 'InstallationToken' -and
        [bool]$_.isReady
    })

if ($githubAppEndpoints.Count -eq 0) {
    Add-StepResult `
        -Step 'GATE' `
        -Name 'GitHub App consent' `
        -Status 'WAITING' `
        -Details "Install Azure Pipelines GitHub App for '$GitHubRepository', then rerun."
    Show-Summary
    Write-Host '[MANUAL ACTION REQUIRED] Install Azure Pipelines GitHub App only for the MovieOps repository.' -ForegroundColor Yellow
    Write-Host '[MANUAL ACTION REQUIRED] Associate it with this Azure DevOps organization/project and rerun the same command.' -ForegroundColor Yellow
    return
}
if ($githubAppEndpoints.Count -gt 1) {
    $connections = ($githubAppEndpoints | ForEach-Object { "$($_.name)=$($_.id)" }) -join ', '
    Add-StepResult -Step 'GATE' -Name 'GitHub App consent' -Status 'FAILED' -Details "Ambiguous connections: $connections"
    Show-Summary
    throw 'Multiple ready GitHub App connections exist. Run step 03 directly with -GitHubServiceConnectionId.'
}
Add-StepResult `
    -Step 'GATE' `
    -Name 'GitHub App consent' `
    -Status 'COMPLETED' `
    -Details "$($githubAppEndpoints[0].name) ($($githubAppEndpoints[0].id))"

Invoke-BootstrapStep `
    -Step '03' `
    -Name 'Diagnostic pipeline' `
    -ScriptPath $StepScripts['03'] `
    -Parameters @{
        OrganizationUrl              = $OrganizationUrl
        ProjectName                  = $ProjectName
        GitHubRepository             = $GitHubRepository
        PipelineName                 = $DiagnosticPipelineName
        AzureServiceConnectionName   = $AzureServiceConnectionName
        GitHubServiceConnectionId    = $githubAppEndpoints[0].id
    }
if (Test-StopRequested -Step '03' -NextAction "Run '$DiagnosticPipelineName' manually on main, then rerun the bootstrap.") { return }

if ($WhatIfPreference) {
    $existingPipelines = @(Invoke-AzCommand `
            -Arguments @('pipelines', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--name', $DiagnosticPipelineName, '--output', 'json', '--only-show-errors') `
            -Operation 'Diagnostic pipeline preview lookup' `
            -ParseJson | Where-Object { $_.name -eq $DiagnosticPipelineName })
    if ($existingPipelines.Count -eq 0) {
        Add-StepResult `
            -Step 'GATE' `
            -Name 'Diagnostic run' `
            -Status 'WAITING' `
            -Details "Pipeline is planned. Apply step 03, run it manually, then rerun."
        Show-Summary
        return
    }
}

$diagnosticPipelines = @(Invoke-AzCommand `
        -Arguments @('pipelines', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--name', $DiagnosticPipelineName, '--output', 'json', '--only-show-errors') `
        -Operation 'Diagnostic pipeline gate lookup' `
        -ParseJson | Where-Object { $_.name -eq $DiagnosticPipelineName })
if ($diagnosticPipelines.Count -ne 1) {
    Add-StepResult -Step 'GATE' -Name 'Diagnostic run' -Status 'FAILED' -Details "Pipeline matches=$($diagnosticPipelines.Count)"
    Show-Summary
    throw "Expected exactly one pipeline '$DiagnosticPipelineName'."
}

$diagnosticRuns = @(Invoke-AzCommand `
        -Arguments @('pipelines', 'runs', 'list', '--organization', $OrganizationUrl, '--project', $ProjectName, '--pipeline-ids', [string]$diagnosticPipelines[0].id, '--top', '20', '--output', 'json', '--only-show-errors') `
        -Operation 'Diagnostic run gate lookup' `
        -ParseJson)
$successfulDiagnosticRuns = @($diagnosticRuns | Where-Object {
        $_.status -eq 'completed' -and
        $_.result -eq 'succeeded' -and
        $_.sourceBranch -eq 'refs/heads/main'
    } | Sort-Object finishTime -Descending)

if ($successfulDiagnosticRuns.Count -eq 0) {
    Add-StepResult `
        -Step 'GATE' `
        -Name 'Diagnostic run' `
        -Status 'WAITING' `
        -Details "Run '$DiagnosticPipelineName' manually on main, then rerun."
    Show-Summary
    Write-Host "[MANUAL ACTION REQUIRED] Run '$DiagnosticPipelineName' on main and wait for success." -ForegroundColor Yellow
    return
}
Add-StepResult `
    -Step 'GATE' `
    -Name 'Diagnostic run' `
    -Status 'COMPLETED' `
    -Details "run=$($successfulDiagnosticRuns[0].id); commit=$($successfulDiagnosticRuns[0].sourceVersion)"

Invoke-BootstrapStep `
    -Step '04' `
    -Name 'Project retention' `
    -ScriptPath $StepScripts['04'] `
    -Parameters @{
        OrganizationUrl        = $OrganizationUrl
        ProjectName            = $ProjectName
        DiagnosticPipelineName = $DiagnosticPipelineName
    }
if (Test-StopRequested -Step '04' -NextAction 'Rerun without -StopAfterStep to perform the final audit.') { return }

if ($WhatIfPreference) {
    Add-StepResult `
        -Step '05' `
        -Name 'Final read-only audit' `
        -Status 'STOPPED' `
        -Details 'Skipped during preview because earlier desired changes are not applied.'
    Show-Summary
    Write-Host '[VERIFIED] Full bootstrap preview completed without applying changes.'
    return
}

Invoke-BootstrapStep `
    -Step '05' `
    -Name 'Final read-only audit' `
    -ScriptPath $StepScripts['05'] `
    -ReadOnly `
    -Parameters @{
        OrganizationUrl              = $OrganizationUrl
        ProjectName                  = $ProjectName
        GitHubRepository             = $GitHubRepository
        SubscriptionId               = $SubscriptionId
        TenantId                     = $TenantId
        ApplicationDisplayName       = $ApplicationDisplayName
        AzureServiceConnectionName   = $AzureServiceConnectionName
        DiagnosticPipelineName       = $DiagnosticPipelineName
        ProductionApprover           = $ProductionApprover
    }

Show-Summary
Write-Host '[VERIFIED] Full Azure DevOps bootstrap completed successfully.' -ForegroundColor Green
Write-Host '[VERIFIED] ADOP-1 is complete; ADOP-2 (CI parity) may begin.' -ForegroundColor Green

