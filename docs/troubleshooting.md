# Troubleshooting — fallos reales y cómo se resolvieron

Bitácora técnica de cada fallo que nos encontramos **de verdad** mientras construíamos MovieOps. No son ejercicios: cada uno rompió algo real y costó tiempo diagnosticarlo.

## Cómo se relaciona con los otros documentos

| Documento | Qué guarda | Para qué sirve |
|---|---|---|
| **`troubleshooting.md`** (este) | Post-mortem técnico detallado de fallos **orgánicos** | "Esto volvió a pasar, ¿cómo lo arreglo?" |
| [`interview-notes.md`](interview-notes.md) | El mismo fallo, condensado en formato STAR | "¿Cómo cuento esto en una entrevista?" |
| `incidents/` | Fallos **provocados a propósito** (LAB-INCIDENT-01..10) | Sprint 13: practicar respuesta a incidentes |

Formato de cada entrada: el de la sección 46 del plan — Síntoma, Impacto, Hipótesis, Evidencia, Diagnóstico, Root Cause, Solución, Acción preventiva.

## Índice

**Casos con diagnóstico profundo**
- [TS-01 — El healthcheck del contenedor miente: unhealthy mientras sirve perfecto](#ts-01)
- [TS-02 — Un proceso zombie de hace 3 sprints secuestraba el puerto](#ts-02)
- [TS-03 — La configuración se capturó "eager" y los tests hablaban con la base equivocada](#ts-03)
- [TS-04 — AKS rechaza su propia configuración de red por defecto](#ts-04)
- [TS-05 — La URL base de TMDB perdía silenciosamente un segmento del path](#ts-05)
- [TS-06 — El workflow no podía ni arrancar: working-directory antes del checkout](#ts-06)
- [TS-07 — El contenido del Sprint 9 desapareció de main después de mergear](#ts-07)
- [TS-08 — Entra ID rechazaba el sujeto OIDC inmutable del repositorio](#ts-08)
- [TS-09 — Contributor no alcanza: 403 al crear role assignments](#ts-09)
- [TS-10 — Ser Owner de la suscripción no da acceso a los secretos del Key Vault](#ts-10)
- [TS-11 — El Ingress tenía IP pública pero el NSG descartaba todo el tráfico](#ts-11)
- [TS-12 — Apocalipsis eliminó la infraestructura, pero dejó el Resource Group](#ts-12)
- [TS-13 — El bootstrap creó los Environments, pero falló al recibir cero checks](#ts-13)
- [TS-14 — La ausencia de acceso global provocó un falso fallo de verificación](#ts-14)
- [TS-15 — La auditoría RBAC combinó dos filtros incompatibles de Azure CLI](#ts-15)

**Gotchas de herramientas y entorno** → [ver tabla al final](#gotchas)

---

<a name="ts-01"></a>
## TS-01 — El healthcheck del contenedor miente: `unhealthy` mientras sirve perfecto

**Sprint 5 · Docker**

### Síntoma
`docker compose ps` marcaba el contenedor del frontend como `unhealthy` después de unos minutos, pero `curl http://localhost:4200/` desde el host respondía **200 OK** sin problema. La app funcionaba perfecto en el navegador.

### Impacto
Bajo en local, **alto en producción**: un readiness gate de Kubernetes o un rolling deployment habrían sacado de rotación un pod que en realidad estaba sano, o bloqueado un deploy correcto.

### Hipótesis descartadas
1. ¿Nginx se cayó o se quedó sin workers? → **No**: `ps aux` dentro del contenedor mostraba el master y los 8 workers vivos.
2. ¿El healthcheck tiene mal la URL o el puerto? → **No**: `nginx -T` confirmó que escuchaba en `:80` y que el `server` block estaba bien.

### Evidencia
```bash
# Desde el HOST: funciona
curl -o /dev/null -w "%{http_code}" http://localhost:4200/   # 200

# El MISMO comando del healthcheck, DENTRO del contenedor: falla
docker compose exec frontend wget --spider -q http://127.0.0.1/
wget: can't connect to remote host: Connection refused
```

Las dos cosas a la vez son la pista: el problema no es nginx, es **desde dónde** se lo consulta.

### Diagnóstico
Dentro del contenedor, `wget` resuelve `localhost` a `::1` (IPv6) **primero**. La directiva `listen 80;` de nginx, sin corchetes, hace bind **solo a IPv4** (`0.0.0.0:80`) — nada escucha en `::1`, así que la conexión se rechaza de inmediato. El `wget` de BusyBox **no reintenta** con la familia de direcciones IPv4 cuando la primera falla; devuelve error y listo.

Desde el host funcionaba porque el port-forwarding de Docker enruta directo al socket IPv4 del contenedor, salteándose por completo la resolución de `localhost`. Eso enmascaraba el problema.

### Root Cause
Usar el nombre `localhost` en un healthcheck, dentro de un contenedor donde el servidor solo hace bind a IPv4 y el cliente prefiere IPv6.

### Solución
IP explícita en vez del nombre, en el `HEALTHCHECK` del Dockerfile y en `docker-compose.yml`:
```diff
- CMD wget --spider -q http://localhost/ || exit 1
+ CMD wget --spider -q http://127.0.0.1/ || exit 1
```

### Acción preventiva
**Nunca usar `localhost` en un healthcheck de contenedor.** Siempre `127.0.0.1` (o `[::1]` si el servidor hace bind explícito a IPv6). El nombre introduce una dependencia de resolución que varía entre imágenes base y clientes HTTP.

---

<a name="ts-02"></a>
## TS-02 — Un proceso zombie de hace 3 sprints secuestraba el puerto

**Sprint 5 · Docker / entorno local**

### Síntoma
Con el stack de Docker corriendo y sano, `GET http://localhost:4200/api/movies` devolvía **500** con un cuerpo `text/plain` y header `Vary: Origin` — un formato que no era ni el `ProblemDetails` JSON de nuestra API, ni la página de error HTML de nginx.

### Impacto
Media hora de diagnóstico persiguiendo un bug que no existía en el código.

### Hipótesis descartadas
1. ¿El `proxy_pass` de nginx está mal? → **No**: `nginx -T` mostraba la config correcta.
2. ¿El backend no es alcanzable desde el contenedor de frontend? → **No**: `wget http://backend:8080/health/live` desde dentro del contenedor devolvía `Healthy`.

### Evidencia
La pista clave fue el **formato de la respuesta**: `text/plain` + `Vary: Origin` es la firma de un proxy de Node/Express, no de nginx ni de ASP.NET Core. Algo que no era ninguno de nuestros dos servicios estaba respondiendo.

```powershell
Get-NetTCPConnection -LocalPort 4200
# DOS listeners:
#   ::1   :4200  → PID 18032 (node.exe)      ← ¿¿de dónde salió esto??
#   ::    :4200  → PID 22660 (com.docker.backend)
```

### Diagnóstico
Había quedado vivo un proceso `ng serve` del Sprint 3, de una prueba manual que creí haber terminado. Escuchaba solo en `::1` (loopback IPv6). En Windows, `::1` tiene **precedencia sobre `::`** al resolver `localhost`, así que **todas** mis requests iban al dev server zombie — no al contenedor. Y ese dev server proxyeaba `/api` hacia `http://localhost:5014`, donde ya no había ningún `dotnet run`: de ahí el 500 genérico de su middleware de proxy.

### Root Cause
Un proceso de desarrollo sin matar, sumado a la precedencia de IPv6 en Windows, que hizo que el tráfico nunca llegara al contenedor que yo creía estar probando.

### Solución
Matar el proceso huérfano (`Stop-Process -Id 18032 -Force`). Sin cambios en el código.

### Acción preventiva
Antes de debuggear "el contenedor responde mal", **verificar primero qué está escuchando realmente en ese puerto**:
```powershell
Get-NetTCPConnection -LocalPort <puerto> | Select LocalAddress,OwningProcess
```
Que un contenedor diga `healthy` no prueba que *tu request* haya llegado a él.

---

<a name="ts-03"></a>
## TS-03 — La configuración se capturó "eager" y los tests hablaban con la base equivocada

**Sprint 4 · Tests de integración / .NET DI**

### Síntoma
Los tests de integración con Testcontainers fallaban con:
```
Npgsql.NpgsqlException: Failed to connect to 127.0.0.1:5432
```
…aunque el contenedor de Postgres levantaba correctamente en un puerto mapeado **aleatorio**, no en el 5432.

### Impacto
Bloqueaba todo el Sprint 4. Y —más grave— era una fragilidad latente de la app real, no solo de los tests.

### Hipótesis descartadas
1. ¿El contenedor no arrancó? → **No**: Testcontainers reportaba el contenedor listo.
2. ¿`WebApplicationFactory` no aplica el override? → **Parcialmente cierto, pero no era la causa raíz.**

### Evidencia
`127.0.0.1:5432` es **exactamente** el valor literal de `appsettings.Development.json`. O sea: el override del test nunca se aplicó — la app usó el valor de disco.

### Diagnóstico
En `AddInfrastructure(configuration)` la connection string se leía **una sola vez, al registrar los servicios**:

```csharp
// ANTES — captura el valor en el momento del registro
var connectionString = configuration.GetConnectionString("Default");
services.AddDbContext<MovieOpsDbContext>(o => o.UseNpgsql(connectionString));
```

Ese `connectionString` queda **capturado en la closure**. El callback `ConfigureAppConfiguration` del test factory agrega su fuente de configuración *después* de que corrieron las líneas de arriba, así que el `DbContext` ya tenía horneado el valor viejo. La configuración se actualizaba; el `DbContext` no se enteraba nunca.

### Root Cause
Leer configuración de forma **eager** (en tiempo de registro de DI) en vez de **lazy** (en tiempo de resolución del servicio), lo que la vuelve inmune a cualquier fuente de configuración agregada después.

### Solución
Resolver `IConfiguration` desde el `IServiceProvider` dentro de la factory del `DbContext`:
```csharp
services.AddDbContext<MovieOpsDbContext>((sp, options) =>
{
    var cs = sp.GetRequiredService<IConfiguration>().GetConnectionString("Default")
        ?? throw new InvalidOperationException("Connection string 'Default' is not configured.");
    options.UseNpgsql(cs);
});
```
Lo mismo se aplicó al health check de Npgsql en `Program.cs`.

### Acción preventiva
En métodos de extensión `Add*(IConfiguration)`, **nunca capturar valores en variables locales**. Usar siempre el overload con `IServiceProvider`. Regla simple: si el valor termina dentro de una closure que se ejecuta una sola vez al arrancar, es eager y va a ignorar cualquier capa de configuración posterior.

---

<a name="ts-04"></a>
## TS-04 — AKS rechaza su propia configuración de red por defecto

**Sprint 7 · Terraform / Azure**

### Síntoma
`terraform apply` creó 15 de 17 recursos correctamente (~7 min) y después falló solo en el cluster:
```
Error: creating Kubernetes Cluster: unexpected status 400
"code": "ServiceCidrOverlapExistingSubnetsCidr",
"message": "The specified service CIDR 10.0.0.0/16 is conflicted with an existing subnet CIDR 10.0.1.0/24"
```

### Impacto
Bloqueaba el cluster. Costo real acumulándose mientras se diagnosticaba (Postgres y demás ya estaban creados y facturando).

### Evidencia
El mensaje de Azure ya nombra los dos rangos en conflicto. El detalle no obvio: **nosotros nunca configuramos** ningún `10.0.0.0/16` como service CIDR.

### Diagnóstico
Dos planes de direccionamiento IP **independientes** colisionaron porque uno era implícito:
- **El nuestro, explícito:** la VNet usa `10.0.0.0/16`, con la subnet de nodos en `10.0.1.0/24`.
- **El de AKS, implícito:** al no especificar `service_cidr` en el `network_profile`, Azure usa su default… que es justamente `10.0.0.0/16`, para las IPs internas de los Services de Kubernetes.

El rango de Services de Kubernetes es virtual e interno al cluster, pero **no puede solaparse** con el direccionamiento real de la VNet, porque el enrutamiento se volvería ambiguo.

### Root Cause
Dejar implícito un parámetro de red (`service_cidr`) que tenía que coordinarse con un valor que sí definimos explícitamente en otro módulo.

### Solución
Rango explícito, fuera del espacio de la VNet:
```hcl
network_profile {
  network_plugin      = "azure"
  network_plugin_mode = "overlay"
  service_cidr        = "172.16.0.0/16"   # no se solapa con la VNet 10.0.0.0/16
  dns_service_ip      = "172.16.0.10"     # tiene que caer dentro del service_cidr
}
```

Detalle valioso: como los otros 15 recursos ya estaban **en el state**, el siguiente `plan` mostró solo **2 recursos a crear**. Terraform no rehizo nada de lo ya aplicado — ese es exactamente el valor del state.

### Acción preventiva
Al crear un cluster dentro de una VNet propia, **definir siempre los tres rangos de forma explícita** (VNet, pod CIDR si aplica, y service CIDR) y verificar que no se solapen. Los defaults de cada servicio se eligieron sin conocer tu red.

---

<a name="ts-05"></a>
## TS-05 — La URL base de TMDB perdía silenciosamente un segmento del path

**Sprint 3 · Integración externa**

### Síntoma
`GET /api/movies/search?query=batman` devolvía siempre **502** (nuestro error controlado de "TMDB no disponible"), incluso con una API key válida.

### Impacto
La feature de búsqueda no funcionaba. Y como el error estaba bien manejado, *parecía* un problema del proveedor externo y no nuestro — el peor tipo de bug.

### Evidencia
El log del `HttpClient` mostraba la URL saliente real:
```
Start processing HTTP request GET https://api.themoviedb.org/search/movie?*
                                                          ↑ falta /3
Received HTTP response headers after 310ms - 404
```
Con API key válida el 404 pasó a **401** — otra pista: la ruta seguía mal.

### Diagnóstico
`BaseAddress` estaba configurado como `"https://api.themoviedb.org/3"` — **sin barra final**. Según las reglas de combinación de URIs del RFC 3986, cuando la URI base **no termina en `/`**, su último segmento se **reemplaza** por la URI relativa, no se le agrega:

```
"https://api.themoviedb.org/3"  +  "search/movie"  →  "https://api.themoviedb.org/search/movie"
"https://api.themoviedb.org/3/" +  "search/movie"  →  "https://api.themoviedb.org/3/search/movie"  ✓
```

### Root Cause
Una barra final faltante en `BaseAddress`, combinada con una regla de combinación de URIs que descarta datos en silencio en vez de fallar.

### Solución
```diff
- public string BaseUrl { get; set; } = "https://api.themoviedb.org/3";
+ public string BaseUrl { get; set; } = "https://api.themoviedb.org/3/";
```
(Y la ruta relativa **no** debe empezar con `/`, o también descarta el path base.)

### Acción preventiva
Regla para `HttpClient`: **`BaseAddress` siempre termina en `/`; la ruta relativa nunca empieza con `/`.** Si algo falla en una integración, mirar la URL efectiva en los logs antes que la lógica.

---

<a name="ts-06"></a>
## TS-06 — El workflow no podía ni arrancar: working-directory antes del checkout

**Sprint 7/9 · GitHub Actions**

### Síntoma
Primera corrida real de `genesis.yml`. Falló en el **primer paso**, una simple comparación de strings que no toca nada:
```
Error: An error occurred trying to start process '/usr/bin/bash' with working directory
'/home/runner/work/movieops/movieops/terraform/environments/azure/dev'. No such file or directory
```
Todos los pasos siguientes figuraban en `0s` — nunca corrieron.

### Impacto
Imposible crear infraestructura desde el pipeline. Y el mismo bug estaba latente en `apocalipsis.yml`, o sea: **tampoco se podía destruir** desde el pipeline.

### Evidencia
El error no habla del `if` ni de la comparación: habla de que **bash no pudo iniciarse**. El proceso nunca llegó a ejecutar el script.

### Diagnóstico
El job define un default global:
```yaml
defaults:
  run:
    working-directory: terraform/environments/azure/${{ inputs.environment }}
```
Eso aplica a **todos** los pasos `run:`, incluido `Verify typed confirmation`, que corre **a propósito antes** de `actions/checkout@v4` (para abortar sin tocar nada si la confirmación no coincide). En ese instante el workspace del runner está **vacío** — el repo todavía no se clonó — así que ese directorio no existe y el sistema operativo no puede lanzar bash con ese `cwd`.

### Root Cause
Un setting implícito a nivel job (`defaults.run.working-directory`) aplicándose a un paso que, por diseño, corre antes de que ese directorio exista.

### Solución
Override explícito en ese paso, manteniendo el orden fail-fast:
```yaml
- name: Verify typed confirmation
  working-directory: ${{ github.workspace }}   # el workspace sí existe, aunque esté vacío
  run: |
    if [ "${{ inputs.confirm }}" != "${{ inputs.environment }}" ]; then ...
```

Después se auditaron **todos** los workflows buscando el mismo patrón: `apocalipsis.yml` tenía el bug idéntico (corregido); `backend-ci.yml` y `frontend-ci.yml` estaban bien porque arrancan con `checkout`.

### Acción preventiva
Dos reglas:
1. Cualquier paso `run:` que corra **antes** de `checkout` necesita `working-directory` explícito si el job define un default.
2. **Un workflow que nunca se ejecutó no está probado**, por más que el YAML sea válido. `apocalipsis.yml` llevaba días "listo" y estaba roto — nunca lo corrimos porque siempre destruíamos con Terraform local. Un procedimiento de emergencia sin probar no es un procedimiento.

---

<a name="ts-07"></a>
## TS-07 — El contenido del Sprint 9 desapareció de `main` después de mergear

**Git / proceso**

### Síntoma
GitHub mostraba los PRs #17, #18 y #19 como **MERGED**, pero los archivos del Sprint 9 (`namespace.yaml`, `ingress.yaml`, `hpa.yaml`, el bloque `web_app_routing`) **no existían** en `main`.

### Impacto
Dos sprints de trabajo aparentemente perdidos. Alto riesgo de rehacerlos por las malas si no se detectaba.

### Evidencia
```bash
git diff main origin/sprint-9-kubernetes --stat
# 14 files changed, 118 insertions(+)   ← todo el Sprint 9 faltaba en main
```
La rama remota **sí** conservaba todo: nada se había perdido de verdad, simplemente nunca llegó a `main`.

### Diagnóstico
Las ramas estaban **apiladas**: `sprint-9-kubernetes` salía de `sprint-8-cd`, que salía de `sprint-7-terraform`. Después de mergear las tres en orden, se abrió y mergeó un **PR #20 desde `sprint-7-terraform` otra vez**, cuando esa rama todavía apuntaba a un commit **anterior** a que las otras dos se ramificaran de ella. Ese merge tardío reintrodujo el estado viejo de los archivos compartidos, pisando lo del Sprint 9.

### Root Cause
PRs apilados mergeados fuera de orden, con una rama base re-mergeada después de que sus descendientes ya estaban en `main`.

### Solución
Merge limpio de la rama que sí tenía el contenido, sobre el `main` actual:
```bash
git checkout -b sprint-9-restore
git merge origin/sprint-9-kubernetes   # sin conflictos
kubectl kustomize k8s/base             # verificado antes de abrir el PR
```

### Acción preventiva
1. Con PRs apilados: **mergear estrictamente en orden** (base → descendiente) y **borrar la rama base** apenas se mergea, para que no pueda re-mergearse después.
2. **No confiar en que GitHub diga "merged"** — verificar que el archivo esperado exista en `main`:
   ```bash
   git diff main origin/<rama> --stat   # debe salir vacío
   ```

---

<a name="ts-08"></a>
## TS-08 — Entra ID rechazaba el sujeto OIDC inmutable del repositorio

**Sprint 9 · GitHub Actions / Azure OIDC**

### Síntoma
`genesis.yml` superó `terraform fmt`, pero `terraform init` falló al intentar
leer el state remoto:

```text
AADSTS700213: No matching federated identity record found for presented
assertion subject
'repo:ajunquit@26319954/movieops@1368790728:environment:dev'
```

### Impacto
Bloqueaba `Genesis`, `Apocalipsis` y cualquier despliegue que usara la misma
App Registration. Terraform ni siquiera podía consultar los workspaces del
backend remoto.

### Hipótesis descartadas
1. ¿Falta `permissions: id-token: write`? → **No**: GitHub sí emitió un token y
   Entra ID pudo leer su assertion.
2. ¿Hay que agregar `azure/login` antes de Terraform? → **No**: el backend
   `azurerm` ya estaba intentando el intercambio OIDC mediante
   `ARM_USE_OIDC=true`.
3. ¿Falló o desapareció el Storage Account del state? → **No**: el error ocurrió
   en la autenticación previa a cualquier operación contra el storage.

### Evidencia
El sujeto presentado en el propio error incluía IDs inmutables:

```text
repo:ajunquit@26319954/movieops@1368790728:environment:dev
```

GitHub confirmó la configuración efectiva:

```powershell
gh api repos/ajunquit/movieops/actions/oidc/customization/sub
# use_immutable_subject: true
# sub_claim_prefix: repo:ajunquit@26319954/movieops@1368790728
```

En cambio, las tres credenciales de la App Registration confiaban en el formato
anterior:

```text
repo:ajunquit/movieops:environment:<environment>
```

### Diagnóstico
GitHub usa por defecto sujetos OIDC inmutables para repositorios creados después
del 15 de julio de 2026. MovieOps fue creado el 13 de septiembre de 2026, pero
las credenciales federadas se prepararon manualmente con el formato histórico
basado solo en nombres. Entra ID compara `issuer`, `subject` y `audience` de
forma exacta y sensible a mayúsculas, por lo que rechazó el token válido.

### Root Cause
La relación de confianza de Entra ID se creó a partir de un formato OIDC
obsoleto, en lugar de consultar el sujeto efectivo del repositorio.

### Solución
Se automatizó la sincronización de las tres credenciales:

```powershell
./scripts/azure/sync-github-oidc-federated-credentials.ps1
```

El script consulta `sub_claim_prefix` en GitHub, localiza
`github-movieops-terraform`, actualiza o crea la credencial de cada environment
y vuelve a leerlas para verificar el resultado. Puede previsualizarse con
`-WhatIf` y ejecutarse repetidamente sin cambios innecesarios.

### Acción preventiva
1. No construir el sujeto desde nombres asumidos; consultar la configuración
   OIDC efectiva de GitHub.
2. Ejecutar el script después de crear, renombrar o transferir el repositorio.
3. Mantener el environment en el sujeto para conservar el aislamiento
   criptográfico entre `dev`, `staging` y `production`.
4. Ante `AADSTS700213`, comparar primero los tres valores exactos del token
   (`issuer`, `subject`, `audience`) contra la credencial de Entra ID.

---

<a name="ts-09"></a>
## TS-09 — Contributor no alcanza: 403 al crear role assignments

**Sprint 9 · Terraform / Azure RBAC**

### Síntoma
Con el OIDC ya resuelto (TS-08), `genesis.yml` llegó hasta `terraform apply`, creó **15 de 17 recursos** (VNet, AKS, ACR, Key Vault, Postgres con su base y su firewall rule) y falló solo en los últimos dos:

```text
Error: unexpected status 403 (403 Forbidden) with error: AuthorizationFailed:
The client '***' with object id '36edcd2d-...' does not have authorization to
perform action 'Microsoft.Authorization/roleAssignments/write' over scope
'/subscriptions/***/resourceGroups/rg-movieops-dev/providers/
Microsoft.ContainerRegistry/registries/acrmovieopsdevcwvc/...'

  with module.kubernetes.azurerm_role_assignment.aks_acr_pull
  with module.secrets.azurerm_role_assignment.current_user_secrets_officer
```

### Impacto
**Alto, y con costo corriendo.** El ambiente quedó a medio crear pero facturando: AKS y Postgres —las dos partes caras— ya estaban levantados. Y funcionalmente el ambiente era inútil: sin `AcrPull`, AKS no puede bajar imágenes del registry; sin `Key Vault Secrets Officer`, Terraform no puede guardar la password de Postgres.

### Hipótesis descartadas
1. ¿El OIDC volvió a fallar? → **No**: el error es 403 (*autorizado pero sin permiso*), no 401 (*no autenticado*). Ese cambio de código es la pista principal: la identidad se validó bien, lo que faltó fue permiso.
2. ¿El scope está mal construido en el Terraform? → **No**: el mensaje incluye el scope completo y apunta exactamente al ACR y al Key Vault correctos.
3. ¿Faltan permisos sobre ACR o Key Vault específicamente? → **No**: el recurso denegado no es el ACR, es `Microsoft.Authorization/roleAssignments` *dentro* de ese scope. Es una acción de RBAC, no de datos.

### Evidencia
```powershell
az role assignment list --assignee <appId> --all -o table
# Role         Scope
# -----------  ---------------------------------------------------
# Contributor  /subscriptions/b7fdb48a-...        ← lo único que tenía
```

### Diagnóstico
**Contributor puede crear casi cualquier recurso de Azure, pero no puede otorgar permisos.** `Microsoft.Authorization/*/Write` está explícitamente en sus `NotActions`. Es una decisión de diseño de Azure para evitar escalada de privilegios: si Contributor pudiera escribir role assignments, cualquier principal con Contributor podría auto-asignarse Owner.

Nuestro Terraform necesita justamente eso, en dos lugares legítimos:

| Recurso | Por qué necesita crear un role assignment |
|---|---|
| `aks_acr_pull` | El `object_id` de la identidad kubelet **solo existe después** de crear el cluster, así que la asignación no puede hacerse a mano de antemano |
| `current_user_secrets_officer` | El propio Terraform necesita permiso de datos sobre el Key Vault recién creado para escribir la password generada |

### Root Cause
El service principal de CI tenía permisos para **crear infraestructura** pero no para **otorgar acceso** — dos planos de permisos distintos en Azure (control plane de recursos vs. control plane de autorización) que suelen confundirse como uno solo.

### Solución
Se agregó el rol **`Role Based Access Control Administrator`**, que es el mínimo privilegio para esto. El fix está scripteado e idempotente en
[`scripts/azure/grant-ci-subscription-roles.ps1`](../scripts/azure/grant-ci-subscription-roles.ps1):

```powershell
./scripts/azure/grant-ci-subscription-roles.ps1 -WhatIf   # previsualizar
./scripts/azure/grant-ci-subscription-roles.ps1           # aplicar y verificar
```

Por qué ese rol y no otro:

| Rol | Permisos | Veredicto |
|---|---|---|
| `Owner` | `*` — todo | Demasiado amplio |
| `User Access Administrator` | `Microsoft.Authorization/*` (incluye deny assignments, policy) | Más de lo necesario |
| **`Role Based Access Control Administrator`** | Solo `roleAssignments/write`, `roleAssignments/delete`, `*/read` | ✅ Exacto |

El `delete` importa: sin él, `apocalipsis.yml` fallaría al intentar destruir esos mismos role assignments.

Como los otros 15 recursos ya estaban en el state, el siguiente `apply` solo tuvo que crear los 2 que faltaban — no rehizo nada (misma propiedad del state que salvó el día en TS-04).

### Acción preventiva
1. **Si tu Terraform contiene algún `azurerm_role_assignment`, el principal que lo ejecuta necesita RBAC Administrator, no alcanza Contributor.** Es el error más común al automatizar Azure con CI.
2. **Todo fix aplicado a mano sobre Azure queda scripteado en [`scripts/azure/`](../scripts/README.md).** Este se resolvió originalmente con un `az role assignment create` suelto desde una terminal: funcionó, pero no dejó rastro reproducible. Si mañana hay que rehacer la suscripción desde cero, un comando que vivió solo en el historial de una shell no existe.
3. **Leer el código HTTP antes que el mensaje:** 401 = identidad no válida (revisar OIDC, TS-08); 403 = identidad válida, permiso faltante (revisar roles). Diagnósticos completamente distintos.
4. **Pendiente de endurecer:** un principal que puede escribir role assignments a nivel suscripción puede auto-asignarse Owner. El endurecimiento profesional es agregar una *condition* al role assignment que restrinja **qué roles** puede asignar (solo `AcrPull` y `Key Vault Secrets Officer`). Aceptable en este lab; no lo sería en producción.

---

<a name="ts-10"></a>
## TS-10 — Ser Owner de la suscripción no da acceso a los secretos del Key Vault

**Sprint 9 · Azure RBAC / Key Vault**

### Síntoma
Con el ambiente `dev` ya creado, intentar leer la password de Postgres que Terraform había guardado en el vault falló:

```text
ERROR: (Forbidden) Caller is not authorized to perform action on resource.
If role assignments, deny assignments or role definitions were changed
recently, please observe propagation time.
```

Lo hacía la misma cuenta que es **Owner de la suscripción** y que creó todo.

### Impacto
Rompía el paso 3 del runbook (`docs/deployment.md`), que instruía leer la password con `az keyvault secret show`. Sin acceso al vault tampoco se podía **sembrar** la key de TMDB. El ambiente quedaba imposible de configurar para el deploy.

### Hipótesis descartadas
1. ¿Propagación de RBAC? → **No**: el mensaje lo sugiere, pero esperar no cambió nada. La asignación que faltaba nunca existió.
2. ¿El vault tiene firewall o private endpoint? → **No**: `public_network_access_enabled` estaba en `true`.
3. ¿El secreto no existe o tiene otro nombre? → **No**: el error es de *autorización*, previo a resolver el nombre del secreto.

### Evidencia
```powershell
az role assignment list --scope <vault-id> -o table
# Solo aparecía el service principal de CI con 'Key Vault Secrets Officer'.
# La cuenta humana (Owner de la suscripción) no figuraba en el scope del vault.
```

### Diagnóstico
Un Key Vault con `rbac_authorization_enabled = true` separa **dos planos de permisos distintos**:

| Plano | Qué permite | Quién lo tiene |
|---|---|---|
| **Management plane** | Crear, borrar y configurar el vault; ver sus propiedades | `Owner`, `Contributor` |
| **Data plane** | Leer y escribir **el contenido** de los secretos | Solo roles específicos: `Key Vault Secrets Officer`, `Key Vault Secrets User` |

**Owner no incluye el data plane, y es a propósito:** permite que alguien administre la infraestructura del vault (crearlo, aplicarle políticas, borrarlo) sin poder leer los secretos que contiene. Es separación de responsabilidades, no un bug.

La causa concreta en nuestro caso: el módulo de Terraform asigna `Key Vault Secrets Officer` a `data.azurerm_client_config.current.object_id` — es decir, **a quien corra el apply**. Mientras Terraform se corría local, ese "quien" era el operador humano y todo funcionaba. Cuando Genesis pasó a correr en CI, pasó a ser el service principal, y el humano se quedó afuera sin que nada lo avisara.

### Root Cause
Un permiso definido como "quien ejecuta" en vez de "quién necesita acceso", combinado con la suposición de que Owner cubre todo.

### Solución
Script idempotente [`scripts/azure/grant-keyvault-operator-access.ps1`](../scripts/azure/grant-keyvault-operator-access.ps1), que asigna el rol de data plane al operador:

```powershell
./scripts/azure/grant-keyvault-operator-access.ps1 -Environment dev
```

Y, aprovechando el hallazgo, se replanteó el diseño completo de secretos: en vez de que un humano lea la password del vault para copiarla a GitHub Secrets, ahora **`deploy.yml` lee los secretos directamente del Key Vault** en cada despliegue. Una copia menos de la password dando vueltas y un paso manual menos en el runbook.

### Acción preventiva
1. **Management plane ≠ data plane.** Owner/Contributor no dan acceso al contenido de Key Vault, Storage (datos) ni Service Bus. Cada uno tiene sus propios roles de datos.
2. **Cuidado con los permisos atados a "quien ejecuta"** (`azurerm_client_config.current`). Funcionan mientras la identidad no cambie; el día que el apply se mueve de una laptop a CI, cambian de destinatario en silencio. Si alguien **necesita** acceso, nombralo explícitamente.
3. Al mover un `terraform apply` de local a CI, revisar qué permisos dependían de quién lo corría.

---

<a name="ts-11"></a>
## TS-11 — El Ingress tenía IP pública pero el NSG descartaba todo el tráfico

**Sprint 9 · AKS / Azure networking / CD**

### Síntoma
El primer despliegue real llegó correctamente hasta AKS: los Deployments
completaron su rollout y el Ingress recibió una IP pública. Sin embargo, el
smoke test contra `http://<EXTERNAL_IP>/api/movies` no obtenía respuesta. La
conexión quedaba esperando hasta agotar el timeout, en vez de devolver un error
HTTP o un `connection refused` inmediato.

### Impacto
El pipeline consideraba fallido un despliegue cuyos pods ya estaban sanos. El
rollback automático tampoco podía recuperar una versión previa por tratarse del
primer deploy. Además, el `curl` original no tenía límite total por request, así
que un solo paquete descartado podía alargar el job mucho más que los reintentos
aparentemente definidos por el loop.

### Hipótesis descartadas
1. ¿El Ingress todavía no tenía dirección externa? → **No**: Kubernetes ya
   publicaba una IP en `.status.loadBalancer.ingress[0].ip`.
2. ¿Los pods o sus probes estaban fallando? → **No**: ambos rollouts habían
   terminado y los pods estaban Ready.
3. ¿El Load Balancer no exponía los puertos correctos? → **No**: Azure mostraba
   reglas TCP `80 → 80` y `443 → 443` para el ingress administrado.

### Evidencia
El Load Balancer estaba configurado, pero el NSG asociado a la subnet de AKS no
tenía ninguna regla personalizada:

```powershell
az network nsg rule list `
    --resource-group rg-movieops-dev `
    --nsg-name nsg-movieops-dev-aks `
    --output table
# Sin resultados
```

Por tanto solo existían las reglas predeterminadas de Azure:

```text
AllowVnetInBound
AllowAzureLoadBalancerInBound
DenyAllInBound
```

La segunda permite los **health probes** del Load Balancer, no el tráfico real
de clientes. Un Standard Load Balancer conserva la IP de origen del cliente; el
NSG ve una IP de Internet y la request termina en `DenyAllInBound`. El descarte
silencioso explica el timeout: no había ningún proceso rechazando activamente la
conexión.

### Diagnóstico
Se confundieron dos flujos distintos que atraviesan el mismo Load Balancer:

| Flujo | Origen que evalúa el NSG | Regla necesaria |
|---|---|---|
| Health probe | Service tag `AzureLoadBalancer` | La regla default ya lo permite |
| Request del usuario | IP pública original del cliente | Regla explícita desde `Internet` |

El Load Balancer estaba sano precisamente porque sus probes sí pasaban, aunque
el tráfico de usuario estuviera bloqueado.

### Root Cause
Se asoció un NSG propio a la subnet de AKS sin declarar los puertos de entrada
de la aplicación. El default `AllowAzureLoadBalancerInBound` se interpretó como
si autorizara todo el tráfico que atraviesa el Load Balancer, cuando solo cubre
su infraestructura de probes.

### Solución
Terraform declara ahora la regla que faltaba:

```hcl
resource "azurerm_network_security_rule" "allow_http_inbound" {
  name                        = "AllowHttpInbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["80", "443"]
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.aks.name
}
```

Los puertos coinciden con las reglas reales del Load Balancer del addon
`web_app_routing`. La regla se aplicó mediante `genesis.yml`; no se ejecutaron
comandos manuales mutantes fuera de Terraform. El siguiente CD terminó con los
dos Deployments en `2/2` y respuestas HTTP 200 desde frontend y API.

El smoke test también quedó acotado y observable:

- Cada request tiene un máximo total de 8 segundos (`curl -m 8`).
- Los fallos de transporte conservan el exit code de `curl` y no se confunden
  con una respuesta HTTP.
- El presupuesto combinado de reintentos cabe dentro del timeout de 7 minutos
  del step.

### Acción preventiva
1. En un Standard Load Balancer, modelar por separado probes y tráfico de
   aplicación; que el backend figure healthy no prueba accesibilidad pública.
2. Toda subnet con NSG propio debe declarar explícitamente los puertos públicos
   que consume el Load Balancer.
3. Todo smoke test de red debe limitar conexión **y transferencia completa**, no
   depender de los timeouts por defecto del cliente.
4. Comparar el presupuesto máximo de los loops con `timeout-minutes`; la defensa
   externa debe ser mayor que la suma de los deadlines internos.

---

<a name="ts-12"></a>
## TS-12 — Apocalipsis eliminó la infraestructura, pero dejó el Resource Group

**Sprint 9 · Terraform / AzureRM / destrucción controlada**

### Síntoma

`apocalipsis.yml` avanzó durante varios minutos y eliminó los recursos
administrados, pero falló al destruir `rg-movieops-dev`:

```text
Error: deleting Resource Group "rg-movieops-dev":
the Resource Group still contains Resources.

Microsoft.OperationsManagement/solutions/
ContainerInsights(log-movieops-dev)
```

En el portal, ese `ContainerInsights(...)` era el único recurso restante.

### Impacto

La mayor parte del ambiente dejó de existir, pero el workflow quedó rojo y el
Resource Group no cumplió el contrato operativo de Apocalipsis: eliminar el
ambiente completo sin afectar el backend remoto del state.

### Evidencia

Una versión anterior del módulo AKS habilitaba `oms_agent`, que hizo que Azure
creara una solución `Microsoft.OperationsManagement/solutions`. Después se
retiró el addon para respetar la estrategia portable de observabilidad, pero la
solución auxiliar permaneció y nunca formó parte del state como recurso
Terraform independiente.

Además, el provider estaba usando su configuración predeterminada:

```hcl
provider "azurerm" {
  features {}
}
```

En AzureRM 4.x, `resource_group.prevent_deletion_if_contains_resources` vale
`true` por defecto. La protección detectó correctamente el recurso no
administrado y bloqueó la eliminación del grupo.

### Root Cause

El contrato del Resource Group y el comportamiento del provider no estaban
alineados. `rg-movieops-dev` es deliberadamente desechable y exclusivo del
ambiente, pero Terraform estaba configurado para preservar cualquier Resource
Group que contuviera incluso un recurso auxiliar fuera del state.

### Solución

El provider permite ahora la eliminación en cascada del Resource Group:

```hcl
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
```

Esto no pone en riesgo `rg-movieops-tfstate`: el backend vive en otro Resource
Group, no está declarado en la configuración del ambiente y, por tanto, nunca
es el target del recurso `azurerm_resource_group.main`.

`apocalipsis.yml` también inicia sesión en Azure CLI mediante OIDC y verifica
después del apply que `rg-movieops-<ambiente>` ya no exista. La verificación
tiene reintentos acotados para tolerar la eliminación asíncrona de Azure; si el
grupo sobrevive, muestra sus recursos residuales y mantiene el job en rojo.

### Acción preventiva

1. Un Resource Group eliminable en cascada debe contener exclusivamente
   recursos del mismo ambiente y propósito.
2. Los backends de state y otros recursos persistentes deben vivir en grupos
   separados.
3. Un destroy no se considera exitoso solo porque `terraform apply` terminó:
   debe comprobarse la ausencia del boundary que representa el ambiente.
4. Todo recurso implícito creado por addons administrados debe evaluarse al
   habilitar y al retirar el addon.

---

<a name="ts-13"></a>
## TS-13 — El bootstrap creó los Environments, pero falló al recibir cero checks

**Azure DevOps parity · PowerShell / bootstrap idempotente**

### Síntoma

El paso 02 creó correctamente los tres Azure DevOps Environments y después
terminó con este error:

```text
[CREATED] Environment 'dev' (11).
[CREATED] Environment 'staging' (12).
[CREATED] Environment 'production' (13).
configure-environments.ps1: No se puede enlazar el argumento al parámetro
"ExistingChecks" porque es una matriz vacía.
```

Los Environments aparecían en el portal, pero todavía no tenían Branch control
ni aprobación de `production`.

### Impacto

El bootstrap quedó parcialmente completado. No se creó infraestructura Azure y
no se ejecutó ningún deployment, pero los controles administrativos esperados
aún no protegían los Environments.

No era necesario eliminar los objetos creados: sus nombres e IDs ya eran un
estado parcial válido que el script debía poder reanudar.

### Hipótesis descartadas

1. ¿La API devolvió un error al crear el Environment? → **No**: los IDs 11, 12
   y 13 se devolvieron y los objetos eran visibles en el portal.
2. ¿La cuenta no tenía permisos para administrar checks? → **No todavía**: el
   fallo ocurrió durante el enlace de parámetros de PowerShell, antes del POST
   del primer check.
3. ¿La respuesta vacía era inválida? → **No**: cero checks es precisamente el
   estado esperado de un Environment recién creado.

### Evidencia

La función recibía una colección tipada y obligatoria:

```powershell
param(
    [Parameter(Mandatory)]
    [object[]]$ExistingChecks
)
```

La consulta de un Environment nuevo devolvía `@()`. PowerShell considera que un
parámetro obligatorio no acepta una colección vacía salvo que el contrato lo
indique explícitamente, por lo que nunca se ejecutó la lógica que interpreta
`Count -eq 0` como “crear el check”.

### Diagnóstico

La API y el estado remoto eran correctos. El contrato del parámetro era más
restrictivo que el dominio: `ExistingChecks` debía estar presente, pero también
debía aceptar válidamente cero elementos.

### Root Cause

Faltaba `AllowEmptyCollection` en un parámetro array obligatorio. Se había
modelado correctamente la rama interna para cero resultados, pero el binder de
PowerShell rechazaba ese valor antes de entrar en la función.

### Solución

Se declaró explícitamente la colección vacía como válida:

```powershell
[Parameter(Mandatory)]
[AllowEmptyCollection()]
[object[]]$ExistingChecks
```

Después se repitió `-WhatIf` sobre el estado parcial. El script detectó:

```text
[EXISTS] Environment 'dev' (11).
[EXISTS] Environment 'staging' (12).
[EXISTS] Environment 'production' (13).
What If: Create branch control on 'dev'
What If: Create branch control on 'staging'
What If: Create branch control on 'production'
What If: Create production approval on 'production'
```

Esto confirmó tanto la corrección como la reanudación idempotente. La
recuperación consiste únicamente en volver a ejecutar el script; no se borran
ni recrean los Environments.

### Acción preventiva

1. Todo parámetro array debe definir el significado de cero elementos, no solo
   su tipo y obligatoriedad.
2. Probar los scripts de convergencia desde estado vacío, parcial y completo.
3. Diseñar cada fase para descubrir antes de crear, de modo que una reejecución
   continúe sin rollback destructivo.
4. Ejecutar `-WhatIf` después de corregir un fallo parcial para comprobar el
   plan restante antes de aplicar.

---

<a name="ts-14"></a>
## TS-14 — La ausencia de acceso global provocó un falso fallo de verificación

**Azure DevOps parity · Pipeline Permissions / PowerShell StrictMode**

### Síntoma

El paso 03 creó correctamente el pipeline y autorizó la service connection solo
para él, pero falló en la verificación final:

```text
[CREATED] Pipeline 'MovieOps-Diagnostic' (8); first run skipped.
[UPDATED] 'sc-movieops-azure-wif' authorized only for 'MovieOps-Diagnostic'.
No se encuentra la propiedad "allPipelines" en este objeto.
```

### Impacto

El resultado remoto era válido: el pipeline ID 8 existía y tenía autorización
individual. Sin embargo, el script terminó en rojo y no pudo emitir su evidencia
final ni indicar la ejecución manual del diagnóstico.

No hubo exposición adicional de permisos y no se ejecutó automáticamente el
pipeline.

### Hipótesis descartadas

1. ¿Falló la creación de `MovieOps-Diagnostic`? → **No**: Azure DevOps devolvió
   el ID 8.
2. ¿Falló la autorización WIF? → **No**: el PATCH finalizó y la respuesta de
   lectura contiene el pipeline en `pipelines` con `authorized: true`.
3. ¿La conexión fue autorizada globalmente? → **No**: la API no devolvió
   `allPipelines`, que es cómo representa la ausencia de esa concesión.

### Evidencia

La primera versión hacía acceso directo:

```powershell
$finalPermissions.allPipelines
```

Con `Set-StrictMode -Version Latest`, PowerShell genera una excepción cuando un
`PSCustomObject` no contiene la propiedad solicitada. La API usa una respuesta
dispersa: las propiedades opcionales pueden omitirse en lugar de devolverse con
valor `$null` o `authorized: false`.

### Diagnóstico

Fue un falso negativo del verificador. La ausencia de `allPipelines` no era
drift ni un error del servicio; significaba que **Grant access permission to all
pipelines** permanecía desactivado, exactamente como exige el diseño.

### Root Cause

El script asumía un response shape completo para una API que omite campos
opcionales. Esa suposición era incompatible con StrictMode.

### Solución

La propiedad se consulta de forma segura antes de inspeccionar su valor:

```powershell
$allPipelinesProperty = $finalPermissions.PSObject.Properties['allPipelines']
$allPipelinesAuthorization = if ($null -ne $allPipelinesProperty) {
    $allPipelinesProperty.Value
} else {
    $null
}
```

Solo se considera un fallo cuando la propiedad existe y su campo `authorized`
es verdadero. La recuperación es reejecutar el mismo script; la idempotencia
reutiliza el pipeline y el permiso específico ya creados.

### Acción preventiva

1. Tratar las propiedades opcionales de respuestas REST como ausentes, no solo
   como `$null`.
2. Bajo StrictMode, usar `PSObject.Properties['nombre']` antes de leer campos
   opcionales.
3. Probar verificadores tanto con flags verdaderos como con campos omitidos.
4. Separar claramente fallo de mutación y fallo de post-verificación para que
   la recuperación nunca empiece eliminando recursos válidos.

---

<a name="ts-15"></a>
## TS-15 — La auditoría RBAC combinó dos filtros incompatibles de Azure CLI

**Azure DevOps parity · Azure CLI / auditoría RBAC read-only**

### Síntoma

La auditoría del paso 05 avanzó correctamente hasta la federated credential y
falló al consultar los roles de la identidad:

```text
Azure RBAC lookup failed with exit code 1.
ERROR: group or scope are not required when --all is used
```

### Impacto

La auditoría no alcanzó los controles RBAC posteriores ni produjo su resumen
final. No hubo mutación, revocación o creación de role assignments.

### Evidencia

La invocación contenía simultáneamente:

```powershell
az role assignment list `
  --assignee-object-id $servicePrincipal.id `
  --scope $SubscriptionScope `
  --all
```

La ayuda de la versión instalada de Azure CLI confirma dos modos distintos:
`--scope` limita la consulta a un boundary y `--all` enumera todas las
asignaciones bajo la suscripción. El comando rechaza combinarlos.

### Diagnóstico

Era un error local de construcción de argumentos, no un problema de permisos
RBAC ni de la service connection. La consulta nunca llegó a Azure Resource
Manager.

### Root Cause

Se añadió `--all` para evitar omitir asignaciones, pero el script ya expresaba
el scope exacto requerido. Ambos modos son mutuamente excluyentes en
`az role assignment list`.

### Solución

Conservar únicamente la consulta por scope:

```powershell
az role assignment list `
  --assignee-object-id $servicePrincipal.id `
  --scope $SubscriptionScope
```

La respuesta todavía se filtra localmente con
`$_.scope -eq $SubscriptionScope` para no aceptar roles heredados o asignados a
otro nivel.

### Acción preventiva

1. Validar combinaciones de flags contra `az <grupo> <comando> --help` de la
   versión instalada.
2. Para controles de least privilege, consultar el boundary exacto en vez de
   enumerar toda la suscripción.
3. Diferenciar errores de parsing del CLI de respuestas 401/403 del servicio.
4. Mantener las auditorías sin rollback: una consulta fallida se corrige y se
   reejecuta sobre el mismo estado.

---

<a name="gotchas"></a>
## Gotchas de herramientas y entorno

Fallos menores, de causa evidente una vez vistos, pero que cuestan tiempo la primera vez.

| # | Síntoma | Causa | Solución |
|---|---|---|---|
| G-01 | `COPY MovieOps.sln` falla en el build de Docker: *not found* | El SDK moderno de .NET genera `MovieOps.slnx`, no `.sln` | Se eliminó el `COPY` — el `restore` apunta directo al `.csproj`, la solución no hace falta en la imagen |
| G-02 | `Unable to resolve action 'aquasecurity/trivy-action@0.28.0'` | Los releases usan tag con prefijo `v` (`v0.28.0`) | `gh api repos/aquasecurity/trivy-action/tags` para ver los tags reales; fijado a `v0.36.0` |
| G-03 | Tests de integración: `JSON value could not be converted to WatchStatus` | El `HttpClient` del test deserializa con opciones default, sin el `JsonStringEnumConverter` que sí usa la API | `JsonSerializerOptions` compartido en el test con el mismo converter |
| G-04 | Test falla con 404 tras un POST exitoso | Faltaba `PropertyNameCaseInsensitive = true`: `"id"` (camelCase) no matcheaba `Id`, quedaba `Guid.Empty` silenciosamente | Agregado al `JsonSerializerOptions` del test |
| G-05 | `az` falla con `ImportError: DLL load failed while importing win32file` | Instalación de Azure CLI corrupta (pywin32 incompleto) | `winget upgrade --id Microsoft.AzureCLI` (reinstala la versión x64 limpia) |
| G-06 | Terraform: `exec: "az": executable file not found in %PATH%` aunque `az` funciona en bash | El shim era un script sin extensión: los procesos nativos de Windows solo buscan extensiones de `PATHEXT` (`.exe`/`.cmd`/`.bat`) | Shim `az.cmd` en un directorio que esté en el PATH **real de Windows** (no el que agrega Git Bash) |
| G-07 | `az`: `Can't find token from MSAL cache` después de actualizar el CLI | El formato de caché de tokens cambió entre versiones mayores | `az login --use-device-code` |
| G-08 | Terraform: constraint `>= 1.9` con 1.5.3 instalado | El binario local estaba desactualizado | Se bajó el constraint a `>= 1.5` (no usamos features nuevas). Alternativa: actualizar el binario |
| G-09 | Warning: `enable_rbac_authorization` deprecado en Key Vault | Renombrado en el provider azurerm 4.x | `rbac_authorization_enabled` |
| G-10 | Tras `terraform destroy` queda un recurso `ContainerInsights(...)` huérfano | El addon `oms_agent` de AKS creó un *Solution* fuera del state y la protección predeterminada impidió borrar el Resource Group | Permitir cascade delete solo para el grupo desechable del ambiente y verificar su ausencia; ver TS-12 |
| G-11 | El cliente de base de datos no conecta a `localhost:5432` con el stack levantado | Postgres no publicaba puerto al host: el backend le habla por la red interna de Docker | Agregado `ports: ["5432:5432"]` en `docker-compose.yml` (solo para inspección local) |
| G-12 | Los integration tests fallan con `DockerUnavailableException` y endpoint `npipe://./pipe/docker_engine` | Docker Desktop no está iniciado en la estación Windows; Testcontainers no puede crear PostgreSQL | Iniciar Docker Desktop y verificar `docker info`. En Azure Pipelines, usar `ubuntu-latest`, que incluye Docker; no omitir los tests |

---

## Patrones que se repiten

Mirando los 12 casos profundos juntos, tres causas raíz aparecen una y otra vez:

1. **Algo implícito chocando con algo explícito** (TS-04 service CIDR, TS-06 working-directory, TS-08 formato OIDC, TS-11 reglas default del NSG). Los defaults se eligieron sin conocer tu configuración.
2. **Resolución de nombres / red donde nadie miraba** (TS-01 IPv6, TS-02 puerto secuestrado, TS-05 combinación de URIs). El código estaba bien; el tráfico iba a otro lado.
3. **Estado capturado demasiado temprano** (TS-03 config eager, TS-07 rama apuntando a un commit viejo). El valor era correcto cuando se leyó, y quedó obsoleto después.

Y una lección transversal: **en los 12 casos, el diagnóstico salió de una evidencia concreta** (un log con la URL real, un `Get-NetTCPConnection`, un `git diff`, las reglas efectivas de Azure), no de razonar sobre el código. Reproducir y observar primero; teorizar después.
