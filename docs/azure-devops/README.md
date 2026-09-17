# Azure DevOps en MovieOps

Este directorio reúne el diseño, bootstrap, operación y evidencia del track de
paridad con Azure Pipelines. El código continúa alojado en GitHub y Microsoft
Azure continúa siendo el proveedor cloud; Azure DevOps sustituye únicamente al
orquestador CI/CD durante las pruebas de paridad.

## Documentos

| Documento | Hito | Estado |
|---|---|---|
| [Baseline y matriz de paridad](parity-matrix.md) | ADOP-0 | Completado |
| [Runbook paso a paso](setup.md) | ADOP-1–ADOP-7 | Activo: guía operativa completa |
| [Estrategia de automatización](automation.md) | ADOP-1 | Completado: pasos 00–05 + orquestador 99 |
| [Diseño de pipelines](pipeline-design.md) | ADOP-2–ADOP-5 | Activo: CI de ADOP-2 implementado |
| `operations.md` | ADOP-3–ADOP-7 | Pendiente |
| [Troubleshooting general](../troubleshooting.md) | Transversal | Activo: incidentes y correcciones del track |

## Documentos rectores

- [Plan de paridad Azure DevOps](../plans/AZURE_DEVOPS_PARITY_PLAN.md)
- [Baseline implementada con GitHub Actions](../plans/GITHUB_ACTIONS_AZURE_IMPLEMENTATION_PLAN.md)
- [Plan rector de MovieOps](../../MovieOps_DevOps_Plan.md)
