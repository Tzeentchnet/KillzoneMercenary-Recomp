// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "host/cli.hpp"
#include "host/exit_codes.hpp"
#include "host/logging.hpp"
#include "host/window.hpp"

#include "vitarecomp/gpu.h"

#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>

namespace kzm::host {

class RendererError final : public std::runtime_error {
public:
    RendererError(ExitCode exit_code, std::string message);
    [[nodiscard]] ExitCode exit_code() const noexcept;

private:
    ExitCode exit_code_;
};

class RendererSession {
public:
    RendererSession(
        const HostConfig& config,
        Window& window,
        Logger& logger);
    ~RendererSession();

    RendererSession(const RendererSession&) = delete;
    RendererSession& operator=(const RendererSession&) = delete;

    [[nodiscard]] std::uint64_t run_self_test(std::uint32_t frames);

private:
    void initialize();
    void select_adapter();
    void create_device();
    void create_swapchain();
    void create_shaders_and_pipeline();
    void create_synchronization();
    void resize(std::uint32_t width, std::uint32_t height);
    std::uint64_t render_frame(bool capture);
    void cleanup() noexcept;

    void require(
        vita_gpu_result result,
        const vita_gpu_error& error,
        std::string_view operation,
        ExitCode default_code);
    [[nodiscard]] std::vector<std::uint8_t> load_shader(
        std::wstring_view file_name);
    [[nodiscard]] vita_gpu_backend requested_backend() const noexcept;

    const HostConfig& config_;
    Window& window_;
    Logger& logger_;
    vita_gpu_backend_info backend_info_{};
    vita_gpu_adapter_info adapter_info_{};
    vita_gpu_device_capabilities capabilities_{};
    std::uint32_t adapter_index_ = 0;
    std::uint32_t width_ = 0;
    std::uint32_t height_ = 0;
    vita_gpu_device device_{};
    vita_gpu_swapchain swapchain_{};
    vita_gpu_shader_module vertex_shader_{};
    vita_gpu_shader_module pixel_shader_{};
    vita_gpu_pipeline pipeline_{};
    vita_gpu_command_list command_{};
    vita_gpu_fence fence_{};
    vita_gpu_readback active_readback_{};
    bool readback_mapped_ = false;
    std::uint64_t fence_value_ = 0;
};

} // namespace kzm::host
