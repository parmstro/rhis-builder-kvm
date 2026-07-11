# kvm_iscsi_lvmlock Implementation Notes

## Overview

This role implements iSCSI shared storage with LVM locking for KVM live migration clusters. It replaces the deprecated GFS2 approach with the modern RHEL 9/10 supported solution using `lvmlockd` and `sanlock`.

## Architecture

### Storage Stack

```
┌─────────────────────────────────────────┐
│     Libvirt Storage Pool (vmstore)      │
│          (LVM Logical Volumes)          │
├─────────────────────────────────────────┤
│   LVM Volume Group (vmstore) - Shared   │
│     with lvmlockd + sanlock locking     │
├─────────────────────────────────────────┤
│      Physical Volume on iSCSI LUN       │
├─────────────────────────────────────────┤
│         iSCSI Target (Synology NAS)     │
└─────────────────────────────────────────┘
```

### Multi-Host Setup

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   KVM Host1  │    │   KVM Host2  │    │   KVM Host3  │
│              │    │              │    │              │
│  lvmlockd    │    │  lvmlockd    │    │  lvmlockd    │
│  sanlock     │    │  sanlock     │    │  sanlock     │
│  iscsid      │    │  iscsid      │    │  iscsid      │
└──────┬───────┘    └──────┬───────┘    └──────┬───────┘
       │                   │                   │
       │    iSCSI (port 3260)                 │
       └───────────────────┴───────────────────┘
                          │
                  ┌───────┴────────┐
                  │  Synology NAS  │
                  │   iSCSI Target │
                  │   Shared LUN   │
                  └────────────────┘
```

## Role Structure

```
kvm_iscsi_lvmlock/
├── defaults/
│   └── main.yml                    # Default variables
├── handlers/
│   └── main.yml                    # Service restart handlers
├── meta/
│   └── main.yml                    # Role metadata
├── tasks/
│   ├── main.yml                    # Main task orchestration
│   ├── ensure_iscsi_packages.yml   # Install required packages
│   ├── ensure_iscsi_initiator.yml  # Configure iSCSI initiator
│   ├── ensure_iscsi_connection.yml # Connect to iSCSI target
│   ├── ensure_sanlock.yml          # Configure sanlock/lvmlockd
│   ├── ensure_lvm_shared_vg.yml    # Create/import shared VG
│   └── ensure_libvirt_storage_pool.yml # Configure libvirt pool
├── templates/
│   └── initiatorname.iscsi.j2      # iSCSI initiator name template
├── vars/
│   └── example.yml                 # Example variable file
├── README.md                       # User documentation
└── IMPLEMENTATION_NOTES.md         # This file
```

## Execution Flow

### First Host (groups['kvm_hosts'][0])

1. **Package Installation**
   - iscsi-initiator-utils
   - lvm2-lockd
   - sanlock

2. **iSCSI Configuration**
   - Set unique initiator name: `iqn.2024-01.{domain}:{hostname}`
   - Optional: Configure CHAP authentication
   - Start iscsid and iscsi services

3. **iSCSI Connection**
   - Discover targets from iSCSI server
   - Login to specified target
   - Configure automatic login on boot
   - Wait for device to appear

4. **Lock Manager Setup**
   - Start sanlock service
   - Start lvmlockd service
   - Configure `/etc/lvm/lvm.conf` to use lvmlockd

5. **Volume Group Creation**
   - Create physical volume on iSCSI device
   - Create shared VG: `vgcreate --shared vmstore /dev/sdb`
   - Start VG lock: `vgchange --lock-start vmstore`
   - Enable autoactivation

6. **Libvirt Pool**
   - Define LVM storage pool
   - Start and enable autostart

### Subsequent Hosts

Steps 1-4 are identical, then:

5. **Volume Group Import**
   - Wait for first host to complete
   - Scan for volume groups
   - Import shared VG: `vgimport --shared vmstore`
   - Start VG lock: `vgchange --lock-start vmstore`
   - Enable autoactivation

6. **Libvirt Pool**
   - Same as first host

## Key Design Decisions

### Sequential VG Creation

The role uses `inventory_hostname == groups['kvm_hosts'][0]` to ensure only one host creates the VG. Other hosts wait and import. This prevents race conditions during initial setup.

### Idempotency

- All tasks check for existing configuration before making changes
- `failed_when` clauses handle "already exists" scenarios gracefully
- Commands use `changed_when` to accurately report changes

### Error Handling

- iSCSI login handles "already logged in" gracefully
- VG import handles "already exists" gracefully
- Device availability checked with `wait_for` module

### Security

- CHAP password tasks use `no_log: true`
- Initiator names are unique per host
- TLS for libvirt (configured by kvm_host role)

## Integration with rhis-builder-kvm

This role complements the existing roles:

- **kvm_host**: Configures base KVM functionality and TLS certificates
- **kvm_iscsi_lvmlock**: Adds shared storage (this role)
- **kvm_pools**: Can create additional pools
- **kvm_networks**: Network configuration
- **kvm_volumes**: Can create volumes in the shared pool

## Testing Checklist

After running the role, verify:

```bash
# On all hosts:
iscsiadm -m session                    # Should show active session
vgs vmstore -o +locktype,lockargs      # Should show "sanlock" lock type
systemctl status sanlock lvmlockd      # Should be active
virsh pool-list --all                  # Should show vmstore active

# Create test volume (on any host):
virsh vol-create-as vmstore test 10G

# Verify volume visible on all hosts:
virsh vol-list vmstore

# Test live migration:
# 1. Create a VM using the shared storage
# 2. Start the VM on host1
# 3. Migrate to host2: virsh migrate --live myvm qemu+tls://host2/system
```

## Troubleshooting Guide

### iSCSI Issues

**Symptom**: Device doesn't appear after login

**Check**:
```bash
iscsiadm -m session                    # Any active sessions?
dmesg | grep -i iscsi                  # Kernel messages
journalctl -u iscsid -u iscsi          # Service logs
```

**Fix**: Verify network connectivity, IQN, and target configuration

### LVM Lock Issues

**Symptom**: VG import fails or lock won't start

**Check**:
```bash
systemctl status sanlock lvmlockd      # Services running?
journalctl -u sanlock -u lvmlockd      # Service logs
vgscan --cache                         # Refresh VG cache
```

**Fix**: Ensure sanlock is running before vgchange --lock-start

### Libvirt Pool Issues

**Symptom**: Pool won't start or shows inactive

**Check**:
```bash
virsh pool-dumpxml vmstore             # Pool configuration
vgs vmstore                            # VG accessible?
journalctl -u libvirtd                 # Libvirt logs
```

**Fix**: Ensure VG is active and locked before starting pool

## Future Enhancements

Potential improvements:

1. **Device Discovery**: Auto-detect iSCSI device instead of hardcoding
2. **Multipath Support**: Configure device-mapper multipath for redundancy
3. **Performance Tuning**: Add iSCSI and LVM performance tuning options
4. **Monitoring**: Add checks for lock health and iSCSI session status
5. **Firewall Rules**: Automatically configure firewall for iSCSI
6. **Network Tuning**: Jumbo frames, dedicated storage network

## References

- Red Hat: [LVM with shared storage](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_and_managing_logical_volumes/assembly_lvm-with-lvmlockd)
- Red Hat: [iSCSI Storage Configuration](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/managing_storage_devices/configuring-an-iscsi-initiator_managing-storage-devices)
- Red Hat: [KVM Live Migration](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_and_managing_virtualization/migrating-virtual-machines_configuring-and-managing-virtualization)

## License

GPL-3.0-or-later

## Author

Paul Armstrong (parmstro)
