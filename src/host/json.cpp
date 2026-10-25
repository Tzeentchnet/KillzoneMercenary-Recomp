// SPDX-License-Identifier: GPL-2.0-or-later
#include "host/json.hpp"

#include <cctype>
#include <cstdint>
#include <limits>

namespace kzm::host {
namespace {

class Parser {
public:
    explicit Parser(std::string_view input) : input_(input) {}

    JsonValue parse() {
        skip_whitespace();
        JsonValue result = parse_value(0U);
        skip_whitespace();
        if (position_ != input_.size()) {
            fail("trailing data");
        }
        return result;
    }

private:
    static constexpr std::size_t kMaxDepth = 32U;

    [[noreturn]] void fail(std::string_view reason) const {
        throw JsonError(
            "invalid JSON at byte " + std::to_string(position_) +
            ": " + std::string(reason));
    }

    void skip_whitespace() {
        while (position_ < input_.size()) {
            const char character = input_[position_];
            if (character != ' ' && character != '\t' &&
                character != '\r' && character != '\n') {
                return;
            }
            ++position_;
        }
    }

    char take() {
        if (position_ >= input_.size()) {
            fail("unexpected end of input");
        }
        return input_[position_++];
    }

    bool consume(char expected) {
        if (position_ < input_.size() && input_[position_] == expected) {
            ++position_;
            return true;
        }
        return false;
    }

    void expect_literal(std::string_view literal) {
        if (input_.substr(position_, literal.size()) != literal) {
            fail("invalid literal");
        }
        position_ += literal.size();
    }

    JsonValue parse_value(std::size_t depth) {
        if (depth > kMaxDepth) {
            fail("maximum nesting depth exceeded");
        }
        skip_whitespace();
        if (position_ >= input_.size()) {
            fail("expected a value");
        }
        switch (input_[position_]) {
        case 'n':
            expect_literal("null");
            return JsonValue{};
        case 't':
            expect_literal("true");
            return JsonValue(true);
        case 'f':
            expect_literal("false");
            return JsonValue(false);
        case '"':
            return JsonValue(parse_string());
        case '[':
            return parse_array(depth + 1U);
        case '{':
            return parse_object(depth + 1U);
        default:
            if (input_[position_] == '-' ||
                (input_[position_] >= '0' && input_[position_] <= '9')) {
                return JsonValue::number(parse_number());
            }
            fail("expected a value");
        }
    }

    static void append_utf8(std::string& output, std::uint32_t code_point) {
        if (code_point <= 0x7FU) {
            output.push_back(static_cast<char>(code_point));
        } else if (code_point <= 0x7FFU) {
            output.push_back(
                static_cast<char>(0xC0U | (code_point >> 6U)));
            output.push_back(
                static_cast<char>(0x80U | (code_point & 0x3FU)));
        } else if (code_point <= 0xFFFFU) {
            output.push_back(
                static_cast<char>(0xE0U | (code_point >> 12U)));
            output.push_back(static_cast<char>(
                0x80U | ((code_point >> 6U) & 0x3FU)));
            output.push_back(
                static_cast<char>(0x80U | (code_point & 0x3FU)));
        } else {
            output.push_back(
                static_cast<char>(0xF0U | (code_point >> 18U)));
            output.push_back(static_cast<char>(
                0x80U | ((code_point >> 12U) & 0x3FU)));
            output.push_back(static_cast<char>(
                0x80U | ((code_point >> 6U) & 0x3FU)));
            output.push_back(
                static_cast<char>(0x80U | (code_point & 0x3FU)));
        }
    }

    std::uint32_t parse_hex_quad() {
        if (input_.size() - position_ < 4U) {
            fail("truncated Unicode escape");
        }
        std::uint32_t value = 0;
        for (unsigned index = 0; index < 4U; ++index) {
            const char character = input_[position_++];
            value <<= 4U;
            if (character >= '0' && character <= '9') {
                value |= static_cast<std::uint32_t>(character - '0');
            } else if (character >= 'a' && character <= 'f') {
                value |= static_cast<std::uint32_t>(character - 'a' + 10);
            } else if (character >= 'A' && character <= 'F') {
                value |= static_cast<std::uint32_t>(character - 'A' + 10);
            } else {
                fail("invalid Unicode escape");
            }
        }
        return value;
    }

    void parse_unicode_escape(std::string& output) {
        std::uint32_t code_point = parse_hex_quad();
        if (code_point >= 0xD800U && code_point <= 0xDBFFU) {
            if (!consume('\\') || !consume('u')) {
                fail("high surrogate without low surrogate");
            }
            const std::uint32_t low = parse_hex_quad();
            if (low < 0xDC00U || low > 0xDFFFU) {
                fail("invalid low surrogate");
            }
            code_point = 0x10000U +
                ((code_point - 0xD800U) << 10U) +
                (low - 0xDC00U);
        } else if (code_point >= 0xDC00U && code_point <= 0xDFFFU) {
            fail("unpaired low surrogate");
        }
        append_utf8(output, code_point);
    }

    static std::size_t utf8_sequence_length(unsigned char lead) {
        if (lead < 0x80U) return 1U;
        if (lead >= 0xC2U && lead <= 0xDFU) return 2U;
        if (lead >= 0xE0U && lead <= 0xEFU) return 3U;
        if (lead >= 0xF0U && lead <= 0xF4U) return 4U;
        return 0U;
    }

    void append_valid_utf8(std::string& output) {
        const auto lead = static_cast<unsigned char>(input_[position_]);
        const std::size_t length = utf8_sequence_length(lead);
        if (length == 0U || input_.size() - position_ < length) {
            fail("invalid UTF-8 string");
        }
        std::uint32_t value = lead & ((1U << (8U - length - 1U)) - 1U);
        for (std::size_t index = 1U; index < length; ++index) {
            const auto continuation =
                static_cast<unsigned char>(input_[position_ + index]);
            if ((continuation & 0xC0U) != 0x80U) {
                fail("invalid UTF-8 string");
            }
            value = (value << 6U) | (continuation & 0x3FU);
        }
        const std::uint32_t minimum[] = {0U, 0U, 0x80U, 0x800U, 0x10000U};
        if (value < minimum[length] || value > 0x10FFFFU ||
            (value >= 0xD800U && value <= 0xDFFFU)) {
            fail("non-canonical UTF-8 string");
        }
        output.append(input_.substr(position_, length));
        position_ += length;
    }

    std::string parse_string() {
        if (take() != '"') {
            fail("expected string");
        }
        std::string output;
        while (position_ < input_.size()) {
            const auto character =
                static_cast<unsigned char>(input_[position_++]);
            if (character == '"') {
                return output;
            }
            if (character == '\\') {
                const char escaped = take();
                switch (escaped) {
                case '"': output.push_back('"'); break;
                case '\\': output.push_back('\\'); break;
                case '/': output.push_back('/'); break;
                case 'b': output.push_back('\b'); break;
                case 'f': output.push_back('\f'); break;
                case 'n': output.push_back('\n'); break;
                case 'r': output.push_back('\r'); break;
                case 't': output.push_back('\t'); break;
                case 'u': parse_unicode_escape(output); break;
                default: fail("invalid string escape");
                }
            } else if (character < 0x20U) {
                fail("control character in string");
            } else if (character < 0x80U) {
                output.push_back(static_cast<char>(character));
            } else {
                --position_;
                append_valid_utf8(output);
            }
        }
        fail("unterminated string");
    }

    std::string parse_number() {
        const std::size_t start = position_;
        (void)consume('-');
        if (consume('0')) {
            if (position_ < input_.size() &&
                std::isdigit(
                    static_cast<unsigned char>(input_[position_])) != 0) {
                fail("leading zero in number");
            }
        } else {
            if (position_ >= input_.size() ||
                input_[position_] < '1' || input_[position_] > '9') {
                fail("invalid number");
            }
            while (position_ < input_.size() &&
                   std::isdigit(
                       static_cast<unsigned char>(input_[position_])) != 0) {
                ++position_;
            }
        }
        if (consume('.')) {
            if (position_ >= input_.size() ||
                std::isdigit(
                    static_cast<unsigned char>(input_[position_])) == 0) {
                fail("invalid fractional number");
            }
            while (position_ < input_.size() &&
                   std::isdigit(
                       static_cast<unsigned char>(input_[position_])) != 0) {
                ++position_;
            }
        }
        if (position_ < input_.size() &&
            (input_[position_] == 'e' || input_[position_] == 'E')) {
            ++position_;
            if (position_ < input_.size() &&
                (input_[position_] == '+' || input_[position_] == '-')) {
                ++position_;
            }
            if (position_ >= input_.size() ||
                std::isdigit(
                    static_cast<unsigned char>(input_[position_])) == 0) {
                fail("invalid exponent");
            }
            while (position_ < input_.size() &&
                   std::isdigit(
                       static_cast<unsigned char>(input_[position_])) != 0) {
                ++position_;
            }
        }
        return std::string(input_.substr(start, position_ - start));
    }

    JsonValue parse_array(std::size_t depth) {
        (void)take();
        JsonValue::Array values;
        skip_whitespace();
        if (consume(']')) {
            return JsonValue(std::move(values));
        }
        for (;;) {
            values.push_back(parse_value(depth));
            skip_whitespace();
            if (consume(']')) {
                return JsonValue(std::move(values));
            }
            if (!consume(',')) {
                fail("expected ',' or ']'");
            }
            skip_whitespace();
        }
    }

    JsonValue parse_object(std::size_t depth) {
        (void)take();
        JsonValue::Object values;
        skip_whitespace();
        if (consume('}')) {
            return JsonValue(std::move(values));
        }
        for (;;) {
            if (position_ >= input_.size() || input_[position_] != '"') {
                fail("expected object key");
            }
            std::string key = parse_string();
            skip_whitespace();
            if (!consume(':')) {
                fail("expected ':'");
            }
            JsonValue value = parse_value(depth);
            if (!values.emplace(std::move(key), std::move(value)).second) {
                fail("duplicate object key");
            }
            skip_whitespace();
            if (consume('}')) {
                return JsonValue(std::move(values));
            }
            if (!consume(',')) {
                fail("expected ',' or '}'");
            }
            skip_whitespace();
        }
    }

    std::string_view input_;
    std::size_t position_ = 0U;
};

} // namespace

JsonValue::JsonValue(bool value) : storage_(value) {}
JsonValue::JsonValue(Number value) : storage_(std::move(value)) {}
JsonValue JsonValue::number(std::string value) {
    return JsonValue(Number{std::move(value)});
}
JsonValue::JsonValue(std::string value) : storage_(std::move(value)) {}
JsonValue::JsonValue(Array value) : storage_(std::move(value)) {}
JsonValue::JsonValue(Object value) : storage_(std::move(value)) {}

JsonValue::Type JsonValue::type() const noexcept {
    return static_cast<Type>(storage_.index());
}

bool JsonValue::as_boolean() const {
    if (const auto* value = std::get_if<bool>(&storage_)) return *value;
    throw JsonError("JSON value has the wrong type");
}

const std::string& JsonValue::as_number() const {
    if (const auto* value = std::get_if<Number>(&storage_)) {
        return value->value;
    }
    throw JsonError("JSON value has the wrong type");
}

const std::string& JsonValue::as_string() const {
    if (const auto* value = std::get_if<std::string>(&storage_)) return *value;
    throw JsonError("JSON value has the wrong type");
}

const JsonValue::Array& JsonValue::as_array() const {
    if (const auto* value = std::get_if<Array>(&storage_)) return *value;
    throw JsonError("JSON value has the wrong type");
}

const JsonValue::Object& JsonValue::as_object() const {
    if (const auto* value = std::get_if<Object>(&storage_)) return *value;
    throw JsonError("JSON value has the wrong type");
}

JsonValue parse_json(std::string_view input) {
    return Parser(input).parse();
}

} // namespace kzm::host
