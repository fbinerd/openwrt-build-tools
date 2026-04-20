# openwrt-build-tools

Workspace de build e deploy para OpenWrt 18.06, com organização de scripts em `scripts/` e um launcher único na raiz.

## Estrutura

- `start.sh`: launcher principal (menu interativo + modo por comando)
- `scripts/`: scripts operacionais
- `openwrt/`: árvore local do OpenWrt (não versionada no `openwrt-build-tools`)
- `patches/openwrt/`: patches opcionais aplicados no início do build
- `reports/`: relatórios de diagnóstico
- `dl/`: cache de downloads

## Launcher principal

Use sempre:

```sh
./start.sh
```

Também funciona por comando direto:

```sh
./start.sh docker [clean]
./start.sh ipk <ip> <pacote> [usuario]
./start.sh sysupgrade <ip> [usuario]
./start.sh diagnose <ip> [usuario] [secao_uci_vxlan]
./start.sh patches
```

## Scripts em `scripts/`

- `docker-build.sh`: build dentro de container
- `build_openwrt.sh`: sequência interna de build executada no container
- `apply-openwrt-patches.sh`: aplica patches em `openwrt/` e garante feed em `feeds.conf`
- `deploy-sysupgrade.sh`: envia firmware e executa `sysupgrade -c`
- `deploy-ipk.sh`: compila um pacote e instala no roteador
- `vxlan-diagnose.sh`: coleta diagnóstico VXLAN remoto e salva em `reports/`

## Notas sobre feed customizado

- `feeds.conf.default` **não é alterado** pelo fluxo de patches.
- O script `apply-openwrt-patches.sh` gerencia apenas `openwrt/feeds.conf`.

## Versionamento

- O repositório `openwrt-build-tools` versiona apenas automação (scripts, patches e documentação).
- A pasta `openwrt/` é sempre reconstruída por clone oficial + aplicação de patches.
