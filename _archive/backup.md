 ```bash
    echo "6. CLOUD BACKUPS:"
    if command -v rclone >/dev/null 2>&1; then
        if timeout 10 rclone lsd googledrive: >/dev/null 2>&1; then
            cloud_size=$(rclone size googledrive:prj/ 2>/dev/null | grep "Total size:" | awk '{print $3, $4}')
            echo "   Google Drive: Available ($cloud_size)"
        else
            echo "   Google Drive: Connection failed"
        fi
    else
        echo "   rclone not available"
    fi
    
    if [ -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs/prj_backup" ]; then
        icloud_size=$(du -sh "$HOME/Library/Mobile Documents/com~apple~CloudDocs/prj_backup" 2>/dev/null | cut -f1)
        echo "   iCloud: Available ($icloud_size)"
    else
        echo "   iCloud: Not available"
    fi
}

perform_recovery() {
    echo ""
    echo "=== RECOVERY COMMANDS ==="
    echo ""
    
    echo "To recover from Grey Drive snapshot (replace TIMESTAMP):"
    echo "  rsync -av /Volumes/PrjSnapshots/snapshot_TIMESTAMP/ ~/prj_recovered/"
    echo ""
    
    echo "To recover from Blue Drive mirror:"
    echo "  rsync -av /Volumes/PrjMirror/current/ ~/prj_recovered/"
    echo ""
    
    echo "To recover from weekly archive (replace DATE):"
    echo "  cd ~ && tar -xzf /Volumes/PrjArchive/weekly/prj_weekly_DATE.tar.gz"
    echo "  mv ~/prj ~/prj_recovered"
    echo ""
    
    echo "To recover from Git:"
    echo "  git clone https://github.com/rgt47/prj-backup.git ~/prj_recovered"
    echo ""
    
    echo "To recover from Time Machine:"
    echo "  Open Time Machine app, navigate to ~/prj, select date, click Restore"
    echo ""
    
    echo "To recover from Google Drive:"
    echo "  rclone sync googledrive:prj/ ~/prj_recovered/"
    echo ""
    
    echo "To recover from iCloud:"
    echo "  rsync -av \"~/Library/Mobile Documents/com~apple~CloudDocs/prj_backup/\" ~/prj_recovered/"
    echo ""
    
    echo "=== PARTIAL RECOVERY (Single file/directory) ==="
    echo ""
    
    echo "Find a specific file across all backups:"
    echo "  find /Volumes/PrjSnapshots -name \"filename\" -type f 2>/dev/null"
    echo "  find /Volumes/PrjMirror -name \"filename\" -type f 2>/dev/null"
    echo ""
    
    echo "Compare versions of a file:"
    echo "  diff ~/prj/path/to/file /Volumes/PrjMirror/current/path/to/file"
    echo ""
    
    echo "Restore single directory from latest snapshot:"
    latest_snapshot=$(ls -1t /Volumes/PrjSnapshots/snapshot_* 2>/dev/null | head -1)
    if [ -n "$latest_snapshot" ]; then
        echo "  rsync -av \"$latest_snapshot/subdirectory/\" ~/prj/subdirectory/"
    fi
}

# Main execution
show_recovery_options
perform_recovery

echo ""
echo "=== RECOVERY VERIFICATION ==="
echo "After recovery, verify with:"
echo "  du -sh ~/prj_recovered"
echo "  find ~/prj_recovered -type d | wc -l  # Should be ~300"
echo "  find ~/prj_recovered -type f | wc -l"
echo ""
echo "Compare with original (if still available):"
echo "  diff -r ~/prj ~/prj_recovered"
```

Make executable:
```bash
chmod +x ~/Scripts/recovery_helper.sh
```

---

## Part 9: Performance Optimization and Monitoring

### Step 1: Create Performance Tuning Script
```bash
vim ~/Scripts/optimize_backups.sh
```

Add content:
```bash
#!/bin/bash

echo "=== BACKUP PERFORMANCE OPTIMIZATION ==="
echo "Optimizing for 20GB across 300 subdirectories"
echo ""

# Check current system resources
echo "Current system status:"
echo "Memory: $(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')KB free"
echo "CPU load: $(uptime | awk '{print $10, $11, $12}')"
echo "Disk I/O: $(iostat -c 2 | tail -1 | awk '{print "user:", $1, "sys:", $2, "idle:", $3}')"
echo ""

# Optimize rsync settings
echo "Recommended rsync optimizations for large directories:"
echo "  --partial-dir=/tmp/rsync-partial"
echo "  --inplace (for large files)"
echo "  --compress-level=1 (for network transfers)"
echo "  --itemize-changes (for detailed logging)"
echo ""

# Check file system cache
echo "File system cache status:"
purge >/dev/null 2>&1 && echo "Cache purged for accurate testing" || echo "Cache purge not available"

# Monitor backup performance
if pgrep -f "prj_backup.sh" >/dev/null; then
    echo "Backup currently running - monitoring performance:"
    backup_pid=$(pgrep -f "prj_backup.sh")
    echo "PID: $backup_pid"
    ps -p $backup_pid -o pid,pcpu,pmem,time,command
    
    # Monitor for 30 seconds
    echo "Monitoring for 30 seconds..."
    for i in {1..6}; do
        sleep 5
        cpu_usage=$(ps -p $backup_pid -o pcpu= 2>/dev/null | tr -d ' ')
        mem_usage=$(ps -p $backup_pid -o pmem= 2>/dev/null | tr -d ' ')
        echo "  $((i*5))s: CPU: ${cpu_usage}%, Memory: ${mem_usage}%"
    done
else
    echo "No backup currently running"
fi

echo ""
echo "Optimization recommendations:"
echo "1. Run backups during low-activity periods"
echo "2. Consider splitting large subdirectories if backup takes >30 minutes"
echo "3. Use SSD drives for faster I/O"
echo "4. Ensure adequate free space (>25GB) on backup drives"
echo "5. Monitor network bandwidth for cloud backups"
```

### Step 2: Create Backup Health Check
```bash
vim ~/Scripts/backup_health.sh
```

Add content:
```bash
#!/bin/bash

LOG_FILE="$HOME/Scripts/health_check.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

echo "[$TIMESTAMP] Starting backup health check" | tee -a "$LOG_FILE"

# Function to check backup integrity
check_backup_integrity() {
    local backup_path="$1"
    local backup_name="$2"
    
    if [ ! -d "$backup_path" ]; then
        echo "❌ $backup_name: Directory not found" | tee -a "$LOG_FILE"
        return 1
    fi
    
    # Count directories and files
    local dir_count=$(find "$backup_path" -type d 2>/dev/null | wc -l | tr -d ' ')
    local file_count=$(find "$backup_path" -type f 2>/dev/null | wc -l | tr -d ' ')
    local size=$(du -sh "$backup_path" 2>/dev/null | cut -f1)
    
    echo "✅ $backup_name: $dir_count dirs, $file_count files, $size" | tee -a "$LOG_FILE"
    
    # Check if counts are reasonable (assuming ~300 dirs, varies for files)
    if [ "$dir_count" -lt 250 ]; then
        echo "⚠️  $backup_name: Directory count seems low ($dir_count < 250)" | tee -a "$LOG_FILE"
    fi
    
    return 0
}

echo ""
echo "=== BACKUP INTEGRITY CHECK ==="

# Check original directory
check_backup_integrity "$HOME/prj" "Original Project"

# Check USB backups
if [ -d "/Volumes/PrjSnapshots" ]; then
    latest_snapshot=$(ls -1t /Volumes/PrjSnapshots/snapshot_* 2>/dev/null | head -1)
    if [ -n "$latest_snapshot" ]; then
        check_backup_integrity "$latest_snapshot" "Latest Grey Snapshot"
    fi
fi

check_backup_integrity "/Volumes/PrjMirror/current" "Blue Drive Mirror"

# Check cloud backup
if command -v rclone >/dev/null 2>&1; then
    if timeout 10 rclone lsd googledrive: >/dev/null 2>&1; then
        cloud_dirs=$(rclone lsd googledrive:prj/ 2>/dev/null | wc -l | tr -d ' ')
        cloud_size=$(rclone size googledrive:prj/ 2>/dev/null | grep "Total size:" | awk '{print $3, $4}')
        echo "✅ Google Drive: $cloud_dirs top-level dirs, $cloud_size" | tee -a "$LOG_FILE"
    else
        echo "❌ Google Drive: Connection failed" | tee -a "$LOG_FILE"
    fi
fi

# Check Git repository
if [ -d "$HOME/prj/.git" ]; then
    cd "$HOME/prj"
    if git status >/dev/null 2>&1; then
        uncommitted=$(git status --porcelain | wc -l | tr -d ' ')
        last_commit=$(git log -1 --format='%cd' --date=short 2>/dev/null)
        echo "✅ Git Repository: Last commit $last_commit, $uncommitted uncommitted files" | tee -a "$LOG_FILE"
    else
        echo "❌ Git Repository: Status check failed" | tee -a "$LOG_FILE"
    fi
fi

# Check recent backup activity
echo ""
echo "=== RECENT BACKUP ACTIVITY ==="
if [ -f "$HOME/Scripts/backup.log" ]; then
    echo "Last successful backup:"
    grep "completed successfully" "$HOME/Scripts/backup.log" | tail -1 | tee -a "$LOG_FILE"
    
    echo ""
    echo "Recent errors:"
    grep "ERROR" "$HOME/Scripts/backup.log" | tail -3 | tee -a "$LOG_FILE"
else
    echo "❌ No backup log found" | tee -a "$LOG_FILE"
fi

# Check disk space
echo ""
echo "=== DISK SPACE CHECK ==="
df -h | grep -E "(PrjSnapshots|PrjMirror|PrjArchive|TimeMachine)" | while read line; do
    usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
    mount=$(echo "$line" | awk '{print $9}')
    if [ "$usage" -gt 90 ]; then
        echo "⚠️  $mount: ${usage}% full" | tee -a "$LOG_FILE"
    else
        echo "✅ $mount: ${usage}% used" | tee -a "$LOG_FILE"
    fi
done

echo ""
echo "Health check completed: $TIMESTAMP" | tee -a "$LOG_FILE"
```

Make scripts executable:
```bash
chmod +x ~/Scripts/optimize_backups.sh
chmod +x ~/Scripts/backup_health.sh
```

---

## Part 10: Final Setup and Testing

### Step 1: Complete System Test
```bash
vim ~/Scripts/system_test.sh
```

Add comprehensive test:
```bash
#!/bin/bash

echo "=== COMPREHENSIVE BACKUP SYSTEM TEST ==="
echo "Testing backup system for ~/prj (20GB, 300 subdirs)"
echo ""

# Create test environment
TEST_DIR="$HOME/prj_test_$(date +%s)"
mkdir -p "$TEST_DIR"

echo "1. Creating test data..."
# Create test structure similar to real project
for i in {1..10}; do
    mkdir -p "$TEST_DIR/subdir_$i"
    echo "Test content $i" > "$TEST_DIR/subdir_$i/file_$i.txt"
done

echo "2. Testing backup script..."
# Temporarily modify backup script to use test directory
sed "s|HOME/prj|HOME/$(basename $TEST_DIR)|g" ~/Scripts/prj_backup.sh > ~/Scripts/test_backup.sh
chmod +x ~/Scripts/test_backup.sh

# Run test backup
if ~/Scripts/test_backup.sh; then
    echo "✅ Backup script test passed"
else
    echo "❌ Backup script test failed"
fi

echo "3. Testing recovery..."
# Test recovery from blue drive
if [ -d "/Volumes/PrjMirror/current" ]; then
    mkdir -p "$HOME/recovery_test"
    if rsync -av "/Volumes/PrjMirror/current/" "$HOME/recovery_test/" >/dev/null 2>&1; then
        echo "✅ Recovery test passed"
        rm -rf "$HOME/recovery_test"
    else
        echo "❌ Recovery test failed"
    fi
fi

echo "4. Testing Git functionality..."
cd "$TEST_DIR"
git init >/dev/null 2>&1
git add . >/dev/null 2>&1
git commit -m "Test commit" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ Git test passed"
else
    echo "❌ Git test failed"
fi

echo "5. Testing monitoring scripts..."
if ~/Scripts/backup_status.sh >/dev/null 2>&1; then
    echo "✅ Status script test passed"
else
    echo "❌ Status script test failed"
fi

# Cleanup
rm -rf "$TEST_DIR"
rm -f ~/Scripts/test_backup.sh

echo ""
echo "System test completed. Check individual components if any tests failed."
```

### Step 2: Create Quick Reference Card
```bash
vim ~/Scripts/QUICK_REFERENCE.md
```

Add content:
```markdown
# PROJECT BACKUP SYSTEM - QUICK REFERENCE

## System Overview
- **Project**: ~/prj (20GB, ~300 subdirectories)
- **USB Drives**: grey (Time Machine + Snapshots), blue (Mirror + Archives)
- **Git**: https://github.com/rgt47/prj-backup.git
- **Cloud**: Google Drive, iCloud (secondary)

## Daily Commands
```bash
# Check system status
~/Scripts/backup_status.sh

# Manual backup
~/Scripts/prj_backup.sh

# Health check
~/Scripts/backup_health.sh

# Recovery helper
~/Scripts/recovery_helper.sh
```

## Vim Commands (in ~/prj)
```vim
:BackupStatus    " System status
:BackupNow       " Manual backup
:BackupPerf      " Performance check
:GitBackup       " Git commit & push
<leader>bs       " Quick status
<leader>bn       " Quick backup
```

## Emergency Recovery
1. **Latest changes**: Grey drive snapshots in `/Volumes/PrjSnapshots/`
2. **Complete mirror**: Blue drive `/Volumes/PrjMirror/current/`
3. **Historical**: Weekly archives in `/Volumes/PrjArchive/weekly/`
4. **Version control**: `git clone https://github.com/rgt47/prj-backup.git`

## Backup Schedule
- **Hourly**: Automated local backups (USB + cloud)
- **Daily**: Git push (6 PM)
- **Weekly**: Compressed archives (Sunday 2 AM), iCloud sync (Sunday 8 PM)
- **Monthly**: Long-term archives (first Sunday)

## Troubleshooting
- **Logs**: `~/Scripts/backup.log`, `~/Scripts/git_backup.log`
- **Performance**: `~/Scripts/optimize_backups.sh`
- **Drive space**: `df -h | grep -E "(Prj|Time)"`
- **Process check**: `ps aux | grep backup`

## Important Paths
- Scripts: `~/Scripts/`
- Grey snapshots: `/Volumes/PrjSnapshots/`
- Blue mirror: `/Volumes/PrjMirror/current/`
- Blue archives: `/Volumes/PrjArchive/weekly/`
- iCloud: `~/Library/Mobile Documents/com~apple~CloudDocs/prj_backup/`
```

### Step 3: Final System Verification
```bash
# Run complete system test
chmod +x ~/Scripts/system_test.sh
~/Scripts/system_test.sh

# Verify all cron jobs
crontab -l

# Verify launch agents
launchctl list | grep backup

# Initial status check
~/Scripts/backup_status.sh

# Run initial backup
~/Scripts/prj_backup.sh

# Verify Git setup
cd ~/prj
git status
git log --oneline -5

echo "Setup complete! Check ~/Scripts/QUICK_REFERENCE.md for daily usage."
```

---

## Summary

Your comprehensive backup system is now configured for your 20GB ~/prj directory with 300 subdirectories:

**Automated Backups:**
- **Hourly**: Time Machine, USB snapshots (grey), USB mirror (blue), Google Drive
- **Daily**: Git commits to github.com/rgt47/prj-backup
- **Weekly**: Compressed archives, iCloud sync

**Storage Allocation:**
- **Grey Drive (1TB)**: 800GB Time Machine + 200GB project snapshots
- **Blue Drive (1TB)**: 600GB current mirror + 400GB compressed archives

**Recovery Options:**
- Recent changes: Grey drive hourly snapshots
- Complete current state: Blue drive mirror
- Historical versions: Weekly/monthly compressed archives
- Version control: Git repository
- Cloud backups: Google Drive (primary), iCloud (secondary)

**Monitoring:**
- Comprehensive status checking
- Performance monitoring
- Health verification
- Vim integration for easy access

The system is optimized for your large directory structure and provides multiple layers of protection against data loss.
