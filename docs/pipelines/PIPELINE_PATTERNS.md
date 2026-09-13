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
| Build Once, Deploy Many | 🔜 | Tagging is in place; actual multi-environment promotion arrives with CD (Sprint 8) |
| Environment Promotion | 🔜 | Sprint 8 |
| Externalized Configuration | ✅ | Images carry no environment-specific config; see `docker-compose.yml` env vars and ADR-0001/0002 |
| Shift Left Security | ✅ | Trivy filesystem scan on every CI run (`security-scan` action); CodeQL SAST (`codeql.yml`); Dependabot (`dependabot.yml`) |
| Health Checks | ✅ | `/health`, `/health/live`, `/health/ready` (backend); container `HEALTHCHECK` (both Dockerfiles) — since Sprint 1/5 |
| Automatic Rollback | 🔜 | Sprint 8 |
| Infrastructure as Code | ✅ | `terraform/modules/azure/{network,postgres,container-registry,secrets,kubernetes,monitoring}` — applied for real against Azure (dev), validated (AKS pulled from ACR with zero `imagePullSecrets`), then destroyed |
| Plan Before Apply | ✅ | `terraform fmt` → `validate` → `plan` (reviewed, 17 resources) → `apply`; automating this into `terraform.yml` with a manual-approval gate is next |
| Blue-Green | 🔜 | Sprint 12 (Argo Rollouts) |
| Canary | 🔜 | Sprint 12 |
| Progressive Delivery | 🔜 | Sprint 12 |

## GitOps patterns

| Pattern | Status | Where |
|---|---|---|
| Git as Source of Truth | 🔜 | Sprint 10-11 (Argo CD) |
| Declarative Deployment | 🔜 | Sprint 9 (Kubernetes manifests) |
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
- **Terraform gets its own pipeline, not a CD stage.** Per plan section 26/40: Terraform provisions the "field" (cluster, network, DB, registry), CD/Argo CD later deploys the "players" (the app) onto it. Mixing them means every app deploy would re-evaluate infrastructure. `terraform.yml` will trigger only on changes under `terraform/**`, and gate `apply` behind a manual approval (GitHub Environment protection) since it's real cost and real infra, unlike `ci.yml`'s Docker builds.
- **ACR now exists for real** (Sprint 7, dev environment) — GHCR remains the CI registry for now (ADR-0001); the app's CD pipeline (Sprint 8+) is what will actually push to ACR for deployment onto AKS.
