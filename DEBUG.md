# Debugging Guide for CustomDLL

This guide provides detailed instructions on how to use the debugging features of the Contact Center Simulator to diagnose and fix issues with the CustomDLL.

## Table of Contents

- [Overview](#overview)
- [Debugging Tools](#debugging-tools)
  - [DLL Configuration Viewer](#dll-configuration-viewer)
  - [Server Connection Test](#server-connection-test)
- [Error Codes and Messages](#error-codes-and-messages)
  - [Specific Error Codes](#specific-error-codes)
  - [Getting Detailed Error Messages](#getting-detailed-error-messages)
- [Common Issues and Solutions](#common-issues-and-solutions)
  - [DLL Returns Error Codes](#dll-returns-error-codes)
  - [Missing CFResp Parameter](#missing-cfresp-parameter)
  - [Server Connection Issues](#server-connection-issues)
  - [Configuration Issues](#configuration-issues)
- [Advanced Debugging](#advanced-debugging)
  - [Logging](#logging)
  - [Tracing DLL Calls](#tracing-dll-calls)

## Overview

The Contact Center Simulator includes several debugging tools to help diagnose issues with the CustomDLL. These tools are accessible from the web interface and provide detailed information about the DLL configuration, server connection, and more.

## Error Codes and Messages

The CustomDLL now provides specific error codes and detailed error messages to help diagnose issues.

### Specific Error Codes

The DLL returns the following error codes:

| Error Code | Name | Description |
|------------|------|-------------|
| 0 | SUCCESS | The function completed successfully |
| 1 | INVALID_INPUT | The input parameters are invalid (e.g., null input buffer) |
| 2 | TOO_MANY_PARAMETERS | Too many parameters were provided (more than 100) |
| 3 | CURL_INIT_FAILED | Failed to initialize the curl library |
| 4 | CURL_REQUEST_FAILED | The curl request failed (e.g., network error, timeout) |
| 5 | HTTP_ERROR | The server returned an HTTP error (status code not in 200-299 range) |
| 6 | UNEXPECTED_EXCEPTION | An unexpected exception occurred during execution |

### Getting Detailed Error Messages

In addition to error codes, the DLL provides detailed error messages that explain what went wrong. These messages are automatically displayed in the Contact Center Simulator when an error occurs.

For developers using the DLL directly, you can get the last error message by calling the `GetLastErrorMessage` function:

```cpp
// Function to get the last error message
extern "C" __declspec(dllexport) const char* GetLastErrorMessage();
```

Example usage:

```cpp
long result = CustomFunctionExample(dataIn, dataOut);
if (result != 0) {
    const char* errorMessage = GetLastErrorMessage();
    printf("Error: %s\n", errorMessage);
}
```

The error messages provide specific information about what went wrong, such as:
- "Invalid input: dataIn is null"
- "Too many parameters: 150 (maximum is 100)"
- "Curl request failed: Couldn't connect to server"
- "HTTP error: received status code 404"
- "Unexpected exception: std::bad_alloc"

## Debugging Tools

### DLL Configuration Viewer

The DLL Configuration Viewer shows detailed information about the DLL's configuration, including:

- DLL path
- DLL type (runtime or static)
- Configuration file path (for runtime DLL)
- API URL
- Timeout settings

To use the DLL Configuration Viewer:

1. Start the Contact Center Simulator
2. Open the web interface (http://localhost:8080 by default)
3. Click the "View DLL Configuration" button in the Debugging Tools section
4. Review the configuration information

This tool is useful for verifying that the DLL is using the correct configuration settings, especially the API URL.

### Server Connection Test

The Server Connection Test checks if the server specified in the DLL configuration is running and accessible. It provides information about:

- Server URL
- Connection status
- Response time
- Error details (if any)

To use the Server Connection Test:

1. Start the Contact Center Simulator
2. Open the web interface (http://localhost:8080 by default)
3. Click the "Check Server Connection" button in the Debugging Tools section
4. Review the connection test results

This tool is useful for verifying that the server is running and accessible from the Contact Center Simulator.

## Common Issues and Solutions

### DLL Returns Error Codes

If the DLL returns a non-zero error code, it means that an error occurred during the DLL function call. The specific error code and message provide information about what went wrong:

#### INVALID_INPUT (1)
This error occurs when the input parameters are invalid, such as a null input buffer.

**Solution:**
- Make sure you're passing a valid input buffer to the DLL
- Check that the input buffer is properly formatted

#### TOO_MANY_PARAMETERS (2)
This error occurs when too many parameters are provided (more than 100).

**Solution:**
- Reduce the number of parameters to 100 or fewer

#### CURL_INIT_FAILED (3)
This error occurs when the DLL fails to initialize the curl library.

**Solution:**
- Make sure the curl library is properly installed
- Check that the DLL has access to the necessary system resources

#### CURL_REQUEST_FAILED (4)
This error occurs when the curl request fails, such as due to a network error or timeout.

**Solution:**
- Check your network connection
- Verify that the server is running and accessible
- Increase the timeout value in the configuration

#### HTTP_ERROR (5)
This error occurs when the server returns an HTTP error (status code not in the 200-299 range).

**Solution:**
- Check the server logs for error messages
- Verify that the endpoint exists and is properly configured
- Make sure the request parameters are valid

#### UNEXPECTED_EXCEPTION (6)
This error occurs when an unexpected exception is thrown during execution.

**Solution:**
- Check the detailed error message for information about the exception
- Contact the DLL developer with the error details

To diagnose any of these issues:

1. Check the error details in the test result, which now includes the specific error code and message
2. Verify that all required parameters are provided
3. Check the server connection using the Server Connection Test
4. Verify the DLL configuration using the DLL Configuration Viewer

### Missing CFResp Parameter

One common issue is that the `CFResp=yes` parameter is missing from the input. This parameter is required to get a response from the DLL.

To fix this issue:

1. Add a parameter with key `CFResp` and value `yes` to your test case
2. Run the test again

You can also use the "procesareDate_1 Test" preset, which includes the `CFResp=yes` parameter.

### Server Connection Issues

If the DLL is failing to connect to the server, you can use the Server Connection Test to diagnose the issue. Common server connection issues include:

- Server not running
- Incorrect server URL in the configuration
- Network issues
- Firewall blocking the connection

To fix server connection issues:

1. Make sure the server is running
2. Verify the server URL in the DLL configuration
3. Check your network connection
4. Check your firewall settings

### Configuration Issues

If the DLL is using incorrect configuration settings, you can use the DLL Configuration Viewer to diagnose the issue. Common configuration issues include:

- Incorrect API URL
- Missing or incorrect config.ini file
- Incorrect timeout settings

To fix configuration issues:

1. Verify the DLL configuration using the DLL Configuration Viewer
2. Make sure the config.ini file exists and is accessible
3. Update the config.ini file with the correct settings
4. Restart the Contact Center Simulator

## Advanced Debugging

### Logging

The Contact Center Simulator logs detailed information about the DLL function calls, including:

- Parameters passed to the DLL
- Error details
- Server connection test results

To view the logs:

1. Start the Contact Center Simulator from the command line
2. Look for log messages in the console output

### Tracing DLL Calls

For more detailed debugging, you can trace the DLL function calls by:

1. Running the Contact Center Simulator with verbose logging
2. Using the debugging tools to get detailed information about the DLL configuration and server connection
3. Examining the error details in the test result

This can help identify the exact cause of the issue and provide more information for troubleshooting.
