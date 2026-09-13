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

Sprint 0 — repository scaffolding. No application code yet; see the plan document for the full roadmap.

## Local development

Not available yet — will be documented once the Docker Compose setup lands (Sprint 5).
