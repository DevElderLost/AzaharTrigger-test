// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#pragma once

#include <array>
#include <memory>
#include "core/hle/service/service.h"

namespace Core {
class System;
}

namespace Kernel {
class Event;
}

namespace Service::AC {
class Module final {
public:
    explicit Module(Core::System& system_);
    ~Module() = default;

    class Interface : public ServiceFramework<Interface> {
    public:
        Interface(std::shared_ptr<Module> ac, const char* name, u32 max_session);

        /**
         * AC::CreateDefaultConfig service function
         *  Inputs:
         *      64 : ACConfig size << 14 | 2
         *      65 : pointer to ACConfig struct
         *  Outputs:
         *      1 : Result of function, 0 on success, otherwise error code
         */
        void CreateDefaultConfig(Kernel::HLERequestContext& ctx);

        /**
         * AC::ConnectAsync service function
         *  Inputs:
         *      1 : ProcessId Header
         *      3 : Copy Handle Header
         *      4 : Connection Event handle
         *      5 : ACConfig size << 14 | 2
         *      6 : pointer to ACConfig struct
         *  Outputs:
         *      1 : Result of function, 0 on success, otherwise error code
         */
        void ConnectAsync(Kernel::HLERequestContext& ctx);

        /**
         * AC::GetConnectResult service function
         *  Inputs:
         *      1 : ProcessId Header
         *  Outputs:
         *      1 : Result of function, 0 on success, otherwise error code
         */
        void GetConnectResult(Kernel::HLERequestContext& ctx);

        /**
         * AC::CancelConnectAsync service function
         *  Inputs:
         *      1 : ProcessId Header
         *  Outputs:
         *      1 : Result of function, 0 on success, otherwise error code
         */
        void CancelConnectAsync(Kernel::HLERequestContext& ctx);

        /**
         * AC::CloseAsync service function
         *  Inputs:
         *      1 : ProcessId Header
         *      3 : Copy Handle Header
         *      4 : Event handle, should be signaled when AC connection is closed
         *  Outputs:
         *      1 : Result of function, 0 on success, otherwise error code
         */
        void CloseAsync(Kernel::HLERequestContext& ctx);

        /**
         * AC::GetCloseResult service function
         *  Inputs:
         *      1 : ProcessId Header
         *  Outputs:
         *      1 : Result of function, 0 on success, otherwise error code
         */
        void GetCloseResult(Kernel::HLERequestContext& ctx);

        /**
         * AC::GetWifiStatus service function
         *  Outputs:
         *      1 : Result of function, 0 on success, otherwise error code
         *      2 : Status
         */
        void GetStatus(Kernel::HLERequestContext& ctx);

        /**
         * AC::GetWifiStatus service function
         *  Outputs:
         *      1 : Result of function, 0 on success, otherwise error code
         *      2 : WifiStatus
         */
        void GetWifiStatus(Kernel::HLERequestContext& ctx);

        /**
         * AC::GetInfraPriority service function
         *  Inputs:
         *      1 : ACConfig size << 14 | 2
         *      2 : pointer to ACConfig struct
         *  Outputs:
         *      1 : Result of function, 0 on success, otherwise error code
         *      2 : Infra Priority
         */
        void GetInfraPriority(Kernel::HLERequestContext& ctx);

        /**
         * AC::SetRequestEulaVersion service function
         *  Inputs:
         *      1 : Eula Version major
         *      2 : Eula Version minor
         *      3 : ACConfig size << 14 | 2
         *      4 : Input pointer to ACConfig struct
         *      64 : ACConfig size << 14 | 2
         *      65 : Output pointer to ACConfig struct
         *  Outputs:
         *      1 : Result of function, 0 on success, otherwise error code
         *      2 : Infra Priority
         */
        void SetRequestEulaVersion(Kernel::HLERequestContext& ctx);

        /**
         * AC::GetNZoneBeaconNotFoundEvent service function
         *  Inputs:
         *      1 : ProcessId Header
         *      2 : ProcessId
         *      3 : Copy Handle Header
         *      4 : Event handle, should be signaled when a Nintendo Zone beacon is not found
         *  Outputs:
         *      1 : Result of function, 0 on success, otherwise error code
         */
        void GetNZoneBeaconNotFoundEvent(Kernel::HLERequestContext& ctx);

        /**
         * AC::RegisterDisconnectEvent service function
         *  Inputs:
         *      1 : ProcessId Header
         *      3 : Copy Handle Header
         *      4 : Event handle, should be signaled when AC connection is closed
         *  Outputs:
         *      1 : Result of function, 0 on success, otherwise error code
         */
        void RegisterDisconnectEvent(Kernel::HLERequestContext& ctx);

        /**
         * AC::GetConnectingProxyEnable service function
         *  Outputs:
         *      1 : Result of function, 0 on success, otherwise error code
         *      2 : bool, is proxy enabled
         */
        void GetConnectingProxyEnable(Kernel::HLERequestContext& ctx);

        /**
         * AC::IsConnected service function
         *  Outputs:
         *      1 : Result of function, 0 on success, otherwise error code
         *      2 : bool, is connected
         */
        void IsConnected(Kernel::HLERequestContext& ctx);

        /**
         * AC::SetClientVersion service function
         *  Inputs:
         *      1 : Used SDK Version
         *  Outputs:
         *      1 : Result of function, 0 on success, otherwise error code
         */
        void SetClientVersion(Kernel::HLERequestContext& ctx);

        /**
         * AC::GetCurrentAPInfo service function (0x000E)
         * Mengembalikan info AP yang sedang terhubung.
         * Di emulator dikembalikan data dummy agar Nimbus/PIA tidak gagal.
         *  Inputs:
         *      1 : ukuran output buffer
         *      2 : mapped write buffer descriptor
         *      3 : pointer ke buffer output APInfo
         *  Outputs:
         *      1 : Result, 0 = sukses
         *      2 : mapped buffer descriptor
         *      3 : pointer ke buffer output
         */
        void GetCurrentAPInfo(Kernel::HLERequestContext& ctx);

    protected:
        std::shared_ptr<Module> ac;
    };

protected:
    enum class Status {
        STATUS_DISCONNECTED = 0,
        STATUS_ENABLED = 1,
        STATUS_CONNECTED = 2,
        STATUS_INTERNET = 3,
    };
    enum class WifiStatus {
        STATUS_DISCONNECTED = 0,
        STATUS_CONNECTED_SLOT1 = (1 << 0),
        STATUS_CONNECTED_SLOT2 = (1 << 1),
        STATUS_CONNECTED_SLOT3 = (1 << 2),
    };

    struct ACConfig {
        std::array<u8, 0x200> data;
    };

    // APInfo: 0x34 bytes sesuai protokol AC service 3DS
    // Dikembalikan oleh GetCurrentAPInfo (command 0x000E)
    // Disimpan sebagai raw array untuk menghindari masalah padding/alignment
    struct APInfo {
        std::array<u8, 0x34> data{};
    };

    // APInfo: data access point yang sedang terhubung
    // Dikembalikan oleh GetCurrentAPInfo (command 0x000E)
    // Total size harus 0x34 bytes sesuai protokol 3DS
    struct APInfo {
        std::array<u8, 6> bssid;       // MAC address AP
        std::array<u8, 6> padding1;
        u8 ssid_len;                   // Panjang SSID
        std::array<u8, 32> ssid;       // SSID string (max 32 char)
        u8 padding2;
        u16 channel;                   // WiFi channel
        u8 signal_strength;            // Kekuatan sinyal 0-100
        u8 link_level;                 // Level link 0-3
        std::array<u8, 6> padding3;
        u32 network_id;                // Network ID
    };
    static_assert(sizeof(APInfo) == 0x34, "APInfo size mismatch");

    ACConfig default_config{};

    bool ac_connected = false;

    std::shared_ptr<Kernel::Event> close_event;
    std::shared_ptr<Kernel::Event> connect_event;
    std::shared_ptr<Kernel::Event> disconnect_event;
    std::shared_ptr<Kernel::Event> nintendo_zone_beacon_not_found_event;

private:
    [[maybe_unused]]
    Core::System& system;

    template <class Archive>
    void serialize(Archive& ar, const unsigned int);
    friend class boost::serialization::access;
};

void InstallInterfaces(Core::System& system);

} // namespace Service::AC

BOOST_CLASS_EXPORT_KEY(Service::AC::Module)
SERVICE_CONSTRUCT(Service::AC::Module)
