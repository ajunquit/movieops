# Paso 08 — Estabilizar identidades Terraform

## Estado

Completado y verificado: `8/8 PASS`, con plan `19 add, 0 change, 0 destroy` y
ningún apply.

## Objetivo

Eliminar la dependencia de la identidad que ejecuta Terraform antes de crear
Genesis en Azure Pipelines.

Antes:

```hcl
admin_object_id = data.azurerm_client_config.current.object_id
```

Ese valor podía ser el operador, GitHub Actions o Azure DevOps. Alternar el
runner cambiaba el desired state del role assignment de Key Vault.

Ahora el ambiente declara explícitamente:

```hcl
automation_principal_object_ids = {
  github_actions = "36edcd2d-3ad8-4aa7-ad5e-e5998f17da2f"
  azure_devops   = "4fbfb3ed-ea64-4c58-85b2-eec87d5f21fb"
}
```

Son Object IDs públicos del tenant, no credenciales ni secretos.

## Alcance de esta subtask

Este paso únicamente:

1. Modela las dos identidades mediante un mapa estable.
2. Crea los role assignments con `for_each` determinista.
3. Declara un bloque `moved` desde el recurso histórico hacia
   `github_actions` para conservar estado.
4. Verifica ambas App Registrations/Service Principals sin secrets.
5. Ejecuta `terraform fmt`, `init`, `validate` y un plan sin refresh.
6. Inspecciona el plan JSON y rechaza la eliminación del permiso GitHub.

No crea el pipeline Genesis, no ejecuta `terraform apply` y no crea recursos
Azure.

## Archivos Terraform modificados

- `terraform/environments/azure/dev/variables.tf`
- `terraform/environments/azure/dev/main.tf`
- `terraform/modules/azure/secrets/variables.tf`
- `terraform/modules/azure/secrets/main.tf`

## Script

[`verify-terraform-identities.ps1`](verify-terraform-identities.ps1)

## Prerrequisitos

- PowerShell 7, Azure CLI y Terraform.
- Sesión Azure activa en el tenant del laboratorio.
- Acceso read-only al backend `rg-movieops-tfstate`.
- ADOP-2 cerrado con `12/12 PASS`.
- Cambios Terraform revisados localmente.

## Parámetros

| Parámetro | Default | Uso |
|---|---|---|
| `GitHubApplicationDisplayName` | `github-movieops-terraform` | Identidad GitHub |
| `AzureDevOpsApplicationDisplayName` | `azure-devops-movieops-wif` | Identidad Azure DevOps |
| `ExpectedGitHubObjectId` | Object ID validado | Desired state GitHub |
| `ExpectedAzureDevOpsObjectId` | Object ID validado | Desired state Azure DevOps |
| `EnvironmentPath` | `terraform/environments/azure/dev` | Root module auditado |

## Ejecución

Desde la raíz del repositorio:

```powershell
./scripts/azure-devops/08-stabilize-terraform-identities/verify-terraform-identities.ps1
```

También puede ejecutarse desde la carpeta del paso:

```powershell
./verify-terraform-identities.ps1
```

## Interpretación

El script es read-only respecto de Azure. `terraform init` puede actualizar el
cache local ignorado `.terraform/`; el plan se escribe en el directorio temporal
del sistema y siempre se elimina. No existe modo apply.

Una acción `create` es normal cuando Apocalipsis dejó el ambiente apagado. Una
acción `delete` sobre `github_actions` falla el gate porque indicaría revocación
de su acceso.

## Salida esperada

```text
[PASS] GitHub Actions service principal
[PASS] Azure DevOps service principal
[PASS] Terraform is runner-independent
[PASS] Terraform formatting
[PASS] Terraform validation
[PASS] Terraform plan generated
[PASS] Stable Key Vault identity: github_actions
[PASS] Stable Key Vault identity: azure_devops
Controls: 8; PASS: 8; FAIL: 0
[VERIFIED] Terraform automation identities are stable. Genesis pipeline work may begin.
```

## Siguiente subtask

Solo después de `8/8 PASS`, crear el paso 09 y
`azure-pipelines/genesis.yml`. Genesis será una pipeline manual separada con su
propio script, documentación, ejecución y gate.
