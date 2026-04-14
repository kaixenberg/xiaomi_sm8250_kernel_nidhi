#!/usr/bin/env bash
# E404 Kernel Compile Script !
# Put a fucking credit if you use something from here !

NIDHIKERNEL_VERSION_STR='2.2-alpha'

# Set kernel source directory and base directory to place tools
KERNEL_DIR="$PWD"
cd ..
BASE_DIR="$PWD"
cd "$KERNEL_DIR"

set -eo pipefail
trap 'errorbuild' INT TERM ERR

AK3_DIR="$BASE_DIR/AnyKernel3"
[[ ! -d "$AK3_DIR" ]] && echo "!! Please Provide AnyKernel3 !!" && exit 1

# Parse command line arguments
TYPE="CI"
TC="Unknown-Clang"
TARGET=""
DEFCONFIG=""

case "$*" in
    *st*)
        git checkout main
        TYPE="STABLE" ;;
    *dev*) TYPE="DEV" ;;
    *sus*) 
        git checkout main-susfs
        TYPE="SUSFS" 
        ;;
esac

if [[ -d "$BASE_DIR/toolchains/lilium-clang" ]]; then
    export PATH="$BASE_DIR/toolchains/lilium-clang/bin:$PATH"
    TC="Lilium-Clang"
else
    echo "-- !! Please provide lilium-clang in toolchains folder !! --"
    exit 1
fi

# Device selection using arrays
    declare -A DEVICE_MAP=(
        ["munch"]="MUNCH:vendor/munch_defconfig"
        ["alioth"]="ALIOTH:vendor/alioth_defconfig"
        ["apollo"]="APOLLO:vendor/apollo_defconfig"
        ["pipa"]="PIPA:vendor/pipa_defconfig"
        ["lmi"]="LMI:vendor/lmi_defconfig"
        ["umi"]="UMI:vendor/umi_defconfig"
        ["cmi"]="CMI:vendor/cmi_defconfig"
        ["cas"]="CAS:vendor/cas_defconfig"
    )

for device in "${!DEVICE_MAP[@]}"; do
    if [[ "$*" == *"$device"* ]]; then
        IFS=':' read -r TARGET DEFCONFIG <<< "${DEVICE_MAP[$device]}"
        sed -i "/devicename=/c\devicename=${device}" "$AK3_DIR/anykernel.sh"
        break
    fi
done

[[ ! "$TARGET" ]] && echo "-- !! Please set build device target !! --" && exit 1

# Set kernel image paths
K_IMG="$KERNEL_DIR/out/arch/arm64/boot/Image"
K_DTBO="$KERNEL_DIR/out/arch/arm64/boot/dtbo.img"
K_DTB="$KERNEL_DIR/out/arch/arm64/boot/dtb"



# Build environment
export ARCH="arm64"
export SUBARCH="arm64"
export TZ="Asia/Jakarta"

# Clean previous builds
# rm -rf ../*NidhiKernel*.zip

# Function definitions

clearbuild() {
    if [[ "$1" == "all" ]]; then
        echo "-- Cleaning Out --"
        rm -rf out/*
    else
        rm -rf "$KERNEL_DIR/out/arch/arm64/boot"
    fi
}

zipbuild() {
    echo "-- Zipping Kernel --"
    cd "$AK3_DIR" || exit 1
    ZIP_NAME="NidhiKernel-${NIDHIKERNEL_VERSION_STR}-BPF-${TARGET}-$(date "+%y%m%d").zip"
    zip -r9 "$BASE_DIR/$ZIP_NAME" META-INF/ tools/ "${TARGET}"*-Image "${TARGET}"*-dtb "${TARGET}"*-dtbo.img anykernel.sh
    cd "$KERNEL_DIR" || exit 1
}

uploadbuild() {
    echo "-- Kernel Flashable Zip Ready at $BASE_DIR/$ZIP_NAME --"
}

setupbuild() {
    BUILD_FLAGS=(
        CC="ccache clang"
        CROSS_COMPILE="aarch64-linux-gnu-"
        CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"
        LLVM=1
        LLVM_IAS=1
        LD="ld.lld"
        AR="llvm-ar"
        NM="llvm-nm"
        OBJCOPY="llvm-objcopy"
        OBJDUMP="llvm-objdump"
        STRIP="llvm-strip"
    )
    
    # Export for defconfig (without ccache)
    export CC="clang"
    export CROSS_COMPILE="aarch64-linux-gnu-"
    export CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"
    export LLVM=1
    export LLVM_IAS=1
}

errorbuild() {
    echo "-- !! Kernel Build Error !! --"
    clearbuild
    exit 1
}

compilebuild() {    
    mkdir -p $KERNEL_DIR/out

    local make_flags=(-j"$(nproc)" O=out "${BUILD_FLAGS[@]}")
    
    echo "-- Compiling with Clang --"
    make "${make_flags[@]}" || errorbuild
}

makebuild() {
    echo "-- Compiling Kernel --"
    export CCACHE_DIR="$BASE_DIR/ccache/.ccache_$TC"

    compilebuild
    # Show ccache stats after build
    echo "======== CCache Stats =========="
    ccache -p | grep cache_dir
    ccache -s
    echo "================================"

    echo "-- Copying files to AnyKernel3 --"
    rm -f "$AK3_DIR/${TARGET}-Image"
    rm -f "$AK3_DIR/${TARGET}-dtbo.img"
    rm -f "$AK3_DIR/${TARGET}-dtb"
    cp "$K_IMG" "$AK3_DIR/${TARGET}-Image"
    cp "$K_DTBO" "$AK3_DIR/${TARGET}-dtbo.img"
    cp "$K_DTB" "$AK3_DIR/${TARGET}-dtb"
}

setupbuild

# Main menu
while true; do
    echo ""
    echo " Menu "
    echo " ╔════════════════════════════════════╗"
    echo " ║ 1. Export Defconfig                ║"
    echo " ║ 2. Start Build                     ║"
    echo " ║ 3. Repack Last Build               ║"
    echo " ║ f. Clean Out Directory             ║"
    echo " ║ fc. Clean Ccache                   ║"
    echo " ║ e. Exit                            ║"
    echo " ╚════════════════════════════════════╝"
    echo -n " Enter your choice : "
    read -r menu
    
    case "$menu" in
        1)
            make O=out "$DEFCONFIG"
            echo "-- Exported $DEFCONFIG to Out Dir --"
            
            # Config modifications for Mountify support
            scripts/config --file out/.config \
                -e CONFIG_OVERLAY_FS \
                -e CONFIG_TMPFS_XATTR 

            # Config modifications for ksu + susfs support
            scripts/config --file out/.config \
                -e CONFIG_KSU \
                -e CONFIG_KSU_TAMPER_SYSCALL_TABLE \
                -e CONFIG_KSU_SUSFS \
                -e CONFIG_KSU_SUSFS_SUS_MAP \
                -e CONFIG_KSU_SUSFS_SUS_MOUNT \
                -e CONFIG_KSU_SUSFS_TRY_UMOUNT 

            # Config modifications for baseband-guard support
            scripts/config --file out/.config \
                -e CONFIG_BBG \
                -e CONFIG_BBG_BLOCK_BOOT \
                -e CONFIG_BBG_BLOCK_RECOVERY 

            # Config modifications to DISBALE kernelpatch/next support
            # It is not ready yet on this tree, causes bootloop & beyond my scope of knowledge
            scripts/config --file out/.config \
                -d CONFIG_DEBUG_KERNEL \
                -d CONFIG_DEBUG_INFO \
                -d CONFIG_DEBUG_INFO_DWARF4 \
                -d CONFIG_KALLSYMS \
                -d CONFIG_KALLSYMS_ALL \

            # Config modifications to make BBR default
            scripts/config --file out/.config \
                -d CONFIG_DEFAULT_WESTWOOD \
                -e CONFIG_TCP_CONG_BBR \
                -e CONFIG_DEFAULT_BBR \

            # Config modifications for localversion
            scripts/config --file out/.config \
                -d CONFIG_LOCALVERSION_AUTO \
                --set-str CONFIG_LOCALVERSION "-Nidhi-${NIDHIKERNEL_VERSION_STR}"
            ;;
        2)
            TIME_START="$(date +"%s")"
            rm -f "$BASE_DIR/compile.log"
            clearbuild
            makebuild 2>&1 | tee -a "$BASE_DIR/compile.log"
            zipbuild
            uploadbuild
            TIME_END=$(("$(date +"%s")" - "$TIME_START"))
            echo "-- Build Success! Date: $(date +"%d %b %Y, %H:%M:%S"), Time: $(($TIME_END / 60))m $(($TIME_END % 60))s --"
            ;;
        3)
            zipbuild
            echo "-- Kernel Flashable Zip Ready at $BASE_DIR/$ZIP_NAME --"
            ;;
        f)
            clearbuild "all"
            ;;
        fc)
            rm -rf "$BASE_DIR/ccache"
            ;;
        e)
            exit 0
            ;;
        *)
            echo "-- !! Invalid option !! --"
            ;;
    esac
done