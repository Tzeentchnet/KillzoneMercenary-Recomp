// SPDX-License-Identifier: GPL-2.0-or-later
#include "game/generated_bundle.hpp"

namespace kzm::game {

GeneratedBundleInfo generated_bundle_info() noexcept {
    return GeneratedBundleInfo{
        .present = false,
        .expected_runtime_manifest_sha256 = {},
        .module_descriptors = nullptr,
        .module_count = 0U,
        .tls_layout = nullptr,
        .dispatch_entries = nullptr,
        .dispatch_count = 0U,
        .entry_module = nullptr,
        .generated_entry = nullptr,
        .callable_entry = nullptr,
    };
}

#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
std::uint32_t generated_entry_call_count_for_test() noexcept { return 0U; }

void reset_generated_entry_call_count_for_test() noexcept {}
#endif

} // namespace kzm::game
