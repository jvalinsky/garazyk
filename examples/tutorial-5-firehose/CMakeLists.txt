cmake_minimum_required(VERSION 3.28)
project(tutorial-5-firehose)

set(CMAKE_C_STANDARD 11)
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fobjc-arc")

# Find Foundation framework
find_library(FOUNDATION_LIBRARY Foundation REQUIRED)

# Add executable
add_executable(tutorial-5-firehose
    src/main.m
    src/WebSocketConnection.m
    src/EventFormatter.m
    src/SubscribeReposHandler.m
)

# Link libraries
target_link_libraries(tutorial-5-firehose
    ${FOUNDATION_LIBRARY}
)

# Set output directory
set_target_properties(tutorial-5-firehose PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)
