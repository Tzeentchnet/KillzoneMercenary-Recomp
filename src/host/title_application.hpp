// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "host/logging.hpp"
#include "host/manifest.hpp"

namespace kzm::host {

[[nodiscard]] int run_title_application(const ValidatedContent &content,
                                        Logger &logger);

} // namespace kzm::host
