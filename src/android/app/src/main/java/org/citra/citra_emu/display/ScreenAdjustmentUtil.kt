// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

package org.citra.citra_emu.display

import android.content.Context
import android.content.pm.ActivityInfo
import android.app.Activity
import android.view.WindowManager
import org.citra.citra_emu.NativeLibrary
import org.citra.citra_emu.display.ScreenLayout
import org.citra.citra_emu.R
import org.citra.citra_emu.features.settings.model.BooleanSetting
import org.citra.citra_emu.features.settings.model.IntSetting
import org.citra.citra_emu.features.settings.model.IntListSetting
import org.citra.citra_emu.features.settings.model.Settings
import org.citra.citra_emu.features.settings.utils.SettingsFile
import org.citra.citra_emu.utils.EmulationMenuSettings

class ScreenAdjustmentUtil(
    private val context: Context,
    private val windowManager: WindowManager,
    private val settings: Settings,
) {
    fun swapScreen() {
        val isEnabled = !EmulationMenuSettings.swapScreens
        EmulationMenuSettings.swapScreens = isEnabled
        NativeLibrary.swapScreens(
            isEnabled,
            windowManager.defaultDisplay.rotation
        )
        BooleanSetting.SWAP_SCREEN.boolean = isEnabled
        settings.saveSetting(BooleanSetting.SWAP_SCREEN, SettingsFile.FILE_NAME_CONFIG)
    }

    /**
     * Toggle tampilan layar kedua saat mode SINGLE_SCREEN aktif.
     *
     * Ketika ON:
     *   - Baca posisi layar kedua dari setting Custom Layout
     *     (IntSetting.LANDSCAPE_BOTTOM_X/Y/WIDTH/HEIGHT)
     *   - Terapkan sementara SCREEN_LAYOUT = CUSTOM_LAYOUT
     *     supaya native core merender layar kedua di posisi tersebut
     *   - Touch input ke layar kedua ikut aktif
     *
     * Ketika OFF:
     *   - Kembalikan SCREEN_LAYOUT ke SINGLE_SCREEN
     *   - Touch input ke layar kedua diblokir kembali
     */
    fun toggleSecondaryScreen() {
        val isNowShowing = !EmulationMenuSettings.showSecondaryScreen
        EmulationMenuSettings.showSecondaryScreen = isNowShowing

        // Berlaku saat SINGLE_SCREEN atau SINGLE_WITH_OVERLAY aktif
        val currentLayout = if (NativeLibrary.isPortraitMode) {
            IntSetting.PORTRAIT_SCREEN_LAYOUT.int
        } else {
            IntSetting.SCREEN_LAYOUT.int
        }
        val isRelevantMode = currentLayout == ScreenLayout.SINGLE_SCREEN.int ||
                             currentLayout == ScreenLayout.SINGLE_WITH_OVERLAY.int

        if (!isRelevantMode) return

        if (isNowShowing) {
            // Terapkan CUSTOM_LAYOUT sementara supaya layar kedua
            // dirender di posisi yang sama dengan Custom Layout setting
            // Native core akan membaca LANDSCAPE_BOTTOM_X/Y/WIDTH/HEIGHT
            // dari settings untuk menentukan posisi & ukuran layar kedua
            if (NativeLibrary.isPortraitMode) {
                IntSetting.PORTRAIT_SCREEN_LAYOUT.int = ScreenLayout.SINGLE_WITH_OVERLAY.int
                settings.saveSetting(IntSetting.PORTRAIT_SCREEN_LAYOUT, SettingsFile.FILE_NAME_CONFIG)
            } else {
                IntSetting.SCREEN_LAYOUT.int = ScreenLayout.SINGLE_WITH_OVERLAY.int
                settings.saveSetting(IntSetting.SCREEN_LAYOUT, SettingsFile.FILE_NAME_CONFIG)
            }
        } else {
            // Kembalikan ke SINGLE_SCREEN
            if (NativeLibrary.isPortraitMode) {
                IntSetting.PORTRAIT_SCREEN_LAYOUT.int = ScreenLayout.SINGLE_SCREEN.int
                settings.saveSetting(IntSetting.PORTRAIT_SCREEN_LAYOUT, SettingsFile.FILE_NAME_CONFIG)
            } else {
                IntSetting.SCREEN_LAYOUT.int = ScreenLayout.SINGLE_SCREEN.int
                settings.saveSetting(IntSetting.SCREEN_LAYOUT, SettingsFile.FILE_NAME_CONFIG)
            }
        }

        // Reload dan refresh render
        NativeLibrary.reloadSettings()
        NativeLibrary.updateFramebuffer(NativeLibrary.isPortraitMode)
    }

    fun cycleLayouts() {

        val landscapeLayoutsToCycle = IntListSetting.LAYOUTS_TO_CYCLE.list;
        val landscapeValues =
            if (landscapeLayoutsToCycle.isNotEmpty())
                landscapeLayoutsToCycle.toIntArray()
            else context.resources.getIntArray(
                R.array.landscapeValues
            )
        val portraitValues = context.resources.getIntArray(R.array.portraitValues)

        if (NativeLibrary.isPortraitMode) {
            val currentLayout = IntSetting.PORTRAIT_SCREEN_LAYOUT.int
            val pos = portraitValues.indexOf(currentLayout)
            val layoutOption = portraitValues[(pos + 1) % portraitValues.size]
            changePortraitOrientation(layoutOption)
        } else {
            val currentLayout = IntSetting.SCREEN_LAYOUT.int
            val pos = landscapeValues.indexOf(currentLayout)
            val layoutOption = landscapeValues[(pos + 1) % landscapeValues.size]
            changeScreenOrientation(layoutOption)
        }
    }

    fun changePortraitOrientation(layoutOption: Int) {
        IntSetting.PORTRAIT_SCREEN_LAYOUT.int = layoutOption
        settings.saveSetting(IntSetting.PORTRAIT_SCREEN_LAYOUT, SettingsFile.FILE_NAME_CONFIG)
        NativeLibrary.reloadSettings()
        NativeLibrary.updateFramebuffer(NativeLibrary.isPortraitMode)
    }

    fun changeScreenOrientation(layoutOption: Int) {
        IntSetting.SCREEN_LAYOUT.int = layoutOption
        settings.saveSetting(IntSetting.SCREEN_LAYOUT, SettingsFile.FILE_NAME_CONFIG)
        NativeLibrary.reloadSettings()
        NativeLibrary.updateFramebuffer(NativeLibrary.isPortraitMode)
    }

    fun changeActivityOrientation(orientationOption: Int) {
        val activity = context as? Activity ?: return
        IntSetting.ORIENTATION_OPTION.int = orientationOption
        settings.saveSetting(IntSetting.ORIENTATION_OPTION, SettingsFile.FILE_NAME_CONFIG)
        activity.requestedOrientation = orientationOption
    }

    fun toggleScreenUpright() {
        val uprightBoolean = BooleanSetting.UPRIGHT_SCREEN.boolean
        BooleanSetting.UPRIGHT_SCREEN.boolean = !uprightBoolean
        settings.saveSetting(BooleanSetting.UPRIGHT_SCREEN, SettingsFile.FILE_NAME_CONFIG)
        NativeLibrary.reloadSettings()
        NativeLibrary.updateFramebuffer(NativeLibrary.isPortraitMode)

    }
}
