# Server Simulation Guide

This guide explains how to simulate the server at `192.168.102.55` for testing the CustomDLL and CustomDLLStatic libraries.

## Overview

The DLL is configured to connect to `https://192.168.102.55/testoscc.php`. To test it locally, we need to:

1. Map the IP address `192.168.102.55` to localhost (`127.0.0.1`)
2. Run a local HTTPS server that handles requests to `/testoscc.php`
3. Generate a self-signed certificate for HTTPS

## Prerequisites

- Windows operating system
- Administrator privileges (required to modify the hosts file)
- PowerShell
- Go (optional, required only if you need to build the Go server)
- OpenSSL (required for generating certificates)

## Step 1: Generate a Self-Signed Certificate

First, generate a self-signed certificate for HTTPS:

```powershell
# Run from the repository root
.\scripts\generate_cert.ps1 -OutputDir ".\certs" -CertName "test_cert" -CommonName "localhost"
```

This will create:
- `certs\test_cert.crt` - The certificate file
- `certs\test_cert.key` - The private key file
- `certs\test_cert.pfx` - The PFX file (for Windows use)

## Step 2: Start the Simulation Server

Run the simulation server script with administrator privileges:

```powershell
# Run from the repository root as Administrator
.\scripts\simulate_server.ps1 -Port 443 -CertFile ".\certs\test_cert.crt" -KeyFile ".\certs\test_cert.key"
```

This script will:
1. Add an entry to your hosts file to map `192.168.102.55` to `127.0.0.1`
2. Start the Go server on port 443 (the default HTTPS port)
3. Configure the server to use the generated certificate

The server will now handle requests to `https://192.168.102.55/testoscc.php`.

## Step 3: Test the DLL

You can now test the DLL using the test_static_dll tool:

```powershell
# Run from the repository root
.\build\bin\test_static_dll.exe --verbose
```

Or use the contact_center_simulator:

```powershell
# Run from the repository root
.\build\bin\ContactCenterSimulator.exe
```

## Cleaning Up

When you're done testing, stop the simulation server by pressing `Ctrl+C` in the PowerShell window. The script will ask if you want to remove the hosts file entry. If you choose not to remove it at that time, you can remove it later with:

```powershell
# Run from the repository root as Administrator
.\scripts\simulate_server.ps1 -RemoveHostsEntry
```

## Troubleshooting

### Certificate Warnings

Since we're using a self-signed certificate, your browser or other tools might show security warnings. This is normal and can be safely ignored for testing purposes.

### Port 443 Already in Use

If port 443 is already in use (common if you have IIS, Apache, or other web servers installed), you can use a different port:

```powershell
.\scripts\simulate_server.ps1 -Port 8443 -CertFile ".\certs\test_cert.crt" -KeyFile ".\certs\test_cert.key"
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
3. The certificate and key files are valid
4. The DLL is configured to ignore SSL certificate validation (verify_ssl=0 in config.ini)