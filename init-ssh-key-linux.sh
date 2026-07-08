#!/usr/bin/env bash
# init-ssh-key-linux-native-v3.1.sh
#
# Native Linux/OpenSSH SSH-key initializer with repeat-run detection.
#
# Requirements:
#   - ssh
#   - scp
#   - ssh-keygen
#   - bash
#   - timeout, awk, sed
#
# Repeat-run behavior:
#   - Same Server IP/HostName + same remote User already exists in ~/.ssh/config:
#       1. Test TCP port 22 first.
#       2. If port is unreachable, report it as network/port/firewall/sshd/VPN/tunnel issue.
#       3. If port is reachable, test the existing SSH config/key.
#       4. If key login succeeds, exit OK.
#       5. If key login fails, report it as SSH authentication/config issue.
#       6. It will NOT generate duplicate keys for an already configured IP/user.
#   - No matching config:
#       Run full initialization flow.
#
# Security model:
#   - Generate private key locally.
#   - Upload only the public key to remote ~/.ssh/authorized_keys.
#   - Private key never leaves the local machine.
#
# Limitation:
#   - This native version does not use sshpass.
#   - You will manually type the remote user's password when ssh/scp prompts.

set -Eeuo pipefail

C_RESET="\033[0m"
C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_CYAN="\033[36m"
C_GRAY="\033[90m"

info() { echo -e "${C_CYAN}[INFO]${C_RESET} $*"; }
ok()   { echo -e "${C_GREEN}[ OK ]${C_RESET} $*"; }
warn() { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
err()  { echo -e "${C_RED}[ERR ]${C_RESET} $*" >&2; }

fail() {
    err "$1"
    exit "${2:-1}"
}

need_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        fail "Missing command: $cmd"
    fi
}

safe_name() {
    printf '%s' "$1" | sed 's/[^A-Za-z0-9_.-]/_/g'
}

is_concrete_alias() {
    local alias="$1"
    [[ -n "$alias" && "$alias" != *"*"* && "$alias" != *"?"* && "$alias" != "!"* ]]
}

test_tcp_port() {
    local host="$1"
    local port="${2:-22}"
    local timeout_sec="${3:-5}"

    timeout "$timeout_sec" bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" >/dev/null 2>&1
}

extract_aliases_from_config() {
    local config_path="$1"

    [[ -f "$config_path" ]] || return 0

    awk '
        BEGIN { IGNORECASE=1 }
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*Host[[:space:]]+/ {
            for (i=2; i<=NF; i++) {
                if ($i !~ /[*?!]/) print $i
            }
        }
    ' "$config_path"
}

find_matching_aliases() {
    local config_path="$1"
    local server_ip="$2"
    local remote_user="$3"

    local alias resolved_host resolved_user

    while IFS= read -r alias; do
        [[ -n "$alias" ]] || continue
        is_concrete_alias "$alias" || continue

        resolved_host="$(
            ssh -G -l "$remote_user" "$alias" 2>/dev/null \
                | awk 'BEGIN{IGNORECASE=1} /^hostname[[:space:]]+/ {print $2; exit}'
        )"

        resolved_user="$(
            ssh -G -l "$remote_user" "$alias" 2>/dev/null \
                | awk 'BEGIN{IGNORECASE=1} /^user[[:space:]]+/ {print $2; exit}'
        )"

        if [[ "$resolved_host" == "$server_ip" && "$resolved_user" == "$remote_user" ]]; then
            printf '%s\n' "$alias"
        fi
    done < <(extract_aliases_from_config "$config_path")
}

test_existing_aliases() {
    local aliases=("$@")

    local alias output code
    local any_result=1

    for alias in "${aliases[@]}"; do
        [[ -n "$alias" ]] || continue

        info "Testing existing SSH config alias: ${alias}"

        set +e
        output="$(
            ssh \
                -o ConnectTimeout=8 \
                -o ConnectionAttempts=1 \
                -o BatchMode=yes \
                -o StrictHostKeyChecking=accept-new \
                "$alias" \
                'echo __SSH_KEY_LOGIN_OK__; hostname; whoami' 2>&1
        )"
        code=$?
        set -e

        any_result=0

        if [[ $code -eq 0 && "$output" == *"__SSH_KEY_LOGIN_OK__"* ]]; then
            ok "Existing SSH key/config login succeeded via alias: ${alias}"
            echo ""
            echo -e "${C_CYAN}Use:${C_RESET}"
            echo -e "${C_YELLOW}ssh ${alias}${C_RESET}"
            return 0
        fi

        echo "----- Test alias: ${alias}, exit=${code} -----" >&2
        echo -e "${C_GRAY}${output}${C_RESET}" >&2
    done

    if [[ $any_result -ne 0 ]]; then
        warn "No concrete alias was available for testing."
    fi

    return 1
}

write_config_block() {
    local config_path="$1"
    local alias="$2"
    local server_ip="$3"
    local remote_user="$4"
    local key_name="$5"

    touch "$config_path"
    chmod 600 "$config_path"

    if grep -Eq "^[[:space:]]*Host[[:space:]]+.*(^|[[:space:]])${alias}([[:space:]]|$)" "$config_path"; then
        warn "SSH alias '${alias}' already exists. Config block will not be duplicated."
        return 0
    fi

    cat >> "$config_path" <<EOF

Host ${alias}
    HostName ${server_ip}
    User ${remote_user}
    IdentityFile ~/.ssh/${key_name}
    IdentitiesOnly yes
EOF

    chmod 600 "$config_path"
    ok "SSH config updated: ${config_path}"
}

clear || true

echo -e "${C_CYAN}"
echo "============================================================"
echo " Native Linux OpenSSH Key Initializer v3.1"
echo " Repeat-run safe: configured IP/user = test only"
echo "============================================================"
echo -e "${C_RESET}"

warn "This script uses native OpenSSH only."
warn "It does not auto-fill SSH password. Type the remote password when prompted."
warn "If the same IP/user is already configured, this script will only test it."
echo ""

for cmd in ssh scp ssh-keygen sed awk timeout; do
    need_cmd "$cmd"
    ok "Found $cmd"
done

read -rp "Server IP or hostname: " SERVER_IP
if [[ -z "${SERVER_IP// }" ]]; then
    fail "Server IP cannot be empty."
fi

read -rp "Remote Linux user: " REMOTE_USER
if [[ -z "${REMOTE_USER// }" ]]; then
    fail "Remote user cannot be empty."
fi

LOCAL_SSH_DIR="$HOME/.ssh"
CONFIG_PATH="$LOCAL_SSH_DIR/config"

mkdir -p "$LOCAL_SSH_DIR"
chmod 700 "$LOCAL_SSH_DIR"
touch "$CONFIG_PATH"
chmod 600 "$CONFIG_PATH"

echo ""
info "Step 1: Checking whether this IP/user is already configured..."

mapfile -t MATCHING_ALIASES < <(find_matching_aliases "$CONFIG_PATH" "$SERVER_IP" "$REMOTE_USER" | sort -u)

if [[ ${#MATCHING_ALIASES[@]} -gt 0 ]]; then
    ok "Existing SSH config found for HostName/IP='${SERVER_IP}', User='${REMOTE_USER}'."
    warn "Repeat-run mode: this script will only test the existing configuration and will not generate a duplicate key."

    echo -e "${C_GRAY}Matched aliases:${C_RESET}"
    for a in "${MATCHING_ALIASES[@]}"; do
        echo "  - $a"
    done

    echo ""
    info "Checking TCP connectivity to ${SERVER_IP}:22..."

    if ! test_tcp_port "$SERVER_IP" 22 5; then
        err "Network/port test failed: cannot reach ${SERVER_IP}:22."
        echo ""
        warn "This is likely a network/port issue, not a key issue."
        warn "Possible causes:"
        warn "  1. Wrong IP or server is offline."
        warn "  2. SSH service is not listening on port 22."
        warn "  3. Firewall blocks port 22."
        warn "  4. VPN/LAN route is missing."
        warn "  5. Cloudflare Tunnel / port forwarding is not active, if you use one."
        exit 3
    fi

    ok "TCP port 22 is reachable."

    if test_existing_aliases "${MATCHING_ALIASES[@]}"; then
        echo ""
        echo -e "${C_CYAN}============================================================${C_RESET}"
        echo -e "${C_GREEN} DONE - existing config is healthy${C_RESET}"
        echo -e "${C_CYAN}============================================================${C_RESET}"
        exit 0
    fi

    err "TCP port is reachable, but existing SSH key/config login failed."
    echo ""
    warn "This is probably NOT a network problem."
    warn "Likely causes:"
    warn "  1. Local IdentityFile path is wrong or private key is missing."
    warn "  2. Remote ~/.ssh/authorized_keys does not contain the matching public key."
    warn "  3. Remote ~/.ssh or authorized_keys permissions are wrong."
    warn "  4. sshd_config restricts this user through AllowUsers/AllowGroups/DenyUsers."
    warn "  5. Remote user is wrong or locked."
    exit 4
fi

ok "No existing SSH config found for this IP/user."
info "New initialization mode: full flow will be executed."

echo ""
info "Step 2/8: Checking TCP connectivity to ${SERVER_IP}:22..."

if ! test_tcp_port "$SERVER_IP" 22 5; then
    err "Cannot reach ${SERVER_IP}:22."
    warn "Stop here because this is a network/port issue."
    warn "Check IP, server power state, sshd status, firewall, VPN/LAN route, or tunnel."
    exit 3
fi

ok "TCP port 22 is reachable."

echo ""
info "Step 3/8: Testing password SSH connection..."
warn "You will be asked to type the remote user's SSH password now."

set +e
PASSWORD_TEST_OUTPUT="$(
    ssh \
        -o ConnectTimeout=8 \
        -o StrictHostKeyChecking=accept-new \
        -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        -o NumberOfPasswordPrompts=3 \
        "${REMOTE_USER}@${SERVER_IP}" \
        'echo __SSH_PASSWORD_LOGIN_OK__; hostname; whoami' 2>&1
)"
PASSWORD_TEST_CODE=$?
set -e

if [[ $PASSWORD_TEST_CODE -ne 0 || "$PASSWORD_TEST_OUTPUT" != *"__SSH_PASSWORD_LOGIN_OK__"* ]]; then
    err "Password SSH connection failed."
    echo ""
    echo -e "${C_GRAY}${PASSWORD_TEST_OUTPUT}${C_RESET}"
    echo ""
    warn "Port 22 is reachable, so this is more likely an SSH login/authentication/server-policy issue."
    fail "Cannot continue. Check username, password, PasswordAuthentication, AllowUsers/AllowGroups, or server-side SSH policy." 5
fi

ok "Password SSH connection succeeded."

DEFAULT_KEY_NAME="id_ed25519_$(safe_name "$REMOTE_USER")_$(safe_name "$SERVER_IP")"

echo ""
info "Step 4/8: Choose local private key name."
warn "Default: ${DEFAULT_KEY_NAME}"

while true; do
    read -rp "Local key name, press Enter to use default: " KEY_NAME_INPUT

    if [[ -z "${KEY_NAME_INPUT// }" ]]; then
        KEY_NAME="$DEFAULT_KEY_NAME"
    else
        KEY_NAME="$KEY_NAME_INPUT"
    fi

    if [[ "$KEY_NAME" == *"/"* || "$KEY_NAME" == *"\\"* || "$KEY_NAME" =~ [[:space:]] ]]; then
        err "Key name cannot contain path separators or spaces."
        continue
    fi

    PRIVATE_KEY_PATH="${LOCAL_SSH_DIR}/${KEY_NAME}"
    PUBLIC_KEY_PATH="${PRIVATE_KEY_PATH}.pub"

    if [[ -f "$PRIVATE_KEY_PATH" && -f "$PUBLIC_KEY_PATH" ]]; then
        warn "Key already exists: ${PRIVATE_KEY_PATH}"
        read -rp "Use this existing local key? Type y to use, n to choose another name: " USE_EXISTING
        if [[ "$USE_EXISTING" == "y" || "$USE_EXISTING" == "Y" || "$USE_EXISTING" == "yes" || "$USE_EXISTING" == "YES" ]]; then
            info "Using existing local key."
            break
        fi
        continue
    fi

    if [[ -e "$PRIVATE_KEY_PATH" || -e "$PUBLIC_KEY_PATH" ]]; then
        err "Only one of private/public key files exists. Choose another key name or fix the pair manually."
        continue
    fi

    info "Generating local SSH key..."

    KEY_COMMENT="${USER}@$(hostname)-to-${REMOTE_USER}@${SERVER_IP}"

    ssh-keygen \
        -t ed25519 \
        -a 100 \
        -N "" \
        -C "$KEY_COMMENT" \
        -f "$PRIVATE_KEY_PATH"

    if [[ ! -f "$PRIVATE_KEY_PATH" || ! -f "$PUBLIC_KEY_PATH" ]]; then
        fail "Key generation failed. Key files not found."
    fi

    break
done

chmod 700 "$LOCAL_SSH_DIR"
chmod 600 "$PRIVATE_KEY_PATH"
chmod 644 "$PUBLIC_KEY_PATH"

ok "Local private key: ${PRIVATE_KEY_PATH}"
ok "Local public key : ${PUBLIC_KEY_PATH}"

REMOTE_TEMP_PUB_NAME=".tmp_$(safe_name "$KEY_NAME")_$(date +%Y%m%d_%H%M%S)_${RANDOM}.pub"

echo ""
info "Step 5/8: Preparing remote ~/.ssh directory..."
warn "You may be asked to type the remote user's password again."

set +e
PREPARE_OUTPUT="$(
    ssh \
        -o StrictHostKeyChecking=accept-new \
        "${REMOTE_USER}@${SERVER_IP}" \
        'umask 077; mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"; echo __REMOTE_PREPARE_DONE__' 2>&1
)"
PREPARE_CODE=$?
set -e

if [[ $PREPARE_CODE -ne 0 || "$PREPARE_OUTPUT" != *"__REMOTE_PREPARE_DONE__"* ]]; then
    err "Remote ~/.ssh preparation failed."
    echo ""
    echo -e "${C_GRAY}${PREPARE_OUTPUT}${C_RESET}"
    fail "Cannot continue. Check remote home directory permission." 6
fi

ok "Remote ~/.ssh directory is ready."

echo ""
info "Step 6/8: Uploading public key and appending to authorized_keys..."
warn "You may be asked to type the remote user's password."

set +e
SCP_OUTPUT="$(
    scp \
        -o StrictHostKeyChecking=accept-new \
        "$PUBLIC_KEY_PATH" \
        "${REMOTE_USER}@${SERVER_IP}:.ssh/${REMOTE_TEMP_PUB_NAME}" 2>&1
)"
SCP_CODE=$?
set -e

if [[ $SCP_CODE -ne 0 ]]; then
    err "Public key upload by scp failed."
    echo ""
    echo -e "${C_GRAY}${SCP_OUTPUT}${C_RESET}"
    fail "Cannot continue. Check scp availability, password, or remote ~/.ssh permission." 7
fi

set +e
APPEND_OUTPUT="$(
    ssh \
        -o StrictHostKeyChecking=accept-new \
        "${REMOTE_USER}@${SERVER_IP}" \
        'sh -s' -- "$REMOTE_TEMP_PUB_NAME" <<'REMOTE_APPEND' 2>&1
set -eu

TEMP_NAME="$1"
TMP="$HOME/.ssh/$TEMP_NAME"
AUTH="$HOME/.ssh/authorized_keys"

umask 077
touch "$AUTH"
chmod 600 "$AUTH"

if [ ! -s "$TMP" ]; then
    echo "__REMOTE_ERROR__: temporary public key file missing or empty"
    exit 30
fi

if grep -qxF -f "$TMP" "$AUTH"; then
    echo "__REMOTE_INFO__: public key already exists in authorized_keys"
else
    cat "$TMP" >> "$AUTH"
    printf '\n' >> "$AUTH"
    echo "__REMOTE_INFO__: public key appended to authorized_keys"
fi

rm -f "$TMP"
chmod 700 "$HOME/.ssh"
chmod 600 "$AUTH"

echo "__REMOTE_DONE__"
REMOTE_APPEND
)"
APPEND_CODE=$?
set -e

if [[ $APPEND_CODE -ne 0 || "$APPEND_OUTPUT" != *"__REMOTE_DONE__"* ]]; then
    err "Appending public key to authorized_keys failed."
    echo ""
    echo -e "${C_GRAY}${APPEND_OUTPUT}${C_RESET}"
    fail "Cannot continue. Check remote shell, authorized_keys permission, or disk permission." 8
fi

ok "Public key appended to remote authorized_keys and permissions fixed."

echo ""
info "Step 7/8: Testing key-based SSH login..."

set +e
KEY_TEST_OUTPUT="$(
    ssh \
        -i "$PRIVATE_KEY_PATH" \
        -o ConnectTimeout=8 \
        -o ConnectionAttempts=1 \
        -o IdentitiesOnly=yes \
        -o BatchMode=yes \
        -o StrictHostKeyChecking=accept-new \
        "${REMOTE_USER}@${SERVER_IP}" \
        'echo __SSH_KEY_LOGIN_OK__; hostname; whoami' 2>&1
)"
KEY_TEST_CODE=$?
set -e

if [[ $KEY_TEST_CODE -ne 0 || "$KEY_TEST_OUTPUT" != *"__SSH_KEY_LOGIN_OK__"* ]]; then
    err "Key-based SSH login failed after public key upload."
    echo ""
    echo -e "${C_GRAY}${KEY_TEST_OUTPUT}${C_RESET}"
    warn "Network is reachable and password login worked, so this is probably an authorized_keys or sshd policy issue."
    fail "Check remote ~/.ssh/authorized_keys, PubkeyAuthentication, AllowUsers/AllowGroups, and file permissions." 9
fi

ok "Key-based SSH login succeeded."

echo ""
info "Step 8/8: Writing SSH config alias for future repeat-run detection."

DEFAULT_ALIAS="ssh-$(safe_name "$REMOTE_USER")-$(safe_name "$SERVER_IP")"

while true; do
    read -rp "SSH alias, press Enter to use default '${DEFAULT_ALIAS}', or type skip: " ALIAS_INPUT

    if [[ -z "${ALIAS_INPUT// }" ]]; then
        HOST_ALIAS="$DEFAULT_ALIAS"
    elif [[ "$ALIAS_INPUT" == "skip" ]]; then
        HOST_ALIAS=""
    else
        HOST_ALIAS="$ALIAS_INPUT"
    fi

    if [[ -z "$HOST_ALIAS" ]]; then
        warn "Skipped SSH config update. Repeat-run detection will not find this IP/user unless you add config manually."
        break
    fi

    if [[ "$HOST_ALIAS" =~ [[:space:]] ]]; then
        err "Alias cannot contain spaces."
        continue
    fi

    write_config_block "$CONFIG_PATH" "$HOST_ALIAS" "$SERVER_IP" "$REMOTE_USER" "$KEY_NAME"
    break
done

echo ""
echo -e "${C_CYAN}============================================================${C_RESET}"
echo -e "${C_GREEN} DONE - new SSH key initialized${C_RESET}"
echo -e "${C_CYAN}============================================================${C_RESET}"
echo ""

echo -e "${C_CYAN}You can connect with:${C_RESET}"
if [[ -n "${HOST_ALIAS:-}" ]]; then
    echo -e "${C_YELLOW}ssh ${HOST_ALIAS}${C_RESET}"
fi
echo -e "${C_YELLOW}ssh -i \"${PRIVATE_KEY_PATH}\" -o IdentitiesOnly=yes ${REMOTE_USER}@${SERVER_IP}${C_RESET}"
echo ""
