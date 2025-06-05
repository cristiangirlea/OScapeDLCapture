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

// Helper function to make an HTTP request
std::string makeHttpRequest(const std::string& host, int port, const std::string& path, 
                           const std::map<std::string, std::string>& parameters) {
#ifdef _WIN32
    // Initialize Winsock
    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
        std::cerr << "Failed to initialize Winsock" << std::endl;
        return "";
    }
#endif

    // Create socket
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        std::cerr << "Failed to create socket" << std::endl;
#ifdef _WIN32
        WSACleanup();
#endif
        return "";
    }

    // Resolve host
    struct hostent* server = gethostbyname(host.c_str());
    if (server == nullptr) {
        std::cerr << "Failed to resolve host: " << host << std::endl;
#ifdef _WIN32
        closesocket(sock);
        WSACleanup();
#else
        close(sock);
#endif
        return "";
    }

    // Set up server address
    struct sockaddr_in serverAddr;
    std::memset(&serverAddr, 0, sizeof(serverAddr));
    serverAddr.sin_family = AF_INET;
    std::memcpy(&serverAddr.sin_addr.s_addr, server->h_addr, server->h_length);
    serverAddr.sin_port = htons(port);

    // Connect to server
    if (connect(sock, (struct sockaddr*)&serverAddr, sizeof(serverAddr)) < 0) {
        std::cerr << "Failed to connect to server" << std::endl;
#ifdef _WIN32
        closesocket(sock);
        WSACleanup();
#else
        close(sock);
#endif
        return "";
    }

    // Construct query string
    std::string queryString;
    bool first = true;
    for (const auto& param : parameters) {
        if (!first) {
            queryString += "&";
        }
        queryString += param.first + "=" + param.second;
        first = false;
    }

    // Construct HTTP request
    std::string request = "GET " + path;
    if (!queryString.empty()) {
        request += "?" + queryString;
    }
    request += " HTTP/1.1\r\n";
    request += "Host: " + host + "\r\n";
    request += "Connection: close\r\n";
    request += "\r\n";

    // Send request
    if (send(sock, request.c_str(), request.length(), 0) < 0) {
        std::cerr << "Failed to send request" << std::endl;
#ifdef _WIN32
        closesocket(sock);
        WSACleanup();
#else
        close(sock);
#endif
        return "";
    }

    // Receive response
    std::string response;
    char buffer[4096];
    int bytesRead;
    while ((bytesRead = recv(sock, buffer, sizeof(buffer) - 1, 0)) > 0) {
        buffer[bytesRead] = '\0';
        response += buffer;
    }

    // Clean up
#ifdef _WIN32
    closesocket(sock);
    WSACleanup();
#else
    close(sock);
#endif

    return response;
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
        std::cout << "\n=== Testing Server: " << serverHost << ":" << serverPort << " ===" << std::endl;

        // Check if server is running
        std::cout << "Checking if server is running..." << std::endl;
        std::string response = makeHttpRequest(serverHost, serverPort, "/", {});
        if (response.empty()) {
            std::cerr << "Failed to connect to server. Make sure the server is running." << std::endl;
            return 1;
        }

        std::cout << "Server is running" << std::endl;

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

            // Make HTTP request
            std::cout << "Making HTTP request..." << std::endl;
            std::string response = makeHttpRequest(serverHost, serverPort, "/api/index.php", serverParams);

            // Extract response body
            std::string responseBody = extractResponseBody(response);

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
    }

    // Print overall summary
    if (testDll && testServer) {
        std::cout << "\n=== Overall Test Summary ===" << std::endl;
        std::cout << "Completed testing of both DLL and server" << std::endl;
    }

    return 0;
}
