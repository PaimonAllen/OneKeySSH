# Native SSH Key Initializer Pack v3.1

这个包包含：

```text
windows/init-ssh-key-windows-native-v3.1.ps1
linux/init-ssh-key-linux-native-v3.1.sh
README.md
SECURITY_NOTES.md
```

## 1. v3.1 修复点

修复 Windows PowerShell 版在 `Set-StrictMode` 下的错误：

```text
The property 'Count' cannot be found on this object.
```

原因是 PowerShell 函数只返回一个对象时，变量可能是单个 `PSCustomObject`，不是数组。v3.1 已把相关返回值全部强制转成数组，并改用 `.Length` 判断。

---

## 2. 重复执行逻辑

对于同一个：

```text
Server IP / HostName
+
Remote Linux user
```

如果本机 `~/.ssh/config` 已经有匹配项，脚本不会再生成新 key。

它会：

```text
1. 测试 TCP 22 端口是否可达
2. 如果 22 不通：
   报告网络/端口/防火墙/sshd/VPN/隧道问题
3. 如果 22 通：
   测试已有 SSH config/key
4. 如果 key 登录成功：
   直接 OK 退出
5. 如果 key 登录失败：
   报告认证/配置问题
   不会重复生成 key
```

如果没有配置过，则执行完整初始化流程：

```text
1. 检查 TCP 22
2. 用密码测试 SSH
3. 本地生成 ed25519 key
4. 上传公钥到远程 ~/.ssh/authorized_keys
5. 设置远程权限
6. 测试免密登录
7. 写入 ~/.ssh/config
```

---

## 3. Windows 使用方法

进入目录：

```powershell
cd .\windows
```

必要时允许本地脚本运行：

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

运行：

```powershell
.\init-ssh-key-windows-native-v3.1.ps1
```

输入示例：

```text
Server IP or hostname: 192.168.10.120
Remote Linux user: cvpr
```

Windows 原生 OpenSSH 不能自动代填密码，中途需要你手动输入远程用户密码。

完成后可用：

```powershell
ssh ssh-cvpr-192.168.10.120
```

或者：

```powershell
ssh -i "$env:USERPROFILE\.ssh\id_ed25519_cvpr_192.168.10.120" -o IdentitiesOnly=yes cvpr@192.168.10.120
```

---

## 4. Linux 使用方法

进入目录：

```bash
cd linux
```

赋予权限：

```bash
chmod +x init-ssh-key-linux-native-v3.1.sh
```

运行：

```bash
./init-ssh-key-linux-native-v3.1.sh
```

输入示例：

```text
Server IP or hostname: 192.168.10.120
Remote Linux user: cvpr
```

完成后可用：

```bash
ssh ssh-cvpr-192.168.10.120
```

或者：

```bash
ssh -i ~/.ssh/id_ed25519_cvpr_192.168.10.120 -o IdentitiesOnly=yes cvpr@192.168.10.120
```

---

## 5. 网络问题和认证问题如何区分

### 5.1 端口 22 不通

脚本会提示：

```text
Network/port test failed: cannot reach <IP>:22
```

通常是：

```text
IP 错
服务器没开
sshd 没启动
防火墙拦截
VPN/LAN 路由不通
Cloudflare Tunnel/端口转发没通
```

这不是 key 问题。

### 5.2 端口 22 通，但 key 登录失败

脚本会提示：

```text
TCP port is reachable, but existing SSH key/config login failed.
```

通常是：

```text
本地 IdentityFile 路径错
私钥文件不存在
远程 authorized_keys 没有对应公钥
远程 ~/.ssh 权限错误
sshd_config 限制了用户或组
远程用户被锁定
```

这不是网络问题。

---

## 6. 安全原则

脚本采用：

```text
本地生成私钥
只上传公钥
私钥永远不离开本机
```

不要多人共用同一个私钥。课题组使用时建议：

```text
一个人 = 一个 Linux 用户 = 一个 SSH 公钥
```
