# Estrategia de automatización del bootstrap Azure DevOps

## Decisión

La ruta predeterminada de MovieOps será **bootstrap mediante scripts
idempotentes**. El runbook manual se conserva como referencia, auditoría y
procedimiento de recuperación, pero no será la forma habitual de configurar el
proyecto.

Aproximadamente el 85–90 % del proceso puede automatizarse usando:

- PowerShell 7.3 o superior.
- Azure CLI.
- Extensión Azure DevOps para Azure CLI.
- APIs REST públicas de Azure DevOps.
- YAML versionado en este repositorio.

No se usarán APIs privadas ni se guardarán Personal Access Tokens, client
secrets o passwords de service principals.

## Límite de automatización

| Operación | Automatización | Mecanismo decidido |
|---|---:|---|
| Crear la organización Azure DevOps | No | Portal; Microsoft exige creación interactiva |
| Autenticación inicial del operador | Parcial | `az login` interactivo, sin credencial persistente en el repo |
| Crear Project `MovieOps` | Sí | `az devops project create` |
| Instalar extensión Azure DevOps CLI | Sí | `az extension add --name azure-devops` |
| Configurar defaults de organización/proyecto | Sí | `az devops configure` |
| Instalar/autorizar Azure Pipelines GitHub App | No | Consentimiento manual en GitHub, limitado a `movieops` |
| Crear App Registration sin secreto | Sí | Azure CLI con creación de password desactivada |
| Crear ARM service connection WIF | Sí | Azure DevOps CLI + REST, modo `Manual` |
| Crear federated credential | Sí | Azure CLI con issuer/subject devueltos por Azure DevOps |
| Asignar RBAC de bootstrap | Sí | `az role assignment create` |
| Crear Environments | Sí | Environments REST API 7.1 |
| Crear branch control y approval/check | Sí | Approvals and Checks REST API |
| Aprobar un deployment real | No | Decisión humana deliberada |
| Registrar pipelines YAML | Sí | `az pipelines create`/REST después de conectar GitHub App |
| Autorizar service connection por pipeline | Sí | REST API, sin autorización global |
| Definir triggers y dependencias | Sí | YAML versionado |
| Configurar retención | Sí/Verificación | API soportada; si una opción no está expuesta, el script informa el ajuste manual exacto |
| Ejecutar Genesis, CI, CD y Apocalipsis | Sí | Triggers YAML o `az pipelines run` |
| Verificar configuración y acceso Azure | Sí | Script read-only + pipeline de diagnóstico |
| Aprobación de producción | No | Check administrado fuera del YAML |

## Por qué quedan pasos manuales

### Organización

Azure DevOps no ofrece creación automatizada de organizaciones. La organización
es el único recurso raíz que debe existir antes del bootstrap.

Referencia: [Create an organization](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/create-organization?view=azure-devops).

### GitHub App

La instalación de Azure Pipelines GitHub App concede acceso al repositorio y
requiere consentimiento del propietario. Se autorizará únicamente
`ajunquit/movieops`, no todos los repositorios. Después del consentimiento, los
scripts sí pueden registrar los pipelines que reutilizan esa conexión.

Referencia: [Build GitHub repositories with Azure Pipelines](https://learn.microsoft.com/en-us/azure/devops/pipelines/repos/github?view=azure-devops).

### Aprobaciones

El script configura quién puede aprobar y las reglas del check, pero no aprueba
una ejecución. Automatizar la decisión eliminaría el control que se pretende
demostrar.

## Diseño de scripts

```text
scripts/
└── azure-devops/
    ├── 00-bootstrap-project/
    ├── 01-service-connection-wif/
    ├── 02-configure-environments/
    ├── 03-configure-pipelines/
    ├── 04-configure-retention/
    ├── 05-verify-bootstrap/
    └── 99-full-bootstrap/
```

### `99-full-bootstrap/Invoke-Bootstrap.ps1`

Estado: **implementado después de validar individualmente los pasos 00–05**.

Orquestador principal. Valida prerrequisitos, ejecuta los scripts en orden,
detiene el proceso en los gates de consentimiento de GitHub App y primer run
diagnóstico verde, y puede reanudarse sin duplicar recursos.

Interfaz prevista:

```powershell
./scripts/azure-devops/99-full-bootstrap/Invoke-Bootstrap.ps1 `
  -OrganizationUrl "https://dev.azure.com/<organization>" `
  -ProjectName "MovieOps" `
  -GitHubRepository "ajunquit/movieops" `
  -SubscriptionId "<subscription-id>" `
  -TenantId "<tenant-id>" `
  -ProductionApprover "<user-principal-name>"
```

Los IDs de suscripción y tenant pueden descubrirse desde `az account show`,
pero permanecen como parámetros para hacer explícito el target y evitar operar
accidentalmente sobre otra suscripción.

### `00-bootstrap-project/bootstrap-project.ps1`

Estado: **completado y verificado**.

- Comprueba Azure CLI y PowerShell.
- Instala/actualiza la extensión `azure-devops`.
- Configura defaults para organización y proyecto.
- Crea `MovieOps` como proyecto privado si no existe.
- Recupera el Project ID para los demás scripts.
- Comprueba capacidad de agentes y emite una acción manual si no existe parallel
  job alojado.

### `01-service-connection-wif/configure-service-connection.ps1`

Estado: **completado y verificado**.

Automatiza el proceso WIF en el orden requerido:

```text
App Registration / Service Principal sin password
  → service connection AzureRM en modo Manual
  → obtener issuer + subject de Azure DevOps
  → federated identity credential en Entra ID
  → roles Contributor + RBAC Administrator
  → verificación de la conexión
```

El orden importa porque issuer y subject solo están disponibles después de
crear la service connection. Para automatización, Microsoft exige
`creationMode: Manual`; `Automatic` está reservado al flujo interactivo con
privilegios de usuario.

Referencia: [Automate Azure Resource Manager WIF service connections](https://learn.microsoft.com/en-us/azure/devops/pipelines/release/automate-service-connections?view=azure-devops).

### `02-configure-environments/configure-environments.ps1`

Estado: **completado y verificado**.

- Crea `dev`, `staging` y `production` si no existen.
- Resuelve sus IDs.
- Configura branch control con `refs/heads/main`.
- Configura el approver de `production`.
- Bloquea self-approval cuando la API lo permita.
- No agrega recursos Kubernetes: los Environments representan historial y
  controles de despliegue.

Referencias: [Environments REST API](https://learn.microsoft.com/en-us/rest/api/azure/devops/distributedtask/environments/add?view=azure-devops-rest-7.1) y [Approvals and Checks REST API](https://learn.microsoft.com/en-us/rest/api/azure/devops/approvalsandchecks/check-configurations/add?view=azure-devops-rest-7.1).

### `03-configure-pipelines/configure-pipelines.ps1`

Estado: **completado y verificado para `MovieOps-Diagnostic`**. La conexión
GitHub App está lista y el run diagnóstico `59` terminó correctamente en
`main`.

Se ejecuta después del consentimiento de GitHub App:

- Detecta la conexión GitHub App existente.
- Registra cada YAML con nombre estable.
- No crea YAML desde la UI.
- Autoriza `sc-movieops-azure-wif` solo para los pipelines que la necesitan.
- Conserva CI sin permiso de mutar Azure cuando no lo requiera.

Pipelines objetivo:

| Nombre Azure DevOps | YAML |
|---|---|
| `MovieOps-Diagnostic` | `azure-pipelines/diagnostic.yml` |
| `MovieOps-CI` | `azure-pipelines/ci.yml` |
| `MovieOps-Genesis` | `azure-pipelines/genesis.yml` |
| `MovieOps-CD` | `azure-pipelines/cd.yml` |
| `MovieOps-Apocalipsis` | `azure-pipelines/apocalipsis.yml` |

### `04-configure-retention/configure-retention.ps1`

Estado: **completado y verificado**.

Aplica o verifica la política acordada:

- Runs y logs: 30 días.
- Artifacts: 30 días.
- Pull Request runs: 14 días.
- Tres runs recientes por pipeline.
- Retención extendida para la evidencia final de Genesis/CD/Apocalipsis.

No utilizará endpoints internos no documentados. Si una opción solo está
disponible en Project Settings, el script falla de forma accionable o reporta
`MANUAL ACTION REQUIRED` con el valor exacto; nunca simula éxito.

### `05-verify-bootstrap/verify-bootstrap.ps1`

Estado: **completado y verificado**. La auditoría final produjo `21/21` PASS y
`0` FAIL.

Es read-only y constituye la prueba final de ADOP-1:

- Project existe y es privado.
- GitHub connection apunta a `ajunquit/movieops`.
- App/Service Principal no tiene client secrets creados por el bootstrap.
- Service connection usa WIF y no está autorizada globalmente.
- Roles de suscripción son correctos.
- Environments y checks existen.
- Pipelines apuntan a los YAML esperados.
- Pipeline de diagnóstico puede leer subscription/resource groups.
- Ninguna verificación crea infraestructura.

## Contrato de idempotencia

Todos los scripts deben seguir estas reglas:

1. **Discover before create:** consultar por nombre e ID antes de mutar.
2. **Create or converge:** crear lo inexistente y corregir lo divergente.
3. **No duplicates:** una segunda ejecución no crea otro Project, principal,
   service connection, Environment, check o pipeline.
4. **No secrets:** no generar passwords; no imprimir tokens; no escribir
   credenciales en disco.
5. **Explicit target:** validar tenant, subscription, organización y proyecto
   antes de cualquier mutación.
6. **Fail closed:** permisos insuficientes o identidad ambigua detienen el
   bootstrap.
7. **Observable:** cada operación informa `EXISTS`, `CREATED`, `UPDATED`,
   `VERIFIED` o `MANUAL ACTION REQUIRED`.
8. **Verifiable:** una ejecución final de `verify-bootstrap.ps1` no cambia nada.

## Fases de ejecución

```text
FASE 0 — Manual
Crear organización y obtener OrganizationUrl
        │
        ▼
FASE 1 — Script
Proyecto + extensión + defaults + identidad + WIF + RBAC + Environments
        │
        ▼
GATE MANUAL
Instalar/autorizar GitHub App solo para movieops
        │
        ▼
FASE 2 — Script
Registrar pipelines + permisos + retención
        │
        ▼
FASE 3 — Verificación
verify-bootstrap + MovieOps-Diagnostic read-only
```

`99-full-bootstrap/Invoke-Bootstrap.ps1` puede ejecutarse nuevamente después de
cualquiera de los gates manuales; al detectar los recursos existentes, los
verifica y continúa sin duplicarlos.

## Permisos requeridos al operador

| Sistema | Permiso mínimo esperado |
|---|---|
| Azure DevOps | Organization owner para el bootstrap inicial o permisos equivalentes delegados |
| Azure DevOps Project | Project/Service Connection administrator |
| Microsoft Entra ID | Capacidad de crear App Registrations o rol Application Developer |
| Suscripción Azure | Contributor + Role Based Access Control Administrator, o Owner durante bootstrap |
| GitHub | Propietario del repositorio/cuenta para instalar GitHub App |

Los permisos del operador no se transfieren automáticamente al pipeline. La
identidad WIF obtiene únicamente los roles que el script declara.

## Qué no hará el bootstrap

- No creará ni importará un repositorio Azure Repos.
- No ejecutará Genesis durante la configuración de ADOP-1.
- No activará CD automático antes de validar CI y artifact handoff.
- No autorizará la service connection para todos los pipelines.
- No aprobará despliegues de producción.
- No eliminará GitHub Actions mientras sea la baseline.
- No almacenará PATs, client secrets ni credenciales de ACR.

## Definition of Done de la automatización

- Una organización recién creada puede converger al estado ADOP-1 ejecutando
  scripts, con una única pausa de consentimiento GitHub App.
- Reejecutar el bootstrap produce cero duplicados y termina verde.
- `verify-bootstrap.ps1` demuestra la configuración sin mutarla.
- El pipeline de diagnóstico se autentica en Azure mediante WIF y solo realiza
  consultas de lectura.
- Todo paso manual restante está identificado explícitamente y tiene evidencia.
