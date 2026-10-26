// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "game/title_config.hpp"
#include "host/sha256.hpp"

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

namespace kzm::host {

class ValidatedContent;

class ManifestError final : public std::runtime_error {
  public:
    using std::runtime_error::runtime_error;
};

struct ValidatedSegment {
    std::uint32_t program_header_index = 0U;
    std::uint32_t file_offset = 0U;
    std::uint32_t virtual_address = 0U;
    std::uint32_t physical_address = 0U;
    std::uint32_t file_size = 0U;
    std::uint32_t memory_size = 0U;
    std::uint32_t flags = 0U;
    std::uint32_t alignment = 0U;
};

class ValidatedModule final {
  public:
    [[nodiscard]] std::string_view relative_path() const noexcept;
    [[nodiscard]] std::string_view module_name() const noexcept;
    [[nodiscard]] std::uint16_t elf_type() const noexcept;
    [[nodiscard]] std::uint16_t machine() const noexcept;
    [[nodiscard]] std::uint32_t entry() const noexcept;
    [[nodiscard]] std::uint32_t elf_flags() const noexcept;
    [[nodiscard]] std::uint16_t program_header_count() const noexcept;
    [[nodiscard]] std::span<const ValidatedSegment> segments() const noexcept;
    [[nodiscard]] std::span<const std::uint8_t> bytes() const noexcept;

  private:
    std::string relative_path_;
    std::string module_name_;
    std::uint16_t elf_type_ = 0U;
    std::uint16_t machine_ = 0U;
    std::uint32_t entry_ = 0U;
    std::uint32_t elf_flags_ = 0U;
    std::uint16_t program_header_count_ = 0U;
    std::vector<ValidatedSegment> segments_;
    std::vector<std::uint8_t> bytes_;

    friend class ValidatedContent;
    friend ValidatedContent
    validate_content_manifest(const std::filesystem::path &manifest_path,
                              const std::filesystem::path &content_root);
};

class ValidatedContent final {
  public:
    ValidatedContent() = default;
    ~ValidatedContent() = default;
    ValidatedContent(const ValidatedContent &) = delete;
    ValidatedContent &operator=(const ValidatedContent &) = delete;
    ValidatedContent(ValidatedContent &&) noexcept = default;
    ValidatedContent &operator=(ValidatedContent &&) noexcept = default;

    [[nodiscard]] const std::filesystem::path &canonical_root() const noexcept;
    [[nodiscard]] const Sha256Digest &manifest_identity() const noexcept;
    [[nodiscard]] std::span<const ValidatedModule> modules() const noexcept;
    [[nodiscard]] std::size_t module_count() const noexcept;
    [[nodiscard]] std::size_t load_segment_count() const noexcept;
    [[nodiscard]] std::span<const game::GuestLoadRange>
    load_ranges() const noexcept;

  private:
    std::filesystem::path canonical_root_;
    Sha256Digest manifest_identity_{};
    std::vector<ValidatedModule> modules_;
    std::size_t load_segment_count_ = 0U;
    std::vector<game::GuestLoadRange> load_ranges_;

    friend ValidatedContent
    validate_content_manifest(const std::filesystem::path &manifest_path,
                              const std::filesystem::path &content_root);
};

[[nodiscard]] ValidatedContent
validate_content_manifest(const std::filesystem::path &manifest_path,
                          const std::filesystem::path &content_root);

} // namespace kzm::host
