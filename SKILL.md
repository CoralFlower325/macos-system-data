---
name: macos-system-data
description: >
  诊断 macOS「系统数据」(System Data) 异常占用，定位真实占用并给出分级清理方案。
  当用户说系统数据太大、存储空间被"其他"占满、设置里显示几十上百 GB 系统数据、
  磁盘空间莫名其妙消失，或怀疑缓存/日志/快照吃掉空间时使用。覆盖
  /private/var/folders 残留、code_sign_clone、APFS 快照、统一日志等。
  本 skill 默认只诊断、不代为删除；任何删除都需用户逐项确认。
  不适用于单纯想知道哪个文件夹大（那用 storage-analyzer 出报告）。
metadata:
  short-description: 诊断 macOS 系统数据（只诊断不代删）
---

# macOS 系统数据清理

macOS 设置里的「系统数据」不是一个文件夹，而是**扣掉照片、音乐、App 等分类后的余数**。Apple 官方定义（[support.apple.com/102624](https://support.apple.com/en-us/102624)）原文是"all Apple and third-party files that don't belong to any more specific category"。所以按名字去找目录必然失败，只能按实际占用逐层定位。

## 铁律

0. **没有人逐项确认，绝不执行删除。** 本 skill 的产出是诊断结论和清理命令，不是删除动作。默认把命令打印给用户自己执行。即使用户说"帮我删"，也必须先列出**确切路径、预估释放量、数据后果**三类信息，得到针对这些具体条目的明确答复后才可执行。含 `rm`、`mv`、`rmdir`、`find -delete`、`sudo log erase` 在内的任何删除或写入命令，都受这一条约束。用户没有明确点名的路径，一律不删。

1. **先测量再动手。** 不看到 `df` 前后对比，不允许删任何东西。
2. **`du` 会双向失准。** 它会把 APFS 写时复制克隆和快照共享块**重复计数**（虚高），也会因缺少「完全磁盘访问权限」对照片图库、`Messages`、`Mail`、`Biome`、Safari、Chrome、`.Trash` 等**静默漏算**（偏小）。判断真实占用一律用 `df` 或 `diskutil info`；见到 `df` 与 `du` 总和大额不符，先查权限，不要当成"神秘占用"去猜。
3. **删除前查占用进程。** `lsof +D <目录>`，有进程持有就不能删。
4. **向用户说明数据后果。** 缓存会自动重建、残留删了无损、历史记录删了不可恢复——这三类必须区分清楚，不能笼统说"清理"。
5. **不碰 SIP 保护路径。** 不为了省空间建议 `csrutil disable`。

铁律 0 优先于其余所有条款：任何档位的清理建议，在没有得到用户逐项确认前，都停留在"建议"状态，不得触发实际删除。

## 第一步：诊断

```bash
bash scripts/diagnose.sh          # 概览
bash scripts/diagnose.sh deep     # 额外下钻 /private/var、~/Library、隐藏目录
```

脚本全程只读。输出顺序刻意设计成：磁盘水位 → APFS 快照 → **家目录可见文件夹**（用户数据的大头通常在这里，容易被忽略）→ `/private/var` 各子项 → 用户临时目录与克隆残留 → 休眠镜像 → 统一日志 → `~/Library` → 常见可回收项 → **权限盲区清单** → **`df` 与 `du` 缺口校验**。

拿到输出后判断每一项的性质。目录语义和风险分级见 [references/macos-layout.md](references/macos-layout.md)。

### 如果用户只要诊断、不要清理

跳过后面所有 `df` 前后对比，改为按四档给区间估算，并明确标注哪些数字是 `du` 口径、哪些是 `df` 口径：

| 档 | 内容 | 风险 |
|---|---|---|
| 无损残留 | 升级备份 `*.pre-*.bak`、修复前快照、`/private/tmp` | 删了不回来但确认无用 |
| 可重建缓存 | `~/Library/Caches`、`~/.cache`、`.npm`、pip 用户包、构建产物 | 会重建，首次变慢 |
| 真实数据 | 下载、文档、媒体、iOS 备份、聊天记录 | **不可恢复** |
| 不值得动 | sleepimage、Preboot、Spotlight 重建 | 收益≈0 |

## 第二步：按收益和风险排序出方案

清理优先级从高到低。**这一阶段的产出是报告和命令，不是删除动作。** 每一档都给出确切路径、预估释放量、数据后果；只有用户逐项确认后，才进入执行。

汇报格式建议固定成三列，避免含糊：

| 路径 | 预估释放 | 数据后果 |
|---|---|---|
| `/private/var/folders/.../X/com.mathworks.matlab.code_sign_clone` | 视实际而定（须用 df 验证） | 签名残留，无数据损失 |

### 档 1：临时目录残留（收益最高，常见几十上百 GB）

`/private/var/folders/<xx>/<随机串>/X/` 下的 `*.code_sign_clone` 是代码签名过程中断留下的残留，MATLAB、Chrome、Edge 都产生过。特征：

- 同一前缀多份，每份体积相同（某机实例：7 个各 16G）
- 修改时间是几天前，`lsof` 无真实占用
- 名字形如 `com.mathworks.matlab.code_sign_clone`

**这里有个必须理解的陷阱：** 这些是 APFS 克隆，共享底层数据块。`du` 会把共享块给每份各算一遍，所以总和是虚高的。某机实例：7 份各 16G（`du` 合计 111G），单删一份只减 0.2G，**整组删掉才释放真正的约 18.7G**。因此不要拿 `du` 数字向用户承诺收益。

给用户的验证与执行命令（**打印给用户，不要代跑**）：

```bash
df -k /System/Volumes/Data | tail -1    # 删前基线
lsof +D /private/var/folders/*/*/X/     # 确认无占用
# 用户确认后，由用户自己执行，或逐项授权后代执行：
rm -rf /private/var/folders/*/*/X/com.mathworks.matlab.code_sign_clone
df -k /System/Volumes/Data | tail -1    # 删后对比差值才是真实收益
```

### 档 2：可重建缓存（无损，但会重新长出来）

`~/Library/Caches/*`、`~/.cache/*`、`~/.npm`、`~/Library/Application Support/*/` 下的 updater/ServiceHost 日志。删了应用自动重建，通常几个 G。

### 档 3：一次性残留（删了不回来但无用）

升级备份（`*.pre-<版本>.bak`）、修复前的数据库快照（`*-repair/before-repair-*.sqlite`）、应用自建的 `version-history`。这类要确认主数据仍在才算安全。

### 档 4：真实数据（会不可恢复，必须让用户决定）

历史会话归档、iOS 设备备份（`~/Library/Application Support/MobileSync/Backup`）、邮件附件、`~/Library/Messages/Attachments`。**不要替用户决定**，列出体积和后果让他选。

### 常见但收益接近零的项

调研和实测都确认这些通常不值得动，别浪费用户时间：

| 项 | 为什么不做 |
|---|---|
| `sleepimage` | 删了下次睡眠立刻重建，净收益≈0 |
| APFS 本地快照 | 空的时候是真的空；有的话收益大，用 `tmutil` 查 |
| `/System/Volumes/Preboot` | `du` 可能显示 35G，`diskutil` 实际只 10.9G，差额是共享块重复计数。**不是真实占用，不要清理** |
| Spotlight 重建 | 不省空间，重建期间索引还会翻倍 |
| 清理类第三方 App | 无文档、不可逆，不建议 |

另外：网上流传的 `sudo periodic daily weekly monthly` 在 macOS 26 已不存在（`/usr/sbin/periodic` 和 `/etc/periodic` 都没有）。

## 第三步：验证与收尾

删除由用户执行后，再做验证；未执行删除时，跳过本节。

- 用户执行完某项后，跑 `df -h /System/Volumes/Data` 对比基线，告知实际释放量
- 和预估差异大时，回头看是不是踩了 APFS 共享块陷阱
- 说明哪些是"永久释放"，哪些是"应用会重建所以只是暂缓"
- 需要 sudo 的项（统一日志 `/usr/bin/log erase --all`、删休眠镜像）如果当前环境没权限，直接说明，不要假装做了

## 参考

- 目录语义、风险分级、各项具体命令：[references/macos-layout.md](references/macos-layout.md)
- 「系统数据」为何虚高、社区争议：同上文件末尾
