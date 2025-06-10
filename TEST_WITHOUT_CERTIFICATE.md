# Testing DLL Connection Without Certificate

This guide explains how to test the DLL connection to the test server on port 443 without using a certificate.

## Overview

The DLL is configured to connect to `https://192.168.102.55/testoscc.php`. To test it without a certificate, we need to:

1. Configure the DLL to ignore SSL certificate validation (already done)
2. Map the IP address `192.168.102.55` to localhost (`127.0.0.1`)
3. Run a local server on port 443 that handles requests to `/testoscc.php`

## Prerequisites

- Windows operating system
- Administrator privileges (required to modify the hosts file and bind to port 443)
- PowerShell

## Step 1: Verify DLL Configuration

Both DLLs are already configured to ignore SSL certificate validation:

- **Runtime DLL (CustomDLL.dll)**: The `verify_ssl=0` setting in `config.ini` disables certificate validation
- **Static DLL (CustomDLLStatic.dll)**: The `verifySSL` variable is hardcoded to `false`

No changes are needed to the DLL code or configuration.

## Step 2: Start the Simulation Server

Run the simulation server script with administrator privileges:

```powershell
# Run from the repository root as Administrator
.\scripts\simulate_server.ps1 -Port 443
```

This script will:
1. Add an entry to your hosts file to map `192.168.102.55` to `127.0.0.1`
2. Start the Go server on port 443
3. The server will run in HTTP mode since no certificate is provided

## Step 3: Test the DLL

You can now test the DLL using the test_static_dll tool:

```powershell
# Run from the repository root
.\build\bin\test_static_dll.exe --verbose
```

This will:
1. Load the CustomDLLStatic.dll
2. Call the CustomFunctionExample function with test parameters
3. The DLL will connect to the server at https://192.168.102.55/testoscc.php
4. Since SSL certificate validation is disabled, the connection will succeed even though the server is running in HTTP mode

## Expected Results

If everything is working correctly:

1. The server logs will show incoming requests to `/testoscc.php`
2. The test_static_dll.exe will report successful test cases
3. No SSL certificate validation errors will occur

## Troubleshooting

### Port 443 Already in Use

If port 443 is already in use (common if you have IIS, Apache, or other web servers installed), you can use a different port:

```powershell
.\scripts\simulate_server.ps1 -Port 8443
```

However, if you use a different port, you'll need to modify the DLL or config.ini to use that port.

### Server Not Starting

If the Go server doesn't start, make sure you have Go installed and try building it manually:

```powershell
.\scripts\build.ps1 -BuildGoServer
```

### DLL Not Connecting

If the DLL fails to connect to the server, check:
1. The hosts file entry was added correctly
2. The server is running and listening on the correct port
3. The DLL is configured to ignore SSL certificate validation

## Cleaning Up

When you're done testing, stop the simulation server by pressing `Ctrl+C` in the PowerShell window. The script will ask if you want to remove the hosts file entry. If you choose not to remove it at that time, you can remove it later with:

```powershell
# Run from the repository root as Administrator
.\scripts\simulate_server.ps1 -RemoveHostsEntry
```