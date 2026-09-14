# Runbook: crear un ambiente desde cero y desplegar `main`

Receta operativa usando los workflows existentes (`ci.yml`, `genesis.yml`, `apocalipsis.yml`, `cd-*.yml` → `deploy.yml`). Ejemplo con `dev`; `staging`/`production` siguen el mismo flujo cambiando el nombre del ambiente (y `production` pide aprobación de un reviewer en cada paso que toca ese Environment).

## 0. Prerrequisito (una sola vez)

Mergear los PRs pendientes que dejan `genesis.yml` y los manifiestos de `k8s/base` (Namespace/Ingress/HPA) en `main`. Sin esto, los pasos siguientes fallan.

## 1. CI construye el artefacto

No hay que disparar nada a mano: `ci.yml` corre automáticamente en cada push/merge a `main` — build + tests de backend y frontend en paralelo, quality gate, y `docker-build.yml` empuja `movieops-api:sha-<corto>` y `movieops-frontend:sha-<corto>` a GHCR.

**Anotá el tag SHA** del commit que querés desplegar (lo ves en el log del job `Docker Build`, o corriendo `git rev-parse --short HEAD` sobre ese commit).

## 2. Genesis: crear la infraestructura de `dev`

GitHub → **Actions** → **Genesis (Create Infrastructure)** → *Run workflow*:

- `environment`: `dev`
- `confirm`: `dev` (tiene que matchear exacto o aborta sin tocar nada)

Esto corre `fmt → init → validate → Checkov → plan → apply` contra `terraform/environments/azure/dev` y crea: resource group, VNet, AKS (con el addon de Ingress), ACR, Postgres Flexible Server, Key Vault, Log Analytics. Tarda ~10-15 min (AKS es lo lento).

## 3. Cargar los secretos que `deploy.yml` necesita

**Gap conocido — todavía manual.** `genesis.yml` no publica automáticamente estos valores como GitHub Secrets; hay que hacerlo a mano después de cada `apply`:

```bash
# Password de Postgres (Terraform la generó y la guardó en Key Vault, nunca en texto plano)
PGPASS=$(az keyvault secret show --vault-name kv-movieops-dev-<sufijo> --name postgres-admin-password --query value -o tsv)

# FQDN del server (sale de terraform output, o del log de Genesis)
PGFQDN=$(cd terraform/environments/azure/dev && terraform output -raw postgres_fqdn)

gh secret set BACKEND_DB_CONNECTION_STRING --body "Host=$PGFQDN;Port=5432;Database=movieops;Username=movieopsadmin;Password=$PGPASS"
gh secret set TMDB_API_KEY --body "<tu api key de TMDB>"
```

Solo hace falta repetirlo si el secreto cambia o si se recreó el ambiente (una password nueva sale de cada `apply` que reemplaza el Postgres).

## 4. CD: desplegar el tag elegido a `dev`

GitHub → **Actions** → **CD - Dev** → *Run workflow*:

- `image_tag`: el `sha-<corto>` del paso 1

Esto corre `deploy.yml`: login OIDC → credenciales de AKS → `az acr import` (promueve la MISMA imagen de GHCR a ACR de `dev`, sin rebuild) → crea/actualiza el Secret de Kubernetes desde los GitHub Secrets → `kustomize set image` → `kubectl apply -k k8s/base` → espera rollout healthy → smoke test contra el Ingress → rollback automático si algo falla.

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
 genesis.yml  (manual)   →  infraestructura de <ambiente> en Azure
      ↓
 [cargar secretos]       →  BACKEND_DB_CONNECTION_STRING, TMDB_API_KEY
      ↓
cd-<ambiente>.yml        →  deploy.yml: promueve la imagen, aplica k8s, health-check, rollback si falla
      ↓
apocalipsis.yml (manual) →  destruye <ambiente> cuando termines
```
