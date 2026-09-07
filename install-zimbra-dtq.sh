#!/usr/bin/env bash

set -Eeuo pipefail
# System installers and APT keyrings need world-readable configuration files.
# Files containing credentials are explicitly restricted to mode 600 below.
umask 022

# ============================================================
# Zimbra 10.1.20 FOSS Automated Installer
# OS    : Ubuntu 22.04
# Build : zcs-10.1.20_GA_0326.UBUNTU22_64.20260821115118
#
# Usage:
# bash install-zimbra.sh \
#   --domain example.com
# ============================================================

readonly ZCS_VERSION="10.1.20"
ZCS_ARCHIVE=""
DEFAULT_ZCS_URL=""
DEFAULT_ZCS_SHA256=""
OS_FAMILY=""
DRY_RUN=no
APPLY=no
LOCAL_IP=""
# Chi cai cac package trong allowlist: zimbra-dnscache=N, zimbra-imapd=N.
# DNS local dung dnsmasq; IMAP thong thuong van do mailbox/store phuc vu.
readonly ZCS_PACKAGES="zimbra-core zimbra-ldap zimbra-logger zimbra-mta zimbra-snmp zimbra-store zimbra-apache zimbra-spell zimbra-memcached zimbra-proxy"
readonly UFW_PUBLIC_TCP_PORTS="25 80 443 465 587 993 995"

ZCS_SOURCE="$DEFAULT_ZCS_URL"
ZCS_SHA256="$DEFAULT_ZCS_SHA256"
ZCS_TGZ=""

DOMAIN=""
SERVER_IP=""
ADMIN_PASS=""
MAIL_HOST="mail"
TIMEZONE="Asia/Ho_Chi_Minh"
CONFIGURE_FIREWALL="no"
SSH_PORT=""
FIREWALL_STATUS="not configured"
FIREWALL_ADMIN_ACCESS="not configured"
UFW_RULES="not configured"
SYSTEM_ACCOUNTS_CHANGED="no"

LOG_FILE="/root/zimbra-auto-install.log"
DOWNLOAD_DIR="/root/zimbra-downloads"
WORKDIR=""

usage() {
    cat <<EOF
Usage:
  sudo bash $0 --domain example.com [options]

Required:
  --domain DOMAIN           Mail domain; bo qua de nhap tu terminal

Automatic defaults:
  Public IPv4 is detected from the VPS when --ip is omitted.
  A strong admin password is generated when no password option is set.

Optional overrides:
  --ip IPV4                 Override the detected public IPv4 address
  --password PASSWORD       Override the generated Zimbra admin password
  --password-file FILE      Read the password from the first line of FILE
  ZIMBRA_ADMIN_PASSWORD     Environment variable password override

Optional:
  --dry-run                Chi hien thi OS, URL, hostname; khong thay doi he thong
  --apply                  Xac nhan cai moi tren VPS sach (co thay doi DNS/hostname)
  --local-ip IPV4           IP gan tren NIC, bat buoc neu --ip la public IP NAT
  --skip-firewall           Firewall duoc giu nguyen mac dinh
  --mail-host NAME          Hostname prefix (default: mail)
  --timezone ZONE           Timezone (default: Asia/Ho_Chi_Minh)
  --installer PATH_OR_URL   Local archive or download URL
  --sha256 HASH             Optional SHA-256 for the archive
  -h, --help                Show this help
EOF
}

# Timeline theo buoc thuc te; khong hien phan tram gia.
STEP_NUMBER=0
STEP_STARTED=0
CURRENT_STEP=""
log() {
    if [[ -n "$CURRENT_STEP" ]]; then
        printf '[%s] KET THUC BUOC %02d | %ss | %s\n' "$(date '+%T')" "$STEP_NUMBER" "$((SECONDS-STEP_STARTED))" "$CURRENT_STEP"
    fi
    STEP_NUMBER=$((STEP_NUMBER+1))
    STEP_STARTED=$SECONDS
    CURRENT_STEP="$*"
    printf '\n============================================================\n'
    printf '[%s] BUOC %02d | %s\n' "$(date '+%F %T')" "$STEP_NUMBER" "$CURRENT_STEP"
    printf 'Tong thoi gian: %ss | Log: %s\n' "$SECONDS" "$LOG_FILE"
    printf '============================================================\n'
}

# Giu nguyen stdout/stderr cua installer va bao con dang chay moi 15s.
# Heartbeat khong dong nghia dich vu da khoi dong thanh cong.
run_visible() (
    label="$1"
    shift
    started=$SECONDS
    monitor=""
    trap '[[ -z "$monitor" ]] || { kill "$monitor" 2>/dev/null || :; wait "$monitor" 2>/dev/null || :; }' EXIT
    (
        while sleep 15; do
            printf '[%s] DANG CHAY | %s | %ss - cho lenh hoan tat\n' "$(date '+%T')" "$label" "$((SECONDS-started))"
        done
    ) &
    monitor=$!
    rc=0
    "$@" || rc=$?
    printf '[%s] %s | %s | exit=%s | %ss\n' "$(date '+%T')" "$([[ "$rc" == 0 ]] && printf OK || printf LOI)" "$label" "$rc" "$((SECONDS-started))"
    exit "$rc"
)

summary_rule() {
    local character="${1:-=}"

    printf '%78s\n' '' | tr ' ' "$character"
}

summary_section() {
    echo
    printf '[ %s ]\n' "$1"
}

summary_field() {
    printf '  %-20s : %s\n' "$1" "$2"
}

print_install_summary() {
    summary_rule '='
    printf '%s\n' '                    ZIMBRA INSTALLATION COMPLETED'
    summary_rule '='

    summary_section "ADMIN LOGIN"
    summary_field "URL" "https://$FQDN:7071"
    summary_field "Username" "$ADMIN_EMAIL"
    summary_field "Password" "Luu rieng tai /root/ZIMBRA-ADMIN-PASSWORD.txt"

    summary_section "DKIM DNS RECORD"
    summary_field "Host / Name" "$DKIM_DNS_NAME"
    summary_field "Type" "TXT"
    summary_field "Value" "$DKIM_TXT_VALUE"

    summary_section "UFW ALLOWED PORTS"
    printf '%s\n' "$UFW_RULES" | sed 's/^/  /'

    summary_section "ZIMBRA SERVICE STATUS"
    printf '%s\n' "$STATUS" | sed 's/^/  /'

    echo
    summary_rule '='
    printf '%s\n' 'Keep this information secure: it contains the admin password.'
    summary_rule '='
}

parse_dkim_query() {
    local query_output="$1"
    local public_signature

    DKIM_SELECTOR=$(awk '
        /^DKIM Selector:$/ {
            getline
            print
            exit
        }
    ' <<< "$query_output")

    public_signature=$(awk '
        /^DKIM Public signature:$/ {
            capture = 1
            next
        }
        /^DKIM Identity:$/ {
            capture = 0
        }
        capture {
            print
        }
    ' <<< "$query_output")

    # Join the quoted DNS chunks into the single value expected by DNS UIs.
    DKIM_TXT_VALUE=$(printf '%s\n' "$public_signature" | \
        perl -0777 -ne 'my @parts = /"([^"]*)"/g; print join("", @parts);')

    [[ -n "$DKIM_SELECTOR" && "$DKIM_TXT_VALUE" == v=DKIM1\;* ]]
}

zimbra_account_exists() {
    local account="$1"

    su - zimbra -c \
        "/opt/zimbra/bin/zmprov -l ga '$account' zimbraAccountStatus" \
        >/dev/null 2>&1
}

zimbra_global_account_value() {
    local attribute="$1"

    su - zimbra -c \
        "/opt/zimbra/bin/zmprov -l gacf '$attribute'" 2>/dev/null | \
        awk -F ': ' -v attribute="$attribute" \
            '$1 == attribute { print $2; exit }'
}

ensure_zimbra_system_account() {
    local account="$1"
    local password="$2"
    local description="$3"
    local lifetime="${4:-}"
    local command

    if zimbra_account_exists "$account"; then
        echo "System account exists: $account"
        return
    fi

    command="/opt/zimbra/bin/zmprov -l ca '$account' '$password'"
    command+=" amavisBypassSpamChecks TRUE"
    command+=" zimbraAttachmentsIndexingEnabled FALSE"
    command+=" zimbraIsSystemAccount TRUE"
    command+=" zimbraIsSystemResource TRUE"
    command+=" zimbraHideInGal TRUE"
    command+=" zimbraMailQuota 0"
    [[ -z "$lifetime" ]] || \
        command+=" zimbraMailMessageLifetime '$lifetime'"
    command+=" description '$description'"

    su - zimbra -c "$command" || \
        die "Cannot create Zimbra system account: $account"

    zimbra_account_exists "$account" || \
        die "Zimbra system account verification failed: $account"

    SYSTEM_ACCOUNTS_CHANGED="yes"
    echo "Created system account: $account"
}

ensure_zimbra_system_accounts() {
    local current_spam
    local current_ham
    local current_quarantine

    log "Verify Zimbra system accounts"

    su - zimbra -c \
        "/opt/zimbra/bin/zmprov -l gd '$DOMAIN' zimbraDomainName" \
        >/dev/null 2>&1 || die "Zimbra domain was not created: $DOMAIN"

    zimbra_account_exists "$ADMIN_EMAIL" || \
        die "Zimbra admin account was not created: $ADMIN_EMAIL"

    ensure_zimbra_system_account \
        "$SPAM_ACCOUNT" "$SPAM_ACCOUNT_PASS" \
        "System account for spam training."
    ensure_zimbra_system_account \
        "$HAM_ACCOUNT" "$HAM_ACCOUNT_PASS" \
        "System account for non-spam training."
    ensure_zimbra_system_account \
        "$QUARANTINE_ACCOUNT" "$QUARANTINE_ACCOUNT_PASS" \
        "System account for antivirus quarantine." "30d"

    current_spam=$(zimbra_global_account_value zimbraSpamIsSpamAccount || true)
    current_ham=$(zimbra_global_account_value zimbraSpamIsNotSpamAccount || true)
    current_quarantine=$(zimbra_global_account_value zimbraAmavisQuarantineAccount || true)

    if [[ "$current_spam" != "$SPAM_ACCOUNT" || \
          "$current_ham" != "$HAM_ACCOUNT" || \
          "$current_quarantine" != "$QUARANTINE_ACCOUNT" ]]; then
        su - zimbra -c \
            "/opt/zimbra/bin/zmprov -l mcf \
            zimbraSpamIsSpamAccount '$SPAM_ACCOUNT' \
            zimbraSpamIsNotSpamAccount '$HAM_ACCOUNT' \
            zimbraAmavisQuarantineAccount '$QUARANTINE_ACCOUNT'" || \
            die "Cannot configure Zimbra spam and quarantine accounts"
        SYSTEM_ACCOUNTS_CHANGED="yes"
    fi

    [[ "$(zimbra_global_account_value zimbraSpamIsSpamAccount)" == \
        "$SPAM_ACCOUNT" ]] || die "Spam account configuration verification failed"
    [[ "$(zimbra_global_account_value zimbraSpamIsNotSpamAccount)" == \
        "$HAM_ACCOUNT" ]] || die "Ham account configuration verification failed"
    [[ "$(zimbra_global_account_value zimbraAmavisQuarantineAccount)" == \
        "$QUARANTINE_ACCOUNT" ]] || \
        die "Quarantine account configuration verification failed"

    if [[ "$SYSTEM_ACCOUNTS_CHANGED" == "yes" ]]; then
        echo "System account configuration repaired; restarting Zimbra services"
        su - zimbra -c 'zmcontrol restart' || \
            die "Zimbra restart failed after system account repair"
    else
        echo "Spam, ham and quarantine accounts are configured correctly."
    fi

    echo "Spam training    : $SPAM_ACCOUNT"
    echo "Ham training     : $HAM_ACCOUNT"
    echo "Virus quarantine : $QUARANTINE_ACCOUNT"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

require_value() {
    local option="$1"
    local count="$2"
    local value="${3:-}"

    (( count >= 2 )) || die "$option requires a value"
    [[ -n "$value" && "$value" != --* ]] || die "$option requires a value"
}

is_valid_ipv4() {
    local ip="$1"
    local octet
    local -a octets

    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r -a octets <<< "$ip"
    for octet in "${octets[@]}"; do
        (( 10#$octet <= 255 )) || return 1
    done
}

detect_ssh_port() {
    local candidate=""

    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        candidate=$(awk '{print $4}' <<< "$SSH_CONNECTION")
    elif [[ -n "${SSH_CLIENT:-}" ]]; then
        candidate=$(awk '{print $3}' <<< "$SSH_CLIENT")
    elif command -v sshd >/dev/null 2>&1; then
        candidate=$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2; exit}')
    fi

    [[ "$candidate" =~ ^[0-9]{1,5}$ ]] || candidate="22"
    (( 10#$candidate >= 1 && 10#$candidate <= 65535 )) || candidate="22"
    printf '%s' "$candidate"
}

detect_server_ipv4() {
    local candidate
    local endpoint

    for endpoint in \
        "https://api.ipify.org" \
        "https://ipv4.icanhazip.com" \
        "https://checkip.amazonaws.com"; do
        candidate=$(curl \
            --ipv4 \
            --fail \
            --silent \
            --connect-timeout 5 \
            --max-time 10 \
            "$endpoint" 2>/dev/null || true)
        candidate=${candidate//[[:space:]]/}

        if is_valid_ipv4 "$candidate" && [[ "$candidate" != 127.* ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    # Fallback for VPS providers that block public IP lookup services.
    candidate=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '
        {
            for (i = 1; i <= NF; i++) {
                if ($i == "src") {
                    print $(i + 1)
                    exit
                }
            }
        }
    ')

    if is_valid_ipv4 "$candidate" && [[ "$candidate" != 127.* ]]; then
        printf '%s' "$candidate"
        return 0
    fi

    return 1
}

is_valid_domain() {
    local domain="$1"
    local label
    local -a labels

    (( ${#domain} <= 253 )) || return 1
    [[ "$domain" == *.* && "$domain" != *..* ]] || return 1
    IFS='.' read -r -a labels <<< "$domain"
    for label in "${labels[@]}"; do
        (( ${#label} <= 63 )) || return 1
        [[ "$label" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] || return 1
    done
}

escape_config_value() {
    local value="$1"

    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    printf '%s' "$value"
}

installer_is_valid() {
    local archive="$1"

    # Checksum tuy chon; van kiem tra archive co doc duoc hay khong.
    if [[ -n "$ZCS_SHA256" ]]; then
        echo "${ZCS_SHA256}  ${archive}" | sha256sum --check --status || return 1
    else
        printf 'CANH BAO: Khong doi chieu SHA-256; chua xac minh tinh xac thuc bo cai.\n' >&2
    fi
    tar -tzf "$archive" >/dev/null
}

verify_installer() {
    local archive="$1"

    installer_is_valid "$archive" || \
        die "SHA-256 verification failed or archive is corrupt: $archive"
}

patch_zimbra_installer() {
    local utilfunc="$1/util/utilfunc.sh"
    local unsafe_condition='if [ $P7ZIPREQUIRED = "yes" ]; then'
    local safe_condition='if [ "${P7ZIPREQUIRED:-no}" = "yes" ]; then'
    local unsafe_count

    [[ -f "$utilfunc" ]] || \
        die "Bundled Zimbra utility is missing: $utilfunc"

    if grep -Fq "$safe_condition" "$utilfunc"; then
        echo "Bundled installer P7ZIP condition is already safe."
        return
    fi

    unsafe_count=$(grep -Fc "$unsafe_condition" "$utilfunc" || true)
    [[ "$unsafe_count" == "1" ]] || \
        die "Unexpected P7ZIP condition in bundled Zimbra installer"

    sed -i.zimbra-auto-backup \
        's/if \[ \$P7ZIPREQUIRED = "yes" \]; then/if [ "${P7ZIPREQUIRED:-no}" = "yes" ]; then/' \
        "$utilfunc"
    rm -f -- "${utilfunc}.zimbra-auto-backup"

    grep -Fq "$safe_condition" "$utilfunc" || \
        die "Cannot patch bundled Zimbra P7ZIP condition"
    bash -n "$utilfunc" || \
        die "Bundled Zimbra utility failed syntax validation after patching"

    echo "Patched bundled installer: initialized empty P7ZIPREQUIRED as no."
}

prepare_installer() {
    local download_tmp

    [[ ! "$ZCS_SOURCE" =~ ^http:// ]] || die "Installer URL must use HTTPS"

    if [[ "$ZCS_SOURCE" =~ ^https:// ]]; then
        mkdir -p "$DOWNLOAD_DIR"
        ZCS_TGZ="${DOWNLOAD_DIR}/${ZCS_ARCHIVE}"

        if [[ -f "$ZCS_TGZ" ]] && installer_is_valid "$ZCS_TGZ"; then
            log "Use verified cached Zimbra archive"
            return
        fi

        if [[ -e "$ZCS_TGZ" ]]; then
            mv -- "$ZCS_TGZ" "${ZCS_TGZ}.invalid.$(date +%s)"
        fi

        log "Download Zimbra ${ZCS_VERSION}"
        download_tmp=$(mktemp "${DOWNLOAD_DIR}/.${ZCS_ARCHIVE}.part.XXXXXX")
        if ! curl \
            --fail \
            --location \
            --proto '=https' \
            --retry 5 \
            --retry-all-errors \
            --connect-timeout 20 \
            --output "$download_tmp" \
            "$ZCS_SOURCE"; then
            rm -f -- "$download_tmp"
            die "Cannot download Zimbra archive: $ZCS_SOURCE"
        fi

        if ! installer_is_valid "$download_tmp"; then
            rm -f -- "$download_tmp"
            die "SHA-256 verification failed or downloaded archive is corrupt"
        fi
        mv -- "$download_tmp" "$ZCS_TGZ"
    else
        ZCS_TGZ="$ZCS_SOURCE"
        [[ -f "$ZCS_TGZ" ]] || die "Cannot find Zimbra archive: $ZCS_TGZ"
        verify_installer "$ZCS_TGZ"
    fi
}

check_zimbra_repository() {
    local repository_path
    local repository_url

    for repository_path in 87 1000 1010; do
        repository_url="https://repo.zimbra.com/apt/${repository_path}/dists/jammy/Release"
        curl \
            --fail \
            --location \
            --silent \
            --show-error \
            --connect-timeout 10 \
            --max-time 30 \
            --output /dev/null \
            "$repository_url" || \
            die "Cannot access the Zimbra APT repository: $repository_url"
    done
}

repair_zimbra_apt_keyring_permissions() {
    local keyring="/etc/apt/trusted.gpg.d/zimbra.gpg"

    [[ -f "$keyring" ]] || return 0

    chown root:root /etc/apt /etc/apt/trusted.gpg.d "$keyring"
    chmod 755 /etc/apt /etc/apt/trusted.gpg.d
    chmod 644 "$keyring"

    if ! su -s /bin/sh _apt -c "test -r '$keyring'"; then
        echo "APT keyring path permissions:"
        namei -l "$keyring" || true
        die "User _apt still cannot read the Zimbra keyring"
    fi
}

fetch_reference_epoch() {
    local date_header
    local endpoint
    local epoch
    local -a epochs=()

    for endpoint in \
        "https://archive.ubuntu.com/ubuntu/dists/jammy-security/InRelease" \
        "https://repo.zimbra.com/apt/1010/dists/jammy/Release" \
        "https://api.github.com"; do
        date_header=""

        if command -v curl >/dev/null 2>&1; then
            date_header=$(curl \
                --head \
                --location \
                --fail \
                --silent \
                --show-error \
                --connect-timeout 5 \
                --max-time 15 \
                "$endpoint" 2>/dev/null | \
                tr -d '\r' | \
                awk 'tolower($1) == "date:" {
                    $1 = ""
                    sub(/^ /, "")
                    value = $0
                } END {print value}')
        elif command -v wget >/dev/null 2>&1; then
            date_header=$(wget \
                --server-response \
                --spider \
                --timeout=15 \
                "$endpoint" 2>&1 | \
                tr -d '\r' | \
                awk 'tolower($1) == "date:" {
                    $1 = ""
                    sub(/^ /, "")
                    value = $0
                } END {print value}')
        fi

        if [[ -n "$date_header" ]]; then
            epoch=$(date -u --date="$date_header" +%s 2>/dev/null || true)
            [[ "$epoch" =~ ^[0-9]{10,}$ ]] && epochs+=("$epoch")
        fi
    done

    (( ${#epochs[@]} > 0 )) || return 1

    printf '%s\n' "${epochs[@]}" | sort -n | \
        awk '{values[NR] = $1} END {print values[int((NR + 1) / 2)]}'
}

synchronize_system_clock() {
    local attempt=1
    local clock_offset=0
    local clock_source="NTP"
    local local_epoch
    local ntp_synchronized="no"
    local reference_epoch=""

    [[ -f "/usr/share/zoneinfo/$TIMEZONE" ]] || die "Unknown timezone: $TIMEZONE"
    timedatectl set-timezone "$TIMEZONE"
    timedatectl set-local-rtc 0 2>/dev/null || true

    log "Configure timezone and synchronize system clock"

    timedatectl set-ntp true 2>/dev/null || true

    if command -v chronyc >/dev/null 2>&1; then
        systemctl enable --now chrony 2>/dev/null || true
        chronyc -a makestep 2>/dev/null || true
    elif systemctl cat systemd-timesyncd.service >/dev/null 2>&1; then
        systemctl enable --now systemd-timesyncd 2>/dev/null || true
        systemctl restart systemd-timesyncd 2>/dev/null || true
    fi

    while (( attempt <= 30 )); do
        ntp_synchronized=$(timedatectl show \
            --property=NTPSynchronized \
            --value 2>/dev/null || true)

        if [[ "$ntp_synchronized" == "yes" ]]; then
            break
        fi

        sleep 2
        (( attempt++ ))
    done

    reference_epoch=$(fetch_reference_epoch || true)

    if [[ "$reference_epoch" =~ ^[0-9]{10,}$ ]]; then
        local_epoch=$(date -u +%s)
        clock_offset=$(( reference_epoch - local_epoch ))

        if (( clock_offset < -60 || clock_offset > 60 )); then
            echo "WARNING: NTP clock differs from trusted HTTPS time by ${clock_offset} seconds."
            timedatectl set-ntp false 2>/dev/null || true
            date --utc --set="@${reference_epoch}" >/dev/null || \
                die "Cannot correct the VPS clock; ask the VPS provider to fix host time"
            hwclock --systohc --utc 2>/dev/null || true
            clock_source="HTTPS median correction"
            ntp_synchronized="temporarily disabled until Chrony starts"
        fi
    else
        clock_source="NTP (HTTPS validation unavailable)"
    fi

    echo "Timezone         : $TIMEZONE ($(date '+%:z'))"
    echo "Local time       : $(date '+%F %T %Z')"
    echo "UTC time         : $(date -u '+%F %T UTC')"
    echo "NTP synchronized : $ntp_synchronized"
    echo "Clock source     : $clock_source"
    echo "HTTPS offset     : ${clock_offset} seconds"

    if [[ "$ntp_synchronized" != "yes" ]]; then
        echo "WARNING: NTP has not confirmed synchronization; APT will perform the final clock validity check."
    fi
}

configure_ufw() {
    local port

    log "Configure UFW firewall"

    command -v ufw >/dev/null 2>&1 || die "UFW is not installed"

    if systemctl is-active --quiet firewalld 2>/dev/null; then
        die "firewalld is active; disable it before configuring UFW"
    fi

    SSH_PORT=$(detect_ssh_port)

    echo "Existing UFW status:"
    ufw status verbose || true
    echo

    # Add access rules before enabling or changing the default incoming policy.
    ufw allow "${SSH_PORT}/tcp"
    ufw allow 7071/tcp
    FIREWALL_ADMIN_ACCESS="7071/tcp from any IPv4/IPv6"
    SSH_PORT="${SSH_PORT}/tcp from any IPv4/IPv6"

    for port in $UFW_PUBLIC_TCP_PORTS; do
        ufw allow "${port}/tcp"
    done

    ufw default deny incoming
    ufw default allow outgoing
    ufw logging low
    ufw --force enable
    systemctl enable --now ufw

    FIREWALL_STATUS=$(ufw status | awk 'NR == 1 {print tolower($2)}')
    [[ "$FIREWALL_STATUS" == "active" ]] || die "UFW did not become active"

    echo
    echo "Final UFW rules:"
    UFW_RULES=$(ufw status numbered)
    printf '%s\n' "$UFW_RULES"
}

cleanup() {
    local exit_code=$?

    if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
        rm -rf -- "$WORKDIR"
    fi

    if (( exit_code != 0 )); then
        echo "Installation failed (exit $exit_code). Review: $LOG_FILE" >&2
    fi
}

trap cleanup EXIT

# ------------------------------------------------------------
# Arguments
# ------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in

        --dry-run) DRY_RUN=yes; shift ;;
        --apply) APPLY=yes; shift ;;
        --local-ip)
            require_value "$1" "$#" "${2:-}"
            LOCAL_IP="$2"; shift 2 ;;
        --domain)
            require_value "$1" "$#" "${2:-}"
            DOMAIN="$2"
            shift 2
            ;;

        --ip)
            require_value "$1" "$#" "${2:-}"
            SERVER_IP="$2"
            shift 2
            ;;

        --password)
            require_value "$1" "$#" "${2:-}"
            ADMIN_PASS="$2"
            shift 2
            ;;

        --password-file)
            require_value "$1" "$#" "${2:-}"
            [[ -r "$2" ]] || die "Cannot read password file: $2"
            IFS= read -r ADMIN_PASS < "$2" || true
            [[ -n "$ADMIN_PASS" ]] || die "Password file is empty: $2"
            shift 2
            ;;

        --mail-host)
            require_value "$1" "$#" "${2:-}"
            MAIL_HOST="$2"
            shift 2
            ;;

        --installer)
            require_value "$1" "$#" "${2:-}"
            ZCS_SOURCE="$2"
            shift 2
            ;;

        --sha256)
            require_value "$1" "$#" "${2:-}"
            ZCS_SHA256="${2,,}"
            shift 2
            ;;

        --timezone)
            require_value "$1" "$#" "${2:-}"
            TIMEZONE="$2"
            shift 2
            ;;

        --skip-firewall)
            CONFIGURE_FIREWALL="no"
            shift
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        *)
            die "Unknown option: $1"
            ;;
    esac
done

ADMIN_PASS="${ADMIN_PASS:-${ZIMBRA_ADMIN_PASSWORD:-}}"

# Hoi domain khi chay bash truc tiep; khong nhan input tu pipe.
if [[ -z "$DOMAIN" ]]; then
    [[ -t 0 ]] || die "Khong co terminal; hay truyen --domain DOMAIN"
    while true; do
        read -r -p "Nhap ten mien mail (vi du example.com, khong nhap https://): " DOMAIN || die "Da huy nhap"
        if is_valid_domain "$DOMAIN"; then
            break
        fi
        printf 'Ten mien khong hop le. Vui long nhap lai.\n'
    done
fi
is_valid_domain "$DOMAIN" || die "Invalid domain: $DOMAIN"
[[ -z "$SERVER_IP" ]] || is_valid_ipv4 "$SERVER_IP" || die "Invalid IPv4: $SERVER_IP"
[[ "$MAIL_HOST" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || \
    die "Invalid mail host: $MAIL_HOST"
[[ "$TIMEZONE" =~ ^[a-zA-Z0-9_+-]+(/[a-zA-Z0-9_+-]+)+$ ]] || \
    die "Invalid timezone: $TIMEZONE"
[[ -z "$ZCS_SHA256" || "$ZCS_SHA256" =~ ^[a-f0-9]{64}$ ]] || die "Invalid SHA-256 value"
[[ "$ADMIN_PASS" != *$'\n'* && "$ADMIN_PASS" != *$'\r'* ]] || \
    die "Admin password must be a single line"

# Mat khau duoc truyen qua su/zmprov trong upstream: chan ky tu pha shell quoting.
[[ "$ADMIN_PASS" != *"'"* && "$ADMIN_PASS" != *'`'* && "$ADMIN_PASS" != *'$'* && "$ADMIN_PASS" != *'\'* ]] || die "Mat khau chua ky tu khong an toan voi flow upstream; dung mat khau tu sinh"
FQDN="${MAIL_HOST}.${DOMAIN}"
ADMIN_EMAIL="admin@${DOMAIN}"

# Nhan dien phien ban chinh xac; khong suy doan URL tu version gan nhat.
detect_os() {
    local id="$1" version="$2"
    case "$id:$version" in
        ubuntu:22.04) OS_FAMILY=ubuntu; ZCS_BUILD=0326.UBUNTU22_64.20260821115118; DEFAULT_ZCS_URL="https://tool.dotrungquan.info/zimbra/source/14BB4E4A_zcs-10.1.20_GA_0326.UBUNTU22_64.20260821115118.tgz" ;;
        ubuntu:24.04) OS_FAMILY=ubuntu; ZCS_BUILD=0326.UBUNTU24_64.20260821120929; DEFAULT_ZCS_URL="https://tool.dotrungquan.info/zimbra/source/AD1FDAC3_zcs-10.1.20_GA_0326.UBUNTU24_64.20260821120929.tgz" ;;
        almalinux:8.10|rocky:8.10|rhel:8.10) OS_FAMILY=rhel; ZCS_BUILD=0326.RHEL8_64.20260821135029; DEFAULT_ZCS_URL="https://tool.dotrungquan.info/zimbra/source/90B8466A_zcs-10.1.20_GA_0326.RHEL8_64.20260821135029.tgz" ;;
        almalinux:9.8|rocky:9.8|rhel:9.8) OS_FAMILY=rhel; ZCS_BUILD=0326.RHEL9_64.20260821135258; DEFAULT_ZCS_URL="https://tool.dotrungquan.info/zimbra/source/3165857B_zcs-10.1.20_GA_0326.RHEL9_64.20260821135258.tgz" ;;
        *) die "OS khong trong danh sach: $id $version" ;;
    esac
    ZCS_ARCHIVE="zcs-${ZCS_VERSION}_GA_${ZCS_BUILD}.tgz"
    ZCS_SOURCE="${ZCS_SOURCE:-$DEFAULT_ZCS_URL}"
}
source /etc/os-release
detect_os "$ID" "$VERSION_ID"
[[ "$(uname -m)" == x86_64 ]] || die "Chi ho tro x86_64"
[[ -z "$LOCAL_IP" ]] || is_valid_ipv4 "$LOCAL_IP" || die "local-ip khong hop le"
if [[ "$DRY_RUN" == yes ]]; then
    printf 'OS=%s %s\nURL=%s\nHOSTNAME=%s\nMX=%s -> %s\nDNS=127.0.0.1 (dnsmasq)\n' "$ID" "$VERSION_ID" "$ZCS_SOURCE" "$FQDN" "$DOMAIN" "$FQDN"
    exit 0
fi
# Xac nhan truoc moi thay doi he thong; khong bat nhap checksum.
if [[ -t 0 ]]; then
    printf '\nOS: %s %s\nDomain: %s\nHostname: %s\nBo cai: %s\n' "$ID" "$VERSION_ID" "$DOMAIN" "$FQDN" "$ZCS_SOURCE"
    if [[ "$APPLY" != yes ]]; then
        printf '\nCANH BAO: cai package, doi hostname va DNS. Chi dung VPS sach, khong co panel.\n'
        printf 'Co the gian doan dich vu; hay snapshot/backup truoc. Hoan tac day du bang snapshot.\n'
        while true; do
            read -r -p "Bat dau cai dat? [y/N]: " CONFIRM_INSTALL || die "Da huy"
            case "$CONFIRM_INSTALL" in
                y|Y) APPLY=yes; break ;;
                n|N|"") die "Da huy, chua thay doi he thong" ;;
                *) printf 'Vui long nhap Y hoac N.\n' ;;
            esac
        done
    fi
fi
[[ "$APPLY" == yes ]] || die "Dung --dry-run de xem, --apply de xac nhan cai moi"
[[ ! -e /opt/zimbra ]] || die "/opt/zimbra da ton tai; khong cai de"
# Khong tu dong go dich vu dang phuc vu production.
for svc in postfix exim4 nginx apache2 httpd named dnsmasq; do
    if systemctl is-active --quiet "$svc"; then
        die "Dich vu $svc dang chay; can VPS sach hoac xu ly thu cong"
    fi
done
# ------------------------------------------------------------
# Root
# ------------------------------------------------------------

[[ "$EUID" -eq 0 ]] || die "Run script as root"

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# Capture output only after the root check, so non-root users get a clear error.
exec > >(tee -a "$LOG_FILE") 2>&1

# ------------------------------------------------------------
# OS validation
# ------------------------------------------------------------

# OS va existing installation da duoc kiem tra truoc khi thay doi.
# ------------------------------------------------------------
# Hardware check
# ------------------------------------------------------------

log "Hardware checks"

RAM_MB=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
DISK_GB=$(df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')

if [[ "$RAM_MB" -lt 7000 ]]; then
    die "Minimum approximately 8 GB RAM required. Current: ${RAM_MB} MB"
fi

echo "RAM: ${RAM_MB} MB"
echo "Free disk: ${DISK_GB} GB"

if [[ "$DISK_GB" -lt 20 ]]; then
    die "At least 20 GB free disk space is required. Current: ${DISK_GB} GB"
fi

# ------------------------------------------------------------
# Packages
# ------------------------------------------------------------

log "Install OS dependencies"

if [[ "$OS_FAMILY" == ubuntu ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates chrony curl dnsutils dnsmasq gnupg iproute2 net-tools netcat-openbsd openssl pax perl rsyslog sqlite3 sysstat tar unzip
    CHRONY_SERVICE=chrony
else
    # Dependency con lai do installer Zimbra kiem tra; khong tu bat repo la.
    dnf install -y ca-certificates chrony curl bind-utils dnsmasq iproute net-tools nmap-ncat openssl perl rsyslog sqlite sysstat tar unzip libaio libstdc++ libnsl
    CHRONY_SERVICE=chronyd
    if command -v getenforce >/dev/null && [[ "$(getenforce)" == Enforcing ]]; then
        die "SELinux Enforcing: can review chinh sach/huong dan Zimbra truoc; script khong tu tat SELinux"
    fi
fi
systemctl enable --now "$CHRONY_SERVICE" rsyslog
timedatectl set-timezone "$TIMEZONE"
chronyc -a makestep

# Detect values only after curl and OpenSSL are guaranteed to be installed.
if [[ -z "$SERVER_IP" ]]; then
    log "Detect public IPv4"
    SERVER_IP=$(detect_server_ipv4) || \
        die "Cannot detect the VPS IPv4 address; rerun with --ip IPV4"
    echo "Detected IPv4: $SERVER_IP"
fi

if [[ -z "$ADMIN_PASS" ]]; then
    ADMIN_PASS=$(openssl rand -hex 16)
fi

[[ "$ADMIN_PASS" != *$'\n'* && "$ADMIN_PASS" != *$'\r'* ]] || \
    die "Admin password must be a single line"

# Fail early with a clear URL if the external packages required by proxy are
# not reachable. The bundled installer otherwise hides this detail in a log.
# Repo checks do installer cho tung OS thuc hien.

# Download and validate the complete installer before changing host services.
prepare_installer

# DNS split horizon phai tro IP thuc tren NIC, khong dung public NAT IP.
LOCAL_IP="${LOCAL_IP:-$SERVER_IP}"
ip -o -4 addr show | awk '{split($4,a,"/"); print a[1]}' | grep -Fxq "$LOCAL_IP" || die "IP $LOCAL_IP khong tren NIC; dung --local-ip"
BACKUP_DIR="/root/zimbra-preinstall-$(date +%Y%m%d_%H%M%S)"
install -d -m 700 "$BACKUP_DIR"
cp -a /etc/hosts /etc/resolv.conf "$BACKUP_DIR/"
cp -L /etc/resolv.conf "$BACKUP_DIR/resolv.conf.content"
hostname > "$BACKUP_DIR/hostname.before"
log "Configuration"

echo "Domain     : $DOMAIN"
echo "Hostname   : $FQDN"
echo "IP         : $SERVER_IP"
echo "Admin      : $ADMIN_EMAIL"
echo "Installer  : $ZCS_TGZ"

# ------------------------------------------------------------
# Hostname
# ------------------------------------------------------------

log "Cau hinh hostname va DNS local"
hostnamectl set-hostname "$FQDN"
HOSTS_TMP=$(mktemp)
awk -v fqdn="$FQDN" -v short="$MAIL_HOST" '
    { drop=0; for(i=2;i<=NF;i++) if($i==fqdn || $i==short) drop=1; if(!drop) print }
' /etc/hosts > "$HOSTS_TMP"
printf '%s %s %s\n' "$LOCAL_IP" "$FQDN" "$MAIL_HOST" >> "$HOSTS_TMP"
install -m 644 "$HOSTS_TMP" /etc/hosts
# Cau hinh rieng, chi bind loopback, tranh open resolver va vong lap DNS.
DNS_CONFIG=/etc/zimbra-local-dns.conf
[[ ! -e "$DNS_CONFIG" ]] || die "$DNS_CONFIG da ton tai"
cat > "$DNS_CONFIG" <<EOF
listen-address=127.0.0.1
bind-interfaces
no-resolv
no-hosts
server=1.1.1.1
server=8.8.8.8
host-record=$FQDN,$LOCAL_IP
mx-host=$DOMAIN,$FQDN,10
mx-host=$FQDN,$FQDN,10
cache-size=1000
EOF
# Dung service dnsmasq voi config rieng, tranh drop-in khac mo port 53 public.
install -d -m 755 /etc/systemd/system/dnsmasq.service.d
cat > /etc/systemd/system/dnsmasq.service.d/zimbra.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/sbin/dnsmasq --keep-in-foreground --conf-file=$DNS_CONFIG
EOF
dnsmasq --test --conf-file="$DNS_CONFIG"
systemctl daemon-reload
systemctl enable --now dnsmasq
[[ "$(dig @127.0.0.1 +short A "$FQDN")" == "$LOCAL_IP" ]] || die "DNS local A loi"
# NetworkManager khong ghi de resolver; khong restart network/SSH.
if systemctl is-active --quiet NetworkManager; then
    install -d -m 755 /etc/NetworkManager/conf.d
    [[ ! -e /etc/NetworkManager/conf.d/90-zimbra-dns.conf ]] || die "NM DNS config da ton tai"
    printf '[main]\ndns=none\n' > /etc/NetworkManager/conf.d/90-zimbra-dns.conf
    nmcli general reload
fi
# Bao toan symlink goc trong backup, khong dung chattr +i.
mv /etc/resolv.conf "$BACKUP_DIR/resolv.conf.original"
printf 'search %s\nnameserver 127.0.0.1\n' "$DOMAIN" > /etc/resolv.conf
chmod 644 /etc/resolv.conf
[[ "$(hostname -f)" == "$FQDN" ]] || die "hostname sai"
[[ "$(dig +short A "$FQDN")" == "$LOCAL_IP" ]] || die "Resolver he thong sai"
dig +short MX "$DOMAIN" | grep -Fq "10 $FQDN." || die "MX local sai"
dig +short A repo.zimbra.com | grep -q . || die "DNS upstream khong hoat dong"
echo "DNS local OK; public MX/PTR/SPF/DKIM van can truoc khi dua mail vao production."

# ------------------------------------------------------------
# Check ports
# ------------------------------------------------------------

log "Port pre-check"

PORT_CONFLICTS=$(
    ss -lntp |
    grep -E ':(25|80|443|465|587|7071)[[:space:]]' || true
)

if [[ -n "$PORT_CONFLICTS" ]]; then
    echo "$PORT_CONFLICTS"
    die "Required Zimbra ports are already occupied"
fi

# ------------------------------------------------------------
# Extract installer
# ------------------------------------------------------------

log "Extract Zimbra"

WORKDIR=$(mktemp -d /root/zimbra-auto.XXXXXX)

tar xzf "$ZCS_TGZ" -C "$WORKDIR"

ZCS_DIR=$(
    find "$WORKDIR" \
        -maxdepth 1 \
        -type d \
        -name 'zcs-*' \
        -print \
        -quit
)

[[ -n "$ZCS_DIR" ]] || die "Cannot locate extracted Zimbra installer"

echo "Zimbra directory: $ZCS_DIR"

log "Patch bundled Zimbra installer"
# Chi patch khi dung condition cu; build khac khong ep patch.
if grep -Fq 'if [ $P7ZIPREQUIRED = "yes" ]; then' "$ZCS_DIR/util/utilfunc.sh"; then
    patch_zimbra_installer "$ZCS_DIR"
fi

# ------------------------------------------------------------
# Software-only installer configuration
#
# Passing a defaults file is deterministic and avoids relying on the order of
# interactive prompts, which can change with repository/package availability.
# ------------------------------------------------------------

log "Create software installer configuration"
printf "Package selection: zimbra-dnscache=N | zimbra-imapd=N\n"

SOFTWARE_CONFIG_FILE="/root/zimbra-software-install.conf"

cat > "$SOFTWARE_CONFIG_FILE" <<EOF
INSTALL_PACKAGES="$ZCS_PACKAGES"
USE_ZIMBRA_PACKAGE_SERVER="yes"
PACKAGE_SERVER="repo.zimbra.com"
EOF

chmod 600 "$SOFTWARE_CONFIG_FILE"

# ------------------------------------------------------------
# Software-only installation
# ------------------------------------------------------------

log "Install Zimbra software"

cd "$ZCS_DIR"

if ! run_visible "Cai package Zimbra" ./install.sh -s "$SOFTWARE_CONFIG_FILE"; then
    echo
    echo "Zimbra installer diagnostics (last 120 log lines):"
    if [[ -r /tmp/install.log ]]; then
        tail -n 120 /tmp/install.log
    else
        echo "Installer log is unavailable: /tmp/install.log"
    fi
    die "Zimbra software installation failed"
fi

# ------------------------------------------------------------
# Check software install
# ------------------------------------------------------------

[[ -x /opt/zimbra/libexec/zmsetup.pl ]] || \
    die "Zimbra package installation failed; zmsetup.pl missing"

# ------------------------------------------------------------
# Generate passwords
# ------------------------------------------------------------

LDAP_ROOT_PASS=$(openssl rand -hex 20)
LDAP_ADMIN_PASS=$(openssl rand -hex 20)
LDAP_AMAVIS_PASS=$(openssl rand -hex 20)
LDAP_POSTFIX_PASS=$(openssl rand -hex 20)
LDAP_NGINX_PASS=$(openssl rand -hex 20)
LDAP_REP_PASS=$(openssl rand -hex 20)
SYSTEM_ACCOUNT_SUFFIX=$(openssl rand -hex 5)
SPAM_ACCOUNT="spam.${SYSTEM_ACCOUNT_SUFFIX}@${DOMAIN}"
HAM_ACCOUNT="ham.${SYSTEM_ACCOUNT_SUFFIX}@${DOMAIN}"
QUARANTINE_ACCOUNT="virus-quarantine.${SYSTEM_ACCOUNT_SUFFIX}@${DOMAIN}"
SPAM_ACCOUNT_PASS=$(openssl rand -hex 16)
HAM_ACCOUNT_PASS=$(openssl rand -hex 16)
QUARANTINE_ACCOUNT_PASS=$(openssl rand -hex 16)

# ------------------------------------------------------------
# Zimbra configuration
# ------------------------------------------------------------

log "Generate Zimbra setup configuration"

CONFIG_FILE="/root/zimbra-setup.conf"
CONFIG_ADMIN_PASS=$(escape_config_value "$ADMIN_PASS")

cat > "$CONFIG_FILE" <<EOF
AVDOMAIN="$DOMAIN"
AVUSER="$ADMIN_EMAIL"

CREATEADMIN="$ADMIN_EMAIL"
CREATEADMINPASS="$CONFIG_ADMIN_PASS"

CREATEDOMAIN="$DOMAIN"

DOCREATEADMIN="yes"
DOCREATEDOMAIN="yes"

DOTRAINSA="yes"
EXPANDMENU="no"

HOSTNAME="$FQDN"

HTTPPORT="8080"
HTTPPROXY="TRUE"
HTTPPROXYPORT="80"

HTTPSPORT="8443"
HTTPSPROXYPORT="443"

IMAPPORT="7143"
IMAPPROXYPORT="143"

IMAPSSLPORT="7993"
IMAPSSLPROXYPORT="993"

POPPORT="7110"
POPPROXYPORT="110"

POPSSLPORT="7995"
POPSSLPROXYPORT="995"

INSTALL_WEBAPPS="service zimlet zimbra zimbraAdmin"

LDAPAMAVISPASS="$LDAP_AMAVIS_PASS"
LDAPPOSTPASS="$LDAP_POSTFIX_PASS"
LDAPROOTPASS="$LDAP_ROOT_PASS"
LDAPADMINPASS="$LDAP_ADMIN_PASS"
LDAPREPPASS="$LDAP_REP_PASS"

LDAPBESSEARCHSET="set"

LDAPHOST="$FQDN"
LDAPPORT="389"
LDAPREPLICATIONTYPE="master"

MAILPROXY="TRUE"

MODE="https"
PROXYMODE="https"

MYSQLMEMORYPERCENT="30"

REMOVE="no"

RUNARCHIVING="no"
RUNAV="yes"
RUNDKIM="yes"
RUNSA="yes"

SERVICEWEBAPP="yes"

SMTPDEST="$ADMIN_EMAIL"
SMTPHOST="$FQDN"
SMTPNOTIFY="yes"
SMTPSOURCE="$ADMIN_EMAIL"

SNMPNOTIFY="yes"
SNMPTRAPHOST="$FQDN"

SPELLURL="http://${FQDN}:7780/aspell.php"

STARTSERVERS="yes"

TRAINSAHAM="$HAM_ACCOUNT"
TRAINSASPAM="$SPAM_ACCOUNT"
VIRUSQUARANTINE="$QUARANTINE_ACCOUNT"

USESPELL="yes"

ZIMBRA_REQ_SECURITY="yes"

ldap_bes_searcher_password="$LDAP_ADMIN_PASS"
ldap_nginx_password="$LDAP_NGINX_PASS"

mailboxd_keystore_password="$CONFIG_ADMIN_PASS"
mailboxd_truststore_password="changeit"

zimbraIPMode="ipv4"

zimbraPrefTimeZoneId="$TIMEZONE"

zimbraReverseProxyLookupTarget="TRUE"

INSTALL_PACKAGES="$ZCS_PACKAGES"
EOF

chmod 600 "$CONFIG_FILE"

# ------------------------------------------------------------
# Setup Zimbra
# ------------------------------------------------------------

log "Configure Zimbra"

run_visible "Cau hinh Zimbra / LDAP / mailbox" /opt/zimbra/libexec/zmsetup.pl -c "$CONFIG_FILE"

# Some Zimbra builds fall back to HOSTNAME for these three accounts even when
# AVDOMAIN is set. Verify them against the primary mail domain and repair the
# configuration before reporting a successful installation.
ensure_zimbra_system_accounts

# ------------------------------------------------------------
# Verification
# ------------------------------------------------------------

log "Verify installation"

VERSION=$(
    su - zimbra -c 'zmcontrol -v' 2>&1
)

STATUS=$(
    su - zimbra -c 'zmcontrol status' 2>&1
)

echo "$VERSION"
echo
echo "$STATUS"

if grep -qiE 'Stopped|not running' <<< "$STATUS"; then
    echo
    echo "WARNING: At least one Zimbra service is not running."
fi

# ------------------------------------------------------------
# Generate DKIM if needed
# ------------------------------------------------------------

log "DKIM"

if ! DKIM_QUERY=$(su - zimbra -c \
    "/opt/zimbra/libexec/zmdkimkeyutil -q -d '$DOMAIN'" 2>/dev/null); then
    if ! DKIM_ADD_OUTPUT=$(su - zimbra -c \
        "/opt/zimbra/libexec/zmdkimkeyutil -a -d '$DOMAIN'" 2>&1); then
        echo "$DKIM_ADD_OUTPUT"
        die "Cannot generate DKIM data for $DOMAIN"
    fi
    echo "$DKIM_ADD_OUTPUT"

    DKIM_QUERY=$(su - zimbra -c \
        "/opt/zimbra/libexec/zmdkimkeyutil -q -d '$DOMAIN'" 2>&1) || \
        die "Cannot retrieve generated DKIM data for $DOMAIN"
fi

parse_dkim_query "$DKIM_QUERY" || die "Cannot parse DKIM DNS data"

DKIM_DNS_NAME="${DKIM_SELECTOR}._domainkey.${DOMAIN}"
unset DKIM_QUERY

echo "DKIM selector : $DKIM_SELECTOR"
echo "DKIM DNS host : $DKIM_DNS_NAME"
echo "DKIM TXT data : prepared for the installation summary"

# ------------------------------------------------------------
# Host firewall
# ------------------------------------------------------------

if [[ "$CONFIGURE_FIREWALL" == "yes" ]]; then
    configure_ufw
else
    SSH_PORT="$(detect_ssh_port)/tcp (unchanged)"
    FIREWALL_STATUS="skipped by --skip-firewall"
    FIREWALL_ADMIN_ACCESS="unchanged"
    UFW_RULES="UFW configuration skipped by --skip-firewall"
    log "Skip UFW firewall configuration"
fi

# ------------------------------------------------------------
# Save credentials / deployment info
# ------------------------------------------------------------

RESULT_FILE="/root/ZIMBRA-INSTALL-INFO.txt"

install -m 600 /dev/null "$RESULT_FILE"
print_install_summary > "$RESULT_FILE"
install -m 600 /dev/null /root/ZIMBRA-ADMIN-PASSWORD.txt
printf '%s\n' "$ADMIN_PASS" > /root/ZIMBRA-ADMIN-PASSWORD.txt

log "Installation completed"
print_install_summary
