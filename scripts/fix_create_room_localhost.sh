#!/bin/bash
# fix_create_room_localhost.sh
# Saat Create Room, host join ke 127.0.0.1 bukan ke ZeroTier IP
# karena room server ada di device yang sama (localhost)
# Client lain tetap join ke ZeroTier IP host

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
MULTI_CPP="$PROJECT_ROOT/src/android/app/src/main/jni/multiplayer.cpp"

[ -f "$MULTI_CPP" ] || { echo "[ERROR] multiplayer.cpp tidak ditemukan: $MULTI_CPP"; exit 1; }

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix: Create Room join via localhost bukan ZeroTier IP"
echo "═══════════════════════════════════════════════════════"
echo ""

python3 - "$MULTI_CPP" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Cari Join() call di NetPlayCreateRoom
# Host harus join ke 127.0.0.1, bukan ke ipaddress (ZeroTier IP)
# Karena room server ada di device yang sama

old_join = '    member->Join(username, Service::CFG::GetConsoleIdHash(system), ipaddress.c_str(), port, 0, Network::NoPreferredMac, password);'

new_join = '''    // Host join ke localhost karena room server ada di device yang sama.
    // Menggunakan ZeroTier IP (ipaddress) akan gagal karena ENet tidak bisa
    // connect ke virtual interface ZeroTier dari device itu sendiri.
    // Client lain tetap join ke ZeroTier IP host dari device mereka.
    member->Join(username, Service::CFG::GetConsoleIdHash(system), "127.0.0.1", port, 0, Network::NoPreferredMac, password);'''

# Hanya ganti yang ada di NetPlayCreateRoom, bukan NetPlayJoinRoom
# Cari konteks NetPlayCreateRoom
create_start = content.find('NetPlayStatus AndroidMultiplayer::NetPlayCreateRoom')
join_start   = content.find('NetPlayStatus AndroidMultiplayer::NetPlayJoinRoom')

if create_start != -1 and join_start != -1:
    # Ambil bagian CreateRoom saja
    create_section = content[create_start:join_start]

    if old_join in create_section:
        create_section = create_section.replace(old_join, new_join, 1)
        content = content[:create_start] + create_section + content[join_start:]
        print("[OK] NetPlayCreateRoom: host join ke 127.0.0.1")
    else:
        print("[WARN] Pattern Join tidak ditemukan di NetPlayCreateRoom")
        # Tampilkan konten untuk debug
        idx = create_section.find('member->Join')
        if idx != -1:
            print("Join call yang ada:")
            print(create_section[idx:idx+200])
else:
    print("[WARN] Tidak bisa temukan fungsi Create/Join Room")

with open(path, 'w') as f:
    f.write(content)
print("[OK] multiplayer.cpp selesai")
PYEOF

echo ""
echo "  git add ."
echo "  git commit -m \"fix: Create Room host join via 127.0.0.1 bukan ZeroTier IP\""
echo "  git push origin DevElderLost-patch-4"
echo ""
