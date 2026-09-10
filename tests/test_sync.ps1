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

# Modified file (content differs)
Set-Content (Join-Path $SourceDir "settings.json") '{"version": "1.0.0"}'
Set-Content (Join-Path $TargetDir "settings.json") '{"version": "2.0.0"}'

# Missing files & folders in target (present in source only, including a DLL)
Set-Content (Join-Path $SourceDir "missing_root.txt") "Missing root file"
New-Item -ItemType Directory (Join-Path $SourceDir "bin") -Force | Out-Null
Set-Content (Join-Path $SourceDir "bin\CustomLibrary.dll") "Binary DLL content 123"
New-Item -ItemType Directory (Join-Path $SourceDir "empty_folder") -Force | Out-Null

# Extra files & folders in target (present in target only, including an extra DLL)
Set-Content (Join-Path $TargetDir "extra_root.txt") "Extra root file in target"
New-Item -ItemType Directory (Join-Path $TargetDir "bin") -Force | Out-Null
Set-Content (Join-Path $TargetDir "bin\OldPlugin.dll") "Old binary plugin content"

# Excluded files (should be ignored)
New-Item -ItemType Directory (Join-Path $SourceDir ".git") -Force | Out-Null
Set-Content (Join-Path $SourceDir ".git\HEAD") "ref: refs/heads/main"
New-Item -ItemType Directory (Join-Path $TargetDir ".git") -Force | Out-Null
Set-Content (Join-Path $TargetDir ".git\HEAD") "ref: refs/heads/main"

# Config file for test specifying ReportsDir, ReportName, and NO bin/obj exclusion
@{
    SourcePath      = $SourceDir
    TargetPath      = $TargetDir
    BinPath         = $BinDir
    ReportsDir      = $ReportsFolder
    ReportName      = $ReportName
    DetectModified  = $true
    ExcludePatterns = @(".git")
} | ConvertTo-Json | Set-Content $TestConfig

Write-Host ">>> STEP 1: Running create_report.ps1..." -ForegroundColor Yellow
$CreateReportScript = Join-Path (Split-Path $PSScriptRoot -Parent) "create_report.ps1"
$MergeScript        = Join-Path (Split-Path $PSScriptRoot -Parent) "merge_changes.ps1"

& $CreateReportScript -ConfigFile $TestConfig

# Verify reports folder and files exist
$ExpectedMasterCsv   = Join-Path $ReportsFolder $ReportName
$ExpectedMissingCsv  = Join-Path $ReportsFolder "sync_report_missing.csv"
$ExpectedExtraCsv    = Join-Path $ReportsFolder "sync_report_extra.csv"
$ExpectedModifiedCsv = Join-Path $ReportsFolder "sync_report_modified.csv"
$ExpectedProcessCsv  = Join-Path $ReportsFolder "sync_report_process.csv"

if (-not (Test-Path $ExpectedMasterCsv))   { throw "TEST FAILED: Master report was not generated!" }
if (-not (Test-Path $ExpectedMissingCsv))  { throw "TEST FAILED: Missing report was not generated!" }
if (-not (Test-Path $ExpectedExtraCsv))    { throw "TEST FAILED: Extra report was not generated!" }
if (-not (Test-Path $ExpectedModifiedCsv)) { throw "TEST FAILED: Modified report was not generated!" }
if (-not (Test-Path $ExpectedProcessCsv))  { throw "TEST FAILED: Process report was not generated!" }

$ReportData = Import-Csv $ExpectedMasterCsv
Write-Host "Report rows count: $($ReportData.Count)"

$MissingEntries  = @($ReportData | Where-Object { $_.Category -eq "Missing" })
$ExtraEntries    = @($ReportData | Where-Object { $_.Category -eq "Extra" })
$ModifiedEntries = @($ReportData | Where-Object { $_.Category -eq "Modified" })

Write-Host "Detected Missing count  : $($MissingEntries.Count)"
Write-Host "Detected Extra count    : $($ExtraEntries.Count)"
Write-Host "Detected Modified count : $($ModifiedEntries.Count)"

# Check missing items including DLL
$MissingRelPaths = $MissingEntries.RelativePath
if ($MissingRelPaths -notcontains "missing_root.txt") { throw "TEST FAILED: missing_root.txt not in Missing list!" }
if ($MissingRelPaths -notcontains "bin\CustomLibrary.dll") { throw "TEST FAILED: bin\CustomLibrary.dll not in Missing list!" }
if ($MissingRelPaths -notcontains "empty_folder") { throw "TEST FAILED: empty_folder not in Missing list!" }

# Check extra items including DLL
$ExtraRelPaths = $ExtraEntries.RelativePath
if ($ExtraRelPaths -notcontains "extra_root.txt") { throw "TEST FAILED: extra_root.txt not in Extra list!" }
if ($ExtraRelPaths -notcontains "bin\OldPlugin.dll") { throw "TEST FAILED: bin\OldPlugin.dll not in Extra list!" }

# Check modified items
$ModifiedRelPaths = $ModifiedEntries.RelativePath
if ($ModifiedRelPaths -notcontains "settings.json") { throw "TEST FAILED: settings.json not in Modified list!" }

# Check that .git was excluded
if ($MissingRelPaths -match '\.git' -or $ExtraRelPaths -match '\.git') {
    throw "TEST FAILED: .git was not properly excluded!"
}

Write-Host ">>> STEP 2: Running merge_changes.ps1 in DRY-RUN mode..." -ForegroundColor Yellow
& $MergeScript -ConfigFile $TestConfig -DryRun

# Verify target has NOT changed yet
if (Test-Path (Join-Path $TargetDir "missing_root.txt")) {
    throw "TEST FAILED: DryRun modified files (missing_root.txt exists in target)!"
}
if (-not (Test-Path (Join-Path $TargetDir "extra_root.txt"))) {
    throw "TEST FAILED: DryRun removed files (extra_root.txt missing from target)!"
}

Write-Host ">>> STEP 3: Running merge_changes.ps1 LIVE with -Force..." -ForegroundColor Yellow
# Mark settings.json for processing as well
$ReportData | ForEach-Object {
    if ($_.Category -eq "Modified") { $_.Process = "Yes" }
}
$ReportData | Export-Csv $ExpectedMasterCsv -NoTypeInformation -Encoding UTF8

& $MergeScript -ConfigFile $TestConfig -Force

# Verify missing files are now present in target
if (-not (Test-Path (Join-Path $TargetDir "missing_root.txt"))) {
    throw "TEST FAILED: missing_root.txt was not copied to target!"
}
if (-not (Test-Path (Join-Path $TargetDir "bin\CustomLibrary.dll"))) {
    throw "TEST FAILED: bin\CustomLibrary.dll was not copied to target!"
}
if (-not (Test-Path (Join-Path $TargetDir "empty_folder"))) {
    throw "TEST FAILED: empty_folder was not created in target!"
}

# Verify extra files are removed from target
if (Test-Path (Join-Path $TargetDir "extra_root.txt")) {
    throw "TEST FAILED: extra_root.txt was not removed from target!"
}
if (Test-Path (Join-Path $TargetDir "bin\OldPlugin.dll")) {
    throw "TEST FAILED: bin\OldPlugin.dll was not removed from target!"
}

# Verify modified file was updated in target
$TargetSettings = Get-Content (Join-Path $TargetDir "settings.json") -Raw
if ($TargetSettings -notmatch "1.0.0") {
    throw "TEST FAILED: settings.json was not updated in target!"
}

# Verify extra and previous files are in bin
$BinItems = Get-ChildItem -LiteralPath $BinDir -Recurse -File
if ($BinItems.Count -eq 0) {
    throw "TEST FAILED: Items were not archived into BinDir!"
}
Write-Host "Bin files archived: $($BinItems.Name -join ', ')"

Write-Host ">>> STEP 4: Re-running create_report.ps1 to verify 0 differences..." -ForegroundColor Yellow
& $CreateReportScript -ConfigFile $TestConfig
$FinalReportData = Import-Csv $ExpectedMasterCsv
if ($FinalReportData.Count -ne 0) {
    throw "TEST FAILED: Differences still remain after merge! Count: $($FinalReportData.Count)"
}

Write-Host "`nAll Tests (Missing, Extra DLLs, Modified Files) Passed Successfully!" -ForegroundColor Green

# Cleanup
Remove-Item -LiteralPath $TestDir -Recurse -Force
