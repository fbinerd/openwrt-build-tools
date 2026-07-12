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

- 2026-07-12: User reported the `probe-vlan2-fixed` image sometimes obtains
  DHCP and pings, but after reload both `eth1.1` and `eth1.2` become
  inaccessible; `eth1.3`/`eth1.4` never work. Root cause is the diagnostic
  overlay still creating many DHCP clients (`eth1.1` through `eth1.5`) and
  competing routes/ubus events. Runtime stable config was applied on the
  router: only `lan` static on `eth1.1` (`192.168.8.1/24`, DHCP server) and
  `wan` DHCP on `eth1.2` (metric 20), plus `wwan` metric 10. VLANs remain
  `1 2 3 6t` for LAN and `0 6t` for WAN. Runtime test showed `lan` up and
  `wan` obtained lease `192.168.1.95` from `192.168.1.254`. The ignored local
  overlay `openwrt/files/etc/uci-defaults/99_mr80x-v5-ethernet-dhcp-probe`
  was changed to this stable LAN/WAN layout; despite the filename, it is no
  longer a VLAN probe. New artifacts tagged `stable-lan-wan`:
  initramfs ITB
  `72005538f0753d4bd51099092b2eddf611aebc74faedd838352566e66ba30226`,
  factory UBI
  `fa64c527edeebab71e6800639933a8c17f7f09a1c35ac60e9474347f357d0e76`,
  sysupgrade
  `759f37401da9c8084b0aeff1b662587545ac925abc17bb07fb6a972b8e0e0b41`.
  Note: do not expect `eth1.3`/`eth1.4` to work on this hardware; MR80X v5
  has only LAN1-LAN3 and WAN in the confirmed mapping.
- 2026-07-12: User booted `egress-tag-original` and reported LAN1/LAN2/LAN3
  get DHCP on `eth1.1`, while physical WAN still had no lease. Runtime
  inspection proved this was not a driver failure: `port0` had physical link
  up at 1 Gbps, but VLAN 2 was empty and `port0 pvid=0` because the local
  diagnostic overlay `openwrt/files/etc/uci-defaults/99_mr80x-v5-ethernet-dhcp-probe`
  deletes all UCI switch sections. Manually programming
  `vlan1 ports '1 2 3 6t'`, `vlan2 ports '0 6t'`, and `port0 pvid 2`
  immediately let `udhcpc -i eth1.2` obtain `192.168.1.53` from
  `192.168.1.254`; `eth1.2` RX counters increased. Conclusion: RTL8367S
  CPU-port egress/tagging and the physical WAN mapping (`0:wan`) are working
  in this image. Do not repeat low-level RTL8367S/SGMII debugging for this
  specific WAN symptom. Next build must either remove the diagnostic overlay
  entirely for a normal image, or include explicit `switch0` UCI sections with
  VLAN 1 LAN and VLAN 2 WAN. Also, for U-Boot TFTP use only the two short
  command lines requested by the user:
  `setenv ipaddr 192.168.6.1 && setenv serverip 192.168.6.83`
  and
  `tftpboot 0x44000000 <image>.itb && bootm 0x44000000`.
  The ignored local overlay was edited accordingly: it now recreates
  `switch0`, VLAN 1 as `1 2 3 6t`, and VLAN 2 as `0 6t` before starting the
  diagnostic DHCP clients. Rebuilt artifacts tagged `probe-vlan2-fixed`:
  initramfs ITB
  `06923db0373c754bb3f9c6f72c7a0d41b1addd9a2856e3f9f52d06a8d57b5951`,
  factory UBI
  `e20261d3e9d3c9acbf846e3c20f70768f3e98b371a0b98f3088a43dddf47d743`,
  sysupgrade
  `0715eac36257808a8f24990786eff2ae05c86040746b308aa28d3cf52216ccca`.
  This image was booted successfully with the two-line U-Boot flow. Validation
  on the router confirmed `swconfig vlan 1 -> 1 2 3 6t`, `vlan 2 -> 0 6t`,
  `port0 pvid=2`, and `dhcp_eth1_2` obtained lease `192.168.1.94` from
  `192.168.1.254`. The diagnostic image still also lets `dhcp_eth1_1` get a
  lease if the upstream network is plugged into a LAN port; that is expected
  for the probe overlay, not the final production LAN behavior.
- 2026-07-11: Booted `literal-portmap` and confirmed the previous
  `hwport=255` corruption is gone. Runtime now shows direct PVID reads/writes
  with correct hwports and `eth1` receives real frames, but `eth1.1` and
  `eth1.2` RX remain zero. `tcpdump` showed DHCP offers arriving untagged on
  parent `eth1`, while OpenWrt DHCP discovers leave through VLAN subinterfaces.
  Therefore do not keep chasing basic VLAN membership/PVID for this stage:
  the next likely blocker is CPU-port egress tag handling. OpenWrt commit
  `29d4e3ff9d` changes RTL8367S init to set EXT0/CPU egress tag mode back to
  `EG_TAG_MODE_ORI` and clears `VlanEgressKeep` instead of forcing `0x7ff`.
  Built test artifacts tagged `egress-tag-original` in
  `/home/fabiano/opw/openwrt/bin/targets/qualcommax/ipq50xx/`:
  initramfs ITB
  `4bea364e80b5e98ada0bd19b2de6e864ceb045025c77e88a20716d0164dd8a7a`,
  factory UBI
  `12af69597cc78afcefc67d98df209dd1d62d846e79fbebcd07015fc9e0223913`,
  sysupgrade
  `736c0579b619c4acc5bd67e25e191f7a9852ac09617aa0e6b81a0c32c99a78ca`.
  On boot, check dmesg for `vlan egress tag ... ori ret=0`,
  `vlan egress keep clear ... ret=0`, and `egress keep get ... val=0x0`.
  Then test whether DHCP offers move from untagged parent `eth1` into
  `eth1.2`; if not, test CPU port tag mode `EG_TAG_MODE_KEEP` or
  `EG_TAG_MODE_REAL_KEEP` as the next isolated image.
- 2026-07-11: Router was rebooted and stopped at U-Boot, but automated serial
  TX stopped working after the broker reset. The prompt was visible in the old
  log as `IPQ5018#`, but neither the broker socket, direct write inside the
  `serial_ttyUSB0` container, nor a one-shot root `python:3.12-slim` container
  opening `/dev/ttyUSB0` could get `printenv`/`help` responses. Do not assume
  the new `egress-tag-original` image was booted yet. Manual U-Boot commands
  to boot it are:
  `setenv ipaddr 192.168.6.1`,
  `setenv serverip 192.168.6.83`,
  `setenv netmask 255.255.255.0`,
  `setenv tftpblocksize 1468`,
  `setenv tftptimeout 3000`,
  `setenv tftptimeoutcountmax 10`,
  `tftpboot 0x44000000 openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-initramfs-uImage-egress-tag-original.itb`,
  `bootm 0x44000000`.
- 2026-07-11: The old sysupgrade suspected by the user was converted to
  `/home/fabiano/opw/openwrt/bin/targets/qualcommax/ipq50xx/mr80x-v5-old-eth-test-rootfs.ubi`
  with OpenWrt's own `scripts/ubinize-image.sh` and flashed successfully from
  U-Boot via `flash rootfs 0x44000000 $filesize`. It boots from NAND and
  creates `eth1.1`/`eth1.2`, but it did not reliably reproduce working
  Ethernet. The important clue is in the logs: during swconfig VLAN setup,
  `rtl8367s: get/set pvid ... hwport=255` and `rtk_vlan_set failed ret=15`
  appear. That means the Realtek switch API path can leave Linux VLAN devices
  UP while the ASIC VLAN table is not programmed. Current OpenWrt branch
  `codex-mr80x-v5-ethernet-debug` now patches `rtl8367s.c` to avoid
  `rtk_switch_port_L2P_get()` for direct PVID writes, use an explicit
  swconfig-to-ASIC physical port map `{0,1,2,3,4,7,6}`, and fallback to direct
  `rtl8367c_setAsicVlan4kEntry()` when `rtk_vlan_set()` fails. The package
  `package/kernel/rtl8367s-vendor/compile` passed in Docker after this change.
  Full Docker build also passed. Test artifacts:
  initramfs ITB
  `ce1433034861a4f987d44d4ce861768c7f423b7bf50c38f7c0bd171d54d32747`,
  factory UBI
  `1a8503433f340e6e7aecd9d7dcbe113f8ebc8f20071dc5b131e56f4624560808`,
  sysupgrade
  `4a4fb2a717e9d0378ca29885961e6270e593b6b9de2a2bbfc151ac7a1711dc1b`.
- 2026-07-11: Initramfs `2b826be3...` carregou por TFTP e confirmou que
  `ptype ext0 tag-only` aplica com sucesso, mas `rtk_vlan_portPvid_set()`
  ainda volta `RT_ERR_OK` enquanto `rtk_vlan_portPvid_get()` le imediatamente
  `pvid=0`. Isso elimina a hipotese de ser apenas exibicao ruim do swconfig.
  O novo material em `source_codes_to_analize/rtl83xx` mostra que o caminho
  RTL8367D grava PVID diretamente em `0x0700 + porta_fisica` com mascara
  `0x0fff`, diferente do caminho RTL8367C/CVIDX usado no nosso driver. Patch
  experimental em `rtl8367s.c` agora testa PVID direto estilo RTL8367D.
- 2026-07-11: Booted MR80X v5 initramfs
  `653d12f7c9cc77723074274f16da9e83c71f92f31370ffb99166c23576d8e5ad`
  after switching the swconfig CPU mapping to `6@eth1`. This is a useful
  direction because it matches OEM runtime: OpenWrt created `br-lan` on
  `eth1.1`, WAN on `eth1.2`, and `nss-dp` reported `eth1` link up at 1 Gbps.
  Ethernet still failed: `eth1`/`eth1.1`/`br-lan` RX stayed at zero, ARP for
  `192.168.8.30` stayed incomplete, and `swconfig dev switch0 show` displayed
  correct VLAN membership but all PVIDs stayed `0`. Runtime `swconfig port ...
  set pvid` also did not stick. New sources under
  `tools/firmware-lab/work/source_codes_to_analize` show TP-Link/Realtek
  examples creating VLANs with `rtk_vlan_set` before `rtk_vlan_portPvid_set`
  and treating any `ret != RT_ERR_OK` as failure. Current OpenWrt edit changes
  `rtl8367s.c` to log/convert positive Realtek API errors and apply PVID only
  after VLAN creation.
- 2026-07-11: Booted latest MR80X v5 initramfs after OpenWrt commit
  `e0a76b3121` (`qca-nss-dp` module sha256
  `42e454ba26d8f9c7a316ad1df596a96838718acde1deb84efb771150fa1a6f13`,
  initramfs sha256
  `ad2bc8153e8442244e06fe7ca3fae41bcdb059ad9329e33888f2b8d03eb63b59`).
  Negative Ethernet test: `nss-dp 39d00000.dp2 eth0` links up at 1 Gbps,
  Realtek init returns 0, physical ports 2/3 and switch CPU port 6 count
  packets, but Linux `eth0`, `eth0.1`, `eth0.2`, and `br-lan` RX remain zero.
  Ping to `192.168.8.30` fails with an incomplete neighbor. This means the
  QCA GMAC flow-control write alone is not enough. Next test mirrors U-Boot
  more closely by changing the vendor RTL8367S init so EXT_PORT1 is also forced
  to HSGMII/2500 with SGMII autoneg disabled, instead of RGMII/1000.
- 2026-07-11: Booted MR80X v5 initramfs
  `b1b1f01680a36736835a6d92145dd00a0e52ddae2b1ecb811817d73d597b4c95`
  after switching QCA ESS to `MAC_MODE_SGMII_PLUS`. Realtek init became
  consistently clean: `ext0 sgmii nway off`, `ext0 hsgmii force`, and ASIC
  reset `0x1322=0x2` returned 0 even after swconfig resets. The link still did
  not pass Ethernet: ARP TX from Linux was visible on `eth0` as VLAN 2 and on
  `eth0.2` untagged, but no ARP replies reached Linux. `eth0` RX improved only
  to 214 bytes/1 packet, while `eth0.2`/`br-lan` stayed at zero. Runtime PVID
  changes through swconfig did not fix it. New source material in
  `tools/firmware-lab/work/source_codes_to_analize/rtl83xx` confirms OEM-style
  Realtek setup is EXT_PORT0/HSGMII/2500 and `ptype set 16 1` is only VLAN
  accept-frame type for the CPU port, not a special CPU-port command. The next
  test aligns the QCA `dp2` fixed-link speed from 1000 to 2500, because the
  current DTS had `switch_mac_mode = MAC_MODE_SGMII_PLUS` plus
  `forced-speed = 2500` on the switch side but still forced the Linux MAC link
  to 1 Gbps.
- 2026-07-11: Built MR80X v5 after aligning `dp2.fixed-link` to 2500 Mbps.
  Test artifacts in `/home/fabiano/opw/openwrt/bin/targets/qualcommax/ipq50xx/`:
  initramfs ITB
  `8ff2899108de093c96b8cd2bc9d72f19c2f724177218e679af7a1b1635359de0`,
  factory UBI
  `e74f27cf9daf8d012db2a06b48fcea505f0e096bab61c72d40b666e9774cdfd0`,
  sysupgrade
  `5b1a2bf60f9dc291538a20433f8c11b150dd2c261c1c6a165a471e5feac6a6ff`.
  TFTP container `recovery-lab-tftp-server-1` is up on UDP/69 and serves the
  same target directory, so U-Boot can request
  `openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-initramfs-uImage.itb`.
- 2026-07-11: Booted the 2500 Mbps fixed-link test image
  `8ff2899108de093c96b8cd2bc9d72f19c2f724177218e679af7a1b1635359de0`.
  It is a negative test: `nss-dp` failed to probe with
  `dp2: fail to register fixed-link: -22` and no `eth0` netdev was created.
  Do not repeat `fixed-link { speed = <2500>; }` on MR80X v5 with the current
  `nss-dp` driver. Revert `dp2.fixed-link` to 1000 and continue with the OEM
  runtime write candidate `devmem 0x39D00018 32 0xFFFF0004` / QCA GMAC register
  comparison instead.
- 2026-07-11: Booted initramfs
  `b8015b5d63d876bac4c15bfb2a5e6ee1bceb0282bd7005c1eec30eb8f78ae851`.
  The RTL8367S side is now much healthier: first init showed
  `rtk_switch_init`, VLAN reset/init, `ext0 sgmii nway off`, HSGMII force,
  ASIC reset `0x1322=0x2`, EXT1 RGMII force/delay, and PHY enable all returning
  0. Runtime `swconfig dev switch0 show` showed physical ports 2 and 3 with
  link/counters, and CPU swconfig port 6 also had MIB traffic. However Linux
  `eth0`, `eth0.1`, `eth0.2`, and `br-lan` RX counters stayed at 0. Therefore
  do not keep debugging basic Realtek MDIO/VLAN first; the remaining blocker is
  likely QCA NSS/GMAC/SerDes mode. OEM FDT has `switch_mac_mode = <0x0c>`,
  which maps to `MAC_MODE_SGMII_PLUS`, while OpenWrt DTS still had
  `MAC_MODE_SGMII_CHANNEL0`. Commit `d13f6bcfbc` changes MR80X v5 to
  `MAC_MODE_SGMII_PLUS`. Built test artifacts:
  initramfs ITB
  `b1b1f01680a36736835a6d92145dd00a0e52ddae2b1ecb811817d73d597b4c95`,
  factory UBI
  `d9ea03e58bb5c04053a329374601f2c3f80aea8bec86b351d1f4422909b44841`,
  sysupgrade
  `f9aeb6f1c97bc8750429a25baf9ad1ded13aafb0bb09293c35482cc39747441f`.
  Next boot must check if `eth0` RX starts counting; if yes, focus on LAN/WAN
  VLAN naming. If no, compare OEM `devmem 0x39D00018 32 0xFFFF0004` and NSS DP
  driver setup.
- 2026-07-11: New material in
  `tools/firmware-lab/work/source_codes_to_analize/rtl83xx` corroborates the
  current RTL8367S direction: TP-Link code uses `EXT_PORT0` as `CPU_PORT`,
  forces `MODE_EXT_HSGMII` at 2500M, disables SGMII autonegotiation, and
  creates per-port VLANs with CPU port 16 tagged. It also exposes a reset path
  that writes ASIC register `0x1322 = 0x2` after SGMII/HSGMII configuration.
  OpenWrt commit in progress adds that internal reset to
  `rtl8367s_mdio.c`. Built test artifacts:
  module `rtl8367s_gsw.ko`
  `f1da083caca12c8bdde4c0fdfd1c483e7291890b270d5f52c2cd156a19f2f07f`,
  initramfs ITB
  `b8015b5d63d876bac4c15bfb2a5e6ee1bceb0282bd7005c1eec30eb8f78ae851`,
  factory UBI
  `ca7724b0fef7d5bf4ea67661e2f4f8077de4f47e816aa5ca9ff723cbd2d3eeab`,
  sysupgrade
  `b1ed684607c8ebaf1cde2a10b4464e0b11ec0195e0c39b3e00f32af5718f1241`.
  Next boot must check whether logs now show `rtl8367s ext0 sgmii nway off`,
  `rtl8367s ext0 hsgmii force`, and `rtl8367s ext0 sgmii reset reg 0x1322`
  all returning 0 before changing VLAN/topology again.
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
- 2026-07-11: New source material in
  `tools/firmware-lab/work/source_codes_to_analize/` reinforces the OEM
  Realtek path: `rtl83xx/src/extphysw.c` defines `CPU_PORT EXT_PORT0`, forces
  `EXT_PORT0` to `MODE_EXT_HSGMII` at `PORT_SPEED_2500M`, disables SGMII
  autoneg, then writes Realtek register `0x1322 = 0x2`. It also shows
  `ptype set <portid> <type>` is just `rtk_vlan_portAcceptFrameType_set()`;
  the OEM `ptype set 16 1` means CPU/EXT port accepts tagged frames only.
  Do not retest `dp2.fixed-link speed=<2500>`: OpenWrt `nss-dp` rejected it
  with `fail to register fixed-link: -22` and no `eth0`. Current viable hybrid
  test is Realtek HSGMII/SGMII_PLUS plus Linux `dp2` fixed-link 1G.
- 2026-07-11: Rebuilt `qca-nss-dp` after confirming the OEM-equivalent GMAC2
  flow-control patch existed but stale root modules were still used. The module
  hash now copied into `root-qualcommax`, `root.orig-qualcommax`, and staging is
  `e660fc309463f4e6b167742bc887b6e14b8adbe3c3dbb60ce974e7c20cf915e1`.
  Fresh MR80X v5 images in
  `/home/fabiano/opw/openwrt/bin/targets/qualcommax/ipq50xx/`:
  initramfs ITB
  `6d8760a280a643e7c447cdb66cea689678ece22e62692cb32803ce4daf1a9d32`,
  factory UBI
  `bda4562a6674c97fea5b2fcd236b2783731d26d718d712737b4bb6abd0f720a9`,
  sysupgrade
  `334a1213b32230c64fc10ef562f59d40e67bda0e9149362fc3903d4247889b19`.
  Next boot must check whether GMAC2 receives frames after this patch before
  changing VLAN topology again.
- 2026-07-11: Initramfs built from OpenWrt commit `c324cbdba1` with sha256
  `e03bf70196098d7788b052a5bdf189b00f40a76aa83deabd4244202a5d466944`
  did not fix Ethernet. The switch still saw physical link/counters, but Linux
  `eth0`, `eth0.1`, `eth0.2`, and `br-lan` RX stayed at zero and ping to
  `192.168.8.30` failed. The added EXT1 HSGMII calls logged `ret=3`, which is
  `RT_ERR_PORT_ID`; do not repeat the EXT1-HSGMII path with this driver. The
  next test restores EXT1 RGMII and instead aligns the OpenWrt topology with
  the OEM FDT/runtime by enabling `dp1` in SGMII so the Realtek conduit can be
  `eth1`, then configuring swconfig as `6@eth1`.
- 2026-07-11: Built the OEM-eth1-conduit test at OpenWrt commit `a76ec66709`.
  It restores EXT1 RGMII after the failed EXT1-HSGMII test, enables `dp1` as
  SGMII/fixed-link 1G, keeps `dp2` as SGMII/fixed-link 1G, and changes MR80X
  swconfig CPU mapping to `6@eth1`. Fresh image hashes in
  `/home/fabiano/opw/openwrt/bin/targets/qualcommax/ipq50xx/`: initramfs ITB
  `653d12f7c9cc77723074274f16da9e83c71f92f31370ffb99166c23576d8e5ad`,
  factory UBI `491cd3f37bb46b2b3ac4287862715f6a35ac3ec4c9d80acd9b1978860f456dae`,
  sysupgrade `3b40862936c2265159f65fab465a772070c3a5350f6e53b2787e9f0aa2125bf4`.
  On boot, first verify whether netdevs enumerate as `eth0`/`eth1` and whether
  `/etc/config/network` now references `eth1.1`/`eth1.2`; then check RX
  counters before changing switch VLANs again.
- 2026-07-11: The direct-PVID experiment fixed the visible PVID state:
  runtime logs show `direct` PVID writes/readbacks and `swconfig` now reports
  WAN port 0 as PVID 2 and LAN ports as PVID 1. Ethernet still does not pass
  useful traffic: DHCP on `eth1.1`, `eth1.2`, and an OEM-style `eth1.4094`
  test failed, while RX counters appeared on `eth1.1`/`eth1.4` but `br-lan`
  did not forward. Do not retest the old CVIDX PVID path; it read back 0.
  Current next patch explicitly disables proprietary RTL CPU-tag, clears the
  CPU-tag aware portmask, sets insert mode to "none", and enables VLAN egress
  keep on EXT_PORT0/CPU so Linux receives ordinary 802.1Q tags.
- 2026-07-11: Returned OpenWrt to latest `codex-mr80x-v5-ethernet-debug`
  and clean-rebuilt the RTL8367S vendor package after commit `9a5aa6294e`.
  The previous `vlan4k-fallback` image was stale and still logged `phyport`;
  ignore that boot as invalid. Clean artifacts in
  `/home/fabiano/opw/openwrt/bin/targets/qualcommax/ipq50xx/` are:
  initramfs ITB
  `1f1ac4cd62a96a64d3d11e1f9fa69c3af013215de5e7d9ffb34ec952dcf290e2`,
  factory UBI
  `d91931e26054443d216c6ff2da4724c949eb7aed02b44d6336de77d7968d2cbf`,
  sysupgrade
  `87f521a97c8091c5d0dbdb2b75d91e8ca448f408b790e922404f66d8cacfa60a`.
  `strings` on `rtl8367s_gsw.ko` confirms `hwport`, `direct pvid`, and
  `vlan4k fallback` strings are present. Router is currently stopped at
  U-Boot, but automated TX via recovery-lab broke after the USB serial
  adapter re-enumerated from `/dev/ttyUSB0` to `/dev/ttyUSB1`: broker/read
  works from old logs, but new writes produce no new output. Recreate the TTL
  session or type the TFTP commands manually before testing this clean image.
- 2026-07-11: Booted the clean `vlan4k-fallback-clean` image. It still did not
  restore Ethernet. Current-boot checks showed `eth1`, `eth1.1`, and `eth1.2`
  TX increasing but RX stuck at zero. `swconfig` later reported all PVIDs as
  4095 and dmesg showed `get pvid ... hwport=255`, even though early boot
  PVID writes initially logged correct hwports. To eliminate possible mutable
  table corruption, OpenWrt commit `e726e45fac` replaces the port-map arrays
  with literal `switch` helpers. Fresh artifacts tagged `literal-portmap`:
  initramfs ITB
  `87e384336978db3752b8ef1c261ebd4d0fbbb4043353ed12fefc7428f651e7fb`,
  factory UBI
  `5b80795c4e09df326c61db75b4c363c02f8dfb536fa9ca0d03f53be83eb7154d`,
  sysupgrade
  `7bbbc3cdfeeff72b9a5720a69730415e22169d5ed4f5a7460ab348b526669cbf`.
  Next test must boot `openwrt-qualcommax-ipq50xx-mercusys_mr80x-v5-initramfs-uImage-literal-portmap.itb`
  and check whether `hwport=255` disappears. If it disappears but RX remains
  zero, stop chasing swconfig PVID and return to GMAC/SGMII/CPU-port path.
