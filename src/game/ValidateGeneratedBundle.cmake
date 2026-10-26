# SPDX-License-Identifier: GPL-2.0-or-later

foreach(_required IN ITEMS
    KZMRECOMP_VALIDATION_POWERSHELL
    KZMRECOMP_VALIDATION_PROVENANCE
    KZMRECOMP_VALIDATION_SOURCE_ROOT
    KZMRECOMP_VALIDATION_RUNTIME_MANIFEST
    KZMRECOMP_VALIDATION_REPOSITORY_ROOT
    KZMRECOMP_VALIDATION_EXPECTED_PROVENANCE_SHA256
    KZMRECOMP_VALIDATION_STAGING_MANIFEST
    KZMRECOMP_VALIDATION_EXPECTED_STAGING_SHA256
)
  if(NOT DEFINED "${_required}" OR "${${_required}}" STREQUAL "")
    message(FATAL_ERROR "Generated title bundle validation is incomplete.")
  endif()
endforeach()

foreach(_required_file IN ITEMS
    "${KZMRECOMP_VALIDATION_PROVENANCE}"
    "${KZMRECOMP_VALIDATION_RUNTIME_MANIFEST}"
    "${KZMRECOMP_VALIDATION_STAGING_MANIFEST}"
)
  if(NOT EXISTS "${_required_file}" OR IS_DIRECTORY "${_required_file}")
    message(FATAL_ERROR "Generated title bundle validation failed (missing-file).")
  endif()
endforeach()

file(
  SHA256
  "${KZMRECOMP_VALIDATION_PROVENANCE}"
  _actual_provenance_sha256
)
file(
  SHA256
  "${KZMRECOMP_VALIDATION_STAGING_MANIFEST}"
  _actual_staging_sha256
)
if(NOT
    _actual_provenance_sha256 STREQUAL
      KZMRECOMP_VALIDATION_EXPECTED_PROVENANCE_SHA256 OR
    NOT
    _actual_staging_sha256 STREQUAL
      KZMRECOMP_VALIDATION_EXPECTED_STAGING_SHA256
)
  message(FATAL_ERROR
    "Generated title bundle validation failed (stale-configuration).")
endif()

execute_process(
  COMMAND
    "${KZMRECOMP_VALIDATION_POWERSHELL}"
    -NoLogo
    -NoProfile
    -ExecutionPolicy Bypass
    -File
      "${KZMRECOMP_VALIDATION_REPOSITORY_ROOT}/tools/generated/Test-GeneratedSourceProvenance.ps1"
    -ProvenanceFile "${KZMRECOMP_VALIDATION_PROVENANCE}"
    -SourceRoot "${KZMRECOMP_VALIDATION_SOURCE_ROOT}"
    -RuntimeManifest "${KZMRECOMP_VALIDATION_RUNTIME_MANIFEST}"
    -RepositoryRoot "${KZMRECOMP_VALIDATION_REPOSITORY_ROOT}"
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
