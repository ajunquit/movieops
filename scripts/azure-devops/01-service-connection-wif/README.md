# Paso 01 — Service connection Azure con WIF

## Estado

Completado y verificado el 16 de septiembre de 2026.

Evidencia registrada:

- Application ID: `8a598c74-ecf7-4d28-be14-5383e7f172d7`.
- Service Principal Object ID: `4fbfb3ed-ea64-4c58-85b2-eec87d5f21fb`.
- Service Connection ID: `245e217a-03ec-4db4-8dad-528a89d5f16c`.
- Esquema: `WorkloadIdentityFederation`; estado `Ready`.
- Una federated credential y cero credenciales de larga duración.
- Roles `Contributor` y `Role Based Access Control Administrator` en la
  suscripción del laboratorio.

## Objetivo

Crear una identidad exclusiva para Azure Pipelines y conectarla con la
suscripción Azure mediante Workload Identity Federation, sin client secrets.

```text
Azure DevOps: sc-movieops-azure-wif
        │ issuer + subject
        ▼
Entra App: azure-devops-movieops-wif
        │ federated credential
        ▼
Service Principal
        │ Contributor + RBAC Administrator
        ▼
Subscription b7fdb48a-4bf0-4c7b-9708-3d875a551936
```

## Script

[`configure-service-connection.ps1`](configure-service-connection.ps1)

## Qué hace

1. Verifica sesión, tenant y suscripción antes de mutar.
2. Verifica que el paso 00 haya creado `MovieOps`.
3. Crea o reutiliza exactamente una App Registration
   `azure-devops-movieops-wif`.
4. Confirma que la App Registration no tenga passwords ni certificados.
5. Crea o reutiliza su Service Principal.
6. Crea la Azure Resource Manager service connection
   `sc-movieops-azure-wif` usando `creationMode: Manual` y esquema
   `WorkloadIdentityFederation`.
7. Lee de Azure DevOps el issuer y subject generados para esa conexión.
8. Crea o sincroniza la federated credential en Entra ID.
9. Asigna al Service Principal sobre la suscripción:
   - `Contributor`.
   - `Role Based Access Control Administrator`.
10. Verifica federación, RBAC y ausencia de credenciales de larga duración.

El orden es obligatorio: Azure DevOps genera issuer y subject después de crear
la service connection, y esos valores crean la relación inversa en Entra ID.

## Qué no hace

- No crea client secrets, passwords ni certificados.
- No concede `Owner` ni `User Access Administrator`.
- No autoriza la conexión para todos los pipelines.
- No crea todavía pipelines o Environments.
- No ejecuta Terraform, Genesis ni Apocalipsis.
- No crea infraestructura Azure.
- No modifica la identidad GitHub `github-movieops-terraform`.

## Prerrequisitos

- Paso 00 completado y `MovieOps` en estado `wellFormed`.
- PowerShell 7 o superior.
- Azure CLI y extensión `azure-devops`.
- Sesión en el tenant y suscripción del laboratorio.
- Permiso para crear App Registrations/Service Principals en Entra ID.
- Permiso para crear service connections en el Project.
- `Owner` o una combinación que permita crear role assignments en la
  suscripción.

Comprobaciones:

```powershell
az account show --output table
az devops project show `
    --organization 'https://dev.azure.com/ajunquit' `
    --project 'MovieOps' `
    --output table
```

## Parámetros

| Parámetro | Default | Propósito |
|---|---|---|
| `OrganizationUrl` | `https://dev.azure.com/ajunquit` | Organización target |
| `ProjectName` | `MovieOps` | Project del endpoint |
| `ApplicationDisplayName` | `azure-devops-movieops-wif` | App Registration/identidad exclusiva |
| `ServiceConnectionName` | `sc-movieops-azure-wif` | Nombre usado por los YAML |
| `SubscriptionId` | `b7fdb48a-4bf0-4c7b-9708-3d875a551936` | Scope Azure autorizado |
| `TenantId` | `71747eda-0e30-46d9-a3dd-09adb3a83ff3` | Tenant esperado |
| `Roles` | `Contributor`, `Role Based Access Control Administrator` | Roles mínimos para Terraform actual |
| `WhatIf` | Desactivado | Muestra la siguiente mutación posible y el plan restante |
| `Confirm` | Según PowerShell | Solicita confirmación de cada mutación |

Los GUID son identificadores públicos, no secretos.

## Ejecución

### 1. Vista previa

```powershell
./scripts/azure-devops/01-service-connection-wif/configure-service-connection.ps1 -WhatIf
```

La primera vista previa se detendrá después de planificar la App Registration,
porque issuer y subject todavía no existen. También mostrará el resto del plan.

### 2. Aplicación

Este paso crea identidad y permisos reales:

```powershell
./scripts/azure-devops/01-service-connection-wif/configure-service-connection.ps1
```

### 3. Reejecución idempotente

```powershell
./scripts/azure-devops/01-service-connection-wif/configure-service-connection.ps1
```

La segunda ejecución debe informar `EXISTS` para App Registration, Service
Principal, service connection, federated credential y ambos roles.

## Salida esperada

```text
[VERIFIED] Azure session: ajunquit@hotmail.com
[VERIFIED] Azure DevOps project: MovieOps (...)
[CREATED] App Registration 'azure-devops-movieops-wif' (...)
[CREATED] Service principal (...)
[CREATED] Service connection 'sc-movieops-azure-wif' (...)
[VERIFIED] WIF issuer: https://login.microsoftonline.com/...
[VERIFIED] WIF subject: ...
[CREATED] Federated credential 'azure-devops-movieops-service-connection'.
[CREATED] Role 'Contributor' ...
[CREATED] Role 'Role Based Access Control Administrator' ...
[VERIFIED] Azure DevOps WIF service connection bootstrap completed.
```

El resumen final incluye Application ID, Principal Object ID y Service
Connection ID. Ninguno es secreto.

## Idempotencia y drift

- Los objetos se buscan antes de crearse.
- Más de una App Registration o service connection con el mismo nombre detiene
  el script.
- Una service connection existente con otro tenant, subscription, identidad o
  esquema se rechaza; no se reemplaza silenciosamente.
- La federated credential sí converge al issuer/subject actual de la conexión.
- Los roles existentes no se duplican.
- Una App Registration con password/certificado se rechaza.

Si el script falla después de crear algún objeto, se vuelve a ejecutar. Cada
fase detecta el estado parcial y continúa desde el siguiente elemento faltante.

## Blast radius

`Contributor` permite administrar recursos en toda la suscripción, pero no
asignar roles. `Role Based Access Control Administrator` permite administrar
role assignments sin conceder las facultades más amplias de `Owner`. Es el
mismo boundary que Terraform necesita para crear `AcrPull` y permisos de Key
Vault y para eliminarlos durante Apocalipsis.

La reducción de scope se evaluará después de validar la paridad, cuando se sepa
qué recursos deben existir antes de Genesis.

## Verificación en portal

Después del script:

1. Azure DevOps → `MovieOps` → **Project settings** → **Service connections**.
2. Abrir `sc-movieops-azure-wif`.
3. Confirmar **Workload identity federation**.
4. Confirmar que **Grant access permission to all pipelines** no esté activo.
5. Azure Portal → Microsoft Entra ID → App registrations →
   `azure-devops-movieops-wif`.
6. Confirmar una federated credential y cero client secrets.

## Resolución de problemas

### No se puede crear la App Registration

La cuenta necesita que el tenant permita registros de aplicaciones o el rol
`Application Developer`.

### No se puede crear un role assignment

La cuenta necesita `Owner`, `User Access Administrator` o
`Role Based Access Control Administrator` en la suscripción.

### Issuer o subject vacíos

No crear manualmente valores aproximados. Eliminar/corregir la service
connection incompleta y volver a ejecutar; ambos valores deben proceder de
Azure DevOps.

### Existe un objeto incompatible

El script falla de manera deliberada. No renombra ni reemplaza identidades de
forma automática. Revisar el objeto indicado antes de decidir si debe migrarse
o eliminarse.

## Evidencia que debes devolver

Comparte la salida completa desde `[VERIFIED] Azure session` hasta el resumen
final. El script no imprime tokens ni secretos.

## Referencias

- [Automate Azure Resource Manager WIF service connections](https://learn.microsoft.com/en-us/azure/devops/pipelines/release/automate-service-connections?view=azure-devops)
- [Configure workload identity federation](https://learn.microsoft.com/en-us/azure/devops/pipelines/release/configure-workload-identity?view=azure-devops)

## Siguiente paso

No continuar automáticamente. Primero se valida la identidad y luego se crea
`02-configure-environments`.
