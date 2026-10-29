<#
.SYNOPSIS
  在没有 Mac 的情况下，尽可能真实地检查这个 iOS 工程的逻辑层。

.DESCRIPTION
  用 Windows 版 Swift 编译器 + 最小平台桩，完成三件事：
    1. 引擎层类型检查（真实编译，捕获类型与成员错误）
    2. 格式化与解析断言
    3. 引擎行为断言（含限时到点、暂停不累计、重启恢复）

  再加上三个 Python 静态检查，覆盖了除 SwiftUI 视图之外的所有层面。
  视图层仍需在 Mac 的 Xcode 里编译验证。

.PARAMETER StaticOnly
  只跑静态检查，不编译 Swift。

.EXAMPLE
  .\Scripts\typecheck-engine.ps1
#>

[CmdletBinding()]
param(
    [switch]$StaticOnly
)

# 原生命令会往 stderr 写正常日志（如 swiftc 的「正在创建库」），
# 所以不能用 Stop，改为显式检查退出码。
$ErrorActionPreference = 'Continue'

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

$failures = 0

function Add-Pass([string]$label) {
    Write-Host "  [通过] $label" -ForegroundColor Green
}

function Add-Fail([string]$label, [string]$detail) {
    Write-Host "  [失败] $label" -ForegroundColor Red
    if ($detail) { Write-Host "         $detail" -ForegroundColor DarkGray }
    $script:failures++
}

function Find-SwiftBin {
    foreach ($base in @(
        "$env:LOCALAPPDATA\Programs\Swift\Toolchains",
        "C:\Program Files\Swift\Toolchains",
        "C:\Library\Developer\Toolchains")) {
        if (-not (Test-Path $base)) { continue }
        $bin = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'usr\bin' } |
            Where-Object { Test-Path (Join-Path $_ 'swiftc.exe') } |
            Select-Object -First 1
        if ($bin) { return $bin }
    }
    return $null
}

function Find-WindowsSdk([string]$SwiftRoot) {
    $platform = Get-ChildItem (Join-Path $SwiftRoot 'Platforms') -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $platform) { return $null }
    $sdk = Join-Path $platform.FullName 'Windows.platform\Developer\SDKs\Windows.sdk'
    if (Test-Path $sdk) { return $sdk }
    return $null
}

function Find-RuntimeBin([string]$SwiftRoot) {
    $rt = Get-ChildItem (Join-Path $SwiftRoot 'Runtimes') -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'usr\bin' } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1
    return $rt
}

function Get-MsvcIncludes {
    $vs = Get-ChildItem 'C:\Program Files (x86)\Microsoft Visual Studio\2022' -Directory -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $vs) { return $null }
    $msvc = Get-ChildItem (Join-Path $vs.FullName 'VC\Tools\MSVC') -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $msvc) { return $null }
    $winSdk = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\Include' -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $winSdk) { return $null }

    return @(
        (Join-Path $msvc.FullName 'include')
        (Join-Path $msvc.FullName 'atlmfc\include')
        (Join-Path $winSdk.FullName 'ucrt')
        (Join-Path $winSdk.FullName 'um')
        (Join-Path $winSdk.FullName 'shared')
    ) | Where-Object { Test-Path $_ }
}

function Find-Python {
    foreach ($c in @('python', 'python3', 'py')) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

function Invoke-PythonScript([string]$Python, [string]$Script) {
    $env:PYTHONIOENCODING = 'utf-8'
    $output = & $Python $Script 2>&1
    $code = $LASTEXITCODE
    $output | ForEach-Object { Write-Host "  $_" }
    return $code
}

Write-Host "== 1/4 静态结构检查 ==" -ForegroundColor Cyan

$python = Find-Python
if (-not $python) {
    Add-Fail "Python 不可用" "静态检查脚本需要 Python 3"
} else {
    $staticScripts = @(
        @{ Name = '源码结构（括号 / UTF-8）'; Path = 'Scripts\structure-check.py' }
        @{ Name = '视图引用 vs 引擎 API';     Path = 'Scripts\api-check.py' }
        @{ Name = '工程文件与资源';           Path = 'Scripts\check-project.py' }
    )
    foreach ($s in $staticScripts) {
        $code = Invoke-PythonScript $python $s.Path
        if ($code -eq 0) { Add-Pass $s.Name } else { Add-Fail $s.Name "退出码 $code" }
    }
}

if ($StaticOnly) {
    Write-Host ''
    if ($failures -eq 0) {
        Write-Host "静态检查全部通过。" -ForegroundColor Green
        exit 0
    }
    Write-Host "$failures 项失败。" -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host "== 2/4 准备 Swift 工具链 ==" -ForegroundColor Cyan

$swiftBin = Find-SwiftBin
if (-not $swiftBin) {
    Write-Host "  未找到 Swift 编译器，跳过类型检查与行为测试。" -ForegroundColor Yellow
    Write-Host "  安装：winget install --id Swift.Toolchain --exact" -ForegroundColor Yellow
} else {
# <root>\Toolchains\<ver>\usr\bin 向上三层才是 Swift 安装根目录
    $swiftRoot = Split-Path (Split-Path (Split-Path (Split-Path $swiftBin)))
    $sdk = Find-WindowsSdk $swiftRoot
    $runtimeBin = Find-RuntimeBin $swiftRoot
    $includes = Get-MsvcIncludes

    if ($runtimeBin) {
        # 编出来的 exe 依赖 Swift 运行库 DLL；缺了会报 0xC0000135
        $env:Path = "$runtimeBin;$env:Path"
        Add-Pass "Swift 运行库在 PATH"
    }

    if (-not $sdk) {
        Add-Fail "找不到 Windows SDK" "Swift 安装不完整"
    } elseif (-not $includes) {
        Add-Fail "缺 MSVC 头文件" "winget install --id Microsoft.VisualStudio.2022.BuildTools --override '--quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'"
    } else {
        Add-Pass "Windows SDK 与 MSVC 头文件就绪"

        $swiftc = Join-Path $swiftBin 'swiftc.exe'
        $swiftFrontend = Join-Path $swiftBin 'swift-frontend.exe'

        # 每个 -I 必须单独传给 clang
        $xcc = @()
        foreach ($dir in $includes) { $xcc += @('-Xcc', "-I$dir") }

        New-Item -ItemType Directory -Force -Path build | Out-Null

        $engineSources = @(
            'Scripts\TypecheckSupport\PlatformStub.swift'
            'LapTimer\TimeFormatting.swift'
            'LapTimer\TimerModels.swift'
            'LapTimer\SessionStore.swift'
            'LapTimer\Feedback.swift'
            'LapTimer\Notifier.swift'
            'LapTimer\StopwatchEngine.swift'
            'LapTimer\CountdownEngine.swift'
            'LapTimer\HistoryStore.swift'
        )

        Write-Host ''
        Write-Host "== 3/4 引擎层类型检查 ==" -ForegroundColor Cyan
        $tc = & $swiftFrontend -sdk $sdk @xcc -typecheck @engineSources 2>&1
        $code = $LASTEXITCODE
        if ($code -eq 0) {
            Add-Pass "引擎层类型检查（9 个源文件）"
        } else {
            Add-Fail "引擎层类型检查" (($tc | Select-Object -First 6) -join "`n")
        }

        Write-Host ''
        Write-Host "== 4/4 行为断言 ==" -ForegroundColor Cyan

        $logicExe = 'build\logic-check.exe'
        $compile = & $swiftc -sdk $sdk @xcc 'LapTimer\TimeFormatting.swift' 'Scripts\logic-check.swift' -o $logicExe 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-Fail "格式化逻辑断言编译" (($compile | Select-Object -First 4) -join "`n")
        } else {
            $out = & ".\$logicExe" 2>&1
            $code = $LASTEXITCODE
            $out | Where-Object { $_ -match 'FAIL|项失败|全部通过' } | ForEach-Object { Write-Host "  $_" }
            $count = ($out | Where-Object { $_ -match '  ok   |  FAIL ' }).Count
            if ($code -eq 0) { Add-Pass "格式化与解析断言（$count 项）" } else { Add-Fail "格式化与解析断言" "退出码 $code" }
        }

        $engineExe = 'build\engine-check.exe'
        $compile2 = & $swiftc -sdk $sdk @xcc @engineSources 'Scripts\engine-check.swift' -o $engineExe 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-Fail "引擎行为断言编译" (($compile2 | Select-Object -First 4) -join "`n")
        } else {
            $out2 = & ".\$engineExe" 2>&1
            $code2 = $LASTEXITCODE
            $out2 | Where-Object { $_ -match 'FAIL|项失败|全部通过' } | ForEach-Object { Write-Host "  $_" }
            $count2 = ($out2 | Where-Object { $_ -match '  ok   |  FAIL ' }).Count
            if ($code2 -eq 0) { Add-Pass "引擎行为断言（$count2 项）" } else { Add-Fail "引擎行为断言" "退出码 $code2" }
        }

        Remove-Item '.enginecheck-store' -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item 'build\logic-check.lib', 'build\logic-check.exp' -Force -ErrorAction SilentlyContinue
        Remove-Item 'build\engine-check.lib', 'build\engine-check.exp' -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
if ($failures -eq 0) {
    Write-Host "全部通过。" -ForegroundColor Green
} else {
    Write-Host "$failures 项失败。" -ForegroundColor Red
}
Write-Host ''
Write-Host "说明：SwiftUI 视图层无法在 Windows 上编译，仍需在 Mac 上打开 Xcode 验证。" -ForegroundColor Yellow

exit ([int]($failures -ne 0))
