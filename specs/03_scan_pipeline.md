# 03 — Scan Pipeline

## Pipeline oficial

```txt
1. Captura de frame pela câmera
2. Detecção ArUco
3. Cálculo de pose
4. Acumulação e smoothing
5. Avaliação de qualidade
6. Readiness
7. Refino final
8. Export STL
9. Salvamento STL + report JSON
```

## 1. Captura

A câmera captura frames via AVFoundation.

Cada frame deve carregar, quando possível:

* pixel buffer;
* timestamp;
* resolução;
* orientação;
* intrinsics;
* informações de câmera/foco;
* futuramente sharpness/blur.

## 2. Detecção

OpenCV detecta ArUcos.

Resultado deve conter:

* ID;
* corners 2D;
* área aproximada;
* centro 2D;
* dados suficientes para foco guiado por ArUco.

## 3. Pose

O `PoseEstimator` calcula pose 3D.

Para v1:

```txt
1 tag → 4 corners → solvePnP
```

Para v2:

```txt
top + bottom → 8 corners → solvePnP dual
top only → top fallback
bottom only → bottom fallback
```

## 4. Acumulação

O app acumula observações ao longo de frames.

Observações ruins devem ter baixo peso ou serem descartadas.

Critérios importantes:

* reprojection error;
* distância;
* borda da imagem;
* source: dual/top/bottom;
* foco;
* sharpness;
* motion;
* normal outlier.

## 5. Diferença entre estados de marker

É obrigatório separar:

### Marker visual

Marker apareceu na UI/overlay recentemente.

Isso NÃO significa que é exportável.

### Marker com pose atual

Marker tem pose no frame atual ou recente.

Isso ainda NÃO significa que é exportável.

### Marker consolidado

Marker tem pose acumulada/filtrada.

Pode ainda não ser exportável.

### Marker exportável

Marker tem pose final válida para export.

Um marker exportável deve ter:

* markerId físico válido;
* translation finita;
* rotation finita;
* observações suficientes;
* qualidade mínima;
* não foi removido no final refinement;
* passou nos gates mínimos.

## 6. Readiness

O scan só deve entrar em `ready` se:

* cobertura suficiente;
* frames bons suficientes;
* distância aceitável;
* reprojection aceitável;
* jitter aceitável;
* estabilidade mínima;
* foco/sharpness aceitáveis, quando disponíveis;
* e principalmente: markers exportáveis suficientes.

No modo padrão atual:

```txt
expectedPhysicalMarkerCount = 4
```

Logo:

```txt
exportableMarkers.count deve ser 4
```

## 7. Export

O export não deve usar lista visual.

O export deve usar apenas poses finais exportáveis.

No modo padrão, não exportar com 3 markers se são esperados 4.

## 8. Report JSON

O report deve refletir exatamente o que foi exportado.

Deve conter:

* expectedMarkerCount;
* exportedMarkerCount;
* missingMarkerIds;
* qualidade dos markers;
* motivo principal de baixa confiança.

## Problema atual crítico

Às vezes o app parece escanear 4 markers, mas o STL final sai com 3.

Isso precisa ser corrigido antes de novas melhorias de precisão.
