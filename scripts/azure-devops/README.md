# Bootstrap de Azure DevOps

Los scripts están organizados por pasos numerados. Cada carpeta representa una
unidad ejecutable, verificable e idempotente y contiene su propio `README.md`.
No se debe avanzar al paso siguiente hasta verificar la salida del anterior.

## Convención

```text
NN-nombre-del-paso/
├── README.md       Objetivo, prerrequisitos, parámetros y ejecución
└── *.ps1           Automatización del paso
```

- `NN` fija el orden de ejecución.
- Cada script admite `-WhatIf` cuando realiza mutaciones.
- Una segunda ejecución debe converger sin crear duplicados.
- Los scripts informan `EXISTS`, `CREATED`, `UPDATED`, `VERIFIED` o
  `MANUAL ACTION REQUIRED`.
- Ninguna carpeta almacena tokens, passwords, PATs ni client secrets.

## Secuencia

| Orden | Carpeta | Propósito | Estado |
|---:|---|---|---|
| 00 | [`00-bootstrap-project`](00-bootstrap-project/) | Crear/verificar el Project `MovieOps` | Completado |
| 01 | [`01-service-connection-wif`](01-service-connection-wif/) | Identidad, service connection WIF y RBAC | Completado |
| 02 | [`02-configure-environments`](02-configure-environments/) | Environments, branch control y approval | Completado |
| 03 | [`03-configure-pipelines`](03-configure-pipelines/) | GitHub App, diagnóstico y autorización por pipeline | Completado |
| 04 | [`04-configure-retention`](04-configure-retention/) | Política de retención del Project | Completado |
| 05 | [`05-verify-bootstrap`](05-verify-bootstrap/) | Auditoría read-only completa de ADOP-1 | Completado: 21/21 PASS |
| 06 | [`06-configure-ci`](06-configure-ci/) | Registrar y verificar `MovieOps-CI` | Completado; runs de `main` verdes |
| 07 | [`07-verify-ci-parity`](07-verify-ci-parity/) | Auditoría read-only de los gates ADOP-2 | Completado: 12/12 PASS |
| 08 | [`08-stabilize-terraform-identities`](08-stabilize-terraform-identities/) | Identidades estables antes de Genesis | Completado: 8/8 PASS |
| 09 | [`09-configure-genesis`](09-configure-genesis/) | Registrar Genesis y autorizar WIF exclusiva | Implementado; pendiente de publicación y ejecución |
| 99 | [`99-full-bootstrap`](99-full-bootstrap/) | Orquestador reanudable de todos los pasos | Completado y verificado |

La creación de la organización Azure DevOps y el consentimiento de GitHub App
permanecen manuales. Ver
[`docs/azure-devops/automation.md`](../../docs/azure-devops/automation.md).
