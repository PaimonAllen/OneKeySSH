# SECURITY_NOTES v3.1

## Recommended SSH key workflow

This pack uses the safer workflow:

```text
Generate private key locally.
Upload public key only.
Never copy private key to the server.
```

## Repeat-run behavior

If `~/.ssh/config` already contains a matching HostName/IP and User, the script only tests the existing configuration and will not create duplicate keys.

This prevents:

```text
uncontrolled key sprawl
messy authorized_keys
unclear IdentityFile mapping
hiding actual network/authentication errors by generating yet another key
```

## Server-side hardening

After key login works, consider:

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

Then:

```bash
sudo groupadd -f lab-ssh
sudo usermod -aG lab-ssh <user>
sudo sshd -t
sudo systemctl reload ssh
```

Keep one terminal logged in while testing new SSH settings.
