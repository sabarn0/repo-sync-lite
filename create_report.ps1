<#
.SYNOPSIS
    Compares two directories (Source and Target) and generates difference reports.

.DESCRIPTION
    Scans the source and target directory trees, identifies missing items (Source - Target)
    and extra items (Target - Source), and generates a structured report.csv along with
    convenience split CSVs (missing, extra, process).

.PARAMETER ConfigFile
    Path to configuration JSON file. Defaults to "config.json".

.PARAMETER Source
    Path to source directory. Overrides ConfigFile if provided.

.PARAMETER Target
    Path to target directory. Overrides ConfigFile if provided.

.PARAMETER Bin
    Path to temporary bin directory for extra items. Overrides ConfigFile if provided.

.PARAMETER OutputPath
    Filename for master CSV report. Defaults to "report.csv".

.EXAMPLE
    .\create_report.ps1
    .\create_report.ps1 -Source "C:\repoA" -Target "C:\repoB"
#>

[CmdletBinding()]
param (
    [string]$ConfigFile = "config.json",
    [string]$Source,
    [string]$Target,
    [string]$Bin,
    [string]$ReportsDir,
    [string]$ReportName,
    [string]$OutputPath
)

# Set strict mode and error handling
$ErrorActionPreference = "Stop"

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
        Write-Verbose "Loaded configuration from '$ConfigPath'"
    } catch {
        Write-Warning "Could not parse configuration file '$ConfigPath'. Using defaults/arguments."
    }
}

# Resolve parameters with precedence: Command argument > Config file > Default
$ResolvedSource     = if ($Source)     { $Source }     elseif ($Config.SourcePath) { $Config.SourcePath } else { "./source" }
$ResolvedTarget     = if ($Target)     { $Target }     elseif ($Config.TargetPath) { $Config.TargetPath } else { "./target" }
$ResolvedBin        = if ($Bin)        { $Bin }        elseif ($Config.BinPath)    { $Config.BinPath }    else { "./temp_bin" }
$ResolvedReportsDir = if ($ReportsDir) { $ReportsDir } elseif ($Config.ReportsDir) { $Config.ReportsDir } else { "./reports" }
$ResolvedReportName = if ($ReportName) { $ReportName } elseif ($Config.ReportName) { $Config.ReportName } else { "report.csv" }
$ExcludePatterns    = if ($Config.ExcludePatterns) { @($Config.ExcludePatterns) } else { @(".git", ".vs", "node_modules", "bin", "obj") }

$SourceFullPath = Resolve-FullPath -Path $ResolvedSource -BasePath $ScriptDir
$TargetFullPath = Resolve-FullPath -Path $ResolvedTarget -BasePath $ScriptDir
$BinFullPath    = Resolve-FullPath -Path $ResolvedBin -BasePath $ScriptDir

if ($OutputPath) {
    $ReportFullPath  = Resolve-FullPath -Path $OutputPath -BasePath $ScriptDir
    $ReportsFullPath = [System.IO.Path]::GetDirectoryName($ReportFullPath)
    $ReportBaseName  = [System.IO.Path]::GetFileNameWithoutExtension($ReportFullPath)
} else {
    $ReportsFullPath = Resolve-FullPath -Path $ResolvedReportsDir -BasePath $ScriptDir
    $ReportFullPath  = [System.IO.Path]::Combine($ReportsFullPath, $ResolvedReportName)
    $ReportBaseName  = [System.IO.Path]::GetFileNameWithoutExtension($ResolvedReportName)
}

# Ensure reports directory exists
if (-not (Test-Path -LiteralPath $ReportsFullPath)) {
    $null = New-Item -ItemType Directory -Path $ReportsFullPath -Force
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "             REPO SYNC LITE - REPORT              " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Source Path  : $SourceFullPath"
Write-Host "Target Path  : $TargetFullPath"
Write-Host "Bin Path     : $BinFullPath"
Write-Host "Reports Dir  : $ReportsFullPath"
Write-Host "Report File  : $ReportFullPath"
Write-Host "Exclusions   : $($ExcludePatterns -join ', ')"
Write-Host "--------------------------------------------------"

if (-not (Test-Path -LiteralPath $SourceFullPath)) {
    throw "Source directory does not exist: '$SourceFullPath'"
}
if (-not (Test-Path -LiteralPath $TargetFullPath)) {
    throw "Target directory does not exist: '$TargetFullPath'"
}

# Function to check if a path or relative path matches exclusion patterns
function Test-IsExcluded {
    param (
        [string]$RelativePath,
        [string[]]$Patterns
    )
    if (-not $Patterns -or $Patterns.Count -eq 0) { return $false }

    $Segments = $RelativePath.Split([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    foreach ($pattern in $Patterns) {
        # Check against each folder/file name segment
        foreach ($segment in $Segments) {
            if ($segment -like $pattern) {
                return $true
            }
        }
        # Also check against full relative path
        if ($RelativePath -like "*$pattern*" -or $RelativePath -like $pattern) {
            return $true
        }
    }
    return $false
}

# Scan a directory recursively and return hashtable of relative paths
function Get-RepoInventory {
    param (
        [string]$RootPath,
        [string[]]$Patterns
    )
    $Inventory = [ordered]@{}
    $RootUri = New-Object System.Uri(($RootPath.TrimEnd('\') + '\'))

    Write-Host "Scanning '$RootPath'..." -ForegroundColor Gray
    $Items = Get-ChildItem -LiteralPath $RootPath -Recurse -Force

    foreach ($item in $Items) {
        $ItemUri = New-Object System.Uri($item.FullName)
        $RelativeUri = $RootUri.MakeRelativeUri($ItemUri)
        $RelativePath = [System.Uri]::UnescapeDataString($RelativeUri.ToString()).Replace('/', '\')

        if (Test-IsExcluded -RelativePath $RelativePath -Patterns $Patterns) {
            continue
        }

        $Inventory[$RelativePath] = [PSCustomObject]@{
            Name         = $item.Name
            RelativePath = $RelativePath
            ItemType     = if ($item.PSIsContainer) { "Folder" } else { "File" }
            FullName     = $item.FullName
            Length       = if ($item.PSIsContainer) { 0 } else { $item.Length }
            LastWrite    = $item.LastWriteTime
        }
    }

    return $Inventory
}

$SourceInventory = Get-RepoInventory -RootPath $SourceFullPath -Patterns $ExcludePatterns
$TargetInventory = Get-RepoInventory -RootPath $TargetFullPath -Patterns $ExcludePatterns

Write-Host "Source scanned : $($SourceInventory.Count) items found."
Write-Host "Target scanned : $($TargetInventory.Count) items found."
Write-Host "Comparing differences..." -ForegroundColor Gray

$ReportEntries = [System.Collections.Generic.List[PSCustomObject]]::new()

# Missing: in Source but not in Target (Source - Target)
foreach ($relPath in $SourceInventory.Keys) {
    if (-not $TargetInventory.Contains($relPath)) {
        $sourceItem = $SourceInventory[$relPath]
        $expectedTargetPath = [System.IO.Path]::Combine($TargetFullPath, $relPath)
        $ReportEntries.Add([PSCustomObject]@{
            Category     = "Missing"
            ItemType     = $sourceItem.ItemType
            Name         = $sourceItem.Name
            RelativePath = $relPath
            SourcePath   = $sourceItem.FullName
            TargetPath   = $expectedTargetPath
            Action       = "Copy"
            Process      = "Yes"
        })
    }
}

# Extra: in Target but not in Source (Target - Source)
foreach ($relPath in $TargetInventory.Keys) {
    if (-not $SourceInventory.Contains($relPath)) {
        $targetItem = $TargetInventory[$relPath]
        $expectedSourcePath = [System.IO.Path]::Combine($SourceFullPath, $relPath)
        $ReportEntries.Add([PSCustomObject]@{
            Category     = "Extra"
            ItemType     = $targetItem.ItemType
            Name         = $targetItem.Name
            RelativePath = $relPath
            SourcePath   = $expectedSourcePath
            TargetPath   = $targetItem.FullName
            Action       = "MoveToBin"
            Process      = "Yes"
        })
    }
}

# Sort report entries by Category, ItemType (Folders first for missing, Files first for extra), RelativePath
$SortedEntries = $ReportEntries | Sort-Object Category, @{
    Expression = {
        if ($_.Category -eq "Missing") {
            if ($_.ItemType -eq "Folder") { 0 } else { 1 }
        } else {
            if ($_.ItemType -eq "File") { 0 } else { 1 }
        }
    }
}, RelativePath

# Export Master CSV
$SortedEntries | Export-Csv -LiteralPath $ReportFullPath -NoTypeInformation -Encoding UTF8

# Export Split CSVs (representing sheets: missing, extra, process)
$MissingReportPath = [System.IO.Path]::Combine($ReportsFullPath, "${ReportBaseName}_missing.csv")
$ExtraReportPath   = [System.IO.Path]::Combine($ReportsFullPath, "${ReportBaseName}_extra.csv")
$ProcessReportPath = [System.IO.Path]::Combine($ReportsFullPath, "${ReportBaseName}_process.csv")

($SortedEntries | Where-Object { $_.Category -eq "Missing" }) |
    Export-Csv -LiteralPath $MissingReportPath -NoTypeInformation -Encoding UTF8

($SortedEntries | Where-Object { $_.Category -eq "Extra" }) |
    Export-Csv -LiteralPath $ExtraReportPath -NoTypeInformation -Encoding UTF8

($SortedEntries | Where-Object { $_.Process -eq "Yes" }) |
    Export-Csv -LiteralPath $ProcessReportPath -NoTypeInformation -Encoding UTF8

# Summary counts
$MissingCount = @($SortedEntries | Where-Object { $_.Category -eq "Missing" }).Count
$MissingFiles = @($SortedEntries | Where-Object { $_.Category -eq "Missing" -and $_.ItemType -eq "File" }).Count
$MissingFolders = @($SortedEntries | Where-Object { $_.Category -eq "Missing" -and $_.ItemType -eq "Folder" }).Count

$ExtraCount   = @($SortedEntries | Where-Object { $_.Category -eq "Extra" }).Count
$ExtraFiles   = @($SortedEntries | Where-Object { $_.Category -eq "Extra" -and $_.ItemType -eq "File" }).Count
$ExtraFolders = @($SortedEntries | Where-Object { $_.Category -eq "Extra" -and $_.ItemType -eq "Folder" }).Count

Write-Host "--------------------------------------------------"
Write-Host "Difference Summary:" -ForegroundColor Green
Write-Host "  Missing (Source - Target) : $MissingCount ($MissingFiles files, $MissingFolders folders)" -ForegroundColor Yellow
Write-Host "  Extra   (Target - Source) : $ExtraCount ($ExtraFiles files, $ExtraFolders folders)" -ForegroundColor Magenta
Write-Host "  Total Differences         : $($SortedEntries.Count)"
Write-Host "--------------------------------------------------"
Write-Host "Generated Reports:" -ForegroundColor Cyan
Write-Host "  Master Report  : $ReportFullPath"
Write-Host "  Missing Sheet  : $MissingReportPath"
Write-Host "  Extra Sheet    : $ExtraReportPath"
Write-Host "  Process Sheet  : $ProcessReportPath"
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Review '$ReportFullPath' and adjust 'Action' or 'Process' before running merge_changes.ps1." -ForegroundColor White
