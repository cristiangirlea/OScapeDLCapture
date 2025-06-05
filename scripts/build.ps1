# Build script for CustomDLL

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

# Configure CMake
cmake -S . -B build -DCMAKE_BUILD_TYPE=$BuildType -DDEFAULT_API_URL="$ApiUrl" -DDEFAULT_TIMEOUT=$Timeout -DDEFAULT_CONNECT_TIMEOUT=$ConnectTimeout -DDEFAULT_SERVER_PORT=$ServerPort

# Build the project based on ConfigType
if ($ConfigType -eq "Runtime" -or $ConfigType -eq "Both") {
    Write-Host "Building runtime-configurable version (CustomDLL)..."
    cmake --build build --config $BuildType --target CustomDLL
}

if ($ConfigType -eq "Static" -or $ConfigType -eq "Both") {
    Write-Host "Building compile-time configured version (CustomDLLStatic)..."
    cmake --build build --config $BuildType --target CustomDLLStatic
}

# Build the test tools if requested
if ($BuildTools) {
    Write-Host "Building test server and client..."
    cmake --build build --config $BuildType --target TestServer
    cmake --build build --config $BuildType --target TestClient
}

# Build the Go server if requested
if ($BuildGoServer) {
    Write-Host "Building Go server..."
    if (Get-Command "go" -ErrorAction SilentlyContinue) {
        Set-Location "tools\go-server"
        & go build -o "..\..\build\bin\GoServer.exe" .
        Set-Location $rootDir
        Write-Host "Go server built successfully."
    } else {
        Write-Host "Go is not installed. Skipping Go server build."
    }
}

# Build the Contact Center simulator if requested
if ($BuildContactCenterSimulator) {
    Write-Host "Building Contact Center simulator..."
    if (Get-Command "go" -ErrorAction SilentlyContinue) {
        Set-Location "tools\contact_center_simulator"
        & go build -o "..\..\build\bin\ContactCenterSimulator.exe" .
        Set-Location $rootDir
        Write-Host "Contact Center simulator built successfully."
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
        Copy-Item "build\bin\CustomDLL.dll" -Destination "dist\runtime\" -Force
        Copy-Item "config\config.ini" -Destination "dist\runtime\" -Force
        Write-Host "Runtime-configurable version copied to dist\runtime\"
    } else {
        Copy-Item "build\bin\CustomDLL.dll" -Destination "dist\" -Force
        Copy-Item "config\config.ini" -Destination "dist\" -Force
        Write-Host "Runtime-configurable version copied to dist\"
    }
}

if ($ConfigType -eq "Static" -or $ConfigType -eq "Both") {
    if ($ConfigType -eq "Both") {
        Copy-Item "build\bin\CustomDLLStatic.dll" -Destination "dist\static\" -Force
        Write-Host "Compile-time configured version copied to dist\static\"
    } else {
        Copy-Item "build\bin\CustomDLLStatic.dll" -Destination "dist\" -Force
        Write-Host "Compile-time configured version copied to dist\"
    }
}

# Copy the test tools if built
if ($BuildTools) {
    Copy-Item "build\bin\TestServer.exe" -Destination "dist\tools\" -Force
    Copy-Item "build\bin\TestClient.exe" -Destination "dist\tools\" -Force
    Write-Host "Test tools copied to dist\tools\"
}

# Copy the Go server if built
if ($BuildGoServer -and (Test-Path "build\bin\GoServer.exe")) {
    Copy-Item "build\bin\GoServer.exe" -Destination "dist\tools\" -Force
    Write-Host "Go server copied to dist\tools\"
}

# Copy the Contact Center simulator if built
if ($BuildContactCenterSimulator -and (Test-Path "build\bin\ContactCenterSimulator.exe")) {
    Copy-Item "build\bin\ContactCenterSimulator.exe" -Destination "dist\tools\" -Force
    Write-Host "Contact Center simulator copied to dist\tools\"
}

Write-Host "Build completed successfully."
