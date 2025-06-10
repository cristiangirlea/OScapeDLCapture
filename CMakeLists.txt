cmake_minimum_required(VERSION 3.14)
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
set(DEFAULT_VERIFY_SSL ON CACHE BOOL "Default SSL verification setting")
set(DEFAULT_SSL_CERT_FILE "" CACHE STRING "Default SSL certificate file path")

# Add definitions for the default values
# Determine proper value for DEFAULT_VERIFY_SSL
if(DEFAULT_VERIFY_SSL)
    add_definitions(-DDEFAULT_VERIFY_SSL=1)
else()
    add_definitions(-DDEFAULT_VERIFY_SSL=0)
endif()

# Add the remaining definitions
add_definitions(
    -DDEFAULT_API_URL="${DEFAULT_API_URL}"
    -DDEFAULT_TIMEOUT=${DEFAULT_TIMEOUT}
    -DDEFAULT_CONNECT_TIMEOUT=${DEFAULT_CONNECT_TIMEOUT}
    -DDEFAULT_SERVER_PORT=${DEFAULT_SERVER_PORT}
    -DDEFAULT_SSL_CERT_FILE="${DEFAULT_SSL_CERT_FILE}"
)

# Find required packages
# First try to find system-installed CURL
find_package(CURL QUIET)

# If CURL is not found, download and build it
if(NOT CURL_FOUND)
    message(STATUS "CURL not found on system. Will download and build it.")
    include(FetchContent)
    FetchContent_Declare(
        curl
        URL https://github.com/curl/curl/releases/download/curl-8_4_0/curl-8.4.0.tar.gz
        URL_HASH SHA256=816e41809c043ff285e8c0f06a75a1fa250211bbfb2dc0a037eeef39f1a9e427
    )

    # Configure curl build options
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
    set(BUILD_CURL_EXE OFF CACHE BOOL "" FORCE)
    set(HTTP_ONLY OFF CACHE BOOL "" FORCE)  # Allow HTTPS and other protocols

    # Use Windows Secure Channel for SSL on Windows
    if(WIN32)
        set(CURL_USE_SCHANNEL ON CACHE BOOL "" FORCE)  # Use Windows Secure Channel
        set(CMAKE_USE_SCHANNEL ON CACHE BOOL "" FORCE)  # Use Windows Secure Channel
        set(CURL_USE_OPENSSL OFF CACHE BOOL "" FORCE)  # Disable OpenSSL
        set(CMAKE_USE_OPENSSL OFF CACHE BOOL "" FORCE)  # Disable OpenSSL
    else()
        # On non-Windows platforms, try to use OpenSSL
        set(CURL_USE_OPENSSL ON CACHE BOOL "" FORCE)
        set(CMAKE_USE_OPENSSL ON CACHE BOOL "" FORCE)
    endif()

    set(CMAKE_USE_LIBSSH2 OFF CACHE BOOL "" FORCE)
    set(BUILD_TESTING OFF CACHE BOOL "" FORCE)

    FetchContent_MakeAvailable(curl)

    # Set variables to make it compatible with find_package(CURL)
    set(CURL_FOUND TRUE)
    set(CURL_INCLUDE_DIRS ${curl_SOURCE_DIR}/include)
    set(CURL_LIBRARIES libcurl)

    # Create a custom target that mimics the CURL::libcurl imported target
    if(NOT TARGET CURL::libcurl)
        add_library(CURL::libcurl INTERFACE IMPORTED)
        set_target_properties(CURL::libcurl PROPERTIES
            INTERFACE_INCLUDE_DIRECTORIES "${CURL_INCLUDE_DIRS}"
            INTERFACE_LINK_LIBRARIES "${CURL_LIBRARIES}"
        )
    endif()
endif()

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
set_target_properties(CustomDLL PROPERTIES PREFIX "")

# Build the static configuration version (no runtime config.ini)
add_library(CustomDLLStatic SHARED src/custom_static.cpp)
target_link_libraries(CustomDLLStatic PRIVATE CURL::libcurl)
set_target_properties(CustomDLLStatic PROPERTIES PREFIX "")

# Build the test server
add_executable(TestServer src/server.cpp)
target_link_libraries(TestServer PRIVATE ${PLATFORM_LIBS})

# Build the test client
add_executable(TestClient tools/test_client.cpp)
target_link_libraries(TestClient PRIVATE CURL::libcurl ${PLATFORM_LIBS})

# Build the test static DLL client
add_executable(test_static_dll tools/test_static_dll.cpp)
target_link_libraries(test_static_dll PRIVATE ${PLATFORM_LIBS})

# Copy configuration files to the output directory
configure_file(config/config.ini ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/config.ini COPYONLY)
