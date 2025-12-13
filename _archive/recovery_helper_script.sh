#!/bin/bash
# ~/Scripts/recovery_helper_single.sh
#
# COMPREHENSIVE DATA RECOVERY GUIDE AND HELPER
#
# PURPOSE:
# This script serves as your primary resource during data loss scenarios,
# providing clear guidance on available recovery options and exact commands
# needed to restore your research data. It's designed to be used when you're
# under stress and need quick, reliable recovery procedures.
#
# RECOVERY SCENARIOS COVERED:
# 1. Recent file deletion (last few hours)
# 2. Project corruption or unwanted changes (last 24 hours)
# 3. Complete project directory loss
# 4. External drive failure
# 5. System failure or laptop replacement
# 6. Specific file or directory recovery
# 7. Git repository corruption or history loss
#
# RECOVERY SOURCES ANALYZED:
# - Hourly snapshots (fastest, most recent)
# - Daily mirror (complete, easy to browse)
# - Weekly/monthly archives (compressed, long-term)
# - Cloud backups (offsite, accessible anywhere)
# - Individual Git repositories (version control)
# - Time Machine (complete system recovery)
#
# RECOVERY STRATEGIES:
# - Fastest recovery: Recent snapshots
# - Complete recovery: Daily mirror or archives
# - Selective recovery: Individual files or projects
# - Remote recovery: Cloud backups when hardware unavailable
# - Historical recovery: Specific dates or versions
#
# AUTHOR: Research Computing Guide
# VERSION: 2.0 (Single Drive)

# =============================================================================
# CONFIGURATION AND SETUP
# =============================================================================

# Color codes for better readability during stressful recovery situations
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

# Core paths
PRJ_DIR="$HOME/prj"
SNAPSHOT_DIR="/Volumes/PrjSnapshots/hourly"
ARCHIVE_DIR="/Volumes/PrjArchive"
CURRENT_MIRROR="$ARCHIVE_DIR/current_mirror"
WEEKLY_ARCHIVES="$ARCHIVE_DIR/weekly"
MONTHLY_ARCHIVES="$ARCHIVE_DIR/monthly"

echo -e "${BOLD}=== DATA RECOVERY HELPER ===${NC}"
echo -e "${BOLD}Single Drive Backup System Recovery Guide${NC}"
echo ""
echo -e "${CYAN}Date: $(date)${NC}"
echo -e "${CYAN}Recovery options analyzed for: $PRJ_DIR${NC}"
echo ""

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function: format_timestamp
# Purpose: Convert snapshot timestamp to readable format
format_timestamp() {
    local timestamp="$1"
    local formatted=$(echo "$timestamp" | sed 's/snapshot_//' | sed 's/_/ /' | sed 's/-/:/3' | sed 's/-/:/3')
    echo "$formatted"
}

# Function: calculate_age
# Purpose: Calculate how old a backup is in human-readable format
calculate_age() {
    local file_path="$1"
    if [ -f "$file_path" ] || [ -d "$file_path" ]; then
        local file_age=$(stat -f "%m" "$file_path" 2>/dev/null)
        local current_time=$(date +%s)
        local diff=$((current_time - file_age))
        
        if [ "$diff" -lt 3600 ]; then
            echo "$((diff / 60)) minutes ago"
        elif [ "$diff" -lt 86400 ]; then
            echo "$((diff / 3600)) hours ago"
        else
            echo "$((diff / 86400)) days ago"
        fi
    else
        echo "Unknown"
    fi
}

# Function: check_recovery_source
# Purpose: Verify if a recovery source is available and provide details
check_recovery_source() {
    local source_path="$1"
    local source_name="$2"
    
    if [ -d "$source_path" ] || [ -f "$source_path" ]; then
        local size=$(du -sh "$source_path" 2>/dev/null | cut -f1)
        local age=$(calculate_age "$source_path")
        echo -e "${GREEN}✓ Available${NC} - Size: $size, Age: $age"
        return 0
    else
        echo -e "${RED}✗ Not available${NC}"
        return 1
    fi
}

# =============================================================================
# RECOVERY SOURCE ANALYSIS
# =============================================================================

echo -e "${BLUE}=== AVAILABLE RECOVERY SOURCES ===${NC}"
echo ""

# Check hourly snapshots
echo -e "${BOLD}1. HOURLY SNAPSHOTS${NC} (Fastest, Most Recent)"
echo "   Purpose: Recover recent changes from the last 24 hours"
echo "   Best for: File deletions, unwanted edits, corruption in last day"
echo ""

if [ -d "$SNAPSHOT_DIR" ]; then
    local snapshots=($(ls -1t "$SNAPSHOT_DIR"/snapshot_* 2>/dev/null))
    local snapshot_count=${#snapshots[@]}
    
    if [ $snapshot_count -gt 0 ]; then
        echo "   Available snapshots: $snapshot_count"
        echo "   Recent snapshots:"
        
        for i in $(seq 0 $((snapshot_count < 10 ? snapshot_count - 1 : 9))); do
            local snapshot_path="${snapshots[$i]}"
            local snapshot_name=$(basename "$snapshot_path")
            local formatted_time=$(format_timestamp "$snapshot_name")
            local age=$(calculate_age "$snapshot_path")
            
            echo "     $formatted_time ($age)"
        done
        
        # Check snapshot health
        local latest_snapshot="${snapshots[0]}"
        local latest_age=$(calculate_age "$latest_snapshot")
        echo ""
        echo -e "   Status: $(check_recovery_source "$latest_snapshot" "Latest Snapshot")"
        
        if [ -d "$latest_snapshot" ]; then
            local snapshot_projects=$(find "$latest_snapshot" -maxdepth 1 -type d | wc -l | tr -d ' ')
            echo "   Latest snapshot contains: $((snapshot_projects - 1)) project directories"
        fi
    else
        echo -e "   ${RED}No snapshots available${NC}"
    fi
else
    echo -e "   ${RED}Snapshot directory not accessible${NC}"
fi

echo ""

# Check daily mirror
echo -e "${BOLD}2. DAILY MIRROR${NC} (Complete, Easy to Browse)"
echo "   Purpose: Complete copy of all projects, synced daily"
echo "   Best for: Browsing projects, bulk recovery, complete restoration"
echo ""

if [ -d "$CURRENT_MIRROR" ]; then
    echo -e "   Status: $(check_recovery_source "$CURRENT_MIRROR" "Daily Mirror")"
    
    local last_sync_file="$CURRENT_MIRROR/.last_sync"
    if [ -f "$last_sync_file" ]; then
        local last_sync=$(cat "$last_sync_file")
        echo "   Last synchronized: $last_sync"
        
        # Check if sync is current
        local today=$(date +%Y-%m-%d)
        if [ "$last_sync" = "$today" ]; then
            echo -e "   ${GREEN}Mirror is current (synced today)${NC}"
        else
            echo -e "   ${YELLOW}Mirror is from: $last_sync${NC}"
        fi
    fi
    
    if [ -d "$CURRENT_MIRROR" ]; then
        local mirror_projects=$(find "$CURRENT_MIRROR" -maxdepth 1 -type d | wc -l | tr -d ' ')
        echo "   Mirror contains: $((mirror_projects - 1)) project directories"
    fi
else
    echo -e "   Status: ${RED}Daily mirror not available${NC}"
fi

echo ""

# Check weekly archives
echo -e "${BOLD}3. WEEKLY ARCHIVES${NC} (Compressed, Medium-term)"
echo "   Purpose: Compressed backups from recent weeks"
echo "   Best for: Recovering projects from 1-4 weeks ago"
echo ""

if [ -d "$WEEKLY_ARCHIVES" ]; then
    local weekly_files=($(ls -1t "$WEEKLY_ARCHIVES"/prj_weekly_*.tar.gz 2>/dev/null))
    local weekly_count=${#weekly_files[@]}
    
    if [ $weekly_count -gt 0 ]; then
        echo "   Available archives: $weekly_count"
        echo "   Recent weekly archives:"
        
        for i in $(seq 0 $((weekly_count < 5 ? weekly_count - 1 : 4))); do
            local archive_path="${weekly_files[$i]}"
            local archive_name=$(basename "$archive_path")
            local archive_date=$(echo "$archive_name" | sed 's/prj_weekly_//' | sed 's/.tar.gz//')
            local archive_size=$(du -sh "$archive_path" 2>/dev/null | cut -f1)
            local age=$(calculate_age "$archive_path")
            
            echo "     $archive_date ($archive_size, $age)"
        done
        
        echo ""
        echo -e "   Status: $(check_recovery_source "${weekly_files[0]}" "Latest Weekly Archive")"
    else
        echo -e "   ${RED}No weekly archives available${NC}"
    fi
else
    echo -e "   ${RED}Weekly archives directory not accessible${NC}"
fi

echo ""

# Check monthly archives
echo -e "${BOLD}4. MONTHLY ARCHIVES${NC} (Compressed, Long-term)"
echo "   Purpose: Long-term preservation archives"
echo "   Best for: Recovering projects from months ago, historical research"
echo ""

if [ -d "$MONTHLY_ARCHIVES" ]; then
    local monthly_files=($(ls -1t "$MONTHLY_ARCHIVES"/prj_monthly_*.tar.gz 2>/dev/null))
    local monthly_count=${#monthly_files[@]}
    
    if [ $monthly_count -gt 0 ]; then
        echo "   Available archives: $monthly_count"
        echo "   Monthly archives:"
        
        for i in $(seq 0 $((monthly_count - 1))); do
            local archive_path="${monthly_files[$i]}"
            local archive_name=$(basename "$archive_path")
            local archive_month=$(echo "$archive_name" | sed 's/prj_monthly_//' | sed 's/.tar.gz//')
            local archive_size=$(du -sh "$archive_path" 2>/dev/null | cut -f1)
            local age=$(calculate_age "$archive_path")
            
            echo "     $archive_month ($archive_size, $age)"
        done
        
        echo ""
        echo -e "   Status: $(check_recovery_source "${monthly_files[0]}" "Latest Monthly Archive")"
    else
        echo -e "   ${RED}No monthly archives available${NC}"
    fi
else
    echo -e "   ${RED}Monthly archives directory not accessible${NC}"
fi

echo ""

# Check cloud backup status
echo -e "${BOLD}5. CLOUD BACKUPS${NC} (Offsite, Always Accessible)"
echo "   Purpose: Remote access when local backups unavailable"
echo "   Best for: Complete system failure, remote recovery, travel access"
echo ""

if command -v rclone >/dev/null 2>&1; then
    # Test Google Drive connectivity
    if rclone lsd googledrive: >/dev/null 2>&1; then
        echo -e "   Google Drive: ${GREEN}✓ Connected and accessible${NC}"
        
        # Try to get basic info about cloud backup
        local cloud_dirs=$(rclone lsd googledrive:prj/ 2>/dev/null | wc -l | tr -d ' ')
        if [ "$cloud_dirs" -gt 0 ]; then
            echo "   Contains: $cloud_dirs project directories"
        fi
    else
        echo -e "   Google Drive: ${RED}✗ Not accessible${NC}"
    fi
    
    # Test Dropbox connectivity (if configured)
    if rclone lsd dropbox: >/dev/null 2>&1; then
        echo -e "   Dropbox: ${GREEN}✓ Connected and accessible${NC}"
    else
        echo -e "   Dropbox: ${YELLOW}Not configured or not accessible${NC}"
    fi
else
    echo -e "   ${RED}rclone not available - cloud recovery not possible${NC}"
fi

echo ""

# Check Git repositories
echo -e "${BOLD}6. GIT REPOSITORIES${NC} (Version Control, Individual Projects)"
echo "   Purpose: Individual project recovery with full version history"
echo "   Best for: Specific project recovery, accessing old versions, collaboration"
echo ""

if [ -f "$HOME/Scripts/repo_list.txt" ]; then
    local total_repos=$(wc -l < "$HOME/Scripts/repo_list.txt" | tr -d ' ')
    local github_repos=0
    
    while IFS='|' read -r project_name project_dir remote_url; do
        if [ "$remote_url" != "NO_REMOTE" ]; then
            github_repos=$((github_repos + 1))
        fi
    done < "$HOME/Scripts/repo_list.txt"
    
    echo "   Total repositories: $total_repos"
    echo "   With GitHub remotes: $github_repos"
    echo -e "   Status: ${GREEN}✓ Available for individual project recovery${NC}"
    
    if [ $github_repos -gt 0 ]; then
        echo "   Recovery method: Clone individual repositories from GitHub"
    fi
else
    echo -e "   ${YELLOW}Repository list not found - run discover_repos.sh${NC}"
fi

echo ""

# =============================================================================
# RECOVERY SCENARIOS AND PROCEDURES
# =============================================================================

echo -e "${BLUE}=== RECOVERY SCENARIOS AND EXACT COMMANDS ===${NC}"
echo ""

# Scenario 1: Recent file recovery
echo -e "${BOLD}SCENARIO 1: Recent File Recovery (Last Few Hours)${NC}"
echo "Problem: Accidentally deleted or modified files recently"
echo "Best source: Hourly snapshots"
echo ""

if [ -d "$SNAPSHOT_DIR" ]; then
    local latest_snapshot=$(ls -1t "$SNAPSHOT_DIR"/snapshot_* 2>/dev/null | head -1)
    if [ -n "$latest_snapshot" ]; then
        local snapshot_time=$(format_timestamp "$(basename "$latest_snapshot")")
        echo -e "${CYAN}Commands:${NC}"
        echo "# Browse the most recent snapshot ($snapshot_time):"
        echo "open '$latest_snapshot'"
        echo ""
        echo "# Recover specific file:"
        echo "cp '$latest_snapshot/PROJECT_NAME/file.txt' '$PRJ_DIR/PROJECT_NAME/'"
        echo ""
        echo "# Recover entire project:"
        echo "rsync -av '$latest_snapshot/PROJECT_NAME/' '$PRJ_DIR/PROJECT_NAME/'"
        echo ""
        echo "# Compare current vs snapshot:"
        echo "diff -r '$PRJ_DIR/PROJECT_NAME' '$latest_snapshot/PROJECT_NAME'"
    fi
else
    echo -e "${RED}No snapshots available for recent recovery${NC}"
fi

echo ""

# Scenario 2: Project directory recovery
echo -e "${BOLD}SCENARIO 2: Complete Project Directory Recovery${NC}"
echo "Problem: Lost entire project directory or major corruption"
echo "Best source: Daily mirror or latest snapshot"
echo ""

if [ -d "$CURRENT_MIRROR" ]; then
    echo -e "${CYAN}From Daily Mirror:${NC}"
    echo "# Restore entire projects directory:"
    echo "rsync -av '$CURRENT_MIRROR/' '$HOME/prj_recovered/'"
    echo ""
    echo "# Restore specific project:"
    echo "rsync -av '$CURRENT_MIRROR/PROJECT_NAME/' '$PRJ_DIR/PROJECT_NAME/'"
    echo ""
fi

if [ -d "$SNAPSHOT_DIR" ]; then
    local latest_snapshot=$(ls -1t "$SNAPSHOT_DIR"/snapshot_* 2>/dev/null | head -1)
    if [ -n "$latest_snapshot" ]; then
        echo -e "${CYAN}From Latest Snapshot:${NC}"
        echo "# Restore entire projects directory:"
        echo "rsync -av '$latest_snapshot/' '$HOME/prj_recovered/'"
        echo ""
    fi
fi

echo ""

# Scenario 3: Archive recovery
echo -e "${BOLD}SCENARIO 3: Historical Recovery (Weeks/Months Ago)${NC}"
echo "Problem: Need to recover projects from specific date in the past"
echo "Best source: Weekly or monthly archives"
echo ""

if [ -d "$WEEKLY_ARCHIVES" ]; then
    local recent_weekly=$(ls -1t "$WEEKLY_ARCHIVES"/prj_weekly_*.tar.gz 2>/dev/null | head -1)
    if [ -n "$recent_weekly" ]; then
        local archive_date=$(basename "$recent_weekly" | sed 's/prj_weekly_//' | sed 's/.tar.gz//')
        echo -e "${CYAN}From Weekly Archive ($archive_date):${NC}"
        echo "# Extract entire archive:"
        echo "tar -xzf '$recent_weekly' -C '$HOME/'"
        echo ""
        echo "# This creates: $HOME/prj/ with all projects from $archive_date"
        echo ""
        echo "# Extract specific project (requires two steps):"
        echo "tar -xzf '$recent_weekly' -C '/tmp/' 'prj/PROJECT_NAME'"
        echo "mv '/tmp/prj/PROJECT_NAME' '$PRJ_DIR/PROJECT_NAME_recovered'"
    fi
fi

if [ -d "$MONTHLY_ARCHIVES" ]; then
    local recent_monthly=$(ls -1t "$MONTHLY_ARCHIVES"/prj_monthly_*.tar.gz 2>/dev/null | head -1)
    if [ -n "$recent_monthly" ]; then
        local archive_month=$(basename "$recent_monthly" | sed 's/prj_monthly_//' | sed 's/.tar.gz//')
        echo -e "${CYAN}From Monthly Archive ($archive_month):${NC}"
        echo "# Extract entire archive:"
        echo "tar -xzf '$recent_monthly' -C '$HOME/'"
    fi
fi

echo ""

# Scenario 4: Cloud recovery
echo -e "${BOLD}SCENARIO 4: Remote/Cloud Recovery${NC}"
echo "Problem: Local backups unavailable, need remote access"
echo "Best source: Cloud storage"
echo ""

if command -v rclone >/dev/null 2>&1; then
    echo -e "${CYAN}From Google Drive:${NC}"
    echo "# Download entire projects directory:"
    echo "rclone sync googledrive:prj/ '$HOME/prj_recovered/'"
    echo ""
    echo "# Download specific project:"
    echo "rclone sync googledrive:prj/PROJECT_NAME/ '$HOME/prj_recovered/PROJECT_NAME/'"
    echo ""
    echo "# List available projects first:"
    echo "rclone lsd googledrive:prj/"
    echo ""
    
    echo -e "${CYAN}From Dropbox (if available):${NC}"
    echo "# Download entire backup:"
    echo "rclone sync dropbox:prj_backup/ '$HOME/prj_recovered/'"
else
    echo -e "${RED}rclone not available - install rclone for cloud recovery${NC}"
fi

echo ""

# Scenario 5: Git repository recovery
echo -e "${BOLD}SCENARIO 5: Individual Project Recovery from Git${NC}"
echo "Problem: Need specific project with full version history"
echo "Best source: GitHub repositories"
echo ""

echo -e "${CYAN}Single Project Recovery:${NC}"
echo "# Clone specific project:"
echo "git clone https://github.com/USERNAME/PROJECT_NAME.git '$HOME/recovered/PROJECT_NAME'"
echo ""
echo "# Clone to specific directory:"
echo "git clone https://github.com/USERNAME/PROJECT_NAME.git '$PRJ_DIR/PROJECT_NAME_recovered'"
echo ""

if [ -f "$HOME/Scripts/repo_list.txt" ]; then
    echo -e "${CYAN}Bulk Repository Recovery:${NC}"
    echo "# Create recovery script from repository list:"
    echo "cat '$HOME/Scripts/repo_list.txt' | while IFS='|' read name dir url; do"
    echo "  if [ \"\$url\" != \"NO_REMOTE\" ]; then"
    echo "    echo \"Cloning \$name from \$url\""
    echo "    git clone \"\$url\" \"$HOME/recovered/\$name\""
    echo "  fi"
    echo "done"
fi

echo ""

# Scenario 6: Time Machine recovery
echo -e "${BOLD}SCENARIO 6: Complete System Recovery${NC}"
echo "Problem: Complete system failure or need full system restore"
echo "Best source: Time Machine"
echo ""

echo -e "${CYAN}Time Machine Recovery:${NC}"
echo "# Browse Time Machine backups:"
echo "tmutil listbackups"
echo ""
echo "# Restore specific directory from Time Machine:"
echo "sudo tmutil restore '/path/to/backup/Users/$(whoami)/prj' '$HOME/prj_recovered'"
echo ""
echo "# Interactive Time Machine recovery:"
echo "# 1. Open Time Machine application"
echo "# 2. Navigate to ~/prj directory"
echo "# 3. Use timeline to select backup date"
echo "# 4. Select files/folders and click 'Restore'"

echo ""

# =============================================================================
# RECOVERY BEST PRACTICES AND SAFETY
# =============================================================================

echo -e "${BLUE}=== RECOVERY BEST PRACTICES ===${NC}"
echo ""

echo -e "${BOLD}SAFETY FIRST:${NC}"
echo "• Always recover to a NEW location first (e.g., ~/prj_recovered/)"
echo "• Never overwrite existing data until you verify the recovery"
echo "• Test recovered files before replacing originals"
echo "• Keep multiple recovery options available"
echo ""

echo -e "${BOLD}CHOOSING THE RIGHT SOURCE:${NC}"
echo "• For files deleted in the last few hours: Use hourly snapshots"
echo "• For complete project recovery: Use daily mirror"
echo "• For historical versions: Use weekly/monthly archives"
echo "• For remote access: Use cloud backups"
echo "• For version control: Use Git repositories"
echo "• For system-wide issues: Use Time Machine"
echo ""

echo -e "${BOLD}VERIFICATION STEPS:${NC}"
echo "1. Check file dates and sizes match expectations"
echo "2. Verify file contents are complete and uncorrupted"
echo "3. Test that recovered projects work properly"
echo "4. Compare recovered data with other backup sources if available"
echo ""

echo -e "${BOLD}POST-RECOVERY ACTIONS:${NC}"
echo "• Identify what caused the data loss to prevent recurrence"
echo "• Update backup procedures if gaps were discovered"
echo "• Verify all recovery sources are functioning properly"
echo "• Consider creating an immediate backup of recovered data"

echo ""

# =============================================================================
# EMERGENCY PROCEDURES
# =============================================================================

echo -e "${BLUE}=== EMERGENCY PROCEDURES ===${NC}"
echo ""

echo -e "${BOLD}COMPLETE SYSTEM FAILURE:${NC}"
echo "If your laptop is completely lost or destroyed:"
echo ""
echo "1. Access cloud backups from any computer:"
echo "   • Install rclone: https://rclone.org/downloads/"
echo "   • Configure Google Drive access"
echo "   • Download: rclone sync googledrive:prj/ ./recovered_projects/"
echo ""
echo "2. Clone Git repositories:"
echo "   • Access GitHub.com with your credentials"
echo "   • Clone important repositories individually"
echo "   • Or use GitHub CLI for bulk operations"
echo ""
echo "3. Access Time Machine backup:"
echo "   • Connect external drive to new Mac"
echo "   • Use Migration Assistant or manual recovery"
echo ""

echo -e "${BOLD}EXTERNAL DRIVE FAILURE:${NC}"
echo "If your backup drive fails completely:"
echo ""
echo "1. Immediately stop using the drive to prevent further damage"
echo "2. Use cloud backups as primary recovery source"
echo "3. Clone all Git repositories from GitHub"
echo "4. Consider professional data recovery for the failed drive"
echo "5. Purchase replacement drive and restore backup system"
echo ""

echo -e "${BOLD}NETWORK/CLOUD ACCESS ISSUES:${NC}"
echo "If you can't access cloud storage:"
echo ""
echo "1. Check internet connectivity and authentication"
echo "2. Use local backups (snapshots, mirror, archives)"
echo "3. Access Git repositories directly if GitHub is accessible"
echo "4. Use Time Machine for complete local recovery"
echo ""

# =============================================================================
# CONTACT AND SUPPORT INFORMATION
# =============================================================================

echo -e "${BLUE}=== SUPPORT INFORMATION ===${NC}"
echo ""

echo -e "${BOLD}LOG FILES FOR TROUBLESHOOTING:${NC}"
echo "• Main backup log: $HOME/Scripts/backup.log"
echo "• Git operations log: $HOME/Scripts/git_bulk.log"
echo "• System log: /var/log/system.log"
echo ""

echo -e "${BOLD}USEFUL COMMANDS FOR DIAGNOSIS:${NC}"
echo "• Check drive status: df -h"
echo "• List available backups: ls -la /Volumes/*/backup_*"
echo "• Check Time Machine: tmutil status"
echo "• Test cloud access: rclone lsd googledrive:"
echo "• Repository status: ~/Scripts/git_dashboard.sh"
echo ""

echo -e "${BOLD}ADDITIONAL RESOURCES:${NC}"
echo "• Backup system status: ~/Scripts/backup_status_single.sh"
echo "• Repository health: ~/Scripts/repo_health_check.sh"
echo "• Space management: ~/Scripts/space_manager.sh"
echo ""

echo -e "${CYAN}Recovery helper completed. Good luck with your data recovery!${NC}"
echo ""

# =============================================================================
# USAGE NOTES
# =============================================================================
#
# MANUAL EXECUTION:
#   bash ~/Scripts/recovery_helper_single.sh
#
# VIM INTEGRATION:
#   :!~/Scripts/recovery_helper_single.sh
#
# PIPE TO FILE FOR REFERENCE:
#   ~/Scripts/recovery_helper_single.sh > recovery_guide.txt
#
# SPECIFIC SCENARIO HELP:
#   ~/Scripts/recovery_helper_single.sh | grep -A 10 "SCENARIO 1"
#
# =============================================================================