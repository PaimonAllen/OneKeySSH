# init-ssh-key-windows-native-v3.1.ps1
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

    Write-Info "Setting strict Windows permission on private key..."

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

        Write-Info "Testing existing SSH config alias: $alias"

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
        Write-Warn "SSH alias '$Alias' already exists. Config block will not be duplicated."
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
    Write-Ok "SSH config updated: $ConfigPath"
}

function New-RemoteTempPubName {
    param([string]$KeyName)
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $rand = Get-Random -Minimum 10000 -Maximum 99999
    return ".tmp_$(Get-SafeName $KeyName)_${stamp}_${rand}.pub"
}

Clear-Host

Write-Host ""
Write-Host "============================================================" -ForegroundColor DarkCyan
Write-Host " Native Windows OpenSSH Key Initializer v3.1" -ForegroundColor Cyan
Write-Host " Repeat-run safe: configured IP/user = test only" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor DarkCyan
Write-Host ""

Write-Warn "This script uses only Windows built-in OpenSSH."
Write-Warn "It cannot auto-fill SSH password. Type the remote password when prompted."
Write-Warn "If the same IP/user is already configured, this script will only test it."
Write-Host ""

foreach ($cmd in @("ssh.exe", "scp.exe", "ssh-keygen.exe")) {
    if (-not (Test-CommandExists $cmd)) {
        Fail "$cmd not found. Enable Windows OpenSSH Client first."
    }
    Write-Ok "Found $cmd"
}

$ServerIP = Read-Host "Server IP or hostname"
if ([string]::IsNullOrWhiteSpace($ServerIP)) {
    Fail "Server IP cannot be empty."
}

$RemoteUser = Read-Host "Remote Linux user"
if ([string]::IsNullOrWhiteSpace($RemoteUser)) {
    Fail "Remote user cannot be empty."
}

$LocalSshDir = Join-Path $env:USERPROFILE ".ssh"
$ConfigPath = Join-Path $LocalSshDir "config"

if (-not (Test-Path $LocalSshDir)) {
    New-Item -ItemType Directory -Force -Path $LocalSshDir | Out-Null
    Write-Ok "Created local SSH directory: $LocalSshDir"
}

if (-not (Test-Path $ConfigPath)) {
    New-Item -ItemType File -Force -Path $ConfigPath | Out-Null
}

Write-Host ""
Write-Info "Step 1: Checking whether this IP/user is already configured..."

$matchingAliases = @(Find-MatchingAliases -ConfigPath $ConfigPath -ServerIP $ServerIP -RemoteUser $RemoteUser)

if ($matchingAliases.Length -gt 0) {
    Write-Ok "Existing SSH config found for HostName/IP='$ServerIP', User='$RemoteUser'."
    Write-Warn "Repeat-run mode: this script will only test the existing configuration and will not generate a duplicate key."

    Write-Host "Matched aliases:" -ForegroundColor Gray
    foreach ($a in $matchingAliases) {
        Write-Host "  - $a" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Info "Checking TCP connectivity to ${ServerIP}:22..."

    if (-not (Test-TcpPort -HostName $ServerIP -Port 22 -TimeoutMs 5000)) {
        Write-Err "Network/port test failed: cannot reach ${ServerIP}:22."
        Write-Host ""
        Write-Warn "This is likely a network/port issue, not a key issue."
        Write-Warn "Possible causes:"
        Write-Warn "  1. Wrong IP or server is offline."
        Write-Warn "  2. SSH service is not listening on port 22."
        Write-Warn "  3. Firewall blocks port 22."
        Write-Warn "  4. VPN/LAN route is missing."
        Write-Warn "  5. Cloudflare Tunnel / port forwarding is not active, if you use one."
        exit 3
    }

    Write-Ok "TCP port 22 is reachable."

    $test = Test-ExistingAliases -Aliases $matchingAliases -RemoteUser $RemoteUser

    if ($test.Ok) {
        Write-Ok "Existing SSH key/config login succeeded."
        Write-Host ""
        Write-Host "Use:" -ForegroundColor Cyan
        Write-Host "ssh $($test.Alias)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "============================================================" -ForegroundColor DarkCyan
        Write-Host " DONE - existing config is healthy" -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor DarkCyan
        exit 0
    }

    Write-Err "TCP port is reachable, but existing SSH key/config login failed."
    Write-Host ""
    Write-Warn "This is probably NOT a network problem."
    Write-Warn "Likely causes:"
    Write-Warn "  1. Local IdentityFile path is wrong or private key is missing."
    Write-Warn "  2. Remote ~/.ssh/authorized_keys does not contain the matching public key."
    Write-Warn "  3. Remote ~/.ssh or authorized_keys permissions are wrong."
    Write-Warn "  4. sshd_config restricts this user through AllowUsers/AllowGroups/DenyUsers."
    Write-Warn "  5. Remote user is wrong or locked."
    Write-Host ""

    foreach ($r in @($test.Results)) {
        Write-Host "----- Test alias: $($r.Alias), exit=$($r.Code) -----" -ForegroundColor DarkGray
        Write-Host $r.Output -ForegroundColor DarkGray
    }

    exit 4
}

Write-Ok "No existing SSH config found for this IP/user."
Write-Info "New initialization mode: full flow will be executed."

Write-Host ""
Write-Info "Step 2/8: Checking TCP connectivity to ${ServerIP}:22..."

if (-not (Test-TcpPort -HostName $ServerIP -Port 22 -TimeoutMs 5000)) {
    Write-Err "Cannot reach ${ServerIP}:22."
    Write-Warn "Stop here because this is a network/port issue."
    Write-Warn "Check IP, server power state, sshd status, firewall, VPN/LAN route, or tunnel."
    exit 3
}

Write-Ok "TCP port 22 is reachable."

Write-Host ""
Write-Info "Step 3/8: Testing password SSH connection..."
Write-Warn "You will be asked to type the remote user's SSH password now."

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
    Write-Err "Password SSH connection failed."
    Write-Host ""
    Write-Host ($PasswordTestOutput -join "`n") -ForegroundColor DarkGray
    Write-Host ""
    Write-Warn "Port 22 is reachable, so this is more likely an SSH login/authentication/server-policy issue."
    Fail "Cannot continue. Check username, password, PasswordAuthentication, AllowUsers/AllowGroups, or server-side SSH policy." 5
}

Write-Ok "Password SSH connection succeeded."

$defaultKeyName = "id_ed25519_$(Get-SafeName $RemoteUser)_$(Get-SafeName $ServerIP)"

Write-Host ""
Write-Info "Step 4/8: Choose local private key name."
Write-Warn "Default: $defaultKeyName"

while ($true) {
    $KeyNameInput = Read-Host "Local key name, press Enter to use default"
    if ([string]::IsNullOrWhiteSpace($KeyNameInput)) {
        $KeyName = $defaultKeyName
    }
    else {
        $KeyName = $KeyNameInput
    }

    if ($KeyName -match '[\\/:*?"<>|\s]') {
        Write-Err "Key name cannot contain path separators, spaces, or Windows-invalid filename characters."
        continue
    }

    $PrivateKeyPath = Join-Path $LocalSshDir $KeyName
    $PublicKeyPath = "$PrivateKeyPath.pub"

    if ((Test-Path $PrivateKeyPath) -and (Test-Path $PublicKeyPath)) {
        Write-Warn "Key already exists: $PrivateKeyPath"
        $UseExisting = Read-Host "Use this existing local key? Type y to use, n to choose another name"
        if ($UseExisting -in @("y", "Y", "yes", "YES")) {
            Write-Info "Using existing local key."
            break
        }
        else {
            continue
        }
    }

    if ((Test-Path $PrivateKeyPath) -or (Test-Path $PublicKeyPath)) {
        Write-Err "Only one of private/public key files exists. Choose another key name or fix the pair manually."
        continue
    }

    Write-Info "Generating local SSH key..."
    $Comment = "$env:USERNAME@$env:COMPUTERNAME-to-$RemoteUser@$ServerIP"

    & ssh-keygen.exe `
        -t ed25519 `
        -a 100 `
        -N "" `
        -C $Comment `
        -f $PrivateKeyPath

    if ($LASTEXITCODE -ne 0) {
        Fail "ssh-keygen failed."
    }

    if (-not (Test-Path $PrivateKeyPath) -or -not (Test-Path $PublicKeyPath)) {
        Fail "Key generation failed. Key files not found."
    }

    break
}

Set-WindowsPrivateKeyPermission -KeyPath $PrivateKeyPath

Write-Ok "Local private key: $PrivateKeyPath"
Write-Ok "Local public key : $PublicKeyPath"

$RemoteTempPubName = New-RemoteTempPubName -KeyName $KeyName

Write-Host ""
Write-Info "Step 5/8: Preparing remote ~/.ssh directory..."
Write-Warn "You may be asked to type the remote user's password again."

$PrepareScript = 'umask 077; mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"; echo __REMOTE_PREPARE_DONE__'

$PrepareOutput = @(& ssh.exe `
    -o StrictHostKeyChecking=accept-new `
    "${RemoteUser}@${ServerIP}" `
    $PrepareScript 2>&1)

$PrepareCode = $LASTEXITCODE

if ($PrepareCode -ne 0 -or (($PrepareOutput -join "`n") -notmatch "__REMOTE_PREPARE_DONE__")) {
    Write-Err "Remote ~/.ssh preparation failed."
    Write-Host ""
    Write-Host ($PrepareOutput -join "`n") -ForegroundColor DarkGray
    Fail "Cannot continue. Check remote home directory permission." 6
}

Write-Ok "Remote ~/.ssh directory is ready."

Write-Host ""
Write-Info "Step 6/8: Uploading public key and appending to authorized_keys..."
Write-Warn "You may be asked to type the remote user's password."

$RemoteScpTarget = "${RemoteUser}@${ServerIP}:.ssh/${RemoteTempPubName}"

$ScpOutput = @(& scp.exe `
    -o StrictHostKeyChecking=accept-new `
    $PublicKeyPath `
    $RemoteScpTarget 2>&1)

$ScpCode = $LASTEXITCODE

if ($ScpCode -ne 0) {
    Write-Err "Public key upload by scp failed."
    Write-Host ""
    Write-Host ($ScpOutput -join "`n") -ForegroundColor DarkGray
    Fail "Cannot continue. Check scp availability, password, or remote ~/.ssh permission." 7
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
    Write-Err "Appending public key to authorized_keys failed."
    Write-Host ""
    Write-Host ($AppendOutput -join "`n") -ForegroundColor DarkGray
    Fail "Cannot continue. Check remote shell, authorized_keys permission, or disk permission." 8
}

Write-Ok "Public key appended to remote authorized_keys and permissions fixed."

Write-Host ""
Write-Info "Step 7/8: Testing key-based SSH login..."

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
    Write-Err "Key-based SSH login failed after public key upload."
    Write-Host ""
    Write-Host ($KeyTestOutput -join "`n") -ForegroundColor DarkGray
    Write-Warn "Network is reachable and password login worked, so this is probably an authorized_keys or sshd policy issue."
    Fail "Check remote ~/.ssh/authorized_keys, PubkeyAuthentication, AllowUsers/AllowGroups, and file permissions." 9
}

Write-Ok "Key-based SSH login succeeded."

Write-Host ""
Write-Info "Step 8/8: Writing SSH config alias for future repeat-run detection."

$defaultAlias = "ssh-$(Get-SafeName $RemoteUser)-$(Get-SafeName $ServerIP)"

while ($true) {
    $AliasInput = Read-Host "SSH alias, press Enter to use default '$defaultAlias', or type skip"
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
        Write-Warn "Skipped SSH config update. Repeat-run detection will not find this IP/user unless you add config manually."
        break
    }

    if ($HostAlias -match '\s') {
        Write-Err "Alias cannot contain spaces."
        continue
    }

    Add-SshConfigBlock -ConfigPath $ConfigPath -Alias $HostAlias -ServerIP $ServerIP -RemoteUser $RemoteUser -KeyName $KeyName
    break
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor DarkCyan
Write-Host " DONE - new SSH key initialized" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor DarkCyan
Write-Host ""

Write-Host "You can connect with:" -ForegroundColor Cyan
if ($null -ne $HostAlias) {
    Write-Host "ssh $HostAlias" -ForegroundColor Yellow
}
Write-Host "ssh -i `"$PrivateKeyPath`" -o IdentitiesOnly=yes ${RemoteUser}@${ServerIP}" -ForegroundColor Yellow
Write-Host ""
