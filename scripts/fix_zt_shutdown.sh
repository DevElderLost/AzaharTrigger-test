#!/bin/bash
# fix_zt_shutdown.sh — Fix crash saat tombol Putuskan ditekan
#
# Cara pakai:
#   bash scripts/fix_zt_shutdown.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
UTILS_DIR="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/utils"

echo "[INFO] Fix shutdown ZeroTierManager..."

python3 - "$UTILS_DIR/ZeroTierManager.kt" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

old_shutdown = '''    fun shutdown() {
        if (state == State.IDLE) return
        try {
            if (currentNetworkId != 0L)
                callStatic("zts_net_leave", currentNetworkId)
            callStatic("zts_node_stop")
        } catch (e: Exception) { Log.e(TAG, "Shutdown: ${e.message}") }
        assignedIp = ""; currentNetworkId = 0L
        state = State.IDLE
    }'''

new_shutdown = '''    fun shutdown() {
        if (state == State.IDLE) return
        // Set IDLE dulu agar tidak ada thread lain yang masuk
        state = State.IDLE
        Thread {
            try {
                if (ztNativeClass != null) {
                    if (currentNetworkId != 0L) {
                        try { callStatic("zts_net_leave", currentNetworkId) }
                        catch (e: Exception) { Log.w(TAG, "leave: ${e.message}") }
                    }
                    try { callStatic("zts_node_stop") }
                    catch (e: Exception) { Log.w(TAG, "stop: ${e.message}") }
                }
                Log.i(TAG, "ZeroTier stopped")
            } catch (e: Exception) {
                Log.e(TAG, "Shutdown error: ${e.message}")
            } finally {
                assignedIp        = ""
                currentNetworkId  = 0L
                ztNativeClass     = null
            }
        }.start()
    }'''

if old_shutdown in content:
    content = content.replace(old_shutdown, new_shutdown)
    with open(path, 'w') as f:
        f.write(content)
    print("[OK] shutdown() dipatch — dijalankan di background thread")
else:
    # Fallback: ganti dengan regex
    import re
    pattern = r'fun shutdown\(\)[^}]+(?:}[^}]+)*?state = State\.IDLE\s*\}'
    if re.search(pattern, content, re.DOTALL):
        content = re.sub(pattern, new_shutdown.strip(), content, flags=re.DOTALL)
        with open(path, 'w') as f:
            f.write(content)
        print("[OK] shutdown() di-patch via regex")
    else:
        print("[WARN] Pattern tidak cocok, tambah manual")
PYEOF

echo ""
echo "  git add ."
echo "  git commit -m \"fix: ZeroTier shutdown di background thread agar tidak crash\""
echo "  git push origin DevElderLost-patch-4"
echo ""
