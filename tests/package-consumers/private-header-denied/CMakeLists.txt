cmake_minimum_required(VERSION 3.21)
project(GarazykPrivateHeaderDenied LANGUAGES OBJC)

find_package(Garazyk 0.1 REQUIRED)

add_executable(private_header_probe main.m)
target_link_libraries(private_header_probe PRIVATE Garazyk::ATProtoCore)

if(APPLE)
  target_compile_options(private_header_probe PRIVATE -fobjc-arc)
endif()
