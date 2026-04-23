# Sample Calibration Dataset

Este diretorio documenta o formato esperado para um dataset de calibracao.

O repositorio nao inclui imagens reais para evitar peso excessivo no Git. Em vez disso, o arquivo `manifest.json` descreve como organizar a coleta.

Estrutura sugerida:

```text
Resources/SampleCalibrationDataset/
|- manifest.json
|- IMG_0001.jpg
|- IMG_0002.jpg
|- ...
```

Regras:

- coletar de 30 a 50 imagens
- variar angulo, distancia e rotacao
- manter o tabuleiro inteiro visivel
- evitar sombras duras

