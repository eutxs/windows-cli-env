---
name: windows-cli-env
description: 在 Windows 上以交互方式为 AI Agent 配置命令行运行环境，逐项询问是否需要 PowerShell 7、Git for Windows、jq、ripgrep、uv/uvx、wget，解释用途，用便携版+手动 PATH 安装，配置 Git Bash 工具链与 HOME，避开 pwsh7 常见问题。当用户表示自己是 Windows 新手、需要配置 Agent 运行环境、安装 CLI 工具或询问"该装什么工具"时使用。
whenToUse: 用户提到 Windows 环境配置、新机器初始化、给 Agent 装 CLI 工具、PATH 设置、pwsh 问题、Git Bash 工具链时。
---

# Windows CLI 环境配置

给 AI Agent 配一套能在 Windows 上干活的命令行环境。**逐项问，逐项装，不打包二进制。**

| 用户要什么 | 去哪 |
|---|---|
| 知道该装什么、每样是干什么的 | 本文件「装之前先问」 |
| 装的具体步骤、PATH、验证 | `references/toolchain.md` |
| 装上以后用哪个命令改文件 | 本文件「编辑文本文件」 |
| 遇上说不通的怪问题 | `references/pitfalls.md` |
| 官方下载地址 | `references/links.yaml` |

**这个 skill 只做环境配置，不做桌面自动化。**

## 四条铁律

1. **先问，不要闷头装。** 见下面「装之前先问」。
2. **不要全量安装。** 先探测机器上已有什么，只补缺的。
3. **每个工具从官方发布页拿**（`references/links.yaml`）。不从第三方镜像、不打包二进制转发。winget 只在它自带的官方清单里有包时才用。
4. **汇报要短。** 装了什么、装在哪、要不要重开终端——三句说完。

---

## 装之前先问

**不要一次性把清单甩给用户说「要装哪些」。** 一项一项来，每项给出「它是干什么的」+「不装的代价」+「要不要」。用户可能只要一半。

### 用 `ask_user_question`，不要在对话里列表格

DSH 有专门的提问工具，会弹出带选项的窗口，用户点一下就行。**在对话正文里打「你要装吗？」然后等用户手打回复，是错的。**

```json
{
  "questions": [
    {
      "id": "bash-toolset",
      "header": "Git Bash 工具集",
      "question": "要不要装 Git for Windows？它会附带 sed / awk / perl / vim / find 一整套 GNU 工具。",
      "options": [
        { "label": "装（推荐）", "description": "附带 sed / awk / perl / vim / find 一整套，改文本、批处理、写脚本都靠它。" },
        { "label": "不装", "description": "这类活只能用 PowerShell 硬拼，跨行替换和字面量容易出错。" }
      ]
    }
  ]
}
```

**写提问的三条要求：**

1. **把推荐项放第一个，标签后加「(推荐)」。** 用户往往懒得比较，默认会点第一个。
2. **`description` 写「不装的代价」，不是「这个工具是什么」。** 工具是什么写在 `question` 里，`description` 回答的是「我点这个会失去什么」。
3. **`id` 用英文短横线词**，方便后面按 id 处理答案。

### 可以一次问多个

`ask_user_question` 支持一次传多个 question，会连续弹出。**适合问「同一层次的选择」**，比如一次问 jq 和 ripgrep 两个要不要装。

**不适合一次问五个不同层次的东西**——用户会被一次性轰炸，容易全选默认。按下面的组来，一组一次。

```json
{
  "questions": [
    {
      "id": "jq",
      "header": "jq",
      "question": "要装 jq 吗？命令行读改写 JSON。",
      "options": [
        { "label": "装", "description": "改 JSON 配置不用手改或上 Python。" },
        { "label": "不装", "description": "碰到 JSON 只能手改或用 PowerShell 的 ConvertFrom-Json，嵌套结构容易搞错。" }
      ]
    },
    {
      "id": "ripgrep",
      "header": "ripgrep",
      "question": "要装 ripgrep 吗？递归搜文件内容。",
      "options": [
        { "label": "装", "description": "大目录搜索快几个数量级，默认跳过 .gitignore 和二进制文件。" },
        { "label": "不装", "description": "只能靠 Select-String，它不递归，搜整个目录要自己套 Get-ChildItem。" }
      ]
    }
  ]
}
```

### 用户跳过不回答怎么办

`ask_user_question` 的返回里，`selected` 为空且没有 `custom` 表示用户跳过了这题。

**跳过不等于同意，也不等于拒绝。** 正确处理：

- 不重复问同一题
- 按「不装」处理（保守），除非那是必需项
- 如果是必需项（比如问「要不要继续」），跳过就当停止，**不要自作主张往下走**

### 别用弹窗做的事

- **不要用弹窗问开放式问题**——「你想要什么功能？」这种写进 `question` 是浪费一次弹窗。开放式问题直接对话里问。
- **不要用弹窗确认危险操作**——那应该在动手前用正文说清楚，让用户有上下文。弹窗里塞不下上下文。
- **不要在弹窗里问「要不要我帮你装」**——那是废话，用户既然触发了这个 skill 就是要装。

---

## 按这五组问

每组问完再下一组。

### 第 1 组：shell 本体

| 工具 | 干什么 | 不装的代价 |
|---|---|---|
| **PowerShell 7** | 新版跨平台 shell。默认 UTF-8 无 BOM，支持 `&&` / `\|\|` / `??` | 只能用系统自带的 5.1：写配置文件带 BOM、一律 ANSI、很多现代语法没有 |
| **Git for Windows** | 版本控制，**附带一整套 GNU 工具**（sed / awk / perl / vim / find / xargs / diff / tar / ssh） | 没有 sed / awk / vim，改文本只能靠 PowerShell 硬拼，跨行和字面量容易出事 |

**只做轻量任务的话这一组可以整组跳过**——系统自带的 PowerShell 5.1 能跑基本命令，只是没有 sed / awk / vim 那套。装它俩是为了后面省事。

### 第 2 组：文本与数据

| 工具 | 干什么 | 不装的代价 |
|---|---|---|
| **jq** | 命令行读改写 JSON | 改 JSON 配置只能上手改或上 Python |
| **ripgrep** `rg` | 递归搜文件内容，默认跳过 .gitignore 和二进制 | 大目录搜索慢到不可用；`Select-String` 不递归 |

### 第 3 组：Python

| 工具 | 干什么 | 不装的代价 |
|---|---|---|
| **uv**（含 `uvx`） | 管 Python 解释器、虚拟环境、包。一个二进制干完 pip+venv+pyenv 的活 | 碰 pip 和 venv 的老坑：全局装坏、版本打架、`pip` 不在 PATH |

**只在用户要用 Python 时问。** 不写 Python 就不装。

### 第 4 组：下载

| 工具 | 干什么 | 备注 |
|---|---|---|
| **curl** | 命令行下载 | Windows 10 1803+ **自带**，在 `C:\Windows\System32\curl.exe`。通常不用装 |
| **wget** | 命令行下载 | **GNU 官方不给 Windows 二进制**。有 curl 就别装 wget，除非用户点名 |

### 第 5 组：不要装

以下这些**主动问用户是不是真的需要**，默认不装：

- **Scoop / Chocolatey**——又一个包管理器。有 winget 就别叠。
- **Windows Terminal**——只是更好看的终端窗口，不影响能力。

---

## 工具链

完整下载地址、校验、逐个安装步骤见 `references/toolchain.md`。这里是必须记住的骨架。

### 目录约定（便携版 + PATH，不用安装程序）

| 放什么 | 放哪 | 为什么 |
|---|---|---|
| 单文件 CLI（uv / jq / rg） | `%USERPROFILE%\.local\bin` | uv 官方安装器默认就装这，天然一致 |
| PowerShell 7 便携版 | `%LOCALAPPDATA%\Programs\pwsh` | 用户级，不需要管理员 |
| Git | 走官方安装程序 | 它有 200+ 文件，别手工摊平。**装在哪由用户决定，路径要现查，见下** |

`%USERPROFILE%\.local\bin` 整目录加进用户 PATH 一次，后面加工具不用再动 PATH。

### PATH 顺序（关键，实测）

**Git 自带的 `usr\bin` 必须加在用户 PATH 的最末尾。**

实测这个目录和 `C:\Windows\System32` 有十余个同名 exe（不写死具体清单，换 Git 版本就会变），最危险的是 **find**（Windows 的 find 是字符串搜索，和 GNU find 完全两回事）、**sort**、**tar**、**timeout**、**whoami**。完整交集现场生成：

```powershell
# 现场列出遮蔽了哪些，不要照抄任何文档里的固定清单
$gitbin = Get-GitBin
$sys = Get-ChildItem C:\Windows\System32 -Filter *.exe -File |
       ForEach-Object { $_.Name.ToLower() }
$gb  = Get-ChildItem (Join-Path $gitbin '*.exe') -File |
       ForEach-Object { $_.Name }
Compare-Object $sys $gb -IncludeEqual -ExcludeDifferent |
    Select-Object -ExpandProperty InputObject
```

```powershell
# Get-GitBin 定义在 scripts/utils.ps1，先加载
. (Join-Path '<skill-root>' 'scripts/utils.ps1')
$gitbin = Get-GitBin
$gitbin      # 例如 C:\Program Files\Git\usr\bin
```

**`<skill-root>` 换成这个 skill 的实际目录。** 如果 `$PSScriptRoot` 可用（写在 .ps1 里），直接 `. (Join-Path $PSScriptRoot '..\scripts\utils.ps1')`。

函数内部有三层回退（见 `scripts/utils.ps1` 源码）：

1. **`Get-Command git.exe`**——正常情况，git 已在 PATH
2. **查注册表** `HKLM:\SOFTWARE\GitForWindows`（含 32 位视图 `WOW6432Node`）——刚装完、当前会话 PATH 还没刷新的情况。此时 `Get-Command` 返回空，光靠第 1 步必挂
3. **从 git.exe 往上找**含 `usr\bin\sed.exe` 的目录——不假设固定层级，兼容默认安装和 MSYS2 布局

**Scoop 装的 Git** 没有注册表键，第 2 步会失败，但它会把自己的 shim 目录加进 PATH，第 1 步能命中。三层里总有一层。

### HOME 怎么处理

**不要设 `HOME` 环境变量。** 默认行为就是对的：

- Git Bash 里 `HOME` = `USERPROFILE`
- PowerShell 里用 `$env:USERPROFILE`，`HOME` 不是标准变量

设了反而会让 Git Bash 的 `~` 和 Windows 侧的路径对不上。

**真正的坑在别处**：如果用户的 `Documents` 被重定向到了 OneDrive，那么 PowerShell 的 `$PROFILE`、vim 的 swap 文件、很多工具的默认配置目录都会落进 OneDrive。**一律用 `pwsh -NoProfile` 跑脚本**，不要依赖 profile。

### 验证装完能用

```powershell
# 每个工具跑一次版本，一次跑完，不要分五次
foreach ($c in 'pwsh','git','sed','perl','vim','jq','rg','uv','uvx') {
  $x = Get-Command $c -ErrorAction SilentlyContinue
  if ($x) { "{0,-6} {1}" -f $c, $x.Source } else { "{0,-6} (缺)" -f $c }
}
```

**验证必须由用户新开终端完成**——PATH 是进程启动时读的，当前会话改完不生效。

**AI 自己开不了新终端**，所以要写成用户指令：

> 请关掉当前终端窗口，新开一个，运行下面这行，把输出贴回来：
> ```
> pwsh -NoProfile -Command "$PSVersionTable.PSVersion; (Get-Command sed).Source"
> ```

这是「装好了但 AI 说找不到」最常见的原因——不是没装好，是没刷新。

---

## 编辑文本文件：用哪个命令

### 先确认 Git 装了没有

这一节的 sed / perl / vim / grep **全部来自 Git 自带的 `usr\bin`**。用户在第 1 组选了「不装 Git」时，这些命令根本不存在，硬调会一个都跑不起来。

```powershell
$gitbin = $null
try { $gitbin = Get-GitBin } catch { $gitbin = $null }
```

**`$gitbin` 为 null 时的降级方案**——只能退回 PowerShell 原生替换，且必须承认它容易出错：

```powershell
# 单行替换（字面量，非正则）
$p = 'C:\path\file.txt'
$old = 'old-text'; $new = 'new-text'
$txt = [System.IO.File]::ReadAllText($p)
$txt = $txt.Replace($old, $new)          # .Replace 是字面量，不解释正则
[System.IO.File]::WriteAllText($p, $txt, (New-Object System.Text.UTF8Encoding($false)))
```

**必须告诉用户的**：这种替换没有行号定位、跨行模式很笨拙、正则要用 `-replace` 但那是 .NET 语法（和 sed/perl 不一样），字面量含特殊字符时容易踩坑。**并建议他重新考虑装 Git。**

**不要**在用户明确拒绝 Git 之后还偷偷去调 `$gitbin` 下的命令——那只会抛一堆找不到文件的错。

### 有 Git 时怎么挑命令

改文件不要一律上 PowerShell 的正则替换，按场景挑：

| 场景 | 工具 | 理由 |
|---|---|---|
| 单行、简单模式替换 | `sed -i -E` | 最轻最快；**失败会报错**，不会假装成功 |
| 按行号范围操作 | `vim -es` | 行号命令比 sed 地址表达式直观；但会吞 stdin、会补末尾换行 |
| 复杂模式 / 跨行 / 用户给的字面内容 | `perl -pi -e` | 字面引用和跨行能力最强；**失败也 exit=0，必须回读** |
| 追加（幂等） | `grep -qF` + `echo >>` | 不需要 sed 参与 |

**正斜杠规则只针对 Git 自带的工具。** 调 `sed` / `perl` / `grep` / `vim` 这些 cygwin 程序时，路径必须写 `C:/Users/me/a.txt`，反斜杠会让它们写回失败。

**纯 PowerShell 操作不要跟着转。** `Get-Content`、`Set-Location`、`Test-Path` 这些 cmdlet 吃反斜杠是正常的，硬把路径改成正斜杠反而可能出问题（比如某些老 API 对正斜杠处理不同）。**判据是「这条命令由谁执行」，不是「文件在哪」。**

**Git 路径不要硬编码**——用户的 Git 可能不在 `C:\Program Files\Git`。用上面 `Get-GitBin` 现查，再拼路径。调用时统一用 `Join-Path` 拼可执行文件路径。

**五条实测结论，动手前必读（在 Git for Windows 官方版上验证过）：**

1. **传路径必须用正斜杠。** 这是唯一真正的硬规则。给 `sed` / `perl` 传 `C:\path\file.txt` 会在写回时炸——`sed` 报 `cannot rename ./sedXXXX: Invalid cross-device link`（exit=4），`perl` 报 `Cannot make temp name: Permission denied`（**而且 exit=0，看起来成功了**）。**文件内容一点没改。** 换成 `C:/path/file.txt` 全部正常，跨目录也正常。`vim` 没有这个问题，反斜杠也能用。

2. **`perl -pi` 失败时 exit=0。** 必须自己回读文件确认改动生效，不能只信退出码。`sed` 失败会给 exit=4 / 2，反而可靠。

3. **只有 `sed` 找不到文件时会报错**（exit=2）。**`vim -es` 和 `perl -pi` 遇到不存在的文件都 exit=0**，vim 还会**直接把文件创建出来**。写之前先 `Test-Path`。

4. **`vim -es` 写入时补末尾换行。** 原文件末尾没换行的话，改完多一个 `\n`（实测 3 字节 `abc` 变 4 字节 `abc\n`）。

5. **`grep -qF` 判幂等时注意 CRLF。** bash 工具写的是 `\n`，Windows 侧某些工具读 `\r\n`。

**另外**：`vim -es` 默认吃 stdin，在管道里会卡住。批处理时给它接 `< NUL`，或者干脆不用它。

---

## 参考文件

- `scripts/utils.ps1`——`Get-GitBin` 的唯一定义。**所有文件都从这里 dot-source，不要在别处复制函数体**
- `references/toolchain.md`——逐个工具的下载、解压、校验、PATH 配置、验证
- `references/pitfalls.md`——pwsh 5.1 vs 7 的差异、命令遮蔽、踩过的坑
- `references/links.yaml`——所有官方发布页
