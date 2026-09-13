# MovieOps

Production-grade DevOps reference lab: a small movie catalog app (.NET + Angular + PostgreSQL, integrated with TMDB) used as the vehicle to practice a complete, real delivery cycle — CI/CD, containers, Infrastructure as Code, Kubernetes, GitOps with Argo CD, progressive delivery, security scanning, and observability.

The full plan, roadmap, patterns catalog, and sprint breakdown live in [MovieOps_DevOps_Plan.md](./MovieOps_DevOps_Plan.md). Design decisions are tracked as ADRs in [docs/adr/](./docs/adr/).

## Stack

- **App:** .NET, Angular, PostgreSQL, Entity Framework Core, TMDB API
- **DevOps:** Docker, Docker Compose, Terraform, Kubernetes, Kustomize, Argo CD, Argo Rollouts, GitHub Actions
- **Cloud:** Azure first (AKS, ACR, PostgreSQL Flexible Server, Key Vault); AWS planned as a second implementation later
- **Security:** Trivy, CodeQL, Dependabot, Checkov
- **Observability:** OpenTelemetry, Prometheus, Grafana (self-hosted — kept portable across cloud providers)

## Repository structure

```text
app/            Backend (.NET) and frontend (Angular) source
.github/        CI/CD workflows and reusable actions
k8s/            Kubernetes manifests (base + dev/staging/production overlays)
argocd/         Argo CD Applications and Projects (GitOps)
terraform/      Infrastructure as Code, organized per cloud provider
scripts/        Local automation (build, test, deploy, health checks)
docs/           Architecture, pipeline design, ADRs, incident postmortems
```

## Status

Sprint 5 done — see the plan document for the full roadmap. Backend (.NET, layered), frontend (Angular), TMDB integration, automated tests, and Docker Compose are all in place.

## Local development

```bash
cp .env.example .env   # fill in TMDB_API_KEY and a POSTGRES_PASSWORD
docker compose up --build
```

This builds and starts everything:

- Frontend (nginx + built Angular app): http://localhost:4200
- Backend API (Swagger UI in Development): http://localhost:8080/swagger
- PostgreSQL: internal to the Docker network only (not published to the host)

The backend applies EF Core migrations automatically on startup. Data persists in a named Docker volume (`postgres-data`) across restarts; run `docker compose down -v` to wipe it.

Running the apps outside Docker (e.g. for faster iteration) still works: `dotnet run --project app/backend/src/MovieOps.Api` and `npm start --prefix app/frontend` (the Angular dev server proxies `/api` to `http://localhost:5014`, see `app/frontend/src/proxy.conf.json`).

### Tests

```bash
scripts/test.sh          # fast unit tests only
scripts/test.sh --all    # + integration tests (Testcontainers, needs Docker) + frontend tests
```
