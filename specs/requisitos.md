## 1. Requisitos Funcionais (RF)

| ID | Requisito | Descrição |
| :--- | :--- | :--- |
| **RF-01** | **Detecção de Marcador** | O sistema deve identificar automaticamente o marcador ArUco 4x4 através da câmera em tempo real. |
| **RF-02** | **Cálculo de Escala** | O app deve utilizar a dimensão física pré-definida do ArUco para calibrar a escala real (1:1) do modelo 3D. |
| **RF-03** | **Captura Guiada** | O app deve orientar o usuário (via interface visual) a capturar todos os ângulos necessários (oclusal, lateral e cervical). |
| **RF-04** | **Reconstrução 3D** | O sistema deve processar a sequência de imagens para gerar uma malha (mesh) tridimensional da arcada dentária. |
| **RF-05** | **Alinhamento CAD** | O app deve alinhar um modelo digital perfeito (STL) do pilar sobre a posição detectada do marcador ArUco. |
| **RF-06** | **Exportação de Ficheiros** | O sistema deve permitir a exportação do modelo final no formato .STL |
| **RF-07** | **Gestão de Casos** | O app deve permitir criar, salvar e editar perfis de pacientes e seus respectivos escaneamentos. |

---

## 2. Requisitos Não Funcionais (RNF)

### A. Precisão e Performance
* **RNF-01 (Acurácia):** O erro linear no posicionamento do implante não deve exceder 50-100 micra para garantir o ajuste protético.
* **RNF-02 (Latência):** A detecção do marcador ArUco na interface de câmera deve ocorrer a uma taxa mínima de 30 FPS.
* **RNF-03 (Processamento):** A reconstrução 3D final (alta resolução) não deve levar mais de 5 minutos em dispositivos iPhone modernos.

### B. Usabilidade e Hardware
* **RNF-04 (Compatibilidade):** O app deve ser compatível com iPhones rodando iOS 17 ou superior.
* **RNF-05 (Interface):** A interface deve ser profissional e com credibilidade, considerando que o dentista estará em ambiente clínico.

---

## 3. Requisitos de Hardware (Setup Clínico)
1.  **Dispositivo:** iPhone com sistema de câmera dupla ou tripla (para foco estável em curtas distâncias).
2.  **Marcador Físico:** ArUco 4x4 impresso em material rígido, autoclavável e com acabamento **mate** (antirreflexo).
3.  **Iluminação:** O app deve exigir uma iluminação mínima de 500 lux (luz do refletor odontológico padrão) para evitar ruído digital nas fotos.

---

## 4. Restrições de Design
* O app não utilizará o sensor LiDAR para garantir maior compatibilidade entre modelos de iPhone.
* Todo o cálculo de profundidade será derivado da visão computacional estereoscópica ou por estrutura de movimento (SfM).