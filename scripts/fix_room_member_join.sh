#!/bin/bash
# fix_room_member_join.sh — Fix signature Join() di room_member.cpp dan .h
# Tambah parameter local_ip untuk bind ENet ke ZeroTier interface

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
ROOM_MEMBER_CPP="$PROJECT_ROOT/src/network/room_member.cpp"
ROOM_MEMBER_H="$PROJECT_ROOT/src/network/room_member.h"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Fix: Join() signature + ENet bind ke ZeroTier IP"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Fix room_member.h — tambah local_ip ke deklarasi ─────────────
[ -f "$ROOM_MEMBER_H" ] || { echo "[ERROR] room_member.h tidak ditemukan"; exit 1; }

python3 - "$ROOM_MEMBER_H" << 'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Cari deklarasi Join() yang ada
old_decl = re.search(
    r'void Join\(const std::string& nick.*?const std::string& token.*?=.*?\{?\}?\);',
    content, re.DOTALL
)
if old_decl:
    old_str = old_decl.group(0)
    if 'local_ip' not in old_str:
        new_str = old_str.rstrip(');') + ',\n              const std::string& local_ip = {});'
        content = content.replace(old_str, new_str)
        with open(path, 'w') as f:
            f.write(content)
        print("[OK] room_member.h: local_ip ditambahkan ke Join()")
    else:
        print("[INFO] room_member.h: local_ip sudah ada")
else:
    print("[WARN] Deklarasi Join() tidak ditemukan di room_member.h")
    # Tampilkan baris yang ada
    for i, line in enumerate(content.split('\n'), 1):
        if 'Join' in line:
            print(f"  Baris {i}: {line.strip()}")
PYEOF

# ── Fix room_member.cpp — update implementasi Join() ─────────────
[ -f "$ROOM_MEMBER_CPP" ] || { echo "[ERROR] room_member.cpp tidak ditemukan"; exit 1; }

python3 - "$ROOM_MEMBER_CPP" << 'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# ── 1. Update signature implementasi Join() ───────────────────────
old_impl_sig = '''void RoomMember::Join(const std::string& nick, const std::string& console_id_hash,
                      const char* server_addr, u16 server_port, u16 client_port,
                      const MacAddress& preferred_mac, const std::string& password,
                      const std::string& token) {'''

new_impl_sig = '''void RoomMember::Join(const std::string& nick, const std::string& console_id_hash,
                      const char* server_addr, u16 server_port, u16 client_port,
                      const MacAddress& preferred_mac, const std::string& password,
                      const std::string& token, const std::string& local_ip) {'''

if old_impl_sig in content:
    content = content.replace(old_impl_sig, new_impl_sig)
    print("[OK] Signature Join() diupdate")
else:
    print("[WARN] Signature implementasi Join() tidak cocok")

# ── 2. Ganti enet_host_create(nullptr) dengan bind ke local_ip ───
old_create = '''    if (!room_member_impl->client) {
        room_member_impl->client = enet_host_create(nullptr, 1, NumChannels, 0, 0);
        ASSERT_MSG(room_member_impl->client != nullptr, "Could not create client");
    }'''

new_create = '''    if (!room_member_impl->client) {
        if (!local_ip.empty() && local_ip != "0.0.0.0") {
            // Bind ke ZeroTier IP agar routing lewat ZeroTier interface
            ENetAddress local_addr{};
            enet_address_set_host(&local_addr, local_ip.c_str());
            local_addr.port = client_port;
            room_member_impl->client = enet_host_create(&local_addr, 1, NumChannels, 0, 0);
        }
        if (!room_member_impl->client) {
            // Fallback: bind ke semua interface (tanpa ZeroTier)
            room_member_impl->client = enet_host_create(nullptr, 1, NumChannels, 0, 0);
        }
        ASSERT_MSG(room_member_impl->client != nullptr, "Could not create client");
    }'''

if old_create in content:
    content = content.replace(old_create, new_create)
    print("[OK] enet_host_create dipatch untuk ZeroTier bind")
else:
    print("[WARN] Pattern enet_host_create tidak cocok")

with open(path, 'w') as f:
    f.write(content)
print("[OK] room_member.cpp selesai")
PYEOF

# ── Fix multiplayer.cpp — pass local_ip ke Join() ─────────────────
MULTI_CPP="$PROJECT_ROOT/src/android/app/src/main/jni/multiplayer.cpp"
if [ -f "$MULTI_CPP" ]; then
    python3 - "$MULTI_CPP" << 'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Cari semua panggilan member->Join() di JoinRoom
# dan tambahkan local_bind_ip sebagai parameter terakhir

# Deteksi apakah sudah ada local_bind_ip
if 'local_bind_ip' in content:
    print("[INFO] local_bind_ip sudah ada di multiplayer.cpp")
else:
    # Tambah deteksi ZT IP dan pass ke Join() di NetPlayJoinRoom
    old_join = '''    member->Join(username, Service::CFG::GetConsoleIdHash(system),
                 ipaddress.c_str(), port, 0, Network::NoPreferredMac, password);'''

    new_join = '''    // Jika join ke ZeroTier IP, bind client ke ZT IP lokal
    // agar Android routing lewat ZeroTier interface, bukan default route
    const std::string local_bind_ip =
        (ipaddress.size() >= 3 &&
         (ipaddress.substr(0,3) == "10." ||
          ipaddress.substr(0,4) == "172.")) ? ipaddress : "";

    member->Join(username, Service::CFG::GetConsoleIdHash(system),
                 ipaddress.c_str(), port, 0, Network::NoPreferredMac,
                 password, "", local_bind_ip);'''

    if old_join in content:
        content = content.replace(old_join, new_join)
        print("[OK] NetPlayJoinRoom: local_bind_ip ditambahkan")
    else:
        print("[WARN] Pattern Join di JoinRoom tidak cocok, coba variasi...")
        # Cari pola yang lebih fleksibel
        pattern = r'(member->Join\(username[^;]+password[^;]*\);)'
        matches = list(re.finditer(pattern, content, re.DOTALL))
        print(f"  Ditemukan {len(matches)} panggilan Join()")
        for m in matches:
            print(f"  {m.group(0)[:100]}...")

    with open(path, 'w') as f:
        f.write(content)
PYEOF
fi

echo ""
echo -e "\033[0;32m  Fix selesai!\033[0m"
echo ""
echo "  git add ."
echo "  git commit -m \"fix: Join() signature + ENet bind ZeroTier IP\""
echo "  git push origin DevElderLost-patch-4"
echo ""
