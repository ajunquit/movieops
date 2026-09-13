# ADR-0002: Observability stack built for portability, not tied to Azure Monitor

## Status

Accepted

## Context

Following [ADR-0001](./0001-cloud-provider-azure-first.md), MovieOps will run on Azure first and on AWS later. Azure offers a native observability stack (Azure Monitor / Log Analytics) that integrates easily with AKS, but that work does not carry over to EKS.

## Decision

Observability is built on **OpenTelemetry + Prometheus + Grafana, self-hosted inside the Kubernetes cluster**, instead of the cloud provider's native monitoring service.

```text
OpenTelemetry (instrumentation, vendor-neutral)
       ↓
Prometheus (metrics, self-hosted in-cluster)
       ↓
Grafana (dashboards, self-hosted in-cluster)
```

Azure Monitor is not used as the primary observability backend.

## Consequences

- The same Helm charts / Kubernetes manifests for Prometheus and Grafana run unchanged on AKS or EKS — migrating cloud providers does not require rebuilding the observability layer.
- Argo Rollouts canary analysis (`AnalysisTemplate`) queries Prometheus directly, keeping automated progressive delivery decisions portable as well.
- Slightly more setup effort upfront (self-hosting Prometheus/Grafana) compared to enabling a managed Azure service, accepted as the cost of avoiding provider lock-in.
- Azure-native monitoring may still be used informally for infrastructure-level Azure resource health (e.g. AKS control plane), but never as the source of truth for application metrics, dashboards, or Rollouts analysis.
