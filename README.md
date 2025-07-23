# CSS Unused Class Detector

A powerful PowerShell script to detect and clean up unused CSS classes in your Next.js/React projects with advanced SCSS parsing, confidence scoring, and intelligent filtering.

## 🚀 **Quick Start**

```powershell
# Basic unused class detection
.\scripts\unused-css-detector.ps1

# Enhanced detection with confidence scoring
.\scripts\unused-css-detector.ps1 -ConfidenceLevel "High"
```

## 🛠️ **Features**

- 🔍 **Advanced SCSS Parsing**: Handles BEM naming, nested selectors, filters functions/URIs
- 🎯 **Confidence Scoring**: High/Medium/Low reliability ratings  
- 🧹 **Intelligent Filtering**: Filters SCSS functions, data URIs, false positives
- 📊 **Categorized Results**: Results grouped by confidence level
- ✅ **Class Validation**: Verifies classes actually exist in files
- 🗑️ **Automated Deletion**: Safely remove unused classes with backups
- 📊 **Multiple Output Formats**: Summary, detailed, JSON
- 🛡️ **Safety Features**: Dry-run, backups, confirmations
- 🔍 **Enhanced Detection**: Multiple detection strategies with context awareness

## 📋 **Usage**

### Basic Analysis
```powershell
# Quick analysis with default settings
.\scripts\unused-css-detector.ps1

# Detailed breakdown by file
.\scripts\unused-css-detector.ps1 -OutputFormat "detailed"

# JSON output for automation/CI
.\scripts\unused-css-detector.ps1 -OutputFormat "json"
```

### Confidence-Based Analysis
```powershell
# High confidence only (safest results)
.\scripts\unused-css-detector.ps1 -ConfidenceLevel "High"

# Medium confidence with detailed breakdown
.\scripts\unused-css-detector.ps1 -ConfidenceLevel "Medium" -OutputFormat "detailed"

# Include low confidence results (comprehensive scan)
.\scripts\unused-css-detector.ps1 -ConfidenceLevel "Low"
```

#### Confidence Levels Explained

**🟢 High Confidence** (Safest to remove)
- Standard kebab-case naming (`.my-component`)
- Clear BEM patterns (`.block__element--modifier`)
- Classes in component files
- Direct class definitions with proper syntax

**🟡 Medium Confidence** (Review recommended)  
- Default confidence level
- Most standard class definitions
- Classes that pass validation

**🔴 Low Confidence** (Manual verification needed)
- Very short class names (< 3 characters)
- Classes with many numbers
- Generated utility classes in mixin files
- Potentially dynamic classes

### Safe Deletion
```powershell
# Preview what would be deleted (dry run)
.\scripts\unused-css-detector.ps1 -DeleteUnused

# Actually delete with automatic backups
.\scripts\unused-css-detector.ps1 -DeleteUnused -DryRun:$false -CreateBackup

# Interactive deletion (confirm each file)
.\scripts\unused-css-detector.ps1 -DeleteUnused -DryRun:$false -Interactive
```

### Troubleshooting & Debug
```powershell
# Enable debug output for troubleshooting
.\scripts\unused-css-detector.ps1 -Debug

# Combined: high confidence with debug output
.\scripts\unused-css-detector.ps1 -ConfidenceLevel "High" -Debug -OutputFormat "detailed"
```

### Recommended Workflow

1. **Start Safe**: Begin with high confidence analysis
   ```powershell
   .\scripts\unused-css-detector.ps1 -ConfidenceLevel "High" -OutputFormat "detailed"
   ```

2. **Review Results**: Manually verify a few classes before proceeding

3. **Delete Safely**: Use dry-run first, then delete with backups
   ```powershell
   .\scripts\unused-css-detector.ps1 -DeleteUnused -ConfidenceLevel "High"
   .\scripts\unused-css-detector.ps1 -DeleteUnused -DryRun:$false -CreateBackup -ConfidenceLevel "High"
   ```

4. **Test & Expand**: Test your app, then consider medium confidence classes

### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `StylesPath` | Path to SCSS files directory | `"./src/styles"` |
| `ComponentsPath` | Path to search for JS/JSX files | `"./src"` |
| `ExcludePatterns` | Array of patterns to exclude | Common utilities |
| `OutputFormat` | `"summary"`, `"detailed"`, or `"json"` | `"summary"` |
| `ConfidenceLevel` | `"High"`, `"Medium"`, or `"Low"` | `"Medium"` |
| `ValidateClasses` | Verify classes exist in files | `$true` |
| `Debug` | Enable detailed diagnostic output | `$false` |
| `DeleteUnused` | Enable deletion mode | `$false` |
| `DryRun` | Preview deletions without changes | `$true` |
| `CreateBackup` | Create backup files | `$true` |
| `Interactive` | Ask for confirmation | `$false` |

## ⚠️ **Important Notes**

### Classes That Might Be Missed
- **Dynamic class generation**: `className={theme + '-button'}`
- **CSS-in-JS libraries**: styled-components, emotion
- **External templates**: Email templates, documentation
- **Conditional classes**: `className={isActive ? 'active' : ''}`

### Best Practices
1. **Always start with dry runs**
2. **Create backups before deletion**
3. **Test incrementally** (don't delete everything at once)
4. **Review medium/low confidence results manually**
5. **Use version control** (commit before cleanup)

## 🔧 **Custom Configuration**

### Exclude Patterns
```powershell
# Custom exclusions for your project
$customExcludes = @(
    "utility-*",        # Your utility classes
    "theme-*",          # Theme-related classes  
    "debug-*",          # Debug classes
    "*-legacy"          # Legacy classes to keep
)

.\scripts\unused-css-detector.ps1 -ExcludePatterns $customExcludes
```

### Different Project Structures
```powershell
# For different folder structures
.\scripts\unused-css-detector.ps1 -StylesPath "./assets/css" -ComponentsPath "./components"

# For Vue.js projects
.\scripts\unused-css-detector.ps1 -ComponentsPath "./src" -OutputFormat "json"
```