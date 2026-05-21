# 05 — Pose Quality and Readiness

## Objetivo

Centralizar e tornar previsível a decisão de qualidade dos frames/poses.

## Conceitos

Cada observação deve poder ser classificada com:

```txt
qualityScore
positionWeight
rotationWeight
isUsableForTracking
isUsableForReadiness
isUsableForFinalExport
rejectionReason
```

## Critérios de qualidade

O quality evaluator deve considerar:

* pose finita;
* markerId válido;
* source: dualTag/topFallback/bottomFallback;
* reprojection error;
* distância;
* edge margin;
* bottom tag area;
* foco estável;
* sharpness;
* lensPosition estável;
* motion/IMU;
* normal outlier;
* ARKit quality futuramente.

## Pesos por source

Sugestão inicial:

```txt
dualTag:
  positionWeight = 1.0
  rotationWeight = 1.0

topFallback:
  positionWeight = 0.35
  rotationWeight = 0.15

bottomFallback:
  positionWeight = 0.15
  rotationWeight = 0.05
```

## Foco/blur

Se foco ou blur estiver ruim:

```txt
posição pode ser penalizada moderadamente
rotação deve ser penalizada fortemente
```

Exemplo conceitual:

```txt
positionWeight *= 0.5
rotationWeight *= 0.2
```

## Readiness

O scan não deve ficar pronto só porque a UI mostra 100%.

Readiness deve exigir:

* frames bons;
* cobertura;
* estabilidade;
* distância;
* reprojection;
* foco/sharpness, quando disponível;
* markers exportáveis suficientes.

No modo padrão atual:

```txt
expectedPhysicalMarkerCount = 4
```

Logo:

```txt
exportableMarkers.count == 4
```

## Fallback

Fallback serve para UX/tracking.

Fallback não deve dominar export final.

Especialmente:

* top fallback pode manter tracking;
* bottom fallback deve ter peso muito baixo;
* fallback não deve puxar rotação se dual-tag confiável existir.

## Normal/inclinação

O problema principal observado não é só posição, mas inclinação.

Logo, o refino deve ter atenção especial a:

* normal outliers;
* rotação média robusta;
* diferença dual vs fallback;
* variação angular.

## Export

O export final deve usar:

* observações com qualidade suficiente;
* pesos separados para posição e rotação;
* outlier rejection;
* confiança final por marker.

## Debug

O debug deve mostrar:

* currentFrameGood;
* rejection reason;
* average quality score;
* rejected by focus;
* rejected by blur;
* rejected by reprojection;
* rejected by edge;
* rejected by fallback;
* marker confidence.
