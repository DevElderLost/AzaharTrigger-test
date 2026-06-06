#!/bin/bash
# fix_join_timeout.sh — Fix timeout join room untuk ZeroTier
# NetPlayCreateRoom: loop 5×100ms = 500ms → terlalu singkat untuk ZeroTier
# Fix: perpanjang ke 15000ms dan tambah enet_peer_timeout
#
# Cara pakai:
#   bash scripts/fix_join_timeout.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
MULTI_CPP="$PROJECT_ROOT/src/android/app/src/main/jni/multiplayer.cpp"

[ -f "$MULTI_CPP" ] || { echo "[ERROR] multiplayer.cpp tidak ditemukan: $MULTI_CPP"; exit 1; }

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix: Join timeout untuk ZeroTier"
echo "═══════════════════════════════════════════════════════"
echo ""

python3 - "$MULTI_CPP" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# ── Fix 1: NetPlayCreateRoom — perpanjang timeout dari 500ms → 15s ─
old_create_wait = '''    // Failsafe timer to avoid joining before creation
    std::this_thread::sleep_for(std::chrono::milliseconds(100));

    member->Join(username, Service::CFG::GetConsoleIdHash(system), ipaddress.c_str(), port, 0, Network::NoPreferredMac, password);

    // Failsafe timer to avoid joining before creation
    for (int i = 0; i < 5; i++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        if (member->GetState() == Network::RoomMember::State::Joined ||
            member->GetState() == Network::RoomMember::State::Moderator) {
            return NetPlayStatus::NO_ERROR;
        }
    }

    // If join failed while room is created, clean up the room
    room->Destroy();
    return NetPlayStatus::CREATE_ROOM_ERROR;'''

new_create_wait = '''    // Beri waktu room untuk fully initialize sebelum join
    std::this_thread::sleep_for(std::chrono::milliseconds(300));

    member->Join(username, Service::CFG::GetConsoleIdHash(system), ipaddress.c_str(), port, 0, Network::NoPreferredMac, password);

    // Tunggu join selesai — ZeroTier butuh waktu lebih lama (via internet)
    // Timeout 15 detik untuk accommodate ZeroTier latency
    constexpr int CREATE_JOIN_TIMEOUT_MS = 15000;
    constexpr int CREATE_JOIN_STEP_MS    = 200;
    for (int elapsed = 0; elapsed < CREATE_JOIN_TIMEOUT_MS; elapsed += CREATE_JOIN_STEP_MS) {
        std::this_thread::sleep_for(std::chrono::milliseconds(CREATE_JOIN_STEP_MS));
        if (member->GetState() == Network::RoomMember::State::Joined ||
            member->GetState() == Network::RoomMember::State::Moderator) {
            return NetPlayStatus::NO_ERROR;
        }
        // Jika state kembali ke Idle sebelum timeout, berarti join gagal
        if (member->GetState() == Network::RoomMember::State::Idle) {
            break;
        }
    }

    // Join gagal — bersihkan room
    room->Destroy();
    return NetPlayStatus::CREATE_ROOM_ERROR;'''

if old_create_wait in content:
    content = content.replace(old_create_wait, new_create_wait)
    print("[OK] Fix 1: NetPlayCreateRoom timeout diperpanjang ke 15s")
else:
    print("[WARN] Fix 1: Pattern NetPlayCreateRoom tidak ditemukan")

# ── Fix 2: NetPlayJoinRoom — perpanjang dari 5s → 15s ─────────────
old_join_timeout = '''    constexpr int JOIN_WAIT_TIMEOUT_MS = 5000;
    constexpr int JOIN_WAIT_STEP_MS = 100;
    for (int elapsed = 0; elapsed < JOIN_WAIT_TIMEOUT_MS; elapsed += JOIN_WAIT_STEP_MS) {
        std::this_thread::sleep_for(std::chrono::milliseconds(JOIN_WAIT_STEP_MS));
        
        if (member->GetState() == Network::RoomMember::State::Joined ||
            member->GetState() == Network::RoomMember::State::Moderator) {
            return NetPlayStatus::NO_ERROR;
        }
    }'''

new_join_timeout = '''    // ZeroTier membutuhkan waktu lebih lama untuk handshake via internet
    constexpr int JOIN_WAIT_TIMEOUT_MS = 15000;
    constexpr int JOIN_WAIT_STEP_MS    = 200;
    for (int elapsed = 0; elapsed < JOIN_WAIT_TIMEOUT_MS; elapsed += JOIN_WAIT_STEP_MS) {
        std::this_thread::sleep_for(std::chrono::milliseconds(JOIN_WAIT_STEP_MS));

        if (member->GetState() == Network::RoomMember::State::Joined ||
            member->GetState() == Network::RoomMember::State::Moderator) {
            return NetPlayStatus::NO_ERROR;
        }
        // Early exit jika state kembali Idle (koneksi ditolak)
        if (member->GetState() == Network::RoomMember::State::Idle) {
            break;
        }
    }'''

if old_join_timeout in content:
    content = content.replace(old_join_timeout, new_join_timeout)
    print("[OK] Fix 2: NetPlayJoinRoom timeout diperpanjang ke 15s")
else:
    print("[WARN] Fix 2: Pattern NetPlayJoinRoom tidak ditemukan, cek spasi")
    # Coba variasi spasi
    import re
    pattern = r'constexpr int JOIN_WAIT_TIMEOUT_MS = 5000;'
    if re.search(pattern, content):
        content = re.sub(
            r'constexpr int JOIN_WAIT_TIMEOUT_MS = 5000;',
            'constexpr int JOIN_WAIT_TIMEOUT_MS = 15000; // diperpanjang untuk ZeroTier',
            content
        )
        print("[OK] Fix 2: Timeout diupdate via regex")

with open(path, 'w') as f:
    f.write(content)
print("[OK] multiplayer.cpp selesai dipatch")
PYEOF

# ── Fix 3: room_member.cpp — tambah enet_peer_timeout ─────────────
ROOM_MEMBER="$PROJECT_ROOT/src/network/room_member.cpp"
if [ -f "$ROOM_MEMBER" ]; then
    echo ""
    echo "[INFO] Patch room_member.cpp: enet_peer_timeout untuk ZeroTier..."
    python3 - "$ROOM_MEMBER" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Tambah enet_peer_timeout setelah connect berhasil
old_connect = '''    if (net > 0 && event.type == ENET_EVENT_TYPE_CONNECT) {'''
new_connect = '''    if (net > 0 && event.type == ENET_EVENT_TYPE_CONNECT) {
        // Set ENet peer timeout — penting untuk ZeroTier via internet
        // Default ENet timeout terlalu agresif untuk latency internet
        enet_peer_timeout(room_member_impl->server,
            0,      // timeout_limit: default (32 round-trips)
            4000,   // timeout_minimum: 4 detik
            30000   // timeout_maximum: 30 detik
        );'''

if old_connect in content:
    if 'enet_peer_timeout' not in content:
        content = content.replace(old_connect, new_connect)
        with open(path, 'w') as f:
            f.write(content)
        print("[OK] Fix 3: enet_peer_timeout ditambahkan ke room_member.cpp")
    else:
        print("[INFO] enet_peer_timeout sudah ada di room_member.cpp")
else:
    print("[WARN] Fix 3: Pattern tidak ditemukan di room_member.cpp")
PYEOF
fi

echo ""
echo -e "\033[0;32m  Fix selesai!\033[0m"
echo ""
echo "  git add ."
echo "  git commit -m \"fix: perpanjang join timeout 15s + enet_peer_timeout untuk ZeroTier\""
echo "  git push origin DevElderLost-patch-4"
echo ""
