#!/usr/bin/env python3
"""
fix_ktlint_errors_v6.py
Perbaikan error ktlint BARU pada file yang diedit ulang oleh Elder
(GameAdapter.kt baru, ComboButtonSettingsFragment.kt ditulis ulang).

File yang diubah:
  - adapters/GameAdapter.kt              : 3 blok duplikat if-landscape
                                            (indentasi continuation + missing
                                            newline sebelum ")")
  - features/settings/ui/ComboButtonSettingsFragment.kt : import order,
                                            spasi berlebih, argumen multi-baris,
                                            Missing { ... }

Jalankan dari root repo:
    python3 scripts/fix_ktlint_errors_v6.py
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
    """replacements item can be (old, new, desc) or (old, new, desc, count)
    where count = berapa kali replace dijalankan (default 1)."""
    global CHANGED, SKIPPED, MISSING
    if not os.path.isfile(path):
        print(f"[MISSING] {label}: {path}"); MISSING += 1; return
    content = read(path); orig = content; changed = False
    for item in replacements:
        if len(item) == 4:
            old, new, desc, count = item
        else:
            old, new, desc = item
            count = 1
        if old not in content:
            print(f"  {'[SKIP]' if new in content else '[WARN]'} {label}: '{desc}'")
            continue
        n_before = content.count(old)
        content = content.replace(old, new, count)
        changed = True
        print(f"  [OK]   {label}: '{desc}' ({min(count, n_before)}x)")
    if changed and content != orig:
        write(path, content); CHANGED += 1
    else:
        SKIPPED += 1


def main():
    root = find_repo_root()
    base = os.path.join(root, BASE_REL)
    print(f"Repo root: {root}\n")

    # =========================================================================
    # 1. adapters/GameAdapter.kt — 3 blok duplikat if-landscape
    # =========================================================================
    path = os.path.join(base, "adapters", "GameAdapter.kt")
    patch_file(path, [
        (
            "        if (context.resources.configuration.orientation ==\n"
            "                android.content.res.Configuration.ORIENTATION_LANDSCAPE) {\n"
            "            bottomSheetBehavior.peekHeight = context.resources.displayMetrics.heightPixels\n"
            "        }\n",
            "        if (context.resources.configuration.orientation ==\n"
            "            android.content.res.Configuration.ORIENTATION_LANDSCAPE\n"
            "        ) {\n"
            "            bottomSheetBehavior.peekHeight = context.resources.displayMetrics.heightPixels\n"
            "        }\n",
            "ratakan indentasi (16->12) & newline sebelum ')' pada blok if-landscape duplikat",
            3,
        ),
    ], "GameAdapter.kt")

    # =========================================================================
    # 2. features/settings/ui/ComboButtonSettingsFragment.kt
    # =========================================================================
    path = os.path.join(base, "features", "settings", "ui", "ComboButtonSettingsFragment.kt")
    patch_file(path, [
        # 2a. Import order: HomeViewModel harus setelah androidx.navigation, sebelum com.google
        (
            "import androidx.fragment.app.activityViewModels\n"
            "import org.citra.citra_emu.viewmodel.HomeViewModel\n"
            "import androidx.navigation.fragment.findNavController\n"
            "import com.google.android.material.chip.Chip\n",
            "import androidx.fragment.app.activityViewModels\n"
            "import androidx.navigation.fragment.findNavController\n"
            "import com.google.android.material.chip.Chip\n",
            "hapus HomeViewModel dari posisi salah (akan ditambahkan di posisi benar)",
        ),
        (
            "import org.citra.citra_emu.databinding.ItemComboButtonBinding\n"
            "import org.citra.citra_emu.overlay.ComboButtonManager\n",
            "import org.citra.citra_emu.databinding.ItemComboButtonBinding\n"
            "import org.citra.citra_emu.overlay.ComboButtonManager\n"
            "import org.citra.citra_emu.viewmodel.HomeViewModel\n",
            "tambahkan import HomeViewModel di posisi lexicographic yang benar",
        ),
        # 2b. Hapus spasi berlebih sebelum '=' (enterTransition / returnTransition)
        (
            "        enterTransition  = MaterialSharedAxis(MaterialSharedAxis.X, true)\n"
            "        returnTransition = MaterialSharedAxis(MaterialSharedAxis.X, false)\n",
            "        enterTransition = MaterialSharedAxis(MaterialSharedAxis.X, true)\n"
            "        returnTransition = MaterialSharedAxis(MaterialSharedAxis.X, false)\n",
            "hapus spasi berlebih sebelum '=' (enterTransition)",
        ),
        # 2c. Pecah argumen ItemComboButtonBinding.inflate (baris 68)
        (
            "            val cardBinding = ItemComboButtonBinding.inflate(\n"
            "                layoutInflater, binding.comboContainer, true\n"
            "            )\n",
            "            val cardBinding = ItemComboButtonBinding.inflate(\n"
            "                layoutInflater,\n"
            "                binding.comboContainer,\n"
            "                true\n"
            "            )\n",
            "satu argumen per baris (ItemComboButtonBinding.inflate, baris 68)",
        ),
        # 2d. Hapus spasi berlebih sebelum '=' (names/ids/selected/checked)
        (
            "        val names      = assignable.map { it.first }.toTypedArray()\n"
            "        val ids        = assignable.map { it.second }\n"
            "        val selected   = ComboButtonManager.getButtonsForSlot(slot).toMutableSet()\n"
            "        val checked    = BooleanArray(names.size) { i -> ids[i] in selected }\n",
            "        val names = assignable.map { it.first }.toTypedArray()\n"
            "        val ids = assignable.map { it.second }\n"
            "        val selected = ComboButtonManager.getButtonsForSlot(slot).toMutableSet()\n"
            "        val checked = BooleanArray(names.size) { i -> ids[i] in selected }\n",
            "hapus spasi berlebih sebelum '=' pada names/ids/selected/checked",
        ),
        # 2e. Toast.makeText getString — pecah argumen & Missing { ... } pada else
        (
            "                        checked[which] = false\n"
            "                        Toast.makeText(\n"
            "                            requireContext(),\n"
            "                            getString(R.string.combo_button_max_exceeded,\n"
            "                                ComboButtonManager.MAX_BUTTONS_PER_COMBO),\n"
            "                            Toast.LENGTH_SHORT\n"
            "                        ).show()\n"
            "                    } else selected.add(id)\n"
            "                } else selected.remove(id)\n",
            "                        checked[which] = false\n"
            "                        Toast.makeText(\n"
            "                            requireContext(),\n"
            "                            getString(\n"
            "                                R.string.combo_button_max_exceeded,\n"
            "                                ComboButtonManager.MAX_BUTTONS_PER_COMBO\n"
            "                            ),\n"
            "                            Toast.LENGTH_SHORT\n"
            "                        ).show()\n"
            "                    } else {\n"
            "                        selected.add(id)\n"
            "                    }\n"
            "                } else {\n"
            "                    selected.remove(id)\n"
            "                }\n",
            "pecah argumen getString (baris 129-130) & Missing { ... } pada 2 else (baris 133-134)",
        ),
    ], "ComboButtonSettingsFragment.kt")

    print()
    print(f"Selesai. Diubah: {CHANGED}, dilewati: {SKIPPED}, hilang: {MISSING}")


if __name__ == "__main__":
    main()
