# 踩过的坑

按「会咬人的程度」排。

---

## 1. Git Bash 工具的路径：一律正斜杠

**这是本文件最重要的一条。**

Git 自带 `usr\bin` 里的工具（sed / perl / grep / awk / find…）运行在 **MSYS2 环境**（源自 Cygwin 的衍生分支）里，它们的写回文件操作走 MSYS2 的 POSIX 路径解析。**传反斜杠路径时，临时文件的创建会落到错的地方**，结果是：

| 工具 | 现象 | 退出码 | 实际结果 |
|---|---|---|---|
| `sed -i` | `cannot rename ./sedXXXX: Invalid cross-device link` | 4 | 文件没改 |
| `sed -i`（目标目录不可写时） | `couldn't open temporary file ./sedXXXX: Permission denied` | 4 | 文件没改 |
| `perl -pi` | `Cannot make temp name: Permission denied` | **0** | 文件没改 |
| `vim -es` | 无报错 | 0 | 正常 |

**解法**：路径写成 `C:/Users/me/a.txt`。正斜杠下全部正常，跨目录也正常。

真正的判据是**路径格式**，不是「必须 cd 到目标目录」。上一版 skill 写错了，实测纠正。

### perl 的危险之处

`perl -pi` 在写回失败时 **exit=0**。脚本里写 `if ($LASTEXITCODE -ne 0) { throw }` 根本拦不住，你以为改完了，实际文件一个字没动。

**用 perl 改完必须回读**：

```powershell
$gitbin = Get-GitBin      # 定义在 scripts/utils.ps1，先 . 加载，见 SKILL.md
& (Join-Path $gitbin 'perl.exe') -pi -e 's/old/new/' 'C:/path/f.txt'
$now = Get-Content 'C:/path/f.txt' -Raw
if ($now -notmatch 'new') { throw 'perl 没改成' }
```

### 不存在的文件

| 工具 | 文件不存在时 |
|---|---|
| `sed -i` | exit=2，报 `can't read ...: No such file or directory`，**不创建** |
| `perl -pi` | exit=0，报错到 stderr，**不创建** |
| `vim -es` | exit=0，**直接把文件创建出来** |

vim 那条最坑：写错路径不会报错，而是在错的地方悄悄建了个空文件。

**写之前先 `Test-Path`。**

---

## 2. 命令遮蔽：usr\bin 必须放 PATH 末尾

Git 自带的 `usr\bin` 和 `C:\Windows\System32` 有十余个同名 exe。**不要在文档里写死这份清单**——换 Git 版本、换 Windows 版本都会变。

**现场生成**：

```powershell
$gitbin = Get-GitBin
$sys = Get-ChildItem C:\Windows\System32 -Filter *.exe -File | ForEach-Object { $_.Name.ToLower() }
$gb  = Get-ChildItem (Join-Path $gitbin '*.exe') -File | ForEach-Object { $_.Name }
Compare-Object $sys $gb -IncludeEqual -ExcludeDifferent | Select-Object -ExpandProperty InputObject
```

实测（Git for Windows + 当前 Windows）交集是 9 个：`bash` `expand` `find` `hostname` `reset` `sort` `tar` `timeout` `whoami`。

**注意 `locale.exe` 和 `notepad` 的陷阱**：`locale.exe` 只在 Git 里，System32 没有；`notepad` 在 Git 里**不是 .exe**（是个 635 字节的 shell 脚本），System32 里才是 `notepad.exe`。**不按扩展名过滤就会把这两个算进交集，得出错误的数字。**

按危害排序：

| 命令 | 加了 usr\bin 在前会变成 | 危害 |
|---|---|---|
| `find` | GNU find（找文件） | Windows 的 `find` 是**字符串搜索**，完全不同的东西。脚本里的 `find "error" file.log` 会突然开始找名为 error 的文件 |
| `sort` | GNU sort | 参数不兼容，`sort /r` 会报错 |
| `tar` | GNU tar | bsdtar 的 `-a` 自动压缩没了 |
| `timeout` | GNU timeout | Windows 的 `timeout /t 5` 语法不通 |
| `whoami` | GNU whoami | 少 `/user` `/groups` 参数 |
| `bash` `expand` `hostname` `reset` | — | 影响较小 |

**解法**：加在用户 PATH **最末尾**：

```powershell
$gitbin = Get-GitBin      # 现查，不硬编码
$cur = [Environment]::GetEnvironmentVariable('Path','User')
[Environment]::SetEnvironmentVariable('Path', "$cur;$gitbin", 'User')
```

代价：要用 GNU 版本得写全路径 `& (Join-Path $gitbin 'find.exe') .`。**这个代价值得付。**

---

## 3. PowerShell 5.1 vs 7

| 方面 | 5.1 | 7 |
|---|---|---|
| 写文件编码 | 默认 ANSI；`-Encoding UTF8` **带 BOM** | 默认 UTF-8 **无 BOM** |
| `curl` / `wget` | 是 `Invoke-WebRequest` 的**别名** | **别名已移除**，`curl` 就是 `curl.exe` |
| `&&` `\|\|` `??` | 不支持 | 支持 |
| 原生命令传参 | 老规则 | 7.3+ 默认 `Standard`，引号处理变了 |
| `ForEach-Object -Parallel` | 没有 | 有 |

### 同一个脚本两个意思

```powershell
curl https://example.com -o out.html
```

- 5.1：调 `Invoke-WebRequest`，`-o` 不是它的参数，报错
- 7：调 `curl.exe`，正常工作

**写跨版本脚本时，永远显式写 `curl.exe` 或 `Invoke-WebRequest`，不要写 `curl`。**

### 5.1 写 UTF-8 无 BOM 的正确姿势

5.1 不支持 `-Encoding utf8NoBOM`，只能走 .NET：

```powershell
$p = 'C:/path/file.txt'
$s = "内容"
[System.IO.File]::WriteAllText($p, $s, (New-Object System.Text.UTF8Encoding($false)))
```

`$false` 那个参数就是「不要 BOM」。

### 引号被吞

在 `pwsh -Command` 里给 Node / Python 传带引号的脚本，引号会被吞掉。踩过：`name: "@scope/pkg"` 落盘变成 `name: @scope/pkg`，直接把 YAML 写坏。

**唯一可靠的姿势是单引号 here-string**：

```powershell
node --input-type=module -e @'
const x = { name: "@scope/pkg" };
console.log(x.name);
'@
```

`-e "..."` 和 `-e '...'` 都不可靠。

---

## 4. HOME 与 profile

**不要设 `HOME`。** 默认就对：Git Bash 里 `HOME` = `USERPROFILE`，PowerShell 里用 `$env:USERPROFILE`。设了反而让 `~` 和 Windows 侧路径对不上。

**真正的坑**：如果 `Documents` 被重定向到 OneDrive，这些会落进 OneDrive：
- PowerShell 的 `$PROFILE`
- vim 的 swap 文件（`~/.vim/swap` 不在 OneDrive 就没事，但要确认）
- 很多工具的默认配置目录

**解法**：脚本一律 `pwsh -NoProfile`，不依赖 profile。

---

## 5. PATH 改了不生效

PATH 是**进程启动时**读的。当前会话里 `[Environment]::SetEnvironmentVariable('Path', ..., 'User')` 改完，`Get-Command` 照样找不到新工具。

**必须新开终端验证。**

如果新开终端还是没有：
```powershell
# 看用户 PATH 里到底有没有
[Environment]::GetEnvironmentVariable('Path','User') -split ';'
```

如果这里没有，说明写入失败（或者是写到了 Machine 级、被策略覆盖）。

---

## 6. 装工具的位置

**不要装到会被清理的目录。** 踩过：把 pwsh 7 装在 AI 的临时产物目录里，而那个目录按规定用完要清空——工具随时可能被删掉，而且没人会记得它曾经在那儿。

**正确位置**：
- 单文件 CLI → `%USERPROFILE%\.local\bin`
- 便携版程序 → `%LOCALAPPDATA%\Programs\<name>`
- 有安装程序的 → 让它自己装

**不要用**：桌面、文档（可能被 OneDrive 同步）、任何带「临时」「scratch」「产物」语义的目录。

---

## 7. winget

| 坑 | 说明 |
|---|---|
| 卡在交互提示 | 必须带 `--accept-package-agreements --accept-source-agreements --disable-interactivity` |
| `upgrade --all` | 会把用户所有软件一起升，包括特意留旧版的。**不要跑** |
| 不存在 | Server / LTSC 早期没有。不要试图装，直接走 zip 路线 |
| 装便携工具 | 不要用 winget 装 uv / jq / rg 这类单文件工具，路径和版本都不可控 |

---

## 8. 不要在 skill 里塞的东西

写这个 skill 时定的边界，改的时候别破坏：

- **不打包二进制**。只教怎么从官方发布页拿。
- **不写机器私有的东西**。比如某个具体网关、某个具体盘的路径约定、某个用户的特殊配置——那些是那台机器的，不是通用的。
- **不做全量安装**。先探测、只补缺。
- **不替用户决定**。每一项都问，给「干什么 / 不装的代价」，让他自己选。---

## 9. `ask_user_question` 的几个坑

| 坑 | 后果 | 正确做法 |
|---|---|---|
| 在正文里问「你要不要装？」 | 用户得手打回复，多一轮往返 | 用 `ask_user_question`，点一下就行 |
| `options` 里没写 `description` | 用户不知道选项区别，只能瞎点或反问 | 每个选项都写「选了会怎样」，尤其写清代价 |
| 把推荐项放最后一个 | 用户习惯性点第一个，选到你不推荐的 | **推荐项放第一个，标签加「(推荐)」** |
| 一次弹十个问题 | 用户被轰炸，全选默认 | 按层次分组，一组一次 |
| 用户跳过（`selected` 为空、无 `custom`）后又问一遍 | 烦人 | 跳过就当「不装」，不重复问 |
| 把跳过当成「同意」 | 装了一堆用户不想要的 | 跳过 = 保守处理，不装 |
| 用弹窗问开放问题 | 弹窗塞不下，用户答不完整 | 开放问题直接对话里问 |

### 返回值的形状

```json
{
  "answers": [
    { "id": "jq", "selected": ["装"] },
    { "id": "ripgrep", "selected": [] },
    { "id": "uv", "selected": [], "custom": "我自己装过了" }
  ]
}
```

- `selected` 有值 → 按选项走
- `selected` 空 + 有 `custom` → 按用户的自定义输入走
- `selected` 空 + 无 `custom` → **用户跳过了**，不是同意

### 多选

需要用户一次勾多个时，question 里加 `"multi_select": true`。适合「这几个里挑几个装」这种场景。

**不要滥用**：需要明确每个工具装不装的时候（因为每个都要解释代价），还是一题一个更清楚。
