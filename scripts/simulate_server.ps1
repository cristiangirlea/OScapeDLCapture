# Simulate Server Script
# This script sets up a local environment to simulate the server at 192.168.102.55
# It modifies the hosts file to map the IP to localhost and starts the Go server

param(
    [switch]$RemoveHostsEntry = $false,
    [int]$Port = 443,
    [string]$CertFile = "",
    [string]$KeyFile = ""
)

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "This script requires administrator privileges to modify the hosts file." -ForegroundColor Red
    Write-Host "Please run PowerShell as administrator and try again." -ForegroundColor Red
    exit 1
}

# Define the IP address and hostname
$hostname = "testing-dll"
$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"

# Function to check if the hosts entry exists
function Test-HostsEntry {
    $hostsContent = Get-Content $hostsFile
    return $hostsContent | Where-Object { $_ -match "^\s*127\.0\.0\.1\s+$hostname\s*.*$" }
}

# Function to add the hosts entry
function Add-HostsEntry {
    $entry = "127.0.0.1 $hostname # Added by simulate_server.ps1"

    # Check if the entry already exists
    if (Test-HostsEntry) {
        Write-Host "Hosts entry already exists." -ForegroundColor Yellow
        return
    }

    # Add the entry to the hosts file
    Add-Content -Path $hostsFile -Value $entry
    Write-Host "Added hosts entry: $entry" -ForegroundColor Green
}

# Function to remove the hosts entry
function Remove-HostsEntry {
    $hostsContent = Get-Content $hostsFile
    $newContent = $hostsContent | Where-Object { $_ -notmatch "^\s*127\.0\.0\.1\s+$hostname\s*.*$" }

    # Check if any changes were made
    if ($hostsContent.Count -eq $newContent.Count) {
        Write-Host "No hosts entry found for $hostname." -ForegroundColor Yellow
        return
    }

    # Write the new content back to the hosts file
    Set-Content -Path $hostsFile -Value $newContent
    Write-Host "Removed hosts entry for $hostname." -ForegroundColor Green
}

# Main script logic
if ($RemoveHostsEntry) {
    # Remove the hosts entry
    Remove-HostsEntry
    Write-Host "Hosts file has been restored." -ForegroundColor Green
    exit 0
}

# Add the hosts entry
Add-HostsEntry

# Determine the path to the Go server
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
$goServerPath = Join-Path $rootDir "tools\go-server"
$goServerExe = Join-Path $rootDir "build\bin\GoServer.exe"

# Check if the Go server executable exists
if (-not (Test-Path $goServerExe)) {
    # Try to build the Go server
    Write-Host "Go server executable not found. Attempting to build it..." -ForegroundColor Yellow

    # Check if Go is installed
    if (Get-Command "go" -ErrorAction SilentlyContinue) {
        Set-Location $goServerPath

        # Check if go.mod exists, if not create it
        if (-not (Test-Path "go.mod")) {
            Write-Host "Initializing Go module..." -ForegroundColor Yellow
            & go mod init go-server
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Error: Failed to initialize Go module." -ForegroundColor Red
                Set-Location $rootDir
                exit 1
            }
        }

        # Build the Go server
        & go build -o "$goServerExe" .
        $buildSuccess = $LASTEXITCODE -eq 0
        Set-Location $rootDir

        if (-not $buildSuccess) {
            Write-Host "Error: Failed to build Go server." -ForegroundColor Red
            Write-Host "Please build the Go server manually using the build.ps1 script with the -BuildGoServer flag." -ForegroundColor Yellow
            exit 1
        }

        Write-Host "Go server built successfully." -ForegroundColor Green
    } else {
        Write-Host "Error: Go is not installed. Cannot build the Go server." -ForegroundColor Red
        Write-Host "Please install Go or build the Go server manually using the build.ps1 script with the -BuildGoServer flag." -ForegroundColor Yellow
        exit 1
    }
}

# Start the Go server
Write-Host "Starting Go server on port $Port..." -ForegroundColor Green

$serverArgs = @("-port", "$Port")

# Add certificate and key files if provided
if ($CertFile -ne "" -and $KeyFile -ne "") {
    $serverArgs += @("-cert", "$CertFile", "-key", "$KeyFile")
    Write-Host "Using HTTPS with certificate: $CertFile and key: $KeyFile" -ForegroundColor Green
} else {
    Write-Host "Using HTTP (no SSL). The DLL expects HTTPS, so you may need to provide certificate and key files." -ForegroundColor Yellow
    Write-Host "You can generate a self-signed certificate using the scripts\generate_cert.ps1 script." -ForegroundColor Yellow
}

# Start the server
Start-Process -FilePath $goServerExe -ArgumentList $serverArgs -NoNewWindow

Write-Host "Server started. Press Ctrl+C to stop." -ForegroundColor Green
Write-Host "The DLL will now connect to the local server when it tries to access $hostname." -ForegroundColor Green
Write-Host "To remove the hosts entry, run this script with the -RemoveHostsEntry switch." -ForegroundColor Green

# Keep the script running to maintain the console output
try {
    while ($true) {
        Start-Sleep -Seconds 1
    }
} finally {
    # This block will execute when the script is interrupted (Ctrl+C)
    Write-Host "Stopping server..." -ForegroundColor Yellow

    # Find and stop the Go server process
    $goServerProcess = Get-Process | Where-Object { $_.Path -eq $goServerExe }
    if ($goServerProcess) {
        $goServerProcess | Stop-Process -Force
        Write-Host "Server stopped." -ForegroundColor Green
    }

    # Ask if the user wants to remove the hosts entry
    $removeEntry = Read-Host "Do you want to remove the hosts entry for $hostname? (y/n)"
    if ($removeEntry -eq "y") {
        Remove-HostsEntry
    } else {
        Write-Host "Hosts entry remains. To remove it later, run this script with the -RemoveHostsEntry switch." -ForegroundColor Yellow
    }
}
