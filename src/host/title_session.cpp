// SPDX-License-Identifier: GPL-2.0-or-later
#include "host/title_session.hpp"

#include "game/title_config.hpp"
#include "host/runtime_session.hpp"

#include "vitarecomp/binding.h"
#include "vitarecomp/cpu.h"
#include "vitarecomp/host.h"
#include "vitarecomp/loader.h"
#include "vitarecomp/reloc.h"
#include "vitarecomp/runtime.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cstddef>
#include <cstring>
#include <limits>
#include <optional>
#include <span>
#include <string>
#include <utility>
#include <vector>

namespace kzm::host {
namespace {

constexpr std::uint32_t kIndexNone = UINT32_MAX;
constexpr std::uint32_t kPtLoad = 1U;
constexpr std::uint32_t kModuleInfoSize = 0x5CU;
constexpr std::size_t kMaximumMetadataRecords = 1U << 20U;

void copy_strict_name(
    const char *source,
    std::array<char, TitleCallResult::strict_name_capacity> &destination)
    noexcept {
    destination.fill('\0');
    if (source == nullptr)
        return;
    for (std::size_t index = 0U; index + 1U < destination.size() &&
                                source[index] != '\0';
         ++index) {
        const unsigned char character =
            static_cast<unsigned char>(source[index]);
        destination[index] =
            character >= 0x20U && character <= 0x7EU &&
                    character != static_cast<unsigned char>('/') &&
                    character != static_cast<unsigned char>('\\')
                ? static_cast<char>(character)
                : '_';
    }
}

#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
std::atomic<int> g_forced_preparation_failure{-1};
#endif

class ParseFailure final {
  public:
    ParseFailure(vita_loader_status status,
                 std::uint32_t record_index = kIndexNone,
                 std::uint32_t program_header_index = kIndexNone)
        : status(status), record_index(record_index),
          program_header_index(program_header_index) {}

    vita_loader_status status;
    std::uint32_t record_index;
    std::uint32_t program_header_index;
};

std::uint16_t
read_u16(std::span<const std::uint8_t> bytes, std::size_t offset,
         vita_loader_status status = VITA_LOADER_ERROR_MODULE_INFO) {
    if (offset > bytes.size() || bytes.size() - offset < 2U) {
        throw ParseFailure(status);
    }
    return static_cast<std::uint16_t>(bytes[offset]) |
           static_cast<std::uint16_t>(
               static_cast<std::uint16_t>(bytes[offset + 1U]) << 8U);
}

std::uint32_t
read_u32(std::span<const std::uint8_t> bytes, std::size_t offset,
         vita_loader_status status = VITA_LOADER_ERROR_MODULE_INFO) {
    if (offset > bytes.size() || bytes.size() - offset < 4U) {
        throw ParseFailure(status);
    }
    return static_cast<std::uint32_t>(bytes[offset]) |
           (static_cast<std::uint32_t>(bytes[offset + 1U]) << 8U) |
           (static_cast<std::uint32_t>(bytes[offset + 2U]) << 16U) |
           (static_cast<std::uint32_t>(bytes[offset + 3U]) << 24U);
}

struct ResolvedBytes {
    std::size_t file_offset;
    std::uint32_t address;
};

ResolvedBytes
resolve_virtual(const ValidatedModule &module, std::uint32_t address,
                std::uint32_t size,
                vita_loader_status status = VITA_LOADER_ERROR_MODULE_INFO) {
    const std::uint64_t end = static_cast<std::uint64_t>(address) + size;
    if (end > UINT64_C(0x100000000)) {
        throw ParseFailure(status);
    }
    for (const ValidatedSegment &segment : module.segments()) {
        const std::uint64_t segment_file_end =
            static_cast<std::uint64_t>(segment.virtual_address) +
            segment.file_size;
        if (address < segment.virtual_address || end > segment_file_end) {
            continue;
        }
        const std::uint64_t file_offset =
            static_cast<std::uint64_t>(segment.file_offset) +
            (address - segment.virtual_address);
        if (file_offset > module.bytes().size() ||
            module.bytes().size() - static_cast<std::size_t>(file_offset) <
                size) {
            throw ParseFailure(status);
        }
        return ResolvedBytes{
            static_cast<std::size_t>(file_offset),
            address,
        };
    }
    throw ParseFailure(status);
}

const ValidatedSegment &segment_for_selector(
    const ValidatedModule &module, std::uint32_t encoded,
    vita_loader_status status = VITA_LOADER_ERROR_MODULE_INFO) {
    const std::uint32_t selector = encoded >> 30U;
    const auto found =
        std::find_if(module.segments().begin(), module.segments().end(),
                     [selector](const ValidatedSegment &segment) {
                         return segment.program_header_index == selector;
                     });
    if (found == module.segments().end()) {
        throw ParseFailure(status);
    }
    return *found;
}

std::uint32_t
encoded_address(const ValidatedModule &module, std::uint32_t encoded,
                std::uint32_t size,
                vita_loader_status status = VITA_LOADER_ERROR_MODULE_INFO) {
    const ValidatedSegment &segment =
        segment_for_selector(module, encoded, status);
    const std::uint32_t offset = encoded & UINT32_C(0x3fffffff);
    const std::uint32_t aligned_offset = offset & ~UINT32_C(1);
    if (aligned_offset > segment.memory_size ||
        size > segment.memory_size - aligned_offset ||
        segment.virtual_address >
            std::numeric_limits<std::uint32_t>::max() - offset) {
        throw ParseFailure(status);
    }
    return segment.virtual_address + offset;
}

std::size_t relative_file_offset(
    const ValidatedModule &module, const ValidatedSegment &segment,
    std::uint32_t relative, std::uint32_t size,
    vita_loader_status status = VITA_LOADER_ERROR_MODULE_INFO) {
    if (relative > segment.file_size || size > segment.file_size - relative) {
        throw ParseFailure(status);
    }
    const std::uint64_t file_offset =
        static_cast<std::uint64_t>(segment.file_offset) + relative;
    if (file_offset > module.bytes().size() ||
        module.bytes().size() - static_cast<std::size_t>(file_offset) < size) {
        throw ParseFailure(status);
    }
    return static_cast<std::size_t>(file_offset);
}

std::uint32_t checked_record_count(
    std::uint32_t left, std::uint32_t middle, std::uint32_t right,
    vita_loader_status status = VITA_LOADER_ERROR_MODULE_INFO) {
    const std::uint64_t count =
        static_cast<std::uint64_t>(left) + middle + right;
    if (count > kMaximumMetadataRecords) {
        throw ParseFailure(status);
    }
    return static_cast<std::uint32_t>(count);
}

struct ParsedPostLink {
    std::vector<vita_binding_export_metadata> exports;
    std::vector<vita_binding_function_import_metadata> function_imports;
    std::vector<std::vector<vita_var_site>> variable_sites;
    std::vector<vita_binding_variable_import_metadata> variable_imports;
    std::uint32_t module_start = UINT32_MAX;
    std::uint32_t tls_start = 0U;
    std::uint32_t tls_file_size = 0U;
    std::uint32_t tls_memory_size = 0U;
};

struct ModuleState {
    const ValidatedModule *content = nullptr;
    const vita_generated_module_descriptor *generated = nullptr;
    std::vector<vita_loader_segment_metadata> loader_segments;
    vita_loader_module_metadata loader_metadata{};
    ParsedPostLink parsed;
    vita_binding_module_metadata post_link{};

    void refresh_views() noexcept {
        post_link.exports =
            parsed.exports.empty() ? nullptr : parsed.exports.data();
        post_link.export_count =
            static_cast<std::uint32_t>(parsed.exports.size());
        post_link.function_imports = parsed.function_imports.empty()
                                         ? nullptr
                                         : parsed.function_imports.data();
        post_link.function_import_count =
            static_cast<std::uint32_t>(parsed.function_imports.size());
        post_link.variable_imports = parsed.variable_imports.empty()
                                         ? nullptr
                                         : parsed.variable_imports.data();
        post_link.variable_import_count =
            static_cast<std::uint32_t>(parsed.variable_imports.size());
    }
};

std::uint16_t decode_thumb_immediate(const ValidatedModule &module,
                                     std::uint32_t address, bool high) {
    const ResolvedBytes resolved =
        resolve_virtual(module, address, 4U, VITA_LOADER_ERROR_RELOCATION);
    const std::span<const std::uint8_t> bytes = module.bytes();
    const std::uint16_t first =
        read_u16(bytes, resolved.file_offset, VITA_LOADER_ERROR_RELOCATION);
    const std::uint16_t second = read_u16(bytes, resolved.file_offset + 2U,
                                          VITA_LOADER_ERROR_RELOCATION);
    const std::uint16_t expected = high ? UINT16_C(0xF2C0) : UINT16_C(0xF240);
    if ((first & UINT16_C(0xFBF0)) != expected ||
        (second & UINT16_C(0x8000)) != 0U) {
        throw ParseFailure(VITA_LOADER_ERROR_RELOCATION);
    }
    return static_cast<std::uint16_t>(((first & UINT16_C(0x000F)) << 12U) |
                                      ((first & UINT16_C(0x0400)) << 1U) |
                                      ((second & UINT16_C(0x7000)) >> 4U) |
                                      (second & UINT16_C(0x00FF)));
}

void add_target_candidate(std::optional<std::uint32_t> &target,
                          std::uint32_t value, std::uint32_t addend) {
    if (value < addend) {
        throw ParseFailure(VITA_LOADER_ERROR_RELOCATION);
    }
    const std::uint32_t candidate = value - addend;
    if (target.has_value() && *target != candidate) {
        throw ParseFailure(VITA_LOADER_ERROR_RELOCATION);
    }
    target = candidate;
}

void validate_identity_relocations(const ValidatedModule &module) {
    vita_reloc_table table{};
    vita_reloc_identity identity{};
    vita_reloc_error error{};
    const vita_reloc_status status = vita_reloc_validate_elf_identity(
        module.bytes().data(), module.bytes().size(), &table, &identity, &error);
    const std::uint32_t streams = table.streams;
    vita_reloc_free(&table);
    if (status == VITA_RELOC_ERROR_NO_MEMORY) {
        throw std::bad_alloc();
    }
    if (status != VITA_RELOC_OK ||
        (module.elf_type() == UINT16_C(0xFE04) && streams == 0U)) {
        throw ParseFailure(VITA_LOADER_ERROR_RELOCATION, error.record_index,
                           error.program_header_index);
    }
}

ParsedPostLink parse_post_link(const ModuleState &state) {
    const ValidatedModule &module = *state.content;
    const vita_generated_module_descriptor &generated = *state.generated;
    if (generated.abi_version != VITA_GENERATED_MODULE_ABI_VERSION ||
        generated.struct_size < sizeof(generated)) {
        throw ParseFailure(VITA_LOADER_ERROR_METADATA_MISMATCH);
    }
    const std::span<const std::uint8_t> bytes = module.bytes();
    const ValidatedSegment &info_segment =
        segment_for_selector(module, module.entry());
    const std::uint32_t info_relative = module.entry() & UINT32_C(0x3fffffff);
    const std::size_t info = relative_file_offset(
        module, info_segment, info_relative, kModuleInfoSize);

    ParsedPostLink parsed;
    const std::uint32_t export_top = read_u32(bytes, info + 0x24U);
    const std::uint32_t export_end = read_u32(bytes, info + 0x28U);
    const std::uint32_t import_top = read_u32(bytes, info + 0x2CU);
    const std::uint32_t import_end = read_u32(bytes, info + 0x30U);
    if (export_top > export_end || import_top > import_end ||
        export_end > info_segment.file_size ||
        import_end > info_segment.file_size) {
        throw ParseFailure(VITA_LOADER_ERROR_MODULE_INFO);
    }
    parsed.module_start = read_u32(bytes, info + 0x44U);
    parsed.tls_start = read_u32(bytes, info + 0x38U);
    parsed.tls_file_size = read_u32(bytes, info + 0x3CU);
    parsed.tls_memory_size = read_u32(bytes, info + 0x40U);
    if (parsed.tls_file_size > parsed.tls_memory_size) {
        throw ParseFailure(VITA_LOADER_ERROR_MODULE_INFO);
    }
    if (parsed.tls_memory_size != 0U) {
        const std::uint32_t tls_address =
            encoded_address(module, parsed.tls_start, parsed.tls_file_size);
        if (parsed.tls_file_size != 0U) {
            (void)resolve_virtual(module, tls_address & ~UINT32_C(1),
                                  parsed.tls_file_size);
        }
    } else if (parsed.tls_file_size != 0U) {
        throw ParseFailure(VITA_LOADER_ERROR_MODULE_INFO);
    }

    std::uint32_t cursor = export_top;
    while (cursor < export_end) {
        const std::size_t entry =
            relative_file_offset(module, info_segment, cursor, 0x20U);
        const std::uint16_t size = read_u16(bytes, entry);
        const std::uint16_t function_count = read_u16(bytes, entry + 6U);
        const std::uint16_t variable_count = read_u16(bytes, entry + 8U);
        const std::uint16_t tls_count = read_u16(bytes, entry + 10U);
        const std::uint32_t count =
            checked_record_count(function_count, variable_count, tls_count);
        if (size < 0x20U || size > export_end - cursor) {
            throw ParseFailure(VITA_LOADER_ERROR_MODULE_INFO);
        }
        (void)relative_file_offset(module, info_segment, cursor, size);
        const std::uint32_t library_nid = read_u32(bytes, entry + 0x0CU);
        const std::uint32_t nid_table = read_u32(bytes, entry + 0x18U);
        const std::uint32_t address_table = read_u32(bytes, entry + 0x1CU);
        const ResolvedBytes nids =
            count == 0U ? ResolvedBytes{0U, 0U}
                        : resolve_virtual(module, nid_table, count * 4U);
        const ResolvedBytes addresses =
            count == 0U ? ResolvedBytes{0U, 0U}
                        : resolve_virtual(module, address_table, count * 4U);
        for (std::uint32_t index = 0U; index < count; ++index) {
            vita_binding_export_kind kind = VITA_BINDING_EXPORT_TLS_VARIABLE;
            if (index < function_count) {
                kind = VITA_BINDING_EXPORT_FUNCTION;
            } else if (index < static_cast<std::uint32_t>(function_count) +
                                   variable_count) {
                kind = VITA_BINDING_EXPORT_VARIABLE;
            }
            parsed.exports.push_back(vita_binding_export_metadata{
                kind,
                library_nid,
                read_u32(bytes, nids.file_offset + index * 4U),
                read_u32(bytes, addresses.file_offset + index * 4U),
            });
        }
        cursor += size;
    }

    struct ImportTable {
        std::uint32_t library_nid;
        std::uint16_t function_count;
        std::uint16_t variable_count;
        std::uint32_t function_nids;
        std::uint32_t function_entries;
        std::uint32_t variable_nids;
        std::uint32_t variable_entries;
    };
    std::vector<ImportTable> imports;
    cursor = import_top;
    std::size_t total_functions = 0U;
    std::size_t total_variables = 0U;
    while (cursor < import_end) {
        const std::size_t entry =
            relative_file_offset(module, info_segment, cursor, 4U);
        const std::uint16_t size = read_u16(bytes, entry);
        if ((size != 0x24U && size != 0x34U) || size > import_end - cursor) {
            throw ParseFailure(VITA_LOADER_ERROR_MODULE_INFO);
        }
        (void)relative_file_offset(module, info_segment, cursor, size);
        const std::uint16_t function_count = read_u16(bytes, entry + 6U);
        const std::uint16_t variable_count = read_u16(bytes, entry + 8U);
        const std::uint16_t tls_variable_count =
            read_u16(bytes, entry + 10U);
        if (tls_variable_count != 0U) {
            throw ParseFailure(VITA_LOADER_ERROR_UNSUPPORTED_LAYOUT);
        }
        if (total_functions + function_count > kMaximumMetadataRecords ||
            total_variables + variable_count > kMaximumMetadataRecords) {
            throw ParseFailure(VITA_LOADER_ERROR_MODULE_INFO);
        }
        total_functions += function_count;
        total_variables += variable_count;
        ImportTable import{};
        import.function_count = function_count;
        import.variable_count = variable_count;
        if (size == 0x34U) {
            import.library_nid = read_u32(bytes, entry + 0x10U);
            import.function_nids = read_u32(bytes, entry + 0x1CU);
            import.function_entries = read_u32(bytes, entry + 0x20U);
            import.variable_nids = read_u32(bytes, entry + 0x24U);
            import.variable_entries = read_u32(bytes, entry + 0x28U);
        } else {
            import.library_nid = read_u32(bytes, entry + 0x0CU);
            import.function_nids = read_u32(bytes, entry + 0x14U);
            import.function_entries = read_u32(bytes, entry + 0x18U);
            import.variable_nids = read_u32(bytes, entry + 0x1CU);
            import.variable_entries = read_u32(bytes, entry + 0x20U);
        }
        imports.push_back(import);
        cursor += size;
    }
    parsed.function_imports.reserve(total_functions);
    parsed.variable_sites.reserve(total_variables);
    parsed.variable_imports.reserve(total_variables);
    if (total_functions != generated.function_import_count ||
        (generated.function_imports != nullptr) != (total_functions != 0U)) {
        throw ParseFailure(VITA_LOADER_ERROR_METADATA_MISMATCH);
    }

    for (const ImportTable &import : imports) {
        const ResolvedBytes function_nids =
            import.function_count == 0U
                ? ResolvedBytes{0U, 0U}
                : resolve_virtual(
                      module, import.function_nids,
                      static_cast<std::uint32_t>(import.function_count) * 4U);
        const ResolvedBytes function_entries =
            import.function_count == 0U
                ? ResolvedBytes{0U, 0U}
                : resolve_virtual(
                      module, import.function_entries,
                      static_cast<std::uint32_t>(import.function_count) * 4U);
        for (std::uint32_t index = 0U; index < import.function_count; ++index) {
            const std::uint32_t function_nid =
                read_u32(bytes, function_nids.file_offset + index * 4U);
            const std::uint32_t target_site =
                import.function_entries + index * 4U;
            const std::uint32_t target =
                read_u32(bytes, function_entries.file_offset + index * 4U);
            std::uint32_t descriptor_matches = 0U;
            for (std::uint32_t descriptor_index = 0U;
                 descriptor_index < generated.function_import_count;
                 ++descriptor_index) {
                const vita_fn_import &descriptor =
                    generated.function_imports[descriptor_index];
                if (descriptor.lib_nid == import.library_nid &&
                    descriptor.func_nid == function_nid &&
                    descriptor.target_site == target_site) {
                    ++descriptor_matches;
                }
            }
            if (descriptor_matches != 1U) {
                throw ParseFailure(
                    VITA_LOADER_ERROR_METADATA_MISMATCH,
                    static_cast<std::uint32_t>(parsed.function_imports.size()));
            }
            parsed.function_imports.push_back(
                vita_binding_function_import_metadata{
                    import.library_nid,
                    function_nid,
                    target_site,
                    target,
                });
        }

        const ResolvedBytes variable_nids =
            import.variable_count == 0U
                ? ResolvedBytes{0U, 0U}
                : resolve_virtual(
                      module, import.variable_nids,
                      static_cast<std::uint32_t>(import.variable_count) * 4U);
        const ResolvedBytes variable_entries =
            import.variable_count == 0U
                ? ResolvedBytes{0U, 0U}
                : resolve_virtual(
                      module, import.variable_entries,
                      static_cast<std::uint32_t>(import.variable_count) * 4U);
        for (std::uint32_t index = 0U; index < import.variable_count; ++index) {
            const std::uint32_t block_address =
                read_u32(bytes, variable_entries.file_offset + index * 4U);
            const ResolvedBytes block = resolve_virtual(
                module, block_address, 4U, VITA_LOADER_ERROR_RELOCATION);
            const std::uint32_t block_size =
                (read_u32(bytes, block.file_offset,
                          VITA_LOADER_ERROR_RELOCATION) >>
                 4U) &
                UINT32_C(0x00ffffff);
            if (block_size < 4U || (block_size - 4U) % 8U != 0U) {
                throw ParseFailure(VITA_LOADER_ERROR_RELOCATION);
            }
            const std::uint32_t site_count = (block_size - 4U) / 8U;
            if (site_count > kMaximumMetadataRecords) {
                throw ParseFailure(VITA_LOADER_ERROR_RELOCATION);
            }
            if (site_count != 0U &&
                block_address >
                    std::numeric_limits<std::uint32_t>::max() - 4U) {
                throw ParseFailure(VITA_LOADER_ERROR_RELOCATION);
            }
            const ResolvedBytes records =
                site_count == 0U
                    ? ResolvedBytes{0U, 0U}
                    : resolve_virtual(module, block_address + 4U,
                                      site_count * 8U,
                                      VITA_LOADER_ERROR_RELOCATION);
            std::vector<vita_var_site> absolute_sites;
            std::optional<std::uint32_t> target;
            std::optional<std::uint16_t> pending_low;
            std::uint32_t pending_addend = 0U;
            for (std::uint32_t site_index = 0U; site_index < site_count;
                 ++site_index) {
                const std::size_t record =
                    records.file_offset + site_index * 8U;
                const std::uint32_t attributes =
                    read_u32(bytes, record, VITA_LOADER_ERROR_RELOCATION);
                const std::uint32_t offset =
                    read_u32(bytes, record + 4U, VITA_LOADER_ERROR_RELOCATION);
                const std::uint32_t code = (attributes >> 8U) & UINT32_C(0xff);
                const std::uint32_t addend =
                    (attributes >> 16U) & UINT32_C(0xfff);
                if (info_segment.virtual_address >
                    std::numeric_limits<std::uint32_t>::max() - offset) {
                    throw ParseFailure(VITA_LOADER_ERROR_RELOCATION);
                }
                const std::uint32_t address =
                    info_segment.virtual_address + offset;
                if (code == 2U) {
                    const ResolvedBytes site = resolve_virtual(
                        module, address, 4U, VITA_LOADER_ERROR_RELOCATION);
                    add_target_candidate(target,
                                         read_u32(bytes, site.file_offset,
                                                  VITA_LOADER_ERROR_RELOCATION),
                                         addend);
                    absolute_sites.push_back(vita_var_site{
                        address,
                        addend,
                    });
                } else if (code == 0x2FU) {
                    if (pending_low.has_value()) {
                        throw ParseFailure(VITA_LOADER_ERROR_RELOCATION);
                    }
                    pending_low =
                        decode_thumb_immediate(module, address, false);
                    pending_addend = addend;
                } else if (code == 0x30U) {
                    if (!pending_low.has_value() || pending_addend != addend) {
                        throw ParseFailure(VITA_LOADER_ERROR_RELOCATION);
                    }
                    const std::uint32_t relocated =
                        static_cast<std::uint32_t>(*pending_low) |
                        (static_cast<std::uint32_t>(
                             decode_thumb_immediate(module, address, true))
                         << 16U);
                    add_target_candidate(target, relocated, addend);
                    pending_low.reset();
                } else {
                    throw ParseFailure(VITA_LOADER_ERROR_RELOCATION);
                }
            }
            if (pending_low.has_value() || !target.has_value()) {
                throw ParseFailure(VITA_LOADER_ERROR_RELOCATION);
            }
            parsed.variable_sites.push_back(std::move(absolute_sites));
            parsed.variable_imports.push_back(
                vita_binding_variable_import_metadata{
                    import.library_nid,
                    read_u32(bytes, variable_nids.file_offset + index * 4U),
                    *target,
                    nullptr,
                    0U,
                });
        }
    }
    for (std::size_t index = 0U; index < parsed.variable_imports.size();
         ++index) {
        const std::vector<vita_var_site> &sites = parsed.variable_sites[index];
        parsed.variable_imports[index].abs_sites =
            sites.empty() ? nullptr : sites.data();
        parsed.variable_imports[index].abs_count =
            static_cast<std::uint32_t>(sites.size());
    }
    return parsed;
}

vita_loader_status
validate_module_extension(const std::uint8_t *bytes, std::size_t size,
                          const vita_loader_module_metadata *metadata,
                          std::uint32_t requested_validation,
                          std::uint32_t *completed_validation,
                          vita_loader_error *error, void *userdata) {
    if (bytes == nullptr || metadata == nullptr ||
        completed_validation == nullptr || userdata == nullptr) {
        return VITA_LOADER_ERROR_INVALID_ARGUMENT;
    }
    *completed_validation = VITA_LOADER_VALIDATE_NONE;
    auto &state = *static_cast<ModuleState *>(userdata);
    if (state.content == nullptr || state.generated == nullptr ||
        bytes != state.content->bytes().data() ||
        size != state.content->bytes().size() ||
        metadata->segment_count != state.loader_metadata.segment_count) {
        return VITA_LOADER_ERROR_METADATA_MISMATCH;
    }
    try {
        ParsedPostLink parsed = parse_post_link(state);
        std::uint32_t completed =
            requested_validation & VITA_LOADER_VALIDATE_MODULE_INFO;
        if ((requested_validation & VITA_LOADER_VALIDATE_RELOCATIONS) != 0U) {
            validate_identity_relocations(*state.content);
            completed |= VITA_LOADER_VALIDATE_RELOCATIONS;
        }
        state.parsed = std::move(parsed);
        state.refresh_views();
        *completed_validation = completed;
        return VITA_LOADER_OK;
    } catch (const ParseFailure &failure) {
        if (error != nullptr) {
            error->program_header_index = failure.program_header_index;
            error->record_index = failure.record_index;
        }
        return failure.status;
    } catch (const std::bad_alloc &) {
        return VITA_LOADER_ERROR_NO_MEMORY;
    } catch (...) {
        return VITA_LOADER_ERROR_EXTENSION;
    }
}

bool identity_matches(const Sha256Digest &supplied,
                      std::string_view expected) noexcept {
    std::array<std::uint8_t, 32> decoded{};
    unsigned invalid = expected.size() == 64U ? 0U : 1U;
    for (std::size_t index = 0U; index < 64U; ++index) {
        const unsigned char character =
            index < expected.size()
                ? static_cast<unsigned char>(expected[index])
                : 0U;
        std::uint8_t nibble = 0U;
        if (character >= '0' && character <= '9') {
            nibble = static_cast<std::uint8_t>(character - '0');
        } else if (character >= 'a' && character <= 'f') {
            nibble = static_cast<std::uint8_t>(character - 'a' + 10U);
        } else {
            invalid |= 1U;
        }
        if (index < decoded.size() * 2U) {
            decoded[index / 2U] = static_cast<std::uint8_t>(
                decoded[index / 2U] |
                (index % 2U == 0U ? nibble << 4U : nibble));
        }
    }
    unsigned difference = invalid;
    for (std::size_t index = 0U; index < supplied.size(); ++index) {
        difference |= static_cast<unsigned>(supplied[index] ^ decoded[index]);
    }
    return difference == 0U;
}

[[noreturn]] void fail_preparation(TitlePreparationStage stage,
                                   std::int32_t status,
                                   std::uint32_t module_index = kIndexNone,
                                   std::uint32_t record_index = kIndexNone,
                                   std::uint32_t site_index = kIndexNone) {
    throw TitlePreparationError(stage, status, module_index, record_index,
                                site_index);
}

void test_preparation_gate(TitlePreparationStage stage) {
#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
    if (g_forced_preparation_failure.load(std::memory_order_relaxed) ==
        static_cast<int>(stage)) {
        fail_preparation(stage, VITA_ERROR_INVALID_ARGUMENT);
    }
#else
    (void)stage;
#endif
}

const vita_generated_module_descriptor *
match_descriptor(const ValidatedModule &module,
                 const game::GeneratedBundleInfo &bundle) {
    const vita_generated_module_descriptor *match = nullptr;
    for (std::uint32_t index = 0U; index < bundle.module_count; ++index) {
        const vita_generated_module_descriptor *candidate =
            bundle.module_descriptors[index];
        if (candidate == nullptr || candidate->module_name == nullptr ||
            module.module_name() != candidate->module_name) {
            continue;
        }
        if (match != nullptr) {
            fail_preparation(TitlePreparationStage::descriptor_agreement,
                             VITA_BINDING_ERROR_INVALID_ARGUMENT);
        }
        match = candidate;
    }
    if (match == nullptr) {
        fail_preparation(TitlePreparationStage::descriptor_agreement,
                         VITA_BINDING_ERROR_INVALID_ARGUMENT);
    }
    return match;
}

bool module_contains(const ValidatedModule &module, std::uint32_t address,
                     std::uint32_t size) {
    const std::uint64_t end = static_cast<std::uint64_t>(address) + size;
    for (const ValidatedSegment &segment : module.segments()) {
        const std::uint64_t segment_end =
            static_cast<std::uint64_t>(segment.virtual_address) +
            segment.memory_size;
        if (address >= segment.virtual_address && end <= segment_end) {
            return true;
        }
    }
    return false;
}

void validate_descriptor(const ModuleState &state, std::uint32_t module_index) {
    const ValidatedModule &module = *state.content;
    const vita_generated_module_descriptor &generated = *state.generated;
    if (generated.abi_version != VITA_GENERATED_MODULE_ABI_VERSION ||
        generated.struct_size < sizeof(generated) ||
        generated.module_id == nullptr || *generated.module_id == '\0' ||
        generated.module_name == nullptr ||
        generated.report.schema_version !=
            VITA_GENERATED_REPORT_SCHEMA_VERSION ||
        generated.report.structural_ready != 1U ||
        generated.report.strict_unsupported != 1U ||
        (generated.report.instrumentation_flags &
         VITA_GENERATED_INSTRUMENT_PC) == 0U ||
        generated.report.unclassified_traps != 0U ||
        generated.report.body_cuts != 0U ||
        generated.report.unreported_partitions != 0U ||
        (generated.dispatch_entries != nullptr) !=
            (generated.dispatch_count != 0U) ||
        (generated.function_imports != nullptr) !=
            (generated.function_import_count != 0U) ||
        (generated.variable_imports != nullptr) !=
            (generated.variable_import_count != 0U)) {
        fail_preparation(TitlePreparationStage::descriptor_agreement,
                         VITA_BINDING_ERROR_GENERATED_ABI, module_index);
    }
    for (std::uint32_t index = 0U; index < generated.dispatch_count; ++index) {
        const vita_dispatch_entry &entry = generated.dispatch_entries[index];
        if (entry.fn == nullptr ||
            !module_contains(module, entry.addr & ~UINT32_C(1), 2U) ||
            (index != 0U &&
             generated.dispatch_entries[index - 1U].addr >= entry.addr)) {
            fail_preparation(TitlePreparationStage::descriptor_agreement,
                             VITA_BINDING_ERROR_LOADER_METADATA, module_index,
                             index);
        }
    }
    for (std::uint32_t index = 0U;
         index < generated.function_import_count; ++index) {
        const vita_fn_import &import = generated.function_imports[index];
        std::uint32_t dispatch_matches = 0U;
        for (std::uint32_t dispatch_index = 0U;
             dispatch_index < generated.dispatch_count; ++dispatch_index) {
            if (generated.dispatch_entries[dispatch_index].addr ==
                import.dispatch_key) {
                ++dispatch_matches;
            }
        }
        if ((import.target_site & 3U) != 0U ||
            !module_contains(module, import.target_site, 4U) ||
            import.target_slot == nullptr || *import.target_slot == nullptr ||
            import.strict_unsupported > 1U ||
            (import.strict_unsupported != 0U &&
             (import.name == nullptr || *import.name == '\0')) ||
            dispatch_matches != 1U) {
            fail_preparation(TitlePreparationStage::descriptor_agreement,
                             VITA_BINDING_ERROR_FUNCTION_METADATA,
                             module_index, index);
        }
        for (std::uint32_t previous = 0U; previous < index; ++previous) {
            const vita_fn_import &prior =
                generated.function_imports[previous];
            if (prior.target_site == import.target_site ||
                prior.target_slot == import.target_slot) {
                fail_preparation(TitlePreparationStage::descriptor_agreement,
                                 VITA_BINDING_ERROR_FUNCTION_METADATA,
                                 module_index, index);
            }
        }
    }

    const bool entry_present = state.parsed.module_start != UINT32_MAX;
    if (generated.entry_present != (entry_present ? 1U : 0U)) {
        fail_preparation(TitlePreparationStage::descriptor_agreement,
                         VITA_BINDING_ERROR_GENERATED_ABI, module_index);
    }
    if (entry_present) {
        const std::uint32_t raw_address =
            encoded_address(module, state.parsed.module_start, 2U);
        const std::uint32_t dispatch_key =
            vita_module_start_dispatch_key(raw_address);
        if (generated.entry_resolved != 1U ||
            generated.entry_function == nullptr ||
            generated.entry_raw_address != raw_address ||
            generated.entry_dispatch_key != dispatch_key) {
            fail_preparation(TitlePreparationStage::descriptor_agreement,
                             VITA_BINDING_ERROR_GENERATED_ABI, module_index);
        }
    } else if (generated.entry_resolved != 0U ||
               generated.entry_function != nullptr ||
               generated.entry_raw_address != 0U ||
               generated.entry_dispatch_key != 0U) {
        fail_preparation(TitlePreparationStage::descriptor_agreement,
                         VITA_BINDING_ERROR_GENERATED_ABI, module_index);
    }

    const bool tls_present = state.parsed.tls_memory_size != 0U;
    if (generated.tls.present != (tls_present ? 1U : 0U)) {
        fail_preparation(TitlePreparationStage::descriptor_agreement,
                         VITA_BINDING_ERROR_GENERATED_ABI, module_index);
    }
    if (tls_present) {
        const ValidatedSegment &tls_segment =
            segment_for_selector(module, state.parsed.tls_start);
        const std::uint32_t address = encoded_address(
            module, state.parsed.tls_start, state.parsed.tls_file_size);
        if (generated.tls.resolved != 1U || generated.tls.address != address ||
            generated.tls.file_size != state.parsed.tls_file_size ||
            generated.tls.memory_size != state.parsed.tls_memory_size ||
            generated.tls.alignment == 0U ||
            (generated.tls.alignment & (generated.tls.alignment - 1U)) != 0U ||
            generated.tls.alignment != tls_segment.alignment) {
            fail_preparation(TitlePreparationStage::descriptor_agreement,
                             VITA_BINDING_ERROR_GENERATED_ABI, module_index);
        }
    } else if (generated.tls.resolved != 0U || generated.tls.address != 0U ||
               generated.tls.file_size != 0U ||
               generated.tls.memory_size != 0U ||
               generated.tls.alignment != 0U) {
        fail_preparation(TitlePreparationStage::descriptor_agreement,
                         VITA_BINDING_ERROR_GENERATED_ABI, module_index);
    }
}

void validate_bundle_dispatch(const std::vector<ModuleState> &states,
                              const game::GeneratedBundleInfo &bundle) {
    std::vector<vita_dispatch_entry> expected;
    for (std::size_t module_index = 0U; module_index < states.size();
         ++module_index) {
        const ModuleState &state = states[module_index];
        for (std::size_t previous = 0U; previous < module_index; ++previous) {
            if (states[previous].generated == state.generated) {
                fail_preparation(TitlePreparationStage::descriptor_agreement,
                                 VITA_BINDING_ERROR_GENERATED_ABI,
                                 static_cast<std::uint32_t>(module_index));
            }
        }
        const vita_generated_module_descriptor &generated = *state.generated;
        if (generated.dispatch_count != 0U) {
            expected.insert(expected.end(), generated.dispatch_entries,
                            generated.dispatch_entries +
                                generated.dispatch_count);
        }
    }
    std::sort(
        expected.begin(), expected.end(),
        [](const vita_dispatch_entry &left, const vita_dispatch_entry &right) {
            return left.addr < right.addr;
        });
    if (bundle.dispatch_count != expected.size() ||
        (bundle.dispatch_entries == nullptr) != expected.empty()) {
        fail_preparation(TitlePreparationStage::descriptor_agreement,
                         VITA_BINDING_ERROR_DISPATCH_NULL_COUNT);
    }
    for (std::size_t index = 0U; index < expected.size(); ++index) {
        if (index != 0U && expected[index - 1U].addr == expected[index].addr) {
            fail_preparation(TitlePreparationStage::descriptor_agreement,
                             VITA_BINDING_ERROR_DUPLICATE_DISPATCH, kIndexNone,
                             static_cast<std::uint32_t>(index));
        }
        if (bundle.dispatch_entries[index].addr != expected[index].addr ||
            bundle.dispatch_entries[index].fn != expected[index].fn) {
            fail_preparation(TitlePreparationStage::descriptor_agreement,
                             VITA_BINDING_ERROR_DISPATCH_UNSORTED, kIndexNone,
                             static_cast<std::uint32_t>(index));
        }
    }
    const auto entry_found = std::find_if(
        states.begin(), states.end(), [&bundle](const ModuleState &state) {
            return state.generated == bundle.entry_module;
        });
    if (entry_found == states.end() || bundle.generated_entry == nullptr ||
        bundle.callable_entry == nullptr ||
        bundle.entry_module->entry_resolved != 1U ||
        bundle.entry_module->entry_function != bundle.generated_entry) {
        fail_preparation(TitlePreparationStage::descriptor_agreement,
                         VITA_BINDING_ERROR_GENERATED_ABI);
    }
}

} // namespace

struct PreparedTitle::State {
    explicit State(Logger &logger) : logger(logger) {}

    ~State() {
        vita_binding_view_destroy(&binding_view);
        runtime.reset();
    }

    Logger &logger;
    std::unique_ptr<RuntimeSession> runtime;
    vita_binding_view binding_view{};
    vita_guest_entry_fn entry = nullptr;
};

std::string_view
title_preparation_stage_name(TitlePreparationStage stage) noexcept {
    switch (stage) {
    case TitlePreparationStage::content_identity:
        return "content_identity";
    case TitlePreparationStage::memory_layout:
        return "memory_layout";
    case TitlePreparationStage::runtime_initialization:
        return "runtime_initialization";
    case TitlePreparationStage::content_mount:
        return "content_mount";
    case TitlePreparationStage::module_preflight:
        return "module_preflight";
    case TitlePreparationStage::module_load:
        return "module_load";
    case TitlePreparationStage::descriptor_agreement:
        return "descriptor_agreement";
    case TitlePreparationStage::binding:
        return "binding";
    case TitlePreparationStage::stack:
        return "stack";
    case TitlePreparationStage::tls:
        return "tls";
    case TitlePreparationStage::cpu_state:
        return "cpu_state";
    }
    return "unknown";
}

#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
void force_title_preparation_failure_for_test(
    TitlePreparationStage stage) noexcept {
    g_forced_preparation_failure.store(static_cast<int>(stage),
                                       std::memory_order_relaxed);
}

void clear_title_preparation_failure_for_test() noexcept {
    g_forced_preparation_failure.store(-1, std::memory_order_relaxed);
}
#endif

TitlePreparationError::TitlePreparationError(TitlePreparationStage stage,
                                             std::int32_t status,
                                             std::uint32_t module_index,
                                             std::uint32_t record_index,
                                             std::uint32_t site_index)
    : std::runtime_error("title preparation precondition failed"),
      stage_(stage), status_(status), module_index_(module_index),
      record_index_(record_index), site_index_(site_index) {}

TitlePreparationStage TitlePreparationError::stage() const noexcept {
    return stage_;
}

std::int32_t TitlePreparationError::status() const noexcept { return status_; }

std::uint32_t TitlePreparationError::module_index() const noexcept {
    return module_index_;
}

std::uint32_t TitlePreparationError::record_index() const noexcept {
    return record_index_;
}

std::uint32_t TitlePreparationError::site_index() const noexcept {
    return site_index_;
}

PreparedTitle::PreparedTitle(std::unique_ptr<State> state) noexcept
    : state_(std::move(state)) {}

PreparedTitle::~PreparedTitle() = default;
PreparedTitle::PreparedTitle(PreparedTitle &&) noexcept = default;
PreparedTitle &PreparedTitle::operator=(PreparedTitle &&) noexcept = default;

TitleCallResult PreparedTitle::execute() && noexcept {
    std::unique_ptr<State> state = std::move(state_);
    if (state == nullptr || state->entry == nullptr) {
        return TitleCallResult{
            .outcome = TitleCallOutcome::boundary_error,
            .status = VITA_ERROR_INVALID_ARGUMENT,
        };
    }
    vita_guest_call_result framework_result{};
    const int call_status = vita_guest_call(state->entry, &framework_result);
    if (call_status != VITA_OK) {
        return TitleCallResult{
            .outcome = TitleCallOutcome::boundary_error,
            .status = call_status,
        };
    }
    TitleCallResult result{
        .status = framework_result.exit_status,
        .strict_kind = static_cast<std::int32_t>(framework_result.failure.kind),
        .source_address = framework_result.failure.source_address,
        .target_address = framework_result.failure.target_address,
        .nid = framework_result.failure.nid,
    };
    copy_strict_name(framework_result.failure.name, result.strict_name);
    switch (framework_result.outcome) {
    case VITA_GUEST_CALL_COMPLETED:
        result.outcome = TitleCallOutcome::completed;
        break;
    case VITA_GUEST_CALL_EXIT_REQUESTED:
        result.outcome = TitleCallOutcome::exit_requested;
        break;
    case VITA_GUEST_CALL_STRICT_FAILURE:
        result.outcome = TitleCallOutcome::strict_failure;
        break;
    }
    return result;
}

PreparedTitle prepare_title(const ValidatedContent &content,
                            const game::GeneratedBundleInfo &bundle,
                            Logger &logger) {
    if (!bundle.present || bundle.module_descriptors == nullptr ||
        bundle.module_count == 0U || bundle.tls_layout == nullptr ||
        bundle.module_count != content.module_count() ||
        !identity_matches(content.manifest_identity(),
                          bundle.expected_runtime_manifest_sha256)) {
        fail_preparation(TitlePreparationStage::content_identity,
                         VITA_ERROR_INVALID_ARGUMENT);
    }
    test_preparation_gate(TitlePreparationStage::content_identity);

    game::RuntimeMemoryLayout layout{};
    const game::MemoryLayoutStatus layout_status = game::plan_memory_layout(
        content.load_ranges(), game::title_memory_policy(), layout);
    if (layout_status != game::MemoryLayoutStatus::success) {
        fail_preparation(TitlePreparationStage::memory_layout,
                         static_cast<std::int32_t>(layout_status));
    }
    test_preparation_gate(TitlePreparationStage::memory_layout);

    auto prepared = std::make_unique<PreparedTitle::State>(logger);
    try {
        prepared->runtime = std::make_unique<RuntimeSession>(logger, layout);
    } catch (...) {
        fail_preparation(TitlePreparationStage::runtime_initialization,
                         VITA_ERROR_NOT_INITIALIZED);
    }
    test_preparation_gate(TitlePreparationStage::runtime_initialization);
    try {
        prepared->runtime->mount_app0(content);
    } catch (...) {
        fail_preparation(TitlePreparationStage::content_mount, VITA_ERROR_IO);
    }
    test_preparation_gate(TitlePreparationStage::content_mount);

    std::vector<ModuleState> states;
    states.reserve(content.module_count());
    for (const ValidatedModule &module : content.modules()) {
        ModuleState state;
        state.content = &module;
        state.generated = match_descriptor(module, bundle);
        state.loader_segments.reserve(module.segments().size());
        for (const ValidatedSegment &segment : module.segments()) {
            state.loader_segments.push_back(vita_loader_segment_metadata{
                segment.program_header_index,
                segment.file_offset,
                segment.virtual_address,
                segment.physical_address,
                segment.file_size,
                segment.memory_size,
                segment.flags,
                segment.alignment,
            });
        }
        state.loader_metadata = vita_loader_module_metadata{
            module.elf_type(),
            module.machine(),
            module.entry(),
            module.elf_flags(),
            module.program_header_count(),
            0U,
            static_cast<std::uint32_t>(state.loader_segments.size()),
            state.loader_segments.data(),
        };
        states.push_back(std::move(state));
    }
    for (ModuleState &state : states) {
        state.loader_metadata.segments = state.loader_segments.data();
    }

    std::vector<vita_loader_module> loader_modules;
    loader_modules.reserve(states.size());
    for (ModuleState &state : states) {
        loader_modules.push_back(vita_loader_module{
            state.content->bytes().data(),
            state.content->bytes().size(),
            &state.loader_metadata,
            VITA_LOADER_VALIDATE_MODULE_INFO | VITA_LOADER_VALIDATE_RELOCATIONS,
            validate_module_extension,
            &state,
        });
    }
    std::vector<vita_load_info> load_infos(states.size());
    vita_loader_error loader_error{};
    vita_loader_status loader_status =
        vita_preflight_module_set(loader_modules.data(), loader_modules.size(),
                                  load_infos.data(), &loader_error);
    if (loader_status != VITA_LOADER_OK) {
        fail_preparation(TitlePreparationStage::module_preflight, loader_status,
                         loader_error.module_index, loader_error.record_index,
                         loader_error.program_header_index);
    }
    test_preparation_gate(TitlePreparationStage::module_preflight);
    loader_status =
        vita_load_module_set(loader_modules.data(), loader_modules.size(),
                             load_infos.data(), &loader_error);
    if (loader_status != VITA_LOADER_OK) {
        fail_preparation(TitlePreparationStage::module_load, loader_status,
                         loader_error.module_index, loader_error.record_index,
                         loader_error.program_header_index);
    }
    test_preparation_gate(TitlePreparationStage::module_load);

    for (std::size_t index = 0U; index < states.size(); ++index) {
        validate_descriptor(states[index], static_cast<std::uint32_t>(index));
    }
    validate_bundle_dispatch(states, bundle);
    test_preparation_gate(TitlePreparationStage::descriptor_agreement);

    std::vector<vita_binding_module> binding_modules;
    binding_modules.reserve(states.size());
    for (ModuleState &state : states) {
        state.refresh_views();
        binding_modules.push_back(vita_binding_module{
            &state.loader_metadata,
            state.generated,
            &state.post_link,
        });
    }
    vita_binding_error binding_error{};
    const vita_binding_status binding_status = vita_binding_install_module_set(
        binding_modules.data(), binding_modules.size(), nullptr, 0U,
        &prepared->binding_view, &binding_error);
    if (binding_status != VITA_BINDING_OK) {
        fail_preparation(TitlePreparationStage::binding, binding_status,
                         binding_error.module_index, binding_error.record_index,
                         binding_error.site_index);
    }
    test_preparation_gate(TitlePreparationStage::binding);

    std::uint32_t initial_stack_pointer = 0U;
    try {
        initial_stack_pointer = prepared->runtime->prepare_main_stack(
            layout.stack_base, layout.stack_size);
    } catch (...) {
        fail_preparation(TitlePreparationStage::stack,
                         VITA_ERROR_INVALID_ARGUMENT);
    }
    test_preparation_gate(TitlePreparationStage::stack);

    std::vector<vita_tls_module_layout> tls_modules(states.size());
    vita_tls_layout tls_layout{};
    const vita_result tls_status = vita_tls_prepare_generated_modules(
        bundle.module_descriptors, bundle.module_count, bundle.tls_layout,
        tls_modules.data(), tls_modules.size(), &tls_layout);
    if (tls_status != VITA_OK) {
        fail_preparation(TitlePreparationStage::tls, tls_status);
    }

    const vita_module_start_state entry_state{
        0U,
        0U,
        initial_stack_pointer,
        0U,
    };
    const vita_result cpu_status = vita_cpu_prepare_module_start(&entry_state);
    if (cpu_status != VITA_OK) {
        fail_preparation(TitlePreparationStage::cpu_state, cpu_status);
    }
    test_preparation_gate(TitlePreparationStage::cpu_state);
    std::uint32_t main_tls_base = 0U;
    const vita_result materialize_status =
        vita_tls_materialize_current(&main_tls_base);
    if (materialize_status != VITA_OK || main_tls_base == 0U) {
        fail_preparation(
            TitlePreparationStage::tls,
            materialize_status != VITA_OK ? materialize_status
                                          : VITA_ERROR_NO_MEMORY);
    }
    test_preparation_gate(TitlePreparationStage::tls);
    prepared->entry = bundle.callable_entry;
    return PreparedTitle(std::move(prepared));
}

} // namespace kzm::host
