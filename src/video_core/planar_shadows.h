// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#pragma once

#include <array>
#include <span>
#include <unordered_map>
#include "common/common_types.h"

namespace VideoCore {

// Planar silhouette shadows, adapted from the PPSSPP implementation (GPU/Common/PlanarShadows).
//
// PPSSPP collects world space triangles on the CPU, rasterizes them into a coverage mask and clips
// the mask against the terrain. That is not possible here: the PICA200 vertex shaders run on the
// host GPU, so the CPU never sees transformed vertices. What carries over is the model:
//  * skinned, opaque, depth writing 3D draws are shadow casters (detected from the vertex shader),
//  * casters are flattened along a fixed direction onto a ground plane,
//  * the result is drawn with alpha blending, once per pixel, depth tested against the scene.
// The flattening happens in the vertex shader (see ApplyPlanarShadow in glsl_shader_gen.cpp) in a
// view space that is rebuilt from the clip space position with an assumed field of view, camera
// pitch and camera height. Those are user settings because the games do not expose them.

struct PlanarShadowOptions {
    bool enabled = false;
    float opacity = 0.25f;  // 0 to 0.6
    float direction_x = 0.45f;  // Shadow offset to the right per unit of height
    float direction_z = 0.30f;  // Shadow offset away from the camera per unit of height
    float pitch_degrees = 35.0f;
    float fov_degrees = 40.0f;
    float ground_distance = 10.0f;
    float max_depth = 0.0f; // 0 = unlimited
    bool all_opaque_draws = false;
    bool flip_up = false;
    bool flip_right = false;

    /// Reads the options from Settings::values
    static PlanarShadowOptions FromSettings();
};

/// Values uploaded to the vertex shader uniform block. Layout matches `shadow_*` in vs_data.
struct PlanarShadowUniforms {
    // x: enabled (1.0 / 0.0), y: tan(fov/2) for the screen vertical axis (signed),
    // z: same for the screen horizontal axis (includes the aspect ratio), w: ground distance
    std::array<float, 4> params{};
    // xyz: unit normal of the ground plane in view space, w: max depth (0 = unlimited)
    std::array<float, 4> normal{};
    // xyz: direction the casters are projected along, w: unused
    std::array<float, 4> direction{};

    bool operator==(const PlanarShadowUniforms&) const = default;
};

/// Builds the uniforms for a viewport whose screen aspect ratio (width / height of the *screen*,
/// not of the rotated framebuffer) is `aspect`.
PlanarShadowUniforms BuildPlanarShadowUniforms(const PlanarShadowOptions& options, float aspect);

/// Returns true when the PICA vertex shader uses relative addressing, which is how the games index
/// bone matrices. `code` is the program code, `size` the number of valid words.
bool IsSkinnedProgram(std::span<const u32> code, u32 size);

/// Caches IsSkinnedProgram per program hash.
class SkinnedProgramCache {
public:
    bool IsSkinned(u64 program_hash, std::span<const u32> code, u32 size);
    void Clear() {
        cache.clear();
    }

private:
    std::unordered_map<u64, bool> cache;
};

} // namespace VideoCore
