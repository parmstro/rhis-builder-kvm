# iSCSI Shared Storage Quick Start Guide

This guide shows how to configure iSCSI shared storage for KVM live migration using the `kvm_iscsi_lvmlock` role.

## Prerequisites

1. **KVM hosts provisioned** via Satellite with `kvm_host` role applied
2. **iSCSI target** (e.g., Synology NAS) with a shared LUN
3. **Network connectivity** from all KVM hosts to iSCSI target (port 3260)
4. **Same CPU generation** on all KVM hosts for migration compatibility

## Step 1: Configure Your iSCSI Target (Synology Example)

On your Synology NAS:

1. Open **Storage Manager** → **iSCSI**
2. Create a new **iSCSI Target**:
   - Name: `kvm-storage`
   - IQN: `iqn.2024-01.ca.example:kvm-storage`
   - Enable **Multiple Sessions** (allow all KVM hosts)
3. Create a **LUN**:
   - Size: 500GB - 1TB (depending on needs)
   - Thin provisioning: Recommended for lab
4. Map the LUN to the target
5. Configure **Access**:
   - Option A: IP-based ACL (add all KVM host IPs)
   - Option B: CHAP authentication (recommended)

Note the:
- Target IQN
- Target IP address
- CHAP credentials (if using)

## Step 2: Update Your Inventory

In your `rhis-builder-inventory` or local inventory, ensure you have:

```yaml
kvm_hosts:
  hosts:
    kvm1.example.ca:
    kvm2.example.ca:
    kvm3.example.ca:
```

## Step 3: Configure Variables

Create or update your variables file (e.g., `group_vars/kvm_hosts/iscsi.yml`):

```yaml
---
# iSCSI Target
iscsi_target_iqn: "iqn.2024-01.ca.example:kvm-storage"
iscsi_target_ip: "192.168.252.100"
iscsi_target_port: 3260

# Optional: CHAP authentication
iscsi_chap_username: "kvm-cluster"
iscsi_chap_password: "{{ vault_iscsi_password }}"  # Use ansible-vault

# LVM Configuration
lvm_device: "/dev/sdb"  # Update after iSCSI discovery if different
lvm_vg_name: "vmstore"

# Storage Pool
storage_pool_name: "vmstore"
```

## Step 4: Run the Configuration

### Option A: Using the Helper Script

```bash
cd /rhis/rhis-builder-kvm
./configure_kvm_iscsi_storage.sh
```

### Option B: Using Ansible Directly

```bash
cd /rhis/rhis-builder-kvm
ansible-playbook \
  -i your_inventory \
  -e "@your_vars.yml" \
  configure_kvm_iscsi_storage.yml
```

### Option C: Using run_role.yml

```bash
ansible-playbook \
  -i your_inventory \
  -e "role_name=kvm_iscsi_lvmlock" \
  -e "vars_path=your_vars.yml" \
  run_role.yml
```

## Step 5: Automatic Validation

The role automatically validates the configuration. Watch for the validation summary:

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

If all validation tests pass, proceed to Step 6. If validation fails, see the [Troubleshooting](#troubleshooting) section.

### Run Validation Manually

You can re-run validation anytime:

```bash
./validate_kvm_iscsi_storage.sh
```

For detailed validation information, see `roles/kvm_iscsi_lvmlock/VALIDATION_GUIDE.md`.

## Step 6: Manual Verification (Optional)

If you want to verify manually on **each KVM host**:

### Check iSCSI Session

```bash
iscsiadm -m session
# Should show: tcp: [1] 192.168.252.100:3260,1 iqn.2024-01.ca.example:kvm-storage
```

### Check Volume Group

```bash
vgs vmstore -o +locktype,lockargs
# Should show locktype: sanlock
```

### Check Services

```bash
systemctl status sanlock lvmlockd
# Both should be active (running)
```

### Check Libvirt Pool

```bash
virsh pool-list --all
# Should show vmstore as active and autostart
```

## Step 7: Create Your First VM

### Create a disk volume

```bash
virsh vol-create-as vmstore myvm-disk 20G
```

### Verify volume on all hosts

```bash
# On each host
virsh vol-list vmstore
# Should show myvm-disk on all hosts
```

### Create VM using the shared storage

```bash
virt-install \
  --name myvm \
  --memory 4096 \
  --vcpus 2 \
  --disk pool=vmstore,size=20 \
  --network bridge=br0 \
  --graphics none \
  --console pty,target_type=serial \
  --location http://satellite.example.ca/pub/RHEL-9/ \
  --extra-args 'console=ttyS0,115200n8'
```

## Step 8: Test Live Migration

### Start VM on first host

```bash
virsh start myvm
virsh console myvm  # Watch it boot
```

### Migrate to second host

```bash
virsh migrate --live --persistent --undefinesource --verbose \
  myvm qemu+tls://kvm2.example.ca/system
```

### Verify migration

```bash
# On kvm1.example.ca
virsh list --all
# myvm should not be listed

# On kvm2.example.ca  
virsh list --all
# myvm should be running
```

## Troubleshooting

### iSCSI device not appearing

```bash
# Check discovery
iscsiadm -m discovery -t st -p 192.168.252.100

# Check all devices
lsblk

# Check kernel messages
dmesg | grep -i iscsi
```

### VG not visible on other hosts

```bash
# Rescan
vgscan --cache

# Check physical volumes
pvs

# Check if lock is started
vgchange --lockstatus vmstore
```

### Pool won't start

```bash
# Check VG is active
vgs vmstore

# Check lock is started
vgchange --lockstatus vmstore

# Try starting manually
virsh pool-start vmstore

# Check libvirt logs
journalctl -u libvirtd -f
```

### Migration fails

```bash
# Verify TLS certificates (kvm_host role should have configured this)
virsh -c qemu+tls://kvm2.example.ca/system list

# Check firewall
firewall-cmd --list-all

# Check if VM is using shared storage
virsh domblklist myvm
# Should show path in /dev/vmstore/
```

## Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "No route to host" | Firewall blocking iSCSI | `firewall-cmd --add-service=iscsi-target --permanent && firewall-cmd --reload` |
| "Device not found" | Wrong lvm_device path | Run `lsblk` after iSCSI login, update variable |
| "VG not found" | First host not complete | Wait for first host to finish, then retry others |
| "Lock failed" | sanlock not running | `systemctl start sanlock && systemctl start lvmlockd` |
| Migration hangs | Network issue | Check migration network, bandwidth |

## Next Steps

- **Add more VMs**: Use the shared storage pool
- **Set up monitoring**: Monitor iSCSI sessions and lock health
- **Configure backup**: Set up VM backup strategy
- **Performance tuning**: Consider jumbo frames for storage network
- **High availability**: Look into clustered resource management

## Additional Resources

- Role README: `roles/kvm_iscsi_lvmlock/README.md`
- Implementation Notes: `roles/kvm_iscsi_lvmlock/IMPLEMENTATION_NOTES.md`
- Example Variables: `roles/kvm_iscsi_lvmlock/vars/example.yml`

## Getting Help

If you encounter issues:

1. Check logs: `journalctl -u iscsid -u sanlock -u lvmlockd -u libvirtd`
2. Review role documentation
3. Check iSCSI target configuration
4. Verify network connectivity between all components

---

**Note**: This guide assumes you're using the RHIS builder framework and have already provisioned your KVM hosts via Satellite. For brownfield environments, you may need to adjust inventory and variable paths.
