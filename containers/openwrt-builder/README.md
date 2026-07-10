# OpenWrt Builder

Docker build image used by the main OpenWrt workflow.

- invoked by `./start.sh docker`
- built from `containers/openwrt-builder/Dockerfile`
- keeps the OpenWrt build dependencies isolated from recovery tooling
