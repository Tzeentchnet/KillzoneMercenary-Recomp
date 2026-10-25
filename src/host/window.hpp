// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <cstdint>
#include <optional>
#include <utility>

namespace kzm::host {

class Window {
public:
    Window(std::uint32_t width, std::uint32_t height);
    ~Window();

    Window(const Window&) = delete;
    Window& operator=(const Window&) = delete;

    [[nodiscard]] HWND native_handle() const noexcept;
    [[nodiscard]] bool closed() const noexcept;
    [[nodiscard]] bool minimized() const noexcept;
    [[nodiscard]] std::pair<std::uint32_t, std::uint32_t>
        client_size() const noexcept;

    void pump_messages();
    [[nodiscard]] std::optional<std::pair<std::uint32_t, std::uint32_t>>
        take_resize();
    void exercise_minimize_restore_resize(
        std::uint32_t width,
        std::uint32_t height);

private:
    static LRESULT CALLBACK window_proc(
        HWND window,
        UINT message,
        WPARAM wparam,
        LPARAM lparam);
    LRESULT handle_message(
        HWND window,
        UINT message,
        WPARAM wparam,
        LPARAM lparam);

    HINSTANCE instance_ = nullptr;
    HWND window_ = nullptr;
    std::uint32_t width_ = 0;
    std::uint32_t height_ = 0;
    bool closed_ = false;
    bool minimized_ = false;
    bool resize_pending_ = false;
};

} // namespace kzm::host
