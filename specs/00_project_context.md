# 00 — Project Context

## Projeto

DentalScanner é um app iOS nativo em Swift/SwiftUI para escaneamento odontológico usando markers visuais.

O objetivo é detectar markers ArUco, estimar suas poses 3D, gerar um STL com modelos de referência posicionados corretamente e permitir análise/exportação do scan.

## Objetivo técnico

O app busca evoluir para um fluxo profissional de captura de scan bodies/markers odontológicos, com foco em:

* detecção confiável de markers;
* pose 3D consistente;
* export STL correto;
* controle de qualidade do scan;
* debug seguro;
* comparação objetiva entre scans;
* repetibilidade entre capturas.

## Stack atual

O projeto atualmente usa ou já implementou partes de:

* Swift
* SwiftUI
* AVFoundation
* OpenCV via bridge Objective-C++
* ArUco
* solvePnP
* CoreMotion/IMU
* STL export
* STL viewer
* debug panel seguro
* scan storage
* report JSON por scan
* comparador externo em Python

## Pipeline principal atual

O pipeline principal é:

```txt
AVFoundation camera frame
→ OpenCV ArUco detection
→ PoseEstimator / solvePnP
→ ScannerViewModel accumulation/filtering
→ readiness
→ FinalPoseRefiner
→ STLExporter
→ ScanStorageManager
→ STL + _report.json
```

## Perfis de marker

O projeto tem pelo menos dois perfis:

* `singleArucoV1`
* `dualArucoV2`

O modo principal atual é `dualArucoV2`, mas ainda é necessário comparar objetivamente v1 vs v2.

## Debug

O debug antigo causava crash ao abrir a engrenagem.

O debug atual foi reconstruído do zero e deve continuar usando:

* `ScannerDebugPanelView`
* `ScannerDebugSnapshot`
* botão `DBG`
* `ScrollView`
* botão fechar
* bindings seguros

Não reativar debug antigo.

## Report JSON

Cada scan salvo deve gerar:

```txt
Scan_YYYY-MM-DD_HH-mm.stl
Scan_YYYY-MM-DD_HH-mm_report.json
```

O JSON deve conter informações técnicas do scan, markers, qualidade e câmera.

## Ferramenta externa

Existe uma ferramenta externa em Python para comparar STLs e componentes.

Ela deve ser evoluída para ler também os `_report.json`, pois comparar poses e métricas diretamente é mais confiável do que apenas comparar malhas.

## Análise de app profissional de referência

Foi feita uma análise estrutural segura de um IPA de referência. Ela mostrou uso de tecnologias como:

* ARKit
* AVFoundation
* CoreMotion
* CoreImage
* CoreML
* Metal
* SceneKit
* SwiftUI

Essa análise deve ser usada apenas como inspiração arquitetural geral.

É proibido copiar:

* código;
* algoritmos;
* assets;
* modelos STL/OBJ;
* arquivos ONNX;
* arquivos JSON;
* imagens;
* qualquer recurso proprietário.

## Problemas atuais principais

1. iPhone 16 desfoca/caça foco.
2. iPhone 11 parece mais estável.
3. Escanear mais perto no iPhone 11 melhora muito o resultado.
4. Às vezes o app parece escanear 4 markers, mas exporta STL com 3.
5. Alguns scans saem muito fora da realidade.
6. Marker 1 já apareceu como instável em comparações.
7. A bottom tag 6,5 mm do v2 é instável.
8. A barra de distância é útil, mas só é confiável se a pose/foco estiverem bons.
