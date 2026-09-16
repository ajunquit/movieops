#Requires -Version 7.0

<#
.SYNOPSIS
Creates or verifies the MovieOps Azure DevOps project.

.DESCRIPTION
Validates the Azure CLI session and access to the target Azure DevOps
organization, installs the azure-devops CLI extension when necessary, creates
the private Git/Basic project only when it does not exist, verifies the final
configuration, and sets Azure DevOps CLI defaults for subsequent bootstrap
scripts.

The script is idempotent: an already compliant project is never recreated.
It does not import code into Azure Repos, create pipelines, service
connections, identities, role assignments, or Azure resources.

.EXAMPLE
./scripts/azure-devops/00-bootstrap-project/bootstrap-project.ps1 -WhatIf

.EXAMPLE
./scripts/azure-devops/00-bootstrap-project/bootstrap-project.ps1
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
    [string]$Description = 'MovieOps multi-platform DevOps laboratory'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$OrganizationUrl = $OrganizationUrl.TrimEnd('/')
$requiredProcess = 'Basic'
$requiredSourceControl = 'Git'
$requiredVisibility = 'private'

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

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Required command 'az' was not found in PATH. Install Azure CLI before running this script."
}

Write-Host 'Checking Azure CLI session...'
$account = Invoke-AzCommand `
    -Arguments @('account', 'show', '--output', 'json', '--only-show-errors') `
    -Operation 'Azure CLI session check' `
    -ParseJson

Write-Host "[VERIFIED] Azure session: $($account.user.name)"
Write-Host "[VERIFIED] Tenant: $($account.tenantId)"
Write-Host "[VERIFIED] Subscription: $($account.name) ($($account.id))"

$extensions = @(Invoke-AzCommand `
        -Arguments @('extension', 'list', '--output', 'json', '--only-show-errors') `
        -Operation 'Azure CLI extension lookup' `
        -ParseJson)
$azureDevOpsExtension = @($extensions | Where-Object { $_.name -eq 'azure-devops' })

if ($azureDevOpsExtension.Count -eq 0) {
    if ($PSCmdlet.ShouldProcess('Azure CLI', "Install extension 'azure-devops'")) {
        $null = Invoke-AzCommand `
            -Arguments @('extension', 'add', '--name', 'azure-devops', '--only-show-errors') `
            -Operation "Installation of Azure CLI extension 'azure-devops'"
        Write-Host "[CREATED] Azure CLI extension 'azure-devops'."
    }
    else {
        Write-Host "[MANUAL ACTION REQUIRED] Install the extension and rerun the script: az extension add --name azure-devops"
        return
    }
}
elseif ($azureDevOpsExtension.Count -eq 1) {
    Write-Host "[EXISTS] Azure CLI extension 'azure-devops' version $($azureDevOpsExtension[0].version)."
}
else {
    throw "Expected at most one Azure CLI extension named 'azure-devops'; found $($azureDevOpsExtension.Count)."
}

Write-Host "Checking access to $OrganizationUrl..."
$projectResponse = Invoke-AzCommand `
    -Arguments @(
        'devops', 'project', 'list',
        '--organization', $OrganizationUrl,
        '--top', '1000',
        '--output', 'json',
        '--only-show-errors'
    ) `
    -Operation "Azure DevOps access check for '$OrganizationUrl'" `
    -ParseJson

$projects = @($projectResponse.value)
$matches = @($projects | Where-Object { $_.name -ieq $ProjectName })

if ($matches.Count -gt 1) {
    throw "More than one project matched '$ProjectName'. Refusing to select an ambiguous target."
}

if ($matches.Count -eq 0) {
    if ($PSCmdlet.ShouldProcess("$OrganizationUrl/$ProjectName", 'Create private Azure DevOps project')) {
        $createdProject = Invoke-AzCommand `
            -Arguments @(
                'devops', 'project', 'create',
                '--organization', $OrganizationUrl,
                '--name', $ProjectName,
                '--description', $Description,
                '--process', $requiredProcess,
                '--source-control', 'git',
                '--visibility', $requiredVisibility,
                '--output', 'json',
                '--only-show-errors'
            ) `
            -Operation "Creation of Azure DevOps project '$ProjectName'" `
            -ParseJson
        Write-Host "[CREATED] Project '$($createdProject.name)' ($($createdProject.id))."
    }
    else {
        Write-Host "[PLAN] Project '$ProjectName' would be created in '$OrganizationUrl'."
        return
    }
}
else {
    Write-Host "[EXISTS] Project '$ProjectName' ($($matches[0].id))."
}

$project = Invoke-AzCommand `
    -Arguments @(
        'devops', 'project', 'show',
        '--organization', $OrganizationUrl,
        '--project', $ProjectName,
        '--output', 'json',
        '--only-show-errors'
    ) `
    -Operation "Verification of Azure DevOps project '$ProjectName'" `
    -ParseJson

$violations = @()
if ($project.state -ne 'wellFormed') {
    $violations += "state is '$($project.state)', expected 'wellFormed'"
}
if ($project.visibility -ne $requiredVisibility) {
    $violations += "visibility is '$($project.visibility)', expected '$requiredVisibility'"
}
if ($project.capabilities.versioncontrol.sourceControlType -ne $requiredSourceControl) {
    $violations += "source control is '$($project.capabilities.versioncontrol.sourceControlType)', expected '$requiredSourceControl'"
}
if ($project.capabilities.processTemplate.templateName -ne $requiredProcess) {
    $violations += "process is '$($project.capabilities.processTemplate.templateName)', expected '$requiredProcess'"
}

if ($violations.Count -gt 0) {
    throw "Project '$ProjectName' exists but is not compliant:`n- $($violations -join "`n- ")"
}

if ($PSCmdlet.ShouldProcess('Azure DevOps CLI defaults', "Set organization='$OrganizationUrl' and project='$ProjectName'")) {
    $null = Invoke-AzCommand `
        -Arguments @(
            'devops', 'configure',
            '--defaults',
            "organization=$OrganizationUrl",
            "project=$ProjectName"
        ) `
        -Operation 'Azure DevOps CLI default configuration'
    Write-Host '[UPDATED] Azure DevOps CLI defaults.'
}

Write-Host "`n[VERIFIED] Azure DevOps project bootstrap completed."
[pscustomobject]@{
    Organization  = $OrganizationUrl
    Project       = $project.name
    ProjectId     = $project.id
    State         = $project.state
    Visibility    = $project.visibility
    Process       = $project.capabilities.processTemplate.templateName
    SourceControl = $project.capabilities.versioncontrol.sourceControlType
} | Format-List

Write-Host 'Azure DevOps creates an empty default Git repository with the project; MovieOps will not use or populate it.'
Write-Host 'GitHub remains the only source repository. No pipelines, identities, RBAC roles, service connections, or Azure resources were created.'
