#!/bin/bash
# ~/Scripts/backup_status_single.sh
#
# COMPREHENSIVE BACKUP SYSTEM STATUS MONITOR
#
# PURPOSE:
# This script provides a complete overview of the single-drive backup system's
# health, performance, and current state. It's designed to give researchers
# a quick but thorough understanding of their data protection status.
#
# WHAT IT MONITORS:
# - Source project directory statistics and health
# - External drive partition usage and availability
# - Recent backup operations and their success/failure
# - Snapshot efficiency and space utilization
# - Archive status and retention compliance
# - Cloud synchronization status and last sync times
# - Git repository health across all 300+ repos
# - Overall system performance metrics
#
# WHEN TO USE:
# - Daily: Quick morning check (30 seconds)
# - After changes: Verify new projects are being backed up
# - Troubleshooting: Identify issues when something seems wrong
# - Planning: Understand space usage trends for future capacity planning
# - Maintenance: Before making system changes or adjustments
#
# OUTPUT FORMATS:
# - Console: Human-readable summary for interactive use
# - Log file: Detailed technical information for troubleshooting
# - Return codes: Script-friendly status indicators
#
# INTEGRATION:
# - Vim command: :BackupStatus
# - Command line: ~/Scripts/backup_status_single.sh
# - Automated monitoring: Called by other scripts for health checks
#
# AUTHOR: Research Computing Guide
# VERSION: 2.0 (Single Drive)

# =============================================================================
# CONFIGURATION AND SETUP
# =============================================================================

# Core directories and files
PRJ_DIR="$HOME/prj"
LOG_FILE="$HOME/Scripts/backup.log"
REPO_LIST="$HOME/Scripts/repo_list.txt"

# Partition paths
SNAPSHOT_PARTITION="/Volumes/PrjSnapshots"
ARCHIVE_PARTITION="/Volumes/PrjArchive"
TIMEMACHINE_PARTITION="/Volumes/TimeMachine"

# Color codes for enhanced readability (when running interactively)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

echo -e "${BOLD}=== SINGLE DRIVE BACKUP SYSTEM STATUS ===${NC}"
echo "Date: $(date)"
echo "Host: $(hostname)"
echo ""

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function: format_size
# Purpose: Convert bytes to human-readable format
# Parameters: $1 - Size in bytes
format_size() {
    local size=$1
    if [ -z "$size" ] || [ "$size" -eq 0 ]; then
        echo "0B"
        return
    fi
    
    local units=("B" "KB" "MB" "GB" "TB")
    local unit_index=0
    
    while [ "$size" -gt 1024 ] && [ "$unit_index" -lt 4 ]; do
        size=$((size / 1024))
        unit_index=$((unit_index + 1))
    done
    
    echo "${size}${units[$unit_index]}"
}

# Function: get_partition_info
# Purpose: Extract detailed partition information
# Parameters: $1 - Partition path
get_partition_info() {
    local partition="$1"
    
    if [ -d "$partition" ]; then
        df -h "$partition" | tail -1
    else
        echo "Not mounted"
    fi
}

# Function: calculate_efficiency
# Purpose: Calculate storage efficiency ratio
# Parameters: $1 - Actual storage used, $2 - Logical size
calculate_efficiency() {
    local actual="$1"
    local logical="$2"
    
    if [ -n "$actual" ] && [ -n "$logical" ] && [ "$logical" -gt 0 ]; then
        local ratio=$(echo "scale=2; $actual / $logical" | bc 2>/dev/null)
        echo "${ratio}x"
    else
        echo "N/A"
    fi
}

# Function: time_since
# Purpose: Calculate human-readable time since a given timestamp
# Parameters: $1 - Timestamp to compare against
time_since() {
    local timestamp="$1"
    local current=$(date +%s)
    local diff=$((current - timestamp))
    
    if [ "$diff" -lt 60 ]; then
        echo "${diff} seconds ago"
    elif [ "$diff" -lt 3600 ]; then
        echo "$((diff / 60)) minutes ago"
    elif [ "$diff" -lt 86400 ]; then
        echo "$((diff / 3600)) hours ago"
    else
        echo "$((diff / 86400)) days ago"
    fi
}

# =============================================================================
# PROJECT DIRECTORY ANALYSIS
# =============================================================================

echo -e "${BLUE}PROJECT OVERVIEW:${NC}"

if [ -d "$PRJ_DIR" ]; then
    # Basic directory statistics
    local project_size=$(du -sh "$PRJ_DIR" 2>/dev/null | cut -f1)
    local total_dirs=$(find "$PRJ_DIR" -type d 2>/dev/null | wc -l | tr -d ' ')
    local total_files=$(find "$PRJ_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    local git_repos=$(find "$PRJ_DIR" -name ".git" -type d 2>/dev/null | wc -l | tr -d ' ')
    
    echo "  Source Directory: $PRJ_DIR"
    echo "  Total Size: $project_size"
    echo "  Subdirectories: $total_dirs"
    echo "  Total Files: $total_files"
    echo "  Git Repositories: $git_repos"
    
    # Analyze project activity (recently modified files)
    local recent_files=$(find "$PRJ_DIR" -type f -mtime -1 2>/dev/null | wc -l | tr -d ' ')
    local very_recent_files=$(find "$PRJ_DIR" -type f -mmin -60 2>/dev/null | wc -l | tr -d ' ')
    
    echo "  Recent Activity:"
    echo "    Files modified today: $recent_files"
    echo "    Files modified last hour: $very_recent_files"
    
    # Check for uncommitted changes across repositories
    if [ -f "$REPO_LIST" ]; then
        local dirty_repos=0
        while IFS='|' read -r project_name project_dir remote_url; do
            if [ -d "$project_dir" ]; then
                cd "$project_dir"
                if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
                    dirty_repos=$((dirty_repos + 1))
                fi
            fi
        done < "$REPO_LIST" 2>/dev/null
        
        if [ "$dirty_repos" -gt 0 ]; then
            echo -e "  ${YELLOW}Uncommitted Changes: $dirty_repos repositories${NC}"
        else
            echo -e "  ${GREEN}All repositories clean${NC}"
        fi
    fi
    
    # Check for large files that might impact backup performance
    local large_files=$(find "$PRJ_DIR" -type f -size +100M 2>/dev/null | wc -l | tr -d ' ')
    if [ "$large_files" -gt 0 ]; then
        echo -e "  ${YELLOW}Large Files (>100MB): $large_files files${NC}"
        echo "    Consider excluding large binary files from cloud sync"
    fi
    
else
    echo -e "  ${RED}ERROR: Project directory not found at $PRJ_DIR${NC}"
fi

echo ""

# =============================================================================
# EXTERNAL DRIVE STATUS
# =============================================================================

echo -e "${BLUE}EXTERNAL DRIVE STATUS:${NC}"

# Check overall drive connectivity
local mounted_volumes=$(ls /Volumes/ 2>/dev/null | grep -E "(PrjSnapshots|PrjArchive|TimeMachine)" | wc -l | tr -d ' ')

if [ "$mounted_volumes" -eq 3 ]; then
    echo -e "  ${GREEN}Drive Status: Fully Connected (3/3 partitions)${NC}"
elif [ "$mounted_volumes" -gt 0 ]; then
    echo -e "  ${YELLOW}Drive Status: Partially Connected ($mounted_volumes/3 partitions)${NC}"
else
    echo -e "  ${RED}Drive Status: Not Connected (0/3 partitions)${NC}"
fi

# Detailed partition analysis
echo "  Partition Details:"

# Time Machine partition
local tm_info=$(get_partition_info "$TIMEMACHINE_PARTITION")
if [ "$tm_info" != "Not mounted" ]; then
    local tm_size=$(echo "$tm_info" | awk '{print $2}')
    local tm_used=$(echo "$tm_info" | awk '{print $3}')
    local tm_avail=$(echo "$tm_info" | awk '{print $4}')
    local tm_percent=$(echo "$tm_info" | awk '{print $5}')
    
    echo "    Time Machine: $tm_used/$tm_size used ($tm_percent), $tm_avail available"
    
    # Check Time Machine health
    local tm_status=$(tmutil status 2>/dev/null | grep "Running" | head -1)
    if [ -n "$tm_status" ]; then
        echo "      Status: Currently backing up"
    else
        local last_backup=$(tmutil latestbackup 2>/dev/null)
        if [ -n "$last_backup" ]; then
            local backup_date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$last_backup" 2>/dev/null)
            echo "      Last Backup: $backup_date"
        fi
    fi
else
    echo -e "    ${RED}Time Machine: Not mounted${NC}"
fi

# Snapshots partition
local snap_info=$(get_partition_info "$SNAPSHOT_PARTITION")
if [ "$snap_info" != "Not mounted" ]; then
    local snap_size=$(echo "$snap_info" | awk '{print $2}')
    local snap_used=$(echo "$snap_info" | awk '{print $3}')
    local snap_avail=$(echo "$snap_info" | awk '{print $4}')
    local snap_percent=$(echo "$snap_info" | awk '{print $5}')
    
    echo "    Snapshots: $snap_used/$snap_size used ($snap_percent), $snap_avail available"
    
    # Analyze snapshot efficiency
    if [ -d "$SNAPSHOT_PARTITION/hourly" ]; then
        local snapshot_count=$(ls -1 "$SNAPSHOT_PARTITION/hourly"/snapshot_* 2>/dev/null | wc -l | tr -d ' ')
        local total_snapshot_size=$(du -sh "$SNAPSHOT_PARTITION/hourly" 2>/dev/null | cut -f1)
        
        echo "      Snapshots: $snapshot_count total using $total_snapshot_size"
        
        if [ "$snapshot_count" -gt 0 ]; then
            # Calculate efficiency (how much space saved by hard linking)
            local avg_logical_size="20GB"  # Approximate project size
            local efficiency=$(calculate_efficiency "$(du -sb "$SNAPSHOT_PARTITION/hourly" 2>/dev/null | cut -f1)" "$((20 * 1024 * 1024 * 1024 * snapshot_count))")
            echo "      Efficiency: $efficiency (hard-link space savings)"
        fi
    fi
else
    echo -e "    ${RED}Snapshots: Not mounted${NC}"
fi

# Archives partition
local arch_info=$(get_partition_info "$ARCHIVE_PARTITION")
if [ "$arch_info" != "Not mounted" ]; then
    local arch_size=$(echo "$arch_info" | awk '{print $2}')
    local arch_used=$(echo "$arch_info" | awk '{print $3}')
    local arch_avail=$(echo "$arch_info" | awk '{print $4}')
    local arch_percent=$(echo "$arch_info" | awk '{print $5}')
    
    echo "    Archives: $arch_used/$arch_size used ($arch_percent), $arch_avail available"
else
    echo -e "    ${RED}Archives: Not mounted${NC}"
fi

echo ""

# =============================================================================
# RECENT BACKUP OPERATIONS
# =============================================================================

echo -e "${BLUE}RECENT BACKUP OPERATIONS:${NC}"

# Analyze recent snapshots
echo "  Hourly Snapshots:"
if [ -d "$SNAPSHOT_PARTITION/hourly" ]; then
    local recent_snapshots=$(ls -1t "$SNAPSHOT_PARTITION/hourly"/snapshot_* 2>/dev/null | head -5)
    
    if [ -n "$recent_snapshots" ]; then
        echo "$recent_snapshots" | while read snapshot_dir; do
            local snapshot_name=$(basename "$snapshot_dir")
            local snapshot_time=$(echo "$snapshot_name" | sed 's/snapshot_//' | sed 's/_/ /' | sed 's/-/:/3' | sed 's/-/:/3')
            local snapshot_timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S" "$snapshot_time" +%s 2>/dev/null)
            
            if [ -n "$snapshot_timestamp" ]; then
                local time_ago=$(time_since "$snapshot_timestamp")
                echo "    $snapshot_time ($time_ago)"
            else
                echo "    $snapshot_name"
            fi
        done
        
        # Check snapshot frequency
        local latest_snapshot=$(ls -1t "$SNAPSHOT_PARTITION/hourly"/snapshot_* 2>/dev/null | head -1)
        if [ -n "$latest_snapshot" ]; then
            local latest_time=$(basename "$latest_snapshot" | sed 's/snapshot_//' | sed 's/_/ /' | sed 's/-/:/3' | sed 's/-/:/3')
            local latest_timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S" "$latest_time" +%s 2>/dev/null)
            local current_timestamp=$(date +%s)
            local hours_ago=$(( (current_timestamp - latest_timestamp) / 3600 ))
            
            if [ "$hours_ago" -gt 2 ]; then
                echo -e "    ${YELLOW}Warning: Last snapshot is $hours_ago hours old${NC}"
            fi
        fi
    else
        echo -e "    ${RED}No snapshots found${NC}"
    fi
else
    echo -e "    ${RED}Snapshots directory not accessible${NC}"
fi

# Check current mirror status
echo "  Daily Mirror:"
if [ -d "$ARCHIVE_PARTITION/current_mirror" ]; then
    local last_sync_file="$ARCHIVE_PARTITION/current_mirror/.last_sync"
    if [ -f "$last_sync_file" ]; then
        local last_sync_date=$(cat "$last_sync_file")
        local today=$(date +%Y-%m-%d)
        
        if [ "$last_sync_date" = "$today" ]; then
            echo -e "    ${GREEN}Synced today ($last_sync_date)${NC}"
        else
            echo -e "    ${YELLOW}Last synced: $last_sync_date${NC}"
        fi
        
        local mirror_size=$(du -sh "$ARCHIVE_PARTITION/current_mirror" 2>/dev/null | cut -f1)
        echo "    Mirror size: $mirror_size"
    else
        echo -e "    ${YELLOW}No sync record found${NC}"
    fi
else
    echo -e "    ${RED}Mirror directory not found${NC}"
fi

echo ""

# =============================================================================
# ARCHIVE STATUS AND MANAGEMENT
# =============================================================================

echo -e "${BLUE}ARCHIVE STATUS:${NC}"

# Weekly archives
echo "  Weekly Archives:"
if [ -d "$ARCHIVE_PARTITION/weekly" ]; then
    local weekly_count=$(ls -1 "$ARCHIVE_PARTITION/weekly"/prj_weekly_*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
    local weekly_size=$(du -sh "$ARCHIVE_PARTITION/weekly" 2>/dev/null | cut -f1)
    
    echo "    Count: $weekly_count archives using $weekly_size"
    
    if [ "$weekly_count" -gt 0 ]; then
        # Show most recent weekly archives
        local recent_weekly=$(ls -1t "$ARCHIVE_PARTITION/weekly"/prj_weekly_*.tar.gz 2>/dev/null | head -3)
        echo "    Recent:"
        echo "$recent_weekly" | while read archive_file; do
            local archive_name=$(basename "$archive_file")
            local archive_date=$(echo "$archive_name" | sed 's/prj_weekly_//' | sed 's/.tar.gz//')
            local archive_size=$(du -sh "$archive_file" 2>/dev/null | cut -f1)
            echo "      $archive_date ($archive_size)"
        done
        
        # Check if this week's archive exists
        local this_week=$(date +%Y-%m-%d)
        local this_week_archive="$ARCHIVE_PARTITION/weekly/prj_weekly_$this_week.tar.gz"
        if [ ! -f "$this_week_archive" ] && [ $(date +%u) -eq 7 ]; then
            echo -e "    ${YELLOW}Note: This week's archive not yet created${NC}"
        fi
    fi
else
    echo -e "    ${RED}Weekly archives directory not found${NC}"
fi

# Monthly archives
echo "  Monthly Archives:"
if [ -d "$ARCHIVE_PARTITION/monthly" ]; then
    local monthly_count=$(ls -1 "$ARCHIVE_PARTITION/monthly"/prj_monthly_*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
    local monthly_size=$(du -sh "$ARCHIVE_PARTITION/monthly" 2>/dev/null | cut -f1)
    
    echo "    Count: $monthly_count archives using $monthly_size"
    
    if [ "$monthly_count" -gt 0 ]; then
        # Show recent monthly archives
        local recent_monthly=$(ls -1t "$ARCHIVE_PARTITION/monthly"/prj_monthly_*.tar.gz 2>/dev/null | head -3)
        echo "    Recent:"
        echo "$recent_monthly" | while read archive_file; do
            local archive_name=$(basename "$archive_file")
            local archive_month=$(echo "$archive_name" | sed 's/prj_monthly_//' | sed 's/.tar.gz//')
            local archive_size=$(du -sh "$archive_file" 2>/dev/null | cut -f1)
            echo "      $archive_month ($archive_size)"
        done
    fi
else
    echo -e "    ${RED}Monthly archives directory not found${NC}"
fi

echo ""

# =============================================================================
# CLOUD BACKUP STATUS
# =============================================================================

echo -e "${BLUE}CLOUD BACKUP STATUS:${NC}"

# Check rclone availability
if command -v rclone >/dev/null 2>&1; then
    echo -e "  ${GREEN}rclone: Available${NC}"
    
    # Parse recent cloud sync operations from log
    if [ -f "$LOG_FILE" ]; then
        # Google Drive sync status
        local google_sync=$(tail -50 "$LOG_FILE" | grep -i "google drive sync" | tail -1)
        if [ -n "$google_sync" ]; then
            local google_timestamp=$(echo "$google_sync" | cut -d']' -f1 | tr -d '[')
            local google_status=$(echo "$google_sync" | grep -i "completed successfully" && echo "SUCCESS" || echo "ERRORS")
            
            if [ "$google_status" = "SUCCESS" ]; then
                echo -e "  ${GREEN}Google Drive: $google_timestamp${NC}"
            else
                echo -e "  ${YELLOW}Google Drive: $google_timestamp (with errors)${NC}"
            fi
        else
            echo -e "  ${YELLOW}Google Drive: No recent sync found${NC}"
        fi
        
        # Dropbox sync status (weekly)
        local dropbox_sync=$(tail -100 "$LOG_FILE" | grep -i "dropbox.*sync" | tail -1)
        if [ -n "$dropbox_sync" ]; then
            local dropbox_timestamp=$(echo "$dropbox_sync" | cut -d']' -f1 | tr -d '[')
            local dropbox_status=$(echo "$dropbox_sync" | grep -i "completed successfully" && echo "SUCCESS" || echo "ERRORS")
            
            if [ "$dropbox_status" = "SUCCESS" ]; then
                echo -e "  ${GREEN}Dropbox: $dropbox_timestamp (weekly)${NC}"
            else
                echo -e "  ${YELLOW}Dropbox: $dropbox_timestamp (with errors)${NC}"
            fi
        else
            echo "  Dropbox: No recent sync found (weekly only)"
        fi
        
        # Check for cloud sync frequency
        local cloud_syncs_today=$(grep "$(date +%Y-%m-%d)" "$LOG_FILE" | grep -i "cloud.*sync" | wc -l | tr -d ' ')
        echo "  Sync Operations Today: $cloud_syncs_today"
        
    else
        echo -e "  ${YELLOW}No log file found for sync status${NC}"
    fi
    
    # Test cloud connectivity (quick check)
    echo "  Connectivity Test:"
    if rclone lsd googledrive: >/dev/null 2>&1; then
        echo -e "    ${GREEN}Google Drive: Connected${NC}"
    else
        echo -e "    ${RED}Google Drive: Connection failed${NC}"
    fi
    
    if rclone lsd dropbox: >/dev/null 2>&1; then
        echo -e "    ${GREEN}Dropbox: Connected${NC}"
    else
        echo -e "    ${YELLOW}Dropbox: Connection failed (may not be configured)${NC}"
    fi
    
else
    echo -e "  ${RED}rclone: Not available - cloud backup disabled${NC}"
fi

echo ""

# =============================================================================
# GIT REPOSITORY HEALTH
# =============================================================================

echo -e "${BLUE}GIT REPOSITORY STATUS:${NC}"

if [ -f "$REPO_LIST" ]; then
    local total_repos=$(wc -l < "$REPO_LIST" | tr -d ' ')
    echo "  Total Repositories: $total_repos"
    
    # Analyze repository states
    local clean_repos=0
    local dirty_repos=0
    local no_remote_repos=0
    local error_repos=0
    local ahead_repos=0
    
    while IFS='|' read -r project_name project_dir remote_url; do
        if [ -d "$project_dir" ]; then
            cd "$project_dir"
            
            # Check if repository is healthy
            if ! git status >/dev/null 2>&1; then
                error_repos=$((error_repos + 1))
                continue
            fi
            
            # Check for uncommitted changes
            if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
                dirty_repos=$((dirty_repos + 1))
            else
                clean_repos=$((clean_repos + 1))
            fi
            
            # Check remote status
            if [ "$remote_url" = "NO_REMOTE" ]; then
                no_remote_repos=$((no_remote_repos + 1))
            else
                # Check if ahead of remote (has unpushed commits)
                git fetch origin >/dev/null 2>&1
                local ahead=$(git rev-list --count HEAD ^origin/main 2>/dev/null || git rev-list --count HEAD ^origin/master 2>/dev/null || echo "0")
                if [ "$ahead" -gt 0 ]; then
                    ahead_repos=$((ahead_repos + 1))
                fi
            fi
        fi
    done < "$REPO_LIST"
    
    # Report repository health
    echo "  Repository Health:"
    if [ "$clean_repos" -gt 0 ]; then
        echo -e "    ${GREEN}Clean: $clean_repos repositories${NC}"
    fi
    
    if [ "$dirty_repos" -gt 0 ]; then
        echo -e "    ${YELLOW}With changes: $dirty_repos repositories${NC}"
    fi
    
    if [ "$ahead_repos" -gt 0 ]; then
        echo -e "    ${YELLOW}Ahead of remote: $ahead_repos repositories${NC}"
    fi
    
    if [ "$no_remote_repos" -gt 0 ]; then
        echo -e "    ${YELLOW}No remote: $no_remote_repos repositories${NC}"
    fi
    
    if [ "$error_repos" -gt 0 ]; then
        echo -e "    ${RED}Errors: $error_repos repositories${NC}"
    fi
    
    # Calculate health percentage
    local healthy_repos=$((clean_repos + dirty_repos))
    local health_percent=$(echo "scale=1; $healthy_repos * 100 / $total_repos" | bc 2>/dev/null)
    echo "  Overall Health: ${health_percent}% ($healthy_repos/$total_repos functional)"
    
    # Check for recent Git activity
    if [ -f "$LOG_FILE" ]; then
        local git_syncs_today=$(grep "$(date +%Y-%m-%d)" "$LOG_FILE" | grep -i "git.*sync" | wc -l | tr -d ' ')
        echo "  Git Sync Operations Today: $git_syncs_today"
    fi
    
else
    echo -e "  ${RED}Repository list not found${NC}"
    echo "  Run: ~/Scripts/discover_repos.sh to generate repository list"
fi

echo ""

# =============================================================================
# SYSTEM PERFORMANCE METRICS
# =============================================================================

echo -e "${BLUE}SYSTEM PERFORMANCE:${NC}"

# Calculate storage efficiency across all backup types
if [ -d "$PRJ_DIR" ]; then
    local source_size_bytes=$(du -sb "$PRJ_DIR" 2>/dev/null | cut -f1)
    local source_size_gb=$(echo "scale=2; $source_size_bytes / 1024 / 1024 / 1024" | bc 2>/dev/null)
    
    # Calculate total backup storage used
    local backup_usage_bytes=0
    
    if [ -d "$SNAPSHOT_PARTITION" ]; then
        local snapshot_bytes=$(du -sb "$SNAPSHOT_PARTITION" 2>/dev/null | cut -f1 || echo "0")
        backup_usage_bytes=$((backup_usage_bytes + snapshot_bytes))
    fi
    
    if [ -d "$ARCHIVE_PARTITION" ]; then
        local archive_bytes=$(du -sb "$ARCHIVE_PARTITION" 2>/dev/null | cut -f1 || echo "0")
        backup_usage_bytes=$((backup_usage_bytes + archive_bytes))
    fi
    
    if [ "$backup_usage_bytes" -gt 0 ] && [ "$source_size_bytes" -gt 0 ]; then
        local storage_efficiency=$(echo "scale=2; $backup_usage_bytes / $source_size_bytes" | bc 2>/dev/null)
        local backup_size_gb=$(echo "scale=2; $backup_usage_bytes / 1024 / 1024 / 1024" | bc 2>/dev/null)
        
        echo "  Storage Efficiency:"
        echo "    Source: ${source_size_gb}GB"
        echo "    Backups: ${backup_size_gb}GB"
        echo "    Ratio: ${storage_efficiency}x (lower is better)"
        
        # Interpret efficiency
        if [ "$(echo "$storage_efficiency < 2.0" | bc 2>/dev/null)" = "1" ]; then
            echo -e "    ${GREEN}Excellent efficiency (hard-linking working well)${NC}"
        elif [ "$(echo "$storage_efficiency < 3.0" | bc 2>/dev/null)" = "1" ]; then
            echo -e "    ${YELLOW}Good efficiency${NC}"
        else
            echo -e "    ${YELLOW}Consider reviewing backup retention policies${NC}"
        fi
    fi
fi

# Check backup operation frequency and timing
if [ -f "$LOG_FILE" ]; then
    echo "  Operation Frequency (last 24 hours):"
    
    local backup_operations=$(grep "$(date +%Y-%m-%d)" "$LOG_FILE" | grep -c "backup process" || echo "0")
    local snapshot_operations=$(grep "$(date +%Y-%m-%d)" "$LOG_FILE" | grep -c "snapshot created" || echo "0")
    local git_operations=$(grep "$(date +%Y-%m-%d)" "$LOG_FILE" | grep -c "Git sync" || echo "0")
    
    echo "    Backup cycles: $backup_operations"
    echo "    Snapshots created: $snapshot_operations"
    echo "    Git synchronizations: $git_operations"
    
    # Check for errors
    local error_count=$(grep "$(date +%Y-%m-%d)" "$LOG_FILE" | grep -c "ERROR" || echo "0")
    local warning_count=$(grep "$(date +%Y-%m-%d)" "$LOG_FILE" | grep -c "WARNING" || echo "0")
    
    if [ "$error_count" -gt 0 ]; then
        echo -e "    ${RED}Errors: $error_count${NC}"
    fi
    
    if [ "$warning_count" -gt 0 ]; then
        echo -e "    ${YELLOW}Warnings: $warning_count${NC}"
    fi
    
    if [ "$error_count" -eq 0 ] && [ "$warning_count" -eq 0 ]; then
        echo -e "    ${GREEN}No errors or warnings${NC}"
    fi
fi

echo ""

# =============================================================================
# HEALTH SUMMARY AND RECOMMENDATIONS
# =============================================================================

echo -e "${BOLD}SYSTEM HEALTH SUMMARY:${NC}"

# Determine overall system health
local health_score=100
local issues=()

# Check critical components
if [ ! -d "$PRJ_DIR" ]; then
    health_score=$((health_score - 50))
    issues+=("Source directory not found")
fi

if [ "$mounted_volumes" -lt 3 ]; then
    health_score=$((health_score - 30))
    issues+=("External drive not fully mounted")
fi

if ! command -v rclone >/dev/null 2>&1; then
    health_score=$((health_score - 20))
    issues+=("Cloud backup not available")
fi

# Check recent backup activity
if [ -f "$LOG_FILE" ]; then
    local recent_backup=$(grep "$(date +%Y-%m-%d)" "$LOG_FILE" | grep "backup process completed" | tail -1)
    if [ -z "$recent_backup" ]; then
        health_score=$((health_score - 15))
        issues+=("No backup completed today")
    fi
fi

# Determine health status
if [ "$health_score" -ge 90 ]; then
    echo -e "  ${GREEN}EXCELLENT${NC} (Score: $health_score/100)"
    echo "  All systems operating normally"
elif [ "$health_score" -ge 70 ]; then
    echo -e "  ${YELLOW}GOOD${NC} (Score: $health_score/100)"
    echo "  Minor issues detected"
elif [ "$health_score" -ge 50 ]; then
    echo -e "  ${YELLOW}FAIR${NC} (Score: $health_score/100)"
    echo "  Several issues need attention"
else
    echo -e "  ${RED}POOR${NC} (Score: $health_score/100)"
    echo "  Critical issues require immediate attention"
fi

# List specific issues
if [ ${#issues[@]} -gt 0 ]; then
    echo ""
    echo "  Issues Detected:"
    for issue in "${issues[@]}"; do
        echo -e "    ${YELLOW}• $issue${NC}"
    done
fi

# Provide actionable recommendations
echo ""
echo -e "${BOLD}RECOMMENDATIONS:${NC}"

if [ "$health_score" -ge 90 ]; then
    echo "  • Continue current backup routine"
    echo "  • Monitor space usage weekly"
    echo "  • Test recovery procedures monthly"
elif [ "$health_score" -ge 70 ]; then
    echo "  • Address minor issues when convenient"
    echo "  • Review backup logs for recurring warnings"
    echo "  • Consider increasing monitoring frequency"
else
    echo "  • Address critical issues immediately"
    echo "  • Review system configuration"
    echo "  • Consider manual backup until issues resolved"
    echo "  • Check hardware connections and software installation"
fi

# Exit with status code based on health
if [ "$health_score" -ge 70 ]; then
    exit 0  # Healthy
elif [ "$health_score" -ge 50 ]; then
    exit 1  # Warning
else
    exit 2  # Critical
fi

# =============================================================================
# USAGE NOTES
# =============================================================================
#
# RETURN CODES:
#   0 - System healthy (score >= 70)
#   1 - Warning condition (score 50-69)
#   2 - Critical condition (score < 50)
#
# MANUAL EXECUTION:
#   bash ~/Scripts/backup_status_single.sh
#
# VIM INTEGRATION:
#   :BackupStatus
#
# AUTOMATED MONITORING:
#   if ! ~/Scripts/backup_status_single.sh; then
#       echo "Backup system needs attention"
#   fi
#
# CUSTOMIZATION:
#   - Adjust health score thresholds
#   - Add custom health checks
#   - Integrate with notification systems
#   - Customize color output
#
# =============================================================================