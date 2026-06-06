#!/bin/bash
# fix_zerotier_layout_dedup.sh — Fix duplicate ID di dialog_zerotier_native.xml

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR")"
LAYOUT="$PROJECT_ROOT/src/android/app/src/main/res/layout/dialog_zerotier_native.xml"

[ -f "$LAYOUT" ] || { echo "[ERROR] Layout tidak ditemukan: $LAYOUT"; exit 1; }

echo "[INFO] Tulis ulang dialog_zerotier_native.xml bersih..."

cat > "$LAYOUT" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="wrap_content">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:padding="16dp">

        <!-- Header -->
        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="ZeroTier"
            android:textAppearance="@style/TextAppearance.Material3.TitleLarge"
            android:layout_marginBottom="4dp" />

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="Tanpa aplikasi tambahan"
            android:textAppearance="@style/TextAppearance.Material3.BodySmall"
            android:textColor="?attr/colorOnSurfaceVariant"
            android:layout_marginBottom="16dp" />

        <!-- Status card -->
        <com.google.android.material.card.MaterialCardView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="12dp"
            app:cardElevation="0dp"
            app:strokeWidth="1dp"
            app:strokeColor="?attr/colorOutline"
            app:cardBackgroundColor="?attr/colorSurfaceVariant">
            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="vertical"
                android:padding="12dp">
                <TextView
                    android:id="@+id/statusText"
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    android:text="@string/zerotier_status_idle"
                    android:textAppearance="@style/TextAppearance.Material3.BodyMedium" />
                <LinearLayout
                    android:id="@+id/ipContainer"
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    android:orientation="horizontal"
                    android:layout_marginTop="6dp"
                    android:visibility="gone">
                    <TextView
                        android:layout_width="wrap_content"
                        android:layout_height="wrap_content"
                        android:text="IP: "
                        android:textAppearance="@style/TextAppearance.Material3.BodySmall" />
                    <TextView
                        android:id="@+id/assignedIp"
                        android:layout_width="wrap_content"
                        android:layout_height="wrap_content"
                        android:fontFamily="monospace"
                        android:textColor="?attr/colorPrimary"
                        android:textAppearance="@style/TextAppearance.Material3.BodyMedium" />
                </LinearLayout>
            </LinearLayout>
        </com.google.android.material.card.MaterialCardView>

        <!-- Progress -->
        <ProgressBar
            android:id="@+id/progressBar"
            style="@style/Widget.Material3.LinearProgressIndicator"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="12dp"
            android:visibility="gone" />

        <!-- Network ID -->
        <com.google.android.material.textfield.TextInputLayout
            android:id="@+id/networkIdLayout"
            style="@style/Widget.Material3.TextInputLayout.OutlinedBox"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginBottom="4dp"
            android:hint="@string/zerotier_network_id_hint"
            app:counterEnabled="true"
            app:counterMaxLength="16">
            <com.google.android.material.textfield.TextInputEditText
                android:id="@+id/networkId"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:inputType="textNoSuggestions"
                android:maxLength="16"
                android:fontFamily="monospace" />
        </com.google.android.material.textfield.TextInputLayout>

        <TextView
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="@string/zerotier_network_id_helper"
            android:textAppearance="@style/TextAppearance.Material3.BodySmall"
            android:textColor="?attr/colorOnSurfaceVariant"
            android:layout_marginStart="4dp"
            android:layout_marginBottom="16dp" />

        <!-- Hubungkan / Putuskan -->
        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="horizontal"
            android:layout_marginBottom="12dp">
            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnConnect"
                style="@style/Widget.Material3.Button"
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:layout_weight="1"
                android:layout_marginEnd="8dp"
                android:text="@string/zerotier_btn_connect" />
            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnDisconnect"
                style="@style/Widget.Material3.Button.OutlinedButton"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:text="@string/zerotier_btn_disconnect" />
        </LinearLayout>

        <!-- Tombol room — hanya tampil saat ZeroTier terhubung (READY) -->
        <LinearLayout
            android:id="@+id/roomButtonsGroup"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            android:visibility="gone">

            <com.google.android.material.divider.MaterialDivider
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="4dp"
                android:layout_marginBottom="8dp" />

            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnCreateRoom"
                style="@style/Widget.Material3.Button.TonalButton"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginBottom="8dp"
                android:text="@string/multiplayer_create_room" />

            <com.google.android.material.button.MaterialButton
                android:id="@+id/btnJoinRoom"
                style="@style/Widget.Material3.Button.OutlinedButton"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginBottom="8dp"
                android:text="@string/multiplayer_join_room" />

        </LinearLayout>

    </LinearLayout>
</ScrollView>
EOF

echo "[OK] dialog_zerotier_native.xml ditulis ulang bersih (tanpa duplicate ID)"
echo ""
echo "  git add ."
echo "  git commit -m \"fix: hapus duplicate ID btnCreateRoom/btnJoinRoom di layout ZeroTier\""
echo "  git push origin DevElderLost-patch-4"
echo ""
