## 1. Objetivo
Esta especificação descreve a infraestrutura de CI/CD para o projeto **Dental Scanner**. O foco é permitir a geração de um artefato `.ipa` funcional para testes em dispositivos físicos, contornando a necessidade de um hardware macOS local e de certificados pagos da Apple através de um "Unsigned Build".

## 2. Stack Tecnológica de Infraestrutura
* **Ambiente de Execução:** GitHub Actions utilizando runners `macos-latest`.
* **Gerenciamento de Ferramentas:** `mise` (utilizado para garantir a versão exata do Tuist).
* **Orquestração de Projeto:** `Tuist 3.42.2` (geração de workspace e gerenciamento de dependências).
* **Motor de Compilação:** `xcodebuild` (Xcode Command Line Tools).

## 3. Arquitetura do Workflow (GitHub Actions)

### Estratégia de Build
Para permitir a compilação sem uma conta de desenvolvedor configurada no runner, o comando de build deve desativar explicitamente as verificações de segurança da Apple:

| Parâmetro | Função |
| :--- | :--- |
| `CODE_SIGNING_ALLOWED=NO` | Impede que o Xcode tente realizar qualquer assinatura no binário. |
| `CODE_SIGNING_REQUIRED=NO` | Remove a obrigatoriedade de certificados para a conclusão do build. |
| `CODE_SIGN_IDENTITY=""` | Garante que o processo não busque identidades no Keychain. |

### Processo de Empacotamento Manual
Como o Xcode não exporta arquivos `.ipa` sem assinatura de forma nativa, o workflow realiza um "workaround" de sistema de arquivos:
1.  O binário `.app` é compilado para o SDK `iphoneos`.
2.  Uma estrutura de pastas padrão iOS é criada via terminal: `mkdir -p Payload`.
3.  O `.app` é movido para dentro da pasta `Payload`.
4.  A pasta é compactada e renomeada para `.ipa`.

## 4. Fluxo de Entrega e Instalação (Post-Build)
O artefato gerado é um **Unsigned IPA**. O método de instalação recomendado para o ambiente Windows do usuário é:
1.  **Download:** Obter o arquivo `DentalScanner.ipa` dos artefatos do GitHub Actions.
2.  **Sideloading:** Utilizar o **Sideloadly**
3.  **Assinatura Local:** Estas ferramentas utilizarão o Apple ID pessoal do usuário para assinar o app localmente, permitindo a instalação no iPhone via cabo ou Wi-Fi.

## 6. Comandos Chave do Runner
```bash
# Geração do projeto via Tuist
mise exec tuist -- tuist fetch
mise exec tuist -- tuist generate

# Build bypassando assinatura
xcodebuild -workspace DentalScanner.xcworkspace \
-scheme DentalScanner \
-configuration Release \
-sdk iphoneos \
CODE_SIGNING_ALLOWED=NO \
CODE_SIGNING_REQUIRED=NO