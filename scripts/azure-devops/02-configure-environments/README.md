# Paso 02 — Environments y checks de despliegue

## Estado

Implementado y validado estáticamente. Pendiente de ejecución por el operador.

## Objetivo

Crear los límites administrativos donde posteriormente se registrarán los
deployments de MovieOps:

```text
dev ─────────┐
staging ─────┼── Branch control: refs/heads/main
production ──┘                  + aprobación humana
                                  + sin autoaprobación
```

Los Environments no crean infraestructura Azure ni namespaces de Kubernetes.
Son objetos de Azure DevOps que conservan historial y aplican checks antes de
que un deployment job pueda consumirlos.

## Script

[`configure-environments.ps1`](configure-environments.ps1)

## Qué hace

1. Verifica que `MovieOps` exista y esté en estado `wellFormed`.
2. Verifica el gate del paso 01: `sc-movieops-azure-wif` debe existir, estar
   lista y utilizar Workload Identity Federation.
3. Resuelve al aprobador por su usuario de Azure DevOps, sin guardar su GUID a
   mano.
4. Reutiliza de forma segura la sesión de la extensión Azure DevOps CLI para
   invocar las APIs públicas; no administra ni imprime el token subyacente.
5. Crea o reutiliza los Environments `dev`, `staging` y `production`.
6. Configura en cada uno **Branch control** con `refs/heads/main`.
7. Configura en `production` una aprobación mínima de una persona.
8. Impide que quien inició el deployment apruebe su propia ejecución.
9. Vuelve a consultar Environments y checks para verificar el resultado.

Los checks viven fuera del YAML. Un cambio en el repositorio no puede retirarlos
por sí solo.

## Qué no hace

- No aprueba ningún deployment.
- No registra pipelines ni conecta GitHub.
- No concede a la service connection acceso global a los pipelines.
- No crea AKS, ACR, redes, Resource Groups o namespaces.
- No agrega recursos Kubernetes a los Environments.
- No crea ni guarda PAT, client secret o password.
- No elimina checks desconocidos que ya existan.

## Prerrequisitos

- Pasos 00 y 01 completados.
- PowerShell 7 o superior.
- Azure CLI con extensión `azure-devops`.
- Sesión Azure CLI válida para la organización.
- El aprobador debe ser un usuario activo de Azure DevOps.
- Permiso para administrar Environments y sus checks en `MovieOps`.

Comprobaciones:

```powershell
az account show --output table

az devops service-endpoint show `
  --organization 'https://dev.azure.com/ajunquit' `
  --project 'MovieOps' `
  --id '245e217a-03ec-4db4-8dad-528a89d5f16c' `
  --output table

az devops user show `
  --organization 'https://dev.azure.com/ajunquit' `
  --user 'ajunquit@hotmail.com' `
  --output table
```

## Parámetros

| Parámetro | Default | Propósito |
|---|---|---|
| `OrganizationUrl` | `https://dev.azure.com/ajunquit` | Organización target |
| `ProjectName` | `MovieOps` | Project que contiene los Environments |
| `ServiceConnectionName` | `sc-movieops-azure-wif` | Gate de entrada del paso 01 |
| `Environments` | `dev`, `staging`, `production` | Ambientes que deben existir |
| `ProductionEnvironment` | `production` | Ambiente que requiere aprobación |
| `ProductionApprover` | `ajunquit@hotmail.com` | Usuario autorizado para aprobar |
| `AllowedBranches` | `refs/heads/main` | Ramas admitidas por Branch control |
| `VerifyBranchProtection` | Desactivado | Exige además que GitHub reporte protección de rama |
| `BranchCheckTimeoutMinutes` | `1440` | Timeout del check de rama |
| `ApprovalTimeoutMinutes` | `43200` | Timeout de la aprobación (30 días) |
| `ApprovalInstructions` | Mensaje predefinido | Instrucción visible para el aprobador |
| `WhatIf` | Desactivado | Muestra el plan sin modificar Azure DevOps |
| `Confirm` | Según PowerShell | Solicita confirmación de cada mutación |

Los nombres de rama deben estar completamente calificados como
`refs/heads/<nombre>`.

`VerifyBranchProtection` queda desactivado inicialmente: el objetivo de este
paso es limitar el origen a `main`; exigir protección se habilitará cuando el
check de Azure Pipelines ya pueda añadirse a la regla de GitHub sin crear una
dependencia circular durante el bootstrap.

## Ejecución

### 1. Vista previa obligatoria

```powershell
./scripts/azure-devops/02-configure-environments/configure-environments.ps1 -WhatIf
```

Debe planificar tres Environments, tres branch controls y una aprobación en
`production`, sin crear objetos.

### 2. Aplicación

```powershell
./scripts/azure-devops/02-configure-environments/configure-environments.ps1
```

### 3. Reejecución idempotente

```powershell
./scripts/azure-devops/02-configure-environments/configure-environments.ps1
```

La segunda ejecución debe informar `EXISTS` y terminar con verificaciones
verdes. No debe crear checks duplicados.

### Variantes opcionales

Otro aprobador:

```powershell
./scripts/azure-devops/02-configure-environments/configure-environments.ps1 `
  -ProductionApprover 'usuario@dominio.com'
```

Varias ramas permitidas:

```powershell
./scripts/azure-devops/02-configure-environments/configure-environments.ps1 `
  -AllowedBranches @('refs/heads/main', 'refs/heads/release')
```

Exigir protección conocida de la rama:

```powershell
./scripts/azure-devops/02-configure-environments/configure-environments.ps1 `
  -VerifyBranchProtection
```

## Salida esperada

Primera aplicación:

```text
[VERIFIED] Azure DevOps project: MovieOps (...).
[VERIFIED] WIF service connection: sc-movieops-azure-wif (...).
[VERIFIED] Production approver: ajunquit@hotmail.com (...).
[CREATED] Environment 'dev' (...).
[CREATED] Environment 'staging' (...).
[CREATED] Environment 'production' (...).
[CREATED] branch control on 'dev' (...).
[CREATED] branch control on 'staging' (...).
[CREATED] branch control on 'production' (...).
[CREATED] production approval on 'production' (...).
[VERIFIED] Azure DevOps Environment bootstrap completed.
```

## Idempotencia y drift

- Cada Environment se descubre antes de crearse.
- Los branch controls se reconocen por el tipo oficial y la definición
  `evaluatebranchProtection`.
- La aprobación se reconoce por el tipo oficial `Approval`.
- Un check administrado por este paso se actualiza si difieren rama, timeout,
  aprobador o política de autoaprobación.
- Un estado ambiguo —nombres duplicados o varios checks equivalentes— detiene
  el script para evitar modificar el objeto incorrecto.
- Checks de otro tipo no se eliminan ni modifican.

## Blast radius

Este paso solo muta objetos administrativos del Project `MovieOps`. Los checks
pueden bloquear futuros deployment jobs, pero no ejecutan pipelines ni cambian
recursos Azure. La aprobación de `production` sigue siendo una decisión humana.

## Verificación en el portal

1. Azure DevOps → `MovieOps` → **Pipelines → Environments**.
2. Confirmar `dev`, `staging` y `production`.
3. Abrir cada Environment → menú de tres puntos → **Approvals and checks**.
4. Confirmar **Branch control** con `refs/heads/main`.
5. En `production`, confirmar además **Approvals**.
6. Abrir la aprobación y verificar:
   - `ajunquit@hotmail.com` como aprobador;
   - un aprobador requerido;
   - desactivado permitir que el solicitante apruebe.

## Resolución de problemas

### `No se encuentra la propiedad "Count" en este objeto`

Este error aparecía en la primera versión del paso 02 cuando una llamada no
necesitaba query parameters. Con `Set-StrictMode`, el parámetro opcional era
`$null` y no admitía `.Count`. La versión actual lo inicializa como un arreglo
vacío. Actualizar el script y repetir primero con `-WhatIf`; la ejecución
fallida no creó ni modificó Environments.

### `ExistingChecks` no acepta una matriz vacía

Síntoma:

```text
No se puede enlazar el argumento al parámetro "ExistingChecks" porque es una matriz vacía.
```

La primera versión declaraba `ExistingChecks` como obligatorio, pero no
autorizaba explícitamente una colección vacía. Ese estado es válido en la
primera ejecución: los Environments ya fueron creados y todavía no tienen
checks. PowerShell detenía la llamada antes de que la función pudiera crear el
primer Branch control.

La versión actual utiliza `AllowEmptyCollection`. No hay que eliminar los
Environments creados ni comenzar de nuevo: se vuelve a ejecutar el mismo
script. Por idempotencia mostrará `EXISTS` para `dev`, `staging` y `production`
y continuará creando los tres Branch controls y la aprobación de
`production`.

El fallo parcial no deja infraestructura Azure ni deployments incompletos;
solo deja los tres objetos Environment sin checks hasta la reejecución.

### El aprobador no existe

Agregar primero al usuario en **Organization settings → Users** y volver a
ejecutar. El script exige un usuario activo y no intenta invitar personas.

### HTTP 401 o 403 al crear checks

La sesión puede leer la organización pero no administrar checks. Verificar que
la cuenta tenga permisos de administrador de Environments en `MovieOps`, cerrar
y renovar `az login`, y volver a ejecutar.

### La rama aparece como no protegida o desconocida

Sin `-VerifyBranchProtection`, el check valida solamente que el ref permitido
sea `refs/heads/main`. Habilitar esa opción después de configurar la protección
de `main` y el required check de Azure Pipelines en GitHub.

### Existe más de un check equivalente

El script falla de forma deliberada y no decide cuál conservar. Revisar
**Approvals and checks**, eliminar manualmente el duplicado correcto y repetir.

## Evidencia que debes devolver

Ejecuta primero `-WhatIf` y comparte su salida completa. Después de revisarla,
ejecuta la aplicación y comparte desde el primer `[VERIFIED]` hasta el resumen
final. El script no imprime el token temporal.

## Referencias

- [Azure DevOps Environments](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/environments?view=azure-devops)
- [Approvals and checks](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/approvals?view=azure-devops)
- [Environments REST API — Add](https://learn.microsoft.com/en-us/rest/api/azure/devops/distributedtask/environments/add?view=azure-devops-rest-7.1)
- [Check Configurations REST API — Add](https://learn.microsoft.com/en-us/rest/api/azure/devops/approvalsandchecks/check-configurations/add?view=azure-devops-rest-7.1)

## Siguiente paso

No continuar automáticamente. Primero se valida este resultado. Luego viene el
gate manual de Azure Pipelines GitHub App y `03-configure-pipelines`.
