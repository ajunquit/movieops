# Paso 04 — Retención de Azure Pipelines

## Estado

Implementado y validado en modo de solo lectura. Pendiente de ejecución por el
operador.

## Objetivo

Aplicar la política de retención acordada para MovieOps en el nivel del Project:

| Configuración | Valor objetivo |
|---|---:|
| Runs y logs | 30 días |
| Artifacts, symbols y attachments | 30 días |
| Pull Request runs | 14 días |
| Runs recientes por pipeline | 3 |

Azure DevOps ya no soporta políticas distintas por pipeline YAML. Estos valores
se administran en `MovieOps → Project settings → Pipelines → Settings`.

## Script

[`configure-retention.ps1`](configure-retention.ps1)

## Qué hace

1. Verifica el Project `MovieOps`.
2. Exige una ejecución verde de `MovieOps-Diagnostic` sobre `main` como gate del
   paso 03.
3. Consulta la API pública Build Retention.
4. Lee para cada setting el valor actual y los límites mínimo/máximo impuestos
   por Azure DevOps.
5. Rechaza un objetivo fuera de esos límites antes de mutar.
6. Aplica los cuatro valores en una única operación PATCH si existe drift.
7. Vuelve a leer la configuración y verifica convergencia exacta.

## Estado descubierto antes de la aplicación

La consulta de solo lectura del 16 de septiembre de 2026 encontró:

| Configuración | Actual | Objetivo | Acción esperada |
|---|---:|---:|---|
| Runs y logs | 30 | 30 | Ninguna |
| Artifacts | 30 | 30 | Ninguna |
| Pull Request runs | 10 | 14 | Actualizar |
| Runs recientes | 3 | 3 | Ninguna |

Aunque el PATCH envía el desired state completo, solo cambia materialmente el
valor divergente.

## Qué no hace

- No elimina runs, logs o artifacts inmediatamente; Azure DevOps evalúa la
  retención periódicamente.
- No modifica políticas de Classic Releases o retención de Test Plans.
- No usa el endpoint legacy `build/settings` como fuente de verdad.
- No crea reglas por pipeline porque Azure DevOps ya no las soporta.
- No marca todavía Genesis/CD/Apocalipsis como retenidos indefinidamente: esos
  runs aún no existen. Sus leases se gestionarán cuando produzcan la evidencia
  final.
- No ejecuta ningún pipeline.

## Prerrequisitos

- Pasos 00–03 completados.
- `MovieOps-Diagnostic` con al menos un run `succeeded` en `main`.
- PowerShell 7, Azure CLI y extensión `azure-devops`.
- Permiso para editar configuración de build/retención del Project.

Gate verificado:

```text
MovieOps-Diagnostic pipeline ID: 8
Successful run ID: 59
Branch: refs/heads/main
Commit: 0c4936d7ef566ed7e4ad5ec7a5333cea7811e402
```

## Parámetros

| Parámetro | Default | Propósito |
|---|---:|---|
| `OrganizationUrl` | `https://dev.azure.com/ajunquit` | Organización target |
| `ProjectName` | `MovieOps` | Project target |
| `RunRetentionDays` | `30` | Días para runs y logs |
| `ArtifactRetentionDays` | `30` | Días para artifacts y adjuntos |
| `PullRequestRunRetentionDays` | `14` | Días para runs de PR |
| `RecentRunsPerPipeline` | `3` | Mínimo de runs recientes |
| `DiagnosticPipelineName` | `MovieOps-Diagnostic` | Gate de entrada |
| `WhatIf` | Desactivado | Muestra drift sin aplicar cambios |

Los artifacts no pueden configurarse para vivir más días que su run; el script
rechaza esa combinación.

## Ejecución

### 1. Vista previa

```powershell
./scripts/azure-devops/04-configure-retention/configure-retention.ps1 -WhatIf
```

La primera vista previa debe planificar únicamente `Pull Request runs: 10 → 14`.

### 2. Aplicación

```powershell
./scripts/azure-devops/04-configure-retention/configure-retention.ps1
```

### 3. Reejecución idempotente

```powershell
./scripts/azure-devops/04-configure-retention/configure-retention.ps1
```

Debe informar `EXISTS` y verificar los cuatro valores.

## Salida esperada

```text
[VERIFIED] Azure DevOps project: MovieOps (...).
[VERIFIED] Diagnostic gate: run 59 succeeded on refs/heads/main.
[PLAN] Update 'Pull Request runs' from 10 to 14.
[UPDATED] Project-level pipeline retention settings.
[VERIFIED] Runs and logs retention: 30 days.
[VERIFIED] Artifact retention: 30 days.
[VERIFIED] Pull Request run retention: 14 days.
[VERIFIED] Recent runs retained per pipeline: 3.
[VERIFIED] Project-level retention bootstrap completed.
```

## Idempotencia y drift

- El estado actual se consulta antes de actualizar.
- No se envía PATCH cuando los cuatro valores cumplen.
- La API publica límites distintos por setting; todos se validan dinámicamente.
- Una segunda ejecución no crea objetos ni altera fechas de runs existentes.
- La verificación posterior exige igualdad exacta con los valores deseados.

## Verificación en el portal

1. Azure DevOps → `MovieOps` → **Project settings**.
2. **Pipelines → Settings**.
3. Confirmar `30`, `30`, `14` y `3` en los cuatro controles de retención.

Las políticas se procesan periódicamente; guardar el setting no borra datos en
el mismo instante.

## Resolución de problemas

### El objetivo está fuera del rango del servidor

Cada organización puede imponer límites. El script muestra el mínimo y máximo
devueltos por Azure DevOps y se detiene antes del PATCH. No forzar valores fuera
de ese boundary.

### HTTP 401 o 403 al aplicar

La cuenta puede consultar pipelines pero no editar políticas del Project.
Verificar permisos de Build/Project administrator y renovar la sesión si cambió
la asignación.

### No existe un diagnóstico verde

El paso 04 no oculta un paso 03 incompleto. Ejecutar `MovieOps-Diagnostic` en
`main`, corregir cualquier fallo y repetir.

### El portal todavía muestra el valor anterior

Refrescar **Project settings → Pipelines → Settings**. Si persiste, reejecutar
el script: la lectura final de API indicará si existe drift real o solo caché de
la interfaz.

## Evidencia que debes devolver

Comparte la salida de `-WhatIf` y luego la aplicación completa. El script no
lee ni imprime secretos.

## Referencias

- [Build Retention REST API](https://learn.microsoft.com/en-us/rest/api/azure/devops/build/retention?view=azure-devops-rest-7.1)
- [Azure Pipelines retention policies](https://learn.microsoft.com/en-us/azure/devops/pipelines/policies/retention?view=azure-devops)

## Siguiente paso

Después de verificar la retención, el paso 05 realizará la auditoría read-only
completa del bootstrap. Luego comenzará ADOP-2: CI parity.

