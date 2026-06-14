// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#include "common/logging/log.h"
#include "core/core.h"
#include "core/hle/applets/network_applet.h"
#include "core/hle/service/apt/apt.h"

namespace HLE::Applets {

Result NetworkApplet::ReceiveParameterImpl(const Service::APT::MessageParameter& parameter) {
    LOG_WARNING(Service_APT,
                "NetworkApplet (C502) ReceiveParameterImpl signal={}, stub returning success",
                parameter.signal);

    if (parameter.signal == Service::APT::SignalType::Request) {
        SendParameter({
            .sender_id = id,
            .destination_id = parent,
            .signal = Service::APT::SignalType::Response,
            .object = nullptr,
            .buffer = {},
        });
    }

    return ResultSuccess;
}

Result NetworkApplet::Start(const Service::APT::MessageParameter& parameter) {
    LOG_WARNING(Service_APT, "NetworkApplet (C502) Start - stub immediately closing");
    Finalize();
    return ResultSuccess;
}

Result NetworkApplet::Finalize() {
    LOG_WARNING(Service_APT, "NetworkApplet (C502) Finalize - sending close signal");
    CloseApplet(nullptr, {});
    return ResultSuccess;
}

void NetworkApplet::Update() {}

} // namespace HLE::Applets
