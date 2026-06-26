# Blessed Samples

Blessed Samples is a feature that enables Demo-in-a-Box to automatically clone, build, and publish Open Horizon services during hub VM provisioning. Simply list service repositories in `blessedSamples.txt` and they will be available in the Exchange when `make init` completes.

> **Architecture note:** Demo-in-a-Box runs exclusively on **x86_64 (amd64)** hosts. All builds occur on amd64 VMs. Services built for other architectures (`arm64`, `arm`, `ppc64le`) use QEMU cross-compilation and are intended for future deployment to external devices (e.g., Raspberry Pi) that connect to the Demo-in-a-Box hub.

## Quick Start

1. Create `blessedSamples.txt` in the project root:

   ```
   https://github.com/open-horizon-services/web-helloworld-python.git
   ```

2. Run `make init` as normal. The build pipeline runs automatically after hub provisioning.

3. Verify services were published:
   ```bash
   make connect-hub
   hzn exchange service list
   ```

## Configuration File Format

`blessedSamples.txt` supports up to four space-separated fields per line:

```
<git_repo_url> [<branch_or_tag>] [<service_path>] [<arch>]
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `git_repo_url` | ✓ | — | HTTPS URL to a public git repository |
| `branch_or_tag` | — | `master` | Git branch, tag, or commit SHA |
| `service_path` | — | repo root | Relative path within the repo to the service directory |
| `arch` | — | `amd64` | Target architecture(s), comma-separated: `amd64`, `arm64`, `arm`, `ppc64le` |

### Examples

```bash
# Issue #21 simple format — one URL per line (fully supported)
https://github.com/open-horizon-services/web-helloworld-python.git
https://github.com/open-horizon-services/helloworld.git

# With branch specified
https://github.com/open-horizon/examples.git main

# With branch and service path (for monorepos)
https://github.com/open-horizon/examples.git master edge/services/helloworld

# Full format — branch, path, and architecture
https://github.com/open-horizon/examples.git master edge/services/cpu amd64

# Multi-architecture build (amd64 for Demo-in-a-Box, arm64 for Raspberry Pi)
https://github.com/open-horizon/examples.git master edge/services/nginx amd64,arm64

# Pin to a specific version tag
https://github.com/open-horizon/examples.git v2.31 edge/services/sdr amd64
```

### Comment and blank lines

Lines starting with `#` and blank lines are ignored.

### Service structure requirements

Each service entry must resolve to a directory containing:
- `horizon/service.definition.json` — required
- `Makefile` with `build` and `publish` targets — required

## Backward Compatibility

The single-URL format from Issue #21 (`one URL per line`) remains fully supported. Existing `blessedSamples.txt` files require no changes.

## Build Pipeline

When `blessedSamples.txt` is present, the pipeline:

1. **Parses** the config file and validates all entries
2. **Clones** each repository (`--depth 1` for speed, full clone as fallback)
3. **Resolves dependencies** by reading `requiredServices` from each `horizon/service.definition.json` and performing a topological sort — dependencies are always built first
4. **Builds** each service (`make build`), with Docker buildx or Podman `--platform` for multi-arch targets
5. **Pushes** built images to the local registry at `192.168.56.10:5000`
6. **Publishes** services to the Exchange (`make publish` or `hzn exchange service publish`)
7. **Reports** a summary of successes and failures

## Local Container Registry

A Docker Registry v2 container is deployed on the hub VM during provisioning:

| Detail | Value |
|--------|-------|
| Address | `http://192.168.56.10:5000` |
| TLS | None (demo environment only) |
| Storage | `/var/lib/registry` (persists across reboots, deleted with `make down`) |

Check registry status and contents from the host:
```bash
make registry-status    # Is the registry container running?
make registry-catalog   # List images in the registry
```

### Enabling host port forwarding (for Raspberry Pi / external devices)

By default, registry port 5000 is not forwarded to the host. To enable access from external devices:

```bash
export EXPOSE_REGISTRY_PORT=true
make init
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `EXPOSE_REGISTRY_PORT` | `false` | Forward registry port 5000 to host for external device access |
| `FAIL_FAST` | `false` | Abort the entire run on the first service failure |
| `USE_LOCAL_REGISTRY` | `false` | Rewrite image names in service definitions to use the local registry prefix |
| `OH_EXAMPLES_REPO` | `https://raw.githubusercontent.com/open-horizon/examples/master` | Base URL for Open Horizon examples (passed to `make publish`) |
| `BLESSED_SAMPLES_CREDENTIALS` | `./mycreds.env` | Path to credentials file used for Exchange publishing |

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make build-blessed-samples` | Manually re-run the build pipeline on the hub VM |
| `make list-blessed-samples` | Print services configured in `blessedSamples.txt` |
| `make registry-status` | Check whether the local registry container is running |
| `make registry-catalog` | List images stored in the local registry |
| `make blessed-samples-logs` | Print the latest build log (`blessed-samples-build-latest.log`) |
| `make clean-blessed-samples` | Remove cloned repos and build logs from hub VM; remove local log copy |

### Dry-run cleanup

```bash
make clean-blessed-samples DRY_RUN=true
```

## Logs

Build logs are written to `/var/log/blessed-samples-build-YYYYMMDD-HHMMSS.log` on the hub VM and copied to `blessed-samples-build-latest.log` in the project root (accessible on the host without SSH).

View the latest log:
```bash
make blessed-samples-logs
# or
cat blessed-samples-build-latest.log
```

## Upgrading from Issue #21 to Issue #34

No changes to your `blessedSamples.txt` are required. The Issue #34 implementation is a strict superset of Issue #21:

- The single-URL format continues to work identically
- All new features (branch, path, arch fields; local registry; dependency ordering) are opt-in
- `OH_EXAMPLES_REPO` and `BLESSED_SAMPLES_FILE` variables are unchanged

## Troubleshooting

### Registry not responding

```bash
# Check container status
make registry-status
# View registry logs (inside hub VM)
make connect-hub
docker logs registry 2>&1 | tail -30
```

### Service build failed

1. Review the log: `make blessed-samples-logs`
2. Verify the service has a `Makefile` with `build` and `publish` targets
3. Verify the `horizon/service.definition.json` is well-formed
4. Re-run manually with verbose output:
   ```bash
   make build-blessed-samples
   ```

### Service path not found

Ensure the `service_path` field (3rd column) points to a directory that contains `horizon/service.definition.json`. For monorepos:
```
https://github.com/open-horizon/examples.git master edge/services/myservice
```

### Circular dependency detected

The pipeline will abort with an `ERROR: Circular dependency detected` message. Review the `requiredServices` fields in the affected services' `service.definition.json` files.

## Security Considerations

> ⚠️ **Warning:** Building services from `blessedSamples.txt` executes arbitrary code from those repositories (`make build`, `make publish`). Only add repositories you trust. Prefer pinning to specific tags or commit SHAs rather than floating branches.

| Risk | Mitigation |
|------|-----------|
| Arbitrary code execution during build | Only use repositories you control or have reviewed |
| Insecure local registry (no TLS) | Registry is private to `192.168.56.x` network; acceptable for demo use |
| Credential exposure | Credentials sourced from `mycreds.env`; never logged |
| Image vulnerabilities | Images are NOT scanned; recommended to scan manually with Trivy for production-like scenarios |
| Private repository access | Only HTTPS repositories supported; use personal access tokens in the URL for private repos |

## Supported Service Structures

Services must follow Open Horizon conventions:

```
my-service/
├── Makefile            # Must have 'build' and 'publish' targets
├── Dockerfile          # (or Containerfile for Podman)
├── horizon/
│   ├── service.definition.json    # Required
│   ├── pattern.json               # Optional
│   └── userinput.json             # Optional
└── src/
    └── ...
```
