# Paso 07 — Verificar paridad CI

## Estado

Completado y verificado el 17 de septiembre de 2026: `12` controles, `12` PASS,
`0` WAITING y `0` FAIL.

Evidencia final:

- Main run `67`, commit `961e441c95a0ab6474fabdbdf088c5c33aef769f`.
- PR sano `#31`, Azure run `65`: `succeeded`.
- PR roto `#9`, Azure run `64`: `failed`.
- Ningún run de PR publicó `movieops-images`.

## Objetivo

Cerrar ADOP-2 con una auditoría read-only de:

- pipeline y último run verde de `main`;
- artifact `movieops-images` y cobertura;
- funcionamiento sin `rg-movieops-dev`;
- ausencia de autorización WIF para CI;
- PR sano verde en GitHub Actions y Azure Pipelines;
- PR roto fallando en ambas plataformas;
- ausencia de `movieops-images` en runs de PR.

## Casos elegidos

Se reutilizan PR reales ya abiertos:

| Caso | PR | Motivo |
|---|---:|---|
| Sano | `#31` | Reemplazo actualizado del antiguo PR `#16`; sus checks deben quedar verdes |
| Roto | `#9` | La actualización Angular incompatible falla en frontend |

No se crean tests falsos ni ramas descartables. Los PR no deben fusionarse como
parte de esta auditoría; solo se actualizan para generar eventos nuevos.

## Gate manual previo

En cada PR que todavía no tenga un run actual, solicitar a Dependabot un rebase
mediante un comentario:

```text
@dependabot rebase
```

Esto actualiza la rama y emite un evento `synchronize`. Esperar que aparezcan
checks de `MovieOps-CI` además de GitHub Actions.

Alternativamente, usar el botón **Update branch** si GitHub lo ofrece. No cerrar
ni fusionar los PR durante la prueba.

## Ejecución

```powershell
./scripts/azure-devops/07-verify-ci-parity/verify-ci-parity.ps1
```

Otros PR:

```powershell
./scripts/azure-devops/07-verify-ci-parity/verify-ci-parity.ps1 `
  -HealthyPullRequestNumber <numero-verde> `
  -BrokenPullRequestNumber <numero-roto>
```

## Comportamiento

- No crea, actualiza ni elimina recursos.
- Consulta Azure DevOps mediante Azure CLI.
- Consulta GitHub mediante `gh`.
- Correlaciona los runs de Azure con el número del PR.
- Falla hasta que ambos PR tengan un run Azure completado.
- Acepta el caso roto solo cuando ambos CI detectan realmente el fallo.

## Salida esperada

```text
PASS  GitHub Actions PR #31 is succeeded
PASS  Azure Pipelines PR #31 is succeeded
PASS  GitHub Actions PR #9 is failed
PASS  Azure Pipelines PR #9 is failed
PASS  PR #31 does not publish movieops-images
PASS  PR #9 does not publish movieops-images
[VERIFIED] ADOP-2 CI parity audit completed successfully.
```

## Recuperación

El estado `WAITING` significa que el run está en cola/en ejecución o que el PR
todavía no produjo un evento nuevo. Esperar o rebasarlo según la evidencia y
ejecutar nuevamente la auditoría. `WAITING` no es un fallo del pipeline. No
recrear `MovieOps-CI` ni repetir ADOP-1.
