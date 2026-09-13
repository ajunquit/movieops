# ADR-0004: GitHub Actions authenticates to Azure via OIDC, not a client secret

## Status

Accepted

## Context

Both `terraform.yml` (plan/apply, pending) and `apocalipsis.yml` (destroy, this sprint) need GitHub Actions to authenticate to Azure. The two common options are: a service principal with a long-lived client secret stored as a GitHub secret, or **workload identity federation (OIDC)** — GitHub issues a short-lived signed token per workflow run, which Azure AD trusts without any stored secret at all.

## Decision

Created an Azure AD App Registration (`github-movieops-terraform`) with **no client secret**. Instead, three federated credentials trust GitHub's OIDC issuer, one per GitHub Environment:

```text
repo:ajunquit/movieops:environment:dev
repo:ajunquit/movieops:environment:staging
repo:ajunquit/movieops:environment:production
```

The service principal has `Contributor` at the subscription scope (see Consequences — this is a lab-scope simplification, not the end state). Workflows set `permissions: id-token: write` and export `ARM_CLIENT_ID` / `ARM_TENANT_ID` / `ARM_SUBSCRIPTION_ID` / `ARM_USE_OIDC=true` as env vars — the `azurerm` Terraform provider picks these up automatically and exchanges the GitHub-issued token for an Azure AD token itself; no `azure/login` action step is needed for Terraform's own auth.

Because the federated credential's `subject` is scoped to `environment:<name>`, a token minted for the `dev` GitHub Environment cannot be used to authenticate a job running against `staging` or `production` — the environment gate isn't just a GitHub-side approval step, it's cryptographically tied to which Azure credentials the job can even obtain.

## Consequences

- No Azure credential ever exists as a long-lived GitHub secret — nothing to rotate, nothing to leak from a workflow log.
- `Contributor` at the **subscription** scope (not per-resource-group) is broader than ideal — the alternative (scoping to `rg-movieops-{dev,staging,production}`) isn't possible until each resource group exists, and `terraform apply` is what creates them. Revisit once all three environments exist: scope down to the three resource groups.
- Locally (this machine), the same Terraform code authenticates via `az login` (Azure CLI auth, the provider's default) — nothing in `providers.tf` had to change; OIDC is purely an env-var-driven override for CI.
