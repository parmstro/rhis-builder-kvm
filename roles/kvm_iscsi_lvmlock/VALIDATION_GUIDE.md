# iSCSI Shared Storage Validation Guide

This guide explains the validation tests performed by the `kvm_iscsi_lvmlock` role and how to interpret the results.

## Automatic Validation

By default, the role automatically runs validation tests after configuration. This can be controlled with:

```yaml
kvm_iscsi_validate_storage: true  # Enable/disable validation (default: true)
kvm_iscsi_cleanup_test_volume: true  # Remove test volume after validation (default: true)
```

## Validation Tests Performed

### 1. iSCSI Session Check

**What it tests**: Verifies active iSCSI session to the target

**Commands run**:
```bash
iscsiadm -m session -P 1
```

**Expected result**: Session shows as active with target IQN visible

**What it validates**:
- iSCSI initiator is configured correctly
- Network connectivity to iSCSI target
- Target is accepting connections
- Session will auto-reconnect on boot

**Failure scenarios**:
- Network connectivity issues
- Incorrect IQN
- CHAP authentication failure
- iSCSI target not accessible

### 2. Volume Group Shared Lock Verification

**What it tests**: Confirms VG is using shared locking with sanlock

**Commands run**:
```bash
vgs vmstore -o vg_name,vg_shared,vg_lock_type --noheadings
vgchange --lockstatus vmstore
```

**Expected result**: VG shows `vg_shared` flag and `sanlock` lock type

**What it validates**:
- VG was created with --shared flag
- sanlock is managing the lock
- Lock is active and functional
- Multiple hosts can access safely

**Failure scenarios**:
- VG created without --shared flag
- sanlock service not running
- Lock not started
- Conflicting lock holders

### 3. Lock Manager Services

**What it tests**: Ensures sanlock and lvmlockd are running

**Commands run**:
```bash
systemctl status sanlock
systemctl status lvmlockd
```

**Expected result**: Both services active and enabled

**What it validates**:
- Lock manager infrastructure is running
- Services will start on boot
- Locking mechanism is available

**Failure scenarios**:
- Services failed to start
- Services not enabled
- Configuration errors in /etc/lvm/lvm.conf

### 4. Libvirt Storage Pool Status

**What it tests**: Verifies storage pool is active and accessible

**Commands run**:
```bash
virsh pool-info vmstore
```

**Expected result**: Pool state is "active", autostart is "yes"

**What it validates**:
- Libvirt can access the LVM VG
- Pool will start automatically on boot
- Pool is ready for volume creation

**Failure scenarios**:
- VG not active or locked
- Pool definition incorrect
- libvirtd not running

### 5. Cross-Host Volume Visibility Test

**What it tests**: Creates a test LV on first host and verifies all hosts can see it

**Commands run** (on first host):
```bash
lvcreate -L 1G -n kvm-validation-test vmstore
```

**Commands run** (on all hosts):
```bash
lvs vmstore/kvm-validation-test --noheadings -o lv_name
virsh vol-list vmstore --details
```

**Expected result**: Test volume visible on all hosts in both LVM and libvirt

**What it validates**:
- Shared locking allows concurrent access
- LVM metadata updates propagate across hosts
- Libvirt can enumerate volumes from shared VG
- Foundation for live migration is working

**Failure scenarios**:
- Volume only visible on first host (locking issue)
- LVM sees volume but libvirt doesn't (pool refresh needed)
- Timeout waiting for propagation (network/lock delay)

## Running Validation Manually

### Option 1: Standalone Validation Script

```bash
cd /rhis/rhis-builder-kvm
./validate_kvm_iscsi_storage.sh
```

This runs only the validation tests without reconfiguring anything.

### Option 2: Re-run Full Configuration with Validation

```bash
cd /rhis/rhis-builder-kvm
./configure_kvm_iscsi_storage.sh
```

This runs the full configuration plus validation.

### Option 3: Ansible Playbook Directly

```bash
ansible-playbook -i inventory validate_kvm_iscsi_storage.yml
```

### Option 4: Skip Validation During Initial Setup

```bash
ansible-playbook \
  -i inventory \
  -e "kvm_iscsi_validate_storage=false" \
  configure_kvm_iscsi_storage.yml
```

Then run validation later when ready.

## Understanding Validation Output

### Successful Validation

```
TASK [Validation: Summary report] ****************************
ok: [kvm1.example.ca] => {
    "msg": [
        "=========================================",
        "iSCSI Shared Storage Validation: PASSED",
        "=========================================",
        "Host: kvm1",
        "iSCSI Session: Active",
        "Volume Group: vmstore (shared, sanlock)",
        "Storage Pool: vmstore (active)",
        "Services: sanlock ✓, lvmlockd ✓",
        "Cross-host visibility: ✓",
        "",
        "Ready for VM deployment and live migration!"
    ]
}
```

This means all tests passed and the system is ready for production use.

### Failed Validation Example

```
TASK [Validation: Verify volume group is using shared locking] ***
fatal: [kvm1.example.ca]: FAILED! => {
    "assertion": "'sanlock' in vg_shared_check.stdout",
    "msg": "Volume group vmstore is not using sanlock"
}
```

This indicates the VG was created without shared locking. Resolution:
1. Remove the VG: `vgremove vmstore`
2. Re-run configuration ensuring --shared flag

## Manual Validation Commands

If you want to verify manually without Ansible:

### Check iSCSI Sessions
```bash
# On each host
iscsiadm -m session
# Should show: tcp: [1] 192.168.252.100:3260,1 iqn.2024-01.ca.example:kvm-storage
```

### Check Volume Group
```bash
# On each host
vgs vmstore -o +vg_shared,locktype,lockargs
# Should show: shared flag, locktype=sanlock
```

### Check Lock Status
```bash
# On each host
vgchange --lockstatus vmstore
# Should show lock status for each LV
```

### Check Services
```bash
# On each host
systemctl status sanlock lvmlockd
# Both should be active (running)
```

### Check Storage Pool
```bash
# On each host
virsh pool-info vmstore
# State should be: active
# Autostart should be: yes
```

### Test Volume Creation and Visibility
```bash
# On kvm1
lvcreate -L 5G -n test-visibility vmstore

# On kvm2 and kvm3 (wait a few seconds)
lvs vmstore/test-visibility
virsh vol-list vmstore | grep test-visibility

# Cleanup
lvremove -f vmstore/test-visibility
```

## Validation Test Volume Cleanup

The validation creates a 1GB test volume named `kvm-validation-test`. By default, this is automatically cleaned up after validation completes.

**To keep the test volume** (for manual inspection):
```yaml
kvm_iscsi_cleanup_test_volume: false
```

**To manually remove it later**:
```bash
lvremove -f vmstore/kvm-validation-test
```

## Continuous Validation

For production environments, consider setting up periodic validation:

### Cron-based Validation
```bash
# Add to cron on one KVM host
0 */6 * * * cd /rhis/rhis-builder-kvm && ./validate_kvm_iscsi_storage.sh >> /var/log/iscsi-validation.log 2>&1
```

### Ansible Tower/AAP Scheduled Job
Create a scheduled job template that runs `validate_kvm_iscsi_storage.yml` daily or weekly.

### Monitoring Integration
Parse the validation output and send to your monitoring system (Prometheus, Nagios, etc.)

## Troubleshooting Failed Validations

### iSCSI Session Validation Fails

**Symptoms**:
- "No active sessions" error
- Target IQN not found in session list

**Diagnosis**:
```bash
# Check iSCSI service
systemctl status iscsid iscsi

# Try manual discovery
iscsiadm -m discovery -t st -p 192.168.252.100

# Check network
ping 192.168.252.100
telnet 192.168.252.100 3260

# Review logs
journalctl -u iscsid -u iscsi
```

**Fix**:
```bash
# Restart iSCSI
systemctl restart iscsid iscsi

# Re-login to target
iscsiadm -m node --targetname iqn.2024-01.ca.example:kvm-storage --login
```

### Volume Group Lock Validation Fails

**Symptoms**:
- VG not showing as shared
- Lock type not sanlock
- Lock status check fails

**Diagnosis**:
```bash
# Check services
systemctl status sanlock lvmlockd

# Check VG creation
vgs vmstore -o +vg_shared,locktype

# Check LVM config
grep use_lvmlockd /etc/lvm/lvm.conf
```

**Fix**:
```bash
# Start services
systemctl start sanlock lvmlockd

# If VG not shared, recreate:
vgremove vmstore
pvcreate /dev/sdb
vgcreate --shared vmstore /dev/sdb
vgchange --lock-start vmstore
```

### Cross-Host Visibility Validation Fails

**Symptoms**:
- Test volume only visible on first host
- Timeout waiting for volume to appear
- LVM sees it but libvirt doesn't

**Diagnosis**:
```bash
# Check if all hosts have VG
vgs vmstore

# Check lock status
vgchange --lockstatus vmstore

# Check libvirt pool refresh
virsh pool-refresh vmstore
```

**Fix**:
```bash
# On hosts where volume not visible
vgscan --cache
vgchange --lock-start vmstore
virsh pool-refresh vmstore
```

## Best Practices

1. **Run validation after any changes** to storage configuration
2. **Include validation in CI/CD** pipelines for infrastructure changes
3. **Set up alerts** for validation failures in production
4. **Document baseline** validation results for comparison
5. **Test live migration** as final validation step

## Validation vs Testing

**Validation** (automated by role):
- Verifies configuration is correct
- Checks services are running
- Confirms basic functionality
- Fast and non-disruptive

**Testing** (manual, recommended before production):
- Create actual VMs on shared storage
- Perform real live migrations
- Test failure scenarios (service crashes, network issues)
- Measure performance under load
- Verify backup/restore procedures

## Next Steps After Successful Validation

1. **Deploy a test VM**:
   ```bash
   virsh vol-create-as vmstore test-vm-disk 20G
   virt-install --name test-vm --disk pool=vmstore,size=20 ...
   ```

2. **Test live migration**:
   ```bash
   virsh migrate --live test-vm qemu+tls://kvm2.example.ca/system
   ```

3. **Set up monitoring** for iSCSI sessions and locks

4. **Configure backups** for VMs on shared storage

5. **Document procedures** for your team

## Additional Resources

- Main README: `roles/kvm_iscsi_lvmlock/README.md`
- Implementation Notes: `roles/kvm_iscsi_lvmlock/IMPLEMENTATION_NOTES.md`
- Quick Start Guide: `ISCSI_QUICKSTART.md`
