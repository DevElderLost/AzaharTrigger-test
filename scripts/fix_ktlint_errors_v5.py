#!/usr/bin/env python3
"""
fix_ktlint_errors_v5.py
Perbaikan error KOMPILASI Kotlin (bukan ktlint) yang muncul setelah ktlint lolos:

  1. NativeLibrary.kt:994 'Unresolved reference Date'
     -> Bug dari v1: import java.util.Date terhapus padahal Date masih dipakai
        sebagai tipe di 'var time: Date? = null' (baris ~999).

  2. ComboButtonManager.kt:102 'Unresolved reference TouchScreenDevice'
     InputOverlay.kt:194    'Unresolved reference TouchScreenDevice'
     -> Nama konstanta yang benar di NativeLibrary.kt adalah TOUCHSCREEN_DEVICE
        (huruf besar), bukan TouchScreenDevice (PascalCase). Ini typo lama,
        bukan akibat patch ktlint sebelumnya.

Jalankan dari root repo SETELAH v1, v2, v3, v4:
    python3 scripts/fix_ktlint_errors_v5.py
"""

import os, sys

REPO_CANDIDATES = [".", "AzaharTrigger-test"]
BASE_REL = "src/android/app/src/main/java/org/citra/citra_emu"
CHANGED = SKIPPED = MISSING = 0


def find_repo_root():
    for c in REPO_CANDIDATES:
        if os.path.isdir(os.path.join(c, BASE_REL)):
            return os.path.abspath(c)
    print(f"[FATAL] '{BASE_REL}' tidak ditemukan"); sys.exit(1)


def read(p): return open(p, encoding="utf-8").read()
def write(p, s): open(p, "w", encoding="utf-8").write(s)


def patch_file(path, replacements, label):
    global CHANGED, SKIPPED, MISSING
    if not os.path.isfile(path):
        print(f"[MISSING] {label}: {path}"); MISSING += 1; return
    content = read(path); orig = content; changed = False
    for old, new, desc in replacements:
        if old not in content:
            print(f"  {'[SKIP]' if new in content else '[WARN]'} {label}: '{desc}'")
            continue
        content = content.replace(old, new, 1); changed = True
        print(f"  [OK]   {label}: '{desc}'")
    if changed and content != orig:
        write(path, content); CHANGED += 1
    else:
        SKIPPED += 1


def main():
    root = find_repo_root()
    base = os.path.join(root, BASE_REL)
    print(f"Repo root: {root}\n")

    # =========================================================================
    # 1. NativeLibrary.kt — kembalikan import java.util.Date (masih dipakai)
    # =========================================================================
    path = os.path.join(base, "NativeLibrary.kt")
    patch_file(path, [
        (
            "import java.lang.ref.WeakReference\n"
            "import org.citra.citra_emu.activities.EmulationActivity\n",
            "import java.lang.ref.WeakReference\n"
            "import java.util.Date\n"
            "import org.citra.citra_emu.activities.EmulationActivity\n",
            "kembalikan import java.util.Date (masih dipakai di 'var time: Date? = null')",
        ),
    ], "NativeLibrary.kt")

    # =========================================================================
    # 2. overlay/ComboButtonManager.kt — perbaiki nama konstanta
    # =========================================================================
    path = os.path.join(base, "overlay", "ComboButtonManager.kt")
    patch_file(path, [
        (
            "NativeLibrary.onGamePadEvent(NativeLibrary.TouchScreenDevice, nativeBtn, state)",
            "NativeLibrary.onGamePadEvent(NativeLibrary.TOUCHSCREEN_DEVICE, nativeBtn, state)",
            "perbaiki nama konstanta TouchScreenDevice -> TOUCHSCREEN_DEVICE",
        ),
    ], "ComboButtonManager.kt")

    # =========================================================================
    # 3. overlay/InputOverlay.kt — perbaiki nama konstanta
    # =========================================================================
    path = os.path.join(base, "overlay", "InputOverlay.kt")
    patch_file(path, [
        (
            "                        NativeLibrary.onGamePadEvent(\n"
            "                            NativeLibrary.TouchScreenDevice,\n"
            "                            button.id,\n"
            "                            button.status\n"
            "                        )\n",
            "                        NativeLibrary.onGamePadEvent(\n"
            "                            NativeLibrary.TOUCHSCREEN_DEVICE,\n"
            "                            button.id,\n"
            "                            button.status\n"
            "                        )\n",
            "perbaiki nama konstanta TouchScreenDevice -> TOUCHSCREEN_DEVICE",
        ),
    ], "InputOverlay.kt")

    print()
    print(f"Selesai. Diubah: {CHANGED}, dilewati: {SKIPPED}, hilang: {MISSING}")
    print()
    print("Catatan: jika pola WARN/SKIP muncul untuk InputOverlay.kt atau")
    print("ComboButtonManager.kt, kemungkinan posisi baris persis sedikit beda")
    print("dari file yang diuji -- cari manual 'NativeLibrary.TouchScreenDevice'")
    print("dan ganti jadi 'NativeLibrary.TOUCHSCREEN_DEVICE' di kedua file.")


if __name__ == "__main__":
    main()
