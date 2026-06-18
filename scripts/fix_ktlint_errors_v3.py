#!/usr/bin/env python3
"""
fix_ktlint_errors_v3.py
Perbaikan sisa error ktlint setelah v1 + v2.

Jalankan dari root repo SETELAH v1 dan v2:
    python3 scripts/fix_ktlint_errors_v3.py
"""

import os, sys

REPO_CANDIDATES = [".", "AzaharTrigger-test"]
BASE_REL = "src/android/app/src/main/java/org/citra/citra_emu"
CHANGED = SKIPPED = MISSING = 0


def find_repo_root():
    for c in REPO_CANDIDATES:
        if os.path.isdir(os.path.join(c, BASE_REL)):
            return os.path.abspath(c)
    print(f"[FATAL] '{BASE_REL}' tidak ditemukan"); sys.exit(1)


def read(p): return open(p, encoding="utf-8").read()
def write(p, s): open(p, "w", encoding="utf-8").write(s)


def patch_file(path, replacements, label):
    global CHANGED, SKIPPED, MISSING
    if not os.path.isfile(path):
        print(f"[MISSING] {label}: {path}"); MISSING += 1; return
    content = read(path); orig = content; changed = False
    for old, new, desc in replacements:
        if old not in content:
            print(f"  {'[SKIP]' if new in content else '[WARN]'} {label}: '{desc}'")
            continue
        content = content.replace(old, new, 1); changed = True
        print(f"  [OK]   {label}: '{desc}'")
    if changed and content != orig:
        write(path, content); CHANGED += 1
    else:
        SKIPPED += 1


def main():
    root = find_repo_root()
    base = os.path.join(root, BASE_REL)
    print(f"Repo root: {root}\n")

    # =========================================================================
    # 1. utils/NetPlayManager.kt
    # =========================================================================
    path = os.path.join(base, "utils", "NetPlayManager.kt")
    patch_file(path, [
        # 1a. Pindahkan java.net.Inet4Address sebelum org.citra.* (j < o)
        (
            "import androidx.preference.PreferenceManager\n"
            "import org.citra.citra_emu.CitraApplication\n"
            "import org.citra.citra_emu.R\n"
            "import org.citra.citra_emu.dialogs.ChatMessage\n"
            "import java.net.Inet4Address\n",
            "import androidx.preference.PreferenceManager\n"
            "import java.net.Inet4Address\n"
            "import org.citra.citra_emu.CitraApplication\n"
            "import org.citra.citra_emu.R\n"
            "import org.citra.citra_emu.dialogs.ChatMessage\n",
            "pindahkan java.net.Inet4Address sebelum org.citra.* (lexicographic order)",
        ),
        # 1b. formatNetPlayStatus: function body -> body expression
        (
            "    private fun formatNetPlayStatus(context: Context, type: Int, msg: String): String {\n"
            "        return when (type) {\n",
            "    private fun formatNetPlayStatus(context: Context, type: Int, msg: String): String =\n"
            "        when (type) {\n",
            "formatNetPlayStatus: function body -> body expression",
        ),
        # 1c. Setelah body expression, kurung tutup when juga perlu disesuaikan
        # (tidak ada perubahan pada kurung, karena return dihapus dan when langsung jadi value)
        # 1c-extra. Hapus kurung tutup fungsi ekstra setelah body expression
        # (saat 'return when {...}' diubah jadi '= when {...}', satu '}' jadi orphan)
        (
            "            else -> \"\"\n"
            "        }\n"
            "    }\n"
            "\n"
            "    fun isConnectedToWifi",
            "            else -> \"\"\n"
            "        }\n"
            "\n"
            "    fun isConnectedToWifi",
            "hapus kurung tutup fungsi orphan setelah formatNetPlayStatus body expression",
        ),
        # 1d. Tambahkan blank line sebelum else -> "" di akhir when (baris 297)
        (
            "            NetPlayStatus.CHAT_MESSAGE -> msg\n"
            "            else -> \"\"\n",
            "            NetPlayStatus.CHAT_MESSAGE -> msg\n"
            "\n"
            "            else -> \"\"\n",
            "tambahkan blank line sebelum else -> \"\" di formatNetPlayStatus",
        ),
    ], "NetPlayManager.kt")

    # =========================================================================
    # 2. dialogs/NetPlayDialog.kt
    # =========================================================================
    path = os.path.join(base, "dialogs", "NetPlayDialog.kt")
    patch_file(path, [
        # 2a. Baris 50: when-branch pertama >100 char — pecah setelah '->'
        (
            "            NetPlayManager.netPlayIsJoined() -> DialogMultiplayerLobbyBinding.inflate(layoutInflater)\n"
            "                .apply {\n",
            "            NetPlayManager.netPlayIsJoined() ->\n"
            "                DialogMultiplayerLobbyBinding.inflate(layoutInflater).apply {\n",
            "pecah when-branch netPlayIsJoined() >100 char (baris 50)",
        ),
        # 2b. Baris 73: tambahkan blank line sebelum else ->
        (
            "                }\n"
            "            else -> {\n"
            "                DialogMultiplayerConnectBinding.inflate(layoutInflater).apply {\n",
            "                }\n"
            "\n"
            "            else -> {\n"
            "                DialogMultiplayerConnectBinding.inflate(layoutInflater).apply {\n",
            "tambahkan blank line sebelum else -> di when{} (baris 73)",
        ),
        # 2c. Baris 107-111: hapus trailing comma data class NetPlayItems
        # (v2 menambahkan trailing comma tapi ktlint justru komplain "Unnecessary trailing comma")
        (
            "    data class NetPlayItems(\n"
            "        val option: Int,\n"
            "        val name: String,\n"
            "        val type: Int,\n"
            "        val id: Int = 0,\n"
            "    ) {\n",
            "    data class NetPlayItems(\n"
            "        val option: Int,\n"
            "        val name: String,\n"
            "        val type: Int,\n"
            "        val id: Int = 0\n"
            "    ) {\n",
            "hapus trailing comma data class NetPlayItems (Unnecessary trailing comma)",
        ),
        # 2d. Baris 127: NetPlayViewHolder super type — View.OnClickListener harus baris baru
        (
            "        abstract inner class NetPlayViewHolder(itemView: View) :\n"
            "            RecyclerView.ViewHolder(itemView), View.OnClickListener {\n",
            "        abstract inner class NetPlayViewHolder(itemView: View) :\n"
            "            RecyclerView.ViewHolder(itemView),\n"
            "            View.OnClickListener {\n",
            "pisahkan View.OnClickListener ke baris baru (Super type should start on a newline, baris 127)",
        ),
        # 2e. Baris 222: NetPlayItems SEPARATOR masih >100 char — pecah argumen
        (
            "                netPlayItems.add(\n"
            "                    NetPlayItems(NetPlayItems.MULTIPLAYER_SEPARATOR, \"\", NetPlayItems.TYPE_SEPARATOR)\n"
            "                )\n",
            "                netPlayItems.add(\n"
            "                    NetPlayItems(\n"
            "                        NetPlayItems.MULTIPLAYER_SEPARATOR,\n"
            "                        \"\",\n"
            "                        NetPlayItems.TYPE_SEPARATOR\n"
            "                    )\n"
            "                )\n",
            "pecah argumen NetPlayItems SEPARATOR >100 char (baris 222)",
        ),
        # 2f. Baris 508: hapus trailing comma BanListAdapter
        # (v2 menambahkan trailing comma tapi ktlint komplain "Unnecessary trailing comma")
        (
            "    private class BanListAdapter(\n"
            "        banList: List<String>,\n"
            "        private val onUnban: (String) -> Unit,\n"
            "    ) : RecyclerView.Adapter<BanListAdapter.ViewHolder>() {\n",
            "    private class BanListAdapter(\n"
            "        banList: List<String>,\n"
            "        private val onUnban: (String) -> Unit\n"
            "    ) : RecyclerView.Adapter<BanListAdapter.ViewHolder>() {\n",
            "hapus trailing comma BanListAdapter (Unnecessary trailing comma, baris 508)",
        ),
    ], "NetPlayDialog.kt")

    print()
    print(f"Selesai. Diubah: {CHANGED}, dilewati: {SKIPPED}, hilang: {MISSING}")


if __name__ == "__main__":
    main()
