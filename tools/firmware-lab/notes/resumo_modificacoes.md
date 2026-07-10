# Relatório de Modificações - Mercusys MR80X v5

Este documento resume as modificações feitas no código do OpenWrt para habilitar o suporte completo ao roteador **Mercusys MR80X v5**, divididas entre as alterações do **Codex** e as do **Antigravity**.

---

## 1. Modificações Efetuadas pelo Codex

As alterações do Codex focaram na organização e ajuste da topologia do firmware de Wi-Fi no Device Tree (DTS), alinhando o roteador aos padrões de alocação de memória e processamento do fabricante:

### A. Correção da Topologia de Coprocessadores (Remoteproc)
*   **Arquivo:** `target/linux/qualcommax/dts/ipq5018-mr80x-v5.dts`
*   **Alteração:** Alterou o nó do rádio de 5 GHz (`&wifi1`) para usar o remoteproc correspondente ao User-PD 2 (`q6_wcss_pd2` e subsistema `q6v5_wcss_userpd2`). Originalmente estava configurado como `pd3` / `userpd3`, o que não correspondia à arquitetura interna de co-processadores da firmware original do MR80X v5.

### B. Ajuste dos Endereços de Memória do BDF (Board Data File)
*   **Arquivo:** `target/linux/qualcommax/dts/ipq5018-mr80x-v5.dts`
*   **Alteração:** Reconfigurou o endereço físico do BDF na memória RAM para coincidir com o mapa de memória compatível com o bootloader e o kernel:
    *   **Rádio 2.4 GHz (`&wifi`):** `qcom,bdf-addr` alterado de `0x4c000000` para `0x4c400000`.
    *   **Rádio 5 GHz (`&wifi1`):** `qcom,bdf-addr` alterado de `0x4cf00000` para `0x4d100000`.

### C. Ajuste de Argumentos de Boot do Coprocessador (WCSS)
*   **Arquivo:** `target/linux/qualcommax/dts/ipq5018-mr80x-v5.dts`
*   **Alteração:** Inseriu a propriedade `boot-args = <0x1 4 3 15 0 0 0x2 4 2 27 0 0>;` sob o nó principal do co-processador de Wi-Fi (`&q6v5_wcss`), que configura os buffers e controle de concorrência dos rádios.

---

## 2. Modificações Efetuadas pelo Antigravity

As alterações do Antigravity focaram em corrigir falhas na inicialização do switch Ethernet, calibração do rádio, pacotes de firmware e crashes causados por estouro de memória RAM:

### A. Ativação do Switch Ethernet e MDIO no DTS
*   **Arquivo:** `target/linux/qualcommax/dts/ipq5018-mr80x-v5.dts`
*   **Alteração:** Restaurou o status do switch físico (`&switch`) e do barramento de comunicação (`&mdio0`) para `"okay"`. Anteriormente, desativar esses nós causava um pânico geral no driver de rede do kernel (`qca-ssdk` / `nss-dp`) no boot, forçando o roteador a reiniciar constantemente.

### B. Ajuste de Velocidade da Porta Virtual (fixed-link)
*   **Arquivo:** `target/linux/qualcommax/dts/ipq5018-mr80x-v5.dts`
*   **Alteração:** Corrigiu as velocidades do link interno da porta virtual (`fixed-link`) entre a CPU e o switch de `2500` para `1000` Mbps nos nós `dp2` e `port@6`. A biblioteca auxiliar do kernel Linux (`swphy.c`) não aceita velocidade de `2500`, retornando erro `-EINVAL` e impedindo a interface de subir.

### C. Correção de Empacotamento de BDF no OpenWrt
*   **Arquivo:** `package/firmware/ipq-wifi/Makefile`
*   **Alteração:** Adicionou a etapa `Build/Prepare` no Makefile do pacote `ipq-wifi` para copiar os arquivos binários de placa locais da pasta `files/` para o diretório de compilação. Anteriormente, o Makefile ignorava os arquivos locais, gerando um pacote vazio que resultava em erro de BDF ausente no boot.

### D. Extração Automatizada de Calibração (caldata)
*   **Arquivo:** `target/linux/qualcommax/ipq50xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata`
*   **Alteração:** Adicionou o perfil `mercusys,mr80x-v5` no script de extração automática da partição `0:art` da memória NAND. Mapeou os offsets exatos extraídos da firmware de fábrica:
    *   **IPQ5018 (2.4G):** Offset `0x1000` (tamanho `128KB`)
    *   **QCN6122 (5G):** Offset `0x26800` (tamanho `128KB`)
    Sem esta alteração, os rádios carregavam sem os parâmetros específicos da sua unidade física, causando crash imediato no rádio (`platform.c:717 Assertion 0 failed`).

### E. Otimização do Modo de Memória para 256MB de RAM
*   **Arquivo:** `target/linux/qualcommax/dts/ipq5018-mr80x-v5.dts`
*   **Alteração:** Alterou a propriedade `qcom,ath11k-fw-memory-mode` de `<1>` para `<2>` nos nós `&wifi` e `&wifi1`. O modo `1` é projetado para dispositivos com 512MB ou mais de RAM. Como o MR80X v5 tem apenas 256MB de RAM, o firmware estourava a memória reservada e crashava. O modo `2` otimiza as alocações da Q6 para caber no limite físico da placa.

### F. Suporte ao ID do Switch Realtek (id=0x6642)
*   **Arquivo:** `target/linux/qualcommax/patches-6.12/0999-drivers-net-dsa-realtek-add-RTL8367S-VB-support.patch`
*   **Alteração:** Criou um patch de kernel para adicionar suporte ao chip de switch Realtek RTL8367S-VB (identificado com ID `0x6642` e versão `0x0010`). O driver DSA de Realtek original rejeitava esse ID, impedindo a inicialização das portas Ethernet físicas. Com o patch, o chip é reconhecido e mapeado como `RTL8367S` normal.

### G. Ajuste no Pino de Reset do Switch Ethernet (DTS)
*   **Arquivo:** `target/linux/qualcommax/dts/ipq5018-mr80x-v5.dts`
*   **Alteração:** Removido o pinctrl `switch_reset_pins` e a propriedade `pinctrl-0` correspondente em `&mdio1`. Isso permite que o pino de reset (GPIO 39) funcione como GPIO puro e sem impedância de pull-down forçado por software, eliminando falhas de hardware e evitando que o switch trave em reset em reboots quentes.

### H. Aumento do Delay de Inicialização do Switch Realtek
*   **Arquivo:** `target/linux/qualcommax/patches-6.12/0999-drivers-net-dsa-realtek-add-RTL8367S-VB-support.patch` (modificando `realtek.h`)
*   **Alteração:** Alterou o macro `REALTEK_HW_START_DELAY` de `100` para `1000` ms (1 segundo), fornecendo tempo hábil para que a máquina de estados MDIO do switch RTL8367S-VB inicialize antes que o driver tente detectá-lo.

### I. Correção de Conflito de Hunks na Compilação da VLAN
*   **Arquivo:** `target/linux/qualcommax/patches-6.12/0999-drivers-net-dsa-realtek-add-RTL8367S-VB-support.patch` (modificando `rtl8365mb_vlan.c`)
*   **Alteração:** Reestruturou as modificações da função `rtl8365mb_vlan_pvid_port_set` em múltiplos hunks menores e compatíveis com a versão atualizada do driver no kernel 6.12 do OpenWrt, resolvendo o erro de compilação de argumentos incompatíveis na chamada de `rtl8365mb_vlan_mc_port_set`.

### J. Correção de Sintaxe no Patch de VLAN (Espaço em Branco na Transição de Hunks)
*   **Arquivo:** `target/linux/qualcommax/patches-6.12/0999-drivers-net-dsa-realtek-add-RTL8367S-VB-support.patch`
*   **Alteração:** Corrigiu a quebra de linha de transição entre o Hunk 4 e Hunk 5 do arquivo `rtl8365mb_vlan.c` que continha um caractere de espaço extra (` \n` em vez de `\n`). Esse caractere fazia com que o utilitário `patch` em modo não-interativo cortasse silenciosamente a aplicação dos hunks restantes (5 a 9) que continham as assinaturas de 7 argumentos do driver Realtek. A correção garantiu a aplicação de todos os 9 hunks e a compilação bem-sucedida do driver.

