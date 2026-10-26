# SPDX-License-Identifier: GPL-2.0-or-later

function(_kzmrecomp_require_private_input input kind output)
  if(NOT IS_ABSOLUTE "${input}")
    message(FATAL_ERROR
      "Generated title bundle inputs must use explicit absolute paths.")
  endif()

  if(kind STREQUAL "DIRECTORY")
    if(NOT IS_DIRECTORY "${input}")
      message(FATAL_ERROR
        "The generated title bundle staging directory is unavailable.")
    endif()
  elseif(NOT EXISTS "${input}" OR IS_DIRECTORY "${input}")
    message(FATAL_ERROR
      "The generated title bundle runtime manifest is unavailable.")
  endif()

  file(REAL_PATH "${input}" _real_input)
  file(REAL_PATH "${PROJECT_SOURCE_DIR}" _source_root)
  cmake_path(NORMAL_PATH _source_root)
  cmake_path(IS_PREFIX _source_root "${_real_input}" NORMALIZE _inside_source)
  if(_inside_source)
    set(_inside_ignored_root FALSE)
    foreach(_relative_root IN ITEMS
        build
        out
        _build
        config/local
        private
        private-data
        local-content
        content-local
        generated
        generated-title
        recompiled
        recomp-output
        src/game/generated
        src/game/recompiled
    )
      file(
        REAL_PATH
        "${PROJECT_SOURCE_DIR}/${_relative_root}"
        _ignored_root
      )
      cmake_path(NORMAL_PATH _ignored_root)
      cmake_path(
        IS_PREFIX
        _ignored_root
        "${_real_input}"
        NORMALIZE
        _inside_this_root
      )
      if(_inside_this_root)
        set(_inside_ignored_root TRUE)
        break()
      endif()
    endforeach()
    if(NOT _inside_ignored_root)
      message(FATAL_ERROR
        "Generated title bundle inputs cannot be tracked source inputs.")
    endif()
  endif()

  set("${output}" "${_real_input}" PARENT_SCOPE)
endfunction()

function(_kzmrecomp_json_get output json)
  string(
    JSON _value
    ERROR_VARIABLE _error
    GET "${json}" ${ARGN}
  )
  if(NOT _error STREQUAL "NOTFOUND")
    message(FATAL_ERROR "Generated title bundle metadata is invalid.")
  endif()
  set("${output}" "${_value}" PARENT_SCOPE)
endfunction()

function(_kzmrecomp_json_length output json)
  string(
    JSON _value
    ERROR_VARIABLE _error
    LENGTH "${json}" ${ARGN}
  )
  if(NOT _error STREQUAL "NOTFOUND")
    message(FATAL_ERROR "Generated title bundle metadata is invalid.")
  endif()
  set("${output}" "${_value}" PARENT_SCOPE)
endfunction()

function(_kzmrecomp_configure_generated_c target)
  set_target_properties("${target}" PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED YES
    C_EXTENSIONS NO
  )
  target_compile_definitions("${target}" PRIVATE
    _CRT_SECURE_NO_WARNINGS
  )
  if(MSVC)
    target_compile_options("${target}" PRIVATE /bigobj)
  endif()
  kzmrecomp_project_warnings("${target}")
endfunction()

set(_generated_bundle_enabled FALSE)
if(KZMRECOMP_GENERATED_SOURCE_DIR)
  set(_generated_bundle_enabled TRUE)
elseif(KZMRECOMP_RUNTIME_MANIFEST)
  message(FATAL_ERROR
    "KZMRECOMP_RUNTIME_MANIFEST requires a generated title bundle.")
endif()

if(NOT _generated_bundle_enabled)
  add_library(kzmrecomp_generated_bundle_adapter STATIC
    generated_bundle_absent.cpp
  )
  target_include_directories(kzmrecomp_generated_bundle_adapter PUBLIC
    "${PROJECT_SOURCE_DIR}/src"
  )
  target_compile_features(kzmrecomp_generated_bundle_adapter
    PUBLIC cxx_std_20)
  target_link_libraries(kzmrecomp_generated_bundle_adapter PRIVATE
    vitarecomp)
  if(BUILD_TESTING)
    target_compile_definitions(kzmrecomp_generated_bundle_adapter PUBLIC
      KZMRECOMP_ENABLE_TEST_SEAMS=1)
  endif()
  kzmrecomp_project_warnings(kzmrecomp_generated_bundle_adapter)

  add_library(kzmrecomp_game_generated_bundle INTERFACE)
  target_link_libraries(kzmrecomp_game_generated_bundle INTERFACE
    kzmrecomp_generated_bundle_adapter
    vitarecomp
  )
  set(KZMRECOMP_GENERATED_BUNDLE_PRESENT FALSE PARENT_SCOPE)
  return()
endif()

if(NOT KZMRECOMP_RUNTIME_MANIFEST)
  message(FATAL_ERROR
    "An explicit runtime manifest is required for a generated title bundle.")
endif()

_kzmrecomp_require_private_input(
  "${KZMRECOMP_GENERATED_SOURCE_DIR}"
  DIRECTORY
  _generated_source_root
)
_kzmrecomp_require_private_input(
  "${KZMRECOMP_RUNTIME_MANIFEST}"
  FILE
  _runtime_manifest
)

set(_provenance
  "${_generated_source_root}/.generated-source-provenance.json")
set(_staging_manifest
  "${_generated_source_root}/.generated-source-manifest.json")
if(NOT EXISTS "${_provenance}" OR IS_DIRECTORY "${_provenance}" OR
   NOT EXISTS "${_staging_manifest}" OR IS_DIRECTORY "${_staging_manifest}")
  message(FATAL_ERROR
    "The generated title bundle is missing required staged metadata.")
endif()

find_program(
  _provenance_powershell
  NAMES pwsh powershell
)
if(NOT _provenance_powershell)
  message(FATAL_ERROR
    "PowerShell is required to validate a generated title bundle.")
endif()

execute_process(
  COMMAND
    "${_provenance_powershell}"
    -NoLogo
    -NoProfile
    -ExecutionPolicy Bypass
    -File
      "${PROJECT_SOURCE_DIR}/tools/generated/Test-GeneratedSourceProvenance.ps1"
    -ProvenanceFile "${_provenance}"
    -SourceRoot "${_generated_source_root}"
    -RuntimeManifest "${_runtime_manifest}"
    -RepositoryRoot "${PROJECT_SOURCE_DIR}"
    -Quiet
  RESULT_VARIABLE _validation_result
  OUTPUT_VARIABLE _validation_stdout
  ERROR_VARIABLE _validation_stderr
  ENCODING UTF-8
)
if(NOT _validation_result EQUAL 0)
  string(
    REGEX MATCH
    "validation failed \\(([A-Za-z0-9-]+)\\)"
    _validation_code_match
    "${_validation_stdout}\n${_validation_stderr}"
  )
  if(CMAKE_MATCH_1)
    message(FATAL_ERROR
      "Generated title bundle validation failed (${CMAKE_MATCH_1}).")
  endif()
  message(FATAL_ERROR "Generated title bundle validation failed.")
endif()

file(READ "${_provenance}" _provenance_json)
_kzmrecomp_json_get(
  _runtime_manifest_sha256
  "${_provenance_json}"
  runtimeManifest sha256
)
string(LENGTH "${_runtime_manifest_sha256}" _runtime_manifest_hash_length)
if(NOT _runtime_manifest_hash_length EQUAL 64 OR
   NOT _runtime_manifest_sha256 MATCHES "^[0-9a-f]+$")
  message(FATAL_ERROR "Generated title bundle metadata is invalid.")
endif()

set(_generated_compilation_sources)
set(_generated_import_sources)
set(_generated_headers)
set(_expected_managed_paths)
_kzmrecomp_json_length(
  _generated_file_count
  "${_provenance_json}"
  generatedFiles
)
if(_generated_file_count LESS 1)
  message(FATAL_ERROR "Generated title bundle metadata is invalid.")
endif()
math(EXPR _generated_file_last "${_generated_file_count} - 1")
foreach(_index RANGE 0 "${_generated_file_last}")
  _kzmrecomp_json_get(
    _generated_relative_path
    "${_provenance_json}"
    generatedFiles "${_index}" path
  )
  _kzmrecomp_json_get(
    _generated_kind
    "${_provenance_json}"
    generatedFiles "${_index}" kind
  )
  set(_generated_path
    "${_generated_source_root}/${_generated_relative_path}")
  if(_generated_kind STREQUAL "module-source" OR
     _generated_kind STREQUAL "module-partition" OR
     _generated_kind STREQUAL "registry-source")
    list(APPEND _generated_compilation_sources "${_generated_path}")
  elseif(_generated_kind STREQUAL "import-source")
    list(APPEND _generated_import_sources "${_generated_path}")
  elseif(_generated_kind STREQUAL "module-header" OR
         _generated_kind STREQUAL "registry-header")
    list(APPEND _generated_headers "${_generated_path}")
  else()
    message(FATAL_ERROR "Generated title bundle metadata is invalid.")
  endif()
  list(APPEND _expected_managed_paths "${_generated_relative_path}")
endforeach()

if(NOT _generated_compilation_sources)
  message(FATAL_ERROR "Generated title bundle metadata is invalid.")
endif()

_kzmrecomp_json_length(
  _module_count
  "${_provenance_json}"
  modules
)
math(EXPR _module_last "${_module_count} - 1")
foreach(_index RANGE 0 "${_module_last}")
  foreach(_artifact IN ITEMS sidecar reportJson reportText)
    _kzmrecomp_json_get(
      _artifact_path
      "${_provenance_json}"
      modules "${_index}" "${_artifact}" path
    )
    list(APPEND _expected_managed_paths "${_artifact_path}")
  endforeach()
endforeach()
foreach(_artifact IN ITEMS reportJson reportText)
  _kzmrecomp_json_get(
    _artifact_path
    "${_provenance_json}"
    aggregate "${_artifact}" path
  )
  list(APPEND _expected_managed_paths "${_artifact_path}")
endforeach()
list(APPEND _expected_managed_paths
  ".generated-source-provenance.json")

set(_unique_expected_managed_paths "${_expected_managed_paths}")
list(REMOVE_DUPLICATES _unique_expected_managed_paths)
list(LENGTH _expected_managed_paths _expected_managed_count)
list(LENGTH _unique_expected_managed_paths _unique_expected_managed_count)
if(NOT _expected_managed_count EQUAL _unique_expected_managed_count)
  message(FATAL_ERROR "Generated title bundle metadata is invalid.")
endif()
list(SORT _expected_managed_paths)

file(READ "${_staging_manifest}" _staging_json)
_kzmrecomp_json_length(_staging_root_member_count "${_staging_json}")
_kzmrecomp_json_get(_staging_schema "${_staging_json}" schemaVersion)
_kzmrecomp_json_length(_staging_file_count "${_staging_json}" files)
if(NOT _staging_root_member_count EQUAL 2 OR
   NOT _staging_schema EQUAL 1 OR
   NOT _staging_file_count EQUAL _expected_managed_count)
  message(FATAL_ERROR
    "Generated title bundle staging inventory is invalid.")
endif()

if(_staging_file_count GREATER 0)
  math(EXPR _staging_file_last "${_staging_file_count} - 1")
  foreach(_index RANGE 0 "${_staging_file_last}")
    _kzmrecomp_json_length(
      _staging_entry_member_count
      "${_staging_json}"
      files "${_index}"
    )
    _kzmrecomp_json_get(
      _staged_relative_path
      "${_staging_json}"
      files "${_index}" path
    )
    _kzmrecomp_json_get(
      _staged_sha256
      "${_staging_json}"
      files "${_index}" sha256
    )
    string(LENGTH "${_staged_sha256}" _staged_hash_length)
    list(GET _expected_managed_paths "${_index}" _expected_relative_path)
    if(NOT _staging_entry_member_count EQUAL 2 OR
       NOT _staged_relative_path STREQUAL _expected_relative_path OR
       NOT _staged_hash_length EQUAL 64 OR
       NOT _staged_sha256 MATCHES "^[0-9a-f]+$")
      message(FATAL_ERROR
        "Generated title bundle staging inventory is invalid.")
    endif()
    set(_staged_path
      "${_generated_source_root}/${_staged_relative_path}")
    if(NOT EXISTS "${_staged_path}" OR IS_DIRECTORY "${_staged_path}")
      message(FATAL_ERROR
        "Generated title bundle staging inventory is invalid.")
    endif()
    file(SHA256 "${_staged_path}" _actual_staged_sha256)
    if(NOT _actual_staged_sha256 STREQUAL _staged_sha256)
      message(FATAL_ERROR
        "Generated title bundle staging inventory is invalid.")
    endif()
  endforeach()
endif()

_kzmrecomp_json_get(
  KZMRECOMP_GENERATED_REGISTRY_HEADER
  "${_provenance_json}"
  aggregate registryHeader path
)
set(KZMRECOMP_EXPECTED_RUNTIME_MANIFEST_SHA256
  "${_runtime_manifest_sha256}")
set(_private_generated_directory
  "${CMAKE_CURRENT_BINARY_DIR}/private")
file(MAKE_DIRECTORY "${_private_generated_directory}")
configure_file(
  generated_bundle_identity.hpp.in
  "${_private_generated_directory}/generated_bundle_identity.hpp"
  @ONLY
)

file(SHA256 "${_provenance}" _provenance_sha256)
file(SHA256 "${_staging_manifest}" _staging_manifest_sha256)
set(KZMRECOMP_VALIDATION_POWERSHELL "${_provenance_powershell}")
set(KZMRECOMP_VALIDATION_PROVENANCE "${_provenance}")
set(KZMRECOMP_VALIDATION_SOURCE_ROOT "${_generated_source_root}")
set(KZMRECOMP_VALIDATION_RUNTIME_MANIFEST "${_runtime_manifest}")
set(KZMRECOMP_VALIDATION_REPOSITORY_ROOT "${PROJECT_SOURCE_DIR}")
set(KZMRECOMP_VALIDATION_EXPECTED_PROVENANCE_SHA256
  "${_provenance_sha256}")
set(KZMRECOMP_VALIDATION_STAGING_MANIFEST "${_staging_manifest}")
set(KZMRECOMP_VALIDATION_EXPECTED_STAGING_SHA256
  "${_staging_manifest_sha256}")
set(_build_validation_script
  "${_private_generated_directory}/validate_generated_bundle.cmake")
configure_file(
  generated_bundle_validation.cmake.in
  "${_build_validation_script}"
  @ONLY
)

add_custom_target(kzmrecomp_validate_generated_bundle
  COMMAND "${CMAKE_COMMAND}" -P "${_build_validation_script}"
  COMMENT "Validating generated title bundle provenance"
  VERBATIM
)

add_library(kzmrecomp_title_generated STATIC
  ${_generated_compilation_sources}
  ${_generated_headers}
)
add_dependencies(kzmrecomp_title_generated
  kzmrecomp_validate_generated_bundle)
target_include_directories(kzmrecomp_title_generated PRIVATE
  "${_generated_source_root}"
  "${PROJECT_SOURCE_DIR}/third_party/vitarecomp/include"
)
_kzmrecomp_configure_generated_c(kzmrecomp_title_generated)

if(_generated_import_sources)
  add_library(kzmrecomp_generated_import_defaults STATIC
    ${_generated_import_sources}
  )
  add_dependencies(kzmrecomp_generated_import_defaults
    kzmrecomp_validate_generated_bundle)
  target_include_directories(kzmrecomp_generated_import_defaults PRIVATE
    "${_generated_source_root}"
    "${PROJECT_SOURCE_DIR}/third_party/vitarecomp/include"
  )
  _kzmrecomp_configure_generated_c(
    kzmrecomp_generated_import_defaults)
else()
  add_library(kzmrecomp_generated_import_defaults INTERFACE)
endif()

add_library(kzmrecomp_generated_bundle_adapter STATIC
  generated_bundle_present.cpp
)
add_dependencies(kzmrecomp_generated_bundle_adapter
  kzmrecomp_validate_generated_bundle)
target_include_directories(kzmrecomp_generated_bundle_adapter
  PUBLIC
    "${PROJECT_SOURCE_DIR}/src"
  PRIVATE
    "${_generated_source_root}"
    "${_private_generated_directory}"
    "${PROJECT_SOURCE_DIR}/third_party/vitarecomp/include"
)
target_compile_features(kzmrecomp_generated_bundle_adapter
  PUBLIC cxx_std_20)
target_link_libraries(kzmrecomp_generated_bundle_adapter PRIVATE
  vitarecomp)
if(BUILD_TESTING)
  target_compile_definitions(kzmrecomp_generated_bundle_adapter PUBLIC
    KZMRECOMP_ENABLE_TEST_SEAMS=1)
endif()
kzmrecomp_project_warnings(kzmrecomp_generated_bundle_adapter)

add_library(kzmrecomp_game_generated_bundle INTERFACE)
target_link_libraries(kzmrecomp_game_generated_bundle INTERFACE
  kzmrecomp_generated_bundle_adapter
  kzmrecomp_title_generated
  vitarecomp
  kzmrecomp_generated_import_defaults
)

set(KZMRECOMP_GENERATED_BUNDLE_PRESENT TRUE PARENT_SCOPE)
message(STATUS "Validated generated title bundle integration enabled.")
