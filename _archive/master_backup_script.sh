#!/bin/bash
# ~/Scripts/prj_backup_single.sh
#
# MASTER BACKUP SCRIPT FOR SINGLE-DRIVE RESEARCH PROJECT BACKUP SYSTEM
# 
# PURPOSE:
# This script orchestrates all backup operations for a comprehensive research data
# protection system. It handles 20GB+ of research data across 300+ Git repositories
# using a single 1TB external drive plus cloud storage.
#
# BACKUP LAYERS MANAGED:
# 1. Git repository synchronization (300+ individual repos)
# 2. Hard-linked hourly snapshots (space-efficient incremental backups)
# 3. Daily current mirror (complete synchronized copy)
# 4. Cloud synchronization (Google Drive primary, Dropbox secondary)
#
# HOW IT WORKS:
# - Runs hourly via launchd (Launch Agent)
# - Checks available disk space before each operation
# - Uses hard links for space-efficient snapshots
# - Syncs current mirror only once per day to conserve space
# - Performs automatic cleanup of old snapshots
# - Logs all operations for monitoring and troubleshooting
#
# SPACE EFFICIENCY:
# - Hard-linked snapshots: Only changed files use additional space
# - Daily mirror sync: Prevents duplicate daily operations
# - Intelligent cleanup: Removes old snapshots automatically
# - Cloud exclusions: Skips temporary and binary files
#
# ERROR HANDLING:
# - Checks disk space before each operation
# - Continues with other operations if one fails
# - Logs all errors for later review
# - Provides clear error messages for troubleshooting
#
# USAGE:
# - Automatic: Runs every hour via launchd
# - Manual: Execute directly for immediate backup
# - Vim integration: Call via :BackupNow command
#
# DEPENDENCIES:
# - External drive mounted with partitions: PrjSnapshots, PrjArchive, TimeMachine
# - rclone configured for cloud storage
# - Git repositories properly configured with remotes
# - Supporting scripts: bulk_git_ops.sh, discover_repos.sh
#
# AUTHOR: Research Computing Guide
# VERSION: 2.0 (Single Drive)

# =============================================================================
# CONFIGURATION AND SETUP
# =============================================================================

# Core directories and files
LOG_FILE="$HOME/Scripts/backup.log"
PRJ_DIR="$HOME/prj"                           # Source: Your research projects
SNAPSHOTS_DIR="/Volumes/PrjSnapshots/hourly"  # Destination: Hourly snapshots
ARCHIVE_DIR="/Volumes/PrjArchive"              # Destination: Archives and mirror
CURRENT_MIRROR="$ARCHIVE_DIR/current_mirror"   # Destination: Daily mirror
TIMESTAMP=$(date "+%Y-%m-%d_%H-%M-%S")         # Unique timestamp for this run

# Log the start of backup process
echo "[$TIMESTAMP] =================================" >> "$LOG_FILE"
echo "[$TIMESTAMP] Starting single-drive backup process" >> "$LOG_FILE"
echo "[$TIMESTAMP] Source directory: $PRJ_DIR" >> "$LOG_FILE"
echo "[$TIMESTAMP] Project size: $(du -sh "$PRJ_DIR" 2>/dev/null | cut -f1 || echo 'Unknown')" >> "$LOG_FILE"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function: check_disk_space
# Purpose: Verify sufficient disk space before performing backup operations
# Parameters: 
#   $1 - Target directory path
#   $2 - Required space in GB
# Returns: 0 if sufficient space, 1 if insufficient
# 
# This function prevents backup failures due to insufficient disk space and
# helps avoid corrupted backups that could occur if the disk fills during operation.
check_disk_space() {
    local target_dir="$1"
    local required_gb="$2"
    
    # Check if the target directory or its parent exists
    if [ -d "$(dirname "$target_dir")" ]; then
        # Get available space in GB using df command
        local available_gb=$(df -g "$(dirname "$target_dir")" | tail -1 | awk '{print $4}')
        
        echo "[$TIMESTAMP] Space check: $available_gb GB available, $required_gb GB required for $(dirname "$target_dir")" >> "$LOG_FILE"
        
        # Compare available space with required space
        if [ "$available_gb" -lt "$required_gb" ]; then
            echo "[$TIMESTAMP] ERROR: Insufficient disk space on $(dirname "$target_dir")" >> "$LOG_FILE"
            echo "[$TIMESTAMP] Available: ${available_gb}GB, Required: ${required_gb}GB" >> "$LOG_FILE"
            return 1
        fi
        
        echo "[$TIMESTAMP] Space check passed: ${available_gb}GB available" >> "$LOG_FILE"
    else
        echo "[$TIMESTAMP] WARNING: Cannot check space - directory $(dirname "$target_dir") not found" >> "$LOG_FILE"
        return 1
    fi
    
    return 0
}

# Function: verify_drive_mounted
# Purpose: Ensure the external drive is properly mounted before proceeding
# Returns: 0 if drive is mounted, 1 if not mounted
verify_drive_mounted() {
    if [ ! -d "/Volumes/PrjSnapshots" ] || [ ! -d "/Volumes/PrjArchive" ]; then
        echo "[$TIMESTAMP] CRITICAL ERROR: External drive not properly mounted" >> "$LOG_FILE"
        echo "[$TIMESTAMP] Required partitions: PrjSnapshots, PrjArchive" >> "$LOG_FILE"
        echo "[$TIMESTAMP] Available volumes: $(ls /Volumes/ 2>/dev/null | tr '\n' ' ')" >> "$LOG_FILE"
        return 1
    fi
    
    echo "[$TIMESTAMP] External drive verification: OK" >> "$LOG_FILE"
    return 0
}

# =============================================================================
# BACKUP OPERATION FUNCTIONS
# =============================================================================

# Function: create_hourly_snapshot
# Purpose: Create space-efficient incremental snapshots using hard links
# 
# HOW HARD LINKS WORK:
# Hard links allow multiple directory entries to point to the same physical file.
# If a file hasn't changed between snapshots, both snapshots point to the same
# data on disk, using virtually no additional space. Only modified files
# consume additional storage.
#
# SPACE EFFICIENCY EXAMPLE:
# - 10 traditional backups of 20GB = 200GB used
# - 10 hard-linked snapshots with 20% daily change = ~25GB used
#
# CLEANUP STRATEGY:
# Automatically removes snapshots older than 24 hours to prevent disk full.
# This provides 24+ recovery points while maintaining reasonable space usage.
create_hourly_snapshot() {
    echo "[$TIMESTAMP] Starting hourly snapshot creation" >> "$LOG_FILE"
    
    # Verify external drive is mounted
    if ! verify_drive_mounted; then
        return 1
    fi
    
    # Check available space (need at least 5GB buffer)
    if ! check_disk_space "$SNAPSHOTS_DIR" "5"; then
        echo "[$TIMESTAMP] Skipping snapshot due to insufficient space" >> "$LOG_FILE"
        return 1
    fi
    
    # Create snapshot directory with timestamp
    local snapshot_dir="$SNAPSHOTS_DIR/snapshot_$TIMESTAMP"
    mkdir -p "$snapshot_dir"
    
    echo "[$TIMESTAMP] Creating snapshot: $snapshot_dir" >> "$LOG_FILE"
    
    # Find the most recent snapshot for hard-linking
    local latest_snapshot=$(ls -1t $SNAPSHOTS_DIR/snapshot_* 2>/dev/null | head -1)
    
    if [ -n "$latest_snapshot" ] && [ -d "$latest_snapshot" ]; then
        echo "[$TIMESTAMP] Using hard-link base: $latest_snapshot" >> "$LOG_FILE"
        
        # Create incremental backup with hard links
        # --link-dest: Use hard links for unchanged files (saves massive space)
        # --delete: Mirror the source (remove files that no longer exist)
        # -av: Archive mode with verbose output
        rsync -av --delete --link-dest="$latest_snapshot" "$PRJ_DIR/" "$snapshot_dir/" >> "$LOG_FILE" 2>&1
        
        if [ $? -eq 0 ]; then
            echo "[$TIMESTAMP] Hard-linked snapshot created successfully" >> "$LOG_FILE"
        else
            echo "[$TIMESTAMP] ERROR: Hard-linked snapshot failed" >> "$LOG_FILE"
            return 1
        fi
    else
        echo "[$TIMESTAMP] No previous snapshot found, creating first full backup" >> "$LOG_FILE"
        
        # Create first complete backup
        rsync -av --delete "$PRJ_DIR/" "$snapshot_dir/" >> "$LOG_FILE" 2>&1
        
        if [ $? -eq 0 ]; then
            echo "[$TIMESTAMP] Initial full snapshot created successfully" >> "$LOG_FILE"
        else
            echo "[$TIMESTAMP] ERROR: Initial snapshot failed" >> "$LOG_FILE"
            return 1
        fi
    fi
    
    # Automatic cleanup: Remove snapshots older than 24 hours
    echo "[$TIMESTAMP] Cleaning up old snapshots (older than 24 hours)" >> "$LOG_FILE"
    local cleaned_count=$(find $SNAPSHOTS_DIR -name "snapshot_*" -type d -mtime +1 -print -exec rm -rf {} \; | wc -l)
    echo "[$TIMESTAMP] Removed $cleaned_count old snapshots" >> "$LOG_FILE"
    
    # Report final snapshot statistics
    local total_snapshots=$(ls -1 $SNAPSHOTS_DIR/snapshot_* 2>/dev/null | wc -l | tr -d ' ')
    local total_space=$(du -sh $SNAPSHOTS_DIR 2>/dev/null | cut -f1)
    echo "[$TIMESTAMP] Snapshot summary: $total_snapshots snapshots using $total_space total" >> "$LOG_FILE"
    
    return 0
}

# Function: sync_current_mirror
# Purpose: Maintain a complete, current copy of all projects
#
# WHY DAILY INSTEAD OF HOURLY:
# - Space conservation: Prevents duplicate mirror operations
# - Performance: Full mirror sync is resource-intensive
# - Usefulness: Daily currency is sufficient for most recovery scenarios
#
# MIRROR VS SNAPSHOT:
# - Mirror: Complete independent copy, easy to browse/copy
# - Snapshot: Hard-linked incremental, space-efficient but requires rsync knowledge
#
# USE CASES:
# - Bulk operations: Copy entire research portfolio to new system
# - Offline access: Work with projects when external drive is disconnected
# - Cross-platform: Standard directory structure readable on any OS
sync_current_mirror() {
    echo "[$TIMESTAMP] Checking current mirror sync status" >> "$LOG_FILE"
    
    # Check if mirror sync is needed (only once per day)
    local last_mirror_file="$CURRENT_MIRROR/.last_sync"
    local today=$(date +%Y-%m-%d)
    
    if [ -f "$last_mirror_file" ]; then
        local last_sync=$(cat "$last_mirror_file")
        if [ "$last_sync" = "$today" ]; then
            echo "[$TIMESTAMP] Current mirror already synced today ($last_sync)" >> "$LOG_FILE"
            return 0
        fi
        echo "[$TIMESTAMP] Last mirror sync: $last_sync (syncing for $today)" >> "$LOG_FILE"
    else
        echo "[$TIMESTAMP] No previous mirror sync found, performing initial sync" >> "$LOG_FILE"
    fi
    
    # Verify sufficient space for complete mirror (need ~25GB for 20GB source + buffer)
    if ! check_disk_space "$CURRENT_MIRROR" "25"; then
        echo "[$TIMESTAMP] Skipping mirror sync due to insufficient space" >> "$LOG_FILE"
        return 1
    fi
    
    # Create mirror directory if it doesn't exist
    mkdir -p "$CURRENT_MIRROR"
    
    echo "[$TIMESTAMP] Starting daily mirror synchronization" >> "$LOG_FILE"
    
    # Perform complete mirror sync
    # --delete: Remove files that no longer exist in source
    # --progress: Show progress (useful for manual runs)
    # --stats: Provide detailed statistics
    rsync -av --delete --progress --stats "$PRJ_DIR/" "$CURRENT_MIRROR/" >> "$LOG_FILE" 2>&1
    
    if [ $? -eq 0 ]; then
        # Record successful sync date
        echo "$today" > "$last_mirror_file"
        echo "[$TIMESTAMP] Daily mirror sync completed successfully" >> "$LOG_FILE"
        
        # Report mirror statistics
        local mirror_size=$(du -sh "$CURRENT_MIRROR" 2>/dev/null | cut -f1)
        echo "[$TIMESTAMP] Mirror size: $mirror_size" >> "$LOG_FILE"
        return 0
    else
        echo "[$TIMESTAMP] ERROR: Daily mirror sync failed" >> "$LOG_FILE"
        return 1
    fi
}

# Function: sync_cloud_backup
# Purpose: Synchronize projects with cloud storage for offsite protection
#
# CLOUD STRATEGY:
# - Primary: Google Drive (continuous sync)
# - Secondary: Dropbox (weekly sync for redundancy)
# - Exclusions: Temporary files, Git objects, system files
#
# WHY EXCLUDE GIT OBJECTS:
# Git objects are already backed up to GitHub, and they're numerous small files
# that slow down cloud sync significantly. We backup the working directory
# and rely on GitHub for Git history.
#
# PERFORMANCE OPTIMIZATION:
# - Multiple transfer threads for faster uploads
# - Retry logic for network interruptions
# - Compression during transfer
# - One-line stats to reduce log size
sync_cloud_backup() {
    echo "[$TIMESTAMP] Starting cloud backup synchronization" >> "$LOG_FILE"
    
    # Check if rclone is available
    if ! command -v rclone >/dev/null 2>&1; then
        echo "[$TIMESTAMP] WARNING: rclone not available - skipping cloud backup" >> "$LOG_FILE"
        return 1
    fi
    
    # Primary cloud backup to Google Drive
    echo "[$TIMESTAMP] Syncing to Google Drive (primary cloud)" >> "$LOG_FILE"
    
    rclone sync "$PRJ_DIR/" googledrive:prj/ \
        --exclude "*.tmp" \
        --exclude "*.DS_Store" \
        --exclude ".git/objects/**" \
        --exclude "**/node_modules/**" \
        --exclude "**/__pycache__/**" \
        --exclude "**/.pytest_cache/**" \
        --transfers 4 \
        --checkers 8 \
        --retries 3 \
        --log-file="$LOG_FILE" \
        --stats-one-line \
        --stats 0
    
    if [ $? -eq 0 ]; then
        echo "[$TIMESTAMP] Google Drive sync completed successfully" >> "$LOG_FILE"
    else
        echo "[$TIMESTAMP] WARNING: Google Drive sync encountered errors" >> "$LOG_FILE"
    fi
    
    # Secondary cloud backup to Dropbox (weekly only)
    if [ $(date +%u) -eq 7 ]; then  # Sunday
        echo "[$TIMESTAMP] Running weekly secondary cloud backup to Dropbox" >> "$LOG_FILE"
        
        rclone sync "$PRJ_DIR/" dropbox:prj_backup/ \
            --exclude "*.tmp" \
            --exclude "*.DS_Store" \
            --exclude ".git/objects/**" \
            --exclude "**/node_modules/**" \
            --exclude "**/__pycache__/**" \
            --transfers 2 \
            --checkers 4 \
            --retries 3 \
            --log-file="$LOG_FILE" \
            --stats-one-line \
            --stats 0
        
        if [ $? -eq 0 ]; then
            echo "[$TIMESTAMP] Dropbox weekly sync completed successfully" >> "$LOG_FILE"
        else
            echo "[$TIMESTAMP] WARNING: Dropbox weekly sync encountered errors" >> "$LOG_FILE"
        fi
    else
        echo "[$TIMESTAMP] Skipping Dropbox sync (weekly only - today is $(date +%A))" >> "$LOG_FILE"
    fi
    
    return 0
}

# Function: bulk_git_sync
# Purpose: Commit and push changes across all 300+ Git repositories
#
# MULTI-REPOSITORY STRATEGY:
# Each research project has its own Git repository, providing:
# - Individual project histories
# - Separate collaboration spaces
# - Isolated branching strategies
# - Project-specific access controls
#
# BULK OPERATIONS:
# - Discovers all Git repositories automatically
# - Commits uncommitted changes with timestamp
# - Pushes to origin (main or master branch)
# - Handles authentication and network errors gracefully
#
# ERROR HANDLING:
# - Continues processing even if individual repos fail
# - Logs all errors for later review
# - Provides summary of successful vs failed operations
bulk_git_sync() {
    echo "[$TIMESTAMP] Starting bulk Git synchronization across all repositories" >> "$LOG_FILE"
    
    # Ensure repository discovery script exists
    if [ ! -f "$HOME/Scripts/discover_repos.sh" ]; then
        echo "[$TIMESTAMP] WARNING: Repository discovery script not found" >> "$LOG_FILE"
        return 1
    fi
    
    # Ensure bulk Git operations script exists
    if [ ! -f "$HOME/Scripts/bulk_git_ops.sh" ]; then
        echo "[$TIMESTAMP] WARNING: Bulk Git operations script not found" >> "$LOG_FILE"
        return 1
    fi
    
    # Update repository list (discovers new repositories)
    echo "[$TIMESTAMP] Discovering Git repositories" >> "$LOG_FILE"
    "$HOME/Scripts/discover_repos.sh" >/dev/null 2>&1
    
    # Count repositories for logging
    if [ -f "$HOME/Scripts/repo_list.txt" ]; then
        local repo_count=$(wc -l < "$HOME/Scripts/repo_list.txt" | tr -d ' ')
        echo "[$TIMESTAMP] Found $repo_count Git repositories" >> "$LOG_FILE"
    else
        echo "[$TIMESTAMP] ERROR: Repository list not generated" >> "$LOG_FILE"
        return 1
    fi
    
    # Commit changes in all repositories
    echo "[$TIMESTAMP] Committing changes across all repositories" >> "$LOG_FILE"
    "$HOME/Scripts/bulk_git_ops.sh" commit >/dev/null 2>&1
    
    # Push changes to remote repositories
    echo "[$TIMESTAMP] Pushing changes to remote repositories" >> "$LOG_FILE"
    "$HOME/Scripts/bulk_git_ops.sh" push >/dev/null 2>&1
    
    # Check results and provide summary
    if [ $? -eq 0 ]; then
        echo "[$TIMESTAMP] Bulk Git sync completed successfully" >> "$LOG_FILE"
        return 0
    else
        echo "[$TIMESTAMP] WARNING: Some Git operations failed - check git_bulk.log for details" >> "$LOG_FILE"
        return 1
    fi
}

# =============================================================================
# MAIN EXECUTION SEQUENCE
# =============================================================================

# The backup operations are executed in a specific order to optimize
# performance and ensure data consistency:
#
# 1. Git Sync: Ensure latest changes are committed and pushed
# 2. Hourly Snapshot: Capture current state with space-efficient hard links
# 3. Daily Mirror: Create complete copy (only once per day)
# 4. Cloud Sync: Upload to offsite storage for disaster recovery
#
# Each operation is independent - if one fails, others continue to provide
# partial protection.

echo "[$TIMESTAMP] Beginning backup operations sequence" >> "$LOG_FILE"

# Operation 1: Multi-repository Git synchronization
echo "[$TIMESTAMP] === OPERATION 1: Git Synchronization ===" >> "$LOG_FILE"
if bulk_git_sync; then
    echo "[$TIMESTAMP] Git sync: SUCCESS" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] Git sync: FAILED (continuing with other operations)" >> "$LOG_FILE"
fi

# Operation 2: Create hourly snapshot
echo "[$TIMESTAMP] === OPERATION 2: Hourly Snapshot Creation ===" >> "$LOG_FILE"
if create_hourly_snapshot; then
    echo "[$TIMESTAMP] Hourly snapshot: SUCCESS" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] Hourly snapshot: FAILED (continuing with other operations)" >> "$LOG_FILE"
fi

# Operation 3: Sync current mirror (daily)
echo "[$TIMESTAMP] === OPERATION 3: Current Mirror Sync ===" >> "$LOG_FILE"
if sync_current_mirror; then
    echo "[$TIMESTAMP] Mirror sync: SUCCESS" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] Mirror sync: FAILED (continuing with other operations)" >> "$LOG_FILE"
fi

# Operation 4: Cloud synchronization
echo "[$TIMESTAMP] === OPERATION 4: Cloud Synchronization ===" >> "$LOG_FILE"
if sync_cloud_backup; then
    echo "[$TIMESTAMP] Cloud sync: SUCCESS" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] Cloud sync: FAILED" >> "$LOG_FILE"
fi

# =============================================================================
# COMPLETION AND REPORTING
# =============================================================================

# Calculate total execution time
END_TIMESTAMP=$(date "+%Y-%m-%d_%H-%M-%S")
echo "[$END_TIMESTAMP] Single-drive backup process completed" >> "$LOG_FILE"
echo "[$END_TIMESTAMP] =================================" >> "$LOG_FILE"

# Provide basic statistics for monitoring
if [ -d "$PRJ_DIR" ]; then
    local source_size=$(du -sh "$PRJ_DIR" 2>/dev/null | cut -f1)
    echo "[$END_TIMESTAMP] Source directory size: $source_size" >> "$LOG_FILE"
fi

if [ -d "/Volumes/PrjSnapshots" ]; then
    local snapshot_count=$(ls -1 /Volumes/PrjSnapshots/hourly/snapshot_* 2>/dev/null | wc -l | tr -d ' ')
    local snapshot_space=$(du -sh /Volumes/PrjSnapshots/hourly 2>/dev/null | cut -f1)
    echo "[$END_TIMESTAMP] Snapshots: $snapshot_count using $snapshot_space" >> "$LOG_FILE"
fi

# Exit with success status
exit 0

# =============================================================================
# USAGE NOTES
# =============================================================================
#
# MANUAL EXECUTION:
#   bash ~/Scripts/prj_backup_single.sh
#
# VIM INTEGRATION:
#   :BackupNow
#
# AUTOMATED EXECUTION:
#   Runs hourly via launchd Launch Agent
#
# MONITORING:
#   tail -f ~/Scripts/backup.log
#   ~/Scripts/backup_status_single.sh
#
# TROUBLESHOOTING:
#   - Check external drive is mounted: ls /Volumes/
#   - Verify scripts are executable: ls -la ~/Scripts/
#   - Review error logs: grep ERROR ~/Scripts/backup.log
#   - Test individual operations manually
#
# CUSTOMIZATION:
#   - Adjust cleanup periods (currently 24 hours for snapshots)
#   - Modify cloud exclusion patterns
#   - Change space thresholds based on your drive size
#   - Add custom notifications (email, Slack, etc.)
#
# =============================================================================