#!/usr/bin/env bash
# =============================================================================
# fix_multiplayer_bugs.sh
# Perbaikan: Memory Leak + Disconnect pada Multiplayer (LAN & Public Room)
# Bug yang diperbaiki:
#   [1] multiplayer/announce_session tidak pernah di-destroy (native.cpp)
#   [2] Callbacks tidak di-Unbind + Invoke copy set (multiplayer.h + .cpp)
#   [3] network_mutex dipegang terlalu lama di MemberLoop (room_member.cpp)
#   [4] send_list tidak dibatasi ukurannya (room_member.cpp)
#   [5] members.size() dibaca di luar lock di BroadcastRoomInformation (room.cpp)
#   [6] Double enet_peer_disconnect di HandleClientDisconnection (room.cpp)
#   [7] NetPlayJoinRoom tidak cleanup saat timeout (multiplayer.cpp)
# =============================================================================

set -e

# ──────────────────────────────────────────────────────────────────────────────
# WARNA & HELPER
# ──────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; }
step()    { echo -e "\n${CYAN}════════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}════════════════════════════════════════${NC}"; }

# ──────────────────────────────────────────────────────────────────────────────
# FASE 0 — PENCARIAN FILE OTOMATIS
# Cari file berdasarkan konten unik, bukan path hardcode.
# ──────────────────────────────────────────────────────────────────────────────
step "FASE 0: Mencari lokasi file yang relevan..."

SEARCH_ROOT="${1:-$(pwd)}"
info "Root pencarian: $SEARCH_ROOT"

find_file() {
    local label="$1"
    local pattern="$2"          # grep pattern unik untuk identifikasi konten
    local filename_hint="$3"    # nama file yang diharapkan (untuk filter)

    local result
    result=$(grep -rl "$pattern" "$SEARCH_ROOT" 2>/dev/null \
        | grep -E "(^|/)${filename_hint}$" \
        | head -1)

    if [ -z "$result" ]; then
        # Fallback: cari tanpa filter nama file
        result=$(grep -rl "$pattern" "$SEARCH_ROOT" 2>/dev/null | head -1)
    fi

    if [ -z "$result" ]; then
        error "Tidak ditemukan: $label (pattern: '$pattern')"
        return 1
    fi

    echo "$result"
}

# Cari setiap file berdasarkan signature konten yang unik
FILE_NATIVE=$(find_file "native.cpp" \
    "Java_org_citra_citra_1emu_NativeLibrary_initMultiplayer" \
    "native.cpp") || { error "native.cpp tidak ditemukan. Pastikan repo sudah di-clone."; exit 1; }

FILE_MULTIPLAYER_CPP=$(find_file "multiplayer.cpp" \
    "AndroidMultiplayer::NetworkInit" \
    "multiplayer.cpp") || { error "multiplayer.cpp tidak ditemukan."; exit 1; }

FILE_MULTIPLAYER_H=$(find_file "multiplayer.h" \
    "class AndroidMultiplayer" \
    "multiplayer.h") || { error "multiplayer.h tidak ditemukan."; exit 1; }

FILE_ROOM_MEMBER=$(find_file "room_member.cpp" \
    "RoomMember::RoomMemberImpl::MemberLoop" \
    "room_member.cpp") || { error "room_member.cpp tidak ditemukan."; exit 1; }

FILE_ROOM=$(find_file "room.cpp" \
    "Room::RoomImpl::BroadcastRoomInformation" \
    "room.cpp") || { error "room.cpp tidak ditemukan."; exit 1; }

echo ""
success "File ditemukan:"
echo "  native.cpp        → $FILE_NATIVE"
echo "  multiplayer.cpp   → $FILE_MULTIPLAYER_CPP"
echo "  multiplayer.h     → $FILE_MULTIPLAYER_H"
echo "  room_member.cpp   → $FILE_ROOM_MEMBER"
echo "  room.cpp          → $FILE_ROOM"

# ──────────────────────────────────────────────────────────────────────────────
# FASE 1 — VALIDASI: Pastikan patch belum pernah diterapkan
# ──────────────────────────────────────────────────────────────────────────────
step "FASE 1: Validasi (cek apakah patch sudah diterapkan)..."

check_already_patched() {
    local file="$1"
    local marker="$2"
    local label="$3"
    if grep -q "$marker" "$file" 2>/dev/null; then
        warn "$label sudah diterapkan sebelumnya — dilewati."
        return 0  # sudah
    fi
    return 1  # belum
}

PATCH1_DONE=0; PATCH2_DONE=0; PATCH3_DONE=0
PATCH4_DONE=0; PATCH5_DONE=0; PATCH6_DONE=0; PATCH7_DONE=0

check_already_patched "$FILE_NATIVE" \
    "shutdownMultiplayer" "Bug#1 (shutdownMultiplayer)" && PATCH1_DONE=1

check_already_patched "$FILE_MULTIPLAYER_H" \
    "cb_state_handle" "Bug#2 (callback handles)" && PATCH2_DONE=1

check_already_patched "$FILE_ROOM_MEMBER" \
    "MAX_SEND_QUEUE" "Bug#3+4 (MemberLoop + send_list limit)" && PATCH3_DONE=1 && PATCH4_DONE=1

check_already_patched "$FILE_ROOM" \
    "PATCH5_BROADCAST_FIXED" "Bug#5 (BroadcastRoomInformation lock)" && PATCH5_DONE=1

check_already_patched "$FILE_ROOM" \
    "PATCH6_NO_DOUBLE_DISCONNECT" "Bug#6 (HandleClientDisconnection)" && PATCH6_DONE=1

check_already_patched "$FILE_MULTIPLAYER_CPP" \
    "PATCH7_JOIN_CLEANUP" "Bug#7 (NetPlayJoinRoom cleanup)" && PATCH7_DONE=1

# ──────────────────────────────────────────────────────────────────────────────
# FASE 2 — BACKUP
# ──────────────────────────────────────────────────────────────────────────────
step "FASE 2: Membuat backup file asli..."

BACKUP_DIR="$(dirname "$FILE_NATIVE")/multiplayer_patch_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

for f in "$FILE_NATIVE" "$FILE_MULTIPLAYER_CPP" "$FILE_MULTIPLAYER_H" \
         "$FILE_ROOM_MEMBER" "$FILE_ROOM"; do
    cp "$f" "$BACKUP_DIR/$(basename "$f").orig"
done
success "Backup tersimpan di: $BACKUP_DIR"

# ──────────────────────────────────────────────────────────────────────────────
# HELPER: patch dengan Python (menghindari masalah escape di sed/bash)
# ──────────────────────────────────────────────────────────────────────────────
py_replace() {
    # Argumen: <file> <old_text_file> <new_text_file>
    python3 - "$1" "$2" "$3" <<'PYEOF'
import sys

filepath   = sys.argv[1]
old_file   = sys.argv[2]
new_file   = sys.argv[3]

with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()
with open(old_file, 'r', encoding='utf-8') as f:
    old = f.read()
with open(new_file, 'r', encoding='utf-8') as f:
    new = f.read()

if old not in content:
    print(f"[PYTHON] GAGAL: pattern tidak ditemukan di {filepath}", file=sys.stderr)
    sys.exit(1)

count = content.count(old)
if count > 1:
    print(f"[PYTHON] WARN: pattern ditemukan {count}x, hanya replace pertama", file=sys.stderr)

content_new = content.replace(old, new, 1)
with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content_new)

print(f"[PYTHON] OK: patch berhasil diterapkan ke {filepath}")
PYEOF
}

# ──────────────────────────────────────────────────────────────────────────────
# BUG #1 — native.cpp: Tambahkan shutdownMultiplayer() JNI
# ──────────────────────────────────────────────────────────────────────────────
step "Bug#1: native.cpp — Tambah shutdownMultiplayer() + perbaiki initMultiplayer()"

if [ "$PATCH1_DONE" -eq 0 ]; then
    OLD1=$(mktemp); NEW1=$(mktemp)

    cat > "$OLD1" <<'EOF'
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
EOF

    cat > "$NEW1" <<'EOF'
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

// [PATCH1] Shutdown multiplayer — hancurkan semua resource jaringan.
// Wajib dipanggil dari Kotlin sebelum/setelah emulasi berhenti untuk
// mencegah memory leak pada ENetHost, thread loop, dan AnnounceSession.
//
// PENTING: Guard null wajib ada — shutdownMultiplayer() bisa dipanggil
// dari onDestroy() bahkan sebelum initMultiplayer() pernah dipanggil
// (misalnya game crash sebelum emulasi mulai). Tanpa guard ini,
// Network::Shutdown() dipanggil tanpa Network::Init() → crash/SIGSEGV.
JNIEXPORT void JNICALL
Java_org_citra_citra_1emu_NativeLibrary_shutdownMultiplayer(
    [[maybe_unused]] JNIEnv* env, [[maybe_unused]] jobject obj) {
    if (!multiplayer) {
        // multiplayer belum pernah diinisialisasi — tidak ada yang perlu di-cleanup.
        // Network::Shutdown() TIDAK boleh dipanggil karena Network::Init() belum jalan.
        return;
    }
    multiplayer->NetPlayLeaveRoom();
    // Aman dipanggil karena NetworkInit() → Network::Init() sudah pasti
    // dijalankan saat multiplayer dibuat via initMultiplayer().
    AndroidMultiplayer::NetworkShutdown();
    multiplayer.reset();
    announce_multiplayer_session.reset();
}
EOF

    py_replace "$FILE_NATIVE" "$OLD1" "$NEW1"
    rm -f "$OLD1" "$NEW1"
    success "Bug#1 diterapkan."
else
    info "Bug#1 dilewati (sudah diterapkan)."
fi

# ──────────────────────────────────────────────────────────────────────────────
# BUG #2a — multiplayer.h: Tambah field callback handles di private section
# ──────────────────────────────────────────────────────────────────────────────
step "Bug#2a: multiplayer.h — Tambah callback handle fields"

if [ "$PATCH2_DONE" -eq 0 ]; then
    OLD2H=$(mktemp); NEW2H=$(mktemp)

    cat > "$OLD2H" <<'EOF'
private:
    Core::System& system;
    static std::unique_ptr<Network::VerifyUser::Backend> CreateVerifyBackend(bool use_validation);
    std::weak_ptr<Network::AnnounceMultiplayerSession> announce_multiplayer_session;
    std::unique_ptr<Network::MelonLANAdapter> melon_lan_adapter;
EOF

    cat > "$NEW2H" <<'EOF'
private:
    Core::System& system;
    static std::unique_ptr<Network::VerifyUser::Backend> CreateVerifyBackend(bool use_validation);
    std::weak_ptr<Network::AnnounceMultiplayerSession> announce_multiplayer_session;
    std::unique_ptr<Network::MelonLANAdapter> melon_lan_adapter;

    // [PATCH2] Handles untuk callback agar bisa di-Unbind saat shutdown,
    // mencegah akumulasi callback dan dangling lambda captures.
    Network::RoomMember::CallbackHandle<Network::RoomMember::State>         cb_state_handle;
    Network::RoomMember::CallbackHandle<Network::RoomMember::Error>         cb_error_handle;
    Network::RoomMember::CallbackHandle<Network::StatusMessageEntry>        cb_status_handle;
    Network::RoomMember::CallbackHandle<Network::ChatEntry>                 cb_chat_handle;
EOF

    py_replace "$FILE_MULTIPLAYER_H" "$OLD2H" "$NEW2H"
    rm -f "$OLD2H" "$NEW2H"
    success "Bug#2a (multiplayer.h) diterapkan."
fi

# ──────────────────────────────────────────────────────────────────────────────
# BUG #2b — multiplayer.cpp: Simpan handles di NetworkInit + UnbindAll di destructor
# ──────────────────────────────────────────────────────────────────────────────
step "Bug#2b: multiplayer.cpp — Simpan callback handles + Unbind di destructor"

if [ "$PATCH2_DONE" -eq 0 ]; then

    # 2b-i: Patch destructor — tambah unbind sebelum melon_lan_adapter shutdown
    OLD2D=$(mktemp); NEW2D=$(mktemp)

    cat > "$OLD2D" <<'EOF'
AndroidMultiplayer::~AndroidMultiplayer() {
    if (melon_lan_adapter) {
        melon_lan_adapter->Shutdown();
    }
}
EOF

    cat > "$NEW2D" <<'EOF'
AndroidMultiplayer::~AndroidMultiplayer() {
    // [PATCH2] Unbind semua callback agar tidak ada dangling reference
    if (auto member = Network::GetRoomMember().lock()) {
        if (cb_state_handle)  member->Unbind(cb_state_handle);
        if (cb_error_handle)  member->Unbind(cb_error_handle);
        if (cb_status_handle) member->Unbind(cb_status_handle);
        if (cb_chat_handle)   member->Unbind(cb_chat_handle);
    }
    if (melon_lan_adapter) {
        melon_lan_adapter->Shutdown();
    }
}
EOF

    py_replace "$FILE_MULTIPLAYER_CPP" "$OLD2D" "$NEW2D"
    rm -f "$OLD2D" "$NEW2D"
    success "Bug#2b-destructor diterapkan."

    # 2b-ii: Patch NetworkInit — simpan return value dari Bind ke handle fields
    OLD2N=$(mktemp); NEW2N=$(mktemp)

    cat > "$OLD2N" <<'EOF'
    if (auto member = Network::GetRoomMember().lock()) {
        // register the network structs to use in slots and signals
        member->BindOnStateChanged([this](const Network::RoomMember::State& state) {
            if (state == Network::RoomMember::State::Joined ||
                state == Network::RoomMember::State::Moderator) {
                NetPlayStatus status;
                std::string msg;
                switch (state) {
                case Network::RoomMember::State::Joined:
                    status = NetPlayStatus::ROOM_JOINED;
                    break;
                case Network::RoomMember::State::Moderator:
                    status = NetPlayStatus::ROOM_MODERATOR;
                    break;
                default:
                    return;
                }
                AddNetPlayMessage(static_cast<int>(status), msg);
            }
        });
        member->BindOnError([this](const Network::RoomMember::Error& error) {
            NetPlayStatus status;
            std::string msg;
            switch (error) {
            case Network::RoomMember::Error::LostConnection:
                status = NetPlayStatus::LOST_CONNECTION;
                break;
            case Network::RoomMember::Error::HostKicked:
                status = NetPlayStatus::HOST_KICKED;
                break;
            case Network::RoomMember::Error::UnknownError:
                status = NetPlayStatus::UNKNOWN_ERROR;
                break;
            case Network::RoomMember::Error::NameCollision:
                status = NetPlayStatus::NAME_COLLISION;
                break;
            case Network::RoomMember::Error::MacCollision:
                status = NetPlayStatus::MAC_COLLISION;
                break;
            case Network::RoomMember::Error::WrongVersion:
                status = NetPlayStatus::WRONG_VERSION;
                break;
            case Network::RoomMember::Error::WrongPassword:
                status = NetPlayStatus::WRONG_PASSWORD;
                break;
            case Network::RoomMember::Error::CouldNotConnect:
                status = NetPlayStatus::COULD_NOT_CONNECT;
                break;
            case Network::RoomMember::Error::RoomIsFull:
                status = NetPlayStatus::ROOM_IS_FULL;
                break;
            case Network::RoomMember::Error::HostBanned:
                status = NetPlayStatus::HOST_BANNED;
                break;
            case Network::RoomMember::Error::PermissionDenied:
                status = NetPlayStatus::PERMISSION_DENIED;
                break;
            case Network::RoomMember::Error::NoSuchUser:
                status = NetPlayStatus::NO_SUCH_USER;
                break;
            case Network::RoomMember::Error::ConsoleIdCollision:
                status = NetPlayStatus::CONSOLE_ID_COLLISION;
                break;
            }
            AddNetPlayMessage(static_cast<int>(status), msg);
        });
        member->BindOnStatusMessageReceived(
            [this](const Network::StatusMessageEntry& status_message) {
                NetPlayStatus status = NetPlayStatus::NO_ERROR;
                std::string msg(status_message.nickname);
                switch (status_message.type) {
                case Network::IdMemberJoin:
                    status = NetPlayStatus::MEMBER_JOIN;
                    break;
                case Network::IdMemberLeave:
                    status = NetPlayStatus::MEMBER_LEAVE;
                    break;
                case Network::IdMemberKicked:
                    status = NetPlayStatus::MEMBER_KICKED;
                    break;
                case Network::IdMemberBanned:
                    status = NetPlayStatus::MEMBER_BANNED;
                    break;
                case Network::IdAddressUnbanned:
                    status = NetPlayStatus::ADDRESS_UNBANNED;
                    break;
                }
                AddNetPlayMessage(static_cast<int>(status), msg);
            });
        member->BindOnChatMessageRecieved([this](const Network::ChatEntry& chat) {
            NetPlayStatus status = NetPlayStatus::CHAT_MESSAGE;
            std::string msg(chat.nickname);
            msg += ": ";
            msg += chat.message;
            AddNetPlayMessage(static_cast<int>(status), msg);
        });
    }
EOF

    cat > "$NEW2N" <<'EOF'
    if (auto member = Network::GetRoomMember().lock()) {
        // [PATCH2] Simpan handle dari setiap Bind agar bisa di-Unbind saat destructor.
        // Tanpa ini, setiap NetworkInit() menambah callback baru tanpa bisa dihapus.
        cb_state_handle = member->BindOnStateChanged([this](const Network::RoomMember::State& state) {
            if (state == Network::RoomMember::State::Joined ||
                state == Network::RoomMember::State::Moderator) {
                NetPlayStatus status;
                std::string msg;
                switch (state) {
                case Network::RoomMember::State::Joined:
                    status = NetPlayStatus::ROOM_JOINED;
                    break;
                case Network::RoomMember::State::Moderator:
                    status = NetPlayStatus::ROOM_MODERATOR;
                    break;
                default:
                    return;
                }
                AddNetPlayMessage(static_cast<int>(status), msg);
            }
        });
        cb_error_handle = member->BindOnError([this](const Network::RoomMember::Error& error) {
            NetPlayStatus status;
            std::string msg;
            switch (error) {
            case Network::RoomMember::Error::LostConnection:
                status = NetPlayStatus::LOST_CONNECTION;
                break;
            case Network::RoomMember::Error::HostKicked:
                status = NetPlayStatus::HOST_KICKED;
                break;
            case Network::RoomMember::Error::UnknownError:
                status = NetPlayStatus::UNKNOWN_ERROR;
                break;
            case Network::RoomMember::Error::NameCollision:
                status = NetPlayStatus::NAME_COLLISION;
                break;
            case Network::RoomMember::Error::MacCollision:
                status = NetPlayStatus::MAC_COLLISION;
                break;
            case Network::RoomMember::Error::WrongVersion:
                status = NetPlayStatus::WRONG_VERSION;
                break;
            case Network::RoomMember::Error::WrongPassword:
                status = NetPlayStatus::WRONG_PASSWORD;
                break;
            case Network::RoomMember::Error::CouldNotConnect:
                status = NetPlayStatus::COULD_NOT_CONNECT;
                break;
            case Network::RoomMember::Error::RoomIsFull:
                status = NetPlayStatus::ROOM_IS_FULL;
                break;
            case Network::RoomMember::Error::HostBanned:
                status = NetPlayStatus::HOST_BANNED;
                break;
            case Network::RoomMember::Error::PermissionDenied:
                status = NetPlayStatus::PERMISSION_DENIED;
                break;
            case Network::RoomMember::Error::NoSuchUser:
                status = NetPlayStatus::NO_SUCH_USER;
                break;
            case Network::RoomMember::Error::ConsoleIdCollision:
                status = NetPlayStatus::CONSOLE_ID_COLLISION;
                break;
            }
            AddNetPlayMessage(static_cast<int>(status), msg);
        });
        cb_status_handle = member->BindOnStatusMessageReceived(
            [this](const Network::StatusMessageEntry& status_message) {
                NetPlayStatus status = NetPlayStatus::NO_ERROR;
                std::string msg(status_message.nickname);
                switch (status_message.type) {
                case Network::IdMemberJoin:
                    status = NetPlayStatus::MEMBER_JOIN;
                    break;
                case Network::IdMemberLeave:
                    status = NetPlayStatus::MEMBER_LEAVE;
                    break;
                case Network::IdMemberKicked:
                    status = NetPlayStatus::MEMBER_KICKED;
                    break;
                case Network::IdMemberBanned:
                    status = NetPlayStatus::MEMBER_BANNED;
                    break;
                case Network::IdAddressUnbanned:
                    status = NetPlayStatus::ADDRESS_UNBANNED;
                    break;
                }
                AddNetPlayMessage(static_cast<int>(status), msg);
            });
        cb_chat_handle = member->BindOnChatMessageRecieved([this](const Network::ChatEntry& chat) {
            NetPlayStatus status = NetPlayStatus::CHAT_MESSAGE;
            std::string msg(chat.nickname);
            msg += ": ";
            msg += chat.message;
            AddNetPlayMessage(static_cast<int>(status), msg);
        });
    }
EOF

    py_replace "$FILE_MULTIPLAYER_CPP" "$OLD2N" "$NEW2N"
    rm -f "$OLD2N" "$NEW2N"
    success "Bug#2b-NetworkInit diterapkan."
else
    info "Bug#2b dilewati (sudah diterapkan)."
fi

# ──────────────────────────────────────────────────────────────────────────────
# BUG #3 + #4 — room_member.cpp: MemberLoop non-blocking + send_list dibatasi
# ──────────────────────────────────────────────────────────────────────────────
step "Bug#3+4: room_member.cpp — MemberLoop non-blocking + send_list MAX_SEND_QUEUE"

if [ "$PATCH3_DONE" -eq 0 ]; then
    OLD34=$(mktemp); NEW34=$(mktemp)

    cat > "$OLD34" <<'EOF'
void RoomMember::RoomMemberImpl::MemberLoop() {
    // Receive packets while the connection is open
    while (IsConnected()) {
        std::lock_guard network_lock(network_mutex);
        ENetEvent event;
        if (enet_host_service(client, &event, 16) > 0) {
            switch (event.type) {
            case ENET_EVENT_TYPE_RECEIVE:
                switch (event.packet->data[0]) {
                case IdWifiPacket:
                    HandleWifiPackets(&event);
                    break;
                case IdChatMessage:
                    HandleChatPacket(&event);
                    break;
                case IdStatusMessage:
                    HandleStatusMessagePacket(&event);
                    break;
                case IdRoomInformation:
                    HandleRoomInformationPacket(&event);
                    break;
                case IdJoinSuccess:
                case IdJoinSuccessAsMod:
                    // The join request was successful, we are now in the room.
                    // Note: member_information may not be populated yet due to packet arrival
                    // order. IdRoomInformation may arrive after IdJoinSuccess for LAN rooms.
                    // This is not a fatal condition, so we just log it and continue.
                    if (member_information.size() == 0) {
                        LOG_WARNING(Network, "Received join success but room information not yet available. "
                                   "This is normal for LAN rooms with packet reordering.");
                    }           
                    HandleJoinPacket(&event); // Get the MAC Address for the client
                    if (event.packet->data[0] == IdJoinSuccessAsMod) {
                        SetState(State::Moderator);
                    } else {
                        SetState(State::Joined);
                    }
                    break;
                case IdModBanListResponse:
                    HandleModBanListResponsePacket(&event);
                    break;
                case IdRoomIsFull:
                    SetState(State::Idle);
                    SetError(Error::RoomIsFull);
                    break;
                case IdNameCollision:
                    SetState(State::Idle);
                    SetError(Error::NameCollision);
                    break;
                case IdMacCollision:
                    SetState(State::Idle);
                    SetError(Error::MacCollision);
                    break;
                case IdConsoleIdCollision:
                    SetState(State::Idle);
                    SetError(Error::ConsoleIdCollision);
                    break;
                case IdVersionMismatch:
                    SetState(State::Idle);
                    SetError(Error::WrongVersion);
                    break;
                case IdWrongPassword:
                    SetState(State::Idle);
                    SetError(Error::WrongPassword);
                    break;
                case IdCloseRoom:
                    SetState(State::Idle);
                    SetError(Error::LostConnection);
                    break;
                case IdHostKicked:
                    SetState(State::Idle);
                    SetError(Error::HostKicked);
                    break;
                case IdHostBanned:
                    SetState(State::Idle);
                    SetError(Error::HostBanned);
                    break;
                case IdModPermissionDenied:
                    SetError(Error::PermissionDenied);
                    break;
                case IdModNoSuchUser:
                    SetError(Error::NoSuchUser);
                    break;
                }
                enet_packet_destroy(event.packet);
                break;
            case ENET_EVENT_TYPE_DISCONNECT:
                if (state == State::Joined || state == State::Moderator) {
                    SetState(State::Idle);
                    SetError(Error::LostConnection);
                }
                break;
            case ENET_EVENT_TYPE_NONE:
                break;
            case ENET_EVENT_TYPE_CONNECT:
                // The ENET_EVENT_TYPE_CONNECT event can not possibly happen here because we're
                // already connected
                ASSERT_MSG(false, "Received unexpected connect event while already connected");
                break;
            }
        }

        std::list<Packet> packets;
        {
            std::lock_guard send_list_lock(send_list_mutex);
            packets.swap(send_list);
        }
        for (const auto& packet : packets) {
            ENetPacket* enetPacket = enet_packet_create(packet.GetData(), packet.GetDataSize(),
                                                        ENET_PACKET_FLAG_RELIABLE);
            enet_peer_send(server, 0, enetPacket);
        }
        enet_host_flush(client);
    }
    Disconnect();
};
EOF

    cat > "$NEW34" <<'EOF'
// [PATCH3] Konstanta batas antrian kirim paket.
// Mencegah send_list membengkak saat device lag, yang sebelumnya
// menyebabkan memory spike → OOM → disconnect paksa.
static constexpr size_t MAX_SEND_QUEUE = 64;

void RoomMember::RoomMemberImpl::MemberLoop() {
    // [PATCH3] Receive dan send dipisah lock-nya sehingga network_mutex
    // tidak dipegang sepanjang iterasi. Sebelumnya satu lock_guard mencakup
    // enet_host_service + semua handler + enet_host_flush, yang menyebabkan
    // disconnect saat device lag karena ENet internal timeout terpicu.
    while (IsConnected()) {
        // --- Tahap 1: Terima semua paket masuk (non-blocking, timeout=0) ---
        {
            std::lock_guard network_lock(network_mutex);
            ENetEvent event;
            while (enet_host_service(client, &event, 0) > 0) {
                switch (event.type) {
                case ENET_EVENT_TYPE_RECEIVE:
                    switch (event.packet->data[0]) {
                    case IdWifiPacket:
                        HandleWifiPackets(&event);
                        break;
                    case IdChatMessage:
                        HandleChatPacket(&event);
                        break;
                    case IdStatusMessage:
                        HandleStatusMessagePacket(&event);
                        break;
                    case IdRoomInformation:
                        HandleRoomInformationPacket(&event);
                        break;
                    case IdJoinSuccess:
                    case IdJoinSuccessAsMod:
                        // The join request was successful, we are now in the room.
                        // Note: member_information may not be populated yet due to packet arrival
                        // order. IdRoomInformation may arrive after IdJoinSuccess for LAN rooms.
                        // This is not a fatal condition, so we just log it and continue.
                        if (member_information.size() == 0) {
                            LOG_WARNING(Network, "Received join success but room information not yet available. "
                                       "This is normal for LAN rooms with packet reordering.");
                        }
                        HandleJoinPacket(&event); // Get the MAC Address for the client
                        if (event.packet->data[0] == IdJoinSuccessAsMod) {
                            SetState(State::Moderator);
                        } else {
                            SetState(State::Joined);
                        }
                        break;
                    case IdModBanListResponse:
                        HandleModBanListResponsePacket(&event);
                        break;
                    case IdRoomIsFull:
                        SetState(State::Idle);
                        SetError(Error::RoomIsFull);
                        break;
                    case IdNameCollision:
                        SetState(State::Idle);
                        SetError(Error::NameCollision);
                        break;
                    case IdMacCollision:
                        SetState(State::Idle);
                        SetError(Error::MacCollision);
                        break;
                    case IdConsoleIdCollision:
                        SetState(State::Idle);
                        SetError(Error::ConsoleIdCollision);
                        break;
                    case IdVersionMismatch:
                        SetState(State::Idle);
                        SetError(Error::WrongVersion);
                        break;
                    case IdWrongPassword:
                        SetState(State::Idle);
                        SetError(Error::WrongPassword);
                        break;
                    case IdCloseRoom:
                        SetState(State::Idle);
                        SetError(Error::LostConnection);
                        break;
                    case IdHostKicked:
                        SetState(State::Idle);
                        SetError(Error::HostKicked);
                        break;
                    case IdHostBanned:
                        SetState(State::Idle);
                        SetError(Error::HostBanned);
                        break;
                    case IdModPermissionDenied:
                        SetError(Error::PermissionDenied);
                        break;
                    case IdModNoSuchUser:
                        SetError(Error::NoSuchUser);
                        break;
                    }
                    enet_packet_destroy(event.packet);
                    break;
                case ENET_EVENT_TYPE_DISCONNECT:
                    if (state == State::Joined || state == State::Moderator) {
                        SetState(State::Idle);
                        SetError(Error::LostConnection);
                    }
                    break;
                case ENET_EVENT_TYPE_NONE:
                    break;
                case ENET_EVENT_TYPE_CONNECT:
                    // The ENET_EVENT_TYPE_CONNECT event can not possibly happen here because we're
                    // already connected
                    ASSERT_MSG(false, "Received unexpected connect event while already connected");
                    break;
                }
            }
        }

        // --- Tahap 2: Kirim paket yang antri (lock terpisah) ---
        // [PATCH4] send_list sudah dibatasi MAX_SEND_QUEUE di Send(),
        // sehingga tidak ada burst traffic stale saat recover dari lag.
        {
            std::list<Packet> packets;
            {
                std::lock_guard send_list_lock(send_list_mutex);
                packets.swap(send_list);
            }
            if (!packets.empty()) {
                std::lock_guard network_lock(network_mutex);
                for (const auto& packet : packets) {
                    ENetPacket* enetPacket = enet_packet_create(packet.GetData(),
                                                                packet.GetDataSize(),
                                                                ENET_PACKET_FLAG_RELIABLE);
                    enet_peer_send(server, 0, enetPacket);
                }
                enet_host_flush(client);
            }
        }

        // Sleep pendek agar tidak busy-spin saat tidak ada paket
        std::this_thread::sleep_for(std::chrono::milliseconds(8));
    }
    Disconnect();
};
EOF

    py_replace "$FILE_ROOM_MEMBER" "$OLD34" "$NEW34"
    rm -f "$OLD34" "$NEW34"
    success "Bug#3+4 (MemberLoop) diterapkan."
else
    info "Bug#3+4 dilewati (sudah diterapkan)."
fi

# Bug #4 — patch Send() agar membuang paket lama jika antrian penuh
if [ "$PATCH4_DONE" -eq 0 ]; then
    OLD4S=$(mktemp); NEW4S=$(mktemp)

    cat > "$OLD4S" <<'EOF'
void RoomMember::RoomMemberImpl::Send(Packet&& packet) {
    std::lock_guard lock(send_list_mutex);
    send_list.push_back(std::move(packet));
}
EOF

    cat > "$NEW4S" <<'EOF'
void RoomMember::RoomMemberImpl::Send(Packet&& packet) {
    std::lock_guard lock(send_list_mutex);
    // [PATCH4] Buang paket paling lama jika antrian sudah penuh.
    // Paket WiFi game yang terlalu lama antri sudah tidak relevan (stale),
    // mengirimnya semua sekaligus hanya membuat burst traffic → disconnect.
    while (send_list.size() >= MAX_SEND_QUEUE) {
        send_list.pop_front();
    }
    send_list.push_back(std::move(packet));
}
EOF

    py_replace "$FILE_ROOM_MEMBER" "$OLD4S" "$NEW4S"
    rm -f "$OLD4S" "$NEW4S"
    success "Bug#4 (Send queue limit) diterapkan."
fi

# ──────────────────────────────────────────────────────────────────────────────
# BUG #5 — room.cpp: BroadcastRoomInformation — members.size() di dalam lock
# ──────────────────────────────────────────────────────────────────────────────
step "Bug#5: room.cpp — Perbaiki race condition members.size() di BroadcastRoomInformation"

if [ "$PATCH5_DONE" -eq 0 ]; then
    OLD5=$(mktemp); NEW5=$(mktemp)

    cat > "$OLD5" <<'EOF'
void Room::RoomImpl::BroadcastRoomInformation() {
    Packet packet;
    packet << static_cast<u8>(IdRoomInformation);
    packet << room_information.name;
    packet << room_information.description;
    packet << room_information.member_slots;
    packet << room_information.port;
    packet << room_information.preferred_game;
    packet << room_information.host_username;

    packet << static_cast<u32>(members.size());
    {
        std::lock_guard lock(member_mutex);
        for (const auto& member : members) {
            packet << member.nickname;
            packet << member.mac_address;
            packet << member.game_info.name;
            packet << member.game_info.id;
            packet << member.user_data.username;
            packet << member.user_data.display_name;
            packet << member.user_data.avatar_url;
        }
    }

    ENetPacket* enet_packet =
        enet_packet_create(packet.GetData(), packet.GetDataSize(), ENET_PACKET_FLAG_RELIABLE);
    enet_host_broadcast(server, 0, enet_packet);
    enet_host_flush(server);
}
EOF

    cat > "$NEW5" <<'EOF'
void Room::RoomImpl::BroadcastRoomInformation() {
    // [PATCH5] members.size() dan iterasi members harus dalam satu lock yang sama.
    // Sebelumnya size() dibaca di luar lock, sehingga member bisa join/disconnect
    // antara pembacaan size dan lock, menghasilkan packet yang corrupt (ukuran
    // tidak cocok dengan data) yang menyebabkan client disconnect.
    Packet packet;
    packet << static_cast<u8>(IdRoomInformation);
    packet << room_information.name;
    packet << room_information.description;
    packet << room_information.member_slots;
    packet << room_information.port;
    packet << room_information.preferred_game;
    packet << room_information.host_username;

    {
        std::lock_guard lock(member_mutex); // PATCH5_BROADCAST_FIXED
        packet << static_cast<u32>(members.size());
        for (const auto& member : members) {
            packet << member.nickname;
            packet << member.mac_address;
            packet << member.game_info.name;
            packet << member.game_info.id;
            packet << member.user_data.username;
            packet << member.user_data.display_name;
            packet << member.user_data.avatar_url;
        }
    }

    ENetPacket* enet_packet =
        enet_packet_create(packet.GetData(), packet.GetDataSize(), ENET_PACKET_FLAG_RELIABLE);
    enet_host_broadcast(server, 0, enet_packet);
    enet_host_flush(server);
}
EOF

    py_replace "$FILE_ROOM" "$OLD5" "$NEW5"
    rm -f "$OLD5" "$NEW5"
    success "Bug#5 diterapkan."
else
    info "Bug#5 dilewati (sudah diterapkan)."
fi

# ──────────────────────────────────────────────────────────────────────────────
# BUG #6 — room.cpp: HandleClientDisconnection — hapus double disconnect
# ──────────────────────────────────────────────────────────────────────────────
step "Bug#6: room.cpp — Hapus enet_peer_disconnect() ganda di HandleClientDisconnection"

if [ "$PATCH6_DONE" -eq 0 ]; then
    OLD6=$(mktemp); NEW6=$(mktemp)

    cat > "$OLD6" <<'EOF'
void Room::RoomImpl::HandleClientDisconnection(ENetPeer* client) {
    // Remove the client from the members list.
    std::string nickname, username, ip;
    {
        std::lock_guard lock(member_mutex);
        auto member = std::find_if(members.begin(), members.end(), [client](const Member& member) {
            return member.peer == client;
        });
        if (member != members.end()) {
            nickname = member->nickname;
            username = member->user_data.username;

            char ip_raw[256];
            enet_address_get_host_ip(&member->peer->address, ip_raw, sizeof(ip_raw) - 1);
            ip = ip_raw;

            members.erase(member);
        }
    }

    // Announce the change to all clients.
    enet_peer_disconnect(client, 0);
    if (!nickname.empty())
        SendStatusMessage(IdMemberLeave, nickname, username, ip);
    BroadcastRoomInformation();
}
EOF

    cat > "$NEW6" <<'EOF'
void Room::RoomImpl::HandleClientDisconnection(ENetPeer* client) {
    // [PATCH6] Fungsi ini dipanggil dari handler ENET_EVENT_TYPE_DISCONNECT,
    // artinya peer SUDAH terputus. Memanggil enet_peer_disconnect() lagi
    // adalah undefined behavior di ENet dan bisa menyebabkan crash/state corrupt.
    // PATCH6_NO_DOUBLE_DISCONNECT
    std::string nickname, username, ip;
    {
        std::lock_guard lock(member_mutex);
        auto member = std::find_if(members.begin(), members.end(), [client](const Member& member) {
            return member.peer == client;
        });
        if (member != members.end()) {
            nickname = member->nickname;
            username = member->user_data.username;

            char ip_raw[256];
            enet_address_get_host_ip(&member->peer->address, ip_raw, sizeof(ip_raw) - 1);
            ip = ip_raw;

            members.erase(member);
        }
    }

    // Peer sudah disconnect — tidak perlu panggil enet_peer_disconnect() lagi.
    if (!nickname.empty())
        SendStatusMessage(IdMemberLeave, nickname, username, ip);
    BroadcastRoomInformation();
}
EOF

    py_replace "$FILE_ROOM" "$OLD6" "$NEW6"
    rm -f "$OLD6" "$NEW6"
    success "Bug#6 diterapkan."
else
    info "Bug#6 dilewati (sudah diterapkan)."
fi

# ──────────────────────────────────────────────────────────────────────────────
# BUG #7 — multiplayer.cpp: NetPlayJoinRoom — cleanup saat timeout
# ──────────────────────────────────────────────────────────────────────────────
step "Bug#7: multiplayer.cpp — NetPlayJoinRoom cleanup saat timeout"

if [ "$PATCH7_DONE" -eq 0 ]; then
    OLD7=$(mktemp); NEW7=$(mktemp)

    cat > "$OLD7" <<'EOF'
    // Wait for the connection and join process to complete.
    // Use a longer timeout (5000ms = 5 seconds) to account for slower LAN networks.
    // This matches the ConnectionTimeoutMs used in RoomMember::Join()
    constexpr int JOIN_WAIT_TIMEOUT_MS = 5000;
    constexpr int JOIN_WAIT_STEP_MS = 100;
    for (int elapsed = 0; elapsed < JOIN_WAIT_TIMEOUT_MS; elapsed += JOIN_WAIT_STEP_MS) {
        std::this_thread::sleep_for(std::chrono::milliseconds(JOIN_WAIT_STEP_MS));
        
        if (member->GetState() == Network::RoomMember::State::Joined ||
            member->GetState() == Network::RoomMember::State::Moderator) {
            return NetPlayStatus::NO_ERROR;
        }
    }

    if (!member->IsConnected()) {
        return NetPlayStatus::COULD_NOT_CONNECT;
    }

    return NetPlayStatus::WRONG_PASSWORD;
}
EOF

    cat > "$NEW7" <<'EOF'
    // Wait for the connection and join process to complete.
    // Use a longer timeout (5000ms = 5 seconds) to account for slower LAN networks.
    // This matches the ConnectionTimeoutMs used in RoomMember::Join()
    constexpr int JOIN_WAIT_TIMEOUT_MS = 5000;
    constexpr int JOIN_WAIT_STEP_MS = 100;
    for (int elapsed = 0; elapsed < JOIN_WAIT_TIMEOUT_MS; elapsed += JOIN_WAIT_STEP_MS) {
        std::this_thread::sleep_for(std::chrono::milliseconds(JOIN_WAIT_STEP_MS));

        if (member->GetState() == Network::RoomMember::State::Joined ||
            member->GetState() == Network::RoomMember::State::Moderator) {
            return NetPlayStatus::NO_ERROR;
        }
    }

    // [PATCH7] Jika timeout, bersihkan state member agar percobaan join
    // berikutnya tidak kena false ALREADY_IN_ROOM. Sebelumnya loop_thread
    // dibiarkan berjalan dalam state Joining tanpa dibersihkan.
    // PATCH7_JOIN_CLEANUP
    if (member->GetState() == Network::RoomMember::State::Joining) {
        member->Leave(); // Hentikan loop_thread dan hancurkan ENetHost
    }

    return NetPlayStatus::COULD_NOT_CONNECT;
}
EOF

    py_replace "$FILE_MULTIPLAYER_CPP" "$OLD7" "$NEW7"
    rm -f "$OLD7" "$NEW7"
    success "Bug#7 diterapkan."
else
    info "Bug#7 dilewati (sudah diterapkan)."
fi

# ──────────────────────────────────────────────────────────────────────────────
# FASE AKHIR — Verifikasi
# ──────────────────────────────────────────────────────────────────────────────
step "VERIFIKASI: Memeriksa hasil patch..."

FAIL=0

verify_patch() {
    local file="$1"; local marker="$2"; local label="$3"
    if grep -q "$marker" "$file" 2>/dev/null; then
        success "$label ✓"
    else
        error "$label ✗ — marker '$marker' tidak ditemukan di $file"
        FAIL=1
    fi
}

verify_patch "$FILE_NATIVE"         "shutdownMultiplayer"          "Bug#1 shutdownMultiplayer"
verify_patch "$FILE_MULTIPLAYER_H"  "cb_state_handle"              "Bug#2a callback handles di .h"
verify_patch "$FILE_MULTIPLAYER_CPP" "cb_state_handle ="           "Bug#2b Bind disimpan ke handle"
verify_patch "$FILE_MULTIPLAYER_CPP" "if (cb_state_handle)"        "Bug#2b Unbind di destructor"
verify_patch "$FILE_ROOM_MEMBER"    "MAX_SEND_QUEUE"               "Bug#3+4 MemberLoop + send limit"
verify_patch "$FILE_ROOM_MEMBER"    "PATCH4"                       "Bug#4 Send queue limit"
verify_patch "$FILE_ROOM"           "PATCH5_BROADCAST_FIXED"       "Bug#5 BroadcastRoomInformation"
verify_patch "$FILE_ROOM"           "PATCH6_NO_DOUBLE_DISCONNECT"  "Bug#6 HandleClientDisconnection"
verify_patch "$FILE_MULTIPLAYER_CPP" "PATCH7_JOIN_CLEANUP"         "Bug#7 NetPlayJoinRoom cleanup"

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  SEMUA PATCH BERHASIL DITERAPKAN ✓          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}CATATAN PENTING:${NC}"
    echo "  1. Daftarkan JNI 'shutdownMultiplayer' di sisi Kotlin/Java:"
    echo "     external fun shutdownMultiplayer()"
    echo "     Panggil di onStop/onDestroy Activity emulasi."
    echo ""
    echo "  2. Backup tersimpan di:"
    echo "     $BACKUP_DIR"
    echo ""
    echo "  3. Build ulang project untuk mengkompilasi perubahan."
else
    echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  BEBERAPA PATCH GAGAL — periksa error di atas ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  File asli ada di backup: $BACKUP_DIR"
    echo "  Restore dengan: cp $BACKUP_DIR/*.orig <lokasi aslinya>"
    exit 1
fi
