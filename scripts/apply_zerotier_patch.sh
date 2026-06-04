#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# apply_zerotier_patch.sh — Patch ZeroTier native (libzt) ke project
# AzaharTrigger di GitHub Codespaces
#
# Cara pakai di GitHub Codespaces (dari root project):
#   bash scripts/apply_zerotier_patch.sh
#
# Script ini HANYA menambahkan logika ZeroTier baru.
# File yang sudah ada (room_member.cpp, dll) tidak disentuh.
# ═══════════════════════════════════════════════════════════════════

set -e

# ── Warna output ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Deteksi root project ────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$SCRIPT_DIR")")"
info "Project root: $PROJECT_ROOT"

# ── Path target ─────────────────────────────────────────────────────
JNI_DIR="$PROJECT_ROOT/src/android/app/src/main/jni"
KOTLIN_DIALOGS="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/dialogs"
KOTLIN_UTILS="$PROJECT_ROOT/src/android/app/src/main/java/org/citra/citra_emu/utils"
LAYOUT_DIR="$PROJECT_ROOT/src/android/app/src/main/res/layout"
VALUES_DIR="$PROJECT_ROOT/src/android/app/src/main/res/values"
EXTERNALS_DIR="$PROJECT_ROOT/externals"

# ── Validasi path ───────────────────────────────────────────────────
[ -d "$JNI_DIR" ]          || error "Folder JNI tidak ditemukan: $JNI_DIR"
[ -d "$KOTLIN_DIALOGS" ]   || error "Folder dialogs tidak ditemukan: $KOTLIN_DIALOGS"
[ -d "$KOTLIN_UTILS" ]     || error "Folder utils tidak ditemukan: $KOTLIN_UTILS"
[ -d "$LAYOUT_DIR" ]       || error "Folder layout tidak ditemukan: $LAYOUT_DIR"
[ -d "$VALUES_DIR" ]       || error "Folder values tidak ditemukan: $VALUES_DIR"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ZeroTier Native Patch — AzaharTrigger"
echo "═══════════════════════════════════════════════════════"
echo ""

# ════════════════════════════════════════════════════════════════════
# LANGKAH 1: Siapkan libzt-release.aar di folder libs
# ════════════════════════════════════════════════════════════════════
info "Langkah 1/7: Siapkan libzt AAR..."

AAR_LIBS_DIR="$PROJECT_ROOT/src/android/app/libs"
AAR_FILE="$AAR_LIBS_DIR/libzt-release.aar"

# Buat folder libs jika belum ada
mkdir -p "$AAR_LIBS_DIR"

if [ -f "$AAR_FILE" ]; then
    success "libzt-release.aar sudah ada di $AAR_LIBS_DIR"
else
    warn "File $AAR_FILE belum ada."
    warn "Salin file libzt-release.aar ke: $AAR_LIBS_DIR"
    warn "Kemudian jalankan script ini lagi."
    echo ""
    echo "  cp /path/to/libzt-release.aar $AAR_LIBS_DIR/"
    echo ""
    read -rp "Sudah disalin? Lanjutkan? (y/N): " aar_confirm
    [[ "$aar_confirm" =~ ^[Yy]$ ]] || exit 1
    [ -f "$AAR_FILE" ] || error "File $AAR_FILE masih tidak ditemukan"
fi
success "libzt-release.aar siap di $AAR_LIBS_DIR"

# ════════════════════════════════════════════════════════════════════
# LANGKAH 2: Buat ZeroTierNative.h
# ════════════════════════════════════════════════════════════════════
info "Langkah 2/7: Buat ZeroTierNative.h..."

cat > "$JNI_DIR/ZeroTierNative.h" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
#pragma once
#include <cstdint>
#include <string>

namespace ZeroTierNative {

enum class ZTResult {
    OK = 0,
    AlreadyRunning,
    InitFailed,
    JoinFailed,
    NetworkNotReady,
    Timeout,
};

ZTResult    Init(const std::string& storage_path, uint64_t network_id);
void        Shutdown();
bool        IsReady();
std::string GetAssignedIP();
uint64_t    GetNodeID();
uint64_t    ParseNetworkId(const std::string& hex_str);

} // namespace ZeroTierNative
EOF
success "ZeroTierNative.h dibuat"

# ════════════════════════════════════════════════════════════════════
# LANGKAH 3: Buat ZeroTierNative.cpp
# ════════════════════════════════════════════════════════════════════
info "Langkah 3/7: Buat ZeroTierNative.cpp..."

cat > "$JNI_DIR/ZeroTierNative.cpp" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
#include "ZeroTierNative.h"
#include "common/logging/log.h"
#include <ZeroTierSockets.h>
#include <atomic>
#include <chrono>
#include <cstring>
#include <string>
#include <thread>

namespace ZeroTierNative {

static std::atomic<bool> zt_initialized{false};
static std::atomic<bool> zt_node_online{false};
static std::atomic<bool> zt_network_ready{false};
static std::string       zt_storage_path;
static uint64_t          zt_network_id = 0;
static char              zt_assigned_ip[ZTS_IP_MAX_STR_LEN] = {0};

static void ZTEventCallback(void* msgPtr) {
    const zts_event_msg_t* msg = static_cast<zts_event_msg_t*>(msgPtr);
    if (!msg) return;
    switch (msg->event_code) {
    case ZTS_EVENT_NODE_ONLINE:
        LOG_INFO(Network, "[ZeroTier] Node online, ID: {:x}", msg->node->node_id);
        zt_node_online = true;
        break;
    case ZTS_EVENT_NODE_OFFLINE:
        LOG_WARNING(Network, "[ZeroTier] Node offline");
        zt_node_online   = false;
        zt_network_ready = false;
        break;
    case ZTS_EVENT_NETWORK_READY_IP4:
        LOG_INFO(Network, "[ZeroTier] Network IPv4 ready");
        zt_network_ready = true;
        if (msg->addr) {
            zts_inet_ntop(ZTS_AF_INET,
                &(((struct zts_sockaddr_in*)&msg->addr->addr)->sin_addr),
                zt_assigned_ip, ZTS_IP_MAX_STR_LEN);
            LOG_INFO(Network, "[ZeroTier] Assigned IP: {}", zt_assigned_ip);
        }
        break;
    case ZTS_EVENT_NETWORK_ACCESS_DENIED:
        LOG_ERROR(Network, "[ZeroTier] Access denied — node belum diauthorize");
        break;
    case ZTS_EVENT_ADDR_ADDED_IP4:
        if (msg->addr) {
            zts_inet_ntop(ZTS_AF_INET,
                &(((struct zts_sockaddr_in*)&msg->addr->addr)->sin_addr),
                zt_assigned_ip, ZTS_IP_MAX_STR_LEN);
        }
        break;
    default: break;
    }
}

ZTResult Init(const std::string& storage_path, uint64_t network_id) {
    if (zt_initialized) return ZTResult::AlreadyRunning;

    zt_storage_path  = storage_path;
    zt_network_id    = network_id;
    zt_node_online   = false;
    zt_network_ready = false;
    memset(zt_assigned_ip, 0, sizeof(zt_assigned_ip));

    if (zts_init_set_path(storage_path.c_str()) != ZTS_ERR_OK)
        return ZTResult::InitFailed;
    if (zts_init_set_event_handler(&ZTEventCallback) != ZTS_ERR_OK)
        return ZTResult::InitFailed;
    if (zts_node_start() != ZTS_ERR_OK)
        return ZTResult::InitFailed;

    constexpr int STEP_MS = 200;
    for (int e = 0; e < 15000; e += STEP_MS) {
        if (zt_node_online) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(STEP_MS));
    }
    if (!zt_node_online) { zts_node_stop(); return ZTResult::Timeout; }

    if (zts_net_join(network_id) != ZTS_ERR_OK) {
        zts_node_stop(); return ZTResult::JoinFailed;
    }

    for (int e = 0; e < 20000; e += STEP_MS) {
        if (zt_network_ready && strlen(zt_assigned_ip) > 0) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(STEP_MS));
    }
    if (!zt_network_ready || strlen(zt_assigned_ip) == 0) {
        zts_net_leave(network_id); zts_node_stop();
        return ZTResult::NetworkNotReady;
    }

    zt_initialized = true;
    return ZTResult::OK;
}

void Shutdown() {
    if (!zt_initialized) return;
    if (zt_network_id != 0) zts_net_leave(zt_network_id);
    zts_node_stop();
    zt_initialized   = false;
    zt_node_online   = false;
    zt_network_ready = false;
    zt_network_id    = 0;
    memset(zt_assigned_ip, 0, sizeof(zt_assigned_ip));
}

bool        IsReady()       { return zt_initialized && zt_node_online && zt_network_ready; }
std::string GetAssignedIP() { return std::string(zt_assigned_ip); }

uint64_t GetNodeID() {
    if (!zt_node_online) return 0;
    uint64_t id = 0; zts_node_get_id(&id); return id;
}

uint64_t ParseNetworkId(const std::string& hex_str) {
    try { return std::stoull(hex_str, nullptr, 16); } catch (...) { return 0; }
}

} // namespace ZeroTierNative
EOF
success "ZeroTierNative.cpp dibuat"

# ════════════════════════════════════════════════════════════════════
# LANGKAH 4: Buat jni_zt_bridge.cpp
# ════════════════════════════════════════════════════════════════════
info "Langkah 4/7: Buat jni_zt_bridge.cpp..."

cat > "$JNI_DIR/jni_zt_bridge.cpp" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
#include <jni.h>
#include <string>
#include "ZeroTierNative.h"

#ifdef __cplusplus
extern "C" {
#endif

JNIEXPORT jint JNICALL
Java_org_citra_citra_1emu_utils_NetPlayManager_ztInit(
        JNIEnv* env, jclass, jstring storagePath, jstring networkIdHex) {
    const char* path  = env->GetStringUTFChars(storagePath,  nullptr);
    const char* netid = env->GetStringUTFChars(networkIdHex, nullptr);
    std::string p(path), n(netid);
    env->ReleaseStringUTFChars(storagePath,  path);
    env->ReleaseStringUTFChars(networkIdHex, netid);
    uint64_t net_id = ZeroTierNative::ParseNetworkId(n);
    if (net_id == 0) return 2;
    return static_cast<jint>(ZeroTierNative::Init(p, net_id));
}

JNIEXPORT void JNICALL
Java_org_citra_citra_1emu_utils_NetPlayManager_ztShutdown(JNIEnv*, jclass) {
    ZeroTierNative::Shutdown();
}

JNIEXPORT jstring JNICALL
Java_org_citra_citra_1emu_utils_NetPlayManager_ztGetAssignedIP(JNIEnv* env, jclass) {
    return env->NewStringUTF(ZeroTierNative::GetAssignedIP().c_str());
}

JNIEXPORT jboolean JNICALL
Java_org_citra_citra_1emu_utils_NetPlayManager_ztIsReady(JNIEnv*, jclass) {
    return ZeroTierNative::IsReady() ? JNI_TRUE : JNI_FALSE;
}

#ifdef __cplusplus
}
#endif
EOF
success "jni_zt_bridge.cpp dibuat"

# ════════════════════════════════════════════════════════════════════
# LANGKAH 5: Buat ZeroTierManager.kt + ZeroTierDialog.kt
# ════════════════════════════════════════════════════════════════════
info "Langkah 5/7: Buat file Kotlin ZeroTier..."

cat > "$KOTLIN_UTILS/ZeroTierManager.kt" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
package org.citra.citra_emu.utils

import android.content.Context
import android.util.Log
import java.io.File

object ZeroTierManager {
    private const val TAG = "ZeroTierManager"
    private const val PREFS_KEY   = "zerotier_prefs"
    private const val KEY_NETWORK = "zt_network_id"

    enum class State { IDLE, STARTING, READY, ERROR }

    @Volatile var state: State = State.IDLE
        private set

    fun saveNetworkId(context: Context, id: String) =
        context.getSharedPreferences(PREFS_KEY, Context.MODE_PRIVATE)
            .edit().putString(KEY_NETWORK, id).apply()

    fun getNetworkId(context: Context): String =
        context.getSharedPreferences(PREFS_KEY, Context.MODE_PRIVATE)
            .getString(KEY_NETWORK, "") ?: ""

    fun hasNetworkId(context: Context) = getNetworkId(context).length == 16

    fun init(context: Context, networkId: String,
             onReady: (ip: String) -> Unit, onError: (msg: String) -> Unit) {
        if (state == State.READY) { onReady(getAssignedIP()); return }
        if (state == State.STARTING) { onError("Sedang dalam proses inisialisasi"); return }
        state = State.STARTING
        val path = File(context.filesDir, "zt/$networkId").apply { mkdirs() }.absolutePath
        Thread {
            Log.i(TAG, "Init ZeroTier network=$networkId path=$path")
            val code = NetPlayManager.ztInit(path, networkId)
            if (code == 0) {
                val ip = NetPlayManager.ztGetAssignedIP()
                state = State.READY
                Log.i(TAG, "ZeroTier ready IP=$ip")
                onReady(ip)
            } else {
                state = State.ERROR
                val msg = when (code) {
                    1 -> "Sudah berjalan"
                    2 -> "Gagal inisialisasi node"
                    3 -> "Gagal join — periksa Network ID"
                    4 -> "Node belum diauthorize di my.zerotier.com"
                    5 -> "Timeout menunggu node online"
                    else -> "Error tidak diketahui (code $code)"
                }
                Log.e(TAG, "ZeroTier error: $msg")
                onError(msg)
            }
        }.start()
    }

    fun shutdown() {
        if (state == State.IDLE) return
        NetPlayManager.ztShutdown()
        state = State.IDLE
    }

    fun isReady() = state == State.READY
    fun getAssignedIP() = if (isReady()) NetPlayManager.ztGetAssignedIP() else ""
}
EOF

cat > "$KOTLIN_DIALOGS/ZeroTierDialog.kt" << 'EOF'
// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
package org.citra.citra_emu.dialogs

import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.widget.Toast
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import org.citra.citra_emu.R
import org.citra.citra_emu.databinding.DialogZerotierNativeBinding
import org.citra.citra_emu.utils.NetPlayManager
import org.citra.citra_emu.utils.ZeroTierManager

class ZeroTierDialog(context: Context) : BottomSheetDialog(context) {
    private lateinit var binding: DialogZerotierNativeBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        behavior.state = BottomSheetBehavior.STATE_EXPANDED
        behavior.skipCollapsed =
            context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE

        binding = DialogZerotierNativeBinding.inflate(LayoutInflater.from(context))
        setContentView(binding.root)

        ZeroTierManager.getNetworkId(context).let {
            if (it.isNotEmpty()) binding.networkId.setText(it)
        }
        updateStatusUI()

        binding.btnConnect.setOnClickListener {
            val networkId = binding.networkId.text.toString().trim()
            if (networkId.length != 16) {
                binding.networkIdLayout.error = context.getString(R.string.zerotier_network_id_invalid)
                return@setOnClickListener
            }
            binding.networkIdLayout.error = null
            ZeroTierManager.saveNetworkId(context, networkId)
            setLoading(true)
            binding.statusText.text = context.getString(R.string.zerotier_status_starting)

            ZeroTierManager.init(context, networkId,
                onReady = { ip ->
                    binding.root.post {
                        setLoading(false)
                        binding.statusText.text = context.getString(R.string.zerotier_status_ready, ip)
                        binding.assignedIp.text  = ip
                        binding.ipContainer.visibility  = View.VISIBLE
                        binding.btnConnect.text         = context.getString(R.string.zerotier_btn_reconnect)
                        binding.btnCreateRoom.isEnabled = true
                        binding.btnJoinRoom.isEnabled   = true
                        NetPlayManager.setRoomAddress(context, ip)
                    }
                },
                onError = { msg ->
                    binding.root.post {
                        setLoading(false)
                        binding.statusText.text = context.getString(R.string.zerotier_status_error, msg)
                        Toast.makeText(context, msg, Toast.LENGTH_LONG).show()
                    }
                }
            )
        }

        binding.btnDisconnect.setOnClickListener {
            ZeroTierManager.shutdown()
            updateStatusUI()
            binding.ipContainer.visibility  = View.GONE
            binding.btnCreateRoom.isEnabled = false
            binding.btnJoinRoom.isEnabled   = false
            Toast.makeText(context, R.string.zerotier_disconnected, Toast.LENGTH_SHORT).show()
        }

        binding.btnCreateRoom.setOnClickListener {
            if (!ZeroTierManager.isReady()) return@setOnClickListener
            NetPlayManager.setRoomAddress(context, ZeroTierManager.getAssignedIP())
            dismiss()
            NetPlayDialog(context).show()
        }

        binding.btnJoinRoom.setOnClickListener {
            if (!ZeroTierManager.isReady()) return@setOnClickListener
            dismiss()
            NetPlayDialog(context).show()
        }
    }

    private fun setLoading(loading: Boolean) {
        binding.progressBar.visibility  = if (loading) View.VISIBLE else View.GONE
        binding.btnConnect.isEnabled    = !loading
        binding.btnDisconnect.isEnabled = !loading
        binding.networkId.isEnabled     = !loading
    }

    private fun updateStatusUI() {
        when (ZeroTierManager.state) {
            ZeroTierManager.State.IDLE -> {
                binding.statusText.text         = context.getString(R.string.zerotier_status_idle)
                binding.btnCreateRoom.isEnabled = false
                binding.btnJoinRoom.isEnabled   = false
                binding.ipContainer.visibility  = View.GONE
            }
            ZeroTierManager.State.READY -> {
                val ip = ZeroTierManager.getAssignedIP()
                binding.statusText.text         = context.getString(R.string.zerotier_status_ready, ip)
                binding.assignedIp.text         = ip
                binding.ipContainer.visibility  = View.VISIBLE
                binding.btnCreateRoom.isEnabled = true
                binding.btnJoinRoom.isEnabled   = true
            }
            ZeroTierManager.State.ERROR -> {
                binding.statusText.text         = context.getString(R.string.zerotier_status_error_generic)
                binding.btnCreateRoom.isEnabled = false
                binding.btnJoinRoom.isEnabled   = false
            }
            else -> {}
        }
    }
}
EOF
success "ZeroTierManager.kt + ZeroTierDialog.kt dibuat"

# ════════════════════════════════════════════════════════════════════
# LANGKAH 6: Patch file yang sudah ada
# ════════════════════════════════════════════════════════════════════
info "Langkah 6/7: Patch file yang sudah ada..."

# ── 6a. multiplayer.cpp: tambah include + 4 fungsi ZT + shutdown ──
MULTI_CPP="$JNI_DIR/multiplayer.cpp"

# Tambah include ZeroTierNative.h setelah include terakhir
if ! grep -q "ZeroTierNative.h" "$MULTI_CPP"; then
    sed -i 's|#include "core/hle/service/cfg/cfg.h"|#include "core/hle/service/cfg/cfg.h"\n#include "ZeroTierNative.h"|' "$MULTI_CPP"
    success "multiplayer.cpp: tambah #include ZeroTierNative.h"
fi

# Tambah 4 fungsi ZeroTier setelah NetworkInit() — cari fungsi pertama setelah NetworkInit
if ! grep -q "ZeroTierInit" "$MULTI_CPP"; then
    # Cari baris "bool AndroidMultiplayer::NetworkInit()" dan sisipkan fungsi ZT setelah closing brace-nya
    python3 - "$MULTI_CPP" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

zt_functions = '''
// ── ZeroTier entry points ─────────────────────────────────────────
NetPlayStatus AndroidMultiplayer::ZeroTierInit(const std::string& storage_path,
                                               const std::string& network_id_hex) {
    if (ZeroTierNative::IsReady()) return NetPlayStatus::NO_ERROR;
    uint64_t net_id = ZeroTierNative::ParseNetworkId(network_id_hex);
    if (net_id == 0) return NetPlayStatus::NETWORK_ERROR;
    auto result = ZeroTierNative::Init(storage_path, net_id);
    switch (result) {
        case ZeroTierNative::ZTResult::OK:
        case ZeroTierNative::ZTResult::AlreadyRunning: return NetPlayStatus::NO_ERROR;
        case ZeroTierNative::ZTResult::Timeout:
        case ZeroTierNative::ZTResult::NetworkNotReady: return NetPlayStatus::COULD_NOT_CONNECT;
        default: return NetPlayStatus::NETWORK_ERROR;
    }
}
void AndroidMultiplayer::ZeroTierShutdown() { ZeroTierNative::Shutdown(); }
std::string AndroidMultiplayer::ZeroTierGetIP() { return ZeroTierNative::GetAssignedIP(); }
bool AndroidMultiplayer::ZeroTierIsReady() { return ZeroTierNative::IsReady(); }

'''

# Insert setelah penutup fungsi NetworkInit (cari return true;\n})
insert_after = 'return true;\n}\n'
idx = content.find(insert_after)
if idx != -1:
    pos = idx + len(insert_after)
    content = content[:pos] + zt_functions + content[pos:]
    with open(path, 'w') as f:
        f.write(content)
    print("  Fungsi ZeroTier berhasil ditambahkan ke multiplayer.cpp")
else:
    print("  WARN: Tidak bisa menemukan titik insert NetworkInit di multiplayer.cpp")
PYEOF
    success "multiplayer.cpp: tambah 4 fungsi ZeroTier"
fi

# Patch NetworkShutdown() untuk matikan ZT saat shutdown
if ! grep -q "ZeroTierNative::Shutdown" "$MULTI_CPP"; then
    sed -i 's|void AndroidMultiplayer::NetworkShutdown() {\n    Network::Shutdown();|void AndroidMultiplayer::NetworkShutdown() {\n    if (ZeroTierNative::IsReady()) ZeroTierNative::Shutdown();\n    Network::Shutdown();|' "$MULTI_CPP" 2>/dev/null || \
    python3 - "$MULTI_CPP" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()
old = 'void AndroidMultiplayer::NetworkShutdown() {\n    Network::Shutdown();'
new = 'void AndroidMultiplayer::NetworkShutdown() {\n    if (ZeroTierNative::IsReady()) ZeroTierNative::Shutdown();\n    Network::Shutdown();'
if old in content:
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print("  NetworkShutdown patched")
else:
    print("  WARN: Tidak bisa patch NetworkShutdown")
PYEOF
    success "multiplayer.cpp: patch NetworkShutdown"
fi

# ── 6b. NetPlayManager.kt: tambah 4 external fun ZT ──────────────
NETPLAY_MGR=$(find "$PROJECT_ROOT/src" -name "NetPlayManager.kt" | head -1)
if [ -z "$NETPLAY_MGR" ]; then
    warn "NetPlayManager.kt tidak ditemukan, skip"
else
    if ! grep -q "ztInit" "$NETPLAY_MGR"; then
        python3 - "$NETPLAY_MGR" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

zt_jni = '''
        // ── ZeroTier JNI ─────────────────────────────────────────
        @JvmStatic external fun ztInit(storagePath: String, networkIdHex: String): Int
        @JvmStatic external fun ztShutdown()
        @JvmStatic external fun ztGetAssignedIP(): String
        @JvmStatic external fun ztIsReady(): Boolean
'''

# Cari companion object atau object dan sisipkan sebelum closing brace terakhir
# Cari external fun terakhir yang ada lalu tambahkan setelahnya
import re
match = list(re.finditer(r'@JvmStatic external fun \w+[^\n]*\n', content))
if match:
    last = match[-1]
    pos  = last.end()
    content = content[:pos] + zt_jni + content[pos:]
    with open(path, 'w') as f:
        f.write(content)
    print("  4 fungsi ztXxx berhasil ditambahkan ke NetPlayManager.kt")
else:
    print("  WARN: Tidak bisa menemukan titik insert di NetPlayManager.kt")
PYEOF
        success "NetPlayManager.kt: tambah ztInit/ztShutdown/ztGetAssignedIP/ztIsReady"
    else
        warn "NetPlayManager.kt: fungsi zt* sudah ada, skip"
    fi
fi

# ── 6c. NetPlayDialog.kt: tambah import + btnZeroTier + mode ─────
NETPLAY_DLG="$KOTLIN_DIALOGS/NetPlayDialog.kt"
if ! grep -q "ZeroTierManager" "$NETPLAY_DLG"; then
    python3 - "$NETPLAY_DLG" << 'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# 1. Tambah import ZeroTierManager
old_import = 'import org.citra.citra_emu.utils.NetPlayManager'
new_import  = ('import org.citra.citra_emu.utils.NetPlayManager\n'
               'import org.citra.citra_emu.utils.ZeroTierManager')
content = content.replace(old_import, new_import)

# 2. Tambah MultiplayerMode enum setelah deklarasi class
old_class = 'class NetPlayDialog(context: Context) : BottomSheetDialog(context) {'
new_class  = (old_class + '\n\n'
    '    enum class MultiplayerMode { LAN, PUBLIC, ZEROTIER }')
content = content.replace(old_class, new_class)

# 3. Tambah btnZeroTier setelah btnLobbyBrowser block
old_lobby = (
    '                    btnLobbyBrowser.setOnClickListener {\n'
    '                        LobbyBrowser(context).show()\n'
    '                        dismiss()\n'
    '                    }')
new_lobby  = (old_lobby + '\n'
    '\n'
    '                    // Mode 3: ZeroTier\n'
    '                    btnZeroTier.setOnClickListener {\n'
    '                        dismiss()\n'
    '                        if (!ZeroTierManager.isReady()) {\n'
    '                            ZeroTierDialog(context).show()\n'
    '                        } else {\n'
    '                            val ztIp = ZeroTierManager.getAssignedIP()\n'
    '                            android.app.AlertDialog.Builder(context)\n'
    '                                .setTitle("ZeroTier \\u2713 IP: $ztIp")\n'
    '                                .setPositiveButton("Buat Room") { _, _ ->\n'
    '                                    showNetPlayInputDialog(true, MultiplayerMode.ZEROTIER)\n'
    '                                }\n'
    '                                .setNeutralButton("Gabung Room") { _, _ ->\n'
    '                                    showNetPlayInputDialog(false, MultiplayerMode.ZEROTIER)\n'
    '                                }\n'
    '                                .setNegativeButton("Pengaturan ZT") { _, _ ->\n'
    '                                    ZeroTierDialog(context).show()\n'
    '                                }\n'
    '                                .show()\n'
    '                        }\n'
    '                    }\n'
    '                    if (ZeroTierManager.isReady())\n'
    '                        btnZeroTier.text = "ZeroTier \\u2713"')
content = content.replace(old_lobby, new_lobby)

# 4. Ubah signature showNetPlayInputDialog tambah mode parameter
old_sig = 'private fun showNetPlayInputDialog(isCreateRoom: Boolean) {'
new_sig  = ('private fun showNetPlayInputDialog(\n'
    '        isCreateRoom: Boolean,\n'
    '        mode: MultiplayerMode = MultiplayerMode.LAN\n'
    '    ) {')
content = content.replace(old_sig, new_sig)

# 5. Patch pre-fill IP berdasarkan mode
old_ip = (
    '        binding.ipAddress.setText(\n'
    '            if (isCreateRoom) NetPlayManager.getIpAddressByWifi(activity)\n'
    '            else NetPlayManager.getRoomAddress(activity)\n'
    '        )')
new_ip  = (
    '        val prefilledIp = when {\n'
    '            isCreateRoom && mode == MultiplayerMode.ZEROTIER -> ZeroTierManager.getAssignedIP()\n'
    '            isCreateRoom -> NetPlayManager.getIpAddressByWifi(activity)\n'
    '            else         -> NetPlayManager.getRoomAddress(activity)\n'
    '        }\n'
    '        binding.ipAddress.setText(prefilledIp)')
content = content.replace(old_ip, new_ip)

with open(path, 'w') as f:
    f.write(content)
print("  NetPlayDialog.kt berhasil di-patch untuk ZeroTier")
PYEOF
    success "NetPlayDialog.kt: tambah ZeroTier mode"
else
    warn "NetPlayDialog.kt: ZeroTierManager sudah ada, skip"
fi

# ── 6d. dialog_multiplayer_connect.xml: tambah btnZeroTier ───────
CONNECT_XML="$LAYOUT_DIR/dialog_multiplayer_connect.xml"
if [ -f "$CONNECT_XML" ] && ! grep -q "btnZeroTier" "$CONNECT_XML"; then
    python3 - "$CONNECT_XML" << 'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

btn_zt = '''
    <com.google.android.material.button.MaterialButton
        android:id="@+id/btnZeroTier"
        style="@style/Widget.Material3.Button.OutlinedButton"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginStart="16dp"
        android:layout_marginEnd="16dp"
        android:layout_marginBottom="8dp"
        android:text="@string/zerotier_button_label"
        app:icon="@drawable/ic_public"
        app:iconGravity="textStart" />

'''

# Sisipkan sebelum tag penutup LinearLayout/ConstraintLayout terakhir
last_tag = content.rfind('</LinearLayout>')
if last_tag == -1:
    last_tag = content.rfind('</ConstraintLayout>')
if last_tag != -1:
    content = content[:last_tag] + btn_zt + content[last_tag:]
    with open(path, 'w') as f:
        f.write(content)
    print("  btnZeroTier ditambahkan ke dialog_multiplayer_connect.xml")
else:
    print("  WARN: Tidak bisa menemukan closing tag di dialog_multiplayer_connect.xml")
PYEOF
    success "dialog_multiplayer_connect.xml: tambah btnZeroTier"
else
    warn "dialog_multiplayer_connect.xml: btnZeroTier sudah ada atau file tidak ditemukan"
fi

# ── 6e. strings.xml: tambah string ZeroTier ──────────────────────
STRINGS_XML="$VALUES_DIR/strings.xml"
if [ -f "$STRINGS_XML" ] && ! grep -q "zerotier_button_label" "$STRINGS_XML"; then
    sed -i 's|</resources>|    <!-- ZeroTier -->\n    <string name="zerotier_button_label">ZeroTier</string>\n    <string name="zerotier_network_id_hint">Network ID (16 karakter)</string>\n    <string name="zerotier_network_id_invalid">Network ID harus 16 karakter</string>\n    <string name="zerotier_status_idle">Tidak terhubung. Masukkan Network ID.</string>\n    <string name="zerotier_status_starting">Memulai tunnel ZeroTier\u2026</string>\n    <string name="zerotier_status_ready">Terhubung \u2713  IP: %s</string>\n    <string name="zerotier_status_error">Error: %s</string>\n    <string name="zerotier_status_error_generic">Gagal terhubung. Coba lagi.</string>\n    <string name="zerotier_network_id_helper">Network ID dari my.zerotier.com \u2192 Networks</string>\n    <string name="zerotier_btn_connect">Hubungkan</string>\n    <string name="zerotier_btn_reconnect">Hubungkan Ulang</string>\n    <string name="zerotier_btn_disconnect">Putuskan</string>\n    <string name="zerotier_disconnected">ZeroTier diputus</string>\n</resources>|' "$STRINGS_XML"
    success "strings.xml: tambah string ZeroTier"
else
    warn "strings.xml: string ZeroTier sudah ada atau file tidak ditemukan"
fi

# ════════════════════════════════════════════════════════════════════
# LANGKAH 7: Buat layout dialog_zerotier_native.xml
# ════════════════════════════════════════════════════════════════════
info "Langkah 7/7: Buat dialog_zerotier_native.xml..."

cat > "$LAYOUT_DIR/dialog_zerotier_native.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="wrap_content">
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:padding="16dp">

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="ZeroTier"
            android:textAppearance="@style/TextAppearance.Material3.TitleLarge"
            android:layout_marginBottom="4dp" />
        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="Tanpa aplikasi tambahan"
            android:textAppearance="@style/TextAppearance.Material3.BodySmall"
            android:textColor="?attr/colorOnSurfaceVariant"
            android:layout_marginBottom="16dp" />

        <com.google.android.material.card.MaterialCardView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="12dp"
            app:cardElevation="0dp"
            app:strokeWidth="1dp"
            app:strokeColor="?attr/colorOutline"
            app:cardBackgroundColor="?attr/colorSurfaceVariant">
            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="vertical"
                android:padding="12dp">
                <TextView
                    android:id="@+id/statusText"
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    android:text="@string/zerotier_status_idle"
                    android:textAppearance="@style/TextAppearance.Material3.BodyMedium" />
                <LinearLayout
                    android:id="@+id/ipContainer"
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    android:orientation="horizontal"
                    android:layout_marginTop="6dp"
                    android:visibility="gone">
                    <TextView
                        android:layout_width="wrap_content"
                        android:layout_height="wrap_content"
                        android:text="IP: "
                        android:textAppearance="@style/TextAppearance.Material3.BodySmall" />
                    <TextView
                        android:id="@+id/assignedIp"
                        android:layout_width="wrap_content"
                        android:layout_height="wrap_content"
                        android:fontFamily="monospace"
                        android:textColor="?attr/colorPrimary"
                        android:textAppearance="@style/TextAppearance.Material3.BodyMedium" />
                </LinearLayout>
            </LinearLayout>
        </com.google.android.material.card.MaterialCardView>

        <ProgressBar
            android:id="@+id/progressBar"
            style="@style/Widget.Material3.LinearProgressIndicator"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="12dp"
            android:visibility="gone" />

        <com.google.android.material.textfield.TextInputLayout
            android:id="@+id/networkIdLayout"
            style="@style/Widget.Material3.TextInputLayout.OutlinedBox"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="4dp"
            android:hint="@string/zerotier_network_id_hint"
            app:counterEnabled="true"
            app:counterMaxLength="16">
            <com.google.android.material.textfield.TextInputEditText
                android:id="@+id/networkId"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:inputType="textNoSuggestions"
                android:maxLength="16"
                android:fontFamily="monospace" />
        </com.google.android.material.textfield.TextInputLayout>

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/zerotier_network_id_helper"
            android:textAppearance="@style/TextAppearance.Material3.BodySmall"
            android:textColor="?attr/colorOnSurfaceVariant"
            android:layout_marginStart="4dp"
            android:layout_marginBottom="16dp" />

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:layout_marginBottom="12dp">
            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnConnect"
                style="@style/Widget.Material3.Button"
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:layout_weight="1"
                android:layout_marginEnd="8dp"
                android:text="@string/zerotier_btn_connect" />
            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnDisconnect"
                style="@style/Widget.Material3.Button.OutlinedButton"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:text="@string/zerotier_btn_disconnect" />
        </LinearLayout>

        <com.google.android.material.divider.MaterialDivider
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="12dp" />

        <com.google.android.material.button.MaterialButton
            android:id="@+id/btnCreateRoom"
            style="@style/Widget.Material3.Button.TonalButton"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="8dp"
            android:enabled="false"
            android:text="@string/multiplayer_create_room" />

        <com.google.android.material.button.MaterialButton
            android:id="@+id/btnJoinRoom"
            style="@style/Widget.Material3.Button.OutlinedButton"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="8dp"
            android:enabled="false"
            android:text="@string/multiplayer_join_room" />

    </LinearLayout>
</ScrollView>
EOF
success "dialog_zerotier_native.xml dibuat"

# ════════════════════════════════════════════════════════════════════
# SELESAI
# ════════════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════"
echo -e "${GREEN}  Patch ZeroTier selesai!${NC}"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "File baru yang dibuat:"
echo "  + $JNI_DIR/ZeroTierNative.h"
echo "  + $JNI_DIR/ZeroTierNative.cpp"
echo "  + $JNI_DIR/jni_zt_bridge.cpp"
echo "  + $KOTLIN_UTILS/ZeroTierManager.kt"
echo "  + $KOTLIN_DIALOGS/ZeroTierDialog.kt"
echo "  + $LAYOUT_DIR/dialog_zerotier_native.xml"
echo ""
echo "File yang di-patch:"
echo "  ~ $JNI_DIR/multiplayer.cpp"
echo "  ~ NetPlayManager.kt"
echo "  ~ NetPlayDialog.kt"
echo "  ~ dialog_multiplayer_connect.xml"
echo "  ~ strings.xml"
echo ""
echo "Langkah selanjutnya:"
echo "  1. Patch CMakeLists.txt — tambah libzt (lihat CMakeLists_libzt_patch.txt)"
echo "  2. ./gradlew assembleDebug"
echo ""
