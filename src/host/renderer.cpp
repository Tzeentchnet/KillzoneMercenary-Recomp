// SPDX-License-Identifier: GPL-2.0-or-later
#include "host/renderer.hpp"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <algorithm>
#include <array>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <sstream>

namespace kzm::host {
namespace {

constexpr std::array<float, 4> kClearColor{
    0.0625F, 0.125F, 0.25F, 1.0F};

std::filesystem::path executable_directory() {
    std::wstring buffer(32768U, L'\0');
    const DWORD length = GetModuleFileNameW(
        nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0U || length >= buffer.size()) {
        throw RendererError(
            ExitCode::graphics_initialization_failed,
            "host executable directory cannot be resolved");
    }
    buffer.resize(length);
    return std::filesystem::path(buffer).parent_path();
}

std::string adapter_type_name(vita_gpu_adapter_type type) {
    switch (type) {
    case VITA_GPU_ADAPTER_INTEGRATED: return "integrated";
    case VITA_GPU_ADAPTER_DISCRETE: return "discrete";
    case VITA_GPU_ADAPTER_SOFTWARE: return "software";
    case VITA_GPU_ADAPTER_OTHER: return "other";
    case VITA_GPU_ADAPTER_TYPE_FORCE_U32: break;
    }
    return "unknown";
}

std::uint32_t align_up(std::uint32_t value, std::uint32_t alignment) {
    if (alignment <= 1U) return value;
    const std::uint64_t result =
        (static_cast<std::uint64_t>(value) + alignment - 1U) /
        alignment * alignment;
    if (result > std::numeric_limits<std::uint32_t>::max()) {
        throw RendererError(
            ExitCode::render_failed,
            "readback row-pitch alignment overflowed");
    }
    return static_cast<std::uint32_t>(result);
}

std::string hexadecimal(std::uint64_t value) {
    std::ostringstream stream;
    stream << "0x" << std::hex << value;
    return stream.str();
}

} // namespace

RendererError::RendererError(ExitCode exit_code, std::string message)
    : std::runtime_error(std::move(message)), exit_code_(exit_code) {}

ExitCode RendererError::exit_code() const noexcept {
    return exit_code_;
}

RendererSession::RendererSession(
    const HostConfig& config,
    Window& window,
    Logger& logger)
    : config_(config), window_(window), logger_(logger) {
    const auto [width, height] = window_.client_size();
    width_ = width;
    height_ = height;
    try {
        initialize();
    } catch (...) {
        cleanup();
        throw;
    }
}

RendererSession::~RendererSession() {
    cleanup();
}

vita_gpu_backend RendererSession::requested_backend() const noexcept {
    return *config_.renderer == Renderer::dx12
        ? VITA_GPU_BACKEND_DX12
        : VITA_GPU_BACKEND_VULKAN;
}

void RendererSession::require(
    vita_gpu_result result,
    const vita_gpu_error& error,
    std::string_view operation,
    ExitCode default_code) {
    if (result == VITA_GPU_SUCCESS) return;
    ExitCode code = default_code;
    if (result == VITA_GPU_ERROR_BACKEND_UNAVAILABLE) {
        code = ExitCode::backend_unavailable;
    } else if (result == VITA_GPU_ERROR_ADAPTER_NOT_FOUND) {
        code = ExitCode::adapter_unavailable;
    }
    logger_.log(
        LogLevel::error,
        "gpu_operation_failed",
        std::string(operation) + " failed",
        {
            {"result", vita_gpu_result_string(result)},
            {"native_code", std::to_string(error.native_code)},
            {"function", error.function_name},
            {"backend_message", error.message},
        });
    throw RendererError(code, std::string(operation) + " failed");
}

void RendererSession::initialize() {
    const vita_gpu_backend backend = requested_backend();
    const std::uint32_t backend_count = vita_gpu_backend_count();
    bool found = false;
    for (std::uint32_t index = 0U; index < backend_count; ++index) {
        vita_gpu_backend_info info =
            VITA_GPU_INIT(vita_gpu_backend_info);
        vita_gpu_error error = VITA_GPU_INIT(vita_gpu_error);
        require(
            vita_gpu_get_backend_info(index, &info, &error),
            error,
            "query renderer backend",
            ExitCode::graphics_initialization_failed);
        if (info.backend == backend) {
            backend_info_ = info;
            found = true;
            break;
        }
    }
    if (!found || backend_info_.available == VITA_GPU_FALSE) {
        logger_.log(
            LogLevel::error,
            "backend_unavailable",
            "the explicitly selected renderer backend is unavailable",
            {
                {"backend", std::string(renderer_name(*config_.renderer))},
                {"reason", found
                    ? std::string(backend_info_.unavailable_reason)
                    : "backend is not registered"},
            });
        throw RendererError(
            ExitCode::backend_unavailable,
            "selected renderer backend is unavailable");
    }
    if (config_.validation &&
        backend_info_.validation_available == VITA_GPU_FALSE) {
        logger_.log(
            LogLevel::error,
            "validation_unavailable",
            "validation was requested but is unavailable for the selected backend",
            {{"backend", std::string(renderer_name(*config_.renderer))}});
        throw RendererError(
            ExitCode::backend_unavailable,
            "requested renderer validation is unavailable");
    }
    select_adapter();
    create_device();
    create_swapchain();
    create_shaders_and_pipeline();
    create_synchronization();
}

void RendererSession::select_adapter() {
    std::uint32_t count = 0U;
    vita_gpu_error error = VITA_GPU_INIT(vita_gpu_error);
    require(
        vita_gpu_adapter_count(requested_backend(), &count, &error),
        error,
        "enumerate renderer adapters",
        ExitCode::backend_unavailable);
    if (count == 0U) {
        throw RendererError(
            ExitCode::adapter_unavailable,
            "selected backend reported no compatible adapters");
    }

    bool selected = false;
    for (std::uint32_t index = 0U; index < count; ++index) {
        vita_gpu_adapter_info info =
            VITA_GPU_INIT(vita_gpu_adapter_info);
        error = vita_gpu_error VITA_GPU_INIT(vita_gpu_error);
        require(
            vita_gpu_get_adapter_info(
                requested_backend(), index, &info, &error),
            error,
            "query renderer adapter",
            ExitCode::adapter_unavailable);
        const bool matches =
            (config_.adapter.kind == AdapterSelectionKind::index &&
             config_.adapter.index == index) ||
            (config_.adapter.kind == AdapterSelectionKind::warp &&
             info.type == VITA_GPU_ADAPTER_SOFTWARE) ||
            (config_.adapter.kind == AdapterSelectionKind::hardware &&
             info.type != VITA_GPU_ADAPTER_SOFTWARE);
        if (matches) {
            adapter_index_ = index;
            adapter_info_ = info;
            selected = true;
            break;
        }
    }
    if (!selected) {
        logger_.log(
            LogLevel::error,
            "adapter_unavailable",
            "the explicitly selected adapter is unavailable",
            {
                {"backend", std::string(renderer_name(*config_.renderer))},
                {"selector", config_.adapter.kind ==
                        AdapterSelectionKind::warp
                    ? "warp"
                    : config_.adapter.kind == AdapterSelectionKind::hardware
                        ? "hardware"
                        : std::to_string(config_.adapter.index)},
            });
        throw RendererError(
            ExitCode::adapter_unavailable,
            "selected adapter is unavailable");
    }
    logger_.log(
        LogLevel::info,
        "adapter_selected",
        "renderer adapter selected without backend fallback",
        {
            {"backend", std::string(renderer_name(*config_.renderer))},
            {"adapter_index", std::to_string(adapter_index_)},
            {"adapter_name", adapter_info_.name},
            {"adapter_type", adapter_type_name(adapter_info_.type)},
            {"adapter_capabilities", hexadecimal(adapter_info_.capabilities)},
        });
}

void RendererSession::create_device() {
    vita_gpu_device_desc descriptor =
        VITA_GPU_INIT(vita_gpu_device_desc);
    descriptor.backend = requested_backend();
    descriptor.adapter_index = adapter_index_;
    descriptor.flags = VITA_GPU_DEVICE_ENABLE_DEBUG_NAMES;
    if (config_.validation) {
        descriptor.flags |= VITA_GPU_DEVICE_ENABLE_VALIDATION;
    }
    descriptor.application_name = "kzmrecomp-native-host";
    vita_gpu_error error = VITA_GPU_INIT(vita_gpu_error);
    require(
        vita_gpu_create_device(&descriptor, &device_, &error),
        error,
        "create renderer device",
        ExitCode::graphics_initialization_failed);

    capabilities_ = vita_gpu_device_capabilities
        VITA_GPU_INIT(vita_gpu_device_capabilities);
    require(
        vita_gpu_device_get_capabilities(
            device_, &capabilities_, &error),
        error,
        "query renderer capabilities",
        ExitCode::graphics_initialization_failed);
    const vita_gpu_capability_flags required =
        VITA_GPU_CAPABILITY_GRAPHICS |
        VITA_GPU_CAPABILITY_TIMELINE_FENCES;
    if ((capabilities_.flags & required) != required) {
        throw RendererError(
            ExitCode::graphics_initialization_failed,
            "renderer omitted required graphics capabilities");
    }
    logger_.log(
        LogLevel::info,
        "renderer_capabilities",
        "renderer device initialized",
        {
            {"backend", std::string(renderer_name(*config_.renderer))},
            {"validation", config_.validation ? "enabled" : "disabled"},
            {"flags", hexadecimal(capabilities_.flags)},
            {"max_texture_2d", std::to_string(capabilities_.max_texture_2d)},
            {"row_pitch_alignment",
                std::to_string(capabilities_.texture_row_pitch_alignment)},
        });
}

void RendererSession::create_swapchain() {
    vita_gpu_swapchain_desc descriptor =
        VITA_GPU_INIT(vita_gpu_swapchain_desc);
    descriptor.label = "kzmrecomp-self-test-swapchain";
    descriptor.window =
        vita_gpu_window_handle VITA_GPU_INIT(vita_gpu_window_handle);
    descriptor.window.system = VITA_GPU_WINDOW_WIN32;
    descriptor.window.native_window = window_.native_handle();
    descriptor.width = width_;
    descriptor.height = height_;
    descriptor.format = VITA_GPU_FORMAT_BGRA8_UNORM;
    descriptor.image_count = 3U;
    descriptor.present_mode = VITA_GPU_PRESENT_FIFO;
    vita_gpu_error error = VITA_GPU_INIT(vita_gpu_error);
    require(
        vita_gpu_create_swapchain(
            device_, &descriptor, &swapchain_, &error),
        error,
        "create Win32 swapchain",
        ExitCode::graphics_initialization_failed);
}

std::vector<std::uint8_t> RendererSession::load_shader(
    std::wstring_view file_name) {
    const std::filesystem::path path =
        executable_directory() / std::filesystem::path(file_name);
    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    if (!stream) {
        throw RendererError(
            ExitCode::graphics_initialization_failed,
            "compiled conformance shader is missing beside the host");
    }
    const std::streamoff length = stream.tellg();
    if (length <= 0 || length > 16 * 1024 * 1024) {
        throw RendererError(
            ExitCode::graphics_initialization_failed,
            "compiled conformance shader size is invalid");
    }
    std::vector<std::uint8_t> bytes(static_cast<std::size_t>(length));
    stream.seekg(0, std::ios::beg);
    stream.read(reinterpret_cast<char*>(bytes.data()), length);
    if (!stream) {
        throw RendererError(
            ExitCode::graphics_initialization_failed,
            "compiled conformance shader cannot be read");
    }
    return bytes;
}

void RendererSession::create_shaders_and_pipeline() {
    const bool dx12 = *config_.renderer == Renderer::dx12;
    const auto vertex_bytes = load_shader(
        dx12
            ? L"kzmrecomp_conformance_vs.dxil"
            : L"kzmrecomp_conformance_vs.spv");
    const auto pixel_bytes = load_shader(
        dx12
            ? L"kzmrecomp_conformance_ps.dxil"
            : L"kzmrecomp_conformance_ps.spv");
    const vita_gpu_shader_target target = dx12
        ? VITA_GPU_SHADER_TARGET_DXIL
        : VITA_GPU_SHADER_TARGET_SPIRV;

    vita_gpu_shader_binary_desc vertex_binary =
        VITA_GPU_INIT(vita_gpu_shader_binary_desc);
    vertex_binary.stage = VITA_GPU_SHADER_VERTEX;
    vertex_binary.target = target;
    vertex_binary.data = vertex_bytes.data();
    vertex_binary.data_size = vertex_bytes.size();
    vertex_binary.key =
        vita_gpu_shader_key VITA_GPU_INIT(vita_gpu_shader_key);
    vita_gpu_shader_module_desc vertex_descriptor =
        VITA_GPU_INIT(vita_gpu_shader_module_desc);
    vertex_descriptor.label = "kzmrecomp-conformance-vs";
    vertex_descriptor.input = VITA_GPU_SHADER_INPUT_BINARY;
    vertex_descriptor.binary = &vertex_binary;
    vita_gpu_error error = VITA_GPU_INIT(vita_gpu_error);
    require(
        vita_gpu_create_shader_module(
            device_, &vertex_descriptor, &vertex_shader_, &error),
        error,
        "create conformance vertex shader",
        ExitCode::graphics_initialization_failed);

    vita_gpu_shader_binary_desc pixel_binary =
        VITA_GPU_INIT(vita_gpu_shader_binary_desc);
    pixel_binary.stage = VITA_GPU_SHADER_PIXEL;
    pixel_binary.target = target;
    pixel_binary.data = pixel_bytes.data();
    pixel_binary.data_size = pixel_bytes.size();
    pixel_binary.key =
        vita_gpu_shader_key VITA_GPU_INIT(vita_gpu_shader_key);
    vita_gpu_shader_module_desc pixel_descriptor =
        VITA_GPU_INIT(vita_gpu_shader_module_desc);
    pixel_descriptor.label = "kzmrecomp-conformance-ps";
    pixel_descriptor.input = VITA_GPU_SHADER_INPUT_BINARY;
    pixel_descriptor.binary = &pixel_binary;
    require(
        vita_gpu_create_shader_module(
            device_, &pixel_descriptor, &pixel_shader_, &error),
        error,
        "create conformance pixel shader",
        ExitCode::graphics_initialization_failed);

    vita_gpu_graphics_pipeline_desc descriptor =
        VITA_GPU_INIT(vita_gpu_graphics_pipeline_desc);
    descriptor.label = "kzmrecomp-conformance-pipeline";
    descriptor.vertex_shader = vertex_shader_;
    descriptor.pixel_shader = pixel_shader_;
    descriptor.topology = VITA_GPU_TOPOLOGY_TRIANGLE_LIST;
    descriptor.rasterizer =
        vita_gpu_rasterizer_desc VITA_GPU_INIT(vita_gpu_rasterizer_desc);
    descriptor.rasterizer.polygon_mode = VITA_GPU_POLYGON_FILL;
    descriptor.rasterizer.cull_mode = VITA_GPU_CULL_NONE;
    descriptor.rasterizer.front_face =
        VITA_GPU_FRONT_COUNTER_CLOCKWISE;
    descriptor.depth_stencil = vita_gpu_depth_stencil_desc
        VITA_GPU_INIT(vita_gpu_depth_stencil_desc);
    descriptor.depth_stencil.depth_compare = VITA_GPU_COMPARE_ALWAYS;
    descriptor.color_target_count = 1U;
    descriptor.color_formats[0] = VITA_GPU_FORMAT_BGRA8_UNORM;
    descriptor.blend[0] = vita_gpu_blend_attachment_desc
        VITA_GPU_INIT(vita_gpu_blend_attachment_desc);
    descriptor.blend[0].source_color = VITA_GPU_BLEND_ONE;
    descriptor.blend[0].source_alpha = VITA_GPU_BLEND_ONE;
    descriptor.blend[0].color_write_mask = 0x0FU;
    descriptor.sample_count = 1U;
    require(
        vita_gpu_create_graphics_pipeline(
            device_, &descriptor, &pipeline_, &error),
        error,
        "create conformance graphics pipeline",
        ExitCode::graphics_initialization_failed);
}

void RendererSession::create_synchronization() {
    vita_gpu_command_list_desc command_descriptor =
        VITA_GPU_INIT(vita_gpu_command_list_desc);
    command_descriptor.label = "kzmrecomp-conformance-command";
    command_descriptor.queue = VITA_GPU_QUEUE_GRAPHICS;
    vita_gpu_error error = VITA_GPU_INIT(vita_gpu_error);
    require(
        vita_gpu_create_command_list(
            device_, &command_descriptor, &command_, &error),
        error,
        "create graphics command list",
        ExitCode::graphics_initialization_failed);

    vita_gpu_fence_desc fence_descriptor =
        VITA_GPU_INIT(vita_gpu_fence_desc);
    fence_descriptor.label = "kzmrecomp-conformance-fence";
    require(
        vita_gpu_create_fence(
            device_, &fence_descriptor, &fence_, &error),
        error,
        "create graphics fence",
        ExitCode::graphics_initialization_failed);
}

void RendererSession::resize(std::uint32_t width, std::uint32_t height) {
    if (width == width_ && height == height_) return;
    vita_gpu_error error = VITA_GPU_INIT(vita_gpu_error);
    require(
        vita_gpu_device_wait_idle(device_, &error),
        error,
        "wait before swapchain resize",
        ExitCode::render_failed);
    require(
        vita_gpu_swapchain_resize(
            device_, swapchain_, width, height, &error),
        error,
        "resize swapchain",
        ExitCode::render_failed);
    width_ = width;
    height_ = height;
}

std::uint64_t RendererSession::render_frame(bool capture) {
    vita_gpu_error error = VITA_GPU_INIT(vita_gpu_error);
    vita_gpu_swapchain_image image =
        VITA_GPU_INIT(vita_gpu_swapchain_image);
    require(
        vita_gpu_swapchain_acquire(
            device_, swapchain_, &image, &error),
        error,
        "acquire swapchain image",
        ExitCode::render_failed);
    require(
        vita_gpu_command_begin(device_, command_, &error),
        error,
        "begin graphics command list",
        ExitCode::render_failed);

    vita_gpu_resource_barrier to_render =
        VITA_GPU_INIT(vita_gpu_resource_barrier);
    to_render.kind = VITA_GPU_RESOURCE_TEXTURE;
    to_render.texture = image.texture;
    to_render.before = VITA_GPU_RESOURCE_STATE_PRESENT;
    to_render.after = VITA_GPU_RESOURCE_STATE_RENDER_TARGET;
    to_render.mip_count = 1U;
    to_render.array_layer_count = 1U;
    to_render.source_queue = VITA_GPU_QUEUE_GRAPHICS;
    to_render.destination_queue = VITA_GPU_QUEUE_GRAPHICS;
    require(
        vita_gpu_cmd_barriers(
            device_, command_, &to_render, 1U, &error),
        error,
        "transition swapchain image for rendering",
        ExitCode::render_failed);

    vita_gpu_color_attachment color =
        VITA_GPU_INIT(vita_gpu_color_attachment);
    color.target = image.render_target;
    color.load_op = VITA_GPU_LOAD_CLEAR;
    color.store_op = VITA_GPU_STORE_PRESERVE;
    std::copy(kClearColor.begin(), kClearColor.end(), color.clear_color);
    vita_gpu_render_pass_desc pass =
        VITA_GPU_INIT(vita_gpu_render_pass_desc);
    pass.color_attachments = &color;
    pass.color_attachment_count = 1U;
    require(
        vita_gpu_cmd_begin_render_pass(
            device_, command_, &pass, &error),
        error,
        "begin conformance render pass",
        ExitCode::render_failed);
    require(
        vita_gpu_cmd_bind_pipeline(
            device_, command_, pipeline_, &error),
        error,
        "bind conformance pipeline",
        ExitCode::render_failed);

    vita_gpu_viewport viewport = VITA_GPU_INIT(vita_gpu_viewport);
    viewport.width = static_cast<float>(width_);
    viewport.height = static_cast<float>(height_);
    viewport.max_depth = 1.0F;
    require(
        vita_gpu_cmd_set_viewport(
            device_, command_, &viewport, &error),
        error,
        "set conformance viewport",
        ExitCode::render_failed);
    vita_gpu_scissor scissor = VITA_GPU_INIT(vita_gpu_scissor);
    scissor.width = width_;
    scissor.height = height_;
    require(
        vita_gpu_cmd_set_scissor(
            device_, command_, &scissor, &error),
        error,
        "set conformance scissor",
        ExitCode::render_failed);
    vita_gpu_draw_desc draw = VITA_GPU_INIT(vita_gpu_draw_desc);
    draw.vertex_count = 3U;
    draw.instance_count = 1U;
    require(
        vita_gpu_cmd_draw(device_, command_, &draw, &error),
        error,
        "draw conformance triangle",
        ExitCode::render_failed);
    require(
        vita_gpu_cmd_end_render_pass(device_, command_, &error),
        error,
        "end conformance render pass",
        ExitCode::render_failed);

    const std::uint32_t alignment = std::max(
        1U, capabilities_.texture_row_pitch_alignment);
    const std::uint32_t row_pitch = align_up(width_ * 4U, alignment);
    if (capture) {
        vita_gpu_readback_desc descriptor =
            VITA_GPU_INIT(vita_gpu_readback_desc);
        descriptor.label = "kzmrecomp-conformance-readback";
        descriptor.byte_size =
            static_cast<std::uint64_t>(row_pitch) * height_;
        require(
            vita_gpu_create_readback(
                device_, &descriptor, &active_readback_, &error),
            error,
            "create conformance readback",
            ExitCode::render_failed);

        vita_gpu_resource_barrier to_copy =
            VITA_GPU_INIT(vita_gpu_resource_barrier);
        to_copy.kind = VITA_GPU_RESOURCE_TEXTURE;
        to_copy.texture = image.texture;
        to_copy.before = VITA_GPU_RESOURCE_STATE_RENDER_TARGET;
        to_copy.after = VITA_GPU_RESOURCE_STATE_COPY_SOURCE;
        to_copy.mip_count = 1U;
        to_copy.array_layer_count = 1U;
        to_copy.source_queue = VITA_GPU_QUEUE_GRAPHICS;
        to_copy.destination_queue = VITA_GPU_QUEUE_GRAPHICS;
        require(
            vita_gpu_cmd_barriers(
                device_, command_, &to_copy, 1U, &error),
            error,
            "transition conformance image for readback",
            ExitCode::render_failed);
        vita_gpu_texture_readback_copy_desc copy =
            VITA_GPU_INIT(vita_gpu_texture_readback_copy_desc);
        copy.source = image.texture;
        copy.destination = active_readback_;
        copy.row_pitch = row_pitch;
        copy.slice_pitch = row_pitch * height_;
        require(
            vita_gpu_cmd_copy_texture_to_readback(
                device_, command_, &copy, &error),
            error,
            "copy conformance image to readback",
            ExitCode::render_failed);

        vita_gpu_resource_barrier to_present =
            VITA_GPU_INIT(vita_gpu_resource_barrier);
        to_present.kind = VITA_GPU_RESOURCE_TEXTURE;
        to_present.texture = image.texture;
        to_present.before = VITA_GPU_RESOURCE_STATE_COPY_SOURCE;
        to_present.after = VITA_GPU_RESOURCE_STATE_PRESENT;
        to_present.mip_count = 1U;
        to_present.array_layer_count = 1U;
        to_present.source_queue = VITA_GPU_QUEUE_GRAPHICS;
        to_present.destination_queue = VITA_GPU_QUEUE_GRAPHICS;
        require(
            vita_gpu_cmd_barriers(
                device_, command_, &to_present, 1U, &error),
            error,
            "transition captured image for presentation",
            ExitCode::render_failed);
    } else {
        vita_gpu_resource_barrier to_present =
            VITA_GPU_INIT(vita_gpu_resource_barrier);
        to_present.kind = VITA_GPU_RESOURCE_TEXTURE;
        to_present.texture = image.texture;
        to_present.before = VITA_GPU_RESOURCE_STATE_RENDER_TARGET;
        to_present.after = VITA_GPU_RESOURCE_STATE_PRESENT;
        to_present.mip_count = 1U;
        to_present.array_layer_count = 1U;
        to_present.source_queue = VITA_GPU_QUEUE_GRAPHICS;
        to_present.destination_queue = VITA_GPU_QUEUE_GRAPHICS;
        require(
            vita_gpu_cmd_barriers(
                device_, command_, &to_present, 1U, &error),
            error,
            "transition image for presentation",
            ExitCode::render_failed);
    }
    require(
        vita_gpu_command_end(device_, command_, &error),
        error,
        "end graphics command list",
        ExitCode::render_failed);

    const std::array<vita_gpu_command_list, 1> commands{command_};
    vita_gpu_submit_desc submit = VITA_GPU_INIT(vita_gpu_submit_desc);
    submit.command_lists = commands.data();
    submit.command_list_count = 1U;
    submit.signal = vita_gpu_fence_point
        VITA_GPU_INIT(vita_gpu_fence_point);
    submit.signal.fence = fence_;
    submit.signal.value = ++fence_value_;
    require(
        vita_gpu_submit(
            device_, VITA_GPU_QUEUE_GRAPHICS, &submit, &error),
        error,
        "submit graphics command list",
        ExitCode::render_failed);
    require(
        vita_gpu_fence_wait(
            device_, fence_, fence_value_,
            UINT64_C(10000000000), &error),
        error,
        "wait for conformance frame",
        ExitCode::render_failed);
    require(
        vita_gpu_command_reset(device_, command_, &error),
        error,
        "reset graphics command list",
        ExitCode::render_failed);
    vita_gpu_present_desc present =
        VITA_GPU_INIT(vita_gpu_present_desc);
    present.image_index = image.image_index;
    require(
        vita_gpu_swapchain_present(
            device_, swapchain_, &present, &error),
        error,
        "present conformance frame",
        ExitCode::render_failed);

    std::uint64_t hash = 0U;
    if (capture) {
        vita_gpu_readback_map mapping =
            VITA_GPU_INIT(vita_gpu_readback_map);
        require(
            vita_gpu_map_readback(
                device_, active_readback_, &mapping, &error),
            error,
            "map conformance readback",
            ExitCode::render_failed);
        readback_mapped_ = true;
        if (mapping.data == nullptr ||
            mapping.byte_size <
                static_cast<std::uint64_t>(row_pitch) * height_ ||
            mapping.row_pitch != row_pitch) {
            throw RendererError(
                ExitCode::render_failed,
                "conformance readback layout is invalid");
        }
        constexpr std::array<int, 4> expected{64, 32, 16, 255};
        for (std::size_t channel = 0U; channel < expected.size(); ++channel) {
            const int actual = mapping.data[channel];
            if (actual < expected[channel] - 2 ||
                actual > expected[channel] + 2) {
                throw RendererError(
                    ExitCode::render_failed,
                    "conformance clear pixel did not match");
            }
        }
        const std::uint8_t* const center =
            mapping.data +
            static_cast<std::size_t>(height_ / 2U) * row_pitch +
            static_cast<std::size_t>(width_ / 2U) * 4U;
        const std::array<std::uint8_t, 4> clear{
            64U, 32U, 16U, 255U};
        if (std::memcmp(center, clear.data(), clear.size()) == 0) {
            throw RendererError(
                ExitCode::render_failed,
                "conformance triangle did not modify the center pixel");
        }
        hash = UINT64_C(1469598103934665603);
        for (std::uint32_t y = 0U; y < height_; ++y) {
            const std::uint8_t* const row =
                mapping.data + static_cast<std::size_t>(y) * row_pitch;
            for (std::uint32_t x = 0U; x < width_ * 4U; ++x) {
                hash ^= row[x];
                hash *= UINT64_C(1099511628211);
            }
        }
        require(
            vita_gpu_unmap_readback(
                device_, active_readback_, &error),
            error,
            "unmap conformance readback",
            ExitCode::render_failed);
        readback_mapped_ = false;
        require(
            vita_gpu_destroy_readback(
                device_, active_readback_, &error),
            error,
            "destroy conformance readback",
            ExitCode::render_failed);
        active_readback_ = {};
    }
    window_.pump_messages();
    return hash;
}

std::uint64_t RendererSession::run_self_test(std::uint32_t frames) {
    window_.exercise_minimize_restore_resize(800U, 450U);
    const auto resize_value = window_.take_resize();
    if (!resize_value.has_value()) {
        throw RendererError(
            ExitCode::window_failed,
            "window lifecycle exercise did not report a resize");
    }
    resize(resize_value->first, resize_value->second);
    logger_.log(
        LogLevel::info,
        "window_lifecycle_exercised",
        "Win32 minimize, restore, and swapchain resize completed",
        {
            {"width", std::to_string(width_)},
            {"height", std::to_string(height_)},
        });

    std::uint64_t hash = 0U;
    std::uint32_t frame = 0U;
    while (frame < frames) {
        window_.pump_messages();
        if (window_.closed()) {
            throw RendererError(
                ExitCode::window_failed,
                "window closed before self-test completed");
        }
        if (const auto requested = window_.take_resize()) {
            resize(requested->first, requested->second);
        }
        if (window_.minimized()) {
            Sleep(10U);
            continue;
        }
        const bool capture = frame + 1U == frames;
        const std::uint64_t frame_hash = render_frame(capture);
        if (capture) hash = frame_hash;
        ++frame;
    }
    logger_.log(
        LogLevel::info,
        "self_test_passed",
        "bounded renderer clear and triangle conformance passed",
        {
            {"backend", std::string(renderer_name(*config_.renderer))},
            {"frames", std::to_string(frames)},
            {"readback_fnv1a", hexadecimal(hash)},
        });
    return hash;
}

void RendererSession::cleanup() noexcept {
    if (device_.value == 0U) return;
    vita_gpu_error error = VITA_GPU_INIT(vita_gpu_error);
    (void)vita_gpu_device_wait_idle(device_, &error);
    if (readback_mapped_ && active_readback_.value != 0U) {
        (void)vita_gpu_unmap_readback(
            device_, active_readback_, &error);
        readback_mapped_ = false;
    }
    if (command_.value != 0U) {
        (void)vita_gpu_destroy_command_list(device_, command_, &error);
        command_ = {};
    }
    if (active_readback_.value != 0U) {
        (void)vita_gpu_destroy_readback(
            device_, active_readback_, &error);
        active_readback_ = {};
    }
    if (pipeline_.value != 0U) {
        (void)vita_gpu_destroy_pipeline(device_, pipeline_, &error);
        pipeline_ = {};
    }
    if (pixel_shader_.value != 0U) {
        (void)vita_gpu_destroy_shader_module(
            device_, pixel_shader_, &error);
        pixel_shader_ = {};
    }
    if (vertex_shader_.value != 0U) {
        (void)vita_gpu_destroy_shader_module(
            device_, vertex_shader_, &error);
        vertex_shader_ = {};
    }
    if (fence_.value != 0U) {
        (void)vita_gpu_destroy_fence(device_, fence_, &error);
        fence_ = {};
    }
    if (swapchain_.value != 0U) {
        (void)vita_gpu_destroy_swapchain(device_, swapchain_, &error);
        swapchain_ = {};
    }
    (void)vita_gpu_destroy_device(device_, &error);
    device_ = {};
    logger_.log(
        LogLevel::debug,
        "renderer_shutdown",
        "renderer and swapchain resources were released deterministically");
}

} // namespace kzm::host
