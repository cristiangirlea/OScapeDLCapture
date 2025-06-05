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
- [Build Automation](#build-automation)
  - [Windows (PowerShell)](#windows-powershell)
  - [Linux/macOS (Bash)](#linuxmacos-bash)
  - [CMake Parameterization](#cmake-parameterization)
- [Additional Notes](#additional-notes)
  - [Character Encoding](#character-encoding)
  - [Build Notes](#build-notes)

## 🚀 Quick Start

### Step 1: Prerequisites

- **Windows**: Visual Studio or Visual Studio Build Tools with C++ support
- **Linux/macOS**: GCC/Clang with C++ support
- CMake (version 3.10 or higher)
- libcurl development libraries
- (Optional) Go compiler (for Go server and Contact Center simulator)

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
# Windows
dist\tools\ContactCenterSimulator.exe

# Linux/macOS
./dist/tools/ContactCenterSimulator
```

The simulator provides a web interface (accessible at http://localhost:8080 by default) that allows you to:

1. Create test cases with custom parameters
2. Use preset test cases for common scenarios
3. View the formatted input and output buffers
4. See the DLL's response

## 📝 Technical Details

### Function Signature

```cpp
extern "C" __declspec(dllexport)
long CustomFunctionExample(const char* dataIn, char* dataOut);
```

- `dataIn`: Input buffer containing encoded key/value pairs
- `dataOut`: Output buffer to store returned key/value response (if `CFResp=yes` is included)

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

- `0` → Success
- Any other value → Treated as failure by Contact Center

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
