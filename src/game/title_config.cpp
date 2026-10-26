// SPDX-License-Identifier: GPL-2.0-or-later
#include "game/title_config.hpp"

#include <algorithm>
#include <array>
#include <limits>
#include <vector>

namespace kzm::game {
namespace {

constexpr std::uint64_t kGuestAddressSpaceSize = UINT64_C(0x100000000);

bool is_power_of_two(std::uint32_t value) noexcept {
    return value != 0U && (value & (value - 1U)) == 0U;
}

bool align_up(std::uint64_t value, std::uint32_t alignment,
              std::uint64_t &result) noexcept {
    const std::uint64_t mask = static_cast<std::uint64_t>(alignment) - 1U;
    if (value > kGuestAddressSpaceSize - mask)
        return false;
    result = (value + mask) & ~mask;
    return result <= kGuestAddressSpaceSize;
}

bool add_guard_and_align(std::uint64_t &cursor,
                         const MemoryLayoutPolicy &policy) noexcept {
    if (cursor > kGuestAddressSpaceSize - policy.guard_size)
        return false;
    return align_up(cursor + policy.guard_size, policy.arena_alignment, cursor);
}

bool place_arena(std::uint64_t &cursor, std::uint32_t size,
                 std::uint32_t &base) noexcept {
    if (cursor > std::numeric_limits<std::uint32_t>::max() ||
        size > kGuestAddressSpaceSize - cursor) {
        return false;
    }
    base = static_cast<std::uint32_t>(cursor);
    cursor += size;
    return true;
}

} // namespace

MemoryLayoutPolicy title_memory_policy() noexcept {
    return MemoryLayoutPolicy{
        .window_alignment = UINT32_C(0x10000),
        .arena_alignment = UINT32_C(0x10000),
        .guard_size = UINT32_C(0x10000),
        .heap_size = 24U * 1024U * 1024U,
        .sysmem_size = 96U * 1024U * 1024U,
        .cdram_size = 128U * 1024U * 1024U,
        .phycont_size = 16U * 1024U * 1024U,
        .kernel_size = 8U * 1024U * 1024U,
        .stack_size = 4U * 1024U * 1024U,
        .tls_size = 4U * 1024U * 1024U,
        .maximum_window_size = 384U * 1024U * 1024U,
    };
}

MemoryLayoutStatus
plan_memory_layout(std::span<const GuestLoadRange> load_ranges,
                   const MemoryLayoutPolicy &policy,
                   RuntimeMemoryLayout &layout) {
    if (load_ranges.empty() || policy.heap_size == 0U ||
        policy.sysmem_size == 0U || policy.cdram_size == 0U ||
        policy.phycont_size == 0U || policy.kernel_size == 0U ||
        policy.stack_size == 0U || policy.tls_size == 0U ||
        policy.maximum_window_size == 0U) {
        return MemoryLayoutStatus::invalid_argument;
    }
    if (!is_power_of_two(policy.window_alignment) ||
        !is_power_of_two(policy.arena_alignment) ||
        policy.arena_alignment < 16U ||
        policy.window_alignment < policy.arena_alignment ||
        policy.window_alignment % policy.arena_alignment != 0U ||
        policy.guard_size % policy.arena_alignment != 0U) {
        return MemoryLayoutStatus::invalid_alignment;
    }
    const std::array<std::uint32_t, 7> arena_sizes{
        policy.heap_size, policy.sysmem_size, policy.cdram_size,
        policy.phycont_size, policy.kernel_size, policy.stack_size,
        policy.tls_size,
    };
    if (std::any_of(arena_sizes.begin(), arena_sizes.end(),
                    [&](std::uint32_t size) {
                        return size % policy.arena_alignment != 0U;
                    })) {
        return MemoryLayoutStatus::invalid_alignment;
    }

    std::vector<GuestLoadRange> sorted(load_ranges.begin(), load_ranges.end());
    std::sort(sorted.begin(), sorted.end(),
              [](const GuestLoadRange &left, const GuestLoadRange &right) {
                  if (left.base != right.base)
                      return left.base < right.base;
                  return left.size < right.size;
              });

    std::uint64_t highest = 0U;
    for (std::size_t index = 0U; index < sorted.size(); ++index) {
        const GuestLoadRange range = sorted[index];
        if (range.size == 0U)
            return MemoryLayoutStatus::invalid_argument;
        const std::uint64_t end =
            static_cast<std::uint64_t>(range.base) + range.size;
        if (end > kGuestAddressSpaceSize)
            return MemoryLayoutStatus::range_overflow;
        if (index != 0U) {
            const GuestLoadRange previous = sorted[index - 1U];
            const std::uint64_t previous_end =
                static_cast<std::uint64_t>(previous.base) + previous.size;
            if (range.base < previous_end)
                return MemoryLayoutStatus::overlapping_load_ranges;
        }
        highest = end;
    }

    const std::uint64_t window_base =
        static_cast<std::uint64_t>(sorted.front().base) &
        ~(static_cast<std::uint64_t>(policy.window_alignment) - 1U);
    std::uint64_t cursor = highest;
    RuntimeMemoryLayout planned{};
    if (!add_guard_and_align(cursor, policy) ||
        !place_arena(cursor, policy.heap_size, planned.heap_base) ||
        !add_guard_and_align(cursor, policy) ||
        !place_arena(cursor, policy.sysmem_size, planned.sysmem_base) ||
        !add_guard_and_align(cursor, policy) ||
        !place_arena(cursor, policy.cdram_size, planned.cdram_base) ||
        !add_guard_and_align(cursor, policy) ||
        !place_arena(cursor, policy.phycont_size,
                     planned.phycont_base) ||
        !add_guard_and_align(cursor, policy) ||
        !place_arena(cursor, policy.kernel_size, planned.kernel_base) ||
        !add_guard_and_align(cursor, policy) ||
        !place_arena(cursor, policy.stack_size, planned.stack_base) ||
        !add_guard_and_align(cursor, policy) ||
        !place_arena(cursor, policy.tls_size, planned.tls_base)) {
        return MemoryLayoutStatus::range_overflow;
    }

    std::uint64_t window_end = 0U;
    if (!align_up(cursor, policy.window_alignment, window_end) ||
        window_end <= window_base) {
        return MemoryLayoutStatus::range_overflow;
    }
    const std::uint64_t window_size = window_end - window_base;
    if (window_size > policy.maximum_window_size)
        return MemoryLayoutStatus::window_too_large;
    if (window_base > std::numeric_limits<std::uint32_t>::max() ||
        window_size > std::numeric_limits<std::size_t>::max()) {
        return MemoryLayoutStatus::range_overflow;
    }

    planned.memory_base = static_cast<std::uint32_t>(window_base);
    planned.memory_size = static_cast<std::size_t>(window_size);
    planned.heap_size = policy.heap_size;
    planned.sysmem_size = policy.sysmem_size;
    planned.cdram_size = policy.cdram_size;
    planned.phycont_size = policy.phycont_size;
    planned.kernel_size = policy.kernel_size;
    planned.stack_size = policy.stack_size;
    planned.tls_size = policy.tls_size;
    layout = planned;
    return MemoryLayoutStatus::success;
}

std::string_view
memory_layout_status_message(MemoryLayoutStatus status) noexcept {
    switch (status) {
    case MemoryLayoutStatus::success:
        return "success";
    case MemoryLayoutStatus::invalid_argument:
        return "invalid argument";
    case MemoryLayoutStatus::invalid_alignment:
        return "invalid alignment";
    case MemoryLayoutStatus::range_overflow:
        return "guest range overflow";
    case MemoryLayoutStatus::overlapping_load_ranges:
        return "overlapping load ranges";
    case MemoryLayoutStatus::window_too_large:
        return "planned guest window exceeds policy";
    }
    return "unknown memory-layout status";
}

RuntimeMemoryLayout scaffold_memory_layout() noexcept {
    constexpr std::uint32_t base = UINT32_C(0x10000000);
    return RuntimeMemoryLayout{
        .memory_base = base,
        .memory_size = 64U * 1024U * 1024U,
        .heap_base = base,
        .heap_size = 24U * 1024U * 1024U,
        .sysmem_base = base + 32U * 1024U * 1024U,
        .sysmem_size = 16U * 1024U * 1024U,
        .cdram_base = 0U,
        .cdram_size = 0U,
        .phycont_base = 0U,
        .phycont_size = 0U,
        .kernel_base = base + 56U * 1024U * 1024U,
        .kernel_size = 8U * 1024U * 1024U,
        .stack_base = base + 24U * 1024U * 1024U,
        .stack_size = 4U * 1024U * 1024U,
        .tls_base = base + 28U * 1024U * 1024U,
        .tls_size = 4U * 1024U * 1024U,
    };
}

} // namespace kzm::game
