# 08 — Known Issues

## 1. iPhone 16 desfoca/caça foco

Sintoma:

* câmera perde foco durante scan;
* tags ficam borradas;
* pose ainda pode ser detectada;
* inclinação/rotação fica instável;
* STLs podem sair fora da realidade.

Observação:

* travar foco melhorou um pouco;
* ainda precisa foco guiado por ArUco e sharpness gating.

## 2. iPhone 11 parece mais estável

O iPhone 11 apresentou resultados melhores em alguns testes.

Escanear mais perto no iPhone 11 melhorou muito.

Isso sugere que tamanho da tag na imagem é crítico.

## 2.1. iPhones novos precisam de avaliacao por perfil de camera

Antes de escolher configuracao automatica por aparelho, os scans devem registrar e comparar:

```txt
deviceModelIdentifier
deviceMarketingName
cameraProfileId
cameraProfileName
camera fisica selecionada
zoom requested/applied/current
focus/exposure mode
intrinsics fx/fy/cx/cy
```

Perfis `Wide 1.0x`, `Wide 1.5x`, `Wide 2.0x` e variantes `Conservative Focus` sao experimentais. O perfil `Default` deve preservar o comportamento atual, especialmente no iPhone 11.

Resultados iniciais no iPhone 16 indicam:

* `Wide 1.5x` deve ser o perfil recomendado para modelos `iPhone17,*`;
* a câmera deve continuar sendo a wide física traseira, sem macro/ultra-wide/virtual como primeira opção;
* `Wide 2.0x` acusou distância/foco ruins e fica experimental/não recomendado por enquanto;
* distâncias abaixo de aproximadamente 120-125 mm aumentam o risco de perda de foco;
* a faixa inicial recomendada para iPhone 16 com `Wide 1.5x` é 150-180 mm.

O perfil `Wide 1.5x High Resolution Experimental` tenta aplicar 3840x2160 apenas quando selecionado manualmente. Ele nao e recomendado automaticamente; se o formato 4K nao estiver disponivel, o app deve voltar ao formato atual e registrar o fallback.

## 2.2. ROI/frame mask e observacoes uteis ainda nao controlam export

Foi adicionada mascara/ROI por classe de device para detectar markers perto demais da borda da imagem.

Estados esperados:

```txt
ok      -> Markers centralizados
warning -> Evite as bordas da camera / Centralize os markers
unknown -> sem dados suficientes
```

O Experimental Quality Mode agora classifica observacoes brutas como aceitas/rejeitadas usando ROI, distancia, risco de foco e pose finita. Esse progresso util experimental fica em paralelo e ainda nao bloqueia export, readiness ou finalizacao.

Valores iniciais registrados:

```txt
minValidFramesPerMarker = 65
targetOptimizationFrames = 300
```

Ela serve para gerar evidencia em `_report.json`, `_diagnostics.json` e debug emergencial antes de qualquer decisao de produto.

Proximos passos ainda pendentes:

* validar se observacoes uteis correlacionam com scans melhores;
* medir diversidade angular completa;
* investigar PnP/reprojection por canto;
* so depois considerar soft gate por ROI.

## 3. Distância de captura afeta muito

Scans perto ficaram muito mais parecidos com a realidade.

Scans longe tiveram P95/máximo muito maiores no comparador.

A barra de distância precisa ser ajustada para considerar:

* tamanho da tag;
* foco;
* sharpness;
* distância;
* confiabilidade da pose.

Atualizacao:

* a barra lateral agora deve usar thresholds dinamicos de `CameraProfile` / `DeviceQualityProfile`;
* no iPhone 16 com `Wide 1.5x`, 150-180 mm deve aparecer como faixa ideal dentro da barra;
* abaixo de 125 mm deve orientar o usuario a afastar para focar;
* acima de 220 mm deve indicar distancia excessiva.

## 4. Export com 3 markers

Erro recorrente:

```txt
Visualmente parece escanear 4 markers, mas o STL final sai com 3.
```

Isso ocorre cerca de 1 em 10 vezes segundo testes.

Prioridade máxima:

```txt
bloquear export se exportableMarkers.count < expectedPhysicalMarkerCount
```

## 5. Marker 1 instável

Em comparações anteriores, o Marker 1 apareceu como mais instável.

Possíveis causas:

* adesivo torto;
* impressão ruim;
* tag inferior desalinhada;
* fica mais na borda da câmera;
* pareamento/agrupamento do comparador;
* geometria física.

É necessário testar:

```txt
Marker 1 no centro
Marker 1 na esquerda
Marker 1 em outra posição
```

## 6. Bottom tag 6,5 mm instável

No v2, a bottom tag pisca mais.

Ela não deve dominar pose final.

Top tag 8x8 é mais confiável.

## 7. Debug antigo quebrado

O debug antigo causava crash.

Não reativar.

## 8. Comparador STL precisa usar report JSON

Hoje o comparador já compara STL/componentes.

Próxima evolução:

```txt
ler _report.json
comparar poses reais
comparar qualidade
identificar missing markers
comparar foco/sharpness
```

## 9. V1 vs V2 ainda precisa validação objetiva

Ainda não está comprovado que v2 é melhor que v1.

É preciso comparar:

```txt
mesma peça
mesma distância
mesmo celular
mesma iluminação
3 a 5 scans por modo
comparador STL + report JSON
```

## 10. Precisão profissional ainda depende do físico

Para chegar a níveis muito baixos de erro, não basta software.

Também é necessário:

* marker físico preciso;
* impressão/adesivo melhor;
* colagem plana;
* controle de iluminação;
* foco estável;
* câmera calibrada;
* protocolo de captura.
