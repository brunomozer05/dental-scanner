# 07 — Debug Panel

## Histórico

O debug antigo causava crash ao abrir a engrenagem.

Foi descoberto que o botão real da engrenagem estava em outro caminho.

O debug foi reconstruído do zero.

## Debug atual seguro

O debug atual deve usar:

```txt
ScannerDebugPanelView
ScannerDebugSnapshot
Button("DBG")
ScrollView
botão Fechar
bindings seguros
```

## Não reativar

Não reativar:

```txt
debugPanel antigo
debugPanel(isLandscape:)
topControlBar antigo
debugPanelToggleButton antigo
EmergencyScannerDebugPanelView antigo
isDebugPanelExpanded antigo
useSafeDebugPanelOnly antigo
```

Se esses nomes não existirem mais, não recriar.

## Regras

* SwiftUI body não deve calcular métricas pesadas.
* O painel deve receber snapshot seguro.
* Nenhum valor deve crashar a UI.
* nil deve aparecer como `—`.
* NaN deve aparecer como `—`.
* infinity deve aparecer como `—`.
* Não usar force unwrap.
* Não usar `.first!`.
* Não usar `.last!`.
* Não acessar array por índice sem checar.
* `ForEach` deve usar ID estável.
* Não usar `id: \.self` em listas instáveis.

## Conteúdo atual esperado

O debug deve mostrar:

* estado do scan;
* perfil marker;
* readiness message;
* markers atuais;
* export STL básico;
* readiness básico;
* config scan editável;
* marker v2 básico.

## Config scan editável

Parâmetros editáveis esperados:

```txt
markerProfile
minimumCoveragePercentPerTag
minimumGoodFrames
targetGoodFrames
minimumDualTagFramesPerMarker
minimumDualAngularCoveragePercentPerMarker
precisionModeV2
preferDualTagForFinalExport
showDistanceGuide
staticPoseStabilityMode
```

Novos parâmetros de câmera/foco podem ser adicionados depois:

```txt
cameraZoomFactor
manualFocusEnabled
manualLensPosition
autoFocusOnDetectedAruco
lockAfterArucoFocus
minimumAllowedSharpness
minimumPreferredSharpness
arkitAssistedCaptureEnabled
```

## Seções avançadas

Seções avançadas devem ser adicionadas apenas de forma segura:

* Motion/IMU;
* Normal/orientation;
* Static pose stability;
* Planar diagnostics;
* Quality diagnostics;
* ARKit Assist.

Essas seções não devem reintroduzir cálculos perigosos no `body`.

## Regra de ouro

Se uma métrica não estiver pronta ou não for segura, mostrar `—` ou esconder a seção.

Nunca deixar o debug crashar.
