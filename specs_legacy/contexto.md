## 1. Visão Geral do Conceito
O projeto consiste no desenvolvimento de uma aplicação iOS para escaneamento intraoral que utiliza exclusivamente as câmeras do dispositivo (sem dependência de LiDAR). O sistema utiliza um marcador **ArUco 4x4** como referência física absoluta. Através da geometria conhecida do marcador, o software calibra a escala real do ambiente e determina a posição tridimensional exata (pose) do implante.

---

## 2. Arquitetura do Aplicativo

### A. Camada de Aquisição de Dados
* **Apple Object Capture API (Modo Fotogrametria):** Reconstrói a malha 3D a partir de uma sequência de fotos de alta resolução capturadas sob diferentes ângulos.
* **Referência de Escala via Software:** Como o sensor LiDAR não é utilizado, a escala 1:1 é definida matematicamente através da detecção do tamanho real (em milímetros) do marcador ArUco 4x4 inserido na cena.
* **AVFoundation (Focus Lock):** Bloqueio de foco macro para garantir nitidez máxima nas bordas do marcador ArUco, essencial para a precisão do algoritmo.

### B. Processamento e Inteligência Artificial
* **Detecção ArUco (OpenCV):** Localização dos quatro vértices do marcador em cada frame para triangulação de dados.
* **Pose Estimation (SolvePnP):** Uso do algoritmo *Perspective-n-Point* para resolver a orientação espacial (translação e rotação) do implante em relação à lente da câmera.
* **Alinhamento de Malha (Best-fit):** O software identifica a captura visual do marcador e a substitui pelo modelo CAD (.STL) perfeito da biblioteca. Isso elimina o ruído visual e garante que a conexão da prótese seja exata.

---

## 3. Fluxo do Utilizador (UX)
1.  **Registo do Caso:** Cadastro do paciente e definição das dimensões físicas do marcador ArUco utilizado (ex: 8.0mm).
2.  **Guião de Captura:** * O app guia o dentista em um movimento semicircular para capturar fotos de múltiplos ângulos.
    * Indicadores visuais confirmam quando o marcador ArUco foi "entendido" pelo software em diferentes perspectivas.
3.  **Processamento:** Reconstrução da malha 3D e alinhamento automático do eixo do implante com base no centro do marcador.
4.  **Exportação:** Geração e compartilhamento do arquivo `.STL` final para uso em softwares de design odontológico.

---

## 4. Requisitos de Sistema e Stack Sugerida
* **Linguagem:** Swift (Nativo).
* **Frameworks 3D:** RealityKit e SceneKit para visualização da malha gerada.
* **Visão Computacional:** OpenCV (via C++ Bridging Header) para detecção de marcadores e cálculo de pose.
* **Compatibilidade:** Funciona em qualquer iPhone moderno com suporte a iOS 17+, expandindo a base de usuários para além da linha Pro.

---

## 5. Desafios de Engenharia e Soluções
* **Precisão de Escala:** Sem LiDAR, o app depende totalmente da nitidez do marcador ArUco. Solução: Implementar um validador que impede a captura se a imagem estiver borrada.
* **Distorção de Lente:** Aplicação de matrizes de calibração intrínseca para corrigir o efeito "olho de peixe" comum em lentes grande-angulares de smartphones.
* **Compensação de Movimento:** Algoritmos de seleção de frames (Keyframes) para descartar fotos tremidas durante o processo de reconstrução 3D.
* **Gestão Térmica:** Otimização do processamento de imagem para evitar o aquecimento do dispositivo durante o uso clínico contínuo.