// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
//
// ZeroTierNative.h — wrapper libzt via AAR Java API
// Tidak memerlukan ZeroTierSockets.h (tidak ada header C dari AAR)
// Semua operasi ZeroTier dipanggil via JNI ke Java class di AAR

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

/**
 * Inisialisasi ZeroTier via AAR Java API.
 * Memanggil com.zerotier.libzt.ZeroTier melalui JNI.
 */
ZTResult    Init(const std::string& storage_path, uint64_t network_id);
void        Shutdown();
bool        IsReady();
std::string GetAssignedIP();
uint64_t    GetNodeID();
uint64_t    ParseNetworkId(const std::string& hex_str);

} // namespace ZeroTierNative
