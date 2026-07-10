# Active Memory

## Current Goal
Keep the OpenWrt tooling organized for multi-agent work and make the working context easy to recover.

## Current State
Repository is on branch `refactor/container-layout`.
The build container lives under `containers/openwrt-builder/`.
The lab areas are split into `containers/firmware-extract/`, `containers/serial-lab/`, and `containers/tftp-lab/`.
The shared analysis/recovery notes are under `tools/firmware-lab/` and `tools/recovery-lab/`.

## Known Facts
`openwrt-build-tools` is the top-level coordination repo.
`tools/recovery-lab/` is its own git repository.
`tools/firmware-lab/tools/tp-link-decrypt/` is also its own git repository.

## Next Step
Keep writing short notes here when the focus changes or when a new blocker appears.

## Recent Notes

- Created shared `ai-memory/` area for agents to record live context.
