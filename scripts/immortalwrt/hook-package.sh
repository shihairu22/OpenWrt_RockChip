#!/bin/bash
# Set to local prepare

mirror="https://raw.githubusercontent.com/sbwml/r4s_build_script/refs/heads/master"
github="github.com"
gitea="git.cooluc.com"

# autocore
rm -rf package/emortal/autocore
git clone https://github.com/shihairu22/autocore-arm -b openwrt-25.12 package/emortal/autocore

# default settings
rm -rf package/emortal/default-settings
git clone https://github.com/shihairu22/default-settings -b openwrt-25.12 package/emortal/default-settings

# custom packages
rm -rf customfeeds/luci/applications/{luci-app-filebrowser,luci-app-argon-config}
rm -rf customfeeds/luci/themes/luci-theme-argon
rm -rf customfeeds/packages/net/shadowsocks-libev

rm -rf customfeeds/packages/net/{*alist,chinadns-ng,dns2socks,dns2tcp,lucky,sing-box}

# Update golang
rm -rf customfeeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang customfeeds/packages/lang/golang

# Docker
rm -rf customfeeds/luci/applications/luci-app-dockerman
git clone https://github.com/sbwml/luci-app-dockerman -b openwrt-25.12 customfeeds/luci/applications/luci-app-dockerman
rm -rf customfeeds/packages/utils/{docker,dockerd,containerd,runc}
git clone https://github.com/sbwml/packages_utils_docker customfeeds/packages/utils/docker
git clone https://github.com/sbwml/packages_utils_dockerd customfeeds/packages/utils/dockerd
git clone https://github.com/sbwml/packages_utils_containerd customfeeds/packages/utils/containerd
git clone https://github.com/sbwml/packages_utils_runc customfeeds/packages/utils/runc

# containerd 2.4.1 的 vendor/github.com/urfave/cli/v3 用 //go:embed autocomplete 引用
# 4 个「没有扩展名」的补全脚本；而 golang-build.sh 的 configure 只把「源码类文件
# (*.c/*.cc/*.cpp/*.go/*.h/*.hh/*.hpp/*.proto/*.s) + testdata + go.mod/sum/work +
# GO_PKG_INSTALL_EXTRA 里点名的文件」搬进 .go_work/build/src，这 4 个文件全部不符合，
# 目录被漏掉 → 编译报 "pattern autocomplete: no matching files found"（实测 2026-10-09）。
# 按 golang-package.mk 第 184 行 GO_INSTALL_EXTRA="$(GO_PKG_INSTALL_EXTRA)" 的机制，
# 在清单里补一条模式即可命中这 4 个文件；grep 守卫保证幂等。
CTR_MK=customfeeds/packages/utils/containerd/Makefile
if ! grep -q 'urfave/cli/v3/autocomplete/' "$CTR_MK"; then
  sed -i 's|^GO_PKG_INSTALL_EXTRA:=\\$|&\n\tvendor/github.com/urfave/cli/v3/autocomplete/ \\|' "$CTR_MK"
fi

# samba4 - bump version
# rm -rf customfeeds/packages/net/samba4
# git clone https://github.com/sbwml/feeds_packages_net_samba4 customfeeds/packages/net/samba4
# enable multi-channel
sed -i '/workgroup/a \\n\t## enable multi-channel' customfeeds/packages/net/samba4/files/smb.conf.template
sed -i '/enable multi-channel/a \\tserver multi channel support = yes' customfeeds/packages/net/samba4/files/smb.conf.template
# default config
sed -i 's/#aio read size = 0/aio read size = 0/g' customfeeds/packages/net/samba4/files/smb.conf.template
sed -i 's/#aio write size = 0/aio write size = 0/g' customfeeds/packages/net/samba4/files/smb.conf.template
sed -i 's/invalid users = root/#invalid users = root/g' customfeeds/packages/net/samba4/files/smb.conf.template
sed -i 's/bind interfaces only = yes/bind interfaces only = no/g' customfeeds/packages/net/samba4/files/smb.conf.template
sed -i 's/#create mask/create mask/g' customfeeds/packages/net/samba4/files/smb.conf.template
sed -i 's/#directory mask/directory mask/g' customfeeds/packages/net/samba4/files/smb.conf.template
sed -i 's/0666/0644/g;s/0744/0755/g;s/0777/0755/g' customfeeds/luci/applications/luci-app-samba4/htdocs/luci-static/resources/view/samba4.js
sed -i 's/0666/0644/g;s/0777/0755/g' customfeeds/packages/net/samba4/files/samba.config
sed -i 's/0666/0644/g;s/0777/0755/g' customfeeds/packages/net/samba4/files/smb.conf.template

# xdp-tools
rm -rf package/network/utils/xdp-tools
git clone --depth 1 https://github.com/sbwml/package_network_utils_xdp-tools package/network/utils/xdp-tools

# clang
# netatop
sed -i 's/$(MAKE)/$(KERNEL_MAKE)/g' customfeeds/packages/admin/netatop/Makefile
curl -s $mirror/openwrt/patch/packages-patches/clang/netatop/900-fix-build-with-clang.patch > customfeeds/packages/admin/netatop/patches/900-fix-build-with-clang.patch
# dmx_usb_module
rm -rf customfeeds/packages/libs/dmx_usb_module
git clone https://git.cooluc.com/sbwml/feeds_packages_libs_dmx_usb_module customfeeds/packages/libs/dmx_usb_module
# macremapper
# curl -s https://raw.githubusercontent.com/xuanranran/r4s_build_script/refs/heads/6.6/openwrt/patch/packages-patches/clang/macremapper/100-macremapper-fix-clang-build.patch | patch -p1
# coova-chilli module
rm -rf customfeeds/packages/net/coova-chilli
git clone https://$github/sbwml/kmod_packages_net_coova-chilli customfeeds/packages/net/coova-chilli

# nat46
mkdir -p package/kernel/nat46/patches
curl -s $mirror/openwrt/patch/packages-patches/nat46/102-fix-build-with-kernel-6.18.patch > package/kernel/nat46/patches/102-fix-build-with-kernel-6.18.patch

# openvswitch
sed -i '/ovs_kmod_openvswitch_depends/a\\t\ \ +kmod-sched-act-sample \\' customfeeds/packages/net/openvswitch/Makefile

# rtpengine
curl -s $mirror/openwrt/patch/packages-patches/rtpengine/901-fix-build-for-linux-6.18.patch > customfeeds/telephony/net/rtpengine/patches/901-fix-build-for-linux-6.18.patch

# usb-serial-xr_usb_serial_common: remove package
# Now that we have packaged the upstream driver[1] and only board[2] that
# includes it by default has been switched to it, remove this out-of-tree
# driver that is broken on 6.12 anyway.
rm -rf customfeeds/packages/libs/xr_usb_serial_common

# v4l2loopback
rm -rf customfeeds/packages/kernel/v4l2loopback
mkdir -p customfeeds/packages/kernel/v4l2loopback
curl -s $mirror/openwrt/patch/packages-patches/v4l2loopback/Makefile > customfeeds/packages/kernel/v4l2loopback/Makefile

# telephony
pushd customfeeds/telephony
  # dahdi-linux
  rm -rf libs/dahdi-linux
  git clone https://$github/sbwml/feeds_telephony_libs_dahdi-linux libs/dahdi-linux -b v6.18
popd

# boots
sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=@SF/$(PKG_NAME)/$(PKG_NAME)/$(PKG_VERSION)|g' customfeeds/packages/libs/boost/Makefile

# fix gcc-15.0.1 gnu17

# xl2tpd
sed -i '/ifneq (0,0)/i TARGET_CFLAGS += -std=gnu17\n' customfeeds/packages/net/xl2tpd/Makefile

# fix gcc-16.1.0
# elfutils lto
curl -s $mirror/openwrt/patch/packages-patches_gcc16/elfutils/900-fix-gcc16-null-dereference-with-lto.patch > package/libs/elfutils/patches/900-fix-gcc16-null-dereference-with-lto.patch
# bash
sed -i "/PKG_INSTALL:=/i\PKG_BUILD_FLAGS:=no-lto" customfeeds/packages/utils/bash/Makefile
# quectel-cm
mkdir -p customfeeds/packages/net/quectel-cm/patches
cp -f $GITHUB_WORKSPACE/data/patches/quectel-cm/030-gcc16.patch customfeeds/packages/net/quectel-cm/patches/030-gcc16.patch

sed -i '/^CONFIG_PAGE_POOL=y$/a CONFIG_SHORTCUT_FE=y' target/linux/rockchip/armv8/config-6.18

# libnftnl
rm -rf package/libs/libnftnl/patches
# nftables
rm -rf package/network/utils/nftables/patches

# del packages
rm -rf customfeeds/packages/net/onionshare-cli
rm -rf package/emortal/cpufreq
