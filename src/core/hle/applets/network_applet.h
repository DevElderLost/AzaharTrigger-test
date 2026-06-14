// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

#pragma once

#include "core/hle/applets/applet.h"
#include "core/hle/result.h"

namespace HLE::Applets {

class NetworkApplet final : public Applet {
public:
    explicit NetworkApplet(Core::System& system, Service::APT::AppletId id,
                           Service::APT::AppletId parent, bool preload,
                           std::weak_ptr<Service::APT::AppletManager> manager)
        : Applet(system, id, parent, preload, std::move(manager)) {}

    Result ReceiveParameterImpl(const Service::APT::MessageParameter& parameter) override;
    Result Start(const Service::APT::MessageParameter& parameter) override;
    Result Finalize() override;
    void Update() override;
};

} // namespace HLE::Applets
