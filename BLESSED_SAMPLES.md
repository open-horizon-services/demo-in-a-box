# Blessed Samples Configuration

This guide explains how to optionally use a custom `blessedSamples.txt` file to pre-populate the Open Horizon Exchange with user-specified services during the hub provisioning process.

## Overview

By default, the hub provisioning script publishes the standard Open Horizon example services to the Exchange. However, you can customize which services are published by providing a `blessedSamples.txt` file containing URLs to git repositories that contain Open Horizon services.

This feature leverages the **BYO (Bring Your Own) Samples** functionality introduced in [PR #619](https://github.com/open-horizon/examples/pull/619) from the open-horizon/examples repository.

## Prerequisites

- A git repository containing Open Horizon services with a `Makefile` that includes a `publish-only` target
- The repository must be accessible from the hub VM (internet-connected)
- Optionally, a fork of the [open-horizon/examples](https://github.com/open-horizon/examples) repository with custom sample configurations

## File Format

Create a file named `blessedSamples.txt` in the project root directory (same location as the Makefile). Each line should contain a git repository URL:

```text
# Blessed Samples Configuration
# Add git repository URLs (one per line) to publish as blessed samples
# Each repository must contain a Makefile with a 'publish-only' target

# Hello World examples
https://github.com/open-horizon-services/web-helloworld-python.git

# Additional services
https://github.com/open-horizon-services/helloworld.git
https://github.com/open-horizon-services/sensor-graph.yml.git
```

### Requirements for Service Repositories

Each repository URL in `blessedSamples.txt` must meet these requirements:

1. **Git Repository** - Must be a public or private git repository
2. **Makefile** - Must contain a `publish-only` target
3. **Horizon Integration** - Services must be compatible with Open Horizon Exchange format

## Usage

### Step 1: Create blessedSamples.txt

Create the `blessedSamples.txt` file in the project root with your desired service repository URLs:

```bash
# Example: Create a custom blessedSamples.txt
cat > blessedSamples.txt << 'EOF'
https://github.com/open-horizon-services/web-helloworld-python.git
https://github.com/open-horizon-services/helloworld.git
EOF
```

### Step 2: Set Environment Variables

Before running `make up-hub`, set the following environment variables:

```bash
# Required: Point to your examples repository fork (or the official PR branch)
export OH_EXAMPLES_REPO=https://raw.githubusercontent.com/t-fine/examples/refs/heads/feat_611_byo_blessed_samples

# Optional: Override the default filename (defaults to blessedSamples.txt)
export BLESSED_SAMPLES_FILE=blessedSamples.txt
```

### Step 3: Provision the Hub

```bash
# Provision hub only (for custom agent setup)
make up-hub

# Or provision the full environment
make init
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `BLESSED_SAMPLES_FILE` | No | `blessedSamples.txt` | Filename containing sample repository URLs |
| `OH_EXAMPLES_REPO` | Yes* | - | Raw URL to the examples repository containing the sample configuration |
| `BYO_SAMPLES` | No | (auto) | Internal variable - filename passed to deploy script |

*Required when using custom blessed samples

## How It Works

1. **VM Provisioning** - The hub VM is provisioned with Exchange, CSS, AgBot, FDO, and MongoDB
2. **Sample Detection** - If `BLESSED_SAMPLES_FILE` exists and `OH_EXAMPLES_REPO` is set, the provisioning script detects this
3. **Custom Publishing** - Instead of publishing the default Open Horizon samples, the script publishes only the repositories listed in your `blessedSamples.txt` file
4. **Exchange Ready** - Your custom services are now available in the Exchange as "blessed" samples

## Example Workflow

### Complete Example

```bash
# 1. Set up environment with custom samples
export OH_EXAMPLES_REPO=https://raw.githubusercontent.com/open-horizon/examples/refs/heads/master

# 2. Create your custom samples file
cat > blessedSamples.txt << 'EOF'
https://github.com/open-horizon-services/web-helloworld-python.git
https://github.com/open-horizon-services/gps-tracking.git
https://github.com/open-horizon-services/edge-ai-camera.git
EOF

# 3. Provision the hub
make up-hub

# 4. After provisioning, verify custom samples are available
# (SSH to hub and check Exchange)
make connect-hub

# Inside the hub VM:
hzn ex service list
```

### Using a Fork

If you've forked the open-horizon/examples repository and added custom services:

```bash
# Set to your fork's raw content URL
export OH_EXAMPLES_REPO=https://raw.githubusercontent.com/YOUR_USERNAME/examples/refs/heads/main

# Create samples file with your custom services
cat > blessedSamples.txt << 'EOF'
https://github.com/YOUR_USERNAME/my-custom-service.git
https://github.com/open-horizon-services/helloworld.git
EOF

# Provision
make up-hub
```

## Verification

After provisioning, you can verify the custom samples are available:

```bash
# Connect to the hub
make connect-hub

# Inside the hub VM, check the Exchange for your services
export $(cat /vagrant/mycreds.env)
hzn exchange service list
hzn exchange pattern list
```

## Troubleshooting

### Samples Not Publishing

1. Verify `OH_EXAMPLES_REPO` is set correctly:
   ```bash
   echo $OH_EXAMPLES_REPO
   ```

2. Verify `blessedSamples.txt` exists in the project root:
   ```bash
   ls -la blessedSamples.txt
   ```

3. Check the provisioning logs for errors:
   ```bash
   # SSH to hub and check logs
   make connect-hub
   docker logs exchange-ubi
   ```

### Repository Access Errors

Ensure the hub VM can access the git repositories:
- For private repos, you may need to configure SSH keys
- For public repos, ensure internet connectivity from the VM

### Makefile publish-only Target Missing

If you see errors about `publish-only` target not existing:
- Ensure your service repository has a Makefile
- Verify the Makefile contains a `publish-only` target

## File Location Summary

```
demo-in-a-box/
├── Makefile                    # Orchestration
├── blessedSamples.txt          # Your custom samples (create this)
├── BLESSED_SAMPLES.md         # This documentation
├── configuration/
│   └── Vagrantfile.hub        # Hub provisioning (modified for BYO samples)
└── ...
```

## Additional Resources

- [Open Horizon Examples Repository](https://github.com/open-horizon/examples)
- [PR #619: BYO Blessed Samples](https://github.com/open-horizon/examples/pull/619)
- [Open Horizon Documentation](https://open-horizon.github.io/)
