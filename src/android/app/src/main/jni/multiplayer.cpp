// Copyright 2024 Mandarine Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#include "id_cache.h"
#include "multiplayer.h"
#include "jni/android_common/android_common.h"
#include "core/core.h"
#include "common/logging/log.h"
#include <thread>
#include <chrono>
#include <network/network_settings.h>
#include "network/announce_multiplayer_session.h"
#include "core/hle/service/cfg/cfg.h"
#include "ZeroTierNative.h"


AndroidMultiplayer::AndroidMultiplayer(Core::System& system_,
                                       std::shared_ptr<Network::AnnounceMultiplayerSession> session)
    : system{system_}, announce_multiplayer_session(session) {}

AndroidMultiplayer::~AndroidMultiplayer() = default;


void AndroidMultiplayer::AddNetPlayMessage(jint type, jstring msg) {
    IDCache::GetEnvForThread()->CallStaticVoidMethod(IDCache::GetNativeLibraryClass(),
                                                     IDCache::GetAddNetPlayMessage(), type, msg);
}

void AndroidMultiplayer::AddNetPlayMessage(int type, const std::string& msg) {
    JNIEnv* env = IDCache::GetEnvForThread();
    AddNetPlayMessage(type, ToJString(env, msg));
}

void AndroidMultiplayer::ClearChat() {
    IDCache::GetEnvForThread()->CallStaticVoidMethod(IDCache::GetNativeLibraryClass(),
                                                     IDCache::ClearChat());
}


bool AndroidMultiplayer::NetworkInit() {
    bool result = Network::Init();

    if (!result) {
        return false;
    }

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
        member->BindOnStatusMessageReceived([this](const Network::StatusMessageEntry& status_message) {
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

    return true;
}

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


NetPlayStatus AndroidMultiplayer::NetPlayCreateRoom(const std::string& ipaddress, int port,
                              const std::string& username, const std::string& preferedGameName, const u64 &preferedGameId, const std::string& password,
                              const std::string& room_name, int max_players) {


    auto member = Network::GetRoomMember().lock();
    if (!member) {
        return NetPlayStatus::NETWORK_ERROR;
    }

    if (member->GetState() == Network::RoomMember::State::Joining || member->IsConnected()) {
        return NetPlayStatus::ALREADY_IN_ROOM;
    }

    auto room = Network::GetRoom().lock();
    if (!room) {
        return NetPlayStatus::NETWORK_ERROR;
    }

    if (room_name.length() < 3 || room_name.length() > 20) {
        return NetPlayStatus::CREATE_ROOM_ERROR;
    }

    if (!room->Create(room_name, "", ipaddress, port, password,
                     std::min(max_players, 16), NetSettings::values.citra_username, preferedGameName, preferedGameId, std::make_unique<Network::VerifyUser::NullBackend>(), {})) {
        return NetPlayStatus::CREATE_ROOM_ERROR;
    }

    // Beri waktu room untuk fully initialize sebelum join
    std::this_thread::sleep_for(std::chrono::milliseconds(300));

    // Host join ke localhost karena room server ada di device yang sama.
    // Menggunakan ZeroTier IP (ipaddress) akan gagal karena ENet tidak bisa
    // connect ke virtual interface ZeroTier dari device itu sendiri.
    // Client lain tetap join ke ZeroTier IP host dari device mereka.
    member->Join(username, Service::CFG::GetConsoleIdHash(system), "127.0.0.1", port, 0, Network::NoPreferredMac, password);

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
    return NetPlayStatus::CREATE_ROOM_ERROR;
}

NetPlayStatus AndroidMultiplayer::NetPlayJoinRoom(const std::string& ipaddress, int port,
                            const std::string& username, const std::string& password) {
    auto member = Network::GetRoomMember().lock();
    if (!member) {
        return NetPlayStatus::NETWORK_ERROR;
    }

    if (member->GetState() == Network::RoomMember::State::Joining || member->IsConnected()) {
        return NetPlayStatus::ALREADY_IN_ROOM;
    }

    member->Join(username, Service::CFG::GetConsoleIdHash(system), ipaddress.c_str(), port, 0, Network::NoPreferredMac, password);

    // Wait for the connection and join process to complete.
    // Use a longer timeout (5000ms = 5 seconds) to account for slower LAN networks.
    // This matches the ConnectionTimeoutMs used in RoomMember::Join()
    // ZeroTier membutuhkan waktu lebih lama untuk handshake via internet
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
    }

    // Join failed - check the error state
    if (!member->IsConnected()) {
        return NetPlayStatus::COULD_NOT_CONNECT;
    }

    return NetPlayStatus::WRONG_PASSWORD;
}

void AndroidMultiplayer::NetPlaySendMessage(const std::string& msg) {
    if (auto room = Network::GetRoomMember().lock()) {
        if (room->GetState() != Network::RoomMember::State::Joined &&
            room->GetState() != Network::RoomMember::State::Moderator) {

            return;
        }
        room->SendChatMessage(msg);
    }
}

void AndroidMultiplayer::NetPlayKickUser(const std::string& username) {
    if (auto room = Network::GetRoomMember().lock()) {
        auto members = room->GetMemberInformation();
        auto it = std::find_if(members.begin(), members.end(),
                               [&username](const Network::RoomMember::MemberInformation& member) {
                                   return member.nickname == username;
                               });
        if (it != members.end()) {
            room->SendModerationRequest(Network::RoomMessageTypes::IdModKick, username);
        }
    }
}

void AndroidMultiplayer::NetPlayBanUser(const std::string& username) {
    if (auto room = Network::GetRoomMember().lock()) {
        auto members = room->GetMemberInformation();
        auto it = std::find_if(members.begin(), members.end(),
                               [&username](const Network::RoomMember::MemberInformation& member) {
                                   return member.nickname == username;
                               });
        if (it != members.end()) {
            room->SendModerationRequest(Network::RoomMessageTypes::IdModBan, username);
        }
    }
}

void AndroidMultiplayer::NetPlayUnbanUser(const std::string& username) {
    if (auto room = Network::GetRoomMember().lock()) {
        room->SendModerationRequest(Network::RoomMessageTypes::IdModUnban, username);
    }
}

std::vector<std::string> AndroidMultiplayer::NetPlayRoomInfo() {
    std::vector<std::string> info_list;
    if (auto room = Network::GetRoomMember().lock()) {
        auto members = room->GetMemberInformation();
        if (!members.empty()) {
            // name and max players
            auto room_info = room->GetRoomInformation();
            info_list.push_back(room_info.name + "|" + std::to_string(room_info.member_slots));
            // all members
            for (const auto& member : members) {
                info_list.push_back(member.nickname);
            }
        }
    }
    return info_list;
}

bool AndroidMultiplayer::NetPlayIsJoined() {
    auto member = Network::GetRoomMember().lock();
    if (!member) {
        return false;
    }

    return (member->GetState() == Network::RoomMember::State::Joined ||
            member->GetState() == Network::RoomMember::State::Moderator);
}

bool AndroidMultiplayer::NetPlayIsHostedRoom() {
    if (auto room = Network::GetRoom().lock()) {
        return room->GetState() == Network::Room::State::Open;
    }
    return false;
}

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

void AndroidMultiplayer::NetworkShutdown() {
    Network::Shutdown();
}

bool AndroidMultiplayer::NetPlayIsModerator() {
    auto member = Network::GetRoomMember().lock();
    if (!member) {
        return false;
    }
    return member->GetState() == Network::RoomMember::State::Moderator;
}

std::vector<std::string> AndroidMultiplayer::NetPlayGetPublicRooms() {
    std::vector<std::string> room_list;

    if (auto session = announce_multiplayer_session.lock()) {
        auto rooms = session->GetRoomList();
        for (const auto &room: rooms) {
            room_list.push_back(room.name + "|" +
                                (room.has_password ? "1" : "0") + "|" +
                                std::to_string(room.max_player) + "|" +
                                room.ip + "|" +
                                std::to_string(room.port) + "|" +
                                room.description + "|" +
                                room.owner + "|" +
                                std::to_string(room.preferred_game_id) + "|" +
                                room.preferred_game);


            for (const auto &member: room.members) {
                room_list.push_back("MEMBER|" + room.name + "|" +
                                    member.username + "|" +
                                    member.nickname + "|" +
                                    std::to_string(member.game_id) + "|" +
                                    member.game_name);
            }
        }

    }
    return room_list;

}


std::vector<std::string> AndroidMultiplayer::NetPlayGetBanList() {
    std::vector<std::string> ban_list;
    if (auto room = Network::GetRoom().lock()) {
        auto [username_bans, ip_bans] = room->GetBanList();

        // Add username bans
        for (const auto& username : username_bans) {
            ban_list.push_back(username);
        }

        // Add IP bans
        for (const auto& ip : ip_bans) {
            ban_list.push_back(ip);
        }
    }
    return ban_list;
}
