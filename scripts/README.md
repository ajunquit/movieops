# Scripts

Automatizaciones locales organizadas por dominio.

```text
scripts/
├── github-actions-azure/   Bootstrap y verificación de Azure para el track GitHub Actions
├── azure-devops/           Bootstrap y verificación de Azure DevOps
└── test.sh                 Ejecución de tests locales del producto
```

## Azure DevOps

Los pasos están numerados y cada carpeta contiene el script junto con su
documentación completa. Ver el
[`índice de bootstrap Azure DevOps`](azure-devops/README.md).

Primer paso disponible:

- [`00-bootstrap-project`](azure-devops/00-bootstrap-project/): crea o verifica
  el Project privado `MovieOps`.

## GitHub Actions → Azure

Igual que Azure DevOps, los pasos están numerados y cada carpeta contiene el
script junto con su documentación completa. Ver el
[`índice de bootstrap`](github-actions-azure/README.md).

Pasos disponibles:

- [`00-bootstrap-terraform-state`](github-actions-azure/00-bootstrap-terraform-state/):
  crea o verifica el resource group, storage account y container del backend
  remoto de Terraform.
- [`01-service-principal-oidc`](github-actions-azure/01-service-principal-oidc/):
  crea o verifica la App Registration, el Service Principal, las federated
  credentials de GitHub Actions (`dev`/`staging`/`production`) y los roles de
  suscripción del service principal de CI.
- [`02-keyvault-operator-access`](github-actions-azure/02-keyvault-operator-access/):
  otorga acceso data-plane al Key Vault de un ambiente a un operador humano —
  operación por-ambiente, repetible, no bootstrap de una sola vez.
- [`03-verify-bootstrap`](github-actions-azure/03-verify-bootstrap/): auditoría
  read-only de los pasos `00` y `01`.

Esta carpeta se llama `github-actions-azure` y no `azure` porque lo que la
distingue de `azure-devops` es el orquestador de CI/CD, no el cloud — ambas
apuntan a Azure. El nombre deja espacio para un futuro `github-actions-aws`
sin volver a renombrar nada.

Esta estructura reemplazó, el 16 de septiembre de 2026, tres scripts sueltos
(`sync-github-oidc-federated-credentials.ps1`, `grant-ci-subscription-roles.ps1`,
`grant-keyvault-operator-access.ps1`) que cubrían fixes puntuales pero dejaban
sin scriptear la identidad y el backend de Terraform en sí — creados
originalmente a mano. Se reconstruyeron por ingeniería inversa: ver el
["por qué"](github-actions-azure/README.md#por-qué-ingeniería-inversa-y-no-solo-un-rename)
en el índice de ese directorio.

