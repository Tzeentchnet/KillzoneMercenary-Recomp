// SPDX-License-Identifier: GPL-2.0-or-later
#include "game/generated_bundle.hpp"

#include <algorithm>
#include <iostream>
#include <string_view>

#ifndef KZMRECOMP_TEST_EXPECT_GENERATED_BUNDLE
#error "The generated-bundle test expectation must be explicit."
#endif

namespace {

bool is_lower_hex_sha256(std::string_view value) {
    return value.size() == 64U &&
           std::all_of(value.begin(), value.end(), [](char character) {
               return (character >= '0' && character <= '9') ||
                      (character >= 'a' && character <= 'f');
           });
}

} // namespace

int main() {
    const kzm::game::GeneratedBundleInfo bundle =
        kzm::game::generated_bundle_info();
#if KZMRECOMP_TEST_EXPECT_GENERATED_BUNDLE
    if (!bundle.present ||
        !is_lower_hex_sha256(bundle.expected_runtime_manifest_sha256) ||
        bundle.module_descriptors == nullptr || bundle.module_count == 0U ||
        bundle.tls_layout == nullptr ||
        bundle.tls_layout->abi_version !=
            VITA_GENERATED_MODULE_ABI_VERSION ||
        bundle.tls_layout->struct_size <
            sizeof(vita_generated_tls_layout) ||
        bundle.tls_layout->descriptor_count != bundle.module_count ||
        bundle.dispatch_entries == nullptr || bundle.dispatch_count == 0U ||
        bundle.entry_module == nullptr || bundle.generated_entry == nullptr ||
        bundle.callable_entry == nullptr) {
        std::cerr << "generated bundle adapter presence check failed\n";
        return 1;
    }
#else
    if (bundle.present || !bundle.expected_runtime_manifest_sha256.empty() ||
        bundle.module_descriptors != nullptr || bundle.module_count != 0U ||
        bundle.tls_layout != nullptr ||
        bundle.dispatch_entries != nullptr || bundle.dispatch_count != 0U ||
        bundle.entry_module != nullptr || bundle.generated_entry != nullptr ||
        bundle.callable_entry != nullptr) {
        std::cerr << "absent generated bundle adapter check failed\n";
        return 1;
    }
#endif
#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
    kzm::game::reset_generated_entry_call_count_for_test();
    if (kzm::game::generated_entry_call_count_for_test() != 0U) {
        std::cerr << "generated entry counter did not reset\n";
        return 1;
    }
#endif
    std::cout << "generated bundle adapter tests passed\n";
    return 0;
}
