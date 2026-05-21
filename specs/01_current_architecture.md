# 01 — Current Architecture

## Visão geral

A arquitetura atual do DentalScanner é um MVP evoluído. O app já tem câmera, detecção, pose, refino, export STL, viewer, storage, debug e report JSON.

O código ainda precisa ser organizado progressivamente para evitar regressões.

## Módulos principais

### Camera

Responsável pela captura de frames da câmera.

Arquivos/conceitos relacionados:

* `CameraFrameService`
* `CameraFrame`
* `CameraPreviewView`

Responsabilidades:

* configurar câmera traseira;
* capturar frames;
* fornecer pixel buffer;
* fornecer timestamp;
* fornecer intrinsics quando disponíveis;
* controlar foco/exposição/torch quando implementado.

### Vision / OpenCV

Responsável pela detecção visual.

Arquivos/conceitos relacionados:

* `ArUcoDetector`
* bridge Objective-C++ OpenCV
* estruturas de resultado de detecção

Responsabilidades:

* converter frame para formato usado pelo OpenCV;
* detectar markers ArUco;
* retornar corners;
* retornar IDs;
* possibilitar cálculo de área/centro das tags;
* futuramente calcular sharpness/blur.

### Pose

Responsável por transformar detecções em poses 3D.

Arquivos/conceitos relacionados:

* `PoseEstimator`
* `PoseResult`
* `MarkerProfile`
* `MarkerConfiguration`
* `PoseSmoother`
* `MultiFramePoseAccumulator`
* `FinalPoseRefiner`
* `PoseQualityEvaluator`, se já existir

Responsabilidades:

* montar pontos 2D/3D;
* rodar solvePnP;
* lidar com v1/v2;
* lidar com dual-tag e fallback;
* acumular frames;
* filtrar outliers;
* calcular pose final.

### Export

Responsável por gerar STL.

Arquivos/conceitos relacionados:

* `STLExporter`
* `marker_reference.stl`
* `marker_reference_2.stl`

Responsabilidades:

* carregar STL de referência;
* aplicar pose final;
* transformar triângulos;
* gerar STL final;
* garantir que não exporta resultado inválido.

### Storage

Responsável por salvar scans.

Arquivos/conceitos relacionados:

* `ScanStorageManager`
* `ScanItem`
* `ScanTechnicalReport`

Responsabilidades:

* salvar STL;
* salvar `_report.json`;
* listar scans;
* manter compatibilidade com scans antigos sem report.

### UI

Responsável pela tela do scanner e debug.

Arquivos/conceitos relacionados:

* `ScannerView`
* `ScannerViewModel`
* `ScannerDebugPanelView`
* `ScannerDebugSnapshot`
* viewer STL
* biblioteca de scans

Responsabilidades:

* mostrar preview;
* mostrar overlay;
* controlar scan;
* mostrar readiness;
* abrir/fechar debug;
* alterar configs de teste;
* mostrar informações seguras.

## Fluxo geral

```txt
CameraFrameService
→ ArUcoDetector
→ PoseEstimator
→ ScannerViewModel
→ PoseQuality/Accumulator
→ Readiness
→ FinalPoseRefiner
→ STLExporter
→ ScanStorageManager
→ STL + report JSON
```

## Regras importantes

* Não calcular coisas pesadas diretamente no `body` SwiftUI.
* Não acessar listas com índice sem checagem.
* Não usar force unwrap no debug.
* Não deixar `NaN` ou `infinity` chegar na UI.
* Não confundir marker visual com marker exportável.
* Não exportar STL com menos markers do que o esperado no modo padrão.
