# 04 — Camera, Focus and Frame Quality

## Problema principal

No iPhone 16, a câmera parece perder/caçar foco durante o scan.

Quando isso acontece:

* a ArUco fica borrada;
* os cantos ficam imprecisos;
* a posição pode ainda parecer próxima;
* mas a inclinação/orientação varia muito;
* alguns STLs saem fora da realidade.

No iPhone 11, a câmera parece mais estável em alguns testes.

## Observação prática

Escanear mais perto no iPhone 11 melhorou muito o resultado.

Isso sugere que o tamanho da tag na imagem é crítico:

```txt
tag maior em pixels → cantos melhores → pose melhor
```

Mas no iPhone 16, escanear perto pode causar perda de foco ou comportamento de macro/foco mínimo.

## Barra de distância

A barra de distância é apenas um guia.

Ela só é confiável quando:

* a pose está boa;
* o foco está bom;
* a tag está nítida;
* o marker não está na borda;
* reprojection está baixo.

Se a câmera está desfocada, a distância calculada pode enganar.

## Melhorias planejadas

### Perfis de camera experimentais

Adicionar perfis manuais para comparar iPhones sem hardcode por modelo:

```txt
Default
Wide 1.0x
Wide 1.5x
Wide 2.0x
Wide 1.5x Conservative Focus
Wide 2.0x Conservative Focus
```

Regras:

* `Default` preserva o comportamento atual.
* Perfis `Wide` usam a wide traseira fisica quando disponivel.
* Zoom deve ser aplicado com clamp e registrado como requested/applied/current.
* Perfis `Conservative Focus` reduzem recuperacao agressiva de foco, sem travar foco permanentemente.
* A primeira etapa e apenas teste manual + diagnostics; selecao automatica fica para depois.

Observacao dos testes iniciais em iPhone 16:

* modelos `iPhone17,*` devem mostrar `Wide 1.5x` como perfil recomendado para teste;
* o perfil deve usar a camera traseira wide fisica, sem macro/ultra-wide/virtual como primeira opcao;
* abaixo de aproximadamente 120-125 mm ha maior risco de perda de foco;
* para `Wide 1.5x`, a faixa inicial recomendada e 150-180 mm;
* `Wide 2.0x` e `Wide 2.0x Conservative Focus` continuam disponiveis, mas devem ser tratados como experimentais/nao recomendados para iPhone 16 ate nova evidencia.

Thresholds iniciais para `Wide 1.5x` em iPhone 16:

```txt
tooCloseFocusRiskDistanceMm = 125
preferredMinScanDistanceMm = 130
preferredIdealMinScanDistanceMm = 150
preferredIdealMaxScanDistanceMm = 180
preferredMaxScanDistanceMm = 220
```

### Device quality profile e ROI

Foi adicionada uma camada read-only de `DeviceQualityProfile`, separada de `CameraProfile`.

Responsabilidades:

* `CameraProfile` continua controlando camera/zoom/foco selecionados.
* `DeviceQualityProfile` registra classe de device, faixa de distancia, risco de foco, escala de overlay e mascara/ROI.

Classes iniciais:

```txt
iPhone
iPhonePro
iPad
unknown
```

Para iPhone 16 / `iPhone17,*`, a recomendacao continua sendo testar `Wide 1.5x`, com distancia ideal inicial de 150-180 mm.

A mascara/ROI calcula uma area segura no frame a partir de bordas percentuais por classe de aparelho. Markers perto ou fora dessa area geram apenas diagnostics e aviso visual/debug:

```txt
Markers centralizados
Evite as bordas da camera
Centralize os markers
```

Essa etapa nao bloqueia export, readiness ou finalizacao.

### Experimental Quality Mode

Foi adicionado um modo experimental diagnostics-first para separar observacoes brutas de observacoes uteis, sem alterar o pipeline principal.

Regras atuais:

* `enableExperimentalQualityMode = true`;
* `enableExperimentalObservationGate = true`;
* ROI/frame mask, distancia, risco de foco e pose finita classificam observacoes aceitas/rejeitadas;
* o progresso util experimental roda em paralelo ao progresso visual/readiness atual;
* `minValidFramesPerMarker = 65` e `targetOptimizationFrames = 300` sao registrados por device quality profile;
* High Resolution Camera Profile fica disponivel para diagnostico manual, mas nao e selecionado automaticamente;
* Reference Camera Matrix Diagnostics e read-only e nao altera solvePnP/export.

O modo existe para comparar aparelhos/perfis antes de qualquer mudanca em export, readiness ou finalizacao.

Reports e diagnostics devem registrar:

```txt
deviceModelIdentifier
deviceMarketingName
cameraRecommendedProfileId
cameraRecommendedProfileName
cameraProfileId
cameraProfileName
cameraProfileTooCloseFocusRiskDistanceMm
cameraProfilePreferredMinScanDistanceMm
cameraProfilePreferredIdealMinScanDistanceMm
cameraProfilePreferredIdealMaxScanDistanceMm
cameraProfilePreferredMaxScanDistanceMm
selectedCameraLocalizedName
selectedCameraDeviceType
requestedZoomFactor
appliedZoomFactor
currentVideoZoomFactor
focusMode
exposureMode
cameraIntrinsicMatrixAvailable
fx/fy/cx/cy
activeVideoDimensions
activeFormatDescription
distanceGuideState
distanceGuideMessage
deviceQualityClass
deviceQualityProfileName
deviceQualityIsKnown
deviceQualityWarning
deviceQualityMinDistanceMm
deviceQualityIdealMinDistanceMm
deviceQualityIdealMaxDistanceMm
deviceQualityMaxDistanceMm
deviceQualityTooCloseFocusRiskDistanceMm
deviceQualityFocusVarianceThreshold
deviceQualityOverlayScale
deviceQualityFrameMaskVerticalBorderPercent
deviceQualityFrameMaskHorizontalBorderPercent
frameMaskSafeRectMinX
frameMaskSafeRectMinY
frameMaskSafeRectMaxX
frameMaskSafeRectMaxY
visibleMarkersInsideFrameMaskCount
visibleMarkersViolatingFrameMaskCount
anyMarkerNearFrameEdge
frameMaskQualityState
frameMaskQualityMessage
experimentalQualityModeEnabled
experimentalObservationGateEnabled
experimentalMinValidFramesPerMarker
experimentalTargetOptimizationFrames
experimentalAcceptedObservationCount
experimentalRejectedObservationCount
experimentalUsefulMarkersReadyCount
experimentalOverallUsefulProgress
cameraHighResolutionProfileAvailable
cameraHighResolutionProfileSelected
referenceCameraMatrixDiagnosticsEnabled
referenceVsActiveFxRatio
```

### Wide física

Forçar câmera traseira wide física:

```swift
AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
```

Evitar câmeras virtuais:

```txt
builtInDualCamera
builtInTripleCamera
builtInDualWideCamera
```

### Zoom digital controlado

Usar zoom na mesma wide física:

```txt
1.0x ... 3.0x
```

Objetivo:

* ficar um pouco mais longe fisicamente;
* evitar limite de foco/macro;
* manter tag grande na imagem.

### Foco manual

Permitir:

```txt
manualFocusEnabled
manualLensPosition
```

### Foco guiado por ArUco

Fluxo desejado:

```txt
1. detectar ArUco confiável
2. escolher top tag 8x8 preferencialmente
3. calcular centro 2D
4. usar focusPointOfInterest
5. usar exposurePointOfInterest
6. esperar estabilizar
7. travar foco/exposição se habilitado
```

Não usar bottom tag 6,5 como alvo principal se houver top tag.

### Sharpness/blur

Calcular nitidez do frame, idealmente por variance of Laplacian.

Frames borrados devem:

* não contar como good frame;
* não entrar no final export se houver melhores;
* penalizar rotação mais que posição.

### Ajustando foco

Se:

```txt
isAdjustingFocus == true
```

o frame não deve contar para readiness/export.

### Lens position settle

Se a lente acabou de mudar, aguardar uma janela antes de aceitar frames:

```txt
focusSettleTimeSeconds ≈ 0.5s
```

## Debug necessário

O debug deve mostrar:

* device name;
* device type;
* resolução;
* FPS;
* fx/fy/cx/cy;
* zoom factor;
* lens position;
* adjusting focus;
* adjusting exposure;
* focus locked;
* sharpness atual;
* sharpness médio;
* frames rejeitados por foco;
* frames rejeitados por blur.

## Regra de segurança

Não deixar frame fora de foco contaminar rotação/inclinação final.
