# Paso 01 — Identidad OIDC para GitHub Actions

## Estado

Reconstruido por ingeniería inversa el 16 de septiembre de 2026. La App
Registration, el Service Principal y los roles de suscripción ya existían —
creados a mano en el Sprint 7 y corregidos ad-hoc en [TS-09](../../../docs/troubleshooting.md#ts-09).
Las federated credentials sí tenían script propio
(`sync-github-oidc-federated-credentials.ps1`), ahora fusionado aquí. La
primera ejecución del script fusionado verificó todo como `[EXISTS]`.

## Objetivo

Dar a `genesis.yml` / `apocalipsis.yml` una identidad sin secretos de larga
duración, confiando en el token OIDC que GitHub emite por cada ejecución:

```text
GitHub Actions Environment (dev/staging/production)
        │ token OIDC (issuer + subject inmutable)
        ▼
Entra App: github-movieops-terraform  (cero client secrets)
        │ federated credential por environment
        ▼
Service Principal
        │ Contributor + RBAC Administrator
        ▼
Subscription
```

## Script

[`configure-service-principal.ps1`](configure-service-principal.ps1)

## Qué hace

1. Verifica sesión de Azure CLI y de GitHub CLI.
2. Busca la App Registration `github-movieops-terraform`.
   - Si no existe, la crea (`AzureADMyOrg`, sin credenciales).
   - Si existe, verifica que tenga **cero** passwords/certificados.
3. Busca o crea su Service Principal.
4. Consulta a GitHub el prefijo OIDC efectivo del repositorio
   (`sub_claim_prefix`, formato inmutable `OWNER@OWNER-ID/REPO@REPO-ID` — ver
   [TS-08](../../../docs/troubleshooting.md#ts-08)).
5. Crea o sincroniza una federated credential por cada environment
   (`dev`, `staging`, `production`).
6. Asigna al Service Principal, en el scope de la suscripción:
   - `Contributor`.
   - `Role Based Access Control Administrator` (sin este rol, Terraform no
     puede crear sus propios `azurerm_role_assignment` — ver [TS-09](../../../docs/troubleshooting.md#ts-09)).
7. Verifica el estado final de credenciales y roles.

## Qué no hace

- No otorga `Owner` ni `User Access Administrator`.
- No crea infraestructura Azure.
- No da acceso de datos a ningún Key Vault (ver paso 02).
- No modifica la identidad `azure-devops-movieops-wif` del track de Azure
  DevOps.

## Prerrequisitos

- Paso 00 completado (el backend de Terraform ya debe existir).
- PowerShell 7, Azure CLI y GitHub CLI (`gh`) autenticados.
- Permiso para crear App Registrations/Service Principals en Entra ID.
- `Owner` o una combinación que permita crear role assignments en la
  suscripción.

## Parámetros

| Parámetro | Default | Descripción |
|---|---|---|
| `ApplicationDisplayName` | `github-movieops-terraform` | App Registration dedicada |
| `Repository` | `ajunquit/movieops` | Repositorio GitHub cuyo OIDC se confía |
| `Environments` | `dev`, `staging`, `production` | Environments con federated credential propia |
| `SubscriptionId` | Suscripción activa | Scope de los role assignments |
| `Roles` | `Contributor`, `Role Based Access Control Administrator` | Roles mínimos que necesita Terraform hoy |

## Ejecución

```powershell
./scripts/github-actions-azure/01-service-principal-oidc/configure-service-principal.ps1 -WhatIf
./scripts/github-actions-azure/01-service-principal-oidc/configure-service-principal.ps1
```

Reejecución idempotente: debe reportar `[EXISTS]` para App Registration,
Service Principal, cada federated credential y ambos roles.

## Cuándo volver a ejecutarlo

- Después de crear, renombrar o transferir el repositorio.
- Ante `AADSTS700213` (sujeto OIDC desincronizado).
- Ante `403 AuthorizationFailed` sobre `roleAssignments/write` durante
  `genesis.yml`.

## Idempotencia y tratamiento de drift

- Más de una App Registration o Service Principal con el mismo nombre
  detiene el script.
- Una App Registration existente con passwords o certificados detiene el
  script; no los elimina automáticamente.
- Las federated credentials convergen al `sub_claim_prefix` actual de
  GitHub; los roles existentes no se duplican.

## Siguiente paso

La identidad de CI queda lista para `genesis.yml`/`apocalipsis.yml`. El
acceso de datos a Key Vault para un operador humano se gestiona por separado
en [`02-keyvault-operator-access`](../02-keyvault-operator-access/), porque
solo aplica una vez que un environment concreto ya fue desplegado.
