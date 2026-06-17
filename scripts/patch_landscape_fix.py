#!/usr/bin/env python3
# patch_landscape_fix.py
# Fix BottomSheet terpotong di landscape mode untuk AzaharTrigger-test
# Usage: python3 patch_landscape_fix.py [repo_root]
# Default repo_root = current directory

import sys
from pathlib import Path

# ─── Warna terminal ───────────────────────────────────────────────────────────
RED    = "\033[91m"
GREEN  = "\033[92m"
YELLOW = "\033[93m"
CYAN   = "\033[96m"
RESET  = "\033[0m"

def ok(msg):   print(f"{GREEN}  ✓ {msg}{RESET}")
def err(msg):  print(f"{RED}  ✗ {msg}{RESET}")
def info(msg): print(f"{CYAN}  → {msg}{RESET}")
def warn(msg): print(f"{YELLOW}  ⚠ {msg}{RESET}")

# ─── Helper: text replace dengan validasi ─────────────────────────────────────
def patch_file(filepath: Path, old: str, new: str, label: str) -> bool:
    if not filepath.exists():
        err(f"File tidak ditemukan: {filepath}")
        return False

    content = filepath.read_text(encoding="utf-8")

    if old not in content:
        warn(f"[{label}] Pola tidak ditemukan — mungkin sudah di-patch sebelumnya?")
        return False

    count = content.count(old)
    if count > 1:
        warn(f"[{label}] Pola ditemukan {count}x — hanya patch pertama yang diubah (periksa manual)")

    filepath.write_text(content.replace(old, new, 1), encoding="utf-8")
    ok(f"[{label}] Berhasil di-patch")
    return True


# ─── Helper: replace XML file sepenuhnya ──────────────────────────────────────
def replace_xml(filepath: Path, new_content: str, label: str) -> bool:
    if not filepath.exists():
        err(f"File tidak ditemukan: {filepath}")
        return False

    filepath.write_text(new_content, encoding="utf-8")
    ok(f"[{label}] XML berhasil diganti")
    return True


# ═══════════════════════════════════════════════════════════════════════════════
# PATCH DEFINITIONS
# ═══════════════════════════════════════════════════════════════════════════════

# ── 1. GameAdapter.kt ─────────────────────────────────────────────────────────
GAME_ADAPTER_OLD = """\
        val bottomSheetBehavior = bottomSheetDialog.getBehavior()
        bottomSheetBehavior.skipCollapsed = true
        bottomSheetBehavior.state = BottomSheetBehavior.STATE_EXPANDED"""

GAME_ADAPTER_NEW = """\
        val bottomSheetBehavior = bottomSheetDialog.getBehavior()
        bottomSheetBehavior.skipCollapsed = true
        bottomSheetBehavior.state = BottomSheetBehavior.STATE_EXPANDED
        // Fix: landscape mode agar BottomSheet tidak terpotong
        if (context.resources.configuration.orientation ==
                android.content.res.Configuration.ORIENTATION_LANDSCAPE) {
            bottomSheetBehavior.peekHeight = context.resources.displayMetrics.heightPixels
        }"""

# ── 2. NetPlayDialog.kt — onCreate ────────────────────────────────────────────
NETPLAY_ONCREATE_OLD = """\
        behavior.state = BottomSheetBehavior.STATE_EXPANDED
        behavior.state = BottomSheetBehavior.STATE_EXPANDED
        behavior.skipCollapsed = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE"""

NETPLAY_ONCREATE_NEW = """\
        behavior.state = BottomSheetBehavior.STATE_EXPANDED
        behavior.skipCollapsed = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        // Fix: landscape mode agar BottomSheet tidak terpotong
        if (context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE) {
            behavior.peekHeight = context.resources.displayMetrics.heightPixels
        }"""

# ── 3. NetPlayDialog.kt — showMelonInputDialogForDiscovery ────────────────────
NETPLAY_MELON_OLD = """\
        dialog.behavior.state = BottomSheetBehavior.STATE_EXPANDED
        dialog.behavior.state = BottomSheetBehavior.STATE_EXPANDED
        dialog.behavior.skipCollapsed = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE"""

NETPLAY_MELON_NEW = """\
        dialog.behavior.state = BottomSheetBehavior.STATE_EXPANDED
        dialog.behavior.skipCollapsed = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        // Fix: landscape mode agar BottomSheet tidak terpotong
        if (context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE) {
            dialog.behavior.peekHeight = context.resources.displayMetrics.heightPixels
        }"""

# ── 4. dialog_about_game.xml ──────────────────────────────────────────────────
DIALOG_ABOUT_GAME_XML = """\
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical">

    <com.google.android.material.bottomsheet.BottomSheetDragHandleView
        android:id="@+id/drag_handle"
        android:layout_width="match_parent"
        android:layout_height="wrap_content" />

    <androidx.core.widget.NestedScrollView
        android:layout_width="match_parent"
        android:layout_height="wrap_content">

        <androidx.constraintlayout.widget.ConstraintLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:nextFocusRight="@id/about_game_play"
            android:paddingHorizontal="16dp"
            android:paddingBottom="8dp">

            <com.google.android.material.imageview.ShapeableImageView
                android:id="@+id/game_icon"
                android:layout_width="100dp"
                android:layout_height="100dp"
                android:focusable="false"
                app:layout_constraintBottom_toBottomOf="@+id/constraintLayout"
                app:layout_constraintStart_toStartOf="parent"
                app:layout_constraintTop_toTopOf="@+id/constraintLayout"
                app:shapeAppearance="?attr/shapeAppearanceCornerLarge" />

            <androidx.constraintlayout.widget.ConstraintLayout
                android:id="@+id/constraintLayout"
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:layout_marginStart="16dp"
                app:layout_constraintEnd_toEndOf="parent"
                app:layout_constraintHeight_min="100dp"
                app:layout_constraintStart_toEndOf="@id/game_icon"
                app:layout_constraintTop_toTopOf="parent">

                <TextView
                    android:id="@+id/about_game_title"
                    style="?attr/textAppearanceTitleMedium"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:textAlignment="viewStart"
                    android:textSize="15sp"
                    android:textStyle="bold"
                    app:layout_constraintStart_toStartOf="parent"
                    app:layout_constraintTop_toTopOf="parent"
                    tools:text="Application Title" />

                <TextView
                    android:id="@+id/about_game_company"
                    style="?attr/textAppearanceBodyMedium"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    app:layout_constraintStart_toStartOf="@id/about_game_filename"
                    app:layout_constraintTop_toBottomOf="@+id/about_game_title"
                    tools:text="Company" />

                <TextView
                    android:id="@+id/about_game_region"
                    style="?attr/textAppearanceBodyMedium"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    app:layout_constraintStart_toStartOf="@id/about_game_title"
                    app:layout_constraintTop_toBottomOf="@+id/about_game_company"
                    tools:text="Application Region" />

                <TextView
                    android:id="@+id/about_game_id"
                    style="?attr/textAppearanceBodyMedium"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    app:layout_constraintStart_toStartOf="@id/about_game_filename"
                    app:layout_constraintTop_toBottomOf="@+id/about_game_region"
                    tools:text="Game ID" />

                <TextView
                    android:id="@+id/about_game_filename"
                    style="?attr/textAppearanceBodyMedium"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    app:layout_constraintStart_toStartOf="@id/about_game_title"
                    app:layout_constraintTop_toBottomOf="@+id/about_game_id"
                    tools:text="Application Filename" />

                <TextView
                    android:id="@+id/about_game_filetype"
                    style="?attr/textAppearanceBodyMedium"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    app:layout_constraintStart_toStartOf="@id/about_game_title"
                    app:layout_constraintTop_toBottomOf="@+id/about_game_filename"
                    tools:text="Game Filetype" />

                <TextView
                    android:id="@+id/about_game_playtime"
                    style="?attr/textAppearanceBodyMedium"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    app:layout_constraintStart_toStartOf="@id/about_game_title"
                    app:layout_constraintTop_toBottomOf="@+id/about_game_filetype"
                    tools:text="Game Playtime" />

            </androidx.constraintlayout.widget.ConstraintLayout>

            <LinearLayout
                android:id="@+id/horizontal_layout"
                style="@style/ThemeOverlay.Material3.Button.IconButton.Filled.Tonal"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="16dp"
                android:gravity="start|center"
                android:orientation="horizontal"
                app:layout_constraintEnd_toEndOf="parent"
                app:layout_constraintStart_toStartOf="parent"
                app:layout_constraintTop_toBottomOf="@id/game_icon">

                <com.google.android.material.button.MaterialButton
                    android:id="@+id/about_game_play"
                    style="@style/Widget.Material3.Button.Icon"
                    android:layout_width="142dp"
                    android:layout_height="wrap_content"
                    android:layout_weight="3"
                    android:contentDescription="@string/play"
                    android:focusedByDefault="true"
                    android:text="@string/play"
                    android:textAlignment="center"
                    app:icon="@drawable/ic_play" />

                <com.google.android.material.button.MaterialButton
                    android:id="@+id/menu_button_open"
                    style="@style/Widget.Material3.Button.IconButton.Filled.Tonal"
                    android:layout_width="48dp"
                    android:layout_height="wrap_content"
                    android:layout_marginStart="8dp"
                    app:icon="@drawable/ic_open"
                    app:iconGravity="textStart" />

                <com.google.android.material.button.MaterialButton
                    android:id="@+id/menu_button_uninstall"
                    style="@style/Widget.Material3.Button.IconButton.Filled.Tonal"
                    android:layout_width="48dp"
                    android:layout_height="wrap_content"
                    android:layout_marginStart="8dp"
                    app:icon="@drawable/ic_uninstall"
                    app:iconGravity="textStart" />

                <com.google.android.material.button.MaterialButton
                    android:id="@+id/game_shortcut"
                    style="@style/Widget.Material3.Button.IconButton.Filled.Tonal"
                    android:layout_width="48dp"
                    android:layout_height="wrap_content"
                    android:layout_marginStart="8dp"
                    android:contentDescription="@string/shortcut"
                    app:icon="@drawable/ic_shortcut"
                    app:iconGravity="textStart" />

            </LinearLayout>

            <LinearLayout
                android:id="@+id/horizontal_layout_2"
                style="@style/ThemeOverlay.Material3.Button.IconButton.Filled.Tonal"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="16dp"
                android:gravity="start|center"
                android:orientation="horizontal"
                app:layout_constraintEnd_toEndOf="parent"
                app:layout_constraintStart_toStartOf="parent"
                app:layout_constraintTop_toBottomOf="@+id/horizontal_layout">

                <com.google.android.material.button.MaterialButton
                    android:id="@+id/cheats"
                    style="@style/Widget.Material3.Button.TonalButton.Icon"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:contentDescription="@string/cheats"
                    android:text="@string/cheats" />

                <com.google.android.material.button.MaterialButton
                    android:id="@+id/insert_cartridge_button"
                    style="@style/Widget.Material3.Button.TonalButton.Icon"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:layout_marginStart="8dp" />

                <com.google.android.material.button.MaterialButton
                    android:id="@+id/compress_decompress"
                    style="@style/Widget.Material3.Button.TonalButton.Icon"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:layout_marginStart="8dp"
                    android:contentDescription="@string/compress"
                    android:text="@string/compress" />

            </LinearLayout>

            <LinearLayout
                android:id="@+id/horizontal_layout_3"
                style="@style/ThemeOverlay.Material3.Button.IconButton.Filled.Tonal"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="16dp"
                android:gravity="start|center"
                android:orientation="horizontal"
                app:layout_constraintEnd_toEndOf="parent"
                app:layout_constraintStart_toStartOf="parent"
                app:layout_constraintTop_toBottomOf="@+id/horizontal_layout_2">

                <com.google.android.material.button.MaterialButton
                    android:id="@+id/delete_cache"
                    style="@style/Widget.Material3.Button.TonalButton.Icon"
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:contentDescription="@string/delete_shader_cache"
                    android:text="@string/delete_shader_cache" />
            </LinearLayout>

        </androidx.constraintlayout.widget.ConstraintLayout>

    </androidx.core.widget.NestedScrollView>

</LinearLayout>
"""

# ── 5. dialog_multiplayer_connect.xml ─────────────────────────────────────────
DIALOG_MULTIPLAYER_XML = """\
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:orientation="vertical"
    android:layout_width="match_parent"
    android:layout_height="wrap_content">

    <com.google.android.material.bottomsheet.BottomSheetDragHandleView
        android:id="@+id/drag_handle"
        android:layout_width="match_parent"
        android:layout_height="wrap_content" />

    <androidx.core.widget.NestedScrollView
        android:layout_width="match_parent"
        android:layout_height="wrap_content">

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:padding="16dp">

            <TextView
                android:id="@+id/text_title"
                android:text="@string/multiplayer"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:textAppearance="?attr/textAppearanceHeadline6"
                android:gravity="center"
                android:layout_marginTop="4dp"
                android:textColor="?attr/colorOnSurface" />

            <com.google.android.material.tabs.TabLayout
                android:id="@+id/tab_layout"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="16dp"
                android:layout_marginBottom="16dp"
                app:tabMode="fixed"
                app:tabGravity="fill">

                <com.google.android.material.tabs.TabItem
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:text="@string/multiplayer_citra_tab" />

                <com.google.android.material.tabs.TabItem
                    android:layout_width="wrap_content"
                    android:layout_height="wrap_content"
                    android:text="@string/multiplayer_melon_tab" />

            </com.google.android.material.tabs.TabLayout>

            <FrameLayout
                android:id="@+id/content_frame"
                android:layout_width="match_parent"
                android:layout_height="wrap_content">

                <!-- Citra Multiplayer Content -->
                <LinearLayout
                    android:id="@+id/citra_content"
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    android:orientation="vertical"
                    android:visibility="visible">

                    <ImageView
                        android:layout_width="80dp"
                        android:layout_height="80dp"
                        android:layout_gravity="center"
                        android:layout_marginTop="8dp"
                        android:layout_marginBottom="16dp"
                        android:src="@drawable/ic_network"
                        app:tint="?attr/colorPrimary" />

                    <LinearLayout
                        android:layout_width="match_parent"
                        android:layout_height="wrap_content"
                        android:orientation="horizontal"
                        android:layout_marginBottom="8dp"
                        android:layout_marginHorizontal="16dp">

                        <Space
                            android:layout_width="40dp"
                            android:layout_height="match_parent" />

                        <com.google.android.material.button.MaterialButton
                            android:id="@+id/btn_lobby_browser"
                            style="@style/Widget.Material3.Button"
                            android:layout_width="0dp"
                            android:layout_height="wrap_content"
                            android:layout_weight="1"
                            android:text="@string/multiplayer_public_room"
                            app:cornerRadius="16dp"
                            app:icon="@drawable/ic_search" />

                        <Space
                            android:layout_width="40dp"
                            android:layout_height="match_parent" />

                    </LinearLayout>

                    <LinearLayout
                        android:layout_width="match_parent"
                        android:layout_height="wrap_content"
                        android:orientation="horizontal"
                        android:layout_marginHorizontal="16dp"
                        android:layout_marginBottom="8dp">

                        <com.google.android.material.button.MaterialButton
                            android:id="@+id/btn_join"
                            style="@style/Widget.Material3.Button.ElevatedButton"
                            android:layout_width="0dp"
                            android:layout_height="wrap_content"
                            android:layout_weight="1"
                            android:text="@string/multiplayer_join_room"
                            app:icon="@drawable/ic_install"
                            app:cornerRadius="16dp" />

                        <Space
                            android:layout_width="16dp"
                            android:layout_height="match_parent" />

                        <com.google.android.material.button.MaterialButton
                            android:id="@+id/btn_create"
                            style="@style/Widget.Material3.Button.TonalButton"
                            android:layout_width="0dp"
                            android:layout_height="wrap_content"
                            android:layout_weight="1"
                            android:text="@string/multiplayer_create_room"
                            app:icon="@drawable/ic_add"
                            app:cornerRadius="16dp" />
                    </LinearLayout>

                </LinearLayout>

                <!-- melonDS LAN Content -->
                <LinearLayout
                    android:id="@+id/melon_content"
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    android:orientation="vertical"
                    android:visibility="gone">

                    <ImageView
                        android:layout_width="80dp"
                        android:layout_height="80dp"
                        android:layout_gravity="center"
                        android:layout_marginTop="8dp"
                        android:layout_marginBottom="16dp"
                        android:src="@drawable/ic_network"
                        app:tint="?attr/colorPrimary" />

                    <LinearLayout
                        android:layout_width="match_parent"
                        android:layout_height="wrap_content"
                        android:orientation="horizontal"
                        android:layout_marginBottom="8dp"
                        android:layout_marginHorizontal="16dp">

                        <Space
                            android:layout_width="40dp"
                            android:layout_height="match_parent" />

                        <com.google.android.material.button.MaterialButton
                            android:id="@+id/btn_melon_discovery"
                            style="@style/Widget.Material3.Button"
                            android:layout_width="0dp"
                            android:layout_height="wrap_content"
                            android:layout_weight="1"
                            android:text="@string/multiplayer_melon_discovery"
                            app:cornerRadius="16dp"
                            app:icon="@drawable/ic_search" />

                        <Space
                            android:layout_width="40dp"
                            android:layout_height="match_parent" />

                    </LinearLayout>

                    <LinearLayout
                        android:layout_width="match_parent"
                        android:layout_height="wrap_content"
                        android:orientation="horizontal"
                        android:layout_marginHorizontal="16dp"
                        android:layout_marginBottom="8dp">

                        <com.google.android.material.button.MaterialButton
                            android:id="@+id/btn_melon_join"
                            style="@style/Widget.Material3.Button.ElevatedButton"
                            android:layout_width="0dp"
                            android:layout_height="wrap_content"
                            android:layout_weight="1"
                            android:text="@string/multiplayer_melon_join"
                            app:icon="@drawable/ic_install"
                            app:cornerRadius="16dp" />

                        <Space
                            android:layout_width="16dp"
                            android:layout_height="match_parent" />

                        <com.google.android.material.button.MaterialButton
                            android:id="@+id/btn_melon_host"
                            style="@style/Widget.Material3.Button.TonalButton"
                            android:layout_width="0dp"
                            android:layout_height="wrap_content"
                            android:layout_weight="1"
                            android:text="@string/multiplayer_melon_host"
                            app:icon="@drawable/ic_add"
                            app:cornerRadius="16dp" />
                    </LinearLayout>

                </LinearLayout>

            </FrameLayout>

        </LinearLayout>

    </androidx.core.widget.NestedScrollView>

</LinearLayout>
"""

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def find_file(root: Path, *rel_candidates: str) -> Path | None:
    for rel in rel_candidates:
        p = root / rel
        if p.exists():
            return p
    return None

def main():
    repo_root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
    print(f"\n{CYAN}{'='*60}{RESET}")
    print(f"{CYAN}  Landscape BottomSheet Fix — AzaharTrigger-test{RESET}")
    print(f"{CYAN}  Repo root: {repo_root}{RESET}")
    print(f"{CYAN}{'='*60}{RESET}\n")

    results = []

    # ── Kotlin files ──────────────────────────────────────────────────────────
    game_adapter = find_file(
        repo_root,
        "src/android/app/src/main/java/org/citra/citra_emu/adapters/GameAdapter.kt",
        "app/src/main/java/org/citra/citra_emu/adapters/GameAdapter.kt",
    )
    netplay_dialog = find_file(
        repo_root,
        "src/android/app/src/main/java/org/citra/citra_emu/dialogs/NetPlayDialog.kt",
        "app/src/main/java/org/citra/citra_emu/dialogs/NetPlayDialog.kt",
    )

    # ── XML files ─────────────────────────────────────────────────────────────
    dialog_about_game = find_file(
        repo_root,
        "src/android/app/src/main/res/layout/dialog_about_game.xml",
        "app/src/main/res/layout/dialog_about_game.xml",
    )
    dialog_multiplayer = find_file(
        repo_root,
        "src/android/app/src/main/res/layout/dialog_multiplayer_connect.xml",
        "app/src/main/res/layout/dialog_multiplayer_connect.xml",
    )

    # ── Jalankan patch ────────────────────────────────────────────────────────
    print(f"{YELLOW}[1/5] GameAdapter.kt — peekHeight landscape{RESET}")
    if game_adapter:
        results.append(patch_file(game_adapter, GAME_ADAPTER_OLD, GAME_ADAPTER_NEW,
                                  "GameAdapter.kt"))
    else:
        err("GameAdapter.kt tidak ditemukan — cek repo_root")
        results.append(False)

    print(f"\n{YELLOW}[2/5] NetPlayDialog.kt — onCreate() duplikat + peekHeight{RESET}")
    if netplay_dialog:
        results.append(patch_file(netplay_dialog, NETPLAY_ONCREATE_OLD, NETPLAY_ONCREATE_NEW,
                                  "NetPlayDialog.kt onCreate"))
    else:
        err("NetPlayDialog.kt tidak ditemukan")
        results.append(False)

    print(f"\n{YELLOW}[3/5] NetPlayDialog.kt — showMelonInputDialogForDiscovery() duplikat + peekHeight{RESET}")
    if netplay_dialog:
        results.append(patch_file(netplay_dialog, NETPLAY_MELON_OLD, NETPLAY_MELON_NEW,
                                  "NetPlayDialog.kt melonDiscovery"))
    else:
        results.append(False)

    print(f"\n{YELLOW}[4/5] dialog_about_game.xml — NestedScrollView + icon 100dp{RESET}")
    if dialog_about_game:
        results.append(replace_xml(dialog_about_game, DIALOG_ABOUT_GAME_XML,
                                   "dialog_about_game.xml"))
    else:
        err("dialog_about_game.xml tidak ditemukan")
        results.append(False)

    print(f"\n{YELLOW}[5/5] dialog_multiplayer_connect.xml — NestedScrollView + icon 80dp{RESET}")
    if dialog_multiplayer:
        results.append(replace_xml(dialog_multiplayer, DIALOG_MULTIPLAYER_XML,
                                   "dialog_multiplayer_connect.xml"))
    else:
        err("dialog_multiplayer_connect.xml tidak ditemukan")
        results.append(False)

    # ── Summary ───────────────────────────────────────────────────────────────
    success = sum(1 for r in results if r)
    total   = len(results)
    print(f"\n{CYAN}{'='*60}{RESET}")
    if success == total:
        print(f"{GREEN}  Semua {total} patch berhasil diterapkan!{RESET}")
    else:
        print(f"{YELLOW}  {success}/{total} patch berhasil — cek pesan di atas{RESET}")
    print(f"{CYAN}{'='*60}{RESET}\n")

if __name__ == "__main__":
    main()
