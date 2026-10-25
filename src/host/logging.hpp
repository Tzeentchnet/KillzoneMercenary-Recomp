// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "host/cli.hpp"

#include <functional>
#include <initializer_list>
#include <mutex>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace kzm::host {

struct LogField {
    std::string_view name;
    std::string value;
};

class Logger {
public:
    using Sink = std::function<void(std::string_view)>;

    explicit Logger(LogLevel minimum = LogLevel::info, Sink sink = {});

    void set_minimum(LogLevel minimum) noexcept;
    void add_secret(std::string secret);
    void log(
        LogLevel level,
        std::string_view event,
        std::string_view message,
        std::initializer_list<LogField> fields = {});

    [[nodiscard]] std::string redact(std::string_view text) const;

private:
    [[nodiscard]] bool enabled(LogLevel level) const noexcept;
    [[nodiscard]] static std::string escape_json(std::string_view text);
    void write(std::string_view line);

    LogLevel minimum_;
    Sink sink_;
    mutable std::mutex mutex_;
    std::vector<std::string> secrets_;
};

[[nodiscard]] std::string utf8_from_wide(std::wstring_view text);

} // namespace kzm::host
