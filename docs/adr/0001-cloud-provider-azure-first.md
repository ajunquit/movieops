# ADR-0001: Azure as the initial cloud provider, AWS as a planned second implementation

## Status

Accepted

## Context

MovieOps needs a concrete cloud target to provision Terraform modules (network, Kubernetes cluster, managed PostgreSQL, container registry, secrets, monitoring). The lab's stated goal is to eventually reproduce the same platform on AWS as well, not just Azure.

Two options were considered:

1. Build Terraform modules with a multi-cloud abstraction from day one (e.g. a `cloud_provider` variable branching resource logic).
2. Build cleanly for Azure first, and add AWS later as a parallel, separate implementation.

## Decision

Azure is the initial provider. AWS will be added later as a **separate** implementation, not as an abstraction layered on top of the Azure modules.

Terraform is organized by provider from the start, so adding AWS later requires no restructuring:

```text
terraform/
├── modules/
│   ├── azure/   (network, postgres, container-registry, kubernetes, secrets, monitoring)
│   └── aws/     (added when the AWS phase starts)
└── environments/
    └── azure/{dev,staging,production}
        # environments/aws/{dev,staging,production} added later
```

Service mapping for the Azure phase:

| Module              | Azure service                              |
|----------------------|---------------------------------------------|
| network              | VNet, Subnets, NSGs                        |
| postgres              | Azure Database for PostgreSQL Flexible Server |
| container-registry    | Azure Container Registry (ACR)             |
| kubernetes            | AKS                                        |
| secrets                | Azure Key Vault                            |
| monitoring             | Support for self-hosted Prometheus/Grafana (see ADR-0002) |

## Consequences

- No `if var.cloud_provider == "azure"` conditionals in module code — each provider gets its own clean module tree.
- Kubernetes manifests, Argo CD Applications, and application code stay 100% provider-agnostic already; only the `terraform/` tree is provider-specific.
- When the AWS phase starts, it is scoped as its own sprint that reimplements `terraform/modules/aws/` and `terraform/environments/aws/`, reusing lessons learned rather than code.
