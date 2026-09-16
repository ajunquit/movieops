# MovieOps — Plan de Laboratorio DevOps End-to-End

> **Objetivo principal:** construir desde cero una aplicación real con **.NET + Angular + PostgreSQL** y utilizarla como vehículo para practicar, implementar y explicar de forma profesional un ciclo DevOps completo: desarrollo, testing, contenedores, CI, CD, Infrastructure as Code, Kubernetes, GitOps, Argo CD, estrategias de despliegue, seguridad, observabilidad, troubleshooting e incidentes.

---

# 1. Visión general

El proyecto se llamará **MovieOps**.

MovieOps será una aplicación sencilla de catálogo y seguimiento de películas. La funcionalidad de negocio será deliberadamente pequeña para que el foco principal del laboratorio sea DevOps.

La aplicación permitirá:

- Buscar películas mediante una API externa.
- Guardar películas en una colección propia.
- Consultar películas guardadas.
- Editar información asociada a la colección.
- Eliminar películas.
- Cambiar estado de visualización.
- Calificar películas.
- Agregar comentarios.
- Marcar películas como favoritas.
- Consumir una integración real con un proveedor externo.

La aplicación será solo el producto base. El verdadero objetivo será construir alrededor de ella una plataforma DevOps completa.

---

# 2. Stack tecnológico

## Aplicación

- Backend: **.NET**
- Frontend: **Angular**
- Base de datos: **PostgreSQL**
- ORM: **Entity Framework Core**
- API externa: **TMDB**
- API REST
- OpenAPI / Swagger

> Recomendación: usar versiones estables/LTS vigentes al momento de iniciar la implementación. La intención del laboratorio no depende de una versión específica.

## DevOps

- Git
- GitHub
- GitHub Actions
- Docker
- Docker Compose
- PostgreSQL
- Terraform
- Kubernetes
- Kustomize
- Argo CD
- Argo Rollouts
- Container Registry
- Cloud
- Bash
- Trivy
- CodeQL
- Dependabot
- Checkov
- OpenTelemetry
- Prometheus
- Grafana
- Logs
- Metrics
- Traces
- Health Checks
- Monitoring
- Alerting

## Cloud

- **Azure** (proveedor inicial): AKS, ACR, Azure Database for PostgreSQL Flexible Server, Azure Key Vault, VNet.
- **AWS** (proveedor futuro, misma plataforma reimplementada más adelante): EKS, ECR, RDS, Secrets Manager, VPC.

> Principio: la infraestructura se modela por proveedor sin abstracción multi-cloud prematura (ver sección 24). La observabilidad, en cambio, se construye deliberadamente **portable** entre proveedores (ver sección 45).

---

# 3. Arquitectura funcional inicial

```text
                    ┌─────────────────┐
                    │     Angular     │
                    │    Frontend     │
                    └────────┬────────┘
                             │ HTTPS
                             ▼
                    ┌─────────────────┐
                    │    .NET API     │
                    │                 │
                    └───────┬─────────┘
                            │
                ┌───────────┴────────────┐
                │                        │
                ▼                        ▼
       ┌────────────────┐       ┌─────────────────┐
       │   PostgreSQL   │       │    TMDB API     │
       │                │       │ External Service│
       └────────────────┘       └─────────────────┘
```

---

# 4. Caso de uso principal

El usuario podrá buscar películas.

```text
Buscar: "Interstellar"

Angular
   ↓
GET /api/movies/search?query=Interstellar
   ↓
.NET API
   ↓
TMDB API
   ↓
Resultados
```

Después podrá guardar una película en su colección:

```text
TMDB
 │
 │ buscar película
 ▼
.NET API
 │
 │ guardar
 ▼
PostgreSQL
```

Estados posibles:

```text
WATCHLIST
WATCHING
WATCHED
FAVORITE
```

Operaciones iniciales:

```text
Agregar película
Editar película
Eliminar película
Consultar película
Calificar película
Agregar comentario
Cambiar estado
```

---

# 5. Modelo de datos inicial

## Movie

```text
Movie
-------------------------
Id
TmdbId
Title
Description
ReleaseDate
PosterUrl
Genre
CreatedAt
UpdatedAt
```

## MovieCollection

```text
MovieCollection
-------------------------
Id
MovieId
Status
Rating
Comment
CreatedAt
UpdatedAt
```

Posibles evoluciones:

```text
User
Favorite
Review
Genre
AuditLog
```

La regla será: **no sobre-diseñar el dominio al principio**.

---

# 6. Integración externa TMDB

La API tendrá un endpoint aproximado:

```text
GET /api/movies/search?query=Batman
```

Internamente:

```text
MovieController
       │
       ▼
MovieService
       │
       ▼
TmdbClient
       │
       ▼
TMDB API
```

A medida que avance el laboratorio se incorporarán:

- HttpClientFactory
- Timeout
- Retry
- Circuit Breaker
- Rate Limiting
- Caching
- Logging
- Metrics
- Error handling
- Degraded behavior

Ejemplo:

```text
TMDB falla
     │
     ▼
Retry 1
     │
     ▼
Retry 2
     │
     ▼
Circuit Breaker OPEN
     │
     ▼
API devuelve error controlado
```

Objetivo de entrevista:

> Poder explicar una integración real con un proveedor externo y cómo se hizo resiliente.

---

# 7. Estructura oficial del repositorio

Se mantendrá una estructura similar a un proyecto DevOps real, como la referencia analizada.

```text
movieops/
│
├── .github/
│   ├── workflows/
│   │   ├── ci.yml
│   │   ├── backend-ci.yml
│   │   ├── frontend-ci.yml
│   │   ├── docker-build.yml
│   │   ├── terraform.yml
│   │   ├── cd-dev.yml
│   │   ├── cd-staging.yml
│   │   ├── cd-production.yml
│   │   └── deploy.yml
│   │
│   └── actions/
│       ├── dotnet-build/
│       ├── angular-build/
│       ├── docker-build/
│       └── security-scan/
│
├── app/
│   │
│   ├── backend/
│   │   ├── src/
│   │   │   ├── MovieOps.Api/
│   │   │   ├── MovieOps.Application/
│   │   │   ├── MovieOps.Domain/
│   │   │   └── MovieOps.Infrastructure/
│   │   │
│   │   ├── tests/
│   │   │   ├── MovieOps.UnitTests/
│   │   │   └── MovieOps.IntegrationTests/
│   │   │
│   │   ├── MovieOps.sln
│   │   └── Dockerfile
│   │
│   └── frontend/
│       ├── src/
│       ├── angular.json
│       ├── package.json
│       └── Dockerfile
│
├── k8s/
│   ├── base/
│   │   ├── backend/
│   │   ├── frontend/
│   │   └── ingress/
│   │
│   └── overlays/
│       ├── dev/
│       ├── staging/
│       └── production/
│
├── argocd/
│   ├── applications/
│   │   ├── movieops-dev.yaml
│   │   ├── movieops-staging.yaml
│   │   └── movieops-production.yaml
│   │
│   └── projects/
│       └── movieops-project.yaml
│
├── terraform/
│   ├── modules/
│   │   ├── azure/
│   │   │   ├── network/
│   │   │   ├── postgres/
│   │   │   ├── container-registry/
│   │   │   ├── kubernetes/
│   │   │   ├── secrets/
│   │   │   └── monitoring/
│   │   │
│   │   └── aws/               # se completa cuando se replique en AWS
│   │
│   ├── environments/
│   │   └── azure/
│   │       ├── dev/
│   │       ├── staging/
│   │       └── production/
│   │       # environments/aws/ se agrega en la fase AWS, sin tocar azure/
│   │
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   └── backend.tf
│
├── scripts/
│   ├── azure/                 # bootstrap y mantenimiento de Azure
│   │                          # (permisos, OIDC) — todo lo que se aplique
│   │                          # a mano sobre un entorno vive acá
│   ├── build.sh
│   ├── test.sh
│   ├── deploy.sh
│   ├── health-check.sh
│   └── database.sh
│
├── docs/
│   ├── architecture/
│   ├── pipelines/
│   │   ├── CI_DESIGN.md
│   │   ├── CD_DESIGN.md
│   │   ├── PIPELINE_PATTERNS.md
│   │   └── DEPLOYMENT_STRATEGIES.md
│   ├── adr/
│   ├── incidents/
│   ├── architecture.md
│   ├── ci-cd.md
│   ├── infrastructure.md
│   ├── deployment.md
│   └── troubleshooting.md
│
├── docker-compose.yml
├── .dockerignore
├── .gitignore
├── .env.example
└── README.md
```

---

# 8. Responsabilidad de cada carpeta

## `.github/`

Contendrá CI/CD como código.

```text
.github/
    workflows/
    actions/
```

Objetivo:

- Pipelines versionados.
- Reutilización.
- Pull Requests.
- Auditoría.
- Historial.
- Rollback.
- Modularidad.

## `app/`

Contendrá todo el producto.

```text
app/
├── backend/
└── frontend/
```

## `k8s/`

Estado deseado de las aplicaciones en Kubernetes.

Inicialmente podrá ser simple y evolucionar luego a:

```text
k8s/
├── base/
└── overlays/
    ├── dev/
    ├── staging/
    └── production/
```

## `terraform/`

Infraestructura como código.

```text
terraform/
├── modules/
└── environments/
```

## `argocd/`

Declaración GitOps de aplicaciones y proyectos Argo CD.

## `scripts/`

Automatización auxiliar, organizada por dominio (`azure/`, tests, etc.).

**Regla del laboratorio: todo comando que se ejecute contra un entorno real —Azure, el cluster, la base de datos— queda registrado como script acá.**

Un comando que vivió solo en el historial de una terminal **no existe**: no se puede revisar, ni repetir, ni ejecutar por otra persona, ni reconstruir el día que haya que rehacer el entorno desde cero. Aplica sobre todo a dos casos:

1. **Lo que Terraform no puede gestionar por definición** — los permisos y la confianza que Terraform *necesita para poder correr* (por eso no puede gestionarlos él mismo), igual que el Storage Account del state remoto.
2. **Los arreglos aplicados en caliente mientras se diagnostica un fallo** — que son justamente los que más se olvidan, porque en el momento lo único que importa es destrabar el problema.

Cada fallo documentado en `docs/troubleshooting.md` cuya solución haya sido un comando manual debe terminar apuntando a un script de esta carpeta.

Convenciones:

- **Idempotentes**: correrlos dos veces no rompe nada ni duplica recursos.
- **Con vista previa** (`-WhatIf` / `--dry-run`) antes de aplicar cambios.
- **Con verificación final** del estado resultante.
- **Parametrizados**, para poder reutilizarlos en otro ambiente o suscripción.
- **Documentados** en `scripts/README.md`: qué hacen, prerrequisitos y por qué existen.

## `docs/`

Documentación del sistema, decisiones técnicas, pipelines, estrategias de despliegue, incidentes y troubleshooting.

---

# 9. Arquitectura del backend

Se aplicará una Clean Architecture moderada.

```text
MovieOps.Api
        │
        ▼
MovieOps.Application
        │
        ▼
MovieOps.Domain
        ▲
        │
MovieOps.Infrastructure
```

Ejemplo:

```text
MovieOps.Api
    ↓
MovieService
    ↓
MovieRepository ──────→ PostgreSQL
    ↓
TmdbClient ───────────→ TMDB API
```

El objetivo no es hacer una arquitectura excesivamente compleja, sino tener una estructura profesional y explicable.

---

# 10. Docker local

Primer gran milestone:

```bash
docker compose up
```

Debe levantar:

```text
┌─────────────────────────────────────────┐
│              Local Machine              │
│                                         │
│   Angular                               │
│   :4200                                 │
│      │                                  │
│      ▼                                  │
│   .NET API                              │
│   :8080                                 │
│      │                                  │
│      ▼                                  │
│   PostgreSQL                            │
│   :5432                                 │
│                                         │
└─────────────────────────────────────────┘
          │
          │ HTTPS
          ▼
        TMDB
```

Prácticas:

- Dockerfile backend.
- Dockerfile frontend.
- Multi-stage builds.
- Networks.
- Volumes.
- Environment variables.
- Health checks.
- `.dockerignore`.
- Docker Compose.

---

# 11. Gestión de configuración y secretos

Archivo inicial:

```text
.env.example
```

Ejemplo:

```text
POSTGRES_DB=movieops
POSTGRES_USER=movieops
POSTGRES_PASSWORD=

TMDB_API_KEY=

ASPNETCORE_ENVIRONMENT=Development
```

El archivo real:

```text
.env
```

irá en:

```text
.gitignore
```

Evolución del laboratorio:

```text
.env
 ↓
GitHub Secrets
 ↓
Cloud Secret Manager / Key Vault
 ↓
Kubernetes Secrets
```

Principio:

> Ningún secreto debe quedar hardcodeado en Git.

---

# 12. Testing

Se incorporarán:

- Unit Tests.
- Integration Tests.
- API Tests.
- Frontend Tests.
- Coverage.
- Smoke Tests.
- Health Checks.

Conceptualmente:

```text
Unit Tests
    ↓
Integration Tests
    ↓
API Tests
    ↓
Smoke Tests
```

El objetivo es que las pruebas formen parte del pipeline y no sean una actividad manual aparte.

---

# 13. Git como parte del laboratorio

Se practicarán deliberadamente:

- Feature branches.
- Pull Requests.
- Merge.
- Rebase.
- Cherry-pick.
- Tags.
- Releases.
- Branch policies.
- Conflicts.
- Revert.
- Rollback.

Se provocarán conflictos intencionalmente para practicar resolución.

---

# 14. Filosofía del CI

El CI no será un único YAML enorme.

Se aplicarán patrones de diseño de pipeline.

---

# 15. Patrón: Pipeline as Code

Todo comportamiento del pipeline estará en Git.

```text
Developer
    ↓
Pull Request
    ↓
.github/workflows/ci.yml
```

Beneficios:

- Versionado.
- Review.
- Historial.
- Auditoría.
- Rollback.

---

# 16. Patrón: Fail Fast

Las validaciones rápidas y baratas se ejecutarán antes que las costosas.

```text
Checkout
   ↓
Lint / Format
   ↓
Restore
   ↓
Compile
   ↓
Unit Tests
   ↓
Integration Tests
   ↓
Security Scan
   ↓
Docker Build
```

Idea:

```text
barato/rápido
      ↓
      ↓
      ↓
caro/lento
```

---

# 17. Patrón: Fan-Out / Fan-In

Backend y frontend correrán en paralelo.

```text
                  CI
                   │
          ┌────────┴────────┐
          ▼                 ▼
      Backend CI        Frontend CI
          │                 │
          ▼                 ▼
      Tests             Tests
          │                 │
          └────────┬────────┘
                   ▼
             Quality Gate
                   │
                   ▼
              Docker Build
```

Esto permitirá practicar paralelización y reducción de tiempo total del pipeline.

---

# 18. Patrón: Reusable Pipeline

Se evitará duplicar lógica.

Ejemplo:

```text
.github/actions/

dotnet-build/
angular-build/
docker-build/
security-scan/
```

Principios asociados:

- DRY.
- Separation of Concerns.
- Composition.
- Reusabilidad.

---

# 19. Patrón: Quality Gate

No todo build será promovido.

```text
Build
 ↓
Tests
 ↓
Coverage
 ↓
Security
 ↓
Quality Gate
 ↓
Artifact
```

Ejemplo:

```text
Tests        ✅
Coverage     ✅
SAST         ✅
Dependencies ✅
Build        ✅

        ↓

Artifact approved
```

Si falla algo:

```text
             ❌
             │
             ▼
       Pipeline stopped
```

---

# 20. Patrón: Immutable Artifact

No se construirá una versión distinta para cada ambiente.

Incorrecto:

```text
build DEV
build QA
build PROD
```

Correcto:

```text
             CI
             │
             ▼
       Docker image
   movieops-api:1.4.7
             │
        ┌────┼─────┐
        ▼    ▼     ▼
       DEV  STG   PROD
```

Principio:

> **Build once, deploy many.**

---

# 21. Patrón: Artifact Versioning

Cada artefacto podrá rastrearse a un commit.

Ejemplos:

```text
movieops-api:1.3.0
movieops-api:sha-a843df2
```

Trazabilidad:

```text
Git commit
     │
     ▼
a843df2
     │
     ▼
Docker image
movieops-api:sha-a843df2
     │
     ▼
Production
```

Pregunta de entrevista que debemos poder responder:

> ¿Qué commit está ejecutándose actualmente en producción?

---

# 22. Patrón: Shift Left Security

La seguridad se ejecutará desde CI.

```text
Source
  │
  ├── secret scanning
  ├── dependency scanning
  ├── SAST
  ├── container scan
  └── IaC scan
```

Herramientas candidatas:

- Trivy.
- CodeQL.
- Dependabot.
- Checkov.

No se incorporarán todas de golpe. Se añadirán progresivamente.

---

# 23. Pipeline CI objetivo

Backend:

```text
Checkout
   ↓
Restore
   ↓
Build
   ↓
Unit Tests
   ↓
Integration Tests
   ↓
Coverage
   ↓
Security Scan
   ↓
Docker Build
   ↓
Push Image
```

Frontend:

```text
npm ci
   ↓
lint
   ↓
test
   ↓
ng build
   ↓
docker build
   ↓
registry
```

Orquestación:

```text
                       Pull Request
                            │
                            ▼
                          CI
                            │
             ┌──────────────┴─────────────┐
             ▼                            ▼
        Backend CI                   Frontend CI
             │                            │
        unit tests                   unit tests
        integration                   lint
        coverage                       build
             │                            │
             └──────────────┬─────────────┘
                            ▼
                       Security Gate
                            │
                            ▼
                        Docker Build
                            │
                            ▼
                     Container Registry
```

---

# 24. Terraform

Terraform se usará para aprovisionar infraestructura.

**Proveedor inicial: Azure.** Más adelante se replicará la misma plataforma en **AWS**. Para evitar reestructurar todo cuando llegue ese momento, los módulos y ambientes se organizan por proveedor desde el principio — sin escribir abstracciones multi-cloud (`if var.cloud_provider == "azure"`) que compliquen cada cambio sin necesidad real todavía. Esto es una aplicación directa del principio "no sobre-diseñar" (sección 5): se construye bien para Azure hoy, y se agrega `aws/` como implementación paralela cuando corresponda, reutilizando el aprendizaje, no el código.

Estructura:

```text
terraform/
├── modules/
│   ├── azure/
│   │   ├── network/                → Azure VNet, Subnets, NSGs
│   │   ├── postgres/                → Azure Database for PostgreSQL Flexible Server
│   │   ├── container-registry/      → Azure Container Registry (ACR)
│   │   ├── kubernetes/              → AKS
│   │   ├── secrets/                 → Azure Key Vault
│   │   └── monitoring/              → soporte para Prometheus/Grafana self-hosted (ver sección 45)
│   │
│   └── aws/                         # vacío hasta la fase AWS: network/, postgres/ (RDS),
│                                     # container-registry/ (ECR), kubernetes/ (EKS), secrets/ (Secrets Manager)
│
└── environments/
    └── azure/
        ├── dev/
        ├── staging/
        └── production/
        # environments/aws/{dev,staging,production} se agrega en la fase AWS
```

Conceptos:

- `terraform init`
- `terraform fmt`
- `terraform validate`
- `terraform plan`
- `terraform apply`
- `terraform destroy`
- State.
- Remote backend.
- Variables.
- Outputs.
- Modules.
- Environments.

---

# 25. Patrón: Plan Before Apply

La infraestructura no aplicará cambios directamente.

```text
terraform fmt
    ↓
terraform validate
    ↓
security scan
    ↓
terraform plan
    ↓
review / approval
    ↓
terraform apply
```

El plan será revisado antes del cambio real.

---

# 26. Separación CI vs CD

No se construirá un `ci-cd-super-pipeline.yml` con todo mezclado.

Conceptualmente:

```text
CI
│
├── compile
├── test
├── analyze
├── package
└── publish
      │
      ▼
   Artifact
      │
      ▼
CD
│
├── configure
├── deploy
├── validate
├── observe
└── promote
```

Definición:

> CI produce un artefacto confiable.

> CD mueve ese artefacto entre ambientes.

---

# 27. Patrón: Environment Promotion

El mismo artefacto avanzará por ambientes.

```text
CI
 │
 ▼
movieops:1.4.0
 │
 ▼
DEV
 │
 ▼
STAGING
 │
 ▼
PRODUCTION
```

Gates:

```text
DEV
 ↓
Automated Tests
 ↓
STAGING
 ↓
Smoke Tests
 ↓
Approval
 ↓
PRODUCTION
```

---

# 28. Patrón: Externalized Configuration

La imagen Docker será la misma en todos los ambientes.

```text
                 movieops-api:1.4
                        │
              ┌─────────┼───────────┐
              ▼         ▼           ▼
             DEV       STG         PROD
              │         │           │
           config     config      config
```

Variables:

```text
DATABASE_HOST
TMDB_URL
LOG_LEVEL
```

Secretos:

```text
DATABASE_PASSWORD
TMDB_API_KEY
```

Todo se configurará fuera de la imagen.

---

# 29. Patrón: Deployment Pipeline

El CD tendrá:

```text
Artifact
   ↓
Validate
   ↓
Deploy
   ↓
Health Check
   ↓
Smoke Tests
   ↓
Observe
   ↓
Promote
```

Un deployment no será exitoso solo porque Kubernetes acepte el manifiesto.

---

# 30. Patrón: Health Check

Endpoints esperados:

```text
/health
/health/live
/health/ready
```

Pipeline:

```text
Deploy
   ↓
Wait
   ↓
GET /health/ready
   ↓
200 OK?
   │
 ┌─┴─┐
 │   │
YES  NO
 │   │
 ▼   ▼
OK  Rollback
```

Más adelante:

```text
livenessProbe
readinessProbe
```

---

# 31. Patrón: Automatic Rollback

```text
v2
 │
 │ deployment
 ▼
Production
 │
 ❌ health check
 │
 ▼
Rollback
 │
 ▼
v1
```

Se practicarán fallos deliberados para activar rollback.

---

# 32. Blue-Green Deployment

Modelo:

```text
               Load Balancer
                     │
                     ▼
                  BLUE
                  v1.5
```

Nueva versión:

```text
GREEN
v1.6
```

Cambio:

```text
               Load Balancer
                     │
                     ▼
                  GREEN
                  v1.6
```

Rollback:

```text
GREEN ❌
  ↓
switch
  ↓
BLUE ✅
```

---

# 33. Canary Deployment

```text
                 Users
                   │
          ┌────────┴─────────┐
          │                  │
         90%                10%
          │                  │
          ▼                  ▼
          V1                 V2
```

Se observarán:

- Error rate.
- Latency.
- HTTP 5xx.
- CPU.
- Memory.

Progresión:

```text
10%
 ↓
25%
 ↓
50%
 ↓
100%
```

Fallo:

```text
10%
 ↓
errors
 ↓
0%
```

---

# 34. Progressive Delivery

```text
Deploy
  ↓
Release 10%
  ↓
Observe
  ↓
Release 25%
  ↓
Observe
  ↓
Release 50%
  ↓
Observe
  ↓
Release 100%
```

Se conectará directamente deployment con observabilidad.

---

# 35. Kubernetes

Kubernetes llegará después de dominar:

```text
App
 ↓
Docker
 ↓
CI/CD
 ↓
Cloud
 ↓
IaC
 ↓
Monitoring
 ↓
Security
 ↓
Kubernetes
```

Conceptos:

- Deployment.
- Service.
- Ingress.
- ConfigMap.
- Secret.
- ReplicaSet.
- Pod.
- Namespace.
- HPA.
- Liveness Probe.
- Readiness Probe.
- Rolling Update.
- Rollback.
- Resource Requests.
- Resource Limits.

---

# 36. GitOps con Argo CD

Argo CD se implementará después de Kubernetes.

Primero se practicará CD tradicional push-based:

```text
Pipeline
   ↓
kubectl apply
   ↓
Kubernetes
```

Después se evolucionará a GitOps:

```text
GitHub Actions
     │
     │ actualiza versión
     ▼
Git
     │
     ▼
Argo CD
     │
     │ observa Git
     ▼
Kubernetes
```

---

# 37. Patrón: Pull-Based Deployment

Argo CD observará Git.

```text
Git
Desired State

backend:v1.8.0
replicas: 3

        │
        ▼

     Argo CD
        │
        │ compare
        ▼

Kubernetes
Actual State

backend:v1.7.0
replicas: 2
```

Resultado:

```text
OUT OF SYNC
```

Luego:

```text
Git                Kubernetes
v1.8.0      →      v1.8.0
3 replicas  →      3 replicas

SYNCED
HEALTHY
```

---

# 38. Patrón: Git as Single Source of Truth

Git será el estado deseado.

Ejemplo:

```text
Git                     Cluster

replicas: 3             replicas: 10
     │                        │
     └──────── DRIFT ─────────┘
```

Argo CD podrá reconciliar nuevamente:

```text
replicas: 3
```

---

# 39. Drift Detection

Se provocarán modificaciones manuales deliberadas en el cluster para comprobar:

- Detección de drift.
- Estado `OutOfSync`.
- Manual Sync.
- Auto Sync.
- Self Healing.

---

# 40. Terraform y Argo CD

Separación de responsabilidades:

## Terraform

```text
Azure
 │
 ├── Network              (VNet)
 ├── Kubernetes Cluster   (AKS)
 ├── PostgreSQL           (Flexible Server)
 ├── Container Registry   (ACR)
 ├── IAM
 └── Argo CD
```

> La misma responsabilidad se reimplementará en AWS más adelante (VPC, EKS, RDS, ECR) sin cambiar lo que Terraform le entrega a Kubernetes/Argo CD — ver sección 24.

## Argo CD

```text
Kubernetes Applications
 │
 ├── backend
 ├── frontend
 ├── ingress
 ├── configmaps
 └── deployments
```

Modelo:

```text
Terraform
   │
   │ crea infraestructura
   ▼
Kubernetes Cluster
   │
   │ instala
   ▼
Argo CD
   │
   │ despliega aplicaciones
   ▼
MovieOps
```

---

# 41. Flujo GitOps

Ejemplo:

```text
CI
 ↓
Artifact
 ↓
Container Registry
 ↓
Update Git
 ↓
Argo CD
 ↓
Kubernetes
```

CI genera:

```text
movieops-api:1.7.3
```

Git antes:

```yaml
image: movieops-api:1.7.2
```

Git después:

```yaml
image: movieops-api:1.7.3
```

Flujo:

```text
commit
   ↓
pull request
   ↓
merge
   ↓
Argo CD
   ↓
Sync
   ↓
Kubernetes
```

---

# 42. Estrategia de adopción Argo CD

Se decidió implementar Argo CD primero solo en DEV.

Orden:

```text
Kubernetes
    ↓
Argo CD DEV
    ↓
GitOps básico
    ↓
Drift Detection
    ↓
Auto Sync
    ↓
Multi-environment
    ↓
DEV → STG → PROD
```

Razón:

> Aprender primero GitOps y reconciliación sin mezclar desde el comienzo la complejidad de promoción multiambiente.

---

# 43. Argo CD multiambiente

Estructura:

```text
k8s/
├── base/
│   ├── backend/
│   ├── frontend/
│   └── ingress/
│
└── overlays/
    ├── dev/
    ├── staging/
    └── production/
```

```text
argocd/
├── applications/
│   ├── movieops-dev.yaml
│   ├── movieops-staging.yaml
│   └── movieops-production.yaml
│
└── projects/
    └── movieops-project.yaml
```

Promoción:

```text
CI
 │
 ├── Build
 ├── Tests
 ├── Security
 └── Docker Push
       │
       ▼
movieops-api:1.8.0
       │
       ▼
Actualizar DEV en Git
       │
       ▼
Argo CD
       │
       ▼
DEV
```

Después:

```text
DEV
 │
 │ Pull Request
 ▼
STAGING
 │
 │ Approval
 ▼
PRODUCTION
```

Siempre con la misma imagen:

```text
DEV
movieops-api:1.8.0

        ↓

STAGING
movieops-api:1.8.0

        ↓

PRODUCTION
movieops-api:1.8.0
```

---

# 44. Argo Rollouts

Después de Argo CD se incorporará Argo Rollouts.

```text
Argo CD
   │
   ▼
Argo Rollouts
   │
   ├── Blue-Green
   └── Canary
```

Canary:

```text
                   Argo Rollouts

                        │
                ┌───────┴────────┐
                ▼                ▼

             Stable             Canary
              v1.7               v1.8
               │                  │
              90%                10%
               │                  │
               └────────┬─────────┘
                        ▼
                       Users
```

Progresión:

```text
10%
 ↓
metrics OK
 ↓
25%
 ↓
metrics OK
 ↓
50%
 ↓
metrics OK
 ↓
100%
```

Fallo:

```text
Canary
  │
  ▼
5xx > threshold
  │
  ▼
Abort rollout
  │
  ▼
Stable version
```

---

# 45. Observabilidad

Se incorporarán:

- Logs.
- Metrics.
- Traces.
- Health checks.
- Dashboards.
- Alerts.
- OpenTelemetry.

> **Principio: evitar atarse a Azure Monitor.** Dado que la plataforma se reimplementará en AWS más adelante (sección 24), el stack de observabilidad se construye con herramientas **portables entre clouds**, no con el servicio nativo del proveedor:
>
> ```text
> OpenTelemetry (instrumentación)
>        ↓
> Prometheus (metrics, self-hosted en el cluster)
>        ↓
> Grafana (dashboards, self-hosted en el cluster)
> ```
>
> Este stack corre igual sobre AKS que sobre EKS — el mismo Helm chart / manifiesto de Kubernetes, sin reescribir nada al migrar de proveedor. Azure Monitor / Log Analytics queda descartado como backend principal precisamente porque ese trabajo no se trasladaría a AWS.

Métricas a observar:

```text
HTTP Request Duration
HTTP Error Rate
CPU
Memory
DB Connections
TMDB Response Time
TMDB Errors
```

---

# 46. Incident Simulation

No solo se construirán cosas. También se romperán intencionalmente.

Escenarios:

```text
LAB-INCIDENT-01
API no conecta con PostgreSQL

LAB-INCIDENT-02
Secret incorrecto

LAB-INCIDENT-03
Container OOMKilled

LAB-INCIDENT-04
Readiness probe falla

LAB-INCIDENT-05
TMDB devuelve 429

LAB-INCIDENT-06
Pipeline falla por unit tests

LAB-INCIDENT-07
Terraform state bloqueado

LAB-INCIDENT-08
Docker image vulnerable

LAB-INCIDENT-09
Deployment V2 genera HTTP 500

LAB-INCIDENT-10
CPU > 80%
```

Para cada incidente se documentará:

- Síntoma.
- Impacto.
- Hipótesis.
- Evidencia.
- Diagnóstico.
- Root Cause.
- Solución.
- Acción preventiva.

---

# 47. Arquitectura DevOps objetivo final

```text
Developer
   │
   ▼
GitHub
   │
   ▼
GitHub Actions
   │
   ├── Build
   ├── Test
   ├── Scan
   └── Docker Push
          │
          ▼
   Container Registry
          │
          ▼
      GitOps Repo
          │
          ▼
       Argo CD
          │
          ▼
    Argo Rollouts
          │
          ▼
      Kubernetes
          │
    ┌─────┴─────┐
    ▼           ▼
 Backend     Frontend
    │
    ▼
PostgreSQL
    │
    └────→ TMDB
```

---

# 48. Flujo completo del proyecto

```text
Developer
    │
    │ git push
    ▼
GitHub
    │
    ▼
.github/workflows/
    │
    ├── Build Angular
    ├── Build .NET
    ├── Tests
    ├── Security
    │
    ▼
Docker
    │
    ▼
Container Registry
    │
    ▼
Terraform
    │
    ├── Network
    ├── PostgreSQL
    ├── Kubernetes
    └── Monitoring
    │
    ▼
Kubernetes
    │
    ▼
Argo CD
    │
    ▼
Argo Rollouts
    │
    ├── Angular
    └── .NET API
            │
            ├──── PostgreSQL
            │
            └──── TMDB
```

---

# 49. Catálogo de patrones CI/CD

Documento esperado:

```text
docs/pipelines/PIPELINE_PATTERNS.md
```

Checklist:

```text
CI/CD PATTERNS

Pipeline as Code              ✅
Fail Fast                     ✅
Fan-Out / Fan-In              ✅
Reusable Pipeline             ✅
Quality Gates                 ✅
Immutable Artifact            ✅
Artifact Versioning           ✅
Build Once Deploy Many        ✅
Environment Promotion         ✅
Externalized Configuration    ✅
Shift Left Security           ✅
Health Checks                 ✅
Automatic Rollback            ✅
Infrastructure as Code        ✅
Plan Before Apply             ✅
Blue-Green                    ✅
Canary                        ✅
Progressive Delivery          ✅

GITOPS PATTERNS

Git as Source of Truth        ✅
Declarative Deployment        ✅
Pull-based Deployment         ✅
Continuous Reconciliation     ✅
Drift Detection               ✅
Git-based Promotion           ✅
Git-based Rollback            ✅
```

---

# 50. Roadmap oficial

## Sprint 0 — Estructura del repositorio

Crear:

```text
app/
.github/
k8s/
terraform/
argocd/
scripts/
docs/
docker-compose.yml
.gitignore
.env.example
README.md
```

Objetivos:

- Crear repositorio.
- Definir naming.
- Estructura base.
- README inicial.
- Git strategy.
- Convenciones.
- ADR inicial.

---

## Sprint 1 — Backend .NET + PostgreSQL CRUD

Objetivos:

- Crear solución .NET.
- Crear proyectos por capa.
- Configurar EF Core.
- PostgreSQL.
- Migraciones.
- CRUD.
- Swagger.
- Validaciones.
- Error handling.
- Health endpoint inicial.

Resultado:

```text
.NET API
   ↓
PostgreSQL
```

---

## Sprint 2 — Angular

Objetivos:

- Crear frontend.
- Pantalla de listado.
- Crear.
- Editar.
- Eliminar.
- Consultar.
- Servicios Angular.
- Models.
- Routing.
- Forms.
- Error handling básico.

Resultado:

```text
Angular
   ↓
.NET
   ↓
PostgreSQL
```

---

## Sprint 3 — Integración TMDB

Objetivos:

- Configurar API Key.
- TmdbClient.
- Buscar películas.
- Mapear DTOs.
- Guardar selección.
- Timeout.
- Retry.
- Manejo de errores.
- Circuit breaker.
- Rate limit handling.
- Cache.

Resultado:

```text
Angular
   ↓
.NET
   ├── PostgreSQL
   └── TMDB
```

---

## Sprint 4 — Testing

Objetivos:

- Unit Tests.
- Integration Tests.
- API Tests.
- Frontend Tests.
- Coverage.
- TestContainers si aplica.
- Separar pruebas rápidas y lentas.

---

## Sprint 5 — Docker

Objetivos:

- Dockerfile backend.
- Dockerfile frontend.
- Multi-stage builds.
- PostgreSQL container.
- Docker Compose.
- Networks.
- Volumes.
- Health checks.
- `.dockerignore`.

Resultado esperado:

```bash
docker compose up
```

debe levantar todo el producto.

---

## Sprint 6 — CI + patrones

Patrones:

- Pipeline as Code.
- Fail Fast.
- Fan-Out / Fan-In.
- Reusable Pipeline.
- Quality Gate.
- Immutable Artifact.
- Artifact Versioning.
- Shift Left Security.

Objetivos:

- Backend CI.
- Frontend CI.
- Tests.
- Coverage.
- Lint.
- Scans.
- Build images.
- Push registry.

---

## Sprint 7 — Terraform (Azure)

Objetivos:

- Provider `azurerm`.
- Backend remoto.
- State.
- Modules bajo `terraform/modules/azure/`.
- DEV.
- STAGING.
- PROD.
- Network (VNet).
- Registry (ACR).
- PostgreSQL (Flexible Server).
- Kubernetes (AKS).
- Secrets (Key Vault).
- Monitoring (soporte base para Prometheus/Grafana self-hosted, sección 45).

Patrón:

- Plan Before Apply.

> `terraform/modules/aws/` y `terraform/environments/aws/` se agregan en una fase posterior, reimplementando este mismo sprint para AWS sin modificar lo construido para Azure.

---

## Sprint 8 — CD tradicional + patrones

Objetivos:

- Push-based deployment.
- DEV.
- STAGING.
- PROD.
- Environment Promotion.
- Externalized Configuration.
- Health Check.
- Smoke Tests.
- Automatic Rollback.
- Build Once Deploy Many.

Esto permitirá comprender CD clásico antes de GitOps.

---

## Sprint 9 — Kubernetes

Objetivos:

- Deployment.
- Service.
- Ingress.
- Namespace.
- ConfigMap.
- Secret.
- ReplicaSet.
- Probes.
- Requests.
- Limits.
- HPA.
- Rolling deployment.
- Rollback.

---

## Sprint 10 — Argo CD en DEV

Objetivos:

- Instalar Argo CD.
- Crear Project.
- Crear Application.
- Conectar Git.
- Manual Sync.
- Auto Sync.
- Drift Detection.
- Self Healing.
- Git como Source of Truth.

Este sprint será únicamente DEV.

---

## Sprint 11 — GitOps multiambiente

Objetivos:

- Kustomize base.
- Overlays DEV/STG/PROD.
- Application DEV.
- Application STAGING.
- Application PRODUCTION.
- Git-based promotion.
- Pull Request promotion.
- Approval a producción.
- Mismo artefacto en todos los ambientes.

Flujo:

```text
DEV
 ↓
STAGING
 ↓
PRODUCTION
```

---

## Sprint 12 — Argo Rollouts

Objetivos:

- Blue-Green.
- Canary.
- Traffic shifting.
- Progressive Delivery.
- Abort.
- Rollback.
- Métricas de salud.

---

## Sprint 13 — Observabilidad e incidentes

Objetivos:

- Logs.
- Metrics.
- Traces.
- Dashboards.
- Alerts.
- OpenTelemetry.
- Simulación de incidentes.
- Root Cause Analysis.
- Troubleshooting.
- Runbooks.
- Postmortems.

---

# 51. Lista de laboratorios sugeridos

```text
LAB 01 — Crear repositorio y estructura
LAB 02 — CRUD .NET + PostgreSQL
LAB 03 — Angular CRUD
LAB 04 — TMDB integration
LAB 05 — Resiliencia integración externa
LAB 06 — Unit testing
LAB 07 — Integration testing
LAB 08 — Docker Compose
LAB 09 — CI pipeline
LAB 10 — Fail Fast
LAB 11 — Parallel pipelines
LAB 12 — Reusable pipelines
LAB 13 — Security gates
LAB 14 — Docker registry
LAB 15 — Artifact versioning
LAB 16 — Build Once Deploy Many
LAB 17 — Terraform modules
LAB 18 — Terraform environments
LAB 19 — Kubernetes
LAB 20 — DEV deployment
LAB 21 — STG promotion
LAB 22 — Production approval
LAB 23 — Health checks
LAB 24 — Automatic rollback
LAB 25 — Argo CD DEV
LAB 26 — Drift detection
LAB 27 — Auto Sync
LAB 28 — GitOps multiambiente
LAB 29 — Git-based promotion
LAB 30 — Blue-Green
LAB 31 — Canary
LAB 32 — Argo Rollouts
LAB 33 — Monitoring
LAB 34 — OpenTelemetry
LAB 35 — Incident simulation
LAB 36 — Root Cause Analysis
```

---

# 52. Ejemplos de incidentes deliberados

## PostgreSQL caído

```text
API
 ↓
PostgreSQL ❌
```

Investigar:

- Logs.
- Connection string.
- DNS.
- Network.
- Health checks.
- Readiness.

## TMDB lento

```text
API
 ↓
TMDB 10s
```

Investigar:

- Timeout.
- Retry.
- Circuit Breaker.
- Metrics.

## Container OOMKilled

Investigar:

```text
kubectl describe pod
kubectl logs
```

Aprender:

- Requests.
- Limits.
- Memory.
- Kubernetes events.

## Readiness falla

Resultado:

```text
Pod Running
Readiness False
```

Aprender que:

> Running no significa Ready.

## Deployment defectuoso

```text
v1 ✅
 ↓
v2 ❌
 ↓
rollback
 ↓
v1 ✅
```

## Drift

Modificar manualmente:

```text
replicas: 10
```

Git mantiene:

```text
replicas: 3
```

Argo CD debe detectar y reconciliar.

---

# 53. Enfoque para entrevistas

Cada etapa debe producir material explicable usando STAR.

Ejemplo:

## Situation

La API dependía de TMDB.

## Task

Evitar que una caída del proveedor externo dejara inutilizable la aplicación.

## Action

Se implementó:

```text
Timeout
Retry
Circuit breaker
Caching
Health checks
Observability
```

## Result

La aplicación pudo degradarse de forma controlada y se obtuvo visibilidad sobre el estado de la integración.

---

# 54. Preguntas de entrevista que este laboratorio debe ayudarte a responder

Al finalizar deberías poder explicar con experiencia práctica:

- ¿Qué diferencia hay entre CI y CD?
- ¿Qué es Pipeline as Code?
- ¿Qué significa Fail Fast?
- ¿Qué es Fan-Out / Fan-In?
- ¿Por qué modularizar pipelines?
- ¿Qué es un Quality Gate?
- ¿Qué significa Build Once, Deploy Many?
- ¿Qué es un artefacto inmutable?
- ¿Cómo versionar imágenes Docker?
- ¿Cómo manejar secretos?
- ¿Qué significa Shift Left Security?
- ¿Por qué Terraform?
- ¿Cómo organizar módulos Terraform?
- ¿Qué diferencia hay entre `plan` y `apply`?
- ¿Cómo manejar ambientes?
- ¿Qué diferencia hay entre readiness y liveness?
- ¿Qué es rolling deployment?
- ¿Qué es Blue-Green?
- ¿Qué es Canary?
- ¿Qué es Progressive Delivery?
- ¿Cómo implementar rollback?
- ¿Qué diferencia hay entre CD tradicional y GitOps?
- ¿Qué problema resuelve Argo CD?
- ¿Qué significa Git as Source of Truth?
- ¿Qué es drift?
- ¿Qué es reconciliación?
- ¿Qué diferencia hay entre push-based y pull-based CD?
- ¿Qué diferencia hay entre Terraform y Argo CD?
- ¿Qué aporta Argo Rollouts?
- ¿Cómo investigar un OOMKilled?
- ¿Cómo investigar HTTP 500 después de un deploy?
- ¿Cómo monitorear latencia y error rate?
- ¿Cómo diseñar un pipeline seguro?
- ¿Cómo promover una misma imagen por DEV/STG/PROD?

---

# 55. Resultado final esperado

El repositorio deberá mostrar aproximadamente:

```text
MovieOps
Production-grade DevOps Reference Project

Stack:
.NET
Angular
PostgreSQL
Docker
Terraform
Cloud
GitHub Actions
Kubernetes
Kustomize
Argo CD
Argo Rollouts
OpenTelemetry
Security Scanning
Monitoring
```

Checklist final:

```text
✅ CRUD funcional
✅ Integración TMDB
✅ PostgreSQL
✅ Docker Compose
✅ Unit Tests
✅ Integration Tests
✅ CI
✅ CD
✅ Pipeline as Code
✅ Fail Fast
✅ Fan-Out / Fan-In
✅ Reusable Pipelines
✅ Quality Gates
✅ Immutable Artifacts
✅ Build Once Deploy Many
✅ Artifact Versioning
✅ Shift Left Security
✅ Infrastructure as Code
✅ Terraform environments
✅ Kubernetes
✅ Health Checks
✅ Automatic Rollback
✅ Blue-Green
✅ Canary
✅ Progressive Delivery
✅ Argo CD
✅ GitOps
✅ Drift Detection
✅ Git-based Promotion
✅ Argo Rollouts
✅ Observability
✅ Incident Simulations
✅ Architecture Documentation
✅ Troubleshooting Documentation
✅ Interview Stories
```

---

# 56. Principios del laboratorio

1. **Primero el producto.**
2. **Después automatización.**
3. **No aprender cinco herramientas simultáneamente sin comprender la anterior.**
4. **Todo debe quedar versionado.**
5. **Los pipelines también son software.**
6. **La infraestructura también es código.**
7. **Los artefactos deben ser inmutables.**
8. **El mismo artefacto debe viajar por todos los ambientes.**
9. **Git debe convertirse gradualmente en la fuente de verdad.**
10. **Los despliegues deben ser observables.**
11. **Todo sistema debe poder fallar de forma controlada.**
12. **Cada incidente debe convertirse en aprendizaje documentado.**
13. **Cada patrón debe poder explicarse en una entrevista.**
14. **Ningún comando aplicado a un entorno real vive solo en una terminal.** Si se ejecutó contra Azure, el cluster o la base de datos, queda como script en `scripts/` — idempotente, con vista previa y verificación. Lo que no está scripteado, no es reproducible; y lo que no es reproducible, no es infraestructura: es suerte.

---

# 57. Orden final recomendado

```text
SPRINT 0
Estructura del repositorio
        ↓
SPRINT 1
.NET + PostgreSQL CRUD
        ↓
SPRINT 2
Angular
        ↓
SPRINT 3
Integración TMDB
        ↓
SPRINT 4
Testing
        ↓
SPRINT 5
Docker
        ↓
SPRINT 6
CI + patrones
        ↓
SPRINT 7
Terraform
        ↓
SPRINT 8
CD tradicional + patrones
        ↓
SPRINT 9
Kubernetes
        ↓
SPRINT 10
Argo CD DEV
        ↓
SPRINT 11
GitOps DEV → STG → PROD
        ↓
SPRINT 12
Argo Rollouts
Blue-Green / Canary
        ↓
SPRINT 13
Observabilidad + incidentes
```

---

# 58. Meta del proyecto

El objetivo no es poder decir:

> “He usado Docker, Terraform, Kubernetes y Argo CD.”

El objetivo es poder explicar:

> “Construí una aplicación desde cero y diseñé su ciclo de entrega completo. Implementé CI con fail-fast, ejecución paralela, quality gates, artefactos inmutables y security scanning. Provisioné infraestructura con Terraform, desplegué sobre Kubernetes, evolucioné de CD push-based hacia GitOps con Argo CD, implementé promoción DEV/STG/PROD y progressive delivery con Argo Rollouts, y simulé incidentes para practicar observabilidad, troubleshooting y rollback.”

Ese será el verdadero resultado del laboratorio.

---

**Proyecto:** MovieOps  
**Tipo:** DevOps End-to-End Practical Lab  
**Propósito:** Preparación práctica para entrevistas de DevOps Engineer y construcción de un proyecto demostrable en GitHub.
