// SPDX-License-Identifier: GPL-2.0-or-later
#include "game/title_config.hpp"

namespace kzm::game {

RuntimeMemoryLayout scaffold_memory_layout() noexcept {
    constexpr std::uint32_t base = UINT32_C(0x10000000);
    return RuntimeMemoryLayout{
        .memory_base = base,
        .memory_size = 64U * 1024U * 1024U,
        .heap_base = base,
        .heap_size = 24U * 1024U * 1024U,
        .sysmem_base = base + 32U * 1024U * 1024U,
        .sysmem_size = 16U * 1024U * 1024U,
        .kernel_base = base + 56U * 1024U * 1024U,
        .kernel_size = 8U * 1024U * 1024U,
    };
}

bool title_execution_ready() noexcept {
    return false;
}

std::string_view title_execution_blocker() noexcept {
    return "generated title code and strict import preconditions are absent";
}

} // namespace kzm::game
