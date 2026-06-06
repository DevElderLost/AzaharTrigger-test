#!/bin/bash
# fix_enet_zerotier_bind.sh
# Fix: bind ENet client ke ZeroTier IP agar routing lewat ZeroTier interface
# Tanpa bind, Android mengirim UDP lewat default interface (bukan ZeroTier)
#
# Cara pakai:
#   bash scripts/fix_enet_zerotier_bind.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
ROOM_MEMBER="$PROJECT_ROOT/src/network/room_member.cpp"
MULTI_CPP="$PROJECT_ROOT/src/android/app/src/main/jni/multiplayer.cpp"
MULTI_H="$PROJECT_ROOT/src/android/app/src/main/jni/multiplayer.h"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix: ENet client bind ke ZeroTier IP"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Fix 1: room_member.cpp — bind ENet client ke local_ip jika ada ─
python3 - "$ROOM_MEMBER" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Ganti Join() signature untuk menerima local_ip
old_signature = '''void RoomMember::Join(const std::string& nick, const std::string& console_id_hash,
                      const char* server_addr, u16 server_port, u16 client_port,
                      const MacAddress& preferred_mac, const std::string& password,
                      const std::string& token) {'''

new_signature = '''void RoomMember::Join(const std::string& nick, const std::string& console_id_hash,
                      const char* server_addr, u16 server_port, u16 client_port,
                      const MacAddress& preferred_mac, const std::string& password,
                      const std::string& token, const std::string& local_ip) {'''

if old_signature in content:
    content = content.replace(old_signature, new_signature)
    print("[OK] Join() signature ditambah parameter local_ip")
else:
    print("[WARN] Signature tidak cocok, coba tanpa whitespace")

# Ganti enet_host_create(nullptr) dengan bind ke local_ip jika ada
old_create = '''    if (!room_member_impl->client) {
        room_member_impl->client = enet_host_create(nullptr, 1, NumChannels, 0, 0);
        ASSERT_MSG(room_member_impl->client != nullptr, "Could not create client");
    }'''

new_create = '''    if (!room_member_impl->client) {
        if (!local_ip.empty() && local_ip != "0.0.0.0") {
            // Bind ke local_ip (ZeroTier IP) agar routing lewat ZeroTier interface
            ENetAddress local_address{};
            enet_address_set_host(&local_address, local_ip.c_str());
            local_address.port = client_port;
            room_member_impl->client = enet_host_create(&local_address, 1, NumChannels, 0, 0);
        }
        if (!room_member_impl->client) {
            // Fallback: bind ke semua interface
            room_member_impl->client = enet_host_create(nullptr, 1, NumChannels, 0, 0);
        }
        ASSERT_MSG(room_member_impl->client != nullptr, "Could not create client");
    }'''

if old_create in content:
    content = content.replace(old_create, new_create)
    print("[OK] enet_host_create dipatch untuk bind ke local_ip")
else:
    print("[WARN] Pattern enet_host_create tidak cocok")

with open(path, 'w') as f:
    f.write(content)
print("[OK] room_member.cpp selesai")
PYEOF

# ── Fix 2: room_member.h — update deklarasi Join() ───────────────
ROOM_MEMBER_H="$PROJECT_ROOT/src/network/room_member.h"
if [ -f "$ROOM_MEMBER_H" ]; then
    python3 - "$ROOM_MEMBER_H" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

old_decl = '''    void Join(const std::string& nick, const std::string& console_id_hash,
              const char* server_addr, u16 server_port, u16 client_port = 0,
              const MacAddress& preferred_mac = NoPreferredMac,
              const std::string& password = {}, const std::string& token = {});'''

new_decl = '''    void Join(const std::string& nick, const std::string& console_id_hash,
              const char* server_addr, u16 server_port, u16 client_port = 0,
              const MacAddress& preferred_mac = NoPreferredMac,
              const std::string& password = {}, const std::string& token = {},
              const std::string& local_ip = {});'''

if old_decl in content:
    content = content.replace(old_decl, new_decl)
    with open(path, 'w') as f:
        f.write(content)
    print("[OK] room_member.h: deklarasi Join() diupdate")
else:
    # Fallback: cari tanpa exact match
    import re
    if 'void Join(' in content:
        content = re.sub(
            r'(void Join\([^)]+\));',
            lambda m: m.group(0).replace(
                'const std::string& token = {})',
                'const std::string& token = {}, const std::string& local_ip = {})'
            ) if 'local_ip' not in m.group(0) else m.group(0),
            content
        )
        with open(path, 'w') as f:
            f.write(content)
        print("[OK] room_member.h: diupdate via fallback")
    else:
        print("[WARN] Deklarasi Join tidak ditemukan di room_member.h")
PYEOF
fi

# ── Fix 3: multiplayer.cpp — pass ZeroTier IP ke Join() ──────────
python3 - "$MULTI_CPP" << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# NetPlayJoinRoom: pass ipaddress sebagai local_ip saat ZT IP
# Deteksi ZeroTier IP: mulai dengan 10. atau sesuai range
old_join_call = '''    member->Join(username, Service::CFG::GetConsoleIdHash(system),
                 ipaddress.c_str(), port, 0, Network::NoPreferredMac, password);'''

new_join_call = '''    // Jika join ke ZeroTier IP (10.x.x.x), bind client ke ZT IP
    // agar Android routing mengarahkan UDP lewat ZeroTier interface
    const std::string local_bind_ip =
        (ipaddress.rfind("10.", 0) == 0 ||
         ipaddress.rfind("172.", 0) == 0) ? ipaddress : "";

    member->Join(username, Service::CFG::GetConsoleIdHash(system),
                 ipaddress.c_str(), port, 0, Network::NoPreferredMac, password, "", local_bind_ip);'''

if old_join_call in content:
    content = content.replace(old_join_call, new_join_call)
    print("[OK] NetPlayJoinRoom: pass local_bind_ip ke Join()")
else:
    print("[WARN] Pattern Join call di JoinRoom tidak cocok")

with open(path, 'w') as f:
    f.write(content)
print("[OK] multiplayer.cpp selesai")
PYEOF

echo ""
echo -e "\033[0;32m  Fix selesai!\033[0m"
echo ""
echo "  git add ."
echo "  git commit -m \"fix: ENet client bind ke ZeroTier IP agar routing lewat ZT interface\""
echo "  git push origin DevElderLost-patch-4"
echo ""
