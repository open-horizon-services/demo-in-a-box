# Operating System Support

> **Note:** Multi-OS environments (Ubuntu 24, Fedora 41, mixed hub/agent OS) are **not supported** in this release. All VMs use Ubuntu 22.04 LTS.
>
> This guide is preserved for historical reference. Multi-OS cloud-init variants will be added in a future change.

## Current Support

| Component | Ubuntu 22.04 |
|-----------|-------------|
| Open Horizon Hub | ✅ |
| Open Horizon Agent | ✅ |
| Docker | docker.io |
| Firewall | UFW |
| Package Manager | apt |

## Roadmap

Future releases will extend cloud-init templates to support:
- Ubuntu 24.04 LTS
- Fedora 41

## Verification

After provisioning, verify the OS:

```bash
make connect-hub
cat /etc/os-release
```
