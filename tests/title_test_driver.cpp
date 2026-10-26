// SPDX-License-Identifier: GPL-2.0-or-later
#include "host/logging.hpp"
#include "host/manifest.hpp"
#include "host/title_application.hpp"
#include "host/title_session.hpp"

#include <algorithm>
#include <array>
#include <filesystem>
#include <string>
#include <string_view>
#include <utility>

int wmain(int argc, wchar_t **argv) {
    kzm::host::Logger logger(kzm::host::LogLevel::debug);
    if ((argc != 3 && argc != 4) || argv == nullptr)
        return 2;
#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
    if (argc == 4) {
        constexpr std::array stages{
            std::pair{std::wstring_view(L"content_identity"),
                      kzm::host::TitlePreparationStage::content_identity},
            std::pair{std::wstring_view(L"memory_layout"),
                      kzm::host::TitlePreparationStage::memory_layout},
            std::pair{std::wstring_view(L"runtime_initialization"),
                      kzm::host::TitlePreparationStage::runtime_initialization},
            std::pair{std::wstring_view(L"content_mount"),
                      kzm::host::TitlePreparationStage::content_mount},
            std::pair{std::wstring_view(L"module_preflight"),
                      kzm::host::TitlePreparationStage::module_preflight},
            std::pair{std::wstring_view(L"module_load"),
                      kzm::host::TitlePreparationStage::module_load},
            std::pair{std::wstring_view(L"descriptor_agreement"),
                      kzm::host::TitlePreparationStage::descriptor_agreement},
            std::pair{std::wstring_view(L"binding"),
                      kzm::host::TitlePreparationStage::binding},
            std::pair{std::wstring_view(L"stack"),
                      kzm::host::TitlePreparationStage::stack},
            std::pair{std::wstring_view(L"tls"),
                      kzm::host::TitlePreparationStage::tls},
            std::pair{std::wstring_view(L"cpu_state"),
                      kzm::host::TitlePreparationStage::cpu_state},
        };
        const std::wstring_view requested(argv[3]);
        const auto found = std::find_if(stages.begin(), stages.end(),
                                        [requested](const auto &candidate) {
                                            return candidate.first == requested;
                                        });
        if (found == stages.end())
            return 2;
        kzm::host::force_title_preparation_failure_for_test(found->second);
    }
#else
    if (argc == 4)
        return 2;
#endif
    const std::filesystem::path content_root(argv[1]);
    const std::filesystem::path manifest_path(argv[2]);
    logger.add_secret(kzm::host::utf8_from_wide(content_root.native()));
    logger.add_secret(kzm::host::utf8_from_wide(manifest_path.native()));
    try {
        kzm::host::ValidatedContent content =
            kzm::host::validate_content_manifest(manifest_path, content_root);
        logger.log(
            kzm::host::LogLevel::info, "content_validated",
            "synthetic title-driver content passed strict validation",
            {
                {"modules", std::to_string(content.module_count())},
                {"segments", std::to_string(content.load_segment_count())},
            });
        return kzm::host::run_title_application(content, logger);
    } catch (const kzm::host::ManifestError &error) {
        logger.log(kzm::host::LogLevel::error, "content_invalid", error.what());
        return 3;
    } catch (...) {
        logger.log(kzm::host::LogLevel::error, "content_invalid",
                   "synthetic title-driver validation failed safely");
        return 3;
    }
}
