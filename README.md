# DentalScanner

Aplicativo iOS nativo em Swift para escaneamento 3D de abutments dentarios usando fotogrametria + marcadores ArUco, sem dependencia de LiDAR.

Este repositorio agora contem a fundacao do projeto:

- Arquitetura modular alinhada ao pipeline pedido
- App iOS em SwiftUI com fluxo demo de captura guiada
- Camada `DentalScannerKit` com Core, ArUco, Photogrammetry e Export
- Testes unitarios iniciais para validacao de sessao, tags, STL e acuracia
- GitHub Actions com geracao de projeto via XcodeGen
- Documentacao tecnica e assets de calibracao

Importante: esta primeira iteracao prioriza arquitetura, contratos e automacao. O backend real de deteccao ArUco via OpenCV e a reconstrucao SfM/MVS de producao ainda precisam ser conectados.

## Requisitos de produto

- iOS 15.0+
- iPhone 8 ou superior
- Camera RGB 12 MP ou superior
- Sem uso de LiDAR
- Tags ArUco 4x4_50 ou 4x4_100 com 8 mm x 8 mm
- Meta de precisao final: +-100 um

## Estrutura do repositorio

```text
DentalScanner/
|- App/
|- UI/
|- Core/
|- ArUco/
|- Photogrammetry/
|- Export/
|- Shared/
|- Support/
Tests/
docs/
Resources/
.github/workflows/
project.yml
```

## Setup do ambiente

### Opcao 1: abrir em um Mac com Xcode

1. Instale Xcode 15.2 ou superior.
2. Instale XcodeGen:

```bash
brew install xcodegen
```

3. Gere o projeto:

```bash
xcodegen generate
```

4. Abra `DentalScanner.xcodeproj` no Xcode.
5. Rode o scheme `DentalScanner` em um simulador iPhone ou dispositivo fisico.

### Opcao 2: usar apenas GitHub Actions

O workflow em `.github/workflows/ios-build.yml`:

- instala Xcode 15.2
- instala XcodeGen
- gera o projeto
- roda build
- roda testes
- gera sempre um `.ipa` unsigned como artifact
- gera tambem um `.ipa` assinado quando os secrets de assinatura estiverem configurados

## Gerar `.ipa` no GitHub Actions

Agora existem dois formatos de artifact:

- `DentalScanner-IPA`: sempre gerado, no mesmo estilo do seu outro projeto, com `.ipa` unsigned
- `DentalScanner-Signed-IPA`: opcional, apenas quando os secrets de assinatura estiverem configurados

Importante: o `.ipa` unsigned serve para baixar o arquivo pronto do GitHub, mas nao instala diretamente no iPhone sem assinatura posterior.

### Secrets obrigatorios

Cadastre em `Settings > Secrets and variables > Actions`:

- `BUILD_CERTIFICATE_BASE64`: conteudo Base64 do certificado `.p12`
- `P12_PASSWORD`: senha do `.p12`
- `BUILD_PROVISION_PROFILE_BASE64`: conteudo Base64 do `.mobileprovision`
- `KEYCHAIN_PASSWORD`: senha temporaria do keychain usado no runner
- `APPLE_TEAM_ID`: Team ID da sua conta Apple Developer

### Variable opcional

Cadastre em `Settings > Secrets and variables > Actions > Variables`:

- `IOS_EXPORT_METHOD`: `development` ou `ad-hoc`

Se nada for definido, o workflow usa `development`.

### Como converter os arquivos para Base64

No Mac:

```bash
base64 -i Certificates.p12 | pbcopy
base64 -i Profile.mobileprovision | pbcopy
```

No Windows PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("Certificates.p12"))
[Convert]::ToBase64String([IO.File]::ReadAllBytes("Profile.mobileprovision"))
```

### Requisitos para instalar no celular

- o `Bundle Identifier` do app precisa bater com o provisioning profile
- o iPhone precisa estar incluido no profile se o metodo for `development` ou `ad-hoc`
- o certificado precisa pertencer ao mesmo time Apple do profile

### Onde baixar o `.ipa`

Depois do workflow terminar:

1. abra a execucao no GitHub Actions
2. entre em `Artifacts`
3. baixe `DentalScanner-IPA` para o `.ipa` unsigned
4. se houver, baixe `DentalScanner-Signed-IPA` para o build assinado

O artifact inclui:

- um `.zip` gerado automaticamente pelo GitHub Actions

Dentro do `.zip` do artifact ficam:

- `DentalScanner.ipa`

No artifact assinado tambem pode haver:

- plist(s) de exportacao
- `DentalScanner.xcarchive`

### Como instalar

Com o `.ipa` assinado em maos, voce pode instalar via:

- Xcode
- Apple Configurator 2
- MDM
- TestFlight, se depois trocar o metodo para distribuicao adequada

## Como calibrar a camera

1. Imprima o tabuleiro `10x7` em escala conhecida.
2. Use iluminacao uniforme e evite reflexos especulares.
3. Capture de 30 a 50 imagens com variacao real de angulo e distancia.
4. Garanta o tabuleiro inteiro visivel em todos os frames.
5. Aceite a calibracao somente quando o erro medio de reprojecao ficar abaixo de `0.3 px`.
6. Persista a calibracao por dispositivo.

Assets de apoio:

- `Resources/CalibrationTargets/checkerboard_10x7.svg`
- `Resources/SampleCalibrationDataset/manifest.json`

## Como posicionar as tags ArUco

- Use 4 a 8 tags simultaneas.
- Tamanho fisico de cada tag: `8 mm x 8 mm`.
- Distribua as tags ao redor do fixture para manter pelo menos 4 visiveis em quase toda a orbita.
- Evite oclusao por dedos, pinas ou suportes.
- Mantenha as tags no mesmo plano de referencia global sempre que possivel.
- Prefira imprimir em material matte para reduzir reflexos.

## Fluxo de captura planejado

1. Carregar calibracao valida.
2. Posicionar o objeto com tags visiveis.
3. Capturar de 15 a 30 poses ao redor do abutment.
4. Garantir sobreposicao de 70-80% entre frames consecutivos.
5. Validar nitidez, blur, iluminacao e visibilidade de tags em tempo real.
6. Rodar SfM incremental, ajuste global e densificacao.
7. Gerar malha e exportar STL/OBJ + relatorio.

## Estado atual da implementacao

Ja implementado:

- `CameraEngine` com configuracao de captura de alta precisao via `AVFoundation`
- `CalibrationManager` para avaliar e persistir intrinsecos
- `SessionManager` com cobertura angular, quality gates e progresso
- `ArUcoDetector` com interface pronta para backend OpenCV
- `TagValidator` e `PoseEstimator`
- `SfMEngine`, `BundleAdjustment`, `MeshReconstructor` e `AccuracyValidator` em modo scaffold
- `STLExporter` e `MeasurementReportGenerator`
- UI demo em SwiftUI para provar o fluxo

Proximo passo tecnico obrigatorio:

- integrar um backend real de OpenCV para deteccao ArUco e `solvePnP`
- implementar ORB/SIFT + matching robusto com RANSAC
- substituir o SfM scaffold por pipeline incremental real
- adicionar MVS e malha de producao
- validar com corpo de prova e ICP contra CAD de referencia

## Debug mode recomendado

Manter um modo debug com:

- IDs das tags visiveis por frame
- score de nitidez
- score de overlap
- mapa de cobertura angular
- contagem de features detectadas
- pares aceitos/rejeitados no matching
- mapa de calor de erro no pos-processamento

## Troubleshooting

### Nao detecta tags

- Verifique impressao das tags.
- Aumente iluminacao difusa.
- Evite motion blur.
- Confirme se 4 ou mais tags estao inteiras no frame.

### Reconstrucao instavel

- Refaca a calibracao se o erro passar de `0.3 px`.
- Aumente a sobreposicao entre capturas.
- Capture em orbita mais lenta.
- Remova frames com brilho especular excessivo.

### Escala incorreta

- Confirme dimensao fisica real das tags.
- Verifique se o backend de pose usa pontos-objeto em milimetros.
- Rejeite tags com escala inconsistente.

### Build do CI falha

- Verifique se o `project.yml` foi atualizado junto com novos arquivos.
- Rode `xcodegen generate` antes do build local.
- Confirme a versao do Xcode no workflow.

## Documentacao tecnica

- [Pipeline de Fotogrametria](docs/photogrammetry-pipeline.md)
- [Estrategia de Precisao](docs/precision-strategy.md)
- [Formato de Dados](docs/data-format.md)

## Roadmap sugerido

1. MVP com precisao de ~500 um
2. Integracao OpenCV + ArUco real
3. SfM incremental com bundle adjustment global
4. Validacao com fixture de referencia
5. Refinamento para meta de +-100 um
