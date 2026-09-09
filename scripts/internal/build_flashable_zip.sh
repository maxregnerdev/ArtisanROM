#!/usr/bin/env bash
# Copyright (c) 2023 Salvo Giangreco
# SPDX-License-Identifier: GPL-3.0-or-later

# [
source "$SRC_DIR/scripts/utils/install_utils.sh" || exit 1

SOURCE_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$SOURCE_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$SOURCE_FIRMWARE")"
TARGET_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")"

SOURCE_FINGERPRINT="$(GET_PROP "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/build.prop" "ro.system.build.fingerprint")"
SOURCE_FINGERPRINT="${SOURCE_FINGERPRINT//$(GET_PROP "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/build.prop" "ro.build.product")/$(GET_PROP "$FW_DIR/$SOURCE_FIRMWARE_PATH/vendor/build.prop" "ro.product.vendor.device")}"
TARGET_FINGERPRINT="$(GET_PROP "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/build.prop" "ro.system.build.fingerprint")"
TARGET_FINGERPRINT="${TARGET_FINGERPRINT//$(GET_PROP "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/build.prop" "ro.build.product")/$(GET_PROP "$FW_DIR/$TARGET_FIRMWARE_PATH/vendor/build.prop" "ro.product.vendor.device")}"

TMP_DIR="$OUT_DIR/zip"

ROM_STATUS="UNOFFICIAL"
$ROM_IS_OFFICIAL && ROM_STATUS="OFFICIAL"

ZIP_FILE_SUFFIX="-sign.zip"
$DEBUG && ! $ROM_IS_OFFICIAL && ZIP_FILE_SUFFIX=".zip"

ZIP_FILE_NAME="ArtisanROM_${ROM_STATUS}_${ROM_VERSION}_$(date +%Y%m%d)_${TARGET_CODENAME}${ZIP_FILE_SUFFIX}"
while [ -f "$OUT_DIR/$ZIP_FILE_NAME" ]; do
    INCREMENTAL=$((INCREMENTAL + 1))
    ZIP_FILE_NAME="ArtisanROM_${ROM_VERSION}_$(date +%Y%m%d)-${INCREMENTAL}_${TARGET_CODENAME}${ZIP_FILE_SUFFIX}"
done

PRIVATE_KEY_PATH="$SRC_DIR/security/"
PUBLIC_KEY_PATH="$SRC_DIR/security/"
if $ROM_IS_OFFICIAL; then
    PRIVATE_KEY_PATH+="artisanrom_ota"
    PUBLIC_KEY_PATH+="artisanrom_ota"
else
    PRIVATE_KEY_PATH+="aosp_testkey"
    PUBLIC_KEY_PATH+="aosp_testkey"
fi
PRIVATE_KEY_PATH+=".pk8"
PUBLIC_KEY_PATH+=".x509.pem"

trap 'rm -rf "$TMP_DIR"' EXIT INT

# https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/build_super_image.py#72
BUILD_SUPER_EMPTY()
{
    local CMD

    CMD="lpmake"
    # https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/build_super_image.py#75
    CMD+=" --metadata-size \"65536\""
    # https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/core/config.mk#1033
    CMD+=" --super-name \"super\""
    # https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/build_super_image.py#85
    CMD+=" --metadata-slots \"2\""
    CMD+=" --device \"super:$TARGET_SUPER_PARTITION_SIZE\""
    CMD+=" --group \"$TARGET_SUPER_GROUP_NAME:$(GET_SUPER_GROUP_SIZE)\""
    if [ -f "$TMP_DIR/system.img" ]; then
        CMD+=" --partition \"system:readonly:$(GET_IMAGE_SIZE "$TMP_DIR/system.img"):$TARGET_SUPER_GROUP_NAME\""
    fi
    if [ -f "$TMP_DIR/vendor.img" ]; then
        CMD+=" --partition \"vendor:readonly:$(GET_IMAGE_SIZE "$TMP_DIR/vendor.img"):$TARGET_SUPER_GROUP_NAME\""
    fi
    if [ -f "$TMP_DIR/product.img" ]; then
        CMD+=" --partition \"product:readonly:$(GET_IMAGE_SIZE "$TMP_DIR/product.img"):$TARGET_SUPER_GROUP_NAME\""
    fi
    if [ -f "$TMP_DIR/system_ext.img" ]; then
        CMD+=" --partition \"system_ext:readonly:$(GET_IMAGE_SIZE "$TMP_DIR/system_ext.img"):$TARGET_SUPER_GROUP_NAME\""
    fi
    if [ -f "$TMP_DIR/odm.img" ]; then
        CMD+=" --partition \"odm:readonly:$(GET_IMAGE_SIZE "$TMP_DIR/odm.img"):$TARGET_SUPER_GROUP_NAME\""
    fi
    if [ -f "$TMP_DIR/vendor_dlkm.img" ]; then
        CMD+=" --partition \"vendor_dlkm:readonly:$(GET_IMAGE_SIZE "$TMP_DIR/vendor_dlkm.img"):$TARGET_SUPER_GROUP_NAME\""
    fi
    if [ -f "$TMP_DIR/odm_dlkm.img" ]; then
        CMD+=" --partition \"odm_dlkm:readonly:$(GET_IMAGE_SIZE "$TMP_DIR/odm_dlkm.img"):$TARGET_SUPER_GROUP_NAME\""
    fi
    if [ -f "$TMP_DIR/system_dlkm.img" ]; then
        CMD+=" --partition \"system_dlkm:readonly:$(GET_IMAGE_SIZE "$TMP_DIR/system_dlkm.img"):$TARGET_SUPER_GROUP_NAME\""
    fi
    CMD+=" --output \"$TMP_DIR/unsparse_super_empty.img\""

    EVAL "$CMD" || exit 1
}

GENERATE_BUILD_INFO()
{
    local BUILD_INFO_FILE="$TMP_DIR/build_info.txt"

    {
        echo -n "device="
        [ "$(GET_PROP "system" "ro.unica.device")" ] && GET_PROP "system" "ro.unica.device" || echo "$TARGET_CODENAME"
        [ "$TARGET_ASSERT_MODEL" ] && echo "model=${TARGET_ASSERT_MODEL//:/;}"
        echo "name=$TARGET_NAME"
        echo -n "codename="
        [ "$(GET_PROP "system" "ro.unica.codename")" ] && GET_PROP "system" "ro.unica.codename" || echo "$ROM_CODENAME"
        echo -n "version="
        [ "$(GET_PROP "system" "ro.unica.version")" ] && GET_PROP "system" "ro.unica.version" || echo "$ROM_VERSION"
        echo -n "timestamp="
        [ "$(GET_PROP "system" "ro.unica.timestamp")" ] && GET_PROP "system" "ro.unica.timestamp" || echo "$ROM_BUILD_TIMESTAMP"
        echo "os_version=$(GET_PROP "system" "ro.build.version.release")"
        echo "oneui_version=$(GET_PROP "system" "ro.build.version.oneui")"
        echo "build_incremental=$(GET_PROP "system" "ro.build.version.incremental")"
        echo "build_date=$(GET_PROP "system" "ro.build.date.utc")"
        echo "security_patch=$(GET_PROP "system" "ro.build.version.security_patch")"
        echo "source_fingerprint=$SOURCE_FINGERPRINT"
        echo "target_fingerprint=$TARGET_FINGERPRINT"
        echo "use_dynamic_partitions=$TARGET_USE_DYNAMIC_PARTITIONS"
        if $TARGET_USE_DYNAMIC_PARTITIONS; then
            echo "super_partition_size=$TARGET_SUPER_PARTITION_SIZE"
            echo "super_partition_group=$TARGET_SUPER_GROUP_NAME"
            echo "super_${TARGET_SUPER_GROUP_NAME}_group_size=$(GET_SUPER_GROUP_SIZE)"
        fi
    } > "$BUILD_INFO_FILE"
}

# https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/common.py#4042
GENERATE_OP_LIST()
{
    local OP_LIST_FILE="$TMP_DIR/dynamic_partitions_op_list"

    local HAS_SYSTEM=false
    local HAS_VENDOR=false
    local HAS_PRODUCT=false
    local HAS_SYSTEM_EXT=false
    local HAS_ODM=false
    local HAS_VENDOR_DLKM=false
    local HAS_ODM_DLKM=false
    local HAS_SYSTEM_DLKM=false

    [ -f "$TMP_DIR/system.img" ] && HAS_SYSTEM=true
    [ -f "$TMP_DIR/vendor.img" ] && HAS_VENDOR=true
    [ -f "$TMP_DIR/product.img" ] && HAS_PRODUCT=true
    [ -f "$TMP_DIR/system_ext.img" ] && HAS_SYSTEM_EXT=true
    [ -f "$TMP_DIR/odm.img" ] && HAS_ODM=true
    [ -f "$TMP_DIR/vendor_dlkm.img" ] && HAS_VENDOR_DLKM=true
    [ -f "$TMP_DIR/odm_dlkm.img" ] && HAS_ODM_DLKM=true
    [ -f "$TMP_DIR/system_dlkm.img" ] && HAS_SYSTEM_DLKM=true

    local PARTITION_SIZE=0
    local OCCUPIED_SPACE=0

    {
        echo "# Remove all existing dynamic partitions and groups before applying full OTA"
        echo "remove_all_groups"
        echo "# Add group $TARGET_SUPER_GROUP_NAME with maximum size $(GET_SUPER_GROUP_SIZE)"
        echo "add_group $TARGET_SUPER_GROUP_NAME $(GET_SUPER_GROUP_SIZE)"
        $HAS_SYSTEM && echo "# Add partition system to group $TARGET_SUPER_GROUP_NAME"
        $HAS_SYSTEM && echo "add system $TARGET_SUPER_GROUP_NAME"
        $HAS_VENDOR && echo "# Add partition vendor to group $TARGET_SUPER_GROUP_NAME"
        $HAS_VENDOR && echo "add vendor $TARGET_SUPER_GROUP_NAME"
        $HAS_PRODUCT && echo "# Add partition product to group $TARGET_SUPER_GROUP_NAME"
        $HAS_PRODUCT && echo "add product $TARGET_SUPER_GROUP_NAME"
        $HAS_SYSTEM_EXT && echo "# Add partition system_ext to group $TARGET_SUPER_GROUP_NAME"
        $HAS_SYSTEM_EXT && echo "add system_ext $TARGET_SUPER_GROUP_NAME"
        $HAS_ODM && echo "# Add partition odm to group $TARGET_SUPER_GROUP_NAME"
        $HAS_ODM && echo "add odm $TARGET_SUPER_GROUP_NAME"
        $HAS_VENDOR_DLKM && echo "# Add partition vendor_dlkm to group $TARGET_SUPER_GROUP_NAME"
        $HAS_VENDOR_DLKM && echo "add vendor_dlkm $TARGET_SUPER_GROUP_NAME"
        $HAS_ODM_DLKM && echo "# Add partition odm_dlkm to group $TARGET_SUPER_GROUP_NAME"
        $HAS_ODM_DLKM && echo "add odm_dlkm $TARGET_SUPER_GROUP_NAME"
        $HAS_SYSTEM_DLKM && echo "# Add partition system_dlkm to group $TARGET_SUPER_GROUP_NAME"
        $HAS_SYSTEM_DLKM && echo "add system_dlkm $TARGET_SUPER_GROUP_NAME"
        if $HAS_SYSTEM; then
            PARTITION_SIZE="$(GET_IMAGE_SIZE "$TMP_DIR/system.img")"
            echo "# Grow partition system from 0 to $PARTITION_SIZE"
            echo "resize system $PARTITION_SIZE"
            OCCUPIED_SPACE=$((OCCUPIED_SPACE + PARTITION_SIZE))
        fi
        if $HAS_VENDOR; then
            PARTITION_SIZE="$(GET_IMAGE_SIZE "$TMP_DIR/vendor.img")"
            echo "# Grow partition vendor from 0 to $PARTITION_SIZE"
            echo "resize vendor $PARTITION_SIZE"
            OCCUPIED_SPACE=$((OCCUPIED_SPACE + PARTITION_SIZE))
        fi
        if $HAS_PRODUCT; then
            PARTITION_SIZE="$(GET_IMAGE_SIZE "$TMP_DIR/product.img")"
            echo "# Grow partition product from 0 to $PARTITION_SIZE"
            echo "resize product $PARTITION_SIZE"
            OCCUPIED_SPACE=$((OCCUPIED_SPACE + PARTITION_SIZE))
        fi
        if $HAS_SYSTEM_EXT; then
            PARTITION_SIZE="$(GET_IMAGE_SIZE "$TMP_DIR/system_ext.img")"
            echo "# Grow partition system_ext from 0 to $PARTITION_SIZE"
            echo "resize system_ext $PARTITION_SIZE"
            OCCUPIED_SPACE=$((OCCUPIED_SPACE + PARTITION_SIZE))
        fi
        if $HAS_ODM; then
            PARTITION_SIZE="$(GET_IMAGE_SIZE "$TMP_DIR/odm.img")"
            echo "# Grow partition odm from 0 to $PARTITION_SIZE"
            echo "resize odm $PARTITION_SIZE"
            OCCUPIED_SPACE=$((OCCUPIED_SPACE + PARTITION_SIZE))
        fi
        if $HAS_VENDOR_DLKM; then
            PARTITION_SIZE="$(GET_IMAGE_SIZE "$TMP_DIR/vendor_dlkm.img")"
            echo "# Grow partition vendor_dlkm from 0 to $PARTITION_SIZE"
            echo "resize vendor_dlkm $PARTITION_SIZE"
            OCCUPIED_SPACE=$((OCCUPIED_SPACE + PARTITION_SIZE))
        fi
        if $HAS_ODM_DLKM; then
            PARTITION_SIZE="$(GET_IMAGE_SIZE "$TMP_DIR/odm_dlkm.img")"
            echo "# Grow partition odm_dlkm from 0 to $PARTITION_SIZE"
            echo "resize odm_dlkm $PARTITION_SIZE"
            OCCUPIED_SPACE=$((OCCUPIED_SPACE + PARTITION_SIZE))
        fi
        if $HAS_SYSTEM_DLKM; then
            PARTITION_SIZE="$(GET_IMAGE_SIZE "$TMP_DIR/system_dlkm.img")"
            echo "# Grow partition system_dlkm from 0 to $PARTITION_SIZE"
            echo "resize system_dlkm $PARTITION_SIZE"
            OCCUPIED_SPACE=$((OCCUPIED_SPACE + PARTITION_SIZE))
        fi
    } > "$OP_LIST_FILE"

    if [[ "$OCCUPIED_SPACE" -gt "$(GET_SUPER_GROUP_SIZE)" ]]; then
        LOGE "OS size ($OCCUPIED_SPACE) is bigger than the target group size ($(GET_SUPER_GROUP_SIZE))"
        exit 1
    fi
}

GENERATE_OTA_METADATA()
{
    local PROTO_FILE="$SRC_DIR/external/android-tools/vendor/build/tools/releasetools/ota_metadata.proto"

    local INCREMENTAL
    local RELEASE
    local SECURITY_PATCH_LEVEL
    local TIMESTAMP

    INCREMENTAL="$(GET_PROP "system" "ro.build.version.incremental")"
    RELEASE="$(GET_PROP "system" "ro.build.version.release")"
    SECURITY_PATCH_LEVEL="$(GET_PROP "system" "ro.build.version.security_patch")"
    TIMESTAMP="$(GET_PROP "system" "ro.build.date.utc")"

    mkdir -p "$TMP_DIR/META-INF/com/android"

    # https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/ota_utils.py#259
    if [ -f "$PROTO_FILE" ]; then
        local MESSAGE

        MESSAGE+="type: BLOCK"
        MESSAGE+=", precondition: {device: \\\"$TARGET_CODENAME\\\"}"
        MESSAGE+=", postcondition: {device: \\\"$TARGET_CODENAME\\\""
        MESSAGE+=", build: \\\"$SOURCE_FINGERPRINT\\\""
        MESSAGE+=", build_incremental: \\\"$INCREMENTAL\\\""
        MESSAGE+=", timestamp: $TIMESTAMP"
        MESSAGE+=", sdk_level: \\\"$RELEASE\\\""
        MESSAGE+=", security_patch_level: \\\"$SECURITY_PATCH_LEVEL\\\"}"

        EVAL "protoc --encode=build.tools.releasetools.OtaMetadata --proto_path=\"$(dirname "$PROTO_FILE")\" \"$PROTO_FILE\" <<< \"$MESSAGE\" > \"$TMP_DIR/META-INF/com/android/metadata.pb\"" || exit 1
    fi

    # https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/ota_utils.py#317
    {
        echo "ota-required-cache=0"
        echo "ota-type=BLOCK"
        echo "post-build=$SOURCE_FINGERPRINT"
        echo "post-build-incremental=$INCREMENTAL"
        echo "post-sdk-level=$RELEASE"
        echo "post-security-patch-level=$SECURITY_PATCH_LEVEL"
        echo "post-timestamp=$TIMESTAMP"
        echo "pre-device=$TARGET_CODENAME"
    } > "$TMP_DIR/META-INF/com/android/metadata"
}

GENERATE_UPDATER_SCRIPT()
{
    local SCRIPT_FILE="$TMP_DIR/META-INF/com/google/android/updater-script"
    local BROTLI_EXTENSION
    $DEBUG || BROTLI_EXTENSION=".br"

    local PARTITION_COUNT=0
    local HAS_UP_PARAM=false
    local HAS_LK3RD=false
    local HAS_BOOT=false
    local HAS_DTBO=false
    local HAS_INIT_BOOT=false
    local HAS_VENDOR_BOOT=false
    local HAS_SUPER_EMPTY=false

    [ -f "$TMP_DIR/up_param.bin" ] && HAS_UP_PARAM=true
    [ -f "$TMP_DIR/lk3rd.img" ] && HAS_LK3RD=true
    [ -f "$TMP_DIR/boot.img" ] && HAS_BOOT=true
    [ -f "$TMP_DIR/dtbo.img" ] && HAS_DTBO=true
    [ -f "$TMP_DIR/init_boot.img" ] && HAS_INIT_BOOT=true
    [ -f "$TMP_DIR/vendor_boot.img" ] && HAS_VENDOR_BOOT=true
    [ -f "$TMP_DIR/unsparse_super_empty.img" ] && HAS_SUPER_EMPTY=true
    for p in $PARTITIONS_LIST $CSC_PARTITIONS_LIST; do
        [ -f "$TMP_DIR/$p.new.dat${BROTLI_EXTENSION}" ] && [ "$p" != "system" ] && PARTITION_COUNT=$((PARTITION_COUNT + 1))
    done

    {
        if [ -n "$TARGET_ASSERT_MODEL" ]; then
            IFS=':' read -r -a TARGET_ASSERT_MODEL <<< "$TARGET_ASSERT_MODEL"
            for i in "${TARGET_ASSERT_MODEL[@]}"; do
                echo -n 'getprop("ro.boot.em.model") == "'
                echo -n "$i"
                echo -n '" || '
            done
            echo -n 'abort("E3004: This package is for \"'
            echo -n "$TARGET_CODENAME"
            echo    '\" devices; this is a \"" + getprop("ro.product.device") + "\".");'
        else
            echo -n 'getprop("ro.product.device") == "'
            echo -n "$TARGET_CODENAME"
            echo -n '" || abort("E3004: This package is for \"'
            echo -n "$TARGET_CODENAME"
            echo    '\" devices; this is a \"" + getprop("ro.product.device") + "\".");'
        fi

        if [ -f "$SRC_DIR/target/$TARGET_CODENAME/installer/assertions.edify" ]; then
            cat "$SRC_DIR/target/$TARGET_CODENAME/installer/assertions.edify"
        fi

        PRINT_HEADER

        if $TARGET_USE_DYNAMIC_PARTITIONS; then
            # https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/common.py#4007
            echo -e "\n# --- Start patching dynamic partitions ---\n\n"
            echo -e "# Update dynamic partition metadata\n"
            echo -n 'assert(update_dynamic_partitions(package_extract_file("dynamic_partitions_op_list")'
            if $HAS_SUPER_EMPTY; then
                # https://github.com/LineageOS/android_build/commit/98549f6893c3a93057e2d4cdd1015a93e9473b16
                # https://github.com/LineageOS/android_bootable_deprecated-ota/commit/e97be4333bd3824b8561c9637e9e6de28bc29da0
                echo -n ', package_extract_file("unsparse_super_empty.img")'
            fi
            echo    '));'
        fi
        for p in $PARTITIONS_LIST $CSC_PARTITIONS_LIST; do
            if [ ! -f "$TMP_DIR/$p.new.dat${BROTLI_EXTENSION}" ]; then
                continue
            fi
            $TARGET_USE_DYNAMIC_PARTITIONS && echo -e "\n# Patch partition $p\n"
            echo -n 'ui_print("Patching '
            echo -n "$p image unconditionally..."
            echo    '");'
            if [[ "$p" == "system" ]]; then
                echo -n 'show_progress(0.'
                echo -n "$(bc -l <<< "9 - $PARTITION_COUNT")"
                echo    '00000, 0);'
            else
                echo    'show_progress(0.100000, 0);'
            fi
            echo -n "block_image_update("
            GET_DEVICE_FROM_MOUNTPOINT "/$p"
            echo -n ', package_extract_file("'
            echo -n "$p.transfer.list"
            echo -n '"), "'
            echo -n "$p.new.dat${BROTLI_EXTENSION}"
            echo -n '", "'
            echo -n "$p.patch.dat"
            echo    '") ||'
            echo -n '  abort("'
            [[ "$p" == "system" ]] && echo -n "E1001" || echo -n "E2001"
            echo -n ": Failed to update $p image."
            echo    '");'
        done
        $TARGET_USE_DYNAMIC_PARTITIONS && echo -e "\n# --- End patching dynamic partitions ---\n"
        if $HAS_DTBO; then
            echo    'ui_print("Full Patching dtbo.img img...");'
            echo -n 'package_extract_file("dtbo.img", '
            GET_DEVICE_FROM_MOUNTPOINT "/dtbo"
            echo    ');'
        fi
        if $HAS_INIT_BOOT; then
            echo    'ui_print("Full Patching init_boot.img img...");'
            echo -n 'package_extract_file("init_boot.img", '
            GET_DEVICE_FROM_MOUNTPOINT "/init_boot"
            echo    ');'
        fi
        if $HAS_VENDOR_BOOT; then
            echo    'ui_print("Full Patching vendor_boot.img img...");'
            echo -n 'package_extract_file("vendor_boot.img", '
            GET_DEVICE_FROM_MOUNTPOINT "/vendor_boot"
            echo    ');'
        fi
        if $HAS_LK3RD; then
            cp -a "$SRC_DIR/prebuilts/extras/setup-boot.sh" "$TMP_DIR/setup-boot.sh"

            echo -e "\n"
            echo    'package_extract_file("boot.img", "/tmp/boot.img");'
            echo    'package_extract_file("lk3rd.img", "/tmp/lk3rd.img");'
            echo    'ui_print("Installing boot image...");'
            echo    'ui_print("Installing lk3rd image...");'
            echo    'ui_print("Note: During boot you may get a warning, This is absolutely normal");'
            echo    'package_extract_file("setup-boot.sh", "/tmp/setup-boot.sh");'
            echo    'set_metadata("/tmp/setup-boot.sh", "uid", 0, "gid", 0, "dmode", 0755, "fmode", 0755);'
            echo    'run_program("/tmp/setup-boot.sh");'
        fi
        if ! $HAS_LK3RD && $HAS_BOOT; then
            echo    'ui_print("Installing boot image...");'
            echo -n 'package_extract_file("boot.img", '
            GET_DEVICE_FROM_MOUNTPOINT "/boot"
            echo    ');'
        fi
        if $HAS_UP_PARAM; then
            echo    'ui_print("Installing up_param image...");'
            echo -n 'package_extract_file("up_param.bin", '
            GET_DEVICE_FROM_MOUNTPOINT "/up_param"
            echo    ');'
        fi

        if [ -f "$SRC_DIR/target/$TARGET_CODENAME/installer/install-end.edify" ]; then
            cat "$SRC_DIR/target/$TARGET_CODENAME/installer/install-end.edify"
        fi

        echo    'set_progress(1.000000);'
        echo    'ui_print("****************************************");'
        echo    'ui_print(" ");'
    } > "$SCRIPT_FILE"
}

GET_SUPER_GROUP_SIZE()
{
    local GROUP_NAME="$TARGET_SUPER_GROUP_NAME"
    GROUP_NAME="$(tr "[:lower:]" "[:upper:]" <<< "$TARGET_SUPER_GROUP_NAME")"

    local VAR="TARGET_${GROUP_NAME}_SIZE"

    _CHECK_NON_EMPTY_PARAM "$VAR" "${!VAR}" || exit 1

    echo "${!VAR}"
}

PRINT_HEADER()
{
    local ONEUI_VERSION
    local MAJOR
    local MINOR
    local PATCH

    ONEUI_VERSION="$(GET_PROP "system" "ro.build.version.oneui")"
    MAJOR=$(bc -l <<< "scale=0; $ONEUI_VERSION / 10000")
    MINOR=$(bc -l <<< "scale=0; $ONEUI_VERSION % 10000 / 100")
    PATCH=$(bc -l <<< "scale=0; $ONEUI_VERSION % 100")
    if [[ "$PATCH" != "0" ]]; then
        ONEUI_VERSION="$MAJOR.$MINOR.$PATCH"
    else
        ONEUI_VERSION="$MAJOR.$MINOR"
    fi

    echo    'ui_print(" ");'
    echo    'ui_print("****************************************************");'
    echo -n 'ui_print("'
    echo -n "Welcome to ArtisanROM $ROM_CODENAME $ROM_VERSION for $TARGET_NAME!"
    echo    '");'
    echo    'ui_print("ArtisanROM developed by Android Artisan @XDAforums");'
    echo    'ui_print("UN1CA build system coded by salvo_giangri @XDAforums");'
    echo    'ui_print("Special thanks to all ArtisanROM Maintainers, Contribuitors and Testers");'
    echo    'ui_print("****************************************************");'
    echo -n 'ui_print("'
    echo -n "One UI version: $ONEUI_VERSION"
    echo    '");'
    echo -n 'ui_print("'
    echo -n "Source: $SOURCE_FINGERPRINT"
    echo    '");'
    echo -n 'ui_print("'
    echo -n "Target: $TARGET_FINGERPRINT"
    echo    '");'
    echo    'ui_print("****************************************************");'
}

SIGN_IMAGE_WITH_AVB()
{
    local FILE="$1"

    # Skip signing lk3rd
    if [[ "$(basename "$FILE")" == "lk3rd.img" ]]; then
        LOG "- Skipping AVB signing for lk3rd"
        return 0
    fi

    if ! avbtool info_image --image "$FILE" &> /dev/null; then
        local PARTITION_NAME
        PARTITION_NAME="$(basename "$FILE")"
        PARTITION_NAME="${PARTITION_NAME//.img/}"

        local PARTITION_SIZE
        PARTITION_SIZE="TARGET_$(tr "[:lower:]" "[:upper:]" <<< "$PARTITION_NAME")_PARTITION_SIZE"
        _CHECK_NON_EMPTY_PARAM "$PARTITION_SIZE" "${!PARTITION_SIZE//none/}" || exit 1

        local CMD
        CMD+="avbtool add_hash_footer "
        CMD+="--image \"$FILE\" "
        CMD+="--partition_size \"${!PARTITION_SIZE}\" "
        CMD+="--partition_name \"$PARTITION_NAME\" "
        CMD+="--hash_algorithm \"sha256\" "
        CMD+="--algorithm \"SHA256_RSA4096\" "
        CMD+="--key \"$SRC_DIR/security/avb/testkey_rsa4096.pem\""

        LOG "- Signing image with AVB"
        EVAL "$CMD" || exit 1
    fi
}
# ]

[ -d "$TMP_DIR" ] && rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR/META-INF/com/google/android"
cp -a "$SRC_DIR/prebuilts/bootable/deprecated-ota/updater" "$TMP_DIR/META-INF/com/google/android/update-binary"

LOG_STEP_IN "- Building OS partitions"
while IFS= read -r f; do
    PARTITION=$(basename "$f")
    IS_VALID_PARTITION_NAME "$PARTITION" || continue

    if $TARGET_USE_DYNAMIC_PARTITIONS; then
        "$SRC_DIR/scripts/build_fs_image.sh" "$TARGET_OS_FILE_SYSTEM_TYPE" \
            -o "$TMP_DIR/$PARTITION.img" -m -S \
            "$WORK_DIR/$PARTITION" "$WORK_DIR/configs/file_context-$PARTITION" "$WORK_DIR/configs/fs_config-$PARTITION" || exit 1
    else
        _GET_PARTITION_SIZE "$PARTITION" > /dev/null || exit 1
        "$SRC_DIR/scripts/build_fs_image.sh" "$TARGET_OS_FILE_SYSTEM_TYPE" \
            -o "$TMP_DIR/$PARTITION.img" -m -S -s "$(_GET_PARTITION_SIZE "$PARTITION")" \
            "$WORK_DIR/$PARTITION" "$WORK_DIR/configs/file_context-$PARTITION" "$WORK_DIR/configs/fs_config-$PARTITION" || exit 1
    fi
done < <(find "$WORK_DIR" -maxdepth 1 -type d)
LOG_STEP_OUT

if $TARGET_USE_DYNAMIC_PARTITIONS; then
    LOG "- Building unsparse_super_empty.img"
    BUILD_SUPER_EMPTY

    LOG "- Generating dynamic_partitions_op_list"
    GENERATE_OP_LIST
fi

while IFS= read -r f; do
    PARTITION="$(basename "$f" | sed "s/.img//g")"
    IS_VALID_PARTITION_NAME "$PARTITION" || continue

    LOG "- Converting $PARTITION.img to $PARTITION.new.dat"
    EVAL "img2sdat -o \"$TMP_DIR\" -B \"$TMP_DIR/$PARTITION.map\" \"$f\"" || exit 1
    rm -f "$f" "$TMP_DIR/$PARTITION.map"

    if ! $DEBUG; then
        LOG "- Compressing $PARTITION.new.dat"
        # https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/common.py#3585
        EVAL "brotli --quality=6 --output=\"$TMP_DIR/$PARTITION.new.dat.br\" \"$TMP_DIR/$PARTITION.new.dat\"" || exit 1
        rm -f "$TMP_DIR/$PARTITION.new.dat"
    fi
done < <(find "$TMP_DIR" -maxdepth 1 -type f -name "*.img")

if [ -d "$WORK_DIR/kernel" ]; then
    while IFS= read -r f; do
        IMG="$(basename "$f")"

        LOG_STEP_IN "- Copying $IMG"

        cp -a "$WORK_DIR/kernel/$IMG" "$TMP_DIR/$IMG"

        if ! $TARGET_DISABLE_AVB_SIGNING; then
            SIGN_IMAGE_WITH_AVB "$TMP_DIR/$IMG"
        fi

        LOG_STEP_OUT
    done < <(find "$WORK_DIR/kernel" -maxdepth 1 -type f -name "*.img")
fi


if [ -f "$WORK_DIR/up_param.bin" ]; then
    LOG "- Copying up_param.bin"
    cp -a "$WORK_DIR/up_param.bin" "$TMP_DIR/up_param.bin"
fi

LOG "- Generating updater-script"
GENERATE_UPDATER_SCRIPT

LOG "- Generating build_info.txt"
GENERATE_BUILD_INFO

LOG "- Generating OTA metadata"
GENERATE_OTA_METADATA

if [ -d "$SRC_DIR/target/$TARGET_CODENAME/installer/root" ]; then
    LOG "- Copying target custom install files"
    EVAL "cp -a \"$SRC_DIR/target/$TARGET_CODENAME/installer/root/\"* \"$TMP_DIR\"" || exit 1
fi

if [ -f "$SRC_DIR/target/$TARGET_CODENAME/installer/customize.sh" ]; then
    LOG_STEP_IN "- Running target custom install script"
    (
    . "$SRC_DIR/target/$TARGET_CODENAME/installer/customize.sh"
    ) || exit 1
    LOG_STEP_OUT
fi

LOG "- Creating zip"
EVAL "rm -f \"$TMP_DIR/rom.zip\"" || exit 1
# https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/common.py#3601
# https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/common.py#3609
# https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/ota_utils.py#184
# https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/ota_utils.py#186
EVAL "cd \"$TMP_DIR\" && 7z a -tzip -mx=0 -mmt=$(nproc) $TMP_DIR/rom.zip -r *.patch.dat -ir!META-INF/com/android/* -i!*.new.dat.br" || exit 1
EVAL "cd \"$TMP_DIR\" && 7z a -tzip -mx=3 -mmt=$(nproc) $TMP_DIR/rom.zip -r * -xr!META-INF/com/android/* -x!*.new.dat.br -x!*.patch.dat -x!rom.zip" || exit 1

if ! $DEBUG || $ROM_IS_OFFICIAL; then
    LOG "- Signing zip"
    EVAL "signapk -w \"$PUBLIC_KEY_PATH\" \"$PRIVATE_KEY_PATH\" \"$TMP_DIR/rom.zip\" \"$OUT_DIR/$ZIP_FILE_NAME\"" || exit 1
    rm -f "$TMP_DIR/rom.zip"
else
    mv -f "$TMP_DIR/rom.zip" "$OUT_DIR/$ZIP_FILE_NAME"
fi

exit 0
