# CI/CD Pattern Catalog

Tracks which patterns from [MovieOps_DevOps_Plan.md](../../MovieOps_DevOps_Plan.md) are implemented, where, and why. Updated as each sprint lands.

## CI/CD patterns

| Pattern | Status | Where |
|---|---|---|
| Pipeline as Code | ✅ | Everything under `.github/workflows/` and `.github/actions/` |
| Fail Fast | ✅ | `backend-ci.yml` (format → build → unit → integration), `frontend-ci.yml` (type-check → test → build) |
| Fan-Out / Fan-In | ✅ | `ci.yml`: `backend` and `frontend` run in parallel, both feed into `quality-gate` |
| Reusable Pipeline | ✅ | Composite actions in `.github/actions/` (`dotnet-build`, `angular-build`, `docker-build`, `security-scan`); reusable workflows (`backend-ci.yml`, `frontend-ci.yml`, `docker-build.yml`) called via `workflow_call` |
| Quality Gates | ✅ | `quality-gate` job in `ci.yml` — Docker build only runs if backend and frontend CI both pass |
| Immutable Artifact | ✅ | One image per commit, tagged with the git SHA; the same image is meant to move through DEV/STG/PROD once CD exists (Sprint 8) |
| Artifact Versioning | ✅ | `movieops-api:sha-<short-sha>` / `movieops-frontend:sha-<short-sha>`, plus `:latest` on `main` |
| Build Once, Deploy Many | 🟡 | `deploy.yml` uses `az acr import` to copy the exact GHCR image built by `ci.yml` into the target environment's ACR — no rebuild. Code complete, not yet run live |
| Environment Promotion | 🟡 | `cd-dev.yml` / `cd-staging.yml` / `cd-production.yml` — same `image_tag` input flows through all three, `production` gated by required-reviewer. Code complete, not yet run live |
| Externalized Configuration | ✅ | Images carry no environment-specific config; see `docker-compose.yml` env vars, `k8s/base/backend/configmap.yaml`, and ADR-0001/0002 |
| Shift Left Security | ✅ | Trivy filesystem scan on every CI run (`security-scan` action); CodeQL SAST (`codeql.yml`); Dependabot (`dependabot.yml`); Checkov IaC scan on every `genesis.yml` run |
| Health Checks | ✅ | `/health`, `/health/live`, `/health/ready` (backend); container `HEALTHCHECK` (both Dockerfiles); k8s liveness/readiness probes (`k8s/base/*/deployment.yaml`) — since Sprint 1/5/8 |
| Automatic Rollback | 🟡 | `deploy.yml`: `kubectl rollout status` (health gate) + bounded smoke test against the Ingress IP; either failing triggers `kubectl rollout undo`. First live run exposed TS-11; end-to-end revalidation pending |
| Infrastructure as Code | ✅ | `terraform/modules/azure/{network,postgres,container-registry,secrets,kubernetes,monitoring}` — applied for real against Azure (dev), validated (AKS pulled from ACR with zero `imagePullSecrets`), then destroyed |
| Plan Before Apply | ✅ | Done by hand in Sprint 7 (`fmt` → `validate` → `plan` → `apply`); now automated in `genesis.yml` (`workflow_dispatch`, always plans then applies in one gated run), same per-environment GitHub Environments as `apocalipsis.yml` |
| Blue-Green | 🔜 | Sprint 12 (Argo Rollouts) |
| Canary | 🔜 | Sprint 12 |
| Progressive Delivery | 🔜 | Sprint 12 |

## GitOps patterns

| Pattern | Status | Where |
|---|---|---|
| Git as Source of Truth | 🔜 | Sprint 10-11 (Argo CD) |
| Declarative Deployment | 🟡 | `k8s/base/` manifests exist and are declarative (Deployment/Service/Ingress/HPA/ConfigMap) — but applied push-based via `kubectl apply` in CD, not pulled/reconciled by Argo CD yet (Sprint 10) |
| Pull-based Deployment | 🔜 | Sprint 10 |
| Continuous Reconciliation | 🔜 | Sprint 10 |
| Drift Detection | 🔜 | Sprint 10 |
| Git-based Promotion | 🔜 | Sprint 11 |
| Git-based Rollback | 🔜 | Sprint 11 |

## Notes on this sprint's decisions

- **Container registry: GHCR, not ACR yet.** [ADR-0001](../adr/0001-cloud-provider-azure-first.md) commits to Azure/ACR once Terraform provisions it (Sprint 7). Until then, GHCR (`ghcr.io`) is used because it needs zero extra secrets (`GITHUB_TOKEN` is enough) and integrates natively with GitHub Actions. Switching the registry later only touches the `registry` input on the `docker-build` composite action.
- **Docker images build on every PR, but only push on `main`.** This still catches a broken Dockerfile on every PR (Fail Fast) without polluting the registry with throwaway PR builds.
- **`dotnet format --verify-no-changes` and `tsc --noEmit`** are the "cheap" fail-fast steps for backend and frontend respectively — no dedicated linter was introduced for the frontend yet (ESLint setup is a deliberate deferral, not an oversight, to avoid adding tooling the codebase doesn't need yet).
- **Integration tests run in CI**, not just locally — GitHub-hosted `ubuntu-latest` runners have Docker preinstalled, so Testcontainers-based tests (Sprint 4) work unmodified.
- **Terraform gets its own pipeline, not a CD stage.** Per plan section 26/40: Terraform provisions the "field" (cluster, network, DB, registry), CD/Argo CD later deploys the "players" (the app) onto it. Mixing them means every app deploy would re-evaluate infrastructure.
- **`genesis.yml` (create/update) and `apocalipsis.yml` (destroy) are deliberately separate workflows**, not one workflow with a destroy flag — the blast radius and review bar for "make infrastructure" and "delete infrastructure" aren't the same, and keeping them apart means a typo in one can't accidentally trigger the other. Both are `workflow_dispatch`-only (manual), both reuse the same per-environment OIDC federated credentials and GitHub Environment gates (ADR-0004) — `production` requires a reviewer either way.
- **ACR now exists for real** (Sprint 7, dev environment) — GHCR remains the CI registry for now (ADR-0001); the app's CD pipeline (Sprint 8+) is what will actually push to ACR for deployment onto AKS.
- **Sprint 8+9 received their first live CD run.** Kubernetes rollouts completed, but the external smoke test exposed TS-11: the custom subnet NSG admitted Load Balancer probes but not real client traffic. The Terraform fix is ready; full end-to-end revalidation is pending the next Genesis/CD run.
- **Secrets are created imperatively by `deploy.yml`** (`kubectl create secret ... --dry-run=client -o yaml | kubectl apply -f -`) from values read at runtime directly from Key Vault — never as a committed manifest or copied into GitHub Secrets.
- **Ingress via Azure's managed `web_app_routing` addon**, not a hand-installed ingress-nginx Helm chart — same underlying NGINX, zero extra Terraform/Helm plumbing. `dns_zone_ids = []` means no custom domain. The AKS subnet NSG explicitly admits the addon's real Load Balancer ports (`80/443`); the default `AzureLoadBalancer` rule only covers probes (TS-11).
- **HPA owns `backend`'s replica count** (`minReplicas: 2`) — the Deployment manifest deliberately has no `replicas:` field, since setting one would fight the HPA on every `kubectl apply`. `frontend` has no HPA, so it keeps a static `replicas: 2`.
- **`maxUnavailable: 0, maxSurge: 1`** on both Deployments: a real zero-downtime rolling update, not just the strategy's default.
