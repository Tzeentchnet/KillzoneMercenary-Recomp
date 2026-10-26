// SPDX-License-Identifier: GPL-2.0-or-later
#include "host/manifest.hpp"

#include "game/title_config.hpp"
#include "host/json.hpp"
#include "host/sha256.hpp"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <algorithm>
#include <array>
#include <charconv>
#include <cctype>
#include <cstdint>
#include <cwctype>
#include <fstream>
#include <limits>
#include <memory>
#include <set>
#include <span>
#include <string_view>
#include <vector>

namespace kzm::host {
namespace {

constexpr std::uint64_t kMaximumManifestBytes = 4U * 1024U * 1024U;
constexpr std::size_t kMaximumModules = 64U;
constexpr std::size_t kMaximumSegmentsPerModule = 256U;

struct FileCloser {
    void operator()(void *handle) const noexcept {
        if (handle != nullptr && handle != INVALID_HANDLE_VALUE) {
            (void)CloseHandle(handle);
        }
    }
};

using UniqueFile = std::unique_ptr<void, FileCloser>;

struct Segment {
    std::uint32_t index = 0;
    std::uint64_t file_offset = 0;
    std::uint64_t file_size = 0;
    std::uint32_t virtual_address = 0;
    std::uint32_t physical_address = 0;
    std::uint64_t memory_size = 0;
    std::uint64_t end = 0;
    std::uint32_t flags = 0;
    std::uint64_t alignment = 0;
};

struct ModuleRecord {
    std::string relative_path;
    std::string expected_hash;
    std::uint64_t file_size = 0;
    std::string module_name;
    std::uint32_t encoded_entry = 0;
    std::uint32_t module_info_segment_index = 0;
    std::uint64_t module_info_segment_offset = 0;
    std::uint32_t module_info_virtual_address = 0;
    std::uint32_t program_header_count = 0;
    std::uint16_t elf_type = 0;
    std::uint16_t machine = 0;
    std::uint32_t elf_flags = 0;
    std::vector<Segment> segments;
    std::vector<std::uint8_t> bytes;
};

struct AddressRange {
    std::uint64_t start;
    std::uint64_t end;
    std::size_t module_index;
    std::uint32_t segment_index;
};

[[noreturn]] void fail(std::string message) {
    throw ManifestError(std::move(message));
}

const JsonValue &member(const JsonValue::Object &object, std::string_view name,
                        std::string_view context) {
    const auto found = object.find(name);
    if (found == object.end()) {
        fail(std::string(context) + " is missing a required property");
    }
    return found->second;
}

void require_keys(const JsonValue::Object &object,
                  std::initializer_list<std::string_view> keys,
                  std::string_view context) {
    if (object.size() != keys.size()) {
        fail(std::string(context) + " has unknown or missing properties");
    }
    for (const std::string_view key : keys) {
        if (!object.contains(key)) {
            fail(std::string(context) + " is missing a required property");
        }
    }
}

const JsonValue::Object &object_value(const JsonValue &value,
                                      std::string_view context) {
    if (value.type() != JsonValue::Type::object) {
        fail(std::string(context) + " must be an object");
    }
    return value.as_object();
}

const JsonValue::Array &array_value(const JsonValue &value,
                                    std::string_view context) {
    if (value.type() != JsonValue::Type::array) {
        fail(std::string(context) + " must be an array");
    }
    return value.as_array();
}

const std::string &string_value(const JsonValue &value,
                                std::string_view context) {
    if (value.type() != JsonValue::Type::string) {
        fail(std::string(context) + " must be a string");
    }
    return value.as_string();
}

std::uint64_t unsigned_value(const JsonValue &value, std::string_view context) {
    if (value.type() != JsonValue::Type::number) {
        fail(std::string(context) + " must be an unsigned integer");
    }
    const std::string &text = value.as_number();
    if (text.empty() || text.front() == '-' ||
        text.find_first_of(".eE") != std::string::npos) {
        fail(std::string(context) + " must be an unsigned integer");
    }
    std::uint64_t parsed = 0;
    const auto result =
        std::from_chars(text.data(), text.data() + text.size(), parsed);
    if (result.ec != std::errc{} || result.ptr != text.data() + text.size()) {
        fail(std::string(context) + " is outside the supported range");
    }
    return parsed;
}

std::uint32_t u32_value(const JsonValue &value, std::string_view context) {
    const std::uint64_t parsed = unsigned_value(value, context);
    if (parsed > std::numeric_limits<std::uint32_t>::max()) {
        fail(std::string(context) + " is outside the 32-bit range");
    }
    return static_cast<std::uint32_t>(parsed);
}

bool is_hex_string(std::string_view text, std::size_t length) {
    if (text.size() != length)
        return false;
    return std::all_of(text.begin(), text.end(), [](char character) {
        return (character >= '0' && character <= '9') ||
               (character >= 'a' && character <= 'f') ||
               (character >= 'A' && character <= 'F');
    });
}

std::uint32_t hex_address(const JsonValue &value, std::string_view context) {
    const std::string &text = string_value(value, context);
    if (text.size() != 10U || text[0] != '0' || text[1] != 'x' ||
        !is_hex_string(std::string_view(text).substr(2U), 8U)) {
        fail(std::string(context) + " must be a canonical 32-bit hex address");
    }
    std::uint32_t parsed = 0;
    const auto result = std::from_chars(text.data() + 2U,
                                        text.data() + text.size(), parsed, 16);
    if (result.ec != std::errc{} || result.ptr != text.data() + text.size()) {
        fail(std::string(context) + " has an invalid address");
    }
    return parsed;
}

std::uint64_t hex_range_end(const JsonValue &value, std::string_view context) {
    const std::string &text = string_value(value, context);
    if ((text.size() != 10U && text.size() != 11U) || text[0] != '0' ||
        text[1] != 'x' ||
        !is_hex_string(std::string_view(text).substr(2U), text.size() - 2U)) {
        fail(std::string(context) + " must be a canonical hex address");
    }
    std::uint64_t parsed = 0;
    const auto result = std::from_chars(text.data() + 2U,
                                        text.data() + text.size(), parsed, 16);
    if (result.ec != std::errc{} || result.ptr != text.data() + text.size() ||
        parsed > UINT64_C(0x100000000)) {
        fail(std::string(context) + " has an invalid address");
    }
    return parsed;
}

std::string read_manifest(const std::filesystem::path &path) {
    const HANDLE raw = CreateFileW(
        path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
    if (raw == INVALID_HANDLE_VALUE)
        fail("manifest cannot be opened");
    const UniqueFile file(raw);
    LARGE_INTEGER length{};
    if (GetFileSizeEx(raw, &length) == FALSE || length.QuadPart <= 0 ||
        static_cast<std::uint64_t>(length.QuadPart) > kMaximumManifestBytes) {
        fail("manifest size is invalid");
    }
    std::string text(static_cast<std::size_t>(length.QuadPart), '\0');
    std::size_t offset = 0U;
    while (offset < text.size()) {
        const DWORD request = static_cast<DWORD>(
            std::min<std::size_t>(text.size() - offset, 64U * 1024U));
        DWORD bytes_read = 0U;
        if (ReadFile(raw, text.data() + offset, request, &bytes_read,
                     nullptr) == FALSE ||
            bytes_read != request) {
            fail("manifest cannot be read");
        }
        offset += bytes_read;
    }
    return text;
}

std::wstring wide_from_utf8(std::string_view text) {
    if (text.empty() || text.size() > static_cast<std::size_t>(
                                          std::numeric_limits<int>::max())) {
        fail("module path encoding is invalid");
    }
    const int needed =
        MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                            static_cast<int>(text.size()), nullptr, 0);
    if (needed <= 0)
        fail("module path encoding is invalid");
    std::wstring result(static_cast<std::size_t>(needed), L'\0');
    const int converted = MultiByteToWideChar(
        CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
        static_cast<int>(text.size()), result.data(), needed);
    if (converted != needed)
        fail("module path encoding is invalid");
    return result;
}

void validate_relative_path(std::string_view path, std::size_t module_index) {
    const std::string prefix = "module[" + std::to_string(module_index) + "]";
    if (path.empty() || path.front() == '/' || path.front() == '\\' ||
        path.find('\\') != std::string_view::npos ||
        path.find(':') != std::string_view::npos ||
        path.find('\0') != std::string_view::npos) {
        fail(prefix + " path is not a normalized relative path");
    }
    std::size_t begin = 0U;
    while (begin <= path.size()) {
        const std::size_t end = path.find('/', begin);
        const std::string_view component = path.substr(
            begin,
            end == std::string_view::npos ? path.size() - begin : end - begin);
        if (component.empty() || component == "." || component == "..") {
            fail(prefix + " path contains traversal or an empty component");
        }
        if (std::any_of(component.begin(), component.end(),
                        [](unsigned char value) {
                            return value < 0x20U || value == 0x7FU;
                        })) {
            fail(prefix + " path contains a control character");
        }
        if (end == std::string_view::npos)
            break;
        begin = end + 1U;
    }
}

std::filesystem::path final_path(HANDLE handle) {
    const DWORD required =
        GetFinalPathNameByHandleW(handle, nullptr, 0, FILE_NAME_NORMALIZED);
    if (required == 0U)
        fail("content path canonicalization failed");
    std::wstring buffer(static_cast<std::size_t>(required), L'\0');
    const DWORD written = GetFinalPathNameByHandleW(
        handle, buffer.data(), required, FILE_NAME_NORMALIZED);
    if (written == 0U || written >= required) {
        fail("content path canonicalization failed");
    }
    buffer.resize(written);
    return std::filesystem::path(buffer);
}

bool path_beneath(const std::filesystem::path &candidate,
                  const std::filesystem::path &root) {
    std::wstring candidate_text = candidate.native();
    std::wstring root_text = root.native();
    auto normalize = [](std::wstring &value) {
        std::replace(value.begin(), value.end(), L'/', L'\\');
        while (value.size() > 1U && value.back() == L'\\')
            value.pop_back();
        std::transform(
            value.begin(), value.end(), value.begin(), [](wchar_t character) {
                return static_cast<wchar_t>(std::towlower(character));
            });
    };
    normalize(candidate_text);
    normalize(root_text);
    if (candidate_text == root_text)
        return true;
    return candidate_text.size() > root_text.size() &&
           candidate_text.compare(0U, root_text.size(), root_text) == 0 &&
           candidate_text[root_text.size()] == L'\\';
}

std::filesystem::path
canonical_content_root(const std::filesystem::path &root) {
    const DWORD attributes = GetFileAttributesW(root.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0U) {
        fail("content root does not exist or is not a directory");
    }
    if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0U) {
        fail("content root must not be a reparse point");
    }
    const HANDLE raw = CreateFileW(
        root.c_str(), FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
        OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
    if (raw == INVALID_HANDLE_VALUE) {
        fail("content root cannot be opened safely");
    }
    const UniqueFile handle(raw);
    return final_path(raw);
}

void reject_reparse_components(const std::filesystem::path &root,
                               const std::filesystem::path &relative,
                               std::size_t module_index) {
    std::filesystem::path current = root;
    for (const auto &component : relative) {
        current /= component;
        const DWORD attributes = GetFileAttributesW(current.c_str());
        if (attributes == INVALID_FILE_ATTRIBUTES) {
            fail("module[" + std::to_string(module_index) + "] is missing");
        }
        if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0U) {
            fail("module[" + std::to_string(module_index) +
                 "] traverses a reparse point");
        }
    }
}

std::uint16_t read_u16(const std::byte *bytes) {
    return static_cast<std::uint16_t>(std::to_integer<std::uint8_t>(bytes[0])) |
           static_cast<std::uint16_t>(std::to_integer<std::uint8_t>(bytes[1])
                                      << 8U);
}

std::uint32_t read_u32(const std::byte *bytes) {
    return static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(bytes[0])) |
           (static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(bytes[1]))
            << 8U) |
           (static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(bytes[2]))
            << 16U) |
           (static_cast<std::uint32_t>(std::to_integer<std::uint8_t>(bytes[3]))
            << 24U);
}

void read_exact(HANDLE file, std::uint64_t offset,
                std::span<std::byte> destination, std::size_t module_index) {
    LARGE_INTEGER position{};
    position.QuadPart = static_cast<LONGLONG>(offset);
    if (offset >
            static_cast<std::uint64_t>(std::numeric_limits<LONGLONG>::max()) ||
        SetFilePointerEx(file, position, nullptr, FILE_BEGIN) == FALSE) {
        fail("module[" + std::to_string(module_index) + "] has invalid bounds");
    }
    if (destination.size() >
        static_cast<std::size_t>(std::numeric_limits<DWORD>::max())) {
        fail("module[" + std::to_string(module_index) + "] has invalid bounds");
    }
    DWORD bytes_read = 0;
    if (ReadFile(file, destination.data(),
                 static_cast<DWORD>(destination.size()), &bytes_read,
                 nullptr) == FALSE ||
        bytes_read != destination.size()) {
        fail("module[" + std::to_string(module_index) +
             "] is truncated or unreadable");
    }
}

std::vector<std::uint8_t> read_module_bytes(HANDLE file, std::uint64_t size,
                                            std::size_t module_index) {
    if (size > std::numeric_limits<std::size_t>::max()) {
        fail("module[" + std::to_string(module_index) + "] is too large");
    }
    std::vector<std::uint8_t> bytes(static_cast<std::size_t>(size));
    LARGE_INTEGER beginning{};
    if (SetFilePointerEx(file, beginning, nullptr, FILE_BEGIN) == FALSE) {
        fail("module[" + std::to_string(module_index) +
             "] cannot be read safely");
    }
    std::size_t offset = 0U;
    while (offset < bytes.size()) {
        const DWORD request = static_cast<DWORD>(
            std::min<std::size_t>(bytes.size() - offset, 64U * 1024U));
        DWORD bytes_read = 0U;
        if (ReadFile(file, bytes.data() + offset, request, &bytes_read,
                     nullptr) == FALSE ||
            bytes_read != request) {
            fail("module[" + std::to_string(module_index) +
                 "] is truncated or unreadable");
        }
        offset += bytes_read;
    }
    return bytes;
}

void validate_elf(HANDLE file, ModuleRecord &module, std::size_t module_index) {
    std::array<std::byte, 52> header{};
    read_exact(file, 0U, header, module_index);
    const bool ready_elf = std::to_integer<std::uint8_t>(header[0]) == 0x7FU &&
                           std::to_integer<std::uint8_t>(header[1]) == 'E' &&
                           std::to_integer<std::uint8_t>(header[2]) == 'L' &&
                           std::to_integer<std::uint8_t>(header[3]) == 'F' &&
                           std::to_integer<std::uint8_t>(header[4]) == 1U &&
                           std::to_integer<std::uint8_t>(header[5]) == 1U &&
                           std::to_integer<std::uint8_t>(header[6]) == 1U;
    if (!ready_elf) {
        fail("module[" + std::to_string(module_index) +
             "] is protected or not a ready ELF32 image");
    }
    const std::uint16_t elf_type = read_u16(header.data() + 16U);
    const std::uint16_t machine = read_u16(header.data() + 18U);
    const std::uint32_t version = read_u32(header.data() + 20U);
    const std::uint32_t entry = read_u32(header.data() + 24U);
    const std::uint32_t program_offset = read_u32(header.data() + 28U);
    const std::uint32_t elf_flags = read_u32(header.data() + 36U);
    const std::uint16_t header_size = read_u16(header.data() + 40U);
    const std::uint16_t program_size = read_u16(header.data() + 42U);
    const std::uint16_t program_count = read_u16(header.data() + 44U);
    if ((elf_type != 2U && elf_type != 0xFE00U && elf_type != 0xFE04U) ||
        machine != 40U || version != 1U || header_size != 52U ||
        program_size != 32U || program_count != module.program_header_count ||
        entry != module.encoded_entry) {
        fail("module[" + std::to_string(module_index) +
             "] ELF metadata does not match the manifest");
    }
    module.elf_type = elf_type;
    module.machine = machine;
    module.elf_flags = elf_flags;
    const std::uint64_t table_end =
        static_cast<std::uint64_t>(program_offset) +
        static_cast<std::uint64_t>(program_size) * program_count;
    if (program_count == 0U || table_end > module.file_size) {
        fail("module[" + std::to_string(module_index) +
             "] program-header table is invalid");
    }

    std::size_t load_count = 0U;
    for (std::uint32_t index = 0U; index < program_count; ++index) {
        std::array<std::byte, 32> program{};
        read_exact(file,
                   static_cast<std::uint64_t>(program_offset) +
                       static_cast<std::uint64_t>(index) * 32U,
                   program, module_index);
        if (read_u32(program.data()) != 1U)
            continue;
        const auto listed = std::find_if(
            module.segments.begin(), module.segments.end(),
            [&](const Segment &segment) { return segment.index == index; });
        if (listed == module.segments.end()) {
            fail("module[" + std::to_string(module_index) +
                 "] has an unlisted load segment");
        }
        ++load_count;
        const Segment &segment = *listed;
        const std::uint32_t file_offset = read_u32(program.data() + 4U);
        const std::uint32_t virtual_address = read_u32(program.data() + 8U);
        const std::uint32_t physical_address = read_u32(program.data() + 12U);
        const std::uint32_t file_size = read_u32(program.data() + 16U);
        const std::uint32_t memory_size = read_u32(program.data() + 20U);
        const std::uint32_t flags = read_u32(program.data() + 24U);
        const std::uint32_t alignment = read_u32(program.data() + 28U);
        if (segment.index != index || segment.file_offset != file_offset ||
            segment.virtual_address != virtual_address ||
            segment.file_size != file_size ||
            segment.memory_size != memory_size || segment.flags != flags ||
            segment.alignment != alignment) {
            fail("module[" + std::to_string(module_index) +
                 "] load segment does not match the ELF");
        }
        listed->physical_address = physical_address;
    }
    if (load_count != module.segments.size()) {
        fail("module[" + std::to_string(module_index) +
             "] manifest contains a nonexistent load segment");
    }

    if (module.module_info_segment_index >= program_count) {
        fail("module[" + std::to_string(module_index) +
             "] module-info selector is invalid");
    }
    const auto selected = std::find_if(
        module.segments.begin(), module.segments.end(),
        [&](const Segment &segment) {
            return segment.index == module.module_info_segment_index;
        });
    if (selected == module.segments.end() || (selected->flags & 1U) == 0U ||
        module.module_info_segment_offset + 0x5CU > selected->file_size) {
        fail("module[" + std::to_string(module_index) +
             "] module-info bounds are invalid");
    }
    const std::uint64_t expected_virtual =
        static_cast<std::uint64_t>(selected->virtual_address) +
        module.module_info_segment_offset;
    if (expected_virtual != module.module_info_virtual_address ||
        (module.encoded_entry >> 30U) != module.module_info_segment_index ||
        (module.encoded_entry & UINT32_C(0x3fffffff)) !=
            module.module_info_segment_offset) {
        fail("module[" + std::to_string(module_index) +
             "] module-info address is inconsistent");
    }
    std::array<std::byte, 0x5C> module_info{};
    read_exact(file, selected->file_offset + module.module_info_segment_offset,
               module_info, module_index);
    if ((read_u16(module_info.data() + 2U) >> 8U) != 1U) {
        fail("module[" + std::to_string(module_index) +
             "] module-info version is invalid");
    }
    std::size_t name_length = 0U;
    while (name_length < 27U &&
           std::to_integer<std::uint8_t>(module_info[4U + name_length]) != 0U) {
        const auto character =
            std::to_integer<std::uint8_t>(module_info[4U + name_length]);
        if (character < 0x20U || character > 0x7EU) {
            fail("module[" + std::to_string(module_index) +
                 "] module-info name is invalid");
        }
        ++name_length;
    }
    const std::string actual_name(
        reinterpret_cast<const char *>(module_info.data() + 4U), name_length);
    if (actual_name.empty() || actual_name != module.module_name) {
        fail("module[" + std::to_string(module_index) +
             "] module-info name does not match the manifest");
    }
}

Segment parse_segment(const JsonValue &value, std::size_t module_index,
                      std::size_t segment_index) {
    const std::string context = "module[" + std::to_string(module_index) +
                                "].loadSegments[" +
                                std::to_string(segment_index) + "]";
    const auto &object = object_value(value, context);
    require_keys(object,
                 {"index", "fileOffset", "fileSize", "virtualAddress",
                  "memorySize", "rangeEndExclusive", "flags", "alignment"},
                 context);
    Segment segment;
    segment.index = u32_value(member(object, "index", context), context);
    segment.file_offset =
        unsigned_value(member(object, "fileOffset", context), context);
    segment.file_size =
        unsigned_value(member(object, "fileSize", context), context);
    segment.virtual_address =
        hex_address(member(object, "virtualAddress", context), context);
    segment.memory_size =
        unsigned_value(member(object, "memorySize", context), context);
    segment.end =
        hex_range_end(member(object, "rangeEndExclusive", context), context);
    const std::string &flags =
        string_value(member(object, "flags", context), context);
    if (flags.size() != 3U || (flags[0] != 'r' && flags[0] != '-') ||
        (flags[1] != 'w' && flags[1] != '-') ||
        (flags[2] != 'x' && flags[2] != '-')) {
        fail(context + " has invalid segment flags");
    }
    segment.flags = (flags[0] == 'r' ? 4U : 0U) | (flags[1] == 'w' ? 2U : 0U) |
                    (flags[2] == 'x' ? 1U : 0U);
    segment.alignment =
        unsigned_value(member(object, "alignment", context), context);

    if (segment.file_size > segment.memory_size ||
        segment.file_offset + segment.file_size < segment.file_offset ||
        segment.file_offset + segment.file_size >
            std::numeric_limits<std::uint32_t>::max() + UINT64_C(1)) {
        fail(context + " has invalid file bounds");
    }
    const std::uint64_t expected_end =
        static_cast<std::uint64_t>(segment.virtual_address) +
        segment.memory_size;
    if (expected_end > UINT64_C(0x100000000) || expected_end != segment.end) {
        fail(context + " has invalid virtual bounds");
    }
    if (segment.alignment > 1U &&
        ((segment.alignment & (segment.alignment - 1U)) != 0U ||
         segment.virtual_address % segment.alignment !=
             segment.file_offset % segment.alignment)) {
        fail(context + " has invalid alignment");
    }
    if ((segment.flags & 1U) != 0U && segment.file_size == 0U) {
        fail(context + " has an empty executable range");
    }
    return segment;
}

ModuleRecord parse_module(const JsonValue &value, std::size_t module_index) {
    const std::string context = "module[" + std::to_string(module_index) + "]";
    const auto &object = object_value(value, context);
    require_keys(object,
                 {"path", "sha256", "fileSize", "moduleInfo",
                  "programHeaderCount", "loadSegments"},
                 context);

    ModuleRecord module;
    module.relative_path =
        string_value(member(object, "path", context), context);
    validate_relative_path(module.relative_path, module_index);
    module.expected_hash =
        string_value(member(object, "sha256", context), context);
    if (!is_hex_string(module.expected_hash, 64U)) {
        fail(context + " SHA-256 is invalid");
    }
    std::transform(module.expected_hash.begin(), module.expected_hash.end(),
                   module.expected_hash.begin(), [](unsigned char value) {
                       return static_cast<char>(std::tolower(value));
                   });
    module.file_size =
        unsigned_value(member(object, "fileSize", context), context);
    if (module.file_size < 52U ||
        module.file_size > std::numeric_limits<std::uint32_t>::max()) {
        fail(context + " file size is invalid");
    }
    module.program_header_count =
        u32_value(member(object, "programHeaderCount", context), context);
    if (module.program_header_count == 0U ||
        module.program_header_count > 4096U) {
        fail(context + " program-header count is invalid");
    }

    const auto &info = object_value(member(object, "moduleInfo", context),
                                    context + ".moduleInfo");
    require_keys(info,
                 {"name", "encodedEntry", "segmentIndex", "segmentOffset",
                  "virtualAddress"},
                 context + ".moduleInfo");
    module.module_name = string_value(member(info, "name", context), context);
    if (module.module_name.empty() || module.module_name.size() > 27U ||
        std::any_of(module.module_name.begin(), module.module_name.end(),
                    [](unsigned char value) {
                        return value < 0x20U || value > 0x7EU;
                    })) {
        fail(context + " module-info name is invalid");
    }
    module.encoded_entry =
        hex_address(member(info, "encodedEntry", context), context);
    module.module_info_segment_index =
        u32_value(member(info, "segmentIndex", context), context);
    module.module_info_segment_offset =
        unsigned_value(member(info, "segmentOffset", context), context);
    module.module_info_virtual_address =
        hex_address(member(info, "virtualAddress", context), context);

    const auto &segments = array_value(member(object, "loadSegments", context),
                                       context + ".loadSegments");
    if (segments.empty() || segments.size() > kMaximumSegmentsPerModule) {
        fail(context + " load-segment count is invalid");
    }
    bool executable = false;
    for (std::size_t index = 0U; index < segments.size(); ++index) {
        Segment segment = parse_segment(segments[index], module_index, index);
        if (segment.file_offset + segment.file_size > module.file_size) {
            fail(context + " load segment extends beyond the module");
        }
        executable = executable || (segment.flags & 1U) != 0U;
        module.segments.push_back(segment);
    }
    if (!executable)
        fail(context + " has no executable load segment");
    return module;
}

void validate_top_level(const JsonValue::Object &root,
                        std::vector<ModuleRecord> &modules) {
    require_keys(root,
                 {"schemaVersion", "titleId", "sourceArchive", "vita3k",
                  "imageFormat", "modules"},
                 "manifest");
    if (unsigned_value(member(root, "schemaVersion", "manifest"),
                       "schemaVersion") != 1U) {
        fail("manifest schema version is unsupported");
    }
    const std::string &title =
        string_value(member(root, "titleId", "manifest"), "titleId");
    if (title != game::kTitleId)
        fail("manifest title ID is incorrect");

    const auto &source = object_value(member(root, "sourceArchive", "manifest"),
                                      "sourceArchive");
    require_keys(source, {"path", "sha256"}, "sourceArchive");
    if (string_value(member(source, "path", "sourceArchive"),
                     "sourceArchive.path")
            .empty()) {
        fail("sourceArchive.path must not be empty");
    }
    const std::string &archive_hash = string_value(
        member(source, "sha256", "sourceArchive"), "sourceArchive.sha256");
    if (!is_hex_string(archive_hash, 64U)) {
        fail("sourceArchive.sha256 is invalid");
    }

    const auto &vita3k =
        object_value(member(root, "vita3k", "manifest"), "vita3k");
    require_keys(vita3k, {"sourceRevision", "dumpCapability"}, "vita3k");
    const std::string &revision = string_value(
        member(vita3k, "sourceRevision", "vita3k"), "vita3k.sourceRevision");
    if (revision.size() < 7U || revision.size() > 40U ||
        !is_hex_string(revision, revision.size())) {
        fail("vita3k.sourceRevision is invalid");
    }
    if (string_value(member(vita3k, "dumpCapability", "vita3k"),
                     "vita3k.dumpCapability") != "--dump-elfs") {
        fail("manifest dump capability is unsupported");
    }

    const auto &format =
        object_value(member(root, "imageFormat", "manifest"), "imageFormat");
    require_keys(format, {"elfClass", "byteOrder", "machine"}, "imageFormat");
    if (string_value(member(format, "elfClass", "imageFormat"), "elfClass") !=
            "ELF32" ||
        string_value(member(format, "byteOrder", "imageFormat"), "byteOrder") !=
            "little-endian" ||
        string_value(member(format, "machine", "imageFormat"), "machine") !=
            "ARM") {
        fail("manifest image format is protected, unsupported, or not ready");
    }

    const auto &module_values =
        array_value(member(root, "modules", "manifest"), "modules");
    if (module_values.empty() || module_values.size() > kMaximumModules) {
        fail("manifest module count is invalid");
    }
    std::set<std::string, std::less<>> paths;
    std::string previous;
    for (std::size_t index = 0U; index < module_values.size(); ++index) {
        ModuleRecord module = parse_module(module_values[index], index);
        if (!paths.emplace(module.relative_path).second) {
            fail("manifest contains a duplicate module path");
        }
        if (index != 0U && module.relative_path <= previous) {
            fail("manifest module order is not deterministic");
        }
        previous = module.relative_path;
        modules.push_back(std::move(module));
    }
}

UniqueFile open_module(const std::filesystem::path &canonical_root,
                       const ModuleRecord &module, std::size_t module_index) {
    const std::filesystem::path relative(wide_from_utf8(module.relative_path));
    reject_reparse_components(canonical_root, relative, module_index);
    const std::filesystem::path candidate = canonical_root / relative;
    const HANDLE raw =
        CreateFileW(candidate.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                    OPEN_EXISTING,
                    FILE_ATTRIBUTE_NORMAL | FILE_FLAG_RANDOM_ACCESS, nullptr);
    if (raw == INVALID_HANDLE_VALUE) {
        fail("module[" + std::to_string(module_index) + "] cannot be opened");
    }
    UniqueFile file(raw);
    const std::filesystem::path final = final_path(raw);
    if (!path_beneath(final, canonical_root)) {
        fail("module[" + std::to_string(module_index) +
             "] resolves outside the content root");
    }
    BY_HANDLE_FILE_INFORMATION information{};
    if (GetFileInformationByHandle(raw, &information) == FALSE ||
        (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0U ||
        (information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0U) {
        fail("module[" + std::to_string(module_index) +
             "] is not a plain file");
    }
    const std::uint64_t size =
        (static_cast<std::uint64_t>(information.nFileSizeHigh) << 32U) |
        information.nFileSizeLow;
    if (size != module.file_size) {
        fail("module[" + std::to_string(module_index) +
             "] size changed after manifest creation");
    }
    return file;
}

void validate_ranges(const std::vector<ModuleRecord> &modules,
                     std::size_t &segment_count,
                     std::vector<game::GuestLoadRange> &validated_ranges) {
    std::vector<AddressRange> ranges;
    for (std::size_t module_index = 0U; module_index < modules.size();
         ++module_index) {
        const auto &segments = modules[module_index].segments;
        segment_count += segments.size();
        for (const Segment &segment : segments) {
            if (segment.memory_size == 0U)
                continue;
            ranges.push_back(AddressRange{
                segment.virtual_address,
                segment.end,
                module_index,
                segment.index,
            });
        }
    }
    std::sort(ranges.begin(), ranges.end(),
              [](const AddressRange &left, const AddressRange &right) {
                  if (left.start != right.start)
                      return left.start < right.start;
                  if (left.end != right.end)
                      return left.end < right.end;
                  if (left.module_index != right.module_index) {
                      return left.module_index < right.module_index;
                  }
                  return left.segment_index < right.segment_index;
              });
    for (std::size_t index = 1U; index < ranges.size(); ++index) {
        if (ranges[index].start < ranges[index - 1U].end) {
            fail("manifest contains overlapping runtime ranges");
        }
    }
    validated_ranges.reserve(ranges.size());
    for (const AddressRange &range : ranges) {
        const std::uint64_t size = range.end - range.start;
        if (range.start > std::numeric_limits<std::uint32_t>::max() ||
            size > std::numeric_limits<std::uint32_t>::max()) {
            fail("manifest runtime range cannot be represented");
        }
        validated_ranges.push_back(game::GuestLoadRange{
            static_cast<std::uint32_t>(range.start),
            static_cast<std::uint32_t>(size),
        });
    }
}

} // namespace

std::string_view ValidatedModule::relative_path() const noexcept {
    return relative_path_;
}

std::string_view ValidatedModule::module_name() const noexcept {
    return module_name_;
}

std::uint16_t ValidatedModule::elf_type() const noexcept { return elf_type_; }

std::uint16_t ValidatedModule::machine() const noexcept { return machine_; }

std::uint32_t ValidatedModule::entry() const noexcept { return entry_; }

std::uint32_t ValidatedModule::elf_flags() const noexcept { return elf_flags_; }

std::uint16_t ValidatedModule::program_header_count() const noexcept {
    return program_header_count_;
}

std::span<const ValidatedSegment> ValidatedModule::segments() const noexcept {
    return segments_;
}

std::span<const std::uint8_t> ValidatedModule::bytes() const noexcept {
    return bytes_;
}

const std::filesystem::path &ValidatedContent::canonical_root() const noexcept {
    return canonical_root_;
}

const Sha256Digest &ValidatedContent::manifest_identity() const noexcept {
    return manifest_identity_;
}

std::span<const ValidatedModule> ValidatedContent::modules() const noexcept {
    return modules_;
}

std::size_t ValidatedContent::module_count() const noexcept {
    return modules_.size();
}

std::size_t ValidatedContent::load_segment_count() const noexcept {
    return load_segment_count_;
}

std::span<const game::GuestLoadRange>
ValidatedContent::load_ranges() const noexcept {
    return load_ranges_;
}

ValidatedContent
validate_content_manifest(const std::filesystem::path &manifest_path,
                          const std::filesystem::path &content_root) {
    const std::string text = read_manifest(manifest_path);
    JsonValue document;
    try {
        document = parse_json(text);
    } catch (const JsonError &error) {
        throw ManifestError(error.what());
    }
    const auto &root = object_value(document, "manifest");
    std::vector<ModuleRecord> modules;
    validate_top_level(root, modules);

    ValidatedContent result;
    result.canonical_root_ = canonical_content_root(content_root);
    result.manifest_identity_ = sha256_bytes(std::span<const std::uint8_t>(
        reinterpret_cast<const std::uint8_t *>(text.data()), text.size()));
    validate_ranges(modules, result.load_segment_count_, result.load_ranges_);
    result.modules_.reserve(modules.size());

    for (std::size_t index = 0U; index < modules.size(); ++index) {
        ModuleRecord &module = modules[index];
        UniqueFile file = open_module(result.canonical_root_, module, index);
        validate_elf(static_cast<HANDLE>(file.get()), module, index);
        module.bytes = read_module_bytes(static_cast<HANDLE>(file.get()),
                                         module.file_size, index);
        const std::string actual_hash = sha256_hex(sha256_bytes(module.bytes));
        unsigned difference = 0U;
        for (std::size_t offset = 0U; offset < actual_hash.size(); ++offset) {
            difference |= static_cast<unsigned>(
                static_cast<unsigned char>(actual_hash[offset]) ^
                static_cast<unsigned char>(module.expected_hash[offset]));
        }
        if (difference != 0U) {
            fail("module[" + std::to_string(index) +
                 "] hash changed after manifest creation");
        }

        ValidatedModule validated;
        validated.relative_path_ = std::move(module.relative_path);
        validated.module_name_ = std::move(module.module_name);
        validated.elf_type_ = module.elf_type;
        validated.machine_ = module.machine;
        validated.entry_ = module.encoded_entry;
        validated.elf_flags_ = module.elf_flags;
        if (module.program_header_count >
            std::numeric_limits<std::uint16_t>::max()) {
            fail("module[" + std::to_string(index) +
                 "] program-header count cannot be represented");
        }
        validated.program_header_count_ =
            static_cast<std::uint16_t>(module.program_header_count);
        validated.segments_.reserve(module.segments.size());
        for (const Segment &segment : module.segments) {
            validated.segments_.push_back(ValidatedSegment{
                .program_header_index = segment.index,
                .file_offset = static_cast<std::uint32_t>(segment.file_offset),
                .virtual_address = segment.virtual_address,
                .physical_address = segment.physical_address,
                .file_size = static_cast<std::uint32_t>(segment.file_size),
                .memory_size = static_cast<std::uint32_t>(segment.memory_size),
                .flags = segment.flags,
                .alignment = static_cast<std::uint32_t>(segment.alignment),
            });
        }
        validated.bytes_ = std::move(module.bytes);
        result.modules_.push_back(std::move(validated));
    }
    return result;
}

} // namespace kzm::host
