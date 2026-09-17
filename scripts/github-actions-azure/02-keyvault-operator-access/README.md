# Paso 02 — Acceso de datos al Key Vault para un operador humano

## Estado

Movido sin cambios de lógica desde `scripts/github-actions-azure/grant-keyvault-operator-access.ps1`
el 16 de septiembre de 2026, como parte de la reestructuración a pasos
numerados. Resuelve [TS-10](../../../docs/troubleshooting.md#ts-10).

## Objetivo

Dar a un operador humano permiso de **data plane** sobre el Key Vault de un
ambiente, para poder sembrar secretos externos (como la API key de TMDB) que
Terraform no debe gestionar.

**Ser Owner de la suscripción no alcanza.** Key Vault con RBAC separa el
*management plane* (crear/configurar el vault — cubierto por `Owner`) del
*data plane* (leer/escribir el contenido de los secretos — exige un rol
específico).

## Diferencia con los pasos 00 y 01

Este paso **no** es bootstrap de una vez por suscripción: es por-ambiente y
se repite cada vez que un ambiente se crea o recrea (`genesis.yml` crea un
Key Vault nuevo cada vez). Por eso no participa en la auditoría de
[`03-verify-bootstrap`](../03-verify-bootstrap/), que solo cubre invariantes
de una sola vez.

## Script

[`grant-keyvault-operator-access.ps1`](grant-keyvault-operator-access.ps1)

## Qué hace

1. Verifica la sesión de Azure CLI.
2. Resuelve el resource group del ambiente (`rg-movieops-<environment>`) y,
   si no se indica explícitamente, descubre el único Key Vault dentro de él.
3. Por defecto usa la identidad de la sesión activa como principal.
4. Verifica si ya tiene `Key Vault Secrets Officer` en el scope del vault.
5. Si no lo tiene, lo asigna y verifica el resultado.

## Qué no hace

- No crea el Key Vault ni el resource group.
- No siembra ningún secreto; solo otorga el permiso para poder hacerlo
  después con `az keyvault secret set`.
- No otorga el rol a nivel suscripción; el scope es siempre el vault.

## Prerrequisitos

- El ambiente ya fue desplegado (`genesis.yml` corrió al menos una vez).
- Permiso para crear role assignments en el scope del vault (`Owner` o
  `User Access Administrator`/`Role Based Access Control Administrator`).

## Parámetros

| Parámetro | Default | Descripción |
|---|---|---|
| `Environment` | `dev` | Ambiente objetivo |
| `ResourceGroupName` | `rg-movieops-<Environment>` | Resource group del ambiente |
| `VaultName` | Autodescubierto | Key Vault dentro del resource group |
| `PrincipalObjectId` | Usuario con sesión activa | Principal al que se otorga el rol |
| `Role` | `Key Vault Secrets Officer` | Rol de data plane |

## Ejecución

```powershell
./scripts/github-actions-azure/02-keyvault-operator-access/grant-keyvault-operator-access.ps1 -Environment dev -WhatIf
./scripts/github-actions-azure/02-keyvault-operator-access/grant-keyvault-operator-access.ps1 -Environment dev
```

Apuntado explícitamente:

```powershell
./scripts/github-actions-azure/02-keyvault-operator-access/grant-keyvault-operator-access.ps1 `
    -ResourceGroupName 'rg-movieops-dev' `
    -VaultName 'kv-movieops-dev-xxxx' `
    -PrincipalObjectId '00000000-0000-0000-0000-000000000000'
```

## Idempotencia y tratamiento de drift

- Si el rol ya está asignado en el scope del vault, informa `[EXISTS]` y no
  hace nada.
- Más de un Key Vault en el resource group detiene el script; exige
  `-VaultName` explícito.

## Siguiente paso

Con el rol otorgado, sembrar el secreto:

```powershell
az keyvault secret set --vault-name <vault> --name Tmdb--ApiKey --value <valor>
```

Ver [`docs/deployment.md`](../../../docs/deployment.md) para el runbook
completo.
