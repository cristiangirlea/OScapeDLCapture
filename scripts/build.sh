#!/bin/bash
# Build script for CustomDLL (cross-platform)

# Change to the root directory (script is in scripts/ folder)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$ROOT_DIR"

# Create directories if they don't exist
mkdir -p build
mkdir -p dist

# Default values
API_URL="https://someurl/api/index.php"
TIMEOUT=4
CONNECT_TIMEOUT=2
SERVER_PORT=8080
BUILD_TYPE="Release"
CONFIG_TYPE="both"  # Options: runtime, static, both
BUILD_TOOLS=true
BUILD_GO_SERVER=false
BUILD_CONTACT_CENTER_SIMULATOR=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --api-url)
      API_URL="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --connect-timeout)
      CONNECT_TIMEOUT="$2"
      shift 2
      ;;
    --server-port)
      SERVER_PORT="$2"
      shift 2
      ;;
    --build-type)
      BUILD_TYPE="$2"
      shift 2
      ;;
    --config-type)
      CONFIG_TYPE="$2"
      if [[ "$CONFIG_TYPE" != "runtime" && "$CONFIG_TYPE" != "static" && "$CONFIG_TYPE" != "both" ]]; then
        echo "Invalid config-type. Must be 'runtime', 'static', or 'both'."
        exit 1
      fi
      shift 2
      ;;
    --no-tools)
      BUILD_TOOLS=false
      shift
      ;;
    --build-go-server)
      BUILD_GO_SERVER=true
      shift
      ;;
    --build-contact-center-simulator)
      BUILD_CONTACT_CENTER_SIMULATOR=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "Building CustomDLL with the following settings:"
echo "API URL: $API_URL"
echo "Timeout: $TIMEOUT seconds"
echo "Connect Timeout: $CONNECT_TIMEOUT seconds"
echo "Server Port: $SERVER_PORT"
echo "Build Type: $BUILD_TYPE"
echo "Configuration Type: $CONFIG_TYPE (runtime = config.ini support, static = compile-time only)"
echo "Build Tools: $BUILD_TOOLS"
echo "Build Go Server: $BUILD_GO_SERVER"
echo "Build Contact Center Simulator: $BUILD_CONTACT_CENTER_SIMULATOR"

# Configure CMake
cmake -S . -B build -DCMAKE_BUILD_TYPE=$BUILD_TYPE -DDEFAULT_API_URL="$API_URL" -DDEFAULT_TIMEOUT=$TIMEOUT -DDEFAULT_CONNECT_TIMEOUT=$CONNECT_TIMEOUT -DDEFAULT_SERVER_PORT=$SERVER_PORT

# Build the project based on CONFIG_TYPE
if [[ "$CONFIG_TYPE" == "runtime" || "$CONFIG_TYPE" == "both" ]]; then
  echo "Building runtime-configurable version (CustomDLL)..."
  cmake --build build --config $BUILD_TYPE --target CustomDLL
fi

if [[ "$CONFIG_TYPE" == "static" || "$CONFIG_TYPE" == "both" ]]; then
  echo "Building compile-time configured version (CustomDLLStatic)..."
  cmake --build build --config $BUILD_TYPE --target CustomDLLStatic
fi

# Build the test tools if requested
if [[ "$BUILD_TOOLS" == true ]]; then
  echo "Building test server and client..."
  cmake --build build --config $BUILD_TYPE --target TestServer
  cmake --build build --config $BUILD_TYPE --target TestClient
fi

# Build the Go server if requested
if [[ "$BUILD_GO_SERVER" == true ]]; then
  echo "Building Go server..."
  if command -v go &> /dev/null; then
    cd "tools/go-server"
    go build -o "../../build/bin/GoServer" .
    cd "$ROOT_DIR"
    echo "Go server built successfully."
  else
    echo "Go is not installed. Skipping Go server build."
  fi
fi

# Build the Contact Center simulator if requested
if [[ "$BUILD_CONTACT_CENTER_SIMULATOR" == true ]]; then
  echo "Building Contact Center simulator..."
  if command -v go &> /dev/null; then
    cd "tools/contact_center_simulator"
    go build -o "../../build/bin/ContactCenterSimulator" .
    cd "$ROOT_DIR"
    echo "Contact Center simulator built successfully."
  else
    echo "Go is not installed. Skipping Contact Center simulator build."
  fi
fi

# Create subdirectories for distribution
mkdir -p dist/tools

if [[ "$CONFIG_TYPE" == "both" ]]; then
  mkdir -p dist/runtime
  mkdir -p dist/static
fi

# Copy the DLL(s) and config.ini to the dist directory
if [[ "$CONFIG_TYPE" == "runtime" || "$CONFIG_TYPE" == "both" ]]; then
  if [[ "$CONFIG_TYPE" == "both" ]]; then
    # Try different possible filenames for different platforms
    cp build/bin/CustomDLL.dll dist/runtime/ 2>/dev/null || \
    cp build/bin/libCustomDLL.dll dist/runtime/ 2>/dev/null || \
    cp build/bin/libCustomDLL.so dist/runtime/ 2>/dev/null
    cp config/config.ini dist/runtime/
    echo "Runtime-configurable version copied to dist/runtime/"
  else
    cp build/bin/CustomDLL.dll dist/ 2>/dev/null || \
    cp build/bin/libCustomDLL.dll dist/ 2>/dev/null || \
    cp build/bin/libCustomDLL.so dist/ 2>/dev/null
    cp config/config.ini dist/
    echo "Runtime-configurable version copied to dist/"
  fi
fi

if [[ "$CONFIG_TYPE" == "static" || "$CONFIG_TYPE" == "both" ]]; then
  if [[ "$CONFIG_TYPE" == "both" ]]; then
    cp build/bin/CustomDLLStatic.dll dist/static/ 2>/dev/null || \
    cp build/bin/libCustomDLLStatic.dll dist/static/ 2>/dev/null || \
    cp build/bin/libCustomDLLStatic.so dist/static/ 2>/dev/null
    echo "Compile-time configured version copied to dist/static/"
  else
    cp build/bin/CustomDLLStatic.dll dist/ 2>/dev/null || \
    cp build/bin/libCustomDLLStatic.dll dist/ 2>/dev/null || \
    cp build/bin/libCustomDLLStatic.so dist/ 2>/dev/null
    echo "Compile-time configured version copied to dist/"
  fi
fi

# Copy the test tools if built
if [[ "$BUILD_TOOLS" == true ]]; then
  cp build/bin/TestServer dist/tools/ 2>/dev/null || \
  cp build/bin/TestServer.exe dist/tools/ 2>/dev/null
  cp build/bin/TestClient dist/tools/ 2>/dev/null || \
  cp build/bin/TestClient.exe dist/tools/ 2>/dev/null
  echo "Test tools copied to dist/tools/"
fi

# Copy the Go server if built
if [[ "$BUILD_GO_SERVER" == true ]] && [[ -f "build/bin/GoServer" || -f "build/bin/GoServer.exe" ]]; then
  cp build/bin/GoServer dist/tools/ 2>/dev/null || \
  cp build/bin/GoServer.exe dist/tools/ 2>/dev/null
  echo "Go server copied to dist/tools/"
fi

# Copy the Contact Center simulator if built
if [[ "$BUILD_CONTACT_CENTER_SIMULATOR" == true ]] && [[ -f "build/bin/ContactCenterSimulator" || -f "build/bin/ContactCenterSimulator.exe" ]]; then
  cp build/bin/ContactCenterSimulator dist/tools/ 2>/dev/null || \
  cp build/bin/ContactCenterSimulator.exe dist/tools/ 2>/dev/null
  echo "Contact Center simulator copied to dist/tools/"
fi

echo "Build completed successfully."
