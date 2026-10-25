// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace kzm::host {

enum class Renderer {
    dx12,
    vulkan,
};

enum class LogLevel {
    trace,
    debug,
    info,
    warning,
    error,
};

enum class AdapterSelectionKind {
    hardware,
    warp,
    index,
};

struct AdapterSelection {
    AdapterSelectionKind kind = AdapterSelectionKind::hardware;
    std::uint32_t index = 0;
};

struct HostConfig {
    std::optional<std::filesystem::path> content_root;
    std::optional<std::filesystem::path> manifest;
    std::optional<Renderer> renderer;
    AdapterSelection adapter;
    bool adapter_explicit = false;
    bool validation = false;
    LogLevel log_level = LogLevel::info;
    bool self_test = false;
    std::uint32_t frames = 4;
    bool frames_explicit = false;
    bool help = false;
};

struct ParseResult {
    std::optional<HostConfig> config;
    std::string error;
};

[[nodiscard]] ParseResult parse_command_line(
    const std::vector<std::wstring>& arguments);
[[nodiscard]] std::string command_line_help();
[[nodiscard]] std::string_view renderer_name(Renderer renderer) noexcept;
[[nodiscard]] std::string_view log_level_name(LogLevel level) noexcept;

} // namespace kzm::host
