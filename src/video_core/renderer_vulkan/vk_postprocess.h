// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#pragma once

#include <chrono>
#include <filesystem>
#include <string>
#include <unordered_map>
#include <vector>
#include "common/common_types.h"
#include "video_core/renderer_vulkan/vk_common.h"

VK_DEFINE_HANDLE(VmaAllocation)

namespace Vulkan {

class Instance;
class Scheduler;
struct Frame;

/**
 * vkBasalt / ReShade style post processing applied to the finished frame of the main window.
 *
 * The chain is described by a vkBasalt.conf or a ReShade preset (Settings reshade_config_path),
 * see video_core/post_process. Every pass is a fullscreen triangle that samples the previous
 * result; the last result is copied back into the frame so presentation is unchanged.
 */
class PostProcessChain {
public:
    explicit PostProcessChain(const Instance& instance, Scheduler& scheduler, vk::Format format);
    ~PostProcessChain();

    /// Records the chain after the frame was drawn. Returns false when nothing was applied.
    bool Apply(Frame* frame);

private:
    struct Target {
        vk::Image image;
        VmaAllocation allocation{};
        vk::ImageView view;
        vk::Framebuffer framebuffer;
        vk::DescriptorSet set;
    };
    struct Pass {
        std::string name;
        vk::ShaderModule fragment;
        vk::Pipeline pipeline;
    };

    bool NeedsRebuild(const Frame* frame);
    void Rebuild(u32 width, u32 height);
    void Destroy();
    bool CreateTargets(u32 width, u32 height);
    bool CreatePipelines(const std::vector<std::pair<std::string, std::string>>& fragments);
    vk::DescriptorSet GetFrameSet(vk::ImageView view);
    void WriteSet(vk::DescriptorSet set, vk::ImageView view);

    const Instance& instance;
    Scheduler& scheduler;
    vk::Format format;

    vk::Sampler linear_sampler;
    vk::Sampler point_sampler;
    vk::DescriptorSetLayout set_layout;
    vk::PipelineLayout pipeline_layout;
    vk::RenderPass render_pass;
    vk::DescriptorPool pool;
    vk::ShaderModule vertex_module;
    std::array<Target, 2> targets{};
    std::vector<Pass> passes;
    std::unordered_map<u64, vk::DescriptorSet> frame_sets;
    u32 pool_sets_used{};

    u32 width{};
    u32 height{};
    bool built{};
    bool enabled_last{};
    std::string config_path;
    std::filesystem::file_time_type config_time{};
    u32 frame_counter{};
    std::chrono::steady_clock::time_point start_time{std::chrono::steady_clock::now()};
    std::chrono::steady_clock::time_point last_frame{std::chrono::steady_clock::now()};
};

} // namespace Vulkan
