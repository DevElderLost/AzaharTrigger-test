// Copyright 2025 AzaharTrigger Project
// Licensed under GPLv2 or any later version
//
// ZeroTierNative.cpp — STUB
// ZeroTier sekarang dikelola langsung dari Kotlin (ZeroTierManager.kt)
// File ini hanya stub agar CMakeLists tidak error saat compile.

#include "ZeroTierNative.h"

namespace ZeroTierNative {

ZTResult Init(const std::string&, uint64_t) { return ZTResult::OK; }
void        Shutdown()       {}
bool        IsReady()        { return false; }
std::string GetAssignedIP()  { return ""; }
uint64_t    GetNodeID()      { return 0; }
uint64_t    ParseNetworkId(const std::string& s) {
    try { return std::stoull(s, nullptr, 16); } catch (...) { return 0; }
}

} // namespace ZeroTierNative
