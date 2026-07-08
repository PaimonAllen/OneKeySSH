# init-ssh-key-windows-native-V1.0.0.ps1
# Native Windows OpenSSH SSH-key initializer with repeat-run detection.
#
# Requirements:
#   - Windows OpenSSH Client: ssh.exe, scp.exe, ssh-keygen.exe
#   - No PuTTY, no WSL, no Git Bash, no Xshell required.
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
#   - Native Windows ssh.exe/scp.exe cannot safely auto-fill passwords from PowerShell.
#   - You will manually type the remote user's password when ssh/scp prompts.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "[ OK ] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "[ERR ] $Message" -ForegroundColor Red }

$Script:UiLanguage = "en"

function Text {
    param(
        [string]$English,
        [string]$Chinese
    )

    if ($Script:UiLanguage -eq "zh") {
        return $Chinese
    }

    return $English
}

function Select-UiLanguage {
    Write-Host ""
    $choice = Read-Host "Choose language / 选择语言 ([en]/zh)"

    if ($choice -match '^(zh|cn|chinese|中文)$') {
        $Script:UiLanguage = "zh"
    }
    else {
        $Script:UiLanguage = "en"
    }
}

function Fail {
    param([string]$Message, [int]$Code = 1)
    Write-Err $Message
    exit $Code
}

function Test-CommandExists {
    param([string]$CommandName)
    return $null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Get-SafeName {
    param([string]$Text)
    return ($Text -replace '[^A-Za-z0-9_.-]', '_')
}

function Test-ConcreteAlias {
    param([string]$Alias)
    if ([string]::IsNullOrWhiteSpace($Alias)) { return $false }
    return ($Alias -notmatch '[\*\?\!]')
}

function Test-TcpPort {
    param(
        [string]$HostName,
        [int]$Port = 22,
        [int]$TimeoutMs = 5000
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        $success = $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $success) { return $false }
        $client.EndConnect($async)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Set-WindowsPrivateKeyPermission {
    param([string]$KeyPath)

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Info (Text "Setting strict Windows permission on private key..." "正在为私钥设置严格的 Windows 权限...")

    & icacls $KeyPath /inheritance:r | Out-Null
    & icacls $KeyPath /grant:r "${identity}:F" | Out-Null

    # These groups may not exist or may have localized names on some systems.
    & icacls $KeyPath /remove "Users" "Authenticated Users" "Everyone" 2>$null | Out-Null
}

function Get-SshConfigAliases {
    param([string]$ConfigPath)

    $aliases = @()

    if (-not (Test-Path $ConfigPath)) {
        return @()
    }

    foreach ($line in Get-Content -Path $ConfigPath) {
        $trim = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim)) { continue }
        if ($trim.StartsWith("#")) { continue }

        if ($trim -match '(?i)^Host\s+(.+)$') {
            $parts = @($Matches[1] -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            foreach ($p in $parts) {
                if (Test-ConcreteAlias -Alias $p) {
                    $aliases += $p
                }
            }
        }
    }

    return @($aliases | Select-Object -Unique)
}

function Get-EffectiveSshValue {
    param(
        [string]$Alias,
        [string]$RemoteUser,
        [string]$Key
    )

    $output = @(& ssh.exe -G -l $RemoteUser $Alias 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    foreach ($line in $output) {
        if ($line -match ("(?i)^" + [Regex]::Escape($Key) + "\s+(.+)$")) {
            return $Matches[1].Trim()
        }
    }

    return $null
}

function Find-MatchingAliases {
    param(
        [string]$ConfigPath,
        [string]$ServerIP,
        [string]$RemoteUser
    )

    $matches = @()
    $aliases = @(Get-SshConfigAliases -ConfigPath $ConfigPath)

    foreach ($alias in $aliases) {
        $resolvedHost = Get-EffectiveSshValue -Alias $alias -RemoteUser $RemoteUser -Key "hostname"
        $resolvedUser = Get-EffectiveSshValue -Alias $alias -RemoteUser $RemoteUser -Key "user"

        if ($resolvedHost -eq $ServerIP -and $resolvedUser -eq $RemoteUser) {
            $matches += $alias
        }
    }

    return @($matches | Select-Object -Unique)
}

function Test-ExistingAliases {
    param(
        [string[]]$Aliases,
        [string]$RemoteUser
    )

    $results = @()

    foreach ($alias in @($Aliases)) {
        if (-not (Test-ConcreteAlias -Alias $alias)) {
            continue
        }

        Write-Info (Text "Testing existing SSH config alias: $alias" "正在测试现有 SSH config 别名：$alias")

        $out = @(& ssh.exe `
            -o ConnectTimeout=8 `
            -o ConnectionAttempts=1 `
            -o BatchMode=yes `
            -o StrictHostKeyChecking=accept-new `
            $alias `
            "echo __SSH_KEY_LOGIN_OK__; hostname; whoami" 2>&1)

        $code = $LASTEXITCODE
        $text = ($out -join "`n")

        $results += [PSCustomObject]@{
            Alias  = $alias
            Code   = $code
            Output = $text
            Ok     = ($code -eq 0 -and $text -match "__SSH_KEY_LOGIN_OK__")
        }

        if ($code -eq 0 -and $text -match "__SSH_KEY_LOGIN_OK__") {
            return [PSCustomObject]@{
                Ok      = $true
                Alias   = $alias
                Results = @($results)
            }
        }
    }

    return [PSCustomObject]@{
        Ok      = $false
        Alias   = $null
        Results = @($results)
    }
}

function Add-SshConfigBlock {
    param(
        [string]$ConfigPath,
        [string]$Alias,
        [string]$ServerIP,
        [string]$RemoteUser,
        [string]$KeyName
    )

    $existingAliases = @(Get-SshConfigAliases -ConfigPath $ConfigPath)
    if ($existingAliases -contains $Alias) {
        Write-Warn (Text "SSH alias '$Alias' already exists. Config block will not be duplicated." "SSH 别名 '$Alias' 已存在，不会重复写入配置块。")
        return
    }

    $block = @"

Host $Alias
    HostName $ServerIP
    User $RemoteUser
    IdentityFile ~/.ssh/$KeyName
    IdentitiesOnly yes
"@

    Add-Content -Path $ConfigPath -Value $block
    Write-Ok (Text "SSH config updated: $ConfigPath" "SSH config 已更新：$ConfigPath")
}

function New-RemoteTempPubName {
    param([string]$KeyName)
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $rand = Get-Random -Minimum 10000 -Maximum 99999
    return ".tmp_$(Get-SafeName $KeyName)_${stamp}_${rand}.pub"
}

Clear-Host
Select-UiLanguage

Write-Host ""
Write-Host "============================================================" -ForegroundColor DarkCyan
Write-Host (Text " Native Windows OpenSSH Key Initializer V1.0.0" " Windows 原生 OpenSSH 密钥初始化工具 V1.0.0") -ForegroundColor Cyan
Write-Host (Text " Repeat-run safe: configured IP/user = test only" " 可重复执行：已配置的 IP/用户只做检测") -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor DarkCyan
Write-Host ""

Write-Info (Text "Language: English" "语言：中文")
Write-Warn (Text "This script uses only Windows built-in OpenSSH." "此脚本仅使用 Windows 内置 OpenSSH。")
Write-Warn (Text "It cannot auto-fill SSH password. Type the remote password when prompted." "脚本无法自动填写 SSH 密码；出现提示时请手动输入远程用户密码。")
Write-Warn (Text "If the same IP/user is already configured, this script will only test it." "如果相同 IP/用户已配置，脚本只会检测现有配置。")
Write-Host ""

foreach ($cmd in @("ssh.exe", "scp.exe", "ssh-keygen.exe")) {
    if (-not (Test-CommandExists $cmd)) {
        Fail (Text "$cmd not found. Enable Windows OpenSSH Client first." "未找到 $cmd。请先启用 Windows OpenSSH Client。")
    }
    Write-Ok (Text "Found $cmd" "已找到 $cmd")
}

$ServerIP = Read-Host (Text "Server IP or hostname" "服务器 IP 或主机名")
if ([string]::IsNullOrWhiteSpace($ServerIP)) {
    Fail (Text "Server IP cannot be empty." "服务器 IP 不能为空。")
}

$RemoteUser = Read-Host (Text "Remote Linux user" "远程 Linux 用户")
if ([string]::IsNullOrWhiteSpace($RemoteUser)) {
    Fail (Text "Remote user cannot be empty." "远程用户不能为空。")
}

$LocalSshDir = Join-Path $env:USERPROFILE ".ssh"
$ConfigPath = Join-Path $LocalSshDir "config"

if (-not (Test-Path $LocalSshDir)) {
    New-Item -ItemType Directory -Force -Path $LocalSshDir | Out-Null
    Write-Ok (Text "Created local SSH directory: $LocalSshDir" "已创建本地 SSH 目录：$LocalSshDir")
}

if (-not (Test-Path $ConfigPath)) {
    New-Item -ItemType File -Force -Path $ConfigPath | Out-Null
}

Write-Host ""
Write-Info (Text "Step 1: Checking whether this IP/user is already configured..." "步骤 1：检查此 IP/用户是否已经配置...")

$matchingAliases = @(Find-MatchingAliases -ConfigPath $ConfigPath -ServerIP $ServerIP -RemoteUser $RemoteUser)

if ($matchingAliases.Length -gt 0) {
    Write-Ok (Text "Existing SSH config found for HostName/IP='$ServerIP', User='$RemoteUser'." "已找到 HostName/IP='$ServerIP'、User='$RemoteUser' 的现有 SSH 配置。")
    Write-Warn (Text "Repeat-run mode: this script will only test the existing configuration and will not generate a duplicate key." "重复执行模式：脚本只会测试现有配置，不会生成重复密钥。")

    Write-Host (Text "Matched aliases:" "匹配到的别名：") -ForegroundColor Gray
    foreach ($a in $matchingAliases) {
        Write-Host "  - $a" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Info (Text "Checking TCP connectivity to ${ServerIP}:22..." "正在检查到 ${ServerIP}:22 的 TCP 连接...")

    if (-not (Test-TcpPort -HostName $ServerIP -Port 22 -TimeoutMs 5000)) {
        Write-Err (Text "Network/port test failed: cannot reach ${ServerIP}:22." "网络/端口测试失败：无法连接 ${ServerIP}:22。")
        Write-Host ""
        Write-Warn (Text "This is likely a network/port issue, not a key issue." "这通常是网络/端口问题，不是密钥问题。")
        Write-Warn (Text "Possible causes:" "可能原因：")
        Write-Warn (Text "  1. Wrong IP or server is offline." "  1. IP 错误或服务器离线。")
        Write-Warn (Text "  2. SSH service is not listening on port 22." "  2. SSH 服务没有监听 22 端口。")
        Write-Warn (Text "  3. Firewall blocks port 22." "  3. 防火墙阻止了 22 端口。")
        Write-Warn (Text "  4. VPN/LAN route is missing." "  4. VPN/LAN 路由不可达。")
        Write-Warn (Text "  5. Cloudflare Tunnel / port forwarding is not active, if you use one." "  5. 如果使用 Cloudflare Tunnel/端口转发，它可能未生效。")
        exit 3
    }

    Write-Ok (Text "TCP port 22 is reachable." "TCP 22 端口可达。")

    $test = Test-ExistingAliases -Aliases $matchingAliases -RemoteUser $RemoteUser

    if ($test.Ok) {
        Write-Ok (Text "Existing SSH key/config login succeeded." "现有 SSH 密钥/配置登录成功。")
        Write-Host ""
        Write-Host (Text "Use:" "使用：") -ForegroundColor Cyan
        Write-Host "ssh $($test.Alias)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "============================================================" -ForegroundColor DarkCyan
        Write-Host (Text " DONE - existing config is healthy" " 完成 - 现有配置正常") -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor DarkCyan
        exit 0
    }

    Write-Err (Text "TCP port is reachable, but existing SSH key/config login failed." "TCP 端口可达，但现有 SSH 密钥/配置登录失败。")
    Write-Host ""
    Write-Warn (Text "This is probably NOT a network problem." "这通常不是网络问题。")
    Write-Warn (Text "Likely causes:" "可能原因：")
    Write-Warn (Text "  1. Local IdentityFile path is wrong or private key is missing." "  1. 本地 IdentityFile 路径错误或私钥缺失。")
    Write-Warn (Text "  2. Remote ~/.ssh/authorized_keys does not contain the matching public key." "  2. 远程 ~/.ssh/authorized_keys 没有对应公钥。")
    Write-Warn (Text "  3. Remote ~/.ssh or authorized_keys permissions are wrong." "  3. 远程 ~/.ssh 或 authorized_keys 权限错误。")
    Write-Warn (Text "  4. sshd_config restricts this user through AllowUsers/AllowGroups/DenyUsers." "  4. sshd_config 通过 AllowUsers/AllowGroups/DenyUsers 限制了该用户。")
    Write-Warn (Text "  5. Remote user is wrong or locked." "  5. 远程用户错误或已锁定。")
    Write-Host ""

    foreach ($r in @($test.Results)) {
        Write-Host (Text "----- Test alias: $($r.Alias), exit=$($r.Code) -----" "----- 测试别名：$($r.Alias)，退出码=$($r.Code) -----") -ForegroundColor DarkGray
        Write-Host $r.Output -ForegroundColor DarkGray
    }

    exit 4
}

Write-Ok (Text "No existing SSH config found for this IP/user." "未找到此 IP/用户的现有 SSH 配置。")
Write-Info (Text "New initialization mode: full flow will be executed." "新初始化模式：将执行完整流程。")

Write-Host ""
Write-Info (Text "Step 2/8: Checking TCP connectivity to ${ServerIP}:22..." "步骤 2/8：检查到 ${ServerIP}:22 的 TCP 连接...")

if (-not (Test-TcpPort -HostName $ServerIP -Port 22 -TimeoutMs 5000)) {
    Write-Err (Text "Cannot reach ${ServerIP}:22." "无法连接 ${ServerIP}:22。")
    Write-Warn (Text "Stop here because this is a network/port issue." "此处停止，因为这是网络/端口问题。")
    Write-Warn (Text "Check IP, server power state, sshd status, firewall, VPN/LAN route, or tunnel." "请检查 IP、服务器电源状态、sshd 状态、防火墙、VPN/LAN 路由或隧道。")
    exit 3
}

Write-Ok (Text "TCP port 22 is reachable." "TCP 22 端口可达。")

Write-Host ""
Write-Info (Text "Step 3/8: Testing password SSH connection..." "步骤 3/8：测试密码 SSH 连接...")
Write-Warn (Text "You will be asked to type the remote user's SSH password now." "现在会提示你输入远程用户的 SSH 密码。")

$PasswordTestOutput = @(& ssh.exe `
    -o ConnectTimeout=8 `
    -o StrictHostKeyChecking=accept-new `
    -o PreferredAuthentications=password `
    -o PubkeyAuthentication=no `
    -o NumberOfPasswordPrompts=3 `
    "${RemoteUser}@${ServerIP}" `
    "echo __SSH_PASSWORD_LOGIN_OK__; hostname; whoami" 2>&1)

$PasswordTestCode = $LASTEXITCODE

if ($PasswordTestCode -ne 0 -or (($PasswordTestOutput -join "`n") -notmatch "__SSH_PASSWORD_LOGIN_OK__")) {
    Write-Err (Text "Password SSH connection failed." "密码 SSH 连接失败。")
    Write-Host ""
    Write-Host ($PasswordTestOutput -join "`n") -ForegroundColor DarkGray
    Write-Host ""
    Write-Warn (Text "Port 22 is reachable, so this is more likely an SSH login/authentication/server-policy issue." "22 端口可达，因此更可能是 SSH 登录/认证/服务器策略问题。")
    Fail (Text "Cannot continue. Check username, password, PasswordAuthentication, AllowUsers/AllowGroups, or server-side SSH policy." "无法继续。请检查用户名、密码、PasswordAuthentication、AllowUsers/AllowGroups 或服务器端 SSH 策略。") 5
}

Write-Ok (Text "Password SSH connection succeeded." "密码 SSH 连接成功。")

$defaultKeyName = "id_ed25519_$(Get-SafeName $RemoteUser)_$(Get-SafeName $ServerIP)"

Write-Host ""
Write-Info (Text "Step 4/8: Choose local private key name." "步骤 4/8：选择本地私钥名称。")
Write-Warn (Text "Default: $defaultKeyName" "默认值：$defaultKeyName")

while ($true) {
    $KeyNameInput = Read-Host (Text "Local key name, press Enter to use default" "本地密钥名称，按 Enter 使用默认值")
    if ([string]::IsNullOrWhiteSpace($KeyNameInput)) {
        $KeyName = $defaultKeyName
    }
    else {
        $KeyName = $KeyNameInput
    }

    if ($KeyName -match '[\\/:*?"<>|\s]') {
        Write-Err (Text "Key name cannot contain path separators, spaces, or Windows-invalid filename characters." "密钥名称不能包含路径分隔符、空格或 Windows 文件名非法字符。")
        continue
    }

    $PrivateKeyPath = Join-Path $LocalSshDir $KeyName
    $PublicKeyPath = "$PrivateKeyPath.pub"

    if ((Test-Path $PrivateKeyPath) -and (Test-Path $PublicKeyPath)) {
        Write-Warn (Text "Key already exists: $PrivateKeyPath" "密钥已存在：$PrivateKeyPath")
        $UseExisting = Read-Host (Text "Use this existing local key? Type y to use, n to choose another name" "使用这个现有本地密钥？输入 y 使用，输入 n 重新选择")
        if ($UseExisting -in @("y", "Y", "yes", "YES")) {
            Write-Info (Text "Using existing local key." "将使用现有本地密钥。")
            break
        }
        else {
            continue
        }
    }

    if ((Test-Path $PrivateKeyPath) -or (Test-Path $PublicKeyPath)) {
        Write-Err (Text "Only one of private/public key files exists. Choose another key name or fix the pair manually." "私钥/公钥文件只有一个存在。请换一个密钥名，或手动修复这对文件。")
        continue
    }

    Write-Info (Text "Generating local SSH key..." "正在生成本地 SSH 密钥...")
    $Comment = "$env:USERNAME@$env:COMPUTERNAME-to-$RemoteUser@$ServerIP"

    & ssh-keygen.exe `
        -t ed25519 `
        -a 100 `
        -N "" `
        -C $Comment `
        -f $PrivateKeyPath

    if ($LASTEXITCODE -ne 0) {
        Fail (Text "ssh-keygen failed." "ssh-keygen 执行失败。")
    }

    if (-not (Test-Path $PrivateKeyPath) -or -not (Test-Path $PublicKeyPath)) {
        Fail (Text "Key generation failed. Key files not found." "密钥生成失败，未找到密钥文件。")
    }

    break
}

Set-WindowsPrivateKeyPermission -KeyPath $PrivateKeyPath

Write-Ok (Text "Local private key: $PrivateKeyPath" "本地私钥：$PrivateKeyPath")
Write-Ok (Text "Local public key : $PublicKeyPath" "本地公钥：$PublicKeyPath")

$RemoteTempPubName = New-RemoteTempPubName -KeyName $KeyName

Write-Host ""
Write-Info (Text "Step 5/8: Preparing remote ~/.ssh directory..." "步骤 5/8：准备远程 ~/.ssh 目录...")
Write-Warn (Text "You may be asked to type the remote user's password again." "可能会再次要求你输入远程用户密码。")

$PrepareScript = 'umask 077; mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"; echo __REMOTE_PREPARE_DONE__'

$PrepareOutput = @(& ssh.exe `
    -o StrictHostKeyChecking=accept-new `
    "${RemoteUser}@${ServerIP}" `
    $PrepareScript 2>&1)

$PrepareCode = $LASTEXITCODE

if ($PrepareCode -ne 0 -or (($PrepareOutput -join "`n") -notmatch "__REMOTE_PREPARE_DONE__")) {
    Write-Err (Text "Remote ~/.ssh preparation failed." "远程 ~/.ssh 准备失败。")
    Write-Host ""
    Write-Host ($PrepareOutput -join "`n") -ForegroundColor DarkGray
    Fail (Text "Cannot continue. Check remote home directory permission." "无法继续。请检查远程 home 目录权限。") 6
}

Write-Ok (Text "Remote ~/.ssh directory is ready." "远程 ~/.ssh 目录已准备好。")

Write-Host ""
Write-Info (Text "Step 6/8: Uploading public key and appending to authorized_keys..." "步骤 6/8：上传公钥并追加到 authorized_keys...")
Write-Warn (Text "You may be asked to type the remote user's password." "可能会要求你输入远程用户密码。")

$RemoteScpTarget = "${RemoteUser}@${ServerIP}:.ssh/${RemoteTempPubName}"

$ScpOutput = @(& scp.exe `
    -o StrictHostKeyChecking=accept-new `
    $PublicKeyPath `
    $RemoteScpTarget 2>&1)

$ScpCode = $LASTEXITCODE

if ($ScpCode -ne 0) {
    Write-Err (Text "Public key upload by scp failed." "通过 scp 上传公钥失败。")
    Write-Host ""
    Write-Host ($ScpOutput -join "`n") -ForegroundColor DarkGray
    Fail (Text "Cannot continue. Check scp availability, password, or remote ~/.ssh permission." "无法继续。请检查 scp 可用性、密码或远程 ~/.ssh 权限。") 7
}

$AppendScript = @'
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
'@

$AppendOutput = @($AppendScript | & ssh.exe `
    -o StrictHostKeyChecking=accept-new `
    "${RemoteUser}@${ServerIP}" `
    "sh -s -- $RemoteTempPubName" 2>&1)

$AppendCode = $LASTEXITCODE

if ($AppendCode -ne 0 -or (($AppendOutput -join "`n") -notmatch "__REMOTE_DONE__")) {
    Write-Err (Text "Appending public key to authorized_keys failed." "追加公钥到 authorized_keys 失败。")
    Write-Host ""
    Write-Host ($AppendOutput -join "`n") -ForegroundColor DarkGray
    Fail (Text "Cannot continue. Check remote shell, authorized_keys permission, or disk permission." "无法继续。请检查远程 shell、authorized_keys 权限或磁盘权限。") 8
}

Write-Ok (Text "Public key appended to remote authorized_keys and permissions fixed." "公钥已追加到远程 authorized_keys，权限已修正。")

Write-Host ""
Write-Info (Text "Step 7/8: Testing key-based SSH login..." "步骤 7/8：测试密钥 SSH 登录...")

$KeyTestOutput = @(& ssh.exe `
    -i $PrivateKeyPath `
    -o ConnectTimeout=8 `
    -o ConnectionAttempts=1 `
    -o IdentitiesOnly=yes `
    -o BatchMode=yes `
    -o StrictHostKeyChecking=accept-new `
    "${RemoteUser}@${ServerIP}" `
    "echo __SSH_KEY_LOGIN_OK__; hostname; whoami" 2>&1)

$KeyTestCode = $LASTEXITCODE

if ($KeyTestCode -ne 0 -or (($KeyTestOutput -join "`n") -notmatch "__SSH_KEY_LOGIN_OK__")) {
    Write-Err (Text "Key-based SSH login failed after public key upload." "公钥上传后，密钥 SSH 登录仍然失败。")
    Write-Host ""
    Write-Host ($KeyTestOutput -join "`n") -ForegroundColor DarkGray
    Write-Warn (Text "Network is reachable and password login worked, so this is probably an authorized_keys or sshd policy issue." "网络可达且密码登录成功，因此这通常是 authorized_keys 或 sshd 策略问题。")
    Fail (Text "Check remote ~/.ssh/authorized_keys, PubkeyAuthentication, AllowUsers/AllowGroups, and file permissions." "请检查远程 ~/.ssh/authorized_keys、PubkeyAuthentication、AllowUsers/AllowGroups 和文件权限。") 9
}

Write-Ok (Text "Key-based SSH login succeeded." "密钥 SSH 登录成功。")

Write-Host ""
Write-Info (Text "Step 8/8: Writing SSH config alias for future repeat-run detection." "步骤 8/8：写入 SSH config 别名，用于后续重复执行检测。")

$defaultAlias = "ssh-$(Get-SafeName $RemoteUser)-$(Get-SafeName $ServerIP)"

while ($true) {
    $AliasInput = Read-Host (Text "SSH alias, press Enter to use default '$defaultAlias', or type skip" "SSH 别名，按 Enter 使用默认值 '$defaultAlias'，或输入 skip 跳过")
    if ([string]::IsNullOrWhiteSpace($AliasInput)) {
        $HostAlias = $defaultAlias
    }
    elseif ($AliasInput -eq "skip") {
        $HostAlias = $null
    }
    else {
        $HostAlias = $AliasInput
    }

    if ($null -eq $HostAlias) {
        Write-Warn (Text "Skipped SSH config update. Repeat-run detection will not find this IP/user unless you add config manually." "已跳过 SSH config 更新。除非你手动添加配置，否则重复执行检测找不到此 IP/用户。")
        break
    }

    if ($HostAlias -match '\s') {
        Write-Err (Text "Alias cannot contain spaces." "别名不能包含空格。")
        continue
    }

    Add-SshConfigBlock -ConfigPath $ConfigPath -Alias $HostAlias -ServerIP $ServerIP -RemoteUser $RemoteUser -KeyName $KeyName
    break
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor DarkCyan
Write-Host (Text " DONE - new SSH key initialized" " 完成 - 新 SSH 密钥已初始化") -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor DarkCyan
Write-Host ""

Write-Host (Text "You can connect with:" "你可以这样连接：") -ForegroundColor Cyan
if ($null -ne $HostAlias) {
    Write-Host "ssh $HostAlias" -ForegroundColor Yellow
}
Write-Host "ssh -i `"$PrivateKeyPath`" -o IdentitiesOnly=yes ${RemoteUser}@${ServerIP}" -ForegroundColor Yellow
Write-Host ""
