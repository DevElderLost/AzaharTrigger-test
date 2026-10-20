// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#include <algorithm>
#include <cmath>
#include "common/settings.h"
#include "video_core/planar_shadows.h"

namespace VideoCore {

namespace {
constexpr float kPi = 3.14159265358979323846f;
constexpr u32 kOpcodeMOVA = 0x12;

// PICA arithmetic instructions: opcode in bits 26-31, relative address register select in bits
// 19-20 (applies to src1), see nihstro::Instruction::{opcode, idx}.
constexpr u32 OpcodeOf(u32 word) {
    return word >> 26;
}
constexpr u32 AddressIndexOf(u32 word) {
    return (word >> 19) & 0x3;
}
// Opcodes below 0x10 (ADD..RSQ) and MAD (0x38-0x3F) use the standard operand encoding where the
// idx field is meaningful; control flow encodings reuse the same bits for other purposes.
constexpr bool UsesStandardOperands(u32 opcode) {
    return opcode <= 0x0F || opcode == 0x13 /* MOV */ || (opcode >= 0x38 && opcode <= 0x3F);
}
} // namespace

PlanarShadowOptions PlanarShadowOptions::FromSettings() {
    PlanarShadowOptions o;
    o.enabled = Settings::values.planar_shadows.GetValue() &&
                Settings::values.graphics_api.GetValue() == Settings::GraphicsAPI::Vulkan;
    o.opacity = std::clamp(Settings::values.planar_shadow_opacity.GetValue(), 0, 60) * 0.01f;
    o.direction_x = Settings::values.planar_shadow_dir_x.GetValue() * 0.01f;
    o.direction_z = Settings::values.planar_shadow_dir_z.GetValue() * 0.01f;
    o.pitch_degrees = static_cast<float>(Settings::values.planar_shadow_pitch.GetValue());
    o.fov_degrees = static_cast<float>(Settings::values.planar_shadow_fov.GetValue());
    o.ground_distance = static_cast<float>(Settings::values.planar_shadow_ground.GetValue());
    o.max_depth = static_cast<float>(Settings::values.planar_shadow_max_depth.GetValue());
    o.all_opaque_draws = Settings::values.planar_shadow_mode.GetValue() == 1;
    o.flip_up = (Settings::values.planar_shadow_flip.GetValue() & 1) != 0;
    o.flip_right = (Settings::values.planar_shadow_flip.GetValue() & 2) != 0;
    return o;
}

PlanarShadowUniforms BuildPlanarShadowUniforms(const PlanarShadowOptions& o, float aspect) {
    PlanarShadowUniforms u;

    const float fov = std::clamp(o.fov_degrees, 5.0f, 150.0f) * kPi / 180.0f;
    const float pitch = std::clamp(o.pitch_degrees, 0.0f, 89.0f) * kPi / 180.0f;
    const float tan_half = std::tan(fov * 0.5f);

    // The PICA framebuffer is rotated by 90 degrees: clip x is the screen vertical axis and clip y
    // the screen horizontal axis. aspect is screen width / screen height.
    const float sign_up = o.flip_up ? -1.0f : 1.0f;
    const float sign_right = o.flip_right ? -1.0f : 1.0f;
    u.params = {o.enabled ? 1.0f : 0.0f, sign_up * tan_half, sign_right * tan_half * aspect,
                std::max(o.ground_distance, 0.001f)};

    // View space: x right, y up, camera looks down -z. World up expressed in view space for a
    // camera pitched down by `pitch`.
    const float sp = std::sin(pitch);
    const float cp = std::cos(pitch);
    const std::array<float, 3> n{0.0f, cp, sp};
    // Horizontal forward axis (forward projected on the ground plane), see planar_shadows.h
    const std::array<float, 3> fh{0.0f, sp, -cp};

    u.normal = {n[0], n[1], n[2], std::max(o.max_depth, 0.0f)};

    // Direction the rays travel: sideways, away from the camera and one unit down.
    u.direction = {o.direction_x * 1.0f + o.direction_z * fh[0] - n[0],
                   o.direction_z * fh[1] - n[1], o.direction_z * fh[2] - n[2], 0.0f};
    return u;
}

bool IsSkinnedProgram(std::span<const u32> code, u32 size) {
    const u32 count = std::min<u32>(size, static_cast<u32>(code.size()));
    for (u32 i = 0; i < count; i++) {
        const u32 word = code[i];
        const u32 opcode = OpcodeOf(word);
        if (opcode == kOpcodeMOVA) {
            return true;
        }
        if (UsesStandardOperands(opcode) && AddressIndexOf(word) != 0) {
            return true;
        }
    }
    return false;
}

bool SkinnedProgramCache::IsSkinned(u64 program_hash, std::span<const u32> code, u32 size) {
    if (const auto it = cache.find(program_hash); it != cache.end()) {
        return it->second;
    }
    const bool skinned = IsSkinnedProgram(code, size);
    cache.emplace(program_hash, skinned);
    return skinned;
}

} // namespace VideoCore
