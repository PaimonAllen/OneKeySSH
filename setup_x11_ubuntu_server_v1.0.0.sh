#!/usr/bin/env bash
set -euo pipefail

# Ubuntu Server X11 Forwarding Setup v1.0.0
# 正式发布版。支持重复运行：托管配置文件会覆盖更新，托管 shell 配置块会先删除后重写。

GREEN='\033[1;32m'; BLUE='\033[1;34m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'

choose_language(){
    local choice="${ONEKEYSSH_LANG:-}"

    if [ -z "$choice" ] && [ -t 0 ]; then
        printf 'Select language / 选择语言 [en/zh] (default: en): '
        IFS= read -r choice || choice=""
    fi

    case "${choice,,}" in
        zh|zh-cn|cn|chinese|中文)
            SCRIPT_LANG="zh"
            ;;
        *)
            SCRIPT_LANG="en"
            ;;
    esac
    export ONEKEYSSH_LANG="$SCRIPT_LANG"
}

tr_msg(){
    local msg="$*"

    if [ "${SCRIPT_LANG:-en}" = "zh" ]; then
        printf '%s' "$msg"
        return 0
    fi

    case "$msg" in
        可选软件包已安装：*)
            printf 'Optional package installed: %s' "${msg#可选软件包已安装：}"
            ;;
        当前软件源中未找到可选软件包：*，已跳过。)
            local value="${msg#当前软件源中未找到可选软件包：}"
            printf 'Optional package not found in current apt sources, skipped: %s' "${value%，已跳过。}"
            ;;
        兼容软件包已安装：*)
            printf 'Compatibility package installed: %s' "${msg#兼容软件包已安装：}"
            ;;
        以下兼容软件包均未在当前软件源中找到，已跳过：*)
            printf 'None of the compatibility packages were found in current apt sources, skipped: %s' "${msg#以下兼容软件包均未在当前软件源中找到，已跳过：}"
            ;;
        未检测到\ ssh/sshd\ 服务管理入口。如\ SSH\ 配置未立即生效，请手动重启\ SSH\ 服务。)
            printf 'No ssh/sshd service manager entry was detected. If the SSH configuration does not take effect immediately, restart the SSH service manually.'
            ;;
        未检测到\ apt-get。本脚本适用于\ Ubuntu/Debian\ 系统。)
            printf 'apt-get was not detected. This script is intended for Ubuntu/Debian systems.'
            ;;
        当前执行用户：*)
            printf 'Current user: %s' "${msg#当前执行用户：}"
            ;;
        当前\ DISPLAY：*)
            printf 'Current DISPLAY: %s' "${msg#当前 DISPLAY：}"
            ;;
        当前\ XAUTHORITY：*)
            printf 'Current XAUTHORITY: %s' "${msg#当前 XAUTHORITY：}"
            ;;
        当前\ DISPLAY\ 为空。服务器端配置将继续执行；完成后请使用已开启\ X11\ forwarding\ 的\ SSH\ 会话重新连接再测试。)
            printf 'DISPLAY is empty. Server-side configuration will continue; after completion, reconnect with an SSH session that has X11 forwarding enabled before testing.'
            ;;
        正在安装\ X11\ 转发工具和磁盘管理应用...)
            printf 'Installing X11 forwarding tools and disk management applications...'
            ;;
        软件包安装完成。)
            printf 'Package installation completed.'
            ;;
        正在配置\ OpenSSH\ 服务端\ X11\ forwarding...)
            printf 'Configuring OpenSSH server-side X11 forwarding...'
            ;;
        未找到\ sshd\ 命令，请确认\ openssh-server\ 已正确安装。)
            printf 'sshd was not found. Verify that openssh-server is installed correctly.'
            ;;
        sshd\ -t\ 配置校验失败，请检查\ SSH\ 配置。)
            printf 'sshd -t configuration validation failed. Check the SSH configuration.'
            ;;
        OpenSSH\ X11\ forwarding\ 配置完成。)
            printf 'OpenSSH X11 forwarding configuration completed.'
            ;;
        正在配置\ sudo\ 保留\ X11\ 环境变量...)
            printf 'Configuring sudo to preserve X11 environment variables...'
            ;;
        sudoers\ X11\ 环境变量配置完成。)
            printf 'sudoers X11 environment configuration completed.'
            ;;
        sudoers\ 配置校验失败，正在回滚生成的\ sudoers\ 文件。)
            printf 'sudoers validation failed. Rolling back the generated sudoers file.'
            ;;
        正在配置用户登录环境，以支持\ sudo\ 图形程序访问当前\ X11\ 会话...)
            printf 'Configuring login environment so sudo GUI programs can access the current X11 session...'
            ;;
        系统级\ XAUTHORITY\ 登录配置完成。)
            printf 'System-wide XAUTHORITY login configuration completed.'
            ;;
        正在为当前\ sudo\ 用户补充个人\ shell\ 启动配置...)
            printf 'Adding personal shell startup compatibility configuration for the current sudo user...'
            ;;
        已为用户*\ 写入个人\ shell\ 兼容配置。)
            local value="${msg#已为用户 }"
            printf 'Personal shell compatibility configuration written for user %s.' "${value% 写入个人 shell 兼容配置。}"
            ;;
        未识别到非\ root\ 的\ SUDO_USER，已跳过个人\ shell\ 配置。)
            printf 'No non-root SUDO_USER was detected. Personal shell configuration was skipped.'
            ;;
        正在安装\ root\ X11\ 授权同步工具：*)
            printf 'Installing root X11 authorization sync tool: %s' "${msg#正在安装 root X11 授权同步工具：}"
            ;;
        x11-root-sync\ 安装完成。)
            printf 'x11-root-sync installation completed.'
            ;;
        正在安装\ root\ X11\ 命令运行器：*)
            printf 'Installing root X11 command runner: %s' "${msg#正在安装 root X11 命令运行器：}"
            ;;
        x11-root-run\ 安装完成。)
            printf 'x11-root-run installation completed.'
            ;;
        正在安装磁盘工具启动命令...)
            printf 'Installing disk tool launch commands...'
            ;;
        xgparted\ 和\ xgnome-disks\ 安装完成。)
            printf 'xgparted and xgnome-disks installation completed.'
            ;;
        正在安装\ X11\ 诊断命令：*)
            printf 'Installing X11 diagnostic command: %s' "${msg#正在安装 X11 诊断命令：}"
            ;;
        x11-debug\ 安装完成。)
            printf 'x11-debug installation completed.'
            ;;
        正在安装\ X11\ 验证命令：*)
            printf 'Installing X11 test command: %s' "${msg#正在安装 X11 验证命令：}"
            ;;
        x11-test\ 安装完成。)
            printf 'x11-test installation completed.'
            ;;
        正在配置\ root\ shell\ 自动使用\ /root/.Xauthority...)
            printf 'Configuring the root shell to automatically use /root/.Xauthority...'
            ;;
        root\ shell\ X11\ 授权配置完成。)
            printf 'Root shell X11 authorization configuration completed.'
            ;;
        *)
            printf '%s' "$msg"
            ;;
    esac
}

choose_language

info(){ echo -e "${BLUE}[INFO]${NC} $(tr_msg "$*")"; }
ok(){ echo -e "${GREEN}[OK]${NC} $(tr_msg "$*")"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $(tr_msg "$*")"; }
fail(){ echo -e "${RED}[ERR]${NC} $(tr_msg "$*")" >&2; }
run_root(){ if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }
pkg_available(){ apt-cache show "$1" >/dev/null 2>&1; }

install_if_available(){
    local pkg="$1"
    if pkg_available "$pkg"; then
        run_root apt-get install -y "$pkg"
        ok "可选软件包已安装：$pkg"
    else
        warn "当前软件源中未找到可选软件包：$pkg，已跳过。"
    fi
}

install_first_available(){
    local pkg
    for pkg in "$@"; do
        if pkg_available "$pkg"; then
            run_root apt-get install -y "$pkg"
            ok "兼容软件包已安装：$pkg"
            return 0
        fi
    done
    warn "以下兼容软件包均未在当前软件源中找到，已跳过：$*"
    return 0
}

append_managed_block(){
    local file="$1" begin="$2" end="$3" content="$4"
    run_root mkdir -p "$(dirname "$file")"
    run_root touch "$file"
    run_root sed -i "\|$begin|,\|$end|d" "$file" 2>/dev/null || true
    {
        printf '\n%s\n' "$begin"
        printf '%s\n' "$content"
        printf '%s\n' "$end"
    } | run_root tee -a "$file" >/dev/null
}

reload_ssh_service(){
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then
            run_root systemctl reload ssh || run_root systemctl restart ssh
            return 0
        fi
        if systemctl list-unit-files 2>/dev/null | grep -q '^sshd\.service'; then
            run_root systemctl reload sshd || run_root systemctl restart sshd
            return 0
        fi
    fi
    if command -v service >/dev/null 2>&1; then
        if service --status-all 2>/dev/null | grep -q '[[:space:]]ssh$'; then
            run_root service ssh reload || run_root service ssh restart
            return 0
        fi
        if service --status-all 2>/dev/null | grep -q '[[:space:]]sshd$'; then
            run_root service sshd reload || run_root service sshd restart
            return 0
        fi
    fi
    warn "未检测到 ssh/sshd 服务管理入口。如 SSH 配置未立即生效，请手动重启 SSH 服务。"
}

if ! command -v apt-get >/dev/null 2>&1; then
    fail "未检测到 apt-get。本脚本适用于 Ubuntu/Debian 系统。"
    exit 1
fi

info "当前执行用户：$(whoami)"
info "当前 DISPLAY：${DISPLAY:-<empty>}"
info "当前 XAUTHORITY：${XAUTHORITY:-<empty>}"

if [ -z "${DISPLAY:-}" ]; then
    warn "当前 DISPLAY 为空。服务器端配置将继续执行；完成后请使用已开启 X11 forwarding 的 SSH 会话重新连接再测试。"
fi

info "正在安装 X11 转发工具和磁盘管理应用..."
export DEBIAN_FRONTEND=noninteractive
run_root apt-get update
run_root apt-get install -y \
    openssh-server \
    xauth \
    x11-apps \
    x11-xserver-utils \
    dbus-x11 \
    gparted \
    gnome-disk-utility \
    sudo
install_first_available policykit-1 polkitd
install_if_available xlockmore
ok "软件包安装完成。"

info "正在配置 OpenSSH 服务端 X11 forwarding..."
run_root mkdir -p /etc/ssh/sshd_config.d
run_root tee /etc/ssh/sshd_config.d/99-x11-forwarding.conf >/dev/null <<'SSHD_X11_CONF'
# Managed by setup_x11_gui_ubuntu_server_v1.0.0.sh
X11Forwarding yes
X11UseLocalhost yes
AllowTcpForwarding yes
SSHD_X11_CONF

SSHD_BIN="$(command -v sshd || true)"
if [ -z "$SSHD_BIN" ] && [ -x /usr/sbin/sshd ]; then SSHD_BIN=/usr/sbin/sshd; fi
if [ -z "$SSHD_BIN" ]; then fail "未找到 sshd 命令，请确认 openssh-server 已正确安装。"; exit 1; fi
if run_root "$SSHD_BIN" -t; then reload_ssh_service; else fail "sshd -t 配置校验失败，请检查 SSH 配置。"; exit 1; fi
ok "OpenSSH X11 forwarding 配置完成。"

info "正在配置 sudo 保留 X11 环境变量..."
run_root tee /etc/sudoers.d/99-x11-env-keep >/dev/null <<'SUDOERS_X11_CONF'
# Managed by setup_x11_gui_ubuntu_server_v1.0.0.sh
Defaults env_keep += "DISPLAY XAUTHORITY XAUTHLOCALHOSTNAME DBUS_SESSION_BUS_ADDRESS"
Defaults env_keep += "XDG_RUNTIME_DIR"
SUDOERS_X11_CONF
run_root chmod 440 /etc/sudoers.d/99-x11-env-keep
if run_root visudo -cf /etc/sudoers.d/99-x11-env-keep >/dev/null; then
    ok "sudoers X11 环境变量配置完成。"
else
    fail "sudoers 配置校验失败，正在回滚生成的 sudoers 文件。"
    run_root rm -f /etc/sudoers.d/99-x11-env-keep
    exit 1
fi

info "正在配置用户登录环境，以支持 sudo 图形程序访问当前 X11 会话..."
run_root tee /etc/profile.d/99-x11-xauthority.sh >/dev/null <<'PROFILE_XAUTH'
# Managed by setup_x11_gui_ubuntu_server_v1.0.0.sh
# 为 SSH X11 forwarding 场景补齐 XAUTHORITY。
# 普通用户 xclock 可能通过默认 ~/.Xauthority 正常运行；sudo 后 HOME 会变为 /root，
# 因此需要在 sudo 前显式设置当前用户的 XAUTHORITY。

if [ -n "${DISPLAY:-}" ] && [ "$(id -u 2>/dev/null || echo 0)" != "0" ]; then
    if [ -z "${XAUTHORITY:-}" ]; then
        if [ -n "${HOME:-}" ] && [ -f "$HOME/.Xauthority" ]; then
            export XAUTHORITY="$HOME/.Xauthority"
        fi
    fi
fi
PROFILE_XAUTH
run_root chmod 644 /etc/profile.d/99-x11-xauthority.sh

SOURCE_BLOCK='if [ -r /etc/profile.d/99-x11-xauthority.sh ]; then
    . /etc/profile.d/99-x11-xauthority.sh
fi'
append_managed_block /etc/bash.bashrc '# >>> x11-xauthority-profile-source >>>' '# <<< x11-xauthority-profile-source <<<' "$SOURCE_BLOCK"
run_root mkdir -p /etc/zsh
append_managed_block /etc/zsh/zprofile '# >>> x11-xauthority-profile-source >>>' '# <<< x11-xauthority-profile-source <<<' "$SOURCE_BLOCK"
append_managed_block /etc/zsh/zshrc '# >>> x11-xauthority-profile-source >>>' '# <<< x11-xauthority-profile-source <<<' "$SOURCE_BLOCK"
ok "系统级 XAUTHORITY 登录配置完成。"

info "正在为当前 sudo 用户补充个人 shell 启动配置..."
TARGET_USER="${SUDO_USER:-}"
if [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != root ] && getent passwd "$TARGET_USER" >/dev/null 2>&1; then
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    TARGET_GROUP="$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")"
    for rc in "$TARGET_HOME/.profile" "$TARGET_HOME/.bashrc" "$TARGET_HOME/.zprofile" "$TARGET_HOME/.zshrc"; do
        run_root touch "$rc"
        run_root chown "$TARGET_USER:$TARGET_GROUP" "$rc" || true
        append_managed_block "$rc" '# >>> x11-user-xauthority-source >>>' '# <<< x11-user-xauthority-source <<<' "$SOURCE_BLOCK"
        run_root chown "$TARGET_USER:$TARGET_GROUP" "$rc" || true
    done
    ok "已为用户 $TARGET_USER 写入个人 shell 兼容配置。"
else
    warn "未识别到非 root 的 SUDO_USER，已跳过个人 shell 配置。"
fi

info "正在安装 root X11 授权同步工具：/usr/local/bin/x11-root-sync"
run_root tee /usr/local/bin/x11-root-sync >/dev/null <<'X11_ROOT_SYNC'
#!/usr/bin/env bash
set -euo pipefail
log(){ echo "[x11-root-sync] $*" >&2; }

if [ "$(id -u)" -ne 0 ]; then exec sudo -E "$0" "$@"; fi
if [ -z "${DISPLAY:-}" ]; then log "DISPLAY 为空。请使用带 X11 forwarding 的 SSH 连接。"; exit 2; fi

ROOT_XAUTH=/root/.Xauthority
if [ -e "$ROOT_XAUTH" ] && [ ! -f "$ROOT_XAUTH" ]; then log "$ROOT_XAUTH 已存在但不是普通文件，请手动检查。"; exit 5; fi
if [ ! -e "$ROOT_XAUTH" ]; then install -o root -g root -m 600 /dev/null "$ROOT_XAUTH"; else chown root:root "$ROOT_XAUTH"; chmod 600 "$ROOT_XAUTH"; fi

SOURCE_USER="${1:-${SUDO_USER:-}}"
if [ -z "$SOURCE_USER" ] || [ "$SOURCE_USER" = root ]; then SOURCE_USER="$(logname 2>/dev/null || true)"; fi

if [ -n "${XAUTHORITY_SRC:-}" ]; then
    SOURCE_XAUTH="$XAUTHORITY_SRC"
elif [ -n "${XAUTHORITY:-}" ] && [ "$XAUTHORITY" != "$ROOT_XAUTH" ] && [ -f "$XAUTHORITY" ]; then
    SOURCE_XAUTH="$XAUTHORITY"
else
    if [ -z "$SOURCE_USER" ] || [ "$SOURCE_USER" = root ]; then
        log "无法识别普通登录用户，也没有可用的 XAUTHORITY 源文件。"
        exit 7
    fi
    SOURCE_HOME="$(getent passwd "$SOURCE_USER" | cut -d: -f6 || true)"
    if [ -z "$SOURCE_HOME" ]; then log "无法找到用户 $SOURCE_USER 的 home 目录。"; exit 3; fi
    SOURCE_XAUTH="$SOURCE_HOME/.Xauthority"
fi

if [ ! -f "$SOURCE_XAUTH" ]; then
    log "找不到源 Xauthority：$SOURCE_XAUTH"
    log "请先确认普通用户下 xclock 可以正常打开。"
    exit 4
fi

TMP_XAUTH="$(mktemp)"
trap 'rm -f "$TMP_XAUTH"' EXIT

# 每次同步当前 SSH 会话的 X11 cookie。
# SSH 重新连接后 DISPLAY 可能仍为 localhost:10.0/11.0，但 cookie 可能已经变化。
if xauth -f "$SOURCE_XAUTH" nlist "$DISPLAY" >"$TMP_XAUTH" 2>/dev/null && [ -s "$TMP_XAUTH" ]; then
    xauth -f "$ROOT_XAUTH" remove "$DISPLAY" >/dev/null 2>&1 || true
    sed -e 's/^..../ffff/' "$TMP_XAUTH" | xauth -f "$ROOT_XAUTH" nmerge -
else
    : >"$TMP_XAUTH"
    xauth -f "$SOURCE_XAUTH" nlist >"$TMP_XAUTH" 2>/dev/null || true
    if [ ! -s "$TMP_XAUTH" ]; then log "源 Xauthority 中没有可导入的 cookie：$SOURCE_XAUTH"; exit 6; fi
    sed -e 's/^..../ffff/' "$TMP_XAUTH" | xauth -f "$ROOT_XAUTH" nmerge -
fi

chown root:root "$ROOT_XAUTH"
chmod 600 "$ROOT_XAUTH"
X11_ROOT_SYNC
run_root chmod +x /usr/local/bin/x11-root-sync
ok "x11-root-sync 安装完成。"

info "正在安装 root X11 命令运行器：/usr/local/bin/x11-root-run"
run_root tee /usr/local/bin/x11-root-run >/dev/null <<'X11_ROOT_RUN'
#!/usr/bin/env bash
set -euo pipefail
if [ -z "${DISPLAY:-}" ]; then echo "[x11-root-run] DISPLAY 为空，请用 Xshell 开启 X11 forwarding 重新连接。" >&2; exit 2; fi
if [ "$#" -eq 0 ]; then echo "用法：x11-root-run <command> [args...]" >&2; exit 2; fi

if [ "$(id -u)" -eq 0 ]; then
    /usr/local/bin/x11-root-sync
    export XAUTHORITY=/root/.Xauthority
    exec "$@"
else
    SRC_XAUTH="${XAUTHORITY:-$HOME/.Xauthority}"
    sudo env DISPLAY="$DISPLAY" XAUTHORITY_SRC="$SRC_XAUTH" /usr/local/bin/x11-root-sync
    if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
        exec sudo env DISPLAY="$DISPLAY" XAUTHORITY=/root/.Xauthority DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" "$@"
    else
        exec sudo env DISPLAY="$DISPLAY" XAUTHORITY=/root/.Xauthority "$@"
    fi
fi
X11_ROOT_RUN
run_root chmod +x /usr/local/bin/x11-root-run
ok "x11-root-run 安装完成。"

info "正在安装磁盘工具启动命令..."
run_root tee /usr/local/bin/xgparted >/dev/null <<'XGPARTED'
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/x11-root-run gparted "$@"
XGPARTED
run_root chmod +x /usr/local/bin/xgparted

run_root tee /usr/local/bin/xgnome-disks >/dev/null <<'XGNOME_DISKS'
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/bin/x11-root-run gnome-disks "$@"
XGNOME_DISKS
run_root chmod +x /usr/local/bin/xgnome-disks
ok "xgparted 和 xgnome-disks 安装完成。"

info "正在安装 X11 诊断命令：/usr/local/bin/x11-debug"
run_root tee /usr/local/bin/x11-debug >/dev/null <<'X11_DEBUG'
#!/usr/bin/env bash
set -u

echo "==== 当前用户环境 ===="
echo "whoami     : $(whoami)"
echo "shell      : ${SHELL:-<empty>}"
echo "HOME       : ${HOME:-<empty>}"
echo "DISPLAY    : ${DISPLAY:-<empty>}"
echo "XAUTHORITY : ${XAUTHORITY:-<empty>}"
echo

echo "==== 当前用户 Xauthority ===="
if [ -n "${XAUTHORITY:-}" ]; then
    ls -l "$XAUTHORITY" 2>/dev/null || true
    xauth -f "$XAUTHORITY" list "$DISPLAY" 2>/dev/null || true
elif [ -f "${HOME:-}/.Xauthority" ]; then
    ls -l "$HOME/.Xauthority" 2>/dev/null || true
    xauth -f "$HOME/.Xauthority" list "$DISPLAY" 2>/dev/null || true
else
    echo "没有 XAUTHORITY，也没有 $HOME/.Xauthority"
fi
echo

echo "==== sudo 环境是否保留 X11 变量 ===="
sudo env | grep -E '^(DISPLAY|XAUTHORITY|XAUTHLOCALHOSTNAME|DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR)=' || true
echo

echo "==== sudoers X11 配置 ===="
sudo cat /etc/sudoers.d/99-x11-env-keep 2>/dev/null || true
echo

echo "==== root Xauthority ===="
sudo ls -l /root/.Xauthority 2>/dev/null || true
sudo xauth -f /root/.Xauthority list "${DISPLAY:-}" 2>/dev/null || true
X11_DEBUG
run_root chmod +x /usr/local/bin/x11-debug
ok "x11-debug 安装完成。"

info "正在安装 X11 验证命令：/usr/local/bin/x11-test"
run_root tee /usr/local/bin/x11-test >/dev/null <<'X11_TEST'
#!/usr/bin/env bash
set -euo pipefail

if [ -n "${DISPLAY:-}" ] && [ -z "${XAUTHORITY:-}" ] && [ -f "${HOME:-}/.Xauthority" ]; then
    export XAUTHORITY="$HOME/.Xauthority"
    echo "[INFO] 当前 shell 的 XAUTHORITY 为空，本次测试临时设置为：$XAUTHORITY"
    echo "       重新登录后会自动设置；当前窗口可手动执行：export XAUTHORITY=\"$HOME/.Xauthority\""
    echo
fi

run_gui_smoke(){
    local label="$1"; shift
    local log_file; log_file="$(mktemp)"
    echo "==== 测试：$label ===="
    echo "将短暂启动安全图形程序，约 2 秒后自动关闭。"
    "$@" >"$log_file" 2>&1 &
    local pid=$!
    sleep 2
    if kill -0 "$pid" >/dev/null 2>&1; then
        kill "$pid" >/dev/null 2>&1 || true
        wait "$pid" >/dev/null 2>&1 || true
        rm -f "$log_file"
        echo "[OK] $label 可以正常启动。"
        echo
        return 0
    fi
    local status=0
    wait "$pid" >/dev/null 2>&1 || status=$?
    echo "[ERR] $label 启动失败。"
    echo "----- 错误输出 -----"
    cat "$log_file" || true
    echo "--------------------"
    rm -f "$log_file"
    return "$status"
}

echo "==== X11 基础信息 ===="
echo "whoami     : $(whoami)"
echo "DISPLAY    : ${DISPLAY:-<empty>}"
echo "XAUTHORITY : ${XAUTHORITY:-<empty>}"
echo

if [ -z "${DISPLAY:-}" ]; then echo "[ERR] DISPLAY 为空。请检查 Xshell 是否开启 X11 forwarding。" >&2; exit 2; fi
if ! command -v xclock >/dev/null 2>&1; then echo "[ERR] xclock 未安装。" >&2; exit 3; fi

run_gui_smoke "普通用户 xclock" xclock

echo "==== sudo 环境中的 DISPLAY / XAUTHORITY ===="
sudo env | grep -E '^(DISPLAY|XAUTHORITY)=' || true
echo

run_gui_smoke "裸命令 sudo xclock" sudo xclock

if [ "$(id -u)" -eq 0 ]; then
    /usr/local/bin/x11-root-sync
    export XAUTHORITY=/root/.Xauthority
    run_gui_smoke "root xclock" xclock
else
    SRC_XAUTH="${XAUTHORITY:-$HOME/.Xauthority}"
    sudo env DISPLAY="$DISPLAY" XAUTHORITY_SRC="$SRC_XAUTH" /usr/local/bin/x11-root-sync
    run_gui_smoke "x11-root-run xclock" /usr/local/bin/x11-root-run xclock
fi

echo "==== 磁盘工具安装状态，仅检查，不启动 ===="
if command -v gparted >/dev/null 2>&1; then echo "[OK] gparted 已安装：$(command -v gparted)"; else echo "[WARN] gparted 未安装或不可用。"; fi
if command -v gnome-disks >/dev/null 2>&1; then echo "[OK] gnome-disks 已安装：$(command -v gnome-disks)"; else echo "[WARN] gnome-disks 未安装或不可用。"; fi
echo

echo "==== xlock 安装状态，仅检查，不启动 ===="
if command -v xlock >/dev/null 2>&1; then echo "[OK] xlock 已安装：$(command -v xlock)"; else echo "[WARN] xlock 未安装或不可用。一般测试 X11 用 xclock 即可。"; fi
echo

echo "[OK] X11 安全测试完成。"
X11_TEST
run_root chmod +x /usr/local/bin/x11-test
ok "x11-test 安装完成。"

info "正在配置 root shell 自动使用 /root/.Xauthority..."
ROOT_BLOCK='if [ "$(id -u)" = "0" ] && [ -n "${DISPLAY:-}" ] && command -v /usr/local/bin/x11-root-sync >/dev/null 2>&1; then
    if [ -n "${XAUTHORITY:-}" ] && [ "$XAUTHORITY" != "/root/.Xauthority" ]; then
        XAUTHORITY_SRC="$XAUTHORITY" /usr/local/bin/x11-root-sync >/dev/null 2>&1 || true
    else
        /usr/local/bin/x11-root-sync >/dev/null 2>&1 || true
    fi
    export XAUTHORITY=/root/.Xauthority
fi'
append_managed_block /root/.bashrc '# >>> x11-root-auto-sync >>>' '# <<< x11-root-auto-sync <<<' "$ROOT_BLOCK"
ok "root shell X11 授权配置完成。"

if [ "${SCRIPT_LANG:-en}" = "zh" ]; then
    cat <<'FINAL_MESSAGE'

============================================================
Ubuntu Server X11 Forwarding Setup v1.0.0
配置完成
============================================================

服务器端 X11 转发环境已配置完成。

后续操作：

1. 请确认 Windows 侧已启动 Xmanager、VcXsrv 或 Xming。

2. 请确认 Xshell 会话已开启 X11 forwarding：

   连接 -> SSH -> 隧道/Tunneling -> Forward X11 connections

3. 请断开当前 SSH 会话并重新连接服务器。

4. 重新连接后，依次执行以下验证命令：

   echo "$DISPLAY"
   echo "$XAUTHORITY"
   xclock
   sudo xclock
   x11-test

预期结果：

- xclock 可以以普通用户身份正常打开。
- sudo xclock 可以以 root 权限正常打开。
- x11-test 显示 X11 验证通过。
- echo "$XAUTHORITY" 通常应指向当前用户的 .Xauthority 文件，例如：

   /home/<user>/.Xauthority

已安装命令：

   x11-test       验证普通用户、sudo 和 root 图形程序启动路径。
   x11-debug      输出 X11、sudo 和 Xauthority 诊断信息。
   x11-root-run   使用 root 权限和同步后的 X11 授权运行命令。
   xgparted       通过 x11-root-run 启动 GParted。
   xgnome-disks   通过 x11-root-run 启动 GNOME Disks。

磁盘工具说明：

- gparted 和 gnome-disks 已安装。
- x11-test 只执行安全图形测试，不会启动磁盘管理工具。
- 使用磁盘管理工具前，请先确认目标磁盘和分区名称。

故障排查：

- 如果 DISPLAY 为空，请确认 Xshell 已开启 X11 forwarding，并重新连接 SSH。
- 如果 sudo xclock 失败，请执行：

   x11-debug

- 如果当前 shell 是脚本执行前已经打开的旧会话，可以重新连接 SSH，或临时执行：

   export XAUTHORITY="$HOME/.Xauthority"

============================================================

FINAL_MESSAGE
else
    cat <<'FINAL_MESSAGE'

============================================================
Ubuntu Server X11 Forwarding Setup v1.0.0
Setup completed
============================================================

Server-side X11 forwarding has been configured.

Next steps:

1. Make sure Xmanager, VcXsrv, or Xming is running on Windows.

2. Make sure X11 forwarding is enabled in your Xshell session:

   Connection -> SSH -> Tunneling -> Forward X11 connections

3. Disconnect the current SSH session and reconnect to the server.

4. After reconnecting, run these verification commands:

   echo "$DISPLAY"
   echo "$XAUTHORITY"
   xclock
   sudo xclock
   x11-test

Expected results:

- xclock opens correctly as the normal user.
- sudo xclock opens correctly as root.
- x11-test reports that X11 validation passed.
- echo "$XAUTHORITY" usually points to the current user's .Xauthority file, for example:

   /home/<user>/.Xauthority

Installed commands:

   x11-test       Tests normal-user, sudo, and root GUI startup paths.
   x11-debug      Prints X11, sudo, and Xauthority diagnostic information.
   x11-root-run   Runs a command as root with synchronized X11 authorization.
   xgparted       Starts GParted through x11-root-run.
   xgnome-disks   Starts GNOME Disks through x11-root-run.

Disk tool notes:

- gparted and gnome-disks have been installed.
- x11-test only runs safe GUI tests; it does not start disk management tools.
- Before using disk management tools, confirm the target disk and partition names.

Troubleshooting:

- If DISPLAY is empty, make sure Xshell X11 forwarding is enabled and reconnect SSH.
- If sudo xclock fails, run:

   x11-debug

- If this shell was already open before the script ran, reconnect SSH or temporarily run:

   export XAUTHORITY="$HOME/.Xauthority"

============================================================

FINAL_MESSAGE
fi
