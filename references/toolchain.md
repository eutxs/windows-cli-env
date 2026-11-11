# 工具链：下载、安装、配置

每一项都从**官方发布页**取（`links.yaml` 有全部地址）。没有打包二进制。

---

## 0. 前置：先探测，再用 `ask_user_question` 问

### 探测

装之前先看机器上已经有什么。**用户可能已经装了一半，全量重装是浪费。**

```powershell
$want = 'pwsh','git','sed','awk','perl','vim','jq','rg','uv','uvx','curl','wget'
foreach ($c in $want) {
    $x = Get-Command $c -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($x) { '{0,-6} {1}' -f $c, $x.Source } else { '{0,-6} (缺)' -f $c }
}
```

**只把标「(缺)」的列进提问清单。** 已经有的跳过，不重复问。

### 用 `ask_user_question` 弹窗

**不要用「你要不要装 X？」这种正文提问。** DSH 有专门的工具，会弹带选项的窗口。见 `SKILL.md` 的「装之前先问」一节，那里写了完整的写法、三条要求和跳过处理。

这里只强调一点：**`description` 写「不装的代价」**，用户靠这个做决定，不是靠「这个工具很好用」。

---

## 1. 通用姿势

### 便携版优先

能用 zip 便携版就别用安装程序——不写注册表、不要管理员、卸载就是删目录。

### 目录

| 放什么 | 放哪 |
|---|---|
| 单文件 CLI | `%USERPROFILE%\.local\bin` |
| PowerShell 7 便携版 | `%LOCALAPPDATA%\Programs\pwsh` |
| 有安装程序的（Git） | 让它自己装，默认位置即可 |

### 把 `%USERPROFILE%\.local\bin` 加进用户 PATH（只做一次）

```powershell
$bin = Join-Path $env:USERPROFILE '.local\bin'
New-Item -ItemType Directory -Force -Path $bin | Out-Null

$cur = [Environment]::GetEnvironmentVariable('Path','User')
if ($cur -notlike "*$bin*") {
    [Environment]::SetEnvironmentVariable('Path', "$bin;$cur", 'User')
    "已加入用户 PATH"
} else { "已在 PATH 中" }
```

**这样做而不是 `$env:Path += ...`**：后者只影响当前进程，新开终端就没了。

### 加完必须新开终端验证

PATH 是进程启动时读的。当前会话里改完，`Get-Command` 照样找不到。这是「装好了但用不了」最常见的原因。

**AI 自己开不了新终端**，这句话要变成给用户的指令（见第 9 节末尾的写法）。

### 下载后必须校验

**「大小对」不等于「内容对」。** 从 CDN 拉大文件时，多连接分片拼出来的东西可能大小完全一致、内容完全不同——踩过：同一个 43MB 文件下两次，大小都是 43849787，sha256 却各不相同。

**每一条下载都走这两步：**

```powershell
param($Url, $Dest, $ExpectedSha256)

Invoke-WebRequest $Url -OutFile $Dest

$actual = (Get-FileHash -Path $Dest -Algorithm SHA256).Hash.ToLower()
if ($ExpectedSha256) {
    if ($actual -ne $ExpectedSha256.ToLower()) {
        Remove-Item $Dest -Force
        throw "校验失败: 期望 $ExpectedSha256，实际 $actual"
    }
    "校验通过: $actual"
} else {
    # 发布页没给 hash 时，至少把实际值打出来让用户核对
    "无预期 hash，实际 sha256 = $actual"
}
```

**hash 从哪来**，优先级从高到低：

1. **官方发布页附带的 sha256 文件**——GitHub Releases 通常有 `sha256sums.txt` / `checksums.txt` / `*.sha256`。从 API 拿的具体写法：

```powershell
# $rel 是前面 Invoke-RestMethod 拉到的 releases/latest；$asset 是选中的那个下载物
$hashAsset = $rel.assets | Where-Object {
    $_.name -match 'checksums?\.txt$|sha256sums?\.txt$|\.sha256$'
} | Select-Object -First 1

if ($hashAsset) {
    $lines = (Invoke-RestMethod $hashAsset.browser_download_url) -split "`n"
    # 格式通常是 "<hash>  <filename>"
    $hit = $lines | Where-Object { $_ -match [regex]::Escape($asset.name) } | Select-Object -First 1
    if ($hit) { $expected = ($hit -split '\s+')[0] }
}
if (-not $expected) { '该发布页没有 checksum 文件，只能记录实际 hash 留档' }
```

**没有 checksum 文件是常见情况**，别卡在这——退到第 3 条，把实际 hash 打出来。
2. **官方安装器自带校验**——比如 uv 的 `install.ps1`，它内部会验
3. **什么都没有时**——至少把 `Get-FileHash` 的结果打出来写进日志，别默不作声

**不要跳过校验。** 下载完直接跑，等于把「下载被投毒」「传输损坏」两类问题全放过。

### 便携版本的额外风险

zip 便携版多一层解压，可能解出多余文件、覆盖 PATH 里的东西。**解压后核对预期的主程序在不在、版本对不对**，再往 PATH 里加。

---

## 2. PowerShell 7（便携版）

**为什么不装安装程序**：MSI 要管理员，且写注册表；便携 zip 解压即用，删目录即卸载。

```powershell
# 1. 查最新版
$rel = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' `
    -Headers @{ 'User-Agent' = 'pwsh-setup' }
$tag = $rel.tag_name                      # 例如 v7.6.0
$ver = $tag.TrimStart('v')

# 2. 挑 win-x64 的 zip
$asset = $rel.assets | Where-Object { $_.name -like "PowerShell-$ver-win-x64.zip" } | Select-Object -First 1
$asset.name
$asset.browser_download_url
```

```powershell
# 3. 下载并解压
$dst = Join-Path $env:LOCALAPPDATA 'Programs\pwsh'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
$zip = Join-Path $env:TEMP $asset.name
Invoke-WebRequest $asset.browser_download_url -OutFile $zip
# 校验：GitHub Releases 附带 hashes 时可核，没有就打印实际值留档
'实际 sha256 = ' + (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
Expand-Archive $zip -DestinationPath $dst -Force
Remove-Item $zip

# 4. 把目录加进 PATH（上一次的那个 $bin 变量之外，单独加）
$cur = [Environment]::GetEnvironmentVariable('Path','User')
if ($cur -notlike "*$dst*") {
    [Environment]::SetEnvironmentVariable('Path', "$dst;$cur", 'User')
}
```

**验证**（必须新开终端）：

```powershell
pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
```

### pwsh 7 的已知麻烦

| 现象 | 原因 | 怎么办 |
|---|---|---|
| 配置文件带 BOM，某个程序读不了 | 5.1 默认带 BOM，7 默认不带 | 用 7 写配置文件；用 5.1 写的时候显式 `-Encoding utf8NoBOM`（5.1 不支持这个值，见下） |
| 写出来的中文变乱码 | 5.1 的 `Out-File` / `>` 默认 ANSI | 一律用 7；或者显式 `[System.IO.File]::WriteAllText($p,$s,(New-Object System.Text.UTF8Encoding($false)))` |
| `curl` 行为和网上教程不符 | **7 移除了 `curl`/`wget` 别名**。5.1 里 `curl` 是 `Invoke-WebRequest`，7 里是真 curl.exe | 显式写 `Invoke-WebRequest`，别用 `curl` |
| 传参给原生命令时引号被吃掉 | 7.3 起 `$PSNativeCommandArgumentPassing` 默认 `Standard`，规则变了 | 复杂脚本用 here-string：`node -e @'...'@` |
| `&&` 报错 | 5.1 不支持 | 用 7，或者拆成 `if ($?) { ... }` |

**实测补充**：在 `pwsh -Command` 里给 Node / Python 传带引号的脚本，引号会被吞（踩过：`name: "@scope/pkg"` 落盘成 `name: @scope/pkg`，直接把 YAML 写坏）。**唯一可靠的姿势是单引号 here-string**：

```powershell
node --input-type=module -e @'
const x = { name: "@scope/pkg" };
console.log(x.name);
'@
```

---

## 3. Git for Windows

**这个值得用安装程序**：它铺 200+ 个文件，手工摊平不现实，而且安装程序会自动配好 `git` 命令和凭据管理器。

装在哪里让用户选，**后面所有步骤都不要假设路径**。

1. 从 `https://git-scm.com/download/win` 下 64-bit 安装包
2. 安装时**唯一要改的一处**：「Adjusting your PATH environment」选 **Git from the command line and also from 3rd-party software**（默认就是它）
3. 其余全部默认

**装在哪里由安装时的选择决定，不要假设是 `C:\Program Files\Git`。** 装完先现查：

**`Get-GitBin` 的完整定义在 `SKILL.md` 的「PATH 顺序」一节**（带注册表回退，三层降级）。这里不重复贴，避免两处定义不同步。

**调用前必须先加载定义**（定义在 `scripts/utils.ps1`，不在本文件里）：

```powershell
. (Join-Path '<skill-root>' 'scripts/utils.ps1')
$gitbin = Get-GitBin
$gitbin      # 例如 C:\Program Files\Git\usr\bin
```

`$gitbin` 指向的那个目录里就有一整套 GNU 工具：

```
sed  grep  awk  perl  vim  find  xargs  sort  uniq  head  tail
cut  tr  tee  diff  patch  tar  gzip  ssh  scp  xxd  base64
iconv  openssl  seq  basename  dirname  timeout  sleep  ps  kill
```

**里面没有的**（Git for Windows 实测）：`wget` `jq` `rg` `rsync` `make` `vi`。
- 只有 `vim`，没有 `vi`。
- 正则一律 `grep -E`，不要用 `grep` 的旧式扩展匹配。
- `curl` 在 `ucrt64\bin`，不在 `usr\bin`——但 Windows 10 1803+ 自带 `C:\Windows\System32\curl.exe`，通常不需要它。

### 把它加进 PATH（加在**最末尾**）

```powershell
$gitbin = Get-GitBin          # 见上一节，现查出来的，不硬编码
$cur = [Environment]::GetEnvironmentVariable('Path','User')
if ($cur -notlike "*$gitbin*") {
    # 放在末尾，不要放前面
    [Environment]::SetEnvironmentVariable('Path', "$cur;$gitbin", 'User')
}
```

**为什么必须放末尾**：这个目录和 `System32` 有 11 个同名 exe，放前面会全部遮蔽——

```
bash  expand  find  hostname  locale  notepad  reset  sort  tar  timeout  whoami
```

真正会咬人的是 `find`（Windows 的字符串搜索，和 GNU find 完全两回事）、`sort`、`tar`、`timeout`、`whoami`。

放末尾的副作用：GNU 版本要显式路径调用，比如 `& (Join-Path $gitbin 'find.exe') .`。这是可以接受的——**宁可多打几个字，也不要让脚本里的 `find` 悄悄变成另一回事**。

---

## 4. jq

单文件，放 `%USERPROFILE%\.local\bin`。

```powershell
$rel = Invoke-RestMethod 'https://api.github.com/repos/jqlang/jq/releases/latest' `
    -Headers @{ 'User-Agent' = 'jq-setup' }
$a = $rel.assets | Where-Object { $_.name -eq 'jq-windows-amd64.exe' } | Select-Object -First 1
$jqExe = Join-Path $env:USERPROFILE '.local\bin\jq.exe'
Invoke-WebRequest $a.browser_download_url -OutFile $jqExe
'实际 sha256 = ' + (Get-FileHash $jqExe -Algorithm SHA256).Hash.ToLower()
```

验证：`jq --version`

---

## 5. ripgrep

zip 里有 `rg.exe`。

```powershell
$rel = Invoke-RestMethod 'https://api.github.com/repos/BurntSushi/ripgrep/releases/latest' `
    -Headers @{ 'User-Agent' = 'rg-setup' }
$a = $rel.assets | Where-Object { $_.name -like '*x86_64-pc-windows-msvc.zip' } | Select-Object -First 1
$zip = Join-Path $env:TEMP $a.name
Invoke-WebRequest $a.browser_download_url -OutFile $zip
'实际 sha256 = ' + (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
Expand-Archive $zip -DestinationPath (Join-Path $env:TEMP 'rgx') -Force
# zip 里套一层目录，把 rg.exe 挑出来
$exe = Get-ChildItem (Join-Path $env:TEMP 'rgx') -Recurse -Filter 'rg.exe' | Select-Object -First 1
Copy-Item $exe.FullName (Join-Path $env:USERPROFILE '.local\bin\rg.exe') -Force
Remove-Item $zip; Remove-Item (Join-Path $env:TEMP 'rgx') -Recurse -Force
```

验证：`rg --version`

**注意**：`rg` 和 `find` 在 Git Bash 里的路径处理不同。给 rg 传 Windows 路径时用正斜杠或双反斜杠。

---

## 6. uv（含 uvx）

**用官方安装器**，它自己处理 PATH 和后续升级。

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

装到 `%USERPROFILE%\.local\bin`（和上面统一）。它带两个命令：
- `uv`——管解释器、虚拟环境、项目依赖
- `uvx`——直接跑一个包里的命令，不装进当前环境

验证：`uv --version`

**只在用户写 Python 时才装。**

---

## 7. curl / wget

**curl 不用装。** Windows 10 1803+ 自带：

```powershell
C:\Windows\System32\curl.exe --version
```

PowerShell 5.1 里 `curl` 是 `Invoke-WebRequest` 的别名，7 里没有这个别名——**写脚本要显式写 `curl.exe`**。

**wget 不建议装。** GNU 官方不给 Windows 二进制，能拿到的都是第三方重编译。有 curl 就够了，功能重叠。用户点名要再说。

---

## 8. winget 的边界

winget 能装 MSI / Store 包，是唯一能静默装这类东西的路。但它**装不了**上面这些便携版单文件工具，也不该用来装它们。

### 该用的场景

用户想要某个 GUI 软件（VSCode、7-Zip、Python、PowerToys），winget 是最快的路。

```powershell
winget install --id Microsoft.VisualStudioCode -e `
  --accept-package-agreements --accept-source-agreements --disable-interactivity
```

三个参数缺一不可，否则会卡在交互式提示上，在非交互环境里等于挂住。

### 不该用的场景

- **`winget upgrade --all`**——不要跑。它会把用户所有软件一起升级，包括用户特意留在旧版的。
- **批量装本 skill 里的工具**——它们是便携版，winget 里的包路径、版本、安装方式都不可控。
- **winget 不存在时**（Windows Server、精简版、LTSC 早期版本）：不要试图装它。直接走官方 zip 路线，本文件每一节都是这么写的。

### 判断有没有

```powershell
if (Get-Command winget -ErrorAction SilentlyContinue) { "有" } else { "没有，走 zip 路线" }
```

---

## 9. 全部装完的自检

一次跑完，不要分五次。**这段与 `SKILL.md` 里的自检列表保持一致**：

```powershell
$want = 'pwsh','git','sed','perl','vim','jq','rg','uv','uvx'
foreach ($c in $want) {
    $x = Get-Command $c -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($x) { '{0,-6} {1}' -f $c, $x.Source } else { '{0,-6} (缺)' -f $c }
}
'---'
'PSVersion = ' + $PSVersionTable.PSVersion

# Git 的 usr\bin 在不在 PATH 里，在哪一段
$gitbin = $null
try { $gitbin = Get-GitBin } catch { $gitbin = $null }
if ($gitbin) {
    $segs = $env:PATH -split ';'
    $idx = [array]::IndexOf($segs, $gitbin)
    if ($idx -ge 0) { "usr/bin 在 PATH 第 $($idx + 1) 段（共 $($segs.Count) 段）" }
    else { "usr/bin 不在 PATH 里：$gitbin" }
} else { 'Git 未安装或不在 PATH' }
```

**不要用 `Select-String 'usr\\bin' | .LineNumber`**——`Select-String` 对字符串数组返回的是 MatchInfo，`.LineNumber` 是文件行号语义，对 `PATH` 分段没有意义。用 `[array]::IndexOf` 直接取下标。

### 「新开终端」怎么落地

AI 在已经启动的会话里**没法自己新开终端**。这句话不是给 AI 执行的动作，是给用户的指令：

> 请关闭当前终端窗口，新开一个，然后运行：
> `pwsh -NoProfile -Command '$PSVersionTable.PSVersion'`
> 把输出贴回来。

**必须写成这样的用户交互指令**，否则 AI 会卡在「我要怎么新开终端」上。
