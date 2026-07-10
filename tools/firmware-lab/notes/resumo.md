# Resumo Técnico: Mercusys MR80X v5.0 (Qualcomm IPQ5018)

Este documento descreve as características de hardware, o layout de partição de memória flash e os requisitos para dar suporte ou compilar o OpenWrt para o roteador **Mercusys MR80X v5.0** (baseado no firmware oficial analisado).

---

## 1. Características do Hardware

* **Processador (SoC):** Qualcomm IPQ5018 (Dual-Core ARM Cortex-A7, 32-bit Little Endian).
* **Arquitetura:** `ARMv7` (MSB/LSB executável de 32 bits, ELF EABI5).
* **Memória RAM:** 256 MB DDR3 (identificado no arquivo CDT do cabeçalho: `DDR3_LM256`).
* **Memória Flash:** 128 MB SPI NAND.
* **Target do SDK da Fabricante:** `board_ipq50xx/generic` (baseado no OpenWrt Attitude Adjustment modificado pela fabricante).

---

## 2. Layout da Tabela de Partições (NAND Flash)
O firmware oficial utiliza um layout de **Dual-Boot / Dual-OS** (sistema redundante com partição ativa e passiva), controlado pela partição `BOOTCONFIG`.

A tabela física mapeada em `/etc/partition_config/partition-table` é a seguinte:

| ID | Nome da Partição | Endereço Base (Offset) | Tamanho (Size) | Descrição / Binário Associado |
|:---|:---|:---|:---|:---|
| **0** | `SBL1` | `0x00000000` | `0x00080000` (512 KB) | `sbl1_nand.mbn` (Qualcomm Secondary Bootloader) |
| **1** | `MIBIB` | `0x00080000` | `0x00080000` (512 KB) | `nand-system-partition-ipq5018.bin` (Tabela MTD Qualcomm) |
| **2** | `BOOTCONFIG` | `0x00100000` | `0x00040000` (256 KB) | Configuração do boot principal (Dual OS flag) |
| **3** | `BOOTCONFIG1` | `0x00140000` | `0x00040000` (256 KB) | Cópia redundante de segurança do BOOTCONFIG |
| **4** | `QSEE` | `0x00180000` | `0x00100000` (1 MB) | `tz.mbn` (Qualcomm TrustZone / Secure Execution Env) |
| **5** | `DEVCFG` | `0x00280000` | `0x00040000` (256 KB) | `devcfg.mbn` (Configuração de periféricos e clock) |
| **6** | `CDT` | `0x002c0000` | `0x00040000` (256 KB) | `cdt-AP-MP02.1_...` (Platform config / Calibração da RAM) |
| **7** | `APPSBLENV` | `0x00300000` | `0x00080000` (512 KB) | Variáveis de ambiente do U-Boot |
| **8** | `APPSBL` | `0x00380000` | `0x00140000` (1.25 MB) | `openwrt-ipq5018-u-boot.mbn` (Bootloader U-Boot principal) |
| **9** | `ART` | `0x004c0000` | `0x00100000` (1 MB) | **CRÍTICO:** Dados de calibração Wi-Fi de fábrica (EEPROM / MAC) |
| **10**| `TRAINING` | `0x005c0000` | `0x00080000` (512 KB) | Parâmetros de calibração dinâmica de memória RAM |
| **11**| `rootfs` | `0x00640000` | `0x02a00000` (42 MB) | **Sistema 1:** Imagem `root.ubi` (Kernel + OS Ativo) |
| **12**| `rootfs_1` | `0x03040000` | `0x02a00000` (42 MB) | **Sistema 2:** Cópia de segurança para rollback/atualizações |
| **13**| `tp_data` | `0x05a40000` | `0x00840000` (8.25 MB) | Dados permanentes de login e perfis TP-Link/Mercusys |

---

## 3. Requisitos para Compatibilidade com OpenWrt

Para que o roteador aceite e execute um binário gerado pelo OpenWrt compilado de forma limpa:

1. **Target de Compilação:** 
   O target correto na árvore moderna do OpenWrt é o `qualcommax/ipq50xx` (arquitetura ARM Cortex-A7). O chip é compatível com os drivers da Qualcomm de wireless `ath11k` (utilizado para os chips integrados QCN6102/QCN9074 ou similares presentes no SoC IPQ5018).

2. **Assinatura e Criptografia do Binário (O que o roteador exige):**
   * O firmware oficial é criptografado usando uma chave RSA-2048 proprietária e uma chave simétrica AES/DES.
   * Ao fazer o upload manual pela interface WEB, o bootloader ou o serviço de atualização valida os metadados do cabeçalho (`fw-type:Cloud`) e a assinatura.
   * **Se compilar um OpenWrt limpo:** A imagem final `.bin` precisará ser empacotada de forma idêntica (criptografada) usando o mesmo algoritmo ou o roteador irá rejeitar a imagem via Web GUI.
   * **Alternativa de Gravação (Bypass):** A melhor forma de flash inicial sem precisar criptografar/assinar é através do terminal serial (**UART**) via TFTP direto no U-Boot, ou se houver um exploit de shell local para gravar diretamente no bloco `/dev/mtd11` (`rootfs`).

3. **Preservação da Partição ART:**
   Ao reescrever o flash com OpenWrt, a partição **`ART` (ID 9)** no offset `0x004c0000` de 1MB **nunca deve ser sobrescrita**. Ela contém os calibradores de rádio de fábrica únicos do aparelho. Sem eles, o sinal Wi-Fi do OpenWrt será extremamente fraco ou nem funcionará.

---

## 4. Dispositivos Semelhantes na Árvore do OpenWrt

Para basear um novo Device Tree (DTS) na árvore do OpenWrt, os seguintes roteadores usam a mesma arquitetura de hardware (Qualcomm IPQ5018 / IPQ5000 / IPQ5010) e possuem suporte na árvore oficial:

* **Linksys SPNMX30 (MX5500):** Usa processador Qualcomm IPQ5018 com arquitetura de partições parecida.
* **Xiaomi AX3000 / Redmi AX3000:** Roteadores chineses populares baseados em IPQ5018/IPQ5000.
* **TP-Link Archer AX3000 / AX53 (v1/v2):** Praticamente a mesma plataforma de hardware da TP-Link que deu origem ao MR80X v5 da Mercusys.
