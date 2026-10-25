// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <map>
#include <stdexcept>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

namespace kzm::host {

class JsonError final : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

class JsonValue {
public:
    using Array = std::vector<JsonValue>;
    using Object = std::map<std::string, JsonValue, std::less<>>;

    enum class Type {
        null,
        boolean,
        number,
        string,
        array,
        object,
    };

    JsonValue() = default;
    explicit JsonValue(bool value);
    static JsonValue number(std::string value);
    explicit JsonValue(std::string value);
    explicit JsonValue(Array value);
    explicit JsonValue(Object value);

    [[nodiscard]] Type type() const noexcept;
    [[nodiscard]] bool as_boolean() const;
    [[nodiscard]] const std::string& as_number() const;
    [[nodiscard]] const std::string& as_string() const;
    [[nodiscard]] const Array& as_array() const;
    [[nodiscard]] const Object& as_object() const;

private:
    struct Number {
        std::string value;
    };
    using Storage = std::variant<
        std::monostate, bool, Number, std::string, Array, Object>;
    explicit JsonValue(Number value);
    Storage storage_;
};

[[nodiscard]] JsonValue parse_json(std::string_view input);

} // namespace kzm::host
