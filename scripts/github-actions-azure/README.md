# GitHub Actions → Azure

Bootstrap y operación de la identidad/infraestructura Azure que usan
`genesis.yml`, `apocalipsis.yml` y `deploy.yml`. Reestructurado el 16 de
septiembre de 2026, por ingeniería inversa, para seguir exactamente el mismo
patrón numerado que [`scripts/azure-devops/`](../azure-devops/README.md):
cada paso es una carpeta con su script y su documentación completa.

Se llama `github-actions-azure` y no `azure` porque lo que distingue este
directorio de `azure-devops` es el **orquestador de CI/CD**, no el cloud —
ambos tracks apuntan a Azure. Nombrarlo por el orquestador deja espacio para
un futuro `github-actions-aws` (el plan maestro contempla llevar esto mismo
a AWS) sin tener que volver a renombrar nada.

## Pasos

| Paso | Qué hace | Estado |
|---|---|---|
| [`00-bootstrap-terraform-state`](00-bootstrap-terraform-state/) | Resource group + storage account + container del backend Terraform | Reconstruido — recursos ya existentes verificados |
| [`01-service-principal-oidc`](01-service-principal-oidc/) | App Registration + Service Principal + federated credentials + roles de suscripción | Reconstruido — fusiona dos scripts previos |
| [`02-keyvault-operator-access`](02-keyvault-operator-access/) | Acceso data-plane al Key Vault de un ambiente para un operador humano | Movido sin cambios de lógica |
| [`03-verify-bootstrap`](03-verify-bootstrap/) | Auditoría read-only de los pasos 00 y 01 | Nuevo |

## Por qué "ingeniería inversa" y no solo un rename

Los tres scripts originales (`sync-github-oidc-federated-credentials.ps1`,
`grant-ci-subscription-roles.ps1`, `grant-keyvault-operator-access.ps1`)
cubrían fixes puntuales (TS-08, TS-09, TS-10), pero la identidad misma
(`github-movieops-terraform`: la App Registration, su Service Principal) y
el backend de Terraform (`rg-movieops-tfstate`) se crearon a mano, en una
terminal, sin quedar nunca scripteados — la razón exacta por la que el
Principio 14 del plan maestro existe.

Reconstruir esos pasos como scripts idempotentes no fue un ejercicio
cosmético: cerró un hueco real. Si hoy hubiera que rehacer la suscripción
desde cero, antes de esta reestructuración no había ningún comando
reproducible para recrear la App Registration, el Service Principal o el
Storage Account del state — solo lo que quedó escrito, en prosa, en
[ADR-0003](../../docs/adr/0003-terraform-remote-state-bootstrap.md) y
[ADR-0004](../../docs/adr/0004-github-actions-azure-oidc.md).

## Nivel de bootstrap vs. operación

- **Bootstrap de una vez por suscripción**: pasos `00` y `01`. Auditados por
  `03`.
- **Operación por-ambiente, repetible**: paso `02` — se ejecuta cada vez que
  un ambiente se crea o recrea, no una sola vez en la vida del laboratorio.

Ambos niveles están, por la misma razón que el bootstrap del state remoto
(ver [ADR-0003](../../docs/adr/0003-terraform-remote-state-bootstrap.md)),
fuera de Terraform: son los permisos y la confianza que Terraform **necesita
para poder correr**, así que no puede gestionarlos él mismo.

## Siguiente paso

Con `00`–`01` verificados por `03`, la identidad de CI está lista. El
runbook completo de despliegue está en
[`docs/deployment.md`](../../docs/deployment.md).
