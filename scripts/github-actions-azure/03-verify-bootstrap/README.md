# Paso 03 — Auditoría read-only del bootstrap

## Estado

Nuevo, escrito el 16 de septiembre de 2026 junto con la reestructuración de
`scripts/github-actions-azure/`. No existía ningún equivalente antes de esta ingeniería
reversa.

## Objetivo

Cerrar el bootstrap de la identidad y el state remoto de GitHub Actions con
una auditoría repetible, exclusivamente de lectura, que pruebe que los pasos
00 y 01 permanecen correctos sin volver a ejecutarlos.

## Script

[`verify-bootstrap.ps1`](verify-bootstrap.ps1)

## Controles auditados

| Área | Control |
|---|---|
| Target | Sesión en la suscripción esperada |
| State remoto | Resource group, storage account (SKU/TLS/acceso público) y container `tfstate` |
| Entra | App Registration dedicada y Service Principal |
| Secretless | Cero passwords y certificados |
| Federación | Issuer, subject y audience coinciden con el prefijo OIDC actual de GitHub, por environment |
| RBAC | `Contributor` + `Role Based Access Control Administrator` en la suscripción |

El script acumula todos los controles; un fallo no detiene la evaluación de
los demás. Al final imprime una tabla y termina con error si existe al menos
un `FAIL`.

## Qué no hace

- No crea, actualiza ni elimina recursos.
- No audita el acceso de datos al Key Vault del paso 02: es por-ambiente y
  no es una invariante de bootstrap único (ver el README de ese paso).
- No corrige drift automáticamente; identifica el paso propietario que debe
  reejecutarse.

## Prerrequisitos

- Pasos 00 y 01 completados.
- Sesión de Azure CLI y de GitHub CLI.
- Acceso de lectura a Entra ID y a Azure RBAC en la suscripción.

## Ejecución

```powershell
./scripts/github-actions-azure/03-verify-bootstrap/verify-bootstrap.ps1
```

No usar `-WhatIf`: no existe ninguna mutación que simular.

## Salida esperada

```text
[PASS] Azure target boundary — ...
[PASS] Terraform state resource group — rg-movieops-tfstate
[PASS] Terraform state storage account baseline — ...
[PASS] Terraform state container — tfstate
[PASS] GitHub Actions App Registration — ...
[PASS] Secretless identity — long-lived credentials=0
[PASS] Service principal — matches=1
[PASS] Federated credential — dev — ...
[PASS] Federated credential — staging — ...
[PASS] Federated credential — production — ...
[PASS] Subscription role — Contributor — ...
[PASS] Subscription role — Role Based Access Control Administrator — ...

Controls: 11; passed: 11; failed: 0.
[VERIFIED] Azure (GitHub Actions track) bootstrap audit completed with zero failures.
[VERIFIED] This script performed read-only operations only.
```

## Interpretación de fallos

| Control | Paso que debe revisarse |
|---|---|
| State remoto | [`00-bootstrap-terraform-state`](../00-bootstrap-terraform-state/) |
| Entra/Secretless/Federación/RBAC | [`01-service-principal-oidc`](../01-service-principal-oidc/) |

No eliminar recursos para "empezar de cero". Reejecutar primero el paso
idempotente propietario del control fallido.

## Siguiente paso

Con cero fallos, el bootstrap de la identidad de GitHub Actions queda
formalmente verificado. Ver [`docs/deployment.md`](../../../docs/deployment.md)
para la receta completa de despliegue.
