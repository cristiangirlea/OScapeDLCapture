#include <iostream>
#include <string>
#include <map>
#include <chrono>
#include <ctime>
#include <iomanip>
#include <sstream>

// Define a simple HTTP server using only standard libraries
// This avoids external dependencies and makes it easier to build
#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#pragma comment(lib, "ws2_32.lib")
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <arpa/inet.h>
#endif

class SimpleHttpServer {
private:
    int serverSocket;
    int port;
    bool running;
    std::string logPrefix;

    // Helper function to get current timestamp for logging
    std::string getCurrentTimestamp() {
        auto now = std::chrono::system_clock::now();
        auto time = std::chrono::system_clock::to_time_t(now);
        std::stringstream ss;
        ss << std::put_time(std::localtime(&time), "%Y-%m-%d %H:%M:%S");
        return ss.str();
    }

    // Log a message with timestamp
    void log(const std::string& message) {
        std::cout << "[" << getCurrentTimestamp() << "] " << logPrefix << ": " << message << std::endl;
    }

    // Parse URL-encoded parameters
    std::map<std::string, std::string> parseQueryString(const std::string& query) {
        std::map<std::string, std::string> params;
        size_t start = 0;
        size_t end = query.find('&');

        while (start < query.length()) {
            std::string param;
            if (end != std::string::npos) {
                param = query.substr(start, end - start);
                start = end + 1;
                end = query.find('&', start);
            } else {
                param = query.substr(start);
                start = query.length();
            }

            size_t equalPos = param.find('=');
            if (equalPos != std::string::npos) {
                std::string key = param.substr(0, equalPos);
                std::string value = param.substr(equalPos + 1);
                params[key] = urlDecode(value);
            }
        }
        return params;
    }

    // URL decode a string
    std::string urlDecode(const std::string& encoded) {
        std::string result;
        for (size_t i = 0; i < encoded.length(); ++i) {
            if (encoded[i] == '%' && i + 2 < encoded.length()) {
                int value;
                std::istringstream iss(encoded.substr(i + 1, 2));
                if (iss >> std::hex >> value) {
                    result += static_cast<char>(value);
                    i += 2;
                } else {
                    result += encoded[i];
                }
            } else if (encoded[i] == '+') {
                result += ' ';
            } else {
                result += encoded[i];
            }
        }
        return result;
    }

public:
    SimpleHttpServer(int port) : port(port), running(false), logPrefix("Server") {
#ifdef _WIN32
        // Initialize Winsock
        WSADATA wsaData;
        int result = WSAStartup(MAKEWORD(2, 2), &wsaData);
        if (result != 0) {
            log("WSAStartup failed: " + std::to_string(result));
            exit(1);
        }
#endif
    }

    ~SimpleHttpServer() {
        stop();
#ifdef _WIN32
        WSACleanup();
#endif
    }

    void start() {
        // Create socket
        serverSocket = socket(AF_INET, SOCK_STREAM, 0);
        if (serverSocket < 0) {
            log("Error opening socket");
            exit(1);
        }

        // Set socket options to reuse address
        int opt = 1;
#ifdef _WIN32
        if (setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, (const char*)&opt, sizeof(opt)) < 0) {
#else
        if (setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) < 0) {
#endif
            log("Error setting socket options");
            exit(1);
        }

        // Bind socket to port
        struct sockaddr_in serverAddr;
        serverAddr.sin_family = AF_INET;
        serverAddr.sin_addr.s_addr = INADDR_ANY;
        serverAddr.sin_port = htons(port);

        if (bind(serverSocket, (struct sockaddr*)&serverAddr, sizeof(serverAddr)) < 0) {
            log("Error binding socket to port " + std::to_string(port));
            exit(1);
        }

        // Start listening
        if (listen(serverSocket, 5) < 0) {
            log("Error listening on socket");
            exit(1);
        }

        running = true;
        log("Server started on port " + std::to_string(port));

        // Main server loop
        while (running) {
            struct sockaddr_in clientAddr;
#ifdef _WIN32
            int clientAddrLen = sizeof(clientAddr);
#else
            socklen_t clientAddrLen = sizeof(clientAddr);
#endif
            int clientSocket = accept(serverSocket, (struct sockaddr*)&clientAddr, &clientAddrLen);

            if (clientSocket < 0) {
                log("Error accepting connection");
                continue;
            }

            // Handle client connection
            handleClient(clientSocket, clientAddr);
        }
    }

    void stop() {
        if (running) {
            running = false;
#ifdef _WIN32
            closesocket(serverSocket);
#else
            close(serverSocket);
#endif
            log("Server stopped");
        }
    }

private:
    void handleClient(int clientSocket, const struct sockaddr_in& clientAddr) {
        char buffer[4096] = {0};

        // Receive request
#ifdef _WIN32
        int bytesRead = recv(clientSocket, buffer, sizeof(buffer) - 1, 0);
#else
        ssize_t bytesRead = recv(clientSocket, buffer, sizeof(buffer) - 1, 0);
#endif

        if (bytesRead <= 0) {
            log("Error reading from socket or client disconnected");
#ifdef _WIN32
            closesocket(clientSocket);
#else
            close(clientSocket);
#endif
            return;
        }

        // Parse HTTP request
        std::string request(buffer);
        std::string method, path, httpVersion;
        std::istringstream requestStream(request);
        requestStream >> method >> path >> httpVersion;

        // Log the request
        char clientIP[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &(clientAddr.sin_addr), clientIP, INET_ADDRSTRLEN);
        log("Request from " + std::string(clientIP) + ": " + method + " " + path);

        // Parse query parameters
        std::map<std::string, std::string> params;
        size_t queryPos = path.find('?');
        if (queryPos != std::string::npos) {
            std::string query = path.substr(queryPos + 1);
            path = path.substr(0, queryPos);
            params = parseQueryString(query);
        }

        // Log parameters
        for (const auto& param : params) {
            log("Parameter: " + param.first + " = " + param.second);
        }

        // Generate response based on path and parameters
        std::string response;
        if (path == "/api/index.php") {
            // Check if endpoint parameter exists
            if (params.find("endpoint") != params.end()) {
                std::string endpoint = params["endpoint"];

                // Simulate different endpoint behaviors
                if (endpoint == "procesareDate_1") {
                    // Check for required parameters
                    if (params.find("tel") != params.end() && 
                        params.find("CIF") != params.end() && 
                        params.find("CID") != params.end()) {

                        // Generate a response with the parameters
                        response = "HTTP/1.1 200 OK\r\n";
                        response += "Content-Type: text/plain\r\n";
                        response += "Connection: close\r\n\r\n";
                        response += "Success! Processed request for:\r\n";
                        response += "Tel: " + params["tel"] + "\r\n";
                        response += "CIF: " + params["CIF"] + "\r\n";
                        response += "CID: " + params["CID"] + "\r\n";
                        response += "Timestamp: " + getCurrentTimestamp() + "\r\n";
                    } else {
                        // Missing required parameters
                        response = "HTTP/1.1 400 Bad Request\r\n";
                        response += "Content-Type: text/plain\r\n";
                        response += "Connection: close\r\n\r\n";
                        response += "Error: Missing required parameters (tel, CIF, CID)";
                    }
                } else {
                    // Unknown endpoint
                    response = "HTTP/1.1 404 Not Found\r\n";
                    response += "Content-Type: text/plain\r\n";
                    response += "Connection: close\r\n\r\n";
                    response += "Error: Unknown endpoint '" + endpoint + "'";
                }
            } else {
                // Missing endpoint parameter
                response = "HTTP/1.1 400 Bad Request\r\n";
                response += "Content-Type: text/plain\r\n";
                response += "Connection: close\r\n\r\n";
                response += "Error: Missing 'endpoint' parameter";
            }
        } else {
            // Unknown path
            response = "HTTP/1.1 404 Not Found\r\n";
            response += "Content-Type: text/plain\r\n";
            response += "Connection: close\r\n\r\n";
            response += "Error: Path not found";
        }

        // Send response
#ifdef _WIN32
        send(clientSocket, response.c_str(), response.length(), 0);
        closesocket(clientSocket);
#else
        send(clientSocket, response.c_str(), response.length(), 0);
        close(clientSocket);
#endif
    }
};

int main(int argc, char* argv[]) {
#ifdef DEFAULT_SERVER_PORT
    int port = DEFAULT_SERVER_PORT;
#else
    int port = 8080;
#endif

    // Parse command line arguments
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--port" && i + 1 < argc) {
            port = std::stoi(argv[++i]);
        }
    }

    std::cout << "Starting API simulation server on port " << port << std::endl;
    std::cout << "This server simulates the API endpoint that the CustomDLL communicates with." << std::endl;
    std::cout << "Press Ctrl+C to stop the server." << std::endl;

    // Start the server
    SimpleHttpServer server(port);
    server.start();

    return 0;
}
