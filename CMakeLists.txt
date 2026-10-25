# SPDX-License-Identifier: GPL-2.0-or-later

cmake_minimum_required(VERSION 3.25)

project(
  KillzoneMercenaryRecomp
  VERSION 0.2.0
  DESCRIPTION "Source-only native Windows host for Killzone Mercenary recompilation"
  LANGUAGES C CXX
)

if(NOT WIN32)
  message(FATAL_ERROR "The native host supports Windows only.")
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "The native host requires a Windows x64 toolchain.")
endif()

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(KZMRECOMP_BUILD_HOST "Build the native Windows host" ON)

set(VITARECOMP_BUILD_GPU ON CACHE BOOL
  "Build the renderer-neutral GPU contract" FORCE)
set(VITARECOMP_ENABLE_DX12 ON CACHE BOOL
  "Build the DirectX 12 backend" FORCE)
set(VITARECOMP_ENABLE_VULKAN ON CACHE BOOL
  "Build the Vulkan backend when SDK headers are available" FORCE)
if(KZMRECOMP_BUILD_HOST)
  set(VITARECOMP_DXC_REQUIRED ON CACHE BOOL
    "Require the framework-pinned DXC for host shaders" FORCE)
endif()

add_subdirectory(third_party/vitarecomp)

function(kzmrecomp_project_warnings target)
  if(MSVC)
    target_compile_options(${target} PRIVATE
      /W4
      /WX
      /permissive-
      /utf-8
    )
  else()
    target_compile_options(${target} PRIVATE
      -Wall
      -Wextra
      -Wpedantic
      -Werror
    )
  endif()
endfunction()

if(KZMRECOMP_BUILD_HOST)
  if(NOT TARGET Vitarecomp::DXC)
    message(FATAL_ERROR
      "The native host requires pinned DXC "
      "${VITARECOMP_DXC_PINNED_VERSION}. Set VITARECOMP_DXC_ROOT to the "
      "extracted official ${VITARECOMP_DXC_RELEASE_TAG} release.")
  endif()

  add_library(kzmrecomp_host_support STATIC
    src/game/title_config.cpp
    src/host/cli.cpp
    src/host/json.cpp
    src/host/logging.cpp
    src/host/manifest.cpp
    src/host/sha256.cpp
  )
  target_include_directories(kzmrecomp_host_support PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  target_compile_features(kzmrecomp_host_support PUBLIC cxx_std_20)
  target_compile_definitions(kzmrecomp_host_support PRIVATE
    NOMINMAX
    WIN32_LEAN_AND_MEAN
    UNICODE
    _UNICODE
  )
  target_link_libraries(kzmrecomp_host_support PRIVATE bcrypt)
  kzmrecomp_project_warnings(kzmrecomp_host_support)

  add_library(kzmrecomp_host_runtime STATIC
    src/host/application.cpp
    src/host/renderer.cpp
    src/host/runtime_session.cpp
    src/host/window.cpp
  )
  target_include_directories(kzmrecomp_host_runtime PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  target_compile_features(kzmrecomp_host_runtime PUBLIC cxx_std_20)
  target_compile_definitions(kzmrecomp_host_runtime PRIVATE
    NOMINMAX
    WIN32_LEAN_AND_MEAN
    UNICODE
    _UNICODE
  )
  target_link_libraries(kzmrecomp_host_runtime PUBLIC
    kzmrecomp_host_support
    vitarecomp
    vitarecomp::gpu
    user32
  )
  kzmrecomp_project_warnings(kzmrecomp_host_runtime)

  set(_host_shader_source
    "${CMAKE_CURRENT_SOURCE_DIR}/src/host/shaders/conformance.hlsl")
  set(_host_shader_directory
    "${CMAKE_CURRENT_BINARY_DIR}/generated/host-shaders")
  set(_host_shader_flags
    -HV 2021
    -Ges
    -WX
    -O3
    -Qstrip_debug
  )

  set(_host_dxil_vs
    "${_host_shader_directory}/kzmrecomp_conformance_vs.dxil")
  set(_host_dxil_ps
    "${_host_shader_directory}/kzmrecomp_conformance_ps.dxil")
  set(_host_spirv_vs
    "${_host_shader_directory}/kzmrecomp_conformance_vs.spv")
  set(_host_spirv_ps
    "${_host_shader_directory}/kzmrecomp_conformance_ps.spv")

  add_custom_command(
    OUTPUT "${_host_dxil_vs}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory
      "${_host_shader_directory}"
    COMMAND "$<TARGET_FILE:Vitarecomp::DXC>"
      ${_host_shader_flags}
      -Qstrip_reflect
      -T vs_6_0
      -E vs_main
      -Fo "${_host_dxil_vs}"
      "${_host_shader_source}"
    DEPENDS "${_host_shader_source}" Vitarecomp::DXC
    VERBATIM
    COMMENT "Compiling native-host DX12 vertex shader"
  )
  add_custom_command(
    OUTPUT "${_host_dxil_ps}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory
      "${_host_shader_directory}"
    COMMAND "$<TARGET_FILE:Vitarecomp::DXC>"
      ${_host_shader_flags}
      -Qstrip_reflect
      -T ps_6_0
      -E ps_main
      -Fo "${_host_dxil_ps}"
      "${_host_shader_source}"
    DEPENDS "${_host_shader_source}" Vitarecomp::DXC
    VERBATIM
    COMMENT "Compiling native-host DX12 pixel shader"
  )
  add_custom_command(
    OUTPUT "${_host_spirv_vs}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory
      "${_host_shader_directory}"
    COMMAND "$<TARGET_FILE:Vitarecomp::DXC>"
      ${_host_shader_flags}
      -spirv
      -fspv-target-env=vulkan1.3
      -fspv-entrypoint-name=main
      -fvk-use-dx-layout
      -T vs_6_0
      -E vs_main
      -Fo "${_host_spirv_vs}"
      "${_host_shader_source}"
    DEPENDS "${_host_shader_source}" Vitarecomp::DXC
    VERBATIM
    COMMENT "Compiling native-host Vulkan vertex shader"
  )
  add_custom_command(
    OUTPUT "${_host_spirv_ps}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory
      "${_host_shader_directory}"
    COMMAND "$<TARGET_FILE:Vitarecomp::DXC>"
      ${_host_shader_flags}
      -spirv
      -fspv-target-env=vulkan1.3
      -fspv-entrypoint-name=main
      -fvk-use-dx-layout
      -T ps_6_0
      -E ps_main
      -Fo "${_host_spirv_ps}"
      "${_host_shader_source}"
    DEPENDS "${_host_shader_source}" Vitarecomp::DXC
    VERBATIM
    COMMENT "Compiling native-host Vulkan pixel shader"
  )
  add_custom_target(kzmrecomp_host_shaders
    DEPENDS
      "${_host_dxil_vs}"
      "${_host_dxil_ps}"
      "${_host_spirv_vs}"
      "${_host_spirv_ps}"
  )

  add_executable(kzmrecomp_host WIN32
    src/host/main.cpp
  )
  add_dependencies(kzmrecomp_host kzmrecomp_host_shaders)
  target_compile_features(kzmrecomp_host PRIVATE cxx_std_20)
  target_compile_definitions(kzmrecomp_host PRIVATE
    NOMINMAX
    WIN32_LEAN_AND_MEAN
    UNICODE
    _UNICODE
  )
  target_link_libraries(kzmrecomp_host PRIVATE
    kzmrecomp_host_runtime
    shell32
  )
  kzmrecomp_project_warnings(kzmrecomp_host)
  add_custom_command(TARGET kzmrecomp_host POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "${_host_dxil_vs}"
      "$<TARGET_FILE_DIR:kzmrecomp_host>/kzmrecomp_conformance_vs.dxil"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "${_host_dxil_ps}"
      "$<TARGET_FILE_DIR:kzmrecomp_host>/kzmrecomp_conformance_ps.dxil"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "${_host_spirv_vs}"
      "$<TARGET_FILE_DIR:kzmrecomp_host>/kzmrecomp_conformance_vs.spv"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "${_host_spirv_ps}"
      "$<TARGET_FILE_DIR:kzmrecomp_host>/kzmrecomp_conformance_ps.spv"
    VERBATIM
  )

  set_property(DIRECTORY PROPERTY VS_STARTUP_PROJECT kzmrecomp_host)
endif()

include(CTest)

if(BUILD_TESTING)
  find_program(
    KZMRECOMP_POWERSHELL
    NAMES pwsh powershell
    REQUIRED
  )

  add_test(
    NAME content-guard-synthetic
    COMMAND
      "${KZMRECOMP_POWERSHELL}"
      -NoLogo
      -NoProfile
      -ExecutionPolicy Bypass
      -File "${CMAKE_CURRENT_SOURCE_DIR}/tests/Test-PrivateContentGuard.ps1"
  )
  add_test(
    NAME content-pipeline-synthetic
    COMMAND
      "${KZMRECOMP_POWERSHELL}"
      -NoLogo
      -NoProfile
      -ExecutionPolicy Bypass
      -File "${CMAKE_CURRENT_SOURCE_DIR}/tests/Test-ContentPipeline.ps1"
  )
  add_test(
    NAME generated-staging-synthetic
    COMMAND
      "${KZMRECOMP_POWERSHELL}"
      -NoLogo
      -NoProfile
      -ExecutionPolicy Bypass
      -File "${CMAKE_CURRENT_SOURCE_DIR}/tests/Test-StageGeneratedSources.ps1"
  )
  add_test(
    NAME content-guard-staged
    COMMAND
      "${KZMRECOMP_POWERSHELL}"
      -NoLogo
      -NoProfile
      -ExecutionPolicy Bypass
      -File "${CMAKE_CURRENT_SOURCE_DIR}/tools/content/Guard-PrivateContent.ps1"
      -RepositoryRoot "${CMAKE_CURRENT_SOURCE_DIR}"
  )

  if(KZMRECOMP_BUILD_HOST)
    add_executable(kzmrecomp_host_tests
      tests/native_host_tests.cpp
    )
    target_compile_features(kzmrecomp_host_tests PRIVATE cxx_std_20)
    target_link_libraries(kzmrecomp_host_tests PRIVATE
      kzmrecomp_host_support
    )
    kzmrecomp_project_warnings(kzmrecomp_host_tests)
    add_test(NAME native-host-unit COMMAND kzmrecomp_host_tests)
    set_tests_properties(native-host-unit PROPERTIES
      WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
      TIMEOUT 60
      LABELS "host;unit"
    )

    add_test(
      NAME native-host-dx12-warp-self-test
      COMMAND kzmrecomp_host
        --self-test
        --renderer=dx12
        --adapter=warp
        --frames=4
        --log-level=debug
    )
    set_tests_properties(native-host-dx12-warp-self-test PROPERTIES
      TIMEOUT 120
      LABELS "host;gpu;dx12;integration"
      PASS_REGULAR_EXPRESSION "\"event\":\"self_test_passed\""
    )

    function(kzmrecomp_add_host_script_test name mode labels)
      add_test(
        NAME "${name}"
        COMMAND
          "${KZMRECOMP_POWERSHELL}"
          -NoLogo
          -NoProfile
          -ExecutionPolicy Bypass
          -File
            "${CMAKE_CURRENT_SOURCE_DIR}/tests/Test-NativeHostIntegration.ps1"
          -HostExecutable "$<TARGET_FILE:kzmrecomp_host>"
          -Mode "${mode}"
      )
      set_tests_properties("${name}" PROPERTIES
        TIMEOUT 240
        LABELS "${labels}"
      )
    endfunction()

    kzmrecomp_add_host_script_test(
      native-host-dx12-hardware-self-test
      OptionalDx12Hardware
      "host;gpu;dx12;integration"
    )
    kzmrecomp_add_host_script_test(
      native-host-vulkan-validation-self-test
      OptionalVulkanValidation
      "host;gpu;vulkan;integration"
    )
    kzmrecomp_add_host_script_test(
      native-host-unavailable-adapter
      UnavailableAdapter
      "host;gpu;negative"
    )
    kzmrecomp_add_host_script_test(
      native-host-unavailable-backend
      InvalidVulkan
      "host;gpu;vulkan;negative"
    )
    kzmrecomp_add_host_script_test(
      native-host-content-validation
      Content
      "host;content;integration"
    )
    kzmrecomp_add_host_script_test(
      native-host-resize-lifecycle-repeat
      RepeatDx12Warp
      "host;gpu;dx12;lifecycle"
    )
    set_tests_properties(
      native-host-dx12-hardware-self-test
      native-host-vulkan-validation-self-test
      PROPERTIES SKIP_RETURN_CODE 77
    )
  endif()
endif()
