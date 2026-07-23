# Documentación — Inventario PROPLAS

## Spec-Driven Development (SDD)

La especificación está organizada como **tres artefactos** (metodología SDD): la spec es la fuente de verdad y **guía la construcción** (primero la historia + criterios, luego el plan, luego las tareas, luego el código).

| Artefacto | Qué contiene |
|---|---|
| [`spec.md`](spec.md) | **El QUÉ y el PORQUÉ**: historias de usuario + criterios de aceptación (Dado/Cuando/Entonces). |
| [`plan.md`](plan.md) | **El CÓMO**: arquitectura, modelo de datos y decisiones técnicas. |
| [`tasks.md`](tasks.md) | **El DESGLOSE**: tareas trazables a cada historia, con estado. |

### Cómo trabajar una función nueva (flujo SDD)
1. Escribir la **historia** + **criterios de aceptación** en `spec.md`.
2. Definir la **técnica** en `plan.md`.
3. Desglosar en **tareas** en `tasks.md`.
4. **Recién entonces** programar, validando contra los criterios.

> Próxima épica a construir con SDD estricto: **Categorías fiscales** (Usados/Activos/Baja).

## Otros documentos
- [`SPEC.md`](SPEC.md) — versión narrativa/monolítica previa (visión general en un solo archivo). Se conserva como referencia; la fuente de verdad ahora es el trío SDD de arriba.
