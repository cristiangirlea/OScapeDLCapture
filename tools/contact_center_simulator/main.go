package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
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
)

// Global variables
var (
	dllPath     string
	dllInstance syscall.Handle
	dllFunction uintptr
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
}

// loadDLL loads the DLL and gets the function pointer
func loadDLL(dllPath string) error {
	// Load the DLL
	dll, err := syscall.LoadLibrary(dllPath)
	if err != nil {
		return fmt.Errorf("failed to load DLL: %v", err)
	}
	dllInstance = dll

	// Get the function pointer
	proc, err := syscall.GetProcAddress(dll, "CustomFunctionExample")
	if err != nil {
		syscall.FreeLibrary(dll)
		return fmt.Errorf("failed to get function pointer: %v", err)
	}
	dllFunction = proc

	return nil
}

// unloadDLL unloads the DLL
func unloadDLL() {
	if dllInstance != 0 {
		syscall.FreeLibrary(dllInstance)
		dllInstance = 0
	}
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

	// Call DLL function
	ret, _, _ := syscall.Syscall(dllFunction, 2,
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

	// Create result
	result := TestResult{
		Success:      ret == 0,
		ReturnCode:   int(ret),
		InputBuffer:  formatBufferForDisplay(inputBuffer),
		OutputBuffer: formatBufferForDisplay(outputBuffer),
		Parameters:   paramMap,
		Response:     outputParams["CFResp"],
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

func main() {
	// Parse command line flags
	port := flag.Int("port", DefaultPort, "Port to listen on")
	dllPathFlag := flag.String("dll", DefaultDllPath, "Path to the DLL")
	flag.Parse()

	// Set DLL path
	dllPath = *dllPathFlag

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

	// Start server
	addr := fmt.Sprintf(":%d", *port)
	log.Printf("Starting Contact Center Simulator on http://localhost%s", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}