# Build script for CustomDLL

# Parse command line arguments
param(
    [string]$ApiUrl = "https://localhost/api/index.php",
    [int]$Timeout = 4,
    [int]$ConnectTimeout = 2,
    [int]$ServerPort = 8080,
    [string]$BuildType = "Release",
    [ValidateSet("Runtime", "Static", "Both")]
    [string]$ConfigType = "Both",
    [switch]$BuildTools = $true,
    [switch]$BuildGoServer = $false,
    [switch]$BuildContactCenterSimulator = $false
)

# Change to the root directory (script is in scripts/ folder)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
Set-Location $rootDir

# Create directories if they don't exist
if (-not (Test-Path "build")) {
    New-Item -ItemType Directory -Path "build" | Out-Null
}

if (-not (Test-Path "dist")) {
    New-Item -ItemType Directory -Path "dist" | Out-Null
}

Write-Host "Building CustomDLL with the following settings:"
Write-Host "API URL: $ApiUrl"
Write-Host "Timeout: $Timeout seconds"
Write-Host "Connect Timeout: $ConnectTimeout seconds"
Write-Host "Server Port: $ServerPort"
Write-Host "Build Type: $BuildType"
Write-Host "Configuration Type: $ConfigType (Runtime = config.ini support, Static = compile-time only)"
Write-Host "Build Tools: $BuildTools"
Write-Host "Build Go Server: $BuildGoServer"
Write-Host "Build Contact Center Simulator: $BuildContactCenterSimulator"

# Check if CMake is installed
$cmakeInstalled = Get-Command "cmake" -ErrorAction SilentlyContinue
if (-not $cmakeInstalled) {
    Write-Host "Error: CMake is not installed or not in the PATH." -ForegroundColor Red
    Write-Host "Please install CMake from https://cmake.org/download/ and make sure it's in your PATH." -ForegroundColor Red
    Write-Host "Alternatively, you can add the CMake bin directory to your PATH environment variable." -ForegroundColor Red
    exit 1
}

# Configure CMake
# Try to detect Visual Studio generator
$vsGenerator = ""
if (Get-Command "vswhere" -ErrorAction SilentlyContinue) {
    $vsPath = & vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
    if ($vsPath) {
        $vsVersion = (Get-Item $vsPath).BaseName
        if ($vsVersion -match "2022") {
            $vsGenerator = "Visual Studio 17 2022"
        } elseif ($vsVersion -match "2019") {
            $vsGenerator = "Visual Studio 16 2019"
        } elseif ($vsVersion -match "2017") {
            $vsGenerator = "Visual Studio 15 2017"
        }
    }
}

# If Visual Studio not found, try to use alternative generators
if (-not $vsGenerator) {
    Write-Host "Visual Studio not detected. Trying alternative generators..." -ForegroundColor Yellow

    # First, check for manually installed build tools
    Write-Host "Looking for manually installed build tools..." -ForegroundColor Yellow
    $ninjaFound = $false
    $compilerFound = $false

    # Check for manually installed compilers (GCC, Clang, MSVC)
    $compilerPaths = @(
        # MSVC
        "$env:ProgramFiles\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "$env:ProgramFiles\Microsoft Visual Studio\2022\Professional\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "$env:ProgramFiles\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "$env:ProgramFiles\Microsoft Visual Studio\2019\Community\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "$env:ProgramFiles\Microsoft Visual Studio\2019\Professional\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "$env:ProgramFiles\Microsoft Visual Studio\2019\Enterprise\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "$env:ProgramFiles (x86)\Microsoft Visual Studio\2019\Community\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "$env:ProgramFiles (x86)\Microsoft Visual Studio\2019\Professional\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",
        "$env:ProgramFiles (x86)\Microsoft Visual Studio\2019\Enterprise\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe",

        # GCC (MinGW)
        "$env:ProgramFiles\mingw-w64\*\mingw64\bin\gcc.exe",
        "$env:ProgramFiles (x86)\mingw-w64\*\mingw64\bin\gcc.exe",
        "$env:LOCALAPPDATA\Programs\mingw-w64\*\mingw64\bin\gcc.exe",
        "$env:USERPROFILE\scoop\apps\mingw\current\bin\gcc.exe",
        "$env:USERPROFILE\scoop\shims\gcc.exe",
        # MinGW in standard locations
        "C:\MinGW\bin\gcc.exe",
        "C:\msys64\mingw64\bin\gcc.exe",
        "C:\msys64\mingw32\bin\gcc.exe",
        # MinGW bundled with CLion
        "$env:LOCALAPPDATA\Programs\CLion\bin\mingw\bin\gcc.exe",
        "$env:LOCALAPPDATA\JetBrains\CLion*\bin\mingw\bin\gcc.exe",
        "$env:PROGRAMFILES\JetBrains\CLion*\bin\mingw\bin\gcc.exe",
        "$env:LOCALAPPDATA\JetBrains\Toolbox\apps\CLion\ch-0\*\bin\mingw\bin\gcc.exe",

        # Clang
        "$env:ProgramFiles\LLVM\bin\clang.exe",
        "$env:ProgramFiles (x86)\LLVM\bin\clang.exe",
        "$env:LOCALAPPDATA\Programs\LLVM\bin\clang.exe",
        "$env:USERPROFILE\scoop\apps\llvm\current\bin\clang.exe",
        "$env:USERPROFILE\scoop\shims\clang.exe",
        # Clang bundled with CLion
        "$env:LOCALAPPDATA\Programs\CLion\bin\clang\bin\clang.exe",
        "$env:LOCALAPPDATA\JetBrains\CLion*\bin\clang\bin\clang.exe",
        "$env:PROGRAMFILES\JetBrains\CLion*\bin\clang\bin\clang.exe",
        "$env:LOCALAPPDATA\JetBrains\Toolbox\apps\CLion\ch-0\*\bin\clang\bin\clang.exe"
    )

    foreach ($compilerPath in $compilerPaths) {
        $resolvedPaths = Resolve-Path $compilerPath -ErrorAction SilentlyContinue
        if ($resolvedPaths) {
            foreach ($path in $resolvedPaths) {
                if (Test-Path $path) {
                    $compilerDir = Split-Path -Parent $path
                    $compilerName = Split-Path -Leaf $path
                    Write-Host "Found manually installed compiler: $compilerName at $path" -ForegroundColor Green

                    # Add compiler directory to the PATH
                    $env:PATH = "$compilerDir;$env:PATH"
                    $compilerFound = $true
                    break
                }
            }
        }
        if ($compilerFound) { break }
    }

    if ($compilerFound) {
        Write-Host "Manually installed compiler found and added to PATH" -ForegroundColor Green

        # Set environment variables for CMake to find the compiler
        if ($compilerPath -match "cl\.exe$") {
            # MSVC compiler
            $env:CC = "cl"
            $env:CXX = "cl"
            Write-Host "Set environment variables for MSVC compiler: CC=cl, CXX=cl" -ForegroundColor Green
        } elseif ($compilerPath -match "gcc\.exe$") {
            # GCC compiler
            $gccPath = $compilerPath
            $gxxPath = $gccPath -replace "gcc\.exe$", "g++.exe"
            if (Test-Path $gxxPath) {
                $env:CC = $gccPath
                $env:CXX = $gxxPath
                Write-Host "Set environment variables for GCC compiler: CC=$gccPath, CXX=$gxxPath" -ForegroundColor Green
            } else {
                $env:CC = "gcc"
                $env:CXX = "g++"
                Write-Host "Set environment variables for GCC compiler: CC=gcc, CXX=g++" -ForegroundColor Green
            }
        } elseif ($compilerPath -match "clang\.exe$") {
            # Clang compiler
            $clangPath = $compilerPath
            $clangppPath = $clangPath -replace "clang\.exe$", "clang++.exe"
            if (Test-Path $clangppPath) {
                $env:CC = $clangPath
                $env:CXX = $clangppPath
                Write-Host "Set environment variables for Clang compiler: CC=$clangPath, CXX=$clangppPath" -ForegroundColor Green
            } else {
                $env:CC = "clang"
                $env:CXX = "clang++"
                Write-Host "Set environment variables for Clang compiler: CC=clang, CXX=clang++" -ForegroundColor Green
            }
        }
    } else {
        Write-Host "No manually installed compiler found. Will continue with other build tools." -ForegroundColor Yellow
    }

    # Check for manually installed Ninja
    $manualNinjaPaths = @(
        "$env:ProgramFiles\ninja-build\ninja.exe",
        "$env:ProgramFiles(x86)\ninja-build\ninja.exe",
        "$env:LOCALAPPDATA\Programs\ninja-build\ninja.exe",
        "$env:USERPROFILE\ninja-build\ninja.exe",
        "$env:USERPROFILE\scoop\apps\ninja\current\ninja.exe",
        "$env:USERPROFILE\scoop\shims\ninja.exe",
        "$env:ChocolateyInstall\bin\ninja.exe"
    )

    foreach ($manualNinjaPath in $manualNinjaPaths) {
        Write-Host "Checking manual Ninja installation: $manualNinjaPath" -ForegroundColor Yellow
        if (Test-Path $manualNinjaPath) {
            Write-Host "Found manually installed Ninja at: $manualNinjaPath" -ForegroundColor Green
            $ninjaDir = Split-Path -Parent $manualNinjaPath
            Write-Host "Using Ninja from: $ninjaDir" -ForegroundColor Green

            # Add Ninja directory to the PATH
            $env:PATH = "$ninjaDir;$env:PATH"

            # Look for manually installed CMake
            $manualCMakePaths = @(
                "$env:ProgramFiles\CMake\bin\cmake.exe",
                "$env:ProgramFiles(x86)\CMake\bin\cmake.exe",
                "$env:LOCALAPPDATA\Programs\CMake\bin\cmake.exe",
                "$env:USERPROFILE\CMake\bin\cmake.exe",
                "$env:USERPROFILE\scoop\apps\cmake\current\bin\cmake.exe",
                "$env:USERPROFILE\scoop\shims\cmake.exe",
                "$env:ChocolateyInstall\bin\cmake.exe"
            )

            Write-Host "Looking for manually installed CMake..." -ForegroundColor Yellow

            $cmakeFound = $false
            foreach ($cmakePath in $manualCMakePaths) {
                Write-Host "  Checking: $cmakePath" -ForegroundColor Gray
                if (Test-Path $cmakePath) {
                    $cmakeDir = Split-Path -Parent $cmakePath
                    Write-Host "  Found manually installed CMake at $cmakePath." -ForegroundColor Green
                    # Add CMake directory to the beginning of the PATH
                    $env:PATH = "$cmakeDir;$env:PATH"
                    $cmakeFound = $true
                    break
                }
            }

            if (-not $cmakeFound) {
                Write-Host "  No manually installed CMake found. Will use system CMake if available." -ForegroundColor Yellow
            }

            # Verify that Ninja is actually in the PATH
            try {
                $ninjaVersion = & ninja --version 2>&1
                Write-Host "Ninja version: $ninjaVersion" -ForegroundColor Green
                Write-Host "Ninja is properly configured and in the PATH" -ForegroundColor Green
            } catch {
                Write-Host "Warning: Ninja was found but could not be executed. It may not be properly in the PATH." -ForegroundColor Yellow
                Write-Host "Error details: $_" -ForegroundColor Yellow
                Write-Host "Current PATH: $env:PATH" -ForegroundColor Yellow
            }

            # Verify that CMake is also properly configured
            try {
                $cmakeVersion = & cmake --version 2>&1
                if ($cmakeVersion -match "version (\d+\.\d+\.\d+)") {
                    Write-Host "CMake version: $($matches[1])" -ForegroundColor Green
                    Write-Host "CMake is properly configured and in the PATH" -ForegroundColor Green
                } else {
                    Write-Host "CMake version could not be determined, but CMake is in the PATH" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "Warning: CMake could not be executed. It may not be properly in the PATH." -ForegroundColor Yellow
                Write-Host "Error details: $_" -ForegroundColor Yellow
            }

            $ninjaFound = $true
            $vsGenerator = "Ninja"
            break
        }
    }

    if (-not $ninjaFound) {
        Write-Host "No manually installed Ninja found. Checking CLion installation..." -ForegroundColor Yellow
    }

    # If we haven't found Ninja yet, check other possible locations
    if (-not $ninjaFound) {
        $clionPaths = @(
        # Common CLion Ninja paths
        "$env:LOCALAPPDATA\Programs\CLion\bin\ninja\win\x64\ninja.exe",

        # Standard installation paths
        "$env:LOCALAPPDATA\Programs\CLion\bin\cmake\win\x64\bin\ninja.exe",
        "$env:LOCALAPPDATA\JetBrains\CLion*\bin\cmake\win\x64\bin\ninja.exe",
        "$env:PROGRAMFILES\JetBrains\CLion*\bin\cmake\win\x64\bin\ninja.exe",

        # Additional paths for different CLion versions and architectures
        "$env:LOCALAPPDATA\JetBrains\CLion*\bin\cmake\win\bin\ninja.exe",
        "$env:PROGRAMFILES\JetBrains\CLion*\bin\cmake\win\bin\ninja.exe",
        "$env:LOCALAPPDATA\Programs\CLion*\bin\cmake\win\bin\ninja.exe",

        # Check for Ninja directly in CLion's bin directory
        "$env:LOCALAPPDATA\Programs\CLion\bin\ninja\win\x64\ninja.exe",
        "$env:LOCALAPPDATA\JetBrains\CLion*\bin\ninja\win\x64\ninja.exe",
        "$env:PROGRAMFILES\JetBrains\CLion*\bin\ninja\win\x64\ninja.exe",

        # Check for Ninja in CLion's bundled tools directory
        "$env:LOCALAPPDATA\JetBrains\Toolbox\apps\CLion\ch-0\*\bin\cmake\win\bin\ninja.exe",
        "$env:LOCALAPPDATA\JetBrains\Toolbox\apps\CLion\ch-0\*\bin\cmake\win\x64\bin\ninja.exe",
        "$env:LOCALAPPDATA\JetBrains\Toolbox\apps\CLion\ch-0\*\bin\ninja\win\x64\ninja.exe"
    )

    Write-Host "Checking the following paths for Ninja:" -ForegroundColor Yellow
    foreach ($clionNinjaPath in $clionPaths) {
        Write-Host "  Checking pattern: $clionNinjaPath" -ForegroundColor Gray
        $resolvedPaths = Resolve-Path $clionNinjaPath -ErrorAction SilentlyContinue
        if ($resolvedPaths) {
            foreach ($path in $resolvedPaths) {
                Write-Host "    Resolved to: $path" -ForegroundColor Gray
                if (Test-Path $path) {
                    Write-Host "    Found Ninja at: $path" -ForegroundColor Green
                    $ninjaDir = Split-Path -Parent $path
                    Write-Host "CLion's Ninja found at $path. Using Ninja generator." -ForegroundColor Green

                    # Add Ninja directory to the PATH
                    $env:PATH = "$ninjaDir;$env:PATH"

                    # Check if we need to look for CMake in a parent directory (for non-standard Ninja locations)
                    # For paths like %LOCALAPPDATA%\Programs\CLion\bin\ninja\win\x64\ninja.exe
                    # we need to look for CMake in %LOCALAPPDATA%\Programs\CLion\bin\cmake\win\bin
                    $cmakeInNinjaDir = Join-Path $ninjaDir "cmake.exe"
                    Write-Host "Checking for CMake in Ninja directory: $cmakeInNinjaDir" -ForegroundColor Yellow

                    if (-not (Test-Path $cmakeInNinjaDir)) {
                        Write-Host "CMake not found in Ninja directory. Looking in sibling directories..." -ForegroundColor Yellow
                        # Try to find CMake in a sibling directory
                        # For the path %LOCALAPPDATA%\Programs\CLion\bin\ninja\win\x64\ninja.exe
                        # we need to try different approaches to find CMake

                        # First, try to get the CLion base directory by going up 3 levels (bin/ninja/win/x64 -> bin)
                        try {
                            $clionDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $ninjaDir))
                            Write-Host "CLion base directory (method 1): $clionDir" -ForegroundColor Yellow
                        } catch {
                            # If that fails, try a different approach
                            $clionDir = $ninjaDir
                            Write-Host "Failed to determine CLion base directory using method 1. Using Ninja directory as base." -ForegroundColor Yellow
                        }

                        # For paths in CLion's bin/ninja directory
                        if ($path -like "*\CLion\bin\ninja\win\x64\ninja.exe" -or $path -like "*\Programs\CLion\bin\ninja\win\x64\ninja.exe") {
                            Write-Host "Detected CLion's Ninja in standard location" -ForegroundColor Green
                            $clionBinDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $ninjaDir))
                            Write-Host "Detected CLion bin directory: $clionBinDir" -ForegroundColor Yellow

                            $possibleCMakePaths = @(
                                # Try to find CMake in the cmake directory at the same level as ninja
                                (Join-Path $clionBinDir "cmake\win\bin\cmake.exe"),
                                (Join-Path $clionBinDir "cmake\win\x64\bin\cmake.exe"),
                                # Also try one level up
                                (Join-Path (Split-Path -Parent $clionBinDir) "bin\cmake\win\bin\cmake.exe"),
                                (Join-Path (Split-Path -Parent $clionBinDir) "bin\cmake\win\x64\bin\cmake.exe")
                            )
                        } else {
                            # For other paths, use the standard approach
                            $possibleCMakePaths = @(
                                (Join-Path $clionDir "cmake\win\bin\cmake.exe"),
                                (Join-Path $clionDir "cmake\win\x64\bin\cmake.exe")
                            )
                        }

                        Write-Host "Checking the following paths for CMake:" -ForegroundColor Yellow
                        foreach ($cmakePath in $possibleCMakePaths) {
                            Write-Host "  Checking: $cmakePath" -ForegroundColor Gray
                            if (Test-Path $cmakePath) {
                                $cmakeDir = Split-Path -Parent $cmakePath
                                Write-Host "  Found CLion's CMake at $cmakePath. Using it for better compatibility." -ForegroundColor Green
                                # Add CLion's CMake directory to the beginning of the PATH
                                $env:PATH = "$cmakeDir;$env:PATH"
                                Write-Host "  Added $cmakeDir to PATH" -ForegroundColor Green
                                break
                            } else {
                                Write-Host "  Not found at: $cmakePath" -ForegroundColor Gray
                            }
                        }
                    } else {
                        # CMake is in the same directory as Ninja
                        Write-Host "CMake found in Ninja directory at $cmakeInNinjaDir" -ForegroundColor Green
                        # We already added this directory to PATH above
                        Write-Host "Using CMake from Ninja directory" -ForegroundColor Green
                    }

                    $ninjaFound = $true
                    $vsGenerator = "Ninja"

                    # If no compiler was found earlier, check for compilers in CLion's installation
                    if (-not $compilerFound) {
                        Write-Host "No compiler found earlier. Checking for compilers in CLion's installation..." -ForegroundColor Yellow

                        # Try to find the CLion installation directory
                        $clionDir = $null
                        if ($path -like "*\CLion\bin\ninja\win\x64\ninja.exe" -or $path -like "*\Programs\CLion\bin\ninja\win\x64\ninja.exe") {
                            # For paths like %LOCALAPPDATA%\Programs\CLion\bin\ninja\win\x64\ninja.exe
                            $clionDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $ninjaDir)))
                            Write-Host "Detected CLion installation directory: $clionDir" -ForegroundColor Yellow
                        } elseif ($path -like "*\JetBrains\CLion*\bin\ninja\win\x64\ninja.exe") {
                            # For paths like %LOCALAPPDATA%\JetBrains\CLion2023.1\bin\ninja\win\x64\ninja.exe
                            $clionDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $ninjaDir)))
                            Write-Host "Detected CLion installation directory: $clionDir" -ForegroundColor Yellow
                        } elseif ($path -like "*\JetBrains\Toolbox\apps\CLion\ch-0\*\bin\ninja\win\x64\ninja.exe") {
                            # For Toolbox installations
                            $clionDir = Split-Path -Parent (Split-Path -Parent $ninjaDir)
                            Write-Host "Detected CLion installation directory (Toolbox): $clionDir" -ForegroundColor Yellow
                        }

                        if ($clionDir) {
                            # Check for bundled compilers in CLion's installation
                            $clionCompilerPaths = @(
                                # MinGW
                                (Join-Path $clionDir "bin\mingw\bin\gcc.exe"),
                                (Join-Path $clionDir "bin\mingw64\bin\gcc.exe"),
                                # Clang
                                (Join-Path $clionDir "bin\clang\bin\clang.exe"),
                                # MSVC - unlikely but check anyway
                                (Join-Path $clionDir "bin\msvc\bin\cl.exe")
                            )

                            foreach ($compPath in $clionCompilerPaths) {
                                if (Test-Path $compPath) {
                                    $compilerDir = Split-Path -Parent $compPath
                                    $compilerName = Split-Path -Leaf $compPath
                                    Write-Host "Found compiler bundled with CLion: $compilerName at $compPath" -ForegroundColor Green

                                    # Add compiler directory to the PATH
                                    $env:PATH = "$compilerDir;$env:PATH"

                                    # Set environment variables for CMake to find the compiler
                                    if ($compPath -match "cl\.exe$") {
                                        # MSVC compiler
                                        $env:CC = "cl"
                                        $env:CXX = "cl"
                                        Write-Host "Set environment variables for MSVC compiler: CC=cl, CXX=cl" -ForegroundColor Green
                                    } elseif ($compPath -match "gcc\.exe$") {
                                        # GCC compiler
                                        $gccPath = $compPath
                                        $gxxPath = $gccPath -replace "gcc\.exe$", "g++.exe"
                                        if (Test-Path $gxxPath) {
                                            $env:CC = $gccPath
                                            $env:CXX = $gxxPath
                                            Write-Host "Set environment variables for GCC compiler: CC=$gccPath, CXX=$gxxPath" -ForegroundColor Green
                                        } else {
                                            $env:CC = "gcc"
                                            $env:CXX = "g++"
                                            Write-Host "Set environment variables for GCC compiler: CC=gcc, CXX=g++" -ForegroundColor Green
                                        }
                                    } elseif ($compPath -match "clang\.exe$") {
                                        # Clang compiler
                                        $clangPath = $compPath
                                        $clangppPath = $clangPath -replace "clang\.exe$", "clang++.exe"
                                        if (Test-Path $clangppPath) {
                                            $env:CC = $clangPath
                                            $env:CXX = $clangppPath
                                            Write-Host "Set environment variables for Clang compiler: CC=$clangPath, CXX=$clangppPath" -ForegroundColor Green
                                        } else {
                                            $env:CC = "clang"
                                            $env:CXX = "clang++"
                                            Write-Host "Set environment variables for Clang compiler: CC=clang, CXX=clang++" -ForegroundColor Green
                                        }
                                    }

                                    $compilerFound = $true
                                    break
                                }
                            }

                            if (-not $compilerFound) {
                                Write-Host "No compiler found in CLion's installation directory. Will try to use system compiler." -ForegroundColor Yellow
                                Write-Host "If you're using CLion, you might need to configure a toolchain in CLion's settings:" -ForegroundColor Yellow
                                Write-Host "  1. Open CLion" -ForegroundColor Yellow
                                Write-Host "  2. Go to File > Settings > Build, Execution, Deployment > Toolchains" -ForegroundColor Yellow
                                Write-Host "  3. Add a toolchain (Visual Studio, MinGW, WSL, etc.)" -ForegroundColor Yellow
                                Write-Host "  4. Make sure the toolchain has a valid C/C++ compiler" -ForegroundColor Yellow
                                Write-Host "  5. Close CLion and try running this script again" -ForegroundColor Yellow
                            }
                        }
                    }

                    # Verify that Ninja is actually in the PATH
                    try {
                        $ninjaVersion = & ninja --version 2>&1
                        Write-Host "Ninja version: $ninjaVersion" -ForegroundColor Green
                        Write-Host "Ninja is properly configured and in the PATH" -ForegroundColor Green
                    } catch {
                        Write-Host "Warning: Ninja was found but could not be executed. It may not be properly in the PATH." -ForegroundColor Yellow
                        Write-Host "Error details: $_" -ForegroundColor Yellow
                        Write-Host "Current PATH: $env:PATH" -ForegroundColor Yellow

                        # Check if this might be due to missing Visual C++ Redistributable
                        if ($_ -match "VCRUNTIME140" -or $_ -match "MSVCP140") {
                            Write-Host "The error suggests that the Visual C++ Redistributable might be missing." -ForegroundColor Yellow
                            Write-Host "Please install the Visual C++ Redistributable from:" -ForegroundColor Yellow
                            Write-Host "https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor Yellow
                        }
                    }

                    # Verify that CMake is also properly configured
                    try {
                        $cmakeVersion = & cmake --version 2>&1
                        if ($cmakeVersion -match "version (\d+\.\d+\.\d+)") {
                            Write-Host "CMake version: $($matches[1])" -ForegroundColor Green
                            Write-Host "CMake is properly configured and in the PATH" -ForegroundColor Green
                        } else {
                            Write-Host "CMake version could not be determined, but CMake is in the PATH" -ForegroundColor Yellow
                        }
                    } catch {
                        Write-Host "Warning: CMake could not be executed. It may not be properly in the PATH." -ForegroundColor Yellow
                        Write-Host "Error details: $_" -ForegroundColor Yellow
                    }

                    break
                }
            }
        }
        if ($ninjaFound) { break }
    }

    # If CLion's Ninja not found, try system PATH
    if (-not $ninjaFound -and (Get-Command "ninja" -ErrorAction SilentlyContinue)) {
        Write-Host "Ninja found in PATH. Using Ninja generator." -ForegroundColor Green
        $vsGenerator = "Ninja"
        $ninjaFound = $true
    }

    # If Ninja is found, verify it works with a test project
    if ($ninjaFound) {
        try {
            # Create a temporary directory for testing Ninja
            $testDir = Join-Path $env:TEMP "cmake_ninja_test_$([Guid]::NewGuid().ToString())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            # Create a minimal CMakeLists.txt file
            Set-Content -Path (Join-Path $testDir "CMakeLists.txt") -Value "cmake_minimum_required(VERSION 3.10)`nproject(test)"

            # Test if Ninja generator works
            Write-Host "Verifying Ninja generator..." -ForegroundColor Yellow
            $testProcess = Start-Process -FilePath "cmake" -ArgumentList "-G", "Ninja", "." -WorkingDirectory $testDir -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$testDir\out.txt" -RedirectStandardError "$testDir\err.txt"

            if ($testProcess.ExitCode -ne 0) {
                $errorContent = Get-Content -Path "$testDir\err.txt" -Raw -ErrorAction SilentlyContinue
                Write-Host "Ninja generator test failed: $errorContent" -ForegroundColor Yellow
                $ninjaFound = $false
                $vsGenerator = ""
            } else {
                Write-Host "Ninja generator verified successfully." -ForegroundColor Green
            }

            # Clean up the test directory
            Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Host "Error verifying Ninja generator: $_" -ForegroundColor Yellow
            $ninjaFound = $false
            $vsGenerator = ""
        }
    }

    # If Ninja not found, try other generators
    if (-not $ninjaFound) {
        # Check if Visual Studio is installed even if vswhere isn't available
        $vsVersions = @(
            "Visual Studio 17 2022",
            "Visual Studio 16 2019",
            "Visual Studio 15 2017"
        )

        $vsFound = $false
        foreach ($version in $vsVersions) {
            try {
                # Create a temporary directory for testing the generator
                $testDir = Join-Path $env:TEMP "cmake_test_$([Guid]::NewGuid().ToString())"
                New-Item -ItemType Directory -Path $testDir -Force | Out-Null

                # Create a minimal CMakeLists.txt file
                Set-Content -Path (Join-Path $testDir "CMakeLists.txt") -Value "cmake_minimum_required(VERSION 3.10)`nproject(test)"

                # Test if this generator works by trying to configure a simple project
                Write-Host "Testing $version generator..." -ForegroundColor Yellow
                $testProcess = Start-Process -FilePath "cmake" -ArgumentList "-G", "`"$version`"", "." -WorkingDirectory $testDir -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$testDir\out.txt" -RedirectStandardError "$testDir\err.txt"

                # Check if the process succeeded and if the error output contains "could not find any instance of Visual Studio"
                $errorContent = Get-Content -Path "$testDir\err.txt" -Raw -ErrorAction SilentlyContinue
                if ($testProcess.ExitCode -eq 0 -and -not ($errorContent -match "could not find any instance of Visual Studio")) {
                    Write-Host "$version found and verified. Using this generator." -ForegroundColor Green
                    $vsGenerator = $version
                    $vsFound = $true
                } else {
                    Write-Host "$version not available or not properly installed." -ForegroundColor Yellow
                }

                # Clean up the test directory
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue

                if ($vsFound) {
                    break
                }
            } catch {
                # Continue to next version
                Write-Host "$version not available: $_" -ForegroundColor Yellow
            }
        }

        # If no Visual Studio found, try MinGW, MSYS2, or NMake
        if (-not $vsFound) {
            Write-Host "No Visual Studio installation detected." -ForegroundColor Yellow
            Write-Host "Trying alternative generators that don't require Visual Studio..." -ForegroundColor Yellow

            # Try MinGW Makefiles
            try {
                if (Get-Command "mingw32-make" -ErrorAction SilentlyContinue) {
                    Write-Host "MinGW detected. Trying MinGW Makefiles generator..." -ForegroundColor Yellow
                    $testResult = Invoke-Expression "cmake -G `"MinGW Makefiles`" --version 2>&1"
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "Using MinGW Makefiles generator." -ForegroundColor Green
                        $vsGenerator = "MinGW Makefiles"
                    }
                }
            } catch {
                Write-Host "MinGW Makefiles generator not available." -ForegroundColor Yellow
            }

            # Try MSYS Makefiles
            if (-not $vsGenerator) {
                try {
                    if (Get-Command "make" -ErrorAction SilentlyContinue) {
                        Write-Host "MSYS detected. Trying MSYS Makefiles generator..." -ForegroundColor Yellow
                        $testResult = Invoke-Expression "cmake -G `"MSYS Makefiles`" --version 2>&1"
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "Using MSYS Makefiles generator." -ForegroundColor Green
                            $vsGenerator = "MSYS Makefiles"
                        }
                    }
                } catch {
                    Write-Host "MSYS Makefiles generator not available." -ForegroundColor Yellow
                }
            }

            # Try NMake Makefiles
            if (-not $vsGenerator) {
                try {
                    if (Get-Command "nmake" -ErrorAction SilentlyContinue) {
                        Write-Host "NMake detected. Trying NMake Makefiles generator..." -ForegroundColor Yellow
                        $testResult = Invoke-Expression "cmake -G `"NMake Makefiles`" --version 2>&1"
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "Using NMake Makefiles generator." -ForegroundColor Green
                            $vsGenerator = "NMake Makefiles"
                        }
                    }
                } catch {
                    Write-Host "NMake Makefiles generator not available." -ForegroundColor Yellow
                }
            }

            # If still no generator found, let CMake choose a default
            if (-not $vsGenerator) {
                Write-Host "No specific generator could be detected. CMake will use its default generator." -ForegroundColor Yellow
                Write-Host "Note: To build with a specific generator, please install Visual Studio, MinGW, MSYS2, or Ninja." -ForegroundColor Yellow
            }
        }
    }
}
}

# Check if we need to clean the build directory due to generator change
$cmakeCachePath = "build\CMakeCache.txt"
$needsCleanBuild = $false

if (Test-Path $cmakeCachePath) {
    $cacheContent = Get-Content $cmakeCachePath -Raw

    # Check if the cache contains a different generator
    if ($vsGenerator -and $cacheContent -match "CMAKE_GENERATOR:INTERNAL=([^\r\n]+)") {
        $cachedGenerator = $matches[1]
        if ($cachedGenerator -ne $vsGenerator) {
            Write-Host "Detected generator change from '$cachedGenerator' to '$vsGenerator'" -ForegroundColor Yellow
            Write-Host "Cleaning build directory to avoid generator conflicts..." -ForegroundColor Yellow
            $needsCleanBuild = $true
        }
    }
}

if ($needsCleanBuild) {
    # Remove CMakeCache.txt and CMakeFiles directory
    Remove-Item $cmakeCachePath -Force -ErrorAction SilentlyContinue
    Remove-Item "build\CMakeFiles" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Build directory cleaned." -ForegroundColor Green
}

# Use the detected generator or let CMake choose a default
if ($vsGenerator) {
    Write-Host "Using generator: $vsGenerator" -ForegroundColor Green
    # Use quoted variables to avoid issues with Ninja generator
    cmake -G $vsGenerator -S . -B build -DCMAKE_BUILD_TYPE="$BuildType" -DDEFAULT_API_URL="$ApiUrl" -DDEFAULT_TIMEOUT="$Timeout" -DDEFAULT_CONNECT_TIMEOUT="$ConnectTimeout" -DDEFAULT_SERVER_PORT="$ServerPort"
} else {
    Write-Host "No specific generator detected. Using CMake default." -ForegroundColor Yellow
    Write-Host "Note: Visual Studio is NOT required to run the DLL, only for building it." -ForegroundColor Cyan
    Write-Host "If the build fails, consider installing one of these build tools:" -ForegroundColor Cyan
    Write-Host "  - Visual Studio Build Tools (https://visualstudio.microsoft.com/downloads/)" -ForegroundColor Cyan
    Write-Host "  - MinGW (https://www.mingw-w64.org/)" -ForegroundColor Cyan
    Write-Host "  - MSYS2 (https://www.msys2.org/)" -ForegroundColor Cyan
    Write-Host "  - Ninja (https://ninja-build.org/)" -ForegroundColor Cyan

    # Try multiple fallback generators in order of preference
    $fallbackGenerators = @(
        "Ninja",                # Try Ninja again with default settings
        "NMake Makefiles JOM",  # JOM is a drop-in replacement for NMake that supports parallel builds
        "NMake Makefiles",      # Standard NMake
        "MinGW Makefiles",      # MinGW
        "MSYS Makefiles",       # MSYS2
        "Unix Makefiles"        # Might work with Git Bash or similar
    )

    $fallbackSuccess = $false
    foreach ($generator in $fallbackGenerators) {
        Write-Host "Attempting to use '$generator' generator as a fallback..." -ForegroundColor Yellow
        try {
            # Create a temporary directory for testing the generator
            $testDir = Join-Path $env:TEMP "cmake_fallback_test_$([Guid]::NewGuid().ToString())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            # Create a minimal CMakeLists.txt file
            Set-Content -Path (Join-Path $testDir "CMakeLists.txt") -Value "cmake_minimum_required(VERSION 3.10)`nproject(test)"

            # Test if this generator works
            $testProcess = Start-Process -FilePath "cmake" -ArgumentList "-G", "`"$generator`"", "." -WorkingDirectory $testDir -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$testDir\out.txt" -RedirectStandardError "$testDir\err.txt"

            # Clean up the test directory
            Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue

            if ($testProcess.ExitCode -eq 0) {
                Write-Host "Using '$generator' generator for the build." -ForegroundColor Green
                # Use quoted variables to avoid issues with Ninja generator
                cmake -G $generator -S . -B build -DCMAKE_BUILD_TYPE="$BuildType" -DDEFAULT_API_URL="$ApiUrl" -DDEFAULT_TIMEOUT="$Timeout" -DDEFAULT_CONNECT_TIMEOUT="$ConnectTimeout" -DDEFAULT_SERVER_PORT="$ServerPort"
                $fallbackSuccess = $true
                break
            }
        } catch {
            Write-Host "'$generator' generator failed: $_" -ForegroundColor Yellow
        }
    }

    # If all fallback generators fail, use CMake default
    if (-not $fallbackSuccess) {
        Write-Host "All fallback generators failed. Using CMake default generator." -ForegroundColor Yellow
        Write-Host "This may not work if you don't have any compatible build tools installed." -ForegroundColor Yellow
        Write-Host "Consider installing one of the recommended build tools mentioned above." -ForegroundColor Yellow

        # Check if a compiler was found
        if (-not $compilerFound) {
            Write-Host "WARNING: No C/C++ compiler was found on your system!" -ForegroundColor Red
            Write-Host "CMake will likely fail with an error about not finding a compiler." -ForegroundColor Red

            # Check if CLion is installed
            $clionInstalled = $false
            $clionPaths = @(
                "$env:LOCALAPPDATA\Programs\CLion\bin\clion64.exe",
                "$env:LOCALAPPDATA\JetBrains\CLion*\bin\clion64.exe",
                "$env:PROGRAMFILES\JetBrains\CLion*\bin\clion64.exe"
            )

            foreach ($clionPath in $clionPaths) {
                $resolvedPaths = Resolve-Path $clionPath -ErrorAction SilentlyContinue
                if ($resolvedPaths) {
                    foreach ($path in $resolvedPaths) {
                        if (Test-Path $path) {
                            $clionInstalled = $true
                            break
                        }
                    }
                }
                if ($clionInstalled) { break }
            }

            if ($clionInstalled) {
                Write-Host "CLion is installed on your system, but no C/C++ compiler was found." -ForegroundColor Yellow
                Write-Host "You can configure a toolchain in CLion's settings:" -ForegroundColor Yellow
                Write-Host "  1. Open CLion" -ForegroundColor Yellow
                Write-Host "  2. Go to File > Settings > Build, Execution, Deployment > Toolchains" -ForegroundColor Yellow
                Write-Host "  3. Add a toolchain (Visual Studio, MinGW, WSL, etc.)" -ForegroundColor Yellow
                Write-Host "  4. Make sure the toolchain has a valid C/C++ compiler" -ForegroundColor Yellow
                Write-Host "  5. Close CLion and try running this script again" -ForegroundColor Yellow
                Write-Host "" -ForegroundColor Yellow
            }

            # Check if Visual Studio is installed but not detected
            $vsInstalled = $false
            $vsPaths = @(
                "$env:ProgramFiles\Microsoft Visual Studio\2022",
                "$env:ProgramFiles\Microsoft Visual Studio\2019",
                "$env:ProgramFiles (x86)\Microsoft Visual Studio\2022",
                "$env:ProgramFiles (x86)\Microsoft Visual Studio\2019"
            )

            foreach ($vsPath in $vsPaths) {
                if (Test-Path $vsPath) {
                    $vsInstalled = $true
                    break
                }
            }

            if ($vsInstalled) {
                Write-Host "Visual Studio appears to be installed on your system, but the C++ compiler was not detected." -ForegroundColor Yellow
                Write-Host "This might be because:" -ForegroundColor Yellow
                Write-Host "  1. The 'Desktop development with C++' workload is not installed" -ForegroundColor Yellow
                Write-Host "  2. Visual Studio installation is incomplete or corrupted" -ForegroundColor Yellow
                Write-Host "" -ForegroundColor Yellow
                Write-Host "To fix this:" -ForegroundColor Yellow
                Write-Host "  1. Open Visual Studio Installer" -ForegroundColor Yellow
                Write-Host "  2. Select 'Modify' on your Visual Studio installation" -ForegroundColor Yellow
                Write-Host "  3. Check 'Desktop development with C++' workload" -ForegroundColor Yellow
                Write-Host "  4. Click 'Modify' to install the C++ components" -ForegroundColor Yellow
                Write-Host "  5. After installation completes, try running this script again" -ForegroundColor Yellow
                Write-Host "" -ForegroundColor Yellow
            }

            # Check if MinGW or MSYS2 is installed but not detected
            $mingwInstalled = $false
            $msys2Installed = $false
            $mingwPaths = @(
                "C:\MinGW",
                "C:\mingw-w64",
                "$env:ProgramFiles\mingw-w64",
                "$env:ProgramFiles (x86)\mingw-w64",
                "$env:LOCALAPPDATA\Programs\mingw-w64"
            )

            $msys2Paths = @(
                "C:\msys64",
                "C:\msys32",
                "$env:ProgramFiles\msys64",
                "$env:ProgramFiles (x86)\msys64"
            )

            foreach ($mingwPath in $mingwPaths) {
                if (Test-Path $mingwPath) {
                    $mingwInstalled = $true
                    break
                }
            }

            foreach ($msys2Path in $msys2Paths) {
                if (Test-Path $msys2Path) {
                    $msys2Installed = $true
                    break
                }
            }

            if ($mingwInstalled) {
                Write-Host "MinGW appears to be installed on your system, but the GCC compiler was not detected." -ForegroundColor Yellow
                Write-Host "This might be because:" -ForegroundColor Yellow
                Write-Host "  1. MinGW's bin directory is not in your PATH" -ForegroundColor Yellow
                Write-Host "  2. The GCC compiler is not installed in your MinGW installation" -ForegroundColor Yellow
                Write-Host "" -ForegroundColor Yellow
                Write-Host "To fix this:" -ForegroundColor Yellow
                Write-Host "  1. Make sure MinGW's bin directory is in your PATH environment variable" -ForegroundColor Yellow
                Write-Host "     - Right-click on 'This PC' or 'My Computer' and select 'Properties'" -ForegroundColor Yellow
                Write-Host "     - Click on 'Advanced system settings'" -ForegroundColor Yellow
                Write-Host "     - Click on 'Environment Variables'" -ForegroundColor Yellow
                Write-Host "     - Under 'System variables', find and edit 'Path'" -ForegroundColor Yellow
                Write-Host "     - Add the path to MinGW's bin directory (e.g., C:\MinGW\bin)" -ForegroundColor Yellow
                Write-Host "  2. If GCC is not installed, run MinGW's package manager to install it" -ForegroundColor Yellow
                Write-Host "  3. After making changes, open a new PowerShell window and try running this script again" -ForegroundColor Yellow
                Write-Host "" -ForegroundColor Yellow
            }

            if ($msys2Installed) {
                Write-Host "MSYS2 appears to be installed on your system, but the GCC compiler was not detected." -ForegroundColor Yellow
                Write-Host "This might be because:" -ForegroundColor Yellow
                Write-Host "  1. You haven't installed the GCC compiler in MSYS2" -ForegroundColor Yellow
                Write-Host "  2. MSYS2's bin directory is not in your PATH" -ForegroundColor Yellow
                Write-Host "" -ForegroundColor Yellow
                Write-Host "To fix this:" -ForegroundColor Yellow
                Write-Host "  1. Open MSYS2 terminal" -ForegroundColor Yellow
                Write-Host "  2. Run the following command to install GCC:" -ForegroundColor Yellow
                Write-Host "     pacman -S mingw-w64-x86_64-gcc" -ForegroundColor Yellow
                Write-Host "  3. Add MSYS2's bin directory to your PATH environment variable:" -ForegroundColor Yellow
                Write-Host "     - Right-click on 'This PC' or 'My Computer' and select 'Properties'" -ForegroundColor Yellow
                Write-Host "     - Click on 'Advanced system settings'" -ForegroundColor Yellow
                Write-Host "     - Click on 'Environment Variables'" -ForegroundColor Yellow
                Write-Host "     - Under 'System variables', find and edit 'Path'" -ForegroundColor Yellow
                Write-Host "     - Add the path to MSYS2's bin directory (e.g., C:\msys64\mingw64\bin)" -ForegroundColor Yellow
                Write-Host "  4. After making changes, open a new PowerShell window and try running this script again" -ForegroundColor Yellow
                Write-Host "" -ForegroundColor Yellow
            }

            Write-Host "To fix this, please install one of the following:" -ForegroundColor Yellow
            Write-Host "  1. Visual Studio Build Tools with C++ support: https://visualstudio.microsoft.com/downloads/" -ForegroundColor Yellow
            Write-Host "  2. MinGW-w64: https://www.mingw-w64.org/downloads/" -ForegroundColor Yellow
            Write-Host "  3. MSYS2 (and install GCC): https://www.msys2.org/" -ForegroundColor Yellow
            Write-Host "  4. Clang: https://releases.llvm.org/download.html" -ForegroundColor Yellow
            Write-Host "After installing, make sure the compiler is in your PATH or run this script again." -ForegroundColor Yellow

            $proceedAnyway = Read-Host "Do you want to proceed anyway? (y/n)"
            if ($proceedAnyway -ne "y") {
                Write-Host "Build aborted. Please install a C/C++ compiler and try again." -ForegroundColor Red
                exit 1
            }

            Write-Host "Proceeding without a detected compiler. This will likely fail..." -ForegroundColor Yellow
        }

        try {
            # Use quoted variables to avoid issues with Ninja generator
            cmake -S . -B build -DCMAKE_BUILD_TYPE="$BuildType" -DDEFAULT_API_URL="$ApiUrl" -DDEFAULT_TIMEOUT="$Timeout" -DDEFAULT_CONNECT_TIMEOUT="$ConnectTimeout" -DDEFAULT_SERVER_PORT="$ServerPort"
        } catch {
            Write-Host "Error: CMake configuration failed with default generator." -ForegroundColor Red
            Write-Host "Error details: $_" -ForegroundColor Red

            if ($_ -match "No CMAKE_C_COMPILER could be found" -or $_ -match "No CMAKE_CXX_COMPILER could be found") {
                Write-Host "The error indicates that CMake could not find a C/C++ compiler." -ForegroundColor Red
                Write-Host "Please install a C/C++ compiler as mentioned above and make sure it's in your PATH." -ForegroundColor Red
            }

            Write-Host "Please install one of the recommended build tools and try again." -ForegroundColor Red
            exit 1
        }
    }
}

# Build the project based on ConfigType
if ($ConfigType -eq "Runtime" -or $ConfigType -eq "Both") {
    Write-Host "Building runtime-configurable version (CustomDLL)..."
    # Use quoted BuildType to avoid issues with Ninja generator
    cmake --build build --config "$BuildType" --target CustomDLL
}

if ($ConfigType -eq "Static" -or $ConfigType -eq "Both") {
    Write-Host "Building compile-time configured version (CustomDLLStatic)..."
    # Use quoted BuildType to avoid issues with Ninja generator
    cmake --build build --config "$BuildType" --target CustomDLLStatic
}

# Build the test tools if requested
if ($BuildTools) {
    Write-Host "Building test server and client..."
    # Use quoted BuildType to avoid issues with Ninja generator
    cmake --build build --config "$BuildType" --target TestServer
    cmake --build build --config "$BuildType" --target TestClient
}

# Build the Go server if requested
if ($BuildGoServer) {
    Write-Host "Building Go server..."
    if (Get-Command "go" -ErrorAction SilentlyContinue) {
        Set-Location "tools\go-server"

        # Check if go.mod exists, if not create it
        if (-not (Test-Path "go.mod")) {
            Write-Host "Initializing Go module..."
            & go mod init go-server
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Error: Failed to initialize Go module." -ForegroundColor Red
                Set-Location $rootDir
                return
            }
        }

        # Build the Go server
        & go build -o "..\..\build\bin\GoServer.exe" .
        $buildSuccess = $LASTEXITCODE -eq 0
        Set-Location $rootDir

        if ($buildSuccess) {
            Write-Host "Go server built successfully." -ForegroundColor Green
        } else {
            Write-Host "Error: Go server build failed." -ForegroundColor Red
        }
    } else {
        Write-Host "Go is not installed. Skipping Go server build."
    }
}

# Build the Contact Center simulator if requested
if ($BuildContactCenterSimulator) {
    Write-Host "Building Contact Center simulator..."
    if (Get-Command "go" -ErrorAction SilentlyContinue) {
        Set-Location "tools\contact_center_simulator"

        # Check if go.mod exists, if not create it
        if (-not (Test-Path "go.mod")) {
            Write-Host "Initializing Go module..."
            & go mod init contact-center-simulator
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Error: Failed to initialize Go module." -ForegroundColor Red
                Set-Location $rootDir
                return
            }
        }

        # Build the Contact Center simulator
        & go build -o "..\..\build\bin\ContactCenterSimulator.exe" .
        $buildSuccess = $LASTEXITCODE -eq 0
        Set-Location $rootDir

        if ($buildSuccess) {
            Write-Host "Contact Center simulator built successfully." -ForegroundColor Green
        } else {
            Write-Host "Error: Contact Center simulator build failed." -ForegroundColor Red
        }
    } else {
        Write-Host "Go is not installed. Skipping Contact Center simulator build."
    }
}

# Create subdirectories for distribution
if (-not (Test-Path "dist\tools")) {
    New-Item -ItemType Directory -Path "dist\tools" | Out-Null
}

if ($ConfigType -eq "Both") {
    if (-not (Test-Path "dist\runtime")) {
        New-Item -ItemType Directory -Path "dist\runtime" | Out-Null
    }
    if (-not (Test-Path "dist\static")) {
        New-Item -ItemType Directory -Path "dist\static" | Out-Null
    }
}

# Copy the DLL(s) and config.ini to the dist directory
if ($ConfigType -eq "Runtime" -or $ConfigType -eq "Both") {
    if ($ConfigType -eq "Both") {
        if (Test-Path "build\bin\CustomDLL.dll") {
            Copy-Item "build\bin\CustomDLL.dll" -Destination "dist\runtime\" -Force
        } elseif (Test-Path "build\bin\Release\CustomDLL.dll") {
            Copy-Item "build\bin\Release\CustomDLL.dll" -Destination "dist\runtime\" -Force
        } elseif (Test-Path "build\bin\Debug\CustomDLL.dll") {
            Copy-Item "build\bin\Debug\CustomDLL.dll" -Destination "dist\runtime\" -Force
        } else {
            Write-Host "Warning: CustomDLL.dll not found. Build may have failed." -ForegroundColor Yellow
        }
        Copy-Item "config\config.ini" -Destination "dist\runtime\" -Force
        Write-Host "Runtime-configurable version copied to dist\runtime\"
    } else {
        if (Test-Path "build\bin\CustomDLL.dll") {
            Copy-Item "build\bin\CustomDLL.dll" -Destination "dist\" -Force
        } elseif (Test-Path "build\bin\Release\CustomDLL.dll") {
            Copy-Item "build\bin\Release\CustomDLL.dll" -Destination "dist\" -Force
        } elseif (Test-Path "build\bin\Debug\CustomDLL.dll") {
            Copy-Item "build\bin\Debug\CustomDLL.dll" -Destination "dist\" -Force
        } else {
            Write-Host "Warning: CustomDLL.dll not found. Build may have failed." -ForegroundColor Yellow
        }
        Copy-Item "config\config.ini" -Destination "dist\" -Force
        Write-Host "Runtime-configurable version copied to dist\"
    }
}

if ($ConfigType -eq "Static" -or $ConfigType -eq "Both") {
    if ($ConfigType -eq "Both") {
        if (Test-Path "build\bin\CustomDLLStatic.dll") {
            Copy-Item "build\bin\CustomDLLStatic.dll" -Destination "dist\static\" -Force
        } elseif (Test-Path "build\bin\Release\CustomDLLStatic.dll") {
            Copy-Item "build\bin\Release\CustomDLLStatic.dll" -Destination "dist\static\" -Force
        } elseif (Test-Path "build\bin\Debug\CustomDLLStatic.dll") {
            Copy-Item "build\bin\Debug\CustomDLLStatic.dll" -Destination "dist\static\" -Force
        } else {
            Write-Host "Warning: CustomDLLStatic.dll not found. Build may have failed." -ForegroundColor Yellow
        }
        Write-Host "Compile-time configured version copied to dist\static\"
    } else {
        if (Test-Path "build\bin\CustomDLLStatic.dll") {
            Copy-Item "build\bin\CustomDLLStatic.dll" -Destination "dist\" -Force
        } elseif (Test-Path "build\bin\Release\CustomDLLStatic.dll") {
            Copy-Item "build\bin\Release\CustomDLLStatic.dll" -Destination "dist\" -Force
        } elseif (Test-Path "build\bin\Debug\CustomDLLStatic.dll") {
            Copy-Item "build\bin\Debug\CustomDLLStatic.dll" -Destination "dist\" -Force
        } else {
            Write-Host "Warning: CustomDLLStatic.dll not found. Build may have failed." -ForegroundColor Yellow
        }
        Write-Host "Compile-time configured version copied to dist\"
    }
}

# Copy the test tools if built
if ($BuildTools) {
    $testServerFound = $false
    $testClientFound = $false

    # Try different possible paths for TestServer.exe
    if (Test-Path "build\bin\TestServer.exe") {
        Copy-Item "build\bin\TestServer.exe" -Destination "dist\tools\" -Force
        $testServerFound = $true
    } elseif (Test-Path "build\bin\Release\TestServer.exe") {
        Copy-Item "build\bin\Release\TestServer.exe" -Destination "dist\tools\" -Force
        $testServerFound = $true
    } elseif (Test-Path "build\bin\Debug\TestServer.exe") {
        Copy-Item "build\bin\Debug\TestServer.exe" -Destination "dist\tools\" -Force
        $testServerFound = $true
    }

    # Try different possible paths for TestClient.exe
    if (Test-Path "build\bin\TestClient.exe") {
        Copy-Item "build\bin\TestClient.exe" -Destination "dist\tools\" -Force
        $testClientFound = $true
    } elseif (Test-Path "build\bin\Release\TestClient.exe") {
        Copy-Item "build\bin\Release\TestClient.exe" -Destination "dist\tools\" -Force
        $testClientFound = $true
    } elseif (Test-Path "build\bin\Debug\TestClient.exe") {
        Copy-Item "build\bin\Debug\TestClient.exe" -Destination "dist\tools\" -Force
        $testClientFound = $true
    }

    if (-not $testServerFound) {
        Write-Host "Warning: TestServer.exe not found. Build may have failed." -ForegroundColor Yellow
    }

    if (-not $testClientFound) {
        Write-Host "Warning: TestClient.exe not found. Build may have failed." -ForegroundColor Yellow
    }

    if ($testServerFound -or $testClientFound) {
        Write-Host "Test tools copied to dist\tools\"
    }
}

# Copy the Go server if built
if ($BuildGoServer) {
    if (Test-Path "build\bin\GoServer.exe") {
        Copy-Item "build\bin\GoServer.exe" -Destination "dist\tools\" -Force
        Write-Host "Go server copied to dist\tools\" -ForegroundColor Green
    } else {
        Write-Host "Error: GoServer.exe not found in expected location. The build may have failed." -ForegroundColor Red
        Write-Host "Check the build output above for errors." -ForegroundColor Yellow
    }
}

# Copy the Contact Center simulator if built
if ($BuildContactCenterSimulator) {
    if (Test-Path "build\bin\ContactCenterSimulator.exe") {
        # Copy the simulator executable
        Copy-Item "build\bin\ContactCenterSimulator.exe" -Destination "dist\tools\" -Force
        Write-Host "Contact Center simulator copied to dist\tools\" -ForegroundColor Green

        # Create the directory structure for the runtime DLL
        $runtimeDllTargetDir = "dist\tools\dist\runtime"
        if (-not (Test-Path $runtimeDllTargetDir)) {
            New-Item -ItemType Directory -Path $runtimeDllTargetDir -Force | Out-Null
            Write-Host "Created directory: $runtimeDllTargetDir" -ForegroundColor Green
        }

        # Copy the runtime DLL to the expected location
        if (Test-Path "dist\runtime\CustomDLL.dll") {
            Copy-Item "dist\runtime\CustomDLL.dll" -Destination "$runtimeDllTargetDir\" -Force
            Write-Host "CustomDLL.dll copied to $runtimeDllTargetDir for Contact Center simulator" -ForegroundColor Green
        } else {
            Write-Host "Warning: CustomDLL.dll not found in dist\runtime. Contact Center simulator may not work correctly with runtime DLL." -ForegroundColor Yellow
        }

        # Copy config.ini if it exists
        if (Test-Path "dist\runtime\config.ini") {
            Copy-Item "dist\runtime\config.ini" -Destination "$runtimeDllTargetDir\" -Force
            Write-Host "config.ini copied to $runtimeDllTargetDir for Contact Center simulator" -ForegroundColor Green
        }

        # Create the directory structure for the static DLL
        $staticDllTargetDir = "dist\tools\dist\static"
        if (-not (Test-Path $staticDllTargetDir)) {
            New-Item -ItemType Directory -Path $staticDllTargetDir -Force | Out-Null
            Write-Host "Created directory: $staticDllTargetDir" -ForegroundColor Green
        }

        # Copy the static DLL to the expected location
        if (Test-Path "dist\static\CustomDLLStatic.dll") {
            Copy-Item "dist\static\CustomDLLStatic.dll" -Destination "$staticDllTargetDir\" -Force
            Write-Host "CustomDLLStatic.dll copied to $staticDllTargetDir for Contact Center simulator" -ForegroundColor Green
        } else {
            Write-Host "Warning: CustomDLLStatic.dll not found in dist\static. Contact Center simulator may not work correctly with static DLL." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Error: ContactCenterSimulator.exe not found in expected location. The build may have failed." -ForegroundColor Red
        Write-Host "Check the build output above for errors." -ForegroundColor Yellow
    }
}

Write-Host "Build completed successfully."
