// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#pragma once

#include <filesystem>
#include <map>
#include <set>
#include <string>
#include <vector>

namespace PostProcess {

/**
 * Translator for a subset of ReShade FX (HLSL based) effects to Vulkan GLSL, as used by vkBasalt.
 *
 * vkBasalt links the full reshadefx compiler. That library is not part of Azahar's externals, so
 * this translator covers what the large majority of single pass post processing effects use
 * (colour grading, sharpening, tonemapping, vignette, film grain, ...):
 *  - #include resolution (ReShade.fxh and ReShadeUI.fxh are built in)
 *  - uniforms with annotations, baked as constants and overridable by name
 *  - the built in uniform sources timer, frametime, framecount and random
 *  - samplers of the back buffer (point or linear)
 *  - techniques made of passes that use PostProcessVS and write the back buffer
 *  - HLSL to GLSL syntax: types, intrinsics, C style casts, matrix conventions, semantics
 *
 * Not supported, the effect is rejected with a message (it is never partially applied):
 * render targets and intermediate textures, textures loaded from files, depth buffer access,
 * custom vertex shaders, compute shaders, namespaces and structs as pixel shader inputs.
 */

struct FxOptions {
    /// Values for uniforms by name, as written in vkBasalt.conf / a ReShade preset.
    std::map<std::string, std::string> uniform_overrides;
    /// Extra directories searched for #include
    std::vector<std::filesystem::path> include_paths;
    /// Back buffer size in pixels, BUFFER_WIDTH / BUFFER_HEIGHT
    unsigned width = 1280;
    unsigned height = 720;
    /// Only these techniques are produced when not empty
    std::set<std::string> enabled_techniques;
};

struct FxPass {
    std::string name;
    /// Complete GLSL 450 fragment shader, input location 0 is the texture coordinate
    std::string fragment_glsl;
};

struct FxTechnique {
    std::string name;
    std::vector<FxPass> passes;
};

struct FxResult {
    bool ok = false;
    std::vector<FxTechnique> techniques;
    std::vector<std::string> messages;
};

/// Translates the effect in `source`. `path` is only used to resolve #include and in messages.
FxResult TranslateEffect(const std::filesystem::path& path, const std::string& source,
                         const FxOptions& options);

/// Reads `path` and calls TranslateEffect
FxResult TranslateEffectFile(const std::filesystem::path& path, const FxOptions& options);

/// Push constant block shared by all translated effects (std430, 16 bytes)
struct FxPushConstants {
    float timer_ms;
    float frame_time_ms;
    float frame_count;
    float random;
};

/// Fullscreen triangle vertex shader matching the fragment shaders (location 0 = texcoord)
const char* GetFullscreenVertexShader();

// Exposed for tests
namespace Detail {
std::string StripComments(const std::string& text);
std::string ConvertCasts(const std::string& text);
std::string ConvertHlslSyntax(const std::string& text);
} // namespace Detail

} // namespace PostProcess
