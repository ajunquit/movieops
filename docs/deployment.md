# Runbook: crear un ambiente desde cero y desplegar `main`

Receta operativa usando los workflows existentes (`ci.yml`, `genesis.yml`, `apocalipsis.yml`, `cd-*.yml` → `deploy.yml`). `dev` es el ambiente implementado y validado; `staging`/`production` seguirán el mismo flujo cuando tengan configuración Terraform propia (y `production` pedirá aprobación de un reviewer en cada paso que toque ese Environment).

Para entender responsabilidades, arquitectura y la diferencia entre Microsoft
Azure y Azure DevOps, ver [CI/CD e infraestructura: flujo implementado](ci-cd.md).

## 0. Prerrequisito (una sola vez)

Confirmar que `genesis.yml`, `deploy.yml` y los manifiestos de `k8s/base`
(Namespace/Ingress/HPA) estén en `main`. Sin esto, los pasos siguientes fallan.

Verificar que las credenciales OIDC de Entra ID coincidan con el sujeto que
GitHub emite actualmente. La sincronización es idempotente:

```powershell
./scripts/azure/sync-github-oidc-federated-credentials.ps1
```

Este paso también debe repetirse si el repositorio se crea, renombra o
transfiere. Para diagnóstico detallado de `AADSTS700213`, ver
[`TS-08`](troubleshooting.md#ts-08).

## 1. CI construye el artefacto

No hay que disparar nada a mano: `ci.yml` corre automáticamente en cada push/merge a `main` — build + tests de backend y frontend en paralelo, quality gate, y `docker-build.yml` empuja `movieops-api:sha-<corto>` y `movieops-frontend:sha-<corto>` a GHCR.

**Anotá el tag SHA** del commit que querés desplegar (lo ves en el log del job `Docker Build`, o corriendo `git rev-parse --short HEAD` sobre ese commit).

## 2. Genesis: crear la infraestructura de `dev`

GitHub → **Actions** → **Genesis (Create Infrastructure)** → *Run workflow*:

- `environment`: `dev`
- `confirm`: `dev` (tiene que matchear exacto o aborta sin tocar nada)

Esto corre `fmt → init → validate → Checkov → plan → apply` contra `terraform/environments/azure/dev` y crea: resource group, VNet + NSG (entrada pública explícita en `80/443`), AKS (con el addon de Ingress), ACR, Postgres Flexible Server, Key Vault y Log Analytics. Tarda ~10-15 min (AKS es lo lento). Si el Ingress obtiene IP pero el tráfico expira, ver [TS-11](troubleshooting.md#ts-11).

## 3. Sembrar los secretos externos en Key Vault (una sola vez por ambiente)

**Key Vault es la única fuente de verdad de los secretos de aplicación.** `deploy.yml` los lee de ahí en cada despliegue — no hay que copiarlos a GitHub Secrets. En GitHub solo viven los identificadores de Azure para el OIDC (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`), que no son secretos.

Cada secreto llega al vault de forma distinta según quién lo origine:

| Secreto | Origen | Cómo llega al vault |
|---|---|---|
| `postgres-admin-password` | Terraform lo **genera** (`random_password`) | Automático: Genesis lo escribe. **Nada que hacer** |
| `tmdb-api-key` | **Externo**, lo emite un tercero | A mano, una sola vez — nunca por Terraform, porque terminaría en texto plano en el state |

Para sembrar la key de TMDB necesitás acceso de datos al vault. Ojo: **ser Owner de la suscripción no alcanza** — Key Vault con RBAC exige un rol de plano de datos explícito (ver [TS-10](troubleshooting.md#ts-10)):

```powershell
# Una sola vez por ambiente: te asigna Key Vault Secrets Officer sobre el vault
./scripts/azure/grant-keyvault-operator-access.ps1 -Environment dev

# Sembrar la key (el valor nunca pasa por GitHub ni por el repo)
az keyvault secret set `
    --vault-name <kv-movieops-dev-xxxx> `
    --name tmdb-api-key `
    --value '<tu api key de TMDB>' `
    --content-type 'TMDB API read access token'
```

Solo hay que repetirlo si recreás el ambiente desde cero o si rotás la key.

## 4. CD: desplegar el tag elegido a `dev`

GitHub → **Actions** → **CD - Dev** → *Run workflow*:

- `image_tag`: el `sha-<corto>` del paso 1

Esto corre `deploy.yml`: login OIDC → credenciales de AKS → `az acr import` (promueve la MISMA imagen de GHCR a ACR de `dev`, sin rebuild) → lee Key Vault y crea/actualiza el Secret de Kubernetes → `kustomize set image` → `kubectl apply -k k8s/base` → espera rollout healthy → smoke test acotado contra el Ingress → rollback automático si algo falla.

## 5. Verificar

```bash
az aks get-credentials --resource-group rg-movieops-dev --name aks-movieops-dev
kubectl get pods -n movieops
IP=$(kubectl get ingress movieops -n movieops -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$IP/            # frontend
curl http://$IP/api/movies  # backend, via el mismo Ingress
```

## 6. Cuando termines: destruir para no seguir pagando

GitHub → **Actions** → **Apocalipsis (Destroy Infrastructure)** → `environment: dev`, `confirm: dev`.

---

## Resumen visual

```text
push/merge a main
      ↓
   ci.yml  (automático)  →  imagen en GHCR (sha-XXXXXXX)
      ↓
 genesis.yml  (manual)   →  infraestructura de <ambiente> + password de Postgres en Key Vault
      ↓
 [sembrar tmdb-api-key]  →  una sola vez por ambiente, directo al Key Vault
      ↓
cd-<ambiente>.yml        →  deploy.yml: lee los secretos del Key Vault, promueve la imagen,
                            aplica k8s, health-check, rollback si falla
      ↓
apocalipsis.yml (manual) →  destruye <ambiente> cuando termines
```
