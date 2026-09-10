# Repo Sync Lite

A lightweight, safe, and flexible PowerShell utility to compare two directory trees or repositories (Source and Target), identify differences, generate CSV reports, and safely synchronize missing/extra files and folders.

---

## Features

- **Difference Detection**:
  - **Missing (`Source - Target`)**: Files and folders present in Source but missing from Target.
  - **Extra (`Target - Source`)**: Files and folders present in Target but absent from Source (including DLLs and new changes).
  - **Modified (`Source != Target`)**: Files present in both whose contents differ (SHA256 checksum & file size validation).
- **Reporting (`report.csv`)**:
  - **Master CSV (`report.csv`)**: Contains all differences with columns `Category`, `ItemType`, `Name`, `RelativePath`, `SourcePath`, `TargetPath`, `Action`, `Process`.
  - **Convenience Split CSVs**: Automatically creates `report_missing.csv`, `report_extra.csv`, `report_modified.csv`, and `report_process.csv`.
- **Validation Before Merge**:
  - Review and edit `report.csv` directly in Excel or any text editor before merging.
  - Set `Process = "No"` or `Action = "Skip"` to exclude any specific files or folders from synchronization.
- **Non-Destructive Safe Merging**:
  - Extra and modified items are **never hard-deleted**. They are archived into a timestamped directory inside `temp_bin/run_<timestamp>/` preserving their original relative directory hierarchy.
- **Dry-Run Mode (`-WhatIf` / `-DryRun`)**:
  - Preview every copy, folder creation, and bin movement without altering any files on disk.
- **Digital Signature / Execution Policy Free Execution**:
  - Included `.bat` launchers (`create_report.bat`, `merge_changes.bat`, `unblock.bat`) bypass execution policy restrictions automatically.

---

## File Structure

```
repo-sync-lite/
├── config.json            # Configuration: Source, Target, Bin, ReportsDir, ReportName, Exclusions
├── create_report.bat      # One-click runner (bypasses PowerShell execution policies)
├── create_report.ps1      # Compares Source and Target, generates CSV reports in reports/
├── merge_changes.bat      # One-click merge runner
├── merge_changes.ps1      # Applies validated differences (copy missing, archive extra/modified to bin)
├── unblock.bat            # One-click unblocker for downloaded git files
├── reports/               # Generated reports folder
│   ├── report.csv         # Generated master CSV report
│   ├── report_missing.csv # Missing items sheet
│   ├── report_extra.csv   # Extra items sheet
│   ├── report_modified.csv# Content-modified items sheet
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

## PowerShell Execution Policy & Digital Signature Fix

When downloading scripts from GitHub/GitLab (e.g. as a zip), Windows flags them with the "Mark of the Web", which triggers `...is not digitally signed` under PowerShell's `RemoteSigned` policy.

You have three easy ways to resolve this:

### Option 1: Double-click `unblock.bat` (Recommended)
Simply double-click `unblock.bat` in the folder. It will strip the Internet flag from all `.ps1` files in one second.

### Option 2: Run via `.bat` Launchers
Instead of running `.ps1`, run the batch wrappers directly from cmd or PowerShell:
```cmd
.\create_report.bat
.\merge_changes.bat
```
These automatically launch PowerShell with `-ExecutionPolicy Bypass`.

### Option 3: Run PowerShell Unblock-File
In PowerShell, run:
```powershell
Get-ChildItem -Recurse | Unblock-File
```

---

## Comparing .NET Repositories

In .NET repositories, assemblies and compiled outputs live in `bin/` and `obj/`.
- If you want to detect **missing or extra `.dll` files** inside `bin/`, ensure `"bin"` and `"obj"` are **NOT** in `ExcludePatterns` in `config.json`.
- Set `"DetectModified": true` in `config.json` to detect code files, `.csproj`, or `.dll` binaries whose contents have changed between Source and Target.

---

## Running Automated Tests

To run the automated test suite:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\test_sync.ps1
```
