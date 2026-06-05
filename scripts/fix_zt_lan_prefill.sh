#!/bin/bash
# fix_zt_lan_prefill.sh — Fix pre-fill IP saat Create Room via ZeroTier
# Masalah: NetPlayDialog pre-fill IP dengan getIpAddressByWifi() yang
# tidak mengembalikan IP ZeroTier saat pakai data seluler.
# Fix: jika ZeroTier ready, gunakan ZeroTier IP sebagai host IP.
#
# Cara pakai:
#   bash scripts/fix_zt_lan_prefill.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
DIALOGS_DIR="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/dialogs"
NETPLAY_DIALOG="$DIALOGS_DIR/NetPlayDialog.kt"

[ -f "$NETPLAY_DIALOG" ] || {
    echo "[ERROR] NetPlayDialog.kt tidak ditemukan: $NETPLAY_DIALOG"
    exit 1
}

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix: ZeroTier IP sebagai host IP saat Create Room"
echo "═══════════════════════════════════════════════════════"
echo ""

python3 - "$NETPLAY_DIALOG" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# ── Fix 1: Pre-fill IP di showNetPlayInputDialog ──────────────────
# Ganti bagian pre-fill IP agar prioritaskan ZeroTier IP
# jika ZeroTier sudah ready

old_prefill_1 = '''        val prefilledIp = when {
            isCreateRoom && mode == MultiplayerMode.ZEROTIER -> ZeroTierManager.getAssignedIP()
            isCreateRoom -> NetPlayManager.getIpAddressByWifi(activity)
            else         -> NetPlayManager.getRoomAddress(activity)
        }
        binding.ipAddress.setText(prefilledIp)'''

new_prefill_1 = '''        // Prioritaskan ZeroTier IP jika sudah terhubung
        // (berlaku untuk semua mode termasuk LAN saat pakai data seluler)
        val prefilledIp = when {
            // Mode ZeroTier Create: pakai ZT IP
            isCreateRoom && mode == MultiplayerMode.ZEROTIER ->
                ZeroTierManager.getAssignedIP()
            // Mode LAN Create: jika ZT ready, pakai ZT IP (data seluler + ZT)
            // jika tidak, pakai WiFi IP seperti biasa
            isCreateRoom ->
                if (ZeroTierManager.isReady()) ZeroTierManager.getAssignedIP()
                else NetPlayManager.getIpAddressByWifi(activity)
            // Mode Join: pakai IP terakhir
            else -> NetPlayManager.getRoomAddress(activity)
        }
        binding.ipAddress.setText(prefilledIp)'''

# Coba pola lain jika tidak ditemukan
old_prefill_2 = '''        binding.ipAddress.setText(
            if (isCreateRoom) NetPlayManager.getIpAddressByWifi(activity)
            else NetPlayManager.getRoomAddress(activity)
        )'''

new_prefill_2 = '''        // Prioritaskan ZeroTier IP jika sudah terhubung
        val hostIp = when {
            isCreateRoom && ZeroTierManager.isReady() -> ZeroTierManager.getAssignedIP()
            isCreateRoom -> NetPlayManager.getIpAddressByWifi(activity)
            else -> NetPlayManager.getRoomAddress(activity)
        }
        binding.ipAddress.setText(hostIp)'''

changed = False
if old_prefill_1 in content:
    content = content.replace(old_prefill_1, new_prefill_1)
    changed = True
    print("  [OK] Pre-fill IP (mode variant) dipatch")
elif old_prefill_2 in content:
    content = content.replace(old_prefill_2, new_prefill_2)
    changed = True
    print("  [OK] Pre-fill IP (simple variant) dipatch")
else:
    # Fallback: ganti semua getIpAddressByWifi yang ada di pre-fill section
    import re
    # Cari pola pre-fill IP
    pattern = r'(binding\.ipAddress\.setText\(\s*\n?\s*if \(isCreateRoom\) NetPlayManager\.getIpAddressByWifi\([^)]+\)\s*\n?\s*else NetPlayManager\.getRoomAddress\([^)]+\)\s*\n?\s*\))'
    if re.search(pattern, content):
        replacement = '''binding.ipAddress.setText(
            if (isCreateRoom) {
                if (ZeroTierManager.isReady()) ZeroTierManager.getAssignedIP()
                else NetPlayManager.getIpAddressByWifi(activity)
            } else NetPlayManager.getRoomAddress(activity)
        )'''
        content = re.sub(pattern, replacement, content)
        changed = True
        print("  [OK] Pre-fill IP (regex) dipatch")

if not changed:
    print("  [WARN] Pattern pre-fill tidak ditemukan, cek manual")
    # Tampilkan baris yang mengandung getIpAddressByWifi
    for i, line in enumerate(content.split('\n'), 1):
        if 'getIpAddressByWifi' in line or 'ipAddress.setText' in line:
            print(f"  Baris {i}: {line.strip()}")

# ── Fix 2: Pastikan import ZeroTierManager ada ────────────────────
if 'import org.citra.citra_emu.utils.ZeroTierManager' not in content:
    content = content.replace(
        'import org.citra.citra_emu.utils.NetPlayManager',
        'import org.citra.citra_emu.utils.NetPlayManager\nimport org.citra.citra_emu.utils.ZeroTierManager'
    )
    print("  [OK] Import ZeroTierManager ditambahkan")

# ── Fix 3: Tampilkan label mode yang informatif ───────────────────
# Tambah info ZeroTier di modeLabel jika ZT ready
old_mode_label = '''        binding.modeLabel.apply {
            visibility = View.VISIBLE
            text = when (mode) {
                MultiplayerMode.LAN ->
                    context.getString(R.string.multiplayer_mode_lan)
                MultiplayerMode.ZEROTIER ->
                    context.getString(R.string.multiplayer_mode_zerotier,
                        ZeroTierManager.getAssignedIP())
                MultiplayerMode.PUBLIC -> ""
            }
        }'''

new_mode_label = '''        binding.modeLabel.apply {
            visibility = View.VISIBLE
            text = when {
                mode == MultiplayerMode.ZEROTIER ->
                    context.getString(R.string.multiplayer_mode_zerotier,
                        ZeroTierManager.getAssignedIP())
                mode == MultiplayerMode.LAN && ZeroTierManager.isReady() ->
                    context.getString(R.string.multiplayer_mode_zerotier,
                        ZeroTierManager.getAssignedIP()) + " (via ZeroTier)"
                mode == MultiplayerMode.LAN ->
                    context.getString(R.string.multiplayer_mode_lan)
                else -> ""
            }
        }'''

if old_mode_label in content:
    content = content.replace(old_mode_label, new_mode_label)
    print("  [OK] modeLabel dipatch untuk ZeroTier + LAN")

with open(path, 'w') as f:
    f.write(content)
print("  NetPlayDialog.kt selesai dipatch")
PYEOF

echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "\033[0;32m  Fix selesai!\033[0m"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  git add ."
echo "  git commit -m \"fix: gunakan ZeroTier IP saat Create Room jika ZT terhubung\""
echo "  git push origin DevElderLost-patch-4"
echo ""
