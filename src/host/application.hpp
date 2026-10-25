// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "host/logging.hpp"

#include <string>
#include <vector>

namespace kzm::host {

[[nodiscard]] int run_application(
    const std::vector<std::wstring>& arguments,
    Logger& logger);
void write_cli_text(std::string_view text);

} // namespace kzm::host
