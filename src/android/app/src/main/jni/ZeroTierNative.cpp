// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
//
// ZeroTierNative.cpp — STUB
// ZeroTier sekarang dikelola langsung dari Kotlin (ZeroTierManager.kt)
// menggunakan reflection ke com.zerotier.sockets.ZeroTierNode.
// File ini hanya menyediakan implementasi kosong agar CMakeLists
// tidak error saat compile.

#include "ZeroTierNative.h"
#include "common/logging/log.h"

JavaVM* ZeroTierNative::g_jvm = nullptr;

namespace ZeroTierNative {

ZTResult Init(const std::string&, uint64_t) {
    // Tidak dipakai — ZeroTier dikelola dari Kotlin
    LOG_WARNING(Network, "[ZT] ZeroTierNative::Init() dipanggil tapi tidak dipakai");
    return ZTResult::OK;
}
void        Shutdown()       { /* stub */ }
bool        IsReady()        { return false; }
std::string GetAssignedIP()  { return ""; }
uint64_t    GetNodeID()      { return 0; }
uint64_t    ParseNetworkId(const std::string& s) {
    try { return std::stoull(s, nullptr, 16); } catch (...) { return 0; }
}

} // namespace ZeroTierNative
