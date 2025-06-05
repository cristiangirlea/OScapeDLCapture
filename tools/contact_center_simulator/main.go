package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

// Constants for buffer sizes
const (
	HeaderSize = 2
	KeySize    = 32
	ValueSize  = 128
	PairSize   = KeySize + ValueSize
)

// Default configuration
var (
	DefaultPort    = 8080
	DefaultDllPath = "dist/runtime/CustomDLL.dll"
	StaticDllPath  = "dist/static/CustomDLLStatic.dll"
)

// Global variables
var (
	dllPath              string
	dllInstance          syscall.Handle
	dllFunction          uintptr
	getLastErrorFunction uintptr
)

// Parameter represents a key/value pair
type Parameter struct {
	Key   string `json:"key"`
	Value string `json:"value"`
}

// TestCase represents a test case for the DLL
type TestCase struct {
	Name       string      `json:"name"`
	Parameters []Parameter `json:"parameters"`
}

// TestResult represents the result of a test case
type TestResult struct {
	Success      bool              `json:"success"`
	ReturnCode   int               `json:"returnCode"`
	InputBuffer  string            `json:"inputBuffer"`
	OutputBuffer string            `json:"outputBuffer"`
	Parameters   map[string]string `json:"parameters"`
	Response     string            `json:"response"`
	ErrorDetails string            `json:"errorDetails"`
	DllConfig    string            `json:"dllConfig"`
}

// loadDLL loads the DLL and gets the function pointers
func loadDLL(dllPath string) error {
	// Load the DLL
	dll, err := syscall.LoadLibrary(dllPath)
	if err != nil {
		return fmt.Errorf("failed to load DLL: %v", err)
	}
	dllInstance = dll

	// Get the main function pointer
	proc, err := syscall.GetProcAddress(dll, "CustomFunctionExample")
	if err != nil {
		syscall.FreeLibrary(dll)
		return fmt.Errorf("failed to get function pointer: %v", err)
	}
	dllFunction = proc

	// Get the GetLastErrorMessage function pointer
	errorProc, err := syscall.GetProcAddress(dll, "GetLastErrorMessage")
	if err != nil {
		// This is not a fatal error, as older DLLs might not have this function
		log.Printf("Warning: GetLastErrorMessage function not found in DLL. Detailed error messages will not be available.")
	} else {
		getLastErrorFunction = errorProc
		log.Printf("GetLastErrorMessage function found in DLL. Detailed error messages will be available.")
	}

	return nil
}

// unloadDLL unloads the DLL
func unloadDLL() {
	if dllInstance != 0 {
		syscall.FreeLibrary(dllInstance)
		dllInstance = 0
	}
}

// getLastError gets the last error message from the DLL
func getLastError() string {
	if getLastErrorFunction == 0 {
		return "Error details not available (GetLastErrorMessage function not found in DLL)"
	}

	// Call the GetLastErrorMessage function
	ret, _, _ := syscall.Syscall(getLastErrorFunction, 0, 0, 0, 0)

	// Convert the returned pointer to a Go string
	if ret != 0 {
		// The function returns a pointer to a null-terminated string
		// We need to convert it to a Go string
		var message string
		ptr := ret
		for {
			b := *(*byte)(unsafe.Pointer(ptr))
			if b == 0 {
				break
			}
			message += string(b)
			ptr++
		}
		return message
	}

	return "Unknown error"
}

// createInputBuffer creates an input buffer for the DLL function
func createInputBuffer(parameters []Parameter) []byte {
	// Calculate buffer size
	bufferSize := HeaderSize + len(parameters)*PairSize
	buffer := make([]byte, bufferSize)

	// Set number of parameters
	numParams := fmt.Sprintf("%02d", len(parameters))
	buffer[0] = numParams[0]
	buffer[1] = numParams[1]

	// Set parameters
	for i, param := range parameters {
		// Copy key (up to KeySize characters)
		keyOffset := HeaderSize + i*PairSize
		keyLength := min(len(param.Key), KeySize)
		copy(buffer[keyOffset:keyOffset+keyLength], param.Key)

		// Copy value (up to ValueSize characters)
		valueOffset := keyOffset + KeySize
		valueLength := min(len(param.Value), ValueSize)
		copy(buffer[valueOffset:valueOffset+valueLength], param.Value)
	}

	return buffer
}

// parseOutputBuffer parses the output buffer from the DLL function
func parseOutputBuffer(buffer []byte) map[string]string {
	result := make(map[string]string)

	// Check if buffer is valid
	if len(buffer) < HeaderSize {
		return result
	}

	// Get number of parameters
	numParamsStr := string(buffer[:HeaderSize])
	numParams, err := strconv.Atoi(numParamsStr)
	if err != nil || numParams <= 0 {
		return result
	}

	// Parse parameters
	for i := 0; i < numParams && HeaderSize+i*PairSize+PairSize <= len(buffer); i++ {
		// Extract key and value
		keyStart := HeaderSize + i*PairSize
		valueStart := keyStart + KeySize

		// Extract key (trim null characters)
		key := string(buffer[keyStart : keyStart+KeySize])
		key = strings.TrimRight(key, "\x00")

		// Extract value (trim null characters)
		value := string(buffer[valueStart : valueStart+ValueSize])
		value = strings.TrimRight(value, "\x00")

		// Store in map
		result[key] = value
	}

	return result
}

// callDLL calls the DLL function with the given parameters
func callDLL(parameters []Parameter) TestResult {
	// Create input buffer
	inputBuffer := createInputBuffer(parameters)

	// Create output buffer (initialized to zeros)
	outputBuffer := make([]byte, HeaderSize+PairSize)

	// Log the parameters being passed to the DLL
	log.Printf("Calling DLL with parameters:")
	for _, param := range parameters {
		log.Printf("  %s = %s", param.Key, param.Value)
	}

	// Call DLL function
	ret, _, errNo := syscall.Syscall(dllFunction, 2,
		uintptr(unsafe.Pointer(&inputBuffer[0])),
		uintptr(unsafe.Pointer(&outputBuffer[0])),
		0)

	// Parse output buffer
	outputParams := parseOutputBuffer(outputBuffer)

	// Create parameter map for display
	paramMap := make(map[string]string)
	for _, param := range parameters {
		paramMap[param.Key] = param.Value
	}

	// Generate error details based on return code and parameters
	errorDetails := ""

	// Check for common error conditions
	hasEndpoint := false
	endpointValue := ""
	hasCFResp := false
	hasTel := false
	hasCIF := false
	hasCID := false

	// Extract parameter values for analysis
	paramValues := make(map[string]string)
	for _, param := range parameters {
		paramValues[param.Key] = param.Value

		if param.Key == "Endpoint" {
			hasEndpoint = true
			endpointValue = param.Value
		}
		if param.Key == "CFResp" && param.Value == "yes" {
			hasCFResp = true
		}
		if param.Key == "Tel" {
			hasTel = true
		}
		if param.Key == "CIF" {
			hasCIF = true
		}
		if param.Key == "CID" {
			hasCID = true
		}
	}

	if ret != 0 {
		// Get the error code name based on the return value
		errorCodeName := "UNKNOWN_ERROR"
		switch int(ret) {
		case 1:
			errorCodeName = "INVALID_INPUT"
		case 2:
			errorCodeName = "TOO_MANY_PARAMETERS"
		case 3:
			errorCodeName = "CURL_INIT_FAILED"
		case 4:
			errorCodeName = "CURL_REQUEST_FAILED"
		case 5:
			errorCodeName = "HTTP_ERROR"
		case 6:
			errorCodeName = "UNEXPECTED_EXCEPTION"
		}

		// Get detailed error message from DLL if available
		dllErrorMessage := getLastError()

		// Construct error details
		errorDetails = fmt.Sprintf("DLL function returned error code: %d (%s)", int(ret), errorCodeName)

		// Add detailed error message if available
		if dllErrorMessage != "Unknown error" && dllErrorMessage != "Error details not available (GetLastErrorMessage function not found in DLL)" {
			errorDetails += "\nDetailed error message: " + dllErrorMessage
		}

		// Check for missing required parameters
		if !hasEndpoint {
			errorDetails += "\nMissing 'Endpoint' parameter which is required"
		} else {
			log.Printf("Using endpoint: %s", endpointValue)

			// Check for endpoint-specific required parameters
			if endpointValue == "procesareDate_1" {
				missingParams := []string{}
				if !hasTel {
					missingParams = append(missingParams, "Tel")
				}
				if !hasCIF {
					missingParams = append(missingParams, "CIF")
				}
				if !hasCID {
					missingParams = append(missingParams, "CID")
				}

				if len(missingParams) > 0 {
					errorDetails += fmt.Sprintf("\nMissing required parameters for endpoint '%s': %s", 
						endpointValue, strings.Join(missingParams, ", "))
				}
			} else if endpointValue == "getInfo" {
				if _, hasID := paramValues["ID"]; !hasID {
					errorDetails += fmt.Sprintf("\nMissing required parameter 'ID' for endpoint '%s'", endpointValue)
				}
			}

			// Check if the endpoint is valid
			validEndpoints := map[string]bool{
				"procesareDate_1": true,
				"getInfo": true,
			}

			if !validEndpoints[endpointValue] {
				errorDetails += fmt.Sprintf("\nInvalid endpoint: '%s'. Valid endpoints are: procesareDate_1, getInfo", endpointValue)
			}
		}

		// Check if we're using the correct DLL
		log.Printf("Using DLL: %s", dllPath)

		// Check if the DLL file exists
		if _, err := os.Stat(dllPath); os.IsNotExist(err) {
			errorDetails += fmt.Sprintf("\nDLL file not found at path: %s", dllPath)
		}

		// Check if config.ini exists (for runtime DLL)
		if strings.Contains(strings.ToLower(dllPath), "customdll.dll") && !strings.Contains(strings.ToLower(dllPath), "static") {
			configPath := filepath.Join(filepath.Dir(dllPath), "config.ini")
			if _, err := os.Stat(configPath); os.IsNotExist(err) {
				errorDetails += fmt.Sprintf("\nWarning: config.ini not found at path: %s", configPath)
				log.Printf("Warning: config.ini not found at path: %s", configPath)
			} else {
				log.Printf("Found config.ini at: %s", configPath)
			}
		}

		// Log the error details
		log.Printf("Test failed with error: %s", errorDetails)

		// Check if there was a syscall error
		if errNo != 0 {
			errorDetails += fmt.Sprintf("\nSystem error: %d", errNo)
			log.Printf("System error code: %d", errNo)
		}

		// Check if the Go server is running
		serverRunning := false
		serverURL := "http://localhost:8080"

		// Try to determine the server URL from config.ini if using runtime DLL
		if strings.Contains(strings.ToLower(dllPath), "customdll.dll") && !strings.Contains(strings.ToLower(dllPath), "static") {
			configPath := filepath.Join(filepath.Dir(dllPath), "config.ini")
			if _, err := os.Stat(configPath); err == nil {
				// Read the config.ini file to get the server URL
				configData, err := os.ReadFile(configPath)
				if err == nil {
					configStr := string(configData)
					// Look for base_url in the config
					for _, line := range strings.Split(configStr, "\n") {
						if strings.HasPrefix(strings.TrimSpace(line), "base_url=") {
							baseURL := strings.TrimSpace(strings.TrimPrefix(line, "base_url="))
							// Extract the server part (scheme + host + port)
							if u, err := url.Parse(baseURL); err == nil {
								serverURL = fmt.Sprintf("%s://%s", u.Scheme, u.Host)
								log.Printf("Extracted server URL from config: %s", serverURL)
							}
							break
						}
					}
				}
			}
		}

		// Check if the server is running
		client := http.Client{
			Timeout: 2 * time.Second,
		}
		resp, err := client.Get(serverURL)
		if err != nil {
			errorDetails += fmt.Sprintf("\nCould not connect to server at %s: %v", serverURL, err)
			log.Printf("Server connection test failed: %v", err)
		} else {
			defer resp.Body.Close()
			serverRunning = true
			log.Printf("Server connection test successful: %s returned status %d", serverURL, resp.StatusCode)
		}

		// Add troubleshooting tips
		errorDetails += "\n\nTroubleshooting tips:"
		errorDetails += "\n- Make sure the DLL file exists and is accessible"
		errorDetails += "\n- Check that all required parameters are provided"
		errorDetails += "\n- Verify that the endpoint name is correct"
		errorDetails += "\n- If using the runtime DLL, ensure config.ini exists in the same directory"

		if !serverRunning {
			errorDetails += fmt.Sprintf("\n- The server at %s appears to be unreachable. Make sure it's running.", serverURL)
			errorDetails += "\n- Check your network connection and firewall settings"
		}

		errorDetails += "\n- Check the server logs for more details"
	}

 // Get DLL configuration information
	dllConfig := getDllConfigInfo(dllPath)

	// Create result
	result := TestResult{
		Success:      ret == 0,
		ReturnCode:   int(ret),
		InputBuffer:  formatBufferForDisplay(inputBuffer),
		OutputBuffer: formatBufferForDisplay(outputBuffer),
		Parameters:   paramMap,
		Response:     outputParams["CFResp"],
		ErrorDetails: errorDetails,
		DllConfig:    dllConfig,
	}

	// Log the result
	if ret == 0 {
		log.Printf("Test succeeded")
		if hasCFResp {
			log.Printf("Response: %s", outputParams["CFResp"])
		}
	}

	return result
}

// formatBufferForDisplay formats a buffer for display
func formatBufferForDisplay(buffer []byte) string {
	// Format header
	if len(buffer) < HeaderSize {
		return "Invalid buffer (too short)"
	}

	result := fmt.Sprintf("Header: %c%c (Number of parameters: %s)\n", 
		buffer[0], buffer[1], string(buffer[:HeaderSize]))

	// Parse number of parameters
	numParamsStr := string(buffer[:HeaderSize])
	numParams, err := strconv.Atoi(numParamsStr)
	if err != nil {
		return result + "Error parsing number of parameters"
	}

	// Format parameters
	for i := 0; i < numParams && HeaderSize+i*PairSize+PairSize <= len(buffer); i++ {
		// Extract key and value
		keyStart := HeaderSize + i*PairSize
		valueStart := keyStart + KeySize

		// Extract key (trim null characters)
		key := string(buffer[keyStart : keyStart+KeySize])
		key = strings.TrimRight(key, "\x00")

		// Extract value (trim null characters)
		value := string(buffer[valueStart : valueStart+ValueSize])
		value = strings.TrimRight(value, "\x00")

		result += fmt.Sprintf("Parameter %d: %s = %s\n", i+1, key, value)
	}

	return result
}

// min returns the minimum of two integers
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// getDllConfigInfo reads and returns the DLL's configuration information
func getDllConfigInfo(dllPath string) string {
	var configInfo strings.Builder

	// Add DLL path information
	configInfo.WriteString(fmt.Sprintf("DLL Path: %s\n", dllPath))

	// Check if the DLL exists
	if _, err := os.Stat(dllPath); os.IsNotExist(err) {
		configInfo.WriteString("DLL file not found!\n")
		return configInfo.String()
	}

	// Determine if this is the runtime or static DLL
	isRuntimeDLL := strings.Contains(strings.ToLower(dllPath), "customdll.dll") && 
		!strings.Contains(strings.ToLower(dllPath), "static")
	isStaticDLL := strings.Contains(strings.ToLower(dllPath), "customdllstatic.dll") || 
		strings.Contains(strings.ToLower(dllPath), "static")

	if isRuntimeDLL {
		configInfo.WriteString("DLL Type: Runtime (uses config.ini)\n")

		// Check for config.ini
		configPath := filepath.Join(filepath.Dir(dllPath), "config.ini")
		if _, err := os.Stat(configPath); os.IsNotExist(err) {
			configInfo.WriteString(fmt.Sprintf("Warning: config.ini not found at %s\n", configPath))
			configInfo.WriteString("Using default configuration values\n")
		} else {
			configInfo.WriteString(fmt.Sprintf("Config File: %s\n", configPath))

			// Read config.ini
			configData, err := os.ReadFile(configPath)
			if err != nil {
				configInfo.WriteString(fmt.Sprintf("Error reading config.ini: %v\n", err))
			} else {
				configInfo.WriteString("\nConfiguration Settings:\n")
				configStr := string(configData)

				// Parse and display config settings
				baseURL := "Not specified (using default)"
				timeout := "Not specified (using default)"
				connectTimeout := "Not specified (using default)"

				for _, line := range strings.Split(configStr, "\n") {
					line = strings.TrimSpace(line)
					if line == "" || strings.HasPrefix(line, ";") || strings.HasPrefix(line, "#") {
						continue // Skip empty lines and comments
					}

					if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
						// Section header
						configInfo.WriteString(fmt.Sprintf("\n%s\n", line))
					} else if strings.Contains(line, "=") {
						parts := strings.SplitN(line, "=", 2)
						key := strings.TrimSpace(parts[0])
						value := strings.TrimSpace(parts[1])

						configInfo.WriteString(fmt.Sprintf("  %s = %s\n", key, value))

						// Store specific values for later use
						if key == "base_url" {
							baseURL = value
						} else if key == "timeout" {
							timeout = value
						} else if key == "connect_timeout" {
							connectTimeout = value
						}
					}
				}

				// Summary of important settings
				configInfo.WriteString("\nSummary:\n")
				configInfo.WriteString(fmt.Sprintf("  API URL: %s\n", baseURL))
				configInfo.WriteString(fmt.Sprintf("  Timeout: %s seconds\n", timeout))
				configInfo.WriteString(fmt.Sprintf("  Connect Timeout: %s seconds\n", connectTimeout))
			}
		}
	} else if isStaticDLL {
		configInfo.WriteString("DLL Type: Static (compile-time configuration)\n")
		configInfo.WriteString("Configuration is hardcoded at compile time\n")

		// Try to determine compile-time settings from build script or CMakeLists.txt
		// This is just a best effort since we can't read the values from the DLL directly
		configInfo.WriteString("\nNote: The following settings are based on default values and may not reflect actual compile-time settings:\n")
		configInfo.WriteString("  API URL: https://localhost/api/index.php (default)\n")
		configInfo.WriteString("  Timeout: 4 seconds (default)\n")
		configInfo.WriteString("  Connect Timeout: 2 seconds (default)\n")
	} else {
		configInfo.WriteString("DLL Type: Unknown\n")
	}

	return configInfo.String()
}

// handleRoot handles requests to the root path
func handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	// Serve the HTML interface
	tmpl := template.Must(template.New("index").Parse(`
<!DOCTYPE html>
<html>
<head>
    <title>OpenScape Contact Center Simulator</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            line-height: 1.6;
        }
        h1, h2 {
            color: #333;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        .form-group {
            margin-bottom: 15px;
        }
        label {
            display: block;
            margin-bottom: 5px;
            font-weight: bold;
        }
        input[type="text"] {
            width: 100%;
            padding: 8px;
            box-sizing: border-box;
        }
        button {
            background-color: #4CAF50;
            color: white;
            padding: 10px 15px;
            border: none;
            cursor: pointer;
        }
        button:hover {
            background-color: #45a049;
        }
        .parameters {
            margin-top: 20px;
        }
        .parameter {
            display: flex;
            margin-bottom: 10px;
        }
        .parameter input {
            flex: 1;
            margin-right: 10px;
        }
        .parameter button {
            background-color: #f44336;
        }
        .parameter button:hover {
            background-color: #d32f2f;
        }
        .add-parameter {
            margin-top: 10px;
        }
        .result {
            margin-top: 30px;
            padding: 15px;
            background-color: #f5f5f5;
            border-radius: 5px;
        }
        .success {
            color: green;
        }
        .error {
            color: red;
        }
        .error-details {
            margin: 10px 0;
            padding: 10px;
            background-color: #fff0f0;
            border-left: 4px solid #ff0000;
            border-radius: 4px;
        }
        .error-details h4 {
            margin-top: 0;
            color: #cc0000;
        }
        .error-details pre {
            background-color: #fff8f8;
            border: 1px solid #ffcccc;
            margin: 0;
        }
        .dll-config {
            margin: 10px 0;
            padding: 10px;
            background-color: #f0f8ff;
            border-left: 4px solid #4682b4;
            border-radius: 4px;
        }
        .dll-config pre {
            background-color: #f8faff;
            border: 1px solid #b0c4de;
            margin: 0;
        }
        pre {
            background-color: #eee;
            padding: 10px;
            overflow-x: auto;
        }
        .hidden {
            display: none;
        }
        .preset-buttons {
            margin-bottom: 20px;
        }
        .preset-buttons button {
            margin-right: 10px;
            background-color: #2196F3;
        }
        .preset-buttons button:hover {
            background-color: #0b7dda;
        }
        .debug-tools {
            margin-bottom: 20px;
            padding: 15px;
            background-color: #f5f5f5;
            border-radius: 5px;
            border-left: 4px solid #ff9800;
        }
        .debug-tools h2 {
            color: #ff9800;
            margin-top: 0;
        }
        .debug-button {
            margin-right: 10px;
            background-color: #ff9800;
        }
        .debug-button:hover {
            background-color: #e68a00;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>OpenScape Contact Center Simulator</h1>
        <p>This simulator allows you to test the CustomDLL by simulating how OpenScape Contact Center would call it.</p>

        <div class="preset-buttons">
            <h2>Preset Test Cases</h2>
            <button onclick="loadPreset('procesareDate')">procesareDate_1 Test</button>
            <button onclick="loadPreset('getInfo')">getInfo Test</button>
            <button onclick="loadPreset('noCFResp')">No CFResp Test</button>
            <button onclick="loadPreset('invalidEndpoint')">Invalid Endpoint Test</button>
        </div>

        <div class="debug-tools">
            <h2>Debugging Tools</h2>
            <button onclick="viewDllConfig()" class="debug-button">View DLL Configuration</button>
            <button onclick="checkServerConnection()" class="debug-button">Check Server Connection</button>
        </div>

        <h2>Test Configuration</h2>
        <div class="form-group">
            <label for="testName">Test Name:</label>
            <input type="text" id="testName" placeholder="Enter a name for this test">
        </div>

        <div class="parameters">
            <h3>Parameters</h3>
            <div id="parametersList"></div>
            <div class="add-parameter">
                <button onclick="addParameter()">Add Parameter</button>
            </div>
        </div>

        <div class="form-group" style="margin-top: 20px;">
            <button onclick="runTest()">Run Test</button>
        </div>

        <div id="result" class="result hidden">
            <h2>Test Result</h2>
            <div id="resultContent"></div>
        </div>
    </div>

    <script>
        // Add initial parameters
        window.onload = function() {
            addParameter();
            addParameter();

            // Initialize the result div
            const resultDiv = document.getElementById('result');
            const resultContent = document.getElementById('resultContent');

            // Create a debug result section if it doesn't exist
            if (!document.getElementById('debugResult')) {
                const debugResult = document.createElement('div');
                debugResult.id = 'debugResult';
                debugResult.className = 'result hidden';
                debugResult.innerHTML = '<h2>Debug Result</h2><div id="debugResultContent"></div>';
                resultDiv.parentNode.insertBefore(debugResult, resultDiv.nextSibling);
            }
        };

        // Add a parameter input
        function addParameter() {
            const parametersList = document.getElementById('parametersList');
            const paramIndex = parametersList.children.length;

            const paramDiv = document.createElement('div');
            paramDiv.className = 'parameter';

            const keyInput = document.createElement('input');
            keyInput.type = 'text';
            keyInput.placeholder = 'Key';
            keyInput.id = 'paramKey' + paramIndex;

            const valueInput = document.createElement('input');
            valueInput.type = 'text';
            valueInput.placeholder = 'Value';
            valueInput.id = 'paramValue' + paramIndex;

            const removeButton = document.createElement('button');
            removeButton.textContent = 'Remove';
            removeButton.onclick = function() {
                parametersList.removeChild(paramDiv);
            };

            paramDiv.appendChild(keyInput);
            paramDiv.appendChild(valueInput);
            paramDiv.appendChild(removeButton);

            parametersList.appendChild(paramDiv);
        }

        // Load a preset test case
        function loadPreset(preset) {
            // Clear existing parameters
            const parametersList = document.getElementById('parametersList');
            parametersList.innerHTML = '';

            let testName = '';
            let parameters = [];

            switch(preset) {
                case 'procesareDate':
                    testName = 'procesareDate_1 Test';
                    parameters = [
                        { key: 'Endpoint', value: 'procesareDate_1' },
                        { key: 'CFResp', value: 'yes' },
                        { key: 'Tel', value: '0744516456' },
                        { key: 'CIF', value: '1234KTE' },
                        { key: 'CID', value: '193691036401673' }
                    ];
                    break;
                case 'getInfo':
                    testName = 'getInfo Test';
                    parameters = [
                        { key: 'Endpoint', value: 'getInfo' },
                        { key: 'CFResp', value: 'yes' },
                        { key: 'ID', value: '12345' }
                    ];
                    break;
                case 'noCFResp':
                    testName = 'No CFResp Test';
                    parameters = [
                        { key: 'Endpoint', value: 'procesareDate_1' },
                        { key: 'Tel', value: '0744516456' },
                        { key: 'CIF', value: '1234KTE' },
                        { key: 'CID', value: '193691036401673' }
                    ];
                    break;
                case 'invalidEndpoint':
                    testName = 'Invalid Endpoint Test';
                    parameters = [
                        { key: 'Endpoint', value: 'invalidEndpoint' },
                        { key: 'CFResp', value: 'yes' },
                        { key: 'Data', value: 'test' }
                    ];
                    break;
            }

            // Set test name
            document.getElementById('testName').value = testName;

            // Add parameters
            for (const param of parameters) {
                const paramIndex = parametersList.children.length;

                const paramDiv = document.createElement('div');
                paramDiv.className = 'parameter';

                const keyInput = document.createElement('input');
                keyInput.type = 'text';
                keyInput.placeholder = 'Key';
                keyInput.id = 'paramKey' + paramIndex;
                keyInput.value = param.key;

                const valueInput = document.createElement('input');
                valueInput.type = 'text';
                valueInput.placeholder = 'Value';
                valueInput.id = 'paramValue' + paramIndex;
                valueInput.value = param.value;

                const removeButton = document.createElement('button');
                removeButton.textContent = 'Remove';
                removeButton.onclick = function() {
                    parametersList.removeChild(paramDiv);
                };

                paramDiv.appendChild(keyInput);
                paramDiv.appendChild(valueInput);
                paramDiv.appendChild(removeButton);

                parametersList.appendChild(paramDiv);
            }
        }

        // Run the test
        // View DLL Configuration
        function viewDllConfig() {
            // Show loading message
            const debugResult = document.getElementById('debugResult');
            const debugResultContent = document.getElementById('debugResultContent');
            debugResult.classList.remove('hidden');
            debugResultContent.innerHTML = '<p>Loading DLL configuration...</p>';

            // Send request to get DLL configuration
            fetch('/debug/dll-config', {
                method: 'GET'
            })
            .then(response => response.json())
            .then(result => {
                // Show result
                let html = '<h3>DLL Configuration</h3>';
                html += '<div class="dll-config">';
                html += '<pre>' + result.dllConfig + '</pre>';
                html += '</div>';

                debugResultContent.innerHTML = html;
            })
            .catch(error => {
                console.error('Error:', error);
                debugResultContent.innerHTML = '<p class="error">Error loading DLL configuration: ' + error.message + '</p>';
            });
        }

        // Check Server Connection
        function checkServerConnection() {
            // Show loading message
            const debugResult = document.getElementById('debugResult');
            const debugResultContent = document.getElementById('debugResultContent');
            debugResult.classList.remove('hidden');
            debugResultContent.innerHTML = '<p>Checking server connection...</p>';

            // Send request to check server connection
            fetch('/debug/server-connection', {
                method: 'GET'
            })
            .then(response => response.json())
            .then(result => {
                // Show result
                let html = '<h3>Server Connection Test</h3>';

                if (result.success) {
                    html += '<p class="success">Server connection successful!</p>';
                    html += '<ul>';
                    html += '<li><strong>Server URL:</strong> ' + result.serverUrl + '</li>';
                    html += '<li><strong>Status Code:</strong> ' + result.statusCode + '</li>';
                    html += '<li><strong>Response Time:</strong> ' + result.responseTime + 'ms</li>';
                    html += '</ul>';
                } else {
                    html += '<p class="error">Server connection failed!</p>';
                    html += '<ul>';
                    html += '<li><strong>Server URL:</strong> ' + result.serverUrl + '</li>';
                    html += '<li><strong>Error:</strong> ' + result.error + '</li>';
                    html += '</ul>';

                    html += '<h4>Troubleshooting Tips:</h4>';
                    html += '<ul>';
                    html += '<li>Make sure the server is running</li>';
                    html += '<li>Check your network connection</li>';
                    html += '<li>Verify the server URL in config.ini</li>';
                    html += '<li>Check firewall settings</li>';
                    html += '</ul>';
                }

                debugResultContent.innerHTML = html;
            })
            .catch(error => {
                console.error('Error:', error);
                debugResultContent.innerHTML = '<p class="error">Error checking server connection: ' + error.message + '</p>';
            });
        }

        function runTest() {
            const testName = document.getElementById('testName').value || 'Unnamed Test';
            const parametersList = document.getElementById('parametersList');
            const parameters = [];

            // Collect parameters
            for (let i = 0; i < parametersList.children.length; i++) {
                const paramDiv = parametersList.children[i];
                const keyInput = paramDiv.children[0];
                const valueInput = paramDiv.children[1];

                if (keyInput.value) {
                    parameters.push({
                        key: keyInput.value,
                        value: valueInput.value
                    });
                }
            }

            // Create test case
            const testCase = {
                name: testName,
                parameters: parameters
            };

            // Send to server
            fetch('/run-test', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(testCase)
            })
            .then(response => response.json())
            .then(result => {
                // Show result
                const resultDiv = document.getElementById('result');
                const resultContent = document.getElementById('resultContent');

                let html = '';

                // Add success/failure status
                if (result.success) {
                    html += '<p class="success">Test succeeded (return code: ' + result.returnCode + ')</p>';
                } else {
                    html += '<p class="error">Test failed (return code: ' + result.returnCode + ')</p>';

                    // Add error details if available
                    if (result.errorDetails) {
                        html += '<div class="error-details">';
                        html += '<h4>Error Details:</h4>';
                        html += '<pre>' + result.errorDetails + '</pre>';
                        html += '</div>';
                    }
                }

                // Add parameters
                html += '<h3>Parameters</h3>';
                html += '<ul>';
                for (const [key, value] of Object.entries(result.parameters)) {
                    html += '<li><strong>' + key + ':</strong> ' + value + '</li>';
                }
                html += '</ul>';

                // Add input buffer
                html += '<h3>Input Buffer</h3>';
                html += '<pre>' + result.inputBuffer + '</pre>';

                // Add output buffer if there's a response
                if (result.response || result.outputBuffer.includes('Parameter')) {
                    html += '<h3>Output Buffer</h3>';
                    html += '<pre>' + result.outputBuffer + '</pre>';

                    if (result.response) {
                        html += '<h3>Response</h3>';
                        html += '<pre>' + result.response + '</pre>';
                    }
                } else {
                    html += '<p>No response returned (CFResp=yes not in input or request failed)</p>';
                }

                // Add DLL configuration information
                if (result.dllConfig) {
                    html += '<h3>DLL Configuration</h3>';
                    html += '<div class="dll-config">';
                    html += '<pre>' + result.dllConfig + '</pre>';
                    html += '</div>';
                }

                resultContent.innerHTML = html;
                resultDiv.classList.remove('hidden');
            })
            .catch(error => {
                console.error('Error:', error);
                alert('An error occurred: ' + error.message);
            });
        }
    </script>
</body>
</html>
`))

	tmpl.Execute(w, nil)
}

// handleRunTest handles requests to run a test
func handleRunTest(w http.ResponseWriter, r *http.Request) {
	// Only accept POST requests
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Parse JSON request
	var testCase TestCase
	err := json.NewDecoder(r.Body).Decode(&testCase)
	if err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Call DLL
	result := callDLL(testCase.Parameters)

	// Return result as JSON
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

// handleDllConfig handles requests to get DLL configuration
func handleDllConfig(w http.ResponseWriter, r *http.Request) {
	// Only accept GET requests
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Get DLL configuration
	dllConfig := getDllConfigInfo(dllPath)

	// Return result as JSON
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"dllConfig": dllConfig,
	})
}

// ServerConnectionResult represents the result of a server connection test
type ServerConnectionResult struct {
	Success      bool   `json:"success"`
	ServerUrl    string `json:"serverUrl"`
	StatusCode   int    `json:"statusCode,omitempty"`
	ResponseTime int64  `json:"responseTime,omitempty"`
	Error        string `json:"error,omitempty"`
}

// handleServerConnection handles requests to check server connection
func handleServerConnection(w http.ResponseWriter, r *http.Request) {
	// Only accept GET requests
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Determine server URL
	serverURL := "http://localhost:8080"

	// Try to determine the server URL from config.ini if using runtime DLL
	if strings.Contains(strings.ToLower(dllPath), "customdll.dll") && !strings.Contains(strings.ToLower(dllPath), "static") {
		configPath := filepath.Join(filepath.Dir(dllPath), "config.ini")
		if _, err := os.Stat(configPath); err == nil {
			// Read the config.ini file to get the server URL
			configData, err := os.ReadFile(configPath)
			if err == nil {
				configStr := string(configData)
				// Look for base_url in the config
				for _, line := range strings.Split(configStr, "\n") {
					if strings.HasPrefix(strings.TrimSpace(line), "base_url=") {
						baseURL := strings.TrimSpace(strings.TrimPrefix(line, "base_url="))
						// Extract the server part (scheme + host + port)
						if u, err := url.Parse(baseURL); err == nil {
							serverURL = fmt.Sprintf("%s://%s", u.Scheme, u.Host)
							log.Printf("Extracted server URL from config: %s", serverURL)
							break
						}
					}
				}
			}
		}
	}

	// Create result
	result := ServerConnectionResult{
		ServerUrl: serverURL,
	}

	// Check server connection
	startTime := time.Now()
	client := http.Client{
		Timeout: 5 * time.Second,
	}
	resp, err := client.Get(serverURL)

	if err != nil {
		// Connection failed
		result.Success = false
		result.Error = err.Error()
		log.Printf("Server connection test failed: %v", err)
	} else {
		// Connection successful
		defer resp.Body.Close()
		result.Success = true
		result.StatusCode = resp.StatusCode
		result.ResponseTime = time.Since(startTime).Milliseconds()
		log.Printf("Server connection test successful: %s returned status %d in %d ms", 
			serverURL, resp.StatusCode, result.ResponseTime)
	}

	// Return result as JSON
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

func main() {
	// Parse command line flags
	port := flag.Int("port", DefaultPort, "Port to listen on")
	dllPathFlag := flag.String("dll", DefaultDllPath, "Path to the DLL")
	useStaticDll := flag.Bool("static", false, "Use the static DLL instead of the runtime DLL")
	flag.Parse()

	// Set DLL path based on flags
	if *useStaticDll {
		dllPath = StaticDllPath
		if *dllPathFlag != DefaultDllPath {
			// If both -static and -dll are specified, -dll takes precedence
			dllPath = *dllPathFlag
		}
	} else {
		dllPath = *dllPathFlag
	}

	// Resolve DLL path if it's relative
	if !filepath.IsAbs(dllPath) {
		// Get executable directory
		exePath, err := os.Executable()
		if err == nil {
			exeDir := filepath.Dir(exePath)
			dllPath = filepath.Join(exeDir, dllPath)
		}
	}

	// Load DLL
	err := loadDLL(dllPath)
	if err != nil {
		log.Fatalf("Failed to load DLL: %v", err)
	}
	defer unloadDLL()

	log.Printf("DLL loaded successfully: %s", dllPath)

	// Register handlers
	http.HandleFunc("/", handleRoot)
	http.HandleFunc("/run-test", handleRunTest)
	http.HandleFunc("/debug/dll-config", handleDllConfig)
	http.HandleFunc("/debug/server-connection", handleServerConnection)

	// Log available debugging tools
	log.Printf("Debugging tools available at:")
	log.Printf("  - /debug/dll-config - View DLL configuration")
	log.Printf("  - /debug/server-connection - Test server connection")

	// Start server
	addr := fmt.Sprintf(":%d", *port)
	log.Printf("Starting Contact Center Simulator on http://localhost%s", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}
