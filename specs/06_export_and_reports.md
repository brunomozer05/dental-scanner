# 06 — Export and Reports

## Export STL

O app exporta STL posicionando modelos de referência nas poses finais dos markers.

Modelos atuais:

```txt
marker_reference.stl
marker_reference_2.stl
```

O v2 usa:

```txt
marker_reference_2.stl
```

## Regra crítica

No modo padrão atual, o app espera 4 markers físicos.

Logo, o app NÃO deve exportar STL final se houver menos de 4 markers exportáveis.

Problema atual:

```txt
às vezes parece escanear 4 markers, mas exporta STL com 3
```

Isso é bug crítico.

## Export gate desejado

Antes de exportar:

```txt
expectedPhysicalMarkerCount = 4
exportableMarkers.count == expectedPhysicalMarkerCount
```

Se não cumprir:

```txt
bloquear export
mostrar erro claro
não gerar STL silenciosamente
```

Mensagem sugerida:

```txt
Export bloqueado: 3/4 markers exportáveis
```

Também mostrar quais markers faltam:

```txt
Markers faltando: M2
```

## Diferença importante

```txt
marker visualmente detectado != marker exportável
```

O export deve usar apenas poses finais exportáveis.

## Report JSON

Cada STL salvo deve ter um report técnico no mesmo diretório:

```txt
Scan_YYYY-MM-DD_HH-mm.stl
Scan_YYYY-MM-DD_HH-mm_report.json
```

Se o STL receber sufixo por conflito:

```txt
Scan_2026-05-21_14-30-1.stl
Scan_2026-05-21_14-30-1_report.json
```

## Campos do report

O report deve incluir, quando disponível:

```txt
createdAt
markerProfile
stlFileName
device
cameraQuality
markers
scanQuality
```

### Device

```txt
model
iosVersion
cameraDevice
resolution
zoomFactor
```

### Camera quality

```txt
focusLocked
sharpnessMean
framesRejectedByFocus
framesRejectedByBlur
```

### Markers

Por marker:

```txt
markerId
translationVector
rotationMatrix
confidence
qualityScore
dualFrames
topFallbackFrames
bottomFallbackFrames
reprojectionError
sharpnessMean
normalStdDegrees
finalObservationsUsed
```

### Scan quality

```txt
confidence
worstMarkerId
mainIssue
planeAverageErrorMm
planeMaxErrorMm
```

## Campos que devem ser adicionados

Próxima evolução do report:

```txt
expectedMarkerCount
exportedMarkerCount
missingMarkerIds
exportBlockedReason
```

## Compatibilidade

Scans antigos sem report devem continuar funcionando.

`ScanItem.reportURL` deve ser opcional.
