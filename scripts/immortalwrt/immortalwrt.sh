#!/bin/bash
# Clone community packages to package/community
mkdir package/community
pushd package/community

# Add openwrt-packages
git clone --depth=1 https://github.com/shihairu22/openwrt-package openwrt-package
git clone --depth=1 https://github.com/shihairu22/rely openwrt-rely
git clone --depth=1 https://github.com/sbwml/wwan-packages wwan-packages
popd

# Update OpenClash Panel
pushd customfeeds/lovepackages/luci-app-openclash/root/usr/share/openclash/ui/
rm -rf yacd zashboard metacubexd/*
curl -sSL https://codeload.github.com/haishanh/yacd/zip/refs/heads/gh-pages -o yacd-dist-cdn-fonts.zip
curl -sSL https://github.com/MetaCubeX/metacubexd/releases/latest/download/compressed-dist.tgz -o compressed-dist.tgz
curl -sSL https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages-cdn-fonts.zip -o dist-cdn-fonts.zip
tar zxf compressed-dist.tgz -C ./metacubexd
unzip -q dist-cdn-fonts.zip && unzip -q yacd-dist-cdn-fonts.zip
mv zashboard-gh-pages-cdn-fonts zashboard && mv yacd-gh-pages yacd
rm -rf yacd-dist-cdn-fonts.zip dist-cdn-fonts.zip compressed-dist.tgz
popd

# Change default shell to zsh
sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd

# Modify default IP
sed -i 's/192.168.1.1/192.168.11.1/g' package/base-files/files/bin/config_generate
sed -i "s/ImmortalWrt/OpenWrt/g" package/base-files/files/bin/config_generate

# 修改开源站地址 (按内容删除国内镜像, 避免行号漂移破坏 JSON)
sed -i '\#mirror.iscas.ac.cn/kernel.org#d; \#mirrors.ustc.edu.cn/kernel.org#d; \#mirror.nju.edu.cn/kernel.org#d; \#mirrors.ustc.edu.cn/gnome#d; \#mirror.nju.edu.cn/gnome#d' scripts/projectsmirrors.json

# Prefer the MIT kernel mirror for the New York runner
sed -i '/"@KERNEL": \[/,/]/ {
  s#"https://cdn.kernel.org/pub"#"https://kernel-mirror-placeholder"#
  s#"https://mirrors.mit.edu/kernel"#"https://cdn.kernel.org/pub"#
  s#"https://kernel-mirror-placeholder"#"https://mirrors.mit.edu/kernel"#
}' scripts/projectsmirrors.json

# Prefer the official Samba source; keep other mirrors as fallbacks
samba_makefile="customfeeds/packages/net/samba4/Makefile"
if [ -f "$samba_makefile" ]; then
  sed -i '\#https://download.samba.org/pub/samba/stable/#d; \#https://www.nic.funet.fi/index/samba/pub/samba/stable/#s/[[:space:]]*\\$//; /^PKG_SOURCE_URL:= \\/a\        https://download.samba.org/pub/samba/stable/ \\' "$samba_makefile"
fi

sed -i 's/services/network/g' customfeeds/luci/applications/luci-app-upnp/root/usr/share/luci/menu.d/luci-app-upnp.json
sed -i 's/services/vpn/g' customfeeds/luci/applications/luci-app-frpc/root/usr/share/luci/menu.d/luci-app-frpc.json
sed -i 's/services/network/g' customfeeds/luci/applications/luci-app-3cat/root/usr/share/luci/menu.d/luci-app-3cat.json
sed -i 's/services/vpn/g' customfeeds/luci/applications/luci-app-tailscale-community/root/usr/share/luci/menu.d/luci-app-tailscale-community.json

# other
rm -rf package/base-files/files/etc/banner
cp -f $GITHUB_WORKSPACE/data/banner package/base-files/files/etc/banner

# Add private cnspeedtest packages
rm -rf package/community/openwrt-cnspeedtest
if [ -z "$CNSPEEDTEST_TOKEN" ]; then
  echo "CNSPEEDTEST_TOKEN is not configured; skipping private cnspeedtest packages"
else
  CNSPEEDTEST_AUTH="$(printf 'x-access-token:%s' "$CNSPEEDTEST_TOKEN" | base64 | tr -d '\n')"
  GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0=http.https://github.com/.extraheader \
  GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $CNSPEEDTEST_AUTH" \
  git clone --depth=1 --branch main \
    https://github.com/shihairu22/openwrt-cnspeedtest.git \
    package/community/openwrt-cnspeedtest
  unset CNSPEEDTEST_AUTH
fi

# ── 修复 rockchip 显示驱动整族被丢（2026-10-09）───────────────────────────────
# 上游把 rockchip 的 DRM 包写成依赖 +kmod-fb，而 kmod-fb 只存在于 bcm27xx / sunxi /
# x86 这些 FBDEV 目标（package/kernel/linux/modules/video.mk 里的 FBDEV_TARGETS）。
# 依赖一传播，整套 DRM（含 HDMI 输出）在 rockchip 上就被判成「不可用」而全部丢掉，
# 且不报错。这里只去掉这一个错的依赖，让 DRM 家族重新可见；不改其它目标的行为。
if [ -f target/linux/rockchip/modules.mk ]; then
  sed -i '/^define KernelPackage\/drm-rockchip$/,/^endef$/ s/ +kmod-fb$//' target/linux/rockchip/modules.mk
  if grep -q '+kmod-fb' target/linux/rockchip/modules.mk; then
    echo "::warning::rockchip DRM 的 +kmod-fb 错依赖没能去掉，显示驱动可能仍被丢弃"
  else
    echo "[fix-drm] rockchip DRM 的 +kmod-fb 错依赖已去掉"
  fi
fi

# ── 修复 kmod-drm-kms-helper 打包检查报 fb.ko 缺失（2026-10-09）─────────────────
# 上面去掉了 +kmod-fb 错依赖后，rockchip 的 DRM 家族重新可见，于是暴露第二个问题：
# drm-rockchip 的 KCONFIG 开了 CONFIG_DRM_FBDEV_EMULATION=y，它会让内核把帧缓冲核心
# 选成模块（CONFIG_FB_CORE=m）→ 内核多出一个 fb.ko，drm_kms_helper.ko 就依赖它；
# 而 fb.ko 只有 kmod-fb 提供，kmod-fb 又只存在于 FBDEV 目标（不含 rockchip）→
# 打包检查直接失败：Package kmod-drm-kms-helper is missing dependencies ... fb.ko
# （在 CI 里被 IGNORE_ERRORS=1 吞掉，只留下一句 package/kernel/linux failed to build）。
# 修法照 x86 / bcm27xx 的做法：在目标内核配置里把帧缓冲核心写成内建，内建就不再产生
# fb.ko，依赖自然消失；顺带把帧缓冲文本控制台（HDMI 上能看内核日志）一起打开。
KCFG=target/linux/rockchip/armv8/config-6.18
if [ -f "$KCFG" ] && ! grep -q '^CONFIG_FB_CORE=y' "$KCFG"; then
  cat >> "$KCFG" <<'FBEOF'
CONFIG_FB=y
CONFIG_FB_CORE=y
CONFIG_FB_DEVICE=y
CONFIG_FB_DEFERRED_IO=y
CONFIG_FB_SYSMEM_FOPS=y
CONFIG_FB_SYSMEM_HELPERS=y
CONFIG_FB_SYSMEM_HELPERS_DEFERRED=y
CONFIG_FB_SYS_COPYAREA=y
CONFIG_FB_SYS_FILLRECT=y
CONFIG_FB_SYS_IMAGEBLIT=y
CONFIG_FONT_8x16=y
CONFIG_FONT_8x8=y
CONFIG_FONT_SUPPORT=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y
CONFIG_FRAMEBUFFER_CONSOLE_ROTATION=n
CONFIG_CONSOLE_TRANSLATIONS=y
CONFIG_VT=y
CONFIG_VT_CONSOLE=y
CONFIG_VT_HW_CONSOLE_BINDING=y
FBEOF
  echo "[fix-fb] rockchip 帧缓冲核心已改为内建（消掉 fb.ko 依赖，并开启文本控制台）"
fi
