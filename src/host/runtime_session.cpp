// SPDX-License-Identifier: GPL-2.0-or-later
#include "host/runtime_session.hpp"

#include "game/title_config.hpp"
#include "host/exit_codes.hpp"

#include "vitarecomp/host.h"
#include "vitarecomp/runtime.h"
#include "vitarecomp/vfs.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <array>
#include <limits>
#include <stdexcept>
#include <string>

namespace kzm::host {
namespace {

class RuntimeError final : public std::runtime_error {
  public:
    using std::runtime_error::runtime_error;
};

LogLevel diagnostic_level(vita_diag_severity severity) {
    switch (severity) {
    case VITA_DIAG_TRACE:
        return LogLevel::trace;
    case VITA_DIAG_INFO:
        return LogLevel::debug;
    case VITA_DIAG_WARNING:
        return LogLevel::warning;
    case VITA_DIAG_ERROR:
    case VITA_DIAG_FATAL:
        return LogLevel::error;
    }
    return LogLevel::error;
}

void runtime_diagnostic(const vita_diagnostic *event, void *userdata) {
    if (event == nullptr || userdata == nullptr)
        return;
    auto &logger = *static_cast<Logger *>(userdata);
    logger.log(diagnostic_level(event->severity), "runtime_diagnostic",
               event->message != nullptr ? event->message : "runtime event",
               {{"status", std::to_string(event->status)}});
}

void runtime_exit_requested(int status, void *userdata) {
    if (userdata == nullptr)
        return;
    auto &logger = *static_cast<Logger *>(userdata);
    logger.log(LogLevel::warning, "runtime_exit_requested",
               "the standalone runtime requested host shutdown",
               {{"status", std::to_string(status)}});
}

std::string path_for_framework(const std::filesystem::path &path) {
    const std::wstring text = path.native();
    if (text.empty() || text.size() > static_cast<std::size_t>(
                                          std::numeric_limits<int>::max())) {
        throw RuntimeError("content root cannot be represented by the VFS");
    }
    BOOL used_default = FALSE;
    const int needed = WideCharToMultiByte(
        CP_ACP, WC_NO_BEST_FIT_CHARS, text.data(),
        static_cast<int>(text.size()), nullptr, 0, nullptr, &used_default);
    if (needed <= 0 || used_default != FALSE) {
        throw RuntimeError(
            "content root is not representable by the current Windows VFS");
    }
    std::string result(static_cast<std::size_t>(needed), '\0');
    used_default = FALSE;
    const int converted =
        WideCharToMultiByte(CP_ACP, WC_NO_BEST_FIT_CHARS, text.data(),
                            static_cast<int>(text.size()), result.data(),
                            needed, nullptr, &used_default);
    if (converted != needed || used_default != FALSE) {
        throw RuntimeError(
            "content root is not representable by the current Windows VFS");
    }
    return result;
}

} // namespace

RuntimeSession::RuntimeSession(Logger &logger)
    : RuntimeSession(logger, game::scaffold_memory_layout()) {}

RuntimeSession::RuntimeSession(Logger &logger,
                               const game::RuntimeMemoryLayout &layout)
    : logger_(logger) {
    vita_runtime_config config{};
    config.memory_base = layout.memory_base;
    config.memory_size = layout.memory_size;
    config.heap_base = layout.heap_base;
    config.heap_size = layout.heap_size;
    config.sysmem_base = layout.sysmem_base;
    config.sysmem_size = layout.sysmem_size;
    config.kernel_base = layout.kernel_base;
    config.kernel_size = layout.kernel_size;
    config.tls_base = layout.tls_base;
    config.tls_size = layout.tls_size;
    config.virtual_clock = 1;
    config.virtual_epoch_us = 0U;
    config.virtual_read_step_us = 100U;
    config.diagnostic = runtime_diagnostic;
    config.diagnostic_userdata = &logger_;
    config.exit_requested = runtime_exit_requested;
    config.exit_userdata = &logger_;
    const int result = vita_runtime_init(&config);
    if (result != VITA_OK) {
        throw RuntimeError(
            "standalone runtime initialization failed with status " +
            std::to_string(result));
    }
    initialized_ = true;
    logger_.log(
        LogLevel::info, "runtime_initialized",
        "standalone runtime initialized without JIT or emulator dependencies",
        {{"memory_bytes", std::to_string(layout.memory_size)}});
}

RuntimeSession::~RuntimeSession() {
    if (initialized_) {
        vita_runtime_shutdown();
        initialized_ = false;
        logger_.log(LogLevel::debug, "runtime_shutdown",
                    "standalone runtime resources were released");
    }
}

void RuntimeSession::mount_app0(const ValidatedContent &content) {
    const std::string root = path_for_framework(content.canonical_root());
    const int mount_result =
        vita_vfs_mount("app0:", root.c_str(), VITA_VFS_MOUNT_READ_ONLY);
    if (mount_result != VITA_OK) {
        throw RuntimeError(
            "validated app0 root could not be mounted read-only");
    }

    std::array<char, 4096> resolved{};
    const int writable_result = vita_vfs_resolve(
        "app0:/__write_probe__", VITA_VFS_OPEN_WRITE | VITA_VFS_OPEN_CREATE,
        resolved.data(), resolved.size());
    if (writable_result != VITA_ERROR_READ_ONLY) {
        throw RuntimeError("app0 mount unexpectedly accepted writable access");
    }
    const int traversal_result =
        vita_vfs_resolve("app0:/../escape", VITA_VFS_OPEN_READ, resolved.data(),
                         resolved.size());
    if (traversal_result != VITA_ERROR_TRAVERSAL) {
        throw RuntimeError("app0 mount unexpectedly accepted traversal");
    }

    logger_.log(
        LogLevel::info, "content_mounted_read_only",
        "validated external app0 root mounted with traversal and write denial",
        {
            {"modules", std::to_string(content.module_count())},
            {"segments", std::to_string(content.load_segment_count())},
        });
}

std::uint32_t RuntimeSession::prepare_main_stack(std::uint32_t base,
                                                 std::uint32_t size) {
    std::uint32_t initial_stack_pointer = 0U;
    const vita_result result =
        vita_main_stack_prepare(base, size, &initial_stack_pointer);
    if (result != VITA_OK) {
        throw RuntimeError(
            "standalone main-stack preparation failed with status " +
            std::to_string(result));
    }
    logger_.log(LogLevel::debug, "runtime_stack_prepared",
                "standalone main stack passed checked preparation",
                {{"initial_sp", std::to_string(initial_stack_pointer)}});
    return initial_stack_pointer;
}

} // namespace kzm::host
