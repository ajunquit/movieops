# MovieOps — Plan de implementación con GitHub Actions y Azure

## Estado

Baseline implementada y validada en `dev` hasta el alcance del Sprint 9.

Este documento reconstruye como plan verificable el trabajo ya realizado con
GitHub Actions. Sirve como:

- registro de cómo se llegó al flujo actual;
- checklist de capacidades realmente probadas;
- baseline para la paridad con Azure DevOps;
- referencia antes de reproducir la plataforma en AWS.

El documento rector continúa siendo
[`MovieOps_DevOps_Plan.md`](../../MovieOps_DevOps_Plan.md).

## Objetivo alcanzado

Construir un ciclo de entrega reproducible en el que GitHub aloja el código y
ejecuta CI/CD, mientras Terraform crea la infraestructura y la aplicación corre
en Microsoft Azure:

```text
GitHub
├── Repository + Pull Requests
├── GitHub Actions
│   ├── CI
│   ├── Genesis
│   ├── CD
│   └── Apocalipsis
└── GHCR
        │
        ▼
Microsoft Azure
├── VNet + NSG
├── AKS + managed Ingress
├── ACR
├── PostgreSQL Flexible Server
├── Key Vault
└── Load Balancer
```

No se utilizó Azure DevOps en esta implementación. La plataforma de pipelines
es GitHub Actions; Azure es el proveedor cloud.

## Alcance

Incluye:

- CI de backend y frontend.
- Tests, quality gate y security scanning.
- Imágenes Docker inmutables por commit.
- Publicación CI en GHCR.
- Terraform remoto y modular para Azure `dev`.
- Autenticación GitHub→Azure mediante OIDC.
- Genesis y Apocalipsis manuales.
- Promoción GHCR→ACR sin rebuild.
- Despliegue push-based en AKS con Kustomize.
- Key Vault como fuente de secretos de aplicación.
- Probes, rollout gate, smoke test e intento de rollback.
- Ingress público hacia frontend y backend.
- Troubleshooting y scripts de bootstrap reproducibles.

Fuera de esta baseline:

- Terraform funcional para `staging` y `production`.
- Dominio estable, DNS administrado y TLS.
- Argo CD y GitOps pull-based.
- Blue-green/canary con Argo Rollouts.
- OpenTelemetry, Prometheus y Grafana.
- Infraestructura AWS.

## Principios aplicados

1. **Pipeline as Code:** workflows y actions viven en Git.
2. **Fail Fast:** formato, lint y validaciones baratas ocurren primero.
3. **Fan-Out/Fan-In:** backend/frontend paralelos, quality gate común.
4. **Immutable Artifact:** imágenes taggeadas con el SHA del commit.
5. **Build Once, Deploy Many:** CD promueve, nunca recompila.
6. **Plan Before Apply:** Terraform aplica el plan guardado.
7. **Separation of Concerns:** CI, infraestructura y CD son workflows distintos.
8. **Least Persistent Credential:** OIDC en vez de client secrets.
9. **Externalized Configuration:** config en ConfigMap; secretos en Key Vault y
   Kubernetes Secret.
10. **Controlled Destruction:** destroy manual con confirmación tipada.
11. **Evidence Before Theory:** cada fallo real queda en troubleshooting.
12. **Reproducibility:** cada cambio mutante de bootstrap queda scripteado.

## Inventario de implementación

### Workflows principales

| Archivo | Trigger | Responsabilidad |
|---|---|---|
| `.github/workflows/ci.yml` | PR/push a `main` | Orquesta CI y quality gate |
| `.github/workflows/backend-ci.yml` | Reusable | Build y tests .NET |
| `.github/workflows/frontend-ci.yml` | Reusable | Build y tests Angular |
| `.github/workflows/docker-build.yml` | Reusable | Construye backend/frontend; publica solo desde `main` |
| `.github/workflows/codeql.yml` | GitHub events | SAST con CodeQL |
| `.github/workflows/genesis.yml` | Manual | Terraform plan/apply |
| `.github/workflows/cd-dev.yml` | Manual | Entrada de despliegue `dev` |
| `.github/workflows/cd-staging.yml` | Manual | Entrada futura de `staging` |
| `.github/workflows/cd-production.yml` | Manual | Entrada futura de producción |
| `.github/workflows/deploy.yml` | Reusable | Promoción, secretos, AKS, gates y rollback |
| `.github/workflows/apocalipsis.yml` | Manual | Terraform plan-destroy/apply |

### Composite actions

```text
.github/actions/
├── dotnet-build/
├── angular-build/
├── docker-build/
└── security-scan/
```

Separan comportamiento reutilizable de la orquestación y mantienen los
workflows principales legibles.

### Scripts de bootstrap Azure

| Script | Propósito |
|---|---|
| `scripts/azure/sync-github-oidc-federated-credentials.ps1` | Sincroniza subjects OIDC inmutables |
| `scripts/azure/grant-ci-subscription-roles.ps1` | Garantiza Contributor + RBAC Administrator para CI |
| `scripts/azure/grant-keyvault-operator-access.ps1` | Da acceso data-plane al operador humano |

## Arquitectura del flujo

### Flujo de CI

```text
Pull Request / push main
          │
          ▼
        ci.yml
     ┌────┴────┐
     ▼         ▼
 Backend CI  Frontend CI
     │         │
     └────┬────┘
          ▼
    Quality Gate
          │
          ▼
 Docker Build ×2
          │
          ├── PR: build only
          └── main: push GHCR
```

Tags publicados:

```text
ghcr.io/ajunquit/movieops-api:sha-<short-sha>
ghcr.io/ajunquit/movieops-frontend:sha-<short-sha>
```

### Flujo de infraestructura

```text
Genesis (manual)
   │ environment + confirm
   ▼
GitHub Environment gate
   │
   ▼ OIDC token
Microsoft Entra ID
   │
   ▼
Terraform
   ├── fmt
   ├── init (remote state)
   ├── validate
   ├── Checkov
   ├── plan -out=tfplan
   └── apply tfplan
```

El backend remoto vive en `rg-movieops-tfstate` y no forma parte del destroy de
un ambiente.

### Flujo de CD

```text
CD Dev (manual image_tag)
        │
        ▼
deploy.yml
   ├── OIDC login Azure
   ├── GHCR ── az acr import ──► ACR
   ├── Key Vault ──► Kubernetes Secret
   ├── Kustomize set image
   ├── kubectl apply
   ├── rollout status
   ├── smoke test Ingress
   └── rollback si falla y existe revisión previa
```

La promoción registry-to-registry conserva el artefacto que pasó CI; el runner
no ejecuta `docker build`, `docker pull` ni `docker push` durante CD.

### Flujo de tráfico

```text
Internet
   │
   ▼
Azure Standard Load Balancer :80/:443
   │ NSG permite tráfico de aplicación
   ▼
Managed NGINX Ingress
   ├── /api/* ──► backend ClusterIP :8080 ──► backend pods
   └── /*     ──► frontend ClusterIP :80  ──► frontend pods
```

Backend y frontend no tienen IP pública propia. El Ingress es el único punto de
entrada externo.

## Roadmap ejecutado

### GH-0 — Repositorio, convenciones y seguridad básica ✅

Entregables:

- Estructura del monorepo.
- `.gitignore`, `.dockerignore` y `.env.example`.
- GitHub como source of truth.
- Dependabot y política de no commitear secretos.

Evidencia: estructura base, README y ADRs iniciales.

### GH-1 — CI backend/frontend ✅

Entregables:

- Workflows reutilizables separados por aplicación.
- Backend/frontend en paralelo.
- Unit e integration tests.
- Quality gate fan-in.
- Cancelación de CI obsoleto por branch/ref.

Evidencia: runs verdes y tests ejecutados en runners GitHub-hosted.

### GH-2 — Contenedores y artefactos inmutables ✅

Entregables:

- Dockerfiles multi-stage.
- Build en todos los PR.
- Push a GHCR únicamente desde `main`.
- Tags `sha-*` trazables al commit.
- Trivy/CodeQL/Dependabot como controles shift-left.

Evidencia: imágenes de backend/frontend publicadas desde CI.

### GH-3 — Terraform Azure y remote state ✅

Entregables:

- Módulos `network`, `monitoring`, `container-registry`, `postgres`, `secrets`
  y `kubernetes`.
- Environment `terraform/environments/azure/dev`.
- Backend remoto separado.
- VNet/subnet/NSG, AKS, ACR, PostgreSQL, Key Vault y Log Analytics.

Evidencia: infraestructura `dev` creada en Azure y registrada en state.

### GH-4 — Identidad federada GitHub→Azure ✅

Entregables:

- App Registration sin client secret.
- Credenciales federadas por GitHub Environment.
- Subjects OIDC inmutables.
- Permisos `id-token: write`.
- Roles de control plane/RBAC necesarios para Terraform.

Evidencia: `terraform init/plan/apply` autenticados mediante OIDC.

### GH-5 — Genesis y Apocalipsis ✅

Entregables:

- Pipelines manuales separados para create/update y destroy.
- Confirmación tipada.
- GitHub Environment gates.
- Plan guardado aplicado sin recalcular.
- Destroy excluye el backend remoto.

Estado:

- Genesis fue validado creando y actualizando `dev`.
- Apocalipsis eliminó `rg-movieops-dev`, incluidos recursos auxiliares fuera del
  state, y verificó su ausencia en el run
  [35158781637](https://github.com/ajunquit/movieops/actions/runs/35158781637).
- `rg-movieops-tfstate` permaneció fuera del boundary de destrucción.

### GH-6 — CD tradicional y promoción de artefacto ✅

Entregables:

- Workflow reusable `deploy.yml`.
- Entradas por ambiente.
- `az acr import` desde GHCR.
- Mismo `image_tag` para backend/frontend y ambientes.
- Lectura runtime desde Key Vault.

Evidencia: ACR recibió las imágenes SHA sin rebuild.

### GH-7 — Kubernetes workload y configuración ✅

Entregables:

- Namespace.
- Deployments y ClusterIP Services.
- ConfigMap y Secret runtime.
- Managed Ingress.
- Startup/liveness/readiness probes.
- Requests/limits, HPA y rolling update.

Evidencia: backend y frontend alcanzaron `2/2` réplicas disponibles.

### GH-8 — Health gates, red y smoke test ✅

Entregables:

- `kubectl rollout status` para ambos Deployments.
- Smoke test con deadlines coherentes.
- Regla NSG explícita para los puertos reales del Load Balancer.
- Acceso público al frontend y `/api/movies`.

Evidencia: frontend y API respondieron HTTP 200 desde la IP del Ingress.

### GH-9 — Rollback y operación segura 🟡

Entregables implementados:

- `kubectl rollout undo` cuando existe una revisión previa.
- Tratamiento explícito del primer deploy sin historial.
- Diagnóstico de pods/deployments al fallar.
- Runbook de create/deploy/verify/destroy.

Pendiente para cerrar totalmente:

- Provocar un segundo deployment defectuoso y demostrar el rollback hacia una
  revisión sana anterior. El fallo del primer deploy validó correctamente la
  rama “no existe revisión previa”, no el undo exitoso.

## Gestión de configuración y secretos

```text
Local development
.env (ignorado por Git)

Cloud
Terraform random_password ──► Key Vault: postgres-admin-password
Operador autorizado       ──► Key Vault: tmdb-api-key
deploy.yml                ──► Kubernetes Secret: backend-secrets
Config no sensible        ──► Kubernetes ConfigMap
```

GitHub Secrets contiene identificadores OIDC (`client`, `tenant`,
`subscription`), no secretos de aplicación. Los valores leídos desde Key Vault
se enmascaran antes de construir la connection string.

## Fallos reales convertidos en controles

| Caso | Aprendizaje incorporado |
|---|---|
| TS-06 | Un step anterior a checkout necesita working directory existente |
| TS-08 | El subject OIDC debe coincidir exactamente con GitHub |
| TS-09 | Contributor no puede crear role assignments |
| TS-10 | Management plane no equivale al data plane de Key Vault |
| TS-11 | Health probes del Load Balancer no prueban tráfico real del cliente |
| TS-12 | Un recurso auxiliar fuera del state puede bloquear el destroy del Resource Group |

Detalle completo: [`docs/troubleshooting.md`](../troubleshooting.md).

## Matriz de capacidades y evidencia

| Capacidad | Estado | Evidencia principal |
|---|---|---|
| CI automático en PR/push main | ✅ | `ci.yml` |
| Fan-Out/Fan-In | ✅ | backend/frontend + quality gate |
| Tests backend/frontend | ✅ | Runs CI verdes |
| Security scanning | ✅ | Trivy, CodeQL, Dependabot, Checkov informativo |
| Imágenes inmutables por SHA | ✅ | GHCR |
| Terraform plan/apply | ✅ | Genesis en `dev` |
| OIDC sin client secret | ✅ | ADR-0004 + runs reales |
| Promote without rebuild | ✅ | GHCR→ACR con `az acr import` |
| Key Vault→Kubernetes Secret | ✅ | Deploy exitoso |
| AKS rollouts sanos | ✅ | backend/frontend `2/2` |
| Ingress + smoke HTTP | ✅ | frontend/API HTTP 200 |
| Destroy controlado | ✅ | Run 35158781637: RG del ambiente ausente; state conservado |
| Rollback con revisión previa | 🟡 | Código implementado; prueba deliberada pendiente |
| STAGING/PRODUCTION | 🔜 | Entradas CD existen; Terraform no implementado |
| GitOps/Argo CD | 🔜 | Sprint 10 del plan rector |

## Definition of Done de la baseline

La baseline GitHub Actions + Azure se considera suficiente para iniciar la
paridad Azure DevOps porque:

- CI valida backend y frontend y produce imágenes por SHA.
- Terraform crea la infraestructura `dev` mediante OIDC.
- CD promueve sin rebuild y despliega sobre AKS.
- Secretos se obtienen de Key Vault en runtime.
- Rollout y smoke test bloquearon fallos reales.
- Frontend y API fueron accesibles públicamente.
- La infraestructura puede destruirse sin eliminar el state remoto.
- Los gaps restantes están explícitos y no se presentarán como validados.

## Relación con los siguientes planes

Azure DevOps debe reproducir esta matriz, no inventar otra arquitectura de
producto. Las diferencias aceptables son las propias de la plataforma:

- GitHub reusable workflows ↔ Azure Pipelines templates.
- GitHub Environments ↔ Azure DevOps Environments.
- GitHub OIDC ↔ Azure Resource Manager service connection con WIF.
- GHCR como handoff ↔ Pipeline Artifacts/ACR según el plan de paridad.

Ver [`AZURE_DEVOPS_PARITY_PLAN.md`](AZURE_DEVOPS_PARITY_PLAN.md).

AWS reutilizará la misma aplicación, imágenes, Kubernetes manifests y criterios
de aceptación, reimplementando únicamente los servicios del proveedor y sus
integraciones.

## Documentos relacionados

- [Flujo CI/CD implementado](../ci-cd.md)
- [Runbook de despliegue](../deployment.md)
- [Patrones de pipeline](../pipelines/PIPELINE_PATTERNS.md)
- [Troubleshooting](../troubleshooting.md)
- [Notas para entrevistas](../interview-notes.md)
