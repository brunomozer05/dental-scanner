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

## 3. Distância de captura afeta muito

Scans perto ficaram muito mais parecidos com a realidade.

Scans longe tiveram P95/máximo muito maiores no comparador.

A barra de distância precisa ser ajustada para considerar:

* tamanho da tag;
* foco;
* sharpness;
* distância;
* confiabilidade da pose.

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
