// SPDX-License-Identifier: GPL-2.0-or-later
#include "game/title_config.hpp"
#include "host/cli.hpp"
#include "host/logging.hpp"
#include "host/manifest.hpp"
#include "host/sha256.hpp"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdio>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

class TestFailure final : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

void check(bool condition, std::string_view message) {
    if (!condition) throw TestFailure(std::string(message));
}

void write_u16(
    std::vector<std::uint8_t>& bytes,
    std::size_t offset,
    std::uint16_t value) {
    bytes.at(offset) = static_cast<std::uint8_t>(value);
    bytes.at(offset + 1U) = static_cast<std::uint8_t>(value >> 8U);
}

void write_u32(
    std::vector<std::uint8_t>& bytes,
    std::size_t offset,
    std::uint32_t value) {
    for (unsigned index = 0U; index < 4U; ++index) {
        bytes.at(offset + index) =
            static_cast<std::uint8_t>(value >> (index * 8U));
    }
}

void write_synthetic_elf(
    const std::filesystem::path& path,
    std::uint32_t base,
    std::string_view module_name,
    bool ready = true) {
    std::vector<std::uint8_t> bytes(512U, 0U);
    if (ready) {
        bytes[0] = 0x7FU;
        bytes[1] = 'E';
        bytes[2] = 'L';
        bytes[3] = 'F';
        bytes[4] = 1U;
        bytes[5] = 1U;
        bytes[6] = 1U;
        write_u16(bytes, 16U, 2U);
        write_u16(bytes, 18U, 40U);
        write_u32(bytes, 20U, 1U);
        write_u32(bytes, 24U, 0x100U);
        write_u32(bytes, 28U, 52U);
        write_u16(bytes, 40U, 52U);
        write_u16(bytes, 42U, 32U);
        write_u16(bytes, 44U, 1U);

        write_u32(bytes, 52U, 1U);
        write_u32(bytes, 56U, 0U);
        write_u32(bytes, 60U, base);
        write_u32(bytes, 68U, 512U);
        write_u32(bytes, 72U, 4096U);
        write_u32(bytes, 76U, 5U);
        write_u32(bytes, 80U, 4096U);

        write_u16(bytes, 0x102U, 0x0100U);
        for (std::size_t index = 0U; index < module_name.size(); ++index) {
            bytes.at(0x104U + index) =
                static_cast<std::uint8_t>(module_name[index]);
        }
    } else {
        constexpr std::string_view marker = "synthetic-protected-input";
        std::copy(marker.begin(), marker.end(), bytes.begin());
    }
    std::filesystem::create_directories(path.parent_path());
    std::ofstream stream(path, std::ios::binary);
    stream.write(
        reinterpret_cast<const char*>(bytes.data()),
        static_cast<std::streamsize>(bytes.size()));
    if (!stream) throw TestFailure("failed to write synthetic ELF");
}

struct ModuleFixture {
    std::string path;
    std::string name;
    std::uint32_t base;
    std::string hash;
};

std::string module_json(const ModuleFixture& module) {
    char base[11]{};
    char end[11]{};
    char info[11]{};
    (void)std::snprintf(base, sizeof(base), "0x%08X", module.base);
    (void)std::snprintf(end, sizeof(end), "0x%08X", module.base + 4096U);
    (void)std::snprintf(info, sizeof(info), "0x%08X", module.base + 0x100U);
    return
        "    {\n"
        "      \"path\": \"" + module.path + "\",\n"
        "      \"sha256\": \"" + module.hash + "\",\n"
        "      \"fileSize\": 512,\n"
        "      \"moduleInfo\": {\n"
        "        \"name\": \"" + module.name + "\",\n"
        "        \"encodedEntry\": \"0x00000100\",\n"
        "        \"segmentIndex\": 0,\n"
        "        \"segmentOffset\": 256,\n"
        "        \"virtualAddress\": \"" + info + "\"\n"
        "      },\n"
        "      \"programHeaderCount\": 1,\n"
        "      \"loadSegments\": [\n"
        "        {\n"
        "          \"index\": 0,\n"
        "          \"fileOffset\": 0,\n"
        "          \"fileSize\": 512,\n"
        "          \"virtualAddress\": \"" + base + "\",\n"
        "          \"memorySize\": 4096,\n"
        "          \"rangeEndExclusive\": \"" + end + "\",\n"
        "          \"flags\": \"r-x\",\n"
        "          \"alignment\": 4096\n"
        "        }\n"
        "      ]\n"
        "    }";
}

std::string manifest_json(
    std::string_view title,
    const std::vector<ModuleFixture>& modules) {
    std::string module_text;
    for (std::size_t index = 0U; index < modules.size(); ++index) {
        if (index != 0U) module_text += ",\n";
        module_text += module_json(modules[index]);
    }
    return
        "{\n"
        "  \"schemaVersion\": 1,\n"
        "  \"titleId\": \"" + std::string(title) + "\",\n"
        "  \"sourceArchive\": {\n"
        "    \"path\": \"C:\\\\synthetic\\\\public.zip\",\n"
        "    \"sha256\": "
        "\"0000000000000000000000000000000000000000000000000000000000000000\"\n"
        "  },\n"
        "  \"vita3k\": {\n"
        "    \"sourceRevision\": \"0000000\",\n"
        "    \"dumpCapability\": \"--dump-elfs\"\n"
        "  },\n"
        "  \"imageFormat\": {\n"
        "    \"elfClass\": \"ELF32\",\n"
        "    \"byteOrder\": \"little-endian\",\n"
        "    \"machine\": \"ARM\"\n"
        "  },\n"
        "  \"modules\": [\n" + module_text + "\n"
        "  ]\n"
        "}\n";
}

void write_text(
    const std::filesystem::path& path,
    std::string_view text) {
    std::ofstream stream(path, std::ios::binary);
    stream.write(text.data(), static_cast<std::streamsize>(text.size()));
    if (!stream) throw TestFailure("failed to write synthetic manifest");
}

void expect_manifest_failure(
    const std::filesystem::path& manifest,
    const std::filesystem::path& root,
    std::string_view expected) {
    try {
        (void)kzm::host::validate_content_manifest(manifest, root);
    } catch (const kzm::host::ManifestError& error) {
        check(
            std::string_view(error.what()).find(expected) !=
                std::string_view::npos,
            "manifest failed for an unexpected reason");
        return;
    }
    throw TestFailure("invalid manifest unexpectedly passed");
}

void test_cli() {
    using kzm::host::AdapterSelectionKind;
    using kzm::host::LogLevel;
    using kzm::host::Renderer;

    auto parsed = kzm::host::parse_command_line({
        L"host", L"--self-test", L"--renderer=dx12",
        L"--adapter=warp", L"--validation=off",
        L"--log-level=debug", L"--frames", L"7"});
    check(parsed.config.has_value(), "valid self-test CLI was rejected");
    check(parsed.config->renderer == Renderer::dx12, "renderer parse failed");
    check(
        parsed.config->adapter.kind == AdapterSelectionKind::warp,
        "adapter parse failed");
    check(parsed.config->frames == 7U, "frame parse failed");
    check(parsed.config->log_level == LogLevel::debug, "log parse failed");

    parsed = kzm::host::parse_command_line({
        L"host", L"--content-root", L"C:\\synthetic\\app0",
        L"--manifest=C:\\synthetic\\manifest.json",
        L"--renderer", L"vulkan", L"--adapter=3", L"--validation"});
    check(parsed.config.has_value(), "valid title-mode CLI was rejected");
    check(parsed.config->renderer == Renderer::vulkan, "Vulkan parse failed");
    check(
        parsed.config->adapter.kind == AdapterSelectionKind::index &&
            parsed.config->adapter.index == 3U,
        "numeric adapter parse failed");
    check(parsed.config->validation, "validation parse failed");

    const std::vector<std::vector<std::wstring>> invalid{
        {L"host", L"--renderer=dx12", L"--unknown"},
        {L"host", L"--self-test", L"--renderer=vulkan", L"--adapter=warp"},
        {L"host", L"--renderer=dx12", L"--content-root=C:\\synthetic"},
        {L"host", L"--renderer=dx12"},
        {L"host", L"--renderer=dx12", L"--frames=4",
         L"--content-root=C:\\a", L"--manifest=C:\\b"},
        {L"host", L"--self-test", L"--renderer=dx12",
         L"--renderer=vulkan"},
        {L"host", L"--self-test", L"--renderer=dx12", L"--frames=0"},
        {L"host", L"--help", L"--self-test"},
    };
    for (const auto& arguments : invalid) {
        check(
            !kzm::host::parse_command_line(arguments).config.has_value(),
            "invalid CLI combination unexpectedly passed");
    }
    check(
        kzm::host::parse_command_line({L"host", L"--help"})
            .config.has_value(),
        "standalone help was rejected");
}

void test_redaction() {
    std::string output;
    kzm::host::Logger logger(
        kzm::host::LogLevel::trace,
        [&](std::string_view line) { output.append(line); });
    logger.add_secret("private-token");
    const std::string hash(64U, 'a');
    logger.log(
        kzm::host::LogLevel::info,
        "redaction_test",
        "C:\\Users\\Synthetic\\private\\module.elf " + hash +
            " private-token");
    check(
        output.find("C:\\Users") == std::string::npos,
        "absolute path was not redacted");
    check(output.find(hash) == std::string::npos, "hash was not redacted");
    check(
        output.find("private-token") == std::string::npos,
        "registered secret was not redacted");
    check(
        output.find("<redacted-path>") != std::string::npos &&
            output.find("<redacted-sha256>") != std::string::npos,
        "redaction markers were not emitted");
}

void test_manifest(const std::filesystem::path& work_root) {
    const std::filesystem::path content = work_root / L"content";
    const std::filesystem::path manifest = work_root / L"manifest.json";
    std::filesystem::create_directories(content);
    const std::filesystem::path alpha = content / L"alpha.elf";
    write_synthetic_elf(alpha, 0x10000000U, "public_alpha");
    ModuleFixture first{
        "alpha.elf",
        "public_alpha",
        0x10000000U,
        kzm::host::sha256_hex(kzm::host::sha256_file(alpha)),
    };
    write_text(
        manifest,
        manifest_json(kzm::game::kTitleId, {first}));
    const kzm::host::ValidatedContent valid =
        kzm::host::validate_content_manifest(manifest, content);
    check(valid.module_count == 1U, "valid manifest module count is wrong");
    check(
        valid.load_segment_count == 1U,
        "valid manifest segment count is wrong");

    write_text(manifest, manifest_json("WRONG0000", {first}));
    expect_manifest_failure(manifest, content, "title ID");

    ModuleFixture traversal = first;
    traversal.path = "../escape.elf";
    write_text(
        manifest,
        manifest_json(kzm::game::kTitleId, {traversal}));
    expect_manifest_failure(manifest, content, "traversal");

    ModuleFixture wrong_hash = first;
    wrong_hash.hash[0] = wrong_hash.hash[0] == '0' ? '1' : '0';
    write_text(
        manifest,
        manifest_json(kzm::game::kTitleId, {wrong_hash}));
    expect_manifest_failure(manifest, content, "hash changed");

    const std::filesystem::path beta = content / L"beta.elf";
    write_synthetic_elf(beta, 0x10000000U, "public_beta");
    ModuleFixture second{
        "beta.elf",
        "public_beta",
        0x10000000U,
        kzm::host::sha256_hex(kzm::host::sha256_file(beta)),
    };
    write_text(
        manifest,
        manifest_json(kzm::game::kTitleId, {first, second}));
    expect_manifest_failure(manifest, content, "overlapping");

    const std::filesystem::path protected_file =
        content / L"protected.elf";
    write_synthetic_elf(
        protected_file, 0x20000000U, "public_protected", false);
    ModuleFixture protected_module{
        "protected.elf",
        "public_protected",
        0x20000000U,
        kzm::host::sha256_hex(kzm::host::sha256_file(protected_file)),
    };
    write_text(
        manifest,
        manifest_json(kzm::game::kTitleId, {protected_module}));
    expect_manifest_failure(manifest, content, "protected or not a ready");
}

} // namespace

int main() {
    const std::filesystem::path work_root =
        std::filesystem::current_path() / L"native-host-unit-work";
    try {
        std::error_code ignored;
        std::filesystem::remove_all(work_root, ignored);
        std::filesystem::create_directories(work_root);
        test_cli();
        test_redaction();
        test_manifest(work_root);
        check(
            !kzm::game::title_execution_ready(),
            "title execution must remain disabled");
        std::filesystem::remove_all(work_root, ignored);
        std::cout << "native host unit tests passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "native host unit tests failed: " << error.what() << '\n';
        std::error_code ignored;
        std::filesystem::remove_all(work_root, ignored);
        return 1;
    }
}
