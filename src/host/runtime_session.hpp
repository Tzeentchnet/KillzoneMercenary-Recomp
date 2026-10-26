// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "game/title_config.hpp"
#include "host/logging.hpp"
#include "host/manifest.hpp"

#include <cstdint>

namespace kzm::host {

class RuntimeSession {
  public:
    explicit RuntimeSession(Logger &logger);
    RuntimeSession(Logger &logger, const game::RuntimeMemoryLayout &layout);
    ~RuntimeSession();

    RuntimeSession(const RuntimeSession &) = delete;
    RuntimeSession &operator=(const RuntimeSession &) = delete;

    void mount_app0(const ValidatedContent &content);
    [[nodiscard]] std::uint32_t prepare_main_stack(std::uint32_t base,
                                                   std::uint32_t size);

  private:
    Logger &logger_;
    bool initialized_ = false;
};

} // namespace kzm::host
