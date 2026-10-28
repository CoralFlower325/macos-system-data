# macOS 存储布局与清理参考

配合 `scripts/diagnose.sh` 使用。这份文档回答"这个目录是什么、能不能删、删了会怎样"。

## 一、为什么「系统数据」的数字不可信

Apple 官方（[102624](https://support.apple.com/en-us/102624)）把它定义为"不属于任何更具体分类的所有文件的统称"——它是**余数**。Howard Oakley 在 [eclecticlight.co](https://eclecticlight.co/2025/02/11/what-is-system-data-in-storage-settings/) 指出这个分类连自身都算不准（他机器上 100GB 的 Music 目录只记录了 50GB），余项只能是估算。

由此产生几个后果：

- 清完缓存后数字反而变大——缓存重建、索引重建都在往余数里加
- 「可用空间」本身含 purgeable（可清除）空间，释放了也常常看不见
- 想判断真实余量，用「磁盘工具」看容器可用空间，或 `df`，别信设置里的分类图

## 二、Top-Level 目录语义

**先看家目录可见文件夹。** 用户说"磁盘满了"时，`~/Downloads`、`~/Desktop`、`~/Documents` 通常才是最大单项，几十 G 的情况很常见。这些被系统归入"文稿/下载"分类，不算系统数据，但排查时不该跳过。

Data 卷顶层（`df` / `du` 实测口径）：

| 路径 | 装什么 | 可否清理 |
|---|---|---|
| `/Users/<you>` | 家目录，真实用户数据 | 看具体内容 |
| `/Applications` | 已安装 App | 只删不用的，注意版本重复 |
| `/private/var` | 系统可写状态：临时、缓存、日志、数据库、VM | **重点排查区** |
| `/private/tmp` | 临时文件 | 可清，重启也清 |
| `/Library` | 全局应用支持、Developer、Input Methods | 部分可清 |
| `/System/Volumes/Preboot` | 启动相关 cryptex | **不要删** |
| `/System/Volumes/VM` | swapfile、sleepimage | 收益≈0 |
| `/System/Library` | 系统本体，SIP 保护只读 | **不要删** |

## 三、`/private/var` 明细

| 子目录 | 内容 | 典型体积 | 处置 |
|---|---|---|---|
| `folders/<u>/X/` | 代码签名克隆残留 | 可达上百 G | **优先清理**，见下节 |
| `folders/<u>/C/` | 应用缓存（python3、clang、metal） | 1–2G | 可清，会重建 |
| `folders/<u>/T/` | 进程临时文件 | <1G | 可清 |
| `db/diagnostics` | 统一日志 | ~1G | `sudo log erase --all` |
| `db/uuidtext` | 日志符号表 | ~700M | 随日志清理 |
| `log/` | 传统日志 | ~100M | 可清 |
| `vm/` | sleepimage 2G + swapfile | 2–3G | 删了重建，收益≈0 |

### `code_sign_clone` 详解

代码签名（如 MATLAB 签名其工具箱、Chrome/Edge 签名更新）会先用 APFS 克隆复制一份应用，签名失败或被中断时就留下残留。

识别特征：

```bash
ls -ld /private/var/folders/*/*/X/*code_sign_clone*
du -sh /private/var/folders/*/*/X/*
```

- 多个同源目录，体积相同
- 修改时间停在某天，之后不再变化
- `lsof +D` 只有 `du` 自己命中

**关键：APFS 克隆共享数据块。** `du` 报告的是"每份看到的逻辑大小总和"，不是物理占用。某机实例：7 份各 16G（`du` 合计 111G），单删一份 `df` 只减 0.2G，整组删除后 `df` 才减少约 18.7G。这说明**不能拿 `du` 数字承诺收益**。

所以判断收益的唯一可靠方式是：整组删 → 对比 `df`。不要拿 `du` 数字向用户承诺能释放多少。

## 四、`~/Library` 明细

| 路径 | 内容 | 风险 |
|---|---|---|
| `Application Support/*` | 应用数据（各类客户端、备份、开发工具） | 中，需逐个判断 |
| `Caches/*` | 缓存 | 低，会重建 |
| `Containers/*` | 沙盒应用数据 | 中，含聊天记录等 |
| `Developer/Xcode/DerivedData` | 编译产物 | 低，重建变慢 |
| `Developer/CoreSimulator` | 模拟器 | 低 |
| `Application Support/MobileSync/Backup` | iOS 备份 | **高，删不可恢复** |
| `Mail/`、`Messages/Attachments` | 邮件与信息附件 | **高** |
| `Python/3.x` | pip 用户包 | 低，可重装 |
| `Mobile Documents/` | iCloud 同步文件 | **高，会同步到其他设备** |

## 五、各项清理命令

本节命令供用户确认后自行执行。**不要代为运行任何删除命令**；确需代执行时，必须先列出确切路径、预估释放量、数据后果，并取得针对该条目的明确答复。

### APFS 本地快照（有则收益大）

```bash
tmutil listlocalsnapshots /
tmutil deletelocalsnapshots <YYYY-MM-DD-HHMMSS>   # 逐个删，保留最新一个
# 或用磁盘工具：显示 → 显示 APFS 快照 → 选中删除
```

注意：`tmutil listlocalsnapshots` 即使没有快照也会打印 `Snapshots for disk /:` 表头，要过滤后再判断。删最新快照会导致下一次 Time Machine 全量备份。

### 统一日志

```bash
/usr/bin/log stats --overview
sudo log erase --all     # 系统自管，会自动重建
```

不要手删 `/private/var/db/` 下的目录。

### iOS 备份

```bash
du -sh ~/Library/Application\ Support/MobileSync/Backup/*
```
GUI：Finder → 设备 → 通用 → 管理备份。**删除不可恢复。**

### Xcode

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/*
rm -rf ~/Library/Developer/Xcode/iOS\ DeviceSupport/*
rm -rf ~/Library/Developer/CoreSimulator/Caches/*
xcrun simctl delete unavailable
```

### 缓存

```bash
du -sh ~/Library/Caches/* | sort -h | tail -20
brew cleanup --prune=all
```

不建议整目录清空：QuickLook 预览和 Finder 会明显变慢，且 CacheDelete 在缺空间时本来就会自动清。

### 安全模式（官方唯一建议的"重建"方式）

Apple silicon：关机 → 长按电源键 → 选启动卷 → 按住 Shift 点「继续」。实际效果是清字体缓存和部分系统缓存，并让 CacheDelete 重新计算，通常只是**让数字变准**，不释放快照、不驱逐 iCloud。参考 [Apple mh21245](https://support.apple.com/guide/mac-help/start-up-your-mac-in-safe-mode-mh21245/mac)。

## 六、权限盲区

`du` 有两类读取失败，原因不同，处理方式也不同——**不要混为一谈**。

### TCC：需要「完全磁盘访问权限」

终端未获授权时，`du` 和 `ls` 对下列目录报 `Operation not permitted` 并**静默跳过**：

- `~/Pictures/Photos Library.photoslibrary`（照片图库）
- `~/Library/Messages`、`~/Library/Mail`
- `~/Library/Biome`、`~/Library/Suggestions`、`~/Library/PersonalizationPortrait`、`~/Library/IntelligencePlatform`
- `~/Library/Safari`、`~/Library/Containers`、`~/Library/Daemon Containers`
- `~/Library/Application Support/Google/Chrome`、`MobileSync`
- `~/Library/Application Support/com.apple.sharedfilelist`、`Knowledge`、`FileProvider`
- `~/.Trash`

某机实例：未授权时 `df` 报已用 141 GiB、`du` 求和只有 113 GiB（缺口 27 GiB）；授权后 `~/Library` 从 12G 跳到 33G，`Containers` 从 12M 跳到 16G。注意 `Containers` 在未授权时几乎完全读不到，会严重低估。

**这正好解释了「系统数据」为什么虚高**：照片图库、邮件、信息、浏览器数据都是真实数据，但因为不在"照片/文稿"等分类里，就被算进了系统数据的余数。

处理：系统设置 → 隐私与安全性 → 完全磁盘访问权限 → 勾选**实际执行命令的那个程序**（终端、iTerm，或你的 Agent 宿主程序）。授权后需重启该程序才生效。

### root：需要 sudo，改 TCC 无效

`/private/var` 下大量目录属 `root:wheel` 且权限 700，例如 `audit`、`backups`、`db/Sandbox`、`db/Spotlight`、`db/CoreDuet`。即使给了完全磁盘访问权限也读不到，会报 `Permission denied`。

这类目录通常体积很小或是系统自管数据，一般不必深究。若确需测量，用 `sudo du -sh`。

### 判断缺口时别急着归因

`df` 已用与 `du` 求和的差额，来源可能包括：未扫描路径、APFS 共享块与元数据开销、root 目录。**不代表存在"神秘占用"**，不要照这个数字去猜。

## 七、雷区

- `/System`：只读系统卷（SSV），SIP 保护，不要尝试
- `/System/Volumes/Preboot`：`du` 数值可比 `diskutil` 大数倍（实测某机 35G vs 10.9G），差额是快照共享块。**假占用**
- `/System/Volumes/Update`：更新暂存
- `/System/Volumes/VM` 正在使用的 `swapfile*`
- `/private/var/db/` 下的系统数据库
- 为了省空间关 SIP（`csrutil disable`）：得不偿失

## 八、第三方工具

Oakley 明确不建议用清理类 App：无文档、不可逆、容易损坏系统（[eclecticlight.co](https://eclecticlight.co/2016/05/28/why-you-shouldnt-use-cleaning-or-housekeeping-apps/)）。DaisyDisk 这类纯可视化工具尚可接受，因为它只读展示、删除由用户自己确认。

## 九、常见误解

| 说法 | 实际 |
|---|---|
| "系统数据是个文件夹" | 是余数，找不到对应目录 |
| "清完反而更大了" | 缓存/索引重建，余数重算 |
| "purgeable 空间能手动释放" | 系统按需回收，无需干预 |
| "`sudo periodic` 能清系统日志" | macOS 26 已移除该机制 |
| "删 sleepimage 能省 2G" | 立刻重建，净收益≈0 |
| "Preboot 占几十 G 要清理" | 共享块重复计数，实际远小于 du 显示值 |
