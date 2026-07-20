# VM Images

Demo-in-a-Box uses [Multipass](https://multipass.run) with standard Ubuntu cloud images. No custom box build step is required.

## Default Image

All VMs use the **Ubuntu 22.04 LTS** cloud image, which Multipass downloads automatically on first launch.

## Customizing the Image

Set `MULTIPASS_IMAGE` before `make init` to use a different Ubuntu release:

```bash
export MULTIPASS_IMAGE=22.04   # default
make init
```

> **Note:** Only Ubuntu 22.04 is tested and supported in this release. Support for additional OS images via cloud-init variants will be added in a future change.

## Provisioning

All software installation (Docker, Open Horizon hub services, agent) happens at VM launch time via cloud-init:

- **Hub:** `cloud-init/hub.yaml`
- **Agents:** `cloud-init/agent.yaml.template` (rendered per-agent at launch)

Cloud-init runs `deploy-mgmt-hub.sh` on the hub and `agent-install.sh` on each agent. Package downloads are cached by the OS package manager on subsequent starts.

## Migration from Custom Box (Packer/VirtualBox)

The Packer-based box build pipeline (`packer/`, `build-custom-box.sh`, `make rebuild-boxes`) has been removed. Multipass uses official cloud images directly — no pre-built box is needed.
