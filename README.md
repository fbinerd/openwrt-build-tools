# openwrt-build-tools

Build/deploy toolkit for OpenWrt 25.12 with:

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
./start.sh docker clean my-router
./start.sh backup-config
./start.sh purge
./start.sh ipk <ip> <package> [user]
./start.sh sysupgrade <ip> [user]
./start.sh deploy-ipk <ip> <package> [user]
./start.sh deploy-sysupgrade <ip> [user]
./start.sh patches
```

## Directory Layout

- `start.sh`: main CLI (interactive menu + direct commands)
- `scripts/`: implementation scripts
- `.env`: local environment overrides loaded automatically by the scripts
- `.env.example`: template for the root environment file
- `containers/openwrt-builder/`: OpenWrt build container definition
- `containers/firmware-extract/`: extraction container notes and layout
- `containers/serial-lab/`: UART/TTL recovery container layout
- `containers/tftp-lab/`: TFTP recovery container layout
- `ai-memory/`: shared working memory for agents and running notes
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
./start.sh docker clean my-router
./start.sh docker clean router-configs/my-router.config
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
- example: `router-configs/tplink_my-router.config`

## Purge Local Runtime/Cache Data

```sh
./start.sh purge
```

Use this when you want to stop using the project and free host resources:

- removes Docker container `openwrt_build` (if present)
- removes Docker image `openwrt-25.12-builder` (if present)
- removes local `openwrt/`, `dl/`, and `reports/`
- recreates empty `dl/` and `reports/`

Non-interactive mode:

```sh
./start.sh purge --yes
```

## Script Reference

- `scripts/docker-build.sh`: Docker orchestration and mode logic
- `scripts/build_openwrt.sh`: in-container build/bootstrap steps
- `scripts/apply-openwrt-patches.sh`: patch + feed setup (`feeds.conf` only)
- `scripts/deploy-ipk.sh`: build one package and install on router
- `scripts/deploy-sysupgrade.sh`: upload firmware + `sysupgrade -c`
- `scripts/backup-router-config.sh`: export current `.config` as named profile
- `scripts/purge-workspace.sh`: purge local Docker runtime/cache/build workspace

## Container Map

- `containers/openwrt-builder/`: builds and runs the OpenWrt toolchain image used by `./start.sh docker`
- `containers/firmware-extract/`: keeps notes and layout for firmware extraction/rebuild work
- `containers/serial-lab/`: keeps the UART console/recovery workflow grouped together
- `containers/tftp-lab/`: keeps TFTP recovery workflow grouped together

## Shared Memory

Use `ai-memory/` as the shared notebook for any agent working in this repo.

- read `ai-memory/README.md` first
- update `ai-memory/active.md` with current goal, findings, and next step
- move older notes into `ai-memory/archive/` when they are no longer active

The intent is to keep the working context visible to any future agent without having to reconstruct it from scratch.

## Feed/Patch Rules

- `feeds.conf.default` is never modified
- only `openwrt/feeds.conf` is managed by scripts
- custom feed injection is disabled by default, and can be enabled at runtime by setting the `ENABLE_CUSTOM_FEED=1` environment variable (e.g., `ENABLE_CUSTOM_FEED=1 ./start.sh`)

## Versioning Model

- This repository tracks automation, patches, and docs
- `openwrt/` is treated as disposable local workspace
