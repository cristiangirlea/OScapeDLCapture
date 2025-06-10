#include <iostream>
#include <string>
#include <vector>
#include <map>
#include <cstring>
#include <windows.h>

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

int main(int argc, char* argv[]) {
    // Default settings
    std::string dllPath = "dist\\CustomDLLStatic.dll";
    bool verbose = false;

    // Parse command line arguments
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--dll" && i + 1 < argc) {
            dllPath = argv[++i];
        } else if (arg == "--verbose" || arg == "-v") {
            verbose = true;
        }
    }

    std::cout << "=== Testing Static DLL: " << dllPath << " ===" << std::endl;

    // Load DLL
    HMODULE dllHandle = LoadLibrary(dllPath.c_str());
    if (!dllHandle) {
        std::cerr << "Failed to load DLL: " << dllPath << std::endl;
        std::cerr << "Error code: " << GetLastError() << std::endl;
        return 1;
    }

    // Get function pointer
    CustomFunctionType customFunction = (CustomFunctionType)GetProcAddress(dllHandle, "ProcessContactCenterRequest");
    if (!customFunction) {
        std::cerr << "Failed to get function pointer from DLL" << std::endl;
        FreeLibrary(dllHandle);
        return 1;
    }

    // Get error message function pointer
    typedef const char* (*GetLastErrorMessageType)();
    GetLastErrorMessageType getLastErrorMessage = (GetLastErrorMessageType)GetProcAddress(dllHandle, "GetLastErrorMessage");
    if (!getLastErrorMessage) {
        std::cerr << "Warning: Failed to get GetLastErrorMessage function pointer from DLL" << std::endl;
    }

    std::cout << "DLL loaded successfully" << std::endl;

    // Define test cases
    std::vector<std::map<std::string, std::string>> testCases = {
        {
            {"Endpoint", "procesareDate_1"},
            {"CFResp", "yes"},
            {"Tel", "0744516456"},
            {"CIF", "1234KTE"},
            {"CID", "193691036401673"}
        },
        {
            {"Endpoint", "getinfo"},
            {"CFResp", "yes"},
            {"ID", "12345"}
        },
        {
            {"Endpoint", "procesareDate_1"},
            {"CFResp", "false"},
            {"Tel", "0744516456"},
            {"CIF", "1234KTE"},
            {"CID", "193691036401673"}
        },
        {
            {"Endpoint", "procesareDate_1"},
            {"CFResp", "0"},
            {"Tel", "0744516456"},
            {"CIF", "1234KTE"},
            {"CID", "193691036401673"}
        },
        {
            {"Endpoint", "procesareDate_1"},
            {"CFResp", "1"},
            {"Tel", "0744516456"},
            {"CIF", "1234KTE"},
            {"CID", "193691036401673"}
        },
    };

    // Run test cases
    int passedTests = 0;
    for (size_t i = 0; i < testCases.size(); i++) {
        const auto& testCase = testCases[i];
        std::cout << "\nRunning test case " << (i + 1) << std::endl;

        // Create input buffer
        std::vector<char> inputBuffer = createInputBuffer(testCase);

        // Create output buffer (initialized to zeros)
        std::vector<char> outputBuffer(2 + 32 + 128, 0);  // Header + Key + Value

        // Print input buffer if verbose
        if (verbose) {
            printBuffer(inputBuffer.data(), inputBuffer.size(), "Input Buffer");
        }

        // Call DLL function
        std::cout << "Calling DLL function..." << std::endl;
        long result = customFunction(inputBuffer.data(), outputBuffer.data());

        // Print result
        std::cout << "Function returned: " << result << " (0 = success, non-zero = failure)" << std::endl;

        // Print error message if available and function failed
        if (result != 0 && getLastErrorMessage) {
            std::cout << "Error message: " << getLastErrorMessage() << std::endl;
        }

        // Print output buffer if CFResp=yes or CFResp=1 was in the input
        bool hasCFResp = false;
        for (const auto& param : testCase) {
            if (param.first == "CFResp" && (param.second == "yes" || param.second == "1")) {
                hasCFResp = true;
                break;
            }
        }

        if (hasCFResp) {
            printBuffer(outputBuffer.data(), outputBuffer.size(), "Output Buffer");
        } else if (verbose) {
            std::cout << "No output expected (CFResp=yes not in input)" << std::endl;
        }

        // Verify result
        if (result == 0) {
            std::cout << "Test PASSED: Function executed successfully" << std::endl;
            passedTests++;
        } else {
            std::cout << "Test FAILED: Function returned error code " << result << std::endl;
        }
    }

    // Print summary
    std::cout << "\nTest Summary: " << passedTests << " of " << testCases.size() << " tests passed" << std::endl;

    // Unload DLL
    FreeLibrary(dllHandle);

    return (passedTests == testCases.size()) ? 0 : 1;
}
