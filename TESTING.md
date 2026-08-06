# Testing Checklist for Multipass-Based Provisioning

This document provides manual testing procedures for verifying Demo-in-a-Box functionality using Multipass and cloud-init.

## Pre-Testing Setup

1. **Verify prerequisites:**
   ```bash
   make check
   # Should confirm multipass and jq are installed
   ```

2. **Clean environment:**
   ```bash
   make down  # Destroy any existing VMs
   ```

3. **Free disk space check:**
   ```bash
   df -h  # Ensure 20 GB+ available
   ```

---

## Test Suite 1: Single-OS Builds (Ubuntu 22)

### Test 1.1: Unicycle (Default)

**Purpose:** Verify default configuration provisions successfully

```bash
make check
make init
```

**Verification:**
- [ ] Hub VM launches successfully (`multipass list` shows `hub` Running)
- [ ] `mycreds.env` created on host with `HZN_ORG_ID`, `HZN_EXCHANGE_USER_AUTH`, and `HUB_IP`
- [ ] Agent VM launches successfully (`multipass list` shows `agent1` Running)
- [ ] `make connect-hub` opens a shell on the hub VM
- [ ] `make connect VMNAME=agent1` opens a shell on agent1
- [ ] On hub: `hzn exchange node list` shows registered agent
- [ ] On agent: `hzn node list` shows HelloWorld workload running
- [ ] `make down` destroys all VMs cleanly

**Expected Time:** 30–45 minutes

---

### Test 1.2: Bicycle (3 Agents)

**Purpose:** Verify multi-agent configuration

```bash
make down
export SYSTEM_CONFIGURATION=bicycle
make init
```

**Verification:**
- [ ] Hub provisions successfully
- [ ] 3 agent VMs provision successfully (`agent1`, `agent2`, `agent3`)
- [ ] All agents connect to Exchange
- [ ] HelloWorld deploys on all agents
- [ ] `make down` completes cleanly

**Expected Time:** 45–60 minutes

---

## Test Suite 2: Connectivity

### Test 2.1: Hub service health

```bash
make connect-hub
```

Inside hub VM:
```bash
# Check Exchange
curl -sf http://localhost:3090/v1/admin/version

# Check registry
curl -sf http://localhost:5000/v2/_catalog

# Check AgBot container
docker ps --filter name=agbot

# Check CSS container
docker ps --filter name=css-api
```

**Verification:**
- [ ] Exchange responds to `/v1/admin/version`
- [ ] Registry catalog endpoint responds
- [ ] AgBot container shows `healthy` status
- [ ] CSS container shows `healthy` status

---

### Test 2.2: Port-forward to localhost

```bash
make port-forward
curl -sf http://localhost:3090/v1/admin/version
make stop-port-forward
```

**Verification:**
- [ ] Exchange accessible at `http://localhost:3090` while port-forward is running
- [ ] `make stop-port-forward` terminates tunnels cleanly

---

## Test Suite 3: Blessed Samples

### Test 3.1: Build pipeline runs

```bash
echo "https://github.com/open-horizon-services/web-helloworld-python.git" > blessedSamples.txt
make build-blessed-samples
```

**Verification:**
- [ ] `multipass transfer` copies script to hub VM without error
- [ ] Build pipeline runs on hub VM
- [ ] `make blessed-samples-logs` shows build output
- [ ] Service appears in Exchange: `make connect-hub` → `hzn exchange service list`

---

### Test 3.2: Registry operations

```bash
make registry-status    # Should show registry container running
make registry-catalog   # Should return JSON with repositories list
```

**Verification:**
- [ ] `registry-status` shows registry container name and status
- [ ] `registry-catalog` returns valid JSON

---

## Test Suite 4: Teardown

### Test 4.1: Clean teardown

```bash
make down
```

**Verification:**
- [ ] Hub VM deleted and purged (`multipass list` does not show `hub`)
- [ ] Agent VMs deleted and purged
- [ ] `mycreds.env` removed from project root
- [ ] No residual `/tmp/agent*-cloud-init.yaml` files

---

## Reporting Results

After completing tests, document:

1. **Pass/Fail Status:** Which tests passed/failed
2. **Timing:** Actual provisioning times
3. **Issues:** Any unexpected behaviors
4. **Environment:** Host OS, Multipass version, RAM

### Example Report Template

```
Test: 1.1 - Unicycle default
Status: PASS
Time: 38 minutes
Environment:
  - Host OS: macOS 14 (Apple Silicon)
  - Multipass: 1.14.0
  - jq: 1.7
  - RAM: 16 GB
Notes: All services healthy, HelloWorld deployed on agent1
```

---

## Quick Smoke Test

For rapid verification after changes:

```bash
make check
make init
make connect-hub
# Inside hub:
hzn exchange node list  # Should show 1+ nodes
exit
make connect VMNAME=agent1
# Inside agent:
hzn node list  # Should show HelloWorld
exit
make down
```

**Expected Time:** ~35 minutes
