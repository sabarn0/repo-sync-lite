# Test script for repo-sync-lite
$ErrorActionPreference = "Stop"

$TestDir = Join-Path $PSScriptRoot "scratch_test"
if (Test-Path $TestDir) { Remove-Item -LiteralPath $TestDir -Recurse -Force }

$SourceDir     = Join-Path $TestDir "source"
$TargetDir     = Join-Path $TestDir "target"
$BinDir        = Join-Path $TestDir "bin"
$ReportsFolder = Join-Path $TestDir "custom_reports"
$ReportName    = "sync_report.csv"
$TestConfig    = Join-Path $TestDir "config.json"

New-Item -ItemType Directory -Path $SourceDir -Force | Out-Null
New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
New-Item -ItemType Directory -Path $BinDir -Force | Out-Null

# 1. Create sample source structure
# Common file
Set-Content (Join-Path $SourceDir "common.txt") "Common file content"
Set-Content (Join-Path $TargetDir "common.txt") "Common file content"

# Missing files & folders in target (present in source only)
Set-Content (Join-Path $SourceDir "missing_root.txt") "Missing root file"
New-Item -ItemType Directory (Join-Path $SourceDir "new_feature") -Force | Out-Null
Set-Content (Join-Path $SourceDir "new_feature\service.js") "console.log('service')"
New-Item -ItemType Directory (Join-Path $SourceDir "empty_folder") -Force | Out-Null

# Extra files & folders in target (present in target only)
Set-Content (Join-Path $TargetDir "extra_root.txt") "Extra root file in target"
New-Item -ItemType Directory (Join-Path $TargetDir "old_feature") -Force | Out-Null
Set-Content (Join-Path $TargetDir "old_feature\deprecated.log") "deprecated data"

# Excluded files (should be ignored)
New-Item -ItemType Directory (Join-Path $SourceDir ".git") -Force | Out-Null
Set-Content (Join-Path $SourceDir ".git\HEAD") "ref: refs/heads/main"
New-Item -ItemType Directory (Join-Path $TargetDir ".git") -Force | Out-Null
Set-Content (Join-Path $TargetDir ".git\HEAD") "ref: refs/heads/main"

# Config file for test specifying ReportsDir and ReportName
@{
    SourcePath      = $SourceDir
    TargetPath      = $TargetDir
    BinPath         = $BinDir
    ReportsDir      = $ReportsFolder
    ReportName      = $ReportName
    ExcludePatterns = @(".git", "node_modules")
} | ConvertTo-Json | Set-Content $TestConfig

Write-Host ">>> STEP 1: Running create_report.ps1 (reading ReportsDir & ReportName from config)..." -ForegroundColor Yellow
$CreateReportScript = Join-Path (Split-Path $PSScriptRoot -Parent) "create_report.ps1"
$MergeScript        = Join-Path (Split-Path $PSScriptRoot -Parent) "merge_changes.ps1"

& $CreateReportScript -ConfigFile $TestConfig

# Verify reports folder and files exist
$ExpectedMasterCsv  = Join-Path $ReportsFolder $ReportName
$ExpectedMissingCsv = Join-Path $ReportsFolder "sync_report_missing.csv"
$ExpectedExtraCsv   = Join-Path $ReportsFolder "sync_report_extra.csv"
$ExpectedProcessCsv = Join-Path $ReportsFolder "sync_report_process.csv"

if (-not (Test-Path $ExpectedMasterCsv)) {
    throw "TEST FAILED: Master report '$ExpectedMasterCsv' was not generated in reports folder!"
}
if (-not (Test-Path $ExpectedMissingCsv)) {
    throw "TEST FAILED: Missing report '$ExpectedMissingCsv' was not generated in reports folder!"
}
if (-not (Test-Path $ExpectedExtraCsv)) {
    throw "TEST FAILED: Extra report '$ExpectedExtraCsv' was not generated in reports folder!"
}
if (-not (Test-Path $ExpectedProcessCsv)) {
    throw "TEST FAILED: Process report '$ExpectedProcessCsv' was not generated in reports folder!"
}

$ReportData = Import-Csv $ExpectedMasterCsv
Write-Host "Report rows count: $($ReportData.Count)"

$MissingEntries = @($ReportData | Where-Object { $_.Category -eq "Missing" })
$ExtraEntries   = @($ReportData | Where-Object { $_.Category -eq "Extra" })

Write-Host "Detected Missing count: $($MissingEntries.Count)"
Write-Host "Detected Extra count  : $($ExtraEntries.Count)"

# Check missing items
$MissingRelPaths = $MissingEntries.RelativePath
if ($MissingRelPaths -notcontains "missing_root.txt") { throw "TEST FAILED: missing_root.txt not in Missing list!" }
if ($MissingRelPaths -notcontains "new_feature\service.js") { throw "TEST FAILED: new_feature\service.js not in Missing list!" }
if ($MissingRelPaths -notcontains "empty_folder") { throw "TEST FAILED: empty_folder not in Missing list!" }

# Check extra items
$ExtraRelPaths = $ExtraEntries.RelativePath
if ($ExtraRelPaths -notcontains "extra_root.txt") { throw "TEST FAILED: extra_root.txt not in Extra list!" }
if ($ExtraRelPaths -notcontains "old_feature\deprecated.log") { throw "TEST FAILED: old_feature\deprecated.log not in Extra list!" }

# Check that .git was excluded
if ($MissingRelPaths -match '\.git' -or $ExtraRelPaths -match '\.git') {
    throw "TEST FAILED: .git was not properly excluded!"
}

Write-Host ">>> STEP 2: Running merge_changes.ps1 in DRY-RUN mode (auto-resolving report from config)..." -ForegroundColor Yellow
& $MergeScript -ConfigFile $TestConfig -DryRun

# Verify target has NOT changed yet
if (Test-Path (Join-Path $TargetDir "missing_root.txt")) {
    throw "TEST FAILED: DryRun modified files (missing_root.txt exists in target)!"
}
if (-not (Test-Path (Join-Path $TargetDir "extra_root.txt"))) {
    throw "TEST FAILED: DryRun removed files (extra_root.txt missing from target)!"
}

Write-Host ">>> STEP 3: Running merge_changes.ps1 LIVE with -Force (auto-resolving report from config)..." -ForegroundColor Yellow
& $MergeScript -ConfigFile $TestConfig -Force

# Verify missing files are now present in target
if (-not (Test-Path (Join-Path $TargetDir "missing_root.txt"))) {
    throw "TEST FAILED: missing_root.txt was not copied to target!"
}
if (-not (Test-Path (Join-Path $TargetDir "new_feature\service.js"))) {
    throw "TEST FAILED: new_feature\service.js was not copied to target!"
}
if (-not (Test-Path (Join-Path $TargetDir "empty_folder"))) {
    throw "TEST FAILED: empty_folder was not created in target!"
}

# Verify extra files are removed from target
if (Test-Path (Join-Path $TargetDir "extra_root.txt")) {
    throw "TEST FAILED: extra_root.txt was not removed from target!"
}
if (Test-Path (Join-Path $TargetDir "old_feature\deprecated.log")) {
    throw "TEST FAILED: old_feature\deprecated.log was not removed from target!"
}

# Verify extra files are in bin
$BinItems = Get-ChildItem -LiteralPath $BinDir -Recurse -File
if ($BinItems.Count -eq 0) {
    throw "TEST FAILED: Extra items were not archived into BinDir!"
}
Write-Host "Bin files archived: $($BinItems.Name -join ', ')"

Write-Host ">>> STEP 4: Re-running create_report.ps1 to verify 0 differences..." -ForegroundColor Yellow
& $CreateReportScript -ConfigFile $TestConfig
$FinalReportData = Import-Csv $ExpectedMasterCsv
if ($FinalReportData.Count -ne 0) {
    throw "TEST FAILED: Differences still remain after merge! Count: $($FinalReportData.Count)"
}

Write-Host "`nAll Tests Passed Successfully!" -ForegroundColor Green

# Cleanup
Remove-Item -LiteralPath $TestDir -Recurse -Force
