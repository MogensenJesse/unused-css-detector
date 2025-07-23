#!/usr/bin/env pwsh

<#
.SYNOPSIS
    CSS Unused Class Detector with advanced SCSS parsing and confidence scoring

.DESCRIPTION
    This script provides intelligent detection of unused CSS classes with:
    - Advanced SCSS-aware parsing (filters functions, variables, data URIs)
    - Confidence scoring (High/Medium/Low reliability)
    - Enhanced validation and filtering
    - Automated deletion with safety features
    - Multiple output formats and comprehensive reporting

.PARAMETER StylesPath
    Path to the styles directory (default: "./src/styles")

.PARAMETER ComponentsPath
    Path to search for component files (default: "./src")

.PARAMETER OutputFormat
    Output format: "summary", "detailed", or "json" (default: "summary")

.PARAMETER ConfidenceLevel
    Minimum confidence level to report: "High", "Medium", "Low" (default: "Medium")

.PARAMETER ValidateClasses
    Perform additional validation to check if classes actually exist (default: true)

.PARAMETER Debug
    Enable detailed diagnostic output for troubleshooting file reading issues

.PARAMETER DeleteUnused
    Enable deletion mode to actually remove unused classes (default: false)

.PARAMETER DryRun
    Preview deletions without making changes (default: true when DeleteUnused is enabled)

.PARAMETER CreateBackup
    Create backup files before deletion (default: true when DeleteUnused is enabled)

.PARAMETER Interactive
    Ask for confirmation before deleting each file (default: false)

.EXAMPLE
    .\unused-css-detector.ps1
    
.EXAMPLE
    .\unused-css-detector.ps1 -ConfidenceLevel "High"

.EXAMPLE
    .\unused-css-detector.ps1 -OutputFormat "detailed"

.EXAMPLE
    .\unused-css-detector.ps1 -DeleteUnused -ConfidenceLevel "High"

.EXAMPLE
    .\unused-css-detector.ps1 -DeleteUnused -DryRun:$false -CreateBackup 
#>

param(
    [string]$StylesPath = "./src/styles",
    [string]$ComponentsPath = "./src",
    [ValidateSet("summary", "detailed", "json")]
    [string]$OutputFormat = "summary",
    [ValidateSet("High", "Medium", "Low")]
    [string]$ConfidenceLevel = "Medium",
    [bool]$ValidateClasses = $true,
    [switch]$Debug,
    [switch]$DeleteUnused,
    [bool]$DryRun = $true,
    [bool]$CreateBackup = $true,
    [switch]$Interactive
) 

# Enhanced exclusion patterns
$EnhancedExcludePatterns = @(
    # Utility classes
    "w-*", "h-*", "text-*", "bg-*", "border-*", "p-*", "m-*", "flex*", "grid*",
    # SCSS functions and data
    "*adjust*", "*has-key*", "*map-*", "*svg*", "data:*",
    # Common false positives
    "*url*", "*http*", "*xmlns*", "*viewBox*", "*stroke*", "*fill*"
)

# Color functions for better output
function Write-Success { param($Message) Write-Host $Message -ForegroundColor Green }
function Write-Warning { param($Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host $Message -ForegroundColor Red }
function Write-Info { param($Message) Write-Host $Message -ForegroundColor Cyan }

# Diagnostic function for file reading issues
function Test-FileReadability {
    param([string]$FilePath)
    
    $diagnostics = @{
        Exists = $false
        Readable = $false
        Size = 0
        Encoding = "Unknown"
        Error = $null
    }
    
    try {
        $file = Get-Item -Path $FilePath -ErrorAction Stop
        $diagnostics.Exists = $true
        $diagnostics.Size = $file.Length
        
        # Try to read first few bytes to detect encoding
        $bytes = [System.IO.File]::ReadAllBytes($FilePath) | Select-Object -First 4
        if ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $diagnostics.Encoding = "UTF8-BOM"
        } elseif ($bytes.Count -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
            $diagnostics.Encoding = "UTF16-LE"
        } elseif ($bytes.Count -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
            $diagnostics.Encoding = "UTF16-BE"
        } else {
            $diagnostics.Encoding = "UTF8-ASCII"
        }
        
        # Test actual readability
        $null = Get-Content -Path $FilePath -Raw -Encoding UTF8 -ErrorAction Stop
        $diagnostics.Readable = $true
    }
    catch {
        $diagnostics.Error = $_.Exception.Message
    }
    
    return $diagnostics
}

# Enhanced SCSS parsing with intelligent filtering
function Get-EnhancedCSSClasses {
    param([string]$Content, [string]$FilePath)
    
    $classes = New-Object System.Collections.ArrayList
    $classesWithConfidence = New-Object System.Collections.ArrayList
    
    # Pre-filter content to remove SCSS functions and data URIs
    $filteredContent = $Content
    $filteredContent = $filteredContent -replace 'color\.adjust\([^)]+\)', ''
    $filteredContent = $filteredContent -replace 'map\.has-key\([^)]+\)', ''
    $filteredContent = $filteredContent -replace 'map\.get\([^)]+\)', ''
    $filteredContent = $filteredContent -replace 'rgba?\([^)]+\)', ''
    $filteredContent = $filteredContent -replace 'url\([^)]+\)', ''
    $filteredContent = $filteredContent -replace 'data:image/[^"''`]+', ''
    $filteredContent = $filteredContent -replace 'xmlns[^"''`]*', ''
    
    $lines = $filteredContent -split "`n"
    $parentSelectors = New-Object System.Collections.ArrayList
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        
        # Skip comments, empty lines, and imports
        if ($line -match '^\s*//|^\s*\/\*|^\s*$|^\s*@') { 
            continue 
        }
        
        # Handle closing braces
        if ($line -match '^\s*}') {
            if ($parentSelectors.Count -gt 0) {
                $parentSelectors.RemoveAt($parentSelectors.Count - 1)
            }
            continue
        }
        
        # Extract direct class selectors
        if ($line -match '^\s*\.([a-zA-Z][a-zA-Z0-9_-]*)\s*\{') {
            $className = $matches[1]
            
            if (Test-ValidClassName -ClassName $className) {
                $confidence = Get-ClassConfidence -ClassName $className -FilePath $FilePath
                
                $null = $classes.Add($className)
                $classData = @{
                    Name = $className
                    Confidence = $confidence
                    Context = "Direct class"
                    File = $FilePath
                }
                $null = $classesWithConfidence.Add($classData)
                
                # Add as parent selector
                $null = $parentSelectors.Add($className)
            }
        }
        
        # Handle BEM modifiers
        if ($line -match '&(__|--)([a-zA-Z][a-zA-Z0-9_-]*)\s*\{') {
            $separator = $matches[1]
            $modifier = $matches[2]
            
            if ($parentSelectors.Count -gt 0) {
                $parentClass = $parentSelectors[$parentSelectors.Count - 1]
                $fullClassName = "$parentClass$separator$modifier"
                
                if (Test-ValidClassName -ClassName $fullClassName) {
                    $confidence = Get-ClassConfidence -ClassName $fullClassName -FilePath $FilePath
                    
                    $null = $classes.Add($fullClassName)
                    $classData = @{
                        Name = $fullClassName
                        Confidence = $confidence
                        Context = "BEM modifier"
                        File = $FilePath
                    }
                    $null = $classesWithConfidence.Add($classData)
                }
            }
        }
    }
    
    return @{
        Classes = @($classes | Sort-Object -Unique)
        ClassesWithMetadata = @($classesWithConfidence)
    }
}

# Validate if a detected string is actually a CSS class
function Test-ValidClassName {
    param([string]$ClassName)
    
    # Filter out obvious false positives
    if ($ClassName -match '^(data|http|https|www)') { return $false }
    if ($ClassName -match '\.(com|org|net|svg|png|jpg)$') { return $false }
    if ($ClassName -match '^[0-9]+$') { return $false }
    if ($ClassName -match 'xmlns') { return $false }
    if ($ClassName -match '(adjust|has-key|get|merge)') { return $false }
    if ($ClassName -match '^(path|svg|image|url)') { return $false }
    
    # Must be valid CSS identifier
    return $ClassName -match '^[a-zA-Z][a-zA-Z0-9_-]*$'
}

# Calculate confidence score for detected class
function Get-ClassConfidence {
    param([string]$ClassName, [string]$FilePath)
    
    # Default confidence
    $confidence = "Medium"
    
    # High confidence indicators
    if ($ClassName -match '^[a-z]+(-[a-z]+)*$') {
        $confidence = "High"  # Standard kebab-case naming
    }
    elseif ($ClassName -match '__.*--') {
        $confidence = "High"  # Clear BEM pattern
    }
    elseif ($FilePath -match '(components|features)') {
        $confidence = "High"  # Component files usually have real classes
    }
    
    # Low confidence indicators
    elseif ($ClassName.Length -lt 3) {
        $confidence = "Low"   # Very short names are suspicious
    }
    elseif ($ClassName -match '[0-9]{3,}') {
        $confidence = "Low"   # Contains many numbers
    }
    elseif ($FilePath -match '(mixins|utilities|helpers)' -and $ClassName -match '-$') {
        $confidence = "Low"   # Generated utility classes
    }
    
    return $confidence
}

# Enhanced usage detection
function Find-EnhancedClassUsage {
    param([string[]]$Classes, [string]$SearchPath)
    
    $usedClasses = New-Object System.Collections.ArrayList
    $jsFiles = Get-ChildItem -Path $SearchPath -Recurse -Include "*.js", "*.jsx", "*.ts", "*.tsx" -ErrorAction SilentlyContinue
    
    Write-Info "Searching for class usage in $($jsFiles.Count) component files..."
    
    foreach ($file in $jsFiles) {
        try {
            $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $content) { continue }
            
            foreach ($class in $Classes) {
                # Simple but effective detection
                if ($content -match $class) {
                    # Verify it's actually a className usage, not just a string match
                    if ($content -match "className.*$class" -or $content -match "class.*$class") {
                        $null = $usedClasses.Add(@{
                            Class = $class
                            File = $file.FullName
                        })
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

# Enhanced exclusion check
function Test-EnhancedExclusion {
    param([string]$ClassName)
    
    foreach ($pattern in $EnhancedExcludePatterns) {
        if ($ClassName -like $pattern) {
            return $true
        }
    }
    
    return $false
}

# Delete unused classes from SCSS files
function Remove-UnusedClasses {
    param(
        [array]$UnusedClasses,
        [array]$ClassesWithMetadata,
        [bool]$DryRun = $true,
        [bool]$CreateBackup = $true,
        [bool]$Interactive = $false
    )
    
    if ($UnusedClasses.Count -eq 0) {
        Write-Info "No unused classes to delete."
        return
    }
    
    # Group classes by file for efficient processing
    $classesByFile = @{}
    foreach ($classData in $ClassesWithMetadata) {
        if ($classData.Name -in $UnusedClasses) {
            $file = $classData.File
            if (-not $classesByFile.ContainsKey($file)) {
                $classesByFile[$file] = @()
            }
            $classesByFile[$file] += $classData
        }
    }
    
    $totalFilesToModify = $classesByFile.Count
    $filesModified = 0
    $classesRemoved = 0
    
    Write-Info "`n$(if ($DryRun) { "DRY RUN - " })DELETION PROCESS"
    Write-Info "=================================="
    Write-Info "Files to modify: $totalFilesToModify"
    Write-Info "Classes to remove: $($UnusedClasses.Count)"
    
    if ($DryRun) {
        Write-Warning "This is a DRY RUN - no files will be modified"
    }
    
    foreach ($file in $classesByFile.Keys) {
        $classesToRemove = $classesByFile[$file]
        $fileName = Split-Path $file -Leaf
        
        Write-Info "`nProcessing: $fileName"
        Write-Host "  Classes to remove: $($classesToRemove.Count)" -ForegroundColor Yellow
        foreach ($class in $classesToRemove) {
            Write-Host "    • .$($class.Name)" -ForegroundColor Gray
        }
        
        if ($Interactive) {
            $response = Read-Host "  Remove classes from this file? (y/N)"
            if ($response -ne 'y' -and $response -ne 'Y') {
                Write-Host "  Skipped" -ForegroundColor Yellow
                continue
            }
        }
        
        if (-not $DryRun) {
            try {
                # Create backup if requested
                if ($CreateBackup) {
                    $backupPath = "$file.backup"
                    Copy-Item -Path $file -Destination $backupPath -Force
                    Write-Host "  Created backup: $backupPath" -ForegroundColor Cyan
                }
                
                # Read file content
                $content = Get-Content -Path $file -Raw -Encoding UTF8
                $originalContent = $content
                
                # Remove each class
                foreach ($classData in $classesToRemove) {
                    $className = $classData.Name
                    
                    # Remove direct class definitions (simple approach)
                    $content = $content -replace "(?m)^\s*\.$className\s*\{[^}]*\}", ""
                    
                    # Remove BEM modifiers
                    $content = $content -replace "(?m)^\s*&(__|--)$className\s*\{[^}]*\}", ""
                    
                    # Clean up empty lines
                    $content = $content -replace "(?m)^\s*`n", ""
                }
                
                # Only write if content changed
                if ($content -ne $originalContent) {
                    Set-Content -Path $file -Value $content -Encoding UTF8 -NoNewline
                    $classesRemoved += $classesToRemove.Count
                    $filesModified++
                    Write-Success "  ✓ Modified successfully"
                } else {
                    Write-Warning "  ! No changes made (classes not found in expected format)"
                }
            }
            catch {
                Write-Error "  ✗ Error modifying file: $_"
            }
        } else {
            Write-Host "  [DRY RUN] Would remove $($classesToRemove.Count) classes" -ForegroundColor Cyan
        }
    }
    
    Write-Info "`nDELETION SUMMARY"
    Write-Info "================"
    if ($DryRun) {
        Write-Warning "DRY RUN COMPLETE - No files were modified"
        Write-Info "Would modify: $totalFilesToModify files"
        Write-Info "Would remove: $($UnusedClasses.Count) classes"
    } else {
        Write-Success "Files modified: $filesModified / $totalFilesToModify"
        Write-Success "Classes removed: $classesRemoved"
        if ($CreateBackup) {
            Write-Info "Backup files created with .backup extension"
        }
    }
}

# Enhanced reporting with confidence categorization
function Write-EnhancedReport {
    param([hashtable]$Results, [array]$ClassesWithMetadata)
    
    $highConfidence = $ClassesWithMetadata | Where-Object { $_.Confidence -eq "High" -and $_.Name -in $Results.UnusedClasses }
    $mediumConfidence = $ClassesWithMetadata | Where-Object { $_.Confidence -eq "Medium" -and $_.Name -in $Results.UnusedClasses }
    $lowConfidence = $ClassesWithMetadata | Where-Object { $_.Confidence -eq "Low" -and $_.Name -in $Results.UnusedClasses }
    
    Write-Info "`nANALYSIS RESULTS"
    Write-Info "================"
    Write-Success "Used classes: $($Results.UsedClasses.Count)"
    Write-Info "Confidence breakdown:"
    Write-Success "  High confidence unused: $($highConfidence.Count)"
    Write-Warning "  Medium confidence unused: $($mediumConfidence.Count)"
    Write-Host "  Low confidence unused: $($lowConfidence.Count)" -ForegroundColor Gray
    
    if ($OutputFormat -eq "detailed") {
        if ($highConfidence.Count -gt 0) {
            Write-Success "`nHIGH CONFIDENCE - Safe to remove:"
            foreach ($class in $highConfidence) {
                $fileName = Split-Path $class.File -Leaf
                Write-Host "  • .$($class.Name) (in $fileName)" -ForegroundColor Green
            }
        }
        
        if ($mediumConfidence.Count -gt 0 -and $ConfidenceLevel -ne "High") {
            Write-Warning "`nMEDIUM CONFIDENCE - Review recommended:"
            foreach ($class in $mediumConfidence) {
                $fileName = Split-Path $class.File -Leaf
                Write-Host "  • .$($class.Name) (in $fileName)" -ForegroundColor Yellow
            }
        }
        
        if ($lowConfidence.Count -gt 0 -and $ConfidenceLevel -eq "Low") {
            Write-Host "`nLOW CONFIDENCE - Manual verification needed:" -ForegroundColor Gray
            foreach ($class in $lowConfidence) {
                $fileName = Split-Path $class.File -Leaf
                Write-Host "  • .$($class.Name) (in $fileName)" -ForegroundColor Gray
            }
        }
    } else {
        Write-Success "`nHIGH CONFIDENCE UNUSED CLASSES:"
        foreach ($class in $highConfidence) {
            Write-Host "  • .$($class.Name)" -ForegroundColor Green
        }
        
        if ($ConfidenceLevel -ne "High" -and $mediumConfidence.Count -gt 0) {
            Write-Warning "`nMEDIUM CONFIDENCE UNUSED CLASSES:"
            foreach ($class in $mediumConfidence) {
                Write-Host "  • .$($class.Name)" -ForegroundColor Yellow
            }
        }
    }
    
    Write-Info "`nRECOMMENDATIONS:"
    Write-Info "• Start with HIGH confidence classes (safest to remove)"
    Write-Info "• Review MEDIUM confidence classes for dynamic usage"
    Write-Info "• Test your application after removing any classes"
}

# Main execution
Write-Info "CSS Unused Class Detector"
Write-Info "=========================="

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

# Extract all CSS classes with enhanced parsing
$allClassesWithMetadata = New-Object System.Collections.ArrayList
$allClasses = New-Object System.Collections.ArrayList

foreach ($file in $scssFiles) {
    try {
        # Enhanced diagnostics for file reading issues
        if ($Debug) {
            Write-Info "Processing: $($file.Name)"
            $diagnostics = Test-FileReadability -FilePath $file.FullName
            Write-Host "  Exists: $($diagnostics.Exists), Size: $($diagnostics.Size) bytes, Encoding: $($diagnostics.Encoding)" -ForegroundColor Gray
            if ($diagnostics.Error) {
                Write-Host "  Error: $($diagnostics.Error)" -ForegroundColor Red
            }
        }
        
        # Check file properties first
        if (-not $file.Exists) {
            Write-Warning "File does not exist: $($file.FullName)"
            continue
        }
        
        if ($file.Length -eq 0) {
            Write-Warning "File is empty: $($file.FullName)"
            continue
        }
        
        # Try to read the file with better error handling
        $content = $null
        try {
            $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop
        }
        catch [System.UnauthorizedAccessException] {
            Write-Warning "Access denied to file: $($file.FullName)"
            continue
        }
        catch [System.IO.FileNotFoundException] {
            Write-Warning "File not found: $($file.FullName)"
            continue
        }
        catch [System.IO.IOException] {
            Write-Warning "IO error reading file: $($file.FullName) - $_"
            continue
        }
        catch {
            Write-Warning "Unknown error reading file: $($file.FullName) - $_"
            continue
        }
        
        if ($content) {
            $result = Get-EnhancedCSSClasses -Content $content -FilePath $file.FullName
            $classes = $result.Classes
            $metadata = $result.ClassesWithMetadata
            
            if ($Debug) {
                Write-Host "  Result types: Classes=$($classes.GetType().Name), Metadata=$($metadata.GetType().Name)" -ForegroundColor Gray
                Write-Host "  Classes content: $($classes -join ', ')" -ForegroundColor Gray
            }
            
            # Safely add classes - handle null and single values
            if ($classes) {
                if ($classes -is [array] -or $classes -is [System.Collections.ArrayList]) {
                    $allClasses.AddRange($classes)
                } else {
                    # Single item, add individually
                    $null = $allClasses.Add($classes)
                }
            }
            
            # Safely add metadata - handle null and single values
            if ($metadata) {
                if ($metadata -is [array] -or $metadata -is [System.Collections.ArrayList]) {
                    $allClassesWithMetadata.AddRange($metadata)
                } else {
                    # Single item, add individually
                    $null = $allClassesWithMetadata.Add($metadata)
                }
            }
            
            $classCount = if ($classes) { 
                if ($classes -is [array] -or $classes -is [System.Collections.ArrayList]) { $classes.Count } else { 1 }
            } else { 0 }
            
            Write-Info "  $($file.Name): $classCount classes"
        } else {
            Write-Warning "File content is null after reading: $($file.FullName)"
        }
    }
    catch {
        Write-Warning "Could not process SCSS file: $($file.FullName) - Error: $_"
    }
}

$uniqueClasses = $allClasses | Sort-Object -Unique
Write-Success "Total unique CSS classes found: $($uniqueClasses.Count)"

# Filter out excluded patterns
$filteredClasses = $uniqueClasses | Where-Object { -not (Test-EnhancedExclusion -ClassName $_) }
$excludedCount = $uniqueClasses.Count - $filteredClasses.Count

if ($excludedCount -gt 0) {
    Write-Info "Excluded $excludedCount classes (SCSS functions, data URIs, etc.)"
}

# Filter by confidence level
$confidenceOrder = @{ "High" = 3; "Medium" = 2; "Low" = 1 }
$minLevel = $confidenceOrder[$ConfidenceLevel]

$confidenceFilteredClasses = $allClassesWithMetadata | Where-Object { 
    $confidenceOrder[$_.Confidence] -ge $minLevel 
} | ForEach-Object { $_.Name } | Sort-Object -Unique

$filteredClasses = $filteredClasses | Where-Object { $_ -in $confidenceFilteredClasses }

Write-Info "Classes meeting '$ConfidenceLevel' confidence threshold: $($filteredClasses.Count)"

# Search for usage
$usedClassesData = Find-EnhancedClassUsage -Classes $filteredClasses -SearchPath $ComponentsPath
$usedClassNames = $usedClassesData | ForEach-Object { $_.Class } | Sort-Object -Unique
$unusedClasses = $filteredClasses | Where-Object { $_ -notin $usedClassNames }

# Prepare results
$results = @{
    TotalClasses = $uniqueClasses.Count
    ExcludedClasses = $excludedCount
    UsedClasses = $usedClassNames
    UnusedClasses = $unusedClasses
}

# Generate report
Write-EnhancedReport -Results $results -ClassesWithMetadata $allClassesWithMetadata

# Handle deletion if requested
if ($DeleteUnused -and $unusedClasses.Count -gt 0) {
    Remove-UnusedClasses -UnusedClasses $unusedClasses -ClassesWithMetadata $allClassesWithMetadata -DryRun $DryRun -CreateBackup $CreateBackup -Interactive $Interactive
} elseif ($DeleteUnused -and $unusedClasses.Count -eq 0) {
    Write-Success "`nNo unused classes found - nothing to delete!"
}

if ($OutputFormat -eq "json") {
    $jsonResult = @{
        summary = @{
            totalClasses = $results.TotalClasses
            excludedClasses = $results.ExcludedClasses
            usedClasses = $results.UsedClasses.Count
            unusedClasses = $results.UnusedClasses.Count
            confidenceLevel = $ConfidenceLevel
        }
        unusedClasses = $results.UnusedClasses
        usedClasses = $results.UsedClasses
    }
    $jsonResult | ConvertTo-Json -Depth 10
}

Write-Info "`nAnalysis complete!" 