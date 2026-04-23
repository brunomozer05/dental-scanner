# Estrategia de Precisao

## Meta

Precisao final de +-100 um com camera RGB, sem LiDAR.

## 1. Calibracao

Sem calibracao forte, a meta de precisao nao e realista.

Parametros minimos:

- tabuleiro 10x7 ou maior
- 30 a 50 imagens
- boa variacao angular
- erro medio de reprojecao < 0.3 px

Modelo de camera recomendado:

- Brown-Conrady completo
- validacao por dispositivo
- recalibracao quando houver troca de iPhone ou mudanca significativa de setup

## 2. Escala absoluta

As tags ArUco devem ancorar:

- escala
- orientacao global
- consistencia entre sequencias de captura

Regras praticas:

- definir os object points das tags em milimetros
- validar escala entre multiplas tags
- rejeitar frames com divergencia de escala

## 3. Subpixel e cantos

Pontos sensiveis:

- cantos ArUco com refinamento subpixel
- localizacao de features com interpolacao adequada
- solvePnP com otimizacao nao linear

## 4. Quality gates que mais impactam precisao

- blur
- foco
- sobrexposicao
- reflexo especular
- cobertura angular incompleta
- baixa sobreposicao entre frames

## 5. Validacao objetiva

O criterio recomendado para aceite:

- RMS dentro da banda alvo
- 95% ou mais dos pontos abaixo de 100 um
- verificacao com fixture de referencia conhecida
- repetibilidade entre sessoes

## 6. Estrategia de entrega incremental

1. Entrega 1: arquitetura, CI, persistencia, quality gates e fluxo guiado
2. Entrega 2: deteccao ArUco real e pose 6DoF
3. Entrega 3: matching robusto e SfM incremental
4. Entrega 4: bundle adjustment global + validacao de escala
5. Entrega 5: STL final das tags e validacao clinica/laboratorial

## 7. Limitacoes conhecidas

- reflexos e sombras duras sobre tags ou suporte degradam a deteccao
- distancia camera-objeto fora da faixa util reduz nitidez e cobertura
- sem fixture estavel, a repetibilidade cai
- a meta de 100 um exige validacao com referencia fisica, nao apenas inspecao visual
