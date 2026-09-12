param(
    [string]$QnxRoot = "C:\QNX650",
    [string]$RgiSource = "D:\github\mib2q-carplay-rgi-cn",
    [string]$LukaSource = "D:\github\mib2q-carplay-rgi",
    [string]$Output = (Join-Path $PSScriptRoot "..\build-v22\maneuver_render"),
    [switch]$PromoteToToolbox
)

$ErrorActionPreference = "Stop"

$ExpectedRgi = "0c77063b824bcb2368740c483e5bbc5204cb0816"
$ExpectedLuka = "ab93a6c7c6976b667b75133da7f3ef057dd4dce8"

function Assert-Commit([string]$Repo, [string]$Expected, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Repo)) { throw "$Label source missing: $Repo" }
    $actual = (& git -C $Repo rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $actual -ne $Expected) {
        throw "$Label commit mismatch: actual=$actual expected=$Expected"
    }
}

Assert-Commit $RgiSource $ExpectedRgi "RGI"
Assert-Commit $LukaSource $ExpectedLuka "Luka"

$env:QNX_HOST = Join-Path $QnxRoot "host\win32\x86"
$env:QNX_TARGET = Join-Path $QnxRoot "target\qnx6"
$env:QNX_CONFIGURATION = "C:\Program Files (x86)\QNX Software Systems"
$qnxBin = Join-Path $env:QNX_HOST "usr\bin"
$env:PATH = "$qnxBin;$env:PATH"
$compiler = Join-Path $qnxBin "ntoarmv7-gcc.exe"
if (-not (Test-Path -LiteralPath $compiler)) { throw "QNX ARMv7 compiler not found: $compiler" }

$work = Join-Path $PSScriptRoot "..\build-v22\rgi-src"
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $work -Force | Out-Null

# Preserve the user's RGI/Amap renderer protocol and drawing engine. Replace only
# the QNX display backend with Luka's proven displayable98/no-dmdt implementation.
Copy-Item -Path (Join-Path $RgiSource "c_render\*") -Destination $work -Recurse -Force
Copy-Item -LiteralPath (Join-Path $LukaSource "maneuver_render\platform_qnx.c") -Destination (Join-Path $work "platform_qnx.c") -Force
Copy-Item -LiteralPath (Join-Path $LukaSource "common\cluster_surface.c") -Destination (Join-Path $work "cluster_surface.c") -Force
Copy-Item -LiteralPath (Join-Path $LukaSource "common\cluster_surface.h") -Destination (Join-Path $work "cluster_surface.h") -Force

# Keep the RGI platform API (including its QNX preview no-op), changing only the
# generated swap declaration to match Luka's recovery-aware backend. main.c may
# legally ignore the integer return value and otherwise remains byte-for-byte.
$platformHeaderPath = Join-Path $work "platform.h"
$platformHeader = Get-Content -LiteralPath $platformHeaderPath -Raw
$platformHeaderBefore = $platformHeader
$platformHeader = $platformHeader -replace 'void\s+platform_swap\s*\(void\s*\)\s*;', 'int platform_swap(void);'
if ($platformHeader -eq $platformHeaderBefore -or $platformHeader -notmatch 'int\s+platform_swap\s*\(void\s*\)') {
    throw "Could not align generated platform_swap declaration with Luka backend"
}
Set-Content -LiteralPath $platformHeaderPath -Value $platformHeader -Encoding ASCII

$protocolPath = Join-Path $work "protocol.h"
$protocol = Get-Content -LiteralPath $protocolPath -Raw
$before = $protocol
$protocol = $protocol -replace '(?m)^#define\s+CR_DISPLAYABLE_ID\s+20\b.*$', '#define CR_DISPLAYABLE_ID   98  /* V2.2: dedicated managed RGI overlay plane */'
$protocol = $protocol -replace '(?m)^#define\s+CR_CONTEXT_ID\s+74\b.*$', '#define CR_CONTEXT_ID       80  /* V2.2: Java-owned composite context */'
if ($protocol -eq $before -or $protocol -notmatch 'CR_DISPLAYABLE_ID\s+98' -or $protocol -notmatch 'CR_CONTEXT_ID\s+80') {
    throw "Could not patch RGI protocol IDs to displayable98/context80"
}
Set-Content -LiteralPath $protocolPath -Value $protocol -Encoding ASCII
$protocolContract = Select-String -LiteralPath $protocolPath -Pattern '^#define\s+CR_(DISPLAYABLE|CONTEXT)_ID\b'
if ($protocolContract.Count -ne 2) {
    throw "Expected exactly two RGI protocol contract definitions"
}
Write-Host "=== Verified generated protocol.h before compilation ==="
$protocolContract | ForEach-Object { Write-Host $_.Line }

$outputPath = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Path (Split-Path -Parent $outputPath) -Force | Out-Null

$sources = @(
    "main.c",
    "render.c",
    "maneuver.c",
    "route_path.c",
    "server.c",
    "platform_qnx.c",
    "cluster_surface.c"
) | ForEach-Object { Join-Path $work $_ }

$abiInclude = Join-Path $LukaSource "toolchain\qnx65-abi\include"
$screenHeader = Join-Path $abiInclude "screen\screen.h"
if (-not (Test-Path -LiteralPath $screenHeader)) {
    throw "Pinned QNX Screen ABI header not found: $screenHeader"
}

# The generic QNX 6.5 SDK omits the target unit's BSP import libraries. Build
# link-only import stubs with the real SONAMEs; the deployed MIB2 unit supplies
# those libraries. This is the same strategy as Luka's pinned renderer build.
$stubDir = Join-Path $work "link-stubs"
New-Item -ItemType Directory -Path $stubDir -Force | Out-Null

function New-ImportStub([string]$Soname, [string]$Pattern) {
    $symbols = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($source in $sources) {
        $text = Get-Content -LiteralPath $source -Raw
        foreach ($match in [regex]::Matches($text, $Pattern)) {
            [void]$symbols.Add($match.Value)
        }
    }
    if ($symbols.Count -eq 0) { throw "No imported symbols found for $Soname" }

    $stubSource = Join-Path $stubDir (($Soname -replace '[^A-Za-z0-9]', '_') + ".c")
    $stubPath = Join-Path $stubDir $Soname
    $definitions = $symbols | Sort-Object | ForEach-Object { "int $_() { return 0; }" }
    Set-Content -LiteralPath $stubSource -Value $definitions -Encoding ASCII

    & $compiler "-shared" "-fPIC" "-Wl,-soname,$Soname" $stubSource "-o" $stubPath
    if ($LASTEXITCODE -ne 0) { throw "Could not build import stub $Soname" }
    return $stubPath
}

$screenStub = New-ImportStub "libscreen.so.1" '\bscreen_[a-z_]+\b'
$eglStub = New-ImportStub "libEGL.so.1" '\begl[A-Z][A-Za-z0-9_]*\b'
$glesStub = New-ImportStub "libGLESv2.so.1" '\bgl[A-Z][A-Za-z0-9_]*\b'

$nativeCode = ($sources | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"
$nativeCode = [regex]::Replace($nativeCode, '(?s)/\*.*?\*/', '')
$nativeCode = [regex]::Replace($nativeCode, '(?m)//.*$', '')
if ($nativeCode -match 'dmdt\s+(gs|sc)' -or $nativeCode -match '\bpopen\s*\(') {
    throw "Generated renderer contains a forbidden native context-routing code path"
}
if (-not (Select-String -LiteralPath (Join-Path $work "cluster_surface.c") -SimpleMatch -Pattern 'screen_manage_window')) {
    throw "Pinned Luka backend is missing screen_manage_window"
}

$arguments = @(
    "-O2",
    "-std=gnu99",
    "-Wall",
    "-D__QNX__",
    "-DPLATFORM_QNX",
    "-fdata-sections",
    "-ffunction-sections",
    "-I$abiInclude",
    "-I$work"
) + $sources + @(
    "-o", $outputPath,
    "-Wl,--gc-sections",
    "-Wl,--allow-shlib-undefined",
    $screenStub,
    $eglStub,
    $glesStub,
    "-lsocket",
    "-lm"
)

Write-Host "=== Building V2.2 RGI renderer ==="
Write-Host "RGI business/render source: $ExpectedRgi"
Write-Host "Luka QNX plane98 backend:   $ExpectedLuka"
Write-Host "Contract: displayable98 / context80 informational / NO dmdt"
& $compiler @arguments
if ($LASTEXITCODE -ne 0) { throw "QNX renderer compilation failed with exit code $LASTEXITCODE" }

$item = Get-Item -LiteralPath $outputPath
$hash = Get-FileHash -LiteralPath $outputPath -Algorithm SHA256
$item | Select-Object FullName, Length, LastWriteTime
$hash | Select-Object Algorithm, Hash, Path

if ($PromoteToToolbox) {
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
    # V2.2 experimental renderer belongs to MMI Mirror. Never overwrite the
    # stable displayable20 recovery renderer under Toolbox/apps/carplay-rgi.
    $dst = Join-Path $repoRoot "Toolbox\apps\mmi-mirror\maneuver_render-rgi98"
    Copy-Item -LiteralPath $outputPath -Destination $dst -Force
    Write-Host "Promoted V2.2 RGI renderer to MMI-owned path: $dst"
    Write-Warning "Stable Toolbox/apps/carplay-rgi/maneuver_render remains the uninstall/rescue recovery source."
}
