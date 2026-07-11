#!/bin/bash
#
# Configure iSCSI shared storage with LVM locking for KVM cluster
#
# This script configures shared storage for live migration across KVM hosts
# using iSCSI with LVM locking (lvmlockd + sanlock) - the modern replacement
# for deprecated GFS2.
#
# Prerequisites:
# - KVM hosts provisioned via Satellite
# - kvm_host role applied (TLS certificates configured)
# - iSCSI target (e.g., Synology NAS) with shared LUN accessible to all hosts
#
# Usage:
#   ./configure_kvm_iscsi_storage.sh [inventory_file] [vars_file]
#
# Examples:
#   ./configure_kvm_iscsi_storage.sh
#   ./configure_kvm_iscsi_storage.sh my_inventory my_vars.yml
#

INVENTORY="${1:-test_inventory}"
VARS_FILE="${2:-test_vars.yml}"

# Check if running in rhis-provisioner container
if [[ -d "/rhis" ]]; then
    PLAYBOOK_DIR="/rhis/rhis-builder-kvm"
else
    PLAYBOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

cd "$PLAYBOOK_DIR" || exit 1

echo "=================================================="
echo "Configuring iSCSI Shared Storage for KVM Cluster"
echo "=================================================="
echo ""
echo "Inventory: $INVENTORY"
echo "Variables: $VARS_FILE"
echo ""
echo "This will configure:"
echo "  - iSCSI initiator on all KVM hosts"
echo "  - LVM with shared locking (lvmlockd + sanlock)"
echo "  - Libvirt storage pool for VMs"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Run the playbook
ansible-playbook \
    -i "$INVENTORY" \
    -e "@$VARS_FILE" \
    configure_kvm_iscsi_storage.yml

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo ""
    echo "=================================================="
    echo "iSCSI Storage Configuration Complete!"
    echo "=================================================="
    echo ""
    echo "Next steps:"
    echo "  1. Verify on each host:"
    echo "     - virsh pool-list --all"
    echo "     - vgs vmstore -o +locktype,lockargs"
    echo "     - iscsiadm -m session"
    echo ""
    echo "  2. Create a test VM:"
    echo "     - virsh vol-create-as vmstore test-disk 10G"
    echo ""
    echo "  3. Test live migration:"
    echo "     - virsh migrate --live myvm qemu+tls://other-host/system"
    echo ""
else
    echo ""
    echo "=================================================="
    echo "Configuration failed with exit code: $exit_code"
    echo "=================================================="
    echo ""
    echo "Check the output above for errors."
    echo "Common issues:"
    echo "  - iSCSI target not accessible"
    echo "  - Incorrect IQN or device path"
    echo "  - Firewall blocking iSCSI port 3260"
    echo "  - First host VG creation not complete before other hosts import"
    echo ""
fi

exit $exit_code
