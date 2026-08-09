if(NOT DEFINED SOURCE_LIBRARY_ASSETS OR NOT DEFINED SOURCE_PACK_ASSETS OR
   NOT DEFINED SOURCE_ROOT_ASSETS OR NOT DEFINED BUILT_ASSETS)
  message(FATAL_ERROR
    "SOURCE_LIBRARY_ASSETS, SOURCE_PACK_ASSETS, SOURCE_ROOT_ASSETS, and BUILT_ASSETS are required")
endif()

foreach(source_dir IN ITEMS "${SOURCE_LIBRARY_ASSETS}" "${SOURCE_PACK_ASSETS}" "${SOURCE_ROOT_ASSETS}")
  if(NOT IS_DIRECTORY "${source_dir}")
    message(FATAL_ERROR "Admin UI source assets do not exist: ${source_dir}")
  endif()
endforeach()
if(NOT IS_DIRECTORY "${BUILT_ASSETS}")
  message(FATAL_ERROR "Admin UI built assets do not exist: ${BUILT_ASSETS}")
endif()

# The build output intentionally flattens the library and pack asset roots so
# existing /css, /js, and template paths remain stable. Build the expected
# inventory using the same overlay order as the CMake asset function.
set(SOURCE_FILES)
file(GLOB_RECURSE LIBRARY_FILES LIST_DIRECTORIES false RELATIVE
  "${SOURCE_LIBRARY_ASSETS}" "${SOURCE_LIBRARY_ASSETS}/*")
list(APPEND SOURCE_FILES ${LIBRARY_FILES})

file(GLOB PACK_DIRS LIST_DIRECTORIES true "${SOURCE_PACK_ASSETS}/*")
foreach(pack_dir IN LISTS PACK_DIRS)
  if(IS_DIRECTORY "${pack_dir}")
    file(GLOB_RECURSE PACK_FILES LIST_DIRECTORIES false RELATIVE
      "${pack_dir}" "${pack_dir}/*")
    list(APPEND SOURCE_FILES ${PACK_FILES})
  endif()
endforeach()

file(GLOB ROOT_FILES LIST_DIRECTORIES false RELATIVE
  "${SOURCE_ROOT_ASSETS}" "${SOURCE_ROOT_ASSETS}/*.md")
list(APPEND SOURCE_FILES ${ROOT_FILES})

set(UNIQUE_SOURCE_FILES ${SOURCE_FILES})
list(REMOVE_DUPLICATES UNIQUE_SOURCE_FILES)
list(LENGTH SOURCE_FILES SOURCE_FILE_COUNT)
list(LENGTH UNIQUE_SOURCE_FILES UNIQUE_SOURCE_FILE_COUNT)
if(NOT SOURCE_FILE_COUNT EQUAL UNIQUE_SOURCE_FILE_COUNT)
  message(FATAL_ERROR "Admin UI library and pack assets contain colliding output paths")
endif()

file(GLOB_RECURSE BUILT_FILES LIST_DIRECTORIES false RELATIVE "${BUILT_ASSETS}" "${BUILT_ASSETS}/*")
list(SORT SOURCE_FILES)
list(SORT BUILT_FILES)

if(NOT SOURCE_FILES STREQUAL BUILT_FILES)
  message(FATAL_ERROR "Admin UI built asset inventory differs from source assets")
endif()

foreach(RELATIVE_PATH IN LISTS LIBRARY_FILES)
  file(SHA256 "${SOURCE_LIBRARY_ASSETS}/${RELATIVE_PATH}" SOURCE_HASH)
  file(SHA256 "${BUILT_ASSETS}/${RELATIVE_PATH}" BUILT_HASH)
  if(NOT SOURCE_HASH STREQUAL BUILT_HASH)
    message(FATAL_ERROR "Admin UI asset differs: ${RELATIVE_PATH}")
  endif()
endforeach()

foreach(pack_dir IN LISTS PACK_DIRS)
  if(IS_DIRECTORY "${pack_dir}")
    file(GLOB_RECURSE PACK_FILES LIST_DIRECTORIES false RELATIVE
      "${pack_dir}" "${pack_dir}/*")
    foreach(RELATIVE_PATH IN LISTS PACK_FILES)
      file(SHA256 "${pack_dir}/${RELATIVE_PATH}" SOURCE_HASH)
      file(SHA256 "${BUILT_ASSETS}/${RELATIVE_PATH}" BUILT_HASH)
      if(NOT SOURCE_HASH STREQUAL BUILT_HASH)
        message(FATAL_ERROR "Admin UI asset differs: ${RELATIVE_PATH}")
      endif()
    endforeach()
  endif()
endforeach()

foreach(RELATIVE_PATH IN LISTS ROOT_FILES)
  file(SHA256 "${SOURCE_ROOT_ASSETS}/${RELATIVE_PATH}" SOURCE_HASH)
  file(SHA256 "${BUILT_ASSETS}/${RELATIVE_PATH}" BUILT_HASH)
  if(NOT SOURCE_HASH STREQUAL BUILT_HASH)
    message(FATAL_ERROR "Admin UI asset differs: ${RELATIVE_PATH}")
  endif()
endforeach()
