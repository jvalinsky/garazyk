cmake_minimum_required(VERSION 3.21)
project(GarazykCoreConsumer LANGUAGES OBJC)

find_package(Garazyk 0.1 REQUIRED)

add_executable(core_consumer main.m)
target_link_libraries(core_consumer PRIVATE Garazyk::ATProtoCore)

if(APPLE)
  target_compile_options(core_consumer PRIVATE -fobjc-arc)
  target_link_options(core_consumer PRIVATE -ObjC)
else()
  target_compile_options(core_consumer PRIVATE -fobjc-arc -fblocks -fobjc-runtime=gnustep-2.2)
endif()
