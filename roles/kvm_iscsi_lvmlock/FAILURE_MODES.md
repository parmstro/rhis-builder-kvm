# iSCSI Shared Storage Failure Modes and Recovery

This document describes common failure scenarios with iSCSI shared storage using lvmlockd and sanlock, and how to detect and recover from them.

## Failure Mode Categories

### 1. iSCSI Layer Failures

#### 1.1 Network Interruption
**Symptoms:**
- iSCSI session shows as "recovery" or "failed"
- Block I/O hangs or times out
- Kernel messages: "connection error or timeout"

**Causes:**
- Network cable unplugged
- Switch port flapping
- Network congestion/packet loss
- Firewall dropping packets

**Detection:**
```bash
iscsiadm -m session
# Look for sessions not in "running" state

dmesg | tail -50 | grep -i iscsi
# Look for connection errors

journalctl -u iscsid -u iscsi --since "10 minutes ago"
```

**Impact:**
- Read/write I/O blocks waiting for timeout
- LVM operations hang
- VMs may freeze or report I/O errors
- Lock renewals fail, leading to lock expiration

**Recovery:**
- Automatic: iSCSI should auto-reconnect when network returns
- Manual: Force logout and re-login to target

#### 1.2 iSCSI Target Unavailable
**Symptoms:**
- No active iSCSI sessions
- Device paths disappear (/dev/sdX)
- VG reports "not found"

**Causes:**
- NAS/SAN powered off or rebooted
- iSCSI target service stopped
- Target configuration changed
- Network route to target broken

**Detection:**
```bash
iscsiadm -m session
# Shows "No active sessions"

lsblk | grep <expected-device>
# Device missing

ping <iscsi-target-ip>
# Cannot reach target
```

**Impact:**
- All I/O fails immediately
- VG becomes inaccessible
- Sanlock loses heartbeat → locks expire
- VMs crash or freeze

**Recovery:**
- Fix target (power on, start service)
- Wait for auto-reconnect or force re-login
- Restart sanlock/lvmlockd
- Restart VG locks
- Restart VMs

#### 1.3 Session Timeout / Replacement Timeout Exceeded
**Symptoms:**
- Session state shows "transport offline"
- I/O errors in kernel log
- Device marked as failed

**Causes:**
- Prolonged network outage beyond replacement timeout
- Storage network MTU mismatch
- iSCSI parameters misconfigured

**Detection:**
```bash
iscsiadm -m session -P 3
# Check "iSCSI Session State" and timeouts

cat /sys/class/iscsi_session/session*/state
# Shows "FAILED" or "TRANSPORT OFFLINE"
```

**Impact:**
- Session recovery fails
- Device removed from system
- VG cannot be accessed
- Requires manual intervention

**Recovery:**
- Logout and re-login to target
- May require VG lock restart
- Check and fix network issues first

### 2. Sanlock Layer Failures

#### 2.1 Sanlock Daemon Crash
**Symptoms:**
- sanlock.service shows as "failed" or "inactive"
- Lock renewals stop
- Eventually locks expire

**Causes:**
- Software bug
- Out of memory
- Disk I/O errors preventing lock writes
- Signal (SIGKILL) sent to daemon

**Detection:**
```bash
systemctl status sanlock
# Shows inactive/failed

journalctl -u sanlock --since "1 hour ago"
# Shows crash reason

sanlock client status
# Shows "cannot connect to daemon"
```

**Impact:**
- Existing locks continue until watchdog timeout (typically 80 seconds)
- No new locks can be acquired
- After timeout, other hosts may steal locks (risk of dual access)

**Recovery:**
- Restart sanlock immediately: `systemctl start sanlock`
- Check if locks were held: `vgchange --lockstatus`
- May need to restart VG locks: `vgchange --lock-start`

#### 2.2 Lock Expiration / Watchdog Timeout
**Symptoms:**
- Host loses locks
- Other hosts log "acquired lock from failed host"
- VMs on this host lose disk access

**Causes:**
- Sanlock unable to renew locks (I/O hang)
- Host heavily loaded (CPU starvation)
- Time spent in suspend/hibernate
- Network partition preventing lock writes

**Detection:**
```bash
# On the affected host
vgchange --lockstatus vmstore
# Shows locks lost

journalctl -u sanlock | grep -i timeout
# Shows watchdog timeouts

# On other hosts
journalctl -u sanlock | grep -i acquired
# Shows lock acquisitions from failed host
```

**Impact:**
- **CRITICAL**: Risk of split-brain and data corruption
- VMs on failed host lose storage access
- Other hosts may start VMs thinking locks are free

**Recovery:**
- **STOP ALL VMs on affected host immediately**
- Verify no dual access: check all hosts' lock status
- Restart sanlock and lvmlockd
- Restart VG locks
- Verify locks acquired before starting VMs

#### 2.3 Lock Corruption
**Symptoms:**
- Sanlock cannot read or write locks
- VG activation fails with lock errors
- "Sanlock error" in logs

**Causes:**
- Disk corruption in lock area
- Simultaneous writes from multiple hosts (bug)
- Storage device failing

**Detection:**
```bash
sanlock client status
# May show errors

vgchange --lock-start vmstore
# Fails with sanlock errors

journalctl -u sanlock | grep -i error
```

**Impact:**
- VG cannot be activated
- Locks unreliable
- Risk of data corruption if dual access

**Recovery:**
- **Dangerous**: May require VG lock reset
- See "Nuclear Option" section below

### 3. lvmlockd Layer Failures

#### 3.1 lvmlockd Daemon Crash
**Symptoms:**
- lvmlockd.service inactive/failed
- LVM commands hang or fail
- Cannot start/stop VG locks

**Causes:**
- Software bug
- Configuration error
- Resource exhaustion

**Detection:**
```bash
systemctl status lvmlockd
# Shows inactive/failed

journalctl -u lvmlockd --since "1 hour ago"
# Shows crash reason

lvm version
lvmconfig --type diff
# Check for configuration issues
```

**Impact:**
- Cannot acquire or release locks
- Existing activated LVs may continue working
- Cannot activate new LVs
- VG operations fail

**Recovery:**
- Restart lvmlockd: `systemctl start lvmlockd`
- May need to restart VG locks
- Existing LVs usually unaffected

#### 3.2 VG Lock Not Started
**Symptoms:**
- `vgchange --lockstatus` shows no locks
- Cannot activate LVs in VG
- "VG is not locked" errors

**Causes:**
- lvmlockd not running when VG activated
- Manual deactivation: `vgchange --lock-stop`
- Host reboot without autoactivation

**Detection:**
```bash
vgchange --lockstatus vmstore
# Shows empty or error

vgs vmstore -o locktype,lockargs
# Shows locktype but no active locks

systemctl status lvmlockd
# May be inactive
```

**Impact:**
- VG is visible but not usable
- Cannot create or activate LVs
- VMs cannot start

**Recovery:**
- Ensure lvmlockd running: `systemctl start lvmlockd`
- Start VG lock: `vgchange --lock-start vmstore`
- Activate VG: `vgchange -ay vmstore`

#### 3.3 Lock Type Mismatch
**Symptoms:**
- VG shows different lock type than expected
- Cannot start lock: "lock type not supported"
- Mixed lock types across hosts

**Causes:**
- VG modified on host without lvmlockd
- VG imported incorrectly
- Configuration drift between hosts

**Detection:**
```bash
vgs vmstore -o locktype,lockargs
# Shows unexpected lock type or "none"

# Compare across hosts
pdsh -w kvm[1-3] 'vgs vmstore -o locktype --noheadings'
```

**Impact:**
- Inconsistent locking across cluster
- Risk of dual access
- Data corruption possible

**Recovery:**
- **STOP ALL VMs IMMEDIATELY**
- Deactivate VG on all hosts
- Convert VG to proper lock type (may require recreation)

### 4. Split-Brain Scenarios

#### 4.1 Network Partition
**Symptoms:**
- Hosts cannot communicate with each other
- Each side thinks other is down
- Both sides try to acquire locks

**Causes:**
- Network switch failure
- Cable failure splitting cluster
- Firewall misconfiguration

**Detection:**
```bash
# From host1, cannot reach host2
ping kvm2.example.ca
# Timeout

# But both hosts show locks
vgchange --lockstatus vmstore
# Each shows it has locks
```

**Impact:**
- **CATASTROPHIC**: Both sides may write to storage
- Data corruption highly likely
- VM data loss possible

**Recovery:**
- **STOP ALL VMs on both sides**
- Fix network first
- Determine which side kept sanlock heartbeat
- Deactivate VG on the side that lost locks
- Restart from known-good side

#### 4.2 Dual VG Activation
**Symptoms:**
- Same LV active on multiple hosts
- Conflicting writes
- Filesystem corruption

**Causes:**
- Lock failure not detected
- Manual activation bypassing locks
- Bug in lock manager

**Detection:**
```bash
# On all hosts
pdsh -w kvm[1-3] 'lvs --noheadings -o lv_name,lv_active vmstore'
# Same LV shows active on multiple hosts
```

**Impact:**
- **CATASTROPHIC**: Filesystem corruption
- Data loss
- VM disk corruption

**Recovery:**
- **STOP ALL VMs USING AFFECTED LVS**
- Deactivate LV on all but one host
- Run fsck on affected filesystems (offline)
- May require VM recovery from backups

### 5. Resource Exhaustion

#### 5.1 Disk Space Exhaustion on iSCSI LUN
**Symptoms:**
- Cannot create new LVs
- LV extend fails
- "No space left" errors

**Detection:**
```bash
vgs vmstore -o vg_free
# Shows zero or minimal free space

pvs /dev/sdb -o pv_free
# Shows no free space
```

**Impact:**
- Cannot create new VMs
- Cannot extend existing VM disks
- VMs may crash if they run out of disk

**Recovery:**
- Expand iSCSI LUN on target
- Rescan iSCSI device: `iscsiadm -m node --rescan`
- Resize PV: `pvresize /dev/sdb`
- Space now available

#### 5.2 Lock Space Exhaustion
**Symptoms:**
- Cannot acquire new locks
- LV activation fails with "no space for locks"

**Causes:**
- Too many LVs for available lock space
- Locks not released properly

**Detection:**
```bash
sanlock client status
# Shows lock space usage

lvs vmstore | wc -l
# Count of LVs
```

**Impact:**
- Cannot create new LVs
- Cannot activate additional LVs

**Recovery:**
- Remove unused LVs
- Extend lock space (complex, may require VG recreation)

### 6. Configuration Drift

#### 6.1 Mismatched LVM Configuration
**Symptoms:**
- Different /etc/lvm/lvm.conf settings across hosts
- Some hosts can't access VG
- Inconsistent behavior

**Detection:**
```bash
pdsh -w kvm[1-3] 'grep use_lvmlockd /etc/lvm/lvm.conf'
# Compare settings
```

**Impact:**
- Unpredictable behavior
- Some hosts may bypass locking

**Recovery:**
- Standardize lvm.conf across all hosts
- Restart lvmlockd on affected hosts

#### 6.2 Mismatched iSCSI Configuration
**Symptoms:**
- Different initiator names
- Different timeout settings
- Inconsistent session behavior

**Detection:**
```bash
pdsh -w kvm[1-3] 'cat /etc/iscsi/initiatorname.iscsi'
# Should all be unique

pdsh -w kvm[1-3] 'iscsiadm -m node -P 1 | grep timeout'
# Should be consistent
```

**Impact:**
- Inconsistent failover behavior
- Unpredictable performance

**Recovery:**
- Standardize critical settings
- May require session re-establishment

## Recovery Strategy Matrix

| Failure Type | Detection Priority | Auto-Remediation Safe? | Manual Steps Required |
|--------------|-------------------|------------------------|----------------------|
| Network interruption | High | Yes (retry) | Fix network |
| iSCSI target down | High | Yes (retry) | Fix target |
| Sanlock crashed | Critical | Yes (restart) | None |
| Lock expired | Critical | No (split-brain risk) | Stop VMs first |
| lvmlockd crashed | High | Yes (restart) | None |
| VG lock not started | Medium | Yes (restart) | None |
| Split-brain | Critical | No (corruption risk) | Manual recovery |
| Dual activation | Critical | No (corruption risk) | Stop VMs, deactivate |
| Lock corruption | Critical | No (data risk) | May need reset |
| Disk full | Medium | No (needs expansion) | Expand LUN |
| Config drift | Low | No (needs standardization) | Fix configs |

## Remediation Levels

### Level 1: Safe Automatic Remediation
- Restart crashed services
- Re-login to iSCSI
- Restart VG locks (if no other hosts have them)
- Refresh libvirt pool

### Level 2: Semi-Automatic with Checks
- Stop specific VMs before lock operations
- Deactivate LVs before lock restart
- Verify no dual access before proceeding

### Level 3: Manual Intervention Required
- Split-brain recovery
- Lock corruption repair
- Dual activation cleanup
- Network partition recovery

### Level 4: Nuclear Option (Last Resort)
- Stop all VMs on all hosts
- Deactivate all LVs on all hosts
- Stop all locks on all hosts
- Clear lock space
- Reinitialize from scratch

## When to Use Each Level

**Level 1**: Use when:
- Single host affected
- Services crashed but no lock loss
- Network interruption recovered
- No VMs running on affected resources

**Level 2**: Use when:
- VMs running but can be stopped safely
- Lock state uncertain
- Preventive maintenance
- Planned recovery

**Level 3**: Use when:
- Split-brain suspected
- Data corruption possible
- Multiple hosts affected
- Inconsistent lock state across cluster

**Level 4**: Use when:
- All else failed
- Corruption confirmed
- Starting fresh required
- **Accept VM data may be lost**

## Best Practices to Prevent Failures

1. **Network Redundancy**: Use dedicated storage network, consider multipath
2. **Monitoring**: Alert on iSCSI session state, sanlock status, lock expirations
3. **Testing**: Regularly test failover scenarios in non-production
4. **Documentation**: Document recovery procedures specific to your environment
5. **Automation**: Create runbooks for common failures
6. **Backups**: Regular VM backups independent of shared storage
7. **Capacity Planning**: Monitor disk usage, leave headroom
8. **Configuration Management**: Ansible to maintain consistent configs
9. **Timeouts**: Tune iSCSI and sanlock timeouts appropriately
10. **Validation**: Run validation tests after any maintenance

## Next Steps

See the following task files for implementation:
- `tasks/diagnose_storage_health.yml` - Detection and diagnosis
- `tasks/remediate_storage_issues.yml` - Automated remediation
- `tasks/reset_storage_cluster.yml` - Nuclear option recovery
