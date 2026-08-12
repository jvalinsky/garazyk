# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# M6.2–M6.4: install curated public headers, export Garazyk:: targets, and
# support relocated package consumers.

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

set(GARAZYK_EXPORT_MODULES
  ATProtoCore
  ATProtoStorage
  ATProtoTransport
  ATProtoServices
  ATProtoXRPC
  ATProtoSync
  ATProtoPLC
  ATProtoRuntime
  ATProtoMediaCore
  ATProtoVideoService
  ATProtoAdminUI
)

set(GARAZYK_UMBRELLA_HEADERS
  "Garazyk/Frameworks/ATProtoCore/ATProtoCore.h"
  "Garazyk/Frameworks/ATProtoStorage/ATProtoStorage.h"
  "Garazyk/Frameworks/ATProtoTransport/ATProtoTransport.h"
  "Garazyk/Frameworks/ATProtoServices/ATProtoServices.h"
  "Garazyk/Frameworks/ATProtoXRPC/ATProtoXRPC.h"
  "Garazyk/Frameworks/ATProtoSync/ATProtoSync.h"
  "Garazyk/Frameworks/ATProtoPLC/ATProtoPLC.h"
  "Garazyk/Frameworks/ATProtoRuntime/ATProtoRuntime.h"
  "Garazyk/Frameworks/ATProtoMediaCore/ATProtoMediaCore.h"
  "Garazyk/Frameworks/ATProtoVideoService/ATProtoVideoService.h"
)

set(_GZ_ALL_PUBLIC_HEADERS "")
foreach(_gz_umbrella IN LISTS GARAZYK_UMBRELLA_HEADERS)
  execute_process(
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/scripts/cmake/collect_public_headers.py"
            "${CMAKE_SOURCE_DIR}" "${_gz_umbrella}" --cmake-list
    OUTPUT_VARIABLE _gz_headers
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE _gz_collect_result
  )
  if(NOT _gz_collect_result EQUAL 0)
    message(FATAL_ERROR "Failed to collect public headers from ${_gz_umbrella}")
  endif()
  list(APPEND _GZ_ALL_PUBLIC_HEADERS ${_gz_headers})
endforeach()
list(REMOVE_DUPLICATES _GZ_ALL_PUBLIC_HEADERS)

foreach(_gz_header IN LISTS _GZ_ALL_PUBLIC_HEADERS)
  if(_gz_header MATCHES "^Garazyk/Sources/")
    string(REGEX REPLACE "^Garazyk/Sources/" "" _gz_install_subpath "${_gz_header}")
    get_filename_component(_gz_install_dir "${_gz_install_subpath}" DIRECTORY)
    install(
      FILES "${CMAKE_SOURCE_DIR}/${_gz_header}"
      DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/garazyk/Sources/${_gz_install_dir}"
    )
  elseif(_gz_header MATCHES "^Garazyk/Frameworks/")
    string(REGEX REPLACE "^Garazyk/Frameworks/" "" _gz_install_subpath "${_gz_header}")
    get_filename_component(_gz_install_dir "${_gz_install_subpath}" DIRECTORY)
    install(
      FILES "${CMAKE_SOURCE_DIR}/${_gz_header}"
      DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/garazyk/Frameworks/${_gz_install_dir}"
    )
  else()
    message(FATAL_ERROR "Unexpected public header path: ${_gz_header}")
  endif()
endforeach()

# secp256k1 is vendored and linked PUBLICly from ATProtoCore. Bundle it in the
# install tree rather than leaving a dangling target reference (WS08 M6.1 #4).
install(
  TARGETS secp256k1
  EXPORT GarazykTargets
  ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}"
  PUBLIC_HEADER DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/secp256k1"
)
install(
  DIRECTORY "${CMAKE_SOURCE_DIR}/secp256k1/include/"
  DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}"
  FILES_MATCHING PATTERN "*.h"
)

install(
  TARGETS ${GARAZYK_EXPORT_MODULES}
  EXPORT GarazykTargets
  ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}"
  INCLUDES DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}"
)

install(
  EXPORT GarazykTargets
  FILE GarazykTargets.cmake
  NAMESPACE Garazyk::
  DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/Garazyk"
)

write_basic_package_version_file(
  "${CMAKE_CURRENT_BINARY_DIR}/GarazykConfigVersion.cmake"
  VERSION "${PROJECT_VERSION}"
  COMPATIBILITY SameMajorVersion
)

set(GARAZYK_INSTALL_INCLUDEDIR "${CMAKE_INSTALL_INCLUDEDIR}")
set(GARAZYK_WITH_OPENSSL OFF)
if(OpenSSL_FOUND)
  set(GARAZYK_WITH_OPENSSL ON)
endif()
configure_package_config_file(
  "${CMAKE_SOURCE_DIR}/cmake/GarazykConfig.cmake.in"
  "${CMAKE_CURRENT_BINARY_DIR}/GarazykConfig.cmake"
  INSTALL_DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/Garazyk"
  PATH_VARS GARAZYK_INSTALL_INCLUDEDIR
)

install(
  FILES
    "${CMAKE_CURRENT_BINARY_DIR}/GarazykConfig.cmake"
    "${CMAKE_CURRENT_BINARY_DIR}/GarazykConfigVersion.cmake"
  DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/Garazyk"
)

install(
  FILES "${CMAKE_SOURCE_DIR}/cmake/GarazykPackageREADME.md"
  DESTINATION "${CMAKE_INSTALL_DATAROOTDIR}/doc/Garazyk"
  RENAME README.md
)
