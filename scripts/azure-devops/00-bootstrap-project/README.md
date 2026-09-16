# Paso 00 — Bootstrap del Project `MovieOps`

## Estado

Completado y verificado contra Azure DevOps.

```text
Project ID: 8194016c-7872-4a13-b3ea-1db569a17e3f
State: wellFormed
Visibility: private
Process: Basic
Source control: Git
```

## Objetivo

Crear o verificar el proyecto privado `MovieOps` dentro de:

```text
https://dev.azure.com/ajunquit
```

Este paso establece el contenedor administrativo donde vivirán los pipelines,
Environments y service connections de los pasos siguientes.

## Script

[`bootstrap-project.ps1`](bootstrap-project.ps1)

## Qué hace

1. Comprueba que `az` esté disponible.
2. Verifica la sesión actual de Azure CLI y muestra usuario, tenant y
   suscripción.
3. Busca la extensión Azure CLI `azure-devops`.
4. La instala si falta y la operación fue autorizada.
5. Comprueba acceso a la organización Azure DevOps.
6. Busca `MovieOps` sin distinguir mayúsculas/minúsculas.
7. Si no existe, crea exactamente:

   | Propiedad | Valor |
   |---|---|
   | Name | `MovieOps` |
   | Visibility | `private` |
   | Process | `Basic` |
   | Source control | `Git` |

8. Si ya existe, no lo recrea.
9. Verifica estado, visibilidad, proceso y tipo de source control.
10. Configura los defaults locales de Azure DevOps CLI para organización y
    proyecto.
11. Devuelve Organization, Project ID y configuración final.

## Qué no hace

- No importa ni copia el repositorio GitHub.
- No crea ni ejecuta pipelines.
- No crea App Registrations ni service connections.
- No asigna roles Azure RBAC.
- No crea infraestructura Azure.
- No modifica el proyecto existente `DevOps Delivery Engineer`.
- No genera ni almacena secretos.

Azure DevOps crea automáticamente un repositorio Git vacío al crear un Project.
MovieOps no lo poblará ni lo utilizará; GitHub seguirá siendo la única fuente de
código.

## Prerrequisitos

- PowerShell 7 o superior.
- Azure CLI disponible en `PATH`.
- Sesión activa de Azure CLI:

  ```powershell
  az login --tenant 71747eda-0e30-46d9-a3dd-09adb3a83ff3
  ```

- Acceso para crear proyectos en `https://dev.azure.com/ajunquit`.
- Ejecutar desde la raíz del repositorio MovieOps.

Comprobaciones opcionales antes de ejecutar:

```powershell
$PSVersionTable.PSVersion
az account show --output table
az devops project list --organization 'https://dev.azure.com/ajunquit' --output table
```

## Parámetros

| Parámetro | Tipo | Default | Descripción |
|---|---|---|---|
| `OrganizationUrl` | `string` | `https://dev.azure.com/ajunquit` | Organización target; solo acepta URLs `dev.azure.com` válidas |
| `ProjectName` | `string` | `MovieOps` | Nombre exacto del Project |
| `Description` | `string` | `MovieOps multi-platform DevOps laboratory` | Descripción usada únicamente al crear el Project |
| `WhatIf` | switch común | Desactivado | Muestra la mutación prevista sin crear el Project ni cambiar defaults |
| `Confirm` | switch común | Según PowerShell | Solicita confirmación explícita si se habilita |

Todos son opcionales porque los defaults ya corresponden a este laboratorio.

## Ejecución

### 1. Vista previa

```powershell
./scripts/azure-devops/00-bootstrap-project/bootstrap-project.ps1 -WhatIf
```

Si el Project no existe, la salida debe incluir algo equivalente a:

```text
[VERIFIED] Azure session: ajunquit@hotmail.com
[EXISTS] Azure CLI extension 'azure-devops' ...
What if: ... Create private Azure DevOps project
[PLAN] Project 'MovieOps' would be created ...
```

### 2. Aplicación

```powershell
./scripts/azure-devops/00-bootstrap-project/bootstrap-project.ps1
```

### 3. Reejecución idempotente

Ejecutar el mismo comando una segunda vez:

```powershell
./scripts/azure-devops/00-bootstrap-project/bootstrap-project.ps1
```

La segunda salida debe contener `[EXISTS] Project 'MovieOps'` y no debe crear
otro Project.

## Ejecución con parámetros explícitos

```powershell
./scripts/azure-devops/00-bootstrap-project/bootstrap-project.ps1 `
    -OrganizationUrl 'https://dev.azure.com/ajunquit' `
    -ProjectName 'MovieOps' `
    -Description 'MovieOps multi-platform DevOps laboratory'
```

## Salida esperada

```text
[VERIFIED] Azure session: ajunquit@hotmail.com
[VERIFIED] Tenant: 71747eda-0e30-46d9-a3dd-09adb3a83ff3
[VERIFIED] Subscription: <nombre> (b7fdb48a-4bf0-4c7b-9708-3d875a551936)
[EXISTS] Azure CLI extension 'azure-devops' ...
[CREATED] Project 'MovieOps' (<project-id>).
[UPDATED] Azure DevOps CLI defaults.
[VERIFIED] Azure DevOps project bootstrap completed.
```

El resumen final debe confirmar:

```text
Organization  : https://dev.azure.com/ajunquit
Project       : MovieOps
State         : wellFormed
Visibility    : private
Process       : Basic
SourceControl : Git
```

## Idempotencia y tratamiento de drift

- Si el Project no existe, lo crea.
- Si existe y cumple el contrato, informa `[EXISTS]` y continúa.
- Si existen coincidencias ambiguas, se detiene.
- Si el Project existe pero es público, usa otro proceso, otro source control o
  no está `wellFormed`, se detiene sin corregirlo silenciosamente.
- No elimina ni reemplaza Projects.

## Efectos locales

Configura estos defaults en Azure DevOps CLI:

```text
organization=https://dev.azure.com/ajunquit
project=MovieOps
```

Pueden consultarse con:

```powershell
az devops configure --list
```

## Resolución de problemas

### Azure CLI no tiene sesión

```powershell
az login --tenant 71747eda-0e30-46d9-a3dd-09adb3a83ff3
```

### No hay acceso a la organización

Confirmar en el navegador que la misma cuenta abre:

```text
https://dev.azure.com/ajunquit
```

### No hay permiso para crear Projects

La cuenta debe ser Organization Owner, miembro de Project Collection
Administrators o tener `Create new projects = Allow`.

### Falta la extensión Azure DevOps

El script intenta instalarla. También puede instalarse manualmente:

```powershell
az extension add --name azure-devops
```

## Evidencia que debes devolver

Después de ejecutarlo, comparte la salida desde `[VERIFIED] Azure session` hasta
el resumen final. No debería contener secretos.

## Siguiente paso

No continuar automáticamente. Primero se valida esta salida y después se crea
`01-service-connection-wif`.
