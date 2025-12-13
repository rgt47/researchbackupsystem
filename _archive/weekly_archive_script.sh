#!/bin/bash
# ~/Scripts/weekly_archive_single.sh
#
# WEEKLY ARCHIVE CREATION FOR SINGLE-DRIVE BACKUP SYSTEM
#
# PURPOSE:
# This script creates compressed long-term archives of your entire research
# project directory. It's designed to provide space-efficient preservation
# of your work while managing storage constraints on a single external drive.
#
# ARCHIVE STRATEGY:
# - Weekly archives: Created every Sunday, kept for 4 weeks
# - Monthly archives: Created first Sunday of month, kept for 6 months
# - Intelligent compression: Excludes unnecessary files to reduce size
# - Space management: Automatically cleans old archives when space is tight
# - Verification: Ensures archives are created successfully before cleanup
#
# WHY COMPRESSED ARCHIVES:
# While snapshots and mirrors provide fast access to recent data, compressed
# archives serve different purposes:
# 1. Long-term preservation: Stable format for years of storage
# 2. Space efficiency: 60-80% size reduction through compression
# 3. Portability: Single file contains entire research portfolio
# 4. Disaster recovery: Self-contained backup independent of other systems
# 5. Historical reference: Access to projects as they existed at specific dates
#
# COMPRESSION BENEFITS:
# - Source code: 80-90% compression (text compresses very well)
# - Documentation: 60-70% compression (Word docs, PDFs moderate compression)
# - Data files: 30-50% compression (varies greatly by file type)
# - Overall project: Typically 70% compression on research directories
#
# SPACE MANAGEMENT:
# The 100GB archive partition handles:
# - 4 weekly archives: ~15GB each = 60GB
# - 6 monthly archives: ~15GB each = 90GB (some overlap with weekly)
# - Current mirror: ~20GB
# - Buffer space: ~10GB for operations
#
# AUTOMATION:
# - Scheduled via cron every Sunday at 2 AM
# - Runs automatically without user intervention
# - Handles errors gracefully and logs all operations
# - Integrates with space management system
#
# AUTHOR: Research Computing Guide
# VERSION: 2.0 (Single Drive)

# =============================================================================
# CONFIGURATION AND SETUP
# =============================================================================

# Core directories and files
PRJ_DIR="$HOME/prj"
ARCHIVE_DIR="/Volumes/PrjArchive"
WEEKLY_DIR="$ARCHIVE_DIR/weekly"
MONTHLY_DIR="$ARCHIVE_DIR/monthly"
LOG_FILE="$HOME/Scripts/backup.log"
TIMESTAMP=$(date "+%Y-%m-%d")
TIME_FULL=$(date "+%Y-%m-%d %H:%M:%S")

# Archive file names
WEEKLY_ARCHIVE="$WEEKLY_DIR/prj_weekly_$TIMESTAMP.tar.gz"
MONTHLY_ARCHIVE="$MONTHLY_DIR/prj_monthly_$(date +%Y-%m).tar.gz"

# Space thresholds (in GB)
MIN_SPACE_REQUIRED=25    # Minimum space needed for archive creation
CLEANUP_THRESHOLD=10     # Trigger aggressive cleanup below this
CRITICAL_THRESHOLD=5     # Emergency cleanup threshold

echo "[$TIME_FULL] =================================" >> "$LOG_FILE"
echo "[$TIME_FULL] Starting weekly archive creation" >> "$LOG_FILE"
echo "[$TIME_FULL] Archive date: $TIMESTAMP" >> "$LOG_FILE"
echo "[$TIME_FULL] Target directory: $PRJ_DIR" >> "$LOG_FILE"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function: get_available_space
# Purpose: Get available space in GB for the archive partition
get_available_space() {
    if [ -d "$ARCHIVE_DIR" ]; then
        df -g "$ARCHIVE_DIR" | tail -1 | awk '{print $4}'
    else
        echo "0"
    fi
}

# Function: get_directory_size
# Purpose: Get size of a directory in GB
get_directory_size() {
    local dir="$1"
    if [ -d "$dir" ]; then
        du -sg "$dir" 2>/dev/null | cut -f1
    else
        echo "0"
    fi
}

# Function: verify_source_directory
# Purpose: Ensure source directory exists and is accessible
verify_source_directory() {
    if [ ! -d "$PRJ_DIR" ]; then
        echo "[$TIME_FULL] ERROR: Source directory not found: $PRJ_DIR" >> "$LOG_FILE"
        return 1
    fi
    
    local source_size=$(get_directory_size "$PRJ_DIR")
    echo "[$TIME_FULL] Source directory verified: ${source_size}GB" >> "$LOG_FILE"
    
    # Check if source directory is reasonable size (not empty, not huge)
    if [ "$source_size" -eq 0 ]; then
        echo "[$TIME_FULL] WARNING: Source directory appears empty" >> "$LOG_FILE"
        return 1
    elif [ "$source_size" -gt 100 ]; then
        echo "[$TIME_FULL] WARNING: Source directory unusually large (${source_size}GB)" >> "$LOG_FILE"
    fi
    
    return 0
}

# Function: ensure_archive_directories
# Purpose: Create archive directories if they don't exist
ensure_archive_directories() {
    if [ ! -d "$ARCHIVE_DIR" ]; then
        echo "[$TIME_FULL] ERROR: Archive partition not mounted at $ARCHIVE_DIR" >> "$LOG_FILE"
        return 1
    fi
    
    # Create subdirectories
    mkdir -p "$WEEKLY_DIR" "$MONTHLY_DIR"
    
    if [ ! -d "$WEEKLY_DIR" ] || [ ! -d "$MONTHLY_DIR" ]; then
        echo "[$TIME_FULL] ERROR: Could not create archive directories" >> "$LOG_FILE"
        return 1
    fi
    
    echo "[$TIME_FULL] Archive directories verified" >> "$LOG_FILE"
    return 0
}

# Function: check_space_requirements
# Purpose: Verify sufficient space for archive creation
check_space_requirements() {
    local available=$(get_available_space)
    local source_size=$(get_directory_size "$PRJ_DIR")
    
    echo "[$TIME_FULL] Space check: ${available}GB available, ${source_size}GB source" >> "$LOG_FILE"
    
    if [ "$available" -lt "$MIN_SPACE_REQUIRED" ]; then
        echo "[$TIME_FULL] ERROR: Insufficient space for archive creation" >> "$LOG_FILE"
        echo "[$TIME_FULL] Required: ${MIN_SPACE_REQUIRED}GB, Available: ${available}GB" >> "$LOG_FILE"
        return 1
    fi
    
    return 0
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

# Function: cleanup_old_archives
# Purpose: Remove old archives based on retention policy and space availability
cleanup_old_archives() {
    local available=$(get_available_space)
    local cleanup_level="normal"
    
    # Determine cleanup aggressiveness based on available space
    if [ "$available" -lt "$CRITICAL_THRESHOLD" ]; then
        cleanup_level="aggressive"
        echo "[$TIME_FULL] CRITICAL SPACE: Performing aggressive cleanup" >> "$LOG_FILE"
    elif [ "$available" -lt "$CLEANUP_THRESHOLD" ]; then
        cleanup_level="moderate"
        echo "[$TIME_FULL] LOW SPACE: Performing moderate cleanup" >> "$LOG_FILE"
    else
        echo "[$TIME_FULL] Performing normal cleanup" >> "$LOG_FILE"
    fi
    
    # Weekly archive cleanup
    cleanup_weekly_archives "$cleanup_level"
    
    # Monthly archive cleanup
    cleanup_monthly_archives "$cleanup_level"
    
    # Report final space status
    local final_space=$(get_available_space)
    echo "[$TIME_FULL] Post-cleanup space: ${final_space}GB available" >> "$LOG_FILE"
}

# Function: cleanup_weekly_archives
# Purpose: Clean up weekly archives based on retention policy
cleanup_weekly_archives() {
    local cleanup_level="$1"
    local retention_days
    
    case "$cleanup_level" in
        "aggressive")
            retention_days=7    # Keep only 1 week
            ;;
        "moderate")
            retention_days=21   # Keep 3 weeks
            ;;
        *)
            retention_days=28   # Keep 4 weeks (normal)
            ;;
    esac
    
    echo "[$TIME_FULL] Cleaning weekly archives older than $retention_days days" >> "$LOG_FILE"
    
    if [ -d "$WEEKLY_DIR" ]; then
        local old_archives=$(find "$WEEKLY_DIR" -name "prj_weekly_*.tar.gz" -mtime "+$retention_days" 2>/dev/null)
        local count=0
        local freed_space=0
        
        if [ -n "$old_archives" ]; then
            echo "$old_archives" | while read archive_file; do
                if [ -f "$archive_file" ]; then
                    local archive_size=$(du -sm "$archive_file" 2>/dev/null | cut -f1 || echo "0")
                    local archive_name=$(basename "$archive_file")
                    
                    echo "[$TIME_FULL] Removing old weekly archive: $archive_name (${archive_size}MB)" >> "$LOG_FILE"
                    rm -f "$archive_file"
                    
                    count=$((count + 1))
                    freed_space=$((freed_space + archive_size))
                fi
            done
            
            echo "[$TIME_FULL] Weekly cleanup: removed $count archives, freed ${freed_space}MB" >> "$LOG_FILE"
        else
            echo "[$TIME_FULL] No weekly archives older than $retention_days days found" >> "$LOG_FILE"
        fi
    fi
}

# Function: cleanup_monthly_archives
# Purpose: Clean up monthly archives based on retention policy
cleanup_monthly_archives() {
    local cleanup_level="$1"
    local retention_days
    
    case "$cleanup_level" in
        "aggressive")
            retention_days=60   # Keep 2 months
            ;;
        "moderate")
            retention_days=120  # Keep 4 months
            ;;
        *)
            retention_days=180  # Keep 6 months (normal)
            ;;
    esac
    
    echo "[$TIME_FULL] Cleaning monthly archives older than $retention_days days" >> "$LOG_FILE"
    
    if [ -d "$MONTHLY_DIR" ]; then
        local old_archives=$(find "$MONTHLY_DIR" -name "prj_monthly_*.tar.gz" -mtime "+$retention_days" 2>/dev/null)
        local count=0
        local freed_space=0
        
        if [ -n "$old_archives" ]; then
            echo "$old_archives" | while read archive_file; do
                if [ -f "$archive_file" ]; then
                    local archive_size=$(du -sm "$archive_file" 2>/dev/null | cut -f1 || echo "0")
                    local archive_name=$(basename "$archive_file")
                    
                    echo "[$TIME_FULL] Removing old monthly archive: $archive_name (${archive_size}MB)" >> "$LOG_FILE"
                    rm -f "$archive_file"
                    
                    count=$((count + 1))
                    freed_space=$((freed_space + archive_size))
                fi
            done
            
            echo "[$TIME_FULL] Monthly cleanup: removed $count archives, freed ${freed_space}MB" >> "$LOG_FILE"
        else
            echo "[$TIME_FULL] No monthly archives older than $retention_days days found" >> "$LOG_FILE"
        fi
    fi
}

# =============================================================================
# ARCHIVE CREATION FUNCTIONS
# =============================================================================

# Function: create_weekly_archive
# Purpose: Create compressed weekly archive with optimized settings
create_weekly_archive() {
    echo "[$TIME_FULL] Creating weekly archive: $WEEKLY_ARCHIVE" >> "$LOG_FILE"
    
    # Check if this week's archive already exists
    if [ -f "$WEEKLY_ARCHIVE" ]; then
        echo "[$TIME_FULL] Weekly archive already exists for $TIMESTAMP" >> "$LOG_FILE"
        return 0
    fi
    
    # Create temporary file for archive (safer than creating directly)
    local temp_archive="${WEEKLY_ARCHIVE}.tmp"
    
    echo "[$TIME_FULL] Starting compression (this may take several minutes)" >> "$LOG_FILE"
    local start_time=$(date +%s)
    
    # Create compressed archive with optimized settings
    # -c: create archive
    # -z: compress with gzip
    # -f: specify filename
    # -C: change to directory before adding files
    # --exclude: skip unnecessary files that don't need backup
    tar -czf "$temp_archive" \
        -C "$HOME" \
        --exclude="prj/**/.git/objects" \
        --exclude="prj/**/.git/logs" \
        --exclude="prj/**/.git/refs/remotes" \
        --exclude="prj/**/node_modules" \
        --exclude="prj/**/__pycache__" \
        --exclude="prj/**/.pytest_cache" \
        --exclude="prj/**/*.tmp" \
        --exclude="prj/**/*.temp" \
        --exclude="prj/**/.DS_Store" \
        --exclude="prj/**/.Trash" \
        --exclude="prj/**/Thumbs.db" \
        --exclude="prj/**/*.pyc" \
        --exclude="prj/**/*.pyo" \
        --exclude="prj/**/*.class" \
        --exclude="prj/**/*.o" \
        --exclude="prj/**/*.so" \
        --exclude="prj/**/*.dylib" \
        --exclude="prj/**/build/" \
        --exclude="prj/**/dist/" \
        --exclude="prj/**/target/" \
        prj/
    
    local tar_exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ $tar_exit_code -eq 0 ]; then
        # Move temporary file to final location
        mv "$temp_archive" "$WEEKLY_ARCHIVE"
        
        # Verify archive was created successfully
        if [ -f "$WEEKLY_ARCHIVE" ]; then
            local archive_size=$(du -sh "$WEEKLY_ARCHIVE" 2>/dev/null | cut -f1)
            echo "[$TIME_FULL] Weekly archive created successfully: $archive_size in ${duration}s" >> "$LOG_FILE"
            
            # Test archive integrity
            if tar -tzf "$WEEKLY_ARCHIVE" >/dev/null 2>&1; then
                echo "[$TIME_FULL] Archive integrity verified" >> "$LOG_FILE"
                return 0
            else
                echo "[$TIME_FULL] ERROR: Archive integrity check failed" >> "$LOG_FILE"
                rm -f "$WEEKLY_ARCHIVE"
                return 1
            fi
        else
            echo "[$TIME_FULL] ERROR: Archive file not found after creation" >> "$LOG_FILE"
            return 1
        fi
    else
        echo "[$TIME_FULL] ERROR: Archive creation failed with exit code $tar_exit_code" >> "$LOG_FILE"
        
        # Clean up temporary file
        rm -f "$temp_archive"
        return 1
    fi
}

# Function: create_monthly_archive
# Purpose: Create monthly archive (first Sunday of month)
create_monthly_archive() {
    local day_of_month=$(date +%d)
    
    # Only create monthly archive on first Sunday of month (day 1-7)
    if [ "$day_of_month" -le 7 ]; then
        echo "[$TIME_FULL] Creating monthly archive (first Sunday of month)" >> "$LOG_FILE"
        
        # Check if this month's archive already exists
        if [ -f "$MONTHLY_ARCHIVE" ]; then
            echo "[$TIME_FULL] Monthly archive already exists for $(date +%Y-%m)" >> "$LOG_FILE"
            return 0
        fi
        
        # Copy weekly archive to monthly (more efficient than re-compressing)
        if [ -f "$WEEKLY_ARCHIVE" ]; then
            echo "[$TIME_FULL] Copying weekly archive to monthly archive" >> "$LOG_FILE"
            cp "$WEEKLY_ARCHIVE" "$MONTHLY_ARCHIVE"
            
            if [ -f "$MONTHLY_ARCHIVE" ]; then
                local monthly_size=$(du -sh "$MONTHLY_ARCHIVE" 2>/dev/null | cut -f1)
                echo "[$TIME_FULL] Monthly archive created: $monthly_size" >> "$LOG_FILE"
                return 0
            else
                echo "[$TIME_FULL] ERROR: Failed to create monthly archive" >> "$LOG_FILE"
                return 1
            fi
        else
            echo "[$TIME_FULL] ERROR: Weekly archive not found for monthly copy" >> "$LOG_FILE"
            return 1
        fi
    else
        echo "[$TIME_FULL] Skipping monthly archive (not first Sunday of month)" >> "$LOG_FILE"
        return 0
    fi
}

# Function: generate_archive_report
# Purpose: Create summary report of archive status
generate_archive_report() {
    echo "[$TIME_FULL] === ARCHIVE STATUS REPORT ===" >> "$LOG_FILE"
    
    # Count and size of weekly archives
    if [ -d "$WEEKLY_DIR" ]; then
        local weekly_count=$(ls -1 "$WEEKLY_DIR"/prj_weekly_*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
        local weekly_size=$(du -sh "$WEEKLY_DIR" 2>/dev/null | cut -f1)
        echo "[$TIME_FULL] Weekly archives: $weekly_count files using $weekly_size" >> "$LOG_FILE"
        
        if [ "$weekly_count" -gt 0 ]; then
            echo "[$TIME_FULL] Recent weekly archives:" >> "$LOG_FILE"
            ls -lt "$WEEKLY_DIR"/prj_weekly_*.tar.gz 2>/dev/null | head -3 | while read line; do
                local archive_name=$(echo "$line" | awk '{print $9}')
                local archive_size=$(echo "$line" | awk '{print $5}')
                local archive_date=$(echo "$line" | awk '{print $6, $7, $8}')
                echo "[$TIME_FULL]   $(basename "$archive_name"): $archive_size bytes ($archive_date)" >> "$LOG_FILE"
            done
        fi
    fi
    
    # Count and size of monthly archives
    if [ -d "$MONTHLY_DIR" ]; then
        local monthly_count=$(ls -1 "$MONTHLY_DIR"/prj_monthly_*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
        local monthly_size=$(du -sh "$MONTHLY_DIR" 2>/dev/null | cut -f1)
        echo "[$TIME_FULL] Monthly archives: $monthly_count files using $monthly_size" >> "$LOG_FILE"
    fi
    
    # Overall archive partition usage
    local total_used=$(du -sh "$ARCHIVE_DIR" 2>/dev/null | cut -f1)
    local available=$(get_available_space)
    echo "[$TIME_FULL] Archive partition: $total_used used, ${available}GB available" >> "$LOG_FILE"
    
    echo "[$TIME_FULL] === END ARCHIVE REPORT ===" >> "$LOG_FILE"
}

# =============================================================================
# MAIN EXECUTION SEQUENCE
# =============================================================================

# Verification phase
echo "[$TIME_FULL] === VERIFICATION PHASE ===" >> "$LOG_FILE"

if ! verify_source_directory; then
    echo "[$TIME_FULL] FATAL: Source directory verification failed" >> "$LOG_FILE"
    exit 1
fi

if ! ensure_archive_directories; then
    echo "[$TIME_FULL] FATAL: Archive directory setup failed" >> "$LOG_FILE"
    exit 1
fi

# Pre-cleanup to ensure space
echo "[$TIME_FULL] === PRE-CLEANUP PHASE ===" >> "$LOG_FILE"
cleanup_old_archives

# Space check after cleanup
if ! check_space_requirements; then
    echo "[$TIME_FULL] FATAL: Insufficient space even after cleanup" >> "$LOG_FILE"
    exit 1
fi

# Archive creation phase
echo "[$TIME_FULL] === ARCHIVE CREATION PHASE ===" >> "$LOG_FILE"

# Create weekly archive
if create_weekly_archive; then
    echo "[$TIME_FULL] Weekly archive creation: SUCCESS" >> "$LOG_FILE"
    
    # Create monthly archive if appropriate
    if create_monthly_archive; then
        echo "[$TIME_FULL] Monthly archive creation: SUCCESS" >> "$LOG_FILE"
    else
        echo "[$TIME_FULL] Monthly archive creation: SKIPPED or FAILED" >> "$LOG_FILE"
    fi
else
    echo "[$TIME_FULL] ERROR: Weekly archive creation failed" >> "$LOG_FILE"
    exit 1
fi

# Final cleanup (more conservative after successful archive creation)
echo "[$TIME_FULL] === POST-CREATION CLEANUP ===" >> "$LOG_FILE"
cleanup_old_archives

# Generate final report
generate_archive_report

# Success completion
echo "[$TIME_FULL] Weekly archive process completed successfully" >> "$LOG_FILE"
echo "[$TIME_FULL] =================================" >> "$LOG_FILE"

exit 0

# =============================================================================
# USAGE NOTES
# =============================================================================
#
# AUTOMATED EXECUTION (Recommended):
#   Add to crontab for weekly execution:
#   0 2 * * 0 /Users/USERNAME/Scripts/weekly_archive_single.sh
#
# MANUAL EXECUTION:
#   bash ~/Scripts/weekly_archive_single.sh
#
# TESTING:
#   # Test archive creation without waiting for Sunday
#   TIMESTAMP=$(date "+%Y-%m-%d") ~/Scripts/weekly_archive_single.sh
#
# MONITORING:
#   tail -f ~/Scripts/backup.log | grep archive
#
# SPACE MANAGEMENT:
#   # Check space before running
#   df -h /Volumes/PrjArchive
#
# CUSTOMIZATION:
#   - Modify exclusion patterns in tar command
#   - Adjust retention periods in cleanup functions
#   - Change compression level (add -1 for fast, -9 for maximum compression)
#   - Add email notifications on success/failure
#
# RECOVERY FROM ARCHIVES:
#   # Extract weekly archive
#   tar -xzf /Volumes/PrjArchive/weekly/prj_weekly_YYYY-MM-DD.tar.gz -C ~/
#
#   # Extract specific project from archive
#   tar -xzf archive.tar.gz -C /tmp/ prj/PROJECT_NAME
#
#   # List contents of archive
#   tar -tzf archive.tar.gz | head -20
#
# =============================================================================