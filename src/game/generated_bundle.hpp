// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "vitarecomp/generated_module.h"
#include "vitarecomp/runtime.h"

#include <cstdint>
#include <span>
#include <string_view>

namespace kzm::game {

struct GeneratedBundleInfo {
    bool present;
    std::string_view expected_runtime_manifest_sha256;
    const vita_generated_module_descriptor *const *module_descriptors;
    std::uint32_t module_count;
    const vita_generated_tls_layout *tls_layout;
    const vita_dispatch_entry *dispatch_entries;
    std::uint32_t dispatch_count;
    const vita_generated_module_descriptor *entry_module;
    vita_guest_entry_fn generated_entry;
    vita_guest_entry_fn callable_entry;
    std::span<const std::string_view> support_module_start_order;
};

[[nodiscard]] GeneratedBundleInfo generated_bundle_info() noexcept;

#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
[[nodiscard]] std::uint32_t generated_entry_call_count_for_test() noexcept;
void reset_generated_entry_call_count_for_test() noexcept;
#endif

} // namespace kzm::game
