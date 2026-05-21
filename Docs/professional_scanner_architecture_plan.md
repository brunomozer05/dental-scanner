# Professional Scanner Architecture Plan

Este documento inicia uma evolucao arquitetural propria para o DentalScanner,
baseada apenas em ideias gerais observadas por analise estrutural segura de um
app profissional de referencia. Nao ha copia de codigo, algoritmos, assets ou
logica proprietaria.

## 1. Estado atual do DentalScanner

O DentalScanner ja possui um pipeline funcional de scan baseado em markers:

- Swift e SwiftUI para app e UI.
- AVFoundation para captura de camera.
- Camera traseira wide fisica preferida.
- OpenCV ArUco via bridge Objective-C++.
- solvePnP para estimativa de pose.
- Perfis de marker `singleArucoV1` e `dualArucoV2`.
- Marker v2 com top tag 8x8 mm e bottom tag 6.5x6.5 mm.
- Fallback top/bottom para manter tracking quando a bottom tag pisca.
- CoreMotion/IMU para score de estabilidade de movimento.
- Quality score, penalidade de borda, sharpness/blur e foco.
- Rejeicao de outliers no refinamento final.
- Diagnosticos planares e de estabilidade estatica.
- Export STL e viewer STL.
- Painel debug seguro com configuracoes editaveis.
- Comparador STL externo no PC.

O app ja tem uma boa base experimental. O proximo salto deve ser menos sobre
adicionar pequenos filtros isolados e mais sobre organizar qualidade, captura e
refinamento como subsistemas claros.

## 2. Problemas atuais

Problemas observados em testes reais:

- iPhone 16 pode cacar/perder foco durante o scan.
- Quando o foco oscila, os cantos ArUco ficam ruins e a inclinacao dos markers
  varia entre scans.
- Mesmo com foco lock, alguns frames ruins ainda podem entrar no resultado.
- A posicao dos markers costuma ficar proxima, mas a rotacao/normal varia.
- Alguns scans ficam fora da realidade.
- Em boca real, encaixar diretamente os 4 markers ainda falha com frequencia.
- A bottom tag 6.5 mm do v2 pisca mais que a top tag 8 mm.
- Fallback e frames de borda podem contaminar o resultado final se nao forem
  tratados de forma centralizada.

Hipoteses principais:

- Variacao de foco/intrinsics/exposicao no iPhone 16.
- Movimento do usuario durante captura.
- Corners ruins perto das bordas da imagem.
- Bottom tag pequena gerando dual-tag fraco.
- Fallback ajudando tracking visual, mas puxando rotacao final.
- Falta de um gate unico e rigoroso para qualidade final de frame.

## 3. Arquitetura alvo propria

A arquitetura alvo deve separar claramente quatro responsabilidades:

- Captura confiavel: camera, foco, exposicao, intrinsics, sharpness e motion.
- Observacao confiavel: deteccao ArUco, score de pose, borda, reprojection e
  consistencia top/bottom.
- Fusao confiavel: pesos separados para posicao/rotacao, rejeicao de outliers,
  preferencia por dual-tag bom e cobertura angular real.
- Diagnostico confiavel: debug seguro, report por scan e metricas legiveis.

Principios:

- Tracking visual pode ser permissivo; export final deve ser rigoroso.
- Fallback mantem UX viva; dual-tag bom domina pose final.
- Frames fora de foco nao contam como good frames.
- Rotacao deve ter score/peso proprio, mais rigoroso que posicao.
- Camera e sensores devem produzir snapshots seguros e auditaveis.
- Todo criterio de qualidade precisa aparecer no debug ou em report.
- O pipeline deve continuar usavel, mas com avisos claros de baixa confianca.

## 4. Modulos planejados

### Camera

Responsabilidades:

- Selecionar camera wide fisica traseira.
- Controlar foco, exposicao, white balance e torch.
- Diagnosticar device, format, fps, intrinsics e lensPosition.
- Detectar mudancas de intrinsics/device/format durante scan.

Alvo futuro:

- `CameraFrameService.swift` continua como orquestrador de captura.
- `CameraFocusController.swift` isola foco manual, foco por ArUco, lock/unlock
  e cooldown.
- `CameraDebugSnapshot.swift` sai de `CameraFrame.swift` se isso reduzir
  acoplamento.

### Focus

Responsabilidades:

- Foco guiado pelo ArUco.
- Foco manual/lensPosition para testes.
- Lock apos foco estabilizar.
- Janela de settle apos mudanca de lensPosition.
- Rejeicao de frames capturados durante foco instavel.

Checklist especifico:

- Escolher preferencialmente top tag 8x8.
- Evitar bottom tag pequena como alvo principal.
- Aplicar cooldown para nao induzir caca de foco.
- Expor no debug ultimo marker/tag/ponto usado para foco.

### Frame Quality

Responsabilidades:

- Sharpness/blur score.
- Rejeicao rigida de frames fora de foco.
- Penalidade por borda da imagem.
- Score de camera por frame.
- Distancia apenas como guia quando pose/frame forem confiaveis.

Alvo futuro:

- `FrameSharpnessAnalyzer.swift` centraliza blur/sharpness.
- `CameraFrameQuality` fica pequeno e auditavel.
- Todos os motivos de rejeicao sao enumerados e contabilizados.

### Motion

Responsabilidades:

- Ler CoreMotion/IMU.
- Calcular estabilidade angular e aceleracao.
- Penalizar mais a rotacao quando ha movimento.
- Expor status seguro no debug.

Alvo futuro:

- `MotionFrameQualityService.swift` continua separado.
- Motion nao deve fundir pose diretamente nesta fase; apenas filtrar qualidade.

### ARKit Assist

Responsabilidades planejadas:

- Usar ARKit como assistente experimental de estabilidade/camera tracking.
- Comparar transform de camera entre frames.
- Diagnosticar movimento e possivel mudanca de escala/normal.
- Nunca substituir solvePnP inicialmente.

Possiveis arquivos:

- `ARKitCaptureAssistService.swift`
- `ARKitFrameQuality.swift`

Regras:

- Comecar desligado por padrao.
- Usar apenas como metrica/assistente.
- Nao misturar ARKit no export final antes de validar repetibilidade.

### Pose Quality

Responsabilidades:

- Score por observacao.
- Reprojection error.
- Area top/bottom.
- Consistencia geometrica top/bottom.
- Edge margin.
- Source da pose: dualTag, topFallback, bottomFallback.
- Confianca separada para posicao e rotacao.

Alvo futuro:

- `PoseQualityEvaluator.swift` centraliza os criterios.
- `PoseObservationQuality` vira fonte unica de decisao para final refinement.

### Final Refinement

Responsabilidades:

- Selecionar melhores observacoes por marker fisico.
- Preferir dual-tag bom.
- Usar fallback apenas quando necessario.
- Rejeitar outliers de posicao, rotacao e normal.
- Usar pesos separados para posicao e rotacao.
- Gerar diagnostico do que foi usado e descartado.

Alvo futuro:

- `FinalPoseRefiner.swift` continua, mas recebe dados ja qualificados.
- Nenhuma observacao fora de foco deve entrar na selecao final quando houver
  alternativa melhor.

### Marker Model Library

Responsabilidades futuras:

- Catalogar modelos de referencia proprios.
- Versionar geometria de markers e scan bodies.
- Validar compatibilidade de STL/modelo com marker profile.
- Preparar caminho para marker v3 hibrido.

Nao fazer:

- Nao reutilizar assets/modelos do app de referencia.
- Nao depender de nomes proprietarios observados no IPA.

### Export

Responsabilidades:

- Exportar apenas com poses finais qualificadas.
- Guardar diagnostico do export.
- Futuramente gerar report JSON por scan.

Alvo futuro:

- `STLExporter.swift` permanece isolado.
- `ScanExportReport.json` pode conter qualidade final, markers usados, outliers,
  foco, blur, motion e cobertura.

### Debug

Responsabilidades:

- Painel seguro, sem crash, com snapshots sanitizados.
- Config editavel para testes.
- Contadores por motivo de rejeicao.
- Mostrar diferenca entre tracking visual e qualidade de export.

Regras:

- UI nao calcula metrica pesada no body.
- Dados invalidos viram `—`.
- Secoes avancadas entram por fases.

## 5. Estrutura modular futura sugerida

Nao mover arquivos agora. Esta estrutura serve como norte para refactors
pequenos e seguros:

```txt
ScannerMVP/
  Camera/
    CameraFrameService.swift
    CameraFocusController.swift
    CameraDebugSnapshot.swift

  ARKitAssist/
    ARKitCaptureAssistService.swift
    ARKitFrameQuality.swift

  Motion/
    MotionFrameQualityService.swift

  Vision/
    ArUcoDetector.swift
    FrameSharpnessAnalyzer.swift

  Pose/
    PoseEstimator.swift
    PoseQualityEvaluator.swift
    PoseFusionService.swift
    FinalPoseRefiner.swift

  Export/
    STLExporter.swift

  UI/
    ScannerView.swift
    ScannerViewModel.swift
    ScannerDebugPanelView.swift
    ScannerDebugSnapshot.swift
```

## 6. Fases de implementacao

### Fase 1 - Camera e foco mais previsiveis

- Confirmar wide fisica em todos os devices.
- Fortalecer foco guiado por ArUco.
- Adicionar foco manual/lensPosition para testes.
- Adicionar zoom digital controlado para melhorar tamanho aparente do marker.
- Bloquear good frames enquanto foco/exposicao estao instaveis.

### Fase 2 - Frame quality centralizado

- Criar `FrameSharpnessAnalyzer`.
- Centralizar motivos de rejeicao de frame.
- Tornar distance guide dependente de qualidade real.
- Adicionar report de frames rejeitados por foco, blur, borda e motion.

### Fase 3 - Pose quality centralizado

- Criar `PoseQualityEvaluator`.
- Consolidar score de observacao.
- Separar score de posicao e score de rotacao.
- Reforcar deteccao de bottom pequena e par top/bottom inconsistente.

### Fase 4 - Final refinement rigido

- Usar top N observacoes por marker.
- Aplicar rejeicao robusta de normal/rotacao.
- Preferir dual-tag bom no v2.
- Gerar diagnostico final por marker.

### Fase 5 - ARKit Assist experimental

- Adicionar servico desligado por padrao.
- Medir estabilidade de camera entre frames.
- Comparar motion/ARKit/ArUco sem alterar export.
- Decidir se ARKit ajuda a detectar frames ruins.

### Fase 6 - Marker Model Library e report por scan

- Criar catalogo proprio de modelos/markers.
- Adicionar `ScanQualityReport.json`.
- Preparar caminho para marker v3 hibrido.

## 7. Checklist tecnico para proximas etapas

- [ ] Camera wide fisica fixa.
- [ ] Foco guiado por ArUco.
- [ ] Foco manual/lensPosition.
- [ ] Zoom digital controlado.
- [ ] Sharpness/blur score.
- [ ] Rejeicao rigida de frames fora de foco.
- [ ] ARKit Assist experimental.
- [ ] Quality score centralizado.
- [ ] Pesos separados para posicao/rotacao.
- [ ] Final refinement mais rigido.
- [ ] Report JSON por scan futuramente.
- [ ] Marker v3 hibrido futuramente.

## 8. Riscos

- ARKit pode introduzir complexidade sem melhorar repetibilidade se usado cedo.
- Zoom digital pode melhorar tamanho do marker, mas piorar ruido se exagerado.
- Foco automatico guiado pode induzir caca de foco se chamado sem cooldown.
- Gates muito rigidos podem impedir scan em condicoes reais.
- Debug excessivo pode voltar a causar instabilidade se calcular no body.
- Refactors grandes podem quebrar um pipeline que ja funciona parcialmente.
- Usar referencia profissional de forma indevida pode criar risco legal; manter
  apenas inspiracao arquitetural e implementacao propria.

## 9. Decisao desta etapa

Nesta etapa nao moveremos arquivos nem alteraremos pipeline. O objetivo e criar
um mapa tecnico para evoluir o DentalScanner com passos pequenos, verificaveis e
seguros.
