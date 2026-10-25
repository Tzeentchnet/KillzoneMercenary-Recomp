// SPDX-License-Identifier: GPL-2.0-or-later
#include "host/application.hpp"

#include "game/title_config.hpp"
#include "host/cli.hpp"
#include "host/exit_codes.hpp"
#include "host/manifest.hpp"
#include "host/renderer.hpp"
#include "host/runtime_session.hpp"
#include "host/window.hpp"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <exception>
#include <optional>
#include <string>

namespace kzm::host {

void write_cli_text(std::string_view text) {
    const HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);
    if (output != nullptr && output != INVALID_HANDLE_VALUE) {
        DWORD written = 0U;
        (void)WriteFile(
            output, text.data(), static_cast<DWORD>(text.size()),
            &written, nullptr);
    }
    std::string debug(text);
    OutputDebugStringA(debug.c_str());
}

int run_application(
    const std::vector<std::wstring>& arguments,
    Logger& logger) {
    const ParseResult parsed = parse_command_line(arguments);
    if (!parsed.config.has_value()) {
        logger.log(
            LogLevel::error,
            "invalid_arguments",
            parsed.error,
            {{"exit_code", std::to_string(value(
                ExitCode::invalid_arguments))}});
        return value(ExitCode::invalid_arguments);
    }
    const HostConfig& config = *parsed.config;
    if (config.help) {
        write_cli_text(command_line_help());
        return value(ExitCode::success);
    }
    logger.set_minimum(config.log_level);
    if (config.content_root.has_value()) {
        logger.add_secret(utf8_from_wide(config.content_root->native()));
        logger.add_secret(utf8_from_wide(config.manifest->native()));
    }
    logger.log(
        LogLevel::info,
        "host_start",
        "native standalone host starting",
        {
            {"renderer", std::string(renderer_name(*config.renderer))},
            {"adapter", config.adapter.kind == AdapterSelectionKind::warp
                ? "warp"
                : config.adapter.kind == AdapterSelectionKind::hardware
                    ? "hardware"
                    : std::to_string(config.adapter.index)},
            {"mode", config.self_test ? "self-test" : "title-disabled"},
        });

    std::optional<ValidatedContent> content;
    if (config.content_root.has_value()) {
        try {
            content = validate_content_manifest(
                *config.manifest, *config.content_root);
            logger.log(
                LogLevel::info,
                "content_validated",
                "private runtime manifest and external content passed strict validation",
                {
                    {"modules", std::to_string(content->module_count)},
                    {"segments", std::to_string(content->load_segment_count)},
                });
        } catch (const ManifestError& error) {
            logger.log(
                LogLevel::error,
                "content_invalid",
                error.what(),
                {{"exit_code", std::to_string(value(
                    ExitCode::content_invalid))}});
            return value(ExitCode::content_invalid);
        } catch (const std::exception&) {
            logger.log(
                LogLevel::error,
                "content_invalid",
                "content validation failed safely",
                {{"exit_code", std::to_string(value(
                    ExitCode::content_invalid))}});
            return value(ExitCode::content_invalid);
        }
    }

    try {
        RuntimeSession runtime(logger);
        if (content.has_value()) {
            runtime.mount_app0(*content);
        }
        if (!config.self_test) {
            if (game::title_execution_ready()) {
                logger.log(
                    LogLevel::error,
                    "title_execution_guard_failed",
                    "title readiness unexpectedly reported success");
                return value(ExitCode::internal_error);
            }
            logger.log(
                LogLevel::error,
                "title_not_implemented",
                std::string(
                    "title execution is disabled: ") +
                    std::string(game::title_execution_blocker()),
                {{"exit_code", std::to_string(value(
                    ExitCode::title_not_implemented))}});
            return value(ExitCode::title_not_implemented);
        }

        try {
            Window window(640U, 360U);
            RendererSession renderer(config, window, logger);
            (void)renderer.run_self_test(config.frames);
        } catch (const RendererError& error) {
            logger.log(
                LogLevel::error,
                "self_test_failed",
                error.what(),
                {{"exit_code", std::to_string(value(error.exit_code()))}});
            return value(error.exit_code());
        } catch (const std::exception& error) {
            logger.log(
                LogLevel::error,
                "window_failed",
                error.what(),
                {{"exit_code", std::to_string(value(
                    ExitCode::window_failed))}});
            return value(ExitCode::window_failed);
        }
    } catch (const std::exception& error) {
        logger.log(
            LogLevel::error,
            "runtime_failed",
            error.what(),
            {{"exit_code", std::to_string(value(
                ExitCode::runtime_failed))}});
        return value(ExitCode::runtime_failed);
    }

    logger.log(
        LogLevel::info,
        "host_shutdown",
        "native host completed successfully",
        {{"exit_code", "0"}});
    return value(ExitCode::success);
}

} // namespace kzm::host
