#!/usr/bin/env python3
# patch_icon_grid.py
# Ubah Game List menjadi icon-only grid (tanpa teks nama/company)
# - Grid horizontal, jumlah kolom otomatis menyesuaikan jumlah game
# - Icon cartridge muncul di pojok kanan bawah icon jika game di-insert
# Usage: python3 patch_icon_grid.py [repo_root]

import sys
from pathlib import Path

RED    = "\033[91m"
GREEN  = "\033[92m"
YELLOW = "\033[93m"
CYAN   = "\033[96m"
RESET  = "\033[0m"

def ok(msg):   print(f"{GREEN}  ✓ {msg}{RESET}")
def err(msg):  print(f"{RED}  ✗ {msg}{RESET}")
def warn(msg): print(f"{YELLOW}  ⚠ {msg}{RESET}")
def info(msg): print(f"{CYAN}  → {msg}{RESET}")

def patch_file(filepath: Path, old: str, new: str, label: str) -> bool:
    if not filepath.exists():
        err(f"File tidak ditemukan: {filepath}")
        return False
    content = filepath.read_text(encoding="utf-8")
    if old not in content:
        warn(f"[{label}] Pola tidak ditemukan — mungkin sudah di-patch?")
        return False
    if content.count(old) > 1:
        warn(f"[{label}] Pola ditemukan lebih dari 1x — hanya patch pertama")
    filepath.write_text(content.replace(old, new, 1), encoding="utf-8")
    ok(f"[{label}] Berhasil di-patch")
    return True

def replace_file(filepath: Path, new_content: str, label: str) -> bool:
    if not filepath.exists():
        err(f"File tidak ditemukan: {filepath}")
        return False
    filepath.write_text(new_content, encoding="utf-8")
    ok(f"[{label}] File berhasil diganti")
    return True

def find_file(root: Path, *candidates: str) -> Path | None:
    for c in candidates:
        p = root / c
        if p.exists():
            return p
    return None


# ═══════════════════════════════════════════════════════════════════════════════
# PATCH 1 — card_game.xml
# Ganti layout card dari horizontal (icon + teks) menjadi FrameLayout icon-only
# dengan ImageView cartridge overlay di pojok kanan bawah
# ═══════════════════════════════════════════════════════════════════════════════
CARD_GAME_XML = """\
<?xml version="1.0" encoding="utf-8"?>
<!--
    card_game.xml — Icon-only grid card
    Icon penuh + cartridge badge di pojok kanan bawah
-->
<com.google.android.material.card.MaterialCardView
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:id="@+id/card_game"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:layout_margin="4dp"
    app:cardCornerRadius="12dp"
    app:cardElevation="2dp">

    <!-- cardContents dipertahankan agar binding.cardContents tetap valid -->
    <FrameLayout
        android:id="@+id/card_contents"
        android:layout_width="match_parent"
        android:layout_height="match_parent">

        <!-- Icon game — rasio 1:1 via paddingTop trick -->
        <ImageView
            android:id="@+id/image_game_screen"
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            android:minHeight="80dp"
            android:adjustViewBounds="true"
            android:scaleType="centerCrop"
            android:contentDescription="@string/grid_menu_icon_overlay" />

        <!-- Cartridge badge — pojok kanan bawah -->
        <ImageView
            android:id="@+id/image_cartridge"
            android:layout_width="24dp"
            android:layout_height="24dp"
            android:layout_gravity="bottom|end"
            android:layout_margin="4dp"
            android:src="@drawable/ic_cartridge"
            android:visibility="gone"
            android:contentDescription="@null"
            android:background="@drawable/cartridge_badge_bg"
            android:padding="2dp" />

        <!-- View dummy agar binding lama tidak crash (visibility GONE) -->
        <TextView
            android:id="@+id/text_game_title"
            android:layout_width="0dp"
            android:layout_height="0dp"
            android:visibility="gone" />

        <TextView
            android:id="@+id/text_company"
            android:layout_width="0dp"
            android:layout_height="0dp"
            android:visibility="gone" />

        <TextView
            android:id="@+id/text_game_region"
            android:layout_width="0dp"
            android:layout_height="0dp"
            android:visibility="gone" />

    </FrameLayout>

</com.google.android.material.card.MaterialCardView>
"""

# ═══════════════════════════════════════════════════════════════════════════════
# PATCH 2 — cartridge_badge_bg.xml (drawable baru)
# Background bulat semi-transparan untuk badge cartridge
# ═══════════════════════════════════════════════════════════════════════════════
CARTRIDGE_BADGE_BG_XML = """\
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="oval">
    <solid android:color="#CC000000" />
</shape>
"""

# ═══════════════════════════════════════════════════════════════════════════════
# PATCH 3 — GamesFragment.kt
# Ganti GridLayoutManager dengan spanCount dinamis berdasarkan jumlah game
# ═══════════════════════════════════════════════════════════════════════════════
GAMES_FRAGMENT_OLD = """\
        binding.gridGames.apply {
            layoutManager = GridLayoutManager(
                requireContext(),
                resources.getInteger(R.integer.game_grid_columns)
            )
            adapter = this@GamesFragment.gameAdapter
        }"""

GAMES_FRAGMENT_NEW = """\
        binding.gridGames.apply {
            layoutManager = GridLayoutManager(
                requireContext(),
                computeGridColumns(gamesViewModel.games.value.size)
            )
            adapter = this@GamesFragment.gameAdapter
        }

        // Update spanCount setiap kali daftar game berubah
        viewLifecycleOwner.lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.RESUMED) {
                gamesViewModel.games.collectLatest { games ->
                    val columns = computeGridColumns(games.size)
                    (binding.gridGames.layoutManager as? GridLayoutManager)
                        ?.spanCount = columns
                }
            }
        }"""

# ═══════════════════════════════════════════════════════════════════════════════
# PATCH 4 — GamesFragment.kt
# Tambah fungsi computeGridColumns sebelum penutup class
# ═══════════════════════════════════════════════════════════════════════════════
GAMES_FRAGMENT_COMPUTE_OLD = """\
    private fun setInsets() ="""

GAMES_FRAGMENT_COMPUTE_NEW = """\
    /**
     * Hitung jumlah kolom grid secara dinamis berdasarkan jumlah game.
     * Lebar layar dibagi lebar minimum per item (96dp).
     * Hasilnya di-clamp antara MIN dan MAX, lalu tidak melebihi jumlah game itu sendiri.
     */
    private fun computeGridColumns(gameCount: Int): Int {
        val displayMetrics = resources.displayMetrics
        val screenWidthDp = displayMetrics.widthPixels / displayMetrics.density
        val itemMinDp = 96f
        val autoColumns = (screenWidthDp / itemMinDp).toInt().coerceAtLeast(3)
        // Jangan lebih banyak kolom dari jumlah game (tapi minimal 1)
        return if (gameCount > 0) autoColumns.coerceAtMost(gameCount) else autoColumns
    }

    private fun setInsets() ="""

# ═══════════════════════════════════════════════════════════════════════════════
# PATCH 5 — GameAdapter.kt
# Di fungsi bind(): hapus logika marquee teks (sudah tidak perlu),
# pastikan imageCartridge ditampilkan sebagai badge (sudah ada di bind lama)
# Tidak perlu ganti — bind() sudah handle imageCartridge.visibility dengan benar.
# Yang perlu diubah hanya hapus blok postDelayed marquee agar tidak error
# karena textGameTitle sudah invisible/0dp.
# ═══════════════════════════════════════════════════════════════════════════════
GAME_ADAPTER_MARQUEE_OLD = """\
            binding.textGameTitle.postDelayed(
                {
                    binding.textGameTitle.ellipsize = TextUtils.TruncateAt.MARQUEE
                    binding.textGameTitle.isSelected = true

                    binding.textCompany.ellipsize = TextUtils.TruncateAt.MARQUEE
                    binding.textCompany.isSelected = true

                    binding.textGameRegion.ellipsize = TextUtils.TruncateAt.MARQUEE
                    binding.textGameRegion.isSelected = true
                },
                3000
            )"""

GAME_ADAPTER_MARQUEE_NEW = """\
            // Marquee dihapus — layout icon-only tidak menampilkan teks"""

# ═══════════════════════════════════════════════════════════════════════════════
# PATCH 6 — GameAdapter.kt
# Hapus import TextUtils yang sudah tidak dipakai (opsional, hanya clean-up)
# ═══════════════════════════════════════════════════════════════════════════════
GAME_ADAPTER_IMPORT_OLD = """\
import android.text.TextUtils
"""
GAME_ADAPTER_IMPORT_NEW = """\
"""


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════
def main():
    repo_root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
    print(f"\n{CYAN}{'='*62}{RESET}")
    print(f"{CYAN}  Icon-Only Grid Patch — AzaharTrigger-test{RESET}")
    print(f"{CYAN}  Repo root: {repo_root}{RESET}")
    print(f"{CYAN}{'='*62}{RESET}\n")

    # Lokasi file
    base_kt   = "src/android/app/src/main/java/org/citra/citra_emu"
    base_kt2  = "app/src/main/java/org/citra/citra_emu"
    base_res  = "src/android/app/src/main/res"
    base_res2 = "app/src/main/res"

    card_xml = find_file(repo_root,
        f"{base_res}/layout/card_game.xml",
        f"{base_res2}/layout/card_game.xml")

    drawable_dir = find_file(repo_root,
        f"{base_res}/drawable",
        f"{base_res2}/drawable")

    games_fragment = find_file(repo_root,
        f"{base_kt}/fragments/GamesFragment.kt",
        f"{base_kt2}/fragments/GamesFragment.kt")

    game_adapter = find_file(repo_root,
        f"{base_kt}/adapters/GameAdapter.kt",
        f"{base_kt2}/adapters/GameAdapter.kt")

    results = []

    # 1. card_game.xml
    print(f"{YELLOW}[1/6] card_game.xml — icon-only layout{RESET}")
    if card_xml:
        results.append(replace_file(card_xml, CARD_GAME_XML, "card_game.xml"))
    else:
        err("card_game.xml tidak ditemukan")
        results.append(False)

    # 2. cartridge_badge_bg.xml (drawable baru)
    print(f"\n{YELLOW}[2/6] drawable/cartridge_badge_bg.xml — badge background{RESET}")
    if drawable_dir and drawable_dir.is_dir():
        badge_file = drawable_dir / "cartridge_badge_bg.xml"
        badge_file.write_text(CARTRIDGE_BADGE_BG_XML, encoding="utf-8")
        ok("cartridge_badge_bg.xml dibuat")
        results.append(True)
    else:
        err("Folder drawable tidak ditemukan")
        results.append(False)

    # 3. GamesFragment.kt — GridLayoutManager dinamis
    print(f"\n{YELLOW}[3/6] GamesFragment.kt — spanCount dinamis{RESET}")
    if games_fragment:
        results.append(patch_file(games_fragment, GAMES_FRAGMENT_OLD, GAMES_FRAGMENT_NEW,
                                  "GamesFragment gridGames"))
    else:
        err("GamesFragment.kt tidak ditemukan")
        results.append(False)

    # 4. GamesFragment.kt — fungsi computeGridColumns
    print(f"\n{YELLOW}[4/6] GamesFragment.kt — fungsi computeGridColumns(){RESET}")
    if games_fragment:
        results.append(patch_file(games_fragment, GAMES_FRAGMENT_COMPUTE_OLD,
                                  GAMES_FRAGMENT_COMPUTE_NEW, "GamesFragment computeGridColumns"))
    else:
        results.append(False)

    # 5. GameAdapter.kt — hapus marquee postDelayed
    print(f"\n{YELLOW}[5/6] GameAdapter.kt — hapus marquee postDelayed{RESET}")
    if game_adapter:
        results.append(patch_file(game_adapter, GAME_ADAPTER_MARQUEE_OLD,
                                  GAME_ADAPTER_MARQUEE_NEW, "GameAdapter marquee"))
    else:
        err("GameAdapter.kt tidak ditemukan")
        results.append(False)

    # 6. GameAdapter.kt — hapus import TextUtils
    print(f"\n{YELLOW}[6/6] GameAdapter.kt — hapus import TextUtils (clean-up){RESET}")
    if game_adapter:
        results.append(patch_file(game_adapter, GAME_ADAPTER_IMPORT_OLD,
                                  GAME_ADAPTER_IMPORT_NEW, "GameAdapter import TextUtils"))
    else:
        results.append(False)

    # Summary
    success = sum(1 for r in results if r)
    total   = len(results)
    print(f"\n{CYAN}{'='*62}{RESET}")
    if success == total:
        print(f"{GREEN}  Semua {total} patch berhasil!{RESET}")
    else:
        print(f"{YELLOW}  {success}/{total} patch berhasil — cek pesan di atas{RESET}")
    print(f"\n{CYAN}  CATATAN:{RESET}")
    print(f"{CYAN}  • Pastikan @drawable/ic_cartridge sudah ada di res/drawable{RESET}")
    print(f"{CYAN}    (icon cartridge yang sudah ada di project, lihat gambar lingkaran merah){RESET}")
    print(f"{CYAN}  • String @string/grid_menu_icon_overlay harus ada di strings.xml{RESET}")
    print(f"{CYAN}    Jika belum ada, tambahkan: <string name=\"grid_menu_icon_overlay\">Game icon</string>{RESET}")
    print(f"{CYAN}{'='*62}{RESET}\n")

if __name__ == "__main__":
    main()
