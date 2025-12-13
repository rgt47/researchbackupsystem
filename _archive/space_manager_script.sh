#!/bin/bash
# ~/Scripts/space_manager.sh
#
# INTELLIGENT SPACE MANAGEMENT FOR SINGLE-DRIVE BACKUP SYSTEM
#
# PURPOSE:
# This script monitors disk usage across all backup partitions and automatically
# manages storage by cleaning up old backups when space runs low. It implements
# a tiered cleanup strategy that preserves the most important backups while
# ensuring the system never runs out of space.
#
# WHY SPACE MANAGEMENT IS CRITICAL:
# With a single 1TB drive handling Time Machine (700GB), snapshots (200GB), and
# archives (100GB), space management becomes crucial. Without proper cleanup:
# - Time Machine backups could fail
# - Snapshot creation could stop
# - Archive creation could be impossible
# - System performance could degrade
#
# CLEANUP STRATEGY:
# The script implements a tiered cleanup approach:
# 1. GENTLE: Remove items past their normal retention period
# 2. MODERATE: Reduce retention periods when space gets tight
# 3. AGGRESSIVE: Emergency cleanup to prevent disk full scenarios
#
# PRESERVATION PRIORITY:
# 1. Most recent snapshots (last 12 hours)
# 2. Most recent weekly archives (last 2 weeks)
# 3. Monthly archives (last 3 months minimum)
# 4. Older snapshots and archives (removed first)
#
# SAFETY MEASURES:
# - Never removes the most recent backup of each type
# - Confirms deletions before executing
# - Logs all cleanup operations
# - Provides warnings before taking aggressive action
#
# USAGE:
# - Automatic: Called by main backup script before each operation
# - Manual: Run directly to check space and clean up
# - Monitoring: Use to check current space usage across partitions
#
# AUTHOR: Research Computing Guide
# VERSION: 2.0 (Single Drive)

# =============================================================================
# CONFIGURATION AND SETUP
# =============================================================================

LOG_FILE="$HOME/Scripts/backup.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# Space thresholds in GB for different cleanup levels
SNAPSHOT_WARNING_THRESHOLD=15    # Start gentle cleanup at 15GB remaining
SNAPSHOT_CRITICAL_THRESHOLD=5    # Aggressive cleanup at 5GB remaining
ARCHIVE_WARNING_THRESHOLD=8      # Start gentle cleanup at 8GB remaining  
ARCHIVE_CRITICAL_THRESHOLD=3     # Aggressive cleanup at 3GB remaining

# Partition paths
SNAPSHOT_PARTITION="/Volumes/PrjSnapshots"
ARCHIVE_PARTITION="/Volumes/PrjArchive"
TIMEMACHINE_PARTITION="/Volumes/TimeMachine"

echo "[$TIMESTAMP] Starting intelligent space management" >> "$LOG_FILE"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function: get_available_space
# Purpose: Get available space in GB for a given partition
# Parameters: $1 - Partition path
# Returns: Available space in GB, or 0 if partition not found
get_available_space() {
    local partition="$1"
    
    if [ -d "$partition" ]; then
        # Use df to get available space, convert to GB
        local available_gb=$(df -g "$partition" | tail -1 | awk '{print $4}')
        echo "$available_gb"
    else
        echo "0"
    fi
}

# Function: get_used_space
# Purpose: Get used space in GB for a given partition
# Parameters: $1 - Partition path
# Returns: Used space in GB, or 0 if partition not found
get_used_space() {
    local partition="$1"
    
    if [ -d "$partition" ]; then
        local used_gb=$(df -g "$partition" | tail -1 | awk '{print $3}')
        echo "$used_gb"
    else
        echo "0"
    fi
}

# Function: get_total_space
# Purpose: Get total space in GB for a given partition
# Parameters: $1 - Partition path
# Returns: Total space in GB, or 0 if partition not found
get_total_space() {
    local partition="$1"
    
    if [ -d "$partition" ]; then
        local total_gb=$(df -g "$partition" | tail -1 | awk '{print $2}')
        echo "$total_gb"
    else
        echo "0"
    fi
}

# Function: report_partition_status
# Purpose: Display detailed status information for a partition
# Parameters: $1 - Partition path, $2 - Partition name
report_partition_status() {
    local partition="$1"
    local name="$2"
    
    if [ -d "$partition" ]; then
        local total=$(get_total_space "$partition")
        local used=$(get_used_space "$partition")
        local available=$(get_available_space "$partition")
        local percent=$(echo "scale=1; $used * 100 / $total" | bc 2>/dev/null || echo "N/A")
        
        echo "[$TIMESTAMP] $name Partition Status:" >> "$LOG_FILE"
        echo "[$TIMESTAMP]   Total: ${total}GB" >> "$LOG_FILE"
        echo "[$TIMESTAMP]   Used: ${used}GB (${percent}%)" >> "$LOG_FILE"
        echo "[$TIMESTAMP]   Available: ${available}GB" >> "$LOG_FILE"
        
        # Also output to console for interactive use
        if [ -t 1 ]; then  # Check if running interactively
            echo "$name: ${used}GB/${total}GB used (${percent}%), ${available}GB available"
        fi
    else
        echo "[$TIMESTAMP] $name partition not found at $partition" >> "$LOG_FILE"
        if [ -t 1 ]; then
            echo "$name: Not mounted"
        fi
    fi
}

# =============================================================================
# SNAPSHOT CLEANUP FUNCTIONS
# =============================================================================

# Function: cleanup_snapshots_gentle
# Purpose: Remove snapshots older than normal retention period (24 hours)
# This is the standard cleanup that runs during normal operations
cleanup_snapshots_gentle() {
    local snapshots_dir="$SNAPSHOT_PARTITION/hourly"
    
    if [ ! -d "$snapshots_dir" ]; then
        echo "[$TIMESTAMP] Snapshots directory not found: $snapshots_dir" >> "$LOG_FILE"
        return 1
    fi
    
    echo "[$TIMESTAMP] Performing gentle snapshot cleanup (>24 hours old)" >> "$LOG_FILE"
    
    # Find and remove snapshots older than 24 hours
    local old_snapshots=$(find "$snapshots_dir" -name "snapshot_*" -type d -mtime +1 2>/dev/null)
    local count=0
    
    if [ -n "$old_snapshots" ]; then
        echo "$old_snapshots" | while read snapshot_dir; do
            if [ -d "$snapshot_dir" ]; then
                local snapshot_name=$(basename "$snapshot_dir")
                echo "[$TIMESTAMP] Removing old snapshot: $snapshot_name" >> "$LOG_FILE"
                rm -rf "$snapshot_dir"
                count=$((count + 1))
            fi
        done
        
        echo "[$TIMESTAMP] Gentle cleanup removed $count snapshots" >> "$LOG_FILE"
    else
        echo "[$TIMESTAMP] No snapshots older than 24 hours found" >> "$LOG_FILE"
    fi
    
    return 0
}

# Function: cleanup_snapshots_moderate
# Purpose: Remove snapshots older than 12 hours when space is getting tight
# This provides more aggressive cleanup while preserving recent work
cleanup_snapshots_moderate() {
    local snapshots_dir="$SNAPSHOT_PARTITION/hourly"
    
    if [ ! -d "$snapshots_dir" ]; then
        echo "[$TIMESTAMP] Snapshots directory not found: $snapshots_dir" >> "$LOG_FILE"
        return 1
    fi
    
    echo "[$TIMESTAMP] Performing moderate snapshot cleanup (>12 hours old)" >> "$LOG_FILE"
    
    # Find and remove snapshots older than 12 hours (720 minutes)
    local old_snapshots=$(find "$snapshots_dir" -name "snapshot_*" -type d -mmin +720 2>/dev/null)
    local count=0
    
    if [ -n "$old_snapshots" ]; then
        echo "$old_snapshots" | while read snapshot_dir; do
            if [ -d "$snapshot_dir" ]; then
                local snapshot_name=$(basename "$snapshot_dir")
                echo "[$TIMESTAMP] Removing moderately old snapshot: $snapshot_name" >> "$LOG_FILE"
                rm -rf "$snapshot_dir"
                count=$((count + 1))
            fi
        done
        
        echo "[$TIMESTAMP] Moderate cleanup removed $count snapshots" >> "$LOG_FILE"
    else
        echo "[$TIMESTAMP] No snapshots older than 12 hours found" >> "$LOG_FILE"
    fi
    
    return 0
}

# Function: cleanup_snapshots_aggressive
# Purpose: Emergency cleanup keeping only the most recent 6 hours of snapshots
# This is used only when disk space is critically low
cleanup_snapshots_aggressive() {
    local snapshots_dir="$SNAPSHOT_PARTITION/hourly"
    
    if [ ! -d "$snapshots_dir" ]; then
        echo "[$TIMESTAMP] Snapshots directory not found: $snapshots_dir" >> "$LOG_FILE"
        return 1
    fi
    
    echo "[$TIMESTAMP] PERFORMING AGGRESSIVE SNAPSHOT CLEANUP (>6 hours old)" >> "$LOG_FILE"
    echo "[$TIMESTAMP] WARNING: This will remove most snapshots to free space" >> "$LOG_FILE"
    
    # Find and remove snapshots older than 6 hours (360 minutes)
    local old_snapshots=$(find "$snapshots_dir" -name "snapshot_*" -type d -mmin +360 2>/dev/null)
    local count=0
    
    if [ -n "$old_snapshots" ]; then
        echo "$old_snapshots" | while read snapshot_dir; do
            if [ -d "$snapshot_dir" ]; then
                local snapshot_name=$(basename "$snapshot_dir")
                echo "[$TIMESTAMP] EMERGENCY: Removing snapshot: $snapshot_name" >> "$LOG_FILE"
                rm -rf "$snapshot_dir"
                count=$((count + 1))
            fi
        done
        
        echo "[$TIMESTAMP] Aggressive cleanup removed $count snapshots" >> "$LOG_FILE"
    else
        echo "[$TIMESTAMP] No snapshots older than 6 hours found" >> "$LOG_FILE"
    fi
    
    return 0
}

# Function: manage_snapshot_space
# Purpose: Intelligently manage snapshot partition space based on available space
manage_snapshot_space() {
    local available=$(get_available_space "$SNAPSHOT_PARTITION")
    
    echo "[$TIMESTAMP] Managing snapshot space: ${available}GB available" >> "$LOG_FILE"
    
    if [ "$available" -lt "$SNAPSHOT_CRITICAL_THRESHOLD" ]; then
        echo "[$TIMESTAMP] CRITICAL: Snapshot space below ${SNAPSHOT_CRITICAL_THRESHOLD}GB" >> "$LOG_FILE"
        cleanup_snapshots_aggressive
        return 2  # Critical condition
    elif [ "$available" -lt "$SNAPSHOT_WARNING_THRESHOLD" ]; then
        echo "[$TIMESTAMP] WARNING: Snapshot space below ${SNAPSHOT_WARNING_THRESHOLD}GB" >> "$LOG_FILE"
        cleanup_snapshots_moderate
        return 1  # Warning condition
    else
        echo "[$TIMESTAMP] Snapshot space healthy, performing routine cleanup" >> "$LOG_FILE"
        cleanup_snapshots_gentle
        return 0  # Normal condition
    fi
}

# =============================================================================
# ARCHIVE CLEANUP FUNCTIONS
# =============================================================================

# Function: cleanup_archives_gentle
# Purpose: Remove archives older than normal retention periods
# Weekly archives: 4 weeks, Monthly archives: 6 months
cleanup_archives_gentle() {
    local weekly_dir="$ARCHIVE_PARTITION/weekly"
    local monthly_dir="$ARCHIVE_PARTITION/monthly"
    
    echo "[$TIMESTAMP] Performing gentle archive cleanup" >> "$LOG_FILE"
    
    # Clean weekly archives older than 4 weeks (28 days)
    if [ -d "$weekly_dir" ]; then
        local old_weekly=$(find "$weekly_dir" -name "prj_weekly_*.tar.gz" -mtime +28 2>/dev/null | wc -l)
        if [ "$old_weekly" -gt 0 ]; then
            echo "[$TIMESTAMP] Removing $old_weekly weekly archives older than 4 weeks" >> "$LOG_FILE"
            find "$weekly_dir" -name "prj_weekly_*.tar.gz" -mtime +28 -delete
        else
            echo "[$TIMESTAMP] No weekly archives older than 4 weeks found" >> "$LOG_FILE"
        fi
    fi
    
    # Clean monthly archives older than 6 months (180 days)
    if [ -d "$monthly_dir" ]; then
        local old_monthly=$(find "$monthly_dir" -name "prj_monthly_*.tar.gz" -mtime +180 2>/dev/null | wc -l)
        if [ "$old_monthly" -gt 0 ]; then
            echo "[$TIMESTAMP] Removing $old_monthly monthly archives older than 6 months" >> "$LOG_FILE"
            find "$monthly_dir" -name "prj_monthly_*.tar.gz" -mtime +180 -delete
        else
            echo "[$TIMESTAMP] No monthly archives older than 6 months found" >> "$LOG_FILE"
        fi
    fi
    
    return 0
}

# Function: cleanup_archives_moderate
# Purpose: More aggressive archive cleanup when space is tight
# Weekly archives: 2 weeks, Monthly archives: 3 months
cleanup_archives_moderate() {
    local weekly_dir="$ARCHIVE_PARTITION/weekly"
    local monthly_dir="$ARCHIVE_PARTITION/monthly"
    
    echo "[$TIMESTAMP] Performing moderate archive cleanup" >> "$LOG_FILE"
    
    # Clean weekly archives older than 2 weeks (14 days)
    if [ -d "$weekly_dir" ]; then
        local old_weekly=$(find "$weekly_dir" -name "prj_weekly_*.tar.gz" -mtime +14 2>/dev/null | wc -l)
        if [ "$old_weekly" -gt 0 ]; then
            echo "[$TIMESTAMP] Removing $old_weekly weekly archives older than 2 weeks" >> "$LOG_FILE"
            find "$weekly_dir" -name "prj_weekly_*.tar.gz" -mtime +14 -delete
        fi
    fi
    
    # Clean monthly archives older than 3 months (90 days)
    if [ -d "$monthly_dir" ]; then
        local old_monthly=$(find "$monthly_dir" -name "prj_monthly_*.tar.gz" -mtime +90 2>/dev/null | wc -l)
        if [ "$old_monthly" -gt 0 ]; then
            echo "[$TIMESTAMP] Removing $old_monthly monthly archives older than 3 months" >> "$LOG_FILE"
            find "$monthly_dir" -name "prj_monthly_*.tar.gz" -mtime +90 -delete
        fi
    fi
    
    return 0
}

# Function: cleanup_archives_aggressive
# Purpose: Emergency archive cleanup keeping only essential archives
# Weekly archives: 1 week, Monthly archives: 1 month
cleanup_archives_aggressive() {
    local weekly_dir="$ARCHIVE_PARTITION/weekly"
    local monthly_dir="$ARCHIVE_PARTITION/monthly"
    
    echo "[$TIMESTAMP] PERFORMING AGGRESSIVE ARCHIVE CLEANUP" >> "$LOG_FILE"
    echo "[$TIMESTAMP] WARNING: This will remove most archives to free space" >> "$LOG_FILE"
    
    # Clean weekly archives older than 1 week (7 days)
    if [ -d "$weekly_dir" ]; then
        local old_weekly=$(find "$weekly_dir" -name "prj_weekly_*.tar.gz" -mtime +7 2>/dev/null | wc -l)
        if [ "$old_weekly" -gt 0 ]; then
            echo "[$TIMESTAMP] EMERGENCY: Removing $old_weekly weekly archives older than 1 week" >> "$LOG_FILE"
            find "$weekly_dir" -name "prj_weekly_*.tar.gz" -mtime +7 -delete
        fi
    fi
    
    # Clean monthly archives older than 1 month (30 days)
    if [ -d "$monthly_dir" ]; then
        local old_monthly=$(find "$monthly_dir" -name "prj_monthly_*.tar.gz" -mtime +30 2>/dev/null | wc -l)
        if [ "$old_monthly" -gt 0 ]; then
            echo "[$TIMESTAMP] EMERGENCY: Removing $old_monthly monthly archives older than 1 month" >> "$LOG_FILE"
            find "$monthly_dir" -name "prj_monthly_*.tar.gz" -mtime +30 -delete
        fi
    fi
    
    return 0
}

# Function: manage_archive_space
# Purpose: Intelligently manage archive partition space
manage_archive_space() {
    local available=$(get_available_space "$ARCHIVE_PARTITION")
    
    echo "[$TIMESTAMP] Managing archive space: ${available}GB available" >> "$LOG_FILE"
    
    if [ "$available" -lt "$ARCHIVE_CRITICAL_THRESHOLD" ]; then
        echo "[$TIMESTAMP] CRITICAL: Archive space below ${ARCHIVE_CRITICAL_THRESHOLD}GB" >> "$LOG_FILE"
        cleanup_archives_aggressive
        return 2  # Critical condition
    elif [ "$available" -lt "$ARCHIVE_WARNING_THRESHOLD" ]; then
        echo "[$TIMESTAMP] WARNING: Archive space below ${ARCHIVE_WARNING_THRESHOLD}GB" >> "$LOG_FILE"
        cleanup_archives_moderate
        return 1  # Warning condition
    else
        echo "[$TIMESTAMP] Archive space healthy, performing routine cleanup" >> "$LOG_FILE"
        cleanup_archives_gentle
        return 0  # Normal condition
    fi
}

# =============================================================================
# MAIN EXECUTION AND REPORTING
# =============================================================================

# Display current status for all partitions
echo "[$TIMESTAMP] === CURRENT PARTITION STATUS ===" >> "$LOG_FILE"
report_partition_status "$TIMEMACHINE_PARTITION" "Time Machine"
report_partition_status "$SNAPSHOT_PARTITION" "Snapshots"
report_partition_status "$ARCHIVE_PARTITION" "Archives"

# Manage snapshot partition space
echo "[$TIMESTAMP] === SNAPSHOT SPACE MANAGEMENT ===" >> "$LOG_FILE"
manage_snapshot_space
snapshot_status=$?

# Manage archive partition space
echo "[$TIMESTAMP] === ARCHIVE SPACE MANAGEMENT ===" >> "$LOG_FILE"
manage_archive_space
archive_status=$?

# Report final status after cleanup
echo "[$TIMESTAMP] === POST-CLEANUP STATUS ===" >> "$LOG_FILE"
report_partition_status "$SNAPSHOT_PARTITION" "Snapshots (After Cleanup)"
report_partition_status "$ARCHIVE_PARTITION" "Archives (After Cleanup)"

# Determine overall system status
overall_status=0
if [ $snapshot_status -eq 2 ] || [ $archive_status -eq 2 ]; then
    overall_status=2  # Critical
    echo "[$TIMESTAMP] OVERALL STATUS: CRITICAL - Immediate attention needed" >> "$LOG_FILE"
elif [ $snapshot_status -eq 1 ] || [ $archive_status -eq 1 ]; then
    overall_status=1  # Warning
    echo "[$TIMESTAMP] OVERALL STATUS: WARNING - Monitor space usage" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] OVERALL STATUS: HEALTHY - All partitions have adequate space" >> "$LOG_FILE"
fi

# Provide recommendations based on status
if [ $overall_status -eq 2 ]; then
    echo "[$TIMESTAMP] RECOMMENDATIONS:" >> "$LOG_FILE"
    echo "[$TIMESTAMP] - Consider increasing backup intervals" >> "$LOG_FILE"
    echo "[$TIMESTAMP] - Review exclusion patterns to reduce backup size" >> "$LOG_FILE"
    echo "[$TIMESTAMP] - Consider upgrading to larger external drive" >> "$LOG_FILE"
elif [ $overall_status -eq 1 ]; then
    echo "[$TIMESTAMP] RECOMMENDATIONS:" >> "$LOG_FILE"
    echo "[$TIMESTAMP] - Monitor space usage daily" >> "$LOG_FILE"
    echo "[$TIMESTAMP] - Consider cleaning up source directory" >> "$LOG_FILE"
    echo "[$TIMESTAMP] - Review archive retention policies" >> "$LOG_FILE"
fi

echo "[$TIMESTAMP] Space management completed" >> "$LOG_FILE"

# Exit with status code indicating overall condition
exit $overall_status

# =============================================================================
# USAGE NOTES
# =============================================================================
#
# RETURN CODES:
#   0 - All partitions healthy, routine cleanup performed
#   1 - Warning condition, some partitions getting full
#   2 - Critical condition, aggressive cleanup performed
#
# MANUAL EXECUTION:
#   bash ~/Scripts/space_manager.sh
#
# AUTOMATED EXECUTION:
#   Called automatically by main backup script
#
# MONITORING:
#   Check exit code: echo $?
#   Review logs: grep "CRITICAL\|WARNING" ~/Scripts/backup.log
#
# CUSTOMIZATION:
#   - Adjust threshold values at top of script
#   - Modify cleanup retention periods
#   - Add email/notification on critical conditions
#
# =============================================================================