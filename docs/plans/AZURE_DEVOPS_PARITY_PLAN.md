# MovieOps — Plan de paridad CI/CD con Azure DevOps

## Estado

En ejecución. **ADOP-0 y ADOP-1 están completados; ADOP-2 está en
implementación**, después del Sprint 9 validado en Azure y antes del Sprint 10 (Argo CD). La baseline y
matriz operativa están en
[`docs/azure-devops/parity-matrix.md`](../azure-devops/parity-matrix.md).

Este plan es complementario. El documento rector continúa siendo
[`MovieOps_DevOps_Plan.md`](../../MovieOps_DevOps_Plan.md); no se renumeran ni
se reemplazan sus sprints.

La capacidad que debe reproducirse está inventariada en
[`GITHUB_ACTIONS_AZURE_IMPLEMENTATION_PLAN.md`](GITHUB_ACTIONS_AZURE_IMPLEMENTATION_PLAN.md).
Ese documento es la baseline funcional; esta paridad no se evaluará contra
suposiciones ni contra objetivos todavía no implementados.

La secuencia operativa pantalla por pantalla está en
[`docs/azure-devops/setup.md`](../azure-devops/setup.md).
La estrategia predeterminada de bootstrap automatizado, sus límites e
idempotencia están en
[`docs/azure-devops/automation.md`](../azure-devops/automation.md).

## Objetivo

Reimplementar hasta el mismo punto alcanzado con GitHub Actions —CI,
provisionamiento Terraform, CD push-based sobre AKS, health gates, smoke test y
destroy— usando **Azure Pipelines**, mientras el código continúa alojado en
GitHub.

Al terminar existirán dos implementaciones comparables del mismo ciclo:

```text
GitHub repository
   ├── GitHub Actions  ──► Microsoft Azure
   └── Azure Pipelines ──► Microsoft Azure
```

Después se diseñará un plan separado para repetir la plataforma en AWS. Solo
cuando ambas expansiones estén completas se retomarán los Sprints 10–13:
Argo CD, GitOps multiambiente, Argo Rollouts, OpenTelemetry, observabilidad e
incidentes.

## Qué significa “Azure DevOps” en este track

Se usará:

- Azure DevOps Organization y Project.
- Azure Pipelines YAML.
- Azure DevOps Environments para historial, checks y aprobaciones.
- Pipeline Artifacts para transportar el artefacto inmutable entre CI y CD.
- Service connections con Workload Identity Federation.

No se usará:

- Azure Repos: GitHub permanece como única fuente del código.
- Classic Pipelines/Releases: todo será YAML versionado.
- Client secrets o credenciales de larga duración.
- Duplicación permanente de la infraestructura `dev`.

## Principios que se conservan del plan rector

1. **Pipeline as Code:** los YAML viven en este repositorio.
2. **Fail Fast:** validaciones baratas antes de builds y despliegues.
3. **Fan-Out/Fan-In:** backend y frontend en paralelo, seguidos por un quality
   gate.
4. **Immutable Artifact:** CD consume exactamente lo que produjo el CI verde.
5. **Build Once, Deploy Many:** ninguna etapa de CD recompila imágenes.
6. **Plan Before Apply:** Terraform siempre genera un plan antes de aplicar.
7. **Separación CI/infra/CD:** desplegar una aplicación no reevalúa Terraform.
8. **No long-lived secrets:** federación de identidad para Azure.
9. **Safety gates:** crear y destruir infraestructura continúa siendo manual.
10. **Todo cambio real es reproducible:** bootstrap y permisos quedan
    scripteados en `scripts/azure-devops/` cuando la API lo permita.

## Decisiones de arquitectura

### 1. GitHub sigue siendo el repositorio

Azure Pipelines se conectará a `ajunquit/movieops` mediante la Azure Pipelines
GitHub App. Los triggers YAML reaccionarán a commits y Pull Requests de GitHub;
no habrá sincronización ni mirror hacia Azure Repos.

La conexión permite que Azure Pipelines publique checks sobre los commits y
Pull Requests de GitHub. Al completar la paridad, ese check podrá agregarse a
las reglas de protección de `main`.

### 2. GitHub Actions no se elimina durante la migración

Los workflows actuales son la implementación de referencia. Permanecerán
intactos hasta que la matriz de paridad esté completamente verde.

Para evitar dos controladores modificando el mismo AKS o state al mismo tiempo:

- Durante la validación Azure DevOps será el único orquestador que ejecutará
  `Genesis`, CD y `Apocalipsis` sobre `dev`.
- GitHub Actions podrá seguir ejecutando CI, pero sus workflows mutantes no se
  dispararán en paralelo.
- No se crearán dos ambientes `dev` simultáneos; se reutilizarán nombres y state
  de forma secuencial para controlar costos.

### 3. Identidad separada y sin secretos

Azure DevOps tendrá una Azure Resource Manager service connection propia:

```text
sc-movieops-azure-wif
```

Usará Workload Identity Federation, la opción recomendada por Microsoft para
service connections nuevas. La identidad será distinta de
`github-movieops-terraform` para mantener auditoría, revocación y blast radius
separados.

Roles iniciales esperados:

| Scope | Rol | Motivo |
|---|---|---|
| Suscripción del lab | Contributor | Crear y destruir recursos |
| Suscripción del lab | Role Based Access Control Administrator | Crear los role assignments definidos por Terraform |
| ACR de `dev` | AcrPush | Publicar el artefacto de CI sin usar password del registry |

La service connection se autorizará pipeline por pipeline; no se activará
“Grant access permission to all pipelines”.

### 4. Terraform no dependerá de “quien lo ejecuta”

Actualmente `data.azurerm_client_config.current.object_id` cambia según ejecute
GitHub Actions, Azure Pipelines o una persona. Alternar plataformas puede
reemplazar el role assignment de Key Vault.

Antes de probar `Genesis` en Azure DevOps se hará explícita la lista de
principales de automatización autorizados. El desired state debe ser estable e
independiente del runner que calcula el plan.

Dirección propuesta:

```hcl
automation_principal_object_ids = {
  github_actions = "<object-id>"
  azure_devops   = "<object-id>"
}
```

El módulo de secretos creará asignaciones deterministas con `for_each`. Los IDs
son identificadores públicos, no secretos.

### 5. El artefacto de CI no dependerá de que `dev` exista

ACR pertenece al ambiente y desaparece con `Apocalipsis`. Por tanto, el CI no
debe requerir que ACR esté encendido.

La primera implementación usará Azure Pipeline Artifacts:

```text
CI
 ├── docker build movieops-api:sha-<commit>
 ├── docker build movieops-frontend:sha-<commit>
 ├── exportar imágenes como artefacto OCI/Docker
 └── PublishPipelineArtifact (solo commits promovibles de main)

CD
 ├── descarga el artefacto de esa ejecución de CI
 ├── importa/carga la misma imagen, sin rebuild
 ├── autentica contra ACR con WIF
 └── push a ACR con el mismo SHA
```

Esto mantiene CI operativo mientras `dev` está destruido y evita introducir un
GitHub PAT únicamente para escribir en GHCR desde Azure Pipelines. En una
iteración posterior se comparará este transporte con un registry central
persistente.

### 6. Política de triggers

“Cada cambio” se implementará con semántica segura:

| Evento en GitHub | Azure Pipeline CI | Azure Pipeline CD |
|---|---|---|
| Push a cualquier branch | Ejecuta validaciones | No despliega |
| Crear/actualizar PR hacia `main` | Ejecuta y publica check | No despliega |
| Push/merge a `main` | Ejecuta CI y publica artefacto | Se dispara después de CI verde |
| Ejecución fallida de CI | Falla el check | No se dispara |
| Ambiente `dev` destruido | CI sigue funcionando | Preflight informa “environment offline” y no crea infraestructura |

CD nunca ejecutará `terraform apply`. La infraestructura solo se crea mediante
el pipeline manual `Genesis`.

### 7. CD comienza push-based

Para alcanzar paridad con el estado actual, Azure Pipelines obtendrá
credenciales de AKS y aplicará Kustomize/kubectl. No se introducirá Argo CD en
este track, porque eso mezclaría la comparación de plataformas con el Sprint 10.

## Estructura objetivo

```text
azure-pipelines/
├── ci.yml
├── cd.yml
├── genesis.yml
├── apocalipsis.yml
└── templates/
    ├── backend-ci.yml
    ├── frontend-ci.yml
    ├── container-build.yml
    ├── terraform-plan.yml
    └── deploy-aks.yml

scripts/
└── azure-devops/
    ├── 00-bootstrap-project/
    ├── 01-service-connection-wif/
    ├── 02-configure-environments/
    ├── 03-configure-pipelines/
    ├── 04-configure-retention/
    ├── 05-verify-bootstrap/
    └── 99-full-bootstrap/

docs/
└── azure-devops/
    ├── setup.md
    ├── pipeline-design.md
    ├── operations.md
    └── troubleshooting.md
```

Los nombres definitivos pueden ajustarse durante el bootstrap, pero la
separación entre pipelines principales y templates reutilizables es obligatoria.

## Roadmap del track Azure DevOps

### ADOP-0 — Baseline y matriz de paridad ✅

Objetivo: congelar qué significa “llegar al mismo punto”.

Entregables:

- Registrar los workflows GitHub actuales y sus triggers.
- Capturar tiempos y resultados de una ejecución verde.
- Definir nombres de Organization, Project, pipelines y service connections.
- Crear una matriz de capacidades con evidencia requerida.
- Decidir retención de Pipeline Artifacts y logs.

Criterio de salida:

- La matriz de paridad está versionada y no contiene requisitos de Argo CD,
  AWS u observabilidad futura.

Estado final: workflows, triggers, tiempos, resultados, nombres y retención
están registrados en
[`docs/azure-devops/parity-matrix.md`](../azure-devops/parity-matrix.md). La
organización `https://dev.azure.com/ajunquit` fue confirmada mediante Azure
DevOps CLI.

### ADOP-1 — Bootstrap seguro de Azure DevOps ✅

Objetivo: conectar Azure DevOps con GitHub y Azure sin secretos persistentes.

Entregables:

- Azure DevOps Project `MovieOps`.
- Instalación/autorización de Azure Pipelines GitHub App solo para el repo.
- Service connection Azure Resource Manager con WIF.
- Environments `dev`, `staging`, `production`.
- Approval/check administrativo para `production`.
- Branch control para aceptar despliegues desde `refs/heads/main`.
- Scripts idempotentes de bootstrap y verificación.
- Documento de pasos que deban permanecer manuales por consentimiento/UI.
- Orquestador reanudable que se detiene en el consentimiento GitHub App y
  continúa sin duplicar recursos.

Criterio de salida:

- Un pipeline de diagnóstico obtiene identidad Azure sin client secret y puede
  leer subscription/resource groups, pero no modifica infraestructura.

Estado final: `MovieOps-Diagnostic` run `59` terminó verde en `main`; la
auditoría read-only validó `21/21` controles sin fallos. Los pasos `00–05` y el
orquestador reanudable `99-full-bootstrap` quedaron implementados y
documentados.

### ADOP-2 — CI parity

Objetivo: reproducir el pipeline de CI en Azure Pipelines.

Estado actual: `MovieOps-CI` ID `9` registrado. Runs `60` y `61` terminaron
verdes en `main`, con tests, cobertura y artifact `movieops-images`; la prueba
también pasó sin `rg-movieops-dev`. Quedan pendientes los escenarios de PR sano
y PR deliberadamente roto.

Entregables:

- `trigger` para pushes y `pr` hacia `main` desde GitHub.
- Backend y frontend en jobs paralelos.
- Restore/install, format/lint, build y tests.
- Publicación de resultados de tests y coverage en Azure DevOps.
- Security scanning equivalente.
- Quality gate fan-in.
- Build de las dos imágenes con tag `sha-<commit>`.
- En `main`, publicación del artefacto inmutable para CD.
- Cancelación de runs obsoletos cuando se actualiza un PR.

Criterio de salida:

- Un PR roto falla tanto en GitHub como en Azure Pipelines.
- Un PR sano deja un check verde en GitHub.
- Un merge a `main` produce un artefacto trazable al mismo commit.

### ADOP-3 — Terraform parity: Genesis y Apocalipsis

Objetivo: ejecutar el ciclo de infraestructura desde Azure Pipelines.

Entregables:

- `genesis.yml` con `trigger: none`, parámetros environment/confirm y
  `fmt → init → validate → Checkov → plan → apply`.
- `apocalipsis.yml` con `trigger: none`, confirmación y
  `plan -destroy → apply saved plan`.
- Estado remoto existente reutilizado, con keys por ambiente.
- Identidades de automatización explícitas y sin drift según el ejecutor.
- Roles bootstrap de la identidad Azure DevOps automatizados/verificados.
- Logs que no exponen valores sensibles.

Criterio de salida:

- Genesis crea `dev` desde cero.
- Un segundo plan es idempotente.
- Apocalipsis elimina `rg-movieops-dev` y conserva `rg-movieops-tfstate`.

### ADOP-4 — Artifact handoff y publicación en ACR

Objetivo: probar Build Once, Deploy Many entre dos pipelines Azure DevOps.

Entregables:

- Pipeline resource que enlaza CD con la ejecución CI exacta.
- Descarga del Pipeline Artifact sin checkout de otro commit.
- Carga y push de las imágenes hacia ACR con el mismo tag SHA.
- Verificación de metadata/digest o contenido antes y después del transporte.
- Preflight que detecta si `dev` está apagado y termina sin intentar crearlo.

Criterio de salida:

- Los logs demuestran qué CI run y commit produjeron la imagen desplegada.
- CD no contiene ningún `docker build`.

### ADOP-5 — CD parity sobre AKS

Objetivo: reproducir el despliegue push-based validado con GitHub Actions.

Entregables:

- Pipeline CD disparado por CI verde en `main`.
- Deployment job asociado al Azure DevOps Environment `dev`.
- Lectura de secretos desde Key Vault.
- Creación/actualización del Kubernetes Secret.
- Kustomize con tags inmutables.
- `kubectl apply`, rollout gates y smoke test con deadlines.
- Rollback cuando existe una revisión anterior.
- Evidencia de frontend y `/api/movies` respondiendo HTTP 200.

Criterio de salida:

- Backend y frontend alcanzan sus réplicas esperadas.
- El Ingress público funciona.
- El historial del Azure DevOps Environment vincula commit, pipeline y deploy.

### ADOP-6 — Fallos controlados y equivalencia operacional

Objetivo: demostrar comportamiento, no solo happy path.

Casos mínimos:

- Test unitario roto: CI bloquea build/publish.
- Dockerfile roto: falla antes de publicar artefacto promovible.
- Tag inexistente: CD falla sin modificar el deployment sano.
- Readiness defectuosa: rollout gate bloquea promoción.
- Segundo deployment defectuoso: rollback vuelve a la revisión previa.
- Confirmación incorrecta: Genesis/Apocalipsis abortan antes de Azure.
- `dev` destruido: CI pasa y CD informa environment offline sin provisionar.

Criterio de salida:

- Cada caso tiene evidencia y una entrada de troubleshooting si descubre un
  fallo orgánico nuevo.

### ADOP-7 — Comparación y cierre

Objetivo: cerrar el ejercicio con una comparación defendible en entrevista.

Entregables:

- Comparativa GitHub Actions vs Azure Pipelines:
  - sintaxis y reutilización;
  - identidad y service connections;
  - approvals/environments;
  - artefactos y trazabilidad;
  - experiencia de diagnóstico;
  - costos y límites;
  - portabilidad.
- Runbook de operación Azure DevOps.
- ADR de convivencia o plataforma preferida para cada escenario.
- Actualización de `docs/ci-cd.md` con ambas implementaciones.
- Decisión explícita sobre qué pipelines quedan activos para evitar dobles
  despliegues.

Criterio de salida:

- Matriz de paridad completa.
- Ninguna funcionalidad del hito actual existe solo en GitHub Actions.
- El siguiente trabajo autorizado es el plan de paridad AWS.

## Matriz de paridad requerida

| Capacidad existente | GitHub Actions | Azure DevOps objetivo | Evidencia |
|---|---|---|---|
| CI en cambios de GitHub | `ci.yml` | `azure-pipelines/ci.yml` | Check en commit/PR |
| Backend/frontend paralelos | Reusable workflows | Jobs/templates | Timeline del run |
| Quality gate | Job fan-in | Stage/job `dependsOn` | Build bloqueado ante fallo |
| Artefacto por SHA | GHCR | Pipeline Artifact | Commit y tag coinciden |
| IaC create/update | `genesis.yml` | Pipeline Genesis manual | Plan/apply verde |
| IaC destroy | `apocalipsis.yml` | Pipeline Apocalipsis manual | RG eliminado, state conservado |
| Identidad sin secreto | GitHub OIDC | ARM service connection WIF | Sin client secret |
| Promote without rebuild | GHCR → ACR import | Artifact → ACR push | CD sin build |
| Key Vault → K8s Secret | `deploy.yml` | Deployment template | Secret creado sin log de valores |
| AKS rollout gate | `kubectl rollout status` | Mismo gate | Réplicas disponibles |
| Smoke test | Ingress HTTP | Mismo endpoint/deadlines | HTTP 200 |
| Rollback | `kubectl rollout undo` | Estrategia equivalente | Revisión anterior restaurada |
| Environment history | GitHub Environment | Azure DevOps Environment | Deployment registrado |
| Production approval | GitHub Environment | Approval/check externo al YAML | Aprobador requerido |

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Dos pipelines despliegan el mismo commit simultáneamente | Un solo orquestador mutante activo durante la validación |
| CI depende de un ACR destruible | Pipeline Artifact persistente como handoff |
| Alternar identidades genera drift de Key Vault | Principales explícitos en Terraform |
| Service connection demasiado amplia | WIF, autorización por pipeline y posterior reducción de scope |
| “Cada commit” provoca infraestructura con costo | Genesis/Apocalipsis permanecen manuales |
| PR despliega código no mergeado | CD solo consume CI verde de `main` |
| Doble ejecución CI en push + PR | Medir y ajustar triggers durante ADOP-2 sin perder el required check |
| Terraform y CD mezclados | Pipelines separados y sin `terraform apply` dentro de CD |
| Introducir GitOps antes de tiempo | Argo CD queda fuera de este track |

## Definition of Done global

El track termina cuando:

- Un cambio en GitHub aparece automáticamente en Azure Pipelines.
- PR y `main` tienen checks de CI reproducibles.
- Un merge verde a `main` puede desplegarse automáticamente en `dev` cuando el
  ambiente está encendido.
- Genesis y Apocalipsis funcionan manualmente desde Azure Pipelines.
- No existen secretos de Azure guardados en variables de pipeline.
- La aplicación responde por Ingress y su commit es trazable hasta CI.
- Se validó al menos un rollback real con una revisión previa.
- La matriz de paridad está completa y documentada.
- GitHub Actions continúa disponible como baseline hasta una decisión explícita.

## Fuera de alcance

- Migrar el repositorio a Azure Repos.
- Argo CD y reconciliación pull-based.
- Argo Rollouts, blue-green o canary.
- OpenTelemetry, Prometheus y Grafana.
- Reimplementación AWS.
- STAGING/PRODUCTION reales antes de validar completamente DEV.

Esos temas mantienen su lugar en el plan rector o tendrán un plan de expansión
propio.

## Referencias oficiales

- [Build GitHub repositories with Azure Pipelines](https://learn.microsoft.com/en-us/azure/devops/pipelines/repos/github?view=azure-devops)
- [Azure Resource Manager service connections with WIF](https://learn.microsoft.com/en-us/azure/devops/pipelines/library/connect-to-azure?view=azure-devops)
- [Pipeline completion triggers](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/resources-pipelines-pipeline-trigger?view=azure-pipelines)
- [Azure DevOps Environments](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/environments?view=azure-devops)
- [Approvals and checks](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/approvals?view=azure-devops)
- [Publish Pipeline Artifacts](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/publish-pipeline-artifact-v1?view=azure-pipelines)
