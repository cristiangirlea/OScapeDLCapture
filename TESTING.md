# Testing Guide for CustomDLL Project

This guide provides detailed instructions on how to test the Go Server and Contact Center Simulator components of the CustomDLL project.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Testing the Go Server](#testing-the-go-server)
  - [Step 1: Start the Go Server](#step-1-start-the-go-server)
  - [Step 2: Verify the Server is Running](#step-2-verify-the-server-is-running)
  - [Step 3: Test with the Test Client](#step-3-test-with-the-test-client)
  - [Step 4: Examine the Log Files](#step-4-examine-the-log-files)
  - [Step 5: Test Direct HTTP Requests](#step-5-test-direct-http-requests)
- [Testing the Contact Center Simulator](#testing-the-contact-center-simulator)
  - [Step 1: Start the Contact Center Simulator](#step-1-start-the-contact-center-simulator)
  - [Step 2: Access the Web Interface](#step-2-access-the-web-interface)
  - [Step 3: Run Preset Test Cases](#step-3-run-preset-test-cases)
  - [Step 4: Create Custom Test Cases](#step-4-create-custom-test-cases)
  - [Step 5: Verify the Results](#step-5-verify-the-results)
- [Testing Both Components Together](#testing-both-components-together)
- [Troubleshooting](#troubleshooting)
  - [Go Server Issues](#go-server-issues)
  - [Contact Center Simulator Issues](#contact-center-simulator-issues)
  - [DLL Loading Issues](#dll-loading-issues)

## Prerequisites

Before testing, ensure you have:

1. Built the project with the Go Server and Contact Center Simulator:
   ```powershell
   .\scripts\build.ps1 -BuildGoServer -BuildContactCenterSimulator
   ```

2. Verified that the following files exist:
   - `dist\tools\GoServer.exe`
   - `dist\tools\ContactCenterSimulator.exe`
   - `dist\runtime\CustomDLL.dll`
   - `dist\static\CustomDLLStatic.dll`

## Testing the Go Server

### Step 1: Start the Go Server

1. Open a command prompt or PowerShell window.
2. Navigate to the project root directory.
3. Start the Go Server:
   ```powershell
   dist\tools\GoServer.exe
   ```
   
   You can specify a different port if needed:
   ```powershell
   dist\tools\GoServer.exe -port 8081
   ```

4. You should see output similar to:
   ```
   2023/05/25 12:34:56 Logging curl requests to logs/curl_requests_2023-05-25.log
   2023/05/25 12:34:56 Starting server on :8080
   ```

### Step 2: Verify the Server is Running

1. Open a web browser and navigate to `http://localhost:8080` (or the port you specified).
2. You should see a message: "CustomDLL Test Server" and "Use /api/index.php with appropriate parameters".
3. Check the server console output to confirm that your request was logged.

### Step 3: Test with the Test Client

1. Open another command prompt or PowerShell window.
2. Navigate to the project root directory.
3. Run the test client in server-only mode:
   ```powershell
   dist\tools\TestClient.exe --test-server-only --server-port 8080
   ```
   
   If you specified a different port for the server, use that port here.

4. The test client will run several test cases against the server and display the results.
5. Verify that the tests pass. You should see output like:
   ```
   Server Test Summary: 4 of 4 tests passed
   ```

### Step 4: Examine the Log Files

1. Check the `logs` directory for a file named `curl_requests_YYYY-MM-DD.log`.
2. Open this file to see detailed logs of all requests made to the server.
3. Each request should include:
   - Client IP address
   - HTTP method and URL
   - Request headers
   - Query parameters
   - Response status and body

### Step 5: Test Direct HTTP Requests

You can also test the server directly using a web browser or tools like curl:

1. Test the `procesareDate_1` endpoint:
   ```
   http://localhost:8080/api/index.php?endpoint=procesareDate_1&tel=0744516456&cif=1234KTE&cid=193691036401673
   ```

2. Test the `getInfo` endpoint:
   ```
   http://localhost:8080/api/index.php?endpoint=getInfo&id=12345
   ```

3. Test error handling with an invalid endpoint:
   ```
   http://localhost:8080/api/index.php?endpoint=invalidEndpoint
   ```

4. Test error handling with missing parameters:
   ```
   http://localhost:8080/api/index.php?endpoint=procesareDate_1
   ```

## Testing the Contact Center Simulator

### Step 1: Start the Contact Center Simulator

1. Open a command prompt or PowerShell window.
2. Navigate to the project root directory.
3. Start the Contact Center Simulator:
   ```powershell
   dist\tools\ContactCenterSimulator.exe
   ```
   
   You can specify a different port if needed:
   ```powershell
   dist\tools\ContactCenterSimulator.exe -port 8081
   ```
   
   You can also specify which DLL to use:
   ```powershell
   # Use the static DLL
   dist\tools\ContactCenterSimulator.exe -static
   
   # Use a custom DLL path
   dist\tools\ContactCenterSimulator.exe -dll path\to\your\custom.dll
   ```

4. You should see output similar to:
   ```
   2023/05/25 12:34:56 DLL loaded successfully: C:\path\to\your\project\dist\runtime\CustomDLL.dll
   2023/05/25 12:34:56 Starting Contact Center Simulator on http://localhost:8080
   ```

### Step 2: Access the Web Interface

1. Open a web browser and navigate to `http://localhost:8080` (or the port you specified).
2. You should see the Contact Center Simulator web interface with:
   - A section for preset test cases
   - A form to create custom test cases
   - A section to display test results

### Step 3: Run Preset Test Cases

1. Click on the "procesareDate_1 Test" button to load a preset test case.
2. Click the "Run Test" button to execute the test.
3. Verify that the test succeeds (return code: 0) and displays:
   - The parameters sent to the DLL
   - The input buffer
   - The output buffer
   - The response from the DLL

4. Repeat with other preset test cases:
   - "getInfo Test"
   - "No CFResp Test"
   - "Invalid Endpoint Test"

### Step 4: Create Custom Test Cases

1. Enter a name for your test case in the "Test Name" field.
2. Add parameters by clicking the "Add Parameter" button.
3. For each parameter, enter a key and value.
4. Click the "Run Test" button to execute your custom test.
5. Verify that the test results are displayed correctly.

### Step 5: Verify the Results

For each test case, verify:

1. **Success Tests**: Tests with valid parameters should succeed (return code: 0).
   - The `procesareDate_1` test should return a success message.
   - The `getInfo` test should return information for the specified ID.

2. **Failure Tests**: Tests with invalid parameters should fail (non-zero return code).
   - The "Invalid Endpoint Test" should fail.
   - Tests with missing required parameters should fail.

3. **Response Handling**: Tests with `CFResp=yes` should display a response in the output buffer.
   - Tests without `CFResp=yes` should not have a response in the output buffer.

## Testing Both Components Together

To test both the Go Server and Contact Center Simulator working together:

1. Start the Go Server on port 8080:
   ```powershell
   dist\tools\GoServer.exe
   ```

2. Start the Contact Center Simulator on a different port:
   ```powershell
   dist\tools\ContactCenterSimulator.exe -port 8081
   ```

3. Access the Contact Center Simulator web interface at `http://localhost:8081`.
4. Run test cases that make requests to the Go Server.
5. Verify that:
   - The Contact Center Simulator successfully calls the DLL
   - The DLL makes HTTP requests to the Go Server
   - The Go Server logs these requests
   - The responses are correctly returned to the DLL and displayed in the Contact Center Simulator

## Troubleshooting

### Go Server Issues

1. **Port Already in Use**:
   - Error: `listen tcp :8080: bind: Only one usage of each socket address (protocol/network address/port) is normally permitted.`
   - Solution: Use a different port with the `-port` flag.

2. **Log Directory Issues**:
   - Error: `Failed to create log directory` or `Failed to open log file`
   - Solution: Ensure the application has write permissions to the specified log directory.

### Contact Center Simulator Issues

1. **DLL Loading Failure**:
   - Error: `Failed to load DLL: failed to load DLL: The specified module could not be found.`
   - Solutions:
     - Ensure the DLL exists at the expected path.
     - Use the `-dll` flag to specify the correct path.
     - Check if the DLL has dependencies that are missing.

2. **Port Already in Use**:
   - Error: `listen tcp :8080: bind: Only one usage of each socket address (protocol/network address/port) is normally permitted.`
   - Solution: Use a different port with the `-port` flag.

### DLL Loading Issues

1. **Missing Dependencies**:
   - If the DLL fails to load due to missing dependencies, ensure that:
     - The Visual C++ Redistributable is installed.
     - Any required DLLs are in the same directory or in the system PATH.

2. **32-bit vs 64-bit Issues**:
   - Ensure you're using the correct version of the DLL for your system architecture.
   - The Contact Center Simulator must be built for the same architecture as the DLL.

3. **Permission Issues**:
   - Ensure the application has permission to access and execute the DLL.
   - Try running the application as administrator if necessary.