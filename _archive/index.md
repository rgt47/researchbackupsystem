# Building a Rock-Solid Backup System for Large Research Projects

As researchers, our data is our lifeline. When you're managing a 20GB research directory with 300+ subdirectories (like my `~/prj` folder), a simple "drag to cloud" backup just won't cut it. This post walks through building a comprehensive, automated backup system that follows the 3-2-1 rule and integrates seamlessly with a vim-based workflow.

## The Challenge

My research setup:
- **Directory**: `~/prj` (20GB, ~300 subdirectories)
- **Hardware**: MacBook with two 1TB USB drives ("grey" and "blue")
- **Cloud accounts**: iCloud, Google Drive, Dropbox
- **Version control**: 300 individual GitHub repositories (one per project)
- **Editor**: vim

The goal: hourly automated backups across multiple storage types with easy recovery options.

## Automation vs. Manual Tasks: Understanding Your Daily Workflow

Before diving into the technical setup, it's crucial to understand what this system automates versus what requires your attention. This determines how the backup system integrates into your daily research workflow.

### Fully Automated (Set-and-Forget)

These operations run without any intervention once configured:

**Hourly:**
- ✅ **Time Machine**: Complete system backups to grey drive
- ✅ **Local snapshots**: Incremental project backups to grey drive  
- ✅ **USB mirroring**: Full project sync to blue drive
- ✅ **Cloud sync**: Project files to Google Drive via rclone

**Daily:**
- ✅ **Multi-repo Git sync**: Commits and pushes changes across all 300 repositories (6 PM)

**Weekly:**
- ✅ **Compressed archives**: Long-term storage to blue drive (Sunday 2 AM)
- ✅ **iCloud backup**: Secondary cloud sync (Sunday 8 PM)

### Semi-Automated (Triggered by Your Actions)

These happen automatically when you work, but are triggered by your vim usage:

**On file save in vim:**
- 🔄 **Smart repository sync**: Auto-commits and pushes the current project's repo (throttled to once per 5 minutes per repo)
- 🔄 **Incremental backup**: Triggers local backup if it's been more than 5 minutes since last one

**This means**: As you work and save files in vim, your individual projects stay backed up to GitHub automatically, without interrupting your flow.

### Manual Tasks (Your Regular Routine)

These require your attention and decision-making:

**Daily (recommended):**
- 👤 **System health check**: Run `:GitDashboard` in vim or `~/Scripts/git_dashboard.sh` to see which projects need attention
- 👤 **Review uncommitted changes**: Check if any projects have experimental work that shouldn't be auto-committed

**Weekly:**
- 👤 **Repository health check**: Run `:RepoHealth` to identify any problematic repositories
- 👤 **Drive space monitoring**: Ensure USB drives aren't getting full
- 👤 **Backup verification**: Spot-check that recent work appears in backups

**As needed:**
- 👤 **Recovery operations**: When you need to restore files or projects
- 👤 **Conflict resolution**: When Git pushes fail due to conflicts
- 👤 **New project setup**: Adding remotes for new repositories

### How Vim Commands Fit Your Daily Routine

The vim integration is designed around natural research workflows:

**During active work sessions:**
```vim
" While editing a file, check if this project needs attention
:GitStatus          " Quick check of current project
<leader>gs          " Sync current project immediately (if needed)
```

**Daily workflow check (morning routine):**
```vim
" Open vim in your project root and run:
:GitDashboard       " See overview of all 300 projects
:BackupStatus       " Check overall backup system health
```

**Weekly maintenance (Friday afternoon):**
```vim
:RepoHealth         " Identify any problematic repositories
:GitSyncAll         " Force sync any repos that might be behind
```

**When something seems wrong:**
```vim
:BackupNow          " Force immediate backup
:GitDashboard       " Check what needs attention
```

### The "Hands-Off" Philosophy

The system is designed so you can focus on research, not backup management:

1. **Work naturally**: Edit files in vim, save frequently - backups happen automatically
2. **Check periodically**: Quick status checks (30 seconds) show you everything is working
3. **Intervene rarely**: Only when the system alerts you to issues or conflicts

**Example daily routine:**
```bash
# Morning: Quick health check (30 seconds)
vim ~/prj/current_project/notes.md
:GitDashboard
# See: "297 clean repos, 3 with changes" - no action needed

# During work: Just work and save normally
# - Files auto-backup to local drives hourly
# - Git repos auto-sync when you save (throttled)
# - No interruption to your workflow

# End of day: Optional final check
:BackupStatus  # "All systems green" - go home!
```

This approach minimizes cognitive overhead while maximizing protection. You spend less than 5 minutes per week actively managing backups, yet have enterprise-level data protection.

## System Architecture: The 3-2-1 Strategy

The [3-2-1 backup rule](https://www.backblaze.com/blog/the-3-2-1-backup-strategy/) forms our foundation:
- **3 copies** of data (original + 2 backups)
- **2 different storage types** (local + cloud)
- **1 offsite backup** (cloud storage)

### Storage Allocation Strategy

**Grey Drive (1TB)**: Dual-purpose drive
- 800GB: Time Machine (complete system backup)
- 200GB: Project snapshots (incremental, hourly)

**Blue Drive (1TB)**: Dedicated project storage
- 600GB: Current project mirror
- 400GB: Compressed weekly/monthly archives

## Part 1: USB Drive Setup

### Partitioning the Drives

First, let's partition our drives for optimal organization:

```bash
# Grey drive: Time Machine + Project snapshots
diskutil partitionDisk /dev/diskX JHFS+ "TimeMachine" 800G JHFS+ "PrjSnapshots" 200G

# Blue drive: Current mirror + Archives
diskutil partitionDisk /dev/diskY JHFS+ "PrjMirror" 600G JHFS+ "PrjArchive" 400G
```

::: {.callout-important}
Replace `/dev/diskX` and `/dev/diskY` with your actual device identifiers. Use `diskutil list` to find them.
:::

### Configure Time Machine on Grey Drive

The grey drive's larger partition handles complete system backups:

1. **Set up Time Machine**:
   - Connect the grey drive
   - When prompted, click "Use as Backup Disk" OR:
   - Go to **System Preferences** > **Time Machine**
   - Click "Select Backup Disk"
   - Choose the "TimeMachine" partition on grey drive
   - Click "Use Disk"

2. **Optimize Time Machine Settings**:
   ```bash
   # In Time Machine preferences:
   # ✓ Back up automatically
   # ✓ Back up while on battery power (optional)
   ```
   
   - Click "Options" to exclude unnecessary folders:
     - Downloads folder
     - Trash
     - Large temporary directories

::: {.callout-note}
Time Machine will now automatically backup your entire system hourly when the grey drive is connected, providing complete system recovery capabilities alongside our project-specific backups.
:::

### Setting Up Directory Structure

```bash
# Create organized directory structure on blue drive
mkdir -p /Volumes/PrjMirror/current
mkdir -p /Volumes/PrjArchive/weekly
mkdir -p /Volumes/PrjArchive/monthly
```

## Part 2: The Master Backup Script

This script handles the heavy lifting of backing up a large directory structure efficiently:

```bash
#!/bin/bash
# ~/Scripts/recovery_helper.sh

echo "=== RECOVERY OPTIONS FOR LARGE PROJECT (300 subdirs, 20GB) ==="
echo ""

show_recovery_options() {
    echo "Available recovery options:"
    echo ""
    
    echo "1. GREY DRIVE SNAPSHOTS (Fast, Recent):"
    if [ -d "/Volumes/PrjSnapshots" ]; then
        ls -lt /Volumes/PrjSnapshots/snapshot_* 2>/dev/null | head -5 | while read line; do
            dir_name=$(echo "$line" | awk '{print $9}')
            if [ -n "$dir_name" ]; then
                timestamp=$(basename "$dir_name" | sed 's/snapshot_//')
                size=$(du -sh "$dir_name" 2>/dev/null | cut -f1)
                echo "   $timestamp ($size)"
            fi
        done
    else
        echo "   Not available"
    fi
    echo ""
    
    echo "2. BLUE DRIVE MIRROR (Complete, Current):"
    if [ -d "/Volumes/PrjMirror/current" ]; then
        if [ -f "/Volumes/PrjMirror/current/.last_backup" ]; then
            last_backup=$(cat /Volumes/PrjMirror/current/.last_backup)
            size=$(du -sh /Volumes/PrjMirror/current 2>/dev/null | cut -f1)
            echo "   Last backup: $last_backup ($size)"
        else
            echo "   Available but no timestamp"
        fi
    else
        echo "   Not available"
    fi
    echo ""
    
    echo "3. WEEKLY ARCHIVES (Compressed, Historical):"
    if [ -d "/Volumes/PrjArchive/weekly" ]; then
        ls -lt /Volumes/PrjArchive/weekly/prj_weekly_*.tar.gz 2>/dev/null | head -3 | while read line; do
            file_name=$(echo "$line" | awk '{print $9}')
            if [ -n "$file_name" ]; then
                date_part=$(basename "$file_name" | sed 's/prj_weekly_//' | sed 's/.tar.gz//')
                size=$(ls -lh "$file_name" | awk '{print $5}')
                echo "   $date_part ($size compressed)"
            fi
        done
    else
        echo "   Not available"
    fi
    echo ""
    
    echo "4. INDIVIDUAL GIT REPOSITORIES:"
    if [ -f "$HOME/Scripts/repo_list.txt" ]; then
        total_repos=$(wc -l < "$HOME/Scripts/repo_list.txt")
        echo "   Total repositories available: $total_repos"
        echo "   All repositories accessible via GitHub"
    else
        echo "   Repository list not found"
    fi
    echo ""
    
    echo "5. TIME MACHINE (System-wide):"
    tmutil listbackups 2>/dev/null | tail -3 | while read backup; do
        date_part=$(basename "$backup")
        echo "   $date_part"
    done
    echo ""
    
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
    
    echo "From individual Git repositories:"
    echo "  # Clone specific project"
    echo "  git clone https://github.com/rgt47/PROJECT_NAME.git ~/recovered/PROJECT_NAME"
    echo ""
    echo "  # Bulk clone all repositories (if you have a list)"
    echo "  while read repo; do"
    echo "    git clone https://github.com/rgt47/\$repo.git ~/recovered/\$repo"
    echo "  done < repository_names.txt"
    echo ""
    echo "  # Find and clone repositories from GitHub API"
    echo "  curl -s 'https://api.github.com/users/rgt47/repos?per_page=100' | \\"
    echo "    jq -r '.[] | select(.name | contains(\"project\")) | .clone_url' | \\"
    echo "    while read url; do git clone \$url ~/recovered/; done"
    echo ""
    echo "From Time Machine (system-wide recovery):"
    echo "  1. Open Time Machine app"
    echo "  2. Navigate to ~/prj directory"  
    echo "  3. Select desired backup date"
    echo "  4. Click 'Restore' for files/folders"
    echo ""
    echo "Command line Time Machine recovery:"
    echo "  tmutil listbackups  # List available backups"
    echo "  sudo tmutil restore /path/to/backup/prj ~/prj_recovered"
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

## Part 8: Performance Optimization

For a 20GB directory with 300 subdirectories, performance matters:

### Optimized rsync Settings

```bash
# For large directory structures
rsync -av --delete \
    --partial-dir=/tmp/rsync-partial \
    --inplace \
    --compress-level=1 \
    --itemize-changes \
    "$SOURCE/" "$DEST/"
```

### rclone Configuration

```ini
# ~/.config/rclone/rclone.conf
[googledrive]
type = drive
# ... your existing config ...
chunk_size = 64M
upload_cutoff = 64M
```

## Part 9: Weekly Archives

Create compressed archives for long-term storage:

```bash
#!/bin/bash
# ~/Scripts/weekly_archive.sh

ARCHIVE_DIR="/Volumes/PrjArchive/weekly"
TIMESTAMP=$(date "+%Y-%m-%d")
archive_file="$ARCHIVE_DIR/prj_weekly_$TIMESTAMP.tar.gz"

# Create compressed archive
tar -czf "$archive_file" -C "$HOME" prj/

# Clean up old archives (keep 8 weeks)
find "$ARCHIVE_DIR" -name "prj_weekly_*.tar.gz" -mtime +56 -delete

# Monthly archive (first Sunday of month)
if [ $(date +%d) -le 7 ]; then
    monthly_file="/Volumes/PrjArchive/monthly/prj_monthly_$(date +%Y-%m).tar.gz"
    cp "$archive_file" "$monthly_file"
fi
```

Schedule weekly:

```bash
(crontab -l 2>/dev/null; echo "0 2 * * 0 $HOME/Scripts/weekly_archive.sh") | crontab -
```

## Quick Reference

### Daily Commands

```bash
# System status
~/Scripts/backup_status.sh

# Multi-repository dashboard
~/Scripts/git_dashboard.sh

# Repository health check
~/Scripts/repo_health_check.sh

# Manual backup
~/Scripts/prj_backup.sh

# Bulk Git operations
~/Scripts/bulk_git_ops.sh sync    # Commit and push all repos
~/Scripts/bulk_git_ops.sh status  # Check status of all repos
~/Scripts/bulk_git_ops.sh pull    # Pull updates for all repos
```

### Vim Commands

Within vim, while editing files in `~/prj`:

```vim
:BackupStatus    " Check system status
:GitDashboard    " Multi-repository overview
:RepoHealth      " Repository health check
:BackupNow       " Run manual backup
:GitSyncAll      " Sync all repositories
:GitSync         " Sync current repository

<leader>bs       " Quick status
<leader>gd       " Git dashboard
<leader>ga       " Git sync all
<leader>gs       " Git sync current
```

### Backup Schedule Summary

| Frequency | Action | Storage |
|-----------|--------|---------|
| Hourly | Time Machine (system), Local snapshots, Cloud sync | Grey drive, Google Drive |
| Daily | Multi-repo Git sync (commit + push all 300 repos) | GitHub (individual repos) |
| Weekly | Compressed archives, iCloud | Blue drive, iCloud |
| Monthly | Long-term archives | Blue drive |

## Conclusion

This comprehensive backup system provides multiple layers of protection for large research projects with individual Git repositories per project. The combination of local snapshots, mirrored drives, individual version control per project, and cloud storage ensures your data is safe from hardware failure, accidental deletion, ransomware, and other disasters.

Key benefits:

- **Project-specific version control**: Each of your 300 projects maintains its own Git history, issues, and collaboration space
- **Automated**: Runs without manual intervention across all repositories
- **Scalable**: Handles large directory structures with hundreds of individual repos efficiently  
- **Granular recovery**: Restore individual projects or the entire collection
- **Integrated**: Works seamlessly with vim workflow and individual project development
- **Monitored**: Easy status checking across all repositories with health verification

The multi-repository approach is particularly powerful for research because:

1. **Isolation**: Issues in one project don't affect others
2. **Collaboration**: Each project can have different collaborators and access levels
3. **History**: Detailed commit history per project for publication and reproducibility
4. **Flexibility**: Different projects can use different branching strategies or release cycles
5. **Discoverability**: Individual repos are easier to find and share with colleagues

The system follows industry best practices while being tailored for academic research workflows. With proper setup, you can focus on your research knowing your data is comprehensively protected.

::: {.callout-tip}
## Implementation Tips

1. Start with the basic scripts and test thoroughly before adding automation
2. Monitor backup logs regularly for the first few weeks
3. Test recovery procedures before you need them
4. Adjust schedules based on your actual usage patterns
5. Keep the quick reference handy for daily operations
:::

---

*This system has been tested with macOS and should work with minor modifications on other Unix-like systems. Always test backup and recovery procedures in a safe environment before relying on them for critical data.*

## Appendix: Complete Script Collection {.appendix}

This appendix contains the five core scripts that power the backup system. Save these to `~/Scripts/` and make them executable with `chmod +x`.

### A.1 Repository Discovery Script

```{.bash filename="~/Scripts/discover_repos.sh"}
#!/bin/bash
# Repository Discovery Script
# Finds all Git repositories in ~/prj and creates a management list

PRJ_DIR="$HOME/prj"
REPO_LIST="$HOME/Scripts/repo_list.txt"

echo "Discovering Git repositories in $PRJ_DIR..."

# Find all .git directories and extract project paths
find "$PRJ_DIR" -name ".git" -type d | while read git_dir; do
    project_dir=$(dirname "$git_dir")
    project_name=$(basename "$project_dir")
    
    # Get remote origin URL if it exists
    cd "$project_dir"
    remote_url=$(git remote get-url origin 2>/dev/null || echo "NO_REMOTE")
    
    echo "$project_name|$project_dir|$remote_url"
done > "$REPO_LIST"

repo_count=$(wc -l < "$REPO_LIST")
echo "Found $repo_count Git repositories"
echo "Repository list saved to $REPO_LIST"

# Create a summary report
echo ""
echo "Repository Summary:"
echo "==================="

remote_count=0
no_remote_count=0

while IFS='|' read -r project_name project_dir remote_url; do
    if [ "$remote_url" = "NO_REMOTE" ]; then
        no_remote_count=$((no_remote_count + 1))
    else
        remote_count=$((remote_count + 1))
    fi
done < "$REPO_LIST"

echo "Repositories with remotes: $remote_count"
echo "Repositories without remotes: $no_remote_count"
echo "Total repositories: $repo_count"
```

### A.2 Bulk Git Operations Script

```{.bash filename="~/Scripts/bulk_git_ops.sh"}
#!/bin/bash
# Bulk Git Operations Script
# Performs git operations across all discovered repositories

REPO_LIST="$HOME/Scripts/repo_list.txt"
LOG_FILE="$HOME/Scripts/git_bulk.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

if [ ! -f "$REPO_LIST" ]; then
    echo "Repository list not found. Run discover_repos.sh first."
    exit 1
fi

operation="$1"
if [ -z "$operation" ]; then
    echo "Usage: $0 [status|pull|push|commit|sync|summary]"
    echo ""
    echo "Operations:"
    echo "  status  - Show git status for all repos"
    echo "  pull    - Pull latest changes from all remotes"
    echo "  push    - Push commits to all remotes"
    echo "  commit  - Commit changes in all repos"
    echo "  sync    - Full sync (commit + push)"
    echo "  summary - Quick summary of repository states"
    exit 1
fi

echo "[$TIMESTAMP] Starting bulk $operation operation" >> "$LOG_FILE"

success_count=0
error_count=0
total_repos=0

while IFS='|' read -r project_name project_dir remote_url; do
    if [ ! -d "$project_dir" ]; then
        continue
    fi
    
    cd "$project_dir"
    total_repos=$((total_repos + 1))
    
    case "$operation" in
        "status")
            echo "=== $project_name ==="
            git_status=$(git status --porcelain 2>/dev/null)
            if [ -n "$git_status" ]; then
                echo "Changes found:"
                echo "$git_status"
            else
                echo "Clean"
            fi
            echo ""
            ;;
        "summary")
            status_output=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
            if [ "$status_output" -gt 0 ]; then
                echo "🔄 $project_name: $status_output changes"
            fi
            ;;
        "pull")
            if [ "$remote_url" != "NO_REMOTE" ]; then
                echo "Pulling $project_name..."
                if git pull origin main >> "$LOG_FILE" 2>&1 || \
                   git pull origin master >> "$LOG_FILE" 2>&1; then
                    success_count=$((success_count + 1))
                else
                    echo "❌ Pull failed for $project_name"
                    error_count=$((error_count + 1))
                fi
            fi
            ;;
        "push")
            if [ "$remote_url" != "NO_REMOTE" ]; then
                echo "Pushing $project_name..."
                if git push origin main >> "$LOG_FILE" 2>&1 || \
                   git push origin master >> "$LOG_FILE" 2>&1; then
                    success_count=$((success_count + 1))
                else
                    echo "❌ Push failed for $project_name"
                    error_count=$((error_count + 1))
                fi
            fi
            ;;
        "commit")
            if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
                echo "Committing changes in $project_name..."
                git add . >> "$LOG_FILE" 2>&1
                if git commit -m "Automated backup: $TIMESTAMP" >> "$LOG_FILE" 2>&1; then
                    echo "[$TIMESTAMP] $project_name: committed changes" >> "$LOG_FILE"
                    success_count=$((success_count + 1))
                else
                    error_count=$((error_count + 1))
                fi
            fi
            ;;
        "sync")
            echo "Syncing $project_name..."
            has_changes=false
            
            # Commit if there are changes
            if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
                git add . >> "$LOG_FILE" 2>&1
                if git commit -m "Automated sync: $TIMESTAMP" >> "$LOG_FILE" 2>&1; then
                    has_changes=true
                else
                    echo "❌ Commit failed for $project_name"
                    error_count=$((error_count + 1))
                    continue
                fi
            fi
            
            # Push if remote exists and we have commits to push
            if [ "$remote_url" != "NO_REMOTE" ]; then
                if git push origin main >> "$LOG_FILE" 2>&1 || \
                   git push origin master >> "$LOG_FILE" 2>&1; then
                    success_count=$((success_count + 1))
                else
                    echo "❌ Push failed for $project_name"
                    error_count=$((error_count + 1))
                fi
            elif [ "$has_changes" = true ]; then
                echo "⚠️  $project_name: Committed locally but no remote configured"
                success_count=$((success_count + 1))
            fi
            ;;
    esac
done < "$REPO_LIST"

if [ "$operation" != "status" ] && [ "$operation" != "summary" ]; then
    echo ""
    echo "Operation completed:"
    echo "  Processed: $total_repos repositories"
    echo "  Successful: $success_count"
    echo "  Errors: $error_count"
fi

echo "[$TIMESTAMP] Bulk $operation completed - $success_count success, $error_count errors" >> "$LOG_FILE"
```

### A.3 Multi-Repository Dashboard Script

```{.bash filename="~/Scripts/git_dashboard.sh"}
#!/bin/bash
# Multi-Repository Dashboard Script
# Provides overview of all repository states

REPO_LIST="$HOME/Scripts/repo_list.txt"

if [ ! -f "$REPO_LIST" ]; then
    echo "❌ Repository list not found"
    echo "Run discover_repos.sh first to generate repository list"
    exit 1
fi

echo "=== MULTI-REPOSITORY STATUS DASHBOARD ==="
echo "Date: $(date)"
echo "Generated from: $REPO_LIST"
echo ""

# Initialize counters
uncommitted_count=0
unpushed_count=0
no_remote_count=0
error_count=0
total_repos=0
clean_count=0

# Arrays to store repository names by status
uncommitted_repos=()
unpushed_repos=()
error_repos=()
old_repos=()

echo "Analyzing repositories..."
echo "========================"

while IFS='|' read -r project_name project_dir remote_url; do
    if [ ! -d "$project_dir" ]; then
        echo "❌ $project_name: Directory not found"
        error_count=$((error_count + 1))
        error_repos+=("$project_name (missing directory)")
        continue
    fi
    
    cd "$project_dir"
    total_repos=$((total_repos + 1))
    
    # Check if git repo is healthy
    if ! git status >/dev/null 2>&1; then
        echo "❌ $project_name: Git repository corrupted"
        error_count=$((error_count + 1))
        error_repos+=("$project_name (corrupted)")
        continue
    fi
    
    # Check for uncommitted changes
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        uncommitted_count=$((uncommitted_count + 1))
        change_count=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        echo "🔄 $project_name: $change_count uncommitted changes"
        uncommitted_repos+=("$project_name ($change_count changes)")
    fi
    
    # Check for unpushed commits (if remote exists)
    if [ "$remote_url" != "NO_REMOTE" ]; then
        # Fetch quietly to get latest remote state
        git fetch origin >/dev/null 2>&1
        
        # Check if ahead of remote
        ahead=$(git rev-list --count HEAD ^origin/main 2>/dev/null || \
                git rev-list --count HEAD ^origin/master 2>/dev/null || echo "0")
        
        if [ "$ahead" -gt 0 ]; then
            unpushed_count=$((unpushed_count + 1))
            echo "📤 $project_name: $ahead commits ahead of remote"
            unpushed_repos+=("$project_name ($ahead commits)")
        fi
        
        # Check for very old repositories (no commits in 6+ months)
        last_commit_date=$(git log -1 --format="%ct" 2>/dev/null)
    if [ -n "$last_commit_date" ]; then
        days_old=$(( ($(date +%s) - last_commit_date) / 86400 ))
        if [ "$days_old" -gt 365 ]; then
            echo "📅 $project_name: Last commit $days_old days ago (consider archiving)" | tee -a "$LOG_FILE"
            issues=$((issues + 1))
        fi
    fi
    
    # Check 8: Git configuration
    if [ -z "$(git config user.name)" ] || [ -z "$(git config user.email)" ]; then
        echo "⚠️  $project_name: Git user not configured" | tee -a "$LOG_FILE"
        issues=$((issues + 1))
    fi
    
    # Classify repository health
    if [ "$issues" -eq 0 ]; then
        healthy_repos=$((healthy_repos + 1))
        echo "✅ $project_name: Healthy" | tee -a "$LOG_FILE"
    elif [ "$issues" -le 2 ]; then
        warning_repos=$((warning_repos + 1))
        echo "⚠️  $project_name: $issues minor issues" | tee -a "$LOG_FILE"
    else
        critical_repos=$((critical_repos + 1))
        echo "❌ $project_name: $issues issues - needs attention" | tee -a "$LOG_FILE"
    fi
    
    return 0
}

# Process all repositories
echo "Checking repository health..."
echo "=============================="

while IFS='|' read -r project_name project_dir remote_url; do
    check_repository_health "$project_name" "$project_dir" "$remote_url"
done < "$REPO_LIST"

echo ""
echo "=== HEALTH CHECK SUMMARY ===" | tee -a "$LOG_FILE"
echo "Total repositories checked: $total_repos" | tee -a "$LOG_FILE"
echo "Healthy repositories: $healthy_repos" | tee -a "$LOG_FILE"
echo "Repositories with warnings: $warning_repos" | tee -a "$LOG_FILE"
echo "Repositories needing attention: $critical_repos" | tee -a "$LOG_FILE"

# Calculate health percentage
if [ "$total_repos" -gt 0 ]; then
    health_percentage=$(( (healthy_repos * 100) / total_repos ))
    echo "Overall health: ${health_percentage}%" | tee -a "$LOG_FILE"
fi

# Show detailed issue summaries
if [ "${#connectivity_issues[@]}" -gt 0 ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "=== CONNECTIVITY ISSUES ===" | tee -a "$LOG_FILE"
    printf '%s\n' "${connectivity_issues[@]}" | tee -a "$LOG_FILE"
fi

if [ "${#corruption_issues[@]}" -gt 0 ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "=== CORRUPTION ISSUES (CRITICAL) ===" | tee -a "$LOG_FILE"
    printf '%s\n' "${corruption_issues[@]}" | tee -a "$LOG_FILE"
fi

if [ "${#size_issues[@]}" -gt 0 ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "=== LARGE REPOSITORIES ===" | tee -a "$LOG_FILE"
    printf '%s\n' "${size_issues[@]}" | tee -a "$LOG_FILE"
fi

if [ "${#permission_issues[@]}" -gt 0 ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "=== PERMISSION ISSUES ===" | tee -a "$LOG_FILE"
    printf '%s\n' "${permission_issues[@]}" | tee -a "$LOG_FILE"
fi

if [ "${#sync_issues[@]}" -gt 0 ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "=== SYNC ISSUES ===" | tee -a "$LOG_FILE"
    printf '%s\n' "${sync_issues[@]}" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "=== RECOMMENDATIONS ===" | tee -a "$LOG_FILE"

if [ "$critical_repos" -gt 0 ]; then
    echo "🚨 CRITICAL: $critical_repos repositories need immediate attention" | tee -a "$LOG_FILE"
    echo "   - Fix corrupted repositories first" | tee -a "$LOG_FILE"
    echo "   - Check file permissions" | tee -a "$LOG_FILE"
fi

if [ "${#sync_issues[@]}" -gt 0 ]; then
    echo "🔄 Run 'bulk_git_ops.sh sync' to resolve sync issues" | tee -a "$LOG_FILE"
fi

if [ "${#connectivity_issues[@]}" -gt 0 ]; then
    echo "🌐 Check network connectivity and remote URLs" | tee -a "$LOG_FILE"
fi

if [ "${#size_issues[@]}" -gt 0 ]; then
    echo "💾 Consider using Git LFS for large files" | tee -a "$LOG_FILE"
fi

if [ "$health_percentage" -lt 80 ]; then
    echo "⚠️  Overall repository health is below 80% - maintenance recommended" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "[$TIMESTAMP] Health check completed" | tee -a "$LOG_FILE"
```

### A.5 Comprehensive Backup Status Script

```{.bash filename="~/Scripts/backup_status.sh"}
#!/bin/bash
# Comprehensive Backup Status Script
# Shows status of all backup components

echo "=== PROJECT BACKUP SYSTEM STATUS ==="
echo "Date: $(date)"
echo "System: $(uname -s) $(uname -r)"
echo ""

# Function to format file sizes
format_size() {
    local size="$1"
    if [ -n "$size" ]; then
        echo "$size"
    else
        echo "Unknown"
    fi
}

# Function to check service status
check_service_status() {
    local service_name="$1"
    local check_command="$2"
    
    if eval "$check_command" >/dev/null 2>&1; then
        echo "✅ $service_name: Active"
        return 0
    else
        echo "❌ $service_name: Inactive"
        return 1
    fi
}

# Project directory overview
echo "=== PROJECT DIRECTORY OVERVIEW ==="
if [ -d "$HOME/prj" ]; then
    project_size=$(du -sh "$HOME/prj" 2>/dev/null | cut -f1)
    dir_count=$(find "$HOME/prj" -type d 2>/dev/null | wc -l | tr -d ' ')
    file_count=$(find "$HOME/prj" -type f 2>/dev/null | wc -l | tr -d ' ')
    
    echo "📁 Location: $HOME/prj"
    echo "📊 Size: $(format_size "$project_size")"
    echo "📂 Subdirectories: $dir_count"
    echo "📄 Files: $file_count"
    
    # Find most recently modified file
    recent_file=$(find "$HOME/prj" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
    if [ -n "$recent_file" ]; then
        recent_date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$recent_file" 2>/dev/null)
        echo "🕒 Last modified: $recent_date"
        echo "📝 Recent file: $(basename "$recent_file")"
    fi
else
    echo "❌ ERROR: Project directory not found at $HOME/prj"
fi
echo ""

# Time Machine status
echo "=== TIME MACHINE STATUS ==="
tm_status=$(tmutil status 2>/dev/null)
if [ $? -eq 0 ]; then
    running=$(echo "$tm_status" | grep "Running" | cut -d'=' -f2 | tr -d ' ;')
    if [ "$running" = "1" ]; then
        echo "🔄 Time Machine: Currently backing up"
        progress=$(echo "$tm_status" | grep "Progress" | cut -d'=' -f2 | tr -d ' ;')
        if [ -n "$progress" ]; then
            echo "   Progress: ${progress}%"
        fi
    else
        echo "✅ Time Machine: Ready"
    fi
    
    # Last backup date
    last_backup=$(tmutil latestbackup 2>/dev/null)
    if [ -n "$last_backup" ]; then
        backup_date=$(basename "$last_backup")
        echo "📅 Last backup: $backup_date"
    fi
    
    # Backup destination
    dest=$(tmutil destinationinfo 2>/dev/null | grep "Name" | head -1 | cut -d':' -f2 | tr -d ' ')
    if [ -n "$dest" ]; then
        echo "💾 Destination: $dest"
    fi
else
    echo "❌ Time Machine: Not configured or accessible"
fi
echo ""

# USB drive status
echo "=== USB DRIVE STATUS ==="
usb_found=false

for mount_point in /Volumes/*; do
    if [ -d "$mount_point" ]; then
        volume_name=$(basename "$mount_point")
        case "$volume_name" in
            "TimeMachine"|"PrjSnapshots"|"PrjMirror"|"PrjArchive")
                usb_found=true
                usage_info=$(df -h "$mount_point" 2>/dev/null | tail -1)
                if [ -n "$usage_info" ]; then
                    size=$(echo "$usage_info" | awk '{print $2}')
                    used=$(echo "$usage_info" | awk '{print $3}')
                    avail=$(echo "$usage_info" | awk '{print $4}')
                    percent=$(echo "$usage_info" | awk '{print $5}')
                    
                    echo "💿 $volume_name: $used/$size used ($percent), $avail available"
                    
                    # Warning for high usage
                    usage_num=$(echo "$percent" | tr -d '%')
                    if [ "$usage_num" -gt 90 ]; then
                        echo "   ⚠️  WARNING: Drive almost full!"
                    fi
                else
                    echo "💿 $volume_name: Mounted (size unknown)"
                fi
                ;;
        esac
    fi
done

if [ "$usb_found" = false ]; then
    echo "❌ No backup USB drives found"
    echo "   Expected: TimeMachine, PrjSnapshots, PrjMirror, PrjArchive"
fi
echo ""

# Recent snapshots status
echo "=== BACKUP SNAPSHOTS ==="
if [ -d "/Volumes/PrjSnapshots" ]; then
    snapshot_count=$(ls /Volumes/PrjSnapshots/snapshot_* 2>/dev/null | wc -l | tr -d ' ')
    echo "📸 Total snapshots: $snapshot_count"
    
    if [ "$snapshot_count" -gt 0 ]; then
        echo "📸 Recent snapshots:"
        ls -lt /Volumes/PrjSnapshots/snapshot_* 2>/dev/null | head -3 | while read line; do
            dir_name=$(echo "$line" | awk '{print $9}')
            if [ -n "$dir_name" ] && [ -d "$dir_name" ]; then
                timestamp=$(basename "$dir_name" | sed 's/snapshot_//')
                size=$(du -sh "$dir_name" 2>/dev/null | cut -f1)
                echo "   $timestamp: $(format_size "$size")"
            fi
        done
    fi
else
    echo "❌ Snapshots directory not available"
fi
echo ""

# Blue drive mirror status
echo "=== MIRROR BACKUP STATUS ==="
if [ -d "/Volumes/PrjMirror/current" ]; then
    mirror_size=$(du -sh "/Volumes/PrjMirror/current" 2>/dev/null | cut -f1)
    echo "🪞 Mirror size: $(format_size "$mirror_size")"
    
    if [ -f "/Volumes/PrjMirror/current/.last_backup" ]; then
        last_mirror=$(cat "/Volumes/PrjMirror/current/.last_backup")
        echo "🕒 Last mirror update: $last_mirror"
        
        # Check if mirror is recent (within last 2 hours)
        if [ -n "$last_mirror" ]; then
            last_timestamp=$(date -j -f "%Y-%m-%d_%H-%M-%S" "$last_mirror" "+%s" 2>/dev/null)
            current_timestamp=$(date "+%s")
            if [ -n "$last_timestamp" ]; then
                hours_old=$(( (current_timestamp - last_timestamp) / 3600 ))
                if [ "$hours_old" -gt 2 ]; then
                    echo "   ⚠️  Mirror is $hours_old hours old"
                fi
            fi
        fi
    else
        echo "❌ No mirror timestamp found"
    fi
else
    echo "❌ Mirror backup not available"
fi
echo ""

# Weekly archives status
echo "=== ARCHIVE STATUS ==="
if [ -d "/Volumes/PrjArchive/weekly" ]; then
    archive_count=$(ls /Volumes/PrjArchive/weekly/prj_weekly_*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
    echo "📦 Weekly archives: $archive_count"
    
    if [ "$archive_count" -gt 0 ]; then
        echo "📦 Recent archives:"
        ls -lt /Volumes/PrjArchive/weekly/prj_weekly_*.tar.gz 2>/dev/null | head -3 | while read line; do
            file_name=$(echo "$line" | awk '{print $9}')
            if [ -n "$file_name" ]; then
                date_part=$(basename "$file_name" | sed 's/prj_weekly_//' | sed 's/.tar.gz//')
                size=$(echo "$line" | awk '{print $5}')
                size_formatted=$(numfmt --to=iec "$size" 2>/dev/null || echo "$size bytes")
                echo "   $date_part: $size_formatted"
            fi
        done
    fi
    
    # Monthly archives
    if [ -d "/Volumes/PrjArchive/monthly" ]; then
        monthly_count=$(ls /Volumes/PrjArchive/monthly/prj_monthly_*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
        echo "📦 Monthly archives: $monthly_count"
    fi
else
    echo "❌ Archive directory not available"
fi
echo ""

# Multi-repository Git status
echo "=== MULTI-REPOSITORY GIT STATUS ==="
if [ -f "$HOME/Scripts/repo_list.txt" ]; then
    total_repos=$(wc -l < "$HOME/Scripts/repo_list.txt")
    echo "📚 Total repositories: $total_repos"
    
    # Quick status check
    uncommitted=0
    unpushed=0
    errors=0
    
    while IFS='|' read -r project_name project_dir remote_url; do
        if [ -d "$project_dir" ]; then
            cd "$project_dir"
            
            # Check for uncommitted changes
            if ! git status >/dev/null 2>&1; then
                errors=$((errors + 1))
            elif [ -n "$(git status --porcelain 2>/dev/null)" ]; then
                uncommitted=$((uncommitted + 1))
            fi
            
            # Check for unpushed commits
            if [ "$remote_url" != "NO_REMOTE" ]; then
                git fetch origin >/dev/null 2>&1
                ahead=$(git rev-list --count HEAD ^origin/main 2>/dev/null || \
                       git rev-list --count HEAD ^origin/master 2>/dev/null || echo "0")
                if [ "$ahead" -gt 0 ]; then
                    unpushed=$((unpushed + 1))
                fi
            fi
        fi
    done < "$HOME/Scripts/repo_list.txt"
    
    echo "🔄 With uncommitted changes: $uncommitted"
    echo "📤 With unpushed commits: $unpushed"
    echo "❌ With errors: $errors"
    echo "✅ Clean repositories: $((total_repos - uncommitted - unpushed - errors))"
    
    if [ "$uncommitted" -gt 0 ] || [ "$unpushed" -gt 0 ]; then
        echo "   💡 Run 'git_dashboard.sh' for detailed status"
    fi
else
    echo "❌ Repository list not found"
    echo "   💡 Run 'discover_repos.sh' to scan for repositories"
fi
echo ""

# Cloud backup status
echo "=== CLOUD BACKUP STATUS ==="

# Check rclone and Google Drive
if command -v rclone >/dev/null 2>&1; then
    echo "☁️  rclone: Available"
    
    if timeout 10 rclone lsd googledrive: >/dev/null 2>&1; then
        echo "☁️  Google Drive: Connected"
        cloud_size=$(timeout 30 rclone size googledrive:prj/ 2>/dev/null | grep "Total size:" | awk '{print $3, $4}')
        if [ -n "$cloud_size" ]; then
            echo "   📊 Cloud backup size: $cloud_size"
        fi
        
        # Check last sync
        if [ -f "$HOME/Scripts/backup.log" ]; then
            last_cloud=$(grep "Cloud backup completed successfully" "$HOME/Scripts/backup.log" | tail -1 | cut -d']' -f1 | tr -d '[')
            if [ -n "$last_cloud" ]; then
                echo "   🕒 Last sync: $last_cloud"
            fi
        fi
    else
        echo "❌ Google Drive: Connection failed"
    fi
else
    echo "❌ rclone: Not available"
fi

# Check iCloud
icloud_dir="$HOME/Library/Mobile Documents/com~apple~CloudDocs/prj_backup"
if [ -d "$icloud_dir" ]; then
    icloud_size=$(du -sh "$icloud_dir" 2>/dev/null | cut -f1)
    echo "☁️  iCloud: Available ($(format_size "$icloud_size"))"
else
    echo "❌ iCloud: Not configured"
fi
echo ""

# System services status
echo "=== SYSTEM SERVICES ==="
check_service_status "Backup Launch Agent" "launchctl list | grep com.user.prj.backup"
check_service_status "Cron Jobs" "crontab -l 2>/dev/null | grep -v '^#'"

# Check script permissions
echo ""
echo "=== SCRIPT STATUS ==="
script_dir="$HOME/Scripts"
if [ -d "$script_dir" ]; then
    echo "📁 Scripts directory: Available"
    
    required_scripts=("prj_backup.sh" "discover_repos.sh" "bulk_git_ops.sh" "git_dashboard.sh" "repo_health_check.sh")
    for script in "${required_scripts[@]}"; do
        script_path="$script_dir/$script"
        if [ -f "$script_path" ]; then
            if [ -x "$script_path" ]; then
                echo "✅ $script: Available and executable"
            else
                echo "⚠️  $script: Available but not executable"
            fi
        else
            echo "❌ $script: Missing"
        fi
    done
else
    echo "❌ Scripts directory not found"
fi
echo ""

# Recent backup activity
echo "=== RECENT BACKUP ACTIVITY ==="
if [ -f "$HOME/Scripts/backup.log" ]; then
    echo "📋 Last 5 backup events:"
    tail -5 "$HOME/Scripts/backup.log" | while read line; do
        echo "   $line"
    done
    
    # Check for recent errors
    recent_errors=$(grep "ERROR" "$HOME/Scripts/backup.log" | tail -3)
    if [ -n "$recent_errors" ]; then
        echo ""
        echo "⚠️  Recent errors:"
        echo "$recent_errors" | while read line; do
            echo "   $line"
        done
    fi
else
    echo "❌ No backup log found"
fi
echo ""

# Disk space warnings
echo "=== DISK SPACE ANALYSIS ==="
echo "💾 Disk usage:"
df -h | grep -E "(^/dev|TimeMachine|PrjSnapshots|PrjMirror|PrjArchive)" | while read line; do
    filesystem=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    used=$(echo "$line" | awk '{print $3}')
    percent=$(echo "$line" | awk '{print $5}' | tr -d '%')
    mount=$(echo "$line" | awk '{print $6}')
    
    if [ "$percent" -gt 90 ]; then
        echo "🚨 $mount: ${percent}% full ($used/$size) - CRITICAL"
    elif [ "$percent" -gt 80 ]; then
        echo "⚠️  $mount: ${percent}% full ($used/$size) - WARNING"
    else
        echo "✅ $mount: ${percent}% full ($used/$size)"
    fi
done

echo ""
echo "=== OVERALL SYSTEM HEALTH ==="

# Calculate overall health score
health_factors=0
health_score=0

# Time Machine (20 points)
if tmutil status >/dev/null 2>&1; then
    health_score=$((health_score + 20))
fi
health_factors=$((health_factors + 20))

# USB drives (20 points)
if [ -d "/Volumes/PrjSnapshots" ] && [ -d "/Volumes/PrjMirror" ]; then
    health_score=$((health_score + 20))
fi
health_factors=$((health_factors + 20))

# Recent backups (20 points)
if [ -f "/Volumes/PrjMirror/current/.last_backup" ]; then
    health_score=$((health_score + 20))
fi
health_factors=$((health_factors + 20))

# Git repositories (20 points)
if [ -f "$HOME/Scripts/repo_list.txt" ] && [ "$errors" -eq 0 ]; then
    health_score=$((health_score + 20))
fi
health_factors=$((health_factors + 20))

# Cloud backup (20 points)
if command -v rclone >/dev/null 2>&1 && timeout 5 rclone lsd googledrive: >/dev/null 2>&1; then
    health_score=$((health_score + 20))
fi
health_factors=$((health_factors + 20))

health_percentage=$((health_score * 100 / health_factors))

echo "🏥 Overall Health Score: ${health_percentage}%"

if [ "$health_percentage" -ge 90 ]; then
    echo "🎉 Excellent - All backup systems are functioning optimally!"
elif [ "$health_percentage" -ge 75 ]; then
    echo "✅ Good - Minor issues that don't affect data protection"
elif [ "$health_percentage" -ge 60 ]; then
    echo "⚠️  Fair - Some backup components need attention"
elif [ "$health_percentage" -ge 40 ]; then
    echo "🔧 Poor - Multiple backup systems are compromised"
else
    echo "🚨 Critical - Backup system requires immediate attention"
fi

echo ""
echo "💡 Quick Actions:"
echo "   • Full dashboard: git_dashboard.sh"
echo "   • Health check: repo_health_check.sh  "
echo "   • Manual backup: prj_backup.sh"
echo "   • Recovery help: recovery_helper.sh"
```

---

*These scripts provide comprehensive automation and monitoring for your research backup system. Make sure to customize paths and repository URLs for your specific setup.*>/dev/null)
        if [ -n "$last_commit_date" ]; then
            days_old=$(( ($(date +%s) - last_commit_date) / 86400 ))
            if [ "$days_old" -gt 180 ]; then
                echo "📅 $project_name: Last commit $days_old days ago"
                old_repos+=("$project_name ($days_old days)")
            fi
        fi
    else
        no_remote_count=$((no_remote_count + 1))
        echo "🔗 $project_name: No remote configured"
    fi
    
    # Count clean repositories
    if [ -z "$(git status --porcelain 2>/dev/null)" ] && [ "$ahead" = "0" ] 2>/dev/null; then
        clean_count=$((clean_count + 1))
    fi
done < "$REPO_LIST"

echo ""
echo "=== SUMMARY STATISTICS ==="
echo "Total repositories: $total_repos"
echo "Clean repositories: $clean_count"
echo "With uncommitted changes: $uncommitted_count"
echo "With unpushed commits: $unpushed_count"
echo "Without remote: $no_remote_count"
echo "With errors: $error_count"
echo "Old repositories (6+ months): ${#old_repos[@]}"

# Show detailed lists if there are issues
if [ "$uncommitted_count" -gt 0 ]; then
    echo ""
    echo "=== REPOSITORIES WITH UNCOMMITTED CHANGES ==="
    printf '%s\n' "${uncommitted_repos[@]}"
fi

if [ "$unpushed_count" -gt 0 ]; then
    echo ""
    echo "=== REPOSITORIES WITH UNPUSHED COMMITS ==="
    printf '%s\n' "${unpushed_repos[@]}"
fi

if [ "$error_count" -gt 0 ]; then
    echo ""
    echo "=== REPOSITORIES WITH ERRORS ==="
    printf '%s\n' "${error_repos[@]}"
fi

if [ "${#old_repos[@]}" -gt 0 ]; then
    echo ""
    echo "=== OLD REPOSITORIES (Consider archiving) ==="
    printf '%s\n' "${old_repos[@]}"
fi

echo ""
echo "=== RECOMMENDED ACTIONS ==="
if [ "$uncommitted_count" -gt 0 ] || [ "$unpushed_count" -gt 0 ]; then
    echo "🔄 Run 'bulk_git_ops.sh sync' to commit and push changes"
fi

if [ "$error_count" -gt 0 ]; then
    echo "🔧 Run 'repo_health_check.sh' for detailed error analysis"
fi

if [ "$no_remote_count" -gt 0 ]; then
    echo "🔗 Consider adding remotes for local-only repositories"
fi

# Overall health score
health_score=$(( (clean_count * 100) / total_repos ))
echo ""
echo "=== OVERALL HEALTH SCORE: ${health_score}% ==="

if [ "$health_score" -ge 90 ]; then
    echo "✅ Excellent - Your repositories are well maintained!"
elif [ "$health_score" -ge 75 ]; then
    echo "✅ Good - Minor maintenance recommended"
elif [ "$health_score" -ge 60 ]; then
    echo "⚠️  Fair - Some attention needed"
else
    echo "❌ Poor - Immediate attention required"
fi
```

### A.4 Repository Health Check Script

```{.bash filename="~/Scripts/repo_health_check.sh"}
#!/bin/bash
# Repository Health Check Script
# Performs deep health analysis of all repositories

REPO_LIST="$HOME/Scripts/repo_list.txt"
LOG_FILE="$HOME/Scripts/health_check.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

if [ ! -f "$REPO_LIST" ]; then
    echo "❌ Repository list not found"
    echo "Run discover_repos.sh first to generate repository list"
    exit 1
fi

echo "=== REPOSITORY HEALTH CHECK ===" | tee -a "$LOG_FILE"
echo "[$TIMESTAMP] Starting comprehensive health check" | tee -a "$LOG_FILE"
echo ""

# Health check counters
healthy_repos=0
warning_repos=0
critical_repos=0
total_repos=0

# Issue tracking arrays
connectivity_issues=()
corruption_issues=()
size_issues=()
permission_issues=()
sync_issues=()

check_repository_health() {
    local project_name="$1"
    local project_dir="$2"
    local remote_url="$3"
    local issues=0
    
    total_repos=$((total_repos + 1))
    
    # Check 1: Directory exists and is accessible
    if [ ! -d "$project_dir" ]; then
        echo "❌ $project_name: Directory missing" | tee -a "$LOG_FILE"
        critical_repos=$((critical_repos + 1))
        return 1
    fi
    
    cd "$project_dir"
    
    # Check 2: Git repository integrity
    if ! git status >/dev/null 2>&1; then
        echo "❌ $project_name: Git repository corrupted" | tee -a "$LOG_FILE"
        corruption_issues+=("$project_name")
        critical_repos=$((critical_repos + 1))
        return 1
    fi
    
    # Check 3: File permissions
    if [ ! -w "$project_dir" ]; then
        echo "⚠️  $project_name: Directory not writable" | tee -a "$LOG_FILE"
        permission_issues+=("$project_name")
        issues=$((issues + 1))
    fi
    
    # Check 4: Repository size (flag unusually large repos)
    repo_size_kb=$(du -sk . | cut -f1)
    if [ "$repo_size_kb" -gt 1048576 ]; then  # > 1GB
        size_mb=$((repo_size_kb / 1024))
        echo "⚠️  $project_name: Large repository (${size_mb}MB)" | tee -a "$LOG_FILE"
        size_issues+=("$project_name (${size_mb}MB)")
        issues=$((issues + 1))
    fi
    
    # Check 5: Remote connectivity
    if [ "$remote_url" != "NO_REMOTE" ]; then
        if ! timeout 10 git ls-remote origin >/dev/null 2>&1; then
            echo "⚠️  $project_name: Remote connectivity issues" | tee -a "$LOG_FILE"
            connectivity_issues+=("$project_name")
            issues=$((issues + 1))
        fi
        
        # Check 6: Sync status with remote
        git fetch origin >/dev/null 2>&1
        
        # Check if behind remote
        behind=$(git rev-list --count origin/main..HEAD 2>/dev/null || \
                git rev-list --count origin/master..HEAD 2>/dev/null || echo "0")
        ahead=$(git rev-list --count HEAD..origin/main 2>/dev/null || \
               git rev-list --count HEAD..origin/master 2>/dev/null || echo "0")
        
        if [ "$behind" -gt 0 ]; then
            echo "⚠️  $project_name: $behind commits behind remote" | tee -a "$LOG_FILE"
            sync_issues+=("$project_name ($behind behind)")
            issues=$((issues + 1))
        fi
        
        if [ "$ahead" -gt 0 ]; then
            uncommitted=$(git status --porcelain | wc -l | tr -d ' ')
            if [ "$uncommitted" -gt 0 ]; then
                echo "⚠️  $project_name: $ahead commits ahead + $uncommitted uncommitted" | tee -a "$LOG_FILE"
                sync_issues+=("$project_name ($ahead ahead, $uncommitted uncommitted)")
                issues=$((issues + 1))
            fi
        fi
    fi
    
    # Check 7: Very old repositories
    last_commit_date=$(git log -1 --format="%ct" 2bin/bash
# ~/Scripts/prj_backup.sh

LOG_FILE="$HOME/Scripts/backup.log"
PRJ_DIR="$HOME/prj"
GREY_SNAPSHOTS="/Volumes/PrjSnapshots"
BLUE_MIRROR="/Volumes/PrjMirror/current"
TIMESTAMP=$(date "+%Y-%m-%d_%H-%M-%S")

echo "[$TIMESTAMP] Starting enhanced backup process" >> "$LOG_FILE"

# Function to check disk space
check_disk_space() {
    local target_dir="$1"
    local required_gb="25"  # 20GB + 5GB buffer
    
    if [ -d "$(dirname "$target_dir")" ]; then
        local available_gb=$(df -g "$(dirname "$target_dir")" | tail -1 | awk '{print $4}')
        if [ "$available_gb" -lt "$required_gb" ]; then
            echo "[$TIMESTAMP] WARNING: Low disk space" >> "$LOG_FILE"
            return 1
        fi
    fi
    return 0
}

# Create incremental snapshot on grey drive
create_grey_snapshot() {
    if [ ! -d "/Volumes/PrjSnapshots" ]; then
        echo "[$TIMESTAMP] ERROR: Grey drive not mounted" >> "$LOG_FILE"
        return 1
    fi
    
    local snapshot_dir="/Volumes/PrjSnapshots/snapshot_$TIMESTAMP"
    mkdir -p "$snapshot_dir"
    
    # Use rsync with hard links for space efficiency
    local latest_snapshot=$(ls -1t /Volumes/PrjSnapshots/snapshot_* 2>/dev/null | head -1)
    
    if [ -n "$latest_snapshot" ] && [ -d "$latest_snapshot" ]; then
        # Incremental backup using hard links
        rsync -av --delete --link-dest="$latest_snapshot" "$PRJ_DIR/" "$snapshot_dir/"
    else
        # First backup
        rsync -av --delete "$PRJ_DIR/" "$snapshot_dir/"
    fi
    
    # Clean up old snapshots (keep last 48 hours)
    find /Volumes/PrjSnapshots -name "snapshot_*" -type d -mtime +2 -exec rm -rf {} \;
}

# Update blue drive mirror
update_blue_mirror() {
    if [ ! -d "/Volumes/PrjMirror" ]; then
        echo "[$TIMESTAMP] ERROR: Blue drive not mounted" >> "$LOG_FILE"
        return 1
    fi
    
    check_disk_space "$BLUE_MIRROR" || return 1
    
    # Full mirror sync with progress
    rsync -av --delete --progress --stats "$PRJ_DIR/" "$BLUE_MIRROR/"
    echo "$TIMESTAMP" > "$BLUE_MIRROR/.last_backup"
}

# Cloud backup with optimizations
update_cloud_backup() {
    if ! command -v rclone >/dev/null 2>&1; then
        echo "[$TIMESTAMP] WARNING: rclone not available" >> "$LOG_FILE"
        return 1
    fi
    
    rclone sync "$PRJ_DIR/" googledrive:prj/ \
        --exclude "*.tmp" \
        --exclude "*.DS_Store" \
        --exclude ".git/objects/**" \
        --transfers 4 \
        --checkers 8 \
        --retries 3 \
        --log-file="$LOG_FILE"
}

# Execute all backups
create_grey_snapshot
update_blue_mirror  
update_cloud_backup

echo "[$TIMESTAMP] Backup process completed" >> "$LOG_FILE"
```

## Part 3: Automation with launchd

macOS uses launchd for scheduling. Create a launch agent for hourly backups:

```xml
<!-- ~/Library/LaunchAgents/com.user.prj.backup.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.prj.backup</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/YOURUSERNAME/Scripts/prj_backup.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>LowPriorityIO</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
```

Load and start the service:

```bash
launchctl load ~/Library/LaunchAgents/com.user.prj.backup.plist
launchctl start com.user.prj.backup
```

## Part 4: Multi-Repository Git Management

Having 300 individual GitHub repositories is actually ideal for research projects! Each project maintains its own history, issues, and collaborators. However, this requires a different management strategy.

### Repository Discovery and Management

First, let's create a script to discover and manage all repositories:

```bash
#!/bin/bash
# ~/Scripts/discover_repos.sh

PRJ_DIR="$HOME/prj"
REPO_LIST="$HOME/Scripts/repo_list.txt"

echo "Discovering Git repositories in $PRJ_DIR..."

# Find all .git directories and extract project paths
find "$PRJ_DIR" -name ".git" -type d | while read git_dir; do
    project_dir=$(dirname "$git_dir")
    project_name=$(basename "$project_dir")
    
    # Get remote origin URL if it exists
    cd "$project_dir"
    remote_url=$(git remote get-url origin 2>/dev/null || echo "NO_REMOTE")
    
    echo "$project_name|$project_dir|$remote_url"
done > "$REPO_LIST"

repo_count=$(wc -l < "$REPO_LIST")
echo "Found $repo_count Git repositories"
echo "Repository list saved to $REPO_LIST"
```

### Bulk Git Operations

Create a script to perform operations across all repositories:

```bash
#!/bin/bash
# ~/Scripts/bulk_git_ops.sh

REPO_LIST="$HOME/Scripts/repo_list.txt"
LOG_FILE="$HOME/Scripts/git_bulk.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

if [ ! -f "$REPO_LIST" ]; then
    echo "Repository list not found. Run discover_repos.sh first."
    exit 1
fi

operation="$1"
if [ -z "$operation" ]; then
    echo "Usage: $0 [status|pull|push|commit|sync]"
    exit 1
fi

echo "[$TIMESTAMP] Starting bulk $operation operation" >> "$LOG_FILE"

while IFS='|' read -r project_name project_dir remote_url; do
    if [ ! -d "$project_dir" ]; then
        continue
    fi
    
    cd "$project_dir"
    echo "Processing: $project_name"
    
    case "$operation" in
        "status")
            echo "=== $project_name ===" >> "$LOG_FILE"
            git status --porcelain >> "$LOG_FILE" 2>&1
            ;;
        "pull")
            if [ "$remote_url" != "NO_REMOTE" ]; then
                git pull origin main >> "$LOG_FILE" 2>&1 || \
                git pull origin master >> "$LOG_FILE" 2>&1
            fi
            ;;
        "push")
            if [ "$remote_url" != "NO_REMOTE" ]; then
                git push origin main >> "$LOG_FILE" 2>&1 || \
                git push origin master >> "$LOG_FILE" 2>&1
            fi
            ;;
        "commit")
            if [ -n "$(git status --porcelain)" ]; then
                git add .
                git commit -m "Automated backup: $TIMESTAMP" >> "$LOG_FILE" 2>&1
                echo "[$TIMESTAMP] $project_name: committed changes" >> "$LOG_FILE"
            fi
            ;;
        "sync")
            # Full sync: commit + push
            if [ -n "$(git status --porcelain)" ]; then
                git add .
                git commit -m "Automated sync: $TIMESTAMP" >> "$LOG_FILE" 2>&1
            fi
            if [ "$remote_url" != "NO_REMOTE" ]; then
                git push origin main >> "$LOG_FILE" 2>&1 || \
                git push origin master >> "$LOG_FILE" 2>&1
            fi
            ;;
    esac
done < "$REPO_LIST"

echo "[$TIMESTAMP] Bulk $operation completed" >> "$LOG_FILE"
```

### Multi-Repository Status Dashboard

```bash
#!/bin/bash
# ~/Scripts/git_dashboard.sh

REPO_LIST="$HOME/Scripts/repo_list.txt"

if [ ! -f "$REPO_LIST" ]; then
    echo "Run discover_repos.sh first to generate repository list"
    exit 1
fi

echo "=== MULTI-REPOSITORY STATUS DASHBOARD ==="
echo "Date: $(date)"
echo ""

uncommitted_count=0
unpushed_count=0
no_remote_count=0
total_repos=0

echo "Repository Status Summary:"
echo "========================="

while IFS='|' read -r project_name project_dir remote_url; do
    if [ ! -d "$project_dir" ]; then
        continue
    fi
    
    cd "$project_dir"
    total_repos=$((total_repos + 1))
    
    # Check for uncommitted changes
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        uncommitted_count=$((uncommitted_count + 1))
        echo "🔄 $project_name: Uncommitted changes"
    fi
    
    # Check for unpushed commits (if remote exists)
    if [ "$remote_url" != "NO_REMOTE" ]; then
        # Check if ahead of remote
        git fetch origin >/dev/null 2>&1
        ahead=$(git rev-list --count HEAD ^origin/main 2>/dev/null || \
                git rev-list --count HEAD ^origin/master 2>/dev/null || echo "0")
        
        if [ "$ahead" -gt 0 ]; then
            unpushed_count=$((unpushed_count + 1))
            echo "📤 $project_name: $ahead commits ahead of remote"
        fi
    else
        no_remote_count=$((no_remote_count + 1))
        echo "🔗 $project_name: No remote configured"
    fi
done < "$REPO_LIST"

echo ""
echo "SUMMARY:"
echo "Total repositories: $total_repos"
echo "With uncommitted changes: $uncommitted_count"
echo "With unpushed commits: $unpushed_count"  
echo "Without remote: $no_remote_count"
echo "Clean repositories: $((total_repos - uncommitted_count - unpushed_count))"
```

### Enhanced Backup Script for Multi-Repo Structure

Update the main backup script to work with individual repositories:

```bash
#!/bin/bash
# ~/Scripts/prj_backup.sh (updated for multiple repos)

LOG_FILE="$HOME/Scripts/backup.log"
PRJ_DIR="$HOME/prj"
GREY_SNAPSHOTS="/Volumes/PrjSnapshots"
BLUE_MIRROR="/Volumes/PrjMirror/current"
TIMESTAMP=$(date "+%Y-%m-%d_%H-%M-%S")

echo "[$TIMESTAMP] Starting multi-repository backup process" >> "$LOG_FILE"

# Update repository list
~/Scripts/discover_repos.sh >/dev/null 2>&1

# Git operations for all repositories
bulk_git_sync() {
    echo "[$TIMESTAMP] Starting bulk Git sync for all repositories" >> "$LOG_FILE"
    
    # Commit changes in all repos
    ~/Scripts/bulk_git_ops.sh commit >/dev/null 2>&1
    
    # Push changes (with error handling)
    if ~/Scripts/bulk_git_ops.sh push >/dev/null 2>&1; then
        echo "[$TIMESTAMP] Bulk Git sync completed successfully" >> "$LOG_FILE"
        return 0
    else
        echo "[$TIMESTAMP] Some Git pushes failed - check git_bulk.log" >> "$LOG_FILE"
        return 1
    fi
}

# [Include previous functions: check_disk_space, create_grey_snapshot, update_blue_mirror, etc.]

# Execute all backups with Git sync
bulk_git_sync
create_grey_snapshot  
update_blue_mirror
update_cloud_backup

echo "[$TIMESTAMP] Multi-repository backup process completed" >> "$LOG_FILE"
```

### Repository Health Check

```bash
#!/bin/bash
# ~/Scripts/repo_health_check.sh

REPO_LIST="$HOME/Scripts/repo_list.txt"

echo "=== REPOSITORY HEALTH CHECK ==="

problem_repos=0
healthy_repos=0

while IFS='|' read -r project_name project_dir remote_url; do
    if [ ! -d "$project_dir" ]; then
        continue
    fi
    
    cd "$project_dir"
    
    # Check if .git directory is healthy
    if ! git status >/dev/null 2>&1; then
        echo "❌ $project_name: Git repository corrupted"
        problem_repos=$((problem_repos + 1))
        continue
    fi
    
    # Check remote connectivity
    if [ "$remote_url" != "NO_REMOTE" ]; then
        if ! git ls-remote origin >/dev/null 2>&1; then
            echo "⚠️  $project_name: Remote connectivity issues"
            problem_repos=$((problem_repos + 1))
            continue
        fi
    fi
    
    # Check for very old commits (possible stale repos)
    last_commit_date=$(git log -1 --format="%ct" 2>/dev/null)
    if [ -n "$last_commit_date" ]; then
        days_old=$(( ($(date +%s) - last_commit_date) / 86400 ))
        if [ "$days_old" -gt 365 ]; then
            echo "📅 $project_name: Last commit $days_old days ago"
        fi
    fi
    
    healthy_repos=$((healthy_repos + 1))
    
done < "$REPO_LIST"

echo ""
echo "Health Summary:"
echo "Healthy repositories: $healthy_repos"
echo "Problem repositories: $problem_repos"
```

## Part 5: Vim Integration

As a vim user, having backup commands at your fingertips is essential:

```vim
" ~/.vimrc additions for multi-repository management
command! BackupStatus :!~/Scripts/backup_status.sh
command! BackupNow :!~/Scripts/prj_backup.sh
command! GitDashboard :!~/Scripts/git_dashboard.sh
command! RepoHealth :!~/Scripts/repo_health_check.sh
command! GitSyncAll :!~/Scripts/bulk_git_ops.sh sync

" Project-specific Git operations (for current directory)
command! GitStatus :!git status
command! GitCommit :!git add . && git commit -m "Manual commit from vim"
command! GitPush :!git push origin main || git push origin master
command! GitSync :!git add . && git commit -m "Manual sync from vim" && (git push origin main || git push origin master)

" Quick mappings
nnoremap <leader>bs :BackupStatus<CR>
nnoremap <leader>bn :BackupNow<CR>
nnoremap <leader>gd :GitDashboard<CR>
nnoremap <leader>gh :RepoHealth<CR>
nnoremap <leader>ga :GitSyncAll<CR>
nnoremap <leader>gs :GitSync<CR>

" Project navigation
nnoremap <leader>pf :find ~/prj/**/*
nnoremap <leader>pg :grep -r "" ~/prj/<Left><Left><Left><Left><Left><Left><Left><Left><Left><Left>

" Smart backup - only sync current project repository
function! SmartGitBackup()
    let current_dir = expand('%:p:h')
    if stridx(current_dir, expand('~/prj')) == 0
        " Find the git root for current file
        let git_root = systemlist('cd ' . shellescape(current_dir) . ' && git rev-parse --show-toplevel 2>/dev/null')[0]
        if !empty(git_root) && !v:shell_error
            execute '!cd ' . shellescape(git_root) . ' && git add . && git commit -m "Auto-save backup" && (git push origin main || git push origin master)'
        endif
    endif
endfunction

" Throttled auto-backup per repository
let g:repo_backup_times = {}
function! ConditionalRepoBackup()
    let current_dir = expand('%:p:h')
    if stridx(current_dir, expand('~/prj')) == 0
        let git_root = systemlist('cd ' . shellescape(current_dir) . ' && git rev-parse --show-toplevel 2>/dev/null')[0]
        if !empty(git_root) && !v:shell_error
            let current_time = localtime()
            if !has_key(g:repo_backup_times, git_root) || (current_time - g:repo_backup_times[git_root] > 300)
                let g:repo_backup_times[git_root] = current_time
                call SmartGitBackup()
            endif
        endif
    endif
endfunction

autocmd BufWritePost ~/prj/* call ConditionalRepoBackup()
```

## Part 6: Enhanced Monitoring for Large Directory Structure

### Comprehensive Status Script

```bash
#!/bin/bash
# ~/Scripts/backup_status.sh

echo "=== PROJECT BACKUP SYSTEM STATUS (Large Directory Structure) ==="
echo "Date: $(date)"
echo ""

# Project directory statistics
echo "PROJECT DIRECTORY OVERVIEW:"
if [ -d "$HOME/prj" ]; then
    echo "Size: $(du -sh "$HOME/prj" | cut -f1)"
    echo "Subdirectories: $(find "$HOME/prj" -type d | wc -l | tr -d ' ')"
    echo "Files: $(find "$HOME/prj" -type f | wc -l | tr -d ' ')"
    echo "Last modified: $(find "$HOME/prj" -type f -exec stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" {} \; | sort -r | head -1)"
else
    echo "ERROR: Project directory not found"
fi
echo ""

# Time Machine status
echo "TIME MACHINE STATUS:"
tmutil status | grep -E "(Running|Backup|Progress|NextBackup)"
if [ $? -ne 0 ]; then
    echo "  Time Machine: $(tmutil status | head -2 | tail -1)"
fi

# USB drive status
echo ""
echo "USB DRIVES:"
df -h | grep -E "(PrjSnapshots|PrjMirror|PrjArchive|TimeMachine)" | \
    while read line; do
        echo "  $line"
    done

# Recent snapshots on grey drive
echo ""
echo "RECENT SNAPSHOTS (Grey Drive):"
if [ -d "/Volumes/PrjSnapshots" ]; then
    ls -lt /Volumes/PrjSnapshots/snapshot_* 2>/dev/null | head -5 | while read line; do
        dir_name=$(echo "$line" | awk '{print $9}')
        if [ -n "$dir_name" ]; then
            size=$(du -sh "$dir_name" 2>/dev/null | cut -f1)
            echo "  $(basename "$dir_name"): $size"
        fi
    done
else
    echo "No snapshots directory found"
fi
echo ""

# Blue drive mirror status
echo "BLUE DRIVE MIRROR STATUS:"
if [ -f "/Volumes/PrjMirror/current/.last_backup" ]; then
    echo "Last backup: $(cat /Volumes/PrjMirror/current/.last_backup)"
    echo "Mirror size: $(du -sh /Volumes/PrjMirror/current 2>/dev/null | cut -f1)"
else
    echo "No mirror backup found"
fi
echo ""

# Weekly archives
echo "WEEKLY ARCHIVES:"
if [ -d "/Volumes/PrjArchive/weekly" ]; then
    ls -lt /Volumes/PrjArchive/weekly/prj_weekly_*.tar.gz 2>/dev/null | head -3 | while read line; do
        file_name=$(echo "$line" | awk '{print $9}')
        if [ -n "$file_name" ]; then
            size=$(echo "$line" | awk '{print $5}')
            echo "  $(basename "$file_name"): $(numfmt --to=iec "$size")"
        fi
    done
else
    echo "No weekly archives found"
fi
echo ""

# Git repository status
echo ""
echo "MULTI-REPOSITORY GIT STATUS:"
if [ -f "$HOME/Scripts/repo_list.txt" ]; then
    total_repos=$(wc -l < "$HOME/Scripts/repo_list.txt")
    echo "Total repositories: $total_repos"
    
    # Count repositories with uncommitted changes
    uncommitted=0
    while IFS='|' read -r project_name project_dir remote_url; do
        if [ -d "$project_dir" ]; then
            cd "$project_dir"
            if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
                uncommitted=$((uncommitted + 1))
            fi
        fi
    done < "$HOME/Scripts/repo_list.txt"
    
    echo "Repositories with uncommitted changes: $uncommitted"
    echo "Clean repositories: $((total_repos - uncommitted))"
    echo "Run 'git_dashboard.sh' for detailed status"
else
    echo "Repository list not found - run discover_repos.sh"
fi
echo ""

# Cloud backup status
echo "CLOUD BACKUP STATUS:"
if command -v rclone >/dev/null 2>&1; then
    echo "rclone available: ✓"
    # Check if we can reach Google Drive
    if timeout 10 rclone lsd googledrive: >/dev/null 2>&1; then
        echo "Google Drive connection: ✓"
        cloud_size=$(rclone size googledrive:prj/ 2>/dev/null | grep "Total size:" | awk '{print $3, $4}')
        echo "Cloud backup size: $cloud_size"
    else
        echo "Google Drive connection: ✗"
    fi
else
    echo "rclone not available"
fi
echo ""

# Recent backup activity
echo "RECENT BACKUP ACTIVITY:"
if [ -f "$HOME/Scripts/backup.log" ]; then
    echo "Last 5 backup events:"
    tail -5 "$HOME/Scripts/backup.log" | while read line; do
        echo "  $line"
    done
else
    echo "No backup log found"
fi
echo ""

# Disk space warnings
echo "DISK SPACE WARNINGS:"
df -h | awk 'NR>1 && $5+0 > 80 {print "WARNING: " $1 " is " $5 " full (" $4 " available)"}'
[ $? -eq 1 ] && echo "All drives have adequate space"
```

Part 7: Recovery Procedures (For Large Directory)

Enhanced Recovery Script

When disaster strikes, you need quick access to recovery options. The recovery helper script (detailed in Appendix A.5) provides comprehensive recovery options from all backup sources.
Quick Recovery Summary:

Recent Changes: Grey drive snapshots (hourly, last 48 hours)
Complete Current State: Blue drive mirror (synchronized copy)
Historical Versions: Weekly compressed archives
Individual Projects: Clone specific repositories from GitHub
System-wide Recovery: Time Machine for complete system restore
Cloud Recovery: Google Drive and iCloud backups

Recovery Command Examples
