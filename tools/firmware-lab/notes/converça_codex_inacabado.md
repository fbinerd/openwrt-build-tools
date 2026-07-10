# MR80X v5 - estado da investigacao Ethernet/OpenWrt

Data desta rodada: 2026-07-08.

## Nota de recovery web OEM

Em 2026-07-09 foi analisado o firmware OEM BR/EU e o APPSBL/U-Boot extraido.
A interface web de recovery do Mercusys nao aceita uma UBI crua: ela chama
`nm_upgradeFirmware`, recebe upload HTTP `multipart/form-data` no campo
`firmware`, checa `support-list`, valida assinatura `RSA2048 PSS` e so entao
grava o conteudo UBI. A imagem OEM tem `fw-type:Cloud` em `0x14`, marcador
RSA-2048 em `0x110`, assinatura RSA-PSS de 256 bytes em `0x130`, `support-list`
em `0x1014`, `soft-version` em `0x12a0` e a primeira UBI em `0x131c`.

O aparelho BR extraido tem `product_name:MR80X`, `product_ver:5.0.0` e
`special_id:42520000`, entrada presente no `support-list` do firmware OEM.
As imagens OpenWrt atuais (`initramfs.itb`, `factory.ubi`, `sysupgrade.bin`)
nao possuem esse envelope/assinatura, entao nao devem ser aceitas pela web OEM.
Detalhes completos: `analis/recovery_mr80x_v5.md`.

## Objetivo imediato

Foco atual: fazer as portas Ethernet do Mercusys MR80X v5 passarem trafego/DHCP no OpenWrt. O hardware sobe link fisico no RTL8367S-VB, mas os testes anteriores mostravam link up sem receber IP.

Ultimo log recebido nesta rodada ainda mostrou a mesma falha funcional: o link fisico da LAN sobe, a porta entra em `br-lan`, mas nao passa DHCP/ping. Como o caminho fisico e a bridge aparecem vivos, a hipotese principal deixou de ser mapeamento basico de portas e passou a ser o caminho de tag CPU/DSA entre o RTL8367S-VB e o `dp2`.

## Achados no firmware original extraido

- A particao correta para o MAC base nao e `0:art` no offset 0.
- O MAC base foi localizado em `tp_data`, dentro do volume UBI `tp_data`, arquivo `default-mac`.
- Caminho extraido usado na analise:
  `/home/fabiano/opw/analis/ubi_tpdata_extract/777166689/tp_data/default-mac`
- Conteudo do arquivo: bytes `08 8a f1 02 d6 88`.
- MAC base do aparelho analisado: `08:8a:f1:02:d6:88`.
- A particao `OpenWrt.mtd9.0-art.bin` comeca com `ff`, entao a celula antiga de MAC em `art@0` era invalida para Ethernet.

## Switch/portas

O switch externo e Realtek RTL8367S-VB. O CPU port usado no DTS/OpenWrt ficou como `port@6` em SGMII, ligado ao `dp2`.

Ha uma contradicao no material OEM:

- o script OEM `/lib/switch/core_phy.sh` cita `LAN_PORTS="1 2 3 4"` e `WAN_PORTS="0"`;
- mas o MR80X v5 fisico informado tem apenas `LAN1`, `LAN2`, `LAN3` e `WAN`;
- o bloco OEM `qcom,port_phyinfo` tambem aponta para uma configuracao mais curta, coerente com tratar o aparelho como 3 LAN + WAN.

Decisao aplicada agora: expor no OpenWrt somente `wan`, `lan1`, `lan2`, `lan3`. A porta `lan4` foi removida do DTS e do caso MR80X em `02_network`.

Rodada seguinte, depois do log `e6e3e496` ainda sem DHCP/ping: o FDT OEM extraido mostrou que a WAN nao e uma porta do switch externo Realtek. O vendor usa:

- `dp1`/GMAC0 em `mdio@88000`, PHY address `7`, como caminho Ethernet separado;
- switch externo em `mdio@90000` com CPU bitmap `0x40`;
- `switch_lan_bmp = <0x1e>` no switch externo, ou seja, portas 1..4 como LAN no firmware OEM;
- `switch_wan_bmp = <0x00>` no switch externo.

Nova decisao aplicada: `dp1` virou `wan`; o RTL8367S-VB fica apenas para LANs.

Mapeamento atual no DTS para esta imagem:

- `port@1`: `lan3`, `rtl8367s_phy1`
- `port@2`: `lan2`, `rtl8367s_phy2`
- `port@3`: `lan1`, `rtl8367s_phy3`
- `port@6`: CPU/SGMII, `ethernet = <&dp2>`, fixed-link 1 Gbps full duplex com pause
- `dp1`: `status = "okay"`, `label = "wan"`, PHY interno/GE em `mdio0` address 7 via `ipq5018-ess.dtsi`

## Alteracoes aplicadas

Arquivos principais:

- `openwrt/target/linux/qualcommax/dts/ipq5018-mr80x-v5.dts`
  - removeu `lan4`/`phy4`;
  - removeu `wan` do switch Realtek;
  - habilitou `dp1` como `wan`;
  - mudou `label-mac-device` para `dp1`;
  - manteve CPU em `port@6` SGMII;
  - removeu a referencia de MAC via `nvmem` em `0:art`, pois o local era invalido;
  - ajustou pinos UART RX/TX para tentar corrigir console que recebe comandos no U-Boot mas nao no OpenWrt.

- `openwrt/target/linux/qualcommax/ipq50xx/base-files/etc/board.d/02_network`
  - caso `mercusys,mr80x-v5` agora usa:
    `ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan"`;
  - explicita conduits: `lan1/lan2/lan3` em `eth1`, `wan` em `eth0`;
  - MAC de LAN/WAN vem de `/tmp/tp_data/default-mac`;
  - LAN usa o MAC base, WAN usa MAC base + 1.

- `openwrt/target/linux/qualcommax/ipq50xx/base-files/lib/preinit/09_mount_tp_data`
  - monta a particao `tp_data` como UBIFS em `/tmp/tp_data`.

- `openwrt/target/linux/qualcommax/ipq50xx/base-files/lib/preinit/10_fix_eth_mac`
  - aplica MAC no preinit usando `/tmp/tp_data/default-mac`;
  - `eth0` recebe MAC base + 1 para WAN;
  - `eth1` recebe MAC base para o conduit LAN/Realtek, quando existir.

- `openwrt/target/linux/qualcommax/patches-6.12/0999-drivers-net-dsa-realtek-add-RTL8367S-VB-support.patch`
  - adiciona suporte ao RTL8367S-VB;
  - adiciona configuracao SGMII/HSGMII/2.5G usada pelo driver Realtek;
  - na rodada atual, nao forca mais `RTL8365MB_CPU_POS_BEFORE_CRC`;
  - o driver preparado ficou com o padrao upstream `RTL8365MB_CPU_POS_AFTER_SA`, fazendo o DSA usar `rtl8_4` em vez de tag de cauda `rtl8_4t`;
  - corrige caminho de VLAN/PVID para reaproveitar o indice de VLAN MC alocado.

- `openwrt/package/kernel/qca-ssdk/patches/010-ignore-unmapped-netdev-change-events.patch`
  - patch local para ignorar eventos de netdev nao mapeados.

- `openwrt/target/linux/qualcommax/image/ipq50xx.mk`
  - adicionou `luci`, `uboot-envtools` e `zram-swap` aos pacotes do perfil MR80X v5.

- `openwrt/package/boot/uboot-tools/uboot-envtools/files/qualcommax_ipq50xx`
  - adicionou caso especifico do MR80X v5 aceitando tanto `0:appsblenv` quanto `0:APPSBLENV`;
  - isto cobre a variacao de nome entre logs/SMEM e ferramentas OEM.

- `openwrt/target/linux/qualcommax/ipq50xx/base-files/lib/upgrade/platform.sh`
  - a primeira rotina TP-Link A/B para o MR80X v5 foi removida depois de teste real;
  - no U-Boot deste aparelho, `tp_boot_idx=1` faz o `bootipq` entrar no caminho `Find boot alter flag!` e em seguida dar `data abort`;
  - o `fw_setenv` tambem gerou um ambiente persistente com `bootcmd=run distro_bootcmd`, mas este U-Boot nao define `distro_bootcmd`;
  - decisao corrigida: `sysupgrade` grava somente no slot primario `rootfs` e nao altera mais `tp_boot_idx`/ambiente U-Boot.

- `openwrt/files/etc/uci-defaults/99_enable-wireless-mr80x-v5`
  - overlay local, nao e parte normal do target;
  - gera `/etc/config/wireless` se necessario e habilita radio/iface por padrao.

- `openwrt/files/etc/uci-defaults/98_mr80x-v5-zram`
  - overlay local para zram de teste;
  - zram usa RAM comprimida, nao usa a SPI/NAND como swap.

## Particoes, boot e sysupgrade

O DTS do MR80X v5 nao contem uma tabela fixa completa de particoes. Ele usa:

```dts
compatible = "qcom,smem-part";
```

Com isso, o Linux/OpenWrt descobre os nomes e offsets reais via SMEM/MIBIB em tempo de boot. Portanto, para o `sysupgrade`, o ponto critico nao e uma tabela fixa no DTS, e sim os nomes MTD vistos em `/proc/mtd`.

Particoes confirmadas nos logs e no firmware OEM extraido:

```text
0:appsblenv / APPSBLENV  offset 0x00300000  size 0x00080000
rootfs                  offset 0x00640000  size 0x02a00000
rootfs_1                offset 0x03040000  size 0x02a00000
```

No firmware original, `/etc/partition_config/partition-table` confirma:

```text
7=APPSBLENV, 0x00300000, 0x00080000
11=rootfs,   0x00640000, 0x02a00000, root.ubi
12=rootfs_1, 0x03040000, 0x02a00000
```

O U-Boot/APPSBL extraido em `analis/fw_extracted/OpenWrt.mtd8.0-appsbl.bin` tambem confirma o modelo A/B:

- `bootcmd=bootipq`;
- `bootargs=console=ttyMSM0,115200n8`;
- `tp_boot_idx`;
- `ubi.mtd=rootfs root=mtd:ubi_rootfs rootfstype=squashfs`;
- `ubi.mtd=rootfs_1 root=mtd:ubi_rootfs rootfstype=squashfs`;
- `rootfsname=rootfs` e `rootfsname=rootfs_1`;
- `ubi part fs && ubi read ... kernel`;
- strings de update com `Setting boot idx: %d`.

Os dumps `OpenWrt.mtd2.0-bootconfig.bin` e `OpenWrt.mtd3.0-bootconfig1.bin` contem magic `a0 a1 a2 a3`, versao 1, 8 entradas, e selecionam `rootfs` no estado extraido:

```text
0:QSEE
0:DEVCFG
0:CDT
0:APPSBL
0:HLOS
rootfs
0:WIFIFW
0:BTFW
```

Conclusao corrigida apos tentativa real de `sysupgrade`: apesar de o firmware OEM ter particoes `rootfs` e `rootfs_1`, a troca via `tp_boot_idx` nao e segura neste MR80X v5. O aparelho deve gravar o OpenWrt em `rootfs`, que e o caminho que o `bootipq` inicia corretamente quando `tp_boot_idx=0`. A particao `rootfs_1` fica fora do caminho de upgrade por enquanto, ate entendermos o mecanismo TP-Link completo que evita o `data abort`.

Recuperacao observada no U-Boot depois da quebra:

```text
setenv tp_boot_idx 0
setenv bootcmd bootipq
bootipq
```

Esses comandos, sem `saveenv`, foram suficientes para iniciar o firmware OEM em `rootfs`. Para tornar a recuperacao persistente seria possivel salvar o ambiente, mas isso deve ser feito com cuidado porque a tentativa anterior mostrou que alterar APPSBLENV pode deixar `bootcmd` em um padrao generico incorreto.

Comandos uteis no aparelho para confirmar:

```sh
cat /proc/mtd
cat /proc/cmdline
cat /etc/fw_env.config
fw_printenv tp_boot_idx
ubiinfo -a
```

## Validacao feita

Build usado:

```sh
docker run --rm \
  -v /home/fabiano/opw/openwrt-build-tools:/home/developer/project \
  -v /home/fabiano/opw/openwrt:/home/developer/openwrt \
  -v /home/fabiano/opw/openwrt-build-tools/dl:/home/developer/dl_cache \
  -e OPENWRT_DIR=/home/developer/openwrt \
  -e DL_CACHE_DIR=/home/developer/dl_cache \
  -w /home/developer/openwrt \
  openwrt-openwrt-25.12-builder \
  make -j$(nproc) package/install target/linux/install V=s
```

Resultado: build concluido.

Build mais recente desta rodada: concluido em 2026-07-08 15:38.

DTB gerado foi decompilado e conferido:

- `dp1` existe com `label = "wan"` e `phy-mode = "internal"`;
- no switch Realtek existem `lan3`, `lan2`, `lan1`;
- existe CPU `port@6`;
- nao existe `port@0` no switch RTL8367S;
- nao existe `port@4` no switch RTL8367S;
- nao existe `ethernet-phy@0`;
- nao existe `ethernet-phy@4`;
- a referencia invalida de MAC em `art@0` nao aparece mais no `dp2`.
- `uart0-state` ficou com `gpio20` e `gpio21`, funcao `blsp0_uart0`, `drive-strength = <8>` e `bias-disable`.

Kernel preparado conferido:

- `rtl8365mb_get_tag_protocol()` retorna `DSA_TAG_PROTO_RTL8_4` quando a CPU tag esta em `RTL8365MB_CPU_POS_AFTER_SA`;
- `rtl8365mb_detect()` inicializa `mb->cpu.position = RTL8365MB_CPU_POS_AFTER_SA`;
- o patch local nao contem mais hunk forcando `RTL8365MB_CPU_POS_BEFORE_CRC` para o RTL8367S-VB.

Rootfs conferido:

- `/etc/uci-defaults/98_mr80x-v5-zram`
- `/etc/uci-defaults/99_enable-wireless-mr80x-v5`
- `/lib/preinit/09_mount_tp_data`
- `/lib/preinit/10_fix_eth_mac` com `eth0 = MAC+1` e `eth1 = MAC base`
- `02_network` tem o caso MR80X com apenas `lan1 lan2 lan3`, `wan`, conduits `eth1` para LAN e `eth0` para WAN.

Manifesto confirmou:

- `ipq-wifi-mercusys_mr80x-v5`
- `kmod-dsa-rtl8365mb`
- `luci`
- `uboot-envtools`
- `zram-swap`

Rootfs extraido de `root.squashfs` confirmou:

- `/lib/upgrade/platform.sh` contem `tplink_get_boot_part()` e `tplink_do_upgrade()`;
- caso `mercusys,mr80x-v5` chama `tplink_do_upgrade`;
- `/etc/uci-defaults/30_uboot-envtools` contem fallback `0:appsblenv` e `0:APPSBLENV`;
- `/etc/init.d/uhttpd` esta presente;
- `/etc/uci-defaults/99_enable-wireless-mr80x-v5` gera wireless se necessario e seta `disabled=0`.

## Imagens geradas

Diretorio:

`/home/fabiano/opw/openwrt/bin/targets/qualcommax/ipq50xx/`

Hashes finais:

```text
934235606a670460aa62b49217eb9a869475829bb1e9e19f50ce459c906053f9  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-initramfs-uImage.itb
111a0c7e30ecd6b3a8b1f5c77a7be819e3e547944cec825196dfd6fa62e1f68f  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-squashfs-factory.ubi
697a96102312cdd6d119a2b046057789099d352fc3b739cc4d8005262c942ed8  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-squashfs-sysupgrade.bin
b5280e46d545cedbd2a8d75fcb81c51e6f8b5d1f3567b24281afda2d7fcce7eb  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5.manifest
```

## O que observar no proximo boot/teste

No log serial, esperar:

- interface `wan` como `eth0`/`dp1`;
- interfaces DSA apenas `lan1`, `lan2`, `lan3` no Realtek;
- conduit DSA do Realtek como `eth1`;
- nenhum `lan4`;
- `br-lan` com `lan1 lan2 lan3`;
- `/tmp/tp_data/default-mac` montado;
- `eth0`/WAN com MAC `08:8a:f1:02:d6:89`;
- `eth1`/LAN conduit com MAC `08:8a:f1:02:d6:88`;
- LuCI instalado;
- Wi-Fi habilitado por padrao, se o ath11k/board file completar a inicializacao.

Comandos uteis via serial:

```sh
cat /tmp/tp_data/default-mac | hexdump -C
ip -br link
bridge link
cat /etc/config/network
logread | grep -Ei 'rtl836|dsa|dnsmasq|dhcp|nss-dp|GMAC|tp_data|netifd'
```

Se ainda houver link up sem DHCP/IP nas LANs, a suspeita principal fica no caminho de tag CPU/DSA do RTL8367S-VB ou em alguma programacao VLAN/PVID que ainda nao corresponde ao que o switch OEM faz. Se a WAN passar a aparecer como `eth0` e subir link no conector WAN, a leitura do FDT OEM foi confirmada.

No proximo teste, a diferenca essencial desta imagem e: WAN em `dp1/eth0`, Realtek apenas LAN em `dp2/eth1`, Realtek em `rtl8_4`/`AFTER_SA` e UART com pinctrl simplificado. Se o UART passar a aceitar entrada, coletar tambem `tcpdump -ni br-lan -e 'arp or port 67 or port 68'` enquanto um cliente tenta DHCP em uma LAN.

## Rodada seguinte: correcao real dos nomes netdev e HSGMII

Data: 2026-07-08.

O log mais recente mostrou que a conclusao anterior sobre os nomes das interfaces estava invertida:

- `dp1` aparece como netdev `wan`;
- `dp2` aparece como netdev `eth0` e e o master DSA do RTL8367S-VB;
- portanto LAN DSA deve usar conduit `eth0`, e WAN deve usar conduit/netdev `wan`.

Mudancas aplicadas:

- `02_network`: MR80X v5 agora tem apenas `lan1 lan2 lan3` e `wan`; conduits `lan1/lan2/lan3 -> eth0`, `wan -> wan`;
- `10_fix_eth_mac`: agora configura MAC base em `eth0` e MAC+1 em `wan`;
- DTS: `dp2` e o CPU `port@6` do RTL8367S-VB passaram de `sgmii`/1000 para `2500base-x`/2500;
- DTS: `qcom,port_phyinfo port@2` passou para `forced-speed = <2500>`, igual ao FDT OEM (`0x9c4`);
- patch Realtek: adicionada sequencia de registradores HSGMII usada pelo driver vendor para MAC6/EXT0;
- patch Realtek: quando phylink pede `SPEED_2500`, o force-link do RTL8367S usa o encoding `RTL8365MB_PORT_SPEED_1000M`, seguindo o API vendor Realtek para HSGMII.

Referencia OEM usada:

- `fdt_mp02.1.dts`: `dp2 phy-mode = "sgmii"` mas `ess-switch port@1/port_id 2` tem `forced-speed = <0x9c4>` (2500);
- driver vendor Realtek em `target/linux/mediatek/files/drivers/net/phy/rtk/rtl8367s_mdio.c`: `set_rtl8367s_sgmii()` usa `MODE_EXT_HSGMII`, `PORT_SPEED_2500M`, force link up e desliga nway;
- API Realtek vendor em `rtl8367c/port.c`: para `MODE_EXT_HSGMII`, valida `PORT_SPEED_2500M`, mas grava `ability.speed = PORT_SPEED_1000M`.

Build Docker executado com limpeza de kernel e base-files:

```sh
docker run --rm -u "$(id -u):$(id -g)" \
  -v /home/fabiano/opw/openwrt-build-tools:/home/developer/project \
  -v /home/fabiano/opw/openwrt:/home/developer/openwrt \
  -v /home/fabiano/opw/openwrt-build-tools/dl:/home/developer/dl_cache \
  -e DL_CACHE_DIR=/home/developer/dl_cache \
  -e OPENWRT_DIR=/home/developer/openwrt \
  -w /home/developer/openwrt \
  openwrt-openwrt-25.12-builder \
  make -j$(nproc) target/linux/clean package/base-files/clean target/linux/compile package/base-files/compile package/install target/linux/install V=s
```

Resultado: build concluido.

Validacao do DTB final:

- `port@6` Realtek: `phy-mode = "2500base-x"` e `speed = <0x9c4>`;
- `dp2`: `phy-mode = "2500base-x"` e fixed-link `speed = <0x9c4>`;
- `qcom,port_phyinfo port_id 2`: `forced-speed = <0x9c4>`;
- `dp1`: `phy-mode = "internal"` e `label = "wan"`;
- switch Realtek segue apenas com `lan3`, `lan2`, `lan1`.

Validacao do rootfs final:

- `/etc/board.d/02_network`: `lan1/lan2/lan3 -> eth0`, `wan -> wan`;
- `/lib/preinit/10_fix_eth_mac`: `eth0 = MAC base`, `wan = MAC+1`;
- Manifesto inclui `luci`, `kmod-dsa-rtl8365mb`, `ipq-wifi-mercusys_mr80x-v5`, `uboot-envtools` e `zram-swap`.

FIT novo para teste TFTP:

```text
kernel crc32 03bddb35
kernel sha1  fff1cedc44d0087e47fae46f9901a8cb6a07d376
initramfs kernel crc32 8bbc6ba6
initramfs kernel sha1  a3dc5b0ad725d442648c051a30e0417427c6a434
fdt crc32 0216cf6a
fdt sha1  613d3e6937e3742cbbbb660f1194698cd5289106
```

Hashes das imagens geradas:

```text
f618a6bc43247edb03ef9be5f75cd30f4e41176b4a3df2a547154d0ec7f0abda  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-initramfs-uImage.itb
31f8451601c48b3fddcc5cf7efd8733fd6eaf4aed2544f9c8bcb822e6d8106ab  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-squashfs-factory.ubi
714143144ecfeb683f872cc879b5c1f5e791bc39062e2ae08bff8be57fcb07f2  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-squashfs-sysupgrade.bin
```

O que observar no proximo log:

- `dp2`/`eth0` deve subir como master DSA em 2.5G ou pelo menos sem erro de `unsupported port speed`;
- `lan1`, `lan2`, `lan3` devem entrar no `br-lan`;
- DHCP em LAN deve aparecer saindo de `br-lan`;
- se ainda nao passar DHCP, proxima suspeita e tag CPU/VLAN/PVID no RTL8367S-VB, nao mais nome errado de netdev.
## 2026-07-08 - Build apos log_openwrtatual: corrigido dp2 fixed-link 2500

Log analisado: `/home/fabiano/opw/analis/logs/log_openwrtatual.log`.

Diagnostico principal do log atual:

- O kernel recebido ainda estava com `dp2` em fixed-link 2500.
- Isso quebrou antes do DSA subir:
  - `swphy: unknown speed`
  - `dp2: fail to register fixed-link: -22`
  - `nss-dp 39d00000.dp2: probe with driver nss-dp failed with error -14`
  - `rtl8365mb-mdio ... deferred probe pending: ... unable to register switch`
- Com o `dp2` fora, o Realtek ate era detectado, mas nao registrava a arvore DSA. Por isso o `br-lan` ficou so com Wi-Fi e sem `lan1/lan2/lan3`, entao DHCP/IP por cabo nao tinha caminho.

Comparacao com firmware original:

- U-Boot usa `serial@78AF000` e `bootargs=console=ttyMSM0,115200n8`.
- Log original e log OpenWrt usam o mesmo UART:
  - `78af000.serial: ttyMSM0 ... is a MSM`
  - `console [ttyMSM0] enabled`
- O original cria LAN como `eth1.2`, `eth1.3`, `eth1.4`, `eth1.5` em `br-lan`.
- No OpenWrt/DSA o equivalente esperado e `dp2` como master/conduit do switch Realtek; sem `dp2`, nenhuma porta DSA consegue passar DHCP.

Alteracoes feitas nesta rodada:

- `target/linux/qualcommax/dts/ipq5018-mr80x-v5.dts`
  - `dp2` voltou para `phy-mode = "sgmii"` e `fixed-link speed = <1000>`.
  - CPU port `port@6` do RTL8367S-VB tambem voltou para `phy-mode = "sgmii"` e `fixed-link speed = <1000>`.
  - Mantido `qcom,port_phyinfo/port@2 forced-speed = <2500>`, porque o FDT OEM tem `forced-speed = <0x9c4>` nessa parte do ESS.
  - DTS mantem apenas `lan1`, `lan2`, `lan3` no Realtek; a WAN fica em `dp1` separado.
- `target/linux/qualcommax/patches-6.12/0999-drivers-net-dsa-realtek-add-RTL8367S-VB-support.patch`
  - Para `PHY_INTERFACE_MODE_SGMII`, o driver Realtek agora aplica sequencia HSGMII no `port == 6`.
  - A intencao e manter o fixed-link aceitavel para `nss-dp`/fixed PHY, mas configurar o RTL8367S-VB como o firmware vendor faz.

Validacao do build:

- Build Docker concluido com sucesso usando `openwrt-openwrt-25.12-builder`.
- FIT normal:
  - kernel crc32: `e7741dd6`
  - kernel sha1: `4c59ba199c8abb362e6a4b30bad2950e0e75a3c7`
  - fdt crc32: `c16e8da9`
  - fdt sha1: `411911bc651d1674af52834274c6a5276ef6cf2c`
- FIT initramfs:
  - kernel crc32: `d6423a1e`
  - kernel sha1: `0de7d91d04ea5967609d0f2959a05da3eb0e357f`
  - fdt crc32: `c16e8da9`
  - fdt sha1: `411911bc651d1674af52834274c6a5276ef6cf2c`
- Hashes dos artefatos:
  - `cde94403981481c79d9e197f3ae1bfe7237bc06b70612a9380ffded05429174d  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-initramfs-uImage.itb`
  - `18605acc7a65179a440f0379641da1e5b221d1082b80f7d2dc594a0dc1ff17e9  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-squashfs-factory.ubi`
  - `181cacd8e8a79363f7f3e65cb22f842dd927d2b386c097125154dc95c1ed123c  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-squashfs-sysupgrade.bin`

DTB final conferido:

- `port@6`: `phy-mode = "sgmii"` e `speed = <0x3e8>`.
- `dp2`: `phy-mode = "sgmii"` e `speed = <0x3e8>`.
- `qcom,port_phyinfo/port@2`: `forced-speed = <0x9c4>`.
- UART final: `serial0 = "/soc@0/serial@78af000"` e `stdout-path = "serial0:115200n8"`.

O que procurar no proximo log:

- Nao deve aparecer mais `swphy: unknown speed`.
- Nao deve aparecer mais `dp2: fail to register fixed-link`.
- Deve aparecer `nss-dp 39d00000.dp2` registrando um netdev, provavelmente `eth0`.
- O Realtek deve sair de `deferred probe pending` e registrar a arvore DSA.
- `br-lan` deve receber `lan1`, `lan2`, `lan3`. Se isso acontecer e ainda nao houver DHCP, a proxima camada a depurar e CPU tag/VLAN/PVID dentro do RTL8367S-VB.

Nota UART:

- O log atual mostra `Please press Enter to activate this console.` e o rootfs contem `::askconsole:/usr/libexec/login.sh`.
- Isso sugere que o console foi criado. Se o teclado nao responde, o problema ainda pode estar no RX/pinmux ou no adaptador/terminal, mas a rota do kernel (`ttyMSM0` em `78af000`) bate com o U-Boot e com o firmware original.
- Para a imagem de teste do OpenWrt, foi adicionado um override de `login.sh` em `target/linux/qualcommax/ipq50xx/base-files/usr/libexec/login.sh` para cair direto em `ash --login` na serial. Isso remove o bloqueio do wrapper antigo e deixa o console funcional para depuracao.

## 2026-07-08 - Ajuste LAN VLAN 2 a partir da engenharia reversa OEM

Motivo da nova suspeita:

- O log OpenWrt atual ja mostra `dp2`, DSA, Realtek e link fisico funcionando.
- Mesmo assim nao passa IP/DHCP por cabo.
- Isso aponta para configuracao L2/VLAN/PVID do switch, nao mais para falha eletrica ou probe do driver.

Pistas confirmadas no firmware original extraido:

- Arquivo OEM:
  `/home/fabiano/opw/analis/extracted/_MR80X_v5_br-up-eu-ver1-3-1-P1[20251226-rel65216]-2048_nosign_2025-12-29_10.01.08.bin.dec.extracted/squashfs-root/lib/network/network_arch.sh`
- Valores importantes:
  - `LAN_PORT_SET="1 2 3 4"`
  - `LAN_PORT_DEVSET="eth1.2 eth1.2 eth1.2 eth1.2"`
  - `WAN_PORT_DEVSET="eth1.4094"`
  - `CPU1_PHY_PORT_SET="16"`
  - `CPU2_PHY_PORT_SET="16"`
  - `WAN_DEFUALT_VID="4094"`
  - `LAN_DEFUALT_VID="2 3 4 5"`
- A funcao OEM `switch_set_default` pega somente o primeiro VID de LAN (`2`) e coloca todas as portas LAN nesse VID, com porta fisica untagged e CPU tagged.
- Log OEM tambem confirma:
  - `WAN_PHY_IF=eth1.4094`
  - `LAN_PHY_IF=eth1.2`
  - `vid=4094 memberMask=65537 untaggedMask=1`
  - `vid=2 memberMask=65538 untaggedMask=2`

Alteracao aplicada no OpenWrt:

- Criado:
  `target/linux/qualcommax/ipq50xx/base-files/etc/uci-defaults/98_mr80x-v5-lan-vlan`
- O script roda apenas em `mercusys,mr80x-v5`.
- Ele muda a LAN para `br-lan.2`.
- Ele cria um `bridge-vlan` no `br-lan`:
  - VLAN `2`
  - `lan1:u*`
  - `lan2:u*`
  - `lan3:u*`
- A ideia e reproduzir em DSA o padrao do OEM: portas fisicas LAN untagged/PVID na VLAN 2 e CPU/master tagged automaticamente pelo bridge VLAN filtering.

Validacao:

- Build Docker concluido com sucesso usando `openwrt-openwrt-25.12-builder`.
- O arquivo entrou no rootfs final:
  `build_dir/target-aarch64_cortex-a53_musl/root-qualcommax/etc/uci-defaults/98_mr80x-v5-lan-vlan`
- FIT initramfs novo:
  - kernel crc32: `e42b7924`
  - kernel sha1: `cf3294e0591668f323552540767c0fa7f3cfb0ca`
  - fdt crc32: `c16e8da9`
  - fdt sha1: `411911bc651d1674af52834274c6a5276ef6cf2c`
- Hashes dos artefatos:
  - `cf9dca17e6ef2b94545cc6ebdcf7e0428f9d421ca773771250edbcbe5a324101  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-initramfs-uImage.itb`
  - `37fb582386c0441df742c85d97037e4c804a62882fcce46c63dd4b4d05d7036e  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-squashfs-factory.ubi`
  - `0265d573f0f9242921f4709bce252fee9473c82017748606f64528237c939fd2  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-squashfs-sysupgrade.bin`

O que observar no proximo teste:

- Se DHCP funcionar, a causa era VLAN/PVID/CPU tagged ausente no DSA.
- Se o link continuar subindo mas sem DHCP, o proximo alvo e o driver Realtek: pode faltar uma configuracao especifica de CPU port/member mask equivalente ao bit `16` usado pelo driver OEM (`/proc/driver/rtl8367s/vlan`).
- Se o log nao mostrar `br-lan.2`/VLAN sendo aplicada, o ajuste deve sair de `uci-defaults` e ir para geracao direta em `board.d/02_network`.

## 2026-07-08 - Ajuste UART RX comparando com FDT OEM

Sintoma:

- U-Boot recebe teclado normalmente.
- OpenWrt imprime logs no UART, mostra `Please press Enter to activate this console.`, mas nao recebe entrada.

Comparacao dos logs:

- Firmware original:
  - U-Boot: `In/Out/Err: serial@78AF000`
  - Linux: `78af000.serial: ttyMSM0 ... is a MSM`
  - Console: `console [ttyMSM0] enabled`
- OpenWrt atual:
  - Kernel cmdline: `console=ttyMSM0,115200n8`
  - Linux: `78af000.serial: ttyMSM0 ... is a MSM`
  - Console: `legacy console [ttyMSM0] enabled`

Conclusao:

- O controlador UART esta correto: `serial@78af000` / `ttyMSM0`.
- A diferenca suspeita estava no pinctrl do DTS OpenWrt.

Comparacao com FDT OEM extraido:

- No FDT OEM, o no `serial@78af000` aparece como `status = "ok"` e nao tem `pinctrl-0`.
- No DTS OpenWrt, eu estava forcando:
  - `pinctrl-0 = <&serial_0_pins>;`
  - `serial_0_pins` com `gpio20`, `gpio21`, `function = "blsp0_uart0"`.
- Isso nao combina com o no `serial@78af000` e pode quebrar RX quando o Linux aplica pinctrl, mesmo que TX continue funcionando por estado herdado do bootloader.

Alteracao aplicada:

- Em `target/linux/qualcommax/dts/ipq5018-mr80x-v5.dts`:
  - removido `pinctrl-0`/`pinctrl-names` de `&blsp1_uart1`;
  - removido o bloco `serial_0_pins`.
- A ideia e deixar o UART como o firmware original: controlador habilitado, mas sem reprogramar pinmux no Linux, preservando a configuracao feita pelo U-Boot.

Build:

- Build Docker concluido com sucesso.
- FIT normal:
  - kernel crc32: `d168c5d6`
  - kernel sha1: `d32e5b326b6b42f20c8ee4523d24c66dafa23487`
  - fdt crc32: `203000b4`
  - fdt sha1: `94aaa2b6229dcefeae94156f4b680d0444f6aa62`
- FIT initramfs:
  - kernel crc32: `96124fb7`
  - kernel sha1: `dfb1614e8bb45d863d3d1422503cd576e37fb3ef`
  - fdt crc32: `203000b4`
  - fdt sha1: `94aaa2b6229dcefeae94156f4b680d0444f6aa62`
- Hashes dos artefatos:
  - `82996c063a09d721f67cab6aad3496a4325af07b9d81eed54bc8f572183e3503  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-initramfs-uImage.itb`
  - `85d1d678a535c02ed57a623698fbd43a6d09bf22613c76fc6b69134f4c5ff1d6  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-squashfs-factory.ubi`
  - `9feb541f69eb926954f017976c8e5f833569365e86e65621ada9aeeb84b5e889  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-squashfs-sysupgrade.bin`

O que observar no proximo teste:

- Ao aparecer `Please press Enter to activate this console.`, pressionar Enter.
- Se funcionar, o problema era pinctrl errado do UART RX.
- Se continuar sem teclado, a proxima hipotese e init/getty/line discipline ou algum detalhe de terminal/adaptador, mas a diferenca mais concreta com o firmware original ja foi removida.

## 2026-07-09 - Corrigida tabela VLAN MC herdada do U-Boot

Diagnostico confirmado pelo terminal:

- `lan1` e `lan2` tinham carrier e recebiam quadros fisicos.
- `eth0` e `br-lan.2` permaneciam com RX igual a zero.
- A VLAN 2 aparecia somente em `lan1`, `br-lan` e `phy0-ap0`.
- Tentar adicionar VLAN 2 em runtime nas outras portas retornou:
  - `RTNETLINK answers: No space left on device`
  - retorno `-ENOSPC` de `rtl8365mb_vlan_mc_port_set()`.

Causa:

- O driver DSA procurava uma entrada livre na tabela VLAN Member Configuration.
- O U-Boot/firmware anterior deixava as 32 entradas preenchidas.
- O driver presumia que os indices `1..31` ja estavam vazios.
- A fonte vendor `target/linux/mediatek/files/drivers/net/phy/rtk/rtl8367c/vlan.c`
  confirma que `rtk_vlan_init()` limpa explicitamente todas as 32 entradas antes
  de configurar VLANs.

Correcao:

- `0999-drivers-net-dsa-realtek-add-RTL8367S-VB-support.patch` agora adiciona
  `rtl8365mb_vlan_mc_reset()`.
- A rotina zera os indices `0..31` da VLAN MC.
- `rtl8365mb_vlan_setup()` chama o reset antes de configurar vlan-filtering nas
  portas.
- O indice 0 fica neutro e os demais ficam disponiveis para PVIDs controlados
  pelo DSA.

Validacao:

- O patch foi aplicado sobre uma arvore Linux limpa com `target/linux/prepare`.
- Build Docker completo concluido com sucesso.
- FIT normal:
  - kernel crc32: `d88865d1`
  - kernel sha1: `0a9f6157cc5d0737e293ee17c777b3a8fd75b1c3`
  - fdt crc32: `203000b4`
  - fdt sha1: `94aaa2b6229dcefeae94156f4b680d0444f6aa62`
- FIT initramfs:
  - kernel crc32: `2616f9e8`
  - kernel sha1: `a693a5b5548335a7210474cdd64d499b237c42d8`
  - fdt crc32: `203000b4`
  - fdt sha1: `94aaa2b6229dcefeae94156f4b680d0444f6aa62`
- Hashes:
  - `edb6d59ccca93fa18271546a69d4533a99040ca10e9e98081ae84d8530d419b3  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-initramfs-uImage.itb`
  - `82039d7a72dfd0b62d98608792f59a950a799190a8e90b989ff9953ac5a93aab  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-squashfs-factory.ubi`
  - `752f135a684868f0535eb3dadff10b4dc126fe21b20017f5131001a07b2e72bd  openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-squashfs-sysupgrade.bin`

Teste esperado:

- `bridge vlan show` deve listar VLAN 2 em `lan1`, `lan2` e `lan3`.
- Nao deve ocorrer `No space left on device`.
- Quadros recebidos nas portas LAN devem incrementar RX de `eth0`/`br-lan.2`.
- DHCP e ping para `192.168.1.1` devem atravessar o switch.

## 2026-07-09 - Nova hipotese: CPU do RTL8367S-VB esta em EXT0, nao EXT1

Contexto do teste:

- Uma imagem anterior tentou deixar `dp2` em `2500base-x`/2500 diretamente.
- Essa imagem falhou no boot do OpenWrt:
  - `swphy: unknown speed`
  - `dp2: fail to register fixed-link: -22`
  - `nss-dp 39d00000.dp2: probe with driver nss-dp failed with error -14`
- Por isso `dp2` precisa permanecer registravel como `sgmii`/1000 no DTS, enquanto
  o lado Realtek pode ser configurado como HSGMII/2.5G.

Nova evidencia do firmware original:

- O firmware OEM cria `eth1.2`, `eth1.3`, `eth1.4` e `eth1.5` em `br-lan`.
- No log OEM, ao configurar VLANs do RTL8367S:
  - `vid=4094 memberMask=65537 untaggedMask=1`
  - `vid=2 memberMask=65538 untaggedMask=2`
  - `vid=3 memberMask=65540 untaggedMask=4`
  - `vid=4 memberMask=65544 untaggedMask=8`
  - `vid=5 memberMask=65552 untaggedMask=16`
- Esses `memberMask` usam o bit `1 << 16` como CPU/ext port. Na SDK Realtek,
  porta 16 normalmente representa `EXT0`.
- O patch anterior cadastrava o `RTL8367S-VB` como `port 6 -> EXT1`.

Correcao aplicada:

- Em `0999-drivers-net-dsa-realtek-add-RTL8367S-VB-support.patch`, a entrada
  `RTL8367S-VB` mudou de:
  - `{ 6, 1, PHY_INTF(SGMII) | PHY_INTF(HSGMII) }`
  para:
  - `{ 6, 0, PHY_INTF(SGMII) | PHY_INTF(HSGMII) }`
- O DTS ficou com:
  - `dp2`: `phy-mode = "sgmii"` e fixed-link 1000, para o NSS registrar.
  - primeiro teste: `port@6` do Realtek em `2500base-x`/2500, seguindo o log OEM.
  - resultado do primeiro teste: o Realtek subiu o CPU link como 2.5G, mas o
    `nss-dp` mostrou `eth0` em 1000; as portas fisicas aprenderam MACs, porem
    `eth0` e `br-lan` continuaram com RX zero.
  - decisao seguinte: testar `port@6` em `sgmii`/1000 mantendo `EXT0`, para casar
    exatamente com a velocidade que o `dp2` registra no OpenWrt.

Build:

- Build Docker `target/linux/install` concluido com sucesso.
- Alias TFTP atualizado:
  - `/home/fabiano/opw/openwrt/bin/targets/qualcommax/ipq50xx/mr80x-v5-diagnostic-initramfs.itb`
- Hash da imagem TFTP:
  - `cb1b2432c5839b44a49288232d8f57e0fe798093bb8abff8f443e654ea142679`

Proximo teste:

- Parar no U-Boot e carregar:
  - `tftpboot 0x44000000 mr80x-v5-diagnostic-initramfs.itb`
  - `bootm 0x44000000`
- Confirmar que nao aparece mais `dp2: fail to register fixed-link`.
- Confirmar que `lan1`, `lan2` e `lan3` aparecem no `ip -brief link`.
- Com o equipamento em `192.168.8.30` / `6C:3B:6B:30:09:FB` ligado na porta
  fisica LAN3, testar:
  - `ping -c 3 -W 1 192.168.8.30`
  - `ip neigh show 192.168.8.30`
  - estatisticas de `eth0`, `br-lan`, `lan1`, `lan2`, `lan3`.

## 2026-07-09 - Observacoes sobre rootfs_1 e testes Ethernet em runtime

Particoes de firmware:

- A tabela SMEM/MIBIB do U-Boot define `rootfs` e `rootfs_1` como duas particoes
  NAND fixas de `0x2a00000` cada uma.
- O U-Boot deste equipamento boota de forma confiavel pelo caminho primario
  (`tp_boot_idx=0`, `rootfs`). Ao tentar usar o caminho alternativo depois de
  sysupgrade, o boot caiu em erro/data abort.
- Por isso `rootfs_1` nao deve ser somada ao `rootfs` principal para aumentar a
  ROM. Fazer isso exigiria alterar a tabela MIBIB/SMEM e o comportamento do
  U-Boot, com risco real de brick.
- Caminho seguro: manter sysupgrade gravando apenas `rootfs`. Se necessario,
  `rootfs_1` pode ser estudada depois como armazenamento secundario/UBI extra,
  mas nao como expansao transparente da ROM principal.

Testes Ethernet no initramfs `r35275+3-273b186ac3`:

- Sintoma confirmado:
  - `lan1` aprende o MAC `6c:3b:6b:30:09:fb` e seus contadores RX sobem.
  - `eth0` permanece com `RX packets = 0`.
  - Durante ping para `192.168.8.30`, `eth0 TX` sobe, mas `lan1 TX` nao sobe.
- Isso indica que o problema nao e DHCP puro: o switch ve quadros na porta
  fisica, mas a passagem CPU-port/DSA ainda nao esta correta.
- Sequencias testadas via MDIO/TTL sem gravar flash:
  - EXT0/SGMII com sequencia vendor detalhada para MAC6.
  - EXT0/HSGMII com sequencia vendor detalhada.
  - EXT1/SGMII ajustando `0x1305` para bits altos.
- Nenhuma dessas combinacoes fez `eth0 RX` sair de zero.
- Durante os testes a imagem de diagnostico entrou em pressao de memoria/OOM
  com Wi-Fi, LuCI e servicos extras ativos. Para os proximos testes convem
  gerar uma initramfs mais enxuta ou parar servicos antes de sequencias longas.

## 2026-07-09 - Recovery, env do U-Boot e boot OEM recuperado

- A env do U-Boot estava quebrada depois do sysupgrade anterior:
  - `bootcmd=run distro_bootcmd`
  - `tp_boot_idx=1`
  - `ipaddr=192.0.2.1`
- Corrigido via OpenWrt initramfs com `fw_setenv`:
  - `bootcmd=bootipq`
  - `tp_boot_idx=0`
  - `ipaddr=192.168.1.1`
  - `netmask=255.255.255.0`
  - `bootdelay=1`
- Depois disso o equipamento voltou a bootar o firmware OEM em `rootfs`.
- O binario `0:appsbl` contem pagina HTTP de `Firmware upgrade` e strings:
  - `FW GPIO is pressed. Enter firmware recovery mode!`
  - `Both image corrupted, Enter http firmware recovery mode!`
  - `Start httpd server`
- Nao foi encontrado nome fixo de arquivo TFTP para recovery automatico sem TTL.
  A instalacao sem TTL deve ser tratada como recovery HTTP em `192.168.1.1`,
  acionado segurando reset no power-on, ate prova em contrario.
- Documento detalhado criado em `analis/recovery_mr80x_v5.md`.

## 2026-07-10 - Pendente: MACs do Wi-Fi

- O Wi-Fi ainda nao esta herdando o mesmo MAC base das Ethernet com incremento
  previsivel.
- Na proxima imagem, ajustar a geracao/aplicacao dos MACs Wi-Fi para usar o MAC
  real do equipamento e auto-incrementar de forma consistente entre Ethernet e
  radios.

## 2026-07-10 - Sysupgrade gravado e novo estado da Ethernet

- A falha de sysupgrade anterior foi explicada: a imagem rodando usava a logica
  generica `tplink_do_upgrade`, que alternava para `rootfs_1` e mantinha
  `tp_boot_idx=1`.
- Corrigido em `platform.sh`: o MR80X v5 agora grava sempre em `rootfs` e força
  `tp_boot_idx 0` antes do `nand_do_upgrade`.
- Teste real feito via Wi-Fi:
  - IP do roteador no STA `Tassotti`: `192.168.1.49` antes do upgrade;
  - imagem enviada por `scp`;
  - `sysupgrade -n` executado;
  - log TTL confirmou `sysupgrade successful`;
  - apos reboot, imagem `r35275+5-273b186ac3` subiu de `rootfs` com rootfs de
    cerca de 10 MiB e firmwares Wi-Fi presentes.
- Estado apos sysupgrade:
  - Wi-Fi/ath11k sobe e conecta no `Tassotti`; IP observado: `192.168.1.52`;
  - `/lib/firmware/ath11k/IPQ5018/hw1.0/q6_fw.mdt` existe e carrega;
  - `fw_env.config` existe;
  - LuCI e ferramentas de diagnostico estao na imagem.
- Ethernet ainda falha antes de criar as portas DSA:
  - no boot normal da flash, `rtl8365mb-mdio 90000.mdio-1:1d` le `id=0xffff`;
  - no boot via U-Boot/TFTP antigo, o mesmo DTS/driver detectava o chip apos o
    U-Boot inicializar a rede para o TFTP.
- Testes manuais no runtime:
  - MDIO direto em `90000.mdio-1:1d` retorna `0xffff`;
  - alternar GPIO39 manualmente nao acordou o switch;
  - alternar GPIO26 manualmente tambem nao acordou o switch.
- Pista do FDT OEM:
  - `mdio@90000` tem `phy-reset-gpio = GPIO26`;
  - o bloco do switch Realtek/QCA tem `reset_gpio = 0x27` (GPIO39);
  - portanto ha duas linhas/etapas de reset no firmware original, e ainda falta
    reproduzir integralmente no boot normal do OpenWrt a sequencia que o U-Boot
    deixa pronta quando faz TFTP.

## 2026-07-10 - Coleta OEM ao vivo e novo teste de CPU tag

- Com o firmware original acessivel por UART, foi confirmado novamente:
  - `eth1` e o master/conduit do switch Realtek;
  - `br-lan` usa `eth1.2 eth1.3 eth1.4 eth1.5`;
  - WAN usa `eth1.4094` e recebeu DHCP;
  - `eth0` fica down e nao participa do switch.
- O driver OEM expõe `/proc/driver/rtl8367s/{init,lut,mib,phy,port,reg,sgmii,vlan}`.
- A leitura de `/proc/driver/rtl8367s/phy` mostra somente as portas fisicas
  0-4. A porta CPU e tratada como extensao/logica (`CPU_PORTS=16` nos scripts).
- A inicializacao OEM relevante em `/lib/switch/core_phy.sh` faz:
  - `echo 1 > /proc/driver/rtl8367s/sgmii`;
  - `echo ptype set $CPU_PORTS 1 > /proc/driver/rtl8367s/port`;
  - `echo linkup 1 > /proc/driver/rtl8367s/phy`;
  - `ssdk_sh port flowCtrl set 2 enable`;
  - `devmem 0x39D00018 32 0xFFFF0004`.
- O teste anterior do OpenWrt mostrava RX nas portas DSA, mas RX zero no master
  e TX do master sem chegar na porta fisica. Isso aponta para drop/posicao de
  CPU tag, nao para DHCP puro.
- Novo ajuste preparado:
  - DTS: `port@6` recebeu `dsa-tag-protocol = "rtl8_4t"`;
  - patch Realtek: removida a escrita customizada que forçava o CPU port para
    aceitar apenas quadros VLAN tagged em `0x07aa`, pois DSA tag nao e tag
    802.1Q e isso pode bloquear trafego CPU->switch.

## 2026-07-10 - Build do teste `rtl8_4t`

- Commits relevantes no repo OpenWrt:
  - `660a849563 net: realtek: test RTL8367S tail CPU tags`;
  - `9139f91788 net: realtek: repair RTL8367S patch header`;
  - `b07f701b3b net: realtek: fix RTL8367S setup hunk`.
- A imagem compilou limpa via Docker.
- Artefatos novos em `/home/fabiano/opw/openwrt/bin/targets/qualcommax/ipq50xx/`:
  - `openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-initramfs-uImage.itb`
    - tamanho: `5505468`
    - sha256: `0cce92465abaa898ec1025e0013ac8cc1487776d5acfdf91f1ab1621ca9fb2cb`
  - `openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-squashfs-factory.ubi`
    - tamanho: `16646144`
    - sha256: `b6b02b8654a4bed92a4bfc7a7f543326c04734bdc958003312b053d8ed1320c6`
  - `openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-squashfs-sysupgrade.bin`
    - tamanho: `15800600`
    - sha256: `2b4439c833ee258828fec1e88a27bbc3a4fdde31d8085456b44f89c92d190efd`
- O pacote `net/dsa/tag_rtl8_4.o` foi compilado, confirmando que o protocolo
  de tag Realtek novo entrou na build.
- O container `recovery-lab-tftp-server-1` esta ativo e serve exatamente esse
  diretorio em `/var/tftpboot` via UDP/69.
- Atenção antes de TFTP pelo U-Boot:
  - `.env` espera `TFTP_HOST_ADDRESS=192.168.6.83/24`;
  - no momento da checagem, `enx000e0986bc59` e `enx00e04c7611f9` estavam com
    endereços `192.168.1.x`;
  - portanto o U-Boot deve usar `serverip` na faixa realmente configurada ou a
    interface do host deve ser recolocada em `192.168.6.83/24`.
- O roteador apareceu no prompt `IPQ5018#` apos um reboot visto no log serial.
  O broker serial recebia saida, mas comandos enviados por socket nao chegaram
  ao U-Boot; ha multiplos clientes conectados ao broker e isso precisa ser
  limpo antes de automacao de flash/boot pelo Codex.
