# Runbook paso a paso — GitHub → Azure Pipelines → Azure

## Objetivo

Llegar al mismo punto validado con GitHub Actions sin mover el repositorio de
GitHub y sin introducir todavía Argo CD:

```text
GitHub
  → Azure Pipelines CI
  → Pipeline Artifact inmutable
  → Azure Pipelines Genesis
  → Microsoft Azure / AKS
  → Azure Pipelines CD
  → rollout + smoke test
  → Azure Pipelines Apocalipsis
```

El plan de hitos está en
[`AZURE_DEVOPS_PARITY_PLAN.md`](../plans/AZURE_DEVOPS_PARITY_PLAN.md). Este
documento especifica el orden operativo y qué evidencia debe existir antes de
avanzar.

## Estado inicial

- Repositorio: `https://github.com/ajunquit/movieops`.
- Suscripción Azure y backend remoto Terraform existentes.
- `rg-movieops-dev` destruido; `rg-movieops-tfstate` conservado.
- Baseline GitHub Actions registrada en [`parity-matrix.md`](parity-matrix.md).
- Organización Azure DevOps: `https://dev.azure.com/ajunquit` (acceso validado).
- Project objetivo: `MovieOps`.

## Regla de ejecución

Completar los pasos en orden. No activar CD automático hasta que CI, WIF,
Genesis y el transporte de artefactos estén validados por separado. Durante las
pruebas mutantes, ejecutar Genesis/CD/Apocalipsis desde una sola plataforma para
evitar dos escritores sobre el mismo state o AKS.

La ruta predeterminada después de crear la organización es el bootstrap
automatizado descrito en [`automation.md`](automation.md). Los pasos de portal
de este runbook permanecen como explicación, verificación y fallback; no es
necesario repetir manualmente una operación que el bootstrap haya marcado como
`VERIFIED`.

## Resumen de fases

| Orden | Fase | Resultado verificable |
|---:|---|---|
| 1 | Organización y Project | URL del proyecto accesible |
| 2 | Conexión GitHub | Azure Pipelines puede leer `ajunquit/movieops` y publicar checks |
| 3 | Service connection WIF | Pipeline obtiene identidad Azure sin secreto |
| 4 | Environments y controles | `dev`, `staging`, `production`; branch control y approval |
| 5 | CI parity | PR/push ejecuta jobs paralelos y publica resultados |
| 6 | Terraform parity | Genesis crea `dev`; Apocalipsis lo elimina completamente |
| 7 | Artifact handoff | CI entrega imágenes por SHA sin depender de ACR |
| 8 | CD parity | Mismo artefacto llega a AKS sin rebuild |
| 9 | Fallos controlados | Gates y rollback se demuestran realmente |
| 10 | Cierre | Matriz completa y decisión de convivencia documentada |

---

## Paso 1 — Crear o elegir la organización Azure DevOps

Este es el **primer paso manual**. Microsoft no permite automatizar la creación
de una organización; sí permite automatizar su configuración posterior.

1. Abrir [Azure DevOps](https://dev.azure.com/).
2. Iniciar sesión con la cuenta asociada al tenant de la suscripción Azure.
3. Si no existe una organización adecuada, seleccionar **New organization**.
4. Elegir un nombre estable y la geografía de alojamiento.
5. Registrar la URL resultante:

   ```text
   https://dev.azure.com/ajunquit
   ```

6. Confirmar que la cuenta figura como Organization Owner.

No instalar todavía extensiones ni crear credenciales.

Referencia: [Create an organization](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/create-organization?view=azure-devops).

### Evidencia de salida

- [x] URL exacta de la organización registrada.
- [x] Acceso de `ajunquit@hotmail.com` validado mediante Azure DevOps CLI.

## Paso 2 — Crear el Project `MovieOps`

Ruta recomendada: `bootstrap-project.ps1` lo creará de forma idempotente. La
siguiente secuencia es el fallback manual y permite verificar el resultado:

```powershell
./scripts/azure-devops/00-bootstrap-project/bootstrap-project.ps1 -WhatIf
./scripts/azure-devops/00-bootstrap-project/bootstrap-project.ps1
```

En la página principal de la organización:

1. Seleccionar **New project**.
2. Configurar:

   | Campo | Valor |
   |---|---|
   | Project name | `MovieOps` |
   | Visibility | `Private` |
   | Version control | `Git` |
   | Work item process | `Basic` |

3. Crear el proyecto.
4. No importar ni duplicar el repositorio en Azure Repos. El repositorio
   canónico seguirá siendo GitHub.
5. Conservar el nombre exacto del proyecto. Los scripts de bootstrap consultarán
   su Project ID mediante la API; no es necesario copiarlo manualmente.

Referencia: [Create a project](https://learn.microsoft.com/en-us/azure/devops/organizations/projects/create-project?view=azure-devops).

### Evidencia de salida

- [ ] `https://dev.azure.com/<organization>/MovieOps` abre correctamente.
- [ ] El proyecto es privado.
- [ ] GitHub continúa siendo el único repositorio utilizado.

## Paso 3 — Comprobar capacidad de agentes

Antes de crear pipelines:

1. Abrir **Organization settings → Pipelines → Parallel jobs**.
2. Confirmar que existe al menos un Microsoft-hosted parallel job disponible.
3. Registrar el límite mensual y de concurrencia.

Con un único job paralelo, backend y frontend estarán definidos como jobs
paralelos pero Azure los ejecutará de forma secuencial por capacidad. Eso no
cambia el diseño, pero sí los tiempos observados.

### Evidencia de salida

- [ ] Hay capacidad para ejecutar `ubuntu-latest`, o se documentó la solicitud
  necesaria para habilitarla.

## Paso 4 — Conectar Azure Pipelines con GitHub

Este paso se realiza cuando `azure-pipelines/diagnostic.yml` ya exista en el
repositorio; ese archivo se añadirá durante ADOP-1.

1. Ir a **Pipelines → New pipeline**.
2. En **Where is your code?**, elegir **GitHub**.
3. Autorizar/instalar **Azure Pipelines GitHub App**.
4. En GitHub, elegir **Only select repositories** y autorizar únicamente
   `ajunquit/movieops`.
5. Volver a Azure DevOps y elegir el mismo repositorio.
6. Seleccionar **Existing Azure Pipelines YAML file**.
7. Indicar:

   ```text
   Branch: main
   Path: /azure-pipelines/diagnostic.yml
   ```

8. Guardar el pipeline con el nombre `MovieOps-Diagnostic`. No ejecutarlo hasta
   crear la service connection.

La GitHub App es necesaria para que Azure Pipelines trabaje con su propia
identidad y publique GitHub Checks; no usar OAuth ni PAT.

Referencia: [Build GitHub repositories with Azure Pipelines](https://learn.microsoft.com/en-us/azure/devops/pipelines/repos/github?view=azure-devops).

### Evidencia de salida

- [ ] GitHub muestra Azure Pipelines entre las aplicaciones instaladas.
- [ ] La instalación tiene acceso únicamente a `movieops`.
- [ ] Azure DevOps muestra el pipeline apuntando al YAML versionado.

## Paso 5 — Crear la service connection con WIF

Ruta recomendada: `configure-service-connection.ps1` creará la identidad sin
password, la service connection, la federación y los roles en el orden
documentado en [`automation.md`](automation.md). Los pasos siguientes describen
el fallback interactivo:

En **Project settings → Service connections**:

1. Seleccionar **New service connection**.
2. Elegir **Azure Resource Manager**.
3. Elegir **App registration (automatic)**.
4. Elegir **Workload identity federation** como credencial.
5. Seleccionar scope **Subscription** y la suscripción del laboratorio.
6. Nombre: `sc-movieops-azure-wif`.
7. No seleccionar **Grant access permission to all pipelines**.
8. Guardar y registrar:
   - Service connection ID.
   - Client/Application ID.
   - Service principal Object ID.
   - Tenant ID y Subscription ID.

WIF evita client secrets. La autorización de la conexión se concede pipeline
por pipeline. Para la creación automática se requiere capacidad de crear la App
Registration y asignar roles en Azure.

Referencia: [Azure Resource Manager service connection with WIF](https://learn.microsoft.com/en-us/azure/devops/pipelines/library/connect-to-azure?view=azure-devops).

### Roles de bootstrap

La identidad requiere inicialmente:

| Scope | Rol |
|---|---|
| Suscripción del laboratorio | `Contributor` |
| Suscripción del laboratorio | `Role Based Access Control Administrator` |

El segundo rol permite que Terraform cree y elimine sus role assignments. Los
roles data-plane sobre ACR y Key Vault se modelarán explícitamente después de
que esos recursos existan.

### Evidencia de salida

- [ ] La service connection indica Workload Identity Federation.
- [ ] No existe client secret asociado al pipeline.
- [ ] La opción global de autorización permanece desactivada.

## Paso 6 — Crear los Azure DevOps Environments

Ruta recomendada: `configure-environments.ps1` utilizará las APIs públicas. La
UI se usa para verificar el resultado o como fallback:

Ir a **Pipelines → Environments → Create environment** y crear, sin añadir
recursos todavía:

```text
dev
staging
production
```

En cada Environment, abrir **Approvals and checks**:

1. Agregar **Branch control**.
2. Allowed branches: `refs/heads/main`.
3. En `production`, agregar además **Approvals** con el usuario responsable.
4. Impedir self-approval en `production`.

Los checks se administran fuera del YAML para que una modificación del pipeline
no pueda retirarlos.

Referencias: [Environments](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/environments?view=azure-devops) y [Approvals and checks](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/approvals?view=azure-devops).

### Evidencia de salida

- [ ] Existen los tres Environments.
- [ ] `refs/heads/main` es la única rama autorizada para deploy.
- [ ] `production` exige un aprobador externo al YAML.

## Paso 7 — Configurar retención del proyecto

Ruta recomendada: `configure-retention.ps1` aplicará o verificará estos valores
y reportará cualquier acción que la API no exponga de forma pública.

En **Project settings → Pipelines → Settings**, configurar lo decidido en
[`parity-matrix.md`](parity-matrix.md):

| Configuración | Valor |
|---|---:|
| Runs y logs | 30 días |
| Artifacts, symbols y attachments | 30 días |
| Pull Request runs | 14 días |
| Recent runs per pipeline | 3 |

Los runs finales de Genesis, CD y Apocalipsis se marcarán para retención hasta
cerrar ADOP-7.

Referencia: [Retention policies](https://learn.microsoft.com/en-us/azure/devops/pipelines/policies/retention?view=azure-devops).

## Paso 8 — Ejecutar el pipeline de diagnóstico

El pipeline `MovieOps-Diagnostic` deberá:

1. Usar `AzureCLI@2` con `sc-movieops-azure-wif`.
2. Ejecutar únicamente consultas de solo lectura:

   ```bash
   az account show
   az group list --query "[].name"
   ```

3. No ejecutar Terraform ni crear recursos.
4. Autorizar la service connection solo cuando Azure DevOps lo solicite para
   ese pipeline.

### Gate ADOP-1

- [ ] El pipeline termina verde.
- [ ] Los logs muestran tenant/subscription correctos.
- [ ] No se almacenó ni imprimió ningún secreto.
- [ ] Los scripts de bootstrap/verify reproducen la configuración comprobable.

No continuar con CI hasta cerrar este gate.

## Paso 9 — Crear `MovieOps-CI`

Después de versionar `azure-pipelines/ci.yml` y sus templates:

1. Crear otro pipeline desde el mismo repositorio y elegir el YAML existente
   `/azure-pipelines/ci.yml`.
2. Renombrarlo `MovieOps-CI`.
3. Verificar que los triggers YAML no estén sobrescritos desde la UI.
4. Abrir un Pull Request de prueba.
5. Confirmar:
   - backend y frontend son jobs independientes;
   - tests y coverage aparecen en Azure DevOps;
   - el quality gate depende de ambos;
   - un fallo bloquea el artifact;
   - Azure Pipelines publica un Check en GitHub.
6. En un merge a `main`, comprobar el artifact `movieops-images` con las dos
   imágenes etiquetadas por SHA.

### Gate ADOP-2

- [ ] PR roto falla.
- [ ] PR sano queda verde.
- [ ] Merge a `main` produce un artifact trazable.
- [ ] CI continúa funcionando con `rg-movieops-dev` inexistente.

## Paso 10 — Estabilizar identidades Terraform

Antes de Genesis, Terraform dejará de depender exclusivamente de
`data.azurerm_client_config.current.object_id`. Se declararán de forma estable
los Object IDs de GitHub Actions y Azure DevOps para evitar que alternar runners
reemplace permisos de Key Vault.

### Gate previo a infraestructura

- [ ] `terraform fmt` y `terraform validate` pasan.
- [ ] El plan no revoca acceso de la identidad GitHub existente.
- [ ] Ambos principales están modelados explícitamente.

## Paso 11 — Crear y ejecutar `MovieOps-Genesis`

1. Crear el pipeline desde `/azure-pipelines/genesis.yml`.
2. Mantener `trigger: none` y parámetros `environment`/`confirm`.
3. Autorizar exclusivamente `sc-movieops-azure-wif`.
4. Ejecutar `environment=dev`, `confirm=dev`.
5. Verificar el orden:

   ```text
   fmt → init → validate → Checkov → plan guardado → apply del mismo plan
   ```

6. Ejecutar un segundo plan y comprobar que no hay drift inesperado.

### Gate Genesis

- [ ] `rg-movieops-dev` existe.
- [ ] AKS, ACR, PostgreSQL, Key Vault, red y monitoring existen.
- [ ] `rg-movieops-tfstate` continúa separado.
- [ ] Segundo plan idempotente.

## Paso 12 — Validar el handoff del artefacto

El CD debe consumir el artifact de una ejecución CI verde específica:

1. Descargar `movieops-images`.
2. Cargar las imágenes localmente sin ejecutar `docker build`.
3. Autenticar contra el ACR creado para `dev` mediante WIF.
4. Taggear y publicar con el mismo `sha-<commit>`.
5. Registrar CI run ID, commit y digest/contenido verificado.

Si `dev` está destruido, el preflight debe informar **environment offline** y
terminar sin ejecutar Genesis implícitamente.

### Gate ADOP-4

- [ ] CD no contiene `docker build`.
- [ ] El SHA del artifact coincide con el commit del run CI.
- [ ] La imagen en ACR es la misma que produjo CI.

## Paso 13 — Crear y ejecutar `MovieOps-CD`

1. Crear el pipeline desde `/azure-pipelines/cd.yml`.
2. Vincularlo como pipeline resource de `MovieOps-CI`.
3. Permitir ejecución automática solo para CI verde de `main`.
4. Usar un deployment job asociado al Environment `dev`.
5. Ejecutar:
   - lectura runtime desde Key Vault;
   - creación/actualización de Kubernetes Secret;
   - Kustomize con tags inmutables;
   - `kubectl apply`;
   - rollout gates;
   - smoke test de frontend y `/api/movies`;
   - rollback si existe revisión anterior.

### Gate ADOP-5

- [ ] Backend y frontend alcanzan las réplicas esperadas.
- [ ] Frontend responde HTTP 200.
- [ ] `/api/movies` responde HTTP 200.
- [ ] Environment `dev` registra pipeline, run y commit.

## Paso 14 — Crear y ejecutar `MovieOps-Apocalipsis`

1. Crear el pipeline desde `/azure-pipelines/apocalipsis.yml`.
2. Mantener `trigger: none` y confirmación tipada.
3. Ejecutar `plan -destroy` y aplicar exactamente el plan guardado.
4. Permitir cascade delete del Resource Group desechable, igual que la
   baseline GitHub.
5. Consultar Azure al final y fallar si `rg-movieops-dev` aún existe.

### Gate Apocalipsis

- [ ] `rg-movieops-dev` no existe.
- [ ] No queda ningún recurso del ambiente.
- [ ] `rg-movieops-tfstate` continúa existiendo.
- [ ] El state remoto continúa accesible.

## Paso 15 — Ejecutar fallos controlados

Ejecutar y guardar evidencia de:

1. Test unitario roto.
2. Dockerfile roto.
3. Tag inexistente.
4. Readiness defectuosa.
5. Segundo deployment defectuoso con rollback exitoso.
6. Confirmación incorrecta de Genesis/Apocalipsis.
7. CI verde y CD detenido limpiamente cuando `dev` no existe.

Cada fallo orgánico nuevo se registra en
`docs/azure-devops/troubleshooting.md`.

## Paso 16 — Cerrar la paridad

1. Completar todas las filas de [`parity-matrix.md`](parity-matrix.md).
2. Marcar los runs finales para retención.
3. Documentar diferencias GitHub Actions vs Azure Pipelines.
4. Decidir qué plataforma puede ejecutar pipelines mutantes para evitar doble
   despliegue.
5. Mantener GitHub Actions como baseline hasta registrar la decisión en un ADR.
6. Autorizar el siguiente track: paridad AWS.

## Qué hacemos ahora

El Paso 1 está completo. La siguiente acción es implementar y ejecutar la
primera fase de ADOP-1. El bootstrap creará o verificará el Project `MovieOps`,
la identidad WIF y los controles; se detendrá únicamente cuando requiera el
consentimiento de GitHub App.
