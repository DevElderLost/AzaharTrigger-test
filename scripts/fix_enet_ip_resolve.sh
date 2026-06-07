#!/bin/bash
# fix_enet_ip_resolve.sh
# Fix: ganti enet_address_set_host() dengan enet_address_set_ip()
# untuk ZeroTier IP agar tidak perlu DNS lookup
#
# enet_address_set_host() → DNS lookup → gagal untuk ZeroTier IP
# enet_address_set_ip()   → langsung parse IP string → berhasil

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
ROOM_MEMBER="$PROJECT_ROOT/src/network/room_member.cpp"

[ -f "$ROOM_MEMBER" ] || { echo "[ERROR] room_member.cpp tidak ditemukan"; exit 1; }

python3 - "$ROOM_MEMBER" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Ganti enet_address_set_host dengan set_ip untuk menghindari DNS lookup
# enet_address_set_ip() tersedia di ENet 1.3.13+
# Fallback: parse manual dengan inet_pton
old_addr = '''    ENetAddress address{};
    enet_address_set_host(&address, server_addr);
    address.port = server_port;'''

new_addr = '''    ENetAddress address{};
    // Gunakan enet_address_set_ip untuk menghindari DNS lookup
    // DNS lookup gagal untuk ZeroTier virtual IP di Android
    // enet_address_set_ip() langsung parse dotted-decimal IP string
    if (enet_address_set_ip(&address, server_addr) != 0) {
        // Fallback ke enet_address_set_host jika bukan IP address
        if (enet_address_set_host(&address, server_addr) != 0) {
            room_member_impl->SetState(State::Idle);
            room_member_impl->SetError(Error::CouldNotConnect);
            return;
        }
    }
    address.port = server_port;'''

if old_addr in content:
    content = content.replace(old_addr, new_addr)
    print("[OK] enet_address_set_host → enet_address_set_ip")
else:
    print("[WARN] Pattern tidak cocok")
    # Tampilkan baris sekitar enet_address_set_host
    for i, line in enumerate(content.split('\n'), 1):
        if 'enet_address_set_host' in line and 'server_addr' in line:
            print(f"  Baris {i}: {line.strip()}")

with open(path, 'w') as f:
    f.write(content)
print("[OK] room_member.cpp selesai")
PYEOF

echo ""
echo "  git add ."
echo "  git commit -m \"fix: ganti enet_address_set_host ke set_ip agar ZeroTier IP bisa resolve\""
echo "  git push origin DevElderLost-patch-4"
