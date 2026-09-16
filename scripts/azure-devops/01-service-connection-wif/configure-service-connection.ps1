#Requires -Version 7.0

<#
.SYNOPSIS
Creates or verifies the Azure DevOps Workload Identity Federation connection.

.DESCRIPTION
Creates a secretless Microsoft Entra application/service principal, an Azure
Resource Manager service connection in Azure DevOps, the bidirectional
federated credential, and the subscription RBAC roles required by Terraform.

The script is idempotent and fails closed when an existing object with the
expected name has an incompatible identity or configuration.

.EXAMPLE
./scripts/azure-devops/01-service-connection-wif/configure-service-connection.ps1 -WhatIf

.EXAMPLE
./scripts/azure-devops/01-service-connection-wif/configure-service-connection.ps1
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
    [string]$ApplicationDisplayName = 'azure-devops-movieops-wif',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceConnectionName = 'sc-movieops-azure-wif',

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId = 'b7fdb48a-4bf0-4c7b-9708-3d875a551936',

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$TenantId = '71747eda-0e30-46d9-a3dd-09adb3a83ff3',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$Roles = @(
        'Contributor',
        'Role Based Access Control Administrator'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$OrganizationUrl = $OrganizationUrl.TrimEnd('/')
$subscriptionScope = "/subscriptions/$SubscriptionId"
$federatedCredentialName = 'azure-devops-movieops-service-connection'
$federatedAudience = 'api://AzureADTokenExchange'
$skippedChange = $false

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

function Write-RemainingPlan {
    Write-Host "[PLAN] Ensure service principal for '$ApplicationDisplayName'."
    Write-Host "[PLAN] Ensure WIF service connection '$ServiceConnectionName'."
    Write-Host "[PLAN] Ensure federated credential '$federatedCredentialName'."
    foreach ($role in $Roles) {
        Write-Host "[PLAN] Ensure role '$role' on '$subscriptionScope'."
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Required command 'az' was not found in PATH. Install Azure CLI before running this script."
}

Write-Host 'Checking Azure CLI session and target boundary...'
$account = Invoke-AzCommand `
    -Arguments @('account', 'show', '--output', 'json', '--only-show-errors') `
    -Operation 'Azure CLI session check' `
    -ParseJson

if ($account.tenantId -ne $TenantId) {
    throw "Current tenant is '$($account.tenantId)', expected '$TenantId'. Use: az login --tenant $TenantId"
}
if ($account.id -ne $SubscriptionId) {
    throw "Current subscription is '$($account.id)', expected '$SubscriptionId'. Use: az account set --subscription $SubscriptionId"
}

Write-Host "[VERIFIED] Azure session: $($account.user.name)"
Write-Host "[VERIFIED] Tenant: $TenantId"
Write-Host "[VERIFIED] Subscription: $($account.name) ($SubscriptionId)"

$extensions = @(Invoke-AzCommand `
        -Arguments @('extension', 'list', '--output', 'json', '--only-show-errors') `
        -Operation 'Azure CLI extension lookup' `
        -ParseJson)
$azureDevOpsExtension = @($extensions | Where-Object { $_.name -eq 'azure-devops' })
if ($azureDevOpsExtension.Count -ne 1) {
    throw "Azure CLI extension 'azure-devops' is required. Complete step 00 or run: az extension add --name azure-devops"
}
Write-Host "[VERIFIED] Azure CLI extension 'azure-devops' version $($azureDevOpsExtension[0].version)."

$project = Invoke-AzCommand `
    -Arguments @(
        'devops', 'project', 'show',
        '--organization', $OrganizationUrl,
        '--project', $ProjectName,
        '--output', 'json',
        '--only-show-errors'
    ) `
    -Operation "Lookup of Azure DevOps project '$ProjectName'" `
    -ParseJson
if ($project.state -ne 'wellFormed') {
    throw "Project '$ProjectName' is '$($project.state)', expected 'wellFormed'."
}
Write-Host "[VERIFIED] Azure DevOps project: $($project.name) ($($project.id))."

$applications = @(Invoke-AzCommand `
        -Arguments @(
            'ad', 'app', 'list',
            '--display-name', $ApplicationDisplayName,
            '--output', 'json',
            '--only-show-errors'
        ) `
        -Operation "Lookup of App Registration '$ApplicationDisplayName'" `
        -ParseJson)

if ($applications.Count -gt 1) {
    throw "Expected at most one App Registration named '$ApplicationDisplayName'; found $($applications.Count)."
}

if ($applications.Count -eq 0) {
    if ($PSCmdlet.ShouldProcess($ApplicationDisplayName, 'Create secretless Microsoft Entra App Registration')) {
        $application = Invoke-AzCommand `
            -Arguments @(
                'ad', 'app', 'create',
                '--display-name', $ApplicationDisplayName,
                '--sign-in-audience', 'AzureADMyOrg',
                '--output', 'json',
                '--only-show-errors'
            ) `
            -Operation "Creation of App Registration '$ApplicationDisplayName'" `
            -ParseJson
        Write-Host "[CREATED] App Registration '$ApplicationDisplayName' ($($application.appId))."
    }
    else {
        Write-Host "[PLAN] App Registration '$ApplicationDisplayName' would be created without a password."
        Write-RemainingPlan
        return
    }
}
else {
    $application = $applications[0]
    Write-Host "[EXISTS] App Registration '$ApplicationDisplayName' ($($application.appId))."
}

$applicationCredentials = @(Invoke-AzCommand `
        -Arguments @(
            'ad', 'app', 'credential', 'list',
            '--id', $application.id,
            '--output', 'json',
            '--only-show-errors'
        ) `
        -Operation "Credential inspection for '$ApplicationDisplayName'" `
        -ParseJson)
if ($applicationCredentials.Count -gt 0) {
    throw "App Registration '$ApplicationDisplayName' has $($applicationCredentials.Count) password/certificate credential(s). This bootstrap requires a secretless identity."
}
Write-Host '[VERIFIED] App Registration has no password or certificate credentials.'

$servicePrincipals = @(Invoke-AzCommand `
        -Arguments @(
            'ad', 'sp', 'list',
            '--filter', "appId eq '$($application.appId)'",
            '--output', 'json',
            '--only-show-errors'
        ) `
        -Operation "Lookup of service principal for '$ApplicationDisplayName'" `
        -ParseJson)
if ($servicePrincipals.Count -gt 1) {
    throw "Expected at most one service principal for App ID '$($application.appId)'; found $($servicePrincipals.Count)."
}

if ($servicePrincipals.Count -eq 0) {
    if ($PSCmdlet.ShouldProcess($application.appId, 'Create Microsoft Entra service principal')) {
        $servicePrincipal = Invoke-AzCommand `
            -Arguments @(
                'ad', 'sp', 'create',
                '--id', $application.appId,
                '--output', 'json',
                '--only-show-errors'
            ) `
            -Operation "Creation of service principal for '$ApplicationDisplayName'" `
            -ParseJson
        Write-Host "[CREATED] Service principal ($($servicePrincipal.id))."
    }
    else {
        Write-Host "[PLAN] Service principal for '$ApplicationDisplayName' would be created."
        Write-RemainingPlan
        return
    }
}
else {
    $servicePrincipal = $servicePrincipals[0]
    Write-Host "[EXISTS] Service principal ($($servicePrincipal.id))."
}

$endpoints = @(Invoke-AzCommand `
        -Arguments @(
            'devops', 'service-endpoint', 'list',
            '--organization', $OrganizationUrl,
            '--project', $ProjectName,
            '--output', 'json',
            '--only-show-errors'
        ) `
        -Operation "Lookup of service connection '$ServiceConnectionName'" `
        -ParseJson)
$endpointMatches = @($endpoints | Where-Object { $_.name -ieq $ServiceConnectionName })
if ($endpointMatches.Count -gt 1) {
    throw "More than one service connection matched '$ServiceConnectionName'."
}

if ($endpointMatches.Count -eq 0) {
    if ($PSCmdlet.ShouldProcess($ServiceConnectionName, 'Create AzureRM Workload Identity Federation service connection')) {
        $endpointConfiguration = @{
            data = @{
                subscriptionId   = $SubscriptionId
                subscriptionName = $account.name
                environment      = 'AzureCloud'
                scopeLevel       = 'Subscription'
                creationMode     = 'Manual'
            }
            name          = $ServiceConnectionName
            type          = 'AzureRM'
            url           = 'https://management.azure.com/'
            authorization = @{
                parameters = @{
                    tenantid          = $TenantId
                    serviceprincipalid = $application.appId
                }
                scheme = 'WorkloadIdentityFederation'
            }
            isShared                         = $false
            isReady                          = $true
            serviceEndpointProjectReferences = @(
                @{
                    projectReference = @{
                        id   = $project.id
                        name = $project.name
                    }
                    name = $ServiceConnectionName
                }
            )
        }

        $configurationPath = Join-Path ([System.IO.Path]::GetTempPath()) "movieops-service-connection-$([guid]::NewGuid()).json"
        try {
            $endpointConfiguration | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $configurationPath -Encoding utf8NoBOM
            $endpoint = Invoke-AzCommand `
                -Arguments @(
                    'devops', 'service-endpoint', 'create',
                    '--service-endpoint-configuration', $configurationPath,
                    '--organization', $OrganizationUrl,
                    '--project', $ProjectName,
                    '--output', 'json',
                    '--only-show-errors'
                ) `
                -Operation "Creation of service connection '$ServiceConnectionName'" `
                -ParseJson
        }
        finally {
            if (Test-Path -LiteralPath $configurationPath) {
                Remove-Item -LiteralPath $configurationPath -Force
            }
        }
        Write-Host "[CREATED] Service connection '$ServiceConnectionName' ($($endpoint.id))."
    }
    else {
        Write-Host "[PLAN] Service connection '$ServiceConnectionName' would be created."
        Write-RemainingPlan
        return
    }
}
else {
    $endpoint = $endpointMatches[0]
    Write-Host "[EXISTS] Service connection '$ServiceConnectionName' ($($endpoint.id))."
}

$endpoint = Invoke-AzCommand `
    -Arguments @(
        'devops', 'service-endpoint', 'show',
        '--id', $endpoint.id,
        '--organization', $OrganizationUrl,
        '--project', $ProjectName,
        '--output', 'json',
        '--only-show-errors'
    ) `
    -Operation "Verification of service connection '$ServiceConnectionName'" `
    -ParseJson

$endpointViolations = @()
if ($endpoint.type -ine 'azurerm') {
    $endpointViolations += "type is '$($endpoint.type)', expected 'azurerm'"
}
if ($endpoint.authorization.scheme -ine 'WorkloadIdentityFederation') {
    $endpointViolations += "authorization scheme is '$($endpoint.authorization.scheme)', expected 'WorkloadIdentityFederation'"
}
if ($endpoint.authorization.parameters.serviceprincipalid -ne $application.appId) {
    $endpointViolations += 'service principal App ID does not match the expected App Registration'
}
if ($endpoint.authorization.parameters.tenantid -ne $TenantId) {
    $endpointViolations += "tenant ID does not match '$TenantId'"
}
if ($endpoint.data.subscriptionId -ne $SubscriptionId) {
    $endpointViolations += "subscription ID does not match '$SubscriptionId'"
}
if ($endpoint.isShared) {
    $endpointViolations += 'connection is shared outside the project'
}
if ($endpointViolations.Count -gt 0) {
    throw "Service connection '$ServiceConnectionName' is not compliant:`n- $($endpointViolations -join "`n- ")"
}

$issuer = [string]$endpoint.authorization.parameters.workloadIdentityFederationIssuer
$subject = [string]$endpoint.authorization.parameters.workloadIdentityFederationSubject
if ([string]::IsNullOrWhiteSpace($issuer) -or [string]::IsNullOrWhiteSpace($subject)) {
    throw "Service connection '$ServiceConnectionName' did not return its WIF issuer and subject."
}
if (-not $issuer.StartsWith("https://login.microsoftonline.com/$TenantId/", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unexpected WIF issuer '$issuer'. New connections must use the Microsoft Entra issuer for tenant '$TenantId'."
}
Write-Host "[VERIFIED] WIF issuer: $issuer"
Write-Host "[VERIFIED] WIF subject: $subject"

$federatedCredentials = @(Invoke-AzCommand `
        -Arguments @(
            'ad', 'app', 'federated-credential', 'list',
            '--id', $application.id,
            '--output', 'json',
            '--only-show-errors'
        ) `
        -Operation "Lookup of federated credential '$federatedCredentialName'" `
        -ParseJson)
$credentialMatches = @($federatedCredentials | Where-Object { $_.name -eq $federatedCredentialName })
if ($credentialMatches.Count -gt 1) {
    throw "More than one federated credential is named '$federatedCredentialName'."
}

$credentialParameters = @{
    name        = $federatedCredentialName
    issuer      = $issuer
    subject     = $subject
    description = "Azure DevOps $ProjectName / $ServiceConnectionName"
    audiences   = @($federatedAudience)
}

if ($credentialMatches.Count -eq 0) {
    if ($PSCmdlet.ShouldProcess($federatedCredentialName, 'Create federated identity credential')) {
        $credentialPath = Join-Path ([System.IO.Path]::GetTempPath()) "movieops-federated-credential-$([guid]::NewGuid()).json"
        try {
            $credentialParameters | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $credentialPath -Encoding utf8NoBOM
            $null = Invoke-AzCommand `
                -Arguments @(
                    'ad', 'app', 'federated-credential', 'create',
                    '--id', $application.id,
                    '--parameters', $credentialPath,
                    '--output', 'none',
                    '--only-show-errors'
                ) `
                -Operation "Creation of federated credential '$federatedCredentialName'"
        }
        finally {
            if (Test-Path -LiteralPath $credentialPath) {
                Remove-Item -LiteralPath $credentialPath -Force
            }
        }
        Write-Host "[CREATED] Federated credential '$federatedCredentialName'."
    }
    else {
        Write-Host "[PLAN] Federated credential '$federatedCredentialName' would be created."
        $skippedChange = $true
    }
}
else {
    $currentCredential = $credentialMatches[0]
    $isCurrent = $currentCredential.issuer -ceq $issuer -and
        $currentCredential.subject -ceq $subject -and
        @($currentCredential.audiences).Count -eq 1 -and
        @($currentCredential.audiences)[0] -ceq $federatedAudience

    if ($isCurrent) {
        Write-Host "[EXISTS] Federated credential '$federatedCredentialName'."
    }
    elseif ($PSCmdlet.ShouldProcess($federatedCredentialName, 'Update federated identity credential to match the service connection')) {
        $credentialPath = Join-Path ([System.IO.Path]::GetTempPath()) "movieops-federated-credential-$([guid]::NewGuid()).json"
        try {
            $credentialParameters.Remove('name')
            $credentialParameters | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $credentialPath -Encoding utf8NoBOM
            $null = Invoke-AzCommand `
                -Arguments @(
                    'ad', 'app', 'federated-credential', 'update',
                    '--id', $application.id,
                    '--federated-credential-id', $federatedCredentialName,
                    '--parameters', $credentialPath,
                    '--output', 'none',
                    '--only-show-errors'
                ) `
                -Operation "Update of federated credential '$federatedCredentialName'"
        }
        finally {
            if (Test-Path -LiteralPath $credentialPath) {
                Remove-Item -LiteralPath $credentialPath -Force
            }
        }
        Write-Host "[UPDATED] Federated credential '$federatedCredentialName'."
    }
    else {
        Write-Host "[PLAN] Federated credential '$federatedCredentialName' would be updated."
        $skippedChange = $true
    }
}

foreach ($role in $Roles) {
    $assignments = @(Invoke-AzCommand `
            -Arguments @(
                'role', 'assignment', 'list',
                '--assignee-object-id', $servicePrincipal.id,
                '--scope', $subscriptionScope,
                '--include-inherited',
                '--output', 'json',
                '--only-show-errors'
            ) `
            -Operation "Lookup of role '$role'" `
            -ParseJson)
    $roleMatches = @($assignments | Where-Object {
            $_.roleDefinitionName -eq $role -and $_.scope -eq $subscriptionScope
        })

    if ($roleMatches.Count -gt 0) {
        Write-Host "[EXISTS] Role '$role' on '$subscriptionScope'."
        continue
    }

    if ($PSCmdlet.ShouldProcess("$($servicePrincipal.id) at $subscriptionScope", "Assign role '$role'")) {
        $null = Invoke-AzCommand `
            -Arguments @(
                'role', 'assignment', 'create',
                '--assignee-object-id', $servicePrincipal.id,
                '--assignee-principal-type', 'ServicePrincipal',
                '--role', $role,
                '--scope', $subscriptionScope,
                '--output', 'none',
                '--only-show-errors'
            ) `
            -Operation "Assignment of role '$role'"
        Write-Host "[CREATED] Role '$role' on '$subscriptionScope'."
    }
    else {
        Write-Host "[PLAN] Role '$role' would be assigned on '$subscriptionScope'."
        $skippedChange = $true
    }
}

if ($skippedChange) {
    Write-Host 'Some planned changes were skipped; final state verification was not performed.'
    return
}

$verifiedCredentials = @(Invoke-AzCommand `
        -Arguments @(
            'ad', 'app', 'federated-credential', 'list',
            '--id', $application.id,
            '--output', 'json',
            '--only-show-errors'
        ) `
        -Operation 'Final federated credential verification' `
        -ParseJson)
$verifiedCredential = @($verifiedCredentials | Where-Object {
        $_.name -eq $federatedCredentialName -and
        $_.issuer -ceq $issuer -and
        $_.subject -ceq $subject -and
        @($_.audiences).Count -eq 1 -and
        @($_.audiences)[0] -ceq $federatedAudience
    })
if ($verifiedCredential.Count -ne 1) {
    throw "Final verification failed for federated credential '$federatedCredentialName'."
}

$verifiedAssignments = @(Invoke-AzCommand `
        -Arguments @(
            'role', 'assignment', 'list',
            '--assignee-object-id', $servicePrincipal.id,
            '--scope', $subscriptionScope,
            '--output', 'json',
            '--only-show-errors'
        ) `
        -Operation 'Final RBAC verification' `
        -ParseJson)
foreach ($role in $Roles) {
    if (@($verifiedAssignments | Where-Object {
                $_.roleDefinitionName -eq $role -and $_.scope -eq $subscriptionScope
            }).Count -lt 1) {
        throw "Final verification failed for role '$role'."
    }
}

Write-Host "`n[VERIFIED] Azure DevOps WIF service connection bootstrap completed."
[pscustomobject]@{
    Organization          = $OrganizationUrl
    Project               = $ProjectName
    Application           = $ApplicationDisplayName
    ApplicationId         = $application.appId
    PrincipalObjectId     = $servicePrincipal.id
    ServiceConnection     = $ServiceConnectionName
    ServiceConnectionId   = $endpoint.id
    Authentication        = $endpoint.authorization.scheme
    Scope                 = $subscriptionScope
    Roles                 = $Roles -join ', '
    LongLivedCredentials  = 0
    AuthorizedForAllPipes = $false
} | Format-List

Write-Host 'No pipeline was authorized and no Azure infrastructure resource was created.'
