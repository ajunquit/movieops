# Paso 03 — GitHub App y pipeline de diagnóstico

## Estado

Implementado. Pendiente del gate manual de GitHub App, commit/push y ejecución
por el operador.

## Objetivo

Cerrar ADOP-1 demostrando esta cadena sin secretos persistentes:

```text
GitHub: ajunquit/movieops
  │ checkout mediante Azure Pipelines GitHub App
  ▼
MovieOps-Diagnostic
  │ autorización exclusiva
  ▼
sc-movieops-azure-wif
  │ Workload Identity Federation
  ▼
Azure: account show + resource group list (solo lectura)
```

## Archivos

- [`configure-pipelines.ps1`](configure-pipelines.ps1): registra y autoriza el
  pipeline.
- [`azure-pipelines/diagnostic.yml`](../../../azure-pipelines/diagnostic.yml):
  diagnóstico manual de GitHub y Azure WIF.

## Qué hace

1. Verifica el Project `MovieOps` y la service connection Azure WIF.
2. Exige una conexión GitHub de tipo `github`, lista y con esquema
   `InstallationToken`, que identifica Azure Pipelines GitHub App.
3. Rechaza implícitamente conexiones OAuth y PAT.
4. Verifica que el YAML esté versionado y publicado en `origin/main` antes de
   aplicar.
5. Crea `MovieOps-Diagnostic` sin ejecutar su primer run.
6. Si el pipeline ya existe, valida repositorio y ruta YAML.
7. Autoriza `sc-movieops-azure-wif` únicamente para ese pipeline.
8. Comprueba que la conexión Azure no esté autorizada globalmente.

## Qué hace el pipeline

- Se ejecuta únicamente de forma manual (`trigger: none`, `pr: none`).
- Hace checkout de GitHub para demostrar que la App puede leer el repositorio.
- Usa `AzureCLI@2` con `sc-movieops-azure-wif`.
- Comprueba Subscription ID y Tenant ID esperados.
- Lista Resource Groups como prueba de acceso de lectura.
- No crea, actualiza ni elimina recursos Azure.
- No expone el token federado mediante `addSpnToEnvironment`.

## Gate manual obligatorio: GitHub App

Microsoft exige consentimiento interactivo del propietario. El script no puede
ni debe automatizarlo.

Después de hacer commit/push de estos archivos:

1. Abrir Azure DevOps → `MovieOps` → **Pipelines → New pipeline**.
2. Elegir **GitHub**.
3. Instalar o autorizar **Azure Pipelines GitHub App**.
4. En GitHub seleccionar **Only select repositories**.
5. Autorizar únicamente `ajunquit/movieops`.
6. Asociar la instalación con la organización `ajunquit` y Project `MovieOps`.
7. Si Azure DevOps propone crear un pipeline, salir antes de guardarlo: el
   script registrará `MovieOps-Diagnostic`.
8. En **Project settings → Service connections**, confirmar una conexión
   GitHub cuya autenticación indique **Azure Pipelines app**.

No elegir **Authorize using OAuth** y no crear un GitHub PAT.

## Prerrequisitos

- Pasos 00, 01 y 02 completados.
- PowerShell 7, Git, Azure CLI y extensión `azure-devops`.
- Los archivos de este paso fusionados y publicados en `origin/main`.
- GitHub App instalada exclusivamente para `ajunquit/movieops`.
- Permiso para crear pipelines y administrar autorizaciones de recursos.
- Capacidad de Microsoft-hosted parallel job disponible para ejecutar el
  diagnóstico posteriormente.

## Parámetros

| Parámetro | Default | Propósito |
|---|---|---|
| `OrganizationUrl` | `https://dev.azure.com/ajunquit` | Organización target |
| `ProjectName` | `MovieOps` | Project target |
| `GitHubRepository` | `ajunquit/movieops` | Repositorio fuente |
| `Branch` | `main` | Rama predeterminada |
| `PipelineName` | `MovieOps-Diagnostic` | Nombre estable en Azure DevOps |
| `YamlPath` | `azure-pipelines/diagnostic.yml` | YAML versionado |
| `AzureServiceConnectionName` | `sc-movieops-azure-wif` | Identidad Azure del diagnóstico |
| `GitHubServiceConnectionId` | Vacío | Desambigua varias conexiones GitHub App |
| `WhatIf` | Desactivado | Previsualiza sin crear ni autorizar |

## Orden de ejecución

### 1. Revisar y publicar este paso

Este paso es diferente a los anteriores: Azure DevOps debe leer el YAML desde
GitHub, por lo que no puede aplicarse mientras el archivo solo exista localmente.

```powershell
git status
git add azure-pipelines/diagnostic.yml scripts/azure-devops docs
git commit -m "feat(azure-devops): add diagnostic pipeline bootstrap"
git push origin main
```

No ejecutar esos comandos automáticamente si el branch requiere Pull Request;
en ese caso, fusionar el cambio por el flujo normal y actualizar el checkout de
`main`.

### 2. Completar el gate GitHub App

Seguir la sección anterior y verificar la conexión en Project settings.

### 3. Vista previa

Desde la raíz del repositorio:

```powershell
./scripts/azure-devops/03-configure-pipelines/configure-pipelines.ps1 -WhatIf
```

Si la GitHub App aún no está autorizada, la vista previa informa
`MANUAL ACTION REQUIRED` y termina correctamente sin mutaciones. La ejecución
sin `-WhatIf` sí falla cerrada hasta completar ese consentimiento.

### 4. Aplicación

```powershell
./scripts/azure-devops/03-configure-pipelines/configure-pipelines.ps1
```

### 5. Reejecución idempotente

```powershell
./scripts/azure-devops/03-configure-pipelines/configure-pipelines.ps1
```

Debe informar `EXISTS` para el pipeline y su autorización.

### 6. Ejecución manual del diagnóstico

1. Azure DevOps → **Pipelines → Pipelines**.
2. Abrir `MovieOps-Diagnostic`.
3. Seleccionar **Run pipeline**.
4. Rama `main` → **Run**.
5. Confirmar checkout, autenticación WIF e inventario de Resource Groups.

## Salida esperada del script

```text
[VERIFIED] Local pipeline YAML: azure-pipelines/diagnostic.yml.
[VERIFIED] Azure DevOps project: MovieOps (...).
[VERIFIED] Azure WIF service connection: sc-movieops-azure-wif (...).
[VERIFIED] GitHub App service connection: ... (...).
[VERIFIED] YAML is committed and published on origin/main (...).
[CREATED] Pipeline 'MovieOps-Diagnostic' (...); first run skipped.
[UPDATED] 'sc-movieops-azure-wif' authorized only for 'MovieOps-Diagnostic'.
[VERIFIED] Azure connection authorization is pipeline-scoped; global access remains disabled.
[MANUAL ACTION REQUIRED] Run MovieOps-Diagnostic ...
```

## Idempotencia y drift

- Un pipeline existente con el nombre correcto se reutiliza.
- Un pipeline homónimo apuntando a otro repositorio o YAML detiene el script.
- La autorización WIF existente no se duplica.
- Nunca se activa acceso a todos los pipelines.
- Varias conexiones GitHub App requieren seleccionar explícitamente un ID.
- Una ejecución interrumpida se reanuda ejecutando el mismo script.

## Resolución de problemas

### No se encuentra la propiedad `allPipelines`

Síntoma después de crear el pipeline y autorizar la conexión:

```text
[CREATED] Pipeline 'MovieOps-Diagnostic' (...); first run skipped.
[UPDATED] 'sc-movieops-azure-wif' authorized only for 'MovieOps-Diagnostic'.
No se encuentra la propiedad "allPipelines" en este objeto.
```

La API de Pipeline Permissions omite `allPipelines` cuando no existe una
autorización global. Ese es precisamente el estado seguro esperado, pero la
primera versión accedía directamente a la propiedad bajo `Set-StrictMode` y
fallaba durante la verificación final.

La versión actual consulta primero `PSObject.Properties`; una propiedad ausente
se interpreta como autorización global desactivada. No se debe eliminar el
pipeline ni revocar su autorización específica. Basta con volver a ejecutar el
script: encontrará `MovieOps-Diagnostic`, comprobará el permiso existente y
completará la verificación.

### No se encontró `InstallationToken`

La GitHub App todavía no está asociada con `MovieOps`, o se creó una conexión
OAuth/PAT. Completar el gate manual y comprobar **Azure Pipelines app** en las
propiedades de la conexión.

### El YAML tiene cambios sin commit

Azure Pipelines consume GitHub, no el filesystem local. Publicar el archivo en
`main` antes de aplicar. `-WhatIf` puede ejecutarse antes para revisar el plan.

### Local HEAD no coincide con `origin/main`

El script evita registrar una definición que Azure DevOps todavía no puede
leer. Hacer push si el commit es local, o pull si `origin/main` avanzó.

### El pipeline solicita autorización de la service connection

Reejecutar el script y verificar el mensaje `[UPDATED]`. No activar **Grant
access permission to all pipelines** como atajo.

### No hay parallelism alojado

El registro puede finalizar, pero el run quedará en cola. Solicitar el grant
gratuito de Microsoft-hosted parallelism o configurar posteriormente un agente
self-hosted; no es un fallo de WIF.

## Evidencia que debes devolver

1. Salida de `-WhatIf`.
2. Salida de la aplicación.
3. URL del run manual de `MovieOps-Diagnostic` y su log completo.

## Referencias

- [Build GitHub repositories with Azure Pipelines](https://learn.microsoft.com/en-us/azure/devops/pipelines/repos/github?view=azure-devops)
- [AzureCLI@2 task](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/azure-cli-v2?view=azure-pipelines)
- [Azure Resource Manager service connections with WIF](https://learn.microsoft.com/en-us/azure/devops/pipelines/library/connect-to-azure?view=azure-devops)

## Siguiente paso

Cuando el diagnóstico sea verde, ADOP-1 queda cerrado. El siguiente entregable
es ADOP-2: diseñar e implementar `azure-pipelines/ci.yml` y sus templates.
