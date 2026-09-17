# Paso 99 — Orquestador de los pasos 00, 01 y 03

## Estado

Nuevo, agregado el 16 de septiembre de 2026 a pedido explícito, para
mantener el mismo patrón que
[`azure-devops/99-full-bootstrap`](../../azure-devops/99-full-bootstrap/README.md).

## Objetivo

Ofrecer una única entrada para reproducir el bootstrap completo de este
track sin duplicar la lógica de los scripts propietarios:

```text
00 Terraform remote state
  → 01 Entra/OIDC/RBAC
  → 03 Auditoría read-only
```

## Script

[`Invoke-Bootstrap.ps1`](Invoke-Bootstrap.ps1)

## Diferencia con el orquestador de Azure DevOps

`azure-devops/99-full-bootstrap` existe sobre todo para resolver **gates
humanos** (instalar la GitHub App, esperar un run verde) entre pasos. Este
orquestador no tiene gates que resolver: `00` y `01` son mutaciones puras de
Azure CLI sin aprobación externa de por medio. Por eso es un wrapper más
simple — encadena tres scripts y consolida su resultado, sin lógica de
espera ni de reanudación entre gates.

## Principio de funcionamiento

El orquestador no reimplementa recursos. Invoca cada script propietario en
orden y le pasa los parámetros comunes. La idempotencia permanece en los
pasos `00` y `01`; el paso `03` conserva su naturaleza exclusivamente
read-only.

**No incluye el paso `02` (`keyvault-operator-access`)**: es una operación
por-ambiente, no una invariante de bootstrap único — no tiene sentido
encadenarla antes de que un ambiente concreto exista. Se ejecuta por
separado, ver su propio [README](../02-keyvault-operator-access/).

## Qué hace

- Centraliza los parámetros comunes (App Registration, repositorio,
  environments, roles, nombres del backend de Terraform).
- Propaga `-WhatIf` a los pasos `00` y `01`.
- Omite el paso `03` durante `-WhatIf`: no puede auditar como aplicado un
  desired state que solo fue simulado.
- Se detiene inmediatamente ante un fallo orgánico y conserva el detalle del
  paso que falló.
- Permite detenerse deliberadamente con `-StopAfterStep`.
- Presenta un resumen final por paso.

## Qué no hace

- No ejecuta el paso `02`.
- No aprueba ni gestiona ningún gate humano — no existe ninguno en este
  track.
- No guarda secretos ni checkpoints locales.
- No oculta fallos de los scripts hijos.

## Prerrequisitos

Los mismos que los pasos `00`, `01` y `03` combinados: PowerShell 7, Azure
CLI y GitHub CLI con sesión activa, y permiso para crear resource groups,
storage accounts, App Registrations, Service Principals y role assignments
en la suscripción.

## Parámetros

| Parámetro | Default | Propósito |
|---|---|---|
| `StopAfterStep` | Vacío | Detener después de `00` o `01` |
| `ApplicationDisplayName` | `github-movieops-terraform` | App Registration dedicada |
| `Repository` | `ajunquit/movieops` | Repositorio cuyo OIDC se confía |
| `Environments` | `dev`, `staging`, `production` | Federated credential por environment |
| `SubscriptionId` | Suscripción activa | Scope de los role assignments |
| `Roles` | `Contributor`, `Role Based Access Control Administrator` | Roles mínimos para Terraform |
| `TfStateResourceGroupName` | `rg-movieops-tfstate` | Resource group del backend |
| `TfStateLocation` | `eastus2` | Región del backend |
| `TfStateStorageAccountName` | `stmovieopstfstate` | Storage account del backend |
| `TfStateContainerName` | `tfstate` | Container del backend |
| `TfStateSku` | `Standard_LRS` | SKU de la storage account |

## Ejecución

### Vista previa completa

```powershell
./scripts/github-actions-azure/99-full-bootstrap/Invoke-Bootstrap.ps1 -WhatIf
```

El paso `03` se omite durante preview.

### Aplicación

```powershell
./scripts/github-actions-azure/99-full-bootstrap/Invoke-Bootstrap.ps1
```

### Ejecución controlada por fases

```powershell
./scripts/github-actions-azure/99-full-bootstrap/Invoke-Bootstrap.ps1 -StopAfterStep 00
```

Valores permitidos: `00`, `01`.

## Estados del resumen

| Estado | Significado |
|---|---|
| `COMPLETED` | Paso ejecutado/verificado |
| `PREVIEWED` | Paso simulado con `-WhatIf` |
| `STOPPED` | Detención solicitada, o auditoría omitida en preview |
| `FAILED` | Fallo orgánico; revisar el README del paso indicado |

## Recuperación

Nunca borrar recursos para "empezar de cero". Identificar el paso fallido en
el resumen, corregir la causa y volver a ejecutar el orquestador — cada
script hijo descubre el estado existente antes de crear y converge desde
ahí.

## Siguiente paso

Con `[VERIFIED] Full github-actions-azure bootstrap completed successfully`,
la identidad de CI está lista para `genesis.yml`/`apocalipsis.yml`. Ver
[`docs/deployment.md`](../../../docs/deployment.md) para el runbook completo.
