// SPDX-License-Identifier: GPL-2.0-or-later
#include "host/title_application.hpp"

#include "game/generated_bundle.hpp"
#include "host/exit_codes.hpp"
#include "host/title_session.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <utility>

namespace kzm::host {
namespace {

std::string index_text(std::uint32_t index) {
    return index == UINT32_MAX ? "none" : std::to_string(index);
}

#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
std::string entry_call_count() {
    return std::to_string(game::generated_entry_call_count_for_test());
}
#endif

} // namespace

int run_title_application(const ValidatedContent &content, Logger &logger) {
    const game::GeneratedBundleInfo bundle = game::generated_bundle_info();
    if (!bundle.present) {
        logger.log(LogLevel::error, "title_not_implemented",
                   "title execution is disabled because no generated bundle is "
                   "configured",
                   {
                       {"exit_code",
                        std::to_string(
                            value(ExitCode::title_not_implemented))},
#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
                       {"entry_calls", entry_call_count()},
#endif
                   });
        return value(ExitCode::title_not_implemented);
    }

#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
    game::reset_generated_entry_call_count_for_test();
#endif
    std::optional<PreparedTitle> prepared;
    try {
        prepared.emplace(prepare_title(content, bundle, logger));
    } catch (const TitlePreparationError &error) {
        logger.log(
            LogLevel::error, "title_precondition_failed",
            "title preparation rejected a required precondition",
            {
                {"stage",
                 std::string(title_preparation_stage_name(error.stage()))},
                {"status", std::to_string(error.status())},
                {"module_index", index_text(error.module_index())},
                {"record_index", index_text(error.record_index())},
                {"site_index", index_text(error.site_index())},
#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
                {"entry_calls", entry_call_count()},
#endif
                {"exit_code",
                 std::to_string(value(ExitCode::title_precondition_failed))},
            });
        return value(ExitCode::title_precondition_failed);
    } catch (...) {
        logger.log(LogLevel::error, "title_precondition_failed",
                   "title preparation failed safely",
                   {
                       {"stage", "internal"},
#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
                       {"entry_calls", entry_call_count()},
#endif
                       {"exit_code", std::to_string(value(
                                         ExitCode::title_precondition_failed))},
                   });
        return value(ExitCode::title_precondition_failed);
    }

    const TitleCallResult result = std::move(*prepared).execute();
    switch (result.outcome) {
    case TitleCallOutcome::completed:
        logger.log(
            LogLevel::info, "title_entry_completed",
            "generated title entry returned through the strict guest boundary",
            {
#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
                {"entry_calls", entry_call_count()},
#endif
                {"exit_code", "0"},
            });
        return value(ExitCode::success);
    case TitleCallOutcome::exit_requested:
        logger.log(LogLevel::warning, "title_exit_requested",
                   "generated title entry explicitly requested process exit",
                   {
                       {"requested_status", std::to_string(result.status)},
#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
                       {"entry_calls", entry_call_count()},
#endif
                       {"exit_code",
                        std::to_string(value(ExitCode::title_exit_requested))},
                   });
        return value(ExitCode::title_exit_requested);
    case TitleCallOutcome::strict_failure:
        logger.log(
            LogLevel::error, "title_strict_failure",
            "generated title entry stopped at the first strict failure",
            {
                {"kind", std::to_string(result.strict_kind)},
                {"source_address", std::to_string(result.source_address)},
                {"target_address", std::to_string(result.target_address)},
                {"nid", std::to_string(result.nid)},
                {"name", result.strict_name.data()},
#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
                {"entry_calls", entry_call_count()},
#endif
                {"exit_code",
                 std::to_string(value(ExitCode::title_strict_failure))},
            });
        return value(ExitCode::title_strict_failure);
    case TitleCallOutcome::boundary_error:
        logger.log(LogLevel::error, "title_precondition_failed",
                   "strict guest entry boundary rejected the prepared call",
                   {
                       {"stage", "guest_call"},
                       {"status", std::to_string(result.status)},
#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
                       {"entry_calls", entry_call_count()},
#endif
                       {"exit_code", std::to_string(value(
                                         ExitCode::title_precondition_failed))},
                   });
        return value(ExitCode::title_precondition_failed);
    }
    return value(ExitCode::internal_error);
}

} // namespace kzm::host
