// Copyright 2017 Citra Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#include <algorithm>
#include <atomic>
#include <chrono>
#include <deque>
#include <list>
#include <mutex>
#include <set>
#include <thread>
#include "common/assert.h"
#include "enet/enet.h"
#include "network/packet.h"
#include "network/room_member.h"

namespace Network {

constexpr u32 ConnectionTimeoutMs = 5000;

// FIX MEMORY LEAK #3: Batas maksimum antrian paket kiriman.
// Tanpa batas ini, send_list bisa tumbuh tak terbatas jika game mengirim
// wifi packet lebih cepat dari ENet bisa flush → memory terus naik → lag/OOM.
constexpr std::size_t MaxSendQueueSize = 256;

// FIX MEMORY LEAK #4: Ganti std::list → std::deque untuk send_list.
// std::list mengalokasikan node heap individual per elemen (tiap WifiPacket = alokasi baru).
// std::deque menggunakan blok memori kontinu → jauh lebih cache-friendly dan
// mengurangi fragmentasi heap yang menyebabkan lag GC/allocator Android.

class RoomMember::RoomMemberImpl {
public:
    ENetHost* client = nullptr; ///< ENet network interface.
    ENetPeer* server = nullptr; ///< The server peer the client is connected to

    /// Information about the clients connected to the same room as us.
    MemberList member_information;
    /// Information about the room we're connected to.
    RoomInformation room_information;

    /// The current game name, id and version
    GameInfo current_game_info;

    std::atomic<State> state{State::Idle}; ///< Current state of the RoomMember.
    void SetState(const State new_state);
    void SetError(const Error new_error);
    bool IsConnected() const;

    std::string nickname; ///< The nickname of this member.

    std::string username;              ///< The username of this member.
    mutable std::mutex username_mutex; ///< Mutex for locking username.

    MacAddress mac_address; ///< The mac_address of this member.

    std::mutex network_mutex; ///< Mutex that controls access to the `client` variable.
    /// Thread that receives and dispatches network packets
    std::unique_ptr<std::thread> loop_thread;
    std::mutex send_list_mutex;  ///< Mutex that controls access to the `send_list` variable.
    // FIX #4: std::deque menggantikan std::list untuk performa alokasi lebih baik
    std::deque<Packet> send_list;

    template <typename T>
    using CallbackSet = std::set<CallbackHandle<T>>;
    std::mutex callback_mutex; ///< The mutex used for handling callbacks

    class Callbacks {
    public:
        template <typename T>
        CallbackSet<T>& Get();

    private:
        CallbackSet<WifiPacket> callback_set_wifi_packet;
        CallbackSet<ChatEntry> callback_set_chat_messages;
        CallbackSet<StatusMessageEntry> callback_set_status_messages;
        CallbackSet<RoomInformation> callback_set_room_information;
        CallbackSet<State> callback_set_state;
        CallbackSet<Error> callback_set_error;
        CallbackSet<Room::BanList> callback_set_ban_list;
    };
    Callbacks callbacks; ///< All CallbackSets to all events

    void MemberLoop();

    void StartLoop();

    /**
     * Sends data to the room. It will be send on channel 0 with flag RELIABLE
     * @param packet The data to send
     */
    void Send(Packet&& packet);

    /**
     * Sends a request to the server, asking for permission to join a room with the specified
     * nickname and preferred mac.
     * @params nickname The desired nickname.
     * @params console_id_hash A hash of the Console ID.
     * @params preferred_mac The preferred MAC address to use in the room, the NoPreferredMac tells
     * @params password The password for the room
     * the server to assign one for us.
     */
    void SendJoinRequest(const std::string& nickname, const std::string& console_id_hash,
                         const MacAddress& preferred_mac = NoPreferredMac,
                         const std::string& password = "", const std::string& token = "");

    /**
     * Extracts a MAC Address from a received ENet packet.
     * @param event The ENet event that was received.
     */
    void HandleJoinPacket(const ENetEvent* event);
    /**
     * Extracts RoomInformation and MemberInformation from a received ENet packet.
     * @param event The ENet event that was received.
     */
    void HandleRoomInformationPacket(const ENetEvent* event);

    /**
     * Extracts a WifiPacket from a received ENet packet.
     * @param event The  ENet event that was received.
     */
    void HandleWifiPackets(const ENetEvent* event);

    /**
     * Extracts a chat entry from a received ENet packet and adds it to the chat queue.
     * @param event The ENet event that was received.
     */
    void HandleChatPacket(const ENetEvent* event);

    /**
     * Extracts a system message entry from a received ENet packet and adds it to the system message
     * queue.
     * @param event The ENet event that was received.
     */
    void HandleStatusMessagePacket(const ENetEvent* event);

    /**
     * Extracts a ban list request response from a received ENet packet.
     * @param event The ENet event that was received.
     */
    void HandleModBanListResponsePacket(const ENetEvent* event);

    /**
     * Disconnects the RoomMember from the Room
     */
    void Disconnect();

    template <typename T>
    void Invoke(const T& data);

    template <typename T>
    CallbackHandle<T> Bind(std::function<void(const T&)> callback);
};

// RoomMemberImpl
void RoomMember::RoomMemberImpl::SetState(const State new_state) {
    if (state != new_state) {
        state = new_state;
        Invoke<State>(state);
    }
}

void RoomMember::RoomMemberImpl::SetError(const Error new_error) {
    Invoke<Error>(new_error);
}

bool RoomMember::RoomMemberImpl::IsConnected() const {
    return state == State::Joining || state == State::Joined || state == State::Moderator;
}

void RoomMember::RoomMemberImpl::MemberLoop() {
    // Receive packets while the connection is open
    while (IsConnected()) {
        ENetEvent event;

        // FIX BUG DISCONNECT #1: Pisahkan scope network_mutex dari operasi send.
        // Sebelumnya mutex di-hold SELURUH iterasi termasuk send & flush,
        // menyebabkan game thread (SendWifiPacket) terkunci → buffer overflow → disconnect palsu.
        {
            std::lock_guard network_lock(network_mutex);
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
                            LOG_WARNING(Network,
                                        "Received join success but room information not yet "
                                        "available. This is normal for LAN rooms with packet "
                                        "reordering.");
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
        } // ← FIX #1: network_mutex dilepas di sini, sebelum proses send

        // Ambil dan kirim paket dari antrian (tanpa hold network_mutex)
        std::deque<Packet> packets;
        {
            std::lock_guard send_list_lock(send_list_mutex);
            packets.swap(send_list);
        }
        for (auto& packet : packets) {
            ENetPacket* enetPacket = enet_packet_create(packet.GetData(), packet.GetDataSize(),
                                                        ENET_PACKET_FLAG_RELIABLE);
            enet_peer_send(server, 0, enetPacket);
        }
        // FIX #1: flush juga dengan scope mutex singkat
        {
            std::lock_guard network_lock(network_mutex);
            enet_host_flush(client);
        }
    }
    Disconnect();
};

void RoomMember::RoomMemberImpl::StartLoop() {
    loop_thread = std::make_unique<std::thread>(&RoomMember::RoomMemberImpl::MemberLoop, this);
}

void RoomMember::RoomMemberImpl::Send(Packet&& packet) {
    std::lock_guard lock(send_list_mutex);
    // FIX MEMORY LEAK #3: Buang paket paling lama jika antrian sudah penuh.
    // Tanpa ini, jika game mengirim wifi packet lebih cepat dari flush,
    // send_list tumbuh tak terbatas → RAM terus naik → lag/OOM crash.
    if (send_list.size() >= MaxSendQueueSize) {
        send_list.pop_front(); // Buang paket terlama (drop oldest)
    }
    send_list.push_back(std::move(packet));
}

void RoomMember::RoomMemberImpl::SendJoinRequest(const std::string& nickname,
                                                 const std::string& console_id_hash,
                                                 const MacAddress& preferred_mac,
                                                 const std::string& password,
                                                 const std::string& token) {
    Packet packet;
    packet << static_cast<u8>(IdJoinRequest);
    packet << nickname;
    packet << console_id_hash;
    packet << preferred_mac;
    packet << network_version;
    packet << password;
    packet << token;
    Send(std::move(packet));
}

void RoomMember::RoomMemberImpl::HandleRoomInformationPacket(const ENetEvent* event) {
    Packet packet;
    packet.Append(event->packet->data, event->packet->dataLength);

    // Ignore the first byte, which is the message id.
    packet.IgnoreBytes(sizeof(u8)); // Ignore the message type

    RoomInformation info{};
    packet >> info.name;
    packet >> info.description;
    packet >> info.member_slots;
    packet >> info.port;
    packet >> info.preferred_game;
    packet >> info.host_username;
    room_information.name = info.name;
    room_information.description = info.description;
    room_information.member_slots = info.member_slots;
    room_information.port = info.port;
    room_information.preferred_game = info.preferred_game;
    room_information.host_username = info.host_username;

    u32 num_members;
    packet >> num_members;
    // FIX MEMORY LEAK #5: Tambah shrink_to_fit setelah resize agar kapasitas
    // vector dikembalikan ke ukuran yang tepat, mencegah memory yang terpakai
    // saat member banyak tidak dibebaskan saat member berkurang.
    member_information.resize(num_members);
    member_information.shrink_to_fit();

    for (auto& member : member_information) {
        packet >> member.nickname;
        packet >> member.mac_address;
        packet >> member.game_info.name;
        packet >> member.game_info.id;
        packet >> member.username;
        packet >> member.display_name;
        packet >> member.avatar_url;

        {
            std::lock_guard lock(username_mutex);
            if (member.nickname == nickname) {
                username = member.username;
            }
        }
    }
    Invoke(room_information);
}

void RoomMember::RoomMemberImpl::HandleJoinPacket(const ENetEvent* event) {
    Packet packet;
    packet.Append(event->packet->data, event->packet->dataLength);

    // Ignore the first byte, which is the message id.
    packet.IgnoreBytes(sizeof(u8)); // Ignore the message type

    // Parse the MAC Address from the packet
    packet >> mac_address;
}

void RoomMember::RoomMemberImpl::HandleWifiPackets(const ENetEvent* event) {
    WifiPacket wifi_packet{};
    Packet packet;
    packet.Append(event->packet->data, event->packet->dataLength);

    // Ignore the first byte, which is the message id.
    packet.IgnoreBytes(sizeof(u8)); // Ignore the message type

    // Parse the WifiPacket from the packet
    u8 frame_type;
    packet >> frame_type;
    WifiPacket::PacketType type = static_cast<WifiPacket::PacketType>(frame_type);

    wifi_packet.type = type;
    packet >> wifi_packet.channel;
    packet >> wifi_packet.transmitter_address;
    packet >> wifi_packet.destination_address;
    packet >> wifi_packet.data;

    Invoke<WifiPacket>(wifi_packet);
}

void RoomMember::RoomMemberImpl::HandleChatPacket(const ENetEvent* event) {
    Packet packet;
    packet.Append(event->packet->data, event->packet->dataLength);

    // Ignore the first byte, which is the message id.
    packet.IgnoreBytes(sizeof(u8));

    ChatEntry chat_entry{};
    packet >> chat_entry.nickname;
    packet >> chat_entry.username;
    packet >> chat_entry.message;
    chat_entry.message.resize(std::min(chat_entry.message.find('\0'), chat_entry.message.size()));
    Invoke<ChatEntry>(chat_entry);
}

void RoomMember::RoomMemberImpl::HandleStatusMessagePacket(const ENetEvent* event) {
    Packet packet;
    packet.Append(event->packet->data, event->packet->dataLength);

    // Ignore the first byte, which is the message id.
    packet.IgnoreBytes(sizeof(u8));

    StatusMessageEntry status_message_entry{};
    u8 type{};
    packet >> type;
    status_message_entry.type = static_cast<StatusMessageTypes>(type);
    packet >> status_message_entry.nickname;
    packet >> status_message_entry.username;
    Invoke<StatusMessageEntry>(status_message_entry);
}

void RoomMember::RoomMemberImpl::HandleModBanListResponsePacket(const ENetEvent* event) {
    Packet packet;
    packet.Append(event->packet->data, event->packet->dataLength);

    // Ignore the first byte, which is the message id.
    packet.IgnoreBytes(sizeof(u8));

    Room::BanList ban_list = {};
    packet >> ban_list.first;
    packet >> ban_list.second;
    Invoke<Room::BanList>(ban_list);
}

void RoomMember::RoomMemberImpl::Disconnect() {
    member_information.clear();
    // FIX MEMORY LEAK #5: Bebaskan kapasitas vector setelah clear
    member_information.shrink_to_fit();

    room_information.member_slots = 0;
    room_information.name.clear();

    // FIX MEMORY LEAK #6: Bersihkan antrian kirim yang tersisa saat disconnect
    // Tanpa ini, paket yang belum sempat terkirim tetap menempati memori.
    {
        std::lock_guard lock(send_list_mutex);
        send_list.clear();
        // shrink_to_fit untuk deque membebaskan semua blok memori internal
        send_list.shrink_to_fit();
    }

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

template <>
RoomMember::RoomMemberImpl::CallbackSet<WifiPacket>& RoomMember::RoomMemberImpl::Callbacks::Get() {
    return callback_set_wifi_packet;
}

template <>
RoomMember::RoomMemberImpl::CallbackSet<RoomMember::State>&
RoomMember::RoomMemberImpl::Callbacks::Get() {
    return callback_set_state;
}

template <>
RoomMember::RoomMemberImpl::CallbackSet<RoomMember::Error>&
RoomMember::RoomMemberImpl::Callbacks::Get() {
    return callback_set_error;
}

template <>
RoomMember::RoomMemberImpl::CallbackSet<RoomInformation>&
RoomMember::RoomMemberImpl::Callbacks::Get() {
    return callback_set_room_information;
}

template <>
RoomMember::RoomMemberImpl::CallbackSet<ChatEntry>& RoomMember::RoomMemberImpl::Callbacks::Get() {
    return callback_set_chat_messages;
}

template <>
RoomMember::RoomMemberImpl::CallbackSet<StatusMessageEntry>&
RoomMember::RoomMemberImpl::Callbacks::Get() {
    return callback_set_status_messages;
}

template <>
RoomMember::RoomMemberImpl::CallbackSet<Room::BanList>&
RoomMember::RoomMemberImpl::Callbacks::Get() {
    return callback_set_ban_list;
}

template <typename T>
void RoomMember::RoomMemberImpl::Invoke(const T& data) {
    std::lock_guard lock(callback_mutex);
    CallbackSet<T> callback_set = callbacks.Get<T>();
    for (auto const& callback : callback_set)
        (*callback)(data);
}

template <typename T>
RoomMember::CallbackHandle<T> RoomMember::RoomMemberImpl::Bind(
    std::function<void(const T&)> callback) {
    std::lock_guard lock(callback_mutex);
    CallbackHandle<T> handle;
    handle = std::make_shared<std::function<void(const T&)>>(callback);
    callbacks.Get<T>().insert(handle);
    return handle;
}

// RoomMember
RoomMember::RoomMember() : room_member_impl{std::make_unique<RoomMemberImpl>()} {}

RoomMember::~RoomMember() {
    ASSERT_MSG(!IsConnected(), "RoomMember is being destroyed while connected");
    if (room_member_impl->loop_thread) {
        Leave();
    }
}

RoomMember::State RoomMember::GetState() const {
    return room_member_impl->state;
}

const RoomMember::MemberList& RoomMember::GetMemberInformation() const {
    return room_member_impl->member_information;
}

const std::string& RoomMember::GetNickname() const {
    return room_member_impl->nickname;
}

const std::string& RoomMember::GetUsername() const {
    std::lock_guard lock(room_member_impl->username_mutex);
    return room_member_impl->username;
}

const MacAddress& RoomMember::GetMacAddress() const {
    ASSERT_MSG(IsConnected(), "Tried to get MAC address while not connected");
    return room_member_impl->mac_address;
}

RoomInformation RoomMember::GetRoomInformation() const {
    return room_member_impl->room_information;
}

void RoomMember::Join(const std::string& nick, const std::string& console_id_hash,
                      const char* server_addr, u16 server_port, u16 client_port,
                      const MacAddress& preferred_mac, const std::string& password,
                      const std::string& token) {
    // If the member is connected, kill the connection first
    if (room_member_impl->loop_thread && room_member_impl->loop_thread->joinable()) {
        Leave();
    }
    // If the thread isn't running but the ptr still exists, reset it
    else if (room_member_impl->loop_thread) {
        room_member_impl->loop_thread.reset();
    }

    if (!room_member_impl->client) {
        room_member_impl->client = enet_host_create(nullptr, 1, NumChannels, 0, 0);
        ASSERT_MSG(room_member_impl->client != nullptr, "Could not create client");
    }

    room_member_impl->SetState(State::Joining);

    ENetAddress address{};
    enet_address_set_host(&address, server_addr);
    address.port = server_port;
    room_member_impl->server =
        enet_host_connect(room_member_impl->client, &address, NumChannels, 0);

    if (!room_member_impl->server) {
        room_member_impl->SetState(State::Idle);
        room_member_impl->SetError(Error::UnknownError);
        return;
    }

    ENetEvent event{};
    int net = enet_host_service(room_member_impl->client, &event, ConnectionTimeoutMs);
    if (net > 0 && event.type == ENET_EVENT_TYPE_CONNECT) {
        // FIX BUG DISCONNECT #2: Set ENet peer timeout agar tidak disconnect
        // saat ada spike latency pendek pada jaringan LAN/Hotspot lokal.
        // Default ENet timeout sangat agresif (~500ms), sering false-positive
        // pada Android WiFi yang bisa spike sesaat saat screen lock, dll.
        enet_peer_timeout(room_member_impl->server,
            0,      // timeout_limit: 0 = gunakan default ENet (32 round-trips)
            4000,   // timeout_minimum: minimal 4 detik sebelum mulai timeout
            30000   // timeout_maximum: maksimal 30 detik sebelum force disconnect
        );

        room_member_impl->nickname = nick;
        room_member_impl->StartLoop();
        room_member_impl->SendJoinRequest(nick, console_id_hash, preferred_mac, password, token);
        SendGameInfo(room_member_impl->current_game_info);
    } else {
        enet_peer_disconnect(room_member_impl->server, 0);
        room_member_impl->SetState(State::Idle);
        room_member_impl->SetError(Error::CouldNotConnect);
    }
}

bool RoomMember::IsConnected() const {
    return room_member_impl->IsConnected();
}

void RoomMember::SendWifiPacket(const WifiPacket& wifi_packet) {
    Packet packet;
    packet << static_cast<u8>(IdWifiPacket);
    packet << static_cast<u8>(wifi_packet.type);
    packet << wifi_packet.channel;
    packet << wifi_packet.transmitter_address;
    packet << wifi_packet.destination_address;
    packet << wifi_packet.data;
    room_member_impl->Send(std::move(packet));
}

void RoomMember::SendChatMessage(const std::string& message) {
    Packet packet;
    packet << static_cast<u8>(IdChatMessage);
    packet << message;
    room_member_impl->Send(std::move(packet));
}

void RoomMember::SendGameInfo(const GameInfo& game_info) {
    room_member_impl->current_game_info = game_info;
    if (!IsConnected())
        return;

    Packet packet;
    packet << static_cast<u8>(IdSetGameInfo);
    packet << game_info.name;
    packet << game_info.id;
    room_member_impl->Send(std::move(packet));
}

void RoomMember::SendModerationRequest(RoomMessageTypes type, const std::string& nickname) {
    ASSERT_MSG(type == IdModKick || type == IdModBan || type == IdModUnban,
               "type is not a moderation request");
    if (!IsConnected())
        return;

    Packet packet;
    packet << static_cast<u8>(type);
    packet << nickname;
    room_member_impl->Send(std::move(packet));
}

void RoomMember::RequestBanList() {
    if (!IsConnected())
        return;

    Packet packet;
    packet << static_cast<u8>(IdModGetBanList);
    room_member_impl->Send(std::move(packet));
}

RoomMember::CallbackHandle<RoomMember::State> RoomMember::BindOnStateChanged(
    std::function<void(const RoomMember::State&)> callback) {
    return room_member_impl->Bind(callback);
}

RoomMember::CallbackHandle<RoomMember::Error> RoomMember::BindOnError(
    std::function<void(const RoomMember::Error&)> callback) {
    return room_member_impl->Bind(callback);
}

RoomMember::CallbackHandle<WifiPacket> RoomMember::BindOnWifiPacketReceived(
    std::function<void(const WifiPacket&)> callback) {
    return room_member_impl->Bind(callback);
}

RoomMember::CallbackHandle<RoomInformation> RoomMember::BindOnRoomInformationChanged(
    std::function<void(const RoomInformation&)> callback) {
    return room_member_impl->Bind(callback);
}

RoomMember::CallbackHandle<ChatEntry> RoomMember::BindOnChatMessageRecieved(
    std::function<void(const ChatEntry&)> callback) {
    return room_member_impl->Bind(callback);
}

RoomMember::CallbackHandle<StatusMessageEntry> RoomMember::BindOnStatusMessageReceived(
    std::function<void(const StatusMessageEntry&)> callback) {
    return room_member_impl->Bind(callback);
}

RoomMember::CallbackHandle<Room::BanList> RoomMember::BindOnBanListReceived(
    std::function<void(const Room::BanList&)> callback) {
    return room_member_impl->Bind(callback);
}

template <typename T>
void RoomMember::Unbind(CallbackHandle<T> handle) {
    std::lock_guard lock(room_member_impl->callback_mutex);
    room_member_impl->callbacks.Get<T>().erase(handle);
}

void RoomMember::Leave() {
    room_member_impl->SetState(State::Idle);
    room_member_impl->loop_thread->join();
    room_member_impl->loop_thread.reset();

    enet_host_destroy(room_member_impl->client);
    room_member_impl->client = nullptr;
}

template void RoomMember::Unbind(CallbackHandle<WifiPacket>);
template void RoomMember::Unbind(CallbackHandle<RoomMember::State>);
template void RoomMember::Unbind(CallbackHandle<RoomMember::Error>);
template void RoomMember::Unbind(CallbackHandle<RoomInformation>);
template void RoomMember::Unbind(CallbackHandle<ChatEntry>);
template void RoomMember::Unbind(CallbackHandle<StatusMessageEntry>);
template void RoomMember::Unbind(CallbackHandle<Room::BanList>);

} // namespace Network
