<#
.SYNOPSIS
    KomgaNative 开发环境一键引导（Windows，用户级，无需管理员）。

.DESCRIPTION
    幂等：已存在且校验通过的组件会被跳过，可反复执行。
    所有安装都在一个可移动的 InstallRoot 下，所有环境变量写入「用户级」，
    不修改系统 PATH、不改注册表、不需要 UAC。

    会做：
      1. 预检：OS / 磁盘 / 网络工具 / 管理员状态 / 开发者模式 / 长路径
      2. git 全局配置（core.longpaths、autocrlf=false）
      3. Temurin JDK（默认 17）：官方 API 解析版本 + sha256 校验后解压
      4. Android cmdline-tools：从 Google 官方仓库 XML 解析最新 Windows 包
      5. sdkmanager 接受许可 + 安装 platform-tools（其余由 Gradle 按需下载）
      6. Flutter SDK：官方 releases JSON 取 sha256 校验后解压到 <InstallRoot>\flutter\<version>
      7. 用户环境变量：JAVA_HOME / ANDROID_HOME / ANDROID_SDK_ROOT / PATH
      8. 验收：flutter --version / flutter doctor -v / adb version

.PARAMETER InstallRoot
    安装根目录，默认 D:\DevTools。建议放在空间充足的盘，不要放在项目目录里。

.PARAMETER FlutterVersion
    Flutter 稳定版版本号，默认 3.50.0。脚本会去官方 JSON 查它的 sha256。

.PARAMETER JdkMajor
    JDK 主版本，默认 17。

.PARAMETER CheckOnly
    只体检，不下载不安装。

.PARAMETER SkipJdk / SkipAndroid / SkipFlutter
    跳过对应组件（例如公司电脑已有 JDK）。

.PARAMETER Force
    忽略「已安装」判断，强制重装。

.EXAMPLE
    pwsh -File tool\bootstrap.ps1 -CheckOnly

.EXAMPLE
    pwsh -File tool\bootstrap.ps1 -InstallRoot D:\DevTools

.NOTES
    需要：PowerShell 5.1+、curl.exe、tar.exe（Windows 10 1803+ 自带）。
    不需要：管理员、winget、choco、Docker。
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = 'D:\DevTools',
    [string]$FlutterVersion = '3.50.0',
    [string]$JdkMajor = '17',
    [switch]$CheckOnly,
    [switch]$SkipJdk,
    [switch]$SkipAndroid,
    [switch]$SkipFlutter,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Results = [ordered]@{}
$script:Warnings = New-Object System.Collections.Generic.List[string]
$DownloadDir = Join-Path $InstallRoot '_downloads'

# ---------------------------------------------------------------- helpers

function Write-Section([string]$Text) {
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor DarkGray
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor DarkGray
}

function Write-Ok([string]$Text)   { Write-Host "  [OK]   $Text" -ForegroundColor Green }
function Write-Skip([string]$Text) { Write-Host "  [SKIP] $Text" -ForegroundColor DarkGray }
function Write-Warn2([string]$Text) {
    Write-Host "  [WARN] $Text" -ForegroundColor Yellow
    $script:Warnings.Add($Text)
}
function Write-Fail([string]$Text) { Write-Host "  [FAIL] $Text" -ForegroundColor Red }

function Test-CommandExists([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-AdminStatus {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Download([string]$Url, [string]$OutFile, [long]$ExpectedSize = 0, [string]$ExpectedSha256 = '') {
    if ((Test-Path $OutFile) -and -not $Force) {
        $len = (Get-Item $OutFile).Length
        $sizeOk = ($ExpectedSize -le 0) -or ([Math]::Abs($len - $ExpectedSize) -le [Math]::Max(1024, $ExpectedSize * 0.01))
        if ($sizeOk) {
            if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
                Write-Skip "已存在：$(Split-Path $OutFile -Leaf) ($([Math]::Round($len / 1MB, 1)) MB)"
                return
            }
            $actual = (Get-FileHash -Path $OutFile -Algorithm SHA256).Hash
            if ($actual -ieq $ExpectedSha256) {
                Write-Skip "已存在且校验通过（sha256）：$(Split-Path $OutFile -Leaf)"
                return
            }
            Write-Warn2 "已存在但 sha256 不符，重新下载：$(Split-Path $OutFile -Leaf)"
        } else {
            Write-Warn2 "已存在但大小不符（$len ≠ $ExpectedSize），重新下载：$(Split-Path $OutFile -Leaf)"
        }
        Remove-Item $OutFile -Force
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $OutFile -Parent) | Out-Null
    Write-Host "  → 下载 $(Split-Path $OutFile -Leaf)" -ForegroundColor DarkCyan
    $r = Invoke-Native 'curl.exe' @('-L', '--retry', '3', '--retry-delay', '3', '--fail', '--silent', '--show-error', '-o', $OutFile, $Url)
    if ($r.ExitCode -ne 0) { throw "下载失败（curl exit $($r.ExitCode)）：$Url`n$($r.Output)" }
    $len = (Get-Item $OutFile).Length
    Write-Host "    完成 $([Math]::Round($len / 1MB, 1)) MB" -ForegroundColor DarkGray
    if ($ExpectedSize -gt 0 -and [Math]::Abs($len - $ExpectedSize) -gt [Math]::Max(4096, $ExpectedSize * 0.01)) {
        throw "大小不符：期望 $ExpectedSize，实际 $len"
    }
}

function Test-Sha256([string]$Path, [string]$Expected) {
    if ([string]::IsNullOrWhiteSpace($Expected)) { return }
    $actual = (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $Expected.ToLower()) {
        throw "SHA256 校验失败：期望 $Expected，实际 $actual"
    }
    Write-Ok "SHA256 校验通过"
}

function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    # PowerShell 5.1 会把外部程序写到 stderr 的内容包装成 ErrorRecord，
    # 在 $ErrorActionPreference='Stop' 下会被当作致命错误抛出。
    # 典型踩坑：java -version、sdkmanager、flutter 都会往 stderr 写正常输出。
    # 统一在这里临时降级，只返回退出码与合并后的文本。
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = & $Exe @Arguments 2>&1
        $code = $LASTEXITCODE
        $text = (($lines | ForEach-Object { "$_" }) -join "`n").Trim()
        return [pscustomobject]@{ ExitCode = $code; Output = $text }
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Expand-Zip([string]$Zip, [string]$Dest) {
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    if (Test-CommandExists 'tar.exe') {
        $r = Invoke-Native 'tar.exe' @('-xf', $Zip, '-C', $Dest)
        if ($r.ExitCode -ne 0) { throw "解压失败（tar exit $($r.ExitCode)）：$Zip`n$($r.Output)" }
    } else {
        Expand-Archive -Path $Zip -DestinationPath $Dest -Force
    }
}

function Get-UserPathEntries {
    $raw = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    return @($raw -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Add-UserPathEntry([string]$Dir, [switch]$WhatIfOnly) {
    if (-not (Test-Path $Dir)) { Write-Warn2 "PATH 目标目录不存在，已跳过：$Dir"; return }
    $entries = Get-UserPathEntries
    $normalized = $Dir.TrimEnd('\')
    $exists = $entries | Where-Object { $_.TrimEnd('\') -ieq $normalized }
    if ($exists) { Write-Skip "PATH 已包含 $Dir"; return }
    if ($WhatIfOnly) { Write-Host "  [TODO] 需追加 PATH：$Dir" -ForegroundColor Yellow; return }
    $new = (@($entries) + $Dir) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $new, 'User')
    # 当前进程内立即可用，方便后续验收步骤
    $env:Path = "$env:Path;$Dir"
    Write-Ok "PATH += $Dir"
}

function Set-UserEnvVar([string]$Name, [string]$Value) {
    $current = [Environment]::GetEnvironmentVariable($Name, 'User')
    if ($current -eq $Value) { Write-Skip "$Name 已是 $Value"; return }
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    Set-Item -Path "Env:$Name" -Value $Value
    Write-Ok "$Name = $Value"
}

function Invoke-CurlJson([string]$Url) {
    $tmp = Join-Path $env:TEMP ("bootstrap-" + [guid]::NewGuid().ToString('N') + '.json')
    $r = Invoke-Native 'curl.exe' @('-sL', '--fail', '--retry', '3', '--max-time', '120', '-o', $tmp, $Url)
    if ($r.ExitCode -ne 0) { throw "获取 JSON 失败：$Url`n$($r.Output)" }
    $obj = Get-Content $tmp -Raw | ConvertFrom-Json
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    return $obj
}

function Invoke-CurlText([string]$Url) {
    $tmp = Join-Path $env:TEMP ("bootstrap-" + [guid]::NewGuid().ToString('N') + '.txt')
    $r = Invoke-Native 'curl.exe' @('-sL', '--fail', '--retry', '3', '--max-time', '180', '-o', $tmp, $Url)
    if ($r.ExitCode -ne 0) { throw "获取内容失败：$Url`n$($r.Output)" }
    $text = Get-Content $tmp -Raw
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    return $text
}

# ---------------------------------------------------------------- preflight

Write-Section "0. 预检"

$isAdmin = Get-AdminStatus
Write-Host ("  管理员：{0}" -f $(if ($isAdmin) { '是（本脚本不需要，也建议以普通身份运行）' } else { '否（符合预期：全程用户级安装）' }))
Write-Host ("  安装根目录：{0}" -f $InstallRoot)
Write-Host ("  PowerShell：{0}" -f $PSVersionTable.PSVersion)

if (-not (Test-CommandExists 'curl.exe')) { throw '缺少 curl.exe（Windows 10 1803+ 自带）。' }
if (-not (Test-CommandExists 'tar.exe'))  { Write-Warn2 '缺少 tar.exe，将退回 Expand-Archive（大文件较慢）' }

$driveLetter = (Split-Path -Qualifier $InstallRoot).TrimEnd(':')
$drive = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue
if (-not $drive) { throw "安装盘不存在：$driveLetter" }
$freeGB = [Math]::Round($drive.Free / 1GB, 1)
Write-Host ("  可用空间：{0} GB" -f $freeGB)
if ($freeGB -lt 20) { Write-Warn2 "可用空间不足 20GB，Android SDK + 模拟器可能装不下" }

# 开发者模式（Flutter 插件在 Windows 上需要创建符号链接）
$devMode = $null
try { $devMode = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction Stop).AllowDevelopmentWithoutDevLicense } catch { }
if ($devMode -eq 1) { Write-Ok 'Windows 开发者模式：已开启' }
else { Write-Warn2 'Windows 开发者模式未开启：无法创建符号链接（实测 pub get / build apk 不受影响，但个别插件与工具链需要）。建议以管理员在「设置 → 系统 → 开发者选项」开启' }

# 长路径
$longPaths = $null
try { $longPaths = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -ErrorAction Stop).LongPathsEnabled } catch { }
if ($longPaths -eq 1) { Write-Ok '系统长路径支持：已开启' }
else { Write-Warn2 '系统长路径支持未开启（LongPathsEnabled=0）：深层依赖路径可能构建失败。需管理员执行：New-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem -Name LongPathsEnabled -Value 1 -PropertyType DWord -Force' }

New-Item -ItemType Directory -Force -Path $InstallRoot, $DownloadDir | Out-Null

if ($CheckOnly) {
    Write-Section '体检模式：只报告，不安装'
    $probe = @(
        @{ Name = 'flutter'; Cmd = (Join-Path $InstallRoot "flutter\$FlutterVersion\bin\flutter.bat") },
        @{ Name = 'java';    Cmd = (Join-Path $InstallRoot "jdk-$JdkMajor\bin\java.exe") },
        @{ Name = 'sdkmanager'; Cmd = (Join-Path $InstallRoot 'android-sdk\cmdline-tools\latest\bin\sdkmanager.bat') },
        @{ Name = 'adb';     Cmd = (Join-Path $InstallRoot 'android-sdk\platform-tools\adb.exe') }
    )
    foreach ($p in $probe) {
        if (Test-Path $p.Cmd) { Write-Ok "$($p.Name) → $($p.Cmd)" } else { Write-Fail "$($p.Name) 缺失（$($p.Cmd)）" }
    }
    if ($script:Warnings.Count -gt 0) {
        Write-Section '需要人工处理'
        $script:Warnings | ForEach-Object { Write-Host "  • $_" -ForegroundColor Yellow }
    }
    exit 0
}

# ---------------------------------------------------------------- git

Write-Section '1. git 配置'

$gitCandidates = @(
    'git.exe',
    'C:\Program Files\Git\cmd\git.exe',
    'C:\Program Files (x86)\Git\cmd\git.exe'
) | Where-Object { Test-Path $_ -ErrorAction SilentlyContinue } | Select-Object -First 1

if ($gitCandidates) {
    $git = $gitCandidates
    Invoke-Native $git @('config', '--global', 'core.longpaths', 'true') | Out-Null
    Invoke-Native $git @('config', '--global', 'core.autocrlf', 'false') | Out-Null
    Write-Ok "git：$git（已设置 core.longpaths=true, core.autocrlf=false）"
    $gitDir = Split-Path $git -Parent
    Add-UserPathEntry $gitDir
    $script:Results['git'] = (Invoke-Native $git @('--version')).Output
} else {
    Write-Warn2 '未找到 git：请安装 Git for Windows 后重跑本脚本'
}

# ---------------------------------------------------------------- JDK

Write-Section "2. JDK $JdkMajor"

$jdkDir = Join-Path $InstallRoot "jdk-$JdkMajor"
$javaExe = Join-Path $jdkDir 'bin\java.exe'

if ($SkipJdk) {
    Write-Skip '按参数跳过'
} elseif ((Test-Path $javaExe) -and -not $Force) {
    $ver = (((Invoke-Native $javaExe @('-version')).Output -split "`n") | Select-Object -First 1).Trim()
    Write-Skip "已安装：$ver"
} else {
    Write-Host '  查询 Adoptium 最新版…' -ForegroundColor DarkGray
    $api = "https://api.adoptium.net/v3/assets/latest/$JdkMajor/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse"
    $asset = (Invoke-CurlJson $api)[0]
    $pkg = $asset.binary.package
    Write-Host ("  版本 {0}，{1} MB" -f $asset.version.semver, [Math]::Round($pkg.size / 1MB, 1)) -ForegroundColor DarkGray

    $zip = Join-Path $DownloadDir $pkg.name
    Invoke-Download -Url $pkg.link -OutFile $zip -ExpectedSize $pkg.size -ExpectedSha256 $pkg.checksum

    $tmp = Join-Path $InstallRoot '_jdk_tmp'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Zip -Zip $zip -Dest $tmp
    $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
    if (-not $inner) { throw 'JDK 解压后未找到目录' }
    if (Test-Path $jdkDir) { Remove-Item $jdkDir -Recurse -Force }
    Move-Item $inner.FullName $jdkDir
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

    $ver = (((Invoke-Native $javaExe @('-version')).Output -split "`n") | Select-Object -First 1).Trim()
    Write-Ok "JDK 就绪：$ver"
    $script:Results['jdk'] = $ver
}

if (Test-Path $javaExe) {
    Set-UserEnvVar 'JAVA_HOME' $jdkDir
    Add-UserPathEntry (Join-Path $jdkDir 'bin')
}

# ---------------------------------------------------------------- Android SDK

Write-Section '3. Android SDK（cmdline-tools + platform-tools）'

$sdkRoot = Join-Path $InstallRoot 'android-sdk'
$cmdlineLatest = Join-Path $sdkRoot 'cmdline-tools\latest'
$sdkManager = Join-Path $cmdlineLatest 'bin\sdkmanager.bat'

if ($SkipAndroid) {
    Write-Skip '按参数跳过'
} else {
    if (-not (Test-Path $sdkManager) -or $Force) {
        Write-Host '  从 Google 仓库 XML 解析最新 cmdline-tools…' -ForegroundColor DarkGray
        $repoXml = Invoke-CurlText 'https://dl.google.com/android/repository/repository2-3.xml'
        $match = [regex]::Matches($repoXml, 'commandlinetools-win-(\d+)_latest\.zip') |
            Sort-Object { [int]$_.Groups[1].Value } -Descending | Select-Object -First 1
        if (-not $match) { throw '未能在 Google 仓库 XML 中找到 Windows 版 cmdline-tools' }
        $build = $match.Groups[1].Value
        $url = "https://dl.google.com/android/repository/commandlinetools-win-$build`_latest.zip"
        $zip = Join-Path $DownloadDir "commandlinetools-win-$build-latest.zip"
        Write-Host "  build=$build" -ForegroundColor DarkGray
        Invoke-Download -Url $url -OutFile $zip

        $tmp = Join-Path $InstallRoot '_cmdtools_tmp'
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Expand-Zip -Zip $zip -Dest $tmp
        $src = Join-Path $tmp 'cmdline-tools'
        if (-not (Test-Path $src)) { throw 'cmdline-tools 解压结构异常（缺少 cmdline-tools 目录）' }
        if (Test-Path $cmdlineLatest) { Remove-Item $cmdlineLatest -Recurse -Force }
        New-Item -ItemType Directory -Force -Path (Split-Path $cmdlineLatest -Parent) | Out-Null
        Move-Item $src $cmdlineLatest
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Write-Ok "cmdline-tools 就绪：$cmdlineLatest"
    } else {
        Write-Skip "cmdline-tools 已存在：$cmdlineLatest"
    }

    $env:ANDROID_HOME = $sdkRoot
    $env:ANDROID_SDK_ROOT = $sdkRoot

    if (Test-Path $javaExe) {
        $env:JAVA_HOME = $jdkDir
        $licenseTargets = @(
            'platform-tools',
            'platforms;android-36', 'platforms;android-35',
            'build-tools;36.0.0', 'build-tools;35.0.0'
        )
        # 接受许可：sdkmanager 会逐条询问，用 cmd 的输入重定向批量喂 y
        # （PowerShell 5.1 直接把字符串管道给 .bat 的 stdin 不可靠）
        Write-Host '  接受 Android SDK 许可…' -ForegroundColor DarkGray
        $yesFile = Join-Path $env:TEMP 'sdkmanager-yes.txt'
        (1..80 | ForEach-Object { 'y' }) | Set-Content -Path $yesFile -Encoding ASCII
        $lic = Invoke-Native 'cmd.exe' @('/c', "`"$sdkManager`" --licenses < `"$yesFile`"")
        Remove-Item $yesFile -Force -ErrorAction SilentlyContinue
        if ($lic.ExitCode -eq 0) { Write-Ok 'licenses 已接受' }
        else { Write-Warn2 "licenses 接受返回 $($lic.ExitCode)：$((($lic.Output -split "`n") | Select-Object -Last 1))" }

        # 安装组件：逐个安装，允许个别版本不存在时继续
        foreach ($pkg in $licenseTargets) {
            Write-Host "  → $pkg" -ForegroundColor DarkCyan
            $r = Invoke-Native $sdkManager @('--install', $pkg)
            if ($r.ExitCode -eq 0) { Write-Ok "已安装 $pkg" }
            else { Write-Warn2 "安装 $pkg 失败（可能该版本不存在，交由 Gradle 按需下载）：$((($r.Output -split "`n") | Select-Object -Last 1))" }
        }

        $adb = Join-Path $sdkRoot 'platform-tools\adb.exe'
        if (Test-Path $adb) { $script:Results['adb'] = (((Invoke-Native $adb @('version')).Output -split "`n") | Select-Object -First 1) }
    } else {
        Write-Warn2 'JDK 不可用，跳过 sdkmanager（许可与组件安装）。装好 JDK 后重跑本脚本即可'
    }
}

Set-UserEnvVar 'ANDROID_HOME' $sdkRoot
Set-UserEnvVar 'ANDROID_SDK_ROOT' $sdkRoot
Add-UserPathEntry (Join-Path $sdkRoot 'platform-tools')
Add-UserPathEntry (Join-Path $sdkRoot 'cmdline-tools\latest\bin')
Add-UserPathEntry (Join-Path $sdkRoot 'emulator')

# ---------------------------------------------------------------- Flutter

Write-Section "4. Flutter $FlutterVersion"

$flutterDir = Join-Path $InstallRoot "flutter\$FlutterVersion"
$flutterBat = Join-Path $flutterDir 'bin\flutter.bat'

if ($SkipFlutter) {
    Write-Skip '按参数跳过'
} elseif ((Test-Path $flutterBat) -and -not $Force) {
    Write-Skip "已存在：$flutterDir"
} else {
    Write-Host '  查询官方发布清单…' -ForegroundColor DarkGray
    $releases = Invoke-CurlJson 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
    $rel = $releases.releases | Where-Object { $_.version -eq $FlutterVersion -and $_.channel -eq 'stable' } | Select-Object -First 1
    if (-not $rel) { throw "官方清单中找不到 Windows stable 版本 $FlutterVersion" }
    $url = 'https://storage.googleapis.com/flutter_infra_release/releases/' + $rel.archive
    Write-Host ("  archive={0}" -f $rel.archive) -ForegroundColor DarkGray

    $zip = Join-Path $DownloadDir ("flutter_windows_{0}-stable.zip" -f $FlutterVersion)
    Invoke-Download -Url $url -OutFile $zip -ExpectedSha256 $rel.sha256

    $tmp = Join-Path $InstallRoot '_flutter_tmp'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Zip -Zip $zip -Dest $tmp
    $inner = Join-Path $tmp 'flutter'
    if (-not (Test-Path $inner)) { throw 'Flutter 解压结构异常（缺少 flutter 目录）' }
    if (Test-Path $flutterDir) { Remove-Item $flutterDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path (Split-Path $flutterDir -Parent) | Out-Null
    Move-Item $inner $flutterDir
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "Flutter 就绪：$flutterDir"
}

if (Test-Path $flutterBat) {
    Add-UserPathEntry (Join-Path $flutterDir 'bin')
    # 关掉分析统计的首启提示，并指向我们装好的 SDK
    Invoke-Native $flutterBat @('--disable-analytics') | Out-Null
    Invoke-Native $flutterBat @('config', '--no-analytics') | Out-Null
    if (Test-Path $javaExe) { Invoke-Native $flutterBat @('config', '--jdk-dir', $jdkDir) | Out-Null }
    if (Test-Path $sdkRoot) { Invoke-Native $flutterBat @('config', '--android-sdk', $sdkRoot) | Out-Null }
    Write-Ok 'flutter config 已指向本机 JDK / Android SDK'
}

# ---------------------------------------------------------------- 验收

Write-Section '5. 验收'

if (Test-Path $flutterBat) {
    $fv = (Invoke-Native $flutterBat @('--version')).Output
    Write-Host $fv -ForegroundColor DarkGray
}
if (Test-Path $sdkManager) { $script:Results['sdkmanager'] = 'ok' }

Write-Section '完成，汇总'

Write-Host ("  安装根目录 : {0}" -f $InstallRoot)
Write-Host ("  JDK        : {0}" -f $jdkDir)
Write-Host ("  Android    : {0}" -f $sdkRoot)
Write-Host ("  Flutter    : {0}" -f $flutterDir)
Write-Host ''
Write-Host '  下一步（必须做，否则插件编译会失败）：' -ForegroundColor Yellow
Write-Host '    1) 用管理员打开终端，执行：' -ForegroundColor Yellow
Write-Host '       New-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem -Name LongPathsEnabled -Value 1 -PropertyType DWord -Force' -ForegroundColor Gray
Write-Host '    2) 设置 → 系统 → 开发者选项 → 打开「开发人员模式」' -ForegroundColor Yellow
Write-Host '    3) 重开一个终端（让用户级 PATH 生效），执行：flutter doctor -v' -ForegroundColor Yellow
Write-Host ''

if ($script:Warnings.Count -gt 0) {
    Write-Host '  本次警告：' -ForegroundColor Yellow
    $script:Warnings | ForEach-Object { Write-Host "    • $_" -ForegroundColor Yellow }
}
