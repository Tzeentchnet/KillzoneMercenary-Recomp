// SPDX-License-Identifier: GPL-2.0-or-later
#include "host/window.hpp"

#include "game/title_config.hpp"

#include <stdexcept>
#include <string>

namespace kzm::host {
namespace {

constexpr wchar_t kWindowClass[] = L"KzmRecompNativeHostWindow";

} // namespace

Window::Window(std::uint32_t width, std::uint32_t height)
    : instance_(GetModuleHandleW(nullptr)), width_(width), height_(height) {
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.lpfnWndProc = window_proc;
    window_class.hInstance = instance_;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground =
        static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    window_class.lpszClassName = kWindowClass;
    if (RegisterClassExW(&window_class) == 0U &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        throw std::runtime_error("Win32 window class registration failed");
    }

    RECT rectangle{
        0,
        0,
        static_cast<LONG>(width),
        static_cast<LONG>(height),
    };
    if (AdjustWindowRectEx(
            &rectangle, WS_OVERLAPPEDWINDOW, FALSE, 0U) == FALSE) {
        (void)UnregisterClassW(kWindowClass, instance_);
        throw std::runtime_error("Win32 window sizing failed");
    }
    window_ = CreateWindowExW(
        0U,
        kWindowClass,
        L"Killzone Mercenary Recomp - Renderer Self-Test",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        rectangle.right - rectangle.left,
        rectangle.bottom - rectangle.top,
        nullptr,
        nullptr,
        instance_,
        this);
    if (window_ == nullptr) {
        (void)UnregisterClassW(kWindowClass, instance_);
        throw std::runtime_error("Win32 window creation failed");
    }
    ShowWindow(window_, SW_SHOWNOACTIVATE);
    UpdateWindow(window_);
    pump_messages();
    resize_pending_ = false;
}

Window::~Window() {
    if (window_ != nullptr) {
        (void)DestroyWindow(window_);
        window_ = nullptr;
        pump_messages();
    }
    (void)UnregisterClassW(kWindowClass, instance_);
}

HWND Window::native_handle() const noexcept {
    return window_;
}

bool Window::closed() const noexcept {
    return closed_;
}

bool Window::minimized() const noexcept {
    return minimized_;
}

std::pair<std::uint32_t, std::uint32_t>
Window::client_size() const noexcept {
    return {width_, height_};
}

void Window::pump_messages() {
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0U, 0U, PM_REMOVE) != FALSE) {
        if (message.message == WM_QUIT) {
            closed_ = true;
        }
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
}

std::optional<std::pair<std::uint32_t, std::uint32_t>>
Window::take_resize() {
    if (!resize_pending_ || minimized_ || width_ == 0U || height_ == 0U) {
        return std::nullopt;
    }
    resize_pending_ = false;
    return std::pair{width_, height_};
}

void Window::exercise_minimize_restore_resize(
    std::uint32_t width,
    std::uint32_t height) {
    ShowWindow(window_, SW_MINIMIZE);
    pump_messages();
    Sleep(20U);
    ShowWindow(window_, SW_RESTORE);

    RECT rectangle{
        0,
        0,
        static_cast<LONG>(width),
        static_cast<LONG>(height),
    };
    if (AdjustWindowRectEx(
            &rectangle, WS_OVERLAPPEDWINDOW, FALSE, 0U) == FALSE ||
        SetWindowPos(
            window_,
            nullptr,
            0,
            0,
            rectangle.right - rectangle.left,
            rectangle.bottom - rectangle.top,
            SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE) == FALSE) {
        throw std::runtime_error(
            "Win32 minimize, restore, and resize exercise failed");
    }
    pump_messages();
    if (minimized_ || width_ == 0U || height_ == 0U) {
        throw std::runtime_error("Win32 window did not restore after minimize");
    }
    resize_pending_ = true;
}

LRESULT CALLBACK Window::window_proc(
    HWND window,
    UINT message,
    WPARAM wparam,
    LPARAM lparam) {
    Window* self = reinterpret_cast<Window*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
        const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
        self = static_cast<Window*>(create->lpCreateParams);
        SetWindowLongPtrW(
            window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    if (self != nullptr) {
        return self->handle_message(window, message, wparam, lparam);
    }
    return DefWindowProcW(window, message, wparam, lparam);
}

LRESULT Window::handle_message(
    HWND window,
    UINT message,
    WPARAM wparam,
    LPARAM lparam) {
    switch (message) {
    case WM_CLOSE:
        closed_ = true;
        (void)DestroyWindow(window);
        return 0;
    case WM_DESTROY:
        window_ = nullptr;
        closed_ = true;
        return 0;
    case WM_SIZE:
        minimized_ = wparam == SIZE_MINIMIZED;
        if (!minimized_) {
            width_ = LOWORD(lparam);
            height_ = HIWORD(lparam);
            resize_pending_ = width_ != 0U && height_ != 0U;
        }
        return 0;
    default:
        return DefWindowProcW(window, message, wparam, lparam);
    }
}

} // namespace kzm::host
