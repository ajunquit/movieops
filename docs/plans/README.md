# Planes de implementación de MovieOps

Este directorio reúne los planes derivados del roadmap rector. Cada plan cambia
una dimensión concreta —plataforma CI/CD o proveedor cloud— sin redefinir el
producto ni los principios generales del laboratorio.

## Jerarquía

| Orden | Plan | Estado | Propósito |
|---:|---|---|---|
| 1 | [Plan rector](../../MovieOps_DevOps_Plan.md) | Activo | Define producto, patrones, arquitectura objetivo y Sprints 0–13 |
| 2 | [GitHub Actions + Azure](GITHUB_ACTIONS_AZURE_IMPLEMENTATION_PLAN.md) | Baseline `dev` validada | Documenta cómo se implementaron CI, Terraform, CD y AKS hasta Sprint 9 |
| 3 | [Azure DevOps parity](AZURE_DEVOPS_PARITY_PLAN.md) | En ejecución (ADOP-1) | Reproduce la baseline con Azure Pipelines y el mismo repositorio GitHub |
| 4 | AWS parity | Pendiente de redactar | Reimplementará infraestructura y delivery en AWS después de cerrar Azure DevOps |
| 5 | Retorno al plan rector | Futuro | Retoma Sprint 10: Argo CD, Rollouts, observabilidad e incidentes |

## Regla de precedencia

Si un plan derivado contradice el plan rector, prevalece el plan rector. Los
planes derivados pueden precisar orden, archivos, criterios de aceptación y
decisiones propias de una plataforma, pero no cambiar los objetivos finales del
laboratorio sin un ADR explícito.

## Secuencia acordada

```text
Plan rector: Sprints 0–9
          │
          ├── baseline GitHub Actions + Azure   ✅
          │
          ├── Azure DevOps parity               ⏭
          │
          ├── AWS parity                        🔜
          │
          └── Plan rector: Sprints 10–13
              Argo CD → Argo Rollouts → Observabilidad/Incidentes
```
