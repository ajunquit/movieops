# Scripts

Automatizaciones locales organizadas por dominio.

```text
scripts/
├── azure/      Operaciones y mantenimiento de recursos/configuración de Azure
└── test.sh     Ejecución de tests locales del producto
```

## Azure

### Sincronizar las credenciales OIDC de GitHub en Entra ID

`azure/sync-github-oidc-federated-credentials.ps1` obtiene de GitHub el prefijo
OIDC efectivo del repositorio y sincroniza las credenciales federadas de los
environments `dev`, `staging` y `production` en la App Registration
`github-movieops-terraform`.

Prerrequisitos:

- Azure CLI con una sesión que pueda modificar la App Registration.
- GitHub CLI autenticado y con acceso al repositorio.

Vista previa sin realizar cambios:

```powershell
./scripts/azure/sync-github-oidc-federated-credentials.ps1 -WhatIf
```

Sincronización y verificación:

```powershell
./scripts/azure/sync-github-oidc-federated-credentials.ps1
```

El script es idempotente: si `issuer`, `subject` y `audience` ya coinciden, no
modifica la credencial. Si una credencial no existe, la crea; si existe con un
sujeto obsoleto, la actualiza. Los parámetros permiten reutilizarlo:

```powershell
./scripts/azure/sync-github-oidc-federated-credentials.ps1 `
    -ApplicationDisplayName 'github-movieops-terraform' `
    -Repository 'ajunquit/movieops' `
    -Environments dev, staging, production
```

### Otorgar los roles de suscripción al service principal de CI

`azure/grant-ci-subscription-roles.ps1` asegura que la App Registration que usa
GitHub Actions tenga los roles necesarios sobre la suscripción:

| Rol | Para qué |
|---|---|
| `Contributor` | Crear la infraestructura (VNet, AKS, ACR, Postgres, Key Vault) |
| `Role Based Access Control Administrator` | Crear los `azurerm_role_assignment` del Terraform (`AcrPull` para el kubelet de AKS, `Key Vault Secrets Officer`) |

Sin el segundo rol, `genesis.yml` crea 15 de 17 recursos y falla con
`403 AuthorizationFailed` sobre `Microsoft.Authorization/roleAssignments/write`
— ver [TS-09](../docs/troubleshooting.md#ts-09). `Contributor` no puede otorgar
permisos: Azure lo excluye a propósito para evitar escalada de privilegios.

Se eligió `Role Based Access Control Administrator` y no `Owner` ni
`User Access Administrator` porque es el mínimo privilegio exacto: solo
`roleAssignments` write/delete más lectura. El `delete` es necesario para que
`apocalipsis.yml` pueda destruir esos mismos role assignments.

Prerrequisitos:

- Azure CLI con una sesión que pueda crear role assignments en la suscripción
  (típicamente Owner o User Access Administrator).

Vista previa sin realizar cambios:

```powershell
./scripts/azure/grant-ci-subscription-roles.ps1 -WhatIf
```

Aplicar y verificar:

```powershell
./scripts/azure/grant-ci-subscription-roles.ps1
```

El script es idempotente: si el rol ya está asignado en el scope de la
suscripción, lo informa como `[OK]` y no hace nada. Los parámetros permiten
apuntarlo a otra App Registration, suscripción o conjunto de roles:

```powershell
./scripts/azure/grant-ci-subscription-roles.ps1 `
    -ApplicationDisplayName 'github-movieops-terraform' `
    -SubscriptionId '00000000-0000-0000-0000-000000000000' `
    -Roles 'Contributor', 'Role Based Access Control Administrator'
```

## Nivel de bootstrap

Los dos scripts de `azure/` son de **nivel bootstrap**: se ejecutan una vez por
suscripción (o cuando cambia la configuración del repositorio), no en cada
despliegue. Están fuera de Terraform por la misma razón que el Storage Account
del state remoto — ver [ADR-0003](../docs/adr/0003-terraform-remote-state-bootstrap.md):
son los permisos y la confianza que Terraform **necesita para poder correr**,
así que no puede gestionarlos él mismo.

