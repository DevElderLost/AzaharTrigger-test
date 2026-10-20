// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#pragma once

#include <filesystem>
#include <map>
#include <string>
#include <vector>
#include "video_core/post_process/reshade_fx.h"

namespace PostProcess {

/// One entry of the effect chain
struct EffectEntry {
    std::string name;                  ///< Name in the chain ("cas", "LumaSharpen", ...)
    std::filesystem::path path;        ///< .fx file, empty for built in effects
    bool builtin = false;
    std::set<std::string> techniques;  ///< Empty = every technique of the file
    std::map<std::string, std::string> options;
};

struct ChainConfig {
    std::vector<EffectEntry> effects;
    std::vector<std::filesystem::path> texture_paths;
    std::vector<std::filesystem::path> include_paths;
    std::vector<std::string> messages;
};

/// vkBasalt.conf: `effects = cas:Name`, `Name = /path/Effect.fx`, `reshadeIncludePath`, ...
/// Keys that are not known to vkBasalt are uniform overrides applied to every ReShade effect.
ChainConfig ParseVkBasaltConfig(const std::string& text, const std::filesystem::path& base_dir);

/// ReShade preset (.ini): `Techniques=A@File.fx,B@Other.fx` and one `[File.fx]` section per effect
/// with its uniform values. Effects are looked up in `shaders_dir`.
ChainConfig ParseReShadePreset(const std::string& text, const std::filesystem::path& shaders_dir,
                               const std::filesystem::path& textures_dir);

/// Loads either format depending on the extension and content
ChainConfig LoadChainConfig(const std::filesystem::path& file);

/// GLSL fragment shader of a built in vkBasalt effect (currently "cas"), empty when unknown
std::string GetBuiltinEffectGlsl(const std::string& name,
                                 const std::map<std::string, std::string>& options);

/// Directory the importer and the default chain use: <user>/shaders/reshade
std::filesystem::path GetReShadeRoot();

struct ImportResult {
    bool ok = false;
    int files_copied = 0;
    /// vkBasalt.conf that references the imported effects, ready to be used as reshade_config_path
    std::filesystem::path config_path;
    std::vector<std::string> messages;
};

/**
 * Imports shaders into `dest_root` (Shaders/, Textures/, Presets/ and vkBasalt.conf).
 * `source` may be
 *  - a .fx / .fxh file (its #include dependencies are copied too),
 *  - a ReShade preset .ini (the effects it lists are copied when found next to it),
 *  - a vkBasalt.conf (the effects and texture/include directories it references are copied and
 *    the paths rewritten),
 *  - a directory, either a reshade-shaders checkout (Shaders/ + Textures/) or a plain folder.
 */
ImportResult ImportShaders(const std::filesystem::path& source, const std::filesystem::path& dest_root);

} // namespace PostProcess
