// SPDX-License-Identifier: GPL-2.0-or-later
#include "host/cli.hpp"

#include <charconv>
#include <limits>
#include <unordered_set>

namespace kzm::host {
namespace {

struct OptionValue {
    std::wstring_view name;
    std::optional<std::wstring_view> value;
};

std::optional<OptionValue> split_option(std::wstring_view argument) {
    if (!argument.starts_with(L"--") || argument.size() == 2) {
        return std::nullopt;
    }
    const std::size_t equals = argument.find(L'=');
    if (equals == std::wstring_view::npos) {
        return OptionValue{argument.substr(2), std::nullopt};
    }
    return OptionValue{
        argument.substr(2, equals - 2),
        argument.substr(equals + 1),
    };
}

bool parse_u32(std::wstring_view text, std::uint32_t& output) {
    if (text.empty()) {
        return false;
    }
    std::string narrow;
    narrow.reserve(text.size());
    for (const wchar_t character : text) {
        if (character < L'0' || character > L'9') {
            return false;
        }
        narrow.push_back(static_cast<char>(character));
    }
    const char* const begin = narrow.data();
    const char* const end = begin + narrow.size();
    const auto result = std::from_chars(begin, end, output);
    return result.ec == std::errc{} && result.ptr == end;
}

std::optional<std::wstring_view> take_value(
    const OptionValue& option,
    const std::vector<std::wstring>& arguments,
    std::size_t& index,
    std::string& error) {
    if (option.value.has_value()) {
        if (option.value->empty()) {
            error = "option value must not be empty";
            return std::nullopt;
        }
        return option.value;
    }
    if (index + 1 >= arguments.size() ||
        arguments[index + 1].starts_with(L"--")) {
        error = "option requires a value";
        return std::nullopt;
    }
    ++index;
    return std::wstring_view(arguments[index]);
}

bool mark_once(
    std::unordered_set<std::wstring>& seen,
    std::wstring_view name,
    std::string& error) {
    if (!seen.emplace(name).second) {
        error = "option was specified more than once";
        return false;
    }
    return true;
}

std::optional<bool> parse_boolean(std::wstring_view text) {
    if (text == L"on" || text == L"true" || text == L"1") {
        return true;
    }
    if (text == L"off" || text == L"false" || text == L"0") {
        return false;
    }
    return std::nullopt;
}

} // namespace

ParseResult parse_command_line(
    const std::vector<std::wstring>& arguments) {
    HostConfig config;
    std::unordered_set<std::wstring> seen;

    for (std::size_t index = 1; index < arguments.size(); ++index) {
        const auto option = split_option(arguments[index]);
        if (!option.has_value()) {
            return {.error = "positional arguments are not supported"};
        }
        std::string error;
        if (!mark_once(seen, option->name, error)) {
            return {.error = std::move(error)};
        }

        if (option->name == L"help") {
            if (option->value.has_value()) {
                return {.error = "--help does not accept a value"};
            }
            config.help = true;
        } else if (option->name == L"self-test") {
            if (option->value.has_value()) {
                return {.error = "--self-test does not accept a value"};
            }
            config.self_test = true;
        } else if (option->name == L"validation") {
            if (!option->value.has_value()) {
                config.validation = true;
            } else {
                const auto parsed = parse_boolean(*option->value);
                if (!parsed.has_value()) {
                    return {.error =
                        "--validation expects on, off, true, false, 1, or 0"};
                }
                config.validation = *parsed;
            }
        } else if (option->name == L"content-root") {
            const auto value = take_value(
                *option, arguments, index, error);
            if (!value.has_value()) {
                return {.error = "--content-root " + error};
            }
            config.content_root = std::filesystem::path(*value);
        } else if (option->name == L"manifest") {
            const auto value = take_value(
                *option, arguments, index, error);
            if (!value.has_value()) {
                return {.error = "--manifest " + error};
            }
            config.manifest = std::filesystem::path(*value);
        } else if (option->name == L"renderer") {
            const auto value = take_value(
                *option, arguments, index, error);
            if (!value.has_value()) {
                return {.error = "--renderer " + error};
            }
            if (*value == L"dx12") {
                config.renderer = Renderer::dx12;
            } else if (*value == L"vulkan") {
                config.renderer = Renderer::vulkan;
            } else {
                return {.error = "--renderer expects dx12 or vulkan"};
            }
        } else if (option->name == L"adapter") {
            const auto value = take_value(
                *option, arguments, index, error);
            if (!value.has_value()) {
                return {.error = "--adapter " + error};
            }
            config.adapter_explicit = true;
            if (*value == L"hardware") {
                config.adapter.kind = AdapterSelectionKind::hardware;
            } else if (*value == L"warp") {
                config.adapter.kind = AdapterSelectionKind::warp;
            } else {
                std::uint32_t adapter_index = 0;
                if (!parse_u32(*value, adapter_index)) {
                    return {.error =
                        "--adapter expects hardware, warp, or a numeric index"};
                }
                config.adapter.kind = AdapterSelectionKind::index;
                config.adapter.index = adapter_index;
            }
        } else if (option->name == L"log-level") {
            const auto value = take_value(
                *option, arguments, index, error);
            if (!value.has_value()) {
                return {.error = "--log-level " + error};
            }
            if (*value == L"trace") {
                config.log_level = LogLevel::trace;
            } else if (*value == L"debug") {
                config.log_level = LogLevel::debug;
            } else if (*value == L"info") {
                config.log_level = LogLevel::info;
            } else if (*value == L"warning" || *value == L"warn") {
                config.log_level = LogLevel::warning;
            } else if (*value == L"error") {
                config.log_level = LogLevel::error;
            } else {
                return {.error =
                    "--log-level expects trace, debug, info, warning, or error"};
            }
        } else if (option->name == L"frames") {
            const auto value = take_value(
                *option, arguments, index, error);
            if (!value.has_value()) {
                return {.error = "--frames " + error};
            }
            std::uint32_t frames = 0;
            if (!parse_u32(*value, frames) || frames == 0U ||
                frames > 10000U) {
                return {.error =
                    "--frames expects an integer from 1 through 10000"};
            }
            config.frames = frames;
            config.frames_explicit = true;
        } else {
            return {.error = "unknown command-line option"};
        }
    }

    if (config.help) {
        if (arguments.size() != 2U) {
            return {.error = "--help must be used by itself"};
        }
        return {.config = config};
    }
    if (!config.renderer.has_value()) {
        return {.error = "--renderer is required"};
    }
    if (config.adapter.kind == AdapterSelectionKind::warp &&
        *config.renderer != Renderer::dx12) {
        return {.error = "--adapter=warp is valid only with --renderer=dx12"};
    }
    if (config.frames_explicit && !config.self_test) {
        return {.error = "--frames requires --self-test"};
    }
    if (config.content_root.has_value() != config.manifest.has_value()) {
        return {.error =
            "--content-root and --manifest must be supplied together"};
    }
    if (!config.self_test && !config.content_root.has_value()) {
        return {.error =
            "title mode requires --content-root and --manifest"};
    }
    return {.config = std::move(config)};
}

std::string command_line_help() {
    return
        "Killzone Mercenary Recomp native host (title execution disabled)\r\n"
        "\r\n"
        "Usage:\r\n"
        "  kzmrecomp_host --self-test --renderer=dx12|vulkan [options]\r\n"
        "  kzmrecomp_host --content-root <path> --manifest <path>\r\n"
        "                  --renderer=dx12|vulkan [options]\r\n"
        "\r\n"
        "Options:\r\n"
        "  --content-root <path>  External app0 root; paired with --manifest.\r\n"
        "  --manifest <path>      Private runtime-image manifest.\r\n"
        "  --renderer <name>      Required: dx12 or vulkan; never falls back.\r\n"
        "  --adapter <selector>   hardware (default), warp (DX12), or index.\r\n"
        "  --validation[=on|off]  Require backend validation when enabled.\r\n"
        "  --log-level <level>    trace, debug, info, warning, or error.\r\n"
        "  --self-test            Run the bounded clear/triangle conformance path.\r\n"
        "  --frames <count>       Self-test frame count, 1 through 10000 (default 4).\r\n"
        "  --help                 Show this help and exit.\r\n";
}

std::string_view renderer_name(Renderer renderer) noexcept {
    return renderer == Renderer::dx12 ? "dx12" : "vulkan";
}

std::string_view log_level_name(LogLevel level) noexcept {
    switch (level) {
    case LogLevel::trace: return "trace";
    case LogLevel::debug: return "debug";
    case LogLevel::info: return "info";
    case LogLevel::warning: return "warning";
    case LogLevel::error: return "error";
    }
    return "error";
}

} // namespace kzm::host
