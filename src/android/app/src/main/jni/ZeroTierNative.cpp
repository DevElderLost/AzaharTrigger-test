// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
#include "ZeroTierNative.h"
#include "common/logging/log.h"
#include <ZeroTierSockets.h>
#include <atomic>
#include <chrono>
#include <cstring>
#include <string>
#include <thread>

namespace ZeroTierNative {

static std::atomic<bool> zt_initialized{false};
static std::atomic<bool> zt_node_online{false};
static std::atomic<bool> zt_network_ready{false};
static std::string       zt_storage_path;
static uint64_t          zt_network_id = 0;
static char              zt_assigned_ip[ZTS_IP_MAX_STR_LEN] = {0};

static void ZTEventCallback(void* msgPtr) {
    const zts_event_msg_t* msg = static_cast<zts_event_msg_t*>(msgPtr);
    if (!msg) return;
    switch (msg->event_code) {
    case ZTS_EVENT_NODE_ONLINE:
        LOG_INFO(Network, "[ZeroTier] Node online, ID: {:x}", msg->node->node_id);
        zt_node_online = true;
        break;
    case ZTS_EVENT_NODE_OFFLINE:
        LOG_WARNING(Network, "[ZeroTier] Node offline");
        zt_node_online   = false;
        zt_network_ready = false;
        break;
    case ZTS_EVENT_NETWORK_READY_IP4:
        LOG_INFO(Network, "[ZeroTier] Network IPv4 ready");
        zt_network_ready = true;
        if (msg->addr) {
            zts_inet_ntop(ZTS_AF_INET,
                &(((struct zts_sockaddr_in*)&msg->addr->addr)->sin_addr),
                zt_assigned_ip, ZTS_IP_MAX_STR_LEN);
            LOG_INFO(Network, "[ZeroTier] Assigned IP: {}", zt_assigned_ip);
        }
        break;
    case ZTS_EVENT_NETWORK_ACCESS_DENIED:
        LOG_ERROR(Network, "[ZeroTier] Access denied — node belum diauthorize");
        break;
    case ZTS_EVENT_ADDR_ADDED_IP4:
        if (msg->addr) {
            zts_inet_ntop(ZTS_AF_INET,
                &(((struct zts_sockaddr_in*)&msg->addr->addr)->sin_addr),
                zt_assigned_ip, ZTS_IP_MAX_STR_LEN);
        }
        break;
    default: break;
    }
}

ZTResult Init(const std::string& storage_path, uint64_t network_id) {
    if (zt_initialized) return ZTResult::AlreadyRunning;

    zt_storage_path  = storage_path;
    zt_network_id    = network_id;
    zt_node_online   = false;
    zt_network_ready = false;
    memset(zt_assigned_ip, 0, sizeof(zt_assigned_ip));

    if (zts_init_set_path(storage_path.c_str()) != ZTS_ERR_OK)
        return ZTResult::InitFailed;
    if (zts_init_set_event_handler(&ZTEventCallback) != ZTS_ERR_OK)
        return ZTResult::InitFailed;
    if (zts_node_start() != ZTS_ERR_OK)
        return ZTResult::InitFailed;

    constexpr int STEP_MS = 200;
    for (int e = 0; e < 15000; e += STEP_MS) {
        if (zt_node_online) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(STEP_MS));
    }
    if (!zt_node_online) { zts_node_stop(); return ZTResult::Timeout; }

    if (zts_net_join(network_id) != ZTS_ERR_OK) {
        zts_node_stop(); return ZTResult::JoinFailed;
    }

    for (int e = 0; e < 20000; e += STEP_MS) {
        if (zt_network_ready && strlen(zt_assigned_ip) > 0) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(STEP_MS));
    }
    if (!zt_network_ready || strlen(zt_assigned_ip) == 0) {
        zts_net_leave(network_id); zts_node_stop();
        return ZTResult::NetworkNotReady;
    }

    zt_initialized = true;
    return ZTResult::OK;
}

void Shutdown() {
    if (!zt_initialized) return;
    if (zt_network_id != 0) zts_net_leave(zt_network_id);
    zts_node_stop();
    zt_initialized   = false;
    zt_node_online   = false;
    zt_network_ready = false;
    zt_network_id    = 0;
    memset(zt_assigned_ip, 0, sizeof(zt_assigned_ip));
}

bool        IsReady()       { return zt_initialized && zt_node_online && zt_network_ready; }
std::string GetAssignedIP() { return std::string(zt_assigned_ip); }

uint64_t GetNodeID() {
    if (!zt_node_online) return 0;
    uint64_t id = 0; zts_node_get_id(&id); return id;
}

uint64_t ParseNetworkId(const std::string& hex_str) {
    try { return std::stoull(hex_str, nullptr, 16); } catch (...) { return 0; }
}

} // namespace ZeroTierNative
