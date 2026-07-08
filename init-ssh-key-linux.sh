#!/usr/bin/env bash
# init-ssh-key-linux-native-V1.0.0.sh
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

UI_LANG="en"

text() {
    if [[ "$UI_LANG" == "zh" ]]; then
        printf '%s' "$2"
    else
        printf '%s' "$1"
    fi
}

select_language() {
    echo ""
    read -rp "Choose language / 选择语言 ([en]/zh): " LANGUAGE_INPUT
    case "${LANGUAGE_INPUT,,}" in
        zh|cn|chinese|中文)
            UI_LANG="zh"
            ;;
        *)
            UI_LANG="en"
            ;;
    esac
}

fail() {
    err "$1"
    exit "${2:-1}"
}

need_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        fail "$(text "Missing command: $cmd" "缺少命令：$cmd")"
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

        info "$(text "Testing existing SSH config alias: ${alias}" "正在测试现有 SSH config 别名：${alias}")"

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
            ok "$(text "Existing SSH key/config login succeeded via alias: ${alias}" "现有 SSH 密钥/配置登录成功，别名：${alias}")"
            echo ""
            echo -e "${C_CYAN}$(text "Use:" "使用：")${C_RESET}"
            echo -e "${C_YELLOW}ssh ${alias}${C_RESET}"
            return 0
        fi

        echo "$(text "----- Test alias: ${alias}, exit=${code} -----" "----- 测试别名：${alias}，退出码=${code} -----")" >&2
        echo -e "${C_GRAY}${output}${C_RESET}" >&2
    done

    if [[ $any_result -ne 0 ]]; then
        warn "$(text "No concrete alias was available for testing." "没有可用于测试的具体别名。")"
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
        warn "$(text "SSH alias '${alias}' already exists. Config block will not be duplicated." "SSH 别名 '${alias}' 已存在，不会重复写入配置块。")"
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
    ok "$(text "SSH config updated: ${config_path}" "SSH config 已更新：${config_path}")"
}

clear || true
select_language

echo -e "${C_CYAN}"
echo "============================================================"
echo "$(text " Native Linux OpenSSH Key Initializer V1.0.0" " Linux 原生 OpenSSH 密钥初始化工具 V1.0.0")"
echo "$(text " Repeat-run safe: configured IP/user = test only" " 可重复执行：已配置的 IP/用户只做检测")"
echo "============================================================"
echo -e "${C_RESET}"

info "$(text "Language: English" "语言：中文")"
warn "$(text "This script uses native OpenSSH only." "此脚本仅使用原生 OpenSSH。")"
warn "$(text "It does not auto-fill SSH password. Type the remote password when prompted." "脚本不会自动填写 SSH 密码；出现提示时请手动输入远程用户密码。")"
warn "$(text "If the same IP/user is already configured, this script will only test it." "如果相同 IP/用户已配置，脚本只会检测现有配置。")"
echo ""

for cmd in ssh scp ssh-keygen sed awk timeout; do
    need_cmd "$cmd"
    ok "$(text "Found $cmd" "已找到 $cmd")"
done

read -rp "$(text "Server IP or hostname" "服务器 IP 或主机名"): " SERVER_IP
if [[ -z "${SERVER_IP// }" ]]; then
    fail "$(text "Server IP cannot be empty." "服务器 IP 不能为空。")"
fi

read -rp "$(text "Remote Linux user" "远程 Linux 用户"): " REMOTE_USER
if [[ -z "${REMOTE_USER// }" ]]; then
    fail "$(text "Remote user cannot be empty." "远程用户不能为空。")"
fi

LOCAL_SSH_DIR="$HOME/.ssh"
CONFIG_PATH="$LOCAL_SSH_DIR/config"

mkdir -p "$LOCAL_SSH_DIR"
chmod 700 "$LOCAL_SSH_DIR"
touch "$CONFIG_PATH"
chmod 600 "$CONFIG_PATH"

echo ""
info "$(text "Step 1: Checking whether this IP/user is already configured..." "步骤 1：检查此 IP/用户是否已经配置...")"

mapfile -t MATCHING_ALIASES < <(find_matching_aliases "$CONFIG_PATH" "$SERVER_IP" "$REMOTE_USER" | sort -u)

if [[ ${#MATCHING_ALIASES[@]} -gt 0 ]]; then
    ok "$(text "Existing SSH config found for HostName/IP='${SERVER_IP}', User='${REMOTE_USER}'." "已找到 HostName/IP='${SERVER_IP}'、User='${REMOTE_USER}' 的现有 SSH 配置。")"
    warn "$(text "Repeat-run mode: this script will only test the existing configuration and will not generate a duplicate key." "重复执行模式：脚本只会测试现有配置，不会生成重复密钥。")"

    echo -e "${C_GRAY}$(text "Matched aliases:" "匹配到的别名：")${C_RESET}"
    for a in "${MATCHING_ALIASES[@]}"; do
        echo "  - $a"
    done

    echo ""
    info "$(text "Checking TCP connectivity to ${SERVER_IP}:22..." "正在检查到 ${SERVER_IP}:22 的 TCP 连接...")"

    if ! test_tcp_port "$SERVER_IP" 22 5; then
        err "$(text "Network/port test failed: cannot reach ${SERVER_IP}:22." "网络/端口测试失败：无法连接 ${SERVER_IP}:22。")"
        echo ""
        warn "$(text "This is likely a network/port issue, not a key issue." "这通常是网络/端口问题，不是密钥问题。")"
        warn "$(text "Possible causes:" "可能原因：")"
        warn "$(text "  1. Wrong IP or server is offline." "  1. IP 错误或服务器离线。")"
        warn "$(text "  2. SSH service is not listening on port 22." "  2. SSH 服务没有监听 22 端口。")"
        warn "$(text "  3. Firewall blocks port 22." "  3. 防火墙阻止了 22 端口。")"
        warn "$(text "  4. VPN/LAN route is missing." "  4. VPN/LAN 路由不可达。")"
        warn "$(text "  5. Cloudflare Tunnel / port forwarding is not active, if you use one." "  5. 如果使用 Cloudflare Tunnel/端口转发，它可能未生效。")"
        exit 3
    fi

    ok "$(text "TCP port 22 is reachable." "TCP 22 端口可达。")"

    if test_existing_aliases "${MATCHING_ALIASES[@]}"; then
        echo ""
        echo -e "${C_CYAN}============================================================${C_RESET}"
        echo -e "${C_GREEN}$(text " DONE - existing config is healthy" " 完成 - 现有配置正常")${C_RESET}"
        echo -e "${C_CYAN}============================================================${C_RESET}"
        exit 0
    fi

    err "$(text "TCP port is reachable, but existing SSH key/config login failed." "TCP 端口可达，但现有 SSH 密钥/配置登录失败。")"
    echo ""
    warn "$(text "This is probably NOT a network problem." "这通常不是网络问题。")"
    warn "$(text "Likely causes:" "可能原因：")"
    warn "$(text "  1. Local IdentityFile path is wrong or private key is missing." "  1. 本地 IdentityFile 路径错误或私钥缺失。")"
    warn "$(text "  2. Remote ~/.ssh/authorized_keys does not contain the matching public key." "  2. 远程 ~/.ssh/authorized_keys 没有对应公钥。")"
    warn "$(text "  3. Remote ~/.ssh or authorized_keys permissions are wrong." "  3. 远程 ~/.ssh 或 authorized_keys 权限错误。")"
    warn "$(text "  4. sshd_config restricts this user through AllowUsers/AllowGroups/DenyUsers." "  4. sshd_config 通过 AllowUsers/AllowGroups/DenyUsers 限制了该用户。")"
    warn "$(text "  5. Remote user is wrong or locked." "  5. 远程用户错误或已锁定。")"
    exit 4
fi

ok "$(text "No existing SSH config found for this IP/user." "未找到此 IP/用户的现有 SSH 配置。")"
info "$(text "New initialization mode: full flow will be executed." "新初始化模式：将执行完整流程。")"

echo ""
info "$(text "Step 2/8: Checking TCP connectivity to ${SERVER_IP}:22..." "步骤 2/8：检查到 ${SERVER_IP}:22 的 TCP 连接...")"

if ! test_tcp_port "$SERVER_IP" 22 5; then
    err "$(text "Cannot reach ${SERVER_IP}:22." "无法连接 ${SERVER_IP}:22。")"
    warn "$(text "Stop here because this is a network/port issue." "此处停止，因为这是网络/端口问题。")"
    warn "$(text "Check IP, server power state, sshd status, firewall, VPN/LAN route, or tunnel." "请检查 IP、服务器电源状态、sshd 状态、防火墙、VPN/LAN 路由或隧道。")"
    exit 3
fi

ok "$(text "TCP port 22 is reachable." "TCP 22 端口可达。")"

echo ""
info "$(text "Step 3/8: Testing password SSH connection..." "步骤 3/8：测试密码 SSH 连接...")"
warn "$(text "You will be asked to type the remote user's SSH password now." "现在会提示你输入远程用户的 SSH 密码。")"

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
    err "$(text "Password SSH connection failed." "密码 SSH 连接失败。")"
    echo ""
    echo -e "${C_GRAY}${PASSWORD_TEST_OUTPUT}${C_RESET}"
    echo ""
    warn "$(text "Port 22 is reachable, so this is more likely an SSH login/authentication/server-policy issue." "22 端口可达，因此更可能是 SSH 登录/认证/服务器策略问题。")"
    fail "$(text "Cannot continue. Check username, password, PasswordAuthentication, AllowUsers/AllowGroups, or server-side SSH policy." "无法继续。请检查用户名、密码、PasswordAuthentication、AllowUsers/AllowGroups 或服务器端 SSH 策略。")" 5
fi

ok "$(text "Password SSH connection succeeded." "密码 SSH 连接成功。")"

DEFAULT_KEY_NAME="id_ed25519_$(safe_name "$REMOTE_USER")_$(safe_name "$SERVER_IP")"

echo ""
info "$(text "Step 4/8: Choose local private key name." "步骤 4/8：选择本地私钥名称。")"
warn "$(text "Default: ${DEFAULT_KEY_NAME}" "默认值：${DEFAULT_KEY_NAME}")"

while true; do
    read -rp "$(text "Local key name, press Enter to use default" "本地密钥名称，按 Enter 使用默认值"): " KEY_NAME_INPUT

    if [[ -z "${KEY_NAME_INPUT// }" ]]; then
        KEY_NAME="$DEFAULT_KEY_NAME"
    else
        KEY_NAME="$KEY_NAME_INPUT"
    fi

    if [[ "$KEY_NAME" == *"/"* || "$KEY_NAME" == *"\\"* || "$KEY_NAME" =~ [[:space:]] ]]; then
        err "$(text "Key name cannot contain path separators or spaces." "密钥名称不能包含路径分隔符或空格。")"
        continue
    fi

    PRIVATE_KEY_PATH="${LOCAL_SSH_DIR}/${KEY_NAME}"
    PUBLIC_KEY_PATH="${PRIVATE_KEY_PATH}.pub"

    if [[ -f "$PRIVATE_KEY_PATH" && -f "$PUBLIC_KEY_PATH" ]]; then
        warn "$(text "Key already exists: ${PRIVATE_KEY_PATH}" "密钥已存在：${PRIVATE_KEY_PATH}")"
        read -rp "$(text "Use this existing local key? Type y to use, n to choose another name" "使用这个现有本地密钥？输入 y 使用，输入 n 重新选择"): " USE_EXISTING
        if [[ "$USE_EXISTING" == "y" || "$USE_EXISTING" == "Y" || "$USE_EXISTING" == "yes" || "$USE_EXISTING" == "YES" ]]; then
            info "$(text "Using existing local key." "将使用现有本地密钥。")"
            break
        fi
        continue
    fi

    if [[ -e "$PRIVATE_KEY_PATH" || -e "$PUBLIC_KEY_PATH" ]]; then
        err "$(text "Only one of private/public key files exists. Choose another key name or fix the pair manually." "私钥/公钥文件只有一个存在。请换一个密钥名，或手动修复这对文件。")"
        continue
    fi

    info "$(text "Generating local SSH key..." "正在生成本地 SSH 密钥...")"

    KEY_COMMENT="${USER}@$(hostname)-to-${REMOTE_USER}@${SERVER_IP}"

    ssh-keygen \
        -t ed25519 \
        -a 100 \
        -N "" \
        -C "$KEY_COMMENT" \
        -f "$PRIVATE_KEY_PATH"

    if [[ ! -f "$PRIVATE_KEY_PATH" || ! -f "$PUBLIC_KEY_PATH" ]]; then
        fail "$(text "Key generation failed. Key files not found." "密钥生成失败，未找到密钥文件。")"
    fi

    break
done

chmod 700 "$LOCAL_SSH_DIR"
chmod 600 "$PRIVATE_KEY_PATH"
chmod 644 "$PUBLIC_KEY_PATH"

ok "$(text "Local private key: ${PRIVATE_KEY_PATH}" "本地私钥：${PRIVATE_KEY_PATH}")"
ok "$(text "Local public key : ${PUBLIC_KEY_PATH}" "本地公钥：${PUBLIC_KEY_PATH}")"

REMOTE_TEMP_PUB_NAME=".tmp_$(safe_name "$KEY_NAME")_$(date +%Y%m%d_%H%M%S)_${RANDOM}.pub"

echo ""
info "$(text "Step 5/8: Preparing remote ~/.ssh directory..." "步骤 5/8：准备远程 ~/.ssh 目录...")"
warn "$(text "You may be asked to type the remote user's password again." "可能会再次要求你输入远程用户密码。")"

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
    err "$(text "Remote ~/.ssh preparation failed." "远程 ~/.ssh 准备失败。")"
    echo ""
    echo -e "${C_GRAY}${PREPARE_OUTPUT}${C_RESET}"
    fail "$(text "Cannot continue. Check remote home directory permission." "无法继续。请检查远程 home 目录权限。")" 6
fi

ok "$(text "Remote ~/.ssh directory is ready." "远程 ~/.ssh 目录已准备好。")"

echo ""
info "$(text "Step 6/8: Uploading public key and appending to authorized_keys..." "步骤 6/8：上传公钥并追加到 authorized_keys...")"
warn "$(text "You may be asked to type the remote user's password." "可能会要求你输入远程用户密码。")"

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
    err "$(text "Public key upload by scp failed." "通过 scp 上传公钥失败。")"
    echo ""
    echo -e "${C_GRAY}${SCP_OUTPUT}${C_RESET}"
    fail "$(text "Cannot continue. Check scp availability, password, or remote ~/.ssh permission." "无法继续。请检查 scp 可用性、密码或远程 ~/.ssh 权限。")" 7
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
    err "$(text "Appending public key to authorized_keys failed." "追加公钥到 authorized_keys 失败。")"
    echo ""
    echo -e "${C_GRAY}${APPEND_OUTPUT}${C_RESET}"
    fail "$(text "Cannot continue. Check remote shell, authorized_keys permission, or disk permission." "无法继续。请检查远程 shell、authorized_keys 权限或磁盘权限。")" 8
fi

ok "$(text "Public key appended to remote authorized_keys and permissions fixed." "公钥已追加到远程 authorized_keys，权限已修正。")"

echo ""
info "$(text "Step 7/8: Testing key-based SSH login..." "步骤 7/8：测试密钥 SSH 登录...")"

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
    err "$(text "Key-based SSH login failed after public key upload." "公钥上传后，密钥 SSH 登录仍然失败。")"
    echo ""
    echo -e "${C_GRAY}${KEY_TEST_OUTPUT}${C_RESET}"
    warn "$(text "Network is reachable and password login worked, so this is probably an authorized_keys or sshd policy issue." "网络可达且密码登录成功，因此这通常是 authorized_keys 或 sshd 策略问题。")"
    fail "$(text "Check remote ~/.ssh/authorized_keys, PubkeyAuthentication, AllowUsers/AllowGroups, and file permissions." "请检查远程 ~/.ssh/authorized_keys、PubkeyAuthentication、AllowUsers/AllowGroups 和文件权限。")" 9
fi

ok "$(text "Key-based SSH login succeeded." "密钥 SSH 登录成功。")"

echo ""
info "$(text "Step 8/8: Writing SSH config alias for future repeat-run detection." "步骤 8/8：写入 SSH config 别名，用于后续重复执行检测。")"

DEFAULT_ALIAS="ssh-$(safe_name "$REMOTE_USER")-$(safe_name "$SERVER_IP")"

while true; do
    read -rp "$(text "SSH alias, press Enter to use default '${DEFAULT_ALIAS}', or type skip" "SSH 别名，按 Enter 使用默认值 '${DEFAULT_ALIAS}'，或输入 skip 跳过"): " ALIAS_INPUT

    if [[ -z "${ALIAS_INPUT// }" ]]; then
        HOST_ALIAS="$DEFAULT_ALIAS"
    elif [[ "$ALIAS_INPUT" == "skip" ]]; then
        HOST_ALIAS=""
    else
        HOST_ALIAS="$ALIAS_INPUT"
    fi

    if [[ -z "$HOST_ALIAS" ]]; then
        warn "$(text "Skipped SSH config update. Repeat-run detection will not find this IP/user unless you add config manually." "已跳过 SSH config 更新。除非你手动添加配置，否则重复执行检测找不到此 IP/用户。")"
        break
    fi

    if [[ "$HOST_ALIAS" =~ [[:space:]] ]]; then
        err "$(text "Alias cannot contain spaces." "别名不能包含空格。")"
        continue
    fi

    write_config_block "$CONFIG_PATH" "$HOST_ALIAS" "$SERVER_IP" "$REMOTE_USER" "$KEY_NAME"
    break
done

echo ""
echo -e "${C_CYAN}============================================================${C_RESET}"
echo -e "${C_GREEN}$(text " DONE - new SSH key initialized" " 完成 - 新 SSH 密钥已初始化")${C_RESET}"
echo -e "${C_CYAN}============================================================${C_RESET}"
echo ""

echo -e "${C_CYAN}$(text "You can connect with:" "你可以这样连接：")${C_RESET}"
if [[ -n "${HOST_ALIAS:-}" ]]; then
    echo -e "${C_YELLOW}ssh ${HOST_ALIAS}${C_RESET}"
fi
echo -e "${C_YELLOW}ssh -i \"${PRIVATE_KEY_PATH}\" -o IdentitiesOnly=yes ${REMOTE_USER}@${SERVER_IP}${C_RESET}"
echo ""
