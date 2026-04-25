## 1. Visão Geral do Conceito
O projeto consiste no desenvolvimento de uma aplicação iOS de alta precisão que utiliza as câmeras avançadas do iPhone para realizar o escaneamento intraoral. O sistema utiliza um marcador **ArUco 4x4** como componente de referência física (Scan Body), permitindo que o software calibre a precisão, determine a escala real e identifique a posição tridimensional exata (pose) do implante.

---

## 2. Arquitetura do Aplicativo

### A. Camada de Aquisição de Dados
* **Apple Object Capture API:** Utilizada para a reconstrução da malha 3D (mesh) a partir da sequência de imagens e vídeos capturados.
* **ARKit + Depth API (LiDAR):** Fornece a telemetria necessária para garantir que o modelo gerado esteja em escala 1:1 e auxilia no rastreamento espacial durante o movimento do cirurgião-dentista.
* **AVFoundation (Macro Mode):** Controle fino de foco e exposição para capturar os detalhes do padrão ArUco em ambiente macro, evitando desfoques.

### B. Processamento e Inteligência Artificial
* **Detecção ArUco (OpenCV):** Identificação e rastreamento dos quatro cantos do marcador em tempo real através de visão computacional.
* **Pose Estimation (SolvePnP):** Implementação do algoritmo *Perspective-n-Point* para calcular a translação e rotação do marcador em relação à câmera, definindo a angulação exata do implante.
* **Alinhamento de Malha (Best-fit):** O software identifica a captura bruta do marcador e a sobrepõe com o arquivo CAD (.STL) perfeito da biblioteca, corrigindo imperfeições da malha gerada pelo celular.

---

## 3. Fluxo do Utilizador (UX)
1.  **Registo do Caso:** Introdução dos dados do paciente e seleção do tipo/plataforma de implante.
2.  **Guião de Captura (AR Overlay):** * Interface de Realidade Aumentada que orienta o movimento (oclusal, vestibular, lingual).
    * Feedback visual (heatmap) indicando as áreas onde a captura de dados já é suficiente.
3.  **Processamento:** Otimização da malha 3D e alinhamento automático do eixo do implante com base no centro do ArUco.
4.  **Exportação:** Opção para salvar no dispositivo ou compartilhar o arquivo `.STL` final para laboratórios ou softwares de design (Exocad/3Shape).

---

## 4. Requisitos de Sistema e Stack Sugerida
* **Linguagem:** Swift (Nativo).
* **Frameworks 3D:** RealityKit e SceneKit.
* **Visão Computacional:** OpenCV (integrado via C++ Bridging Header) para processamento de imagem personalizado.
* **Segurança:** Encriptação de dados e conformidade com a LGPD/GDPR para proteção de dados de saúde.

---

## 5. Desafios de Engenharia e Soluções
* **Compensação de Movimento:** Filtros para lidar com a micro-movimentação da língua e respiração do paciente durante o scan.
* **Calibração de Lente:** Algoritmo para compensar as distorções ópticas específicas de cada modelo de iPhone (matriz intrínseca).
* **Gestão Térmica:** O processamento de fotogrametria é intensivo; o app deve gerir o uso do hardware para evitar o sobreaquecimento e a consequente perda de precisão do LiDAR.
* **Controle de Reflexos:** Requisito de uso de marcadores ArUco com acabamento fosco para garantir a leitura dos pontos de contraste sob a luz do consultório.