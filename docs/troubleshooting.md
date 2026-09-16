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
| G-10 | Tras `terraform destroy` queda un recurso `ContainerInsights(...)` huérfano | El addon `oms_agent` de AKS crea un *Solution* que Terraform no gestiona directamente | Se borra al eliminar el resource group (que es lo que hace el destroy completo) |
| G-11 | El cliente de base de datos no conecta a `localhost:5432` con el stack levantado | Postgres no publicaba puerto al host: el backend le habla por la red interna de Docker | Agregado `ports: ["5432:5432"]` en `docker-compose.yml` (solo para inspección local) |

---

## Patrones que se repiten

Mirando los 7 casos profundos juntos, tres causas raíz aparecen una y otra vez:

1. **Algo implícito chocando con algo explícito** (TS-04 service CIDR, TS-06 working-directory). Los defaults se eligieron sin conocer tu configuración.
2. **Resolución de nombres / red donde nadie miraba** (TS-01 IPv6, TS-02 puerto secuestrado, TS-05 combinación de URIs). El código estaba bien; el tráfico iba a otro lado.
3. **Estado capturado demasiado temprano** (TS-03 config eager, TS-07 rama apuntando a un commit viejo). El valor era correcto cuando se leyó, y quedó obsoleto después.

Y una lección transversal: **en los 7 casos, el diagnóstico salió de una evidencia concreta** (un log con la URL real, un `Get-NetTCPConnection`, un `git diff`), no de razonar sobre el código. Reproducir y observar primero; teorizar después.
