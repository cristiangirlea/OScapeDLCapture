#include <iostream>
#include <string>
#include <vector>
#include <map>
#include <cstring>
#include <iomanip>
#include <sstream>
#include <chrono>
#include <thread>
#include <algorithm>
#include <curl/curl.h>

// Platform-specific includes for DLL loading and networking
#ifdef _WIN32
#include <winsock2.h>  // Include winsock2.h before windows.h to avoid warnings
#include <ws2tcpip.h>
#include <windows.h>
#define DLL_EXTENSION ".dll"
#pragma comment(lib, "ws2_32.lib")
#else
#include <dlfcn.h>
#define DLL_EXTENSION ".so"
#endif

// Additional platform-specific includes for HTTP client
#ifdef _WIN32
// Winsock headers already included above
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <netdb.h>
#endif

// Type definition for the DLL function
typedef long (*CustomFunctionType)(const char*, char*);

// Helper function to print a buffer in a readable format
void printBuffer(const char* buffer, size_t size, const std::string& label) {
    std::cout << "=== " << label << " (" << size << " bytes) ===" << std::endl;

    // Print header (first 2 bytes - number of parameters)
    if (size >= 2) {
        std::cout << "Number of parameters: " << buffer[0] << buffer[1] << std::endl;
    }

    // Print key-value pairs
    const size_t HEADER_SIZE = 2;
    const size_t KEY_SIZE = 32;
    const size_t VALUE_SIZE = 128;
    const size_t PAIR_SIZE = KEY_SIZE + VALUE_SIZE;

    if (size >= 2) {
        int numPairs = std::stoi(std::string(buffer, 2));
        std::cout << "Parsed number of parameters: " << numPairs << std::endl;

        for (int i = 0; i < numPairs && HEADER_SIZE + i * PAIR_SIZE + PAIR_SIZE <= size; i++) {
            // Extract key and value
            std::string key(buffer + HEADER_SIZE + i * PAIR_SIZE, KEY_SIZE);
            std::string value(buffer + HEADER_SIZE + i * PAIR_SIZE + KEY_SIZE, VALUE_SIZE);

            // Trim null characters
            key = key.c_str();  // This will stop at the first null character
            value = value.c_str();  // This will stop at the first null character

            std::cout << "Parameter " << (i + 1) << ": " << key << " = " << value << std::endl;
        }
    }

    std::cout << "===========================" << std::endl;
}

// Helper function to create input buffer for the DLL function
std::vector<char> createInputBuffer(const std::map<std::string, std::string>& parameters) {
    const size_t HEADER_SIZE = 2;
    const size_t KEY_SIZE = 32;
    const size_t VALUE_SIZE = 128;
    const size_t PAIR_SIZE = KEY_SIZE + VALUE_SIZE;

    // Calculate buffer size
    size_t bufferSize = HEADER_SIZE + parameters.size() * PAIR_SIZE;
    std::vector<char> buffer(bufferSize, 0);

    // Set number of parameters
    std::string numParams = std::to_string(parameters.size());
    if (numParams.length() == 1) {
        numParams = "0" + numParams;
    }
    buffer[0] = numParams[0];
    buffer[1] = numParams[1];

    // Set parameters
    int i = 0;
    for (const auto& param : parameters) {
        // Copy key (up to KEY_SIZE characters)
        size_t keyOffset = HEADER_SIZE + i * PAIR_SIZE;
        size_t keyLength = std::min(param.first.length(), KEY_SIZE);
        std::memcpy(buffer.data() + keyOffset, param.first.c_str(), keyLength);

        // Copy value (up to VALUE_SIZE characters)
        size_t valueOffset = keyOffset + KEY_SIZE;
        size_t valueLength = std::min(param.second.length(), VALUE_SIZE);
        std::memcpy(buffer.data() + valueOffset, param.second.c_str(), valueLength);

        i++;
    }

    return buffer;
}

// Callback function for curl to write response data
size_t HttpWriteCallback(void* contents, size_t size, size_t nmemb, std::string* userp) {
    const size_t totalSize = size * nmemb;
    userp->append(static_cast<char*>(contents), totalSize);
    return totalSize;
}

// Structure to hold SSL information
struct SSLInfo {
    bool isSSL;
    bool verifyPeer;
    bool verifyHost;
    std::string certInfo;
    std::string sslVersion;
};

// Helper function to make an HTTP/HTTPS request using curl
std::string makeHttpRequest(const std::string& host, int port, const std::string& path, 
                           const std::map<std::string, std::string>& parameters,
                           bool useSSL = false, bool verifySSL = true, 
                           const std::string& certFile = "", SSLInfo* sslInfo = nullptr) {
    // Initialize curl
    CURL* curl = curl_easy_init();
    if (!curl) {
        std::cerr << "Failed to initialize curl" << std::endl;
        return "";
    }

    // Construct URL
    std::string protocol = useSSL ? "https" : "http";
    std::string url = protocol + "://" + host + ":" + std::to_string(port) + path;

    // Construct query string
    std::string queryString;
    bool first = true;
    for (const auto& param : parameters) {
        if (!first) {
            queryString += "&";
        }

        // URL encode key and value
        char* encodedKey = curl_easy_escape(curl, param.first.c_str(), static_cast<int>(param.first.length()));
        char* encodedValue = curl_easy_escape(curl, param.second.c_str(), static_cast<int>(param.second.length()));

        if (encodedKey && encodedValue) {
            queryString += std::string(encodedKey) + "=" + std::string(encodedValue);
        } else {
            queryString += param.first + "=" + param.second;
        }

        if (encodedKey) curl_free(encodedKey);
        if (encodedValue) curl_free(encodedValue);

        first = false;
    }

    // Append query string to URL
    if (!queryString.empty()) {
        url += "?" + queryString;
    }

    // Set URL
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());

    // Set SSL options if using HTTPS
    if (useSSL) {
        // Configure SSL verification
        if (!verifySSL) {
            // Disable SSL certificate verification
            curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
            curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);
        } else if (!certFile.empty()) {
            // Use custom certificate file
            curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
            curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
            curl_easy_setopt(curl, CURLOPT_CAINFO, certFile.c_str());
        }
    }

    // Set up response buffer
    std::string responseData;
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, HttpWriteCallback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &responseData);

    // Set timeout
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30L);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 10L);

    // Perform the request
    CURLcode res = curl_easy_perform(curl);

    // Capture SSL information if requested
    if (sslInfo != nullptr) {
        // Check if SSL was used
        long usedSSL = 0;
        curl_easy_getinfo(curl, CURLINFO_USED_SSL, &usedSSL);
        sslInfo->isSSL = (usedSSL != 0);

        // Get SSL verification settings
        long verifyPeer = 0;
        curl_easy_getopt(curl, CURLOPT_SSL_VERIFYPEER, &verifyPeer);
        sslInfo->verifyPeer = (verifyPeer != 0);

        long verifyHost = 0;
        curl_easy_getopt(curl, CURLOPT_SSL_VERIFYHOST, &verifyHost);
        sslInfo->verifyHost = (verifyHost > 0);

        // Get SSL version
        char* sslVersion = nullptr;
        curl_easy_getinfo(curl, CURLINFO_SSL_VERIFYRESULT, &sslVersion);
        if (sslVersion) {
            sslInfo->sslVersion = sslVersion;
        }

        // Get certificate info
        char* certInfo = nullptr;
        curl_easy_getinfo(curl, CURLINFO_CERTINFO, &certInfo);
        if (certInfo) {
            sslInfo->certInfo = certInfo;
        }
    }

    // Check for errors
    if (res != CURLE_OK) {
        std::cerr << "Curl request failed: " << curl_easy_strerror(res) << std::endl;
        curl_easy_cleanup(curl);
        return "";
    }

    // Clean up
    curl_easy_cleanup(curl);

    return responseData;
}

// Helper function to extract response body from HTTP response
std::string extractResponseBody(const std::string& response) {
    size_t pos = response.find("\r\n\r\n");
    if (pos != std::string::npos) {
        return response.substr(pos + 4);
    }
    return "";
}

// Test case structure
struct TestCase {
    std::string name;
    std::map<std::string, std::string> parameters;
    bool expectSuccess;
    std::string expectedResponse;
};

int main(int argc, char* argv[]) {
    // Default settings
    std::string dllPath = "dist/runtime/CustomDLL" DLL_EXTENSION;
    std::string serverHost = "localhost";
#ifdef DEFAULT_SERVER_PORT
    int serverPort = DEFAULT_SERVER_PORT;
#else
    int serverPort = 8080;
#endif
    bool testDll = true;
    bool testServer = true;
    bool useHttps = false;
    bool verifySSL = true;
    std::string certFile = "";

    // Initialize curl globally
    curl_global_init(CURL_GLOBAL_DEFAULT);

    // Parse command line arguments
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--dll" && i + 1 < argc) {
            dllPath = argv[++i];
        } else if (arg == "--server-host" && i + 1 < argc) {
            serverHost = argv[++i];
        } else if (arg == "--server-port" && i + 1 < argc) {
            serverPort = std::stoi(argv[++i]);
        } else if (arg == "--test-dll-only") {
            testDll = true;
            testServer = false;
        } else if (arg == "--test-server-only") {
            testDll = false;
            testServer = true;
        } else if (arg == "--use-https") {
            useHttps = true;
        } else if (arg == "--no-verify-ssl") {
            verifySSL = false;
        } else if (arg == "--cert-file" && i + 1 < argc) {
            certFile = argv[++i];
            verifySSL = true;  // If cert file is specified, enable verification
        }
    }

    // Define test cases
    std::vector<TestCase> testCases = {
        {
            "Basic test with CFResp=yes",
            {
                {"Endpoint", "procesareDate_1"},
                {"CFResp", "yes"},
                {"Tel", "0744516456"},
                {"CIF", "1234KTE"},
                {"CID", "193691036401673"}
            },
            true,
            "Success!"
        },
        {
            "Test without CFResp",
            {
                {"Endpoint", "procesareDate_1"},
                {"Tel", "0744516456"},
                {"CIF", "1234KTE"},
                {"CID", "193691036401673"}
            },
            true,
            ""  // No response expected
        },
        {
            "Test with missing parameters",
            {
                {"Endpoint", "procesareDate_1"},
                {"CFResp", "yes"},
                {"Tel", "0744516456"}
                // Missing CIF and CID
            },
            false,
            "Error: Missing required parameters"
        },
        {
            "Test with unknown endpoint",
            {
                {"Endpoint", "unknownEndpoint"},
                {"CFResp", "yes"},
                {"Tel", "0744516456"},
                {"CIF", "1234KTE"},
                {"CID", "193691036401673"}
            },
            false,
            "Error: Unknown endpoint"
        }
    };

    // Test DLL
    if (testDll) {
        std::cout << "=== Testing DLL: " << dllPath << " ===" << std::endl;

        // Load DLL
#ifdef _WIN32
        HMODULE dllHandle = LoadLibrary(dllPath.c_str());
        if (!dllHandle) {
            std::cerr << "Failed to load DLL: " << dllPath << std::endl;
            std::cerr << "Error code: " << GetLastError() << std::endl;
            return 1;
        }

        // Get function pointer
        CustomFunctionType customFunction = (CustomFunctionType)GetProcAddress(dllHandle, "CustomFunctionExample");
        if (!customFunction) {
            std::cerr << "Failed to get function pointer from DLL" << std::endl;
            FreeLibrary(dllHandle);
            return 1;
        }
#else
        void* dllHandle = dlopen(dllPath.c_str(), RTLD_LAZY);
        if (!dllHandle) {
            std::cerr << "Failed to load DLL: " << dllPath << std::endl;
            std::cerr << "Error: " << dlerror() << std::endl;
            return 1;
        }

        // Get function pointer
        CustomFunctionType customFunction = (CustomFunctionType)dlsym(dllHandle, "CustomFunctionExample");
        if (!customFunction) {
            std::cerr << "Failed to get function pointer from DLL" << std::endl;
            dlclose(dllHandle);
            return 1;
        }
#endif

        std::cout << "DLL loaded successfully" << std::endl;

        // Run test cases
        int passedTests = 0;
        for (const auto& testCase : testCases) {
            std::cout << "\nRunning test case: " << testCase.name << std::endl;

            // Create input buffer
            std::vector<char> inputBuffer = createInputBuffer(testCase.parameters);

            // Create output buffer (initialized to zeros)
            std::vector<char> outputBuffer(2 + 32 + 128, 0);  // Header + Key + Value

            // Print input buffer
            printBuffer(inputBuffer.data(), inputBuffer.size(), "Input Buffer");

            // Call DLL function
            std::cout << "Calling DLL function..." << std::endl;
            long result = customFunction(inputBuffer.data(), outputBuffer.data());

            // Print result
            std::cout << "Function returned: " << result << " (0 = success, non-zero = failure)" << std::endl;

            // Print output buffer if CFResp=yes was in the input
            bool hasCFResp = false;
            for (const auto& param : testCase.parameters) {
                if (param.first == "CFResp" && param.second == "yes") {
                    hasCFResp = true;
                    break;
                }
            }

            if (hasCFResp) {
                printBuffer(outputBuffer.data(), outputBuffer.size(), "Output Buffer");
            } else {
                std::cout << "No output expected (CFResp=yes not in input)" << std::endl;
            }

            // Verify result
            bool success = (result == 0) == testCase.expectSuccess;
            if (success) {
                if (hasCFResp && testCase.expectSuccess) {
                    // Extract response from output buffer
                    std::string response;
                    if (outputBuffer[0] == '0' && outputBuffer[1] == '1') {
                        // Extract the value part (skip header and key)
                        response = std::string(outputBuffer.data() + 2 + 32);
                        // Trim at first null character
                        response = response.c_str();
                    }

                    // Check if response contains expected text
                    if (response.find(testCase.expectedResponse) != std::string::npos) {
                        std::cout << "Test PASSED: Response contains expected text" << std::endl;
                        passedTests++;
                    } else {
                        std::cout << "Test FAILED: Response does not contain expected text" << std::endl;
                        std::cout << "Expected to find: " << testCase.expectedResponse << std::endl;
                        std::cout << "Actual response: " << response << std::endl;
                    }
                } else {
                    std::cout << "Test PASSED: Function returned expected result" << std::endl;
                    passedTests++;
                }
            } else {
                std::cout << "Test FAILED: Function returned unexpected result" << std::endl;
                std::cout << "Expected success: " << (testCase.expectSuccess ? "true" : "false") << std::endl;
                std::cout << "Actual result: " << result << std::endl;
            }
        }

        // Print summary
        std::cout << "\nDLL Test Summary: " << passedTests << " of " << testCases.size() << " tests passed" << std::endl;

        // Unload DLL
#ifdef _WIN32
        FreeLibrary(dllHandle);
#else
        dlclose(dllHandle);
#endif
    }

    // Test server
    if (testServer) {
        std::string protocol = useHttps ? "HTTPS" : "HTTP";
        std::cout << "\n=== Testing Server: " << protocol << "://" << serverHost << ":" << serverPort << " ===" << std::endl;
        std::cout << "SSL Verification: " << (verifySSL ? "Enabled" : "Disabled") << std::endl;
        if (!certFile.empty()) {
            std::cout << "Using Certificate File: " << certFile << std::endl;
        }

        // Check if server is running
        std::cout << "Checking if server is running..." << std::endl;
        SSLInfo sslInfo;
        std::string response = makeHttpRequest(serverHost, serverPort, "/", {}, useHttps, verifySSL, certFile, &sslInfo);
        if (response.empty()) {
            std::cerr << "Failed to connect to server. Make sure the server is running." << std::endl;
            curl_global_cleanup();
            return 1;
        }

        std::cout << "Server is running" << std::endl;

        // Report SSL status
        if (useHttps) {
            std::cout << "SSL Status:" << std::endl;
            std::cout << "  - SSL Used: " << (sslInfo.isSSL ? "Yes" : "No") << std::endl;
            std::cout << "  - Peer Verification: " << (sslInfo.verifyPeer ? "Enabled" : "Disabled") << std::endl;
            std::cout << "  - Host Verification: " << (sslInfo.verifyHost ? "Enabled" : "Disabled") << std::endl;
            if (!sslInfo.sslVersion.empty()) {
                std::cout << "  - SSL Version: " << sslInfo.sslVersion << std::endl;
            }
            if (!sslInfo.certInfo.empty()) {
                std::cout << "  - Certificate Info: " << sslInfo.certInfo << std::endl;
            }
        }

        // Run test cases
        int passedTests = 0;
        for (const auto& testCase : testCases) {
            std::cout << "\nRunning test case: " << testCase.name << std::endl;

            // Convert parameters to lowercase for server request
            std::map<std::string, std::string> serverParams;
            for (const auto& param : testCase.parameters) {
                // Convert key to lowercase for server request (server expects lowercase keys)
                std::string key = param.first;
                std::transform(key.begin(), key.end(), key.begin(), ::tolower);
                serverParams[key] = param.second;
            }

            // Make HTTP/HTTPS request
            std::cout << "Making " << protocol << " request..." << std::endl;
            SSLInfo requestSslInfo;
            std::string response = makeHttpRequest(serverHost, serverPort, "/api/index.php", 
                                                 serverParams, useHttps, verifySSL, certFile, 
                                                 &requestSslInfo);

            // For HTTPS requests, report SSL status
            if (useHttps) {
                std::cout << "SSL Status for this request:" << std::endl;
                std::cout << "  - SSL Used: " << (requestSslInfo.isSSL ? "Yes" : "No") << std::endl;
                std::cout << "  - Certificate Verification: " << (requestSslInfo.verifyPeer ? "Enabled" : "Disabled") << std::endl;
            }

            // Extract response body if it's an HTTP response with headers
            std::string responseBody = response;
            if (response.find("HTTP/") == 0) {
                responseBody = extractResponseBody(response);
            }

            // Print response
            std::cout << "Response body:" << std::endl;
            std::cout << responseBody << std::endl;

            // Verify response
            bool success;
            if (testCase.expectSuccess) {
                success = !responseBody.empty() && responseBody.find(testCase.expectedResponse) != std::string::npos;
            } else {
                success = responseBody.find("Error") != std::string::npos;
            }

            if (success) {
                std::cout << "Test PASSED: Server returned expected response" << std::endl;
                passedTests++;
            } else {
                std::cout << "Test FAILED: Server returned unexpected response" << std::endl;
                if (testCase.expectSuccess) {
                    std::cout << "Expected to find: " << testCase.expectedResponse << std::endl;
                } else {
                    std::cout << "Expected to find an error message" << std::endl;
                }
                std::cout << "Actual response: " << responseBody << std::endl;
            }
        }

        // Print summary
        std::cout << "\nServer Test Summary: " << passedTests << " of " << testCases.size() << " tests passed" << std::endl;
        std::cout << "Protocol used: " << protocol << std::endl;
        std::cout << "SSL Verification: " << (verifySSL ? "Enabled" : "Disabled") << std::endl;
    }

    // Print overall summary
    if (testDll && testServer) {
        std::cout << "\n=== Overall Test Summary ===" << std::endl;
        std::cout << "Completed testing of both DLL and server" << std::endl;
    }

    // Clean up curl resources
    curl_global_cleanup();

    return 0;
}
