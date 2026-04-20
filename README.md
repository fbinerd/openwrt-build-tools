# openwrt-build-tools

Build and deployment workspace for OpenWrt 18.06, with scripts organized under `scripts/` and a single launcher at the repository root.

## Structure

- `start.sh`: main launcher (interactive menu + direct command mode)
- `scripts/`: operational scripts
- `openwrt/`: local OpenWrt tree (not tracked by `openwrt-build-tools`)
- `router-configs/`: saved router profiles (`*.config`, e.g. `my-router.config`)
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
./start.sh docker [normal|clean] [router_name_or_config_file]
./start.sh ipk <ip> <package> [user]
./start.sh sysupgrade <ip> [user]
./start.sh diagnose <ip> [user] [vxlan_uci_section]
./start.sh patches
```

`docker` mode behavior:

- `./start.sh docker`:
Uses current binaries/workspace as-is, does not clean, and opens an interactive shell in the build container.
- `./start.sh docker clean`:
Deletes local `openwrt/`, reclones OpenWrt, reapplies patches, refreshes feeds/download bootstrap, then opens an interactive shell. `dl/` cache is preserved.

Router profile behavior:

- On `docker` and `docker clean`, the script asks whether to prepare a specific router profile.
- Profiles are read from `router-configs/*.config`.
- If you select one, it is copied to `openwrt/.config` (replacing the existing one).
- If you press Enter or choose none, behavior remains unchanged.

Make jobs behavior:

- During Docker flow, the script asks how many CPU cores should be used by `make`.
- Press Enter to keep default `make` behavior.
- Enter a number (for example `40`) to use parallel mode (`make -j40`).

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
