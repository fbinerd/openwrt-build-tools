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
- 2026-07-10: OEM MR80X v5 rootfs rebuild must preserve the real `ubi_rootfs`
  layout: volume 1 has 157 LEBs, not 160. Also build SquashFS with plain XZ
  for the OEM 4.4 kernel; `-Xbcj arm` made the rebuilt rootfs fail to mount
  with `Cannot open root device "mtd:ubi_rootfs"` / `error -5`. The corrected
  image booted to `MR80X login:` after flashing via U-Boot `flash rootfs`.
- 2026-07-10: OEM MR80X v5 Ethernet topology was verified from live OEM
  firmware over UART. OEM uses `eth1` as the CPU/conduit link to RTL8367S:
  LAN bridge is `eth1.2 eth1.3 eth1.4 eth1.5`, WAN is `eth1.4094`, and
  `eth0` is unused/down. `/lib/network/network_arch.sh` maps LAN logical
  ports 1-4 to PHY 1-4 and WAN to PHY 0; `/etc/config/switch` tags CPU port
  `6t` and the live bridge FDB showed host cables on `eth1.2` and `eth1.4`,
  while WAN DHCP was on `eth1.4094`.
