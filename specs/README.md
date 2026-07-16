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
* `11_device_quality_pipeline.md` - perfis por device, frame mask e quality diagnostics.
* `12_observation_quality_and_angle_diversity.md` - qualidade de observacoes e diversidade angular.
* `13_camera_resolution_focus_intrinsics.md` - camera, foco, resolucao e intrinsics.
* `14_marker_v3_and_robust_pnp.md` - marker futuro, pontos extras e PnP robusto.
* `15_validation_protocol_and_accuracy.md` - protocolo de validacao e limites das afirmacoes de accuracy.
* `16_frame_indexed_observations.md` - Frame Indexed Observation Model.
* `17_pre_accumulation_observation_gate.md` - Pre-Accumulation Observation Quality Gate.
* `18_scan_session_replay.md` - Scan Session Capture and Deterministic Replay.
* `19_frame_indexed_bundle_adjustment.md` - active frame-indexed bundle-adjustment investigation and implementation plan.
* `19_offline_frame_indexed_optimization.md` - historical optimizer roadmap, superseded by the detailed Spec 19A design.

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

## Roadmap arquitetural frame-indexed

As specs 16–19 seguem a ordem abaixo. As fundações diagnostics/shadow 16–17, as phases 18A/18B, o replay offline ALL/Pre-Gate persistido e o export diagnóstico de STLs ALL/FILTERED em frame comum estão implementados. A Spec 19A está especificada; validação física do A/B, blocking ao vivo e implementação 19B permanecem pendentes.

### Phase A

`16_frame_indexed_observations.md`

Criar a fundação diagnostics/read-only que preserva a associação entre frame, intrinsics, correspondências e pose por frame.

### Phase B

`17_pre_accumulation_observation_gate.md`

Avaliar e, atrás de feature flag desligada por padrão, impedir que observações rejeitadas entrem no acumulador primário.

### Phase C

`18_scan_session_replay.md`

Persistir sessões geométricas versionadas para replay determinístico e comparação A/B sobre os mesmos dados.

### Phase D

`19_frame_indexed_bundle_adjustment.md`

Investigar, especificar e depois comparar offline o acumulador atual com um bundle adjustment que mantém uma pose de câmera por frame e uma pose compartilhada por marker. A implementação começa em 19B somente após revisão da Spec 19A.

Somente depois dessas fases avaliar integração primária de diversidade angular, pose graph, marker v3 e otimização global.
