#!/bin/bash
#
# Validate iSCSI shared storage configuration
#
# This script runs validation tests to ensure iSCSI shared storage is
# working correctly across all KVM hosts.
#
# Usage:
#   ./validate_kvm_iscsi_storage.sh [inventory_file] [vars_file]
#
# Examples:
#   ./validate_kvm_iscsi_storage.sh
#   ./validate_kvm_iscsi_storage.sh my_inventory my_vars.yml
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
echo "Validating iSCSI Shared Storage Configuration"
echo "=================================================="
echo ""
echo "Inventory: $INVENTORY"
echo "Variables: $VARS_FILE"
echo ""
echo "This will validate:"
echo "  - iSCSI sessions are active"
echo "  - Volume groups are accessible and locked"
echo "  - Storage pools are functional"
echo "  - Cross-host volume visibility"
echo "  - Live migration prerequisites"
echo ""

# Run the validation playbook
ansible-playbook \
    -i "$INVENTORY" \
    -e "@$VARS_FILE" \
    validate_kvm_iscsi_storage.yml

exit_code=$?

echo ""
if [ $exit_code -eq 0 ]; then
    echo "=================================================="
    echo "✓ Validation Passed!"
    echo "=================================================="
    echo ""
    echo "All checks passed. Your iSCSI shared storage is"
    echo "correctly configured and ready for use."
    echo ""
    echo "You can now:"
    echo "  • Deploy VMs using the storage pool"
    echo "  • Perform live migrations between hosts"
    echo "  • Create shared volumes visible to all hosts"
    echo ""
else
    echo "=================================================="
    echo "✗ Validation Failed"
    echo "=================================================="
    echo ""
    echo "One or more validation checks failed."
    echo "Review the output above to identify issues."
    echo ""
    echo "Common problems:"
    echo "  • iSCSI session not established"
    echo "  • sanlock/lvmlockd services not running"
    echo "  • Volume group not shared or locked"
    echo "  • Storage pool not active"
    echo "  • Network connectivity issues"
    echo ""
    echo "For troubleshooting, see:"
    echo "  roles/kvm_iscsi_lvmlock/README.md"
    echo ""
fi

exit $exit_code
