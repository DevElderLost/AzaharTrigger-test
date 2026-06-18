// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

package org.citra.citra_emu.overlay

import android.content.SharedPreferences
import androidx.preference.PreferenceManager
import org.citra.citra_emu.CitraApplication
import org.citra.citra_emu.NativeLibrary

/**
 * Manages Combo Buttons (Combo 1–5).
 *
 * Each combo stores up to [MAX_BUTTONS_PER_COMBO] native button IDs.
 * When pressed/released, all assigned buttons are fired simultaneously.
 *
 * SharedPreferences layout (example slot 1):
 *   "combo_button_1_enabled"  → Boolean
 *   "combo_button_1_label"    → String  (custom label; blank = auto)
 *   "combo_button_1_buttons"  → String  (comma-separated IDs, e.g. "700,701")
 */
object ComboButtonManager {

    const val COMBO_COUNT          = 5
    const val MAX_BUTTONS_PER_COMBO = 4

    // Virtual overlay button IDs (900–904, free in ButtonType range)
    const val COMBO_BUTTON_1 = 900
    const val COMBO_BUTTON_2 = 901
    const val COMBO_BUTTON_3 = 902
    const val COMBO_BUTTON_4 = 903
    const val COMBO_BUTTON_5 = 904

    val COMBO_IDS = intArrayOf(
        COMBO_BUTTON_1, COMBO_BUTTON_2, COMBO_BUTTON_3,
        COMBO_BUTTON_4, COMBO_BUTTON_5,
    )

    // SharedPrefs key helpers
    fun enabledKey(slot: Int) = "combo_button_${slot}_enabled"
    fun labelKey(slot: Int)   = "combo_button_${slot}_label"
    fun buttonsKey(slot: Int) = "combo_button_${slot}_buttons"

    private val preferences: SharedPreferences
        get() = PreferenceManager.getDefaultSharedPreferences(CitraApplication.appContext)

    /** Returns true if the given virtual button ID belongs to a combo slot. */
    fun isComboButton(buttonId: Int) = buttonId in COMBO_BUTTON_1..COMBO_BUTTON_5

    /** Returns 1-based slot index (1–5), or -1 if not a combo ID. */
    fun slotForId(buttonId: Int): Int {
        val idx = COMBO_IDS.indexOf(buttonId)
        return if (idx >= 0) idx + 1 else -1
    }

    /** Native button IDs assigned to a slot (1-based). */
    fun getButtonsForSlot(slot: Int): List<Int> {
        val raw = preferences.getString(buttonsKey(slot), "") ?: ""
        if (raw.isBlank()) return emptyList()
        return raw.split(",")
            .mapNotNull { it.trim().toIntOrNull() }
            .distinct()
            .take(MAX_BUTTONS_PER_COMBO)
    }

    /** Persists button assignments for a slot (1-based). */
    fun setButtonsForSlot(slot: Int, buttonIds: List<Int>) {
        preferences.edit()
            .putString(buttonsKey(slot), buttonIds.distinct().take(MAX_BUTTONS_PER_COMBO).joinToString(","))
            .apply()
    }

    /** Display label; falls back to auto-generated "A+B" style. */
    fun getLabelForSlot(slot: Int): String =
        preferences.getString(labelKey(slot), "")
            ?.takeIf { it.isNotBlank() } ?: autoLabel(slot)

    fun setLabelForSlot(slot: Int, label: String?) {
        preferences.edit().putString(labelKey(slot), label ?: "").apply()
    }

    fun isEnabled(slot: Int): Boolean = preferences.getBoolean(enabledKey(slot), false)

    fun setEnabled(slot: Int, enabled: Boolean) {
        preferences.edit().putBoolean(enabledKey(slot), enabled).apply()
    }

    /**
     * Fires all native buttons assigned to the combo slot in one shot.
     * Called from InputOverlay.onTouch() instead of the regular onGamePadEvent.
     */
    fun dispatchComboEvent(buttonId: Int, state: Int) {
        val slot = slotForId(buttonId)
        if (slot < 0) return
        for (nativeBtn in getButtonsForSlot(slot)) {
            NativeLibrary.onGamePadEvent(NativeLibrary.TouchScreenDevice, nativeBtn, state)
        }
    }

    /** Auto-generates a label like "A+B" from current assignments. */
    fun autoLabel(slot: Int): String {
        val ids = getButtonsForSlot(slot)
        return if (ids.isEmpty()) "Combo $slot" else ids.joinToString("+") { buttonShortName(it) }
    }

    fun buttonShortName(id: Int): String = when (id) {
        NativeLibrary.ButtonType.BUTTON_A      -> "A"
        NativeLibrary.ButtonType.BUTTON_B      -> "B"
        NativeLibrary.ButtonType.BUTTON_X      -> "X"
        NativeLibrary.ButtonType.BUTTON_Y      -> "Y"
        NativeLibrary.ButtonType.BUTTON_START  -> "Start"
        NativeLibrary.ButtonType.BUTTON_SELECT -> "Select"
        NativeLibrary.ButtonType.BUTTON_HOME   -> "Home"
        NativeLibrary.ButtonType.TRIGGER_L     -> "L"
        NativeLibrary.ButtonType.TRIGGER_R     -> "R"
        NativeLibrary.ButtonType.BUTTON_ZL     -> "ZL"
        NativeLibrary.ButtonType.BUTTON_ZR     -> "ZR"
        NativeLibrary.ButtonType.DPAD_UP       -> "↑"
        NativeLibrary.ButtonType.DPAD_DOWN     -> "↓"
        NativeLibrary.ButtonType.DPAD_LEFT     -> "←"
        NativeLibrary.ButtonType.DPAD_RIGHT    -> "→"
        else                                   -> "[$id]"
    }

    /** All buttons available for assignment (name → ID). */
    val assignableButtons: List<Pair<String, Int>> = listOf(
        "A"       to NativeLibrary.ButtonType.BUTTON_A,
        "B"       to NativeLibrary.ButtonType.BUTTON_B,
        "X"       to NativeLibrary.ButtonType.BUTTON_X,
        "Y"       to NativeLibrary.ButtonType.BUTTON_Y,
        "L"       to NativeLibrary.ButtonType.TRIGGER_L,
        "R"       to NativeLibrary.ButtonType.TRIGGER_R,
        "ZL"      to NativeLibrary.ButtonType.BUTTON_ZL,
        "ZR"      to NativeLibrary.ButtonType.BUTTON_ZR,
        "Start"   to NativeLibrary.ButtonType.BUTTON_START,
        "Select"  to NativeLibrary.ButtonType.BUTTON_SELECT,
        "D-Up"    to NativeLibrary.ButtonType.DPAD_UP,
        "D-Down"  to NativeLibrary.ButtonType.DPAD_DOWN,
        "D-Left"  to NativeLibrary.ButtonType.DPAD_LEFT,
        "D-Right" to NativeLibrary.ButtonType.DPAD_RIGHT,
    )
}
