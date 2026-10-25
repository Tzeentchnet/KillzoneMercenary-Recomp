// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <cstddef>
#include <filesystem>
#include <stdexcept>
#include <string>

namespace kzm::host {

class ManifestError final : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

struct ValidatedContent {
    std::filesystem::path canonical_root;
    std::string first_module_path;
    std::size_t module_count = 0;
    std::size_t load_segment_count = 0;
};

[[nodiscard]] ValidatedContent validate_content_manifest(
    const std::filesystem::path& manifest_path,
    const std::filesystem::path& content_root);

} // namespace kzm::host
