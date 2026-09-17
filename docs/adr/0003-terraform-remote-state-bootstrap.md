# ADR-0003: Terraform remote state bootstrapped by hand, outside Terraform

## Status

Accepted

## Context

Terraform's `azurerm` backend needs a Storage Account + blob container to exist *before* `terraform init` can configure it — a classic chicken-and-egg problem: Terraform can't manage the very storage that holds its own state, at least not on the first run.

## Decision

The state backend (`rg-movieops-tfstate` resource group, `stmovieopstfstate` storage account, `tfstate` container) is created once, outside any Terraform run. It is **not** destroyed when environments are torn down, and it is **not** managed by any `terraform/environments/*` configuration.

It was originally created by hand, with raw `az cli` commands that left no reproducible trace. That gap was closed by reverse-engineering it into an idempotent script — [`scripts/github-actions-azure/00-bootstrap-terraform-state/bootstrap-terraform-state.ps1`](../../scripts/github-actions-azure/00-bootstrap-terraform-state/bootstrap-terraform-state.ps1) — which now owns this bootstrap:

```powershell
./scripts/github-actions-azure/00-bootstrap-terraform-state/bootstrap-terraform-state.ps1
```

Each environment's `backend.tf` points at this same storage account, with a distinct blob key per environment (`dev.terraform.tfstate`, `staging.terraform.tfstate`, `production.terraform.tfstate`), so all environments share one bootstrap but never share state files.

## Consequences

- One manual, one-time step outside "everything is Terraform" — acceptable because it happens exactly once per Azure subscription, not per environment or per apply.
- `terraform destroy` on any environment (`dev`, later `staging`/`production`) never touches the state backend itself — there is no `azurerm_storage_account` resource for it anywhere in `terraform/`.
- Losing or corrupting this storage account would strand every environment's state; it is intentionally kept in its own resource group, separate from anything that gets destroyed/recreated during normal lab iteration.
