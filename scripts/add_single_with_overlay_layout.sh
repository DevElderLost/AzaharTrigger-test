#!/usr/bin/env bash
# ============================================================
# add_single_with_overlay_layout.sh
#
# Tambah layout baru: SingleWithOverlay (nilai 6)
# - top_screen = fullscreen (sama dengan SingleScreen)
# - bottom_screen = overlay kecil di atas top_screen
#   posisi & ukuran dari custom layout settings
#   (Settings::values.custom_bottom_x/y/width/height)
#
# File yang dimodifikasi:
# 1. src/common/settings.h          — tambah enum SingleWithOverlay
# 2. src/core/frontend/framebuffer_layout.h   — deklarasi fungsi
# 3. src/core/frontend/framebuffer_layout.cpp — implementasi fungsi
# 4. src/android/app/src/main/java/.../display/ScreenLayout.kt
#    — tambah SINGLE_WITH_OVERLAY(6)
# 5. src/android/app/src/main/java/.../display/ScreenAdjustmentUtil.kt
#    — update toggleSecondaryScreen() pakai SingleWithOverlay
# ============================================================

set -e

SETTINGS_H="src/common/settings.h"
LAYOUT_H="src/core/frontend/framebuffer_layout.h"
LAYOUT_CPP="src/core/frontend/framebuffer_layout.cpp"
SCREEN_LAYOUT_KT="src/android/app/src/main/java/org/citra/citra_emu/display/ScreenLayout.kt"
ADJUSTMENT_KT="src/android/app/src/main/java/org/citra/citra_emu/display/ScreenAdjustmentUtil.kt"

for f in "$SETTINGS_H" "$LAYOUT_H" "$LAYOUT_CPP" "$SCREEN_LAYOUT_KT" "$ADJUSTMENT_KT"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: File tidak ditemukan: $f"
        exit 1
    fi
done

echo "=== Backup ==="
for f in "$SETTINGS_H" "$LAYOUT_H" "$LAYOUT_CPP" "$SCREEN_LAYOUT_KT" "$ADJUSTMENT_KT"; do
    cp "$f" "${f}.bak5"
done
echo "Backup selesai."

# ============================================================
# Step 1: settings.h — tambah SingleWithOverlay = 6
# ============================================================
echo ""
echo "=== Step 1: Tambah SingleWithOverlay di settings.h ==="

python3 - "$SETTINGS_H" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'SingleWithOverlay' in content:
    print("Sudah ada, skip.")
    sys.exit(0)

# Cari enum LayoutOption dan tambahkan setelah CustomLayout
import re
# Pattern: CustomLayout, diikuti titik koma atau koma
pattern = r'(CustomLayout\s*,?\s*\n)'
match = re.search(pattern, content)
if match:
    old = match.group(0)
    # Tambahkan setelah CustomLayout
    new = old.rstrip('\n') + '\n        SingleWithOverlay,  // Single screen with bottom screen overlay\n'
    content = content.replace(old, new, 1)
    print("SingleWithOverlay ditambahkan setelah CustomLayout.")
else:
    # Coba pattern lebih sederhana
    old = 'CustomLayout,'
    if old in content:
        new = 'CustomLayout,\n        SingleWithOverlay,  // Single screen with bottom screen overlay'
        content = content.replace(old, new, 1)
        print("SingleWithOverlay ditambahkan (fallback).")
    else:
        print("ERROR: CustomLayout tidak ditemukan!")
        sys.exit(1)

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 2: framebuffer_layout.h — deklarasi fungsi baru
# ============================================================
echo ""
echo "=== Step 2: Tambah deklarasi SingleWithOverlayFrameLayout ==="

python3 - "$LAYOUT_H" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'SingleWithOverlayFrameLayout' in content:
    print("Sudah ada, skip.")
    sys.exit(0)

# Tambahkan setelah deklarasi SingleFrameLayout
old = 'FramebufferLayout SingleFrameLayout(u32 width, u32 height, bool is_swapped, bool upright);'
new = '''FramebufferLayout SingleFrameLayout(u32 width, u32 height, bool is_swapped, bool upright);

/**
 * Factory method for constructing a Single Screen layout with
 * the bottom screen overlaid on top using custom layout position.
 * @param width Window framebuffer width in pixels
 * @param height Window framebuffer height in pixels
 * @param is_swapped if true, the bottom screen will be the large display
 * @param upright if true, the screens will be rotated 90 degrees anti-clockwise
 * @return Newly created FramebufferLayout object with top screen fullscreen
 *         and bottom screen as overlay using custom layout coordinates
 */
FramebufferLayout SingleWithOverlayFrameLayout(u32 width, u32 height, bool is_swapped, bool upright);'''

if old in content:
    content = content.replace(old, new, 1)
    print("Deklarasi ditambahkan.")
else:
    # Tambahkan sebelum CustomFrameLayout
    old2 = 'FramebufferLayout CustomFrameLayout'
    if old2 in content:
        content = content.replace(old2,
            'FramebufferLayout SingleWithOverlayFrameLayout(u32 width, u32 height, bool is_swapped, bool upright);\n\nFramebufferLayout CustomFrameLayout', 1)
        print("Deklarasi ditambahkan sebelum CustomFrameLayout.")
    else:
        print("WARNING: Tidak bisa menemukan anchor.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 3: framebuffer_layout.cpp — implementasi fungsi baru
# ============================================================
echo ""
echo "=== Step 3: Tambah implementasi SingleWithOverlayFrameLayout ==="

python3 - "$LAYOUT_CPP" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'SingleWithOverlayFrameLayout' in content:
    print("Sudah ada, skip.")
    sys.exit(0)

# Fungsi baru yang akan ditambahkan
new_func = '''
FramebufferLayout SingleWithOverlayFrameLayout(u32 width, u32 height, bool is_swapped,
                                               bool upright) {
    ASSERT(width > 0);
    ASSERT(height > 0);

    if (upright) {
        std::swap(width, height);
    }

    FramebufferLayout res{width, height, true, true, {}, {}, !upright};

    // Top screen (primary) takes the full window - same as SingleScreen
    Common::Rectangle<u32> screen_window_area{0, 0, width, height};
    Common::Rectangle<u32> top_screen{0, 0, Core::kScreenTopWidth, Core::kScreenTopHeight};
    Common::Rectangle<u32> bot_screen{0, 0, Core::kScreenBottomWidth, Core::kScreenBottomHeight};

    const float window_aspect_ratio = static_cast<float>(height) / static_cast<float>(width);

    // Top screen fills the entire display
    res.top_screen = MaxRectangle(screen_window_area, top_screen);

    // Bottom screen uses custom layout position as overlay
    // Read position from custom layout settings
    u32 bot_x = static_cast<u32>(Settings::values.custom_bottom_x.GetValue());
    u32 bot_y = static_cast<u32>(Settings::values.custom_bottom_y.GetValue());
    u32 bot_w = static_cast<u32>(Settings::values.custom_bottom_width.GetValue());
    u32 bot_h = static_cast<u32>(Settings::values.custom_bottom_height.GetValue());

    // Scale the overlay position to match the current window size
    // Custom layout is defined in 800x480 space (top screen resolution)
    const float scale_x = static_cast<float>(width) / static_cast<float>(Core::kScreenTopWidth);
    const float scale_y = static_cast<float>(height) / static_cast<float>(Core::kScreenTopHeight);

    u32 scaled_x = static_cast<u32>(bot_x * scale_x);
    u32 scaled_y = static_cast<u32>(bot_y * scale_y);
    u32 scaled_w = static_cast<u32>(bot_w * scale_x);
    u32 scaled_h = static_cast<u32>(bot_h * scale_y);

    // Clamp to window bounds
    if (scaled_x + scaled_w > width)  scaled_w = width - scaled_x;
    if (scaled_y + scaled_h > height) scaled_h = height - scaled_y;

    res.bottom_screen = {scaled_x, scaled_y, scaled_x + scaled_w, scaled_y + scaled_h};

    if (is_swapped) {
        return reverseLayout(res);
    }
    return res;
}

'''

# Tambahkan setelah fungsi SingleFrameLayout
# Cari akhir fungsi SingleFrameLayout
import re
# Cari pola: fungsi SingleFrameLayout yang diakhiri dengan return res; atau return reverseLayout
pattern = r'(FramebufferLayout SingleFrameLayout\(.*?\}\n)'
match = re.search(pattern, content, re.DOTALL)

if match:
    old_text = match.group(0)
    content = content.replace(old_text, old_text + new_func, 1)
    print("SingleWithOverlayFrameLayout berhasil ditambahkan.")
else:
    # Tambahkan sebelum LargeFrameLayout
    anchor = 'FramebufferLayout LargeFrameLayout('
    if anchor in content:
        content = content.replace(anchor, new_func + anchor, 1)
        print("Ditambahkan sebelum LargeFrameLayout.")
    else:
        print("ERROR: Tidak bisa menemukan anchor.")
        sys.exit(1)

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 4: framebuffer_layout.cpp — tambah case di switch
# ============================================================
echo ""
echo "=== Step 4: Tambah case SingleWithOverlay di FrameLayoutFromResolutionScale ==="

python3 - "$LAYOUT_CPP" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'SingleWithOverlay' in content and 'case Settings::LayoutOption::SingleWithOverlay' in content:
    print("Case sudah ada, skip.")
    sys.exit(0)

# Tambahkan case setelah case SingleScreen
old = '''        case Settings::LayoutOption::SingleScreen:'''

# Cari blok case SingleScreen lengkap
import re
pattern = r'(case Settings::LayoutOption::SingleScreen:\s*\{[^}]+\})'
match = re.search(pattern, content, re.DOTALL)

if match:
    old_case = match.group(0)
    new_case = old_case + '''
        case Settings::LayoutOption::SingleWithOverlay: {
            layout = SingleWithOverlayFrameLayout(res_scale * Core::kScreenTopWidth,
                                                  res_scale * Core::kScreenTopHeight,
                                                  Settings::values.swap_screen.GetValue(),
                                                  is_portrait_mode);
            break;
        }'''
    content = content.replace(old_case, new_case, 1)
    print("Case SingleWithOverlay ditambahkan.")
else:
    # Cari case SingleScreen dengan pattern lebih sederhana dan tambahkan setelahnya
    old2 = 'case Settings::LayoutOption::SingleScreen:'
    idx = content.find(old2)
    if idx != -1:
        # Cari closing brace setelah case ini
        depth = 0
        i = idx
        found = False
        while i < len(content):
            if content[i] == '{':
                depth += 1
            elif content[i] == '}':
                depth -= 1
                if depth == 0:
                    # Tambahkan setelah brace ini
                    insert_pos = i + 1
                    new_case_str = '''
        case Settings::LayoutOption::SingleWithOverlay: {
            layout = SingleWithOverlayFrameLayout(res_scale * Core::kScreenTopWidth,
                                                  res_scale * Core::kScreenTopHeight,
                                                  Settings::values.swap_screen.GetValue(),
                                                  is_portrait_mode);
            break;
        }'''
                    content = content[:insert_pos] + new_case_str + content[insert_pos:]
                    print("Case ditambahkan (brace matching).")
                    found = True
                    break
            i += 1
        if not found:
            print("WARNING: Tidak bisa parse case SingleScreen.")
    else:
        print("WARNING: case SingleScreen tidak ditemukan.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 5: ScreenLayout.kt — tambah SINGLE_WITH_OVERLAY(6)
# ============================================================
echo ""
echo "=== Step 5: Tambah SINGLE_WITH_OVERLAY di ScreenLayout.kt ==="

python3 - "$SCREEN_LAYOUT_KT" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

if 'SINGLE_WITH_OVERLAY' in content:
    print("Sudah ada, skip.")
    sys.exit(0)

# Tambahkan setelah CUSTOM_LAYOUT(5)
old = 'CUSTOM_LAYOUT(5);'
new = 'CUSTOM_LAYOUT(5),\n    SINGLE_WITH_OVERLAY(6);'

if old in content:
    content = content.replace(old, new, 1)
    print("SINGLE_WITH_OVERLAY(6) ditambahkan.")
else:
    # Coba tanpa semicolon
    import re
    pattern = r'(CUSTOM_LAYOUT\s*\(\s*5\s*\))'
    match = re.search(pattern, content)
    if match:
        old_text = match.group(0)
        # Cek apakah diakhiri ; atau ,
        pos = match.end()
        if content[pos:pos+1] == ';':
            content = content[:pos-len(old_text)] + old_text.replace(')', '),') + \
                '\n    SINGLE_WITH_OVERLAY(6)' + content[pos:]
        else:
            content = content.replace(old_text, old_text + ',\n    SINGLE_WITH_OVERLAY(6)', 1)
        print("SINGLE_WITH_OVERLAY ditambahkan (regex).")
    else:
        print("ERROR: CUSTOM_LAYOUT(5) tidak ditemukan!")
        sys.exit(1)

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 6: ScreenAdjustmentUtil.kt — update toggleSecondaryScreen
# ============================================================
echo ""
echo "=== Step 6: Update toggleSecondaryScreen() pakai SINGLE_WITH_OVERLAY ==="

python3 - "$ADJUSTMENT_KT" << 'PYEOF'
import sys
import re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Replace LARGE_SCREEN atau CUSTOM_LAYOUT dengan SINGLE_WITH_OVERLAY
replacements = [
    ('ScreenLayout.LARGE_SCREEN.int', 'ScreenLayout.SINGLE_WITH_OVERLAY.int'),
    ('ScreenLayout.CUSTOM_LAYOUT.int', 'ScreenLayout.SINGLE_WITH_OVERLAY.int'),
]

changed = False
for old, new in replacements:
    if old in content:
        # Hanya replace yang ada di dalam toggleSecondaryScreen
        # Cari fungsi toggleSecondaryScreen
        func_start = content.find('fun toggleSecondaryScreen()')
        if func_start != -1:
            # Cari akhir fungsi
            depth = 0
            i = func_start
            func_end = func_start
            found_open = False
            while i < len(content):
                if content[i] == '{':
                    depth += 1
                    found_open = True
                elif content[i] == '}':
                    depth -= 1
                    if found_open and depth == 0:
                        func_end = i + 1
                        break
                i += 1
            
            func_body = content[func_start:func_end]
            if old in func_body:
                new_body = func_body.replace(old, new)
                content = content[:func_start] + new_body + content[func_end:]
                print(f"Replaced {old} -> {new}")
                changed = True

if not changed:
    print("INFO: Tidak ada perubahan diperlukan atau pattern tidak ditemukan.")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Step 7: Update isTouchScreenVisible() di InputOverlay.kt
# SINGLE_WITH_OVERLAY harus return true untuk touch layar kedua
# ============================================================
echo ""
echo "=== Step 7: Update isTouchScreenVisible() untuk SINGLE_WITH_OVERLAY ==="

OVERLAY_KT="src/android/app/src/main/java/org/citra/citra_emu/overlay/InputOverlay.kt"

python3 - "$OVERLAY_KT" << 'PYEOF'
import sys
import re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

old_func = '''    private fun isTouchScreenVisible(): Boolean {
        val layout = IntSetting.SCREEN_LAYOUT.int
        val isSingleScreen = layout == ScreenLayout.SINGLE_SCREEN.int
        // Saat single screen: cek apakah user mengaktifkan show secondary screen
        // Ketika showSecondaryScreen = ON, layout sudah diubah ke CUSTOM_LAYOUT
        // oleh toggleSecondaryScreen(), jadi isSingleScreen = false otomatis.
        // Guard ini sebagai fallback keamanan tambahan.
        if (isSingleScreen) {
            return EmulationMenuSettings.showSecondaryScreen
        }
        return true
    }'''

new_func = '''    private fun isTouchScreenVisible(): Boolean {
        val layout = IntSetting.SCREEN_LAYOUT.int
        // SINGLE_SCREEN: blokir touch layar kedua
        // SINGLE_WITH_OVERLAY: izinkan touch layar kedua (overlay aktif)
        // Mode lain: selalu izinkan
        return when (layout) {
            ScreenLayout.SINGLE_SCREEN.int -> false
            else -> true
        }
    }'''

if old_func in content:
    content = content.replace(old_func, new_func, 1)
    print("isTouchScreenVisible() diupdate.")
else:
    # Cari dengan regex
    pattern = r'private fun isTouchScreenVisible\(\): Boolean \{.*?\}'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        content = content[:match.start()] + new_func + content[match.end():]
        print("isTouchScreenVisible() diupdate (regex).")
    else:
        print("WARNING: Tidak bisa menemukan isTouchScreenVisible().")

with open(path, 'w') as f:
    f.write(content)
PYEOF

# ============================================================
# Verifikasi
# ============================================================
echo ""
echo "=== VERIFIKASI ==="

echo "--- settings.h ---"
grep -n "SingleWithOverlay\|CustomLayout" "$SETTINGS_H" | head -5

echo ""
echo "--- framebuffer_layout.h ---"
grep -n "SingleWithOverlay" "$LAYOUT_H"

echo ""
echo "--- framebuffer_layout.cpp ---"
grep -n "SingleWithOverlay" "$LAYOUT_CPP"

echo ""
echo "--- ScreenLayout.kt ---"
grep -n "SINGLE_WITH_OVERLAY\|CUSTOM_LAYOUT" "$SCREEN_LAYOUT_KT"

echo ""
echo "--- ScreenAdjustmentUtil.kt ---"
grep -n "SINGLE_WITH_OVERLAY\|toggleSecondaryScreen" "$ADJUSTMENT_KT" | head -10

echo ""
echo "--- InputOverlay.kt ---"
grep -n "isTouchScreenVisible\|SINGLE_WITH_OVERLAY\|SINGLE_SCREEN" "$OVERLAY_KT" | head -10

echo ""
echo "=== SELESAI ==="
echo ""
echo "Hapus backup lama:"
echo "find . -name '*.bak5' | grep -v build | xargs rm -f"
echo ""
echo "git add -A && git commit -m 'feat: add SingleWithOverlay C++ layout for secondary screen overlay' && git push"
