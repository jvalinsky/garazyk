cmake_minimum_required(VERSION 3.21)
project(GarazykFullGraphConsumer LANGUAGES OBJC)

find_package(Garazyk 0.1 REQUIRED)

add_executable(full_graph_consumer main.m)
target_link_libraries(full_graph_consumer PRIVATE Garazyk::ATProtoRuntime)

if(APPLE)
  target_compile_options(full_graph_consumer PRIVATE -fobjc-arc)
  target_link_options(full_graph_consumer PRIVATE -ObjC)
  find_library(GARAZYK_CoreMedia CoreMedia REQUIRED)
  find_library(GARAZYK_AVFoundation AVFoundation REQUIRED)
  find_library(GARAZYK_ImageIO ImageIO REQUIRED)
  find_library(GARAZYK_CoreImage CoreImage REQUIRED)
  find_library(GARAZYK_CoreServices CoreServices REQUIRED)
  target_link_libraries(full_graph_consumer PRIVATE
    ${GARAZYK_CoreMedia}
    ${GARAZYK_AVFoundation}
    ${GARAZYK_ImageIO}
    ${GARAZYK_CoreImage}
    ${GARAZYK_CoreServices})
else()
  target_compile_options(full_graph_consumer PRIVATE -fobjc-arc -fblocks -fobjc-runtime=gnustep-2.2)
endif()
