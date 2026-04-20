# openwrt-build-tools

Build and deployment workspace for OpenWrt 18.06, with scripts organized under `scripts/` and a single launcher at the repository root.

## Structure

- `start.sh`: main launcher (interactive menu + direct command mode)
- `scripts/`: operational scripts
- `openwrt/`: local OpenWrt tree (not tracked by `openwrt-build-tools`)
- `patches/openwrt/`: optional patches applied at build bootstrap
- `reports/`: diagnostic reports
- `dl/`: download cache

## Main launcher

Always use:

```sh
./start.sh
```

Direct command mode is also available:

```sh
./start.sh docker [clean]
./start.sh ipk <ip> <package> [user]
./start.sh sysupgrade <ip> [user]
./start.sh diagnose <ip> [user] [vxlan_uci_section]
./start.sh patches
```

## Scripts in `scripts/`

- `docker-build.sh`: runs build inside a Docker container
- `build_openwrt.sh`: internal build sequence executed in the container
- `apply-openwrt-patches.sh`: applies patches in `openwrt/` and ensures feed line in `feeds.conf`
- `deploy-sysupgrade.sh`: uploads firmware and runs `sysupgrade -c`
- `deploy-ipk.sh`: builds one package and installs it on the router
- `vxlan-diagnose.sh`: collects remote VXLAN diagnostics and stores reports under `reports/`

## Custom feed notes

- `feeds.conf.default` is **never modified** by this flow.
- `apply-openwrt-patches.sh` manages only `openwrt/feeds.conf`.

## Versioning model

- `openwrt-build-tools` tracks only automation (scripts, patches, docs).
- `openwrt/` is always rebuilt from official clone + local patch application.
