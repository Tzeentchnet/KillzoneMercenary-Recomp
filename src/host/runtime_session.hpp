// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "host/logging.hpp"
#include "host/manifest.hpp"

namespace kzm::host {

class RuntimeSession {
public:
    explicit RuntimeSession(Logger& logger);
    ~RuntimeSession();

    RuntimeSession(const RuntimeSession&) = delete;
    RuntimeSession& operator=(const RuntimeSession&) = delete;

    void mount_app0(const ValidatedContent& content);

private:
    Logger& logger_;
    bool initialized_ = false;
};

} // namespace kzm::host
