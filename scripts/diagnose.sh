#!/bin/bash
# 只读诊断：定位 macOS「系统数据」的真实占用。
# 不做任何写操作。
#
# 用法：
#   ./diagnose.sh            # 概览 + 定向扫描
#   ./diagnose.sh deep       # 额外下钻 /private/var、~/Library、家目录

set -uo pipefail
MODE="${1:-normal}"
DENIED=$(mktemp)
trap 'rm -f "$DENIED"' EXIT

hr() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }

# du 但把权限拒绝记录到 DENIED，避免静默漏算
top() {  # top <dir> <n>
  local dir="$1" n="${2:-10}"
  du -sh "$dir"/* 2>>"$DENIED" | sort -rh | head -"$n"
}

hr "磁盘与容器"
df -h /System/Volumes/Data 2>/dev/null | tail -1
# df 的 GiB 与 diskutil 的 GB 口径不同，两者都打印便于交叉核对
USED_BYTES=$(df -k /System/Volumes/Data 2>/dev/null | tail -1 | awk '{print $3*1024}')
echo
diskutil info /System/Volumes/Data 2>/dev/null | grep -E "Volume Used Space|Container Free Space"
echo
echo "口径提醒：du 对 /System/Volumes/Preboot 等卷会重复计算 APFS 快照共享块，"
echo "          数值可远大于 diskutil 的 Volume Used Space。判断真实占用看 df/diskutil。"

hr "APFS 本地快照"
# tmutil 无快照时仍打印表头行，需过滤后才能判断
snaps=$(tmutil listlocalsnapshots / 2>/dev/null | grep -v '^Snapshots for' | sed '/^$/d')
if [ -n "$snaps" ]; then
  echo "$snaps" | sed 's/^/  /'
  echo "  → 有本地快照，可逐个 sudo tmutil deletelocalsnapshots <日期>，保留最新一个"
else
  echo "  （无本地快照，此项无可回收空间）"
fi

hr "家目录可见文件夹（先看这里）"
# 用户问"磁盘满了"时最大的答案通常在这，不在系统目录
top "$HOME" 12

hr "系统数据嫌疑目录"
for d in /private/var/folders /private/var/db /private/var/vm /private/var/log /private/tmp; do
  [ -d "$d" ] && printf '  %-8s %s\n' "$(du -sh "$d" 2>/dev/null | cut -f1)" "$d"
done

hr "用户临时目录 /private/var/folders"
# 每个用户一个随机目录：X/ 是代码签名克隆等残留，C/ 缓存，T/ 临时
du -sh /private/var/folders/*/*/ 2>/dev/null | sort -rh | head -5 | sed 's/^/  /'
echo
clones=$(du -sh /private/var/folders/*/*/X/* 2>/dev/null | sort -rh | head -10)
if [ -n "$clones" ]; then
  echo "  X/ 下的残留（code_sign_clone 常见于 MATLAB/Chrome/Edge 签名中断）："
  echo "$clones" | sed 's/^/    /'
  echo
  echo "    ⚠ 同源 code_sign_clone 是 APFS 写时复制克隆，共享底层数据块。"
  echo "      du 把共享块给每份各算一遍，总和虚高；必须整组删除后对比 df 才是真实收益。"
else
  echo "    （X/ 为空，无 code_sign_clone 残留）"
fi

hr "休眠镜像与交换"
ls -lh /private/var/vm/ 2>/dev/null | sed 's/^/  /'
echo "  sleepimage 删除后会在下次睡眠/重启重建，净收益通常接近 0。"

hr "统一日志（需 sudo 才能清理）"
du -sh /private/var/db/diagnostics /private/var/db/uuidtext 2>/dev/null | sed 's/^/  /'

hr "Preboot / Update 卷（勿手删）"
for d in /System/Volumes/Preboot /System/Volumes/Update; do
  [ -d "$d" ] && echo "  du 口径 $(du -sh "$d" 2>/dev/null | cut -f1)  $d"
done
diskutil info /System/Volumes/Preboot 2>/dev/null | grep "Volume Used Space" | sed 's/^/  diskutil 口径 /'
echo "  两者差额来自快照共享块重复计数，不是真实占用，不要清理。"

hr "~/Library 体积"
top "$HOME/Library" 12

hr "常见可回收项"
found=0
for p in \
  "$HOME/Library/Application Support/MobileSync" \
  "$HOME/Library/Developer/Xcode/DerivedData" \
  "$HOME/Library/Developer/CoreSimulator" \
  "$HOME/Library/Mail" \
  "$HOME/Library/Messages/Attachments" \
  "$HOME/Library/Python" ; do
  if [ -d "$p" ]; then
    sz=$(du -sh "$p" 2>/dev/null | cut -f1)
    printf '  %-8s %s\n' "${sz:-0B}" "$p"
    found=1
  fi
done
[ "$found" = 0 ] && echo "  （以上目录均不存在，对应清理项无收益）"

if [ "$MODE" = "deep" ]; then
  hr "深度：/private/var 一级子项"
  du -sh /private/var/* 2>>"$DENIED" | sort -rh | head -20 | sed 's/^/  /'
  hr "深度：~/Library 前 30"
  du -sh "$HOME/Library"/* 2>>"$DENIED" | sort -rh | head -30 | sed 's/^/  /'
  hr "深度：家目录隐藏目录前 20"
  du -sh "$HOME"/.[a-zA-Z]* 2>>"$DENIED" | sort -rh | head -20 | sed 's/^/  /'
fi

hr "权限盲区检查"
# 两种原因要分开报告，否则用户会去改错误的设置：
#   TCC  —— 终端未获「完全磁盘访问权限」，影响 ~/Library 下的照片/Messages/Chrome 等
#   root —— 目录属 root:wheel 700，需 sudo，改 TCC 也没用
# 上面普通模式可能没扫到这些目录，这里主动探一次
du -sk /private/var/* 2>>"$DENIED" >/dev/null
du -sk "$HOME/Library"/* 2>>"$DENIED" >/dev/null

tcc_denied=$(grep -o "$HOME/[^:]*" "$DENIED" 2>/dev/null | sort -u | head -15)
root_denied=$(grep -o '/private/var/[^:]*' "$DENIED" 2>/dev/null | sort -u | head -15)

if [ -n "$tcc_denied" ]; then
  echo "  [TCC] 用户目录被「完全磁盘访问权限」拦下，实际体积可能更大："
  echo "$tcc_denied" | sed 's/^/    /'
  echo "  → 系统设置 → 隐私与安全性 → 完全磁盘访问权限，勾选当前终端后重跑"
  echo
else
  echo "  [TCC] 无用户目录被拦，du 对 ~/Library 覆盖完整"
  echo
fi
if [ -n "$root_denied" ]; then
  echo "  [root] 系统目录属 root:wheel，需 sudo 才能读取（改 TCC 无效）："
  echo "$root_denied" | sed 's/^/    /'
  echo "  → 这类多为系统自管、体积很小，一般不必深究"
fi

hr "df 与 du 缺口"
# 粗算已知大项之和，与 df 已用量对比。缺口常见于：
#   - 未扫描的路径（如 /System 以外的挂载点、其他用户）
#   - APFS 共享块与元数据开销
#   - root 权限目录
du_sum=$(du -sk "$HOME" /private/var /Library /Applications /opt /usr/local 2>/dev/null \
         | awk '{s+=$1} END {printf "%d", s}')
if [ -n "$USED_BYTES" ] && [ "${du_sum:-0}" -gt 0 ]; then
  used_k=$((USED_BYTES / 1024))
  gap_k=$((used_k - du_sum))
  printf '  df 已用 : %d MiB\n' $((used_k / 1024))
  printf '  du 合计 : %d MiB（约，仅含已扫描路径）\n' $((du_sum / 1024))
  printf '  缺口    : %d MiB（约）\n' $((gap_k / 1024))
  if [ "$gap_k" -gt 2048 ]; then
    echo "  ⚠ 缺口较大。常见来源：未扫描路径、APFS 共享块/元数据开销、root 权限目录。"
    echo "    不代表有「神秘占用」，别照这个数字去猜。"
  fi
fi

hr "下一步"
cat <<'EOF'
  1. 先看「家目录可见文件夹」，用户数据的答案通常在那里
  2. 判断每一项是「缓存/残留」还是「真实数据」，两者的后果完全不同
  3. 候选目录用 lsof +D <目录> 确认无进程占用
  4. 删除前后都用 df -k /System/Volumes/Data 对比，验证真实收益
  5. APFS clone 必须整组删，单删一份几乎不减 df
  本脚本全程只读，未修改任何文件。
EOF
