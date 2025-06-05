#include <cstdlib>
#include <cstring>
#include <string>
#include <string_view>
#include <map>
#include <curl/curl.h>
#include <windows.h>
#include <mutex>
#include <filesystem>

// Configuration settings
struct ConfigSettings {
#ifdef DEFAULT_API_URL
    std::string baseUrl = DEFAULT_API_URL;
#else
    std::string baseUrl = "https://localhost/api/index.php";
#endif

#ifdef DEFAULT_TIMEOUT
    long timeout = DEFAULT_TIMEOUT;
#else
    long timeout = 4;
#endif

#ifdef DEFAULT_CONNECT_TIMEOUT
    long connectTimeout = DEFAULT_CONNECT_TIMEOUT;
#else
    long connectTimeout = 2;
#endif
};

// Function to read configuration from INI file
ConfigSettings ReadConfig() {
    ConfigSettings config;

    // Get the directory where the DLL is located
    char dllPath[MAX_PATH] = {0};
    HMODULE hModule = NULL;
    GetModuleHandleEx(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | 
                      GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                      (LPCSTR)&ReadConfig, &hModule);
    GetModuleFileName(hModule, dllPath, sizeof(dllPath));

    // Get the directory path
    std::filesystem::path dllDir = std::filesystem::path(dllPath).parent_path();
    std::string configPath = (dllDir / "config.ini").string();

    // Check if config file exists, if not, use default values
    if (!std::filesystem::exists(configPath)) {
        return config;
    }

    // Read base URL
    char baseUrl[256] = {0};
    GetPrivateProfileString("api", "base_url", config.baseUrl.c_str(), 
                           baseUrl, sizeof(baseUrl), configPath.c_str());
    config.baseUrl = baseUrl;

    // Read timeout
    config.timeout = GetPrivateProfileInt("api", "timeout", config.timeout, configPath.c_str());

    // Read connect timeout
    config.connectTimeout = GetPrivateProfileInt("api", "connect_timeout", config.connectTimeout, configPath.c_str());

    return config;
}

// Global curl initialization mutex
std::mutex curlInitMutex;
bool curlGlobalInitialized = false;

// DllMain function
BOOL APIENTRY DllMain(HANDLE hModule, DWORD ul_reason_for_call, LPVOID lpReserved)
{
    // Initialize curl globally when DLL is loaded
    if (ul_reason_for_call == DLL_PROCESS_ATTACH) {
        std::lock_guard<std::mutex> lock(curlInitMutex);
        if (!curlGlobalInitialized) {
            curl_global_init(CURL_GLOBAL_DEFAULT);
            curlGlobalInitialized = true;
        }
    } else if (ul_reason_for_call == DLL_PROCESS_DETACH) {
        std::lock_guard<std::mutex> lock(curlInitMutex);
        if (curlGlobalInitialized) {
            curl_global_cleanup();
            curlGlobalInitialized = false;
        }
    }
    return TRUE;
}

// Callback function for curl to write response data
size_t WriteCallback(void* contents, size_t size, size_t nmemb, std::string* userp)
{
    const size_t totalSize = size * nmemb;
    userp->append(static_cast<char*>(contents), totalSize);
    return totalSize;
}

// URL encode a string
std::string UrlEncode(const std::string& value, CURL* curl) {
    char* encoded = curl_easy_escape(curl, value.c_str(), static_cast<int>(value.length()));
    if (encoded) {
        std::string result(encoded);
        curl_free(encoded);
        return result;
    }
    return value; // Return original if encoding fails
}

extern "C"
{
    __declspec(dllexport) long CustomFunctionExample(const char* dataIn, char* dataOut) 
    {
        try {
            // Constants for parsing input/output
            constexpr unsigned int HEADER_SIZE = 2;
            constexpr unsigned int KEY_SIZE = 32;
            constexpr unsigned int VALUE_SIZE = 128;
            constexpr unsigned int PAIR_SIZE = KEY_SIZE + VALUE_SIZE;

            // Ensure dataIn is not null
            if (!dataIn) {
                return 1; // Invalid input
            }

            // Determine number of input parameters
            char numParametersAsString[3] = {dataIn[0], dataIn[1], '\0'};
            const unsigned int numParameters = atoi(numParametersAsString);

            // Validate number of parameters
            if (numParameters > 100) { // Arbitrary limit for safety
                return 1; // Too many parameters
            }

            // Map to store key/value pairs
            std::map<std::string, std::string> parameters;
            bool shouldReturnResponse = false;

            // Read each input parameter
            for (unsigned int i = 0; i < numParameters; i++)
            {
                // Allocate on stack for better performance
                char key[KEY_SIZE + 1] = {0};
                char value[VALUE_SIZE + 1] = {0};

                const unsigned int keyIndex = HEADER_SIZE + i * PAIR_SIZE;
                const unsigned int valueIndex = keyIndex + KEY_SIZE;

                // Copy key and value, ensuring null termination
                memcpy(key, dataIn + keyIndex, KEY_SIZE);
                memcpy(value, dataIn + valueIndex, VALUE_SIZE);

                key[KEY_SIZE] = '\0';
                value[VALUE_SIZE] = '\0';

                // Create string_view first to avoid unnecessary string copies
                // std::string_view automatically stops at the first null character
                std::string_view keyView(key);

                // For value, we can use strlen since we trust null-termination
                size_t valueLength = strlen(value);
                std::string_view valueView(value, valueLength);

                // Convert to strings only when needed
                std::string keyStr(keyView);
                std::string valueStr(valueView);

                // Store in map
                parameters[keyStr] = valueStr;

                // Check if CFResp is set to yes
                if (keyStr == "CFResp" && valueStr == "yes") {
                    shouldReturnResponse = true;
                }
            }

            // Initialize curl
            CURL* curl = curl_easy_init();
            if (!curl) {
                return 1; // Return error code if curl initialization failed
            }

            // Use RAII to ensure curl cleanup
            struct CurlCleanup {
                CURL* curl;
                CurlCleanup(CURL* c) : curl(c) {}
                ~CurlCleanup() { if (curl) curl_easy_cleanup(curl); }
            } curlGuard(curl);

            // Read configuration settings
            ConfigSettings config = ReadConfig();

            // Construct URL for GET request with proper encoding
            std::string url = config.baseUrl + "?";
            bool firstParam = true;

            // Reserve space for URL to avoid reallocations
            url.reserve(256);

            for (const auto& [key, value] : parameters) {
                // Skip CFResp parameter in URL
                if (key == "CFResp") {
                    continue;
                }

                if (!firstParam) {
                    url += "&";
                }

                // URL encode both key and value
                url += key + "=" + UrlEncode(value, curl);
                firstParam = false;
            }

            // Initialize response string with reasonable capacity
            std::string responseData;
            responseData.reserve(1024);

            // Set URL
            curl_easy_setopt(curl, CURLOPT_URL, url.c_str());

            // Set timeout from configuration
            curl_easy_setopt(curl, CURLOPT_TIMEOUT, config.timeout);

            // Set connection timeout from configuration
            curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, config.connectTimeout);

            // Follow redirects
            curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
            curl_easy_setopt(curl, CURLOPT_MAXREDIRS, 3L);

            // Enable TCP keepalive
            curl_easy_setopt(curl, CURLOPT_TCP_KEEPALIVE, 1L);

            // Use HTTP/1.1
            curl_easy_setopt(curl, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1);

            // Set write callback function
            curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteCallback);
            curl_easy_setopt(curl, CURLOPT_WRITEDATA, &responseData);

            // Perform the request
            CURLcode res = curl_easy_perform(curl);

            // Check for errors
            if (res != CURLE_OK) {
                return 1; // Return error code
            }

            // Get HTTP response code
            long httpCode = 0;
            curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);

            // Check if HTTP response is successful (200-299)
            if (httpCode < 200 || httpCode >= 300) {
                return 1; // Return error code
            }

            // If CFResp=yes was in the input, return the response
            if (shouldReturnResponse && dataOut) {
                // Set number of output parameters to 1
                dataOut[0] = '0';
                dataOut[1] = '1';

                // Prepare output key/value
                char outputKey[KEY_SIZE] = {0};
                char outputValue[VALUE_SIZE] = {0};

                // Set key to "CFResp"
                strncpy(outputKey, "CFResp", KEY_SIZE - 1);

                // Copy response data to output value (truncate if too long)
                strncpy(outputValue, responseData.c_str(), VALUE_SIZE - 1);

                // Write to output buffer
                memcpy(dataOut + HEADER_SIZE, outputKey, KEY_SIZE);
                memcpy(dataOut + HEADER_SIZE + KEY_SIZE, outputValue, VALUE_SIZE);
            }

            return 0; // Success
        }
        catch (...) {
            // Catch any unexpected exceptions to ensure DLL doesn't crash
            return 1;
        }
    }
}
