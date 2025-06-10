# SSL Configuration Guide

This document provides information about SSL/TLS configuration options in the CustomDLL project.

## Overview

The CustomDLL project supports SSL/TLS for secure communication with the server. The following components have SSL support:

1. **CustomDLL** - The main DLL that can be configured to use SSL with or without certificate verification
2. **Test Client** - A command-line tool for testing the DLL and server with SSL support
3. **Go Server** - A test server that can serve HTTPS with proper certificate configuration
4. **Contact Center Simulator** - A GUI tool for testing the DLL that can report SSL status

## SSL Configuration Options

### CustomDLL (Runtime Version)

The runtime version of CustomDLL reads SSL configuration from the `config.ini` file:

```ini
[api]
base_url=https://example.com/api/index.php
timeout=4
connect_timeout=2
verify_ssl=1
ssl_cert_file=C:\path\to\certificate.crt
```

- `verify_ssl` - Set to `1` to enable SSL certificate verification, `0` to disable it
- `ssl_cert_file` - Path to the SSL certificate file to use for verification (only used if `verify_ssl=1`)

### CustomDLL (Static Version)

The static version of CustomDLL uses compile-time configuration for SSL:

```cmake
set(DEFAULT_VERIFY_SSL ON CACHE BOOL "Default SSL verification setting")
set(DEFAULT_SSL_CERT_FILE "" CACHE STRING "Default SSL certificate file path")
```

These options can be set when building the DLL:

```powershell
.\scripts\build.ps1 -VerifySSL $true -SSLCertFile "C:\path\to\certificate.crt"
```

### Test Client

The test client supports the following SSL-related command-line options:

```
--use-https           Use HTTPS instead of HTTP for server communication
--no-verify-ssl       Disable SSL certificate verification
--cert-file <path>    Path to the SSL certificate file to use for verification
```

Example:

```powershell
.\dist\tools\test_client.exe --use-https --cert-file ".\certs\test_cert.crt"
```

### Go Server

The Go server supports the following SSL-related command-line options:

```
-cert <path>    Path to the TLS certificate file for HTTPS
-key <path>     Path to the TLS key file for HTTPS
```

Example:

```powershell
.\dist\tools\go-server.exe -cert ".\certs\test_cert.crt" -key ".\certs\test_cert.key"
```

## Generating Test Certificates

The project includes a PowerShell script for generating self-signed certificates for testing:

```powershell
.\scripts\generate_cert.ps1 -OutputDir ".\certs" -CertName "test_cert" -CommonName "localhost"
```

You can also generate a test certificate during the build process:

```powershell
.\scripts\build.ps1 -GenerateTestCertificate
```

This will generate a self-signed certificate in the `certs` directory and configure the build to use it.

## Building with SSL Support

To build the project with SSL support:

```powershell
.\scripts\build.ps1 -VerifySSL $true -SSLCertFile ".\certs\test_cert.crt"
```

To build without SSL verification:

```powershell
.\scripts\build.ps1 -VerifySSL $false
```

To build with SSL verification but without a specific certificate file (will use system certificates):

```powershell
.\scripts\build.ps1 -VerifySSL $true
```

## Testing SSL Configuration

To test the SSL configuration:

1. Generate a test certificate:
   ```powershell
   .\scripts\generate_cert.ps1
   ```

2. Start the Go server with HTTPS:
   ```powershell
   .\dist\tools\go-server.exe -cert ".\certs\test_cert.crt" -key ".\certs\test_cert.key"
   ```

3. Run the test client with HTTPS:
   ```powershell
   .\dist\tools\test_client.exe --use-https --cert-file ".\certs\test_cert.crt"
   ```

4. Configure the DLL to use SSL:
   - Edit `config.ini` to set `verify_ssl=1` and `ssl_cert_file=.\certs\test_cert.crt`
   - Or build the static version with `-VerifySSL $true -SSLCertFile ".\certs\test_cert.crt"`

## Troubleshooting

### Certificate Verification Failures

If you encounter certificate verification failures:

1. Make sure the certificate file exists and is accessible
2. Check that the certificate is valid for the domain you're connecting to
3. Try disabling certificate verification for testing (`verify_ssl=0` or `--no-verify-ssl`)
4. Check the certificate's expiration date

### OpenSSL Not Found

If you get an error about OpenSSL not being found when generating certificates:

1. Install OpenSSL from https://slproweb.com/products/Win32OpenSSL.html
2. Add the OpenSSL bin directory to your PATH environment variable
3. Restart your command prompt or PowerShell session