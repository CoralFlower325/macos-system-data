# macOS System Data Cleanup Skill

一个用于诊断 macOS「系统数据」(System Data) 异常占用的 Agent skill。默认**只诊断、不代为删除**。

## 为什么需要它

macOS 设置里的「系统数据」不是一个文件夹，而是扣掉照片、音乐、App 等分类后的**余数**。所以你在 Finder 里永远找不到它，网上多数教程也停留在"清缓存"层面。

这个 skill 提供一套可复现的定位方法，并记录了几个容易踩的坑：

- **`du` 双向失准**：APFS 克隆和快照共享块会被重复计数（虚高），缺少完全磁盘访问权限时又会静默漏算（偏小）
- **APFS 克隆陷阱**：几个 16G 的克隆目录，`du` 合计 111G，实际共享同一批数据块，整组删除才释放约 18.7G
- **系统数据的真实大头**：常是 `~/Library/Containers`（聊天记录）、`Application Support`，而非 `/System/Library`

## 安装

```bash
git clone https://github.com/<owner>/macos-system-data.git
cp -r macos-system-data ~/.zcode/skills/     # 或你的 Agent skills 目录
```

确认目录结构为 `SKILL.md` + `scripts/` + `references/` 即可被识别。

## 使用

通常直接说出意图即可触发：

> 系统数据太大了，磁盘快满了，帮我看看到底什么在占空间

或显式运行诊断脚本（只读）：

```bash
bash scripts/diagnose.sh          # 概览
bash scripts/diagnose.sh deep     # 额外下钻 /private/var、~/Library、家目录
```

建议先授予「完全磁盘访问权限」，否则 `~/Library` 会被大幅低估（系统设置 → 隐私与安全性 → 完全磁盘访问权限 → 勾选实际执行命令的程序，重启生效）。

## 删除边界

**本 skill 不会自动删除任何文件。** 它输出诊断结论和建议命令，由你确认后自行执行。规则详见 `SKILL.md` 铁律 0：

> 没有人逐项确认，绝不执行删除。即使用户说"帮我删"，也必须先列出确切路径、预估释放量、数据后果三类信息，得到针对这些具体条目的明确答复后才可执行。

`diagnose.sh` 本身不含任何 `rm` / `mv` / `sudo` 写操作，可用 `grep` 核验。

## 内容

| 文件 | 说明 |
|---|---|
| `SKILL.md` | 主流程：五条铁律 + 诊断 → 分档处置 → 验证 |
| `scripts/diagnose.sh` | 只读诊断脚本 |
| `references/macos-layout.md` | 目录语义、风险分级、清理命令、雷区、常见误解 |

诊断结论基于 macOS 26 实测。部分数字标注为「某机实例」，仅作量级参考。

## 免责

清理系统文件有风险。删除前请自行确认路径与后果，重要数据先备份。作者不对误删造成的损失负责。
