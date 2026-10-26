// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <array>
#include <cstdint>
#include <filesystem>
#include <span>
#include <string>

namespace kzm::host {

using Sha256Digest = std::array<std::uint8_t, 32>;

[[nodiscard]] Sha256Digest sha256_handle(void *native_handle);
[[nodiscard]] Sha256Digest sha256_file(const std::filesystem::path &path);
[[nodiscard]] Sha256Digest sha256_bytes(std::span<const std::uint8_t> bytes);
[[nodiscard]] std::string sha256_hex(const Sha256Digest &digest);

} // namespace kzm::host
