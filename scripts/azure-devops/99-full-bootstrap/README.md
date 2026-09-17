# Paso 99 — Orquestador completo y reanudable

## Estado

Implementado después de validar individualmente los pasos 00–05. Su recorrido
integral en `-WhatIf` fue validado el 16 de septiembre de 2026 sin errores ni
mutaciones.

## Objetivo

Ofrecer una única entrada para reproducir el bootstrap de ADOP-1 sin duplicar
la lógica de los scripts propietarios:

```text
00 Project
  → 01 Entra/WIF/RBAC
  → 02 Environments/checks
  → GATE GitHub App
  → 03 Pipeline diagnóstico
  → GATE run diagnóstico verde
  → 04 Retención
  → 05 Auditoría read-only
```

## Script

[`Invoke-Bootstrap.ps1`](Invoke-Bootstrap.ps1)

## Principio de funcionamiento

El orquestador no reimplementa recursos. Invoca cada script en orden y le pasa
los parámetros comunes. La idempotencia permanece en los pasos `00–04`; el
paso `05` conserva su naturaleza exclusivamente read-only.

Una reejecución empieza en `00` y vuelve a validar el estado previo. Esto es
intencional: “reanudar” significa converger y verificar, no saltar controles de
seguridad basándose en un archivo de checkpoint local potencialmente obsoleto.

## Gates humanos

### Gate 1 — GitHub App

Si no existe una conexión GitHub lista con esquema `InstallationToken`, el
orquestador termina correctamente después del paso 02 e informa:

```text
[MANUAL ACTION REQUIRED] Install Azure Pipelines GitHub App...
```

Instalarla exclusivamente para `ajunquit/movieops` y ejecutar nuevamente el
mismo comando. OAuth y PAT no satisfacen el gate.

### Gate 2 — Diagnóstico

El paso 03 registra el pipeline sin ejecutar automáticamente el primer run. Si
no existe un `succeeded` en `refs/heads/main`, el orquestador se detiene para que
el operador ejecute `MovieOps-Diagnostic`. Después se reanuda con el mismo
comando.

## Qué hace

- Centraliza organización, Project, repositorio, tenant y suscripción.
- Propaga `-WhatIf` a todos los pasos mutantes.
- Desactiva prompts duplicados en los hijos; el modo lo decide el orquestador.
- Permite detenerse deliberadamente con `-StopAfterStep`.
- Mide duración y presenta estado por paso.
- Se detiene inmediatamente ante un fallo orgánico y conserva su contexto.
- Ejecuta la auditoría final solamente después de aplicar y cruzar los gates.

## Qué no hace

- No automatiza consentimiento de GitHub App.
- No aprueba deployments.
- No ejecuta automáticamente el primer diagnóstico.
- No guarda tokens, passwords, PAT o checkpoints locales.
- No oculta fallos de scripts hijos.
- No cubre ADOP-2 o pipelines CI/CD; su boundary termina en ADOP-1.

## Prerrequisitos

- Organización Azure DevOps existente.
- PowerShell 7, Azure CLI y Git.
- Sesión Azure CLI en el tenant y suscripción target.
- Permisos descritos en los README de pasos `00–05`.
- Archivos del bootstrap publicados en `main` antes de registrar pipelines.

## Parámetros

| Parámetro | Default | Propósito |
|---|---|---|
| `OrganizationUrl` | `https://dev.azure.com/ajunquit` | Organización target |
| `ProjectName` | `MovieOps` | Project target |
| `GitHubRepository` | `ajunquit/movieops` | Repositorio autorizado |
| `SubscriptionId` | ID del laboratorio | Suscripción target |
| `TenantId` | ID del laboratorio | Tenant target |
| `ApplicationDisplayName` | `azure-devops-movieops-wif` | App Registration dedicada |
| `AzureServiceConnectionName` | `sc-movieops-azure-wif` | Conexión WIF |
| `ProductionApprover` | `ajunquit@hotmail.com` | Aprobador de production |
| `DiagnosticPipelineName` | `MovieOps-Diagnostic` | Pipeline del gate |
| `StopAfterStep` | Vacío | Detener después de `00`–`05` |
| `WhatIf` | Desactivado | Preview completo sin mutaciones |

## Ejecución

### Vista previa completa

```powershell
./scripts/azure-devops/99-full-bootstrap/Invoke-Bootstrap.ps1 -WhatIf
```

El paso 05 se omite durante preview porque no puede auditar como aplicado un
desired state que solo fue simulado.

### Aplicación o reanudación

```powershell
./scripts/azure-devops/99-full-bootstrap/Invoke-Bootstrap.ps1
```

Se usa exactamente el mismo comando después de cualquiera de los dos gates.

### Ejecución controlada por fases

```powershell
./scripts/azure-devops/99-full-bootstrap/Invoke-Bootstrap.ps1 `
  -StopAfterStep 02
```

Valores permitidos: `00`, `01`, `02`, `03`, `04`, `05`.

### Otros targets

```powershell
./scripts/azure-devops/99-full-bootstrap/Invoke-Bootstrap.ps1 `
  -OrganizationUrl 'https://dev.azure.com/<organization>' `
  -ProjectName 'MovieOps' `
  -GitHubRepository '<owner>/movieops' `
  -SubscriptionId '<subscription-id>' `
  -TenantId '<tenant-id>' `
  -ProductionApprover '<user-principal-name>'
```

## Estados del resumen

| Estado | Significado |
|---|---|
| `COMPLETED` | Paso ejecutado/verificado |
| `PREVIEWED` | Paso simulado con `-WhatIf` |
| `WAITING` | Gate humano pendiente; volver a ejecutar después |
| `STOPPED` | Detención solicitada o auditoría omitida en preview |
| `FAILED` | Fallo orgánico; revisar el README del paso indicado |

## Recuperación

Nunca borrar todo para recuperarse. Identificar la fila fallida, corregir la
causa y ejecutar nuevamente el orquestador. Los scripts descubren antes de crear
y convergen el estado parcial.

Para aislar un problema puede ejecutarse directamente el script propietario.
Después se vuelve al orquestador para obtener la auditoría integral.

## Evidencia esperada

El preview integral ya confirmó:

- Pasos 00–04 recorridos correctamente.
- GitHub App gate satisfecho.
- Run diagnóstico `59` verde en `main`.
- Retención conforme con `30/30/14/3`.
- Paso 05 omitido deliberadamente por tratarse de una simulación.

En el estado actual de MovieOps, la aplicación debe finalizar con:

```text
STEP 00 ... COMPLETED
STEP 01 ... COMPLETED
STEP 02 ... COMPLETED
GATE GitHub App ... COMPLETED
STEP 03 ... COMPLETED
GATE Diagnostic run ... COMPLETED
STEP 04 ... COMPLETED
STEP 05 ... COMPLETED
[VERIFIED] Full Azure DevOps bootstrap completed successfully.
[VERIFIED] ADOP-1 is complete; ADOP-2 (CI parity) may begin.
```

## Siguiente paso

Con el orquestador validado, comenzar ADOP-2: pipeline CI en Azure Pipelines con
backend/frontend paralelos, resultados de test, coverage, security scanning,
quality gate y artefacto inmutable para CD.
