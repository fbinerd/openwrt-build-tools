# Recovery e instalacao - Mercusys MR80X v5

Data da analise: 2026-07-09.

## Estado confirmado

- U-Boot: `U-Boot 2016.01 (Nov 11 2024 - 20:42:13 +0800)`.
- SoC: IPQ5018.
- Flash: SPI-NAND 128 MiB.
- Particoes relevantes:
  - `rootfs`: offset `0x00640000`, tamanho `0x02a00000`.
  - `rootfs_1`: offset `0x03040000`, tamanho `0x02a00000`.
  - `0:appsblenv`: ambiente do U-Boot.
- A env quebrada pelo sysupgrade anterior foi corrigida no OpenWrt initramfs:
  - `bootcmd=bootipq`
  - `tp_boot_idx=0`
  - `ipaddr=192.168.1.1`
  - `netmask=255.255.255.0`
  - `bootdelay=1`
- Depois dessa correcao, o roteador voltou a bootar o firmware OEM de `rootfs`.

## Recovery sem TTL

O U-Boot do MR80X v5 contem suporte a modo de recovery por botao:

- String no binario `0:appsbl`:
  - `FW GPIO is pressed. Enter firmware recovery mode!`
  - `Both image corrupted, Enter http firmware recovery mode!`
  - `Start httpd server`
  - Pagina HTML embutida com titulo `Firmware upgrade`.
- No boot normal o U-Boot imprime:
  - `button_init done~`
  - `key 14 addr 0x0100e004 val 0x1`
- O GPIO/key `14` corresponde ao botao reset no DTS.

Conclusao atual: o recovery sem TTL parece ser HTTP, nao TFTP automatico.

Procedimento esperado para testar:

1. Configurar o PC em uma porta LAN com IP estatico `192.168.1.2/24`.
2. Desligar o roteador.
3. Segurar o botao reset.
4. Ligar o roteador mantendo reset pressionado ate entrar no modo recovery.
5. Acessar `http://192.168.1.1/` no navegador.
6. Enviar uma imagem aceita pelo validador do U-Boot.

Observacao importante: nao foi encontrado nome fixo de arquivo TFTP para recovery
automatico sem TTL. As strings de TFTP presentes no U-Boot parecem ser do comando
generico `tftpboot` e de dump/debug, nao de um fluxo automatico tipo
`mr80xv5_tp_recovery.bin`.

## Imagem para recovery sem TTL

O caminho HTTP passa por rotinas OEM como `nm_upgradeFirmware` e imprime strings
como `Firmware checking passed`. Portanto, a imagem provavelmente precisa estar no
formato de firmware Mercusys/TP-Link aceito pelo bootloader.

### Requisitos observados da imagem HTTP OEM

Analise feita com:

- firmware OEM:
  `analis/binaries/MR80X_v5_br-up-eu-ver1-3-1-P1[20251226-rel65216]-2048_nosign_2025-12-29_10.01.08.bin`
- firmware OEM descriptografado:
  `analis/binaries/MR80X_v5_br-up-eu-ver1-3-1-P1[20251226-rel65216]-2048_nosign_2025-12-29_10.01.08.bin.dec`
- ferramenta local:
  `analis/tools/tp-link-decrypt/bin/tp-link-decrypt`
- U-Boot/APPSBL:
  `analis/fw_extracted/OpenWrt.mtd8.0-appsbl.bin`

O U-Boot contem a pagina web de upgrade e espera upload HTTP
`multipart/form-data` com campo `firmware`. As strings relevantes no APPSBL sao:

```text
nm_upgradeFirmware
Content-Type: multipart/form-data; boundary=
Firmware Upgrade
name="firmware"
support-list
SupportList:
Firmwave supports, check OK.
Firmwave not supports, check failed.
checkUpdateContent failed.
RSA2048 PSS
Verify sig error!
Firmware checking passed
```

O firmware OEM aceito nao e uma UBI crua. Ele e um pacote TP-Link/Mercusys
`fw-type:Cloud`:

```text
offset 0x0014: "fw-type:Cloud\n"
offset 0x0110: 00 00 02 00        # RSA-2048
offset 0x0114: aa 55 4c 5e 83 1f 53 4b a1 f8 f7 c9 18 df 8f bf 7d a1 55 aa
offset 0x0130: assinatura RSA-PSS de 256 bytes
```

A ferramenta `tp-link-decrypt` confirmou:

```text
fw-type: found
RSA-2048
Firmware verification successful
```

Depois da verificacao/decriptacao, o pacote contem metadados antes da UBI:

```text
offset 0x1014: support-list
offset 0x1040: SupportList:
offset 0x12a0: soft-version
offset 0x12f4: fw_id
offset 0x131c: UBI#
```

Lista de suporte presente no firmware OEM analisado:

```text
{product_name:MR80X,product_ver:2.0.0,special_id:45550000}
{product_name:MR80X,product_ver:2.0.0,special_id:55530000}
{product_name:MR80X,product_ver:5.0.0,special_id:42520000}
{product_name:MR80X,product_ver:5.0.0,special_id:52550000}
{product_name:MR80X,product_ver:2.0.0,special_id:43410000}
{product_name:MR3000X,product_ver:2.0.0,special_id:45550000}
{product_name:MR3000X,product_ver:5.0.0,special_id:52550000}
{product_name:MR1800X,product_ver:2.0.0,special_id:45550000}
{product_name:MR70X,product_ver:2.0.0,special_id:45550000}
{product_name:MR70X,product_ver:2.0.0,special_id:55530000}
```

O `tp_data/product-info` extraido do aparelho BR contem:

```text
product_name:MR80X
product_ver:5.0.0
special_id:42520000
```

Portanto o firmware OEM BR/EU analisado cobre este aparelho porque possui a
entrada `MR80X`, `5.0.0`, `42520000`.

Conclusao: a interface web de recovery deve rejeitar as imagens OpenWrt atuais
como estao, porque:

- `initramfs-uImage.itb` e uma FIT para `bootm` via U-Boot/TFTP;
- `squashfs-sysupgrade.bin` e um tar de `sysupgrade`;
- `squashfs-factory.ubi` comeca direto em `UBI#`;
- nenhuma delas tem `fw-type:Cloud`, `support-list` e assinatura RSA-PSS valida.

A ferramenta local permite descriptografar e verificar firmware OEM, mas o README
deixa claro que ela nao cria firmware assinado. Sem a chave privada TP-Link/
Mercusys ou uma falha/bypass no validador, nao da para gerar uma imagem OpenWrt
aceita pela web OEM apenas envelopando a UBI.

Estado atual das imagens OpenWrt:

- `openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-initramfs-uImage.itb`
  - Boa para boot temporario via U-Boot/TFTP.
  - Nao deve ser gravada como firmware permanente.
- `openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-squashfs-sysupgrade.bin`
  - Boa para `sysupgrade` a partir de um OpenWrt funcional.
  - Nao e imagem de recovery web OEM.
- `openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-squashfs-factory.ubi`
  - UBI da particao `rootfs`.
  - Ainda nao esta provado que o recovery HTTP OEM aceita esse arquivo cru.

Para instalacao oficial sem TTL, ainda falta criar ou confirmar uma imagem
`factory` no formato Mercusys/TP-Link aceito pelo recovery HTTP. Enquanto isso,
nao declarar o recovery HTTP como metodo oficial de instalacao OpenWrt.

## TFTP com TTL

Este caminho ja foi testado e funciona para boot temporario de initramfs.

Configuracao do host usada nos testes:

- IP do host/TFTP: `10.0.0.83/24`.
- TFTP root: `/home/fabiano/opw/openwrt/bin/targets/qualcommax/ipq50xx`.
- Alias de teste:
  - `mr80x-v5-diagnostic-initramfs.itb`.

Comandos no U-Boot:

```text
setenv serverip 10.0.0.83
setenv ipaddr 10.0.0.1
tftpboot 0x44000000 mr80x-v5-diagnostic-initramfs.itb
bootm 0x44000000
```

Imagem correta para esse fluxo:

- `openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-initramfs-uImage.itb`
  ou o alias `mr80x-v5-diagnostic-initramfs.itb`.

Nao usar neste fluxo:

- `sysupgrade.bin`, porque ele e pacote para OpenWrt em execucao.
- `factory.ubi`, porque ele e conteudo de flash/UBI, nao kernel initramfs para
  `bootm`.

## Observacoes Ethernet do firmware original

O firmware OEM usa o switch Realtek de forma diferente do DSA atual:

- Interface CPU original: `eth1`.
- Portas LAN no bridge:
  - `eth1.2`
  - `eth1.3`
  - `eth1.4`
  - `eth1.5`
- Todas entram em `br-lan`.

Isso reforca que o problema atual do OpenWrt nao e DHCP isolado. O driver DSA
atual aprende MAC nas portas fisicas, mas `eth0` fica com RX zerado; o caminho
CPU-port/tagging/SerDes ainda nao esta equivalente ao firmware OEM.
