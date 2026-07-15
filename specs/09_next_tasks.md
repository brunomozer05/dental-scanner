# 09 — Next Tasks

## Prioridade 1 — Bloquear export com menos de 4 markers

Problema:

```txt
às vezes o app exporta STL com 3 markers mesmo parecendo ter escaneado 4.
```

Tarefa:

* separar visual markers de exportable markers;
* definir `expectedPhysicalMarkerCount = 4`;
* bloquear export se `exportableMarkers.count < 4`;
* mostrar erro claro;
* mostrar markers faltando;
* atualizar report JSON.

Commit sugerido:

```txt
Block STL export when markers are missing
```

## Prioridade 2 — Atualizar comparador Python para ler `_report.json`

Tarefa:

* carregar reports junto com STLs;
* comparar poses por marker;
* mostrar qualidade por scan;
* mostrar missing markers;
* mostrar focus/sharpness;
* cruzar erro STL com qualidade reportada.

## Prioridade 3 — Melhorar câmera/foco/sharpness

Tarefa:

* wide física fixa;
* zoom digital controlado;
* foco manual;
* foco guiado por ArUco;
* lock after focus;
* sharpness/blur score;
* rejeitar frames fora de foco;
* debug camera/focus.

## Prioridade 4 — Testes iPhone 11 vs iPhone 16

Fazer pastas:

```txt
tests/iphone11_perto
tests/iphone11_longe
tests/iphone16_auto_focus
tests/iphone16_focus_locked
```

Para cada teste:

* 3 a 5 scans;
* guardar STL;
* guardar report JSON;
* rodar comparador;
* anotar distância/foco/zoom/configs.

Adicionar tambem testes por `cameraProfileId`:

```txt
Default
Wide 1.0x
Wide 1.5x
Wide 2.0x
Wide 1.5x Conservative Focus
Wide 2.0x Conservative Focus
```

Nos testes iniciais do iPhone 16:

* priorizar `Wide 1.5x` como recomendado para `iPhone17,*`;
* testar distância ideal inicial de 150-180 mm;
* evitar ficar abaixo de 120-125 mm, pois aumenta risco de perda de foco;
* manter `Wide 2.0x` e `Wide 2.0x Conservative Focus` como experimentais/não recomendados até nova evidência.
* confirmar no app que a barra lateral de distancia mostra 150-180 mm dentro da faixa verde e usa escala dinamica do perfil.

Proxima etapa futura:

```txt
Auto Camera Profile Evaluation
```

Esse modo deve testar perfis por uma janela curta e escolher o melhor usando:

* markerDetectionRate;
* averageSharpness;
* averageReprojection;
* poseQuality;
* focusLostCount;
* relativeMarkerDistanceStdMean;
* relativeMarkerDistanceStdMax.

Nao automatizar antes de comparar resultados por aparelho/perfil nos reports.

Fases ja implementadas como diagnostics/read-only:

```txt
DeviceQualityProfile por classe de device
Frame Mask / ROI Quality Diagnostics
Experimental Quality Mode com observacoes uteis em paralelo
```

Ainda pendente:

* validar os contadores de observacoes uteis contra CSVs e scans reais;
* adicionar diagnostics completos de diversidade angular;
* adicionar PnP robustness diagnostics;
* atualizar o comparador para expor os novos campos;
* decidir, com dados, se ROI/observacao util vira soft gate.

O modo experimental registra 65 frames uteis por marker como meta inicial e 300 frames/observacoes como alvo de otimizacao, mas ainda nao altera export, readiness ou finalizacao.

High Resolution Camera Profile esta preparado para teste manual e permanece desligado por padrao. Quando `Wide 1.5x High Resolution Experimental` for selecionado manualmente, o app deve tentar 3840x2160 e registrar fallback se o formato nao estiver disponivel.

Reference Camera Matrix Diagnostics e read-only e nao substitui os intrinsics reais da camera.

## Prioridade 5 — Comparar v1 vs v2

Objetivo:

Decidir se o `dualArucoV2` realmente melhora.

Se v1 for mais consistente, considerar voltar foco para v1 ou criar v3 híbrido.

## Prioridade 6 — ARKit Assist experimental

Adicionar ARKit como diagnóstico/quality score, não substituição.

Padrão desligado.

Usar para:

* tracking state;
* camera transform;
* intrinsics;
* motion;
* light estimate;
* penalizar frames ruins.

## Prioridade 7 — Final refinement mais rígido

Tarefa:

* usar quality score centralizado;
* rejeitar blur/foco;
* rejeitar missing markers;
* normal outlier;
* pesos separados posição/rotação;
* confiança final por marker.

## Prioridade 8 — Marker v3 híbrido

Futuro:

```txt
1 ArUco maior
+ bolinhas/pontos
+ fundo branco
+ elementos pretos
```

Não implementar antes de estabilizar v1/v2 e câmera.

## Tarefa futura - Best Final Pose Candidate

Implementar a spec `10_best_final_pose_candidate.md`.

Objetivo:

* durante o refinamento apos 4 markers em 100%, avaliar candidatos com throttle;
* salvar o melhor conjunto de poses final encontrado;
* exportar usando esse melhor candidato quando valido;
* manter fallback seguro para o fluxo atual;
* registrar uso, score, idade e metricas do candidato em diagnostics/report;
* expor campos simples no debug emergencial.

Commit sugerido:

```txt
Add best final pose candidate tracking
```
## Task - Validate high resolution frame processing

Run side-by-side scans with `Wide 1.5x` and
`Wide 1.5x High Resolution Experimental`.

Use the new diagnostics to compare:

```txt
cameraFramePixelBufferWidth/Height
cameraFrameProcessingWidth/Height
cameraFramesReceived/Processed/Dropped
cameraLastFrameProcessingMs
cameraAverageFrameProcessingMs
arucoDetectedMarkerCountLastFrame
arucoDetectedExpectedMarkerCountLastFrame
arucoFramesWithAnyMarkerCount
arucoFramesWithExpectedMarkerCount
poseAcceptedLastFrame
poseRejectedLastFrame
poseLastRejectReason
```

Only consider downscale or intrinsics/corner scaling if the diagnostics prove
that 4K frames arrive but detection or pose acceptance fails.

## Roadmap arquitetural — observações e otimização multi-frame

As próximas fundações arquiteturais devem ser executadas em commits separados e na ordem abaixo. A primeira fase diagnostics-only da Phase A, o shadow diagnostics da Phase B e as fases 18A/18B da Phase C estão implementados; blocking/A-B da Phase B e a Phase D permanecem não implementados.

### Phase A — Spec 16

`16_frame_indexed_observations.md`

Adicionar um modelo de observação por frame, inicialmente diagnostics/read-only, preservando:

```txt
frame index e timestamp
intrinsics e dimensões do frame
observações por marker
correspondências 2D/3D
pose individual por frame
quality metadata
```

Não alterar acumulador, readiness, finalization ou export nessa fase.

Status: primeira fase diagnostics-only implementada em 2026-07-12, com modelo explícito por frame, buffer limitado, diagnostics agregados e reset de sessão. A captura full-session passou à Phase 18A; reader/replay e qualquer consumo pelo pipeline primário permanecem pendentes.

### Phase B — Spec 17

`17_pre_accumulation_observation_gate.md`

Criar um quality gate antes da inserção no `MultiFramePoseAccumulator`, primeiro em shadow mode e depois atrás de feature flag desligada por padrão.

Comparar obrigatoriamente:

```txt
gate OFF
gate ON
```

Diversidade angular não entra no primeiro commit dessa fase.

Status: shadow diagnostics implementado em 2026-07-12. O gate avalia antes do accumulator e registra decisões/comparação pareada. O replay offline ALL versus decisões persistidas `wouldAccept` foi implementado, mas blocking ao vivo permanece desligado e sua validação física continua pendente.

### Phase C — Spec 18

`18_scan_session_replay.md`

Persistir somente geometria e quality metadata suficientes para replay determinístico. Não salvar frames completos por padrão e não alterar o comparador Python nesta fase.

Status: Phase 18A de captura progressiva full-session, Phase 18B de reader/replay determinístico e replay diagnóstico ALL versus Pre-Gate aceito persistido implementados. Cada modo prova determinismo com accumulators novos; a comparação entre modos usa geometria relativa por pares. Validação física, integração com comparador e optimizer continuam pendentes.

### Phase D — Spec 19

`19_offline_frame_indexed_optimization.md`

Executar experimento A/B offline:

```txt
A = MultiFramePoseAccumulator atual
B = otimizador com uma pose de câmera por frame e uma pose compartilhada por marker
```

Manter intrinsics fixos e usar residual reprojetivo robusto na primeira versão. O resultado B não controla export.

### Depois das phases A–D

Avaliar, em tarefas/specs separadas:

1. integração primária de diversidade angular por marker;
2. pose graph;
3. marker v3 e pontos extras próprios;
4. otimização global e eventual viabilidade runtime.

Não implementar bundle adjustment, pose graph ou otimização de focal/distorção antes de existirem observações frame-indexed e replay determinístico.
