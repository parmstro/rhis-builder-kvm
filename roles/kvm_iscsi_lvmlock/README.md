# kvm_iscsi_lvmlock

Configure iSCSI shared storage with LVM locking (lvmlockd + sanlock) for KVM live migration.

This role replaces the deprecated GFS2 approach with the modern RHEL 9/10 supported solution for shared block storage in KVM clusters.

## Description

This role:
- Installs and configures iSCSI initiator on KVM hosts
- Connects to shared iSCSI storage
- Sets up LVM with shared locking using sanlock
- Creates a libvirt storage pool for VM storage
- Enables seamless live migration between KVM hosts

## Requirements

- RHEL 9 or later (GFS2 is deprecated in RHEL 10)
- iSCSI target (e.g., Synology NAS) with a shared LUN
- All KVM hosts must be able to connect to the iSCSI target simultaneously
- Same CPU generation on all KVM hosts (for live migration compatibility)

## Validation

The role includes comprehensive validation tests that automatically run after configuration (can be disabled). Validation tests verify:

- ✓ iSCSI sessions are active
- ✓ Volume groups use shared locking with sanlock
- ✓ Lock manager services are running
- ✓ Libvirt storage pools are functional
- ✓ Volumes are visible across all hosts
- ✓ Live migration prerequisites are met

### Running Validation

**Automatic** (runs by default after configuration):
```yaml
kvm_iscsi_validate_storage: true  # default
```

**Manual validation anytime**:
```bash
./validate_kvm_iscsi_storage.sh
```

For detailed validation information, see [VALIDATION_GUIDE.md](VALIDATION_GUIDE.md).

## Role Variables

### Required Variables

```yaml
# iSCSI target configuration
iscsi_target_iqn: "iqn.2024-01.ca.example:kvm-storage"
iscsi_target_ip: "192.168.1.100"
iscsi_target_port: 3260

# LVM device (update after iSCSI discovery shows the actual device)
lvm_device: "/dev/sdb"
```

### Optional Variables

```yaml
# iSCSI CHAP authentication (leave empty to disable)
iscsi_chap_username: ""
iscsi_chap_password: ""

# LVM Volume Group name
lvm_vg_name: "vmstore"

# Libvirt storage pool configuration
storage_pool_name: "vmstore"
storage_pool_path: "/dev/vmstore"

# Async task parameters
kvm_iscsi_async_timeout: 300
kvm_iscsi_async_delay: 10

# Validation options
kvm_iscsi_validate_storage: true      # Run validation tests (default: true)
kvm_iscsi_cleanup_test_volume: true   # Remove test volume after validation (default: true)
```

## Dependencies

- community.libvirt collection
- community.general collection

Install with:
```bash
ansible-galaxy collection install community.libvirt community.general
```

## Example Playbook

```yaml
---
- name: Configure KVM cluster with iSCSI shared storage
  hosts: kvm_hosts
  become: true
  vars:
    iscsi_target_iqn: "iqn.2024-01.ca.parmstrong:kvm-storage"
    iscsi_target_ip: "192.168.252.100"
    lvm_device: "/dev/sdb"
    lvm_vg_name: "vmstore"
    
  roles:
    - kvm_iscsi_lvmlock
```

## How It Works

### First Host (groups['kvm_hosts'][0])

1. Installs iSCSI initiator and LVM locking packages
2. Configures unique iSCSI initiator name
3. Discovers and logs into iSCSI target
4. Enables sanlock and lvmlockd services
5. Creates physical volume on iSCSI device
6. Creates shared volume group with `--shared` flag
7. Starts the VG lock
8. Defines and starts libvirt LVM storage pool

### Subsequent Hosts

1. Same steps 1-4 as first host
2. Imports the shared volume group
3. Starts the VG lock
4. Defines and starts libvirt storage pool

### Result

All hosts can:
- Create LVs in the shared volume group
- Use the storage pool for VM disks
- Perform live migration of VMs between hosts
- Access VM storage simultaneously with proper locking

## Usage

### Creating VMs

```bash
# Create a 20GB volume for a VM
virsh vol-create-as vmstore myvm-disk 20G

# Or create directly with virt-install
virt-install \
  --name myvm \
  --memory 2048 \
  --vcpus 2 \
  --disk pool=vmstore,size=20 \
  --network bridge=br0 \
  --graphics none \
  --console pty,target_type=serial \
  --location http://satellite.example.ca/pub/RHEL-9.5/ \
  --extra-args 'console=ttyS0,115200n8'
```

### Live Migration

```bash
# Migrate VM from current host to target-host
virsh migrate --live --persistent --undefinesource \
  myvm qemu+tls://target-host.example.ca/system
```

## Troubleshooting

### Check iSCSI Connection

```bash
# View active iSCSI sessions
iscsiadm -m session

# Check iSCSI device
lsblk /dev/sdb
```

### Check LVM Status

```bash
# View volume group
vgs vmstore -o +locktype,lockargs

# Check lock status
vgchange --lockstatus vmstore

# View physical volume
pvs /dev/sdb
```

### Check Libvirt Pool

```bash
# List pools
virsh pool-list --all

# Pool details
virsh pool-info vmstore

# List volumes
virsh vol-list vmstore
```

### Common Issues

**iSCSI device not appearing:**
- Check network connectivity to iSCSI target
- Verify IQN is correct
- Check iSCSI target allows multiple initiators

**VG import fails:**
- Ensure first host completed VG creation
- Run `vgscan --cache` to refresh
- Check all hosts can see the iSCSI device

**Lock failures:**
- Verify sanlock is running: `systemctl status sanlock`
- Check lvmlockd is running: `systemctl status lvmlockd`
- Verify `/etc/lvm/lvm.conf` has `use_lvmlockd = 1`

## License

GPL-3.0-or-later

## Author

Paul Armstrong
