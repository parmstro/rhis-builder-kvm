# KVM iSCSI Storage Logging Guide

This guide explains the logging capabilities of the `kvm_iscsi_lvmlock` role for monitoring storage health and troubleshooting issues.

## Overview

The role provides multiple logging outputs suitable for different use cases:

1. **JSON logs** - Structured machine-readable format
2. **Syslog-compatible logs** - Traditional syslog format
3. **System logger integration** - Direct to syslog via `logger` command
4. **Optional rsyslog configuration** - Centralized logging setup

## Log Formats

### JSON Format (`/var/log/kvm-storage-health.json`)

Complete structured data suitable for log aggregation tools (Splunk, ELK, etc.):

```json
{
    "timestamp": "2026-07-10T23:45:12Z",
    "hostname": "kvm1.example.ca",
    "facility": "local0",
    "severity": "info",
    "priority": 6,
    "application": "kvm-storage-health",
    "message_type": "health_check",
    "overall_status": "healthy",
    "remediation_level": 0,
    "components": {
        "iscsi_session": true,
        "iscsi_device": true,
        "sanlock": true,
        "lvmlockd": true,
        "volume_group": true,
        "vg_lock_type": true,
        "vg_locked": true,
        "storage_pool": true
    },
    "issues": [],
    "vms_on_storage": 3,
    "target_iqn": "iqn.2024-01.ca.example:kvm-storage",
    "volume_group": "vmstore",
    "storage_pool": "vmstore"
}
```

### Syslog Format (`/var/log/kvm-storage-health.log`)

Traditional syslog format for easy parsing:

```
2026-07-10T23:45:12Z kvm1 kvm-storage-health[12345]: status=healthy remediation_level=0 issues=0 components_ok=7/7 vms=3 details=none
```

For degraded state:
```
2026-07-10T23:50:15Z kvm2 kvm-storage-health[12346]: status=degraded remediation_level=2 issues=2 components_ok=5/7 vms=1 details=sanlock_not_running,vg_not_locked
```

For critical state:
```
2026-07-10T23:55:20Z kvm3 kvm-storage-health[12347]: status=critical remediation_level=3 issues=4 components_ok=3/7 vms=0 details=iscsi_session_failed,sanlock_not_running,vg_not_locked,pool_not_active
```

### System Logger Messages

Messages sent via `logger` command appear in `/var/log/messages` (or wherever syslog directs local0 facility):

```
Jul 10 23:45:12 kvm1 kvm-storage-health: status=healthy remediation_level=0 issues=0 iscsi_ok=True sanlock_ok=True lvmlockd_ok=True vg_locked=True pool_active=True vms=3
```

## Log Fields Explained

| Field | Values | Description |
|-------|--------|-------------|
| `overall_status` | healthy, degraded, critical | Overall health assessment |
| `remediation_level` | 0-3 | Recovery complexity (0=no issues, 3=manual required) |
| `severity` | info, warning, crit | Syslog severity level |
| `priority` | 6, 4, 2 | Numeric syslog priority |
| `issues` | Array of strings | List of detected issues |
| `components_ok` | X/7 | Fraction of components healthy |
| `vms` | Number | VMs using shared storage |

### Component Checks

1. `iscsi_session` - iSCSI session to target is active
2. `iscsi_device` - Block device is present
3. `sanlock` - Sanlock daemon running
4. `lvmlockd` - lvmlockd daemon running
5. `volume_group` - VG exists and accessible
6. `vg_lock_type` - VG using correct lock type (sanlock)
7. `vg_locked` - VG lock is active
8. `storage_pool` - Libvirt pool is active

### Issue Codes

| Issue Code | Meaning | Remediation Level |
|------------|---------|-------------------|
| `iscsi_session_failed` | No active iSCSI session | 1 (auto) |
| `iscsi_device_missing` | Block device not present | 2 (semi-auto) |
| `sanlock_not_running` | Sanlock service stopped | 1 (auto) |
| `lvmlockd_not_running` | lvmlockd service stopped | 1 (auto) |
| `vg_not_found` | Volume group missing | 3 (manual) |
| `vg_lock_type_incorrect` | VG not using sanlock | 3 (manual) |
| `vg_not_locked` | VG lock not started | 2 (semi-auto) |
| `pool_not_active` | Libvirt pool inactive | 1 (auto) |

## Configuration Options

### Enable/Disable Logging

```yaml
# defaults/main.yml or your variables file

# Save diagnostic reports to log files
kvm_iscsi_save_diagnostics: true  # default: true

# Send diagnostic results to syslog via logger command
kvm_iscsi_use_logger: true  # default: true

# Configure rsyslog for structured logging
kvm_iscsi_setup_rsyslog: false  # default: false
```

### Remote Syslog Configuration

```yaml
# Enable rsyslog setup
kvm_iscsi_setup_rsyslog: true

# Remote syslog server
kvm_iscsi_rsyslog_server: "syslog.example.ca"
kvm_iscsi_rsyslog_port: 514  # default: 514
kvm_iscsi_rsyslog_protocol: "tcp"  # default: tcp, options: tcp, udp

# Optional: Email alerts for critical events
kvm_iscsi_rsyslog_email: "ops-team@example.ca"
kvm_iscsi_smtp_server: "smtp.example.ca"
kvm_iscsi_smtp_port: 25
```

## Rsyslog Integration

When `kvm_iscsi_setup_rsyslog: true`, the role configures rsyslog:

### Installed Configuration

File: `/etc/rsyslog.d/20-kvm-storage-health.conf`

Features:
- Dedicated log files for each component
- Optional remote forwarding
- Critical event notifications
- Integration with system logging

### Log Files Created

```
/var/log/kvm-storage-health.log   # Health check results
/var/log/kvm-storage-health.json  # JSON format
/var/log/sanlock.log              # Sanlock daemon messages
/var/log/lvmlockd.log             # lvmlockd daemon messages
/var/log/iscsi.log                # iSCSI kernel/daemon messages
```

### Log Rotation

Logs are automatically rotated:
- Daily rotation
- Keep 30 days
- Compress old logs
- Configuration: `/etc/logrotate.d/kvm-storage-health`

## Monitoring Integration

### Prometheus Node Exporter (Textfile Collector)

Convert JSON log to Prometheus metrics:

```bash
#!/bin/bash
# /usr/local/bin/kvm-storage-metrics.sh

JSON_LOG="/var/log/kvm-storage-health.json"
METRICS_FILE="/var/lib/node_exporter/textfile_collector/kvm_storage.prom"

if [ -f "$JSON_LOG" ]; then
    STATUS=$(jq -r '.overall_status' $JSON_LOG)
    STATUS_NUM=0
    case "$STATUS" in
        healthy) STATUS_NUM=0 ;;
        degraded) STATUS_NUM=1 ;;
        critical) STATUS_NUM=2 ;;
    esac
    
    cat > $METRICS_FILE << EOF
# HELP kvm_storage_health Overall storage health status
# TYPE kvm_storage_health gauge
kvm_storage_health{hostname="$(hostname -f)"} $STATUS_NUM

# HELP kvm_storage_remediation_level Required remediation level
# TYPE kvm_storage_remediation_level gauge
kvm_storage_remediation_level{hostname="$(hostname -f)"} $(jq -r '.remediation_level' $JSON_LOG)

# HELP kvm_storage_issues_count Number of issues detected
# TYPE kvm_storage_issues_count gauge
kvm_storage_issues_count{hostname="$(hostname -f)"} $(jq -r '.issues | length' $JSON_LOG)

# HELP kvm_storage_vms_count VMs on shared storage
# TYPE kvm_storage_vms_count gauge
kvm_storage_vms_count{hostname="$(hostname -f)"} $(jq -r '.vms_on_storage' $JSON_LOG)

# HELP kvm_storage_component_status Individual component health
# TYPE kvm_storage_component_status gauge
kvm_storage_component_status{hostname="$(hostname -f)",component="iscsi_session"} $(jq -r '.components.iscsi_session' $JSON_LOG | sed 's/true/1/;s/false/0/')
kvm_storage_component_status{hostname="$(hostname -f)",component="sanlock"} $(jq -r '.components.sanlock' $JSON_LOG | sed 's/true/1/;s/false/0/')
kvm_storage_component_status{hostname="$(hostname -f)",component="lvmlockd"} $(jq -r '.components.lvmlockd' $JSON_LOG | sed 's/true/1/;s/false/0/')
kvm_storage_component_status{hostname="$(hostname -f)",component="vg_locked"} $(jq -r '.components.vg_locked' $JSON_LOG | sed 's/true/1/;s/false/0/')
EOF
fi
```

Run via cron every 5 minutes.

### Splunk Integration

Splunk configuration for JSON ingestion:

```ini
[monitor:///var/log/kvm-storage-health.json]
sourcetype = kvm:storage:health
index = infrastructure
disabled = false

[kvm:storage:health]
KV_MODE = json
TIME_PREFIX = "timestamp":\"
TIME_FORMAT = %Y-%m-%dT%H:%M:%SZ
MAX_TIMESTAMP_LOOKAHEAD = 30
```

Example Splunk search:
```spl
index=infrastructure sourcetype="kvm:storage:health" 
| stats latest(overall_status) as status, 
        latest(remediation_level) as level,
        latest(vms_on_storage) as vms
  by hostname
```

### ELK Stack (Elasticsearch, Logstash, Kibana)

Logstash configuration:

```ruby
input {
  file {
    path => "/var/log/kvm-storage-health.json"
    codec => "json"
    type => "kvm-storage-health"
  }
}

filter {
  if [type] == "kvm-storage-health" {
    date {
      match => [ "timestamp", "ISO8601" ]
      target => "@timestamp"
    }
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "kvm-storage-health-%{+YYYY.MM.dd}"
  }
}
```

### Nagios/Icinga Checks

```bash
#!/bin/bash
# /usr/lib64/nagios/plugins/check_kvm_storage

JSON_LOG="/var/log/kvm-storage-health.json"

if [ ! -f "$JSON_LOG" ]; then
    echo "UNKNOWN: Log file not found"
    exit 3
fi

STATUS=$(jq -r '.overall_status' $JSON_LOG)
LEVEL=$(jq -r '.remediation_level' $JSON_LOG)
ISSUES=$(jq -r '.issues | length' $JSON_LOG)

case "$STATUS" in
    healthy)
        echo "OK: Storage healthy | issues=0 level=0"
        exit 0
        ;;
    degraded)
        echo "WARNING: Storage degraded - $ISSUES issues (level $LEVEL) | issues=$ISSUES level=$LEVEL"
        exit 1
        ;;
    critical)
        echo "CRITICAL: Storage critical - $ISSUES issues (level $LEVEL) | issues=$ISSUES level=$LEVEL"
        exit 2
        ;;
    *)
        echo "UNKNOWN: Status=$STATUS"
        exit 3
        ;;
esac
```

## Log Analysis Examples

### Find All Issues in Last 24 Hours

```bash
# From syslog format
grep kvm-storage-health /var/log/kvm-storage-health.log | \
  grep -v "status=healthy" | \
  tail -24

# From JSON format
jq 'select(.issues | length > 0)' /var/log/kvm-storage-health.json
```

### Count Issue Types

```bash
jq -r '.issues[]' /var/log/kvm-storage-health.json | \
  sort | uniq -c | sort -rn
```

### Track Remediation Level Over Time

```bash
awk '{print $1,$2,$5}' /var/log/kvm-storage-health.log | \
  sed 's/remediation_level=//' | \
  column -t
```

### Identify VMs at Risk

```bash
# When storage is degraded/critical
jq -r 'select(.overall_status != "healthy") | .vms_on_storage' \
  /var/log/kvm-storage-health.json
```

## Troubleshooting Logging

### Logs Not Being Created

Check permissions:
```bash
ls -la /var/log/kvm-storage-health*
```

Check if diagnostics enabled:
```bash
grep kvm_iscsi_save_diagnostics /path/to/your/vars.yml
```

### Syslog Messages Not Appearing

Check logger works:
```bash
logger -t kvm-storage-health -p local0.info "Test message"
tail /var/log/messages | grep kvm-storage-health
```

Check rsyslog configuration:
```bash
rsyslogd -N1  # Syntax check
systemctl status rsyslog
```

### Remote Forwarding Not Working

Test connectivity:
```bash
telnet syslog.example.ca 514
```

Check rsyslog config:
```bash
grep -A 5 kvm-storage-health /etc/rsyslog.d/20-kvm-storage-health.conf
```

Check rsyslog errors:
```bash
journalctl -u rsyslog | tail -50
```

## Best Practices

1. **Enable JSON logging** for machine parsing and aggregation
2. **Use remote syslog** for centralized monitoring in production
3. **Set up alerts** based on `overall_status` and `remediation_level`
4. **Review logs daily** or integrate with your monitoring system
5. **Archive logs** beyond 30 days for compliance/analysis
6. **Test alerting** by simulating failures in non-production
7. **Document** your specific alert thresholds and response procedures
8. **Automate** log analysis with scheduled checks

## Next Steps

- Configure your SIEM/monitoring system to ingest logs
- Set up alerting rules for critical/degraded states
- Create dashboards for storage health visualization
- Integrate with your existing incident management system
- Document your team's escalation procedures

## References

- [FAILURE_MODES.md](FAILURE_MODES.md) - Detailed failure scenarios
- [diagnose_storage_health.yml](tasks/diagnose_storage_health.yml) - Diagnostic task implementation
- Rsyslog documentation: https://www.rsyslog.com/doc/
