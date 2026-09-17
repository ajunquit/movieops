# Paso 05 — Auditoría read-only del bootstrap

## Estado

Completado y verificado el 16 de septiembre de 2026: `21` controles, `21` PASS,
`0` FAIL.

## Objetivo

Cerrar ADOP-1 con una auditoría repetible que pruebe que Azure DevOps puede
acceder a GitHub y Azure sin secretos persistentes, y que los boundaries
administrativos configurados en los pasos 00–04 permanecen correctos.

Este paso es exclusivamente de lectura. No admite ni necesita `-WhatIf`.

## Script

[`verify-bootstrap.ps1`](verify-bootstrap.ps1)

## Controles auditados

| Área | Control |
|---|---|
| Target | Sesión en tenant y suscripción esperados |
| Project | `MovieOps`, privado, Git, Basic, `wellFormed` |
| Azure connection | AzureRM, WIF, ready, no compartida |
| GitHub connection | GitHub App `InstallationToken`, ready, no compartida |
| Entra | App dedicada y Service Principal habilitado |
| Secretless | Cero passwords y certificados |
| Federación | Issuer, subject y audience coinciden con Azure DevOps |
| RBAC | Contributor + Role Based Access Control Administrator |
| Environments | `dev`, `staging`, `production` |
| Checks | Branch control `refs/heads/main` en los tres |
| Producción | Un aprobador y solicitante sin autoaprobación |
| Pipeline | Repositorio y YAML del diagnóstico correctos |
| Evidencia | Run verde del diagnóstico en `main` |
| Autorización | WIF autorizada para el pipeline, no globalmente |
| Retención | `30/30/14/3` |

El script acumula todos los controles. Un drift no impide comprobar los demás;
al final muestra una tabla y termina con error si existe al menos un `FAIL`.

## Qué no hace

- No crea, actualiza o elimina recursos.
- No ejecuta ni pone pipelines en cola.
- No aprueba deployments.
- No muestra tokens, passwords o contenido de secretos.
- No corrige drift automáticamente; identifica el paso propietario para que se
  reejecute de forma consciente.

## Prerrequisitos

- Pasos 00–04 completados.
- Sesión Azure CLI en la suscripción y tenant del laboratorio.
- Acceso de lectura a Entra ID, Azure RBAC y Azure DevOps `MovieOps`.
- PowerShell 7, Azure CLI y extensión `azure-devops`.

## Parámetros principales

Todos tienen defaults para este laboratorio:

| Parámetro | Default |
|---|---|
| `OrganizationUrl` | `https://dev.azure.com/ajunquit` |
| `ProjectName` | `MovieOps` |
| `SubscriptionId` | `b7fdb48a-4bf0-4c7b-9708-3d875a551936` |
| `TenantId` | `71747eda-0e30-46d9-a3dd-09adb3a83ff3` |
| `ApplicationDisplayName` | `azure-devops-movieops-wif` |
| `AzureServiceConnectionName` | `sc-movieops-azure-wif` |
| `GitHubRepository` | `ajunquit/movieops` |
| `DiagnosticPipelineName` | `MovieOps-Diagnostic` |
| `EnvironmentNames` | `dev`, `staging`, `production` |
| `ProductionApprover` | `ajunquit@hotmail.com` |
| `AllowedBranches` | `refs/heads/main` |

Los GUID usados son identificadores públicos, no secretos.

## Ejecución

Desde la raíz:

```powershell
./scripts/azure-devops/05-verify-bootstrap/verify-bootstrap.ps1
```

Desde esta carpeta:

```powershell
./verify-bootstrap.ps1
```

No usar `-WhatIf`: no existe ninguna mutación que simular.

## Salida esperada

```text
[PASS] Azure target boundary — ...
[PASS] Private Git/Basic Project — ...
[PASS] Azure WIF service connection — ...
[PASS] GitHub App service connection — ...
...
[PASS] Project retention policy — runs=30; artifacts=30; PR=14; recent=3

Controls: <n>; passed: <n>; failed: 0.
[VERIFIED] ADOP-1 bootstrap audit completed with zero failures.
[VERIFIED] This script performed read-only operations only.
```

## Interpretación de fallos

| Control | Paso que debe revisarse |
|---|---|
| Project | `00-bootstrap-project` |
| Entra/WIF/RBAC | `01-service-connection-wif` |
| Environment/check/approval | `02-configure-environments` |
| GitHub/pipeline/permisos/run | `03-configure-pipelines` |
| Retención | `04-configure-retention` |

No eliminar recursos para “empezar de cero”. Reejecutar primero el paso
idempotente propietario del control fallido.

## Resolución de problemas

### `--scope` y `--all` no son compatibles

Síntoma:

```text
Azure RBAC lookup failed with exit code 1.
ERROR: group or scope are not required when --all is used
```

La primera versión combinaba `az role assignment list --scope ... --all`.
Azure CLI considera ambas opciones mutuamente excluyentes: `--scope` consulta
un boundary concreto y `--all` enumera asignaciones bajo toda la suscripción.

La auditoría necesita los roles asignados exactamente en la suscripción, por lo
que la versión corregida conserva `--scope` y elimina `--all`. El filtro local
por igualdad de scope permanece como defensa adicional. El fallo fue de solo
lectura y no requiere rollback; basta con actualizar y reejecutar el script.

### El script termina antes del resumen

Una consulta base no pudo ejecutarse —por ejemplo, sesión expirada o permiso de
lectura ausente— y no sería fiable continuar. Renovar `az login`, confirmar el
target y repetir.

### Aparece `FAIL` pero el portal parece correcto

Leer la evidencia exacta de la fila. Verificar IDs y no solo nombres; refrescar
el portal y reejecutar el paso propietario. El script compara el estado devuelto
por las APIs, no capturas o caché visual.

### El diagnóstico fue verde, pero ahora falla su control

La auditoría busca un run exitoso de `main` entre las ejecuciones recientes. Si
la evidencia expiró por retención, ejecutar nuevamente `MovieOps-Diagnostic`.

## Evidencia que debes conservar

- Salida completa con todos los controles.
- ID y commit del run diagnóstico verde.
- Fecha de auditoría.

No es necesario guardar respuestas crudas que pudieran contener metadata
innecesaria de identidades.

## Siguiente paso

ADOP-1 quedó formalmente completado y ADOP-2 cerró con `12/12 PASS`. El trabajo
activo es ADOP-3, comenzando por estabilizar identidades Terraform en el paso
08 antes de crear Genesis.
