#!/bin/bash
# fix_zerotier_room_create.sh — Fix Create Room via ZeroTier
# ENet tidak bisa bind ke ZeroTier IP → bind ke ENET_HOST_ANY
# tapi advertise ZeroTier IP agar client bisa connect
#
# Cara pakai:
#   bash scripts/fix_zerotier_room_create.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
ROOM_CPP="$PROJECT_ROOT/src/network/room.cpp"

[ -f "$ROOM_CPP" ] || { echo "[ERROR] room.cpp tidak ditemukan: $ROOM_CPP"; exit 1; }

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix: Room::Create bind ke ANY saat ZeroTier IP"
echo "═══════════════════════════════════════════════════════"
echo ""

python3 - "$ROOM_CPP" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Ganti logika bind di Room::Create
# Masalah: enet_address_set_host(ZeroTier IP) gagal karena
# ZeroTier virtual interface tidak dikenali ENet
# Fix: selalu bind ke ENET_HOST_ANY (0.0.0.0) agar ENet
# mendengarkan di semua interface termasuk ZeroTier

old_create = '''    ENetAddress address;
    address.host = ENET_HOST_ANY;
    if (!server_address.empty()) {
        enet_address_set_host(&address, server_address.c_str());
    }
    address.port = server_port;'''

new_create = '''    ENetAddress address;
    // Selalu bind ke ENET_HOST_ANY (0.0.0.0) agar server mendengarkan
    // di semua network interface termasuk ZeroTier virtual interface.
    // Jika bind ke IP spesifik (terutama ZeroTier IP), ENet akan gagal
    // karena ZeroTier virtual interface tidak selalu dikenali sebagai
    // interface standar oleh Android.
    address.host = ENET_HOST_ANY;
    address.port = server_port;
    (void)server_address; // server_address tetap disimpan untuk informasi room'''

if old_create in content:
    content = content.replace(old_create, new_create)
    print("[OK] room.cpp: Room::Create dipatch untuk bind ke ENET_HOST_ANY")
else:
    print("[WARN] Pattern tidak ditemukan, cek manual")
    # Tampilkan area yang relevan
    idx = content.find('bool Room::Create')
    if idx != -1:
        print("Konten sekitar Room::Create:")
        print(content[idx:idx+400])

with open(path, 'w') as f:
    f.write(content)
PYEOF

echo ""
echo "  git add ."
echo "  git commit -m \"fix: Room::Create bind ke ENET_HOST_ANY agar ZeroTier bisa digunakan\""
echo "  git push origin DevElderLost-patch-4"
echo ""
