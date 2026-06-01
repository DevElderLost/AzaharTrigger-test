// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

package org.citra.citra_emu.features.settings.ui

import android.content.Context
import android.graphics.Typeface
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.appcompat.widget.SwitchCompat
import androidx.fragment.app.Fragment
import com.google.android.material.chip.Chip
import com.google.android.material.chip.ChipGroup
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import org.citra.citra_emu.overlay.ComboButtonManager

/**
 * Settings screen for configuring Combo Buttons 1–5.
 *
 * Add to nav_graph.xml:
 *   <fragment
 *       android:id="@+id/comboButtonSettingsFragment"
 *       android:name="org.citra.citra_emu.features.settings.ui.ComboButtonSettingsFragment"
 *       android:label="Combo Buttons" />
 *
 * Navigate to it from any fragment:
 *   findNavController().navigate(R.id.action_..._to_comboButtonSettingsFragment)
 */
class ComboButtonSettingsFragment : Fragment() {

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View = buildScrollView(requireContext())

    // ── Build UI programmatically (no extra layout XML needed) ───────────────

    private fun buildScrollView(ctx: Context): ScrollView {
        val scroll = ScrollView(ctx).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        val root = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            val p = 16.dp(ctx)
            setPadding(p, p, p, p)
        }
        for (slot in 1..ComboButtonManager.COMBO_COUNT) {
            root.addView(buildSlotCard(ctx, slot))
        }
        scroll.addView(root)
        return scroll
    }

    private fun buildSlotCard(ctx: Context, slot: Int): View {
        val card = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            val p = 12.dp(ctx); val m = 8.dp(ctx)
            setPadding(p, p, p, p)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).also { it.setMargins(0, 0, 0, m) }
            setBackgroundResource(android.R.drawable.dialog_holo_light_frame)
        }

        // Header row: title + enable switch
        val headerRow = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
        val title = TextView(ctx).apply {
            text = "Combo $slot"
            textSize = 18f
            setTypeface(null, Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        val enableSwitch = SwitchCompat(ctx).apply {
            text = "Show on overlay"
            isChecked = ComboButtonManager.isEnabled(slot)
            setOnCheckedChangeListener { _, on -> ComboButtonManager.setEnabled(slot, on) }
        }
        headerRow.addView(title)
        headerRow.addView(enableSwitch)
        card.addView(headerRow)

        // Label field
        card.addView(TextView(ctx).apply {
            text = "Custom label (blank = auto)"
            textSize = 12f
            setPadding(0, 8.dp(ctx), 0, 2.dp(ctx))
        })
        val labelField = EditText(ctx).apply {
            val auto = ComboButtonManager.autoLabel(slot)
            hint = auto
            setText(ComboButtonManager.getLabelForSlot(slot).takeIf { it != auto } ?: "")
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            setOnFocusChangeListener { _, focused ->
                if (!focused) ComboButtonManager.setLabelForSlot(slot, text.toString())
            }
        }
        card.addView(labelField)

        // Chips showing assigned buttons
        card.addView(TextView(ctx).apply {
            text = "Assigned (max ${ComboButtonManager.MAX_BUTTONS_PER_COMBO}):"
            textSize = 13f
            setPadding(0, 12.dp(ctx), 0, 4.dp(ctx))
        })
        val chipGroup = ChipGroup(ctx)

        fun refreshChips() {
            chipGroup.removeAllViews()
            val assigned = ComboButtonManager.getButtonsForSlot(slot)
            if (assigned.isEmpty()) {
                chipGroup.addView(Chip(ctx).apply { text = "(none)" })
            } else {
                assigned.forEach { id ->
                    chipGroup.addView(Chip(ctx).apply {
                        text = ComboButtonManager.buttonShortName(id)
                    })
                }
            }
            labelField.hint = ComboButtonManager.autoLabel(slot)
        }

        refreshChips()
        card.addView(chipGroup)

        // Edit button → dialog
        card.addView(Button(ctx).apply {
            text = "Edit buttons…"
            setOnClickListener { showPickerDialog(ctx, slot, ::refreshChips) }
        })

        return card
    }

    private fun showPickerDialog(ctx: Context, slot: Int, onDone: () -> Unit) {
        val assignable = ComboButtonManager.assignableButtons
        val names      = assignable.map { it.first }.toTypedArray()
        val ids        = assignable.map { it.second }
        val selected   = ComboButtonManager.getButtonsForSlot(slot).toMutableSet()
        val checked    = BooleanArray(names.size) { i -> ids[i] in selected }

        MaterialAlertDialogBuilder(ctx)
            .setTitle("Assign buttons — Combo $slot")
            .setMultiChoiceItems(names, checked) { _, which, isChecked ->
                val id = ids[which]
                if (isChecked) {
                    if (selected.size >= ComboButtonManager.MAX_BUTTONS_PER_COMBO) {
                        checked[which] = false
                        Toast.makeText(
                            ctx,
                            "Max ${ComboButtonManager.MAX_BUTTONS_PER_COMBO} buttons",
                            Toast.LENGTH_SHORT
                        ).show()
                    } else selected.add(id)
                } else selected.remove(id)
            }
            .setPositiveButton(android.R.string.ok) { _, _ ->
                ComboButtonManager.setButtonsForSlot(slot, selected.toList())
                onDone()
            }
            .setNeutralButton("Clear all") { _, _ ->
                ComboButtonManager.setButtonsForSlot(slot, emptyList())
                onDone()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun Int.dp(ctx: Context) =
        (this * ctx.resources.displayMetrics.density).toInt()
}
