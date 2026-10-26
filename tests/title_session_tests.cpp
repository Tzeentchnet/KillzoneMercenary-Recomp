// SPDX-License-Identifier: GPL-2.0-or-later
#include "game/generated_bundle.hpp"
#include "game/title_config.hpp"
#include "host/logging.hpp"
#include "host/manifest.hpp"
#include "host/sha256.hpp"
#include "host/title_session.hpp"

#include "vitarecomp/host.h"
extern "C" {
#include "vitarecomp/mem.h"
#include "vitarecomp/recomp_rt.h"
}

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdio>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <type_traits>
#include <utility>
#include <vector>

namespace {

class TestFailure final : public std::runtime_error {
  public:
    using std::runtime_error::runtime_error;
};

void check(bool condition, std::string_view message) {
    if (!condition)
        throw TestFailure(std::string(message));
}

void write_u16(std::vector<std::uint8_t> &bytes, std::size_t offset,
               std::uint16_t value) {
    bytes.at(offset) = static_cast<std::uint8_t>(value);
    bytes.at(offset + 1U) = static_cast<std::uint8_t>(value >> 8U);
}

void write_u32(std::vector<std::uint8_t> &bytes, std::size_t offset,
               std::uint32_t value) {
    for (unsigned index = 0U; index < 4U; ++index) {
        bytes.at(offset + index) =
            static_cast<std::uint8_t>(value >> (index * 8U));
    }
}

void write_text(const std::filesystem::path &path, std::string_view text) {
    std::ofstream stream(path, std::ios::binary);
    stream.write(text.data(), static_cast<std::streamsize>(text.size()));
    if (!stream)
        throw TestFailure("failed to write test text");
}

enum class RelocationCase {
    none,
    valid_identity,
    malformed_one_byte,
    unknown_format,
    trailing_record,
    unsupported_code,
    changed_image,
    outside_file
};

void write_elf(const std::filesystem::path &path,
               bool invalid_module_tables = false,
               RelocationCase relocation = RelocationCase::none,
               std::uint32_t module_start = 0x1001U,
               std::uint16_t elf_type = 2U,
               bool function_import = false,
               std::uint32_t tls_memory_size = 0U,
               std::uint32_t tls_alignment = 4096U,
               bool tls_variable_import = false,
               bool data_function_export = false,
               bool zero_site_variable_import = false,
               bool segmented_variable_import = false,
               bool strict_variable_import = false) {
    const bool segmented =
        segmented_variable_import || strict_variable_import;
    if ((data_function_export || segmented) &&
        relocation != RelocationCase::none)
        throw TestFailure("data export fixture cannot include relocations");
    std::vector<std::uint8_t> bytes(512U, 0U);
    bytes[0] = 0x7FU;
    bytes[1] = 'E';
    bytes[2] = 'L';
    bytes[3] = 'F';
    bytes[4] = 1U;
    bytes[5] = 1U;
    bytes[6] = 1U;
    if (relocation != RelocationCase::none || segmented)
        elf_type = UINT16_C(0xFE04);
    write_u16(bytes, 16U, elf_type);
    write_u16(bytes, 18U, 40U);
    write_u32(bytes, 20U, 1U);
    write_u32(bytes, 24U, 0x100U);
    write_u32(bytes, 28U, 52U);
    write_u16(bytes, 40U, 52U);
    write_u16(bytes, 42U, 32U);
    write_u16(bytes, 44U, static_cast<std::uint16_t>(
                              1U +
                              (relocation == RelocationCase::none ? 0U : 1U) +
                              (data_function_export ? 1U : 0U) +
                              (segmented ? 2U : 0U)));

    write_u32(bytes, 52U, 1U);
    write_u32(bytes, 56U, 0U);
    write_u32(bytes, 60U, 0U);
    write_u32(bytes, 64U, 0U);
    write_u32(bytes, 68U, segmented ? 448U : 512U);
    const std::uint32_t segment_memory_size =
        std::max<std::uint32_t>(
            8192U, tls_memory_size > 0U
                       ? tls_memory_size + UINT32_C(0x1D0)
                       : 0U);
    write_u32(bytes, 72U, segment_memory_size);
    write_u32(bytes, 76U, 5U);
    write_u32(bytes, 80U, tls_alignment);

    if (segmented) {
        constexpr std::size_t data_header = 84U;
        constexpr std::size_t relocation_header = 116U;
        write_u32(bytes, data_header + 0U, 1U);
        write_u32(bytes, data_header + 4U, 448U);
        write_u32(bytes, data_header + 8U, 0x3000U);
        write_u32(bytes, data_header + 12U, 0x3000U);
        write_u32(bytes, data_header + 16U, 4U);
        write_u32(bytes, data_header + 20U, 16U);
        write_u32(bytes, data_header + 24U, 6U);
        write_u32(bytes, data_header + 28U, 16U);
        write_u32(bytes, relocation_header + 0U, UINT32_C(0x60000000));
        write_u32(bytes, relocation_header + 4U, 0x1B0U);
        write_u32(bytes, relocation_header + 16U, 12U);
        write_u32(bytes, 0x1B0U,
                  (UINT32_C(0xF) << 4U) | (2U << 8U) | (1U << 16U));
        write_u32(bytes, 0x1B4U, UINT32_C(0x12345678));
        write_u32(bytes, 0x1B8U, 0U);
        write_u32(bytes, 0x1C0U, 0x4000U + 0xABCDU);
    } else if (data_function_export) {
        constexpr std::size_t header = 84U;
        write_u32(bytes, header + 0U, 1U);
        write_u32(bytes, header + 4U, 512U);
        write_u32(bytes, header + 8U, 0x3000U);
        write_u32(bytes, header + 12U, 0x3000U);
        write_u32(bytes, header + 16U, 0U);
        write_u32(bytes, header + 20U, 16U);
        write_u32(bytes, header + 24U, 6U);
        write_u32(bytes, header + 28U, 16U);
    } else if (relocation != RelocationCase::none) {
        constexpr std::size_t header = 84U;
        constexpr std::size_t stream = 0x180U;
        constexpr std::size_t patch = 0x1C0U;
        std::uint32_t stream_size = 12U;
        std::uint32_t code = 2U;
        write_u32(bytes, header + 0U, UINT32_C(0x60000000));
        write_u32(bytes, header + 4U,
                  static_cast<std::uint32_t>(stream));
        if (relocation == RelocationCase::malformed_one_byte) {
            stream_size = 1U;
        } else if (relocation == RelocationCase::unknown_format) {
            stream_size = 4U;
            write_u32(bytes, stream, 0xAU);
        } else {
            if (relocation == RelocationCase::trailing_record)
                stream_size = 13U;
            if (relocation == RelocationCase::unsupported_code)
                code = 0x7EU;
            write_u32(bytes, stream, (UINT32_C(0xF) << 4U) |
                                         (code << 8U));
            write_u32(bytes, stream + 4U, UINT32_C(0x12345678));
            write_u32(bytes, stream + 8U,
                      static_cast<std::uint32_t>(patch));
            write_u32(bytes, patch,
                      relocation == RelocationCase::changed_image
                          ? UINT32_C(0x87654321)
                          : UINT32_C(0x12345678));
            if (relocation == RelocationCase::outside_file)
                write_u32(bytes, stream + 8U, 512U);
        }
        write_u32(bytes, header + 16U, stream_size);
    }

    write_u16(bytes, 0x102U, 0x0100U);
    constexpr std::string_view name = "synthetic_module";
    std::copy(name.begin(), name.end(), bytes.begin() + 0x104U);
    if (invalid_module_tables) {
        write_u32(bytes, 0x124U, 8U);
        write_u32(bytes, 0x128U, 4U);
    } else if (data_function_export) {
        write_u32(bytes, 0x124U, 0x160U);
        write_u32(bytes, 0x128U, 0x180U);
        write_u16(bytes, 0x160U, 0x20U);
        write_u16(bytes, 0x166U, 1U);
        write_u32(bytes, 0x16CU, UINT32_C(0x11110000));
        write_u32(bytes, 0x178U, 0x1A0U);
        write_u32(bytes, 0x17CU, 0x1A4U);
        write_u32(bytes, 0x1A0U, UINT32_C(0x22220000));
        write_u32(bytes, 0x1A4U, 0x3001U);
    }
    if (function_import || tls_variable_import ||
        zero_site_variable_import || segmented) {
        write_u32(bytes, 0x12CU, 0x160U);
        write_u32(bytes, 0x130U, 0x184U);
        write_u16(bytes, 0x160U, 0x24U);
        write_u16(bytes, 0x166U, function_import ? 1U : 0U);
        write_u16(bytes, 0x168U,
                  (zero_site_variable_import ||
                   segmented) ? 1U : 0U);
        write_u16(bytes, 0x16AU, tls_variable_import ? 1U : 0U);
        write_u32(bytes, 0x16CU,
                  segmented_variable_import
                      ? UINT32_C(0xCAE9ACE6)
                      : UINT32_C(0x11110000));
        write_u32(bytes, 0x174U, 0x190U);
        write_u32(bytes, 0x178U, 0x194U);
        write_u32(bytes, 0x17CU, 0x198U);
        write_u32(bytes, 0x180U, 0x19CU);
        write_u32(bytes, 0x190U, UINT32_C(0x11110001));
        write_u32(bytes, 0x194U, UINT32_C(0xF0000002));
        write_u32(bytes, 0x198U,
                  segmented_variable_import
                      ? UINT32_C(0x93B8AA67)
                      : UINT32_C(0x11110002));
        write_u32(bytes, 0x19CU, 0x1A0U);
        write_u32(bytes, 0x1A0U,
                  segmented ? (12U << 4U) : 0x40U);
        if (segmented) {
            write_u32(bytes, 0x1A4U,
                      1U | (1U << 4U) | (2U << 8U) |
                          (0xABCDU << 16U));
            write_u32(bytes, 0x1A8U, 0U);
        }
    }
    if (tls_memory_size != 0U) {
        write_u32(bytes, 0x138U, 0x1D0U);
        write_u32(bytes, 0x13CU, 4U);
        write_u32(bytes, 0x140U, tls_memory_size);
        bytes[0x1D0U] = 0xA1U;
        bytes[0x1D1U] = 0xB2U;
        bytes[0x1D2U] = 0xC3U;
        bytes[0x1D3U] = 0xD4U;
    }
    write_u32(bytes, 0x144U, module_start);
    std::filesystem::create_directories(path.parent_path());
    std::ofstream stream(path, std::ios::binary);
    stream.write(reinterpret_cast<const char *>(bytes.data()),
                 static_cast<std::streamsize>(bytes.size()));
    if (!stream)
        throw TestFailure("failed to write test ELF");
}

std::filesystem::path write_fixture(const std::filesystem::path &root,
                                    bool invalid_module_tables = false,
                                    RelocationCase relocation =
                                        RelocationCase::none,
                                    std::uint32_t module_start = 0x1001U,
                                    std::uint16_t elf_type = 2U,
                                    bool function_import = false,
                                    std::uint32_t tls_memory_size = 0U,
                                    std::uint32_t tls_alignment = 4096U,
                                    bool tls_variable_import = false,
                                    bool data_function_export = false,
                                    bool reverse_manifest_segments = false,
                                    bool zero_site_variable_import = false,
                                    bool segmented_variable_import = false,
                                    bool strict_variable_import = false) {
    const bool segmented =
        segmented_variable_import || strict_variable_import;
    const std::filesystem::path content = root / L"app0";
    const std::filesystem::path module = content / L"module.elf";
    const std::filesystem::path manifest = root / L"runtime-manifest.json";
    write_elf(module, invalid_module_tables, relocation, module_start,
              elf_type, function_import, tls_memory_size, tls_alignment,
              tls_variable_import, data_function_export,
              zero_site_variable_import, segmented_variable_import,
              strict_variable_import);
    const std::string hash =
        kzm::host::sha256_hex(kzm::host::sha256_file(module));
    std::array<char, 11> range_end{};
    const int range_written = std::snprintf(
        range_end.data(), range_end.size(), "0x%08X",
        std::max<std::uint32_t>(
            8192U, tls_memory_size > 0U
                       ? tls_memory_size + UINT32_C(0x1D0)
                       : 0U));
    check(range_written == 10, "failed to format segment range");
    const std::uint32_t segment_memory_size =
        std::max<std::uint32_t>(
            8192U, tls_memory_size > 0U
                       ? tls_memory_size + UINT32_C(0x1D0)
                       : 0U);
    const std::string primary_segment =
        "{\"index\": 0, \"fileOffset\": 0, \"fileSize\": " +
        std::to_string(segmented ? 448U : 512U) + ", "
        "\"virtualAddress\": \"0x00000000\", \"memorySize\": " +
        std::to_string(segment_memory_size) +
        ", \"rangeEndExclusive\": \"" + range_end.data() +
        "\", \"flags\": \"r-x\", \"alignment\": " +
        std::to_string(tls_alignment) + "}";
    const std::string data_segment =
        "{\"index\": 1, \"fileOffset\": " +
        std::to_string(segmented ? 448U : 512U) +
        ", \"fileSize\": " +
        std::to_string(segmented ? 4U : 0U) + ", "
        "\"virtualAddress\": \"0x00003000\", \"memorySize\": 16, "
        "\"rangeEndExclusive\": \"0x00003010\", "
        "\"flags\": \"rw-\", \"alignment\": 16}";
    const std::string load_segments =
        (data_function_export || segmented)
            ? (reverse_manifest_segments
                   ? data_segment + ", " + primary_segment
                   : primary_segment + ", " + data_segment)
            : primary_segment;
    const std::string json =
        "{\n"
        "  \"schemaVersion\": 1,\n"
        "  \"titleId\": \"PCSA00107\",\n"
        "  \"sourceArchive\": {\"path\": \"synthetic.zip\", "
        "\"sha256\": "
        "\"0000000000000000000000000000000000000000000000000000000000000000\"},"
        "\n"
        "  \"vita3k\": {\"sourceRevision\": \"0000000\", "
        "\"dumpCapability\": \"--dump-elfs\"},\n"
        "  \"imageFormat\": {\"elfClass\": \"ELF32\", "
        "\"byteOrder\": \"little-endian\", \"machine\": \"ARM\"},\n"
        "  \"modules\": [{\n"
        "    \"path\": \"module.elf\",\n"
        "    \"sha256\": \"" +
        hash +
        "\",\n"
        "    \"fileSize\": 512,\n"
        "    \"moduleInfo\": {\"name\": \"synthetic_module\", "
        "\"encodedEntry\": \"0x00000100\", \"segmentIndex\": 0, "
        "\"segmentOffset\": 256, \"virtualAddress\": \"0x00000100\"},\n"
        "    \"programHeaderCount\": " +
        std::to_string(
            1U + (relocation == RelocationCase::none ? 0U : 1U) +
            (data_function_export ? 1U : 0U) +
            (segmented ? 2U : 0U)) +
        ",\n"
        "    \"loadSegments\": [" + load_segments + "]\n"
        "  }]\n"
        "}\n";
    write_text(manifest, json);
    return manifest;
}

std::uint32_t g_entry_calls = 0U;
std::uint32_t g_after_strict = 0U;
std::uint32_t g_entry_tls_base = 0U;
std::array<std::uint8_t, 5> g_entry_tls_image{};

void completed_entry() { ++g_entry_calls; }

void tls_entry() {
    ++g_entry_calls;
    g_entry_tls_base = vita_tls_base();
    for (std::size_t index = 0U; index < g_entry_tls_image.size(); ++index) {
        g_entry_tls_image[index] =
            vita_read8(g_entry_tls_base + static_cast<std::uint32_t>(index));
    }
}

void strict_entry() {
    ++g_entry_calls;
    vita_trap_unimpl(0x1000U, 0xE7F000F0U, "synthetic strict failure");
    ++g_after_strict;
}

void strict_variable_entry() {
    ++g_entry_calls;
    (void)vita_read32(0x4000U);
    ++g_after_strict;
}

void exit_entry() {
    ++g_entry_calls;
    vita_host_exit(23);
}

void strict_import_default() {
    vita_trap_import(0x1A0U, UINT32_C(0x11110001),
                     "FixtureImport::namedDefault");
}

struct BundleFixture {
    vita_dispatch_entry dispatch[3]{};
    vita_fn_import function_imports[2]{};
    vita_fn import_slots[2]{};
    vita_var_import variable_imports[1]{};
    vita_var_site variable_sites[1]{};
    std::uint32_t variable_storage = 0U;
    vita_generated_module_descriptor descriptor{};
    const vita_generated_module_descriptor *modules[1]{};
    vita_generated_tls_layout_entry tls_entries[1]{};
    vita_generated_tls_layout tls_layout{};
    std::string identity;
    kzm::game::GeneratedBundleInfo bundle{};

    BundleFixture(const kzm::host::ValidatedContent &content, vita_fn entry,
                  std::uint32_t raw_address = 0x1001U,
                  std::uint32_t dispatch_key = 0x1001U,
                  std::uint32_t tls_memory_size = 0U,
                  std::uint32_t tls_alignment = 0U) {
        dispatch[0] = vita_dispatch_entry{dispatch_key, entry};
        descriptor.abi_version = VITA_GENERATED_MODULE_ABI_VERSION;
        descriptor.struct_size = static_cast<std::uint32_t>(sizeof(descriptor));
        descriptor.module_id = "synthetic";
        descriptor.module_name = "synthetic_module";
        descriptor.dispatch_entries = dispatch;
        descriptor.dispatch_count = 1U;
        descriptor.entry_present = 1U;
        descriptor.entry_raw_address = raw_address;
        descriptor.entry_dispatch_key = dispatch_key;
        descriptor.entry_function = entry;
        descriptor.entry_resolved = 1U;
        if (tls_memory_size != 0U) {
            descriptor.tls = vita_generated_module_tls{
                1U, 1U, 0x1D0U, 4U, tls_memory_size, tls_alignment};
            tls_entries[0] = vita_generated_tls_layout_entry{
                &descriptor, 0U, 0U, 0U, tls_alignment};
        }
        descriptor.report.schema_version = VITA_GENERATED_REPORT_SCHEMA_VERSION;
        descriptor.report.structural_ready = 1U;
        descriptor.report.production_ready = 1U;
        descriptor.report.strict_unsupported = 1U;
        descriptor.report.instrumentation_flags = VITA_GENERATED_INSTRUMENT_PC;
        modules[0] = &descriptor;
        tls_layout = vita_generated_tls_layout{
            VITA_GENERATED_MODULE_ABI_VERSION,
            static_cast<std::uint32_t>(sizeof(vita_generated_tls_layout)),
            tls_memory_size != 0U ? tls_entries : nullptr,
            1U,
            tls_memory_size != 0U ? 1U : 0U,
            tls_memory_size,
            tls_memory_size != 0U
                ? std::max<std::uint32_t>(16U, tls_alignment)
                : 16U,
        };
        identity = kzm::host::sha256_hex(content.manifest_identity());
        bundle = kzm::game::GeneratedBundleInfo{
            .present = true,
            .expected_runtime_manifest_sha256 = identity,
            .module_descriptors = modules,
            .module_count = 1U,
            .tls_layout = &tls_layout,
            .dispatch_entries = dispatch,
            .dispatch_count = 1U,
            .entry_module = &descriptor,
            .generated_entry = entry,
            .callable_entry = entry,
        };
    }

    void add_function_import(std::uint32_t target_site = 0x194U,
                             std::uint32_t function_nid =
                                 UINT32_C(0x11110001)) {
        dispatch[1] = dispatch[0];
        dispatch[0] =
            vita_dispatch_entry{0x1A1U, strict_import_default};
        import_slots[0] = strict_import_default;
        function_imports[0] = vita_fn_import{
            UINT32_C(0x11110000),
            function_nid,
            0x1A1U,
            target_site,
            "FixtureImport::namedDefault",
            1U,
            &import_slots[0],
        };
        descriptor.dispatch_count = 2U;
        descriptor.function_imports = function_imports;
        descriptor.function_import_count = 1U;
        bundle.dispatch_count = 2U;
    }

    void add_zero_site_variable_import() {
        variable_imports[0] = vita_var_import{
            UINT32_C(0x11110000),
            UINT32_C(0x11110002),
            "FixtureVariable::unused",
            &variable_storage,
            nullptr,
            0U,
        };
        descriptor.variable_imports = variable_imports;
        descriptor.variable_import_count = 1U;
    }

    void add_segmented_variable_import() {
        variable_sites[0] = vita_var_site{0x3000U, 0xABCDU};
        variable_imports[0] = vita_var_import{
            UINT32_C(0xCAE9ACE6),
            UINT32_C(0x93B8AA67),
            "SceLibKernel::__stack_chk_guard",
            &variable_storage,
            variable_sites,
            1U,
        };
        descriptor.variable_imports = variable_imports;
        descriptor.variable_import_count = 1U;
    }

    void add_strict_variable_import() {
        variable_sites[0] = vita_var_site{0x3000U, 0xABCDU};
        variable_imports[0] = vita_var_import{
            UINT32_C(0x11110000),
            UINT32_C(0x11110002),
            "FixtureVariable::segmented",
            &variable_storage,
            variable_sites,
            1U,
        };
        descriptor.variable_imports = variable_imports;
        descriptor.variable_import_count = 1U;
    }
};

kzm::host::Logger quiet_logger() {
    return kzm::host::Logger(kzm::host::LogLevel::error,
                             [](std::string_view) {});
}

void expect_preparation_failure(const kzm::host::ValidatedContent &content,
                                const kzm::game::GeneratedBundleInfo &bundle,
                                kzm::host::TitlePreparationStage stage) {
    kzm::host::Logger logger = quiet_logger();
    try {
        (void)kzm::host::prepare_title(content, bundle, logger);
    } catch (const kzm::host::TitlePreparationError &error) {
        check(error.stage() == stage, "unexpected preparation stage failed");
        check(g_entry_calls == 0U, "failed preparation called title entry");
        return;
    }
    throw TestFailure("invalid title preparation unexpectedly succeeded");
}

void test_completion_and_retained_bytes(const std::filesystem::path &root) {
    const std::filesystem::path manifest = write_fixture(root);
    kzm::host::ValidatedContent content =
        kzm::host::validate_content_manifest(manifest, root / L"app0");
    check(content.module_count() == 1U, "module was not retained");
    check(content.modules()[0].bytes().size() == 512U,
          "immutable module bytes were not retained");
    check(content.modules()[0].segments().size() == 1U,
          "module metadata was not retained");
    std::filesystem::remove(root / L"app0" / L"module.elf");

    BundleFixture fixture(content, completed_entry);
    g_entry_calls = 0U;
    kzm::host::Logger logger = quiet_logger();
    kzm::host::PreparedTitle prepared =
        kzm::host::prepare_title(content, fixture.bundle, logger);
    const kzm::host::TitleCallResult result = std::move(prepared).execute();
    check(result.outcome == kzm::host::TitleCallOutcome::completed,
          "clean synthetic entry did not complete");
    check(g_entry_calls == 1U, "clean synthetic entry was not called once");
    const kzm::host::TitleCallResult repeated = std::move(prepared).execute();
    check(repeated.outcome == kzm::host::TitleCallOutcome::boundary_error &&
              g_entry_calls == 1U,
          "consumed prepared capability called entry again");
}

void test_data_address_function_export(const std::filesystem::path &root) {
    const std::filesystem::path manifest = write_fixture(
        root, false, RelocationCase::none, 0x1001U, 2U, false, 0U, 4096U,
        false, true);
    kzm::host::ValidatedContent content =
        kzm::host::validate_content_manifest(manifest, root / L"app0");
    BundleFixture fixture(content, completed_entry);
    g_entry_calls = 0U;
    kzm::host::Logger logger = quiet_logger();
    kzm::host::PreparedTitle prepared =
        kzm::host::prepare_title(content, fixture.bundle, logger);
    const kzm::host::TitleCallResult result = std::move(prepared).execute();
    check(result.outcome == kzm::host::TitleCallOutcome::completed &&
              g_entry_calls == 1U,
          "data-address function export blocked title entry");
}

void test_manifest_segment_order(const std::filesystem::path &root) {
    const std::filesystem::path manifest = write_fixture(
        root, false, RelocationCase::none, 0x1001U, 2U, false, 0U, 4096U,
        false, true, true);
    kzm::host::ValidatedContent content =
        kzm::host::validate_content_manifest(manifest, root / L"app0");
    check(content.modules()[0].segments()[0].program_header_index == 1U,
          "segment-order fixture was not reversed");

    BundleFixture fixture(content, completed_entry);
    g_entry_calls = 0U;
    kzm::host::Logger logger = quiet_logger();
    kzm::host::PreparedTitle prepared =
        kzm::host::prepare_title(content, fixture.bundle, logger);
    const kzm::host::TitleCallResult result = std::move(prepared).execute();
    check(result.outcome == kzm::host::TitleCallOutcome::completed &&
              g_entry_calls == 1U,
          "manifest segment order blocked title entry");
}

void test_zero_site_variable_import(const std::filesystem::path &root) {
    const std::filesystem::path manifest = write_fixture(
        root, false, RelocationCase::none, 0x1001U, 2U, false, 0U, 4096U,
        false, false, false, true);
    kzm::host::ValidatedContent content =
        kzm::host::validate_content_manifest(manifest, root / L"app0");
    BundleFixture fixture(content, completed_entry);
    fixture.add_zero_site_variable_import();
    g_entry_calls = 0U;
    kzm::host::Logger logger = quiet_logger();
    kzm::host::PreparedTitle prepared =
        kzm::host::prepare_title(content, fixture.bundle, logger);
    check(fixture.variable_storage == 0U,
          "unreferenced zero-site variable received an invented address");
    const kzm::host::TitleCallResult result = std::move(prepared).execute();
    check(result.outcome == kzm::host::TitleCallOutcome::completed &&
              g_entry_calls == 1U,
          "unreferenced zero-site variable blocked title entry");
}

void test_segmented_variable_import(const std::filesystem::path &root) {
    const std::filesystem::path manifest = write_fixture(
        root, false, RelocationCase::none, 0x1001U, 2U, false, 0U, 4096U,
        false, false, false, false, true);
    kzm::host::ValidatedContent content =
        kzm::host::validate_content_manifest(manifest, root / L"app0");
    BundleFixture fixture(content, completed_entry);
    fixture.add_segmented_variable_import();
    g_entry_calls = 0U;
    kzm::host::Logger logger = quiet_logger();
    kzm::host::PreparedTitle prepared =
        kzm::host::prepare_title(content, fixture.bundle, logger);
    check(fixture.variable_storage == 0x4000U,
          "runtime variable provider did not bind the validated target");
    check(vita_read32(0x4000U) == UINT32_C(0x0DEADBEE),
          "stack guard provider did not initialize the validated target");
    const kzm::host::TitleCallResult result = std::move(prepared).execute();
    check(result.outcome == kzm::host::TitleCallOutcome::completed &&
              g_entry_calls == 1U,
          "runtime variable provider blocked title entry");
}

void test_strict_variable_import(const std::filesystem::path &root) {
    const std::filesystem::path manifest = write_fixture(
        root, false, RelocationCase::none, 0x1001U, 2U, false, 0U, 4096U,
        false, false, false, false, false, true);
    kzm::host::ValidatedContent content =
        kzm::host::validate_content_manifest(manifest, root / L"app0");
    BundleFixture fixture(content, strict_variable_entry);
    fixture.add_strict_variable_import();
    g_entry_calls = 0U;
    g_after_strict = 0U;
    kzm::host::Logger logger = quiet_logger();
    kzm::host::PreparedTitle prepared =
        kzm::host::prepare_title(content, fixture.bundle, logger);
    check(fixture.variable_storage == 0x4000U,
          "strict variable provider did not bind the validated target");
    const kzm::host::TitleCallResult result = std::move(prepared).execute();
    check(result.outcome == kzm::host::TitleCallOutcome::strict_failure &&
              result.strict_kind ==
                  VITA_STRICT_FAILURE_UNRESOLVED_VARIABLE &&
              result.target_address == 0x4000U &&
              result.nid == UINT32_C(0x11110002) &&
              std::string_view(result.strict_name.data()) ==
                  "FixtureVariable::segmented" &&
              g_entry_calls == 1U && g_after_strict == 0U,
          "unresolved variable access did not stop at the strict boundary");
}

void test_failed_preconditions(const std::filesystem::path &root) {
    {
        const std::filesystem::path case_root = root / L"identity";
        const std::filesystem::path manifest = write_fixture(case_root);
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest, case_root / L"app0");
        BundleFixture fixture(content, completed_entry);
        fixture.identity[0] = fixture.identity[0] == '0' ? '1' : '0';
        fixture.bundle.expected_runtime_manifest_sha256 = fixture.identity;
        g_entry_calls = 0U;
        expect_preparation_failure(
            content, fixture.bundle,
            kzm::host::TitlePreparationStage::content_identity);
    }
    {
        const std::filesystem::path case_root = root / L"descriptor";
        const std::filesystem::path manifest = write_fixture(case_root);
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest, case_root / L"app0");
        BundleFixture fixture(content, completed_entry);
        fixture.descriptor.module_name = "wrong_module";
        g_entry_calls = 0U;
        expect_preparation_failure(
            content, fixture.bundle,
            kzm::host::TitlePreparationStage::descriptor_agreement);
    }
    {
        const std::filesystem::path case_root = root / L"preflight";
        const std::filesystem::path manifest = write_fixture(case_root, true);
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest, case_root / L"app0");
        BundleFixture fixture(content, completed_entry);
        g_entry_calls = 0U;
        expect_preparation_failure(
            content, fixture.bundle,
            kzm::host::TitlePreparationStage::module_preflight);
    }
}

void test_entry_relocation_contract(const std::filesystem::path &root) {
    {
        const std::filesystem::path case_root = root / L"clear-retail";
        const std::filesystem::path manifest = write_fixture(
            case_root, false, RelocationCase::none, 0x1000U,
            UINT16_C(0xFE00));
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest,
                                                 case_root / L"app0");
        BundleFixture fixture(content, completed_entry, 0x1000U, 0x1001U);
        g_entry_calls = 0U;
        kzm::host::Logger logger = quiet_logger();
        kzm::host::PreparedTitle prepared =
            kzm::host::prepare_title(content, fixture.bundle, logger);
        const kzm::host::TitleCallResult result =
            std::move(prepared).execute();
        check(result.outcome == kzm::host::TitleCallOutcome::completed &&
                  g_entry_calls == 1U,
              "clear-bit retail entry did not resolve to Thumb dispatch");
    }
    {
        const std::filesystem::path case_root = root / L"mode-mismatch";
        const std::filesystem::path manifest = write_fixture(
            case_root, false, RelocationCase::none, 0x1000U,
            UINT16_C(0xFE00));
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest,
                                                 case_root / L"app0");
        BundleFixture fixture(content, completed_entry, 0x1000U, 0x1000U);
        g_entry_calls = 0U;
        expect_preparation_failure(
            content, fixture.bundle,
            kzm::host::TitlePreparationStage::descriptor_agreement);
    }
}

void test_relocation_preflight(const std::filesystem::path &root) {
    {
        const std::filesystem::path case_root = root / L"valid";
        const std::filesystem::path manifest =
            write_fixture(case_root, false,
                          RelocationCase::valid_identity);
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest,
                                                 case_root / L"app0");
        BundleFixture fixture(content, completed_entry);
        g_entry_calls = 0U;
        kzm::host::Logger logger = quiet_logger();
        kzm::host::PreparedTitle prepared =
            kzm::host::prepare_title(content, fixture.bundle, logger);
        const kzm::host::TitleCallResult result =
            std::move(prepared).execute();
        check(result.outcome == kzm::host::TitleCallOutcome::completed &&
                  g_entry_calls == 1U,
              "idempotent relocation stream did not reach the entry");
    }

    const std::array cases{
        std::pair{L"one-byte", RelocationCase::malformed_one_byte},
        std::pair{L"unknown-format", RelocationCase::unknown_format},
        std::pair{L"trailing-record", RelocationCase::trailing_record},
        std::pair{L"unsupported-code", RelocationCase::unsupported_code},
        std::pair{L"changed-image", RelocationCase::changed_image},
        std::pair{L"outside-file", RelocationCase::outside_file},
    };
    for (const auto &[name, relocation] : cases) {
        const std::filesystem::path case_root = root / name;
        const std::filesystem::path manifest =
            write_fixture(case_root, false, relocation);
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest,
                                                 case_root / L"app0");
        BundleFixture fixture(content, completed_entry);
        g_entry_calls = 0U;
        expect_preparation_failure(
            content, fixture.bundle,
            kzm::host::TitlePreparationStage::module_preflight);
    }
}

void test_function_import_descriptor_agreement(
    const std::filesystem::path &root) {
    {
        const std::filesystem::path case_root = root / L"valid-independent";
        const std::filesystem::path manifest = write_fixture(
            case_root, false, RelocationCase::none, 0x1001U, 2U, true);
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest,
                                                 case_root / L"app0");
        BundleFixture fixture(content, completed_entry);
        fixture.add_function_import();
        g_entry_calls = 0U;
        kzm::host::Logger logger = quiet_logger();
        kzm::host::PreparedTitle prepared =
            kzm::host::prepare_title(content, fixture.bundle, logger);
        const kzm::host::TitleCallResult result =
            std::move(prepared).execute();
        check(result.outcome == kzm::host::TitleCallOutcome::completed &&
                  g_entry_calls == 1U,
              "resolved target word was incorrectly used as local stub key");
    }
    {
        const std::filesystem::path case_root = root / L"site-mismatch";
        const std::filesystem::path manifest = write_fixture(
            case_root, false, RelocationCase::none, 0x1001U, 2U, true);
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest,
                                                 case_root / L"app0");
        BundleFixture fixture(content, completed_entry);
        fixture.add_function_import(0x198U);
        g_entry_calls = 0U;
        expect_preparation_failure(
            content, fixture.bundle,
            kzm::host::TitlePreparationStage::module_preflight);
    }
    {
        const std::filesystem::path case_root = root / L"nid-mismatch";
        const std::filesystem::path manifest = write_fixture(
            case_root, false, RelocationCase::none, 0x1001U, 2U, true);
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest,
                                                 case_root / L"app0");
        BundleFixture fixture(content, completed_entry);
        fixture.add_function_import(0x194U, UINT32_C(0x11110002));
        g_entry_calls = 0U;
        expect_preparation_failure(
            content, fixture.bundle,
            kzm::host::TitlePreparationStage::module_preflight);
    }
    {
        const std::filesystem::path case_root = root / L"duplicate-record";
        const std::filesystem::path manifest = write_fixture(
            case_root, false, RelocationCase::none, 0x1001U, 2U, true);
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest,
                                                 case_root / L"app0");
        BundleFixture fixture(content, completed_entry);
        fixture.add_function_import();
        fixture.function_imports[1] = fixture.function_imports[0];
        fixture.descriptor.function_import_count = 2U;
        g_entry_calls = 0U;
        expect_preparation_failure(
            content, fixture.bundle,
            kzm::host::TitlePreparationStage::module_preflight);
    }
    {
        const std::filesystem::path case_root =
            root / L"tls-variable-import";
        const std::filesystem::path manifest = write_fixture(
            case_root, false, RelocationCase::none, 0x1001U, 2U, false,
            0U, 4096U, true);
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest,
                                                 case_root / L"app0");
        BundleFixture fixture(content, completed_entry);
        g_entry_calls = 0U;
        expect_preparation_failure(
            content, fixture.bundle,
            kzm::host::TitlePreparationStage::module_preflight);
    }
}

void test_tls_readiness(const std::filesystem::path &root) {
    {
        const std::filesystem::path case_root = root / L"materialized";
        const std::filesystem::path manifest = write_fixture(
            case_root, false, RelocationCase::none, 0x1001U, 2U, false,
            0x1000U, 64U);
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest,
                                                 case_root / L"app0");
        BundleFixture fixture(content, tls_entry, 0x1001U, 0x1001U,
                              0x1000U, 64U);
        g_entry_calls = 0U;
        g_entry_tls_base = 0U;
        g_entry_tls_image.fill(0U);
        kzm::host::Logger logger = quiet_logger();
        kzm::host::PreparedTitle prepared =
            kzm::host::prepare_title(content, fixture.bundle, logger);
        const kzm::host::TitleCallResult result =
            std::move(prepared).execute();
        check(result.outcome == kzm::host::TitleCallOutcome::completed &&
                  g_entry_calls == 1U && g_entry_tls_base != 0U,
              "main TLS was not materialized before entry");
        check(g_entry_tls_image ==
                  std::array<std::uint8_t, 5>{
                      0xA1U, 0xB2U, 0xC3U, 0xD4U, 0U},
              "main TLS initialized bytes were not copied");
        g_entry_tls_base = 0U;
        g_entry_tls_image.fill(0U);
        kzm::host::PreparedTitle repeated =
            kzm::host::prepare_title(content, fixture.bundle, logger);
        const kzm::host::TitleCallResult repeated_result =
            std::move(repeated).execute();
        check(repeated_result.outcome ==
                      kzm::host::TitleCallOutcome::completed &&
                  g_entry_calls == 2U && g_entry_tls_base != 0U &&
                  g_entry_tls_image ==
                      std::array<std::uint8_t, 5>{
                          0xA1U, 0xB2U, 0xC3U, 0xD4U, 0U},
              "repeated title preparation did not rebuild main TLS");
    }
    {
        const std::filesystem::path case_root =
            root / L"descriptor-alignment";
        const std::filesystem::path manifest = write_fixture(
            case_root, false, RelocationCase::none, 0x1001U, 2U, false,
            0x1000U, 64U);
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest,
                                                 case_root / L"app0");
        BundleFixture fixture(content, completed_entry, 0x1001U, 0x1001U,
                              0x1000U, 64U);
        fixture.descriptor.tls.alignment = 32U;
        g_entry_calls = 0U;
        expect_preparation_failure(
            content, fixture.bundle,
            kzm::host::TitlePreparationStage::descriptor_agreement);
    }
    {
        const std::filesystem::path case_root = root / L"aggregate-offset";
        const std::filesystem::path manifest = write_fixture(
            case_root, false, RelocationCase::none, 0x1001U, 2U, false,
            0x1000U, 64U);
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest,
                                                 case_root / L"app0");
        BundleFixture fixture(content, completed_entry, 0x1001U, 0x1001U,
                              0x1000U, 64U);
        fixture.tls_entries[0].expected_offset = 16U;
        g_entry_calls = 0U;
        expect_preparation_failure(
            content, fixture.bundle, kzm::host::TitlePreparationStage::tls);
    }
    {
        const std::filesystem::path case_root =
            root / L"insufficient-arena";
        constexpr std::uint32_t oversized_tls = 4U * 1024U * 1024U;
        const std::filesystem::path manifest = write_fixture(
            case_root, false, RelocationCase::none, 0x1001U, 2U, false,
            oversized_tls, 16U);
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest,
                                                 case_root / L"app0");
        BundleFixture fixture(content, completed_entry, 0x1001U, 0x1001U,
                              oversized_tls, 16U);
        g_entry_calls = 0U;
        expect_preparation_failure(
            content, fixture.bundle, kzm::host::TitlePreparationStage::tls);
        check(g_entry_calls == 0U,
              "TLS materialization failure reached title entry");
    }
}

void test_strict_and_exit(const std::filesystem::path &root) {
    {
        const std::filesystem::path case_root = root / L"strict";
        const std::filesystem::path manifest = write_fixture(case_root);
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest, case_root / L"app0");
        BundleFixture fixture(content, strict_entry);
        g_entry_calls = 0U;
        g_after_strict = 0U;
        kzm::host::Logger logger = quiet_logger();
        kzm::host::PreparedTitle prepared =
            kzm::host::prepare_title(content, fixture.bundle, logger);
        const kzm::host::TitleCallResult result = std::move(prepared).execute();
        check(result.outcome == kzm::host::TitleCallOutcome::strict_failure,
              "strict failure was not returned explicitly");
        check(std::string_view(result.strict_name.data()) ==
                  "synthetic strict failure",
              "strict failure name was not retained");
        check(g_entry_calls == 1U && g_after_strict == 0U,
              "strict failure continued or called entry more than once");
    }
    {
        const std::filesystem::path case_root = root / L"exit";
        const std::filesystem::path manifest = write_fixture(case_root);
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest, case_root / L"app0");
        BundleFixture fixture(content, exit_entry);
        g_entry_calls = 0U;
        kzm::host::Logger logger = quiet_logger();
        kzm::host::PreparedTitle prepared =
            kzm::host::prepare_title(content, fixture.bundle, logger);
        const kzm::host::TitleCallResult result = std::move(prepared).execute();
        check(result.outcome == kzm::host::TitleCallOutcome::exit_requested &&
                  result.status == 23 && g_entry_calls == 1U,
              "exit request was not returned explicitly");
    }
}

} // namespace

int main() {
    static_assert(!std::is_copy_constructible_v<kzm::host::ValidatedContent>);
    static_assert(
        std::is_nothrow_move_constructible_v<kzm::host::ValidatedContent>);
    static_assert(!std::is_copy_constructible_v<kzm::host::PreparedTitle>);
    const std::filesystem::path root =
        std::filesystem::current_path() / L"title-session-unit-work";
    try {
        std::error_code ignored;
        std::filesystem::remove_all(root, ignored);
        std::filesystem::create_directories(root);
        test_completion_and_retained_bytes(root / L"completion");
        test_data_address_function_export(root / L"data-export");
        test_manifest_segment_order(root / L"segment-order");
        test_zero_site_variable_import(root / L"zero-site-variable");
        test_segmented_variable_import(root / L"segmented-variable");
        test_strict_variable_import(root / L"strict-variable");
        test_failed_preconditions(root);
        test_entry_relocation_contract(root / L"entry-contract");
        test_relocation_preflight(root / L"relocations");
        test_function_import_descriptor_agreement(root / L"imports");
        test_tls_readiness(root / L"tls");
        test_strict_and_exit(root);
        std::filesystem::remove_all(root, ignored);
        std::cout << "title session tests passed\n";
        return 0;
    } catch (const kzm::host::TitlePreparationError &error) {
        std::cerr << "title session tests failed at "
                  << kzm::host::title_preparation_stage_name(error.stage())
                  << " (" << error.status() << ")\n";
        std::error_code ignored;
        std::filesystem::remove_all(root, ignored);
        return 1;
    } catch (const std::exception &error) {
        std::cerr << "title session tests failed: " << error.what() << '\n';
        std::error_code ignored;
        std::filesystem::remove_all(root, ignored);
        return 1;
    }
}
