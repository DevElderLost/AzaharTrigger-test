#!/usr/bin/env python3
"""
fix_ktlint_errors_v4.py
Perbaikan sisa error ktlint setelah v1 + v2 + v3.

Error tersisa (dari log build):
  NetPlayDialog.kt:108-111 — data class NetPlayItems parameter harus satu baris
  NetPlayDialog.kt:513-515 — BanListAdapter parameter harus satu baris, super type baris baru

Jalankan dari root repo SETELAH v1, v2, v3:
    python3 scripts/fix_ktlint_errors_v4.py
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

    path = os.path.join(base, "dialogs", "NetPlayDialog.kt")
    patch_file(path, [
        # Fix 1: data class NetPlayItems — jadikan satu baris (96 char, muat dalam 100)
        (
            "    data class NetPlayItems(\n"
            "        val option: Int,\n"
            "        val name: String,\n"
            "        val type: Int,\n"
            "        val id: Int = 0\n"
            "    ) {\n",
            "    data class NetPlayItems(val option: Int, val name: String, val type: Int, val id: Int = 0) {\n",
            "jadikan parameter NetPlayItems satu baris (96 char, no whitespace after '(')",
        ),
        # Fix 2: BanListAdapter — parameter satu baris, super type di baris baru
        # "    private class BanListAdapter(params) :" = 94 char — aman
        (
            "    private class BanListAdapter(\n"
            "        banList: List<String>,\n"
            "        private val onUnban: (String) -> Unit\n"
            "    ) : RecyclerView.Adapter<BanListAdapter.ViewHolder>() {\n",
            "    private class BanListAdapter(banList: List<String>, private val onUnban: (String) -> Unit) :\n"
            "        RecyclerView.Adapter<BanListAdapter.ViewHolder>() {\n",
            "jadikan parameter BanListAdapter satu baris & super type di baris baru (no whitespace after '(')",
        ),
    ], "NetPlayDialog.kt")

    print()
    print(f"Selesai. Diubah: {CHANGED}, dilewati: {SKIPPED}, hilang: {MISSING}")


if __name__ == "__main__":
    main()
