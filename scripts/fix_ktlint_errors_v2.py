#!/usr/bin/env python3
"""
fix_ktlint_errors_v2.py
Perbaikan sisa error ktlint setelah fix_ktlint_errors.py (v1).

File yang diubah:
  - activities/EmulationActivity.kt  : import order (NetPlayManager sebelum RefreshRateUtil)
  - dialogs/ChatDialog.kt            : indentasi continuation binary expression (baris 50)
  - dialogs/NetPlayDialog.kt         : banyak sisa (indentasi, Missing{}, argumen, blank-line
                                       antar when-condition, baris >100 char)
  - utils/NetPlayManager.kt          : unused import WifiManager & Formatter, import order,
                                       blank line antar multiline when-conditions
  - NativeLibrary.kt                 : unused import (EmulationMenuSettings)

Jalankan dari root repo AzaharTrigger-test SETELAH v1:

    python3 scripts/fix_ktlint_errors_v2.py
"""

import os
import sys

REPO_CANDIDATES = [".", "AzaharTrigger-test"]
BASE_REL = "src/android/app/src/main/java/org/citra/citra_emu"
CHANGED = 0
SKIPPED = 0
MISSING = 0


def find_repo_root():
    for cand in REPO_CANDIDATES:
        probe = os.path.join(cand, BASE_REL)
        if os.path.isdir(probe):
            return os.path.abspath(cand)
    print(f"[FATAL] Tidak menemukan folder '{BASE_REL}'")
    sys.exit(1)


def read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write(path, content):
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def patch_file(path, replacements, label):
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
            status = "[SKIP] (sudah terpatch)" if new in content else "[WARN] pola tidak ditemukan"
            print(f"  {status} {label}: '{desc}'")
            continue
        content = content.replace(old, new, 1)
        file_changed = True
        print(f"  [OK]   {label}: '{desc}'")
    if file_changed and content != original:
        write(path, content)
        CHANGED += 1
    else:
        SKIPPED += 1


def main():
    root = find_repo_root()
    base = os.path.join(root, BASE_REL)
    print(f"Repo root: {root}\n")

    # =========================================================================
    # 1. activities/EmulationActivity.kt — import order
    # =========================================================================
    path = os.path.join(base, "activities", "EmulationActivity.kt")
    patch_file(path, [
        (
            "import org.citra.citra_emu.utils.Log\n"
            "import org.citra.citra_emu.utils.RefreshRateUtil\n"
            "import org.citra.citra_emu.utils.NetPlayManager\n"
            "import org.citra.citra_emu.utils.ThemeUtil\n",
            "import org.citra.citra_emu.utils.Log\n"
            "import org.citra.citra_emu.utils.NetPlayManager\n"
            "import org.citra.citra_emu.utils.RefreshRateUtil\n"
            "import org.citra.citra_emu.utils.ThemeUtil\n",
            "pindahkan NetPlayManager sebelum RefreshRateUtil (lexicographic order)",
        ),
    ], "EmulationActivity.kt")

    # =========================================================================
    # 2. dialogs/ChatDialog.kt — indentasi continuation binary expression
    # =========================================================================
    path = os.path.join(base, "dialogs", "ChatDialog.kt")
    patch_file(path, [
        (
            "        behavior.skipCollapsed =\n"
            "            context.resources.configuration.orientation ==\n"
            "                Configuration.ORIENTATION_LANDSCAPE\n",
            "        behavior.skipCollapsed =\n"
            "            context.resources.configuration.orientation ==\n"
            "            Configuration.ORIENTATION_LANDSCAPE\n",
            "ratakan indentasi continuation binary expression (baris 50, should be 12 not 16)",
        ),
        # Hapus juga duplikat behavior.state
        (
            "        behavior.state = BottomSheetBehavior.STATE_EXPANDED\n"
            "        behavior.state = BottomSheetBehavior.STATE_EXPANDED\n",
            "        behavior.state = BottomSheetBehavior.STATE_EXPANDED\n",
            "hapus duplikat behavior.state",
        ),
    ], "ChatDialog.kt")

    # =========================================================================
    # 3. NativeLibrary.kt — unused import EmulationMenuSettings (baris 32)
    # =========================================================================
    path = os.path.join(base, "NativeLibrary.kt")
    patch_file(path, [
        (
            "import org.citra.citra_emu.utils.EmulationMenuSettings\n",
            "",
            "hapus unused import EmulationMenuSettings (baris 32)",
        ),
    ], "NativeLibrary.kt")

    # =========================================================================
    # 4. utils/NetPlayManager.kt
    # =========================================================================
    path = os.path.join(base, "utils", "NetPlayManager.kt")
    patch_file(path, [
        # 4a. Hapus unused import WifiManager (baris 11) & Formatter (baris 15)
        (
            "import android.net.wifi.WifiManager\n",
            "",
            "hapus unused import WifiManager",
        ),
        (
            "import android.text.format.Formatter\n",
            "",
            "hapus unused import Formatter",
        ),
        # 4b. blank line antar multiline when-conditions di formatNetPlayStatus
        # Setiap when-branch yang terdiri dari 2 baris (condition + getString) harus
        # dipisah blank line dari branch berikutnya.
        (
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
            "                context.getString(R.string.multiplayer_room_uninitialized)\n"
            "            NetPlayStatus.ROOM_IDLE -> context.getString(R.string.multiplayer_room_idle)\n"
            "            NetPlayStatus.ROOM_JOINING -> context.getString(R.string.multiplayer_room_joining)\n"
            "            NetPlayStatus.ROOM_JOINED -> context.getString(R.string.multiplayer_room_joined)\n"
            "            NetPlayStatus.ROOM_MODERATOR -> context.getString(R.string.multiplayer_room_moderator)\n"
            "            NetPlayStatus.MEMBER_JOIN ->\n"
            "                context.getString(R.string.multiplayer_member_join, msg)\n"
            "            NetPlayStatus.MEMBER_LEAVE ->\n"
            "                context.getString(R.string.multiplayer_member_leave, msg)\n"
            "            NetPlayStatus.MEMBER_KICKED ->\n"
            "                context.getString(R.string.multiplayer_member_kicked, msg)\n"
            "            NetPlayStatus.MEMBER_BANNED ->\n"
            "                context.getString(R.string.multiplayer_member_banned, msg)\n"
            "            NetPlayStatus.ADDRESS_UNBANNED ->\n"
            "                context.getString(R.string.multiplayer_address_unbanned)\n"
            "            NetPlayStatus.CHAT_MESSAGE -> msg\n"
            "            else -> \"\"\n",
            "            NetPlayStatus.NETWORK_ERROR ->\n"
            "                context.getString(R.string.multiplayer_network_error)\n"
            "\n"
            "            NetPlayStatus.LOST_CONNECTION ->\n"
            "                context.getString(R.string.multiplayer_lost_connection)\n"
            "\n"
            "            NetPlayStatus.NAME_COLLISION ->\n"
            "                context.getString(R.string.multiplayer_name_collision)\n"
            "\n"
            "            NetPlayStatus.MAC_COLLISION ->\n"
            "                context.getString(R.string.multiplayer_mac_collision)\n"
            "\n"
            "            NetPlayStatus.CONSOLE_ID_COLLISION ->\n"
            "                context.getString(R.string.multiplayer_console_id_collision)\n"
            "\n"
            "            NetPlayStatus.WRONG_VERSION ->\n"
            "                context.getString(R.string.multiplayer_wrong_version)\n"
            "\n"
            "            NetPlayStatus.WRONG_PASSWORD ->\n"
            "                context.getString(R.string.multiplayer_wrong_password)\n"
            "\n"
            "            NetPlayStatus.COULD_NOT_CONNECT ->\n"
            "                context.getString(R.string.multiplayer_could_not_connect)\n"
            "\n"
            "            NetPlayStatus.ROOM_IS_FULL ->\n"
            "                context.getString(R.string.multiplayer_room_is_full)\n"
            "\n"
            "            NetPlayStatus.HOST_BANNED ->\n"
            "                context.getString(R.string.multiplayer_host_banned)\n"
            "\n"
            "            NetPlayStatus.PERMISSION_DENIED ->\n"
            "                context.getString(R.string.multiplayer_permission_denied)\n"
            "\n"
            "            NetPlayStatus.NO_SUCH_USER ->\n"
            "                context.getString(R.string.multiplayer_no_such_user)\n"
            "\n"
            "            NetPlayStatus.ALREADY_IN_ROOM ->\n"
            "                context.getString(R.string.multiplayer_already_in_room)\n"
            "\n"
            "            NetPlayStatus.CREATE_ROOM_ERROR ->\n"
            "                context.getString(R.string.multiplayer_create_room_error)\n"
            "\n"
            "            NetPlayStatus.HOST_KICKED ->\n"
            "                context.getString(R.string.multiplayer_host_kicked)\n"
            "\n"
            "            NetPlayStatus.UNKNOWN_ERROR ->\n"
            "                context.getString(R.string.multiplayer_unknown_error)\n"
            "\n"
            "            NetPlayStatus.ROOM_UNINITIALIZED ->\n"
            "                context.getString(R.string.multiplayer_room_uninitialized)\n"
            "\n"
            "            NetPlayStatus.ROOM_IDLE -> context.getString(R.string.multiplayer_room_idle)\n"
            "\n"
            "            NetPlayStatus.ROOM_JOINING -> context.getString(R.string.multiplayer_room_joining)\n"
            "\n"
            "            NetPlayStatus.ROOM_JOINED -> context.getString(R.string.multiplayer_room_joined)\n"
            "\n"
            "            NetPlayStatus.ROOM_MODERATOR ->\n"
            "                context.getString(R.string.multiplayer_room_moderator)\n"
            "\n"
            "            NetPlayStatus.MEMBER_JOIN ->\n"
            "                context.getString(R.string.multiplayer_member_join, msg)\n"
            "\n"
            "            NetPlayStatus.MEMBER_LEAVE ->\n"
            "                context.getString(R.string.multiplayer_member_leave, msg)\n"
            "\n"
            "            NetPlayStatus.MEMBER_KICKED ->\n"
            "                context.getString(R.string.multiplayer_member_kicked, msg)\n"
            "\n"
            "            NetPlayStatus.MEMBER_BANNED ->\n"
            "                context.getString(R.string.multiplayer_member_banned, msg)\n"
            "\n"
            "            NetPlayStatus.ADDRESS_UNBANNED ->\n"
            "                context.getString(R.string.multiplayer_address_unbanned)\n"
            "\n"
            "            NetPlayStatus.CHAT_MESSAGE -> msg\n"
            "            else -> \"\"\n",
            "tambahkan blank line antar semua multiline when-conditions di formatNetPlayStatus",
        ),
        # 4c. getBanList body expression (baris 221 versi setelah v1)
        (
            "    fun getBanList(): List<String> = netPlayGetBanList().toList()\n",
            "    fun getBanList(): List<String> = netPlayGetBanList().toList()\n",
            "getBanList sudah body expression (no-op check)",
        ),
    ], "NetPlayManager.kt")

    # =========================================================================
    # 5. dialogs/NetPlayDialog.kt — semua sisa error
    # =========================================================================
    path = os.path.join(base, "dialogs", "NetPlayDialog.kt")
    patch_file(path, [
        # 5a. Indentasi continuation binary expression (baris 47 & 288)
        # Pola ini muncul 2x — replace both
        (
            "        behavior.skipCollapsed =\n"
            "            context.resources.configuration.orientation ==\n"
            "                Configuration.ORIENTATION_LANDSCAPE\n"
            "\n"
            "        when {\n",
            "        behavior.skipCollapsed =\n"
            "            context.resources.configuration.orientation ==\n"
            "            Configuration.ORIENTATION_LANDSCAPE\n"
            "\n"
            "        when {\n",
            "ratakan indentasi continuation binary expr baris 47 (should be 12 not 16)",
        ),
        (
            "        dialog.behavior.skipCollapsed =\n"
            "            context.resources.configuration.orientation ==\n"
            "                Configuration.ORIENTATION_LANDSCAPE\n",
            "        dialog.behavior.skipCollapsed =\n"
            "            context.resources.configuration.orientation ==\n"
            "            Configuration.ORIENTATION_LANDSCAPE\n",
            "ratakan indentasi continuation binary expr baris 288 (showNetPlayInputDialog)",
        ),
        # 5b. data class NetPlayItems — No whitespace expected between opening paren
        # dan first parameter (baris 107-111), kondisi ini terjadi karena
        # ktlint mendeteksi spasi berlebih setelah '(' pada pemanggilan constructor.
        # Sebenarnya ini adalah aturan "Function parameter should not start with whitespace".
        # Ini terjadi pada argumen yang multiline tanpa trailing comma.
        # Cara fix: tambahkan blank line sebelum setiap when-condition di onCreateViewHolder
        # DAN tambahkan blank line antar when-conditions di TYPE_SEPARATOR.
        # Baris 107-110 sebenarnya error di data class parameters — ktlint minta
        # format konsisten: jika multi-line, tiap param di baris sendiri dengan trailing comma.
        (
            "    data class NetPlayItems(\n"
            "        val option: Int,\n"
            "        val name: String,\n"
            "        val type: Int,\n"
            "        val id: Int = 0\n"
            "    ) {\n",
            "    data class NetPlayItems(\n"
            "        val option: Int,\n"
            "        val name: String,\n"
            "        val type: Int,\n"
            "        val id: Int = 0,\n"
            "    ) {\n",
            "tambahkan trailing comma pada parameter terakhir data class NetPlayItems",
        ),
        # 5c. TextViewHolder — Missing { ... } di else View.GONE (baris 153)
        (
            "                    visibility = if (iconRes != 0) {\n"
            "                        setImageResource(iconRes)\n"
            "                        View.VISIBLE\n"
            "                    } else View.GONE\n",
            "                    visibility = if (iconRes != 0) {\n"
            "                        setImageResource(iconRes)\n"
            "                        View.VISIBLE\n"
            "                    } else {\n"
            "                        View.GONE\n"
            "                    }\n",
            "Missing { ... } pada else View.GONE (baris 153)",
        ),
        # 5d. showNetPlayInputDialog — Missing { ... } pada if/else expressions
        # baris 294-295 (binding.textTitle.text)
        (
            "        binding.textTitle.text = activity.getString(\n"
            "            if (isCreateRoom) R.string.multiplayer_create_room\n"
            "            else R.string.multiplayer_join_room\n"
            "        )\n",
            "        binding.textTitle.text = activity.getString(\n"
            "            if (isCreateRoom) {\n"
            "                R.string.multiplayer_create_room\n"
            "            } else {\n"
            "                R.string.multiplayer_join_room\n"
            "            }\n"
            "        )\n",
            "Missing { ... } pada if/else di binding.textTitle.text (baris 294-295)",
        ),
        # 5e. binding.ipAddress.setText — Missing { ... } (baris 299-300)
        (
            "        binding.ipAddress.setText(\n"
            "            if (isCreateRoom) NetPlayManager.getIpAddressByWifi(activity)\n"
            "            else NetPlayManager.getRoomAddress(activity)\n"
            "        )\n",
            "        binding.ipAddress.setText(\n"
            "            if (isCreateRoom) {\n"
            "                NetPlayManager.getIpAddressByWifi(activity)\n"
            "            } else {\n"
            "                NetPlayManager.getRoomAddress(activity)\n"
            "            }\n"
            "        )\n",
            "Missing { ... } pada if/else di binding.ipAddress.setText (baris 299-300)",
        ),
        # 5f. Toast.makeText success — if/else di argumen Toast (baris 407-408)
        (
            "                            Toast.makeText(\n"
            "                                CitraApplication.appContext,\n"
            "                                if (isCreateRoom) R.string.multiplayer_create_room_success\n"
            "                                else R.string.multiplayer_join_room_success,\n"
            "                                Toast.LENGTH_LONG\n"
            "                            ).show()\n",
            "                            Toast.makeText(\n"
            "                                CitraApplication.appContext,\n"
            "                                if (isCreateRoom) {\n"
            "                                    R.string.multiplayer_create_room_success\n"
            "                                } else {\n"
            "                                    R.string.multiplayer_join_room_success\n"
            "                                },\n"
            "                                Toast.LENGTH_LONG\n"
            "                            ).show()\n",
            "Missing { ... } pada if/else argumen Toast.makeText success (baris 407-408)",
        ),
        # 5g. binding.btnConfirm.text line >100 char (baris 419)
        (
            "                            binding.btnConfirm.text = activity.getString(R.string.original_button_text)\n"
            "                        }\n"
            "                    }\n"
            "                }.start()\n",
            "                            binding.btnConfirm.text =\n"
            "                                activity.getString(R.string.original_button_text)\n"
            "                        }\n"
            "                    }\n"
            "                }.start()\n",
            "pecah baris >100 char binding.btnConfirm.text (baris 419)",
        ),
        # 5h. BanListAdapter constructor — No whitespace setelah '(' (baris 469-471)
        # Super type harus mulai baris baru (baris 471)
        (
            "    private class BanListAdapter(\n"
            "        banList: List<String>,\n"
            "        private val onUnban: (String) -> Unit\n"
            "    ) : RecyclerView.Adapter<BanListAdapter.ViewHolder>() {\n",
            "    private class BanListAdapter(\n"
            "        banList: List<String>,\n"
            "        private val onUnban: (String) -> Unit,\n"
            "    ) : RecyclerView.Adapter<BanListAdapter.ViewHolder>() {\n",
            "tambahkan trailing comma param terakhir BanListAdapter & super type sudah di baris baru",
        ),
        # 5i. onBindViewHolder — baris 489 >100 char
        (
            "            val item = if (isUsername) usernameBans[position] else ipBans[position - usernameBans.size]\n",
            "            val item = if (isUsername) {\n"
            "                usernameBans[position]\n"
            "            } else {\n"
            "                ipBans[position - usernameBans.size]\n"
            "            }\n",
            "pecah baris >100 char & Missing { ... } pada if/else di onBindViewHolder (baris 489)",
        ),
        # 5j. NetPlayItems.TYPE_SEPARATOR — add blank line antar when-conditions (baris 258)
        # Sudah ada blank line di antara TYPE_TEXT, TYPE_BUTTON, TYPE_SEPARATOR dari v1,
        # tapi perlu tambahkan blank line sebelum 'else ->'
        (
            "                }\n"
            "                else -> throw IllegalStateException(\"Unsupported view type\")\n",
            "                }\n"
            "\n"
            "                else -> throw IllegalStateException(\"Unsupported view type\")\n",
            "tambahkan blank line sebelum else-branch di onCreateViewHolder when (baris 258)",
        ),
        # 5k. indentasi Toast.makeText multiplayer_port_invalid (baris 348)
        (
            "                Toast.makeText(activity, R.string.multiplayer_port_invalid, Toast.LENGTH_LONG).show()\n",
            "                Toast.makeText(\n"
            "                    activity,\n"
            "                    R.string.multiplayer_port_invalid,\n"
            "                    Toast.LENGTH_LONG\n"
            "                ).show()\n",
            "pecah Toast.makeText multiplayer_port_invalid argumen (baris 348)",
        ),
        # 5l. Toast.makeText room_name_invalid (baris 357)
        (
            "                Toast.makeText(activity, R.string.multiplayer_room_name_invalid, Toast.LENGTH_LONG).show()\n",
            "                Toast.makeText(\n"
            "                    activity,\n"
            "                    R.string.multiplayer_room_name_invalid,\n"
            "                    Toast.LENGTH_LONG\n"
            "                ).show()\n",
            "pecah Toast.makeText multiplayer_room_name_invalid argumen (baris 357)",
        ),
        # 5m. Toast.makeText prefered_game_name_invalid (baris 364)
        (
            "                Toast.makeText(activity, R.string.multiplayer_prefered_game_name_invalid, Toast.LENGTH_LONG).show()\n",
            "                Toast.makeText(\n"
            "                    activity,\n"
            "                    R.string.multiplayer_prefered_game_name_invalid,\n"
            "                    Toast.LENGTH_LONG\n"
            "                ).show()\n",
            "pecah Toast.makeText multiplayer_prefered_game_name_invalid (baris 364)",
        ),
        # 5n. Toast.makeText input_invalid (baris 371)
        (
            "                Toast.makeText(activity, R.string.multiplayer_input_invalid, Toast.LENGTH_LONG).show()\n",
            "                Toast.makeText(\n"
            "                    activity,\n"
            "                    R.string.multiplayer_input_invalid,\n"
            "                    Toast.LENGTH_LONG\n"
            "                ).show()\n",
            "pecah Toast.makeText multiplayer_input_invalid (baris 371)",
        ),
        # 5o. preferedGameName baris 341 >100 char
        (
            "            val preferedGameName = if (isCreateRoom) binding.dropdownPreferedGameName.text.toString() else \"\"\n",
            "            val preferedGameName =\n"
            "                if (isCreateRoom) binding.dropdownPreferedGameName.text.toString() else \"\"\n",
            "pecah baris >100 char preferedGameName (baris 341)",
        ),
        # 5p. binding.btnConfirm.text di port_invalid (baris 350) — juga >100 char
        (
            "                binding.btnConfirm.text = activity.getString(R.string.original_button_text)\n"
            "                return@setOnClickListener\n",
            "                binding.btnConfirm.text =\n"
            "                    activity.getString(R.string.original_button_text)\n"
            "                return@setOnClickListener\n",
            "pecah baris >100 char binding.btnConfirm.text di port_invalid block",
        ),
        # 5q. binding.btnConfirm.text di room_name_invalid (baris 359)
        (
            "                binding.btnConfirm.text = activity.getString(R.string.original_button_text)\n"
            "                return@setOnClickListener\n"
            "            }\n"
            "\n"
            "            if (isCreateRoom && preferedGameName.isEmpty()) {\n",
            "                binding.btnConfirm.text =\n"
            "                    activity.getString(R.string.original_button_text)\n"
            "                return@setOnClickListener\n"
            "            }\n"
            "\n"
            "            if (isCreateRoom && preferedGameName.isEmpty()) {\n",
            "pecah baris >100 char binding.btnConfirm.text di room_name_invalid block",
        ),
        # 5r. binding.btnConfirm.text di prefered_game_name_invalid (baris 366)
        (
            "                binding.btnConfirm.text = activity.getString(R.string.original_button_text)\n"
            "                return@setOnClickListener\n"
            "            }\n"
            "\n"
            "            if (ipAddress.length < 7 || username.length < 5) {\n",
            "                binding.btnConfirm.text =\n"
            "                    activity.getString(R.string.original_button_text)\n"
            "                return@setOnClickListener\n"
            "            }\n"
            "\n"
            "            if (ipAddress.length < 7 || username.length < 5) {\n",
            "pecah baris >100 char binding.btnConfirm.text di prefered_game_name_invalid block",
        ),
        # 5s. ViewHolder class di BanListAdapter — super type >100 char (baris 476)
        (
            "        class ViewHolder(val binding: ItemBanListBinding) : RecyclerView.ViewHolder(binding.root)\n",
            "        class ViewHolder(val binding: ItemBanListBinding) :\n"
            "            RecyclerView.ViewHolder(binding.root)\n",
            "pecah super type ViewHolder >100 char (baris 476)",
        ),
        # 5t. icon.setImageResource baris 493 >100 char
        (
            "                icon.setImageResource(if (isUsername) R.drawable.ic_user else R.drawable.ic_ip)\n",
            "                icon.setImageResource(\n"
            "                    if (isUsername) R.drawable.ic_user else R.drawable.ic_ip\n"
            "                )\n",
            "pecah baris >100 char icon.setImageResource (baris 493)",
        ),
        # 5u. preferedGameId baris 342 — val isCreateRoom -> Binary expr, break after '='
        (
            "            val preferedGameId: Long = if (isCreateRoom) {\n"
            "                val idx = gameNameList.indexOfFirst { it[0] == preferedGameName }\n"
            "                if (idx >= 0) gameIdList[idx][0] else 0L\n"
            "            } else 0L\n",
            "            val preferedGameId: Long =\n"
            "                if (isCreateRoom) {\n"
            "                    val idx = gameNameList.indexOfFirst { it[0] == preferedGameName }\n"
            "                    if (idx >= 0) gameIdList[idx][0] else 0L\n"
            "                } else {\n"
            "                    0L\n"
            "                }\n",
            "break after '=' binary expr preferedGameId & Missing { ... } else 0L (baris 342-345)",
        ),
        # 5v. NetPlayManager.setRoomAddress baris 404 >100 char
        (
            "                            if (!isCreateRoom) NetPlayManager.setRoomAddress(activity, ipAddress)\n",
            "                            if (!isCreateRoom) {\n"
            "                                NetPlayManager.setRoomAddress(activity, ipAddress)\n"
            "                            }\n",
            "Missing { ... } & pecah baris >100 char setRoomAddress (baris 404)",
        ),
    ], "NetPlayDialog.kt")

    print()
    print(f"Selesai. File diubah: {CHANGED}, dilewati: {SKIPPED}, hilang: {MISSING}")


if __name__ == "__main__":
    main()
