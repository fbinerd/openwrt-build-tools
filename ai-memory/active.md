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

- 2026-07-11: Built a new MR80X v5 initramfs after adding chip ID `0x6642`
  to the RTL8367C ASIC EXT-port helpers. New hashes in
  `/home/fabiano/opw/openwrt/bin/targets/qualcommax/ipq50xx/`:
  initramfs ITB `e267dbf3e700cfac274b28d39c1dc11cb95110262dc8b0441d0d06c71f983605`,
  factory UBI `dd4c0ed5deec80010533823e879374d2f0810f4418f302e9fc8a5bdb93310f27`,
  sysupgrade `1ecd7a2f461c7364fda919e4940cd482d520d6fb3e6d7af70505c92e087a6e81`.
  TFTP attempt from U-Boot using `serverip=192.168.6.83`, `ipaddr=192.168.6.1`,
  `tftpblocksize=1468` stalled after OACK with repeated `T`; dnsmasq logged
  both `failed sending` and `Network is unreachable`. Do not repeat that exact
  transfer setup. Next attempt should use the other host adapter
  `enx000e0986bc59`/`192.168.8.2` or a smaller/no-blocksize setup after a
  manual reboot clears the stuck U-Boot TFTP command.
- 2026-07-11: Latest RTL8367S swconfig initramfs finally registered
  `switch0 - RTL8367C`, but Ethernet still did not pass traffic. `swconfig`
  showed VLAN membership and physical ports 2/3 had link/counters, while Linux
  `eth0`/`eth0.2` RX stayed at zero and ARP for `192.168.8.2` stayed
  incomplete. Runtime tests changing the tagged CPU port from `6t` to `5t`
  did not restore RX. New concrete blocker: kernel logs show
  `rtl8367s ext0 hsgmii force ret=-1`, `ext0 sgmii nway off ret=-1`, and
  `ext1 rgmii force ret=-1`, while U-Boot reports all matching Realtek calls
  with ret 0. Source check found the cause for at least this failure:
  `rtk_switch_probe()` accepts chip ID `0x6642`, but
  `rtl8367c_asicdrv_port.c` still rejected `0x6642` in the EXT/HSGMII helper
  functions and returned `RT_ERR_FAILED`. Next test adds `0x6642` to those
  switch cases; if the HSGMII logs become ret 0, re-test Ethernet RX before
  changing topology again.
- 2026-07-11: Valid RTL8367S vendor-driver boot with initramfs sha256
  `c29c9a7082c697c484ae53eb6f1fb9fdbf22b9bc63f5de37eafa39b13a490f0b`
  proved the new module was loaded. The driver can read the switch over MDIO:
  register `0x1300 = 0x6642`, `0x1301 = 0x0010`. The immediate failure is
  `rtk_switch_init ret=-1`; every later Realtek API call returns `15`
  (`RT_ERR_NOT_INIT`). Cause found in vendor `rtk_switch_probe()`: it accepts
  RTL8367C IDs `0x0276`, `0x0597`, `0x6367` but rejected MR80X v5 chip ID
  `0x6642`. Current test adds `0x6642` as RTL8367C-compatible. If this boots
  with `rtk_switch_init ret=0`, continue with CPU/ext port and VLAN traffic
  tests instead of re-testing MDIO access.
- 2026-07-11: Test image sha256
  `f189e711707865b689a5d5793b203b7af03564c65145dea6b6778bbb7da0560f`
  confirmed `rtk_switch_init ret=0`, `rtk_vlan_reset/init ret=0`, and VLAN/PVID
  writes all return 0 after adding chip ID `0x6642`. However `swconfig list`
  was empty and `/etc/rc.d/S20network` logged "Failed to connect to the
  switch" because DTS property `mediatek,port_map = "wllll"` takes the fixed
  VLAN path in `rtl8367s_mdio.c` and skips `rtl8367s_swconfig_init()`. Current
  next test removes that property so `switch0` can register and UCI board.d can
  configure VLANs.
- 2026-07-11: Current OpenWrt Ethernet direction is to test the existing vendor
  RTL8367S MDIO/swconfig driver instead of DSA. Commit `ca5b7b6960` adds
  `kmod-rtl8367s-vendor` and a `switch0` board config using `6@eth0`,
  `0:wan`, `1:lan:3`, `2:lan:2`, `3:lan:1`. The first vendor-driver boot was
  inconclusive because the built root still had stale DSA board config and
  lacked `/sbin/swconfig`; do not treat that image as a failed driver test.
- 2026-07-11: Commit `b7679c5f9c` makes the vendor driver compile with
  `-DCONFIG_SWCONFIG=1 -DMDC_MDIO_OPERATION=1`. Runtime hot-reload proved
  `CONFIG_SWCONFIG` is needed to register `switch0`, and `MDC_MDIO_OPERATION`
  is needed to avoid the empty GPIO/I2C access path. Do not repeat the
  hot-reload test as conclusive: it left the router in a dirty state with
  `swconfig list` stuck and a `register_switch()` trace. Next test is a clean
  TFTP boot of initramfs sha256
  `7ca443d77daa30ac333e37a8dea2ea20cf49dc1ebc512cd3a0297ee97583c0f8`.
- 2026-07-11: Clean boot of initramfs sha256 `7ca443...` did not trace or
  stall, and `swconfig list` showed `switch0 - RTL8367C`, but all swconfig
  PVID/link/VLAN data still came back as `???`; `eth0`/`eth0.2` RX stayed zero
  and host ping to `192.168.8.1` failed. That means switch registration is
  working but the vendor Realtek API still is not really reading/writing the
  RTL8367S over MDIO/SMI.
- 2026-07-11: New OpenWrt test changes `MDC_MDIO_PHY_ID` from hardcoded 29 to
  build-time override and builds the vendor driver with PHY ID 0 plus limited
  MDIO transaction logs. New initramfs sha256 is
  `454e74f130df27415bb289393edec7bf10ffe77d6f7977fa443271903a2f0641`.
  This specifically tests the vendor code comment "PHY ID 0 or 29" against the
  OEM FDT, which declares external switch PHY children at 0..3 on `mdio@90000`.
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
- 2026-07-10: live OEM shell confirmed `/proc/driver/rtl8367s/phy` sees physical
  ports 0-4, `/proc/driver/rtl8367s/sgmii` is enabled by the switch init, and
  OEM runs `echo ptype set 16 1 > /proc/driver/rtl8367s/port`,
  `echo linkup 1 > /proc/driver/rtl8367s/phy`, and
  `devmem 0x39D00018 32 0xFFFF0004`. The next OpenWrt test relaxes the custom
  VLAN tagged-only CPU-port setting and forces DSA `rtl8_4t` on the Realtek CPU
  port to test whether the failure is CPU tag placement/drop.
- 2026-07-10: OpenWrt branch `codex-mr80x-v5-ethernet-debug` built cleanly after
  commits `660a849563`, `9139f91788`, and `b07f701b3b`. Fresh images are in
  `/home/fabiano/opw/openwrt/bin/targets/qualcommax/ipq50xx/` with hashes:
  initramfs `0cce92465abaa898ec1025e0013ac8cc1487776d5acfdf91f1ab1621ca9fb2cb`,
  factory UBI `b6b02b8654a4bed92a4bfc7a7f543326c04734bdc958003312b053d8ed1320c6`,
  sysupgrade `2b4439c833ee258828fec1e88a27bbc3a4fdde31d8085456b44f89c92d190efd`.
  TFTP container `recovery-lab-tftp-server-1` serves that directory on UDP 69,
  but host USB Ethernet interfaces currently have `192.168.1.x`, not the desired
  `192.168.6.83/24` from `.env`.
- 2026-07-10: The previous 5.3 MiB `initramfs-uImage.itb` was not a real
  initramfs; it booted a kernel that tried to mount `/dev/ubiblock0_1` and
  panicked. Rebuilt with `CONFIG_EXTERNAL_CPIO=""`; the valid initramfs ITB is
  15 MiB, embeds `root-qualcommax`, and booted to OpenWrt over TFTP.
- 2026-07-10: TFTP transfer of the 15 MiB ITB only completed after removing
  `--tftp-no-blocksize` from recovery-lab dnsmasq and moving `192.168.6.83/24`
  to `enx000e0986bc59`. U-Boot command used:
  `setenv tftpblocksize 1468; tftpboot 0x44000000 openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-initramfs-uImage.itb; bootm 0x44000000`.
- 2026-07-10: Current initramfs boot reaches OpenWrt, Wi-Fi STA gets
  `192.168.1.57`, `br-lan` is `192.168.8.1/24`, and DSA ports are
  `lan1 lan2 lan3 wan`. Ethernet still does not pass host traffic: DHCP on the
  host times out, static `192.168.8.2` cannot ping `192.168.8.1`, and counters
  show LAN link/RX inconsistencies. Avoid running multiple tcpdump instances in
  initramfs; RAM pressure caused OOM kills of `netifd`/`wpa_supplicant`.
