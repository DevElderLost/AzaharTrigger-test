#!/usr/bin/env python3
"""
Patch script untuk memperbaiki semua error ktlint dari log build
(ktlintMainSourceSetCheck FAILED) pada AzaharTrigger-test.

Semua error pada log adalah error GAYA KODE (ktlint), bukan error
kompilasi C++/Kotlin. Script ini memperbaiki:

  - ChatDialog.kt              : import order, unnecessary block, blank
                                  line, line >100 char, missing newline
  - LobbyBrowser.kt            : import order, unused import (CompatUtils),
                                  blank line, indentasi salah, EOF newline
  - NetPlayDialog.kt           : duplikat behavior.state, line >100 char,
                                  pemisahan argumen, when-condition blank
                                  line, dll (lihat fungsi masing-masing)
  - NetPlayManager.kt          : line >100 char pada deklarasi external fun,
                                  spasi ganda, indentasi if/else, dll
  - Settings.kt                : kolom yang diratakan dengan spasi berlebih
  - ComboButtonSettingsFragment.kt : kolom diratakan, argumen multi-baris
  - EmulationFragment.kt       : baris >100 char pada showAdjustScaleDialog,
                                  spasi berlebih
  - ComboButtonManager.kt      : kolom diratakan, trailing comma, argumen
  - InputOverlay.kt            : duplikat import, trailing comma, argumen
  - NativeLibrary.kt           : duplikat import, import tak terpakai,
                                  "else" harus sebaris dengan "}"
  - CompatUtils.kt             : function body -> body expression (=)

Jalankan dari root repo (folder yang berisi src/android/...):

    python3 fix_ktlint_errors.py

Script ini AMAN dijalankan berulang kali (idempotent) -- jika suatu
pola sudah tidak ditemukan (karena sudah diperbaiki), patch untuk
bagian itu akan dilewati dengan pesan SKIP, bukan error fatal.
"""

import os
import sys

# ---------------------------------------------------------------------------
# Util
# ---------------------------------------------------------------------------

REPO_CANDIDATES = [
    ".",
    "AzaharTrigger-test",
]

BASE_REL = "src/android/app/src/main/java/org/citra/citra_emu"

CHANGED = 0
SKIPPED = 0
MISSING = 0


def find_repo_root():
    for cand in REPO_CANDIDATES:
        probe = os.path.join(cand, BASE_REL)
        if os.path.isdir(probe):
            return os.path.abspath(cand)
    print(f"[FATAL] Tidak menemukan folder '{BASE_REL}' dari direktori saat ini.")
    print("        Jalankan script ini dari root repo AzaharTrigger-test.")
    sys.exit(1)


def read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write(path, content):
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def patch_file(path, replacements, label):
    """replacements: list of (old, new, description)"""
    global CHANGED, SKIPPED, MISSING

    if not os.path.isfile(path):
        print(f"[MISSING] {label}: file tidak ditemukan -> {path}")
        MISSING += 1
        return

    content = read(path)
    original = content
    file_changed = False

    for old, new, desc in replacements:
        if old not in content:
            if new in content:
                print(f"  [SKIP] {label}: '{desc}' (sudah terpatch)")
            else:
                print(f"  [WARN] {label}: pola tidak ditemukan untuk '{desc}'")
            continue
        content = content.replace(old, new, 1)
        file_changed = True
        print(f"  [OK]   {label}: '{desc}'")

    if file_changed and content != original:
        write(path, content)
        CHANGED += 1
    else:
        SKIPPED += 1


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    root = find_repo_root()
    base = os.path.join(root, BASE_REL)
    print(f"Repo root terdeteksi: {root}\n")

    # =========================================================================
    # 1. dialogs/ChatDialog.kt
    # =========================================================================
    path = os.path.join(base, "dialogs", "ChatDialog.kt")
    patch_file(path, [
        (
            "import android.content.Context\n"
            "import android.content.res.Configuration\n"
            "import android.os.Bundle\n"
            "import android.os.Handler\n"
            "import android.os.Looper\n"
            "import android.view.LayoutInflater\n"
            "import android.view.ViewGroup\n"
            "import androidx.recyclerview.widget.LinearLayoutManager\n"
            "import androidx.recyclerview.widget.RecyclerView\n"
            "import com.google.android.material.bottomsheet.BottomSheetBehavior\n"
            "import com.google.android.material.bottomsheet.BottomSheetDialog\n"
            "import org.citra.citra_emu.R\n"
            "import org.citra.citra_emu.databinding.DialogChatBinding\n"
            "import org.citra.citra_emu.databinding.ItemChatMessageBinding\n"
            "import org.citra.citra_emu.utils.NetPlayManager\n"
            "import java.text.SimpleDateFormat\n"
            "import java.util.*\n",
            "import android.content.Context\n"
            "import android.content.res.Configuration\n"
            "import android.os.Bundle\n"
            "import android.os.Handler\n"
            "import android.os.Looper\n"
            "import android.view.LayoutInflater\n"
            "import android.view.ViewGroup\n"
            "import androidx.recyclerview.widget.LinearLayoutManager\n"
            "import androidx.recyclerview.widget.RecyclerView\n"
            "import com.google.android.material.bottomsheet.BottomSheetBehavior\n"
            "import com.google.android.material.bottomsheet.BottomSheetDialog\n"
            "import java.text.SimpleDateFormat\n"
            "import java.util.Date\n"
            "import java.util.Locale\n"
            "import org.citra.citra_emu.R\n"
            "import org.citra.citra_emu.databinding.DialogChatBinding\n"
            "import org.citra.citra_emu.databinding.ItemChatMessageBinding\n"
            "import org.citra.citra_emu.utils.NetPlayManager\n",
            "urutkan import (lexicographic) & ganti java.util.* -> Date, Locale eksplisit",
        ),
        (
            "    val timestamp: String = SimpleDateFormat(\"HH:mm\", Locale.getDefault()).format(Date())\n"
            ") {\n"
            "}\n",
            "    val timestamp: String = SimpleDateFormat(\"HH:mm\", Locale.getDefault()).format(Date())\n"
            ")\n",
            "hapus unnecessary block {} kosong setelah data class ChatMessage",
        ),
        (
            "        behavior.skipCollapsed = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE\n"
            "\n"
            "\n"
            "        handler.post {",
            "        behavior.skipCollapsed =\n"
            "            context.resources.configuration.orientation ==\n"
            "                Configuration.ORIENTATION_LANDSCAPE\n"
            "\n"
            "        handler.post {",
            "pecah baris >100 char & hapus blank line ganda (needless blank lines)",
        ),
        (
            "            binding.userIcon.setImageResource(when (message.nickname) {\n"
            "                \"System\" -> R.drawable.ic_system\n"
            "                else -> R.drawable.ic_user\n"
            "            })\n",
            "            binding.userIcon.setImageResource(\n"
            "                when (message.nickname) {\n"
            "                    \"System\" -> R.drawable.ic_system\n"
            "                    else -> R.drawable.ic_user\n"
            "                }\n"
            "            )\n",
            "pindahkan argumen when{} ke baris baru (missing newline after '(')",
        ),
    ], "ChatDialog.kt")

    # =========================================================================
    # 2. dialogs/LobbyBrowser.kt
    # =========================================================================
    path = os.path.join(base, "dialogs", "LobbyBrowser.kt")
    patch_file(path, [
        (
            "import com.google.android.material.textfield.TextInputEditText\n"
            "import info.debatty.java.stringsimilarity.Jaccard\n"
            "import info.debatty.java.stringsimilarity.JaroWinkler\n"
            "import org.citra.citra_emu.R\n"
            "import org.citra.citra_emu.databinding.DialogLobbyBrowserBinding\n"
            "import org.citra.citra_emu.databinding.ItemLobbyRoomBinding\n"
            "import org.citra.citra_emu.utils.CompatUtils\n"
            "import org.citra.citra_emu.utils.NetPlayManager\n"
            "import java.util.Locale\n",
            "import com.google.android.material.textfield.TextInputEditText\n"
            "import info.debatty.java.stringsimilarity.Jaccard\n"
            "import info.debatty.java.stringsimilarity.JaroWinkler\n"
            "import java.util.Locale\n"
            "import org.citra.citra_emu.R\n"
            "import org.citra.citra_emu.databinding.DialogLobbyBrowserBinding\n"
            "import org.citra.citra_emu.databinding.ItemLobbyRoomBinding\n"
            "import org.citra.citra_emu.utils.NetPlayManager\n",
            "urutkan import & hapus unused import CompatUtils",
        ),
        (
            "        binding.chipGroup.setOnCheckedStateChangeListener { _, _ -> adapter.filterAndSearch() }\n"
            "\n"
            "\n"
            "        binding.searchText.doOnTextChanged",
            "        binding.chipGroup.setOnCheckedStateChangeListener { _, _ -> adapter.filterAndSearch() }\n"
            "\n"
            "        binding.searchText.doOnTextChanged",
            "hapus needless blank line ganda",
        ),
        (
            "            val sortedList: List<NetPlayManager.RoomInfo> = filteredList.mapNotNull { room ->\n"
            "                    val roomName = room.name.lowercase(Locale.getDefault())\n"
            "\n"
            "                    val score = searchAlgorithm.similarity(roomName, searchTerm)\n"
            "                    if (score > 0.03) {\n"
            "                        ScoreItem(score, room)\n"
            "                    } else {\n"
            "                        null\n"
            "                    }\n"
            "                }.sortedByDescending { it ->\n"
            "                    it.score\n"
            "                }.map { it.item }\n"
            "            adapter.updateRooms(sortedList)\n"
            "\n"
            "        }\n",
            "            val sortedList: List<NetPlayManager.RoomInfo> = filteredList.mapNotNull { room ->\n"
            "                val roomName = room.name.lowercase(Locale.getDefault())\n"
            "\n"
            "                val score = searchAlgorithm.similarity(roomName, searchTerm)\n"
            "                if (score > 0.03) {\n"
            "                    ScoreItem(score, room)\n"
            "                } else {\n"
            "                    null\n"
            "                }\n"
            "            }.sortedByDescending { it ->\n"
            "                it.score\n"
            "            }.map { it.item }\n"
            "            adapter.updateRooms(sortedList)\n"
            "        }\n",
            "perbaiki indentasi blok lambda mapNotNull/sortedByDescending & hapus blank line sebelum }",
        ),
        (
            "    private inner class ScoreItem(val score: Double, val item: NetPlayManager.RoomInfo)\n"
            "}",
            "    private inner class ScoreItem(val score: Double, val item: NetPlayManager.RoomInfo)\n"
            "}\n",
            "tambahkan newline di akhir file",
        ),
    ], "LobbyBrowser.kt")

    # =========================================================================
    # 3. dialogs/NetPlayDialog.kt
    # =========================================================================
    path = os.path.join(base, "dialogs", "NetPlayDialog.kt")
    patch_file(path, [
        (
            "        behavior.state = BottomSheetBehavior.STATE_EXPANDED\n"
            "        behavior.state = BottomSheetBehavior.STATE_EXPANDED\n"
            "        behavior.skipCollapsed = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE\n"
            "\n"
            "        when {\n",
            "        behavior.state = BottomSheetBehavior.STATE_EXPANDED\n"
            "        behavior.skipCollapsed =\n"
            "            context.resources.configuration.orientation ==\n"
            "                Configuration.ORIENTATION_LANDSCAPE\n"
            "\n"
            "        when {\n",
            "hapus duplikat behavior.state & pecah baris >100 char",
        ),
        (
            "                    btnModeration.visibility = if (NetPlayManager.netPlayIsModerator()) View.VISIBLE else View.GONE\n"
            "                    btnModeration.setOnClickListener {\n"
            "                        showModerationDialog()\n"
            "                    }\n"
            "\n"
            "                }\n",
            "                    btnModeration.visibility =\n"
            "                        if (NetPlayManager.netPlayIsModerator()) View.VISIBLE else View.GONE\n"
            "                    btnModeration.setOnClickListener {\n"
            "                        showModerationDialog()\n"
            "                    }\n"
            "                }\n",
            "pecah baris >100 char & hapus blank line sebelum }",
        ),
        (
            "        abstract inner class NetPlayViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView), View.OnClickListener {\n"
            "            init {\n"
            "                itemView.setOnClickListener(this)\n"
            "            }\n"
            "            abstract fun bind(item: NetPlayItems)\n"
            "        }\n"
            "\n"
            "        inner class TextViewHolder(private val binding: ItemTextNetplayBinding) : NetPlayViewHolder(binding.root) {\n",
            "        abstract inner class NetPlayViewHolder(itemView: View) :\n"
            "            RecyclerView.ViewHolder(itemView), View.OnClickListener {\n"
            "            init {\n"
            "                itemView.setOnClickListener(this)\n"
            "            }\n"
            "            abstract fun bind(item: NetPlayItems)\n"
            "        }\n"
            "\n"
            "        inner class TextViewHolder(private val binding: ItemTextNetplayBinding) :\n"
            "            NetPlayViewHolder(binding.root) {\n",
            "super type harus mulai di baris baru (baris 125, 132)",
        ),
        (
            "            override fun onClick(clicked: View) {}\n"
            "\n"
            "            override fun bind(item: NetPlayItems) {\n"
            "                netPlayItem = item\n",
            "            override fun onClick(clicked: View) {\n"
            "            }\n"
            "\n"
            "            override fun bind(item: NetPlayItems) {\n"
            "                netPlayItem = item\n",
            "lengkapi blok kosong onClick TextViewHolder dengan { } eksplisit (Missing { ... })",
        ),
        (
            "        inner class ButtonViewHolder(private val binding: ItemButtonNetplayBinding) : NetPlayViewHolder(binding.root) {\n",
            "        inner class ButtonViewHolder(private val binding: ItemButtonNetplayBinding) :\n"
            "            NetPlayViewHolder(binding.root) {\n",
            "super type harus mulai baris baru (ButtonViewHolder, baris 154)",
        ),
        (
            "            override fun onClick(clicked: View) {}\n"
            "\n"
            "            private fun showPopupMenu(view: View) {\n"
            "                PopupMenu(view.context, view).apply {\n"
            "                    inflate(R.menu.menu_netplay_member)\n"
            "                    menu.findItem(R.id.action_kick).isEnabled = isModerator &&\n"
            "                            netPlayItems.name != NetPlayManager.getUsername(context)\n"
            "                    menu.findItem(R.id.action_ban).isEnabled = isModerator &&\n"
            "                            netPlayItems.name != NetPlayManager.getUsername(context)\n"
            "                    setOnMenuItemClickListener { item ->\n"
            "                        if (item.itemId == R.id.action_kick) {\n"
            "                            NetPlayManager.netPlayKickUser(netPlayItems.name)\n"
            "                            true\n"
            "                        } else if (item.itemId == R.id.action_ban) {\n"
            "                            NetPlayManager.netPlayBanUser(netPlayItems.name)\n"
            "                            true\n"
            "                        } else false\n"
            "                    }\n"
            "                    show()\n"
            "                }\n"
            "            }\n",
            "            override fun onClick(clicked: View) {\n"
            "            }\n"
            "\n"
            "            private fun showPopupMenu(view: View) {\n"
            "                PopupMenu(view.context, view).apply {\n"
            "                    inflate(R.menu.menu_netplay_member)\n"
            "                    menu.findItem(R.id.action_kick).isEnabled = isModerator &&\n"
            "                        netPlayItems.name != NetPlayManager.getUsername(context)\n"
            "                    menu.findItem(R.id.action_ban).isEnabled = isModerator &&\n"
            "                        netPlayItems.name != NetPlayManager.getUsername(context)\n"
            "                    setOnMenuItemClickListener { item ->\n"
            "                        if (item.itemId == R.id.action_kick) {\n"
            "                            NetPlayManager.netPlayKickUser(netPlayItems.name)\n"
            "                            true\n"
            "                        } else if (item.itemId == R.id.action_ban) {\n"
            "                            NetPlayManager.netPlayBanUser(netPlayItems.name)\n"
            "                            true\n"
            "                        } else {\n"
            "                            false\n"
            "                        }\n"
            "                    }\n"
            "                    show()\n"
            "                }\n"
            "            }\n",
            "lengkapi blok kosong onClick ButtonViewHolder & 'else false' -> Missing { ... }",
        ),
        (
            "                netPlayItems.add(NetPlayItems(NetPlayItems.MULTIPLAYER_ROOM_TEXT, roomInfo[0], NetPlayItems.TYPE_TEXT))\n"
            "                netPlayItems.add(NetPlayItems(NetPlayItems.MULTIPLAYER_ROOM_COUNT, \"${infos.size - 1}/${roomInfo[1]}\", NetPlayItems.TYPE_TEXT))\n"
            "                netPlayItems.add(NetPlayItems(NetPlayItems.MULTIPLAYER_SEPARATOR, \"\", NetPlayItems.TYPE_SEPARATOR))\n"
            "                for (i in 1 until infos.size) {\n"
            "                    netPlayItems.add(NetPlayItems(NetPlayItems.MULTIPLAYER_ROOM_MEMBER, infos[i], NetPlayItems.TYPE_BUTTON))\n"
            "                }\n",
            "                netPlayItems.add(\n"
            "                    NetPlayItems(\n"
            "                        NetPlayItems.MULTIPLAYER_ROOM_TEXT,\n"
            "                        roomInfo[0],\n"
            "                        NetPlayItems.TYPE_TEXT\n"
            "                    )\n"
            "                )\n"
            "                netPlayItems.add(\n"
            "                    NetPlayItems(\n"
            "                        NetPlayItems.MULTIPLAYER_ROOM_COUNT,\n"
            "                        \"${infos.size - 1}/${roomInfo[1]}\",\n"
            "                        NetPlayItems.TYPE_TEXT\n"
            "                    )\n"
            "                )\n"
            "                netPlayItems.add(\n"
            "                    NetPlayItems(NetPlayItems.MULTIPLAYER_SEPARATOR, \"\", NetPlayItems.TYPE_SEPARATOR)\n"
            "                )\n"
            "                for (i in 1 until infos.size) {\n"
            "                    netPlayItems.add(\n"
            "                        NetPlayItems(\n"
            "                            NetPlayItems.MULTIPLAYER_ROOM_MEMBER,\n"
            "                            infos[i],\n"
            "                            NetPlayItems.TYPE_BUTTON\n"
            "                        )\n"
            "                    )\n"
            "                }\n",
            "pecah baris >100 char di loadMultiplayerMenu() (baris 197-199)",
        ),
        (
            "                NetPlayItems.TYPE_TEXT -> TextViewHolder(ItemTextNetplayBinding.inflate(inflater, parent, false))\n"
            "                NetPlayItems.TYPE_BUTTON -> ButtonViewHolder(ItemButtonNetplayBinding.inflate(inflater, parent, false))\n"
            "                NetPlayItems.TYPE_SEPARATOR -> object : NetPlayViewHolder(inflater.inflate(R.layout.item_separator_netplay, parent, false)) {\n"
            "                    override fun bind(item: NetPlayItems) {}\n"
            "                    override fun onClick(clicked: View) {}\n"
            "                }\n",
            "                NetPlayItems.TYPE_TEXT ->\n"
            "                    TextViewHolder(ItemTextNetplayBinding.inflate(inflater, parent, false))\n"
            "\n"
            "                NetPlayItems.TYPE_BUTTON ->\n"
            "                    ButtonViewHolder(ItemButtonNetplayBinding.inflate(inflater, parent, false))\n"
            "\n"
            "                NetPlayItems.TYPE_SEPARATOR -> {\n"
            "                    val separatorView = inflater.inflate(\n"
            "                        R.layout.item_separator_netplay,\n"
            "                        parent,\n"
            "                        false\n"
            "                    )\n"
            "                    object : NetPlayViewHolder(separatorView) {\n"
            "                        override fun bind(item: NetPlayItems) {\n"
            "                        }\n"
            "                        override fun onClick(clicked: View) {\n"
            "                        }\n"
            "                    }\n"
            "                }\n",
            "pecah baris >100 char & blank line antar when-condition multiline (onCreateViewHolder)",
        ),
        (
            "        NetPlayManager.setOnAdapterRefreshListener() { type, msg ->\n",
            "        NetPlayManager.setOnAdapterRefreshListener { type, msg ->\n",
            "hapus tanda kurung kosong sebelum lambda (unnecessary empty parentheses)",
        ),
        (
            "        dialog.behavior.state = BottomSheetBehavior.STATE_EXPANDED\n"
            "        dialog.behavior.state = BottomSheetBehavior.STATE_EXPANDED\n"
            "        dialog.behavior.skipCollapsed = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE\n",
            "        dialog.behavior.state = BottomSheetBehavior.STATE_EXPANDED\n"
            "        dialog.behavior.skipCollapsed =\n"
            "            context.resources.configuration.orientation ==\n"
            "                Configuration.ORIENTATION_LANDSCAPE\n",
            "hapus duplikat dialog.behavior.state & pecah baris >100 char (showNetPlayInputDialog)",
        ),
        (
            "        binding.maxPlayersLabel.text = context.getString(R.string.multiplayer_max_players_value, binding.maxPlayers.value.toInt())\n"
            "\n"
            "        binding.maxPlayers.addOnChangeListener { _, value, _ ->\n"
            "            binding.maxPlayersLabel.text = context.getString(R.string.multiplayer_max_players_value, value.toInt())\n"
            "        }\n",
            "        binding.maxPlayersLabel.text = context.getString(\n"
            "            R.string.multiplayer_max_players_value,\n"
            "            binding.maxPlayers.value.toInt()\n"
            "        )\n"
            "\n"
            "        binding.maxPlayers.addOnChangeListener { _, value, _ ->\n"
            "            binding.maxPlayersLabel.text = context.getString(\n"
            "                R.string.multiplayer_max_players_value,\n"
            "                value.toInt()\n"
            "            )\n"
            "        }\n",
            "pecah baris >100 char (maxPlayersLabel.text, baris 276, 279)",
        ),
        (
            "                        NetPlayManager.netPlayCreateRoom(\n"
            "                            ipAddress, port, username,\n"
            "                            preferedGameName, preferedGameId,\n"
            "                            password, roomName, maxPlayers\n"
            "                        )\n",
            "                        NetPlayManager.netPlayCreateRoom(\n"
            "                            ipAddress,\n"
            "                            port,\n"
            "                            username,\n"
            "                            preferedGameName,\n"
            "                            preferedGameId,\n"
            "                            password,\n"
            "                            roomName,\n"
            "                            maxPlayers\n"
            "                        )\n",
            "satu argumen per baris (Argument should be on a separate line)",
        ),
        (
            "                    } else {\n"
            "                        NetPlayManager.netPlayJoinRoom(ipAddress, port, username, password)\n"
            "                    }\n",
            "                    } else {\n"
            "                        NetPlayManager.netPlayJoinRoom(\n"
            "                            ipAddress,\n"
            "                            port,\n"
            "                            username,\n"
            "                            password\n"
            "                        )\n"
            "                    }\n",
            "satu argumen per baris (netPlayJoinRoom, baris 333-335)",
        ),
        (
            "                        } else {\n"
            "                            Toast.makeText(activity, R.string.multiplayer_could_not_connect, Toast.LENGTH_LONG).show()\n"
            "                            binding.btnConfirm.isEnabled = true\n",
            "                        } else {\n"
            "                            Toast.makeText(\n"
            "                                activity,\n"
            "                                R.string.multiplayer_could_not_connect,\n"
            "                                Toast.LENGTH_LONG\n"
            "                            ).show()\n"
            "                            binding.btnConfirm.isEnabled = true\n",
            "pecah baris >100 char Toast.makeText (multiplayer_could_not_connect)",
        ),
        (
            "            val binding = ItemBanListBinding.inflate(\n"
            "                LayoutInflater.from(parent.context), parent, false)\n"
            "            return ViewHolder(binding)\n",
            "            val binding = ItemBanListBinding.inflate(\n"
            "                LayoutInflater.from(parent.context),\n"
            "                parent,\n"
            "                false\n"
            "            )\n"
            "            return ViewHolder(binding)\n",
            "missing newline sebelum ) pada ItemBanListBinding.inflate",
        ),
    ], "NetPlayDialog.kt")

    # =========================================================================
    # 4. utils/NetPlayManager.kt
    # =========================================================================
    path = os.path.join(base, "utils", "NetPlayManager.kt")
    patch_file(path, [
        (
            "    external fun netPlayCreateRoom(ipAddress: String, port: Int, username: String, preferedGameName:String, preferredGameId: Long, password: String, roomName: String, maxPlayers: Int): Int\n",
            "    external fun netPlayCreateRoom(\n"
            "        ipAddress: String,\n"
            "        port: Int,\n"
            "        username: String,\n"
            "        preferedGameName: String,\n"
            "        preferredGameId: Long,\n"
            "        password: String,\n"
            "        roomName: String,\n"
            "        maxPlayers: Int\n"
            "    ): Int\n",
            "pecah deklarasi netPlayCreateRoom & tambahkan spasi setelah ':' (preferedGameName:String)",
        ),
        (
            "    external fun netPlayJoinRoom(ipAddress: String, port: Int, username: String, password: String): Int\n",
            "    external fun netPlayJoinRoom(\n"
            "        ipAddress: String,\n"
            "        port: Int,\n"
            "        username: String,\n"
            "        password: String\n"
            "    ): Int\n",
            "pecah deklarasi netPlayJoinRoom (baris >100 char)",
        ),
        (
            "    fun getUsername(activity: Context): String {        val prefs = PreferenceManager.getDefaultSharedPreferences(activity)\n",
            "    fun getUsername(activity: Context): String {\n"
            "        val prefs = PreferenceManager.getDefaultSharedPreferences(activity)\n",
            "tambahkan newline setelah '{' (getUsername)",
        ),
        (
            "        Thread {\n"
            "            val rooms =  getPublicRooms()\n",
            "        Thread {\n"
            "            val rooms = getPublicRooms()\n",
            "hapus unnecessary long whitespace (rooms = getPublicRooms)",
        ),
        (
            "                if (parts.size == 2) {\n"
            "                    val nickname = parts[0].trim()\n"
            "                    val chatMessage = parts[1].trim()\n"
            "                    addChatMessage(\n"
            "                        ChatMessage(\n"
            "                        nickname = nickname,\n"
            "                        username = \"\",\n"
            "                        message = chatMessage\n"
            "                    )\n"
            "                    )\n"
            "                }\n"
            "            }\n"
            "            NetPlayStatus.MEMBER_JOIN,\n"
            "            NetPlayStatus.MEMBER_LEAVE,\n"
            "            NetPlayStatus.MEMBER_KICKED,\n"
            "            NetPlayStatus.MEMBER_BANNED -> {\n"
            "                addChatMessage(\n"
            "                    ChatMessage(\n"
            "                    nickname = \"System\",\n"
            "                    username = \"\",\n"
            "                    message = message\n"
            "                )\n"
            "                )\n"
            "            }\n"
            "        }\n"
            "\n"
            "            Handler(Looper.getMainLooper()).post {\n"
            "                if (!isChatOpen) {\n"
            "                    Toast.makeText(context, message, Toast.LENGTH_SHORT).show()\n"
            "                }\n"
            "            }\n"
            "\n"
            "\n"
            "        messageListener?.invoke(type, msg)\n",
            "                if (parts.size == 2) {\n"
            "                    val nickname = parts[0].trim()\n"
            "                    val chatMessage = parts[1].trim()\n"
            "                    addChatMessage(\n"
            "                        ChatMessage(\n"
            "                            nickname = nickname,\n"
            "                            username = \"\",\n"
            "                            message = chatMessage\n"
            "                        )\n"
            "                    )\n"
            "                }\n"
            "            }\n"
            "\n"
            "            NetPlayStatus.MEMBER_JOIN,\n"
            "            NetPlayStatus.MEMBER_LEAVE,\n"
            "            NetPlayStatus.MEMBER_KICKED,\n"
            "            NetPlayStatus.MEMBER_BANNED -> {\n"
            "                addChatMessage(\n"
            "                    ChatMessage(\n"
            "                        nickname = \"System\",\n"
            "                        username = \"\",\n"
            "                        message = message\n"
            "                    )\n"
            "                )\n"
            "            }\n"
            "        }\n"
            "\n"
            "        Handler(Looper.getMainLooper()).post {\n"
            "            if (!isChatOpen) {\n"
            "                Toast.makeText(context, message, Toast.LENGTH_SHORT).show()\n"
            "            }\n"
            "        }\n"
            "\n"
            "        messageListener?.invoke(type, msg)\n",
            "perbaiki indentasi ChatMessage(), blank line antar when-condition, indentasi Handler.post",
        ),
        (
            "            NetPlayStatus.NETWORK_ERROR -> context.getString(R.string.multiplayer_network_error)\n"
            "            NetPlayStatus.LOST_CONNECTION -> context.getString(R.string.multiplayer_lost_connection)\n"
            "            NetPlayStatus.NAME_COLLISION -> context.getString(R.string.multiplayer_name_collision)\n"
            "            NetPlayStatus.MAC_COLLISION -> context.getString(R.string.multiplayer_mac_collision)\n"
            "            NetPlayStatus.CONSOLE_ID_COLLISION -> context.getString(R.string.multiplayer_console_id_collision)\n"
            "            NetPlayStatus.WRONG_VERSION -> context.getString(R.string.multiplayer_wrong_version)\n"
            "            NetPlayStatus.WRONG_PASSWORD -> context.getString(R.string.multiplayer_wrong_password)\n"
            "            NetPlayStatus.COULD_NOT_CONNECT -> context.getString(R.string.multiplayer_could_not_connect)\n"
            "            NetPlayStatus.ROOM_IS_FULL -> context.getString(R.string.multiplayer_room_is_full)\n"
            "            NetPlayStatus.HOST_BANNED -> context.getString(R.string.multiplayer_host_banned)\n"
            "            NetPlayStatus.PERMISSION_DENIED -> context.getString(R.string.multiplayer_permission_denied)\n"
            "            NetPlayStatus.NO_SUCH_USER -> context.getString(R.string.multiplayer_no_such_user)\n"
            "            NetPlayStatus.ALREADY_IN_ROOM -> context.getString(R.string.multiplayer_already_in_room)\n"
            "            NetPlayStatus.CREATE_ROOM_ERROR -> context.getString(R.string.multiplayer_create_room_error)\n"
            "            NetPlayStatus.HOST_KICKED -> context.getString(R.string.multiplayer_host_kicked)\n"
            "            NetPlayStatus.UNKNOWN_ERROR -> context.getString(R.string.multiplayer_unknown_error)\n"
            "            NetPlayStatus.ROOM_UNINITIALIZED -> context.getString(R.string.multiplayer_room_uninitialized)\n",
            "            NetPlayStatus.NETWORK_ERROR ->\n"
            "                context.getString(R.string.multiplayer_network_error)\n"
            "            NetPlayStatus.LOST_CONNECTION ->\n"
            "                context.getString(R.string.multiplayer_lost_connection)\n"
            "            NetPlayStatus.NAME_COLLISION ->\n"
            "                context.getString(R.string.multiplayer_name_collision)\n"
            "            NetPlayStatus.MAC_COLLISION ->\n"
            "                context.getString(R.string.multiplayer_mac_collision)\n"
            "            NetPlayStatus.CONSOLE_ID_COLLISION ->\n"
            "                context.getString(R.string.multiplayer_console_id_collision)\n"
            "            NetPlayStatus.WRONG_VERSION ->\n"
            "                context.getString(R.string.multiplayer_wrong_version)\n"
            "            NetPlayStatus.WRONG_PASSWORD ->\n"
            "                context.getString(R.string.multiplayer_wrong_password)\n"
            "            NetPlayStatus.COULD_NOT_CONNECT ->\n"
            "                context.getString(R.string.multiplayer_could_not_connect)\n"
            "            NetPlayStatus.ROOM_IS_FULL ->\n"
            "                context.getString(R.string.multiplayer_room_is_full)\n"
            "            NetPlayStatus.HOST_BANNED ->\n"
            "                context.getString(R.string.multiplayer_host_banned)\n"
            "            NetPlayStatus.PERMISSION_DENIED ->\n"
            "                context.getString(R.string.multiplayer_permission_denied)\n"
            "            NetPlayStatus.NO_SUCH_USER ->\n"
            "                context.getString(R.string.multiplayer_no_such_user)\n"
            "            NetPlayStatus.ALREADY_IN_ROOM ->\n"
            "                context.getString(R.string.multiplayer_already_in_room)\n"
            "            NetPlayStatus.CREATE_ROOM_ERROR ->\n"
            "                context.getString(R.string.multiplayer_create_room_error)\n"
            "            NetPlayStatus.HOST_KICKED ->\n"
            "                context.getString(R.string.multiplayer_host_kicked)\n"
            "            NetPlayStatus.UNKNOWN_ERROR ->\n"
            "                context.getString(R.string.multiplayer_unknown_error)\n"
            "            NetPlayStatus.ROOM_UNINITIALIZED ->\n"
            "                context.getString(R.string.multiplayer_room_uninitialized)\n",
            "pecah baris >100 char di formatNetPlayStatus (banyak baris when-branch)",
        ),
        (
            "            NetPlayStatus.MEMBER_JOIN -> context.getString(R.string.multiplayer_member_join, msg)\n"
            "            NetPlayStatus.MEMBER_LEAVE -> context.getString(R.string.multiplayer_member_leave, msg)\n"
            "            NetPlayStatus.MEMBER_KICKED -> context.getString(R.string.multiplayer_member_kicked, msg)\n"
            "            NetPlayStatus.MEMBER_BANNED -> context.getString(R.string.multiplayer_member_banned, msg)\n"
            "            NetPlayStatus.ADDRESS_UNBANNED -> context.getString(R.string.multiplayer_address_unbanned)\n",
            "            NetPlayStatus.MEMBER_JOIN ->\n"
            "                context.getString(R.string.multiplayer_member_join, msg)\n"
            "            NetPlayStatus.MEMBER_LEAVE ->\n"
            "                context.getString(R.string.multiplayer_member_leave, msg)\n"
            "            NetPlayStatus.MEMBER_KICKED ->\n"
            "                context.getString(R.string.multiplayer_member_kicked, msg)\n"
            "            NetPlayStatus.MEMBER_BANNED ->\n"
            "                context.getString(R.string.multiplayer_member_banned, msg)\n"
            "            NetPlayStatus.ADDRESS_UNBANNED ->\n"
            "                context.getString(R.string.multiplayer_address_unbanned)\n",
            "pecah baris >100 char di formatNetPlayStatus (MEMBER_JOIN s.d. ADDRESS_UNBANNED)",
        ),
        (
            "    fun getBanList(): List<String> {\n"
            "        Log.info(\"Netplay Ban ${netPlayGetBanList()}.toList()\")\n"
            "        return netPlayGetBanList().toList()\n"
            "    }\n",
            "    fun getBanList(): List<String> = netPlayGetBanList().toList()\n",
            "function body -> body expression (getBanList)",
        ),
    ], "NetPlayManager.kt")

    # Pastikan NetPlayManager.kt diakhiri newline (File must end with a newline)
    if os.path.isfile(path):
        content = read(path)
        if not content.endswith("\n"):
            write(path, content + "\n")
            print("  [OK]   NetPlayManager.kt: 'tambahkan newline di akhir file'")
        else:
            print("  [SKIP] NetPlayManager.kt: 'newline akhir file' (sudah OK)")

    # =========================================================================
    # 5. features/settings/model/Settings.kt
    # =========================================================================
    path = os.path.join(base, "features", "settings", "model", "Settings.kt")
    patch_file(path, [
        (
            "        const val PREF_COMBO_1_LABEL   = \"combo_button_1_label\"\n"
            "        const val PREF_COMBO_2_LABEL   = \"combo_button_2_label\"\n"
            "        const val PREF_COMBO_3_LABEL   = \"combo_button_3_label\"\n"
            "        const val PREF_COMBO_4_LABEL   = \"combo_button_4_label\"\n"
            "        const val PREF_COMBO_5_LABEL   = \"combo_button_5_label\"\n",
            "        const val PREF_COMBO_1_LABEL = \"combo_button_1_label\"\n"
            "        const val PREF_COMBO_2_LABEL = \"combo_button_2_label\"\n"
            "        const val PREF_COMBO_3_LABEL = \"combo_button_3_label\"\n"
            "        const val PREF_COMBO_4_LABEL = \"combo_button_4_label\"\n"
            "        const val PREF_COMBO_5_LABEL = \"combo_button_5_label\"\n",
            "hapus spasi berlebih sebelum '=' pada konstanta PREF_COMBO_*_LABEL",
        ),
    ], "Settings.kt")

    # =========================================================================
    # 6. features/settings/ui/ComboButtonSettingsFragment.kt
    # =========================================================================
    path = os.path.join(base, "features", "settings", "ui", "ComboButtonSettingsFragment.kt")
    patch_file(path, [
        (
            "            val cardBinding = ItemComboButtonBinding.inflate(\n"
            "                layoutInflater, binding.comboContainer, true\n"
            "            )\n",
            "            val cardBinding = ItemComboButtonBinding.inflate(\n"
            "                layoutInflater,\n"
            "                binding.comboContainer,\n"
            "                true\n"
            "            )\n",
            "satu argumen per baris (ItemComboButtonBinding.inflate)",
        ),
        (
            "        val names      = assignable.map { it.first }.toTypedArray()\n"
            "        val ids        = assignable.map { it.second }\n"
            "        val selected   = ComboButtonManager.getButtonsForSlot(slot).toMutableSet()\n"
            "        val checked    = BooleanArray(names.size) { i -> ids[i] in selected }\n",
            "        val names = assignable.map { it.first }.toTypedArray()\n"
            "        val ids = assignable.map { it.second }\n"
            "        val selected = ComboButtonManager.getButtonsForSlot(slot).toMutableSet()\n"
            "        val checked = BooleanArray(names.size) { i -> ids[i] in selected }\n",
            "hapus spasi berlebih sebelum '=' pada names/ids/selected/checked",
        ),
    ], "ComboButtonSettingsFragment.kt")

    # =========================================================================
    # 7. fragments/EmulationFragment.kt
    # =========================================================================
    path = os.path.join(base, "fragments", "EmulationFragment.kt")
    patch_file(path, [
        (
            "                R.id.menu_emulation_adjust_scale_combo_1 -> {\n"
            "                    showAdjustScaleDialog(\"controlScale-\" + org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_1)\n"
            "                    true\n"
            "                }\n",
            "                R.id.menu_emulation_adjust_scale_combo_1 -> {\n"
            "                    showAdjustScaleDialog(\n"
            "                        \"controlScale-\" +\n"
            "                            org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_1\n"
            "                    )\n"
            "                    true\n"
            "                }\n",
            "pecah baris >100 char (combo_1)",
        ),
        (
            "                R.id.menu_emulation_adjust_scale_combo_2 -> {\n"
            "                    showAdjustScaleDialog(\"controlScale-\" + org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_2)\n"
            "                    true\n"
            "                }\n",
            "                R.id.menu_emulation_adjust_scale_combo_2 -> {\n"
            "                    showAdjustScaleDialog(\n"
            "                        \"controlScale-\" +\n"
            "                            org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_2\n"
            "                    )\n"
            "                    true\n"
            "                }\n",
            "pecah baris >100 char (combo_2)",
        ),
        (
            "                R.id.menu_emulation_adjust_scale_combo_3 -> {\n"
            "                    showAdjustScaleDialog(\"controlScale-\" + org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_3)\n"
            "                    true\n"
            "                }\n",
            "                R.id.menu_emulation_adjust_scale_combo_3 -> {\n"
            "                    showAdjustScaleDialog(\n"
            "                        \"controlScale-\" +\n"
            "                            org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_3\n"
            "                    )\n"
            "                    true\n"
            "                }\n",
            "pecah baris >100 char (combo_3)",
        ),
        (
            "                R.id.menu_emulation_adjust_scale_combo_4 -> {\n"
            "                    showAdjustScaleDialog(\"controlScale-\" + org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_4)\n"
            "                    true\n"
            "                }\n",
            "                R.id.menu_emulation_adjust_scale_combo_4 -> {\n"
            "                    showAdjustScaleDialog(\n"
            "                        \"controlScale-\" +\n"
            "                            org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_4\n"
            "                    )\n"
            "                    true\n"
            "                }\n",
            "pecah baris >100 char (combo_4)",
        ),
        (
            "                R.id.menu_emulation_adjust_scale_combo_5 -> {\n"
            "                    showAdjustScaleDialog(\"controlScale-\" + org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_5)\n"
            "                    true\n"
            "                }\n",
            "                R.id.menu_emulation_adjust_scale_combo_5 -> {\n"
            "                    showAdjustScaleDialog(\n"
            "                        \"controlScale-\" +\n"
            "                            org.citra.citra_emu.overlay.ComboButtonManager.COMBO_BUTTON_5\n"
            "                    )\n"
            "                    true\n"
            "                }\n",
            "pecah baris >100 char (combo_5)",
        ),
        (
            "                if (indexSelected in 16..20) {\n"
            "                    val slot = indexSelected - 15  // 16->1, 17->2, ...\n"
            "                    org.citra.citra_emu.overlay.ComboButtonManager.setEnabled(slot, isChecked)\n"
            "                }\n",
            "                if (indexSelected in 16..20) {\n"
            "                    val slot = indexSelected - 15 // 16->1, 17->2, ...\n"
            "                    org.citra.citra_emu.overlay.ComboButtonManager.setEnabled(slot, isChecked)\n"
            "                }\n",
            "hapus unnecessary long whitespace sebelum comment '// 16->1, 17->2, ...'",
        ),
    ], "EmulationFragment.kt")

    # =========================================================================
    # 8. overlay/ComboButtonManager.kt
    # =========================================================================
    path = os.path.join(base, "overlay", "ComboButtonManager.kt")
    patch_file(path, [
        (
            "    const val COMBO_COUNT          = 5\n"
            "    const val MAX_BUTTONS_PER_COMBO = 4\n",
            "    const val COMBO_COUNT = 5\n"
            "    const val MAX_BUTTONS_PER_COMBO = 4\n",
            "hapus spasi berlebih sebelum '=' (COMBO_COUNT)",
        ),
        (
            "    val COMBO_IDS = intArrayOf(\n"
            "        COMBO_BUTTON_1, COMBO_BUTTON_2, COMBO_BUTTON_3,\n"
            "        COMBO_BUTTON_4, COMBO_BUTTON_5,\n"
            "    )\n",
            "    val COMBO_IDS = intArrayOf(\n"
            "        COMBO_BUTTON_1,\n"
            "        COMBO_BUTTON_2,\n"
            "        COMBO_BUTTON_3,\n"
            "        COMBO_BUTTON_4,\n"
            "        COMBO_BUTTON_5\n"
            "    )\n",
            "satu argumen per baris & hapus trailing comma (COMBO_IDS)",
        ),
        (
            "    fun enabledKey(slot: Int) = \"combo_button_${slot}_enabled\"\n"
            "    fun labelKey(slot: Int)   = \"combo_button_${slot}_label\"\n"
            "    fun buttonsKey(slot: Int) = \"combo_button_${slot}_buttons\"\n",
            "    fun enabledKey(slot: Int) = \"combo_button_${slot}_enabled\"\n"
            "    fun labelKey(slot: Int) = \"combo_button_${slot}_label\"\n"
            "    fun buttonsKey(slot: Int) = \"combo_button_${slot}_buttons\"\n",
            "hapus spasi berlebih & unexpected whitespace sebelum '=' (labelKey)",
        ),
        (
            "        preferences.edit()\n"
            "            .putString(buttonsKey(slot), buttonIds.distinct().take(MAX_BUTTONS_PER_COMBO).joinToString(\",\"))\n"
            "            .apply()\n",
            "        preferences.edit()\n"
            "            .putString(\n"
            "                buttonsKey(slot),\n"
            "                buttonIds.distinct().take(MAX_BUTTONS_PER_COMBO).joinToString(\",\")\n"
            "            )\n"
            "            .apply()\n",
            "pecah baris >100 char & satu argumen per baris (setButtonsForSlot)",
        ),
        (
            "    /** Display label; falls back to auto-generated \"A+B\" style. */\n"
            "    fun getLabelForSlot(slot: Int): String =\n"
            "        preferences.getString(labelKey(slot), \"\")\n"
            "            ?.takeIf { it.isNotBlank() } ?: autoLabel(slot)\n",
            "    /** Display label; falls back to auto-generated \"A+B\" style. */\n"
            "    fun getLabelForSlot(slot: Int): String = preferences.getString(labelKey(slot), \"\")\n"
            "        ?.takeIf { it.isNotBlank() } ?: autoLabel(slot)\n",
            "satukan body expression dengan signature (First line of body expression fits on same line)",
        ),
        (
            "    fun buttonShortName(id: Int): String = when (id) {\n"
            "        NativeLibrary.ButtonType.BUTTON_A      -> \"A\"\n"
            "        NativeLibrary.ButtonType.BUTTON_B      -> \"B\"\n"
            "        NativeLibrary.ButtonType.BUTTON_X      -> \"X\"\n"
            "        NativeLibrary.ButtonType.BUTTON_Y      -> \"Y\"\n"
            "        NativeLibrary.ButtonType.BUTTON_START  -> \"Start\"\n"
            "        NativeLibrary.ButtonType.BUTTON_SELECT -> \"Select\"\n"
            "        NativeLibrary.ButtonType.BUTTON_HOME   -> \"Home\"\n"
            "        NativeLibrary.ButtonType.TRIGGER_L     -> \"L\"\n"
            "        NativeLibrary.ButtonType.TRIGGER_R     -> \"R\"\n"
            "        NativeLibrary.ButtonType.BUTTON_ZL     -> \"ZL\"\n"
            "        NativeLibrary.ButtonType.BUTTON_ZR     -> \"ZR\"\n"
            "        NativeLibrary.ButtonType.DPAD_UP       -> \"↑\"\n"
            "        NativeLibrary.ButtonType.DPAD_DOWN     -> \"↓\"\n"
            "        NativeLibrary.ButtonType.DPAD_LEFT     -> \"←\"\n"
            "        NativeLibrary.ButtonType.DPAD_RIGHT    -> \"→\"\n"
            "        else                                   -> \"[$id]\"\n"
            "    }\n",
            "    fun buttonShortName(id: Int): String = when (id) {\n"
            "        NativeLibrary.ButtonType.BUTTON_A -> \"A\"\n"
            "        NativeLibrary.ButtonType.BUTTON_B -> \"B\"\n"
            "        NativeLibrary.ButtonType.BUTTON_X -> \"X\"\n"
            "        NativeLibrary.ButtonType.BUTTON_Y -> \"Y\"\n"
            "        NativeLibrary.ButtonType.BUTTON_START -> \"Start\"\n"
            "        NativeLibrary.ButtonType.BUTTON_SELECT -> \"Select\"\n"
            "        NativeLibrary.ButtonType.BUTTON_HOME -> \"Home\"\n"
            "        NativeLibrary.ButtonType.TRIGGER_L -> \"L\"\n"
            "        NativeLibrary.ButtonType.TRIGGER_R -> \"R\"\n"
            "        NativeLibrary.ButtonType.BUTTON_ZL -> \"ZL\"\n"
            "        NativeLibrary.ButtonType.BUTTON_ZR -> \"ZR\"\n"
            "        NativeLibrary.ButtonType.DPAD_UP -> \"↑\"\n"
            "        NativeLibrary.ButtonType.DPAD_DOWN -> \"↓\"\n"
            "        NativeLibrary.ButtonType.DPAD_LEFT -> \"←\"\n"
            "        NativeLibrary.ButtonType.DPAD_RIGHT -> \"→\"\n"
            "        else -> \"[$id]\"\n"
            "    }\n",
            "hapus semua spasi perataan kolom pada when-branch buttonShortName",
        ),
        (
            "    val assignableButtons: List<Pair<String, Int>> = listOf(\n"
            "        \"A\"       to NativeLibrary.ButtonType.BUTTON_A,\n"
            "        \"B\"       to NativeLibrary.ButtonType.BUTTON_B,\n"
            "        \"X\"       to NativeLibrary.ButtonType.BUTTON_X,\n"
            "        \"Y\"       to NativeLibrary.ButtonType.BUTTON_Y,\n"
            "        \"L\"       to NativeLibrary.ButtonType.TRIGGER_L,\n"
            "        \"R\"       to NativeLibrary.ButtonType.TRIGGER_R,\n"
            "        \"ZL\"      to NativeLibrary.ButtonType.BUTTON_ZL,\n"
            "        \"ZR\"      to NativeLibrary.ButtonType.BUTTON_ZR,\n"
            "        \"Start\"   to NativeLibrary.ButtonType.BUTTON_START,\n"
            "        \"Select\"  to NativeLibrary.ButtonType.BUTTON_SELECT,\n"
            "        \"D-Up\"    to NativeLibrary.ButtonType.DPAD_UP,\n"
            "        \"D-Down\"  to NativeLibrary.ButtonType.DPAD_DOWN,\n"
            "        \"D-Left\"  to NativeLibrary.ButtonType.DPAD_LEFT,\n"
            "        \"D-Right\" to NativeLibrary.ButtonType.DPAD_RIGHT,\n"
            "    )\n",
            "    val assignableButtons: List<Pair<String, Int>> = listOf(\n"
            "        \"A\" to NativeLibrary.ButtonType.BUTTON_A,\n"
            "        \"B\" to NativeLibrary.ButtonType.BUTTON_B,\n"
            "        \"X\" to NativeLibrary.ButtonType.BUTTON_X,\n"
            "        \"Y\" to NativeLibrary.ButtonType.BUTTON_Y,\n"
            "        \"L\" to NativeLibrary.ButtonType.TRIGGER_L,\n"
            "        \"R\" to NativeLibrary.ButtonType.TRIGGER_R,\n"
            "        \"ZL\" to NativeLibrary.ButtonType.BUTTON_ZL,\n"
            "        \"ZR\" to NativeLibrary.ButtonType.BUTTON_ZR,\n"
            "        \"Start\" to NativeLibrary.ButtonType.BUTTON_START,\n"
            "        \"Select\" to NativeLibrary.ButtonType.BUTTON_SELECT,\n"
            "        \"D-Up\" to NativeLibrary.ButtonType.DPAD_UP,\n"
            "        \"D-Down\" to NativeLibrary.ButtonType.DPAD_DOWN,\n"
            "        \"D-Left\" to NativeLibrary.ButtonType.DPAD_LEFT,\n"
            "        \"D-Right\" to NativeLibrary.ButtonType.DPAD_RIGHT\n"
            "    )\n",
            "hapus spasi perataan kolom & trailing comma terakhir pada assignableButtons",
        ),
    ], "ComboButtonManager.kt")

    # =========================================================================
    # 9. overlay/InputOverlay.kt
    # =========================================================================
    path = os.path.join(base, "overlay", "InputOverlay.kt")
    patch_file(path, [
        (
            "import androidx.core.content.ContextCompat\n"
            "import androidx.preference.PreferenceManager\n"
            "import java.lang.NullPointerException\n"
            "import kotlin.math.min\n"
            "import org.citra.citra_emu.CitraApplication\n"
            "import org.citra.citra_emu.NativeLibrary\n"
            "import org.citra.citra_emu.R\n"
            "import org.citra.citra_emu.utils.EmulationMenuSettings\n"
            "import org.citra.citra_emu.utils.TurboHelper\n"
            "import org.citra.citra_emu.overlay.ComboButtonManager\n"
            "import java.lang.NullPointerException\n"
            "import kotlin.math.min\n",
            "import androidx.core.content.ContextCompat\n"
            "import androidx.preference.PreferenceManager\n"
            "import java.lang.NullPointerException\n"
            "import kotlin.math.min\n"
            "import org.citra.citra_emu.CitraApplication\n"
            "import org.citra.citra_emu.NativeLibrary\n"
            "import org.citra.citra_emu.R\n"
            "import org.citra.citra_emu.utils.EmulationMenuSettings\n"
            "import org.citra.citra_emu.utils.TurboHelper\n",
            "hapus duplikat import NullPointerException, kotlin.math.min, dan ComboButtonManager (sama package, tidak perlu di-import)",
        ),
        (
            "                    } else if (button.id == NativeLibrary.ButtonType.BUTTON_TURBO && button.status == NativeLibrary.ButtonState.PRESSED) {\n"
            "                        TurboHelper.toggleTurbo(true)\n"
            "                    }\n",
            "                    } else if (button.id == NativeLibrary.ButtonType.BUTTON_TURBO &&\n"
            "                        button.status == NativeLibrary.ButtonState.PRESSED\n"
            "                    ) {\n"
            "                        TurboHelper.toggleTurbo(true)\n"
            "                    }\n",
            "pecah baris >100 char (BUTTON_TURBO check)",
        ),
        (
            "            ComboButtonManager.COMBO_BUTTON_1,\n"
            "            ComboButtonManager.COMBO_BUTTON_2,\n"
            "            ComboButtonManager.COMBO_BUTTON_3,\n"
            "            ComboButtonManager.COMBO_BUTTON_4,\n"
            "            ComboButtonManager.COMBO_BUTTON_5,\n"
            "        )\n"
            "        val comboDefaultDrawables = intArrayOf(\n"
            "            R.drawable.combo_button_1,\n"
            "            R.drawable.combo_button_2,\n"
            "            R.drawable.combo_button_3,\n"
            "            R.drawable.combo_button_4,\n"
            "            R.drawable.combo_button_5,\n"
            "        )\n"
            "        val comboPressedDrawables = intArrayOf(\n"
            "            R.drawable.combo_button_1_pressed,\n"
            "            R.drawable.combo_button_2_pressed,\n"
            "            R.drawable.combo_button_3_pressed,\n"
            "            R.drawable.combo_button_4_pressed,\n"
            "            R.drawable.combo_button_5_pressed,\n"
            "        )\n",
            "            ComboButtonManager.COMBO_BUTTON_1,\n"
            "            ComboButtonManager.COMBO_BUTTON_2,\n"
            "            ComboButtonManager.COMBO_BUTTON_3,\n"
            "            ComboButtonManager.COMBO_BUTTON_4,\n"
            "            ComboButtonManager.COMBO_BUTTON_5\n"
            "        )\n"
            "        val comboDefaultDrawables = intArrayOf(\n"
            "            R.drawable.combo_button_1,\n"
            "            R.drawable.combo_button_2,\n"
            "            R.drawable.combo_button_3,\n"
            "            R.drawable.combo_button_4,\n"
            "            R.drawable.combo_button_5\n"
            "        )\n"
            "        val comboPressedDrawables = intArrayOf(\n"
            "            R.drawable.combo_button_1_pressed,\n"
            "            R.drawable.combo_button_2_pressed,\n"
            "            R.drawable.combo_button_3_pressed,\n"
            "            R.drawable.combo_button_4_pressed,\n"
            "            R.drawable.combo_button_5_pressed\n"
            "        )\n",
            "hapus trailing comma sebelum ')' pada 3 array combo button",
        ),
        (
            "        val combo1X = preferences.getFloat(\n"
            "            \"${ComboButtonManager.COMBO_BUTTON_1}-X\", -1f\n"
            "        )\n",
            "        val combo1X = preferences.getFloat(\"${ComboButtonManager.COMBO_BUTTON_1}-X\", -1f)\n",
            "satukan argumen getFloat combo1X dalam satu baris (fit on single line)",
        ),
        (
            "        val combo1PortraitX = preferences.getFloat(\n"
            "            \"${ComboButtonManager.COMBO_BUTTON_1}-Portrait-X\", -1f\n"
            "        )\n",
            "        val combo1PortraitX =\n"
            "            preferences.getFloat(\"${ComboButtonManager.COMBO_BUTTON_1}-Portrait-X\", -1f)\n",
            "satukan argumen getFloat combo1PortraitX dalam satu baris (fit on single line)",
        ),
    ], "InputOverlay.kt")

    # =========================================================================
    # 10. NativeLibrary.kt
    # =========================================================================
    path = os.path.join(base, "NativeLibrary.kt")
    patch_file(path, [
        (
            "import com.google.android.material.dialog.MaterialAlertDialogBuilder\n"
            "import java.lang.ref.WeakReference\n"
            "import java.util.Date\n"
            "import org.citra.citra_emu.activities.EmulationActivity\n"
            "import org.citra.citra_emu.utils.EmulationMenuSettings\n"
            "import org.citra.citra_emu.model.Game\n"
            "import org.citra.citra_emu.utils.BuildUtil\n"
            "import org.citra.citra_emu.utils.FileUtil\n"
            "import org.citra.citra_emu.utils.GraphicsUtil\n"
            "import org.citra.citra_emu.utils.Log\n"
            "import org.citra.citra_emu.utils.RemovableStorageHelper\n"
            "import org.citra.citra_emu.viewmodel.CompressProgressDialogViewModel\n"
            "import org.citra.citra_emu.utils.NetPlayManager\n"
            "import java.lang.ref.WeakReference\n"
            "import java.util.Date\n",
            "import com.google.android.material.dialog.MaterialAlertDialogBuilder\n"
            "import java.lang.ref.WeakReference\n"
            "import org.citra.citra_emu.activities.EmulationActivity\n"
            "import org.citra.citra_emu.model.Game\n"
            "import org.citra.citra_emu.utils.BuildUtil\n"
            "import org.citra.citra_emu.utils.EmulationMenuSettings\n"
            "import org.citra.citra_emu.utils.FileUtil\n"
            "import org.citra.citra_emu.utils.GraphicsUtil\n"
            "import org.citra.citra_emu.utils.Log\n"
            "import org.citra.citra_emu.utils.NetPlayManager\n"
            "import org.citra.citra_emu.utils.RemovableStorageHelper\n"
            "import org.citra.citra_emu.viewmodel.CompressProgressDialogViewModel\n",
            "urutkan import lexicographic, hapus duplikat WeakReference & import java.util.Date yang tak terpakai",
        ),
        (
            "        if (emulationActivity != null) {\n"
            "            emulationActivity.addNetPlayMessages(type, message)\n"
            "        }\n"
            "        else {\n"
            "            NetPlayManager.addNetPlayMessage(type, message)\n"
            "        }\n",
            "        if (emulationActivity != null) {\n"
            "            emulationActivity.addNetPlayMessages(type, message)\n"
            "        } else {\n"
            "            NetPlayManager.addNetPlayMessage(type, message)\n"
            "        }\n",
            "'else' harus sebaris dengan '}' penutup if (unexpected newline before else)",
        ),
    ], "NativeLibrary.kt")

    # =========================================================================
    # 11. utils/CompatUtils.kt
    # =========================================================================
    path = os.path.join(base, "utils", "CompatUtils.kt")
    patch_file(path, [
        (
            "    fun findActivity(context: Context): Activity {\n"
            "        return when (context) {\n"
            "            is Activity -> context\n"
            "            is ContextWrapper -> findActivity(context.baseContext)\n"
            "            else -> throw IllegalArgumentException(\"Context is not an Activity\")\n"
            "        }\n"
            "    }\n",
            "    fun findActivity(context: Context): Activity = when (context) {\n"
            "        is Activity -> context\n"
            "        is ContextWrapper -> findActivity(context.baseContext)\n"
            "        else -> throw IllegalArgumentException(\"Context is not an Activity\")\n"
            "    }\n",
            "function body -> body expression (findActivity)",
        ),
    ], "CompatUtils.kt")

    # =========================================================================
    # Catatan: activities/EmulationActivity.kt juga punya error import order
    # (baris 7:1) pada log, tapi file tersebut TIDAK diupload sehingga tidak
    # bisa dipatch otomatis di sini. Perbaikan manual: urutkan semua import
    # secara lexicographic tanpa baris kosong di antaranya (android.* < androidx.* <
    # com.* < java.* < org.*), sama seperti pola pada file-file lain di atas.
    # =========================================================================

    print()
    print(f"Selesai. File diubah: {CHANGED}, dilewati (sudah OK/tidak cocok): {SKIPPED}, hilang: {MISSING}")
    if MISSING:
        print("\nPERHATIAN: ada file yang tidak ditemukan -- pastikan kamu menjalankan")
        print("script ini dari root repo AzaharTrigger-test (folder yang berisi 'src/').")


if __name__ == "__main__":
    main()
