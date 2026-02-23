# scripts/setup-deps.ps1
#
# Builds and installs the custom Grumbel/Pingus libraries that are not available
# in vcpkg. Run this once before the first cmake configure.
#
# Prerequisites:
#   - git
#   - cmake (3.21+)
#   - A C++ compiler (Visual Studio 2022 or MinGW-w64 via MSYS2)
#   - vcpkg installed and VCPKG_ROOT environment variable set
#
# Usage:
#   # MSVC (default):
#   .\scripts\setup-deps.ps1
#
#   # MinGW via MSYS2 (run from MSYS2 MinGW64 shell or set PATH appropriately):
#   .\scripts\setup-deps.ps1 -Triplet x64-mingw-dynamic -Generator Ninja
#
#   # Force reinstall of all libs:
#   .\scripts\setup-deps.ps1 -Force
#
#   # Custom install prefix:
#   .\scripts\setup-deps.ps1 -Prefix C:\my\deps

param(
    # Directory to install the custom libraries into.
    # CMakePresets.json references ${sourceDir}/deps by default.
    [string]$Prefix = (Join-Path $PSScriptRoot "..\deps"),

    # vcpkg target triplet. Use x64-windows for MSVC, x64-mingw-dynamic for MinGW.
    [string]$Triplet = "x64-windows",

    # CMake generator override. Leave empty for cmake auto-detection (Visual Studio on Windows).
    # Use "Ninja" for MinGW builds (requires Ninja in PATH).
    [string]$Generator = "",

    # Path to vcpkg CMake toolchain file.
    # Defaults to $env:VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake.
    [string]$VcpkgToolchain = "",

    # Re-build and re-install a library even if it was previously installed.
    [switch]$Force,

    # Skip the vcpkg standard library installation step.
    [switch]$SkipVcpkg
)

$ErrorActionPreference = "Stop"

# ── Resolve paths ────────────────────────────────────────────────────────────

$Prefix      = [IO.Path]::GetFullPath($Prefix)
$ProjectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$BuildRoot   = Join-Path $ProjectRoot "build-deps"

if (-not $VcpkgToolchain) {
    if ($env:VCPKG_ROOT) {
        $VcpkgToolchain = Join-Path $env:VCPKG_ROOT "scripts/buildsystems/vcpkg.cmake"
    }
}

$VcpkgExe = if ($env:VCPKG_ROOT) { Join-Path $env:VCPKG_ROOT "vcpkg.exe" } else { $null }

# ── Banner ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          Pingus Windows Dependency Setup             ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Install prefix : $Prefix"
Write-Host "  Build cache    : $BuildRoot"
Write-Host "  vcpkg triplet  : $Triplet"
if ($VcpkgToolchain -and (Test-Path $VcpkgToolchain)) {
    Write-Host "  vcpkg toolchain: $VcpkgToolchain"
} else {
    Write-Host "  vcpkg toolchain: NOT FOUND (standard libs may not be found)" -ForegroundColor Yellow
}
if ($Generator) {
    Write-Host "  CMake generator: $Generator"
} else {
    Write-Host "  CMake generator: (cmake auto-detect)"
}
Write-Host ""

# ── Check prerequisites ───────────────────────────────────────────────────────

foreach ($tool in @("git", "cmake")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: '$tool' not found in PATH." -ForegroundColor Red
        Write-Host "       Please install it and ensure it is on your PATH."
        exit 1
    }
}

# ── Create directories ────────────────────────────────────────────────────────

New-Item -ItemType Directory -Force -Path $Prefix    | Out-Null
New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Prefix ".installed") | Out-Null

# ── Step 1: Install standard libs via vcpkg ───────────────────────────────────
#
# These are needed when building wstsound, tinygettext, and uitest.
# We install them into the vcpkg classic-mode store so they are findable
# during the Grumbel lib builds below.

if (-not $SkipVcpkg) {
    if ($VcpkgExe -and (Test-Path $VcpkgExe)) {
        Write-Host "── Step 1: Installing standard libraries via vcpkg ──────────" -ForegroundColor Blue
        $stdLibs = @(
            "sdl2",
            "sdl2-image",
            "glm",          # required by geomcpp (and pingus directly)
            "openal-soft",
            "libogg",
            "libvorbis",
            "mpg123",
            "libmodplug",
            "opus",
            "opusfile",
            "pkgconf"
        )
        $pkgArgs = $stdLibs | ForEach-Object { "$_`:$Triplet" }
        Write-Host "  Running: vcpkg install $($pkgArgs -join ' ')" -ForegroundColor DarkGray
        & $VcpkgExe install @pkgArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: vcpkg install returned non-zero. Some libs may be missing." -ForegroundColor Yellow
        }
        Write-Host ""
    } else {
        Write-Host "── Step 1: Skipping vcpkg (VCPKG_ROOT not set or vcpkg.exe not found) ──" -ForegroundColor Yellow
        Write-Host "   If wstsound/tinygettext/uitest fail to build, install vcpkg and set VCPKG_ROOT."
        Write-Host ""
    }
} else {
    Write-Host "── Step 1: Skipping vcpkg (-SkipVcpkg) ─────────────────────" -ForegroundColor DarkGray
    Write-Host ""
}

# ── Library definitions ───────────────────────────────────────────────────────
#
# Order matters: each entry must come after all of its dependencies.
# Revisions are pinned to match the versions in flake.lock for reproducibility.
#
# CMake package names (used by find_package) differ from repo names in some cases:
#   strutcpp  -> "strut"
#   geomcpp   -> "geom"
#   priocpp   -> "prio"
#   sexp-cpp  -> "sexp"

$LIBS = @(
    @{
        Name   = "tinycmmc"
        Repo   = "https://github.com/grumbel/tinycmmc.git"
        Rev    = "2e007ba059a4991c011a7193c9d7df28826c9adc"
        Flags  = @()
    },
    @{
        Name   = "logmich"
        Repo   = "https://github.com/logmich/logmich.git"
        Rev    = "f69ccb6b8963d995eeb886f60e8c30b2742d596e"
        Flags  = @()
    },
    @{
        # Installs as CMake package "sexp". Required by priocpp.
        Name   = "sexp-cpp"
        Repo   = "https://github.com/lispparser/sexp-cpp.git"
        Rev    = "e33eacf64ee5f1c24ed715ffc62519543bd40d64"
        Flags  = @()
    },
    @{
        # Installs as CMake package "strut".
        Name   = "strutcpp"
        Repo   = "https://github.com/grumbel/strutcpp.git"
        Rev    = "04b3bf106b67a2870c2dc3d9ba843e375a834983"
        Flags  = @()
    },
    @{
        Name   = "argpp"
        Repo   = "https://github.com/grumbel/argpp.git"
        Rev    = "b52420a843327361713b6242e47afaa6b6ab2a89"
        Flags  = @()
    },
    @{
        # Installs as CMake package "geom".
        Name   = "geomcpp"
        Repo   = "https://github.com/grumbel/geomcpp.git"
        Rev    = "d3a94b28cbce9da9a59129919d33ee1465e5b5a3"
        Flags  = @()
    },
    @{
        # Installs as CMake package "prio". Depends on logmich and sexp-cpp.
        # PRIO_USE_SEXPCPP defaults to ON when sexp is findable.
        Name   = "priocpp"
        Repo   = "https://github.com/grumbel/priocpp.git"
        Rev    = "ea15402adcd0d9191dc29ca6f7e4dd0bff67b9b5"
        Flags  = @()
    },
    @{
        # Needs SDL2 from vcpkg (for TINYGETTEXT_WITH_SDL=ON).
        Name   = "tinygettext"
        Repo   = "https://github.com/tinygettext/tinygettext.git"
        Rev    = "ddd8d9a5b9c4c4523b85cb6f722b1d624f11db14"
        Flags  = @("-DTINYGETTEXT_WITH_SDL=ON")
    },
    @{
        # Needs SDL2 from vcpkg.
        Name   = "uitest"
        Repo   = "https://github.com/grumbel/uitest.git"
        Rev    = "2968b238dbf49af082f30d9b6633a085554027e6"
        Flags  = @()
    },
    @{
        # Needs openal-soft, libogg, libvorbis, mpg123, libmodplug, opus, opusfile from vcpkg.
        Name   = "wstsound"
        Repo   = "https://github.com/WindstilleTeam/wstsound.git"
        Rev    = "cd2bbcd7ed0d4fcb57e549803f722dee31b3963e"
        Flags  = @()
    }
)

# ── Build helper ─────────────────────────────────────────────────────────────

function Build-Lib {
    param([hashtable]$Lib)

    $name     = $Lib.Name
    $srcDir   = Join-Path $BuildRoot "src\$name"
    $buildDir = Join-Path $BuildRoot "build\$name"
    $sentinel = Join-Path $Prefix ".installed\$name"

    if ((Test-Path $sentinel) -and -not $Force) {
        Write-Host "  [skip] $name (already installed)" -ForegroundColor DarkGray
        return
    }

    Write-Host "  ► $name" -ForegroundColor Green

    # Clone if needed
    if (-not (Test-Path (Join-Path $srcDir ".git"))) {
        Write-Host "    Cloning $($Lib.Repo) ..." -ForegroundColor DarkGray
        git clone --quiet $Lib.Repo $srcDir
        if ($LASTEXITCODE -ne 0) { throw "git clone failed for $name" }
    }

    # Checkout pinned revision
    Write-Host "    Checking out $($Lib.Rev.Substring(0,8))..." -ForegroundColor DarkGray
    Push-Location $srcDir
    try {
        git checkout --quiet $Lib.Rev 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "git checkout failed for $name" }
    } finally {
        Pop-Location
    }

    # Build cmake argument list
    $args = [System.Collections.Generic.List[string]]@(
        "-S", $srcDir,
        "-B", $buildDir,
        "-DCMAKE_BUILD_TYPE=Release",
        "-DCMAKE_INSTALL_PREFIX=$Prefix",
        "-DCMAKE_PREFIX_PATH=$Prefix",
        "-DWARNINGS=OFF",
        "-DBUILD_TESTS=OFF"
    )

    if ($Generator) {
        $args.AddRange([string[]]@("-G", $Generator))
    }

    # Always pass vcpkg toolchain if available so all libs can find vcpkg packages
    # (e.g. geomcpp needs glm, wstsound needs openal/libogg/etc.)
    if ($VcpkgToolchain -and (Test-Path $VcpkgToolchain)) {
        $args.Add("-DCMAKE_TOOLCHAIN_FILE=$VcpkgToolchain")
        $args.Add("-DVCPKG_TARGET_TRIPLET=$Triplet")
        $args.Add("-DVCPKG_MANIFEST_MODE=OFF")  # Use classic mode (packages installed above)
    }

    foreach ($f in $Lib.Flags) { $args.Add($f) }

    # Configure
    Write-Host "    Configuring..." -ForegroundColor DarkGray
    & cmake @args
    if ($LASTEXITCODE -ne 0) { throw "cmake configure failed for $name" }

    # Build
    Write-Host "    Building..." -ForegroundColor DarkGray
    & cmake --build $buildDir --config Release --parallel
    if ($LASTEXITCODE -ne 0) { throw "cmake build failed for $name" }

    # Install
    Write-Host "    Installing..." -ForegroundColor DarkGray
    & cmake --install $buildDir --config Release
    if ($LASTEXITCODE -ne 0) { throw "cmake install failed for $name" }

    # Mark installed
    New-Item -ItemType File -Force -Path $sentinel | Out-Null
    Write-Host "    ✓ Done" -ForegroundColor Green
}

# ── Step 2: Build and install Grumbel libs ────────────────────────────────────

Write-Host "── Step 2: Building custom libraries ───────────────────────" -ForegroundColor Blue
Write-Host ""

$failed = @()
foreach ($lib in $LIBS) {
    try {
        Build-Lib $lib
    } catch {
        Write-Host "  ERROR: $($lib.Name) - $_" -ForegroundColor Red
        $failed += $lib.Name
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host "══════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "  FAILED: $($failed -join ', ')" -ForegroundColor Red
    Write-Host "  Fix the errors above and re-run setup-deps.ps1." -ForegroundColor Red
    Write-Host "══════════════════════════════════════════════════════════" -ForegroundColor Red
    exit 1
}

Write-Host "══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  All dependencies installed to:" -ForegroundColor Green
Write-Host "    $Prefix" -ForegroundColor Green
Write-Host "" -ForegroundColor Green
Write-Host "  Next steps:" -ForegroundColor Green
Write-Host "    1. Ensure VCPKG_ROOT is set (e.g. setx VCPKG_ROOT C:\vcpkg)" -ForegroundColor Green
Write-Host "    2. cmake --preset windows-vs2022" -ForegroundColor Green
Write-Host "       (or: cmake --preset windows-mingw  for MinGW builds)" -ForegroundColor Green
Write-Host "    3. cmake --build build/windows-vs2022 --config Release" -ForegroundColor Green
Write-Host "    4. cd build/windows-vs2022/Release && .\pingus.exe" -ForegroundColor Green
Write-Host "══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
