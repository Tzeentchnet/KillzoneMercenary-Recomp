// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <cstddef>
#include <cstdint>
#include <string_view>

namespace kzm::game {

inline constexpr std::string_view kTitleId = "PCSA00107";
inline constexpr std::string_view kDisplayName = "Killzone Mercenary Recomp";

struct RuntimeMemoryLayout {
    std::uint32_t memory_base;
    std::size_t memory_size;
    std::uint32_t heap_base;
    std::uint32_t heap_size;
    std::uint32_t sysmem_base;
    std::uint32_t sysmem_size;
    std::uint32_t kernel_base;
    std::uint32_t kernel_size;
};

[[nodiscard]] RuntimeMemoryLayout scaffold_memory_layout() noexcept;
[[nodiscard]] bool title_execution_ready() noexcept;
[[nodiscard]] std::string_view title_execution_blocker() noexcept;

} // namespace kzm::game
