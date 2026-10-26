// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

namespace kzm::host {

enum class ExitCode : int {
    success = 0,
    invalid_arguments = 2,
    content_invalid = 3,
    backend_unavailable = 4,
    adapter_unavailable = 5,
    graphics_initialization_failed = 6,
    render_failed = 7,
    runtime_failed = 8,
    title_not_implemented = 9,
    window_failed = 10,
    title_precondition_failed = 11,
    title_strict_failure = 12,
    title_exit_requested = 13,
    internal_error = 70,
};

[[nodiscard]] constexpr int value(ExitCode code) noexcept {
    return static_cast<int>(code);
}

} // namespace kzm::host
