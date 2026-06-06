#!/bin/bash
# fix_netplay_final.sh — Fix 2 masalah sekaligus:
# 1. Hapus AlertDialog duplikat di btnZeroTier
# 2. Fix validasi IP agar tidak reject ZeroTier IP

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
NETPLAY="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/dialogs/NetPlayDialog.kt"

[ -f "$NETPLAY" ] || { echo "[ERROR] NetPlayDialog.kt tidak ditemukan"; exit 1; }

python3 - "$NETPLAY" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# ── Fix 1: Hapus AlertDialog duplikat di btnZeroTier ─────────────
# Ganti seluruh block ZeroTier listener yang ada AlertDialog
# menjadi: langsung buka ZeroTierDialog saja
old_btn = '''                    // Mode 3: ZeroTier
                    btnZeroTier.setOnClickListener {
                        dismiss()
                        if (!ZeroTierManager.isReady()) {
                            ZeroTierDialog(context).show()
                        } else {
                            val ztIp = ZeroTierManager.getAssignedIP()
                            android.app.AlertDialog.Builder(context)
                                .setTitle("ZeroTier \\u2713 IP: $ztIp")
                                .setPositiveButton("Buat Room") { _, _ ->
                                    showNetPlayInputDialog(true, MultiplayerMode.ZEROTIER)
                                }
                                .setNeutralButton("Gabung Room") { _, _ ->
                                    showNetPlayInputDialog(false, MultiplayerMode.ZEROTIER)
                                }
                                .setNegativeButton("Pengaturan ZT") { _, _ ->
                                    ZeroTierDialog(context).show()
                                }
                                .show()
                        }
                    }
                    if (ZeroTierManager.isReady())
                        btnZeroTier.text = "ZeroTier \\u2713"'''

new_btn = '''                    // Mode 3: ZeroTier — langsung buka ZeroTierDialog
                    // Tombol Create/Join sudah ada di menu utama (btnCreate/btnJoin)
                    btnZeroTier.setOnClickListener {
                        dismiss()
                        ZeroTierDialog(context).show()
                    }
                    // Update teks tombol sesuai status ZeroTier
                    btnZeroTier.text = if (ZeroTierManager.isReady())
                        "ZeroTier \\u2713" else "ZeroTier"'''

if old_btn in content:
    content = content.replace(old_btn, new_btn)
    print("[OK] Fix 1: AlertDialog duplikat dihapus dari btnZeroTier")
else:
    # Fallback regex
    import re
    content = re.sub(
        r'// Mode 3: ZeroTier.*?btnZeroTier\.text = "ZeroTier \\\\u2713"',
        new_btn,
        content,
        flags=re.DOTALL
    )
    print("[OK] Fix 1: AlertDialog duplikat dihapus (regex)")

# ── Fix 2: IP validation — accept ZeroTier IP ────────────────────
# Masalah: getIpAddressByWifi() return "" atau "0.0.0.0" saat no WiFi
# lalu validasi ipAddress.length < 7 menolak IP kosong
# Fix: jika ZeroTier ready dan IP kosong/invalid, pakai ZT IP
old_validation = '''            if (ipAddress.length < 7 || username.length < 5) {
                Toast.makeText(activity, R.string.multiplayer_input_invalid, Toast.LENGTH_LONG).show()
                binding.btnConfirm.isEnabled = true
                binding.btnConfirm.text = activity.getString(R.string.original_button_text)
            } else {'''

new_validation = '''            // Jika IP kosong/invalid dan ZeroTier ready, otomatis pakai ZT IP
            val effectiveIp = if ((ipAddress.isEmpty() || ipAddress == "0.0.0.0" ||
                ipAddress.length < 7) && ZeroTierManager.isReady()) {
                ZeroTierManager.getAssignedIP()
            } else {
                ipAddress
            }
            binding.ipAddress.setText(effectiveIp)

            if (effectiveIp.length < 7 || username.length < 5) {
                Toast.makeText(activity, R.string.multiplayer_input_invalid, Toast.LENGTH_LONG).show()
                binding.btnConfirm.isEnabled = true
                binding.btnConfirm.text = activity.getString(R.string.original_button_text)
            } else {'''

if old_validation in content:
    content = content.replace(old_validation, new_validation)
    print("[OK] Fix 2: IP validation dipatch untuk ZeroTier")
else:
    print("[WARN] Fix 2: Pattern validasi tidak cocok, cek manual")

# ── Fix 3: Ganti ipAddress dengan effectiveIp di Thread block ────
# Agar Thread menggunakan effectiveIp bukan ipAddress yang mungkin kosong
old_thread_ip = '''                Thread {
                    val result = if (isCreateRoom) {
                        NetPlayManager.netPlayCreateRoom(
                            ipAddress, port, username,'''
new_thread_ip = '''                Thread {
                    val result = if (isCreateRoom) {
                        NetPlayManager.netPlayCreateRoom(
                            effectiveIp, port, username,'''
if old_thread_ip in content:
    content = content.replace(old_thread_ip, new_thread_ip)
    print("[OK] Fix 3: Thread pakai effectiveIp")

old_join_ip = '''                        NetPlayManager.netPlayJoinRoom(ipAddress, port, username, password)'''
new_join_ip = '''                        NetPlayManager.netPlayJoinRoom(effectiveIp, port, username, password)'''
if old_join_ip in content:
    content = content.replace(old_join_ip, new_join_ip)

with open(path, 'w') as f:
    f.write(content)
print("[OK] NetPlayDialog.kt selesai dipatch")
PYEOF

echo ""
echo "  git add ."
echo "  git commit -m \"fix: hapus dialog duplikat ZeroTier + fix IP validation untuk ZT\""
echo "  git push origin DevElderLost-patch-4"
echo ""
