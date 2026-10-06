#!/usr/bin/env bash
set -Eeuo pipefail

############################################################
# Image Factory – ساخت ایمیج OpenStack 
############################################################

# === نمایش راهنما ===
show_help() {
    cat <<EOF
Usage: $0 [OPTIONS] [IMAGE_NAME] [VERSION] [DOWNLOAD_URL]

Options:
  -i, --interactive       حالت تعاملی: تمام پارامترها را به صورت سوال از کاربر می‌پرسد
  --local-file PATH       استفاده از فایل ایمیج محلی به جای دانلود (در این صورت DOWNLOAD_URL اختیاری است)
  --checksum-url URL      دانلود فایل checksum و تأیید ایمیج (فقط در حالت دانلود معتبر است)
  --os-distro DISTRO      توزیع عامل مهمان (مقدار property os_distro) [پیش‌فرض: خالی - تنظیم نمی‌شود]
  --no-upload             فقط ایمیج را ساخته و در Glance آپلود نکن
  --visibility {public|private|shared|community}  سطح دسترسی در Glance [پیش‌فرض: public]
  --keep-workdir          دایرکتوری کار را پاک نکن (برای دیباگ)
  -h, --help              نمایش این راهنما

Examples:
  # حالت تعاملی
  $0 -i

  # حالت غیرتعاملی با دانلود از URL
  $0 --checksum-url https://.../SHA256SUMS --os-distro debian --visibility private "Debian 12" "12" "https://..."

  # حالت غیرتعاملی با فایل محلی
  $0 --local-file /path/to/image.img --visibility public "Ubuntu 26.04" "26.04"
EOF
}

# === متغیرهای پیش‌فرض ===
INTERACTIVE=false
LOCAL_FILE=""
CHECKSUM_URL=""
OS_DISTRO=""
NO_UPLOAD=false
VISIBILITY="public"
KEEP_WORKDIR=false
IMAGE_NAME=""
IMAGE_VERSION=""
DOWNLOAD_URL=""

# === پردازش آرگومان‌ها ===
OPTS=$(getopt -o ih --long interactive,local-file:,checksum-url:,os-distro:,no-upload,visibility:,keep-workdir,help -n "$0" -- "$@")
eval set -- "$OPTS"

while true; do
    case "$1" in
        -i|--interactive) INTERACTIVE=true; shift ;;
        --local-file)   LOCAL_FILE="$2"; shift 2 ;;
        --checksum-url) CHECKSUM_URL="$2"; shift 2 ;;
        --os-distro)    OS_DISTRO="$2"; shift 2 ;;
        --no-upload)    NO_UPLOAD=true; shift ;;
        --visibility)   VISIBILITY="$2"; shift 2 ;;
        --keep-workdir) KEEP_WORKDIR=true; shift ;;
        -h|--help)      show_help; exit 0 ;;
        --) shift; break ;;
        *) echo "Invalid option"; exit 1 ;;
    esac
done

# === حالت تعاملی ===
if [[ "${INTERACTIVE}" == true ]]; then
    echo "======================================================"
    echo "        OpenStack Image Factory (Interactive Mode)"
    echo "======================================================"
    echo "Enter the required parameters (press Enter to use default values):"
    echo

    # 1. Image Name
    read -p "Image Name [Required]: " IMAGE_NAME
    while [[ -z "${IMAGE_NAME}" ]]; do
        echo "❌ Image Name is required."
        read -p "Image Name [Required]: " IMAGE_NAME
    done

    # 2. Version
    read -p "Version [Required]: " IMAGE_VERSION
    while [[ -z "${IMAGE_VERSION}" ]]; do
        echo "❌ Version is required."
        read -p "Version [Required]: " IMAGE_VERSION
    done

    # 3. Source Type: URL or Local File
    echo
    echo "Select source type:"
    echo "  1) Download from URL"
    echo "  2) Use local file"
    read -p "Choice (1/2) [1]: " SOURCE_CHOICE
    SOURCE_CHOICE="${SOURCE_CHOICE:-1}"

    if [[ "${SOURCE_CHOICE}" == "1" ]] || [[ "${SOURCE_CHOICE}" == "" ]]; then
        # URL
        read -p "Download URL [Required]: " DOWNLOAD_URL
        while [[ -z "${DOWNLOAD_URL}" ]]; do
            echo "❌ Download URL is required."
            read -p "Download URL [Required]: " DOWNLOAD_URL
        done
        LOCAL_FILE=""

        # Checksum (اختیاری)
        read -p "Checksum URL (optional, press Enter to skip): " CHECKSUM_URL
        CHECKSUM_URL="${CHECKSUM_URL:-}"
    else
        # Local File
        read -p "Local file path [Required]: " LOCAL_FILE
        while [[ -z "${LOCAL_FILE}" ]]; do
            echo "❌ Local file path is required."
            read -p "Local file path [Required]: " LOCAL_FILE
        done
        while [[ ! -f "${LOCAL_FILE}" ]]; do
            echo "❌ File not found: ${LOCAL_FILE}"
            read -p "Local file path [Required]: " LOCAL_FILE
        done
        DOWNLOAD_URL=""
        CHECKSUM_URL=""  # چکسام در حالت فایل محلی پشتیبانی نمی‌شود
        echo "ℹ️  Checksum verification is skipped when using local file."
    fi

    # 4. OS Distro (اختیاری)
    read -p "OS Distro (optional, press Enter to skip): " OS_DISTRO
    OS_DISTRO="${OS_DISTRO:-}"

    # 5. Upload to Glance?
    echo
    read -p "Upload image to Glance? (y/N): " UPLOAD_CHOICE
    if [[ "${UPLOAD_CHOICE}" =~ ^[Yy]$ ]]; then
        NO_UPLOAD=false

        # 6. Visibility
        echo
        echo "Select visibility:"
        echo "  1) public"
        echo "  2) private"
        echo "  3) shared"
        echo "  4) community"
        read -p "Choice (1-4) [1]: " VIS_CHOICE
        case "${VIS_CHOICE:-1}" in
            1|"") VISIBILITY="public" ;;
            2) VISIBILITY="private" ;;
            3) VISIBILITY="shared" ;;
            4) VISIBILITY="community" ;;
            *) echo "Invalid choice, using 'public'."; VISIBILITY="public" ;;
        esac
    else
        NO_UPLOAD=true
        VISIBILITY="public"
    fi

    # 7. Keep work directory?
    echo
    read -p "Keep work directory for debugging? (y/N): " KEEP_CHOICE
    if [[ "${KEEP_CHOICE}" =~ ^[Yy]$ ]]; then
        KEEP_WORKDIR=true
    else
        KEEP_WORKDIR=false
    fi

    # در حالت تعاملی، اگر --keep-workdir داده نشده باشد، سوالات انتهایی پرسیده می‌شود
    # ولی در اینجا خودکار انجام می‌شود

    echo
    echo "======================================================"
    echo "Summary of entered parameters:"
    echo "  Image Name   : ${IMAGE_NAME}"
    echo "  Version      : ${IMAGE_VERSION}"
    echo "  Source       : $([[ -n "${LOCAL_FILE}" ]] && echo "Local: ${LOCAL_FILE}" || echo "URL: ${DOWNLOAD_URL}")"
    echo "  Checksum URL : ${CHECKSUM_URL:-"<not set>"}"
    echo "  OS Distro    : ${OS_DISTRO:-"<not set>"}"
    echo "  Upload       : $([[ $NO_UPLOAD == true ]] && echo "No" || echo "Yes (${VISIBILITY})")"
    echo "  Keep WorkDir : ${KEEP_WORKDIR}"
    echo "======================================================"
    echo
    read -p "Proceed with these settings? (Y/n): " CONFIRM
    if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]] && [[ -n "${CONFIRM}" ]]; then
        echo "❌ Aborted by user."
        exit 1
    fi
else
    # === حالت غیرتعاملی ===
    # آرگومان‌های اجباری
    if [[ $# -lt 2 ]]; then
        echo "Error: missing required arguments (IMAGE_NAME and VERSION)."
        echo "Use -i for interactive mode."
        show_help
        exit 1
    fi

    # اگر --local-file داده نشده، DOWNLOAD_URL اجباری است
    if [[ -z "${LOCAL_FILE}" && $# -lt 3 ]]; then
        echo "Error: either --local-file or DOWNLOAD_URL must be provided."
        show_help
        exit 1
    fi

    IMAGE_NAME="$1"
    IMAGE_VERSION="$2"
    DOWNLOAD_URL="${3:-}"

    # اگر --local-file داده شده ولی DOWNLOAD_URL هم داده شده، هشدار می‌دهیم و از local-file استفاده می‌کنیم
    if [[ -n "${LOCAL_FILE}" && -n "${DOWNLOAD_URL}" ]]; then
        echo "Warning: both --local-file and DOWNLOAD_URL provided. Ignoring DOWNLOAD_URL and using local file."
        DOWNLOAD_URL=""
    fi
fi

# === تبدیل فاصله‌ها در نام ایمیج برای استفاده در مسیرها ===
IMAGE_NAME_SAFE="$(echo "${IMAGE_NAME}" | tr ' ' '_')"

# === سایر متغیرها ===
ARCH="x86_64"
WORK_ROOT="${PWD}/image-build"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
BUILD_ID="${IMAGE_NAME_SAFE}-${IMAGE_VERSION}-${TIMESTAMP}"
WORK_DIR="${WORK_ROOT}/${BUILD_ID}"
SOURCE_DIR="${WORK_DIR}/source"
BUILD_DIR="${WORK_DIR}/build"
LOG_DIR="${WORK_DIR}/logs"
LOG_FILE="${LOG_DIR}/build.log"

# === آماده‌سازی دایرکتوری‌ها ===
mkdir -p "${SOURCE_DIR}" "${BUILD_DIR}" "${LOG_DIR}"

# === لاگینگ ===
exec > >(tee -a "${LOG_FILE}") 2>&1

# === تله خطا ===
trap 'on_error' ERR

on_error() {
    echo "======================================================"
    echo "ERROR: Build failed at line $LINENO"
    echo "======================================================"
    echo "Work directory: ${WORK_DIR}"
    echo "Log: ${LOG_FILE}"
    echo "Check logs for details."
    exit 1
}

# === توابع کمکی ===
info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*"; }
error() { echo "ERROR: $*" >&2; exit 1; }
check_cmd() { command -v "$1" >/dev/null 2>&1 || error "Command '$1' not found"; }

# === بررسی ابزارها ===
for cmd in curl wget qemu-img virt-customize virt-sysprep virt-ls virt-cat sha256sum openstack; do
    check_cmd "$cmd"
done

# === نمایش سرآغاز ===
echo "
======================================================
        OpenStack Image Factory
======================================================
Image Name    : ${IMAGE_NAME}
Version       : ${IMAGE_VERSION}
Architecture  : ${ARCH}
Source        : $([[ -n "${LOCAL_FILE}" ]] && echo "Local file: ${LOCAL_FILE}" || echo "URL: ${DOWNLOAD_URL}")
Checksum URL  : ${CHECKSUM_URL:-"None"}
OS Distro     : ${OS_DISTRO:-"<not set>"}
Upload        : $([[ $NO_UPLOAD == true ]] && echo "No" || echo "Yes (${VISIBILITY})")
Build ID      : ${BUILD_ID}
Work Dir      : ${WORK_DIR}
======================================================
"

# === تعیین فایل منبع (دانلود یا کپی از محلی) ===
SOURCE_FILENAME="$(basename "${DOWNLOAD_URL%%\?*}" 2>/dev/null || echo "local-image.img")"
if [[ -n "${LOCAL_FILE}" ]]; then
    # استفاده از فایل محلی
    if [[ ! -f "${LOCAL_FILE}" ]]; then
        error "Local file not found: ${LOCAL_FILE}"
    fi
    SOURCE_PATH="${SOURCE_DIR}/$(basename "${LOCAL_FILE}")"
    info "Copying local file to work directory..."
    cp -p "${LOCAL_FILE}" "${SOURCE_PATH}"
else
    # دانلود از URL
    SOURCE_PATH="${SOURCE_DIR}/${SOURCE_FILENAME}"
    info "Downloading source image..."
    if [[ -f "${SOURCE_PATH}" ]]; then
        info "Source already exists: ${SOURCE_PATH}"
    else
        wget --progress=bar:force -O "${SOURCE_PATH}" "${DOWNLOAD_URL}"
    fi
fi

# === چکسام (فقط در حالت دانلود معتبر است، برای فایل محلی انجام نمی‌شود) ===
if [[ -z "${LOCAL_FILE}" && -n "${CHECKSUM_URL}" ]]; then
    info "Downloading checksum file..."
    CHECKSUM_FILE="${SOURCE_DIR}/checksums"
    wget -O "${CHECKSUM_FILE}" "${CHECKSUM_URL}"
    info "Verifying checksum..."
    (cd "${SOURCE_DIR}" && sha256sum -c --ignore-missing "$(basename "${CHECKSUM_FILE}")") || error "Checksum verification failed"
elif [[ -n "${LOCAL_FILE}" && -n "${CHECKSUM_URL}" ]]; then
    echo "Warning: checksum verification is skipped when using --local-file."
fi

# === تشخیص فرمت ===
info "Detecting image format..."
SOURCE_FORMAT=$(qemu-img info --output=json "${SOURCE_PATH}" | python3 -c 'import sys,json; print(json.load(sys.stdin)["format"])')
info "Detected format: ${SOURCE_FORMAT}"

# === تبدیل به RAW ===
RAW_FILENAME="${IMAGE_NAME_SAFE}-${IMAGE_VERSION}.raw"
RAW_PATH="${BUILD_DIR}/${RAW_FILENAME}"
SHA256_FILE="${BUILD_DIR}/${RAW_FILENAME}.sha256"

info "Converting to RAW..."
rm -f "${RAW_PATH}"
qemu-img convert -p -f "${SOURCE_FORMAT}" -O raw "${SOURCE_PATH}" "${RAW_PATH}"

# === نصب پکیج‌های مهمان ===
info "Installing required packages..."
virt-customize -a "${RAW_PATH}" --install qemu-guest-agent,cloud-init,openssh-server

# === پاکسازی cloud-init ===
virt-customize -a "${RAW_PATH}" --run-command 'cloud-init clean --logs --seed'

# === اجرای virt-sysprep ===
virt-sysprep -a "${RAW_PATH}" --operations machine-id,ssh-hostkeys,dhcp-client-state,bash-history,tmp-files

# === محاسبه SHA256 ===
sha256sum "${RAW_PATH}" | tee "${SHA256_FILE}"

# === آپلود در Glance (در صورت درخواست) ===
if [[ "${NO_UPLOAD}" == false ]]; then
    # نگاشت visibility به پرچم مناسب openstack
    case "${VISIBILITY}" in
        public)    VIS_FLAG="--public" ;;
        private)   VIS_FLAG="--private" ;;
        shared)    VIS_FLAG="--shared" ;;
        community) VIS_FLAG="--community" ;;
        *) error "Invalid visibility: ${VISIBILITY}. Allowed: public, private, shared, community." ;;
    esac

    # ساخت آرایه از پارامترهای دستور
    CMD_ARGS=(
        "image" "create" "${IMAGE_NAME}"
        "--file" "${RAW_PATH}"
        "--disk-format" "raw"
        "--container-format" "bare"
        "--property" "os_version=${IMAGE_VERSION}"
        "--property" "architecture=${ARCH}"
        "--property" "hw_disk_bus=virtio"
        "--property" "hw_qemu_guest_agent=yes"
        ${VIS_FLAG}
    )

    # اگر OS_DISTRO خالی نبود، آن را اضافه کن
    if [[ -n "${OS_DISTRO}" ]]; then
        CMD_ARGS+=("--property" "os_distro=${OS_DISTRO}")
    fi

    info "Uploading to Glance (visibility: ${VISIBILITY})${OS_DISTRO:+ with os_distro=${OS_DISTRO}}..."
    openstack "${CMD_ARGS[@]}"

    # بررسی وجود ایمیج
    openstack image show "${IMAGE_NAME}" >/dev/null || error "Image not found after upload"
    UPLOAD_SUCCESS=true
else
    UPLOAD_SUCCESS=false
fi

# === گزارش نهایی ===
echo
echo "======================================================"
if [[ "${NO_UPLOAD}" == false ]] && [[ "${UPLOAD_SUCCESS}" == true ]]; then
    echo "   ✅ IMAGE BUILD & UPLOAD: SUCCESSFUL"
elif [[ "${NO_UPLOAD}" == true ]]; then
    echo "   ✅ IMAGE BUILD SUCCESSFUL (upload skipped)"
else
    echo "   ❌ IMAGE BUILD FAILED (see logs)"
    exit 1
fi
echo "======================================================"
echo "Image Name    : ${IMAGE_NAME}"
echo "Version       : ${IMAGE_VERSION}"
echo "OS Distro     : ${OS_DISTRO:-"<not set>"}"
echo "RAW Image     : ${RAW_PATH}"
echo "SHA256        : $(cat "${SHA256_FILE}")"
echo "Work Dir      : ${WORK_DIR}"
echo "Log           : ${LOG_FILE}"
echo "======================================================"

# === سوالات تعاملی برای حذف فایل‌ها (فقط در صورت تعاملی بودن) ===
if [[ -t 0 ]] && [[ -t 1 ]]; then
    echo
    echo "------------------------------------------------------"
    echo "Cleanup Options"
    echo "------------------------------------------------------"

    # سوال ۱: حذف فایل منبع
    read -p "آیا فایل منبع (${SOURCE_PATH}) را حذف کنم؟ [y/N] " -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ -f "${SOURCE_PATH}" ]]; then
            rm -f "${SOURCE_PATH}"
            echo "✅ فایل منبع حذف شد."
        else
            echo "⚠️  فایل منبع وجود ندارد (قبلاً حذف شده یا پیدا نمی‌شود)."
        fi
    else
        echo "ℹ️  فایل منبع نگهداری شد."
    fi

    # سوال ۲: حذف فایل RAW
    read -p "آیا فایل RAW (${RAW_PATH}) را حذف کنم؟ [y/N] " -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ -f "${RAW_PATH}" ]]; then
            rm -f "${RAW_PATH}"
            rm -f "${SHA256_FILE}"  # حذف فایل SHA256 همراه با RAW
            echo "✅ فایل RAW و SHA256 حذف شدند."
        else
            echo "⚠️  فایل RAW وجود ندارد (قبلاً حذف شده یا پیدا نمی‌شود)."
        fi
    else
        echo "ℹ️  فایل RAW نگهداری شد."
    fi

    # اگر --keep-workdir فعال نبود، دایرکتوری‌های خالی را پاک کن
    if [[ "${KEEP_WORKDIR}" == false ]]; then
        # حذف دایرکتوری‌های خالی (source, build, logs) اگر خالی باشند
        rmdir "${SOURCE_DIR}" 2>/dev/null || true
        rmdir "${BUILD_DIR}" 2>/dev/null || true
        rmdir "${LOG_DIR}" 2>/dev/null || true
        # اگر کل WORK_DIR خالی شد، آن را هم حذف کن
        rmdir "${WORK_DIR}" 2>/dev/null || true
    fi
else
    # در حالت غیرتعاملی، پیام می‌دهیم که فایل‌ها نگهداری شدند
    echo
    echo "ℹ️  Non-interactive mode: source and RAW files are kept."
    echo "   Use --keep-workdir to preserve work directory."
fi

exit 0
