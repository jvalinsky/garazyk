cmake_minimum_required(VERSION 3.28)
project(tutorial-4-auth C)

set(CMAKE_C_STANDARD 11)

# Find required libraries
find_library(FOUNDATION_LIB Foundation REQUIRED)
find_library(SQLITE3_LIB sqlite3 REQUIRED)

# Source files
set(SOURCES
    src/main.m
    src/JWTVerifier.m
    src/DPoPHandler.m
    src/OAuth2Handler.m
)

# Create executable
add_executable(tutorial-4-auth ${SOURCES})

# Link libraries
target_link_libraries(tutorial-4-auth
    ${FOUNDATION_LIB}
    ${SQLITE3_LIB}
    objc
)

# Enable ARC
target_compile_options(tutorial-4-auth PRIVATE -fobjc-arc)

# Platform-specific settings
if(APPLE)
    find_library(SECURITY_LIB Security REQUIRED)
    find_library(COREFOUNDATION_LIB CoreFoundation REQUIRED)
    target_link_libraries(tutorial-4-auth
        ${SECURITY_LIB}
        ${COREFOUNDATION_LIB}
    )
endif()

