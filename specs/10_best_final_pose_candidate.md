# 10 - Best Final Pose Candidate

## 1. Problema

O fluxo normal `singleArucoV1` melhorou bastante: os 4 markers chegam a 100%, a UI mostra refinamento, o usuario mantem todos os markers visiveis e o app gera STL ao fim da janela de qualidade.

Mesmo assim, scans da mesma peca ainda variam. Como a peca fisica e a geometria dos markers sao as mesmas, os STLs deveriam ser muito parecidos entre si. Essa repetibilidade ainda precisa melhorar.

O problema provavel e que esperar mais tempo nem sempre melhora a pose final. O melhor conjunto de poses pode ter ocorrido alguns segundos antes do export. Se o app exporta sempre o estado mais recente, frames posteriores com normal instavel, reprojection pior, movimento ou foco ruim podem degradar o resultado.

Precisamos separar "ultimo estado no momento do export" de "melhor candidato observado durante o refinamento".

## 2. Escopo

Dentro do escopo desta melhoria futura:

```txt
singleArucoV1
fase apos M0/M1/M2/M3 em 100%
fase de refinamento normal
selecao de melhor pose final
diagnostics/report
debug emergencial
```

Fora do escopo:

```txt
OpenCV detector
solvePnP base
STLExporter geometry
Guided Static Capture
v2 dual-tag
ARKit Assist
GitHub Actions
comparador Python
scanner profissional/ground truth real
```

## 3. Definicao de Best Final Pose Candidate

Um Best Final Pose Candidate e um snapshot leve do melhor conjunto de poses/observacoes finais encontrado durante a fase de refinamento.

Conceitualmente, o candidato deve conter:

```txt
score
timestamp
poses por marker
observacoes por marker
worst normal std
worst reprojection
motivo de aceite
```

Os nomes finais devem se adaptar aos tipos reais do projeto. O candidato nao deve guardar imagens, frame buffers ou dados pesados.

## 4. Quando comeca

O sistema so deve comecar quando todos estes criterios forem verdadeiros:

```txt
profile == singleArucoV1
Guided Static Capture == off
M0/M1/M2/M3 == 100%
export gate real valido
normal finalization em andamento
```

Nao deve rodar antes dos 4 markers chegarem em 100%. O export gate momentaneamente valido, sozinho, nao basta.

## 5. Frequencia de avaliacao

A avaliacao deve ser throttled:

```txt
normalBestCandidateEvaluationIntervalSeconds = 1.0
```

Se performance exigir, usar 2.0 segundos.

Regras:

```txt
nao avaliar score pesado em todo frame
nao gerar STL temporario
nao fazer I/O durante captura
nao serializar JSON durante callback de frame
```

## 6. Score inicial

O score inicial deve ser simples, incremental e facil de calibrar pelos diagnostics.

O score deve favorecer:

```txt
export gate valido
todos markers em 100%
mais observacoes uteis por marker
menor reprojection
menor normalStdDegrees
maior estabilidade angular
menor motion/camera instability
poses finitas/validas
```

O score deve penalizar:

```txt
marker faltando
pose nao finita
reprojection alto
normalStdDegrees alto
variacao angular alta
observacoes muito desequilibradas entre markers
```

O primeiro score nao precisa ser perfeito. Ele precisa ser registrado em diagnostics para calibracao posterior com CSVs, comparador STL e testes repetidos da mesma peca.

## 7. Salvamento do candidato

Durante o refinamento, a cada avaliacao throttled:

```txt
se currentCandidate.score > bestFinalPoseCandidate.score:
    bestFinalPoseCandidate = currentCandidate
```

Salvar apenas os dados necessarios e leves:

```txt
poses finais candidatas
contagens por marker
score
metricas agregadas
timestamp
motivo de aceite/rejeicao
```

Nao salvar:

```txt
imagens
pixel buffers
listas enormes de observacoes
arquivos temporarios
STL temporario
```

## 8. Uso no export

No momento do export:

```txt
se bestFinalPoseCandidate valido existir:
    exportar usando ele
senao:
    usar fluxo atual como fallback
```

O fallback e obrigatorio. A feature nao pode quebrar export se nenhum candidato valido tiver sido encontrado.

Tambem deve haver protecao contra candidato antigo demais ou incompatibilidade de markers:

```txt
candidato deve conter os 4 markers esperados
poses devem ser finitas
poses nao podem ser default/placeholders
export gate ainda deve ser valido
```

## 9. Diagnostics/report

Adicionar ao `_diagnostics.json` e ao `_report.json`, quando a feature for implementada:

```txt
usedBestFinalPoseCandidate
bestFinalPoseCandidateScore
bestFinalPoseCandidateTimestampSeconds
bestFinalPoseCandidateAgeSeconds
bestFinalPoseCandidateWorstNormalStd
bestFinalPoseCandidateWorstReprojection
bestFinalPoseCandidateObservationsByMarker
bestFinalPoseCandidateAcceptedCount
bestFinalPoseCandidateLastRejectReason
```

Esses campos devem permitir responder:

```txt
o export usou o melhor candidato ou o fluxo atual?
o melhor candidato aconteceu quanto tempo antes do export?
qual era o score?
qual marker limitou o score?
normal/reprojection estavam melhores do que no estado final?
```

## 10. Debug emergencial

O debug completo continua desligado enquanto estiver instavel.

Quando esta feature for implementada, adicionar ao debug emergencial, sem montar `ScannerDebugSnapshot` completo:

```txt
Best candidate score
Best candidate age
Best candidate normal
Best candidate reprojection
Best candidate obs M0
Best candidate obs M1
Best candidate obs M2
Best candidate obs M3
Used best candidate
```

Tudo deve vir de propriedades estreitas e read-only no `ScannerViewModel`, com `N/A` para valores ausentes, NaN ou infinity.

## 11. UI

Feedback simples desejado:

```txt
Melhor qualidade encontrada
Qualidade atual: ...
Melhor qualidade salva
```

UI nao e prioridade da primeira implementacao se isso complicar o fluxo. A prioridade inicial e escolher melhor pose com seguranca e registrar diagnostics.

## 12. Criterios de aceitacao

1. Nao roda antes dos 4 markers em 100%.
2. Nao avalia em todo frame sem throttle.
3. Nao gera STL temporario.
4. Nao faz I/O durante captura.
5. Export usa best candidate quando valido.
6. Fallback usa fluxo atual.
7. Diagnostics indicam se usou best candidate.
8. Debug emergencial continua abrindo.
9. `singleArucoV1` continua padrao.
10. Guided Static continua desligado.

## 13. Plano de implementacao futura

Dividir em commits pequenos:

```txt
Commit 1: criar tipos internos e score read-only sem alterar export
Commit 2: salvar best candidate durante refinamento
Commit 3: usar best candidate no export com fallback
Commit 4: diagnostics/report/debug emergencial
Commit 5: calibrar score com CSVs
```

Cada commit deve manter o app compilavel e testavel no iPhone.

## 14. Riscos

```txt
score mal calibrado pode escolher candidato pior
salvar candidato pesado pode afetar performance
usar candidato antigo demais pode exportar pose desatualizada
misturar observacoes de momentos diferentes pode piorar geometria
diagnostics podem ficar confusos
```

Mitigacoes:

```txt
usar throttle
guardar snapshot leve
manter fallback do fluxo atual
registrar score e motivo no diagnostics
validar com scans repetidos antes de confiar no score
```

## 15. Relacao com validacao futura

Quando houver STL do scanner profissional do molde, esta feature deve ser validada contra ground truth real.

Por enquanto, validar por:

```txt
repetibilidade entre scans da mesma peca
comparador STL
inspecao visual
diagnostics
```

O objetivo inicial nao e provar precisao absoluta, mas reduzir variacao entre scans iguais e evitar que o export use um estado final pior do que um candidato anterior ja observado.
