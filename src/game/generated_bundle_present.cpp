// SPDX-License-Identifier: GPL-2.0-or-later
#include "game/generated_bundle.hpp"
#include "game/title_config.hpp"

#include "generated_bundle_identity.hpp"
#include KZMRECOMP_GENERATED_REGISTRY_HEADER

#include "vitarecomp/dispatch.h"

#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
#include <atomic>
#endif

namespace kzm::game {
namespace {

#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
std::atomic<std::uint32_t> g_entry_call_count{0U};
#endif

void generated_entry_trampoline() {
#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
    g_entry_call_count.fetch_add(1U, std::memory_order_relaxed);
#endif
    vita_call(vita_generated_image_entry());
}

std::span<const std::string_view> support_module_start_order() noexcept {
#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
    if (vita_generated_image_module_count == 1U &&
        vita_generated_image_modules[0] != nullptr &&
        vita_generated_image_modules[0]->module_name != nullptr &&
        std::string_view(vita_generated_image_modules[0]->module_name) ==
            "synthetic_module") {
        return {};
    }
#endif
    return kSupportingModuleStartOrder;
}

} // namespace

GeneratedBundleInfo generated_bundle_info() noexcept {
    return GeneratedBundleInfo{
        .present = true,
        .expected_runtime_manifest_sha256 =
            detail::kExpectedRuntimeManifestSha256,
        .module_descriptors = vita_generated_image_modules,
        .module_count = vita_generated_image_module_count,
        .tls_layout = &vita_generated_image_tls_layout,
        .dispatch_entries = vita_generated_image_dispatch,
        .dispatch_count = vita_generated_image_dispatch_count,
        .entry_module = vita_generated_image_entry_module(),
        .generated_entry = vita_generated_image_entry(),
        .callable_entry = generated_entry_trampoline,
        .support_module_start_order = support_module_start_order(),
    };
}

#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
std::uint32_t generated_entry_call_count_for_test() noexcept {
    return g_entry_call_count.load(std::memory_order_relaxed);
}

void reset_generated_entry_call_count_for_test() noexcept {
    g_entry_call_count.store(0U, std::memory_order_relaxed);
}
#endif

} // namespace kzm::game
