# Repo Sync Lite

A lightweight, safe, and flexible PowerShell utility to compare two directory trees or repositories (Source and Target), identify differences, generate CSV reports, and safely synchronize missing/extra files and folders.

---

## Features

- **Difference Detection**:
  - **Missing (`Source - Target`)**: Files and folders present in Source but missing from Target.
  - **Extra (`Target - Source`)**: Files and folders present in Target but absent from Source.
- **Reporting (`report.csv`)**:
  - **Master CSV (`report.csv`)**: Contains all differences with columns `Category`, `ItemType`, `Name`, `RelativePath`, `SourcePath`, `TargetPath`, `Action`, `Process`.
  - **Convenience Split CSVs**: Automatically creates `report_missing.csv`, `report_extra.csv`, and `report_process.csv`.
- **Validation Before Merge**:
  - Review and edit `report.csv` directly in Excel or any text editor before merging.
  - Set `Process = "No"` or `Action = "Skip"` to exclude any specific files or folders from synchronization.
- **Non-Destructive Safe Merging**:
  - Extra items are **never hard-deleted**. They are archived into a timestamped directory inside `temp_bin/run_<timestamp>/` preserving their original relative directory hierarchy.
- **Dry-Run Mode (`-WhatIf` / `-DryRun`)**:
  - Preview every copy, folder creation, and bin movement without altering any files on disk.
- **Flexible Exclusions**:
  - Exclude `.git`, `node_modules`, `.vs`, build outputs, or custom file patterns via `config.json`.

---

## File Structure

```
repo-sync-lite/
├── config.json            # Configuration: Source, Target, Bin, ReportsDir, ReportName, Exclusions
├── create_report.ps1      # Compares Source and Target, generates CSV reports in reports/
├── merge_changes.ps1      # Applies validated differences (copy missing, archive extra to bin)
├── reports/               # Generated reports folder
│   ├── report.csv         # Generated master CSV report
│   ├── report_missing.csv # Missing items sheet
│   ├── report_extra.csv   # Extra items sheet
│   └── report_process.csv # Validated items sheet for processing
├── README.md              # Documentation and guide
└── tests/
    └── test_sync.ps1      # End-to-end automated tests
```

---

## Quick Start

### 1. Configure Paths

Edit `config.json` to specify your directories and report settings:

```json
{
  "SourcePath": "C:/Projects/SourceRepo",
  "TargetPath": "C:/Projects/TargetRepo",
  "BinPath": "C:/Projects/TargetRepo_Bin",
  "ReportsDir": "./reports",
  "ReportName": "report.csv",
  "ExcludePatterns": [
    ".git",
    ".vs",
    ".idea",
    "node_modules",
    "bin",
    "obj",
    ".DS_Store",
    "Thumbs.db"
  ]
}
```

*You can also pass paths via command-line arguments (e.g. `-Source`, `-Target`, `-Bin`).*

---

### 2. Generate Difference Report

Run:

```powershell
.\create_report.ps1
```

Or with explicit paths:

```powershell
.\create_report.ps1 -Source "C:\repoA" -Target "C:\repoB" -Bin "C:\repo_bin"
```

This generates:
- `report.csv` (Master difference report)
- `report_missing.csv` (Items present in Source but missing from Target)
- `report_extra.csv` (Items present in Target but not in Source)
- `report_process.csv` (Items queued for processing)

---

### 3. Review & Validate the Report

Open `report.csv` in Excel or VS Code:

| Category | ItemType | Name | RelativePath | SourcePath | TargetPath | Action | Process |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Missing | File | `utils.js` | `src\utils.js` | `C:\source\src\utils.js` | `C:\target\src\utils.js` | Copy | **Yes** |
| Extra | File | `temp.log` | `logs\temp.log` | `C:\source\logs\temp.log` | `C:\target\logs\temp.log` | MoveToBin | **Yes** |
| Extra | File | `secret.key` | `config\secret.key` | ... | ... | MoveToBin | **No** |

- **To skip an item**: Change `Process` to `No` or change `Action` to `Skip`.
- **To process an item**: Ensure `Process` is `Yes`.

---

### 4. Preview with Dry-Run (`-WhatIf`)

Simulate the merge without changing any files:

```powershell
.\merge_changes.ps1 -DryRun
```

Or:

```powershell
.\merge_changes.ps1 -WhatIf
```

---

### 5. Execute Merge

When you are ready to synchronize:

```powershell
.\merge_changes.ps1
```

*(You will be asked to confirm before operations commence. Use `-Force` to bypass the prompt for automation/scripts).*

- **Missing items** (`Action: Copy`): Copied from `Source` to `Target`.
- **Extra items** (`Action: MoveToBin`): Moved into `temp_bin/run_<yyyyMMdd_HHmmss>/<RelativePath>`.

---

## Running Automated Tests

To run the automated test suite:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\test_sync.ps1
```
