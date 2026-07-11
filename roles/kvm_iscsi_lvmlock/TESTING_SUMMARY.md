# Testing Summary for kvm_iscsi_lvmlock Role

## Validation Features Added

The `kvm_iscsi_lvmlock` role now includes comprehensive automated testing and validation capabilities.

## What Gets Validated

### 1. Infrastructure Layer
- ✓ iSCSI initiator configured correctly
- ✓ iSCSI session active to target
- ✓ iSCSI device accessible
- ✓ Auto-login configured for boot persistence

### 2. Lock Manager Layer
- ✓ sanlock service running and enabled
- ✓ lvmlockd service running and enabled
- ✓ LVM configured to use lvmlockd
- ✓ Lock infrastructure operational

### 3. Storage Layer
- ✓ Physical volume created on iSCSI device
- ✓ Volume group exists with shared flag
- ✓ Volume group using sanlock lock type
- ✓ VG lock started and active
- ✓ Autoactivation enabled

### 4. Libvirt Layer
- ✓ Storage pool defined for the VG
- ✓ Storage pool active
- ✓ Storage pool autostart enabled
- ✓ Pool capacity reported correctly

### 5. Cross-Host Functionality
- ✓ Test volume created on first host
- ✓ Test volume visible on all hosts via LVM
- ✓ Test volume visible on all hosts via libvirt
- ✓ Shared access working (prerequisite for live migration)

## Validation Workflow

```
┌─────────────────────────────────────────┐
│   Configure iSCSI Shared Storage        │
│   (kvm_iscsi_lvmlock role)              │
└────────────────┬────────────────────────┘
                 │
                 ├─> Install packages
                 ├─> Configure iSCSI
                 ├─> Setup locking
                 ├─> Create/import VG
                 ├─> Configure libvirt pool
                 │
                 ▼
┌─────────────────────────────────────────┐
│   Automatic Validation                  │
│   (if kvm_iscsi_validate_storage=true)  │
└────────────────┬────────────────────────┘
                 │
                 ├─> Check iSCSI session
                 ├─> Verify VG locking
                 ├─> Check services
                 ├─> Validate pool
                 ├─> Create test volume
                 ├─> Verify cross-host visibility
                 ├─> Clean up test volume
                 │
                 ▼
┌─────────────────────────────────────────┐
│   Report Results                        │
│   - Per-host validation status          │
│   - Summary report                      │
│   - Ready/Not Ready determination       │
└─────────────────────────────────────────┘
```

## Files Added for Validation

### Task Files
```
roles/kvm_iscsi_lvmlock/tasks/validate_iscsi_storage.yml
```
Contains all validation logic and tests.

### Playbooks
```
validate_kvm_iscsi_storage.yml
```
Standalone playbook to run validation independently.

### Scripts
```
validate_kvm_iscsi_storage.sh
```
Wrapper script for easy validation execution.

### Documentation
```
roles/kvm_iscsi_lvmlock/VALIDATION_GUIDE.md
```
Complete guide to validation tests and troubleshooting.

## Usage Examples

### 1. Validation Runs Automatically

By default, validation runs after initial configuration:

```bash
./configure_kvm_iscsi_storage.sh
```

Output will include validation results:
```
TASK [Validation: Summary report] ****************************
ok: [kvm1.example.ca] => {
    "msg": [
        "iSCSI Shared Storage Validation: PASSED",
        ...
    ]
}
```

### 2. Disable Automatic Validation

```yaml
# In your vars file
kvm_iscsi_validate_storage: false
```

### 3. Run Validation Manually Later

```bash
./validate_kvm_iscsi_storage.sh
```

### 4. Keep Test Volume for Inspection

```yaml
# In your vars file
kvm_iscsi_cleanup_test_volume: false
```

Then manually inspect:
```bash
lvs vmstore/kvm-validation-test
virsh vol-info --pool vmstore kvm-validation-test
```

Remove when done:
```bash
lvremove -f vmstore/kvm-validation-test
```

### 5. Run Validation from Ansible

```bash
ansible-playbook -i inventory validate_kvm_iscsi_storage.yml
```

## Test Volume Details

**Name**: `kvm-validation-test`  
**Size**: 1GB  
**Purpose**: Verify cross-host volume visibility  
**Created on**: First host in `groups['kvm_hosts'][0]`  
**Verified on**: All hosts in `groups['kvm_hosts']`  
**Lifecycle**: Created → Verified → Deleted (default)

## Success Criteria

All tests must pass for validation to succeed:

| Test | Success Criteria |
|------|------------------|
| iSCSI Session | Target IQN appears in active sessions |
| VG Shared Lock | VG shows `shared` flag and `sanlock` lock type |
| Lock Status | `vgchange --lockstatus` returns success |
| Services | sanlock and lvmlockd both active |
| Pool Status | Pool state is "active" |
| Pool Autostart | Pool autostart is enabled |
| Test Volume LVM | Volume visible via `lvs` on all hosts |
| Test Volume Libvirt | Volume visible via `virsh vol-list` on all hosts |

## Integration with Main Configuration

Validation is integrated into the main task flow:

```yaml
# roles/kvm_iscsi_lvmlock/tasks/main.yml

- name: "Install iSCSI and LVM locking packages"
  ansible.builtin.include_tasks: "ensure_iscsi_packages.yml"

- name: "Configure iSCSI initiator"
  ansible.builtin.include_tasks: "ensure_iscsi_initiator.yml"

- name: "Discover and connect to iSCSI target"
  ansible.builtin.include_tasks: "ensure_iscsi_connection.yml"

- name: "Enable and start sanlock service"
  ansible.builtin.include_tasks: "ensure_sanlock.yml"

- name: "Configure shared LVM volume group"
  ansible.builtin.include_tasks: "ensure_lvm_shared_vg.yml"

- name: "Configure libvirt storage pool"
  ansible.builtin.include_tasks: "ensure_libvirt_storage_pool.yml"

- name: "Validate iSCSI shared storage configuration"
  when: kvm_iscsi_validate_storage | default(true) | bool
  ansible.builtin.include_tasks: "validate_iscsi_storage.yml"
```

## Validation Variables

### Control Variables

```yaml
# Enable/disable validation
kvm_iscsi_validate_storage: true  # default

# Clean up test volume after validation
kvm_iscsi_cleanup_test_volume: true  # default
```

### Required Variables (from main role)

These must be set for validation to work:

```yaml
iscsi_target_iqn: "iqn.2024-01.ca.example:kvm-storage"
lvm_vg_name: "vmstore"
storage_pool_name: "vmstore"
```

## Troubleshooting Validation Failures

See [VALIDATION_GUIDE.md](VALIDATION_GUIDE.md) for detailed troubleshooting steps for each validation test.

Quick reference:

```bash
# Re-run validation with verbose output
ansible-playbook -i inventory -vvv validate_kvm_iscsi_storage.yml

# Check individual components
iscsiadm -m session
vgs vmstore -o +vg_shared,locktype
systemctl status sanlock lvmlockd
virsh pool-info vmstore

# Manual cross-host test
# On host1:
lvcreate -L 5G -n manual-test vmstore
# On host2 and host3:
lvs vmstore/manual-test
virsh vol-list vmstore | grep manual-test
```

## Continuous Validation

For production environments, schedule periodic validation:

### Using Cron
```bash
# Run validation daily at 2 AM
0 2 * * * cd /rhis/rhis-builder-kvm && ./validate_kvm_iscsi_storage.sh >> /var/log/iscsi-validation.log 2>&1
```

### Using Ansible Tower/AAP
Create a scheduled job template that runs `validate_kvm_iscsi_storage.yml` on a regular schedule.

## Benefits of Automated Validation

1. **Catch Issues Early**: Detect problems before they affect VMs
2. **Verify Configuration**: Confirm setup was successful
3. **Ongoing Monitoring**: Detect drift or degradation
4. **Documentation**: Validation output serves as proof of correct config
5. **Troubleshooting**: Pinpoint exactly which component is failing
6. **Confidence**: Know the system is ready for production use

## What Validation Doesn't Test

Validation confirms basic functionality but doesn't test:

- **Performance**: Throughput, latency, IOPS
- **Failure scenarios**: Network loss, service crashes
- **Actual live migration**: Real VM migration between hosts
- **Scale**: Behavior with many VMs or volumes
- **Backup/restore**: DR procedures

These should be tested separately as part of your operational procedures.

## Next Steps After Successful Validation

1. ✓ Configuration verified - proceed with confidence
2. Create production VMs on shared storage
3. Test live migration with real workloads
4. Implement monitoring for iSCSI sessions and locks
5. Document backup and DR procedures
6. Train operations team on maintenance procedures

## References

- [README.md](README.md) - Main role documentation
- [VALIDATION_GUIDE.md](VALIDATION_GUIDE.md) - Detailed validation guide
- [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md) - Technical architecture
- [../../ISCSI_QUICKSTART.md](../../ISCSI_QUICKSTART.md) - Quick start guide
