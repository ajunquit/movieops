# CI/CD e infraestructura: flujo implementado

Este documento describe el flujo que MovieOps ya ejecutó de extremo a extremo
en `dev`: integración continua en GitHub, creación de infraestructura en Azure,
despliegue de la aplicación sobre AKS y destrucción controlada del ambiente.

## Aclaración de términos

MovieOps utiliza **GitHub Actions como plataforma de CI/CD** y **Microsoft Azure
como proveedor cloud**. No utiliza el producto **Azure DevOps**.

| Responsabilidad | Tecnología usada |
|---|---|
| Repositorio, Pull Requests y revisión | GitHub |
| Pipelines de CI, infraestructura, CD y destroy | GitHub Actions |
| Registro inicial de imágenes | GitHub Container Registry (GHCR) |
| Infrastructure as Code | Terraform |
| Identidad de CI/CD hacia Azure | GitHub OIDC + Microsoft Entra ID |
| Infraestructura y runtime | Microsoft Azure |
| Orquestación de contenedores | Azure Kubernetes Service (AKS) |
| Registro del ambiente | Azure Container Registry (ACR) |
| Secretos de aplicación | Azure Key Vault → Kubernetes Secret |

Azure DevOps —Azure Repos, Azure Pipelines, Boards y Artifacts— no participa en
este diseño. La forma precisa de describirlo es:

> CI/CD con GitHub Actions, Infrastructure as Code con Terraform y despliegue
> de la plataforma y la aplicación sobre Microsoft Azure.

## Vista completa

```text
Developer
   │
   │ push / pull request
   ▼
GitHub Repository
   │
   ▼
GitHub Actions · ci.yml
   ├── Backend CI ── build + tests + security
   ├── Frontend CI ─ build + tests + security
   └── Quality Gate
             │
             ▼
       Docker Build
             │ push en main
             ▼
          GHCR
   movieops-api:sha-xxxxxxx
   movieops-frontend:sha-xxxxxxx

GitHub Actions · genesis.yml             GitHub Actions · cd-dev.yml
   │ OIDC                                   │ image_tag=sha-xxxxxxx
   ▼                                        ▼
Terraform ───────── crea ──────────────► Microsoft Azure
                                            ├── VNet + NSG
                                            ├── AKS
GHCR ── az acr import ───────────────────►  ├── ACR
                                            ├── PostgreSQL
Key Vault ── runtime read ───────────────►  ├── Kubernetes Secret
                                            └── Load Balancer + Ingress
                                                        │
                                                        ▼
                                               Frontend + Backend

GitHub Actions · apocalipsis.yml
   └── Terraform destroy ── elimina el ambiente, conserva el backend del state
```

## 1. Integración continua

Archivo principal: [`.github/workflows/ci.yml`](../.github/workflows/ci.yml).

Se ejecuta automáticamente en cada Pull Request y push a `main`:

1. Backend y frontend se validan en paralelo (*fan-out*).
2. Cada rama ejecuta compilación, tests y controles de seguridad.
3. El job `quality-gate` espera a ambos (*fan-in*).
4. Se construyen las imágenes del backend y frontend.
5. En Pull Requests las imágenes solo se construyen; en `main` también se
   publican en GHCR.
6. Cada imagen queda identificada por el commit:

```text
ghcr.io/ajunquit/movieops-api:sha-<commit>
ghcr.io/ajunquit/movieops-frontend:sha-<commit>
```

El SHA conecta código, ejecución de CI, imagen y despliegue.

## 2. Creación o actualización de infraestructura

Workflow: [`.github/workflows/genesis.yml`](../.github/workflows/genesis.yml).

`Genesis` es manual porque crea recursos con costo real. Requiere seleccionar
un GitHub Environment y escribir su nombre como confirmación.

```text
workflow_dispatch
   → confirmación tipada
   → OIDC GitHub/Entra ID
   → terraform fmt
   → terraform init
   → terraform validate
   → Checkov
   → terraform plan
   → terraform apply
```

Terraform crea en Azure:

- VNet, subnet y NSG.
- AKS con Application Routing/Ingress administrado.
- ACR.
- PostgreSQL Flexible Server.
- Key Vault.
- Log Analytics.
- Roles necesarios entre AKS, ACR y Key Vault.

El state vive fuera del ambiente en `rg-movieops-tfstate`. Por eso puede leerse
antes de crear `dev` y permanece después de destruirlo.

## 3. Despliegue continuo actual

Entrada de `dev`: [`.github/workflows/cd-dev.yml`](../.github/workflows/cd-dev.yml).
Implementación reutilizable: [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml).

El operador selecciona un `image_tag` producido por un CI verde. El despliegue:

1. Autentica GitHub Actions en Azure mediante OIDC.
2. Promueve las imágenes exactas desde GHCR hacia ACR con `az acr import`.
3. No recompila: conserva el artefacto que superó CI (*Build Once, Deploy Many*).
4. Lee la password de PostgreSQL y la API key de TMDB desde Key Vault.
5. Crea o actualiza el Kubernetes Secret sin guardar valores en Git.
6. Establece las imágenes con Kustomize y aplica `k8s/base` sobre AKS.
7. Espera que terminen los rollouts del backend y frontend.
8. Ejecuta un smoke test acotado contra la IP pública del Ingress.
9. Si falla un health gate o smoke test, intenta volver a la revisión anterior.

El ciclo `dev` fue validado en Azure: backend y frontend llegaron a `2/2`
réplicas disponibles, el Ingress quedó accesible y frontend/API respondieron
`HTTP 200`.

## 4. Tráfico en ejecución

Backend y frontend no reciben IP pública individual. Ambos son servicios
`ClusterIP`; el único punto de entrada público es el Ingress:

```text
Browser
   │ HTTP
   ▼
Azure Standard Load Balancer
   │
   ▼
Managed NGINX Ingress
   ├── /api/* ──► service/backend:8080 ──► backend pods ──► PostgreSQL / TMDB
   └── /*     ──► service/frontend:80  ──► frontend pods
```

La IP se descubre en Azure Portal:

```text
AKS → Kubernetes resources → Services and ingresses → Ingresses → movieops
```

No hay dominio estable ni TLS todavía. La IP puede cambiar al destruir y volver
a crear el ambiente.

## 5. Destrucción controlada

Workflow: [`.github/workflows/apocalipsis.yml`](../.github/workflows/apocalipsis.yml).

`Apocalipsis` es manual, exige environment y confirmación tipada, genera un
plan de destrucción y aplica exactamente ese plan:

```text
workflow_dispatch
   → confirmación tipada
   → OIDC
   → terraform init
   → terraform plan -destroy
   → terraform apply destroy.tfplan
```

Destruye `rg-movieops-dev` y sus recursos facturables. No destruye:

- El repositorio, workflows o imágenes de GHCR.
- La App Registration y sus credenciales OIDC de bootstrap.
- `rg-movieops-tfstate`, su Storage Account ni el historial del state.

## Modelo actual y evolución GitOps

El CD actual es **push-based**: GitHub Actions obtiene credenciales del cluster
y ejecuta `kubectl apply`. Los manifiestos ya son declarativos, pero GitHub
todavía inicia y empuja el cambio.

La evolución prevista es **pull-based GitOps** con Argo CD:

```text
Actual: GitHub Actions ── kubectl apply ──► AKS
Futuro: Git commit ◄── observado y reconciliado por ── Argo CD dentro de AKS
```

Argo CD añadirá reconciliación continua y detección/corrección de drift. No
reemplazará el CI ni Terraform: CI seguirá construyendo artefactos y Terraform
seguirá creando la infraestructura.

## Documentos relacionados

- [Runbook operativo](deployment.md)
- [Patrones de pipeline](pipelines/PIPELINE_PATTERNS.md)
- [OIDC entre GitHub y Azure](adr/0004-github-actions-azure-oidc.md)
- [Troubleshooting real](troubleshooting.md)

