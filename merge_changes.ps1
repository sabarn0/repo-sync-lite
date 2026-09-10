<#
.SYNOPSIS
    Applies validated differences from report.csv to synchronize repositories.

.DESCRIPTION
    Reads report.csv, validates rows marked for processing (Process = 'Yes'),
    copies missing items from Source to Target, and safely moves extra items
    from Target to a timestamped folder in BinPath preserving folder structure.
    Supports -WhatIf / -DryRun for safe pre-execution inspection.

.PARAMETER ReportPath
    Path to the CSV report. Defaults to "report.csv".

.PARAMETER ConfigFile
    Path to configuration JSON file. Defaults to "config.json".

.PARAMETER Bin
    Path to temporary bin directory. Overrides ConfigFile if provided.

.PARAMETER WhatIf
    Simulates the merge operations without modifying any files or folders.

.PARAMETER DryRun
    Alias for -WhatIf.

.PARAMETER Force
    Executes changes without interactive confirmation prompt.

.EXAMPLE
    .\merge_changes.ps1 -WhatIf
    .\merge_changes.ps1
    .\merge_changes.ps1 -ReportPath "report.csv" -Force
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [string]$ReportPath,
    [string]$ConfigFile = "config.json",
    [string]$Bin,
    [switch]$DryRun,
    [switch]$Force
)

# Set strict mode and error handling
$ErrorActionPreference = "Stop"

# Honor DryRun alias for ShouldProcess / WhatIf
$IsWhatIf = $PSCmdlet.MyInvocation.BoundParameters.ContainsKey('WhatIf') -or $DryRun

# Helper to resolve absolute paths relative to script root
function Resolve-FullPath {
    param ([string]$Path, [string]$BasePath)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($BasePath, $Path))
}

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

# Load configuration if available
$ConfigPath = Resolve-FullPath -Path $ConfigFile -BasePath $ScriptDir
$Config = $null
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $Config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Warning "Could not parse configuration file '$ConfigPath'."
    }
}

$ConfigReportsDir     = if ($Config.ReportsDir) { $Config.ReportsDir } else { "./reports" }
$ConfigReportName     = if ($Config.ReportName) { $Config.ReportName } else { "report.csv" }
$ConfigReportCombined = [System.IO.Path]::Combine($ConfigReportsDir, $ConfigReportName)

$ChosenReport = if ($ReportPath) {
    $ReportPath
} elseif (Test-Path -LiteralPath (Resolve-FullPath -Path $ConfigReportCombined -BasePath $ScriptDir)) {
    $ConfigReportCombined
} elseif (Test-Path -LiteralPath (Resolve-FullPath -Path "./reports/report.csv" -BasePath $ScriptDir)) {
    "./reports/report.csv"
} elseif (Test-Path -LiteralPath (Resolve-FullPath -Path "./report.csv" -BasePath $ScriptDir)) {
    "./report.csv"
} else {
    $ConfigReportCombined
}

$ResolvedReportPath = Resolve-FullPath -Path $ChosenReport -BasePath $ScriptDir
$ResolvedBin = if ($Bin) { $Bin } elseif ($Config.BinPath) { $Config.BinPath } else { "./temp_bin" }
$BinFullPath = Resolve-FullPath -Path $ResolvedBin -BasePath $ScriptDir

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "             REPO SYNC LITE - MERGE               " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Report Path : $ResolvedReportPath"
Write-Host "Bin Path    : $BinFullPath"
if ($IsWhatIf) {
    Write-Host "Mode        : DRY RUN (WhatIf) - No files will be modified" -ForegroundColor Yellow
} else {
    Write-Host "Mode        : LIVE EXECUTION" -ForegroundColor Green
}
Write-Host "--------------------------------------------------"

if (-not (Test-Path -LiteralPath $ResolvedReportPath)) {
    throw "Report file does not exist: '$ResolvedReportPath'. Please run create_report.ps1 first."
}

# Read report
$Report = @(Import-Csv -LiteralPath $ResolvedReportPath -Encoding UTF8)

if (-not $Report -or $Report.Count -eq 0) {
    Write-Host "Report is empty. Nothing to process." -ForegroundColor Green
    return
}

# Helper to check if a row is marked for processing
function Test-ShouldProcessItem {
    param ($Row)
    if ([string]::IsNullOrWhiteSpace($Row.Process)) { return $false }
    $p = $Row.Process.Trim().ToLowerInvariant()
    $a = if ($Row.Action) { $Row.Action.Trim().ToLowerInvariant() } else { "" }

    if ($a -eq "skip" -or $a -eq "ignore") { return $false }
    return ($p -eq "yes" -or $p -eq "true" -or $p -eq "1" -or $p -eq "y")
}

$ItemsToProcess = @($Report | Where-Object { Test-ShouldProcessItem $_ })
$SkippedCount = $Report.Count - $ItemsToProcess.Count

Write-Host "Found $($Report.Count) total difference record(s)."
Write-Host "Items marked for processing : $($ItemsToProcess.Count)" -ForegroundColor Cyan
Write-Host "Items skipped               : $SkippedCount" -ForegroundColor Gray

if ($ItemsToProcess.Count -eq 0) {
    Write-Host "No items marked for processing (Process = 'Yes' and Action != 'Skip')." -ForegroundColor Yellow
    Write-Host "Review '$ResolvedReportPath' and set Process = 'Yes' for items you wish to synchronize."
    return
}

$CopyItems = @($ItemsToProcess | Where-Object { $_.Action -like "Copy*" -or ($_.Category -eq "Missing" -and -not $_.Action) })
$MoveItems = @($ItemsToProcess | Where-Object { $_.Action -like "Move*" -or $_.Action -like "Remove*" -or ($_.Category -eq "Extra" -and -not $_.Action) })

Write-Host "  -> Items to Copy (Missing)  : $($CopyItems.Count)"
Write-Host "  -> Items to Bin  (Extra)    : $($MoveItems.Count)"
Write-Host "--------------------------------------------------"

if (-not $IsWhatIf -and -not $Force) {
    $Confirmation = Read-Host "Proceed with merging $($ItemsToProcess.Count) items? (y/N)"
    if ($Confirmation -notmatch '^(y|yes)$') {
        Write-Host "Merge operation cancelled by user." -ForegroundColor Yellow
        return
    }
}

# Timestamped session bin folder for this run
$Timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$SessionBinPath = [System.IO.Path]::Combine($BinFullPath, "run_$Timestamp")

$SuccessCopyCount = 0
$SuccessMoveCount = 0
$ErrorList = [System.Collections.Generic.List[PSCustomObject]]::new()

# Phase 1: Process Copy (Missing items)
# Order: Process folders first to ensure directory structure, then files
$SortedCopyItems = $CopyItems | Sort-Object @{ Expression = { if ($_.ItemType -eq "Folder") { 0 } else { 1 } } }, RelativePath

foreach ($item in $SortedCopyItems) {
    $src = $item.SourcePath
    $dest = $item.TargetPath
    $rel = $item.RelativePath
    $isFolder = ($item.ItemType -eq "Folder")

    try {
        if (-not (Test-Path -LiteralPath $src)) {
            throw "Source item not found: '$src'"
        }

        if ($isFolder) {
            if ($IsWhatIf) {
                Write-Host "[WHATIF] Would CREATE FOLDER '$dest'" -ForegroundColor Cyan
            } else {
                if (-not (Test-Path -LiteralPath $dest)) {
                    $null = New-Item -ItemType Directory -Path $dest -Force
                }
                Write-Host "[COPIED] Created folder '$rel'" -ForegroundColor Green
            }
            $SuccessCopyCount++
        } else {
            if ($IsWhatIf) {
                Write-Host "[WHATIF] Would COPY FILE '$rel' -> '$dest'" -ForegroundColor Cyan
            } else {
                $destParent = [System.IO.Path]::GetDirectoryName($dest)
                if (-not (Test-Path -LiteralPath $destParent)) {
                    $null = New-Item -ItemType Directory -Path $destParent -Force
                }
                Copy-Item -LiteralPath $src -Destination $dest -Force
                Write-Host "[COPIED] '$rel'" -ForegroundColor Green
            }
            $SuccessCopyCount++
        }
    } catch {
        Write-Host "[ERROR] Failed copying '$rel': $($_.Exception.Message)" -ForegroundColor Red
        $ErrorList.Add([PSCustomObject]@{
            RelativePath = $rel
            Action       = "Copy"
            Error        = $_.Exception.Message
        })
    }
}

# Phase 2: Process MoveToBin (Extra items)
# Order: Process files first, then directories
$SortedMoveItems = $MoveItems | Sort-Object @{ Expression = { if ($_.ItemType -eq "File") { 0 } else { 1 } } }, @{ Expression = { $_.RelativePath.Length } } -Descending

foreach ($item in $SortedMoveItems) {
    $targetPath = $item.TargetPath
    $rel = $item.RelativePath
    $isFolder = ($item.ItemType -eq "Folder")
    $binDest = [System.IO.Path]::Combine($SessionBinPath, $rel)

    try {
        if (-not (Test-Path -LiteralPath $targetPath)) {
            # Might have been already moved if parent was moved
            continue
        }

        if ($isFolder) {
            # Check if folder has any remaining files or subdirectories
            $remaining = @(Get-ChildItem -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue)
            if ($remaining.Count -eq 0) {
                if ($IsWhatIf) {
                    Write-Host "[WHATIF] Would REMOVE empty extra folder '$rel'" -ForegroundColor Cyan
                } else {
                    Remove-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
                    Write-Host "[REMOVED] Empty extra folder '$rel'" -ForegroundColor Magenta
                }
            } else {
                if ($IsWhatIf) {
                    Write-Host "[WHATIF] Would MOVE extra folder '$rel' -> '$binDest'" -ForegroundColor Cyan
                } else {
                    $binParent = [System.IO.Path]::GetDirectoryName($binDest)
                    if (-not (Test-Path -LiteralPath $binParent)) {
                        $null = New-Item -ItemType Directory -Path $binParent -Force
                    }
                    Move-Item -LiteralPath $targetPath -Destination $binDest -Force
                    Write-Host "[MOVED TO BIN] Folder '$rel'" -ForegroundColor Magenta
                }
            }
            $SuccessMoveCount++
        } else {
            if ($IsWhatIf) {
                Write-Host "[WHATIF] Would MOVE extra file '$rel' -> '$binDest'" -ForegroundColor Cyan
            } else {
                $binParent = [System.IO.Path]::GetDirectoryName($binDest)
                if (-not (Test-Path -LiteralPath $binParent)) {
                    $null = New-Item -ItemType Directory -Path $binParent -Force
                }
                Move-Item -LiteralPath $targetPath -Destination $binDest -Force
                Write-Host "[MOVED TO BIN] File '$rel'" -ForegroundColor Magenta
            }
            $SuccessMoveCount++
        }
    } catch {
        Write-Host "[ERROR] Failed moving '$rel' to bin: $($_.Exception.Message)" -ForegroundColor Red
        $ErrorList.Add([PSCustomObject]@{
            RelativePath = $rel
            Action       = "MoveToBin"
            Error        = $_.Exception.Message
        })
    }
}

Write-Host "--------------------------------------------------"
Write-Host "Execution Summary:" -ForegroundColor Green
Write-Host "  Items Copied (Missing)   : $SuccessCopyCount" -ForegroundColor Green
Write-Host "  Items Moved to Bin (Extra): $SuccessMoveCount" -ForegroundColor Magenta
Write-Host "  Items Skipped            : $SkippedCount" -ForegroundColor Gray
Write-Host "  Errors Encountered       : $($ErrorList.Count)" -ForegroundColor $(if ($ErrorList.Count -gt 0) { "Red" } else { "Green" })

if (-not $IsWhatIf -and $SuccessMoveCount -gt 0) {
    Write-Host "Extra items safely archived in : $SessionBinPath" -ForegroundColor Cyan
}

if ($ErrorList.Count -gt 0) {
    Write-Host "`nError Details:" -ForegroundColor Red
    $ErrorList | Format-Table -AutoSize
}
Write-Host "==================================================" -ForegroundColor Cyan
