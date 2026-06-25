#----------------------------------------------------------------
# Generated CMake target import file for configuration "Release".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "realsense2::rsutils" for configuration "Release"
set_property(TARGET realsense2::rsutils APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(realsense2::rsutils PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_RELEASE "CXX"
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/lib/rsutils.lib"
  )

list(APPEND _cmake_import_check_targets realsense2::rsutils )
list(APPEND _cmake_import_check_files_for_realsense2::rsutils "${_IMPORT_PREFIX}/lib/rsutils.lib" )

# Import target "realsense2::realsense-file" for configuration "Release"
set_property(TARGET realsense2::realsense-file APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(realsense2::realsense-file PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_RELEASE "C;CXX"
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/lib/realsense-file.lib"
  )

list(APPEND _cmake_import_check_targets realsense2::realsense-file )
list(APPEND _cmake_import_check_files_for_realsense2::realsense-file "${_IMPORT_PREFIX}/lib/realsense-file.lib" )

# Import target "realsense2::rs_lz4" for configuration "Release"
set_property(TARGET realsense2::rs_lz4 APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(realsense2::rs_lz4 PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_RELEASE "C"
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/lib/rs_lz4.lib"
  )

list(APPEND _cmake_import_check_targets realsense2::rs_lz4 )
list(APPEND _cmake_import_check_files_for_realsense2::rs_lz4 "${_IMPORT_PREFIX}/lib/rs_lz4.lib" )

# Import target "realsense2::realsense2" for configuration "Release"
set_property(TARGET realsense2::realsense2 APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(realsense2::realsense2 PROPERTIES
  IMPORTED_IMPLIB_RELEASE "${_IMPORT_PREFIX}/lib/realsense2.lib"
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/bin/realsense2.dll"
  )

list(APPEND _cmake_import_check_targets realsense2::realsense2 )
list(APPEND _cmake_import_check_files_for_realsense2::realsense2 "${_IMPORT_PREFIX}/lib/realsense2.lib" "${_IMPORT_PREFIX}/bin/realsense2.dll" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
