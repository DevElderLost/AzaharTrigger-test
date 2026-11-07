#!/usr/bin/env python3
# patch_cartridge_icon_name.py
# Fix nama icon cartridge: @drawable/ic_cartridge → @drawable/cartridge
# Usage: python3 patch_cartridge_icon_name.py [repo_root]

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

def patch_file(filepath: Path, old: str, new: str, label: str) -> bool:
    if not filepath.exists():
        err(f"File tidak ditemukan: {filepath}")
        return False
    content = filepath.read_text(encoding="utf-8")
    if old not in content:
        warn(f"[{label}] Pola tidak ditemukan — mungkin sudah di-patch?")
        return False
    filepath.write_text(content.replace(old, new, 1), encoding="utf-8")
    ok(f"[{label}] Berhasil di-patch")
    return True

def find_file(root: Path, *candidates: str) -> Path | None:
    for c in candidates:
        p = root / c
        if p.exists():
            return p
    return None

def main():
    repo_root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
    print(f"\n{CYAN}{'='*52}{RESET}")
    print(f"{CYAN}  Cartridge Icon Name Fix — AzaharTrigger-test{RESET}")
    print(f"{CYAN}  Repo root: {repo_root}{RESET}")
    print(f"{CYAN}{'='*52}{RESET}\n")

    base_res  = "src/android/app/src/main/res"
    base_res2 = "app/src/main/res"

    card_xml = find_file(repo_root,
        f"{base_res}/layout/card_game.xml",
        f"{base_res2}/layout/card_game.xml")

    results = []

    print(f"{YELLOW}[1/1] card_game.xml — ganti ic_cartridge → cartridge{RESET}")
    if card_xml:
        results.append(patch_file(
            card_xml,
            'android:src="@drawable/ic_cartridge"',
            'android:src="@drawable/cartridge"',
            "card_game.xml cartridge src"
        ))
    else:
        err("card_game.xml tidak ditemukan")
        results.append(False)

    success = sum(1 for r in results if r)
    print(f"\n{CYAN}{'='*52}{RESET}")
    if success == len(results):
        print(f"{GREEN}  Patch berhasil!{RESET}")
    else:
        print(f"{YELLOW}  Patch gagal — cek pesan di atas{RESET}")
    print(f"{CYAN}{'='*52}{RESET}\n")

if __name__ == "__main__":
    main()
