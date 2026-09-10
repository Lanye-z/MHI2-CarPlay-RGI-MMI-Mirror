$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$BuildDir = Join-Path $Root 'build'
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$QnxRoot = if ($env:QNX650) { $env:QNX650 } else { 'C:\QNX650' }
$QnxHost = if ($env:QNX_HOST) { $env:QNX_HOST } else { Join-Path $QnxRoot 'host\win32\x86' }
$QnxTarget = if ($env:QNX_TARGET) { $env:QNX_TARGET } else { Join-Path $QnxRoot 'target\qnx6' }

# is linked with the gcc driver and the QNX ARMv7 static libstdc++ archive.
# The Native binary owns pixels only; Java owns terminal1/ctx80.
$Compiler = if ($env:CC) { $env:CC } else { Join-Path $QnxHost 'usr\bin\ntoarmv7-gcc.exe' }
$StaticStdCpp = if ($env:MMI_STATIC_STDCXX) {
    $env:MMI_STATIC_STDCXX
} else {
    Join-Path $QnxTarget 'armle-v7\lib\gcc\4.4.2\libstdc++.a'
}

if (-not (Test-Path $Compiler)) {
    throw "QNX ARMv7 gcc driver not found: $Compiler`nSet QNX650, QNX_HOST/QNX_TARGET, or CC."
}
if (-not (Test-Path $StaticStdCpp)) {
    throw "Static QNX ARMv7 libstdc++ not found: $StaticStdCpp`nSet MMI_STATIC_STDCXX to the correct libstdc++.a path."
}

$env:QNX_HOST = $QnxHost
$env:QNX_TARGET = $QnxTarget

# Keep this list in lock-step with MMI-Mirror/Makefile.
$Sources = @(
    (Join-Path $Root 'src\main_v2.cpp'),
    (Join-Path $Root 'src\v2_options.cpp'),
    (Join-Path $Root 'src\v2_runtime.cpp'),
    (Join-Path $Root 'src\mmi_capture_source.cpp'),
    (Join-Path $Root 'src\cluster_layout_state.cpp'),
    (Join-Path $Root 'src\base_video_layout_controller.cpp'),
    (Join-Path $Root 'src\cluster_video_display.cpp'),
    (Join-Path $Root 'src\mhi2q_backend.cpp'),
    (Join-Path $Root 'src\gl_renderer.cpp')
)

foreach ($Source in $Sources) {
    if (-not (Test-Path $Source)) {
        throw "source file missing: $Source"
    }
}

$Out = Join-Path $BuildDir 'mmi-mirror-display'
$Args = @(
    '-O2',
    '-Wall',
    '-Wextra',
    '-fno-exceptions',
    '-fno-rtti',
    ('-I' + (Join-Path $Root 'src'))
) + $Sources + @(
    '-o', $Out,
    $StaticStdCpp,
    '-lEGL',
    '-lGLESv2',
    '-lm'
)

Write-Host 'MHI2Q MMI Mirror / JAVA80 Native build'
Write-Host "QNX_HOST      = $QnxHost"
Write-Host "QNX_TARGET    = $QnxTarget"
Write-Host "Driver        = $Compiler"
Write-Host "Static C++ ABI= $StaticStdCpp"
Write-Host "Output        = $Out"
Write-Host ''

& $Compiler @Args
if ($LASTEXITCODE -ne 0) {
    throw "QNX build failed with exit code $LASTEXITCODE"
}

Write-Host ''
Write-Host 'Build completed:'
Get-Item $Out | Format-List FullName,Length,LastWriteTime
Get-FileHash $Out -Algorithm SHA256 | Format-List Algorithm,Hash,Path

$ReadElf = Join-Path $QnxHost 'usr\bin\ntoarmv7-readelf.exe'
if (Test-Path $ReadElf) {
    $Dynamic = (& $ReadElf -d $Out 2>&1) -join "`n"
    Write-Host 'Dynamic dependencies:'
    ($Dynamic -split "`n" | Select-String 'NEEDED') | ForEach-Object { Write-Host $_.Line }
    if ($Dynamic -match 'libstdc\+\+') {
        throw 'Unexpected dynamic libstdc++ dependency remains in mmi-mirror-display.'
    }
    Write-Host 'Dependency check OK: no dynamic libstdc++.so dependency.'
}

$Strings = Join-Path $QnxHost 'usr\bin\ntoarmv7-strings.exe'
if (Test-Path $Strings) {
    $Text = (& $Strings $Out 2>&1) -join "`n"
    if ($Text -match '/eso/bin/apps/dmdt|dmdt gs|dmdt sc|dmdt dc') {
        throw 'Forbidden Native context-routing string found in rebuilt mmi-mirror-display.'
    }
    Write-Host 'Context-routing check OK: no dmdt command strings in Native artifact.'
}

Write-Host ''
Write-Host 'NOTE: build_windows.ps1 only builds MMI-Mirror\build\mmi-mirror-display.'
Write-Host 'It does NOT promote or overwrite Toolbox\apps\mmi-mirror\mmi-mirror-display.'
