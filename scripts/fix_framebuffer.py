path = "src/core/frontend/framebuffer_layout.cpp"
with open(path, 'r') as f:
    content = f.read()

# Fix: Pisahkan case SingleScreen dan SingleWithOverlay
# yang sekarang kacau (SingleWithOverlay tersisip di dalam SingleScreen)

bad = '''        case Settings::LayoutOption::SingleScreen: {
            const bool swap_screens = is_secondary || Settings::values.swap_screen.GetValue();
            if (swap_screens) {
                width = Core::kScreenBottomWidth * res_scale;
                height = Core::kScreenBottomHeight * res_scale;
            }
        case Settings::LayoutOption::SingleWithOverlay: {
            layout = SingleWithOverlayFrameLayout(res_scale * Core::kScreenTopWidth,
                                                  res_scale * Core::kScreenTopHeight,
                                                  Settings::values.swap_screen.GetValue(),
                                                  is_portrait);
            break;
        } else {
                width = Core::kScreenTopWidth * res_scale;
                height = Core::kScreenTopHeight * res_scale;
            }
            if (Settings::values.upright_screen.GetValue()) {
                std::swap(width, height);
            }

            layout = SingleFrameLayout(width, height, swap_screens,
                                       Settings::values.upright_screen.GetValue());
            break;
        }'''

good = '''        case Settings::LayoutOption::SingleScreen: {
            const bool swap_screens = is_secondary || Settings::values.swap_screen.GetValue();
            if (swap_screens) {
                width = Core::kScreenBottomWidth * res_scale;
                height = Core::kScreenBottomHeight * res_scale;
            } else {
                width = Core::kScreenTopWidth * res_scale;
                height = Core::kScreenTopHeight * res_scale;
            }
            if (Settings::values.upright_screen.GetValue()) {
                std::swap(width, height);
            }
            layout = SingleFrameLayout(width, height, swap_screens,
                                       Settings::values.upright_screen.GetValue());
            break;
        }
        case Settings::LayoutOption::SingleWithOverlay: {
            width = Core::kScreenTopWidth * res_scale;
            height = Core::kScreenTopHeight * res_scale;
            if (Settings::values.upright_screen.GetValue()) {
                std::swap(width, height);
            }
            layout = SingleWithOverlayFrameLayout(width, height,
                                                  Settings::values.swap_screen.GetValue(),
                                                  Settings::values.upright_screen.GetValue());
            break;
        }'''

if bad in content:
    content = content.replace(bad, good, 1)
    print("Fix berhasil diterapkan.")
else:
    print("ERROR: Pattern tidak ditemukan persis.")
    # Coba cari bagian yang ada
    idx = content.find("case Settings::LayoutOption::SingleScreen:")
    print(f"SingleScreen ditemukan di indeks: {idx}")
    print(content[idx:idx+500])

with open(path, 'w') as f:
    f.write(content)
