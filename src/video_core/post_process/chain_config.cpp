// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#include <algorithm>
#include <cctype>
#include <fstream>
#include <set>
#include <sstream>
#include "common/file_util.h"
#include "video_core/post_process/chain_config.h"

namespace fs = std::filesystem;

namespace PostProcess {

namespace {

std::string Trim(const std::string& s) {
    size_t b = 0;
    size_t e = s.size();
    while (b < e && std::isspace(static_cast<unsigned char>(s[b]))) {
        b++;
    }
    while (e > b && std::isspace(static_cast<unsigned char>(s[e - 1]))) {
        e--;
    }
    return s.substr(b, e - b);
}

std::string Unquote(std::string s) {
    s = Trim(s);
    if (s.size() >= 2 && ((s.front() == '"' && s.back() == '"') ||
                          (s.front() == '\'' && s.back() == '\''))) {
        s = s.substr(1, s.size() - 2);
    }
    return s;
}

std::string Lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return s;
}

std::vector<std::string> Split(const std::string& s, char sep) {
    std::vector<std::string> out;
    std::string cur;
    std::istringstream in(s);
    while (std::getline(in, cur, sep)) {
        cur = Trim(cur);
        if (!cur.empty()) {
            out.push_back(cur);
        }
    }
    return out;
}

std::string ReadFile(const fs::path& p) {
    std::ifstream f(p, std::ios::binary);
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

fs::path Resolve(const std::string& value, const fs::path& base) {
    fs::path p = Unquote(value);
    if (p.is_relative()) {
        p = base / p;
    }
    return p;
}

bool IsImage(const fs::path& p) {
    const std::string e = Lower(p.extension().string());
    return e == ".png" || e == ".jpg" || e == ".jpeg" || e == ".bmp" || e == ".tga" || e == ".dds";
}

bool CopyOne(const fs::path& from, const fs::path& to, ImportResult& r) {
    std::error_code ec;
    fs::create_directories(to.parent_path(), ec);
    fs::copy_file(from, to, fs::copy_options::overwrite_existing, ec);
    if (ec) {
        r.messages.push_back("cannot copy " + from.string() + ": " + ec.message());
        return false;
    }
    r.files_copied++;
    return true;
}

/// Copies the #include dependencies of an effect file (relative to its folder) into dest
void CopyIncludes(const fs::path& file, const fs::path& source_root, const fs::path& dest_root,
                  std::set<fs::path>& done, ImportResult& r, int depth = 0) {
    if (depth > 8) {
        return;
    }
    std::istringstream lines(ReadFile(file));
    std::string line;
    while (std::getline(lines, line)) {
        const std::string t = Trim(line);
        if (t.rfind('#', 0) != 0) {
            continue;
        }
        const std::string d = Trim(t.substr(1));
        if (d.rfind("include", 0) != 0) {
            continue;
        }
        const size_t a = d.find_first_of("\"<");
        if (a == std::string::npos) {
            continue;
        }
        const size_t b = d.find_first_of("\">", a + 1);
        if (b == std::string::npos) {
            continue;
        }
        const std::string name = d.substr(a + 1, b - a - 1);
        if (name == "ReShade.fxh" || name == "ReShadeUI.fxh") {
            continue; // built in
        }
        for (const fs::path& base : {file.parent_path(), source_root}) {
            std::error_code ec;
            const fs::path candidate = fs::weakly_canonical(base / name, ec);
            if (!ec && fs::is_regular_file(candidate) && done.insert(candidate).second) {
                const fs::path rel = fs::relative(candidate, source_root, ec);
                const fs::path target =
                    dest_root / "Shaders" / ((ec || rel.string().rfind("..", 0) == 0) ? candidate.filename() : rel);
                CopyOne(candidate, target, r);
                CopyIncludes(candidate, source_root, dest_root, done, r, depth + 1);
                break;
            }
        }
    }
}

void CopyShaderFile(const fs::path& file, const fs::path& source_root, const fs::path& dest_root,
                    std::set<fs::path>& done, ImportResult& r) {
    std::error_code ec;
    const fs::path canon = fs::weakly_canonical(file, ec);
    if (!done.insert(canon).second) {
        return;
    }
    fs::path rel = fs::relative(canon, source_root, ec);
    // Keep the layout below a "Shaders" directory when the source is a reshade-shaders checkout
    fs::path target;
    const std::string rel_s = rel.generic_string();
    if (ec || rel_s.rfind("..", 0) == 0) {
        target = dest_root / "Shaders" / canon.filename();
    } else if (rel_s.rfind("Shaders/", 0) == 0) {
        target = dest_root / rel;
    } else {
        target = dest_root / "Shaders" / rel;
    }
    if (CopyOne(canon, target, r)) {
        CopyIncludes(canon, source_root, dest_root, done, r);
    }
}

void CopyTree(const fs::path& dir, const fs::path& dest_root, ImportResult& r) {
    std::set<fs::path> done;
    std::error_code ec;
    const bool is_checkout = fs::is_directory(dir / "Shaders", ec);
    const fs::path root = dir;
    for (auto it = fs::recursive_directory_iterator(dir, ec); it != fs::recursive_directory_iterator(); it.increment(ec)) {
        if (ec) {
            break;
        }
        if (!it->is_regular_file()) {
            continue;
        }
        const fs::path& p = it->path();
        const std::string ext = Lower(p.extension().string());
        if (ext == ".fx" || ext == ".fxh") {
            CopyShaderFile(p, root, dest_root, done, r);
        } else if (IsImage(p)) {
            const fs::path rel = fs::relative(p, root, ec);
            const std::string rs = rel.generic_string();
            const fs::path target = rs.rfind("Textures/", 0) == 0 ? dest_root / rel
                                                                    : dest_root / "Textures" / p.filename();
            CopyOne(p, target, r);
        } else if (ext == ".ini") {
            CopyOne(p, dest_root / "Presets" / p.filename(), r);
        }
    }
    (void)is_checkout;
}

/// Adds `name = path` and the name to `effects =` of the managed vkBasalt.conf
void RegisterEffect(const fs::path& conf, const fs::path& dest_root, const std::string& name,
                    const fs::path& effect_path) {
    std::vector<std::string> lines;
    {
        std::istringstream in(ReadFile(conf));
        std::string l;
        while (std::getline(in, l)) {
            lines.push_back(l);
        }
    }
    bool has_effects = false;
    bool has_entry = false;
    for (auto& l : lines) {
        const size_t eq = l.find('=');
        if (eq == std::string::npos || Trim(l).rfind('#', 0) == 0) {
            continue;
        }
        const std::string key = Trim(l.substr(0, eq));
        if (key == "effects") {
            has_effects = true;
            auto names = Split(Unquote(l.substr(eq + 1)), ':');
            if (std::find(names.begin(), names.end(), name) == names.end()) {
                names.push_back(name);
            }
            std::string joined;
            for (size_t i = 0; i < names.size(); i++) {
                joined += (i ? ":" : "") + names[i];
            }
            l = "effects = " + joined;
        } else if (key == name && !effect_path.empty()) {
            has_entry = true;
            l = name + " = \"" + effect_path.generic_string() + "\"";
        }
    }
    if (!has_effects) {
        lines.insert(lines.begin(), "effects = " + name);
    }
    if (!has_entry && !effect_path.empty()) {
        lines.push_back(name + " = \"" + effect_path.generic_string() + "\"");
    }
    bool has_paths = false;
    for (const auto& l : lines) {
        if (Trim(l).rfind("reshadeTexturePath", 0) == 0) {
            has_paths = true;
        }
    }
    if (!has_paths) {
        lines.push_back("reshadeTexturePath = \"" + (dest_root / "Textures").generic_string() + "\"");
        lines.push_back("reshadeIncludePath = \"" + (dest_root / "Shaders").generic_string() + "\"");
    }
    std::ofstream out(conf, std::ios::trunc);
    for (const auto& l : lines) {
        out << l << '\n';
    }
}

} // namespace

fs::path GetReShadeRoot() {
    return fs::path(FileUtil::GetUserPath(FileUtil::UserPath::ShaderDir)) / "reshade";
}

// ---------------------------------------------------------------------------------------------
// Parsers
// ---------------------------------------------------------------------------------------------

ChainConfig ParseVkBasaltConfig(const std::string& text, const fs::path& base_dir) {
    ChainConfig cfg;
    std::map<std::string, std::string> kv;
    std::istringstream in(text);
    std::string line;
    while (std::getline(in, line)) {
        line = Trim(line);
        if (line.empty() || line[0] == '#') {
            continue;
        }
        const size_t eq = line.find('=');
        if (eq == std::string::npos) {
            continue;
        }
        kv[Trim(line.substr(0, eq))] = Unquote(line.substr(eq + 1));
    }
    static const std::set<std::string> kReserved = {
        "effects", "reshadeTexturePath", "reshadeIncludePath", "depthCapture", "toggleKey",
        "enableOnLaunch", "casSharpness", "dlsSharpness", "dlsDenoise", "fxaaQualitySubpix",
        "fxaaQualityEdgeThreshold", "fxaaQualityEdgeThresholdMin", "smaaEdgeDetection",
        "smaaThreshold", "smaaMaxSearchSteps", "smaaMaxSearchStepsDiag", "smaaCornerRounding",
        "lutFile"};
    if (kv.count("reshadeTexturePath")) {
        cfg.texture_paths.push_back(Resolve(kv["reshadeTexturePath"], base_dir));
    }
    if (kv.count("reshadeIncludePath")) {
        cfg.include_paths.push_back(Resolve(kv["reshadeIncludePath"], base_dir));
    }
    const std::vector<std::string> names = Split(kv["effects"], ':');
    std::map<std::string, std::string> uniforms;
    for (const auto& [k, v] : kv) {
        if (!kReserved.count(k) && !v.empty() &&
            std::find(names.begin(), names.end(), k) == names.end()) {
            uniforms[k] = v;
        }
    }
    for (const std::string& name : names) {
        EffectEntry e;
        e.name = name;
        if (name == "cas" || name == "fxaa" || name == "smaa" || name == "dls" || name == "lut") {
            e.builtin = true;
            e.options = kv;
        } else if (kv.count(name)) {
            e.path = Resolve(kv[name], base_dir);
            e.options = uniforms;
        } else {
            cfg.messages.push_back("effect '" + name + "' has no path in the configuration");
            continue;
        }
        cfg.effects.push_back(std::move(e));
    }
    return cfg;
}

ChainConfig ParseReShadePreset(const std::string& text, const fs::path& shaders_dir,
                               const fs::path& textures_dir) {
    ChainConfig cfg;
    cfg.include_paths.push_back(shaders_dir);
    cfg.texture_paths.push_back(textures_dir);
    std::map<std::string, std::map<std::string, std::string>> sections;
    std::vector<std::string> techniques;
    std::string section;
    std::istringstream in(text);
    std::string line;
    while (std::getline(in, line)) {
        line = Trim(line);
        if (line.empty() || line[0] == ';' || line[0] == '#') {
            continue;
        }
        if (line.front() == '[' && line.back() == ']') {
            section = line.substr(1, line.size() - 2);
            continue;
        }
        const size_t eq = line.find('=');
        if (eq == std::string::npos) {
            continue;
        }
        const std::string key = Trim(line.substr(0, eq));
        const std::string value = Trim(line.substr(eq + 1));
        if (section.empty() && key == "Techniques") {
            techniques = Split(value, ',');
        } else if (section.empty() && key == "TechniqueSorting" && !value.empty()) {
            // Order is what matters, the enabled set is Techniques
            const auto sorted = Split(value, ',');
            std::vector<std::string> ordered;
            for (const auto& s : sorted) {
                if (std::find(techniques.begin(), techniques.end(), s) != techniques.end()) {
                    ordered.push_back(s);
                }
            }
            if (!ordered.empty()) {
                techniques = ordered;
            }
        } else if (!section.empty()) {
            sections[section][key] = value;
        }
    }
    std::vector<std::string> order;
    std::map<std::string, std::set<std::string>> by_file;
    for (const auto& t : techniques) {
        const size_t at = t.find('@');
        if (at == std::string::npos) {
            continue;
        }
        const std::string file = t.substr(at + 1);
        if (!by_file.count(file)) {
            order.push_back(file);
        }
        by_file[file].insert(t.substr(0, at));
    }
    for (const auto& file : order) {
        EffectEntry e;
        e.name = fs::path(file).stem().string();
        e.path = shaders_dir / file;
        e.techniques = by_file[file];
        e.options = sections[file];
        cfg.effects.push_back(std::move(e));
    }
    return cfg;
}

ChainConfig LoadChainConfig(const fs::path& file) {
    ChainConfig cfg;
    std::error_code ec;
    if (!fs::is_regular_file(file, ec)) {
        cfg.messages.push_back("configuration file not found: " + file.string());
        return cfg;
    }
    const std::string text = ReadFile(file);
    const std::string ext = Lower(file.extension().string());
    if (ext == ".ini" && text.find("Techniques=") != std::string::npos) {
        const fs::path root = GetReShadeRoot();
        return ParseReShadePreset(text, root / "Shaders", root / "Textures");
    }
    return ParseVkBasaltConfig(text, file.parent_path());
}

// ---------------------------------------------------------------------------------------------
// Built in effects
// ---------------------------------------------------------------------------------------------

std::string GetBuiltinEffectGlsl(const std::string& name,
                                 const std::map<std::string, std::string>& options) {
    if (name != "cas") {
        return {};
    }
    float sharpness = 0.4f;
    if (const auto it = options.find("casSharpness"); it != options.end()) {
        try {
            sharpness = std::clamp(std::stof(it->second), 0.0f, 1.0f);
        } catch (...) {
        }
    }
    // Contrast adaptive sharpening, plus shaped kernel (after AMD FidelityFX CAS)
    std::ostringstream s;
    s << "#version 450\n"
         "layout(set = 0, binding = 0) uniform sampler2D rs_bb_linear;\n"
         "layout(set = 0, binding = 1) uniform sampler2D rs_bb_point;\n"
         "layout(location = 0) in vec2 rs_texcoord;\n"
         "layout(location = 0) out vec4 rs_color;\n"
         "const float kSharpness = "
      << sharpness
      << ";\nvoid main() {\n"
         "    ivec2 p = ivec2(gl_FragCoord.xy);\n"
         "    ivec2 sz = textureSize(rs_bb_point, 0) - 1;\n"
         "    vec3 b = texelFetch(rs_bb_point, clamp(p + ivec2(0, -1), ivec2(0), sz), 0).rgb;\n"
         "    vec3 d = texelFetch(rs_bb_point, clamp(p + ivec2(-1, 0), ivec2(0), sz), 0).rgb;\n"
         "    vec3 e = texelFetch(rs_bb_point, clamp(p, ivec2(0), sz), 0).rgb;\n"
         "    vec3 f = texelFetch(rs_bb_point, clamp(p + ivec2(1, 0), ivec2(0), sz), 0).rgb;\n"
         "    vec3 h = texelFetch(rs_bb_point, clamp(p + ivec2(0, 1), ivec2(0), sz), 0).rgb;\n"
         "    vec3 mn = min(min(min(d, e), min(f, b)), h);\n"
         "    vec3 mx = max(max(max(d, e), max(f, b)), h);\n"
         "    vec3 amp = clamp(min(mn, 1.0 - mx) / max(mx, vec3(1e-5)), 0.0, 1.0);\n"
         "    amp = sqrt(amp);\n"
         "    float peak = -1.0 / mix(8.0, 5.0, kSharpness);\n"
         "    vec3 w = amp * peak;\n"
         "    vec3 rcp_w = 1.0 / (1.0 + 4.0 * w);\n"
         "    rs_color = vec4(clamp((b * w + d * w + f * w + h * w + e) * rcp_w, 0.0, 1.0), 1.0);\n"
         "}\n";
    return s.str();
}

// ---------------------------------------------------------------------------------------------
// Import
// ---------------------------------------------------------------------------------------------

ImportResult ImportShaders(const fs::path& source, const fs::path& dest_root) {
    ImportResult r;
    std::error_code ec;
    fs::create_directories(dest_root / "Shaders", ec);
    fs::create_directories(dest_root / "Textures", ec);
    fs::create_directories(dest_root / "Presets", ec);
    const fs::path conf = dest_root / "vkBasalt.conf";

    if (!fs::exists(source, ec)) {
        r.messages.push_back("source not found: " + source.string());
        return r;
    }

    if (fs::is_directory(source, ec)) {
        CopyTree(source, dest_root, r);
        r.ok = r.files_copied > 0;
        r.config_path = conf;
        if (!r.ok) {
            r.messages.push_back("no .fx, .fxh or texture files found in " + source.string());
        }
        return r;
    }

    const std::string ext = Lower(source.extension().string());
    std::set<fs::path> done;
    const fs::path src_dir = source.parent_path();
    // A file inside a reshade-shaders checkout resolves includes against its Shaders folder
    fs::path src_root = src_dir;

    if (ext == ".fx" || ext == ".fxh") {
        CopyShaderFile(source, src_root, dest_root, done, r);
        if (ext == ".fx") {
            const fs::path target = dest_root / "Shaders" / source.filename();
            RegisterEffect(conf, dest_root, source.stem().string(), target);
        }
    } else if (IsImage(source)) {
        CopyOne(source, dest_root / "Textures" / source.filename(), r);
    } else if (ext == ".ini") {
        CopyOne(source, dest_root / "Presets" / source.filename(), r);
        const std::string text = ReadFile(source);
        const ChainConfig cfg = ParseReShadePreset(text, src_dir, src_dir);
        for (const auto& e : cfg.effects) {
            std::error_code e2;
            fs::path found;
            for (const fs::path& cand : {src_dir / e.path.filename(), src_dir / "Shaders" / e.path.filename(),
                                         src_dir.parent_path() / "Shaders" / e.path.filename()}) {
                if (fs::is_regular_file(cand, e2)) {
                    found = cand;
                    break;
                }
            }
            if (found.empty()) {
                r.messages.push_back("effect " + e.path.filename().string() +
                                     " was not found next to the preset, import it separately");
                continue;
            }
            CopyShaderFile(found, found.parent_path(), dest_root, done, r);
        }
        r.config_path = dest_root / "Presets" / source.filename();
        r.ok = r.files_copied > 0;
        return r;
    } else if (ext == ".conf") {
        const ChainConfig cfg = ParseVkBasaltConfig(ReadFile(source), src_dir);
        for (const auto& tp : cfg.texture_paths) {
            if (fs::is_directory(tp, ec)) {
                for (const auto& f : fs::directory_iterator(tp, ec)) {
                    if (f.is_regular_file() && IsImage(f.path())) {
                        CopyOne(f.path(), dest_root / "Textures" / f.path().filename(), r);
                    }
                }
            }
        }
        for (const auto& e : cfg.effects) {
            if (e.builtin) {
                RegisterEffect(conf, dest_root, e.name, {});
                continue;
            }
            fs::path root = e.path.parent_path();
            for (const auto& ip : cfg.include_paths) {
                root = ip;
            }
            CopyShaderFile(e.path, root, dest_root, done, r);
            RegisterEffect(conf, dest_root, e.name, dest_root / "Shaders" / e.path.filename());
        }
        for (const auto& m : cfg.messages) {
            r.messages.push_back(m);
        }
    } else {
        r.messages.push_back("unsupported file type '" + ext + "'");
        return r;
    }
    r.ok = r.files_copied > 0;
    r.config_path = conf;
    return r;
}

} // namespace PostProcess
