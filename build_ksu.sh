#!/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# --- 🎨 Palette ---
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# --- 🌐 Paths & Vars ---
AK3_REPO="https://github.com/omarsmehan1/AnyKernel3.git"
SRC_DIR="$(pwd)"
OUT_DIR="$SRC_DIR/out"
TC_DIR="$HOME/toolchains"
JOBS="$(nproc 2>/dev/null || echo 1)"

# Toolchain path (Clang 11.0.2)
CLANG_DIR="$TC_DIR/clang-11.0.2"
export PATH="$CLANG_DIR/bin:$PATH"

# --- ✨ البانر ---
display_target_banner() {
    local device_full_name=""
    case "$1" in
        a73xq) device_full_name="SAMSUNG GALAXY A73 5G";;
        *) device_full_name="UNKNOWN DEVICE";;
    esac

    echo -e "${CYAN}------------------------------------------------------------${NC}"
    echo -e "${PURPLE}   ____    _    _        _    __  ____   __"
    echo -e "  / ___|  / \\  | |      / \\   \\ \\/ /\\ \\ / /"
    echo -e " | |  _  / _ \\ | |     / _ \\   \\  /  \\ V / "
    echo -e " | |_| |/ ___ \\| |___ / ___ \\  /  \\   | |  "
    echo -e "  \\____/_/   \\_\\_____/_/   \\_\\/_/\\_\\  |_|  "
    echo -e "${NC}"
    echo -e "${CYAN}  🚀 NOVA KERNEL BUILD SYSTEM | VERSION 2.0${NC}"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    echo -e "${WHITE}  📱 DEVICE   :${NC} ${GREEN}$device_full_name${NC}"
    echo -e "${WHITE}  🆔 VARIANT  :${NC} ${YELLOW}$1${NC}"
    echo -e "${WHITE}  📅 DATE     :${NC} ${CYAN}$(date "+%Y-%m-%d %H:%M:%S")${NC}"
    echo -e "${WHITE}  🛠️ COMPILER :${NC} ${PURPLE}Clang 11.0.2${NC}"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    echo ""
}

# --- 📦 1. تثبيت الاعتمادات ---
install_deps() {
    local device="$1"
    display_target_banner "$device"

    echo -e "${BLUE}===> Updating package lists...${NC}"
    sudo apt update

    echo -e "${BLUE}===> Installing System Dependencies...${NC}"
    sudo apt install -y \
        git \
        curl \
        zip \
        wget \
        make \
        gcc \
        g++ \
        bc \
        libssl-dev \
        aria2 \
        tar \
        bison \
        flex \
        libelf-dev

    echo -e "${GREEN}✔ Dependencies installed.${NC}"
}

# --- 🛠️ 2. تحميل الأدوات (Clang 11.0.2 + AnyKernel3) ---
fetch_tools() {
    echo -e "${BLUE}===> Checking Toolchain...${NC}"
    if [[ ! -d "$CLANG_DIR/bin" ]]; then
        echo -e "${YELLOW}-> Toolchain not found, downloading Clang 11.0.2...${NC}"
        mkdir -p "$CLANG_DIR"
        aria2c -x16 -s16 -k1M \
            "https://android.googlesource.com/toolchain/llvm-project/+archive/b397f81060ce6d701042b782172ed13bee898b79.tar.gz" \
            -d "$TC_DIR" -o "clang-11.0.2.tar.gz"
        tar -xf "$TC_DIR/clang-11.0.2.tar.gz" -C "$CLANG_DIR" --strip-components=0 || true
        rm -f "$TC_DIR/clang-11.0.2.tar.gz"
        echo -e "${GREEN}✔ Clang 11.0.2 downloaded and extracted.${NC}"
    else
        echo -e "${GREEN}✔ Toolchain found (cache).${NC}"
    fi

    echo -e "${BLUE}===> Cloning AnyKernel3 (shallow clone)...${NC}"
    rm -rf "$TC_DIR/AnyKernel3"
    git clone --depth 1 "$AK3_REPO" "$TC_DIR/AnyKernel3"
    echo -e "${GREEN}✔ AnyKernel3 ready at $TC_DIR/AnyKernel3.${NC}"
}

# --- 🧬 3. إعداد KernelSU ---
setup_ksu() {
    echo -e "${BLUE}===> Integrating KernelSU & SUSFS...${NC}"

    # تأكد إننا على الفرع الرئيسي لدليل المصدر إن كان داخل git repo
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git switch main >/dev/null 2>&1 || git checkout main >/dev/null 2>&1 || true
    fi

    # ازالة مجلدات سابقة (إن وُجدت)
    rm -rf "$SRC_DIR/KernelSU" "$SRC_DIR/drivers/kernelsu" || true

    # تنفيذ سكربت الإعداد الرسمي (مأخوذ من KernelSU-Next)
    curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s v1.1.1
    echo -e "${GREEN}✔ KernelSU & SUSFS integrated (if setup succeeded).${NC}"
}

# --- 🏗️ 4. بناء النواة (مُقفل على a73xq) ---
build_kernel() {
    local device="${1:-a73xq}"

    # هذا السكربت يدعم جهاز واحد فقط: a73xq
    if [[ "$device" != "a73xq" ]]; then
        echo -e "${YELLOW}This build script supports only 'a73xq'. Requested: '$device'. Exiting.${NC}"
        exit 1
    fi

    display_target_banner "$device"

    echo -e "${PURPLE}===> Configuring GKI & Starting Build...${NC}"

    # --- كافة الـ Exports المطلوبة (ثابتة لجهاز a73xq) ---
    export ARCH=arm64
    export BRANCH="android11"
    export DEPMOD=depmod
    export KCFLAGS="${KCFLAGS:-} -D__ANDROID_COMMON_KERNEL__"
    export KMI_GENERATION=2
    export STOP_SHIP_TRACEPRINTK=1
    export IN_KERNEL_MODULES=1
    export DO_NOT_STRIP_MODULES=1
    export KMI_ENFORCED=0
    export TRIM_NONLISTED_KMI=0
    export KMI_SYMBOL_LIST_STRICT_MODE=0
    export KMI_SYMBOL_LIST_ADD_ONLY=1
    export ABI_DEFINITION=android/abi_gki_aarch64.xml
    export KMI_SYMBOL_LIST=android/abi_gki_aarch64

    # --- Force usage of Clang 11 tools ---
    export CC=clang
    export CXX=clang++
    export LD=ld.lld
    export AR=llvm-ar
    export NM=llvm-nm
    export STRIP=llvm-strip
    export OBJCOPY=llvm-objcopy
    export OBJDUMP=llvm-objdump
    export READELF=llvm-readelf
    export LLVM=1
    export LLVM_IAS=1

    # تأكد أن PATH يحتوي bin الخاص بالتول تشين
    export PATH="$CLANG_DIR/bin:$PATH"

    # DEFCONFIG ثابت لجهاز a73xq
    export DEFCONF="a73xq_defconfig"

    mkdir -p "$OUT_DIR"

    # منع مشكلة HDRINST عبر تحديد مسار تثبيت الهيدرز
    export INSTALL_HDR_PATH="$OUT_DIR/usr"

    START=$(date +%s)

    echo -e "${BLUE}--> Running make $DEFCONF${NC}"
    make -j"$JOBS" -C "$SRC_DIR" O="$OUT_DIR" "$DEFCONF"

    echo -e "${BLUE}--> Building kernel (make)...${NC}"
    make -j"$JOBS" -C "$SRC_DIR" O="$OUT_DIR"

    echo -e "\n${GREEN}✔ Build completed in $(( $(date +%s) - START )) seconds.${NC}"
}

# --- 🎁 5. التجميع النهائي ---
gen_anykernel() {
    echo -e "${BLUE}===> Preparing AnyKernel3 package...${NC}"

    AK3_DIR="$TC_DIR/RIO/work_ksu"
    rm -rf "$AK3_DIR"
    mkdir -p "$AK3_DIR"

    # انسخ ملفات AnyKernel3 الأساسية
    cp -af "$TC_DIR/AnyKernel3/"* "$AK3_DIR/"

    # نسخ ملفات النواة الناتجة
    if [[ -f "$OUT_DIR/arch/arm64/boot/Image" ]]; then
        cp "$OUT_DIR/arch/arm64/boot/Image" "$AK3_DIR/"
    else
        echo -e "${YELLOW}Warning: Image not found at $OUT_DIR/arch/arm64/boot/Image${NC}"
    fi

    if [[ -f "$OUT_DIR/arch/arm64/boot/dtbo.img" ]]; then
        cp "$OUT_DIR/arch/arm64/boot/dtbo.img" "$AK3_DIR/"
    fi

    # مثال نقل DTB إن وُجد
    if [[ -f "$OUT_DIR/arch/arm64/boot/dts/vendor/qcom/yupik.dtb" ]]; then
        mkdir -p "$AK3_DIR/dtb"
        cp "$OUT_DIR/arch/arm64/boot/dts/vendor/qcom/yupik.dtb" "$AK3_DIR/dtb/"
    fi

    echo -e "${GREEN}✔ Final package directory ready at: $AK3_DIR${NC}"
}

# --- 🚀 Main Control Logic ---
case "${1:-}" in
    deps) install_deps "a73xq" ;;
    tools) fetch_tools ;;
    ksu) setup_ksu ;;
    build) build_kernel "a73xq" ;;
    pack) gen_anykernel ;;
    *)
        echo "Usage: $0 {deps|tools|ksu|build|pack}"
        exit 1
        ;;
esac

exit 0
