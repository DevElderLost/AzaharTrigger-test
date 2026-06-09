#!/bin/bash
# =============================================================================
# fix_multiplayer_memleak_disconnect.sh
# Fix memory leak dan disconnect bug di sistem multiplayer AzaharTrigger-test
#
# Bug yang diperbaiki:
#  [1+6] MEMORY LEAK: CallbackHandle tidak disimpan → callbacks tidak bisa Unbind
#  [2]   MEMORY LEAK: send_list tidak di-clear saat Leave()
#  [3]   DISCONNECT CRASH: Leave() tidak cek joinable() → UB jika thread sudah selesai
#  [4]   DISCONNECT LAG: Disconnect() re-disconnect peer yang sudah disconnected → stall 5s
#  [5]   DISCONNECT CRASH: NetPlayCreateRoom cleanup member sebelum room->Destroy()
#  [7]   DISCONNECT LAG→DC: send_list unbounded → burst saat lag → server timeout
#  [8]   MEMORY LEAK: announce_multiplayer_session tidak di-cleanup di TryShutdown
#  [+]   NetPlayLeaveRoom: guard IsConnected() + MelonLAN cleanup
# =============================================================================

set -euo pipefail

REPO="${1:-.}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err_exit() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

find_file() {
    find "$REPO" -type f -name "$1" ! -path "*/build/*" ! -path "*/.git/*" 2>/dev/null | head -1
}

MULTIPLAYER_H=$(find_file "multiplayer.h")
MULTIPLAYER_CPP=$(find_file "multiplayer.cpp")
ROOM_MEMBER_CPP=$(find_file "room_member.cpp")
NATIVE_CPP=$(find_file "native.cpp")

[[ -z "$MULTIPLAYER_H"   ]] && err_exit "multiplayer.h tidak ditemukan"
[[ -z "$MULTIPLAYER_CPP" ]] && err_exit "multiplayer.cpp tidak ditemukan"
[[ -z "$ROOM_MEMBER_CPP" ]] && err_exit "room_member.cpp tidak ditemukan"
[[ -z "$NATIVE_CPP"      ]] && err_exit "native.cpp tidak ditemukan"

info "File target:"
info "  multiplayer.h   → $MULTIPLAYER_H"
info "  multiplayer.cpp → $MULTIPLAYER_CPP"
info "  room_member.cpp → $ROOM_MEMBER_CPP"
info "  native.cpp      → $NATIVE_CPP"

BACKUP_DIR="$REPO/.multiplayer_fix_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp "$MULTIPLAYER_H" "$MULTIPLAYER_CPP" "$ROOM_MEMBER_CPP" "$NATIVE_CPP" "$BACKUP_DIR/"
ok "Backup tersimpan di: $BACKUP_DIR"

PATCH_OLD=$(mktemp); PATCH_NEW=$(mktemp)
ERRORS=0
trap 'rm -f "$PATCH_OLD" "$PATCH_NEW"' EXIT

apply_patch() {
    local file="$1" desc="$2"
    # $PATCH_OLD dan $PATCH_NEW sudah ditulis sebelum pemanggilan
    if python3 - "$file" "$PATCH_OLD" "$PATCH_NEW" << 'PYEOF'
import sys
path, old_f, new_f = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, 'r') as f: content = f.read()
with open(old_f, 'r') as f: old = f.read()
with open(new_f, 'r') as f: new = f.read()
if old not in content:
    sys.exit(1)
content = content.replace(old, new, 1)
with open(path, 'w') as f: f.write(content)
PYEOF
    then
        ok "  ✓ $desc"
    else
        warn "  ⚠ SKIP (pattern tidak cocok): $desc"
        ERRORS=$((ERRORS+1))
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "FIX [1+6] multiplayer.h — tambah include + simpan CallbackHandle fields"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cat > "$PATCH_OLD" << 'OLD'
#include <memory>
#include <string>
#include <vector>
OLD
cat > "$PATCH_NEW" << 'NEW'
#include <functional>
#include <memory>
#include <string>
#include <vector>
NEW
apply_patch "$MULTIPLAYER_H" "multiplayer.h: tambah #include <functional>"

cat > "$PATCH_OLD" << 'OLD'
    void NetPlayUnbanUser(const std::string& username);

    std::vector<std::string> NetPlayGetPublicRooms();
OLD
cat > "$PATCH_NEW" << 'NEW'
    void NetPlayUnbanUser(const std::string& username);

    std::vector<std::string> NetPlayGetPublicRooms();

    // Unbind semua callbacks (panggil sebelum destroy)
    void UnbindCallbacks();
NEW
apply_patch "$MULTIPLAYER_H" "multiplayer.h: deklarasi UnbindCallbacks()"

cat > "$PATCH_OLD" << 'OLD'
private:
    Core::System& system;
    static std::unique_ptr<Network::VerifyUser::Backend> CreateVerifyBackend(bool use_validation);
    std::weak_ptr<Network::AnnounceMultiplayerSession> announce_multiplayer_session;
    std::unique_ptr<Network::MelonLANAdapter> melon_lan_adapter;
OLD
cat > "$PATCH_NEW" << 'NEW'
private:
    Core::System& system;
    static std::unique_ptr<Network::VerifyUser::Backend> CreateVerifyBackend(bool use_validation);
    std::weak_ptr<Network::AnnounceMultiplayerSession> announce_multiplayer_session;
    std::unique_ptr<Network::MelonLANAdapter> melon_lan_adapter;

    // FIX [1+6]: Simpan callback handles agar bisa di-Unbind untuk cegah memory leak.
    // Tanpa ini, lambda menyimpan `this` selamanya dan tidak bisa dibersihkan.
    Network::RoomMember::CallbackHandle<Network::RoomMember::State>  cb_state;
    Network::RoomMember::CallbackHandle<Network::RoomMember::Error>  cb_error;
    Network::RoomMember::CallbackHandle<Network::StatusMessageEntry> cb_status;
    Network::RoomMember::CallbackHandle<Network::ChatEntry>          cb_chat;
NEW
apply_patch "$MULTIPLAYER_H" "multiplayer.h: tambah cb_state/error/status/chat fields"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "FIX [1+6] multiplayer.cpp — destructor cleanup + UnbindCallbacks() + NetworkInit"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cat > "$PATCH_OLD" << 'OLD'
AndroidMultiplayer::~AndroidMultiplayer() {
    if (melon_lan_adapter) {
        melon_lan_adapter->Shutdown();
    }
}
OLD
cat > "$PATCH_NEW" << 'NEW'
AndroidMultiplayer::~AndroidMultiplayer() {
    // FIX [1+6]: Unbind semua callbacks sebelum destroy agar tidak ada dangling `this`
    UnbindCallbacks();
    if (melon_lan_adapter) {
        melon_lan_adapter->Shutdown();
    }
}

void AndroidMultiplayer::UnbindCallbacks() {
    if (auto member = Network::GetRoomMember().lock()) {
        if (cb_state)  { member->Unbind(cb_state);  cb_state  = nullptr; }
        if (cb_error)  { member->Unbind(cb_error);  cb_error  = nullptr; }
        if (cb_status) { member->Unbind(cb_status); cb_status = nullptr; }
        if (cb_chat)   { member->Unbind(cb_chat);   cb_chat   = nullptr; }
    } else {
        // RoomMember sudah destroyed, cukup clear handle
        cb_state = cb_error = cb_status = cb_chat = nullptr;
    }
}
NEW
apply_patch "$MULTIPLAYER_CPP" "multiplayer.cpp: destructor Unbind + implementasi UnbindCallbacks()"

cat > "$PATCH_OLD" << 'OLD'
    if (auto member = Network::GetRoomMember().lock()) {
        // register the network structs to use in slots and signals
        member->BindOnStateChanged([this](const Network::RoomMember::State& state) {
OLD
cat > "$PATCH_NEW" << 'NEW'
    if (auto member = Network::GetRoomMember().lock()) {
        // Bersihkan callback lama sebelum register baru (cegah double-bind)
        UnbindCallbacks();

        // register the network structs to use in slots and signals
        cb_state = member->BindOnStateChanged([this](const Network::RoomMember::State& state) {
NEW
apply_patch "$MULTIPLAYER_CPP" "NetworkInit: UnbindCallbacks() sebelum Bind + simpan cb_state"

cat > "$PATCH_OLD" << 'OLD'
        member->BindOnError([this](const Network::RoomMember::Error& error) {
OLD
cat > "$PATCH_NEW" << 'NEW'
        cb_error = member->BindOnError([this](const Network::RoomMember::Error& error) {
NEW
apply_patch "$MULTIPLAYER_CPP" "NetworkInit: simpan cb_error"

cat > "$PATCH_OLD" << 'OLD'
        member->BindOnStatusMessageReceived(
            [this](const Network::StatusMessageEntry& status_message) {
OLD
cat > "$PATCH_NEW" << 'NEW'
        cb_status = member->BindOnStatusMessageReceived(
            [this](const Network::StatusMessageEntry& status_message) {
NEW
apply_patch "$MULTIPLAYER_CPP" "NetworkInit: simpan cb_status"

cat > "$PATCH_OLD" << 'OLD'
        member->BindOnChatMessageRecieved([this](const Network::ChatEntry& chat) {
OLD
cat > "$PATCH_NEW" << 'NEW'
        cb_chat = member->BindOnChatMessageRecieved([this](const Network::ChatEntry& chat) {
NEW
apply_patch "$MULTIPLAYER_CPP" "NetworkInit: simpan cb_chat"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "FIX [2+3] room_member.cpp — Leave(): joinable check + clear send_list"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cat > "$PATCH_OLD" << 'OLD'
void RoomMember::Leave() {
    room_member_impl->SetState(State::Idle);
    room_member_impl->loop_thread->join();
    room_member_impl->loop_thread.reset();

    enet_host_destroy(room_member_impl->client);
    room_member_impl->client = nullptr;
}
OLD
cat > "$PATCH_NEW" << 'NEW'
void RoomMember::Leave() {
    // Set Idle agar MemberLoop bisa exit dengan benar
    room_member_impl->SetState(State::Idle);

    // FIX [3]: Cek joinable() sebelum join().
    // Jika koneksi putus dari sisi server, MemberLoop bisa selesai sendiri
    // sebelum Leave() dipanggil dari Java. Memanggil join() pada thread yang
    // sudah selesai (joinable=false) adalah undefined behavior.
    if (room_member_impl->loop_thread && room_member_impl->loop_thread->joinable()) {
        room_member_impl->loop_thread->join();
    }
    room_member_impl->loop_thread.reset();

    // FIX [2]: Bersihkan send_list agar tidak ada packet yang bocor di heap.
    // Bisa terjadi burst packets sesaat sebelum disconnect yang tidak sempat terkirim.
    {
        std::lock_guard<std::mutex> lock(room_member_impl->send_list_mutex);
        room_member_impl->send_list.clear();
    }

    // Guard: client bisa nullptr jika Join() gagal di tengah jalan
    if (room_member_impl->client) {
        enet_host_destroy(room_member_impl->client);
        room_member_impl->client = nullptr;
    }
}
NEW
apply_patch "$ROOM_MEMBER_CPP" "room_member.cpp Leave(): joinable check + clear send_list + null guard"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "FIX [4] room_member.cpp — Disconnect(): skip re-disconnect peer yang sudah down"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cat > "$PATCH_OLD" << 'OLD'
void RoomMember::RoomMemberImpl::Disconnect() {
    member_information.clear();
    room_information.member_slots = 0;
    room_information.name.clear();

    if (!server)
        return;
    enet_peer_disconnect(server, 0);

    ENetEvent event;
    while (enet_host_service(client, &event, ConnectionTimeoutMs) > 0) {
        switch (event.type) {
        case ENET_EVENT_TYPE_RECEIVE:
            enet_packet_destroy(event.packet); // Ignore all incoming data
            break;
        case ENET_EVENT_TYPE_DISCONNECT:
            server = nullptr;
            return;
        case ENET_EVENT_TYPE_NONE:
        case ENET_EVENT_TYPE_CONNECT:
            break;
        }
    }
    // didn't disconnect gracefully force disconnect
    enet_peer_reset(server);
    server = nullptr;
}
OLD
cat > "$PATCH_NEW" << 'NEW'
void RoomMember::RoomMemberImpl::Disconnect() {
    member_information.clear();
    room_information.member_slots = 0;
    room_information.name.clear();

    if (!server)
        return;

    // FIX [4]: Jika peer sudah disconnect dari sisi remote (ENET_PEER_STATE_DISCONNECTED
    // atau ZOMBIE), JANGAN panggil enet_peer_disconnect() lagi. Tanpa fix ini,
    // enet_host_service akan menunggu hingga ConnectionTimeoutMs (5000ms) sia-sia,
    // yang terasa sebagai LAG/freeze ~5 detik setiap kali koneksi terputus tiba-tiba.
    if (server->state == ENET_PEER_STATE_DISCONNECTED ||
        server->state == ENET_PEER_STATE_ZOMBIE) {
        enet_peer_reset(server);
        server = nullptr;
        return;
    }

    enet_peer_disconnect(server, 0);

    // Gunakan timeout lebih pendek (1000ms) — cukup untuk graceful disconnect
    // tanpa menyebabkan freeze panjang jika server tidak merespons
    constexpr u32 GracefulDisconnectTimeoutMs = 1000;
    ENetEvent event;
    while (enet_host_service(client, &event, GracefulDisconnectTimeoutMs) > 0) {
        switch (event.type) {
        case ENET_EVENT_TYPE_RECEIVE:
            enet_packet_destroy(event.packet); // Buang semua incoming data
            break;
        case ENET_EVENT_TYPE_DISCONNECT:
            server = nullptr;
            return;
        case ENET_EVENT_TYPE_NONE:
        case ENET_EVENT_TYPE_CONNECT:
            break;
        }
    }
    // Graceful disconnect tidak berhasil, force reset
    enet_peer_reset(server);
    server = nullptr;
}
NEW
apply_patch "$ROOM_MEMBER_CPP" "room_member.cpp Disconnect(): skip re-disconnect + timeout 1000ms"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "FIX [7] room_member.cpp — Send(): batasi send_list agar tidak OOM saat lag"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cat > "$PATCH_OLD" << 'OLD'
void RoomMember::RoomMemberImpl::Send(Packet&& packet) {
    std::lock_guard lock(send_list_mutex);
    send_list.push_back(std::move(packet));
}
OLD
cat > "$PATCH_NEW" << 'NEW'
// FIX [7]: Batas maksimum packet di send_list.
// Skenario: Android lag/low-memory → emulator melambat → MemberLoop jarang jalan
// → send_list terakumulasi (unbounded) → burst besar saat akhirnya diproses
// → server-side ENet timeout → server disconnect client → LostConnection.
// Dengan batas ini, packet lama di-drop (WiFi packet lama tidak relevan lagi),
// lebih baik dari OOM atau disconnect total.
constexpr std::size_t MaxSendListSize = 64;

void RoomMember::RoomMemberImpl::Send(Packet&& packet) {
    std::lock_guard lock(send_list_mutex);
    if (send_list.size() >= MaxSendListSize) {
        // Drop packet TERTUA (head), bukan yang baru — packet terbaru lebih relevan
        LOG_WARNING(Network,
            "send_list overflow ({} packets), drop packet tertua untuk cegah memory bloat",
            send_list.size());
        send_list.pop_front();
    }
    send_list.push_back(std::move(packet));
}
NEW
apply_patch "$ROOM_MEMBER_CPP" "room_member.cpp Send(): MaxSendListSize=64 + drop oldest on overflow"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "FIX [5] multiplayer.cpp — NetPlayCreateRoom: Leave() sebelum Destroy()"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cat > "$PATCH_OLD" << 'OLD'
    // If join failed while room is created, clean up the room
    room->Destroy();
    return NetPlayStatus::CREATE_ROOM_ERROR;
OLD
cat > "$PATCH_NEW" << 'NEW'
    // FIX [5]: Join timeout — member loop_thread sudah berjalan tapi join gagal.
    // HARUS stop member thread dulu sebelum Destroy() room, jika tidak ada
    // race condition antara member thread (masih sending) dan room yang di-destroy.
    if (auto member_cleanup = Network::GetRoomMember().lock()) {
        member_cleanup->Leave();
    }
    room->Destroy();
    return NetPlayStatus::CREATE_ROOM_ERROR;
NEW
apply_patch "$MULTIPLAYER_CPP" "multiplayer.cpp NetPlayCreateRoom: Leave() sebelum Destroy() room"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "FIX [+] multiplayer.cpp — NetPlayLeaveRoom: guard IsConnected() + MelonLAN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cat > "$PATCH_OLD" << 'OLD'
void AndroidMultiplayer::NetPlayLeaveRoom() {
    if (auto room = Network::GetRoom().lock()) {
        // if you are in a room, leave it
        if (auto member = Network::GetRoomMember().lock()) {
            member->Leave();
        }

        ClearChat();

        // if you are hosting a room, also stop hosting
        if (room->GetState() == Network::Room::State::Open) {
            room->Destroy();
        }
    }
}
OLD
cat > "$PATCH_NEW" << 'NEW'
void AndroidMultiplayer::NetPlayLeaveRoom() {
    // Hentikan MelonLAN session jika aktif (cegah thread leak di LAN mode)
    if (melon_lan_adapter && melon_lan_adapter->IsActive()) {
        melon_lan_adapter->EndSession();
    }

    if (auto room = Network::GetRoom().lock()) {
        // FIX [+]: Cek IsConnected() sebelum Leave() untuk mencegah Leave()
        // dipanggil dua kali (sekali dari error callback, sekali dari Java).
        // Double-Leave() menyebabkan join() pada thread yang sudah selesai → crash.
        if (auto member = Network::GetRoomMember().lock()) {
            if (member->IsConnected()) {
                member->Leave();
            } else if (member->GetState() == Network::RoomMember::State::Joining) {
                // Jika masih di tengah join, tetap perlu cleanup thread
                member->Leave();
            }
        }

        ClearChat();

        // Hancurkan room jika kita yang hosting
        if (room->GetState() == Network::Room::State::Open) {
            room->Destroy();
        }
    }
}
NEW
apply_patch "$MULTIPLAYER_CPP" "multiplayer.cpp NetPlayLeaveRoom: guard IsConnected + MelonLAN cleanup"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "FIX [8] native.cpp — TryShutdown: cleanup multiplayer + announce_session"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cat > "$PATCH_OLD" << 'OLD'
    window.reset();
    if (secondary_window) {
        secondary_window.reset();
    }

    InputManager::Shutdown();
    MicroProfileShutdown();
}
OLD
cat > "$PATCH_NEW" << 'NEW'
    window.reset();
    if (secondary_window) {
        secondary_window.reset();
    }

    // FIX [8]: Cleanup multiplayer sebelum shutdown.
    // announce_multiplayer_session di-reset SETELAH multiplayer di-destroy
    // agar weak_ptr di dalam AndroidMultiplayer tidak menjadi dangling.
    if (multiplayer) {
        if (multiplayer->NetPlayIsJoined() || multiplayer->NetPlayIsHostedRoom()) {
            multiplayer->NetPlayLeaveRoom();
        }
        // Unbind semua callbacks sebelum destroy untuk cegah dangling `this`
        multiplayer->UnbindCallbacks();
        multiplayer.reset();
    }
    // Shutdown ENet layer setelah multiplayer object destroyed
    AndroidMultiplayer::NetworkShutdown();
    // Reset session shared_ptr — sekarang aman karena multiplayer sudah destroyed
    announce_multiplayer_session.reset();

    InputManager::Shutdown();
    MicroProfileShutdown();
}
NEW
apply_patch "$NATIVE_CPP" "native.cpp TryShutdown: multiplayer + announce_session cleanup"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "FIX [8] native.cpp — initMultiplayer: NetworkShutdown sebelum reinit + error guard"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cat > "$PATCH_OLD" << 'OLD'
// init multiplayer class
JNIEXPORT void JNICALL
Java_org_citra_citra_1emu_NativeLibrary_initMultiplayer(JNIEnv* env, [[maybe_unused]] jobject obj) {
    if (multiplayer) {
        return;
    }

    announce_multiplayer_session = std::make_shared<Network::AnnounceMultiplayerSession>();

    multiplayer = std::make_unique<AndroidMultiplayer>(Core::System::GetInstance(),
                                                       announce_multiplayer_session);
    multiplayer->NetworkInit();
}
OLD
cat > "$PATCH_NEW" << 'NEW'
// init multiplayer class
JNIEXPORT void JNICALL
Java_org_citra_citra_1emu_NativeLibrary_initMultiplayer(JNIEnv* env, [[maybe_unused]] jobject obj) {
    if (multiplayer) {
        // Sudah diinit, jangan re-init: NetworkInit() mendaftarkan callbacks,
        // double-register tanpa Unbind dulu = memory leak callbacks.
        return;
    }

    // FIX [8]: Pastikan ENet layer bersih sebelum init ulang
    // (aman dipanggil meski belum pernah Init sebelumnya)
    AndroidMultiplayer::NetworkShutdown();

    announce_multiplayer_session = std::make_shared<Network::AnnounceMultiplayerSession>();
    multiplayer = std::make_unique<AndroidMultiplayer>(Core::System::GetInstance(),
                                                       announce_multiplayer_session);

    if (!multiplayer->NetworkInit()) {
        LOG_ERROR(Frontend, "initMultiplayer: NetworkInit() gagal, cleanup resources");
        multiplayer.reset();
        announce_multiplayer_session.reset();
    }
}
NEW
apply_patch "$NATIVE_CPP" "native.cpp initMultiplayer: NetworkShutdown dulu + guard NetworkInit gagal"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ $ERRORS -gt 0 ]]; then
    warn "$ERRORS patch SKIP karena pattern tidak cocok (mungkin sudah dimodifikasi)."
    warn "Cek diff manual:"
    for f in multiplayer.h multiplayer.cpp room_member.cpp native.cpp; do
        warn "  diff $BACKUP_DIR/$f <file_terbaru>"
    done
    echo ""
fi

ok "Selesai! Ringkasan fix yang diterapkan:"
echo ""
echo "  File: multiplayer.h"
echo "    [1+6] Tambah #include <functional>"
echo "    [1+6] Deklarasi UnbindCallbacks() + cb_state/error/status/chat fields"
echo ""
echo "  File: multiplayer.cpp"
echo "    [1+6] Destructor memanggil UnbindCallbacks()"
echo "    [1+6] Implementasi UnbindCallbacks()"
echo "    [1+6] NetworkInit() simpan cb_state/error/status/chat + UnbindCallbacks dulu"
echo "    [5]   NetPlayCreateRoom: Leave() member sebelum room->Destroy()"
echo "    [+]   NetPlayLeaveRoom: guard IsConnected() + MelonLAN EndSession()"
echo ""
echo "  File: room_member.cpp"
echo "    [2]   Leave(): clear send_list setelah thread join"
echo "    [3]   Leave(): cek joinable() sebelum join()"
echo "    [4]   Disconnect(): skip re-disconnect peer DISCONNECTED/ZOMBIE + timeout 1s"
echo "    [7]   Send(): MaxSendListSize=64, drop oldest on overflow"
echo ""
echo "  File: native.cpp"
echo "    [8]   TryShutdown(): cleanup multiplayer → NetworkShutdown → reset session"
echo "    [8]   initMultiplayer(): NetworkShutdown sebelum reinit + guard NetworkInit gagal"
echo ""
echo "  Backup: $BACKUP_DIR"
