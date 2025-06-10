# Generate self-signed certificate for testing
# This script generates a self-signed certificate for testing SSL/TLS connections

param(
    [string]$OutputDir = ".\certs",
    [string]$CertName = "test_cert",
    [string]$CommonName = "localhost",
    [int]$ValidDays = 365
)

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
    Write-Host "Created directory: $OutputDir" -ForegroundColor Green
}

# Full paths for certificate files
$CertPath = Join-Path $OutputDir "$CertName.crt"
$KeyPath = Join-Path $OutputDir "$CertName.key"
$PfxPath = Join-Path $OutputDir "$CertName.pfx"

# Check if OpenSSL is installed
$openssl = Get-Command "openssl" -ErrorAction SilentlyContinue
if (-not $openssl) {
    Write-Host "OpenSSL is not installed or not in the PATH." -ForegroundColor Red
    Write-Host "Please install OpenSSL and make sure it's in your PATH." -ForegroundColor Red
    Write-Host "You can download OpenSSL from https://slproweb.com/products/Win32OpenSSL.html" -ForegroundColor Red
    exit 1
}

Write-Host "Generating self-signed certificate for $CommonName..." -ForegroundColor Yellow

# Generate private key
Write-Host "Generating private key..." -ForegroundColor Yellow
& openssl genrsa -out $KeyPath 2048
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to generate private key." -ForegroundColor Red
    exit 1
}

# Generate certificate signing request (CSR)
Write-Host "Generating certificate signing request..." -ForegroundColor Yellow
$ConfigFile = Join-Path $OutputDir "openssl.cnf"
@"
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = $CommonName

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $CommonName
DNS.2 = localhost
IP.1 = 127.0.0.1
IP.2 = ::1
"@ | Out-File -FilePath $ConfigFile -Encoding ASCII

# Generate self-signed certificate
Write-Host "Generating self-signed certificate..." -ForegroundColor Yellow
& openssl req -new -x509 -key $KeyPath -out $CertPath -days $ValidDays -config $ConfigFile
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to generate self-signed certificate." -ForegroundColor Red
    exit 1
}

# Create PFX file (for Windows use)
Write-Host "Creating PFX file..." -ForegroundColor Yellow
& openssl pkcs12 -export -out $PfxPath -inkey $KeyPath -in $CertPath -passout pass:
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to create PFX file." -ForegroundColor Red
    exit 1
}

# Clean up temporary files
Remove-Item $ConfigFile -Force

Write-Host "Certificate generation complete!" -ForegroundColor Green
Write-Host "Certificate file: $CertPath" -ForegroundColor Green
Write-Host "Private key file: $KeyPath" -ForegroundColor Green
Write-Host "PFX file: $PfxPath" -ForegroundColor Green
Write-Host ""
Write-Host "To use this certificate with the Go server:" -ForegroundColor Yellow
Write-Host "  go-server.exe -cert $CertPath -key $KeyPath" -ForegroundColor Yellow
Write-Host ""
Write-Host "To use this certificate with the test client:" -ForegroundColor Yellow
Write-Host "  test_client.exe --use-https --cert-file $CertPath" -ForegroundColor Yellow
Write-Host ""
Write-Host "To use this certificate with the DLL, add the following to config.ini:" -ForegroundColor Yellow
Write-Host "  [api]" -ForegroundColor Yellow
Write-Host "  verify_ssl=1" -ForegroundColor Yellow
Write-Host "  ssl_cert_file=$CertPath" -ForegroundColor Yellow