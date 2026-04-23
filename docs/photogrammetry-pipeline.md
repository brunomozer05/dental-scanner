# Pipeline de Fotogrametria

## Objetivo

Reconstruir a pose espacial de um conjunto de tags ArUco com escala absoluta, orientacao global e qualidade suficiente para convergir de um MVP de ~500 um para uma meta de +-100 um.

## 1. Aquisicao

Entradas esperadas:

- 15 a 30 imagens RGB de alta resolucao
- 4 a 8 tags ArUco visiveis em boa parte da orbita
- camera calibrada por dispositivo

Quality gates em tempo real:

- sharpness acima do limiar configurado
- overlap estimado entre 70% e 80%
- motion blur abaixo do limite
- iluminacao com desvio padrao menor que 15% da media
- pelo menos 4 tags com deteccao estavel

## 2. Pre-processamento

Passos planejados:

1. Correcao de distorcao com intrinsecos persistidos
2. Normalizacao de iluminacao
3. CLAHE quando a iluminacao estiver heterogenea
4. Rejeicao de frames com blur excessivo
5. Preparacao de dados para feature detection

## 3. ArUco como ancora de escala

Cada tag fornece:

- identificacao unica
- corners refinados em subpixel
- pose relativa camera-tag
- unidade absoluta se os object points forem definidos em milimetros

Uso no pipeline:

- inicializacao de referencia global
- validacao de cobertura
- verificacao de consistencia de escala
- restricao de bundle adjustment

## 4. Features e matching

Abordagem recomendada:

- ORB como baseline por desempenho
- SIFT como opcao para cenas mais dificeis
- matching com filtro bidirecional
- RANSAC para rejeicao de outliers
- grafo incremental de pares validos

Heuristicas de pareamento:

- proximidade angular entre buckets de cobertura
- tags compartilhadas entre frames
- overlap minimo configuravel

## 5. Structure from Motion

Pipeline alvo:

1. escolher pares robustos
2. estimar pose relativa
3. triangular pontos esparsos
4. expandir mapa incrementalmente
5. executar bundle adjustment local e global
6. prender escala ao sistema ArUco

No estado atual do repositorio, `SfMEngine` e `BundleAdjustment` funcionam como scaffold de arquitetura e precisam ser substituidos por implementacao de producao.

## 6. Malha STL das tags

Fase desejada:

- fusao das poses por ID de tag
- rejeicao de outliers entre vistas
- geracao de volumes simples representando cada tag no espaco
- exportacao STL final

O `MeshReconstructor` atual gera volumes simples orientados pelas poses das tags.

## 7. Validacao final

Saidas tecnicas:

- nuvem esparsa
- nuvem densa
- malha
- relatorio de captura
- relatorio de erro contra referencia

Validacao final recomendada:

- alinhamento ICP contra CAD/fixture de referencia
- RMS em micrometros
- percentual de pontos abaixo de 100 um
- heatmap de erro
