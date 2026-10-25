// SPDX-License-Identifier: GPL-2.0-or-later
#include "host/logging.hpp"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdio>
#include <ctime>
#include <limits>

namespace kzm::host {
namespace {

bool is_hex(char character) {
    return (character >= '0' && character <= '9') ||
        (character >= 'a' && character <= 'f') ||
        (character >= 'A' && character <= 'F');
}

bool is_path_terminator(char character) {
    return character == '\0' || character == '"' || character == '\'' ||
        character == '\r' || character == '\n' || character == '\t' ||
        character == ' ';
}

void replace_all(
    std::string& text,
    std::string_view needle,
    std::string_view replacement) {
    if (needle.empty()) return;
    std::size_t position = 0U;
    while ((position = text.find(needle, position)) != std::string::npos) {
        text.replace(position, needle.size(), replacement);
        position += replacement.size();
    }
}

std::string redact_hashes(std::string text) {
    std::size_t index = 0U;
    while (index < text.size()) {
        if (!is_hex(text[index])) {
            ++index;
            continue;
        }
        const std::size_t start = index;
        while (index < text.size() && is_hex(text[index])) ++index;
        if (index - start == 64U) {
            text.replace(start, 64U, "<redacted-sha256>");
            index = start + 17U;
        }
    }
    return text;
}

std::string redact_paths(std::string text) {
    std::size_t index = 0U;
    while (index + 2U < text.size()) {
        const bool drive =
            ((text[index] >= 'A' && text[index] <= 'Z') ||
             (text[index] >= 'a' && text[index] <= 'z')) &&
            text[index + 1U] == ':' &&
            (text[index + 2U] == '\\' || text[index + 2U] == '/');
        const bool unc =
            text[index] == '\\' && text[index + 1U] == '\\';
        if (!drive && !unc) {
            ++index;
            continue;
        }
        std::size_t end = index + (drive ? 3U : 2U);
        while (end < text.size() && !is_path_terminator(text[end])) ++end;
        text.replace(index, end - index, "<redacted-path>");
        index += 15U;
    }
    return text;
}

} // namespace

Logger::Logger(LogLevel minimum, Sink sink)
    : minimum_(minimum), sink_(std::move(sink)) {}

void Logger::set_minimum(LogLevel minimum) noexcept {
    minimum_ = minimum;
}

void Logger::add_secret(std::string secret) {
    if (!secret.empty()) {
        std::scoped_lock lock(mutex_);
        secrets_.push_back(std::move(secret));
    }
}

bool Logger::enabled(LogLevel level) const noexcept {
    return static_cast<int>(level) >= static_cast<int>(minimum_);
}

std::string Logger::escape_json(std::string_view text) {
    std::string result;
    result.reserve(text.size() + 8U);
    constexpr char hexadecimal[] = "0123456789abcdef";
    for (const unsigned char character : text) {
        switch (character) {
        case '"': result += "\\\""; break;
        case '\\': result += "\\\\"; break;
        case '\b': result += "\\b"; break;
        case '\f': result += "\\f"; break;
        case '\n': result += "\\n"; break;
        case '\r': result += "\\r"; break;
        case '\t': result += "\\t"; break;
        default:
            if (character < 0x20U) {
                result += "\\u00";
                result.push_back(hexadecimal[character >> 4U]);
                result.push_back(hexadecimal[character & 0x0FU]);
            } else {
                result.push_back(static_cast<char>(character));
            }
        }
    }
    return result;
}

std::string Logger::redact(std::string_view text) const {
    std::string result(text);
    {
        std::scoped_lock lock(mutex_);
        for (const std::string& secret : secrets_) {
            replace_all(result, secret, "<redacted>");
        }
    }
    result = redact_hashes(std::move(result));
    result = redact_paths(std::move(result));
    return result;
}

void Logger::log(
    LogLevel level,
    std::string_view event,
    std::string_view message,
    std::initializer_list<LogField> fields) {
    if (!enabled(level)) return;

    const auto now = std::chrono::system_clock::now();
    const std::time_t time = std::chrono::system_clock::to_time_t(now);
    std::tm utc{};
    (void)gmtime_s(&utc, &time);
    std::array<char, 32> timestamp{};
    (void)std::strftime(
        timestamp.data(), timestamp.size(), "%Y-%m-%dT%H:%M:%SZ", &utc);

    std::string line;
    line.reserve(256U);
    line += "{\"timestamp\":\"";
    line += timestamp.data();
    line += "\",\"level\":\"";
    line += log_level_name(level);
    line += "\",\"event\":\"";
    line += escape_json(redact(event));
    line += "\",\"message\":\"";
    line += escape_json(redact(message));
    line += '"';
    for (const LogField& field : fields) {
        line += ",\"";
        line += escape_json(field.name);
        line += "\":\"";
        line += escape_json(redact(field.value));
        line += '"';
    }
    line += "}\r\n";
    write(line);
}

void Logger::write(std::string_view line) {
    if (sink_) {
        sink_(line);
        return;
    }
    const HANDLE error_handle = GetStdHandle(STD_ERROR_HANDLE);
    if (error_handle != nullptr && error_handle != INVALID_HANDLE_VALUE) {
        DWORD written = 0;
        (void)WriteFile(
            error_handle, line.data(), static_cast<DWORD>(line.size()),
            &written, nullptr);
    }
    std::string debug(line);
    OutputDebugStringA(debug.c_str());
}

std::string utf8_from_wide(std::wstring_view text) {
    if (text.empty()) return {};
    if (text.size() >
        static_cast<std::size_t>(std::numeric_limits<int>::max())) {
        return {};
    }
    const int needed = WideCharToMultiByte(
        CP_UTF8, WC_ERR_INVALID_CHARS, text.data(),
        static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
    if (needed <= 0) return {};
    std::string output(static_cast<std::size_t>(needed), '\0');
    const int converted = WideCharToMultiByte(
        CP_UTF8, WC_ERR_INVALID_CHARS, text.data(),
        static_cast<int>(text.size()), output.data(), needed, nullptr, nullptr);
    return converted == needed ? output : std::string{};
}

} // namespace kzm::host
