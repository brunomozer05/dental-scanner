# Formato de Dados

## 1. Camera calibration

Arquivo persistido por `CalibrationManager`:

```json
{
  "fx": 3020.0,
  "fy": 3020.0,
  "cx": 2016.0,
  "cy": 1512.0,
  "distortionCoefficients": [0.01, -0.04, 0.001, 0.0008, 0.0],
  "reprojectionErrorPixels": 0.24
}
```

Convencoes:

- unidades de pixel para intrinsecos
- coeficientes de distorcao na ordem definida pelo backend de calibracao
- um arquivo por dispositivo

## 2. Captura e sessao

Estruturas principais em `DentalScanner/Shared/ScanTypes.swift`:

- `CaptureFrame`
- `FrameQualityMetrics`
- `DetectedMarker`
- `CaptureGuidance`
- `ScanSessionState`

Essas estruturas representam:

- qualidade de cada frame
- tags detectadas
- bucket angular de cobertura
- progresso da sessao

## 3. Reconstrucao

Estruturas principais:

- `SparsePoint`
- `DensePoint`
- `ReconstructionState`
- `Mesh3D`

Convencoes:

- coordenadas esperadas em milimetros quando a pose ArUco vier de object points em mm
- eixo e handedness devem ser padronizados quando o backend real de pose for integrado

## 4. Relatorio

Saida atual:

- relatorio Markdown via `MeasurementReportGenerator`
- exportacao STL ASCII via `STLExporter`

Campos importantes do relatorio:

- stage final
- quantidade de frames validos
- cobertura angular
- marcadores visiveis
- total de pontos esparsos/densos
- vertices/faces da malha
- metricas de erro quando houver referencia

## 5. Dataset de calibracao

Arquivos de apoio:

- `Resources/SampleCalibrationDataset/README.md`
- `Resources/SampleCalibrationDataset/manifest.json`
- `Resources/CalibrationTargets/checkerboard_10x7.svg`

Uso sugerido:

1. imprimir o checkerboard
2. capturar imagens seguindo o manifesto
3. armazenar os JPGs reais fora do Git ou em LFS
4. manter apenas manifesto e assets leves no repositorio

