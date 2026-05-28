# DentalScanner Specs

Esta pasta contém as specs oficiais do projeto DentalScanner.

Antes de qualquer alteração no código, o agente deve ler:

1. `00_project_context.md`
2. `08_known_issues.md`
3. `09_next_tasks.md`
4. A spec específica da área que será alterada

Estas specs são a fonte de verdade do projeto.

## Indice

* `00_project_context.md` - contexto geral do projeto.
* `03_scan_pipeline.md` - pipeline principal de scan/export.
* `05_pose_quality_and_readiness.md` - qualidade de pose e readiness.
* `06_export_and_reports.md` - export STL e reports.
* `07_debug_panel.md` - regras do debug seguro.
* `08_known_issues.md` - problemas conhecidos.
* `09_next_tasks.md` - backlog tecnico.
* `10_best_final_pose_candidate.md` - plano futuro para exportar o melhor candidato de pose final.

## Regras gerais

* Não reativar código antigo de debug que já causou crash.
* Não alterar OpenCV, solvePnP, STLExporter ou GitHub Actions sem necessidade explícita.
* Não copiar código, assets, modelos ou algoritmos de terceiros.
* Não usar arquivos de apps externos dentro do projeto.
* Manter o pipeline atual funcional.
* Toda alteração deve ser incremental, segura e fácil de reverter.
* Se algum dado for inválido, nil, NaN ou infinity, a UI deve mostrar `—`, nunca crashar.

## Ordem recomendada das próximas tarefas

1. Bloquear export STL se houver menos de 4 markers exportáveis.
2. Melhorar câmera/foco/sharpness.
3. Atualizar comparador Python para ler `_report.json`.
4. Comparar iPhone 11 vs iPhone 16 com dados objetivos.
5. Comparar marker v1 vs marker v2.
6. Avaliar marker v3 híbrido futuramente.
7. Adicionar ARKit Assist experimental.
8. Refinar final pose/export quality gates.
