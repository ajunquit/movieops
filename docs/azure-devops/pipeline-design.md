# Diseño de Azure Pipelines para MovieOps

## Estado

ADOP-2 completado con `12/12 PASS`. Este documento describe el CI versionado en
`azure-pipelines/ci.yml`; se ampliará paso a paso cuando ADOP-3–ADOP-5
incorporen infraestructura y despliegue.

## Principios

1. GitHub continúa siendo la única fuente de código.
2. GitHub Actions permanece como baseline durante la validación de paridad.
3. CI no recibe permisos para modificar Azure.
4. Backend y frontend fallan de forma independiente y convergen en un quality
   gate explícito.
5. Las imágenes se construyen una vez y se transportan como un artifact
   inmutable; CD no las reconstruirá.
6. Todo artifact conserva vínculo con commit y run.

## Flujo ADOP-2

```text
GitHub push/PR hacia main
          │
          ├───────────────┐
          ▼               ▼
 BackendCI             FrontendCI
 restore               npm ci
 format                type-check
 build                 tests
 unit/integration      coverage
 coverage              build
 Trivy                 Trivy
          └───────┬───────┘
                  ▼
             QualityGate
                  │
                  ▼
              BuildImages
                  │
        ┌─────────┴─────────┐
        │ PR                │ main
        ▼                   ▼
 validate only       movieops-images
```

## Stages y jobs

| Stage | Job | Responsabilidad |
|---|---|---|
| `Validate` | `BackendCI` | .NET restore, format, build, unit/integration tests, coverage y scan |
| `Validate` | `FrontendCI` | npm install, type-check, tests, coverage, production build y scan |
| `Validate` | `QualityGate` | Fan-in; solo pasa si ambos jobs anteriores terminan verdes |
| `Package` | `BuildImages` | Construye las dos imágenes desde el commit exacto |

`BackendCI` y `FrontendCI` no tienen dependencia entre sí y Azure DevOps puede
ejecutarlos en paralelo.

## Triggers y cancelación

- `trigger.batch: true` agrupa cambios nuevos de `main` mientras existe un run
  en curso.
- `pr.autoCancel: true` cancela la validación obsoleta cuando se actualiza un
  Pull Request hacia `main`.
- Los triggers viven únicamente en YAML; no deben sobrescribirse desde la UI.

## Tests y cobertura

- Backend publica archivos TRX mediante `PublishTestResults@2`.
- Frontend genera JUnit con el runner Vitest de Angular.
- Ambos generan Cobertura y lo publican mediante
  `PublishCodeCoverageResults@2`.
- Los integration tests utilizan Testcontainers y requieren un Docker daemon.

## Security scanning

Trivy `0.70.0` se ejecuta desde una imagen versionada, igualando el engine por
default de `aquasecurity/trivy-action@v0.36.0` usado en GitHub Actions. Falla
por vulnerabilidades `HIGH` o `CRITICAL` con solución disponible. El scan
analiza las dependencias restauradas y no necesita una service connection
Azure.

## Artifact inmutable

En un push a `main`, `BuildImages` publica `movieops-images`:

| Archivo | Contenido |
|---|---|
| `movieops-api.tar.gz` | Imagen backend exportada con `docker save` |
| `movieops-frontend.tar.gz` | Imagen frontend exportada con `docker save` |
| `manifest.json` | Commit, branch, run, tag e IDs de imagen |
| `SHA256SUMS` | Integridad de imágenes y manifest |

El tag es `sha-<Build.SourceVersion>` con el SHA Git completo. En PR las
imágenes se construyen para validar Dockerfiles, pero no se publica artifact.

ADOP-4 descargará este artifact desde el run CI exacto, verificará los
checksums y publicará las mismas imágenes en ACR sin ejecutar `docker build`.

## Boundary de identidad

| Recurso | MovieOps-CI |
|---|---|
| GitHub App connection | Permitida para checkout y GitHub Checks |
| `sc-movieops-azure-wif` | Prohibida |
| Azure Resource Manager | Sin acceso |
| ACR | Sin acceso durante ADOP-2 |
| AKS | Sin acceso |

El script del paso 06 revoca una autorización WIF accidental y falla si la
service connection está disponible globalmente.

## Gates de validación

ADOP-2 termina únicamente cuando existe evidencia de:

1. Run manual verde sobre `main`.
2. Tests y cobertura visibles en Azure DevOps.
3. Artifact asociado al SHA exacto.
4. PR sano verde en GitHub Actions y Azure Pipelines.
5. PR roto fallando en ambos sin artifact.
6. CI exitoso sin que exista `rg-movieops-dev`.

## ADOP-3 — Genesis

La primera pipeline de infraestructura es manual e independiente:

```text
MovieOps-Genesis
  → confirmación environment/confirm
  → deployment job asociado al Environment dev
  → WIF exclusiva de la pipeline
  → fmt → init → validate → Checkov
  → plan guardado → apply del mismo plan
  → segundo plan sin cambios
```

Genesis no consume el artifact CI y no despliega aplicaciones. Su única
responsabilidad es crear la infraestructura Terraform reproducible. La pipeline
Apocalipsis se diseñará como una subtask posterior.
