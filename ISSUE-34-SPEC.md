# Issue #34: Blessed Samples Support Specification

**Version:** 2.0
**Date:** 2026-05-13
**Status:** Draft
**Based On:** Issue #21 Implementation (PR #619 approach)

## Executive Summary

This specification defines the enhancement of the existing `blessedSamples.txt` support in Demo-in-a-Box (implemented in Issue #21) to enable developers to pre-configure automatic service publication during demo environment provisioning. The feature leverages the Open Horizon examples repository's BYO (Bring Your Own) samples mechanism to clone service repositories, build containers (Docker/Podman), and publish them to the Exchange.

**IMPORTANT:** Demo-in-a-Box runs exclusively on **x86_64 (amd64) architecture hosts**. All VMs (hub and agents) are amd64-based. While services can be built for multiple architectures (arm64, arm, ppc64le) for future deployment to external devices, the build process itself occurs on amd64 VMs within Demo-in-a-Box.

**Implementation Note:** Issue #21 has already implemented basic blessed samples support. This specification (Issue #34) extends that implementation to support local container registry integration and enhanced service building capabilities.

## Background

### Problem Statement

Currently, Demo-in-a-Box provisions Open Horizon environments with only the default HelloWorld service. Developers wanting to demonstrate custom services must manually:
1. Clone service repositories
2. Build container images
3. Publish services to the Exchange
4. Configure deployment policies

This manual process is time-consuming, error-prone, and creates barriers for new users.

**Architecture Context:** Demo-in-a-Box is an x86_64 (amd64) only system. All VMs (hub and agents) run on amd64 architecture. While the blessed samples feature can build services for multiple architectures (using cross-compilation), only amd64 services can be deployed within Demo-in-a-Box itself. Services built for other architectures (arm64, arm, ppc64le) are intended for future deployment to external devices that will connect to the Demo-in-a-Box hub.

### Related Work

- **GitHub Issue:** [open-horizon/examples#611](https://github.com/open-horizon/examples/issues/611) - BYO Blessed Samples feature
- **Demo-in-a-Box Issue #21:** Already implemented basic blessed samples support
- **PR #619 Approach:** BYO (Bring Your Own) samples mechanism in examples repository
- **Existing Implementation:**
  - `BLESSED_SAMPLES.md` documentation created
  - `blessedSamples.txt` file format defined (one repository URL per line)
  - `Vagrantfile.hub` modified to detect and publish custom samples
  - `OH_EXAMPLES_REPO` environment variable for examples repository URL
  - Integration with hub provisioning workflow
- **Existing Pattern:** HelloWorld service is already auto-deployed via `IBM/pattern-ibm.helloworld`

## Objectives

### Primary Goals

1. **Extend Issue #21 Implementation:** Build upon the existing blessed samples feature with enhanced capabilities
2. **Local Registry Integration:** Establish a local container registry on the hub VM for service images (NEW)
3. **Enhanced Configuration Format:** Support optional branch, service path, and architecture specifications (ENHANCEMENT)
4. **Container Runtime Flexibility:** Support both Docker and Podman container runtimes (NEW)
5. **Backward Compatibility:** Maintain compatibility with Issue #21's simple URL-per-line format
6. **OH_EXAMPLES_REPO Integration:** Leverage existing `OH_EXAMPLES_REPO` environment variable for examples repository

### Secondary Goals

1. **Error Handling:** Graceful failure with clear error messages if service build fails
2. **Build Caching:** Leverage container layer caching to speed up rebuilds
3. **Verification:** Validate published services are accessible to agents
4. **Documentation:** Comprehensive guide for creating and using blessed samples

## Features

### Core Features

#### 1. blessedSamples.txt Configuration File

**Location:** `./blessedSamples.txt` (project root)

**Current Format (Issue #21 Implementation):**
```
# Lines starting with # are comments
# Format: One repository URL per line (simple format)

https://github.com/open-horizon-services/web-helloworld-python.git
https://github.com/open-horizon-services/helloworld.git
```

**Enhanced Format (Issue #34 - This Specification):**
```
# Lines starting with # are comments
# Format: <git_repo_url> [<branch_or_tag>] [<service_path>] [<arch>]
# Fields in brackets are optional; defaults apply if omitted

# Simple format (compatible with Issue #21)
https://github.com/open-horizon-services/web-helloworld-python.git

# With branch specified
https://github.com/open-horizon/examples.git master

# With branch and service path
https://github.com/open-horizon/examples.git master edge/services/helloworld

# Full format with architecture
https://github.com/open-horizon/examples.git master edge/services/cpu2evtstreams amd64
https://github.com/open-horizon/examples.git v2.31 edge/services/gps amd64,arm64
```

**Fields:**
- `git_repo_url`: (Required) Full HTTPS URL to Git repository
- `branch_or_tag`: (Optional) Git branch, tag, or commit SHA (default: `master` or repo default branch)
- `service_path`: (Optional) Relative path within repo to service directory (default: root or auto-detect)
- `arch`: (Optional) Comma-separated list of architectures to build for (default: `amd64`)

**Architecture Notes:**
- **Build Host:** All builds occur on amd64 (x86_64) VMs within Demo-in-a-Box
- **Target Architectures:** Services can be built for multiple architectures using cross-compilation or multi-arch Docker builds
- **Current Limitation:** Only amd64 services can be deployed to Demo-in-a-Box VMs
- **Future Use:** arm64/arm/ppc64le builds are for future deployment to external devices (e.g., Raspberry Pi) that will connect to Demo-in-a-Box

**Validation Rules:**
- Empty lines and comments ignored
- Must have 1-4 fields per line (backward compatible with Issue #21 single-URL format)
- Repository URL must be accessible
- Service path (if specified) must contain `horizon/` subdirectory with service definition
- Architecture must be valid Open Horizon architecture (amd64, arm64, arm, ppc64le)
- **Note:** Only amd64 services can be deployed to Demo-in-a-Box VMs; other architectures are for future external device deployment

**Backward Compatibility:**
- Issue #21 format (single URL per line) remains fully supported
- Enhanced format is optional and provides additional control

#### 2. Local Container Registry (Optional)

**Purpose:** Enable air-gapped operation and support for external devices (e.g., Raspberry Pi)

**Scope:**
- **VirtualBox Network Only:** Registry accessible at `192.168.56.10:5000` within private network
- **External Device Support:** If external devices (Raspberry Pi, etc.) need access, registry must be accessible from host machine's network
- **Port Forwarding:** Add port forwarding in `Vagrantfile.hub` when external device support is needed

**Implementation:**
- Deploy Docker Registry v2 container on hub VM
- Bind to port 5000 (internal network)
- Optional: Forward port 5000 to host for external device access
- Configure as insecure registry for local development
- Persist registry data to `/var/lib/registry` on hub VM (survives reboots, destroyed with `make down`)

**Configuration:**
```bash
# On hub VM
docker run -d -p 5000:5000 \
  --restart=always \
  --name registry \
  -v /var/lib/registry:/var/lib/registry \
  registry:2
```

**Vagrantfile.hub Port Forwarding (Optional - for external devices):**
```ruby
config.vm.network "forwarded_port", guest: 5000, host: 5000, auto_correct: true
```

**Agent Configuration:**
- Add `192.168.56.10:5000` to insecure registries
- Update `/etc/docker/daemon.json` or `/etc/containers/registries.conf`
- Same verification requirements as external registries (no special trust)

#### 3. Service Build Pipeline

**Workflow:**
1. Parse `blessedSamples.txt` during hub provisioning
2. Resolve service dependencies (topological sort)
3. For each service entry (in dependency order):
   - Clone repository to `/tmp/blessed-samples/<repo_name>`
   - Checkout specified branch/tag
   - Navigate to service path (or auto-detect)
   - Detect container runtime (Docker/Podman)
   - Execute `make build` or equivalent
   - For multi-arch builds: Use Docker buildx with QEMU emulation
   - Tag images matching service definition's image name exactly
   - Push to local registry (if configured)
   - Execute `hzn exchange service publish` with configurable credentials (default: user's credentials from mycreds.env)
4. Verify service publication via `hzn exchange service list`

**Image Naming:**
- Match service definition's image name exactly (from `horizon/service.definition.json`)
- Do not add registry prefix unless specified in service definition
- Support multi-arch image manifests as best practice

**Dependency Resolution:**
- Parse service definitions to identify dependencies
- Build services in topological order
- Fail if circular dependencies detected
- Allow manual ordering override via line order in blessedSamples.txt (optional)

**Build Script Location:** `scripts/build-blessed-samples.sh`

**Error Handling:**
- Log all operations to `/var/log/blessed-samples-build.log` (hub VM) and `./blessed-samples-build.log` (host)
- Rotate logs for each run (timestamp-based: `blessed-samples-build-YYYYMMDD-HHMMSS.log`)
- Continue processing remaining services if one fails (default behavior)
- Support atomic operation mode via `FAIL_FAST=true` environment variable
- Generate summary report at end
- Exit with non-zero status if any service fails
- Different behavior for hub provisioning (continue) vs. manual builds (configurable)

#### 4. Container Runtime Detection

**Detection Logic:**
```bash
if command -v docker &> /dev/null && docker info &> /dev/null; then
    CONTAINER_RUNTIME="docker"
elif command -v podman &> /dev/null; then
    CONTAINER_RUNTIME="podman"
else
    echo "ERROR: Neither Docker nor Podman found"
    exit 1
fi
```

**Runtime-Specific Handling:**
- **Docker:** Use standard Docker commands, configure daemon.json, support buildx for multi-arch
- **Podman:** Use podman commands, configure registries.conf, handle rootless mode, support buildah for multi-arch

**Multi-Architecture Build Support:**
- **Docker:** Use `docker buildx` with QEMU emulation
- **Podman:** Use `podman build --platform` with QEMU emulation
- **Prerequisites:** QEMU user-mode emulation installed on hub VM
- **Best Practice:** Services should have multi-arch Dockerfiles and image manifests
- **Limitation:** Document as "best effort" - not all services may support cross-compilation

### Optional Features

#### 1. Pre-built Image Cache

**Purpose:** Speed up provisioning by caching built images

**Implementation:**
- Store built images in `~/.demo-in-a-box/image-cache/`
- Check cache before building
- Invalidate cache based on Git commit SHA
- Optional: `make clean-cache` to clear

**Status:** Future enhancement (Phase 5)

#### 2. Service Dependencies (REQUIRED - Phase 2)

**Purpose:** Handle services that depend on other services

**Implementation:**
- Parse `horizon/service.definition.json` to extract dependencies
- Build dependencies first (topological sort)
- Fail if circular dependencies detected
- Allow manual ordering override via line order in blessedSamples.txt

**No Format Extension Needed:** Dependencies extracted from service definitions automatically

#### 3. Custom Build Commands

**Purpose:** Support services with non-standard build processes

**Format Extension:**
```
# Add optional 5th field for custom build command
https://github.com/open-horizon/examples.git master edge/services/custom amd64 "make custom-build && make publish"
```

**Status:** Future enhancement (Phase 5)

#### 4. Configurable Credentials

**Purpose:** Allow different credentials for service publishing

**Environment Variables:**
- `BLESSED_SAMPLES_CREDENTIALS`: Path to alternative credentials file (default: `mycreds.env`)
- `BLESSED_SAMPLES_ORG_ID`: Override organization ID
- `BLESSED_SAMPLES_USER_AUTH`: Override user authentication

**Default Behavior:** Use credentials from `mycreds.env`

**Status:** Implemented in Phase 2

## Constraints

### Technical Constraints

1. **Architecture Limitation - CRITICAL:**
   - **Host Machine:** Must be x86_64 (amd64) architecture
   - **All VMs:** Run on x86_64 (amd64) architecture only
   - **Build Environment:** All container builds occur on amd64 VMs
   - **Deployment:** Only amd64 services can be deployed to Demo-in-a-Box VMs
   - **Cross-Architecture Builds:** Services can be built for arm64/arm/ppc64le using Docker buildx or similar, but these are for future external device deployment only
2. **Network Requirement:** Internet access required for cloning repositories
3. **Disk Space:** Additional 5-10GB per service for source code and images
4. **Memory:** No additional memory required beyond existing requirements
5. **Container Runtime:** Must have Docker or Podman installed on hub VM (already required)

### Security Constraints

1. **Insecure Registry:** Local registry runs without TLS (acceptable for demo environments)
2. **Repository Verification:**
   - Local repositories use same verification as external repositories
   - Do NOT rely solely on HTTPS and user trust
   - Implement checksum verification where possible
   - GPG signature verification deferred to future enhancement
3. **Git HTTPS Only:** No SSH key support for private repositories (use HTTPS with tokens)
4. **Credential Management:**
   - Service publishing uses configurable credentials (default: mycreds.env)
   - Support for dedicated service account credentials
   - Document security implications of credential choices
5. **Image Scanning:**
   - Built images NOT scanned for vulnerabilities in Phase 1-4
   - Vulnerability scanning (e.g., Trivy) deferred to Phase 5 (future enhancement)
   - Document as security limitation in BLESSED_SAMPLES.md

### Operational Constraints

1. **Build Time:** Each service adds 2-5 minutes to provisioning time
2. **Single-threaded:** Services built sequentially (parallel builds in future)
3. **No Rollback:** Failed builds require manual cleanup
4. **Hub VM Only:** Services built on hub VM, not distributed

### Compatibility Constraints

1. **Service Structure:** Services must follow Open Horizon conventions:
   - `horizon/service.definition.json` present
   - Makefile with `build` and `publish` targets (or equivalent)
   - Compatible with `hzn` CLI tools
2. **Git Repository:** Must be publicly accessible or use token authentication
3. **Container Images:**
   - **For Demo-in-a-Box deployment:** Must be amd64 (x86_64) compatible
   - **For external device deployment:** Can target arm64, arm, or ppc64le architectures
   - **Build process:** Occurs on amd64 VMs regardless of target architecture

## Implementation Plan

### Phase 0: Analysis of Existing Implementation (Week 1)

#### Step 0.1: Review Issue #21 Implementation
**Activities:**
- Review existing `BLESSED_SAMPLES.md` documentation
- Analyze current `Vagrantfile.hub` blessed samples logic
- Understand `OH_EXAMPLES_REPO` environment variable usage
- Document current workflow and limitations

**Deliverables:**
- Gap analysis document
- Compatibility requirements list
- Migration strategy for enhanced features

#### Step 0.2: Design Backward Compatibility
**Activities:**
- Define enhanced configuration format
- Ensure Issue #21 simple format remains supported
- Plan extraction of inline logic to separate script
- Design registry integration points

**Deliverables:**
- Enhanced format specification
- Backward compatibility test plan
- Integration design document

### Phase 1: Foundation (Week 2-3)

#### Step 1.1: Local Registry Setup
**Files Modified:**
- `configuration/Vagrantfile.hub`

**Changes:**
- Add Docker Registry v2 container deployment (after existing blessed samples logic)
- Configure registry to start on boot
- Add health check for registry availability
- Update firewall rules for port 5000
- **Preserve existing blessed samples functionality**

**Acceptance Criteria:**
- Registry accessible at `http://192.168.56.10:5000/v2/`
- Registry persists data across hub VM reboots
- `curl http://192.168.56.10:5000/v2/_catalog` returns valid JSON
- Existing Issue #21 blessed samples still work

#### Step 1.2: Agent Registry Configuration
**Files Modified:**
- `configuration/Vagrantfile.template.erb`

**Changes:**
- Detect container runtime (Docker/Podman)
- Configure insecure registry for Docker (`/etc/docker/daemon.json`)
- Configure insecure registry for Podman (`/etc/containers/registries.conf`)
- Restart container runtime service

**Acceptance Criteria:**
- Agents can pull images from `192.168.56.10:5000`
- `docker pull 192.168.56.10:5000/test` succeeds (after pushing test image)

#### Step 1.3: Build Script Framework
**Files Created:**
- `scripts/build-blessed-samples.sh`

**Functionality:**
- Parse `blessedSamples.txt` (if exists)
- Validate file format
- Log to `/var/log/blessed-samples-build.log`
- Exit gracefully if file not present

**Acceptance Criteria:**
- Script runs without errors when `blessedSamples.txt` absent
- Script validates format and reports errors for malformed entries
- Log file created with timestamps

### Phase 2: Core Build Pipeline (Week 4-5)

#### Step 2.0: Extract Existing Logic
**Files Modified:**
- `scripts/build-blessed-samples.sh` (NEW)
- `configuration/Vagrantfile.hub` (REFACTOR)

**Functionality:**
- Extract inline blessed samples logic from `Vagrantfile.hub` to separate script
- Maintain exact same behavior as Issue #21 implementation
- Support `OH_EXAMPLES_REPO` environment variable
- Support simple URL-per-line format

**Acceptance Criteria:**
- Existing Issue #21 functionality preserved
- Script can be called from Vagrantfile or manually
- `OH_EXAMPLES_REPO` variable respected
- No regression in service publishing

#### Step 2.1: Repository Cloning Enhancement
**Files Modified:**
- `scripts/build-blessed-samples.sh`

**Functionality:**
- Support both simple (Issue #21) and enhanced (Issue #34) formats
- Clone repositories to `/tmp/blessed-samples/`
- Checkout specified branch/tag (or default)
- Verify service path exists (or auto-detect)
- Verify `horizon/service.definition.json` present

**Acceptance Criteria:**
- Both formats work correctly
- Repositories cloned successfully
- Correct branch/tag checked out
- Missing service paths reported as errors
- Backward compatible with Issue #21

#### Step 2.2: Container Runtime Detection
**Files Modified:**
- `scripts/build-blessed-samples.sh`

**Functionality:**
- Detect Docker or Podman
- Set environment variables for runtime
- Validate runtime is functional

**Acceptance Criteria:**
- Correctly identifies Docker when present
- Correctly identifies Podman when Docker absent
- Fails gracefully if neither present

#### Step 2.3: Dependency Resolution
**Files Modified:**
- `scripts/build-blessed-samples.sh`

**Functionality:**
- Parse `horizon/service.definition.json` for each service
- Extract service dependencies from `requiredServices` field
- Build dependency graph
- Perform topological sort to determine build order
- Detect circular dependencies and fail with clear error
- Allow manual ordering override via line order in blessedSamples.txt (optional flag)

**Acceptance Criteria:**
- Dependencies correctly identified from service definitions
- Services built in correct order
- Circular dependencies detected and reported
- Clear error messages for dependency issues

#### Step 2.4: Service Building
**Files Modified:**
- `scripts/build-blessed-samples.sh`

**Functionality:**
- Execute `make build` in service directory
- Support multi-arch builds via Docker buildx or Podman with QEMU
- Capture build output to log (both hub VM and host)
- Handle build failures gracefully (continue or fail-fast based on mode)
- Tag images matching service definition's image name exactly
- Support multi-arch image manifests

**Acceptance Criteria:**
- Services build successfully
- Multi-arch builds work with buildx/QEMU
- Build errors logged with context
- Images tagged correctly matching service definition
- Logs available on both hub VM and host

#### Step 2.5: Image Publishing
**Files Modified:**
- `scripts/build-blessed-samples.sh`

**Functionality:**
- Push images to local registry (if configured)
- Execute `hzn exchange service publish` with configurable credentials
- Support `BLESSED_SAMPLES_CREDENTIALS` environment variable
- Verify service appears in Exchange
- Generate summary report with timestamps and status

**Acceptance Criteria:**
- Images pushed to registry successfully (if registry configured)
- Services published to Exchange with correct credentials
- `hzn exchange service list` shows published services
- Summary report shows success/failure for each service
- Configurable credentials work correctly

### Phase 3: Integration (Week 6)

#### Step 3.1: Hub Provisioning Integration
**Files Modified:**
- `configuration/Vagrantfile.hub`

**Changes:**
- Replace inline blessed samples logic with call to `build-blessed-samples.sh`
- Maintain existing `OH_EXAMPLES_REPO` support
- Pass credentials from mycreds.env
- Handle script failures appropriately
- **Ensure backward compatibility with Issue #21**

**Acceptance Criteria:**
- Script executes during `make up-hub`
- Credentials passed correctly
- Hub provisioning succeeds even if blessed samples fail
- Issue #21 simple format still works
- Enhanced format works correctly

#### Step 3.2: Makefile Targets
**Files Modified:**
- `Makefile`

**Changes:**
- Preserve existing `BLESSED_SAMPLES_FILE` and `OH_EXAMPLES_REPO` variables
- Add new registry-related targets

**New Targets:**
- `build-blessed-samples`: Manually trigger blessed samples build (may already exist from Issue #21)
- `clean-blessed-samples`: Remove all blessed samples assets:
  - Cloned repositories
  - Build logs (rotated logs)
  - Images from local registry
  - Services from Exchange (unless used outside blessedSamples.txt)
  - Local build artifacts
- `list-blessed-samples`: Show configured services from blessedSamples.txt
- `registry-status`: Check local registry status
- `registry-catalog`: List images in local registry
- `blessed-samples-logs`: Display recent build logs

**Acceptance Criteria:**
- All existing Makefile functionality preserved
- New targets work correctly
- `make check` shows all relevant variables including new ones
- `make clean-blessed-samples` performs comprehensive cleanup
- Cleanup is safe (checks for services used outside blessedSamples.txt)

#### Step 3.3: Documentation Updates
**Files Modified:**
- `BLESSED_SAMPLES.md` (EXISTS - enhance)
- `README.md` (EXISTS - update)
- `AGENTS.md` (EXISTS - update)

**Content Updates:**
- Document enhanced configuration format
- Add local registry documentation
- Update examples with both formats
- Add troubleshooting for registry issues
- Document backward compatibility

**Acceptance Criteria:**
- Documentation complete and accurate
- Both formats documented with examples
- Registry usage explained
- Troubleshooting covers common issues
- Migration guide from Issue #21 to Issue #34

### Phase 4: Testing & Validation (Week 7)

#### Step 4.1: Unit Testing
**Files Created:**
- `tests/test-blessed-samples.sh`

**Tests:**
- Configuration file parsing (both formats)
- Edge cases:
  - Empty blessedSamples.txt file
  - File with only comments
  - Invalid URLs
  - Malformed lines
  - Mixed Issue #21 and Issue #34 formats
- Repository cloning
- Dependency resolution
- Container runtime detection
- Image tagging
- Service publishing
- Registry integration
- Backward compatibility with Issue #21
- Credential configuration

**Acceptance Criteria:**
- All unit tests pass
- Both formats tested
- All edge cases handled correctly
- Error messages clear and actionable
- Issue #21 format still works

#### Step 4.2: Integration Testing
**Test Scenarios:**
1. Fresh install with Issue #21 simple format
2. Fresh install with Issue #34 enhanced format
3. Fresh install with mixed formats
4. Fresh install without blessedSamples.txt
5. Multiple services in blessedSamples.txt
6. Service build failure handling (continue vs. fail-fast)
7. Docker environment
8. Podman environment
9. Mixed OS environments (Ubuntu/Fedora)
10. Registry integration (with and without)
11. Migration from Issue #21 to Issue #34
12. Service dependencies (correct build order)
13. Multi-architecture builds
14. Network failure simulation (repository unavailable)
15. Resource usage monitoring (disk space, memory)
16. Configurable credentials

**Performance Metrics:**
- Collect build time per service (no strict requirements)
- Monitor disk space usage
- Monitor memory usage during builds
- Document performance characteristics

**Acceptance Criteria:**
- All scenarios pass
- No regression in Issue #21 functionality
- Enhanced features work correctly
- Performance metrics collected and documented
- Registry works correctly
- Network failures handled gracefully
- Resource usage within acceptable limits

#### Step 4.3: Regression Testing with Issue #21 Golden Cases
**Activities:**
- Inherit golden test cases from Issue #21 implementation
- Create test suite that runs both old and new formats
- Verify all Issue #21 functionality preserved
- Document any behavioral changes

**Test Cases:**
- Issue #21 simple format (one URL per line)
- OH_EXAMPLES_REPO environment variable usage
- Existing BLESSED_SAMPLES_FILE variable
- Service publishing workflow
- Error handling from Issue #21

**Acceptance Criteria:**
- All Issue #21 golden test cases pass
- No regression in existing functionality
- Behavioral changes documented
- Test suite can be run repeatedly

#### Step 4.4: Documentation Review
**Activities:**
- Technical review by maintainers
- User testing with new users
- Documentation updates based on feedback
- Document OH_EXAMPLES_REPO exact role in enhanced implementation

**Acceptance Criteria:**
- Documentation approved by maintainers
- New users can successfully use feature
- All feedback incorporated
- OH_EXAMPLES_REPO usage clearly documented
- Migration guide from Issue #21 to Issue #34 complete

## File Structure

```
demo-in-a-box/
├── blessedSamples.txt              # EXISTS (Issue #21): Configuration file (optional)
├── BLESSED_SAMPLES.md              # EXISTS (Issue #21): Feature documentation
├── scripts/                         # NEW: Directory for scripts
│   └── build-blessed-samples.sh    # NEW: Enhanced build script (replaces inline logic)
├── tests/                           # NEW: Test directory
│   └── test-blessed-samples.sh     # NEW: Test script
├── configuration/
│   ├── Vagrantfile.hub             # EXISTS (Issue #21): Already has blessed samples support
│   │                               # MODIFY: Add registry + enhanced build logic
│   └── Vagrantfile.template.erb    # MODIFY: Add registry config for agents
├── Makefile                        # EXISTS (Issue #21): Has BLESSED_SAMPLES_FILE + OH_EXAMPLES_REPO
│                                   # MODIFY: Add registry-related targets
├── README.md                       # EXISTS (Issue #21): References BLESSED_SAMPLES.md
│                                   # MODIFY: Add registry documentation
└── AGENTS.md                       # EXISTS (Issue #21): Updated with blessed samples info
                                    # MODIFY: Add registry and enhanced features
```

**Key Changes from Issue #21:**
- Extract inline blessed samples logic from `Vagrantfile.hub` to `scripts/build-blessed-samples.sh`
- Add local container registry support
- Enhance configuration format (backward compatible)
- Add registry configuration for agent VMs

## Example blessedSamples.txt

```
# Open Horizon Example Services
# Supports both Issue #21 simple format and Issue #34 enhanced format
#
# IMPORTANT: Demo-in-a-Box runs on amd64 (x86_64) only
# - amd64 services can be deployed to Demo-in-a-Box VMs
# - arm64/arm/ppc64le services are built for future external device deployment
# - All builds occur on amd64 VMs using cross-compilation when needed

# ===== Issue #21 Simple Format (backward compatible) =====
# One repository URL per line - uses defaults (master branch, root path, amd64)
https://github.com/open-horizon-services/web-helloworld-python.git
https://github.com/open-horizon-services/helloworld.git

# ===== Issue #34 Enhanced Format =====
# Format: <repo_url> [<branch>] [<service_path>] [<arch>]

# With branch specified
https://github.com/open-horizon/examples.git master

# With branch and service path
https://github.com/open-horizon/examples.git master edge/services/helloworld

# Full format with architecture (amd64 - deployable to Demo-in-a-Box)
https://github.com/open-horizon/examples.git master edge/services/cpu amd64
https://github.com/open-horizon/examples.git master edge/services/cpu2evtstreams amd64

# Multi-architecture (amd64 for Demo-in-a-Box, arm64 for future Raspberry Pi)
https://github.com/open-horizon/examples.git master edge/services/nginx amd64,arm64

# Specific version tag
https://github.com/open-horizon/examples.git v2.31 edge/services/sdr amd64
```

## Error Handling

### Build Failures

**Scenario:** Service build fails due to missing dependencies

**Handling:**
1. Log error with full build output
2. Continue with next service
3. Include in summary report
4. Exit with status code 1 at end

**User Action:**
- Review `/var/log/blessed-samples-build.log`
- Fix service or remove from blessedSamples.txt
- Re-run `make build-blessed-samples`

### Repository Access Failures

**Scenario:** Git repository not accessible

**Handling:**
1. Log error with repository URL
2. Skip service
3. Continue with next service

**User Action:**
- Verify repository URL
- Check network connectivity
- Verify authentication if private repo

### Registry Failures

**Scenario:** Local registry not responding

**Handling:**
1. Detect registry unavailable before building
2. Fail fast with clear error message
3. Provide troubleshooting steps

**User Action:**
- Verify registry container running: `docker ps | grep registry`
- Check registry logs: `docker logs registry`
- Restart registry: `docker restart registry`

## Security Considerations

### Insecure Registry

**Risk:** Local registry runs without TLS encryption

**Mitigation:**
- Registry accessible on private network (192.168.56.x) by default
- Optional port forwarding to host for external device support
- Acceptable for demo/development environments
- Same verification requirements as external registries

**Documentation:**
- Clearly state this is for demo purposes only
- Warn against using in production
- Provide guidance for securing registry if needed
- Document port forwarding implications for external devices

### Credential Handling

**Risk:** Exchange credentials used for service publishing

**Mitigation:**
- Configurable credentials via environment variables
- Default: Use credentials from mycreds.env (already secured)
- Support for dedicated service account credentials
- Don't log credentials
- Don't expose in error messages

**Documentation:**
- Explain credential usage and configuration options
- Recommend using dedicated service account for production-like scenarios
- Document security implications of each credential approach

### Repository Verification

**Risk:** Cloning and building from untrusted repositories

**Mitigation:**
- Local repositories use same verification as external repositories
- Do NOT rely solely on HTTPS and user trust
- Implement checksum verification where possible
- GPG signature verification deferred to Phase 5

**Documentation:**
- Security warning in BLESSED_SAMPLES.md
- Best practices for vetting repositories
- Recommend using specific tags/commits vs. branches
- Document verification mechanisms

### Arbitrary Code Execution

**Risk:** Building services executes arbitrary code from repositories

**Mitigation:**
- Only use trusted repositories
- Recommend reviewing service code before adding to blessedSamples.txt
- Run builds in isolated VM environment
- Document as inherent risk of building from source

**Documentation:**
- Prominent security warning in BLESSED_SAMPLES.md
- Best practices for vetting services
- Recommend using specific tags/commits vs. branches
- Suggest code review process

### Image Vulnerability Scanning

**Risk:** Built images may contain vulnerabilities

**Mitigation:**
- Document as limitation in Phase 1-4
- Vulnerability scanning (e.g., Trivy) deferred to Phase 5
- Recommend manual scanning for production use

**Documentation:**
- Clearly state images are not scanned
- Provide guidance for manual scanning
- Document as future enhancement

## Performance Considerations

### Build Time

**Impact:** Each service adds 2-5 minutes to provisioning

**Optimization:**
- Use container layer caching
- Consider parallel builds in future
- Provide progress indicators

**User Control:**
- Make feature optional (only if blessedSamples.txt present)
- Allow disabling via environment variable
- Provide `make build-blessed-samples` for manual builds

### Disk Space

**Impact:** 5-10GB per service for source + images

**Optimization:**
- Clean up source repositories after build
- Use Docker/Podman image pruning
- Document disk requirements

**User Control:**
- Provide `make clean-blessed-samples` target
- Document disk space requirements in README

### Network Bandwidth

**Impact:** Cloning repositories and pulling base images

**Optimization:**
- Use shallow clones (`--depth 1`)
- Leverage Docker layer caching
- Consider optional image cache

**User Control:**
- Allow offline mode (skip if blessedSamples.txt absent)
- Document network requirements

## Testing Strategy

### Unit Tests

**Scope:** Individual functions in build script

**Tests:**
- Configuration file parsing
- URL validation
- Architecture validation
- Container runtime detection
- Image tagging logic

**Tools:** Bash test framework (bats or similar)

### Integration Tests

**Scope:** End-to-end workflow

**Tests:**
- Complete provisioning with blessed samples
- Service build and publish
- Agent deployment of blessed services
- Error handling scenarios

**Tools:** Vagrant + shell scripts

### Manual Tests

**Scope:** User experience and edge cases

**Tests:**
- Documentation accuracy
- Error message clarity
- Performance under load
- Mixed OS environments

**Tools:** Manual testing by maintainers and users

## Documentation Requirements

### BLESSED_SAMPLES.md

**Sections:**
1. Overview and benefits
2. Configuration file format
3. Supported service structures
4. Example configurations
5. Troubleshooting guide
6. Security considerations
7. Best practices

### README.md Updates

**Additions:**
- Feature overview in main README
- Link to BLESSED_SAMPLES.md
- Quick start example
- Prerequisites update (if any)

### AGENTS.md Updates

**Additions:**
- Feature description in project knowledge base
- File structure updates
- Convention documentation
- Anti-pattern warnings (if any)

## Success Criteria

### Functional Requirements

- [ ] Issue #21 simple format still works (backward compatibility)
- [ ] Issue #34 enhanced format works correctly
- [ ] Mixed format files work correctly
- [ ] Local registry deployed and accessible
- [ ] Services built successfully
- [ ] Images pushed to local registry
- [ ] Services published to Exchange
- [ ] Agents can deploy blessed services
- [ ] Works with Docker
- [ ] Works with Podman
- [ ] Works on Ubuntu 22/24
- [ ] Works on Fedora 41
- [ ] Backward compatible (no blessedSamples.txt)
- [ ] `OH_EXAMPLES_REPO` environment variable still works
- [ ] Existing `BLESSED_SAMPLES_FILE` variable still works

### Non-Functional Requirements

- [ ] Build time < 5 minutes per service
- [ ] Clear error messages
- [ ] Comprehensive logging
- [ ] Complete documentation
- [ ] All tests passing
- [ ] No regression in existing features
- [ ] Code reviewed and approved

### User Experience

- [ ] New users can configure blessed samples
- [ ] Error messages actionable
- [ ] Documentation clear and complete
- [ ] Troubleshooting guide helpful
- [ ] Examples work as documented

## Future Enhancements

### Phase 5: Advanced Features (Future)

1. **Parallel Builds:** Build multiple services concurrently
2. **Image Cache:** Cache built images for faster rebuilds
3. **Service Dependencies:** Handle inter-service dependencies
4. **Custom Build Commands:** Support non-standard build processes
5. **Private Repositories:** Support SSH keys for private repos
6. **Build Notifications:** Notify user of build progress/completion
7. **Service Verification:** Automated testing of deployed services
8. **Registry UI:** Web interface for browsing local registry
9. **Multi-architecture Builds:** Enhanced cross-compilation for arm64/arm/ppc64le (for external device deployment)
10. **Service Catalog:** Browse available blessed samples
11. **External Device Support:** Enable arm64 devices (e.g., Raspberry Pi) to connect to Demo-in-a-Box hub and deploy pre-built arm64 services

## References

### Related Issues and PRs
- [Demo-in-a-Box Issue #21](https://github.com/open-horizon-services/demo-in-a-box/issues/21) - Original blessed samples implementation
- [Demo-in-a-Box Issue #34](https://github.com/open-horizon-services/demo-in-a-box/issues/34) - This specification (enhancements)
- [Open Horizon Examples Issue #611](https://github.com/open-horizon/examples/issues/611) - BYO Blessed Samples feature
- [Open Horizon Examples PR #619](https://github.com/open-horizon/examples/pull/619) - BYO samples implementation approach

### Documentation
- [Open Horizon Examples Repository](https://github.com/open-horizon/examples)
- [Docker Registry Documentation](https://docs.docker.com/registry/)
- [Podman Registry Documentation](https://docs.podman.io/en/latest/markdown/podman-registry.1.html)
- [Open Horizon Service Definition](https://github.com/open-horizon/anax/blob/master/doc/service_def.md)
- [Demo-in-a-Box BLESSED_SAMPLES.md](./BLESSED_SAMPLES.md) - Existing documentation from Issue #21

## Appendix A: Script Pseudocode

```bash
#!/bin/bash
# scripts/build-blessed-samples.sh
# Enhanced version supporting both Issue #21 and Issue #34 formats

set -e

BLESSED_SAMPLES_FILE="${1:-./blessedSamples.txt}"
LOG_FILE="/var/log/blessed-samples-build.log"
WORK_DIR="/tmp/blessed-samples"
REGISTRY_URL="192.168.56.10:5000"
OH_EXAMPLES_REPO="${OH_EXAMPLES_REPO:-https://raw.githubusercontent.com/open-horizon/examples/master}"

# Initialize logging
init_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2>&1
    echo "=== Blessed Samples Build Started: $(date) ==="
    echo "=== OH_EXAMPLES_REPO: $OH_EXAMPLES_REPO ==="
}

# Check if blessed samples file exists
check_config_file() {
    if [ ! -f "$BLESSED_SAMPLES_FILE" ]; then
        echo "No blessedSamples.txt found. Skipping blessed samples build."
        exit 0
    fi
}

# Detect container runtime
detect_container_runtime() {
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        echo "docker"
    elif command -v podman &> /dev/null; then
        echo "podman"
    else
        echo "ERROR: Neither Docker nor Podman found"
        exit 1
    fi
}

# Parse configuration file (supports both formats)
parse_config() {
    grep -v '^#' "$BLESSED_SAMPLES_FILE" | grep -v '^[[:space:]]*$' | while read -r line; do
        # Count fields
        field_count=$(echo "$line" | wc -w)
        
        if [ "$field_count" -eq 1 ]; then
            # Issue #21 simple format: just URL
            repo="$line"
            branch="master"
            path=""
            arch="amd64"
        elif [ "$field_count" -eq 2 ]; then
            # URL + branch
            read -r repo branch <<< "$line"
            path=""
            arch="amd64"
        elif [ "$field_count" -eq 3 ]; then
            # URL + branch + path
            read -r repo branch path <<< "$line"
            arch="amd64"
        elif [ "$field_count" -eq 4 ]; then
            # Full format: URL + branch + path + arch
            read -r repo branch path arch <<< "$line"
        else
            echo "ERROR: Invalid line format: $line"
            continue
        fi
        
        echo "$repo|$branch|$path|$arch"
    done
}

# Clone repository
clone_repo() {
    local repo_url="$1"
    local branch="$2"
    local repo_name=$(basename "$repo_url" .git)
    local clone_dir="$WORK_DIR/$repo_name"
    
    if [ -d "$clone_dir" ]; then
        rm -rf "$clone_dir"
    fi
    
    git clone --depth 1 --branch "$branch" "$repo_url" "$clone_dir"
    echo "$clone_dir"
}

# Build service
build_service() {
    local service_dir="$1"
    local runtime="$2"
    
    cd "$service_dir"
    
    if [ -f "Makefile" ]; then
        make build
    else
        echo "ERROR: No Makefile found in $service_dir"
        return 1
    fi
}

# Tag and push images
push_images() {
    local service_dir="$1"
    local runtime="$2"
    
    # Parse service.definition.json for image names
    # Tag with registry prefix
    # Push to local registry
}

# Publish service to Exchange
publish_service() {
    local service_dir="$1"
    
    cd "$service_dir"
    
    if [ -f "Makefile" ]; then
        make publish
    else
        hzn exchange service publish -f horizon/service.definition.json
    fi
}

# Main execution
main() {
    init_logging
    check_config_file
    
    RUNTIME=$(detect_container_runtime)
    echo "Using container runtime: $RUNTIME"
    
    mkdir -p "$WORK_DIR"
    
    SUCCESS_COUNT=0
    FAILURE_COUNT=0
    
    parse_config | while read -r repo branch path arch; do
        echo "=== Processing: $repo ($branch) - $path ==="
        
        if clone_dir=$(clone_repo "$repo" "$branch"); then
            service_dir="$clone_dir/$path"
            
            if [ -d "$service_dir" ]; then
                if build_service "$service_dir" "$RUNTIME" && \
                   push_images "$service_dir" "$RUNTIME" && \
                   publish_service "$service_dir"; then
                    echo "✓ Success: $path"
                    ((SUCCESS_COUNT++))
                else
                    echo "✗ Failed: $path"
                    ((FAILURE_COUNT++))
                fi
            else
                echo "✗ Service path not found: $service_dir"
                ((FAILURE_COUNT++))
            fi
        else
            echo "✗ Failed to clone: $repo"
            ((FAILURE_COUNT++))
        fi
    done
    
    echo "=== Build Summary ==="
    echo "Successful: $SUCCESS_COUNT"
    echo "Failed: $FAILURE_COUNT"
    
    if [ $FAILURE_COUNT -gt 0 ]; then
        exit 1
    fi
}

main "$@"
```

## Appendix B: Registry Configuration

### Docker Daemon Configuration

**File:** `/etc/docker/daemon.json`

```json
{
  "insecure-registries": ["192.168.56.10:5000"]
}
```

### Podman Registry Configuration

**File:** `/etc/containers/registries.conf`

```toml
[[registry]]
location = "192.168.56.10:5000"
insecure = true
```

## Appendix C: Example Service Structure

```
edge/services/myservice/
├── horizon/
│   ├── service.definition.json
│   ├── pattern.json
│   └── userinput.json
├── Makefile
├── Dockerfile
├── src/
│   └── myservice.py
└── README.md
```

**Required Files:**
- `horizon/service.definition.json`: Service metadata
- `Makefile`: Build and publish targets
- `Dockerfile`: Container image definition

**Makefile Targets:**
- `make build`: Build container image
- `make publish`: Publish service to Exchange

---

**End of Specification**