#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Detects unused CSS classes in a Next.js project

.DESCRIPTION
    This script scans SCSS files to extract CSS class names and then searches
    JavaScript/JSX files to determine which classes are actually used.
    It handles BEM naming conventions and nested SCSS structures.

.PARAMETER StylesPath
    Path to the styles directory (default: "./src/styles")

.PARAMETER ComponentsPath
    Path to search for component files (default: "./src")

.PARAMETER ExcludePatterns
    Array of patterns to exclude from usage search (default: common utility classes)

.PARAMETER OutputFormat
    Output format: "summary", "detailed", or "json" (default: "summary")

.PARAMETER DeleteUnused
    Actually delete unused CSS classes from files (default: false)

.PARAMETER DryRun
    Show what would be deleted without actually deleting (default: true when DeleteUnused is true)

.PARAMETER CreateBackup
    Create backup copies of files before deletion (default: true when DeleteUnused is true)

.PARAMETER Interactive
    Ask for confirmation before deleting each file (default: false)

.EXAMPLE
    .\unused-css-detector.ps1
    
.EXAMPLE
    .\unused-css-detector.ps1 -StylesPath "./styles" -ComponentsPath "./components" -OutputFormat "detailed"

.EXAMPLE
    .\unused-css-detector.ps1 -DeleteUnused -DryRun:$false -CreateBackup

.EXAMPLE
    .\unused-css-detector.ps1 -DeleteUnused -Interactive
#>

param(
    [string]$StylesPath = "./src/styles",
    [string]$ComponentsPath = "./src",
    [string[]]$ExcludePatterns = @("w-*", "h-*", "text-*", "bg-*", "border-*", "p-*", "m-*", "flex*", "grid*"),
    [ValidateSet("summary", "detailed", "json")]
    [string]$OutputFormat = "summary",
    [switch]$DeleteUnused,
    [bool]$DryRun = $true,
    [bool]$CreateBackup = $true,
    [switch]$Interactive
)

# Color functions for better output
function Write-Success { param($Message) Write-Host $Message -ForegroundColor Green }
function Write-Warning { param($Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host $Message -ForegroundColor Red }
function Write-Info { param($Message) Write-Host $Message -ForegroundColor Cyan }

# Function to extract CSS classes from SCSS content
function Get-CSSClassesFromSCSS {
    param([string]$Content, [string]$FilePath)
    
    $classes = @()
    $lines = $Content -split "`n"
    $parentSelectors = @()
    $indentLevel = 0
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        
        # Skip comments and empty lines
        if ($line -match '^\s*//|^\s*\/\*|^\s*$') { continue }
        
        # Calculate indent level for nested structure
        $currentIndent = ($lines[$i] -replace '[^\s].*$', '').Length
        
        # Handle closing braces - pop parent selectors
        if ($line -match '^\s*}') {
            if ($parentSelectors.Count -gt 0) {
                $parentSelectors = $parentSelectors | Select-Object -First ($parentSelectors.Count - 1)
            }
            continue
        }
        
        # Extract direct class selectors
        if ($line -match '\.([a-zA-Z][a-zA-Z0-9_-]*)\s*\{?') {
            $className = $matches[1]
            $classes += $className
            
            # If this starts a block, add as parent selector
            if ($line -match '\{' -or ($i + 1 -lt $lines.Count -and $lines[$i + 1] -match '^\s*[\.&]')) {
                $parentSelectors += $className
            }
        }
        
        # Handle BEM modifiers (&__element, &--modifier)
        if ($line -match '&(__|--)([a-zA-Z][a-zA-Z0-9_-]*)\s*\{?') {
            $separator = $matches[1]
            $modifier = $matches[2]
            
            # Construct full class name with current parent
            if ($parentSelectors.Count -gt 0) {
                $parentClass = $parentSelectors[-1]
                $fullClassName = "$parentClass$separator$modifier"
                $classes += $fullClassName
            }
        }
        
        # Handle nested selectors with parent reference
        if ($line -match '&\.([a-zA-Z][a-zA-Z0-9_-]*)\s*\{?') {
            $nestedClass = $matches[1]
            if ($parentSelectors.Count -gt 0) {
                $parentClass = $parentSelectors[-1]
                $classes += $nestedClass  # The nested class itself
            }
        }
    }
    
    return $classes | Sort-Object -Unique
}

# Function to search for CSS class usage in JavaScript/JSX files
function Find-ClassUsageInFiles {
    param([string[]]$Classes, [string]$SearchPath)
    
    $usedClasses = @()
    $jsFiles = Get-ChildItem -Path $SearchPath -Recurse -Include "*.js", "*.jsx", "*.ts", "*.tsx" -ErrorAction SilentlyContinue
    
    Write-Info "Searching for class usage in $($jsFiles.Count) JavaScript/TypeScript files..."
    
    foreach ($file in $jsFiles) {
        try {
            $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $content) { continue }
            
            foreach ($class in $Classes) {
                # Simple check: does the class name appear anywhere in the file?
                if ($content -match [regex]::Escape($class)) {
                    $usedClasses += @{
                        Class = $class
                        File = $file.FullName
                        Context = "Found in file"
                    }
                }
            }
        }
        catch {
            Write-Warning "Could not read file: $($file.FullName)"
        }
    }
    
    return $usedClasses
}

# Function to check if a class should be excluded
function Test-ExcludeClass {
    param([string]$ClassName, [string[]]$ExcludePatterns)
    
    foreach ($pattern in $ExcludePatterns) {
        if ($ClassName -like $pattern) {
            return $true
        }
    }
    return $false
}

# Function to create backup of a file
function New-FileBackup {
    param([string]$FilePath)
    
    try {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupPath = "$FilePath.backup_$timestamp"
        Copy-Item -Path $FilePath -Destination $backupPath -Force
        return $backupPath
    }
    catch {
        Write-Warning "Failed to create backup for ${FilePath}: $($_.Exception.Message)"
        return $null
    }
}

# Function to remove unused CSS classes from SCSS content
function Remove-UnusedCSSFromContent {
    param([string]$Content, [string[]]$UnusedClasses, [string]$FilePath)
    
    $lines = $Content -split "`n"
    $newLines = @()
    $skipBlock = $false
    $currentBlockClass = ""
    $blockStartLine = -1
    $braceCount = 0
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $trimmedLine = $line.Trim()
        
        # Check if this line starts a CSS class block that should be removed
        if ($trimmedLine -match '\.([a-zA-Z][a-zA-Z0-9_-]*)\s*\{?') {
            $className = $matches[1]
            if ($className -in $UnusedClasses) {
                $skipBlock = $true
                $currentBlockClass = $className
                $blockStartLine = $i
                $braceCount = 0
                
                # Count opening braces in this line
                $braceCount += ($line -split '\{', 0, "SimpleMatch").Count - 1
                
                # If there's no opening brace, look ahead for it
                if ($braceCount -eq 0) {
                    for ($j = $i + 1; $j -lt [Math]::Min($i + 3, $lines.Count); $j++) {
                        if ($lines[$j] -match '\{') {
                            $braceCount += ($lines[$j] -split '\{', 0, "SimpleMatch").Count - 1
                            break
                        }
                    }
                }
                
                continue  # Skip this line
            }
        }
        
        # Handle BEM modifiers and nested selectors
        if ($skipBlock -eq $false -and $trimmedLine -match '&(__|--)([a-zA-Z][a-zA-Z0-9_-]*)\s*\{?') {
            $separator = $matches[1]
            $modifier = $matches[2]
            $fullClassName = "$currentBlockClass$separator$modifier"
            
            if ($fullClassName -in $UnusedClasses) {
                $skipBlock = $true
                $braceCount = 0
                $braceCount += ($line -split '\{', 0, "SimpleMatch").Count - 1
                continue  # Skip this line
            }
        }
        
        # If we're skipping a block, track braces to know when to stop
        if ($skipBlock) {
            # Count braces in current line
            $openBraces = ($line -split '\{', 0, "SimpleMatch").Count - 1
            $closeBraces = ($line -split '\}', 0, "SimpleMatch").Count - 1
            
            $braceCount += $openBraces - $closeBraces
            
            # If braces are balanced, we've reached the end of the block
            if ($braceCount -le 0) {
                $skipBlock = $false
                $currentBlockClass = ""
            }
            continue  # Skip this line
        }
        
        # Add the line if we're not skipping
        $newLines += $line
    }
    
    # Clean up empty lines (remove multiple consecutive empty lines)
    $cleanedLines = @()
    $emptyLineCount = 0
    
    foreach ($line in $newLines) {
        if ($line.Trim() -eq "") {
            $emptyLineCount++
            if ($emptyLineCount -le 2) {  # Allow max 2 consecutive empty lines
                $cleanedLines += $line
            }
        } else {
            $emptyLineCount = 0
            $cleanedLines += $line
        }
    }
    
    return $cleanedLines -join "`n"
}

# Function to delete unused classes from files
function Remove-UnusedCSSClasses {
    param(
        [hashtable]$ClassesByFile,
        [string[]]$UnusedClasses,
        [bool]$DryRun,
        [bool]$CreateBackup,
        [bool]$Interactive
    )
    
    $deletionResults = @{
        FilesModified = 0
        ClassesRemoved = 0
        BackupsCreated = @()
        Errors = @()
    }
    
    Write-Info "`n🗑️ DELETION PROCESS"
    Write-Info "=================="
    
    if ($DryRun) {
        Write-Warning "DRY RUN MODE - No files will be modified"
    }
    
    foreach ($file in $ClassesByFile.Keys) {
        $fileUnusedClasses = $ClassesByFile[$file] | Where-Object { $_ -in $UnusedClasses }
        
        if ($fileUnusedClasses.Count -eq 0) {
            continue  # No unused classes in this file
        }
        
        $relativePath = (Resolve-Path -Path $file -Relative -ErrorAction SilentlyContinue) -replace '^\.[\\/]', ''
        if (-not $relativePath) { $relativePath = $file }
        
        Write-Host "`n📄 Processing: $relativePath" -ForegroundColor Cyan
        Write-Host "   Classes to remove: $($fileUnusedClasses.Count)" -ForegroundColor Yellow
        $fileUnusedClasses | ForEach-Object { Write-Host "   - .$_" -ForegroundColor Red }
        
        # Interactive confirmation
        if ($Interactive -and -not $DryRun) {
            $response = Read-Host "   Remove these classes from this file? (y/N)"
            if ($response -ne 'y' -and $response -ne 'Y') {
                Write-Host "   Skipped by user" -ForegroundColor Gray
                continue
            }
        }
        
        if (-not $DryRun) {
            try {
                # Create backup if requested
                if ($CreateBackup) {
                    $backupPath = New-FileBackup -FilePath $file
                    if ($backupPath) {
                        $deletionResults.BackupsCreated += $backupPath
                        Write-Info "   ✅ Backup created: $backupPath"
                    }
                }
                
                # Read current content
                $currentContent = Get-Content -Path $file -Raw -ErrorAction Stop
                
                # Remove unused classes
                $newContent = Remove-UnusedCSSFromContent -Content $currentContent -UnusedClasses $fileUnusedClasses -FilePath $file
                
                # Write back to file
                Set-Content -Path $file -Value $newContent -NoNewline -ErrorAction Stop
                
                $deletionResults.FilesModified++
                $deletionResults.ClassesRemoved += $fileUnusedClasses.Count
                
                Write-Success "   ✅ Removed $($fileUnusedClasses.Count) unused classes"
            }
            catch {
                $errorMsg = "Failed to process ${relativePath}: " + $_.Exception.Message
                $deletionResults.Errors += $errorMsg
                Write-Error "   ❌ $errorMsg"
            }
        } else {
            Write-Info "   [DRY RUN] Would remove $($fileUnusedClasses.Count) classes"
        }
    }
    
    return $deletionResults
}

# Main execution
Write-Info "CSS Unused Class Detector"
Write-Info "========================="

# Validate paths
if (-not (Test-Path $StylesPath)) {
    Write-Error "Styles path not found: $StylesPath"
    exit 1
}

if (-not (Test-Path $ComponentsPath)) {
    Write-Error "Components path not found: $ComponentsPath"
    exit 1
}

# Find all SCSS files
Write-Info "Scanning SCSS files in: $StylesPath"
$scssFiles = Get-ChildItem -Path $StylesPath -Recurse -Include "*.scss", "*.sass" -ErrorAction SilentlyContinue

if ($scssFiles.Count -eq 0) {
    Write-Error "No SCSS files found in $StylesPath"
    exit 1
}

Write-Success "Found $($scssFiles.Count) SCSS files"

# Extract all CSS classes
$allClasses = @()
$classesByFile = @{}

foreach ($file in $scssFiles) {
    try {
        $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($content) {
            $classes = Get-CSSClassesFromSCSS -Content $content -FilePath $file.FullName
            $allClasses += $classes
            $classesByFile[$file.FullName] = $classes
            Write-Info "  $($file.Name): $($classes.Count) classes"
        }
    }
    catch {
        Write-Warning "Could not read SCSS file: $($file.FullName)"
    }
}

$uniqueClasses = $allClasses | Sort-Object -Unique
Write-Success "Total unique CSS classes found: $($uniqueClasses.Count)"

# Filter out excluded patterns
$filteredClasses = $uniqueClasses | Where-Object { -not (Test-ExcludeClass -ClassName $_ -ExcludePatterns $ExcludePatterns) }
$excludedCount = $uniqueClasses.Count - $filteredClasses.Count

if ($excludedCount -gt 0) {
    Write-Info "Excluded $excludedCount classes matching patterns: $($ExcludePatterns -join ', ')"
}

# Search for usage
Write-Info "Searching for class usage in: $ComponentsPath"
$usedClassesData = Find-ClassUsageInFiles -Classes $filteredClasses -SearchPath $ComponentsPath

$usedClassNames = $usedClassesData | ForEach-Object { $_.Class } | Sort-Object -Unique
$unusedClasses = $filteredClasses | Where-Object { $_ -notin $usedClassNames }

# Handle deletion parameters
if ($DeleteUnused) {
    # Override DryRun default when DeleteUnused is specified
    if ($PSBoundParameters.ContainsKey('DryRun') -eq $false) {
        $DryRun = $true  # Default to dry run for safety
    }
}

# Output results
Write-Info "`nRESULTS"
Write-Info "======="
Write-Success "Used classes: $($usedClassNames.Count)"
Write-Warning "Unused classes: $($unusedClasses.Count)"

if ($unusedClasses.Count -gt 0) {
    # Perform deletion if requested
    if ($DeleteUnused) {
        # Safety confirmation for non-dry-run deletion
        if (-not $DryRun -and -not $Interactive) {
            Write-Warning "`n⚠️  DANGER: You are about to delete $($unusedClasses.Count) CSS classes from $($classesByFile.Keys.Count) files!"
            Write-Warning "This action cannot be easily undone (except from backups)."
            $confirmation = Read-Host "Are you sure you want to proceed? Type 'DELETE' to confirm"
            
            if ($confirmation -ne 'DELETE') {
                Write-Info "Deletion cancelled by user."
                exit 0
            }
        }
        
        # Perform the deletion
        $deletionResults = Remove-UnusedCSSClasses -ClassesByFile $classesByFile -UnusedClasses $unusedClasses -DryRun $DryRun -CreateBackup $CreateBackup -Interactive $Interactive
        
        # Report deletion results
        Write-Info "`n📊 DELETION SUMMARY"
        Write-Info "=================="
        
        if ($DryRun) {
            Write-Warning "DRY RUN COMPLETED - No files were modified"
        } else {
            Write-Success "Files modified: $($deletionResults.FilesModified)"
            Write-Success "Classes removed: $($deletionResults.ClassesRemoved)"
            
            if ($deletionResults.BackupsCreated.Count -gt 0) {
                Write-Info "Backups created: $($deletionResults.BackupsCreated.Count)"
                $deletionResults.BackupsCreated | ForEach-Object {
                    Write-Info "  - $_"
                }
            }
            
            if ($deletionResults.Errors.Count -gt 0) {
                Write-Warning "Errors encountered: $($deletionResults.Errors.Count)"
                $deletionResults.Errors | ForEach-Object {
                    Write-Warning "  - $_"
                }
            }
        }
    } else {
        # Original output logic when not deleting
        switch ($OutputFormat) {
            "detailed" {
                Write-Warning "`nUNUSED CLASSES (by file):"
                
                foreach ($file in $classesByFile.Keys) {
                    $fileUnusedClasses = $classesByFile[$file] | Where-Object { $_ -in $unusedClasses }
                    if ($fileUnusedClasses.Count -gt 0) {
                        $relativePath = (Resolve-Path -Path $file -Relative) -replace '^\.[\\/]', ''
                        Write-Host "`n$relativePath" -ForegroundColor Magenta
                        $fileUnusedClasses | ForEach-Object {
                            Write-Host "   - .$_" -ForegroundColor Red
                        }
                    }
                }
            }
            "json" {
                $result = @{
                    summary = @{
                        totalClasses = $uniqueClasses.Count
                        excludedClasses = $excludedCount
                        usedClasses = $usedClassNames.Count
                        unusedClasses = $unusedClasses.Count
                    }
                    unusedClasses = $unusedClasses
                    usedClasses = $usedClassNames
                    classesByFile = $classesByFile
                }
                $result | ConvertTo-Json -Depth 10
            }
            default {
                Write-Warning "`nUNUSED CLASSES:"
                $unusedClasses | ForEach-Object {
                    Write-Host "   - .$_" -ForegroundColor Red
                }
            }
        }
        
        Write-Info "`nTIP: Review these classes before deletion. Some might be:"
        Write-Info "   - Used in dynamic class generation"
        Write-Info "   - Applied via CSS-in-JS libraries"
        Write-Info "   - Reserved for future features"
        Write-Info "   - Used in HTML templates or external files"
        
        Write-Info "`n🔧 TO DELETE UNUSED CLASSES:"
        Write-Info "   # Dry run (safe preview):"
        Write-Info "   .\scripts\unused-css-detector.ps1 -DeleteUnused"
        Write-Info ""
        Write-Info "   # Actually delete with backups:"
        Write-Info "   .\scripts\unused-css-detector.ps1 -DeleteUnused -DryRun:`$false -CreateBackup"
        Write-Info ""
        Write-Info "   # Interactive deletion:"
        Write-Info "   .\scripts\unused-css-detector.ps1 -DeleteUnused -DryRun:`$false -Interactive"
    }
} else {
    Write-Success "`nNo unused CSS classes found! Your styles are clean."
}

Write-Info "`nAnalysis complete!" 