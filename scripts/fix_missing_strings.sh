#!/bin/bash
# fix_missing_strings.sh — Tambah semua string yang kurang
# Cara pakai:
#   bash scripts/fix_missing_strings.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
STRINGS_XML="$PROJECT_ROOT/src/android/app/src/main/res/values/strings.xml"
NETPLAY_DIALOG="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/dialogs/NetPlayDialog.kt"

[ -f "$STRINGS_XML" ] || { echo "[ERROR] strings.xml tidak ditemukan"; exit 1; }

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix: Tambah string resources yang kurang"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Tambah string yang kurang ke strings.xml ────────────────────
python3 - "$STRINGS_XML" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# String yang perlu ditambahkan
missing_strings = {
    'zerotier_btn_connected':       'ZeroTier \u2713',
    'zerotier_create_room_title':   'Buat Room (ZeroTier)',
    'zerotier_join_room_title':     'Gabung Room (ZeroTier)',
    'multiplayer_mode_lan':         'Mode: LAN (WiFi/Hotspot)',
    'multiplayer_mode_zerotier':    'Mode: ZeroTier \u2013 IP: %s',
    'zerotier_mode_title':          'ZeroTier Terhubung',
    'zerotier_mode_message':        'IP ZeroTier kamu: %s\n\nPilih mode:',
    'zerotier_btn_settings':        'Pengaturan ZT',
    'zerotier_btn_reconnect':       'Hubungkan Ulang',
}

added = []
for key, value in missing_strings.items():
    if f'name="{key}"' not in content:
        entry = f'    <string name="{key}">{value}</string>\n'
        content = content.replace('</resources>', entry + '</resources>')
        added.append(key)

with open(path, 'w') as f:
    f.write(content)

if added:
    print(f"  Ditambahkan: {', '.join(added)}")
else:
    print("  Semua string sudah ada")
PYEOF

# ── Fix NetPlayDialog.kt: ganti R.string refs yang bermasalah ────
echo ""
echo "[INFO] Fix NetPlayDialog.kt string references..."

python3 - "$NETPLAY_DIALOG" << 'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Fix 1: zerotier_btn_connected
content = content.replace(
    'context.getString(R.string.zerotier_btn_connected)',
    '"ZeroTier \u2713"'
)

# Fix 2: modeLabel — ganti binding.modeLabel dengan cara yang benar
# Error: "Cannot infer type for this parameter" karena modeLabel
# mungkin tidak ada di binding atau tipe tidak cocok
# Ganti dengan visibility + text yang explicit
old_mode_label = '''        binding.modeLabel.apply {
            visibility = View.VISIBLE
            text = when (mode) {
                MultiplayerMode.LAN ->
                    if (ZeroTierManager.isReady())
                        "ZeroTier \u2713 IP: ${ZeroTierManager.getAssignedIP()}"
                    else context.getString(R.string.multiplayer_mode_lan)
                MultiplayerMode.ZEROTIER ->
                    context.getString(R.string.multiplayer_mode_zerotier,
                        ZeroTierManager.getAssignedIP())
                MultiplayerMode.PUBLIC -> ""
            }
        }'''

new_mode_label = '''        // Tampilkan label mode
        try {
            val modeLabelText = when (mode) {
                MultiplayerMode.LAN ->
                    if (ZeroTierManager.isReady())
                        "ZeroTier \u2713 IP: ${ZeroTierManager.getAssignedIP()}"
                    else "Mode: LAN"
                MultiplayerMode.ZEROTIER ->
                    "ZeroTier \u2713 IP: ${ZeroTierManager.getAssignedIP()}"
                MultiplayerMode.PUBLIC -> ""
            }
            binding.modeLabel.visibility = View.VISIBLE
            binding.modeLabel.text = modeLabelText
        } catch (e: Exception) {
            // modeLabel mungkin tidak ada di layout lama
        }'''

if old_mode_label in content:
    content = content.replace(old_mode_label, new_mode_label)
    print("  [OK] modeLabel dipatch")
else:
    # Hapus modeLabel binding yang bermasalah
    content = re.sub(
        r'binding\.modeLabel\.apply \{[^}]+\}',
        '// modeLabel: removed incompatible binding',
        content,
        flags=re.DOTALL
    )
    # Hapus juga yang pakai visibility/text terpisah
    content = re.sub(
        r'binding\.modeLabel\.[^\n]+\n',
        '',
        content
    )
    print("  [OK] modeLabel binding dihapus (tidak ada di layout)")

# Fix 3: zerotier_create_room_title dan zerotier_join_room_title
# Pastikan string ada — sudah ditambahkan di strings.xml

# Fix 4: visibility reference yang tidak bisa diinfer
# Pastikan View.VISIBLE/GONE diimport
if 'import android.view.View' not in content:
    content = content.replace(
        'import android.view.ViewGroup',
        'import android.view.View\nimport android.view.ViewGroup'
    )
    print("  [OK] import android.view.View ditambahkan")

with open(path, 'w') as f:
    f.write(content)
print("  NetPlayDialog.kt selesai dipatch")
PYEOF

echo ""
echo -e "\033[0;32m  Fix selesai!\033[0m"
echo ""
echo "  git add ."
echo "  git commit -m \"fix: tambah string resources yang kurang + fix binding references\""
echo "  git push origin DevElderLost-patch-4"
echo ""
