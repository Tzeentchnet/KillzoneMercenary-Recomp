// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "game/generated_bundle.hpp"
#include "host/logging.hpp"
#include "host/manifest.hpp"

#include <array>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <string_view>

namespace kzm::host {

enum class TitlePreparationStage {
    content_identity,
    memory_layout,
    runtime_initialization,
    content_mount,
    module_preflight,
    module_load,
    descriptor_agreement,
    binding,
    stack,
    tls,
    cpu_state,
};

[[nodiscard]] std::string_view
title_preparation_stage_name(TitlePreparationStage stage) noexcept;

class TitlePreparationError final : public std::runtime_error {
  public:
    TitlePreparationError(TitlePreparationStage stage, std::int32_t status,
                          std::uint32_t module_index = UINT32_MAX,
                          std::uint32_t record_index = UINT32_MAX,
                          std::uint32_t site_index = UINT32_MAX);

    [[nodiscard]] TitlePreparationStage stage() const noexcept;
    [[nodiscard]] std::int32_t status() const noexcept;
    [[nodiscard]] std::uint32_t module_index() const noexcept;
    [[nodiscard]] std::uint32_t record_index() const noexcept;
    [[nodiscard]] std::uint32_t site_index() const noexcept;

  private:
    TitlePreparationStage stage_;
    std::int32_t status_;
    std::uint32_t module_index_;
    std::uint32_t record_index_;
    std::uint32_t site_index_;
};

enum class TitleCallOutcome {
    completed,
    exit_requested,
    strict_failure,
    boundary_error,
};

struct TitleCallResult {
    static constexpr std::size_t strict_name_capacity = 128U;

    TitleCallOutcome outcome = TitleCallOutcome::boundary_error;
    std::int32_t status = 0;
    std::int32_t strict_kind = 0;
    std::uint32_t source_address = 0U;
    std::uint32_t target_address = 0U;
    std::uint32_t nid = 0U;
    std::array<char, strict_name_capacity> strict_name{};
};

class PreparedTitle final {
  public:
    ~PreparedTitle();
    PreparedTitle(PreparedTitle &&) noexcept;
    PreparedTitle &operator=(PreparedTitle &&) noexcept;
    PreparedTitle(const PreparedTitle &) = delete;
    PreparedTitle &operator=(const PreparedTitle &) = delete;

    [[nodiscard]] TitleCallResult execute() && noexcept;

  private:
    struct State;
    explicit PreparedTitle(std::unique_ptr<State> state) noexcept;
    std::unique_ptr<State> state_;

    friend PreparedTitle prepare_title(const ValidatedContent &content,
                                       const game::GeneratedBundleInfo &bundle,
                                       Logger &logger);
};

[[nodiscard]] PreparedTitle
prepare_title(const ValidatedContent &content,
              const game::GeneratedBundleInfo &bundle, Logger &logger);

#if defined(KZMRECOMP_ENABLE_TEST_SEAMS)
void force_title_preparation_failure_for_test(
    TitlePreparationStage stage) noexcept;
void clear_title_preparation_failure_for_test() noexcept;
#endif

} // namespace kzm::host
