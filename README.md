# CustomDLL Project - OpenScape Contact Center Integration

## 🧩 Overview

This project implements a Windows DLL containing a custom function compatible with OpenScape Contact Center.  
The DLL receives key/value input parameters, performs an HTTP GET request to a configured URL, and optionally returns the result.

## 📋 Table of Contents

- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Testing Tools](#testing-tools)
  - [Test Client](#test-client)
  - [Go Server](#go-server)
  - [Contact Center Simulator](#contact-center-simulator)
- [Testing Guide](#testing-guide)
- [Technical Details](#technical-details)
  - [Function Signature](#function-signature)
  - [Request Behavior](#request-behavior)
  - [Input Format](#input-format)
  - [Output Format](#output-format)
  - [Constraints & Runtime](#constraints--runtime)
  - [Return Codes](#return-codes)
- [Configuration](#configuration)
  - [Runtime Configuration](#runtime-configuration)
  - [Compile-Time Configuration](#compile-time-configuration)
  - [SSL Configuration](#ssl-configuration)
- [Build Automation](#build-automation)
  - [Windows (PowerShell)](#windows-powershell)
  - [Linux/macOS (Bash)](#linuxmacos-bash)
  - [CMake Parameterization](#cmake-parameterization)
- [Additional Notes](#additional-notes)
  - [Character Encoding](#character-encoding)
  - [Build Notes](#build-notes)
- [Troubleshooting](#troubleshooting)
  - [DLL Function Issues](#dll-function-issues)
  - [CURL Library Not Found](#curl-library-not-found)
  - [Compiler Not Found](#compiler-not-found)
  - [Build Fails with Ninja](#build-fails-with-ninja)

## 🚀 Quick Start

### Step 1: Prerequisites

#### For Running the DLL
- Windows operating system
- The compiled DLL files (CustomDLL.dll or CustomDLLStatic.dll)
- (Optional) Configuration file (config.ini) for the runtime-configurable version

#### For Building the Project
- **Windows**: One of the following C/C++ compilers:
  - Visual Studio or Visual Studio Build Tools with C++ support (recommended)
  - MinGW-w64 with GCC
  - MSYS2 with GCC
  - Clang
- **Build tools**:
  - CMake (version 3.14 or higher)
  - One of the following build systems:
    - Visual Studio's MSBuild (included with Visual Studio)
    - Ninja (fastest, automatically used if CLion is installed)
    - MinGW's mingw32-make
    - MSYS2's make
    - NMake (included with Visual Studio Build Tools)
- **Libraries**:
  - libcurl development libraries (required for HTTP requests)
    - For Visual Studio: Install vcpkg and run `vcpkg install curl:x64-windows`
    - For MinGW/MSYS2: Run `pacman -S mingw-w64-x86_64-curl`
    - For CLion: Install using the bundled package manager or manually add to your toolchain
- **Optional**:
  - Go compiler (for Go server and Contact Center simulator)

**Important Notes**:
- Visual Studio is NOT required to run the DLL, only for building it.
- The build script will automatically detect available build tools and use the most appropriate one.
- If you have CLion installed, the script will use CLion's bundled Ninja and compiler.
- If you encounter "No CMAKE_C_COMPILER could be found" errors, you need to install a C/C++ compiler.
- If you encounter "Could NOT find CURL" errors, you need to install the libcurl development libraries (see above).

### Step 2: Building the Project

#### Windows (PowerShell)

```powershell
# Basic build with default settings
.\scripts\build.ps1

# Build with custom API URL and timeouts
.\scripts\build.ps1 -ApiUrl "https://your-api-url.com/api" -Timeout 5 -ConnectTimeout 3

# Build only runtime-configurable version
.\scripts\build.ps1 -ConfigType Runtime

# Build with Go server and Contact Center simulator
.\scripts\build.ps1 -BuildGoServer -BuildContactCenterSimulator
```

#### Linux/macOS (Bash)

```bash
# Basic build with default settings
./scripts/build.sh

# Build with custom API URL and timeouts
./scripts/build.sh --api-url "https://localhost/api" --timeout 5 --connect-timeout 3

# Build only runtime-configurable version
./scripts/build.sh --config-type runtime

# Build with Go server and Contact Center simulator
./scripts/build.sh --build-go-server --build-contact-center-simulator
```

After a successful build, the compiled DLLs and tools will be placed in the `dist` directory.

### Step 3: Running the Project

#### Option 1: Using the Test Server and Client

1. Start the test server:

```bash
# Windows
dist\tools\TestServer.exe

# Linux/macOS
./dist/tools/TestServer
```

2. In a separate terminal, run the test client:

```bash
# Windows
dist\tools\TestClient.exe

# Linux/macOS
./dist/tools/TestClient
```

#### Option 2: Using the Go Server (if built)

```bash
# Windows
dist\tools\GoServer.exe

# Linux/macOS
./dist/tools/GoServer
```

#### Option 3: Using the Contact Center Simulator (if built)

```bash
# Windows
dist\tools\ContactCenterSimulator.exe

# Linux/macOS
./dist/tools/ContactCenterSimulator
```

Then open your web browser and navigate to http://localhost:8080

#### Option 4: Using the DLL Directly in Your Application

1. Include the DLL in your project
2. Import the `CustomFunctionExample` function
3. Call the function with properly formatted input buffers

### Step 4: Verifying the Installation

To verify that everything is working correctly:

1. Run the test client with the `--test-dll-only` flag:

```bash
# Windows
dist\tools\TestClient.exe --test-dll-only

# Linux/macOS
./dist/tools/TestClient --test-dll-only
```

This will run a series of tests against the DLL and report any issues.

## 📁 Project Structure

The project is organized into the following directories:

```
project/
├── src/                       # Source code for the DLL and C++ server
├── include/                   # Header files
├── config/                    # Configuration files
├── scripts/                   # Build scripts
├── tools/                     # Testing tools and simulators
│   ├── go-server/             # Go implementation of the test server
│   ├── contact_center_simulator/ # Contact Center simulator
│   └── test_client.cpp        # C++ test client
└── CMakeLists.txt             # CMake build configuration
```

## 🧪 Testing Tools

### Test Client

The test client is a command-line tool that:
- Tests both the DLL directly and the server via HTTP requests
- Runs predefined test cases covering various scenarios
- Displays detailed input/output buffers and results
- Provides automated verification of DLL functionality

This makes it particularly useful for:
- Automated testing during development
- Regression testing after code changes
- Verifying both DLL and server functionality in a single run

### Go Server

A lightweight Go implementation of the test server is also available. To build it:

```bash
# Windows
.\scripts\build.ps1 -BuildGoServer

# Linux/macOS
./scripts/build.sh --build-go-server
```

Then run it:

```bash
# Windows
dist\tools\GoServer.exe [-port 8080] [-logdir logs]

# Linux/macOS
./dist/tools/GoServer [-port 8080] [-logdir logs]
```

The Go server includes a logging feature that captures all curl requests from the DLL to a log file. This is useful for debugging and monitoring the DLL's HTTP requests. The log files are stored in the specified directory (default: "logs") with filenames based on the current date (e.g., "curl_requests_2023-05-25.log").

The log file contains detailed information about each request, including:
- Client IP address
- HTTP method and URL
- All request headers (including User-Agent which identifies curl)
- All query parameters
- Response status and body

### Contact Center Simulator

A web-based simulator is provided to test the DLL in a way that mimics how OpenScape Contact Center would call it. To build it:

```bash
# Windows
.\scripts\build.ps1 -BuildContactCenterSimulator

# Linux/macOS
./scripts/build.sh --build-contact-center-simulator
```

Then run it:

```bash
# Windows - Using runtime DLL (default)
dist\tools\ContactCenterSimulator.exe

# Windows - Using static DLL
dist\tools\ContactCenterSimulator.exe -static

# Windows - Using a different port (if 8080 is already in use)
dist\tools\ContactCenterSimulator.exe -port 8081

# Linux/macOS - Using runtime DLL (default)
./dist/tools/ContactCenterSimulator

# Linux/macOS - Using static DLL
./dist/tools/ContactCenterSimulator -static

# Linux/macOS - Using a different port (if 8080 is already in use)
./dist/tools/ContactCenterSimulator -port 8081
```

You can also specify a custom DLL path:

```bash
# Windows
dist\tools\ContactCenterSimulator.exe -dll path\to\your\custom.dll

# Linux/macOS
./dist/tools/ContactCenterSimulator -dll path/to/your/custom.dll
```

Multiple flags can be combined:

```bash
# Windows - Using static DLL on port 8081
dist\tools\ContactCenterSimulator.exe -static -port 8081

# Linux/macOS - Using custom DLL on port 8081
./dist/tools/ContactCenterSimulator -dll path/to/your/custom.dll -port 8081
```

The simulator provides a web interface (accessible at http://localhost:8080 by default, or http://localhost:PORT if you specified a different port) that allows you to:

1. Create test cases with custom parameters
2. Use preset test cases for common scenarios
3. View the formatted input and output buffers
4. See the DLL's response

## 🧪 Testing Guide

For detailed instructions on how to test if the Go Server and Contact Center Simulator are working correctly, please refer to the [Testing Guide](TESTING.md). This guide provides:

- Step-by-step instructions for testing each component
- Verification procedures to ensure everything is working correctly
- Troubleshooting tips for common issues
- Examples of expected outputs and behaviors

## 📝 Technical Details

### Function Signatures

```cpp
// Main function to process requests
extern "C" __declspec(dllexport)
long CustomFunctionExample(const char* dataIn, char* dataOut);

// Function to get the last error message
extern "C" __declspec(dllexport)
const char* GetLastErrorMessage();
```

#### CustomFunctionExample
- `dataIn`: Input buffer containing encoded key/value pairs
- `dataOut`: Output buffer to store returned key/value response (if `CFResp=yes` is included)
- Returns: Error code (0 for success, non-zero for failure)

#### GetLastErrorMessage
- Returns: Pointer to a null-terminated string containing the last error message
- Call this function after CustomFunctionExample returns a non-zero error code to get detailed error information

### Request Behavior

The function extracts input parameters and sends a GET request to:

```
https://localhost/api/index.php?{parameters}
```

This URL can be configured via the `config.ini` file or build parameters.

#### Example

Input parameters:
```
Endpoint => procesareDate_1  
CFResp   => yes  
Tel      => 0744516456  
CIF      => 1234KTE  
CID      => 193691036401673
```

Resulting GET request:
```
https://localhost/api/index.php?endpoint=procesareDate_1&tel=0744516456&CIF=1234KTE&CID=193691036401673
```

If `CFResp=yes`, the response body is copied back into the `CFResp` output field.

### Input Format

Contact Center encodes input as a fixed-length string:

- **First 2 characters**: number of key/value pairs (e.g., `01`, `02`, …)
- **Each key/value**: 160 characters total
    - 32 bytes: key
    - 128 bytes: value
- All fields are padded with NULLs (`\0`)

Example Layout:

| Char Pos | 1–2 | 3–34     | 35–162        |
|----------|-----|----------|---------------|
| Value    | 01  | `PIN`    | `1234`        |

### Output Format

Follows the same structure:

- 2 characters: number of output key/value pairs
- Each key/value: 160 characters (32 + 128)

Only returned if a `CFResp=yes` field exists in the input.

### Constraints & Runtime

- The function **must return within 5 seconds**
- Curl timeout is configurable (default: **4 seconds**)
- Must return `0` on success (required by OpenScape Contact Center)
- Thread-safe and reentrant (no global state, no dynamic memory allocations)

### Return Codes

- `0` → Success (SUCCESS)
- `1` → Invalid input parameters (INVALID_INPUT)
- `2` → Too many parameters (TOO_MANY_PARAMETERS)
- `3` → CURL initialization failed (CURL_INIT_FAILED)
- `4` → CURL request failed (CURL_REQUEST_FAILED)
- `5` → HTTP error (HTTP_ERROR)
- `6` → Unexpected exception (UNEXPECTED_EXCEPTION)

Any non-zero value is treated as a failure by Contact Center. For detailed information about error codes and messages, see the [Debugging Guide](DEBUG.md).

## ⚙️ Configuration

This project provides two different approaches to configuration:

### Runtime Configuration

The standard version (CustomDLL.dll) supports external configuration through a `config.ini` file:

```ini
[api]
base_url=https://localhost/api/index.php
timeout=4
connect_timeout=2
```

The configuration file should be placed in the same directory as the DLL. If the file is not found, default values will be used.

#### Configuration Options

- `base_url`: The base URL for the API endpoint
- `timeout`: The request timeout in seconds
- `connect_timeout`: The connection timeout in seconds

### Compile-Time Configuration

The static version (CustomDLLStatic.dll) has all configuration values baked in at compile time. This version:

- Does not read any configuration files at runtime
- Has all settings hardcoded during compilation
- Is faster and more secure for production use
- Requires recompilation to change any settings

This approach is ideal when you want to:
- Maximize performance (no file I/O)
- Create self-contained DLLs that can be distributed without config files
- Ensure consistent behavior across deployments

### SSL Configuration

The project supports SSL/TLS for secure communication with the server. For detailed information about SSL configuration options, see the [SSL Configuration Guide](SSL.md).

#### Runtime Configuration (config.ini)

```ini
[api]
base_url=https://example.com/api/index.php
verify_ssl=1
ssl_cert_file=C:\path\to\certificate.crt
```

- `verify_ssl` - Set to `1` to enable SSL certificate verification, `0` to disable it
- `ssl_cert_file` - Path to the SSL certificate file to use for verification (only used if `verify_ssl=1`)

#### Compile-Time Configuration

```powershell
.\scripts\build.ps1 -VerifySSL $true -SSLCertFile "C:\path\to\certificate.crt"
```

#### Test Certificate Generation

The project includes a script to generate self-signed certificates for testing:

```powershell
.\scripts\generate_cert.ps1
# Or during build
.\scripts\build.ps1 -GenerateTestCertificate
```

## 🛠️ Build Automation

The project includes build scripts for both Windows (PowerShell) and cross-platform (Bash) environments. These scripts support building either or both configuration approaches, as well as the test tools and Go server.

### Windows (PowerShell)

A PowerShell build script (`scripts\build.ps1`) is provided for Windows:

```powershell
# Build both DLL versions with test tools (default)
.\scripts\build.ps1 -ApiUrl "https://yourdomain/api.php" -Timeout 5 -ConnectTimeout 3 -ServerPort 8080 -BuildType Release -ConfigType Both

# Build only the runtime-configurable version
.\scripts\build.ps1 -ApiUrl "https://yourdomain/api.php" -ConfigType Runtime

# Build only the compile-time configured version
.\scripts\build.ps1 -ApiUrl "https://yourdomain/api.php" -ConfigType Static

# Build with Go server (requires Go to be installed)
.\scripts\build.ps1 -BuildGoServer
```

#### Alternative Build Tools for Windows

The build script automatically detects available build tools and uses the most appropriate one in this order:

1. **Visual Studio** (recommended if available)
   - Provides the best debugging experience and IDE integration
   - Supports both 32-bit and 64-bit builds

2. **Ninja**
   - Fastest build times
   - Automatically used if CLion is installed (CLion bundles Ninja)
   - Otherwise, install with: `choco install ninja` or download from https://ninja-build.org/

3. **MinGW**
   - GNU compiler collection for Windows
   - Install with: `choco install mingw` or download from https://www.mingw-w64.org/
   - Make sure `mingw32-make` is in your PATH

4. **MSYS2**
   - Unix-like development environment for Windows
   - Install from https://www.msys2.org/
   - Run `pacman -S mingw-w64-x86_64-toolchain` to install the toolchain
   - Make sure `make` is in your PATH

5. **NMake**
   - Comes with Visual Studio but can be used without the full IDE
   - Install Visual Studio Build Tools from https://visualstudio.microsoft.com/downloads/
   - Make sure `nmake` is in your PATH

No special command-line options are needed to use these alternative build tools - the script automatically detects what's available and uses the best option.

### Linux/macOS (Bash)

A Bash build script (`scripts/build.sh`) is provided for cross-platform builds:

```bash
# Build both DLL versions with test tools (default)
./scripts/build.sh --api-url "https://yourdomain/api.php" --timeout 5 --connect-timeout 3 --server-port 8080 --config-type both

# Build only the runtime-configurable version
./scripts/build.sh --api-url "https://yourdomain/api.php" --config-type runtime

# Build only the compile-time configured version
./scripts/build.sh --api-url "https://yourdomain/api.php" --config-type static

# Build without test tools
./scripts/build.sh --no-tools

# Build with Go server (requires Go to be installed)
./scripts/build.sh --build-go-server
```

### Output Files

When building both versions, the output will be organized as follows:

```
dist/
├── runtime/
│   ├── CustomDLL.dll       # Runtime-configurable version
│   └── config.ini          # Configuration file
├── static/
│   └── CustomDLLStatic.dll # Compile-time configured version
└── tools/
    ├── TestServer.exe      # C++ test server
    ├── TestClient.exe      # C++ test client
    └── GoServer.exe        # Go test server (if built)
```

When building a single version, the DLL will be placed directly in the `dist` directory.

### CMake Parameterization

You can also override default values directly with CMake:

```bash
cmake -S . -B build -DDEFAULT_API_URL="https://yourdomain/api.php" -DDEFAULT_TIMEOUT=5 -DDEFAULT_CONNECT_TIMEOUT=3 -DDEFAULT_SERVER_PORT=8080
cmake --build build --config Release --target CustomDLL        # Build runtime version
cmake --build build --config Release --target CustomDLLStatic  # Build static version
cmake --build build --config Release --target TestServer       # Build C++ test server
cmake --build build --config Release --target TestClient       # Build test client
```

## 📌 Additional Notes

### Character Encoding

- DLL: Must use **ISO-8859-1 single-byte strings**
- COM (if applicable): Must use **UNICODE (codepage 28591)**

### Build Notes

- Set project as a **Shared Library**
- Recommended C++ standard: `C++17`
- If using libcurl:

```cmake
find_package(CURL REQUIRED)
target_link_libraries(CustomDLL PRIVATE CURL::libcurl)
```

DLL is generated in:
```
<build_dir>/bin/CustomDLL.dll
```

## 🔧 Troubleshooting

### DLL Function Issues

If you're experiencing issues with the DLL function returning error codes or not behaving as expected, please refer to the [Debugging Guide](DEBUG.md) for detailed instructions on:

- Using the built-in debugging tools
- Diagnosing common issues
- Tracing DLL function calls
- Fixing configuration problems

The Contact Center Simulator includes several debugging features that can help identify and resolve issues with the DLL.

### CURL Library Not Found

If you encounter the following error during the build process:

```
CMake Error: Could NOT find CURL (missing: CURL_LIBRARY CURL_INCLUDE_DIR)
```

This means that CMake cannot find the libcurl development libraries. 

**Note: As of the latest update, the build system will automatically download and build cURL if it's not found on your system.** This means you can usually ignore this error and continue with the build, as the system will handle it for you.

If you prefer to install cURL manually (which may provide better performance), you can use one of the following methods:

#### For Visual Studio Users:
1. Install vcpkg:
   ```powershell
   git clone https://github.com/Microsoft/vcpkg.git
   cd vcpkg
   .\bootstrap-vcpkg.bat
   ```
2. Install curl:
   ```powershell
   .\vcpkg install curl:x64-windows
   ```
3. Integrate with CMake:
   ```powershell
   .\vcpkg integrate install
   ```
4. Run the build script again

#### For MinGW/MSYS2 Users:
1. Open MSYS2 terminal
2. Install curl:
   ```bash
   pacman -S mingw-w64-x86_64-curl
   ```
3. Make sure the MinGW bin directory is in your PATH
4. Run the build script again

#### For CLion Users with Bundled MinGW:
1. If you're using CLion's bundled MinGW (which is common), you'll need to install MSYS2 to get the curl libraries:
   - Download and install MSYS2 from https://www.msys2.org/
   - Open MSYS2 MinGW 64-bit terminal
   - Update the package database:
     ```bash
     pacman -Syu
     ```
   - Install curl development libraries:
     ```bash
     pacman -S mingw-w64-x86_64-curl
     ```
2. Add the MSYS2 MinGW bin directory to your PATH:
   - Typically located at `C:\msys64\mingw64\bin`
   - Add this to your system PATH environment variable
3. In CLion, go to File > Settings > Build, Execution, Deployment > Toolchains
4. Make sure your MinGW toolchain is configured correctly:
   - If using CLion's bundled MinGW, it should be detected automatically
   - If using MSYS2's MinGW, set the MinGW Home to your MSYS2 MinGW directory (e.g., `C:\msys64\mingw64`)
5. Run the build script again

#### Alternative Method for CLion Users:
1. Open CLion
2. Go to File > Settings > Build, Execution, Deployment > Toolchains
3. Make sure your toolchain has curl installed
4. If not, install it using the package manager for your toolchain
5. Run the build script again

### Compiler Not Found

If you encounter the following error during the build process:

```
CMake Error: No CMAKE_C_COMPILER could be found
CMake Error: No CMAKE_CXX_COMPILER could be found
```

This means that CMake cannot find a C/C++ compiler. To fix this:

1. Make sure you have a C/C++ compiler installed (Visual Studio, MinGW, MSYS2, or Clang)
2. Make sure the compiler is in your PATH
3. If using Visual Studio, make sure the "Desktop development with C++" workload is installed
4. If using MinGW or MSYS2, make sure the bin directory is in your PATH
5. Run the build script again

### Build Fails with Ninja

If you're using Ninja and the build fails with errors, try the following:

1. Make sure you have the Visual C++ Redistributable installed:
   - Download from: https://aka.ms/vs/17/release/vc_redist.x64.exe
   - Install and restart your computer

2. If you're using CLion's bundled Ninja, make sure you also have a compatible compiler:
   - Open CLion
   - Go to File > Settings > Build, Execution, Deployment > Toolchains
   - Make sure your toolchain has a valid C/C++ compiler
   - If not, install one using the package manager for your toolchain

3. Try using a different generator:
   ```powershell
   # Try with Visual Studio generator
   .\scripts\build.ps1

   # Or try with MinGW Makefiles
   $env:PATH = "C:\path\to\mingw\bin;$env:PATH"
   .\scripts\build.ps1
   ```

## 💸 Commercial Use

This project is licensed under the [Apache License 2.0](./LICENSE).  
If you're using it commercially and would like to support its development, consider [sponsoring me](https://github.com/sponsors/yourusername).

