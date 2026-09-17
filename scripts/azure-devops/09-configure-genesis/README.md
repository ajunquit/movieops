# Paso 09 — Configurar MovieOps-Genesis

## Estado

Implementado; pendiente de publicación en `main`, registro y primera ejecución.

## Objetivo

Crear una pipeline Azure DevOps exclusivamente manual para desplegar la
infraestructura `dev` mediante Terraform y WIF, sin secrets persistentes.

```text
Run manual: environment=dev + confirm=dev
  → typed confirmation
  → checkout del commit exacto
  → terraform fmt
  → terraform init con WIF
  → terraform validate
  → Checkov informativo
  → terraform plan guardado
  → terraform apply del mismo plan
  → segundo plan: 0 cambios
```

## Separación deliberada

Esta subtask contiene únicamente Genesis:

- [`azure-pipelines/genesis.yml`](../../../azure-pipelines/genesis.yml)
- [`configure-genesis.ps1`](configure-genesis.ps1)

No implementa Apocalipsis, publicación ACR, despliegue AKS ni CD. Cada uno
tendrá su propio paso, script, README, pipeline y gate.

## Controles de seguridad

- `trigger: none` y `pr: none`: ningún commit crea infraestructura.
- Solo se ofrece `dev`, porque es el único ambiente Terraform existente.
- `confirm` debe coincidir exactamente con `dev`.
- Usa `sc-movieops-azure-wif`; no almacena client secret.
- La service connection se autoriza únicamente para `MovieOps-Genesis`.
- El plan se guarda en `$(Pipeline.Workspace)` y el apply consume ese archivo.
- El plan no se publica como artifact porque puede contener datos sensibles.
- El archivo local se elimina con `condition: always()`.
- El segundo plan falla si detecta drift inmediatamente después del apply.

## Herramientas fijadas

| Herramienta | Versión | Fuente |
|---|---:|---|
| Terraform | `1.9.8` | `TerraformInstaller@1` disponible en la organización |
| Checkov | `3.2.495` | Imagen `bridgecrew/checkov:3.2.495` |
| Agente | `ubuntu-latest` | Microsoft-hosted |

Checkov conserva la paridad actual con GitHub Actions como control
informativo (`--soft-fail`). Endurecerlo será una decisión separada, no un
cambio accidental durante la migración.

## Prerrequisitos

- ADOP-2 cerrado con `12/12 PASS`.
- Paso 08 cerrado con `8/8 PASS`.
- `rg-movieops-dev` inexistente antes del primer Genesis.
- Backend remoto `rg-movieops-tfstate` disponible.
- GitHub App y `sc-movieops-azure-wif` listas.
- Los archivos Genesis y Terraform publicados en `origin/main`.

## Parámetros del script

| Parámetro | Default | Uso |
|---|---|---|
| `OrganizationUrl` | `https://dev.azure.com/ajunquit` | Organización Azure DevOps |
| `ProjectName` | `MovieOps` | Project target |
| `GitHubRepository` | `ajunquit/movieops` | Repositorio fuente |
| `Branch` | `main` | Rama de publicación |
| `PipelineName` | `MovieOps-Genesis` | Nombre estable |
| `YamlPath` | `azure-pipelines/genesis.yml` | Entry point |
| `AzureServiceConnectionName` | `sc-movieops-azure-wif` | WIF exclusiva |
| `GitHubServiceConnectionId` | Vacío | Desambiguación opcional |

## Ejecución paso a paso

### 1. Preview del registro

```powershell
./scripts/azure-devops/09-configure-genesis/configure-genesis.ps1 -WhatIf
```

No crea pipeline, permisos ni infraestructura.

### 2. Commit y push

El modo apply exige estar en `main`, tener los archivos relevantes limpios y
que `HEAD` coincida con `origin/main`.

### 3. Registrar sin ejecutar

```powershell
./scripts/azure-devops/09-configure-genesis/configure-genesis.ps1
```

Esto crea `MovieOps-Genesis` con `--skip-run` y autoriza WIF únicamente para su
ID. Todavía no crea infraestructura.

### 4. Ejecutar manualmente

En Azure DevOps:

```text
Pipelines → MovieOps-Genesis → Run pipeline
environment: dev
confirm: dev
```

Esta acción sí crea recursos con costo. Revisar que Apocalipsis esté disponible
en GitHub Actions mientras el paso Azure DevOps correspondiente aún no existe.

## Evidencia esperada

- Pipeline registrada desde GitHub y YAML correcto.
- WIF autorizada para Genesis, no globalmente.
- Secuencia `fmt → init → validate → Checkov → plan → apply`.
- Apply usa el plan guardado.
- `rg-movieops-dev` existe.
- GitHub Actions y Azure DevOps tienen `Key Vault Secrets Officer`.
- Segundo plan devuelve cero cambios.
- `rg-movieops-tfstate` permanece separado.

## Recuperación

- Confirmación incorrecta: corregir parámetros y crear un run nuevo.
- Fallo antes de apply: corregir y reejecutar; no hubo creación parcial salvo lo
  indicado explícitamente por Terraform.
- Fallo durante apply: no borrar manualmente; ejecutar plan para conocer el
  estado parcial y reanudar de forma idempotente.
- No ejecutar Genesis simultáneamente desde GitHub Actions y Azure DevOps.

## Gate de la subtask

- [x] Preview del script correcto (`2026-09-17`; sin cambios remotos).
- [ ] `MovieOps-Genesis` registrada sin primer run automático.
- [ ] WIF autorizada solo para Genesis.
- [ ] Run `environment=dev`, `confirm=dev` verde.
- [ ] Segundo plan con cero cambios.
- [ ] Infraestructura y ambos role assignments verificados.

Solo después se creará la subtask de Apocalipsis.
