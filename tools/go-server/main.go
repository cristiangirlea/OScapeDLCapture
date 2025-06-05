package main

import (
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

func main() {
	// Parse command line flags
	port := flag.Int("port", DefaultPort, "Port to listen on")
	logDir := flag.String("logdir", DefaultLogDir, "Directory to store log files")
	flag.Parse()

	// Create log directory if it doesn't exist
	if err := os.MkdirAll(*logDir, 0755); err != nil {
		log.Fatalf("Failed to create log directory: %v", err)
	}

	// Create log file with current date
	logFileName := fmt.Sprintf("curl_requests_%s.log", time.Now().Format("2006-01-02"))
	logFilePath := filepath.Join(*logDir, logFileName)

	logFile, err := os.OpenFile(logFilePath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		log.Fatalf("Failed to open log file: %v", err)
	}
	defer logFile.Close()

	// Set up logging to both stdout and file
	multiWriter := io.MultiWriter(os.Stdout, logFile)
	log.SetOutput(multiWriter)
	log.SetFlags(log.LstdFlags | log.Lmicroseconds)

	log.Printf("Logging curl requests to %s", logFilePath)

	// Register handlers
	http.HandleFunc("/", handleRoot)
	http.HandleFunc("/api/index.php", handleAPI)

	// Start server
	addr := fmt.Sprintf(":%d", *port)
	log.Printf("Starting server on %s", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}

// handleRoot handles requests to the root path
func handleRoot(w http.ResponseWriter, r *http.Request) {
	// Get client IP address
	clientIP := r.RemoteAddr
	if forwardedFor := r.Header.Get("X-Forwarded-For"); forwardedFor != "" {
		clientIP = forwardedFor
	}

	log.Printf("Received request from %s: %s %s", clientIP, r.Method, r.URL.Path)

	// Log request headers
	log.Printf("Request headers:")
	for name, values := range r.Header {
		log.Printf("  %s: %s", name, strings.Join(values, ", "))
	}

	fmt.Fprintf(w, "CustomDLL Test Server\n")
	fmt.Fprintf(w, "Use /api/index.php with appropriate parameters\n")

	log.Printf("Response: 200 OK - Root page served")
}

// handleAPI handles requests to the API endpoint
func handleAPI(w http.ResponseWriter, r *http.Request) {
	// Get client IP address
	clientIP := r.RemoteAddr
	if forwardedFor := r.Header.Get("X-Forwarded-For"); forwardedFor != "" {
		clientIP = forwardedFor
	}

	// Log basic request info
	log.Printf("=== CURL REQUEST FROM DLL ===")
	log.Printf("Received API request from %s: %s %s", clientIP, r.Method, r.URL.String())

	// Log request headers (useful for identifying curl)
	log.Printf("Request headers:")
	for name, values := range r.Header {
		log.Printf("  %s: %s", name, strings.Join(values, ", "))
	}

	// Parse query parameters
	err := r.ParseForm()
	if err != nil {
		errMsg := fmt.Sprintf("Error parsing form data: %v", err)
		http.Error(w, "Error parsing form data", http.StatusBadRequest)
		log.Printf("Response: 400 Bad Request - %s", errMsg)
		log.Printf("=== END CURL REQUEST ===")
		return
	}

	// Log all parameters
	log.Printf("Request parameters:")
	for key, values := range r.Form {
		log.Printf("  %s = %s", key, strings.Join(values, ", "))
	}

	// Check for required parameters
	endpoint := r.FormValue("endpoint")
	if endpoint == "" {
		errMsg := "Error: Missing 'endpoint' parameter"
		http.Error(w, errMsg, http.StatusBadRequest)
		log.Printf("Response: 400 Bad Request - %s", errMsg)
		log.Printf("=== END CURL REQUEST ===")
		return
	}

	// Process based on endpoint
	switch strings.ToLower(endpoint) {
	case "procesaredate_1":
		handleProcessareDate(w, r)
	case "getinfo":
		handleGetInfo(w, r)
	default:
		errMsg := fmt.Sprintf("Error: Unknown endpoint '%s'", endpoint)
		http.Error(w, errMsg, http.StatusBadRequest)
		log.Printf("Response: 400 Bad Request - %s", errMsg)
		log.Printf("=== END CURL REQUEST ===")
	}
}

// handleProcessareDate handles the procesareDate_1 endpoint
func handleProcessareDate(w http.ResponseWriter, r *http.Request) {
	// Check for required parameters
	tel := r.FormValue("tel")
	cif := r.FormValue("cif")
	cid := r.FormValue("cid")

	if tel == "" || cif == "" || cid == "" {
		errMsg := "Error: Missing required parameters (tel, cif, cid)"
		http.Error(w, errMsg, http.StatusBadRequest)
		log.Printf("Response: 400 Bad Request - %s", errMsg)
		return
	}

	// Generate response
	response := fmt.Sprintf("Success: Processed data for Tel=%s, CIF=%s, CID=%s", tel, cif, cid)
	fmt.Fprintln(w, response)

	// Log the successful response
	log.Printf("Response: 200 OK - procesareDate_1 endpoint")
	log.Printf("Response body: %s", response)
	log.Printf("=== END CURL REQUEST ===")
}

// handleGetInfo handles the getInfo endpoint
func handleGetInfo(w http.ResponseWriter, r *http.Request) {
	// Check for required parameters
	id := r.FormValue("id")
	if id == "" {
		errMsg := "Error: Missing required parameter 'id'"
		http.Error(w, errMsg, http.StatusBadRequest)
		log.Printf("Response: 400 Bad Request - %s", errMsg)
		return
	}

	// Generate response
	response := fmt.Sprintf("Info for ID=%s: Customer information retrieved successfully", id)
	fmt.Fprintln(w, response)

	// Log the successful response
	log.Printf("Response: 200 OK - getInfo endpoint")
	log.Printf("Response body: %s", response)
	log.Printf("=== END CURL REQUEST ===")
}
