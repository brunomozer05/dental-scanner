# 02 — Marker Profiles

## Perfis atuais

O app possui dois perfis principais:

```txt
singleArucoV1
dualArucoV2
```

O padrão atual do projeto é `dualArucoV2`, mas o `singleArucoV1` deve continuar disponível para testes e comparação.

## Marker v1

O `singleArucoV1` usa uma ArUco por marker físico.

Vantagens:

* mais simples;
* menos pontos de falha;
* tag maior tende a ser mais estável;
* pode ser mais repetível se a tag v2 inferior estiver piscando.

Desvantagens:

* menos pontos 2D para solvePnP;
* orientação pode ser mais sensível a erro nos cantos;
* menos informação geométrica que v2.

## Marker v2

O `dualArucoV2` usa duas ArUcos por marker físico:

```txt
top tag: 8x8 mm
bottom tag: 6,5x6,5 mm
gap vertical: 0,5 mm
distância aproximada entre centros: 7,75 mm
```

IDs:

```txt
Marker físico 1: top ID 0 / bottom ID 1
Marker físico 2: top ID 2 / bottom ID 3
Marker físico 3: top ID 4 / bottom ID 5
Marker físico 4: top ID 6 / bottom ID 7
```

## Regras do v2

* A top tag 8x8 é mais estável.
* A bottom tag 6,5 mm é mais instável e pode piscar.
* O solvePnP dual-tag com top + bottom deve ter prioridade quando confiável.
* O top fallback pode manter tracking visual.
* O top fallback não deve dominar a rotação final.
* O bottom fallback deve ter peso muito baixo.
* A bottom tag pequena não deve contaminar a orientação se estiver com baixa qualidade.

## Export v2

O v2 deve exportar usando:

```txt
marker_reference_2.stl
```

O modelo de referência precisa estar alinhado corretamente com a origem/local frame definido para o marker.

## Futuro marker v3

Existe a ideia de um marker híbrido:

```txt
1 ArUco maior
+ bolinhas/pontos proprietários
+ fundo branco / elementos pretos
```

Esse marker v3 ainda não deve ser implementado agora.

Possíveis vantagens:

* ArUco identifica o marker;
* bolinhas extras ajudam orientação/refino;
* evita depender de uma segunda ArUco pequena;
* pode ser mais robusto para impressão/adesivo.

## Regra de segurança

Não remover v1 enquanto v2 não for comprovadamente melhor.

Deve haver comparação objetiva usando:

* comparador STL;
* `_report.json`;
* scans repetidos;
* mesmo celular;
* mesma distância;
* mesma iluminação.
