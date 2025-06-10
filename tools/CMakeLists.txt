# Add the test_static_dll executable
add_executable(test_static_dll test_static_dll.cpp)

# Link against required libraries
target_link_libraries(test_static_dll PRIVATE ${CURL_LIBRARIES})

# Set output directory
set_target_properties(test_static_dll PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)