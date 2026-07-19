#!/bin/bash -ex

export NDK_CCACHE=$(which ccache)

if [ -z "${ANDROID_KEYSTORE_B64}" ]; then
    echo "::warning::ANDROID_KEYSTORE_B64 is empty, generating a temporary debug keystore instead"
    export ANDROID_KEYSTORE_FILE="${GITHUB_WORKSPACE}/ks.jks"
    export ANDROID_KEYSTORE_PASS="android"
    export ANDROID_KEY_PASS="android"
    keytool -genkeypair -v \
        -keystore "${ANDROID_KEYSTORE_FILE}" \
        -alias dlix69 \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -storepass "${ANDROID_KEYSTORE_PASS}" \
        -keypass "${ANDROID_KEY_PASS}" \
        -dname "CN=CI Debug, OU=CI, O=CI, L=CI, S=CI, C=ID"
    export ANDROID_KEYSTORE_B64=$(base64 -w0 "${ANDROID_KEYSTORE_FILE}")
fi

if [ ! -z "${ANDROID_KEYSTORE_B64}" ]; then
    export ANDROID_KEYSTORE_FILE="${GITHUB_WORKSPACE}/ks.jks"
    base64 --decode <<< "${ANDROID_KEYSTORE_B64}" > "${ANDROID_KEYSTORE_FILE}"

    cat >> src/android/local.properties <<EOF
ANDROID_KEYSTORE=${ANDROID_KEYSTORE_FILE}
ANDROID_KEYSTORE_PASSWORD=${ANDROID_KEYSTORE_PASS}
ANDROID_KEY_ALIAS=dlix69
ANDROID_KEY_PASSWORD=${ANDROID_KEY_PASS}
EOF
fi

cd src/android
chmod +x ./gradlew
./gradlew assembleRelease
./gradlew bundleRelease

ccache -s -v

if [ ! -z "${ANDROID_KEYSTORE_B64}" ]; then
    rm "${ANDROID_KEYSTORE_FILE}"
    sed -i '/^ANDROID_KEYSTORE/d;/^ANDROID_KEY_ALIAS/d;/^ANDROID_KEY_PASSWORD/d' "${GITHUB_WORKSPACE}/src/android/local.properties" || true
fi
