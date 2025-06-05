cmake_minimum_required(VERSION 3.31)
project(CustomDLL)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# Include directories
include_directories(${CMAKE_SOURCE_DIR}/include)

# Default configuration values (can be overridden with -D options)
set(DEFAULT_API_URL "https://localhost/api/index.php" CACHE STRING "Default API URL")
set(DEFAULT_TIMEOUT 4 CACHE STRING "Default timeout in seconds")
set(DEFAULT_CONNECT_TIMEOUT 2 CACHE STRING "Default connection timeout in seconds")
set(DEFAULT_SERVER_PORT 8080 CACHE STRING "Default server port")

# Add definitions for the default values
add_definitions(
    -DDEFAULT_API_URL="${DEFAULT_API_URL}"
    -DDEFAULT_TIMEOUT=${DEFAULT_TIMEOUT}
    -DDEFAULT_CONNECT_TIMEOUT=${DEFAULT_CONNECT_TIMEOUT}
    -DDEFAULT_SERVER_PORT=${DEFAULT_SERVER_PORT}
)

# Find required packages
find_package(CURL REQUIRED)

# Platform-specific settings
if(WIN32)
    set(PLATFORM_LIBS ws2_32)
    set(DLL_EXTENSION ".dll")
else()
    set(PLATFORM_LIBS dl pthread)
    set(DLL_EXTENSION ".so")
endif()
add_definitions(-DDLL_EXTENSION="${DLL_EXTENSION}")

# Build the standard version with runtime configuration support
add_library(CustomDLL SHARED src/custom.cpp)
target_link_libraries(CustomDLL PRIVATE CURL::libcurl)

# Build the static configuration version (no runtime config.ini)
add_library(CustomDLLStatic SHARED src/custom_static.cpp)
target_link_libraries(CustomDLLStatic PRIVATE CURL::libcurl)

# Build the test server
add_executable(TestServer src/server.cpp)
target_link_libraries(TestServer PRIVATE ${PLATFORM_LIBS})

# Build the test client
add_executable(TestClient tools/test_client.cpp)
target_link_libraries(TestClient PRIVATE CURL::libcurl ${PLATFORM_LIBS})

# Copy configuration files to the output directory
configure_file(config/config.ini ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/config.ini COPYONLY)
