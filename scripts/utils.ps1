# Git 工具链定位
# 用法：. (Join-Path $PSScriptRoot 'utils.ps1')  或  . '<skill-root>/scripts/utils.ps1'
# 定义后可用：$gitbin = Get-GitBin

function Get-GitBin {
    # ① 正常路径：git 已在 PATH 里
    $exe = (Get-Command git.exe -ErrorAction SilentlyContinue).Source

    # ② 刚装完、PATH 还没刷新：查注册表（64 位视图，再退 32 位视图）
    if (-not $exe) {
        foreach ($k in 'HKLM:\SOFTWARE\GitForWindows',
                       'HKLM:\SOFTWARE\WOW6432Node\GitForWindows') {
            $reg = Get-ItemProperty $k -ErrorAction SilentlyContinue
            if ($reg -and $reg.InstallPath) {
                $cand = Join-Path $reg.InstallPath 'cmd\git.exe'
                if (Test-Path $cand) { $exe = $cand; break }
            }
        }
    }

    if (-not $exe -or -not (Test-Path $exe)) {
        throw '找不到 Git。可能还没装，或装了但 PATH 未刷新——请新开终端后重试。'
    }

    # ③ 从 git.exe 往上找含 usr/bin/sed.exe 的目录（不假设固定层级）
    $d = Split-Path $exe -Parent
    while ($d) {
        if (Test-Path (Join-Path $d 'usr\bin\sed.exe')) { return (Join-Path $d 'usr\bin') }
        $parent = Split-Path $d -Parent
        if ($parent -eq $d) { break }
        $d = $parent
    }
    throw '找到了 git.exe 但没找到 usr\bin——这个 Git 可能是 MSYS2 或 Scoop 的精简安装。'
}
