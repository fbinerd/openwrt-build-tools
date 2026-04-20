# openwrt-build-tools

Build/deploy toolkit for OpenWrt 18.06 with:

- one entrypoint (`start.sh`)
- Docker-based build environment
- reusable router `.config` profiles
- custom feed patch/bootstrap flow

## Quick Start

```sh
cd /media/storage/openwrt-build-tools
./start.sh
```

Or run directly:

```sh
./start.sh docker
./start.sh docker clean
./start.sh docker clean tplink_tl-wr740n-v6
./start.sh backup-config
./start.sh ipk <ip> <package> [user]
./start.sh sysupgrade <ip> [user]
./start.sh diagnose <ip> [user] [vxlan_uci_section]
./start.sh patches
```

## Directory Layout

- `start.sh`: main CLI (interactive menu + direct commands)
- `scripts/`: implementation scripts
- `openwrt/`: local OpenWrt workspace (not tracked in Git)
- `router-configs/`: saved router profiles (`*.config`)
- `patches/openwrt/`: OpenWrt patch set applied during bootstrap
- `reports/`: diagnostics output
- `dl/`: download cache (preserved on clean)

## Docker Modes

### Normal mode
`./start.sh docker`

- reuses existing workspace
- does not clean sources
- opens interactive shell in container
- if a matching `openwrt_build` container already exists, CLI attaches/reuses it

### Clean mode
`./start.sh docker clean`

- resets local OpenWrt workspace
- reclones OpenWrt (full clone, not shallow)
- reapplies local patches
- updates/install feeds and bootstraps sources
- keeps `dl/` cache

When compiled tools/toolchain are detected, clean mode asks whether to remove them.  
Press Enter/No to preserve and save rebuild time.

## Router Profile Flow

During `docker` and `docker clean`:

- CLI asks if you want to use a specific router profile
- profiles are loaded from `router-configs/*.config`
- if you choose one, it is copied to `openwrt/.config`
- if you do not choose one, `router-configs/default.config` is applied automatically (if present)

You can also pass profile inline:

```sh
./start.sh docker clean tplink_tl-wr740n-v6
./start.sh docker clean router-configs/tplink_tl-wr740n-v6.config
```

## Build Parallelism

During Docker flow, CLI asks for number of CPU cores for `make`.

- Enter empty value: default `make`
- Enter value (example `40`): `make -j40`

Inline override:

```sh
MAKE_JOBS=40 ./start.sh docker clean
```

## Backup Current .config

```sh
./start.sh backup-config
```

This reads `openwrt/.config`, detects target/profile, and writes:

- `router-configs/brand_router-model.config`
- example: `router-configs/tplink_tl-wr740n-v6.config`

## Script Reference

- `scripts/docker-build.sh`: Docker orchestration and mode logic
- `scripts/build_openwrt.sh`: in-container build/bootstrap steps
- `scripts/apply-openwrt-patches.sh`: patch + feed setup (`feeds.conf` only)
- `scripts/deploy-ipk.sh`: build one package and install on router
- `scripts/deploy-sysupgrade.sh`: upload firmware + `sysupgrade -c`
- `scripts/vxlan-diagnose.sh`: collect VXLAN diagnostics
- `scripts/backup-router-config.sh`: export current `.config` as named profile

## Feed/Patch Rules

- `feeds.conf.default` is never modified
- only `openwrt/feeds.conf` is managed by scripts
- custom feed is injected during patch/bootstrap flow

## Versioning Model

- This repository tracks automation, patches, and docs
- `openwrt/` is treated as disposable local workspace
