// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#include <random>
#include "common/logging/log.h"
#include "common/settings.h"
#include "video_core/post_process/chain_config.h"
#include "video_core/post_process/reshade_fx.h"
#include "video_core/renderer_vulkan/vk_instance.h"
#include "video_core/renderer_vulkan/vk_postprocess.h"
#include "video_core/renderer_vulkan/vk_present_window.h"
#include "video_core/renderer_vulkan/vk_scheduler.h"
#include "video_core/renderer_vulkan/vk_shader_util.h"

#include <vk_mem_alloc.h>

namespace Vulkan {

namespace fs = std::filesystem;

namespace {
constexpr u32 kMaxPasses = 16;
constexpr u32 kMaxDescriptorSets = 24;

void ImageBarrier(vk::CommandBuffer cmdbuf, vk::Image image, vk::ImageLayout from,
                  vk::ImageLayout to, vk::PipelineStageFlags src_stage, vk::AccessFlags src_access,
                  vk::PipelineStageFlags dst_stage, vk::AccessFlags dst_access) {
    const vk::ImageMemoryBarrier barrier = {
        .srcAccessMask = src_access,
        .dstAccessMask = dst_access,
        .oldLayout = from,
        .newLayout = to,
        .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresourceRange{
            .aspectMask = vk::ImageAspectFlagBits::eColor,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };
    cmdbuf.pipelineBarrier(src_stage, dst_stage, vk::DependencyFlags{}, {}, {}, barrier);
}
} // namespace

PostProcessChain::PostProcessChain(const Instance& instance_, Scheduler& scheduler_,
                                   vk::Format format_)
    : instance{instance_}, scheduler{scheduler_}, format{format_} {
    const vk::Device device = instance.GetDevice();

    const auto make_sampler = [&](vk::Filter filter) {
        return device.createSampler({
            .magFilter = filter,
            .minFilter = filter,
            .mipmapMode = vk::SamplerMipmapMode::eNearest,
            .addressModeU = vk::SamplerAddressMode::eClampToEdge,
            .addressModeV = vk::SamplerAddressMode::eClampToEdge,
            .addressModeW = vk::SamplerAddressMode::eClampToEdge,
            .maxLod = 0.0f,
        });
    };
    linear_sampler = make_sampler(vk::Filter::eLinear);
    point_sampler = make_sampler(vk::Filter::eNearest);

    // binding 0: linear, binding 1: point, both sample the same image
    const std::array<vk::DescriptorSetLayoutBinding, 2> bindings = {{
        {.binding = 0,
         .descriptorType = vk::DescriptorType::eCombinedImageSampler,
         .descriptorCount = 1,
         .stageFlags = vk::ShaderStageFlagBits::eFragment},
        {.binding = 1,
         .descriptorType = vk::DescriptorType::eCombinedImageSampler,
         .descriptorCount = 1,
         .stageFlags = vk::ShaderStageFlagBits::eFragment},
    }};
    set_layout = device.createDescriptorSetLayout({
        .bindingCount = static_cast<u32>(bindings.size()),
        .pBindings = bindings.data(),
    });

    const vk::PushConstantRange push_range = {
        .stageFlags = vk::ShaderStageFlagBits::eFragment,
        .offset = 0,
        .size = sizeof(PostProcess::FxPushConstants),
    };
    pipeline_layout = device.createPipelineLayout({
        .setLayoutCount = 1,
        .pSetLayouts = &set_layout,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_range,
    });

    const vk::AttachmentDescription color = {
        .format = format,
        .loadOp = vk::AttachmentLoadOp::eDontCare,
        .storeOp = vk::AttachmentStoreOp::eStore,
        .stencilLoadOp = vk::AttachmentLoadOp::eDontCare,
        .stencilStoreOp = vk::AttachmentStoreOp::eDontCare,
        .initialLayout = vk::ImageLayout::eUndefined,
        .finalLayout = vk::ImageLayout::eShaderReadOnlyOptimal,
    };
    const vk::AttachmentReference color_ref = {
        .attachment = 0,
        .layout = vk::ImageLayout::eColorAttachmentOptimal,
    };
    const vk::SubpassDescription subpass = {
        .pipelineBindPoint = vk::PipelineBindPoint::eGraphics,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_ref,
    };
    // The previous pass may still be reading the image this pass writes (ping pong), and the
    // result is read by the next pass or copied.
    const std::array<vk::SubpassDependency, 2> dependencies = {{
        {.srcSubpass = VK_SUBPASS_EXTERNAL,
         .dstSubpass = 0,
         .srcStageMask = vk::PipelineStageFlagBits::eFragmentShader |
                         vk::PipelineStageFlagBits::eColorAttachmentOutput |
                         vk::PipelineStageFlagBits::eTransfer,
         .dstStageMask = vk::PipelineStageFlagBits::eColorAttachmentOutput,
         .srcAccessMask = vk::AccessFlagBits::eShaderRead |
                          vk::AccessFlagBits::eColorAttachmentWrite |
                          vk::AccessFlagBits::eTransferRead,
         .dstAccessMask = vk::AccessFlagBits::eColorAttachmentWrite},
        {.srcSubpass = 0,
         .dstSubpass = VK_SUBPASS_EXTERNAL,
         .srcStageMask = vk::PipelineStageFlagBits::eColorAttachmentOutput,
         .dstStageMask = vk::PipelineStageFlagBits::eFragmentShader |
                         vk::PipelineStageFlagBits::eTransfer,
         .srcAccessMask = vk::AccessFlagBits::eColorAttachmentWrite,
         .dstAccessMask = vk::AccessFlagBits::eShaderRead | vk::AccessFlagBits::eTransferRead},
    }};
    render_pass = device.createRenderPass({
        .attachmentCount = 1,
        .pAttachments = &color,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = static_cast<u32>(dependencies.size()),
        .pDependencies = dependencies.data(),
    });

    vertex_module = Compile(PostProcess::GetFullscreenVertexShader(),
                            vk::ShaderStageFlagBits::eVertex, device);
}

PostProcessChain::~PostProcessChain() {
    scheduler.Finish();
    Destroy();
    const vk::Device device = instance.GetDevice();
    device.destroyShaderModule(vertex_module);
    device.destroyRenderPass(render_pass);
    device.destroyPipelineLayout(pipeline_layout);
    device.destroyDescriptorSetLayout(set_layout);
    device.destroySampler(linear_sampler);
    device.destroySampler(point_sampler);
}

void PostProcessChain::Destroy() {
    const vk::Device device = instance.GetDevice();
    for (Pass& pass : passes) {
        if (pass.pipeline) {
            device.destroyPipeline(pass.pipeline);
        }
        if (pass.fragment) {
            device.destroyShaderModule(pass.fragment);
        }
    }
    passes.clear();
    for (Target& t : targets) {
        if (t.framebuffer) {
            device.destroyFramebuffer(t.framebuffer);
        }
        if (t.view) {
            device.destroyImageView(t.view);
        }
        if (t.image) {
            vmaDestroyImage(instance.GetAllocator(), t.image, t.allocation);
        }
        t = {};
    }
    if (pool) {
        device.destroyDescriptorPool(pool);
        pool = nullptr;
    }
    frame_sets.clear();
    pool_sets_used = 0;
    built = false;
}

bool PostProcessChain::CreateTargets(u32 w, u32 h) {
    const vk::Device device = instance.GetDevice();
    const vk::ImageCreateInfo image_info = {
        .imageType = vk::ImageType::e2D,
        .format = format,
        .extent = {w, h, 1},
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = vk::SampleCountFlagBits::e1,
        .usage = vk::ImageUsageFlagBits::eColorAttachment | vk::ImageUsageFlagBits::eSampled |
                 vk::ImageUsageFlagBits::eTransferSrc,
    };
    const VmaAllocationCreateInfo alloc_info = {
        .flags = VMA_ALLOCATION_CREATE_WITHIN_BUDGET_BIT,
        .usage = VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE,
    };
    const std::array<vk::DescriptorPoolSize, 1> sizes = {
        {{vk::DescriptorType::eCombinedImageSampler, kMaxDescriptorSets * 2}}};
    pool = device.createDescriptorPool({
        .maxSets = kMaxDescriptorSets,
        .poolSizeCount = 1,
        .pPoolSizes = sizes.data(),
    });

    for (Target& t : targets) {
        VkImage raw{};
        VkImageCreateInfo raw_info = static_cast<VkImageCreateInfo>(image_info);
        if (vmaCreateImage(instance.GetAllocator(), &raw_info, &alloc_info, &raw, &t.allocation,
                           nullptr) != VK_SUCCESS) {
            LOG_ERROR(Render_Vulkan, "Post processing: failed to allocate the intermediate image");
            return false;
        }
        t.image = vk::Image{raw};
        t.view = device.createImageView({
            .image = t.image,
            .viewType = vk::ImageViewType::e2D,
            .format = format,
            .subresourceRange{.aspectMask = vk::ImageAspectFlagBits::eColor,
                              .levelCount = 1,
                              .layerCount = 1},
        });
        t.framebuffer = device.createFramebuffer({
            .renderPass = render_pass,
            .attachmentCount = 1,
            .pAttachments = &t.view,
            .width = w,
            .height = h,
            .layers = 1,
        });
        const vk::DescriptorSetAllocateInfo alloc = {
            .descriptorPool = pool,
            .descriptorSetCount = 1,
            .pSetLayouts = &set_layout,
        };
        t.set = device.allocateDescriptorSets(alloc)[0];
        pool_sets_used++;
        WriteSet(t.set, t.view);
    }
    return true;
}

void PostProcessChain::WriteSet(vk::DescriptorSet set, vk::ImageView view) {
    const vk::DescriptorImageInfo linear = {
        .sampler = linear_sampler,
        .imageView = view,
        .imageLayout = vk::ImageLayout::eShaderReadOnlyOptimal,
    };
    vk::DescriptorImageInfo point = linear;
    point.sampler = point_sampler;
    const std::array<vk::WriteDescriptorSet, 2> writes = {{
        {.dstSet = set,
         .dstBinding = 0,
         .descriptorCount = 1,
         .descriptorType = vk::DescriptorType::eCombinedImageSampler,
         .pImageInfo = &linear},
        {.dstSet = set,
         .dstBinding = 1,
         .descriptorCount = 1,
         .descriptorType = vk::DescriptorType::eCombinedImageSampler,
         .pImageInfo = &point},
    }};
    instance.GetDevice().updateDescriptorSets(writes, {});
}

vk::DescriptorSet PostProcessChain::GetFrameSet(vk::ImageView view) {
    const u64 key = reinterpret_cast<u64>(static_cast<VkImageView>(view));
    if (const auto it = frame_sets.find(key); it != frame_sets.end()) {
        return it->second;
    }
    if (pool_sets_used >= kMaxDescriptorSets) {
        return {};
    }
    const vk::DescriptorSetAllocateInfo alloc = {
        .descriptorPool = pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &set_layout,
    };
    const vk::DescriptorSet set = instance.GetDevice().allocateDescriptorSets(alloc)[0];
    pool_sets_used++;
    WriteSet(set, view);
    frame_sets.emplace(key, set);
    return set;
}

bool PostProcessChain::CreatePipelines(
    const std::vector<std::pair<std::string, std::string>>& fragments) {
    const vk::Device device = instance.GetDevice();
    for (const auto& [name, glsl] : fragments) {
        if (passes.size() >= kMaxPasses) {
            LOG_WARNING(Render_Vulkan, "Post processing: more than {} passes, ignoring the rest",
                        kMaxPasses);
            break;
        }
        Pass pass;
        pass.name = name;
        pass.fragment = Compile(glsl, vk::ShaderStageFlagBits::eFragment, device);
        if (!pass.fragment) {
            LOG_ERROR(Render_Vulkan, "Post processing: '{}' failed to compile, see the log above",
                      name);
            continue;
        }
        const std::array<vk::PipelineShaderStageCreateInfo, 2> stages = {{
            {.stage = vk::ShaderStageFlagBits::eVertex, .module = vertex_module, .pName = "main"},
            {.stage = vk::ShaderStageFlagBits::eFragment, .module = pass.fragment, .pName = "main"},
        }};
        const vk::PipelineVertexInputStateCreateInfo vertex_input{};
        const vk::PipelineInputAssemblyStateCreateInfo input_assembly = {
            .topology = vk::PrimitiveTopology::eTriangleList,
        };
        const vk::PipelineViewportStateCreateInfo viewport_state = {
            .viewportCount = 1,
            .scissorCount = 1,
        };
        const vk::PipelineRasterizationStateCreateInfo rasterization = {
            .polygonMode = vk::PolygonMode::eFill,
            .cullMode = vk::CullModeFlagBits::eNone,
            .frontFace = vk::FrontFace::eClockwise,
            .lineWidth = 1.0f,
        };
        const vk::PipelineMultisampleStateCreateInfo multisample = {
            .rasterizationSamples = vk::SampleCountFlagBits::e1,
        };
        const vk::PipelineColorBlendAttachmentState attachment = {
            .blendEnable = VK_FALSE,
            .colorWriteMask = vk::ColorComponentFlagBits::eR | vk::ColorComponentFlagBits::eG |
                              vk::ColorComponentFlagBits::eB | vk::ColorComponentFlagBits::eA,
        };
        const vk::PipelineColorBlendStateCreateInfo blend = {
            .attachmentCount = 1,
            .pAttachments = &attachment,
        };
        const std::array<vk::DynamicState, 2> dynamic = {vk::DynamicState::eViewport,
                                                         vk::DynamicState::eScissor};
        const vk::PipelineDynamicStateCreateInfo dynamic_state = {
            .dynamicStateCount = static_cast<u32>(dynamic.size()),
            .pDynamicStates = dynamic.data(),
        };
        const auto result = device.createGraphicsPipeline(
            {}, vk::GraphicsPipelineCreateInfo{
                    .stageCount = static_cast<u32>(stages.size()),
                    .pStages = stages.data(),
                    .pVertexInputState = &vertex_input,
                    .pInputAssemblyState = &input_assembly,
                    .pViewportState = &viewport_state,
                    .pRasterizationState = &rasterization,
                    .pMultisampleState = &multisample,
                    .pColorBlendState = &blend,
                    .pDynamicState = &dynamic_state,
                    .layout = pipeline_layout,
                    .renderPass = render_pass,
                    .subpass = 0,
                });
        if (result.result != vk::Result::eSuccess) {
            LOG_ERROR(Render_Vulkan, "Post processing: pipeline creation of '{}' failed", name);
            device.destroyShaderModule(pass.fragment);
            continue;
        }
        pass.pipeline = result.value;
        passes.push_back(std::move(pass));
    }
    return !passes.empty();
}

bool PostProcessChain::NeedsRebuild(const Frame* frame) {
    const bool enabled = Settings::values.reshade_enabled.GetValue();
    const std::string& path = Settings::values.reshade_config_path.GetValue();
    bool dirty = !built || frame->width != width || frame->height != height || path != config_path;
    // Hot reload: look at the file a couple of times per second
    if (!dirty && (frame_counter % 120) == 0 && !path.empty()) {
        std::error_code ec;
        const auto time = fs::last_write_time(path, ec);
        if (!ec && time != config_time) {
            dirty = true;
        }
    }
    (void)enabled;
    return dirty;
}

void PostProcessChain::Rebuild(u32 w, u32 h) {
    scheduler.Finish();
    Destroy();
    width = w;
    height = h;
    config_path = Settings::values.reshade_config_path.GetValue();
    built = true; // do not retry every frame when the configuration is broken

    std::error_code ec;
    if (config_path.empty()) {
        LOG_WARNING(Render_Vulkan, "Post processing is enabled but no configuration is set");
        return;
    }
    config_time = fs::last_write_time(config_path, ec);

    PostProcess::ChainConfig cfg = PostProcess::LoadChainConfig(config_path);
    for (const auto& m : cfg.messages) {
        LOG_WARNING(Render_Vulkan, "Post processing: {}", m);
    }

    std::vector<std::pair<std::string, std::string>> fragments;
    for (const auto& effect : cfg.effects) {
        if (effect.builtin) {
            std::string glsl = PostProcess::GetBuiltinEffectGlsl(effect.name, effect.options);
            if (glsl.empty()) {
                LOG_WARNING(Render_Vulkan, "Post processing: the built in effect '{}' is not "
                                           "implemented, skipping it",
                            effect.name);
                continue;
            }
            fragments.emplace_back(effect.name, std::move(glsl));
            continue;
        }
        PostProcess::FxOptions options;
        options.uniform_overrides = effect.options;
        options.include_paths = cfg.include_paths;
        options.enabled_techniques = effect.techniques;
        options.width = w;
        options.height = h;
        const PostProcess::FxResult result =
            PostProcess::TranslateEffectFile(effect.path, options);
        for (const auto& m : result.messages) {
            LOG_WARNING(Render_Vulkan, "Post processing: {}: {}", effect.name, m);
        }
        if (!result.ok) {
            LOG_ERROR(Render_Vulkan, "Post processing: effect '{}' was skipped", effect.name);
            continue;
        }
        for (const auto& tech : result.techniques) {
            for (const auto& pass : tech.passes) {
                fragments.emplace_back(effect.name + ":" + pass.name, pass.fragment_glsl);
            }
        }
    }
    if (fragments.empty() || !CreateTargets(w, h) || !CreatePipelines(fragments)) {
        LOG_WARNING(Render_Vulkan, "Post processing: nothing to apply");
        Destroy();
        built = true;
        return;
    }
    LOG_INFO(Render_Vulkan, "Post processing: {} pass(es) active", passes.size());
}

bool PostProcessChain::Apply(Frame* frame) {
    if (!Settings::values.reshade_enabled.GetValue()) {
        if (built) {
            scheduler.Finish();
            Destroy();
            config_path.clear();
        }
        return false;
    }
    frame_counter++;
    if (NeedsRebuild(frame)) {
        Rebuild(frame->width, frame->height);
    }
    if (passes.empty()) {
        return false;
    }
    const vk::DescriptorSet frame_set = GetFrameSet(frame->image_view);
    if (!frame_set) {
        // Out of descriptor sets (many recreated frames), start over next frame
        built = false;
        return false;
    }

    const auto now = std::chrono::steady_clock::now();
    static thread_local std::mt19937 rng{std::random_device{}()};
    PostProcess::FxPushConstants push{};
    push.timer_ms =
        std::chrono::duration<float, std::milli>(now - start_time).count();
    push.frame_time_ms = std::chrono::duration<float, std::milli>(now - last_frame).count();
    push.frame_count = static_cast<float>(frame_counter);
    push.random = std::uniform_real_distribution<float>(0.0f, 1.0f)(rng);
    last_frame = now;

    std::vector<vk::Pipeline> pipelines;
    pipelines.reserve(passes.size());
    for (const Pass& p : passes) {
        pipelines.push_back(p.pipeline);
    }

    scheduler.Record([this, frame_image = frame->image, frame_set, pipelines, push,
                      w = frame->width, h = frame->height](vk::CommandBuffer cmdbuf) {
        using Stage = vk::PipelineStageFlagBits;
        using Access = vk::AccessFlagBits;
        using Layout = vk::ImageLayout;

        // The render pass of the present window leaves the frame in TransferSrcOptimal
        ImageBarrier(cmdbuf, frame_image, Layout::eTransferSrcOptimal, Layout::eShaderReadOnlyOptimal,
                     Stage::eColorAttachmentOutput, Access::eColorAttachmentWrite,
                     Stage::eFragmentShader, Access::eShaderRead);

        const vk::Viewport viewport = {0.0f, 0.0f, static_cast<float>(w), static_cast<float>(h),
                                       0.0f, 1.0f};
        const vk::Rect2D scissor = {{0, 0}, {w, h}};

        vk::DescriptorSet input = frame_set;
        u32 last = 0;
        for (u32 i = 0; i < pipelines.size(); i++) {
            const Target& out = targets[i % 2];
            const vk::RenderPassBeginInfo begin = {
                .renderPass = render_pass,
                .framebuffer = out.framebuffer,
                .renderArea = {{0, 0}, {w, h}},
            };
            cmdbuf.beginRenderPass(begin, vk::SubpassContents::eInline);
            cmdbuf.bindPipeline(vk::PipelineBindPoint::eGraphics, pipelines[i]);
            cmdbuf.setViewport(0, viewport);
            cmdbuf.setScissor(0, scissor);
            cmdbuf.bindDescriptorSets(vk::PipelineBindPoint::eGraphics, pipeline_layout, 0, input,
                                      {});
            cmdbuf.pushConstants(pipeline_layout, vk::ShaderStageFlagBits::eFragment, 0,
                                 sizeof(push), &push);
            cmdbuf.draw(3, 1, 0, 0);
            cmdbuf.endRenderPass();
            input = out.set;
            last = i % 2;
        }

        // Copy the result back so presentation keeps using the frame image unchanged
        const Target& result = targets[last];
        ImageBarrier(cmdbuf, result.image, Layout::eShaderReadOnlyOptimal, Layout::eTransferSrcOptimal,
                     Stage::eColorAttachmentOutput, Access::eColorAttachmentWrite, Stage::eTransfer,
                     Access::eTransferRead);
        ImageBarrier(cmdbuf, frame_image, Layout::eShaderReadOnlyOptimal, Layout::eTransferDstOptimal,
                     Stage::eFragmentShader, Access::eShaderRead, Stage::eTransfer,
                     Access::eTransferWrite);
        const vk::ImageCopy region = {
            .srcSubresource = {vk::ImageAspectFlagBits::eColor, 0, 0, 1},
            .dstSubresource = {vk::ImageAspectFlagBits::eColor, 0, 0, 1},
            .extent = {w, h, 1},
        };
        cmdbuf.copyImage(result.image, Layout::eTransferSrcOptimal, frame_image,
                         Layout::eTransferDstOptimal, region);
        ImageBarrier(cmdbuf, frame_image, Layout::eTransferDstOptimal, Layout::eTransferSrcOptimal,
                     Stage::eTransfer, Access::eTransferWrite, Stage::eTransfer,
                     Access::eTransferRead);
    });
    return true;
}

} // namespace Vulkan
