// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#include <algorithm>
#include <cctype>
#include <charconv>
#include <fstream>
#include <regex>
#include <sstream>
#include "video_core/post_process/reshade_fx.h"

namespace fs = std::filesystem;

namespace PostProcess {

namespace {

// ---------------------------------------------------------------------------------------------
// Generic text helpers
// ---------------------------------------------------------------------------------------------

bool IsIdentChar(char c) {
    return std::isalnum(static_cast<unsigned char>(c)) || c == '_';
}

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

std::string ToLower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return s;
}

std::string ToUpper(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c) { return static_cast<char>(std::toupper(c)); });
    return s;
}

std::string ReadWholeFile(const fs::path& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        return {};
    }
    std::ostringstream ss;
    ss << file.rdbuf();
    return ss.str();
}

/// Index of the bracket matching the one at `open`, or npos
size_t MatchBracket(const std::string& s, size_t open) {
    const char o = s[open];
    const char c = o == '(' ? ')' : o == '{' ? '}' : o == '[' ? ']' : '>';
    int depth = 0;
    for (size_t i = open; i < s.size(); i++) {
        if (s[i] == o) {
            depth++;
        } else if (s[i] == c) {
            if (--depth == 0) {
                return i;
            }
        }
    }
    return std::string::npos;
}

/// Splits at commas that are not nested in brackets
std::vector<std::string> SplitTopLevel(const std::string& s, char sep = ',') {
    std::vector<std::string> out;
    int depth = 0;
    std::string cur;
    for (char c : s) {
        if (c == '(' || c == '[' || c == '{') {
            depth++;
        } else if (c == ')' || c == ']' || c == '}') {
            depth--;
        }
        if (c == sep && depth == 0) {
            out.push_back(cur);
            cur.clear();
        } else {
            cur += c;
        }
    }
    if (!Trim(cur).empty()) {
        out.push_back(cur);
    }
    return out;
}

/// Replaces whole identifier tokens
std::string ReplaceToken(const std::string& text, const std::string& from, const std::string& to) {
    std::string out;
    out.reserve(text.size());
    size_t i = 0;
    while (i < text.size()) {
        if (IsIdentChar(text[i]) && (i == 0 || !IsIdentChar(text[i - 1]))) {
            size_t j = i;
            while (j < text.size() && IsIdentChar(text[j])) {
                j++;
            }
            if (text.compare(i, j - i, from) == 0 && j - i == from.size()) {
                out += to;
            } else {
                out.append(text, i, j - i);
            }
            i = j;
        } else {
            out += text[i++];
        }
    }
    return out;
}

// ---------------------------------------------------------------------------------------------
// Includes
// ---------------------------------------------------------------------------------------------

// ReShade.fxh is provided by the GLSL prelude, only the UI macros need to exist as text.
const char* BuiltinHeader(const std::string& name) {
    if (name == "ReShade.fxh" || name == "ReShadeUI.fxh" || name == "ReShade/ReShade.fxh") {
        return "";
    }
    return nullptr;
}

struct IncludeContext {
    std::vector<fs::path> search_paths;
    std::set<fs::path> pragma_once;
    std::vector<std::string>* messages;
};

std::string ResolveIncludes(const std::string& raw, const fs::path& dir, IncludeContext& ctx,
                            int depth) {
    if (depth > 16) {
        ctx.messages->push_back("error: #include nested too deeply");
        return {};
    }
    const std::string text = Detail::StripComments(raw);
    std::string out;
    std::istringstream lines(text);
    std::string line;
    while (std::getline(lines, line)) {
        const std::string trimmed = Trim(line);
        if (trimmed.rfind('#', 0) == 0) {
            std::string directive = Trim(trimmed.substr(1));
            if (directive.rfind("include", 0) == 0) {
                const std::string rest = Trim(directive.substr(7));
                if (rest.size() > 2 && (rest[0] == '"' || rest[0] == '<')) {
                    const char close = rest[0] == '"' ? '"' : '>';
                    const size_t end = rest.find(close, 1);
                    if (end != std::string::npos) {
                        const std::string name = rest.substr(1, end - 1);
                        if (BuiltinHeader(name)) {
                            out += '\n';
                            continue;
                        }
                        fs::path found;
                        std::vector<fs::path> candidates{dir / name};
                        for (const auto& p : ctx.search_paths) {
                            candidates.push_back(p / name);
                        }
                        for (const auto& c : candidates) {
                            std::error_code ec;
                            if (fs::is_regular_file(c, ec)) {
                                found = fs::weakly_canonical(c, ec);
                                break;
                            }
                        }
                        if (found.empty()) {
                            ctx.messages->push_back("error: cannot find include '" + name + "'");
                            out += '\n';
                            continue;
                        }
                        if (ctx.pragma_once.count(found)) {
                            out += '\n';
                            continue;
                        }
                        const std::string body = ReadWholeFile(found);
                        if (body.find("#pragma once") != std::string::npos) {
                            ctx.pragma_once.insert(found);
                        }
                        out += ResolveIncludes(body, found.parent_path(), ctx, depth + 1);
                        out += '\n';
                        continue;
                    }
                }
            } else if (directive.rfind("pragma", 0) == 0) {
                // #pragma once and #pragma reshade are meaningless to glslang
                out += '\n';
                continue;
            }
        }
        out += line;
        out += '\n';
    }
    return out;
}

// ---------------------------------------------------------------------------------------------
// Declarations
// ---------------------------------------------------------------------------------------------

struct TextureInfo {
    enum class Kind { BackBuffer, Depth, File, RenderTarget } kind = Kind::RenderTarget;
    std::string source;
};

struct PassInfo {
    std::string name;
    std::string pixel_shader;
    std::string vertex_shader;
    bool unsupported_state = false;
    std::string unsupported_reason;
};

struct TechniqueInfo {
    std::string name;
    std::vector<PassInfo> passes;
};

struct ParseState {
    std::map<std::string, TextureInfo> textures;
    std::vector<TechniqueInfo> techniques;
    std::vector<std::string>* messages = nullptr;
    const FxOptions* options = nullptr;
    bool failed = false;

    void Error(const std::string& m) {
        messages->push_back("error: " + m);
        failed = true;
    }
    void Warn(const std::string& m) {
        messages->push_back("warning: " + m);
    }
};

const char* GlslTypeOf(const std::string& hlsl) {
    static const std::map<std::string, const char*> kTypes = {
        {"float", "float"},   {"half", "float"},    {"int", "int"},       {"uint", "uint"},
        {"bool", "bool"},     {"float2", "vec2"},   {"float3", "vec3"},   {"float4", "vec4"},
        {"half2", "vec2"},    {"half3", "vec3"},    {"half4", "vec4"},    {"int2", "ivec2"},
        {"int3", "ivec3"},    {"int4", "ivec4"},    {"uint2", "uvec2"},   {"uint3", "uvec3"},
        {"uint4", "uvec4"},   {"bool2", "bvec2"},   {"bool3", "bvec3"},   {"bool4", "bvec4"},
    };
    const auto it = kTypes.find(hlsl);
    return it == kTypes.end() ? nullptr : it->second;
}

int ComponentCount(const std::string& hlsl) {
    if (!hlsl.empty() && std::isdigit(static_cast<unsigned char>(hlsl.back()))) {
        return hlsl.back() - '0';
    }
    return 1;
}

std::string BaseKind(const std::string& hlsl) {
    if (hlsl.rfind("float", 0) == 0 || hlsl.rfind("half", 0) == 0) {
        return "float";
    }
    if (hlsl.rfind("uint", 0) == 0) {
        return "uint";
    }
    if (hlsl.rfind("int", 0) == 0) {
        return "int";
    }
    return "bool";
}

bool IsNumberLiteral(const std::string& s) {
    static const std::regex re(R"(^[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?[fFhH]?$)");
    return std::regex_match(s, re);
}

std::string FloatLiteral(const std::string& s) {
    std::string t = Trim(s);
    if (!t.empty() && (t.back() == 'f' || t.back() == 'F' || t.back() == 'h' || t.back() == 'H')) {
        t.pop_back();
    }
    if (t.find_first_of(".eE") == std::string::npos) {
        t += ".0";
    }
    return t;
}

/// Formats a user supplied override ("0.5", "1, 2, 3", "true") as a GLSL expression
std::string FormatOverride(const std::string& type, const std::string& value) {
    const char* glsl = GlslTypeOf(type);
    if (!glsl) {
        return {};
    }
    std::string v = value;
    std::replace(v.begin(), v.end(), ',', ' ');
    std::istringstream in(v);
    std::vector<std::string> parts;
    std::string tok;
    while (in >> tok) {
        parts.push_back(tok);
    }
    const int n = ComponentCount(type);
    const std::string kind = BaseKind(type);
    if (parts.empty()) {
        return {};
    }
    std::vector<std::string> converted;
    for (const auto& p : parts) {
        const std::string lower = ToLower(p);
        if (kind == "bool") {
            converted.push_back((lower == "true" || lower == "1") ? "true" : "false");
        } else if (kind == "float") {
            if (!IsNumberLiteral(p)) {
                return {};
            }
            converted.push_back(FloatLiteral(p));
        } else {
            if (!IsNumberLiteral(p)) {
                return {};
            }
            std::string iv = p;
            const size_t dot = iv.find('.');
            if (dot != std::string::npos) {
                iv = iv.substr(0, dot);
            }
            converted.push_back(kind == "uint" ? iv + "u" : iv);
        }
    }
    if (n == 1) {
        return converted[0];
    }
    while (static_cast<int>(converted.size()) < n) {
        converted.push_back(converted.back());
    }
    std::string out = std::string(glsl) + "(";
    for (int i = 0; i < n; i++) {
        out += (i ? ", " : "") + converted[i];
    }
    return out + ")";
}

std::string ZeroValue(const std::string& type) {
    const char* glsl = GlslTypeOf(type);
    const std::string kind = BaseKind(type);
    const std::string zero = kind == "float" ? "0.0" : kind == "bool" ? "false" : "0";
    if (ComponentCount(type) == 1) {
        return zero;
    }
    return std::string(glsl) + "(" + zero + ")";
}

/// Reads annotation `key = "value";` from the text between '<' and '>'
std::string Annotation(const std::string& ann, const std::string& key) {
    size_t pos = 0;
    while ((pos = ann.find(key, pos)) != std::string::npos) {
        const bool left_ok = pos == 0 || !IsIdentChar(ann[pos - 1]);
        const size_t after = pos + key.size();
        if (left_ok && (after >= ann.size() || !IsIdentChar(ann[after]))) {
            size_t eq = ann.find('=', after);
            if (eq == std::string::npos) {
                return {};
            }
            size_t end = ann.find(';', eq);
            std::string value = Trim(ann.substr(eq + 1, end == std::string::npos ? end : end - eq - 1));
            if (value.size() >= 2 && value.front() == '"' && value.back() == '"') {
                value = value.substr(1, value.size() - 2);
            }
            return value;
        }
        pos = after;
    }
    return {};
}

/// `uniform float3 name < annotations > = init;` -> constant or macro. Returns replacement text.
std::string HandleUniform(const std::string& stmt, ParseState& st) {
    // stmt excludes the trailing ';'
    size_t p = stmt.find("uniform") + 7;
    auto skip_ws = [&] {
        while (p < stmt.size() && std::isspace(static_cast<unsigned char>(stmt[p]))) {
            p++;
        }
    };
    auto read_ident = [&] {
        skip_ws();
        size_t b = p;
        while (p < stmt.size() && IsIdentChar(stmt[p])) {
            p++;
        }
        return stmt.substr(b, p - b);
    };
    std::string type = read_ident();
    if (type == "const" || type == "static") {
        type = read_ident();
    }
    const std::string name = read_ident();
    if (type.empty() || name.empty() || !GlslTypeOf(type)) {
        st.Error("unsupported uniform declaration '" + Trim(stmt) + "'");
        return {};
    }
    skip_ws();
    std::string annotations;
    if (p < stmt.size() && stmt[p] == '<') {
        const size_t close = MatchBracket(stmt, p);
        if (close == std::string::npos) {
            st.Error("unterminated annotation of uniform " + name);
            return {};
        }
        annotations = stmt.substr(p + 1, close - p - 1);
        p = close + 1;
    }
    skip_ws();
    std::string init;
    if (p < stmt.size() && stmt[p] == '=') {
        init = Trim(stmt.substr(p + 1));
    }

    const char* glsl = GlslTypeOf(type);
    const std::string source = Annotation(annotations, "source");
    if (!source.empty()) {
        const std::string kind = BaseKind(type);
        std::string field;
        if (source == "timer") {
            field = "rs_pc.rs_timer";
        } else if (source == "frametime") {
            field = "rs_pc.rs_frametime";
        } else if (source == "framecount") {
            field = "rs_pc.rs_framecount";
        } else if (source == "random") {
            field = "rs_pc.rs_random";
        }
        if (!field.empty() && ComponentCount(type) == 1) {
            const std::string expr = kind == "float" ? field : std::string(glsl) + "(" + field + ")";
            return "#define " + name + " (" + expr + ")\n";
        }
        st.Warn("uniform source '" + source + "' is not available, using a constant (" + name + ")");
        return std::string("const ") + glsl + " " + name + " = " + ZeroValue(type) + ";\n";
    }

    std::string value;
    const auto ov = st.options->uniform_overrides.find(name);
    if (ov != st.options->uniform_overrides.end()) {
        value = FormatOverride(type, ov->second);
        if (value.empty()) {
            st.Warn("ignoring invalid value '" + ov->second + "' for " + name);
        }
    }
    if (value.empty()) {
        if (!init.empty()) {
            value = init;
            if (ComponentCount(type) > 1 && IsNumberLiteral(init)) {
                value = std::string(glsl) + "(" + init + ")";
            }
        } else {
            value = ZeroValue(type);
        }
    }
    return std::string("const ") + glsl + " " + name + " = " + value + ";\n";
}

/// Reads `Key = Value;` states of a sampler / pass body
std::map<std::string, std::string> ParseStates(const std::string& body) {
    std::map<std::string, std::string> out;
    for (const auto& stmt : SplitTopLevel(body, ';')) {
        const size_t eq = stmt.find('=');
        if (eq == std::string::npos) {
            continue;
        }
        out[Trim(stmt.substr(0, eq))] = Trim(stmt.substr(eq + 1));
    }
    return out;
}

std::string HandleTexture(const std::string& stmt, ParseState& st) {
    // texture2D Name < ... > [: SEMANTIC] [{ ... }]
    static const std::regex head(R"(^\s*texture(?:2D)?\s+(\w+))");
    std::smatch m;
    if (!std::regex_search(stmt, m, head)) {
        st.Error("unsupported texture declaration");
        return {};
    }
    const std::string name = m[1];
    TextureInfo info;
    const size_t lt = stmt.find('<');
    const size_t brace = stmt.find('{');
    std::string annotations;
    if (lt != std::string::npos && (brace == std::string::npos || lt < brace)) {
        const size_t close = MatchBracket(stmt, lt);
        if (close != std::string::npos) {
            annotations = stmt.substr(lt + 1, close - lt - 1);
        }
    }
    const std::string tail = stmt.substr(m.length(0));
    const std::string upper = ToUpper(tail);
    if (upper.find(": COLOR") != std::string::npos || upper.find(":COLOR") != std::string::npos) {
        info.kind = TextureInfo::Kind::BackBuffer;
    } else if (upper.find(": DEPTH") != std::string::npos ||
               upper.find(":DEPTH") != std::string::npos) {
        info.kind = TextureInfo::Kind::Depth;
    } else if (const std::string src = Annotation(annotations, "source"); !src.empty()) {
        info.kind = TextureInfo::Kind::File;
        info.source = src;
    } else {
        info.kind = TextureInfo::Kind::RenderTarget;
    }
    st.textures[name] = info;
    return {};
}

std::string HandleSampler(const std::string& stmt, ParseState& st) {
    static const std::regex head(R"(^\s*sampler(?:2D)?\s+(\w+)\s*\{)");
    std::smatch m;
    if (!std::regex_search(stmt, m, head)) {
        st.Error("unsupported sampler declaration");
        return {};
    }
    const std::string name = m[1];
    const size_t open = stmt.find('{');
    const size_t close = MatchBracket(stmt, open);
    const auto states = ParseStates(stmt.substr(open + 1, close - open - 1));
    std::string texture;
    bool point = false;
    for (const auto& [key, value] : states) {
        if (key == "Texture") {
            texture = value;
        } else if ((key == "MinFilter" || key == "MagFilter") && ToUpper(value) == "POINT") {
            point = true;
        }
    }
    TextureInfo info;
    if (texture == "ReShade_BackBuffer" || texture == "ReShade_BackBufferTex") {
        info.kind = TextureInfo::Kind::BackBuffer;
    } else if (auto it = st.textures.find(texture); it != st.textures.end()) {
        info = it->second;
    } else {
        st.Error("sampler " + name + " uses unknown texture '" + texture + "'");
    }
    switch (info.kind) {
    case TextureInfo::Kind::BackBuffer:
        break;
    case TextureInfo::Kind::Depth:
        st.Error("depth buffer access (sampler " + name + ") is not supported");
        break;
    case TextureInfo::Kind::File:
        st.Error("textures loaded from files ('" + info.source + "') are not supported");
        break;
    case TextureInfo::Kind::RenderTarget:
        st.Error("intermediate render target textures (sampler " + name + ") are not supported");
        break;
    }
    return "#define " + name + (point ? " rs_bb_point\n" : " rs_bb_linear\n");
}

void HandleTechnique(const std::string& stmt, ParseState& st) {
    static const std::regex head(R"(^\s*technique(?:11)?\s+(\w+))");
    std::smatch m;
    if (!std::regex_search(stmt, m, head)) {
        st.Error("unsupported technique declaration");
        return;
    }
    TechniqueInfo tech;
    tech.name = m[1];
    const size_t open = stmt.find('{');
    const size_t close = open == std::string::npos ? open : MatchBracket(stmt, open);
    if (close == std::string::npos) {
        st.Error("unterminated technique " + tech.name);
        return;
    }
    const std::string body = stmt.substr(open + 1, close - open - 1);
    size_t p = 0;
    while (true) {
        const size_t kw = body.find("pass", p);
        if (kw == std::string::npos) {
            break;
        }
        if ((kw > 0 && IsIdentChar(body[kw - 1])) ||
            (kw + 4 < body.size() && IsIdentChar(body[kw + 4]) && body[kw + 4] != '\0' &&
             !std::isspace(static_cast<unsigned char>(body[kw + 4])))) {
            p = kw + 4;
            continue;
        }
        const size_t pass_open = body.find('{', kw);
        if (pass_open == std::string::npos) {
            break;
        }
        const size_t pass_close = MatchBracket(body, pass_open);
        if (pass_close == std::string::npos) {
            break;
        }
        PassInfo pass;
        pass.name = Trim(body.substr(kw + 4, pass_open - kw - 4));
        for (const auto& [key, value] : ParseStates(body.substr(pass_open + 1, pass_close - pass_open - 1))) {
            if (key == "PixelShader") {
                pass.pixel_shader = value;
            } else if (key == "VertexShader") {
                pass.vertex_shader = value;
            } else if (key.rfind("RenderTarget", 0) == 0 && !value.empty()) {
                pass.unsupported_state = true;
                pass.unsupported_reason = "render targets (" + key + " = " + value + ")";
            } else if (key == "ComputeShader") {
                pass.unsupported_state = true;
                pass.unsupported_reason = "compute shaders";
            } else if (key == "BlendEnable" && ToLower(value) == "true") {
                st.Warn("BlendEnable in pass '" + pass.name + "' is ignored");
            }
        }
        tech.passes.push_back(std::move(pass));
        p = pass_close + 1;
    }
    st.techniques.push_back(std::move(tech));
}

// ---------------------------------------------------------------------------------------------
// Top level scan
// ---------------------------------------------------------------------------------------------

/// Expands the ReShadeUI.fxh macros (__UNIFORM_DRAG_FLOAT1 -> uniform float ...)
std::string ExpandUiMacros(const std::string& text) {
    static const std::regex re(
        R"(__UNIFORM_(?:DRAG|SLIDER|INPUT|COLOR|RADIO|COMBO|LIST)_(FLOAT|INT|UINT|BOOL)([1-4])?\b)");
    std::string out;
    auto begin = std::sregex_iterator(text.begin(), text.end(), re);
    size_t last = 0;
    for (auto it = begin; it != std::sregex_iterator(); ++it) {
        out.append(text, last, it->position() - last);
        std::string kind = ToLower((*it)[1]);
        std::string n = (*it)[2];
        out += "uniform " + kind + (n.empty() || n == "1" ? "" : n);
        last = it->position() + it->length();
    }
    out.append(text, last, std::string::npos);
    return out;
}

/// Walks the top level statements. Declarations the translator owns are replaced in place by
/// their GLSL equivalent (keeping preprocessor conditionals around them intact), everything else
/// is copied.
std::string ProcessTopLevel(const std::string& text, ParseState& st) {
    std::string out;
    size_t i = 0;
    const size_t n = text.size();
    while (i < n) {
        // Skip whitespace
        if (std::isspace(static_cast<unsigned char>(text[i]))) {
            out += text[i++];
            continue;
        }
        // Preprocessor line (with continuations)
        if (text[i] == '#') {
            size_t e = i;
            while (e < n) {
                if (text[e] == '\n' && (e == 0 || text[e - 1] != '\\')) {
                    break;
                }
                e++;
            }
            out.append(text, i, e - i);
            i = e;
            continue;
        }
        // Find the end of this statement: ';' at depth 0, or the closing '}' of a body that is
        // not followed by ';' (functions) or is followed by ';' (struct, sampler, technique).
        size_t e = i;
        int paren = 0;
        bool body = false;
        size_t end = std::string::npos;
        while (e < n) {
            const char c = text[e];
            if (c == '(' || c == '[') {
                paren++;
            } else if (c == ')' || c == ']') {
                paren--;
            } else if (c == '<' && paren == 0) {
                // annotation block of uniforms / textures / techniques
                const size_t close = MatchBracket(text, e);
                if (close != std::string::npos &&
                    text.find(';', e) < close) { // annotations contain ';'
                    e = close;
                }
            } else if (c == '{' && paren == 0) {
                const size_t close = MatchBracket(text, e);
                if (close == std::string::npos) {
                    break;
                }
                body = true;
                e = close;
                size_t q = e + 1;
                while (q < n && std::isspace(static_cast<unsigned char>(text[q]))) {
                    q++;
                }
                // `= { 1, 2 };` initializers and `struct {};` end with a semicolon
                if (q < n && text[q] == ';') {
                    end = q;
                } else {
                    end = e;
                }
                break;
            } else if (c == ';' && paren == 0) {
                end = e;
                break;
            }
            e++;
        }
        if (end == std::string::npos) {
            out.append(text, i, std::string::npos);
            break;
        }
        const std::string stmt = text.substr(i, end - i + 1);
        std::string first;
        {
            size_t b = 0;
            while (b < stmt.size() && IsIdentChar(stmt[b])) {
                first += stmt[b++];
            }
        }
        // `static const` and friends are plain constants
        if (first == "uniform") {
            out += HandleUniform(stmt.substr(0, stmt.size() - 1), st);
        } else if (first == "texture" || first == "texture2D") {
            HandleTexture(stmt, st);
        } else if (first == "sampler" || first == "sampler2D") {
            out += HandleSampler(stmt, st);
        } else if (first == "technique" || first == "technique11") {
            HandleTechnique(stmt, st);
        } else if (first == "namespace") {
            st.Error("namespaces are not supported");
            out += stmt;
        } else {
            out += stmt;
        }
        (void)body;
        i = end + 1;
    }
    return out;
}

// ---------------------------------------------------------------------------------------------
// Pixel shader entry points
// ---------------------------------------------------------------------------------------------

struct EntryParam {
    enum class Role { Position, TexCoord, OutColor } role;
    std::string type;
};

struct EntryInfo {
    bool ok = false;
    bool returns_color = false;
    std::vector<EntryParam> params;
    std::string message;
};

EntryInfo ParseEntry(const std::string& text, const std::string& name) {
    EntryInfo info;
    size_t pos = 0;
    while ((pos = text.find(name, pos)) != std::string::npos) {
        const size_t after = pos + name.size();
        const bool left_ok = pos == 0 || !IsIdentChar(text[pos - 1]);
        size_t q = after;
        while (q < text.size() && std::isspace(static_cast<unsigned char>(text[q]))) {
            q++;
        }
        if (!left_ok || q >= text.size() || text[q] != '(' || IsIdentChar(text[after])) {
            pos = after;
            continue;
        }
        // Return type: previous identifier
        size_t r = pos;
        while (r > 0 && std::isspace(static_cast<unsigned char>(text[r - 1]))) {
            r--;
        }
        size_t rb = r;
        while (rb > 0 && IsIdentChar(text[rb - 1])) {
            rb--;
        }
        const std::string ret = text.substr(rb, r - rb);
        const size_t close = MatchBracket(text, q);
        if (close == std::string::npos) {
            break;
        }
        // Definitions have a body, calls and prototypes do not
        size_t after_params = close + 1;
        while (after_params < text.size() &&
               std::isspace(static_cast<unsigned char>(text[after_params]))) {
            after_params++;
        }
        std::string ret_semantic;
        if (after_params < text.size() && text[after_params] == ':') {
            size_t se = after_params + 1;
            while (se < text.size() && (std::isspace(static_cast<unsigned char>(text[se])) ||
                                        IsIdentChar(text[se]))) {
                se++;
            }
            ret_semantic = ToUpper(Trim(text.substr(after_params + 1, se - after_params - 1)));
            after_params = se;
        }
        if (after_params >= text.size() || text[after_params] != '{') {
            pos = after;
            continue;
        }
        for (const auto& param : SplitTopLevel(text.substr(q + 1, close - q - 1))) {
            std::string p = Trim(param);
            if (p.empty()) {
                continue;
            }
            std::string semantic;
            if (const size_t colon = p.find(':'); colon != std::string::npos) {
                semantic = ToUpper(Trim(p.substr(colon + 1)));
                p = Trim(p.substr(0, colon));
            }
            std::istringstream words(p);
            std::vector<std::string> w;
            std::string tok;
            while (words >> tok) {
                w.push_back(tok);
            }
            const bool is_out = !w.empty() && (w[0] == "out" || w[0] == "inout");
            if (!w.empty() && (w[0] == "in" || is_out)) {
                w.erase(w.begin());
            }
            if (w.size() < 2) {
                info.message = "unsupported parameter '" + p + "'";
                return info;
            }
            const std::string type = w[0];
            if (semantic == "SV_POSITION" || semantic == "POSITION") {
                info.params.push_back({EntryParam::Role::Position, type});
            } else if (semantic.rfind("TEXCOORD", 0) == 0 && (semantic == "TEXCOORD" || semantic == "TEXCOORD0")) {
                info.params.push_back({EntryParam::Role::TexCoord, type});
            } else if (is_out && (semantic.rfind("SV_TARGET", 0) == 0 || semantic.rfind("COLOR", 0) == 0)) {
                info.params.push_back({EntryParam::Role::OutColor, type});
            } else {
                info.message = "pixel shader input '" + p + (semantic.empty() ? "" : " : " + semantic) +
                               "' is not supported";
                return info;
            }
        }
        const bool has_out = std::any_of(info.params.begin(), info.params.end(), [](const auto& p) {
            return p.role == EntryParam::Role::OutColor;
        });
        info.returns_color = ret != "void";
        if (!info.returns_color && !has_out) {
            info.message = "pixel shader writes no color";
            return info;
        }
        if (info.returns_color && ret != "float4" && ret != "half4") {
            info.message = "pixel shader returns " + ret + ", float4 is required";
            return info;
        }
        (void)ret_semantic;
        info.ok = true;
        return info;
    }
    info.message = "pixel shader '" + name + "' was not found";
    return info;
}

std::string BuildMain(const std::string& name, const EntryInfo& entry) {
    std::string args;
    for (size_t i = 0; i < entry.params.size(); i++) {
        const auto& p = entry.params[i];
        std::string a;
        const int comps = ComponentCount(p.type);
        switch (p.role) {
        case EntryParam::Role::Position:
            a = comps == 4 ? "gl_FragCoord" : comps == 3 ? "gl_FragCoord.xyz" : "gl_FragCoord.xy";
            break;
        case EntryParam::Role::TexCoord:
            a = comps == 4 ? "vec4(rs_texcoord, 0.0, 0.0)"
                           : comps == 3 ? "vec3(rs_texcoord, 0.0)" : "rs_texcoord";
            break;
        case EntryParam::Role::OutColor:
            a = "rs_result";
            break;
        }
        args += (i ? ", " : "") + a;
    }
    std::string out = "\nlayout(location = 0) in vec2 rs_texcoord;\n"
                      "layout(location = 0) out vec4 rs_color;\n"
                      "void main() {\n    vec4 rs_result = vec4(0.0);\n";
    if (entry.returns_color) {
        out += "    rs_result = " + name + "(" + args + ");\n";
    } else {
        out += "    " + name + "(" + args + ");\n";
    }
    out += "    rs_color = vec4(rs_result.rgb, 1.0);\n}\n";
    return out;
}

// ---------------------------------------------------------------------------------------------
// GLSL prelude
// ---------------------------------------------------------------------------------------------

std::string BuildPrelude(const FxOptions& o) {
    std::ostringstream p;
    p << "#version 450\n"
         "#extension GL_ARB_separate_shader_objects : enable\n"
         "#define float2 vec2\n#define float3 vec3\n#define float4 vec4\n"
         "#define half float\n#define half2 vec2\n#define half3 vec3\n#define half4 vec4\n"
         "#define int2 ivec2\n#define int3 ivec3\n#define int4 ivec4\n"
         "#define uint2 uvec2\n#define uint3 uvec3\n#define uint4 uvec4\n"
         "#define bool2 bvec2\n#define bool3 bvec3\n#define bool4 bvec4\n"
         "#define float2x2 mat2\n#define float3x3 mat3\n#define float4x4 mat4\n"
         "#define float2x3 mat2x3\n#define float3x2 mat3x2\n#define float2x4 mat2x4\n"
         "#define float4x2 mat4x2\n#define float3x4 mat3x4\n#define float4x3 mat4x3\n"
         "#define lerp mix\n#define frac fract\n#define rsqrt inversesqrt\n"
         "#define ddx dFdx\n#define ddy dFdy\n#define ddx_fine dFdxFine\n#define ddy_fine dFdyFine\n"
         "#define RS_RENDERER 0x20000\n#define RS_VENDOR 0\n#define RS_DEVICE 0\n"
         "#define RS_APPLICATION 0\n#define RS_VERSION 50000\n"
         "#define BUFFER_WIDTH "
      << o.width << "\n#define BUFFER_HEIGHT " << o.height
      << "\n"
         "#define BUFFER_RCP_WIDTH (1.0 / BUFFER_WIDTH)\n"
         "#define BUFFER_RCP_HEIGHT (1.0 / BUFFER_HEIGHT)\n"
         "#define BUFFER_PIXEL_SIZE float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT)\n"
         "#define BUFFER_SCREEN_SIZE float2(BUFFER_WIDTH, BUFFER_HEIGHT)\n"
         "#define BUFFER_ASPECT_RATIO (BUFFER_WIDTH * BUFFER_RCP_HEIGHT)\n"
         "#define BUFFER_COLOR_BIT_DEPTH 8\n"
         "#define BUFFER_COLOR_SPACE 1\n"
         "layout(set = 0, binding = 0) uniform sampler2D rs_bb_linear;\n"
         "layout(set = 0, binding = 1) uniform sampler2D rs_bb_point;\n"
         "layout(push_constant) uniform RsPush {\n"
         "    float rs_timer;\n    float rs_frametime;\n    float rs_framecount;\n    float rs_random;\n"
         "} rs_pc;\n"
         "#define ReShade_BackBuffer rs_bb_linear\n#define ReShade_BackBufferTex rs_bb_linear\n"
         "const vec2 ReShade_PixelSize = vec2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);\n"
         "const vec2 ReShade_ScreenSize = vec2(BUFFER_WIDTH, BUFFER_HEIGHT);\n"
         "const float ReShade_AspectRatio = BUFFER_ASPECT_RATIO;\n"
         "float ReShade_GetAspectRatio() { return BUFFER_ASPECT_RATIO; }\n"
         "vec2 ReShade_GetPixelSize() { return ReShade_PixelSize; }\n"
         "vec2 ReShade_GetScreenSize() { return ReShade_ScreenSize; }\n"
         "float ReShade_GetLinearizedDepth(vec2 uv) { return 1.0; }\n"
         // HLSL intrinsics that differ from GLSL
         "float saturate(float x) { return clamp(x, 0.0, 1.0); }\n"
         "vec2 saturate(vec2 x) { return clamp(x, 0.0, 1.0); }\n"
         "vec3 saturate(vec3 x) { return clamp(x, 0.0, 1.0); }\n"
         "vec4 saturate(vec4 x) { return clamp(x, 0.0, 1.0); }\n"
         "float rcp(float x) { return 1.0 / x; }\n"
         "vec2 rcp(vec2 x) { return 1.0 / x; }\n"
         "vec3 rcp(vec3 x) { return 1.0 / x; }\n"
         "vec4 rcp(vec4 x) { return 1.0 / x; }\n"
         "float fmod(float x, float y) { return x - y * trunc(x / y); }\n"
         "vec2 fmod(vec2 x, vec2 y) { return x - y * trunc(x / y); }\n"
         "vec3 fmod(vec3 x, vec3 y) { return x - y * trunc(x / y); }\n"
         "vec4 fmod(vec4 x, vec4 y) { return x - y * trunc(x / y); }\n"
         "float atan2(float y, float x) { return atan(y, x); }\n"
         "vec2 atan2(vec2 y, vec2 x) { return atan(y, x); }\n"
         "vec3 atan2(vec3 y, vec3 x) { return atan(y, x); }\n"
         "vec4 atan2(vec4 y, vec4 x) { return atan(y, x); }\n"
         "vec2 pow(vec2 x, float y) { return pow(x, vec2(y)); }\n"
         "vec3 pow(vec3 x, float y) { return pow(x, vec3(y)); }\n"
         "vec4 pow(vec4 x, float y) { return pow(x, vec4(y)); }\n"
         "vec2 max(float a, vec2 b) { return max(vec2(a), b); }\n"
         "vec3 max(float a, vec3 b) { return max(vec3(a), b); }\n"
         "vec4 max(float a, vec4 b) { return max(vec4(a), b); }\n"
         "vec2 min(float a, vec2 b) { return min(vec2(a), b); }\n"
         "vec3 min(float a, vec3 b) { return min(vec3(a), b); }\n"
         "vec4 min(float a, vec4 b) { return min(vec4(a), b); }\n"
         "float mad(float a, float b, float c) { return a * b + c; }\n"
         "vec2 mad(vec2 a, vec2 b, vec2 c) { return a * b + c; }\n"
         "vec3 mad(vec3 a, vec3 b, vec3 c) { return a * b + c; }\n"
         "vec4 mad(vec4 a, vec4 b, vec4 c) { return a * b + c; }\n"
         "void sincos(float x, out float s, out float c) { s = sin(x); c = cos(x); }\n"
         "void sincos(vec2 x, out vec2 s, out vec2 c) { s = sin(x); c = cos(x); }\n"
         "void sincos(vec3 x, out vec3 s, out vec3 c) { s = sin(x); c = cos(x); }\n"
         "void sincos(vec4 x, out vec4 s, out vec4 c) { s = sin(x); c = cos(x); }\n"
         "void clip(float x) { if (x < 0.0) discard; }\n"
         "void clip(vec2 x) { if (any(lessThan(x, vec2(0.0)))) discard; }\n"
         "void clip(vec3 x) { if (any(lessThan(x, vec3(0.0)))) discard; }\n"
         "void clip(vec4 x) { if (any(lessThan(x, vec4(0.0)))) discard; }\n"
         "float asfloat(int x) { return intBitsToFloat(x); }\n"
         "float asfloat(uint x) { return uintBitsToFloat(x); }\n"
         "int asint(float x) { return floatBitsToInt(x); }\n"
         "uint asuint(float x) { return floatBitsToUint(x); }\n"
         // HLSL matrices are row major, the GLSL matrices built from the same constructor
         // arguments are their transpose, which flips the operand order of mul().
         "vec2 mul(mat2 m, vec2 v) { return v * m; }\nvec2 mul(vec2 v, mat2 m) { return m * v; }\n"
         "vec3 mul(mat3 m, vec3 v) { return v * m; }\nvec3 mul(vec3 v, mat3 m) { return m * v; }\n"
         "vec4 mul(mat4 m, vec4 v) { return v * m; }\nvec4 mul(vec4 v, mat4 m) { return m * v; }\n"
         "mat2 mul(mat2 a, mat2 b) { return b * a; }\n"
         "mat3 mul(mat3 a, mat3 b) { return b * a; }\n"
         "mat4 mul(mat4 a, mat4 b) { return b * a; }\n"
         "float mul(float a, float b) { return a * b; }\n"
         "vec2 mul(float a, vec2 b) { return a * b; }\nvec3 mul(float a, vec3 b) { return a * b; }\n"
         "vec4 mul(float a, vec4 b) { return a * b; }\n"
         "vec2 mul(vec2 a, float b) { return a * b; }\nvec3 mul(vec3 a, float b) { return a * b; }\n"
         "vec4 mul(vec4 a, float b) { return a * b; }\n"
         // Texture functions
         "vec4 tex2D(sampler2D s, vec2 uv) { return texture(s, uv); }\n"
         "vec4 tex2Dlod(sampler2D s, vec4 c) { return textureLod(s, c.xy, c.w); }\n"
         "vec4 tex2Dbias(sampler2D s, vec4 c) { return texture(s, c.xy, c.w); }\n"
         "vec4 tex2Dfetch(sampler2D s, ivec2 p) { return texelFetch(s, p, 0); }\n"
         "vec4 tex2Dfetch(sampler2D s, ivec2 p, int lod) { return texelFetch(s, p, lod); }\n"
         "ivec2 tex2Dsize(sampler2D s, int lod) { return textureSize(s, lod); }\n"
         "vec4 tex2Doffset(sampler2D s, vec2 uv, ivec2 o) { return textureOffset(s, uv, o); }\n"
         "vec4 tex2Dgather(sampler2D s, vec2 uv, int c) { return textureGather(s, uv, c); }\n";
    return p.str();
}

} // namespace

// ---------------------------------------------------------------------------------------------
// Detail (exposed for tests)
// ---------------------------------------------------------------------------------------------

namespace Detail {

std::string StripComments(const std::string& text) {
    std::string out;
    out.reserve(text.size());
    size_t i = 0;
    while (i < text.size()) {
        if (text[i] == '"') {
            size_t j = i + 1;
            while (j < text.size() && text[j] != '"') {
                if (text[j] == '\\') {
                    j++;
                }
                j++;
            }
            out.append(text, i, std::min(j + 1, text.size()) - i);
            i = j + 1;
        } else if (text.compare(i, 2, "//") == 0) {
            while (i < text.size() && text[i] != '\n') {
                i++;
            }
        } else if (text.compare(i, 2, "/*") == 0) {
            const size_t end = text.find("*/", i + 2);
            const size_t stop = end == std::string::npos ? text.size() : end + 2;
            for (size_t k = i; k < stop; k++) {
                if (text[k] == '\n') {
                    out += '\n';
                }
            }
            out += ' ';
            i = stop;
        } else {
            out += text[i++];
        }
    }
    return out;
}

/// `(float3)expr` -> `float3(expr)`
std::string ConvertCasts(const std::string& text) {
    static const std::regex cast(R"(\(\s*(float|half|int|uint|bool)([234]?)\s*\))");
    std::string result = text;
    size_t search_from = 0;
    while (true) {
        std::smatch m;
        auto begin = result.cbegin() + search_from;
        if (!std::regex_search(begin, result.cend(), m, cast)) {
            break;
        }
        const size_t start = search_from + m.position(0);
        const size_t after = start + m.length(0);
        // A cast is followed by an operand, a function declaration `(float) ...` is not possible
        size_t p = after;
        while (p < result.size() && std::isspace(static_cast<unsigned char>(result[p]))) {
            p++;
        }
        size_t operand_begin = p;
        while (p < result.size() && (result[p] == '-' || result[p] == '+' || result[p] == '!' ||
                                      result[p] == '~')) {
            p++;
        }
        if (p >= result.size()) {
            break;
        }
        if (result[p] == '(') {
            const size_t close = MatchBracket(result, p);
            if (close == std::string::npos) {
                break;
            }
            p = close + 1;
        } else if (IsIdentChar(result[p]) || result[p] == '.') {
            while (p < result.size() && (IsIdentChar(result[p]) || result[p] == '.')) {
                p++;
            }
        } else {
            search_from = after;
            continue;
        }
        // Postfix: member access, indexing, calls
        while (p < result.size()) {
            if (result[p] == '(' || result[p] == '[') {
                const size_t close = MatchBracket(result, p);
                if (close == std::string::npos) {
                    break;
                }
                p = close + 1;
            } else if (result[p] == '.' && p + 1 < result.size() && IsIdentChar(result[p + 1])) {
                p++;
                while (p < result.size() && IsIdentChar(result[p])) {
                    p++;
                }
            } else {
                break;
            }
        }
        const std::string type = std::string(m[1]) + std::string(m[2]);
        const std::string operand = result.substr(operand_begin, p - operand_begin);
        const std::string replaced = type + "(" + operand + ")";
        result.replace(start, p - start, replaced);
        search_from = start + type.size() + 1; // rescan inside, nested casts are possible
    }
    return result;
}

std::string ConvertHlslSyntax(const std::string& input) {
    std::string t = input;

    // Attributes of statements
    static const std::regex attrs(
        R"(\[\s*(unroll|loop|branch|flatten|fastopt|call|forcecase|allow_uav_condition)\s*(\([^)]*\))?\s*\])");
    t = std::regex_replace(t, attrs, "");

    // Semantics: `: SV_Target`, `: TEXCOORD0`, ...
    static const std::regex semantics(
        R"(\s*:\s*(SV_[A-Za-z]+\d*|TEXCOORD\d*|COLOR\d*|POSITION\d*|NORMAL\d*|DEPTH\d*)\b)");
    t = std::regex_replace(t, semantics, "");

    // Storage and interpolation modifiers
    static const std::regex static_const(R"(\bstatic\s+const\b)");
    t = std::regex_replace(t, static_const, "const");
    static const std::regex modifiers(R"(\b(static|inline|precise|nointerpolation|linear|centroid|noperspective|volatile)\s+)");
    t = std::regex_replace(t, modifiers, "");

    // Predefined macros with reserved names
    for (const char* name : {"__RENDERER__", "__VENDOR__", "__DEVICE__", "__APPLICATION__",
                              "__VERSION__"}) {
        std::string repl = "RS_" + std::string(name).substr(2, std::string(name).size() - 4);
        t = ReplaceToken(t, name, repl);
    }

    t = ConvertCasts(t);

    // `sampler` used as a type (function parameters)
    t = ReplaceToken(t, "sampler", "sampler2D");

    // Scalar initializers of vectors: `float3 c = 0.5;`
    static const std::regex scalar_init(
        R"(\b(float|half|int|uint)([234])\s+(\w+)\s*=\s*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?[fFhH]?)\s*;)");
    t = std::regex_replace(t, scalar_init, "$1$2 $3 = $1$2($4);");

    // Array initializers: `static const float w[3] = { 1, 2, 3 };`
    static const std::regex array_init(
        R"(\b(const\s+)?(float|half|int|uint|float2|float3|float4)\s+(\w+)\s*\[\s*(\w+)\s*\]\s*=\s*\{([^}]*)\})");
    t = std::regex_replace(t, array_init, "$1$2 $3[$4] = $2[]($5)");
    return t;
}

} // namespace Detail

// ---------------------------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------------------------

const char* GetFullscreenVertexShader() {
    return "#version 450\n"
           "layout(location = 0) out vec2 rs_texcoord;\n"
           "void main() {\n"
           "    vec2 pos = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));\n"
           "    rs_texcoord = pos;\n"
           "    gl_Position = vec4(pos * 2.0 - 1.0, 0.0, 1.0);\n"
           "}\n";
}

FxResult TranslateEffect(const fs::path& path, const std::string& source,
                         const FxOptions& options) {
    FxResult result;
    ParseState st;
    st.messages = &result.messages;
    st.options = &options;

    IncludeContext ctx;
    ctx.search_paths = options.include_paths;
    ctx.messages = &result.messages;
    std::string text = ResolveIncludes(source, path.parent_path(), ctx, 0);
    for (const auto& m : result.messages) {
        if (m.rfind("error", 0) == 0) {
            st.failed = true;
        }
    }

    // ReShade::Name -> ReShade_Name, the only namespace of the built in headers
    text = std::regex_replace(text, std::regex(R"(\bReShade\s*::\s*)"), "ReShade_");
    text = ExpandUiMacros(text);
    text = ProcessTopLevel(text, st);

    if (st.techniques.empty()) {
        st.Error("the effect has no technique");
    }
    if (st.failed) {
        return result;
    }

    // Entry points
    std::vector<std::pair<FxTechnique, std::vector<EntryInfo>>> built;
    std::string converted = Detail::ConvertHlslSyntax(text);
    for (const auto& tech : st.techniques) {
        if (!options.enabled_techniques.empty() && !options.enabled_techniques.count(tech.name)) {
            continue;
        }
        FxTechnique out;
        out.name = tech.name;
        bool tech_ok = true;
        int pass_index = 0;
        for (const auto& pass : tech.passes) {
            pass_index++;
            const std::string label = tech.name + (pass.name.empty() ? "#" + std::to_string(pass_index) : "/" + pass.name);
            if (pass.unsupported_state) {
                result.messages.push_back("error: technique " + label + " uses " + pass.unsupported_reason);
                tech_ok = false;
                break;
            }
            if (!pass.vertex_shader.empty() && pass.vertex_shader != "PostProcessVS" &&
                pass.vertex_shader != "ReShade_PostProcessVS") {
                result.messages.push_back("error: technique " + label +
                                          " uses the custom vertex shader " + pass.vertex_shader);
                tech_ok = false;
                break;
            }
            if (pass.pixel_shader.empty()) {
                result.messages.push_back("error: technique " + label + " has no PixelShader");
                tech_ok = false;
                break;
            }
            // The entry point is analysed on the text that still has its semantics
            const EntryInfo entry = ParseEntry(text, pass.pixel_shader);
            if (!entry.ok) {
                result.messages.push_back("error: technique " + label + ": " + entry.message);
                tech_ok = false;
                break;
            }
            FxPass fp;
            fp.name = pass.name.empty() ? tech.name : tech.name + "/" + pass.name;
            fp.fragment_glsl = BuildPrelude(options) + "\n" + converted + BuildMain(pass.pixel_shader, entry);
            out.passes.push_back(std::move(fp));
        }
        if (tech_ok && !out.passes.empty()) {
            result.techniques.push_back(std::move(out));
        }
    }
    result.ok = !result.techniques.empty();
    return result;
}

FxResult TranslateEffectFile(const fs::path& path, const FxOptions& options) {
    FxResult result;
    const std::string source = ReadWholeFile(path);
    if (source.empty()) {
        result.messages.push_back("error: cannot read " + path.string());
        return result;
    }
    return TranslateEffect(path, source, options);
}

} // namespace PostProcess
