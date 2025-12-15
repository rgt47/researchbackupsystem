# ==========================================
# ZZCOLLAB .Rprofile - Three-Part Structure
# ==========================================
# Part 1: User Personal Settings (from ~/.Rprofile)
# Part 2: renv Activation + Reproducibility Options
# Part 3: Auto-Snapshot on Exit
# ==========================================

# ==========================================
# Part 1: User Personal Settings
# ==========================================
q <- function(save="no", ...) quit(save=save, ...)

# Package installation behavior (non-interactive)
# Prevents prompts during install.packages()
options(
  install.packages.check.source = "no",
  install.packages.compile.from.source = "never",
  Ncpus = parallel::detectCores()
)

# ==========================================
# Part 2: Container Detection
# ==========================================
# Set ZZCOLLAB_CONTAINER=true in Dockerfile to enable renv
in_container <- Sys.getenv("ZZCOLLAB_CONTAINER") == "true"

# Set repos based on environment
if (in_container) {
  # Use Posit Package Manager for pre-compiled binaries in container
  # Set both repos AND renv.repos.cran (renv uses this option as its default)
  options(
    repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/latest"),
    renv.repos.cran = "https://packagemanager.posit.co/cran/__linux__/noble/latest"
  )
} else {
  options(repos = c(CRAN = "https://cloud.r-project.org"))
}

if (!in_container) {
  # ==========================================
  # Host R: Skip renv
  # ==========================================
  message("ℹ️ Host R session (renv skipped - use container for reproducibility)")

} else {
  # ==========================================
  # Container R: Full renv workflow
  # ==========================================

  # renv Cache Path Configuration
  # If RENV_PATHS_CACHE already set (e.g., via docker -e), use it
  # Otherwise use project-local cache
  if (Sys.getenv("RENV_PATHS_CACHE") == "") {
    Sys.setenv(RENV_PATHS_CACHE = file.path(getwd(), ".cache/R/renv"))
  }

  # Activate renv (set project-local library paths)
  if (file.exists("renv/activate.R")) {
    source("renv/activate.R")
  }

  # renv consent (skips first-time prompts)
  options(
    renv.consent = TRUE,
    renv.config.install.prompt = FALSE,
    renv.config.auto.snapshot = FALSE
  )

  # Helper function for initializing renv without prompts
  renv_init_quiet <- function() {
    renv::init(
      bare = TRUE,
      settings = list(snapshot.type = "implicit"),
      force = TRUE,
      restart = FALSE
    )

    message("✅ renv initialized")
    message("   Install packages with: install.packages('package')")
  }

  # ==========================================
  # Auto-Initialize renv (New Projects)
  # ==========================================
  if (!file.exists("renv.lock")) {
    auto_init <- Sys.getenv("ZZCOLLAB_AUTO_INIT", "true")
    is_project <- file.exists("DESCRIPTION") || getwd() == "/home/analyst/project"

    if (tolower(auto_init) %in% c("true", "t", "1") && is_project) {
      message("\n🔧 ZZCOLLAB: Auto-initializing renv for new project...")
      tryCatch({
        renv_init_quiet()
      }, error = function(e) {
        warning("⚠️  Auto-init failed: ", conditionMessage(e),
                "\n   Run manually: renv_init_quiet()", call. = FALSE)
      })
    }
  } else {
    # ==========================================
    # Skip Auto-Restore in CI Containers
    # ==========================================
    # NOTE: Packages are PRE-INSTALLED in Docker image during build
    # (see Dockerfile: COPY renv.lock + RUN renv::restore())
    # Auto-restore here would be redundant
    # Auto-restore is only useful for local development with host R
    message("ℹ️ Container mode: packages pre-installed in Docker image")
    message("   (auto-restore skipped - not needed in CI/CD)")
  }

  # ==========================================
  # Auto-Snapshot on R Exit (Development only, disabled in CI)
  # ==========================================
  .Last <- function() {
    # Disable snapshots in CI to prevent containers modifying renv.lock
    in_ci <- nzchar(Sys.getenv("CI")) || nzchar(Sys.getenv("GITHUB_ACTIONS"))

    if (!in_ci) {
      auto_snapshot <- Sys.getenv("ZZCOLLAB_AUTO_SNAPSHOT", "true")

      if (tolower(auto_snapshot) %in% c("true", "t", "1")) {
        if (file.exists("renv.lock") && file.exists("renv/activate.R")) {
          message("\n📸 Auto-snapshot: Updating renv.lock...")

          snapshot_result <- tryCatch({
            renv::snapshot(prompt = FALSE)
            TRUE
          }, error = function(e) {
            warning("Auto-snapshot failed: ", conditionMessage(e), call. = FALSE)
            FALSE
          })

          if (snapshot_result) {
            message("✅ renv.lock updated successfully")
            message("   Commit changes: git add renv.lock && git commit -m 'Update packages'")
          }
        }
      }
    }

    if (exists(".Last.user", mode = "function", envir = .GlobalEnv)) {
      tryCatch(
        .Last.user(),
        error = function(e) warning("User .Last failed: ", conditionMessage(e))
      )
    }
  }

  # Re-apply Posit PM repos AFTER renv::load() (which overrides from lockfile)
  options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/latest"))
}

# ==========================================
# Part 3: Reproducibility Options (always)
# ==========================================
# These ensure consistent behavior on both host and container
options(
  stringsAsFactors = FALSE,
  contrasts = c("contr.treatment", "contr.poly"),
  na.action = "na.omit",
  digits = 7,
  OutDec = "."
)

# ==========================================
# Part 4: Personal Customizations (always)
# ==========================================
if (file.exists(".Rprofile.local")) {
  tryCatch(
    source(".Rprofile.local"),
    error = function(e) {
      warning(".Rprofile.local failed to load: ", conditionMessage(e))
    }
  )
}
