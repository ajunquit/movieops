# Paso 06 — Configurar CI parity

## Estado

Completado y registrado como `MovieOps-CI` (ID `9`). El cierre de ADOP-2 quedó
demostrado con main run `67`, PR sano `#31`/run `65`, PR roto `#9`/run `64` y
auditoría `12/12 PASS`.

## Objetivo

Registrar `MovieOps-CI` en Azure DevOps y reproducir el comportamiento del CI
de GitHub Actions sin conceder permisos para modificar Azure.

```text
PR o push a main
  ├── BackendCI (.NET 10)
  └── FrontendCI (Angular / Node 22)
             │
             ▼
        QualityGate
             │
             ▼
        BuildImages
             │
       solo en main
             ▼
  artifact: movieops-images
```

## Archivos

- [`configure-ci.ps1`](configure-ci.ps1): registra y verifica el pipeline.
- [`azure-pipelines/ci.yml`](../../../azure-pipelines/ci.yml): triggers, stages y
  quality gate.
- [`backend-ci.yml`](../../../azure-pipelines/templates/backend-ci.yml):
  restore, format, build, unit/integration tests, coverage y scan.
- [`frontend-ci.yml`](../../../azure-pipelines/templates/frontend-ci.yml):
  Node mediante `UseNode@1`, install, type-check, tests, coverage, build y
  scan.
- [`security-scan.yml`](../../../azure-pipelines/templates/security-scan.yml):
  análisis de dependencias HIGH/CRITICAL con Trivy.
- [`docker-build.yml`](../../../azure-pipelines/templates/docker-build.yml):
  imágenes inmutables y artifact para CD.

## Comportamiento del pipeline

### Pull Requests hacia `main`

- Cancela el run anterior cuando el PR recibe un commit nuevo.
- Ejecuta backend y frontend en paralelo.
- Publica resultados JUnit/TRX y cobertura Cobertura.
- Ejecuta Trivy sin requerir credenciales Azure.
- Construye las dos imágenes para validar los Dockerfiles.
- No publica artefactos ni imágenes en un registry.

### Push a `main`

Ejecuta los mismos controles y publica `movieops-images` con:

```text
movieops-api.tar.gz
movieops-frontend.tar.gz
manifest.json
SHA256SUMS
```

Ambas imágenes usan `sha-<Build.SourceVersion>`. `manifest.json` registra
commit, branch, run, tag e IDs de imagen. El artifact de Azure Pipelines queda
asociado al run y será consumido sin rebuild en ADOP-4.

## Principio de mínimo privilegio

CI solo necesita leer GitHub. No usa Azure CLI, Terraform, ACR ni AKS.
`configure-ci.ps1` comprueba que:

- la conexión GitHub usa Azure Pipelines GitHub App;
- `sc-movieops-azure-wif` no tiene autorización global;
- `MovieOps-CI` no está autorizado para usar la conexión WIF;
- cualquier autorización explícita accidental de CI se revoca al aplicar.

## Prerrequisitos

- ADOP-1 completado con `21/21` controles.
- PowerShell 7, Azure CLI y extensión `azure-devops`.
- Sesiones Azure/Azure DevOps todavía válidas.
- GitHub App connection existente.
- Archivos de este paso publicados en `origin/main` antes de aplicar.

## Parámetros

| Parámetro | Default | Uso |
|---|---|---|
| `OrganizationUrl` | `https://dev.azure.com/ajunquit` | Organización target |
| `ProjectName` | `MovieOps` | Project target |
| `GitHubRepository` | `ajunquit/movieops` | Repositorio GitHub |
| `Branch` | `main` | Rama donde se publica el YAML |
| `PipelineName` | `MovieOps-CI` | Nombre estable del pipeline |
| `YamlPath` | `azure-pipelines/ci.yml` | Entry point del pipeline |
| `AzureServiceConnectionName` | `sc-movieops-azure-wif` | Conexión que CI no debe usar |
| `GitHubServiceConnectionId` | Vacío | Desambiguación opcional |

## Orden de ejecución

### 1. Revisar localmente

```powershell
./scripts/azure-devops/06-configure-ci/configure-ci.ps1 -WhatIf
```

Mientras el pipeline no exista, el preview mostrará el plan y no exigirá que
los archivos ya estén publicados.

### 2. Commit y push

El modo apply exige:

- working tree limpio para los YAML de CI;
- estar en `main`;
- `HEAD` local igual a `origin/main`.

Esto evita registrar una ruta que Azure DevOps todavía no puede leer.

### 3. Registrar el pipeline

```powershell
./scripts/azure-devops/06-configure-ci/configure-ci.ps1
```

El pipeline se crea con `--skip-run`; el primer run permanece bajo control del
operador.

### 4. Ejecutar y validar

Desde Azure DevOps, ejecutar `MovieOps-CI` sobre `main`. Después crear:

1. Un PR sano, que debe finalizar verde en ambas plataformas.
2. Un PR deliberadamente roto, que debe fallar sin producir artifact.

No mezclar el fallo deliberado con `main`.

## Salida esperada del script

```text
[CREATED] Pipeline 'MovieOps-CI' (...); first run skipped.
[EXISTS] 'MovieOps-CI' has no authorization for 'sc-movieops-azure-wif'.
[VERIFIED] Pipeline 'MovieOps-CI' is registered with GitHub App authentication.
[VERIFIED] 'sc-movieops-azure-wif' is not authorized for CI.
[MANUAL ACTION REQUIRED] Run MovieOps-CI on main...
```

## Idempotencia y recuperación

Una segunda ejecución verifica nombre, repositorio, YAML y permisos sin crear
duplicados. Si falla:

1. Corregir la causa indicada.
2. Ejecutar nuevamente el mismo comando.
3. No eliminar el Project ni repetir ADOP-1.

## Gate ADOP-2

- [x] Run manual sobre `main` verde (`60`, `ci-20260917-1`).
- [x] Resultados backend/frontend visibles en **Tests**.
- [x] Cobertura backend/frontend visible en **Code Coverage**.
- [x] Artifact `movieops-images` vinculado al SHA correcto.
- [ ] PR sano verde en GitHub y Azure Pipelines.
- [ ] PR roto falla y no produce artifact.
- [x] CI funciona con `rg-movieops-dev` inexistente.
