# Paso 00 — Bootstrap del state remoto de Terraform

## Estado

Reconstruido por ingeniería inversa el 16 de septiembre de 2026. Los recursos
ya existían — creados a mano en su momento — y el script los verificó como
`[EXISTS]` sin recrear nada. Ver [ADR-0003](../../../docs/adr/0003-terraform-remote-state-bootstrap.md).

## Objetivo

Crear o verificar el Storage Account que sostiene el backend `azurerm` de
Terraform, **fuera** de cualquier `terraform apply`:

```text
rg-movieops-tfstate/
└── stmovieopstfstate (StorageV2, Standard_LRS, TLS1.2, sin acceso público)
    └── tfstate/  (blob container)
        ├── dev.terraform.tfstate
        ├── staging.terraform.tfstate
        └── production.terraform.tfstate
```

Este es el clásico problema del huevo y la gallina: Terraform no puede
gestionar el almacenamiento que guarda su propio estado en el primer `init`.

## Script

[`bootstrap-terraform-state.ps1`](bootstrap-terraform-state.ps1)

## Qué hace

1. Verifica la sesión de Azure CLI y muestra la suscripción activa.
2. Busca el resource group `rg-movieops-tfstate`; lo crea si falta.
3. Busca la storage account `stmovieopstfstate`; si existe, verifica que
   cumpla el baseline de seguridad (SKU, `StorageV2`, TLS 1.2, sin acceso
   público a blobs, solo HTTPS). Si no lo cumple, se detiene sin corregirlo
   silenciosamente.
4. Si no existe, la crea con ese mismo baseline.
5. Busca el blob container `tfstate`; lo crea si falta.
6. Verifica el estado final de los tres recursos.

## Qué no hace

- No crea ni gestiona ningún `backend.tf` de `terraform/environments/*`.
- No es destruido nunca por `apocalipsis.yml`: vive en su propio resource
  group, separado de todo lo que se recrea en cada ciclo del laboratorio.
- No usa ni imprime la clave de la storage account: las operaciones de
  contenedor dependen del permiso de control (`Contributor`/`Owner`), no de
  una clave que haya que manejar.

## Prerrequisitos

- PowerShell 7 o superior.
- Azure CLI con sesión activa (`az login`).
- Permiso para crear resource groups y storage accounts en la suscripción
  (típicamente `Contributor` u `Owner`).

## Parámetros

| Parámetro | Default | Descripción |
|---|---|---|
| `ResourceGroupName` | `rg-movieops-tfstate` | Resource group dedicado al state |
| `Location` | `eastus2` | Región |
| `StorageAccountName` | `stmovieopstfstate` | Storage account del backend |
| `ContainerName` | `tfstate` | Blob container que aloja los `.tfstate` |
| `Sku` | `Standard_LRS` | SKU de la storage account |

## Ejecución

```powershell
./scripts/github-actions-azure/00-bootstrap-terraform-state/bootstrap-terraform-state.ps1 -WhatIf
./scripts/github-actions-azure/00-bootstrap-terraform-state/bootstrap-terraform-state.ps1
```

Reejecución idempotente: el mismo comando una segunda vez debe reportar
`[EXISTS]` en los tres recursos.

## Idempotencia y tratamiento de drift

- Cada recurso se busca antes de crearse.
- Un baseline distinto (otro SKU, TLS antiguo, acceso público habilitado) en
  la storage account existente detiene el script; no lo corrige en silencio.
- No elimina ni reemplaza recursos.

## Siguiente paso

Con el state remoto verificado, continuar con
[`01-service-principal-oidc`](../01-service-principal-oidc/).
