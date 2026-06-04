// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
#pragma once
#include <cstdint>
#include <string>

namespace ZeroTierNative {

enum class ZTResult {
    OK = 0,
    AlreadyRunning,
    InitFailed,
    JoinFailed,
    NetworkNotReady,
    Timeout,
};

ZTResult    Init(const std::string& storage_path, uint64_t network_id);
void        Shutdown();
bool        IsReady();
std::string GetAssignedIP();
uint64_t    GetNodeID();
uint64_t    ParseNetworkId(const std::string& hex_str);

} // namespace ZeroTierNative
