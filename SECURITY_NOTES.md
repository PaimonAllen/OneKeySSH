# SECURITY_NOTES V1.0.0

## English

### Recommended SSH key workflow

OneKeySSH uses this safer workflow:

```text
Generate the private key locally.
Upload only the public key.
Never copy the private key to the server.
```

### Repeat-run behavior

If `~/.ssh/config` already contains a matching `HostName`/IP and `User`, the script only tests the existing configuration and does not create duplicate keys.

This prevents:

```text
uncontrolled key sprawl
messy authorized_keys files
unclear IdentityFile mapping
hiding actual network or authentication errors by generating another key
```

### Language behavior

The scripts ask for language before the rest of the setup flow starts:

```text
Choose language / 选择语言 ([en]/zh):
```

English is the default. Press `Enter` to continue in English, or type `zh` for Chinese.

### Server-side hardening

After key login works, consider hardening the SSH server:

```sshconfig
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
```

If you control access by group:

```sshconfig
AllowGroups lab-ssh
```

Then run:

```bash
sudo groupadd -f lab-ssh
sudo usermod -aG lab-ssh <user>
sudo sshd -t
sudo systemctl reload ssh
```

Keep one terminal logged in while testing new SSH settings.

---

## 中文

### 推荐的 SSH 密钥流程

OneKeySSH 使用更安全的流程：

```text
本地生成私钥。
只上传公钥。
永远不要把私钥复制到服务器。
```

### 重复执行行为

如果 `~/.ssh/config` 已经包含匹配的 `HostName`/IP 和 `User`，脚本只会测试现有配置，不会创建重复密钥。

这样可以避免：

```text
密钥无控制地增多
authorized_keys 文件混乱
IdentityFile 映射不清晰
通过不断生成新 key 掩盖真正的网络或认证问题
```

### 语言行为

脚本会在其他设置流程开始前先选择语言：

```text
Choose language / 选择语言 ([en]/zh):
```

默认语言是英文。直接按 `Enter` 使用英文，输入 `zh` 使用中文。

### 服务器端加固

密钥登录可用后，可以考虑加固 SSH 服务端：

```sshconfig
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
```

如果通过组控制访问：

```sshconfig
AllowGroups lab-ssh
```

然后运行：

```bash
sudo groupadd -f lab-ssh
sudo usermod -aG lab-ssh <user>
sudo sshd -t
sudo systemctl reload ssh
```

测试新的 SSH 设置时，请保留一个已经登录的终端。
