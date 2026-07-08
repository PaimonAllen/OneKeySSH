# Native SSH Key Initializer Pack V1.0.0

## English

OneKeySSH is a native OpenSSH helper for setting up key-based SSH login from a local Windows or Linux machine to a remote Linux account.

The pack contains:

```text
init-ssh-key-windows.ps1
init-ssh-key-linux.sh
README.md
SECURITY_NOTES.md
```

### Language support

- The scripts ask you to choose a language before the setup flow starts.
- English is the default language. Press `Enter` at the language prompt to continue in English.
- Chinese is available by entering `zh`.
- Markdown documentation is provided in both English and Chinese.

### Repeat-run behavior

For the same:

```text
Server IP / HostName
+
Remote Linux user
```

If `~/.ssh/config` already contains a matching entry, the script does not generate a new key.

It will:

```text
1. Test TCP port 22.
2. If port 22 is unreachable, report a network/port/firewall/sshd/VPN/tunnel issue.
3. If port 22 is reachable, test the existing SSH config/key.
4. If key login succeeds, exit successfully.
5. If key login fails, report an authentication/configuration issue.
6. Avoid generating duplicate keys for the same configured IP/user.
```

If no matching configuration exists, the script runs the full initialization flow:

```text
1. Choose language. Default: English.
2. Check TCP port 22.
3. Test password-based SSH login.
4. Generate a local ed25519 key.
5. Upload only the public key to remote ~/.ssh/authorized_keys.
6. Set remote SSH file permissions.
7. Test key-based login.
8. Write an alias to ~/.ssh/config.
```

### Windows usage

Run in PowerShell:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\init-ssh-key-windows.ps1
```

Language prompt:

```text
Choose language / 选择语言 ([en]/zh):
```

Press `Enter` for English, or type `zh` for Chinese.

Input example:

```text
Server IP or hostname: <server-host>
Remote Linux user: <remote-user>
```

Native Windows OpenSSH cannot safely auto-fill passwords from PowerShell. Type the remote user's password when `ssh` or `scp` prompts.

After setup, connect with:

```powershell
ssh ssh-<remote-user>-<server-host>
```

Or:

```powershell
ssh -i "$env:USERPROFILE\.ssh\id_ed25519_<remote-user>_<server-host>" -o IdentitiesOnly=yes <remote-user>@<server-host>
```

### Linux usage

Run:

```bash
chmod +x init-ssh-key-linux.sh
./init-ssh-key-linux.sh
```

Language prompt:

```text
Choose language / 选择语言 ([en]/zh):
```

Press `Enter` for English, or type `zh` for Chinese.

Input example:

```text
Server IP or hostname: <server-host>
Remote Linux user: <remote-user>
```

After setup, connect with:

```bash
ssh ssh-<remote-user>-<server-host>
```

Or:

```bash
ssh -i ~/.ssh/id_ed25519_<remote-user>_<server-host> -o IdentitiesOnly=yes <remote-user>@<server-host>
```

### Network vs authentication failures

If port 22 is unreachable, the script reports:

```text
Network/port test failed: cannot reach <IP>:22
```

Common causes:

```text
Wrong IP
Server is offline
sshd is not running
Firewall blocks port 22
VPN/LAN route is missing
Cloudflare Tunnel or port forwarding is inactive
```

This is not a key problem.

If port 22 is reachable but key login fails, the script reports:

```text
TCP port is reachable, but existing SSH key/config login failed.
```

Common causes:

```text
Local IdentityFile path is wrong
Private key file is missing
Remote authorized_keys does not contain the matching public key
Remote ~/.ssh permissions are wrong
sshd_config restricts the user or group
Remote user is wrong or locked
```

This is not a network problem.

### Security principle

The scripts use this workflow:

```text
Generate the private key locally.
Upload only the public key.
Never move the private key off the local machine.
```

Do not share one private key across multiple people. For a lab or team, prefer:

```text
One person = one Linux user = one SSH public key
```

---

## 中文

OneKeySSH 是一个原生 OpenSSH 辅助工具，用于从本地 Windows 或 Linux 机器向远程 Linux 账户配置 SSH 密钥免密登录。

本包包含：

```text
init-ssh-key-windows.ps1
init-ssh-key-linux.sh
README.md
SECURITY_NOTES.md
```

### 语言支持

- 脚本启动后会先选择语言，再进入后续配置流程。
- 默认语言是英文。在语言提示处直接按 `Enter` 会使用英文。
- 输入 `zh` 可使用中文。
- Markdown 文档同时提供英文版和中文版。

### 重复执行逻辑

对于同一个：

```text
Server IP / HostName
+
Remote Linux user
```

如果本机 `~/.ssh/config` 已经有匹配项，脚本不会再生成新 key。

它会：

```text
1. 测试 TCP 22 端口是否可达。
2. 如果 22 不通，报告网络/端口/防火墙/sshd/VPN/隧道问题。
3. 如果 22 可达，测试已有 SSH config/key。
4. 如果 key 登录成功，直接成功退出。
5. 如果 key 登录失败，报告认证/配置问题。
6. 避免为同一个已配置 IP/用户生成重复 key。
```

如果没有匹配配置，则执行完整初始化流程：

```text
1. 选择语言。默认：英文。
2. 检查 TCP 22 端口。
3. 测试密码 SSH 登录。
4. 本地生成 ed25519 key。
5. 只上传公钥到远程 ~/.ssh/authorized_keys。
6. 设置远程 SSH 文件权限。
7. 测试密钥登录。
8. 写入 ~/.ssh/config 别名。
```

### Windows 使用方法

在 PowerShell 中运行：

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\init-ssh-key-windows.ps1
```

语言提示：

```text
Choose language / 选择语言 ([en]/zh):
```

直接按 `Enter` 使用英文，输入 `zh` 使用中文。

输入示例：

```text
Server IP or hostname: <server-host>
Remote Linux user: <remote-user>
```

Windows 原生 OpenSSH 不能安全地由 PowerShell 自动代填密码。出现 `ssh` 或 `scp` 提示时，请手动输入远程用户密码。

完成后可用：

```powershell
ssh ssh-<remote-user>-<server-host>
```

或者：

```powershell
ssh -i "$env:USERPROFILE\.ssh\id_ed25519_<remote-user>_<server-host>" -o IdentitiesOnly=yes <remote-user>@<server-host>
```

### Linux 使用方法

运行：

```bash
chmod +x init-ssh-key-linux.sh
./init-ssh-key-linux.sh
```

语言提示：

```text
Choose language / 选择语言 ([en]/zh):
```

直接按 `Enter` 使用英文，输入 `zh` 使用中文。

输入示例：

```text
Server IP or hostname: <server-host>
Remote Linux user: <remote-user>
```

完成后可用：

```bash
ssh ssh-<remote-user>-<server-host>
```

或者：

```bash
ssh -i ~/.ssh/id_ed25519_<remote-user>_<server-host> -o IdentitiesOnly=yes <remote-user>@<server-host>
```

### 网络问题和认证问题如何区分

如果端口 22 不通，脚本会提示：

```text
Network/port test failed: cannot reach <IP>:22
```

常见原因：

```text
IP 错
服务器离线
sshd 未运行
防火墙拦截 22 端口
VPN/LAN 路由不通
Cloudflare Tunnel 或端口转发未生效
```

这不是 key 问题。

如果端口 22 可达，但 key 登录失败，脚本会提示：

```text
TCP port is reachable, but existing SSH key/config login failed.
```

常见原因：

```text
本地 IdentityFile 路径错误
私钥文件不存在
远程 authorized_keys 没有对应公钥
远程 ~/.ssh 权限错误
sshd_config 限制了用户或组
远程用户错误或已锁定
```

这不是网络问题。

### 安全原则

脚本采用：

```text
本地生成私钥。
只上传公钥。
私钥永远不离开本机。
```

不要多人共用同一个私钥。课题组或团队使用时建议：

```text
一个人 = 一个 Linux 用户 = 一个 SSH 公钥
```
