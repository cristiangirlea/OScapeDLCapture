package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Default configuration
const (
	DefaultPort = 8080
	DefaultLogDir = "logs"
)

// Global loggers
var (
	mainLogger  *log.Logger
	errorLogger *log.Logger
	dataLogger  *log.Logger
)

func main() {
	// Parse command line flags
	port := flag.Int("port", DefaultPort, "Port to listen on")
	logDir := flag.String("logdir", DefaultLogDir, "Directory to store log files")
	flag.Parse()

	// Create log directory if it doesn't exist
	if err := os.MkdirAll(*logDir, 0755); err != nil {
		log.Fatalf("Failed to create log directory: %v", err)
	}

	// Create log files with current date
	date := time.Now().Format("2006-01-02")
	mainLogFileName := fmt.Sprintf("curl_requests_%s.log", date)
	errorLogFileName := fmt.Sprintf("error_responses_%s.log", date)
	dataLogFileName := fmt.Sprintf("dll_data_%s.log", date)

	mainLogFilePath := filepath.Join(*logDir, mainLogFileName)
	errorLogFilePath := filepath.Join(*logDir, errorLogFileName)
	dataLogFilePath := filepath.Join(*logDir, dataLogFileName)

	// Open main log file
	mainLogFile, err := os.OpenFile(mainLogFilePath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		log.Fatalf("Failed to open main log file: %v", err)
	}
	defer mainLogFile.Close()

	// Open error log file
	errorLogFile, err := os.OpenFile(errorLogFilePath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		log.Fatalf("Failed to open error log file: %v", err)
	}
	defer errorLogFile.Close()

	// Open data log file
	dataLogFile, err := os.OpenFile(dataLogFilePath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		log.Fatalf("Failed to open data log file: %v", err)
	}
	defer dataLogFile.Close()

	// Set up loggers
	mainWriter := io.MultiWriter(os.Stdout, mainLogFile)
	errorWriter := io.MultiWriter(os.Stderr, errorLogFile)
	dataWriter := dataLogFile

	mainLogger = log.New(mainWriter, "", log.LstdFlags|log.Lmicroseconds)
	errorLogger = log.New(errorWriter, "ERROR: ", log.LstdFlags|log.Lmicroseconds)
	dataLogger = log.New(dataWriter, "", log.LstdFlags|log.Lmicroseconds)

	// Set the standard logger to use mainLogger for backward compatibility
	log.SetOutput(mainWriter)
	log.SetFlags(log.LstdFlags | log.Lmicroseconds)

	mainLogger.Printf("Logging curl requests to %s", mainLogFilePath)
	mainLogger.Printf("Logging error responses to %s", errorLogFilePath)
	mainLogger.Printf("Logging DLL data to %s", dataLogFilePath)

	// Register handlers
	http.HandleFunc("/", handleRoot)
	http.HandleFunc("/api/index.php", handleAPI)

	// Start server
	addr := fmt.Sprintf(":%d", *port)
	log.Printf("Starting server on %s", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}

// getCaseInsensitiveFormValue gets a form value in a case-insensitive manner
// This function is used to handle parameter names regardless of their case.
// For example, it will find "endpoint", "Endpoint", "ENDPOINT", etc.
// This is necessary because some clients (like the CustomDLL) may send parameters
// with different case than what the server expects.
func getCaseInsensitiveFormValue(r *http.Request, paramName string) string {
	// First try the exact case
	value := r.FormValue(paramName)
	if value != "" {
		return value
	}

	// If not found, try case-insensitive search
	paramNameLower := strings.ToLower(paramName)
	for key, values := range r.Form {
		if strings.ToLower(key) == paramNameLower && len(values) > 0 {
			// Log if we're using a non-standard case version
			if key != paramName {
				mainLogger.Printf("Note: Using '%s' parameter instead of standard '%s'", key, paramName)
			}
			return values[0]
		}
	}

	return ""
}

// handleRoot handles requests to the root path
func handleRoot(w http.ResponseWriter, r *http.Request) {
	// Get client IP address
	clientIP := r.RemoteAddr
	if forwardedFor := r.Header.Get("X-Forwarded-For"); forwardedFor != "" {
		clientIP = forwardedFor
	}

	mainLogger.Printf("Received request from %s: %s %s", clientIP, r.Method, r.URL.Path)

	// Log request headers
	mainLogger.Printf("Request headers:")
	for name, values := range r.Header {
		mainLogger.Printf("  %s: %s", name, strings.Join(values, ", "))
	}

	fmt.Fprintf(w, "CustomDLL Test Server\n")
	fmt.Fprintf(w, "Use /api/index.php with appropriate parameters\n")

	mainLogger.Printf("Response: 200 OK - Root page served")
}

// handleAPI handles requests to the API endpoint
func handleAPI(w http.ResponseWriter, r *http.Request) {
	// Get client IP address
	clientIP := r.RemoteAddr
	if forwardedFor := r.Header.Get("X-Forwarded-For"); forwardedFor != "" {
		clientIP = forwardedFor
	}

	// Log basic request info
	mainLogger.Printf("=== CURL REQUEST FROM DLL ===")
	mainLogger.Printf("Received API request from %s: %s %s", clientIP, r.Method, r.URL.String())

	// Log request headers (useful for identifying curl)
	mainLogger.Printf("Request headers:")
	for name, values := range r.Header {
		mainLogger.Printf("  %s: %s", name, strings.Join(values, ", "))
	}

	// Parse query parameters
	err := r.ParseForm()
	if err != nil {
		errMsg := fmt.Sprintf("Error parsing form data: %v", err)
		http.Error(w, "Error parsing form data", http.StatusBadRequest)
		errorLogger.Printf("Response: 400 Bad Request - %s", errMsg)
		errorLogger.Printf("Client IP: %s, URL: %s", clientIP, r.URL.String())
		mainLogger.Printf("Response: 400 Bad Request - %s", errMsg)
		mainLogger.Printf("=== END CURL REQUEST ===")
		return
	}

	// Log all parameters
	mainLogger.Printf("Request parameters:")

	// Create a map for JSON export
	requestData := make(map[string]interface{})
	requestData["timestamp"] = time.Now().Format(time.RFC3339)
	requestData["client_ip"] = clientIP
	requestData["method"] = r.Method
	requestData["url"] = r.URL.String()
	requestData["parameters"] = make(map[string]string)

	for key, values := range r.Form {
		mainLogger.Printf("  %s = %s", key, strings.Join(values, ", "))
		requestData["parameters"].(map[string]string)[key] = strings.Join(values, ", ")
	}

	// Export request data to data log
	if jsonData, err := json.MarshalIndent(requestData, "", "  "); err == nil {
		dataLogger.Printf("REQUEST DATA: %s", string(jsonData))
	}

	// Check for required parameters - case-insensitive approach
	endpoint := getCaseInsensitiveFormValue(r, "endpoint")

	// If no endpoint parameter found, return an error
	if endpoint == "" {
		errMsg := "Error: Missing 'endpoint' parameter"
		http.Error(w, errMsg, http.StatusBadRequest)
		errorLogger.Printf("Response: 400 Bad Request - %s", errMsg)
		errorLogger.Printf("Client IP: %s, URL: %s", clientIP, r.URL.String())
		mainLogger.Printf("Response: 400 Bad Request - %s", errMsg)
		mainLogger.Printf("=== END CURL REQUEST ===")
		return
	}

	// Process based on endpoint
	switch strings.ToLower(endpoint) {
	case "procesaredate_1":
		handleProcessareDate(w, r)
	case "getinfo":
		handleGetInfo(w, r)
	case "savecid":
		handleSaveCID(w, r)
	default:
		errMsg := fmt.Sprintf("Error: Unknown endpoint '%s'", endpoint)
		http.Error(w, errMsg, http.StatusBadRequest)
		errorLogger.Printf("Response: 400 Bad Request - %s", errMsg)
		errorLogger.Printf("Client IP: %s, URL: %s, Endpoint: %s", clientIP, r.URL.String(), endpoint)
		mainLogger.Printf("Response: 400 Bad Request - %s", errMsg)
		mainLogger.Printf("=== END CURL REQUEST ===")
	}
}

// handleProcessareDate handles the procesareDate_1 endpoint
func handleProcessareDate(w http.ResponseWriter, r *http.Request) {
	// Get client IP for logging
	clientIP := r.RemoteAddr
	if forwardedFor := r.Header.Get("X-Forwarded-For"); forwardedFor != "" {
		clientIP = forwardedFor
	}

	// Check for required parameters - case-insensitive approach
	tel := getCaseInsensitiveFormValue(r, "tel")
	cif := getCaseInsensitiveFormValue(r, "cif")
	cid := getCaseInsensitiveFormValue(r, "cid")

	if tel == "" || cif == "" || cid == "" {
		errMsg := "Error: Missing required parameters (tel, cif, cid)"
		http.Error(w, errMsg, http.StatusBadRequest)
		errorLogger.Printf("Response: 400 Bad Request - %s", errMsg)
		errorLogger.Printf("Client IP: %s, Endpoint: procesareDate_1", clientIP)
		mainLogger.Printf("Response: 400 Bad Request - %s", errMsg)
		mainLogger.Printf("=== END CURL REQUEST ===")
		return
	}

	// Generate response
	response := fmt.Sprintf("Success: Processed data for Tel=%s, CIF=%s, CID=%s", tel, cif, cid)
	fmt.Fprintln(w, response)

	// Create response data for JSON export
	responseData := map[string]interface{}{
		"timestamp":  time.Now().Format(time.RFC3339),
		"client_ip":  clientIP,
		"endpoint":   "procesareDate_1",
		"status":     200,
		"parameters": map[string]string{
			"tel": tel,
			"cif": cif,
			"cid": cid,
		},
		"response": response,
	}

	// Export response data to data log
	if jsonData, err := json.MarshalIndent(responseData, "", "  "); err == nil {
		dataLogger.Printf("RESPONSE DATA: %s", string(jsonData))
	}

	// Log the successful response
	mainLogger.Printf("Response: 200 OK - procesareDate_1 endpoint")
	mainLogger.Printf("Response body: %s", response)
	mainLogger.Printf("=== END CURL REQUEST ===")
}

// handleGetInfo handles the getInfo endpoint
func handleGetInfo(w http.ResponseWriter, r *http.Request) {
	// Get client IP for logging
	clientIP := r.RemoteAddr
	if forwardedFor := r.Header.Get("X-Forwarded-For"); forwardedFor != "" {
		clientIP = forwardedFor
	}

	// Check for required parameters - case-insensitive approach
	id := getCaseInsensitiveFormValue(r, "id")
	if id == "" {
		errMsg := "Error: Missing required parameter 'id'"
		http.Error(w, errMsg, http.StatusBadRequest)
		errorLogger.Printf("Response: 400 Bad Request - %s", errMsg)
		errorLogger.Printf("Client IP: %s, Endpoint: getInfo", clientIP)
		mainLogger.Printf("Response: 400 Bad Request - %s", errMsg)
		mainLogger.Printf("=== END CURL REQUEST ===")
		return
	}

	// Generate response
	response := fmt.Sprintf("Info for ID=%s: Customer information retrieved successfully", id)
	fmt.Fprintln(w, response)

	// Create response data for JSON export
	responseData := map[string]interface{}{
		"timestamp":  time.Now().Format(time.RFC3339),
		"client_ip":  clientIP,
		"endpoint":   "getInfo",
		"status":     200,
		"parameters": map[string]string{
			"id": id,
		},
		"response": response,
	}

	// Export response data to data log
	if jsonData, err := json.MarshalIndent(responseData, "", "  "); err == nil {
		dataLogger.Printf("RESPONSE DATA: %s", string(jsonData))
	}

	// Log the successful response
	mainLogger.Printf("Response: 200 OK - getInfo endpoint")
	mainLogger.Printf("Response body: %s", response)
	mainLogger.Printf("=== END CURL REQUEST ===")
}

// handleSaveCID handles the saveCID endpoint
func handleSaveCID(w http.ResponseWriter, r *http.Request) {
	// Get client IP for logging
	clientIP := r.RemoteAddr
	if forwardedFor := r.Header.Get("X-Forwarded-For"); forwardedFor != "" {
		clientIP = forwardedFor
	}

	// Check for required parameters - case-insensitive approach
	cid := getCaseInsensitiveFormValue(r, "cid")
	if cid == "" {
		errMsg := "Error: Missing required parameter 'cid'"
		http.Error(w, errMsg, http.StatusBadRequest)
		errorLogger.Printf("Response: 400 Bad Request - %s", errMsg)
		errorLogger.Printf("Client IP: %s, Endpoint: saveCID", clientIP)
		mainLogger.Printf("Response: 400 Bad Request - %s", errMsg)
		mainLogger.Printf("=== END CURL REQUEST ===")
		return
	}

	// Generate response
	response := fmt.Sprintf("Success: Saved CID=%s", cid)
	fmt.Fprintln(w, response)

	// Create response data for JSON export
	responseData := map[string]interface{}{
		"timestamp":  time.Now().Format(time.RFC3339),
		"client_ip":  clientIP,
		"endpoint":   "saveCID",
		"status":     200,
		"parameters": map[string]string{
			"cid": cid,
		},
		"response": response,
	}

	// Export response data to data log
	if jsonData, err := json.MarshalIndent(responseData, "", "  "); err == nil {
		dataLogger.Printf("RESPONSE DATA: %s", string(jsonData))
	}

	// Log the successful response
	mainLogger.Printf("Response: 200 OK - saveCID endpoint")
	mainLogger.Printf("Response body: %s", response)
	mainLogger.Printf("=== END CURL REQUEST ===")
}
