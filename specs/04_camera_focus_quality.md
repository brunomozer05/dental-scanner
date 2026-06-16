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

Reports e diagnostics devem registrar:

```txt
deviceModelIdentifier
deviceMarketingName
cameraProfileId
cameraProfileName
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
