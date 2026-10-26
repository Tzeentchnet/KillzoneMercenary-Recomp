// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <string_view>

namespace kzm::game {

inline constexpr std::string_view kTitleId = "PCSA00107";
inline constexpr std::string_view kDisplayName = "Killzone Mercenary Recomp";
inline constexpr std::array<std::string_view, 2>
    kSupportingModuleStartOrder{"SceLibc", "SceLibFios2"};

struct RuntimeMemoryLayout {
    std::uint32_t memory_base;
    std::size_t memory_size;
    std::uint32_t heap_base;
    std::uint32_t heap_size;
    std::uint32_t sysmem_base;
    std::uint32_t sysmem_size;
    std::uint32_t cdram_base;
    std::uint32_t cdram_size;
    std::uint32_t phycont_base;
    std::uint32_t phycont_size;
    std::uint32_t kernel_base;
    std::uint32_t kernel_size;
    std::uint32_t stack_base;
    std::uint32_t stack_size;
    std::uint32_t tls_base;
    std::uint32_t tls_size;

    bool operator==(const RuntimeMemoryLayout &) const = default;
};

struct GuestLoadRange {
    std::uint32_t base;
    std::uint32_t size;
};

struct MemoryLayoutPolicy {
    std::uint32_t window_alignment;
    std::uint32_t arena_alignment;
    std::uint32_t guard_size;
    std::uint32_t heap_size;
    std::uint32_t sysmem_size;
    std::uint32_t cdram_size;
    std::uint32_t phycont_size;
    std::uint32_t kernel_size;
    std::uint32_t stack_size;
    std::uint32_t tls_size;
    std::uint32_t maximum_window_size;
};

enum class MemoryLayoutStatus {
    success,
    invalid_argument,
    invalid_alignment,
    range_overflow,
    overlapping_load_ranges,
    window_too_large,
};

[[nodiscard]] MemoryLayoutPolicy title_memory_policy() noexcept;
[[nodiscard]] MemoryLayoutStatus
plan_memory_layout(std::span<const GuestLoadRange> load_ranges,
                   const MemoryLayoutPolicy &policy,
                   RuntimeMemoryLayout &layout);
[[nodiscard]] std::string_view
memory_layout_status_message(MemoryLayoutStatus status) noexcept;
[[nodiscard]] RuntimeMemoryLayout scaffold_memory_layout() noexcept;

} // namespace kzm::game
