#!/bin/bash
# 让 .config 收敛：反复「把要求开启的符号贴回 .config + 重跑 make defconfig」，直到解析结果不再变化。
#
# 背景：OpenWrt 的 kconfig 从「稀疏配置」起步（.config 只写了几百行、绝大多数符号没有值）时，
# 会把一部分明确 =y 的符号解析成 n —— 本仓库遇到的是 rockchip 的 DRM 家族（依赖链长，且上游
# 存在循环依赖告警）。跑第二遍、第三遍就稳定下来了；不收敛的话这些包会静默消失，
# 固件里既没有显示驱动也没有报错。
#
# 用法: cfg-converge.sh <要求的配置文件> <源码树> [最大轮数]
set -eu
REQ="$1"; TREE="$2"; MAX="${3:-3}"
CFG="$TREE/.config"
TMPD="$(mktemp -d -p "${RUNNER_TEMP:-/tmp}")"
trap 'rm -rf "$TMPD"' EXIT

grep -E '^CONFIG_[A-Za-z0-9_]+=[ym]$' "$REQ" > "$TMPD/req.txt" || true
echo "[cfg-converge] 要求开启的符号 $(wc -l < "$TMPD/req.txt") 个"
awk -F= '{print "/^" $1 "=/d"}'              "$TMPD/req.txt" >  "$TMPD/del.sed"
awk -F= '{print "/^# " $1 " is not set$/d"}' "$TMPD/req.txt" >> "$TMPD/del.sed"

# 比较「解析结果」而不是文件内容：贴回符号会改变行序，比内容会永远不稳定。
snap() { grep -E '^CONFIG_[A-Za-z0-9_]+=' "$CFG" | sort | sha256sum | awk '{print $1}'; }

for i in $(seq 1 "$MAX"); do
  before="$(snap)"
  sed -i -f "$TMPD/del.sed" "$CFG"
  cat "$TMPD/req.txt" >> "$CFG"
  ( cd "$TREE" && make defconfig ) > "$TMPD/defconfig.$i.log" 2>&1 || true
  after="$(snap)"
  if [ "$before" = "$after" ]; then echo "[cfg-converge] 第 $i 轮已稳定（收敛完成）"; break; fi
  echo "[cfg-converge] 第 $i 轮解析结果有变化，再跑一轮"
done
echo "[cfg-converge] 最终 =y/=m 符号数 $(grep -cE '^CONFIG_[A-Za-z0-9_]+=[ym]$' "$CFG")"
