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

