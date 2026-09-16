# ADOP-0 — Baseline y matriz de paridad

## Estado

Completado. La baseline GitHub Actions fue capturada el 16 de septiembre de
2026, Apocalipsis quedó validado de extremo a extremo y se confirmó acceso a la
organización Azure DevOps `ajunquit`. ADOP-1 puede iniciar el bootstrap.

## Boundary de la comparación

La paridad termina en el mismo punto funcional ya probado con GitHub Actions:

```text
GitHub commit/PR
  → CI
  → artefacto inmutable sha-<commit>
  → Terraform manual create/update
  → CD push-based sobre AKS
  → rollout + smoke test
  → Terraform manual destroy
```

No forman parte de esta matriz Argo CD, Argo Rollouts, AWS, OpenTelemetry,
Prometheus/Grafana ni ambientes reales de staging/production.

## Nombres acordados

| Componente | Nombre |
|---|---|
| Azure DevOps Organization | `https://dev.azure.com/ajunquit` |
| Azure DevOps Project | `MovieOps` |
| Método de bootstrap | Scripts idempotentes; portal como fallback |
| Repositorio | `github.com/ajunquit/movieops` |
| GitHub connection | Azure Pipelines GitHub App, limitada a `movieops` |
| CI pipeline | `MovieOps-CI` |
| Genesis pipeline | `MovieOps-Genesis` |
| CD pipeline | `MovieOps-CD` |
| Apocalipsis pipeline | `MovieOps-Apocalipsis` |
| ARM service connection | `sc-movieops-azure-wif` |
| Environments | `dev`, `staging`, `production` |
| Pipeline artifact | `movieops-images` |
| Tag inmutable | `sha-$(Build.SourceVersion)` |

La service connection no se autorizará globalmente. Cada pipeline que la
necesite deberá recibir permiso explícito.

## Retención decidida

Azure DevOps aplica la retención de pipelines en Project Settings, no mediante
reglas YAML por pipeline. Para este laboratorio se configurará:

| Dato | Retención |
|---|---:|
| Runs y logs generales | 30 días |
| Artifacts, símbolos y attachments | 30 días |
| Runs de Pull Request | 14 días |
| Runs recientes conservados por pipeline | 3 |
| Evidencia final Genesis/CD/Apocalipsis | Retención indefinida hasta cerrar ADOP-7 |

La evidencia final se conservará marcando los runs correspondientes o creando
una retention lease. Un Terraform plan guardado no se publicará como artefacto:
se aplica dentro del mismo run para impedir que un plan obsoleto cruce
ejecuciones.

Referencia: [Azure Pipelines retention policies](https://learn.microsoft.com/en-us/azure/devops/pipelines/policies/retention?view=azure-devops).

## Inventario de la baseline GitHub Actions

| Workflow | Trigger actual | Función que Azure Pipelines debe reproducir |
|---|---|---|
| `ci.yml` | Push/PR a `main` | Fan-out backend/frontend, quality gate e imágenes |
| `backend-ci.yml` | `workflow_call` | Restore, format, build, unit/integration tests y scan |
| `frontend-ci.yml` | `workflow_call` | Install, typecheck, tests, build y scan |
| `docker-build.yml` | `workflow_call` | Build paralelo y publicación SHA desde `main` |
| `codeql.yml` | Push/PR a `main` + schedule | SAST |
| `genesis.yml` | Manual | Terraform fmt/init/validate/scan/plan/apply |
| `cd-dev.yml` | Manual | Entrada de despliegue dev |
| `deploy.yml` | `workflow_call` | Promoción, secretos, AKS, gates y rollback |
| `apocalipsis.yml` | Manual | Plan/apply destroy y verificación de ausencia del RG |

`cd-staging.yml` y `cd-production.yml` existen como entradas futuras, pero no
son evidencia de ambientes implementados.

## Evidencia congelada

| Capacidad | Run GitHub | Commit | Duración | Resultado observado |
|---|---|---|---:|---|
| CI completo | [35158019216](https://github.com/ajunquit/movieops/actions/runs/35158019216) | `006786e` | 2m08s | Backend/frontend paralelos, quality gate e imágenes verdes |
| Genesis `dev` | [35152325541](https://github.com/ajunquit/movieops/actions/runs/35152325541) | `ad8de0f` | 1m29s | Plan y apply completados mediante OIDC |
| CD `dev` | [35152984204](https://github.com/ajunquit/movieops/actions/runs/35152984204) | `ad8de0f` | 1m05s | Promoción sin rebuild, rollout y smoke test verdes |
| Apocalipsis `dev` | [35158781637](https://github.com/ajunquit/movieops/actions/runs/35158781637) | `39fd4ca` | 2m01s | Resource Group eliminado y ausencia confirmada |

Los tiempos son referencias, no SLOs. La comparación Azure DevOps debe capturar
el mismo desglose de jobs y no limitarse a comparar la duración total.

## Matriz operativa

| Capacidad | Evidencia GitHub | Azure DevOps objetivo | Evidencia de aceptación | Estado ADO |
|---|---|---|---|---|
| CI en cambios de GitHub | Check `CI` en push/PR | Triggers CI/PR mediante GitHub App | Check de Azure Pipelines en el commit y PR | ⏳ |
| Backend/frontend paralelos | Jobs reutilizables paralelos | Jobs basados en templates | Timeline muestra solapamiento | ⏳ |
| Quality gate | Job posterior a ambos CI | Job `dependsOn` con condición de éxito | Un fallo impide imágenes/artifact | ⏳ |
| Tests y coverage | .NET, Angular y Testcontainers | Publicación nativa de resultados/coverage | Tests visibles en Azure DevOps | ⏳ |
| Security scanning | Dependency scan, Trivy, CodeQL | Controles equivalentes y resultados trazables | Hallazgo bloqueante falla CI | ⏳ |
| Artefacto inmutable | GHCR `sha-<commit>` | Pipeline Artifact `movieops-images` | Nombre/tag contiene SHA completo | ⏳ |
| CI sin ambiente activo | GHCR persiste fuera de `dev` | Pipeline Artifact no depende de ACR | CI verde con `dev` destruido | ⏳ |
| Terraform create/update | Genesis manual | `MovieOps-Genesis` manual | Plan aplicado y segundo plan sin cambios | ⏳ |
| Terraform destroy | Apocalipsis manual | `MovieOps-Apocalipsis` manual | `rg-movieops-dev` ausente; tfstate presente | ⏳ |
| Identidad sin secreto | GitHub OIDC | ARM service connection WIF | Diagnóstico de identidad sin client secret | ⏳ |
| Promote without rebuild | GHCR → ACR import | Artifact → Docker load/tag/push ACR | Digest/contenido y SHA trazables | ⏳ |
| Key Vault → K8s Secret | Lectura runtime | AzureCLI task con WIF | Valores ausentes de logs | ⏳ |
| AKS rollout gate | `kubectl rollout status` | Mismo gate con deadlines | Réplicas esperadas disponibles | ⏳ |
| Smoke test | Frontend y `/api/movies` HTTP 200 | Mismos endpoints y presupuesto temporal | HTTP 200 registrado | ⏳ |
| Rollback | Código presente; prueba previa pendiente | Undo hacia revisión sana | Fallo deliberado recuperado | ⏳ |
| Environment history | GitHub Environment | Deployment job a ADO Environment | Commit/run/deploy relacionados | ⏳ |
| Production approval | GitHub Environment | Approval/check fuera del YAML | Ejecución espera aprobador | ⏳ |

## Criterio de cierre de ADOP-0

- [x] Baseline y boundary versionados.
- [x] Workflows y triggers inventariados.
- [x] Runs verdes de CI, Genesis, CD y Apocalipsis registrados.
- [x] Nombres de proyecto, pipelines, service connection y environments fijados.
- [x] Política de retención decidida.
- [x] Organización Azure DevOps confirmada y acceso verificado mediante Azure DevOps CLI.
