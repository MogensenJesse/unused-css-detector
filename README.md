# CSS Unused Class Detector

A PowerShell script to detect unused CSS classes in your Next.js project by analyzing SCSS files and searching for usage in JavaScript/JSX components.

## Features

- 🔍 **Comprehensive SCSS Parsing**: Handles BEM naming conventions, nested selectors, and modifiers
- 🎯 **Smart Usage Detection**: Searches through JS/JSX/TS/TSX files for className usage
- 📊 **Multiple Output Formats**: Summary, detailed (by file), or JSON
- 🚫 **Intelligent Filtering**: Excludes common utility class patterns
- 🎨 **Colorized Output**: Easy-to-read results with emojis and colors
- 🗑️ **Automated Deletion**: Safely remove unused classes with backup and confirmation options
- 🛡️ **Safety Features**: Dry-run mode, automatic backups, and interactive confirmation

## Usage

### Basic Usage
```powershell
# Run from project root
.\scripts\unused-css-detector.ps1
```

### Custom Paths
```powershell
# Specify custom paths
.\scripts\unused-css-detector.ps1 -StylesPath "./styles" -ComponentsPath "./components"
```

### Different Output Formats
```powershell
# Detailed output (grouped by file)
.\scripts\unused-css-detector.ps1 -OutputFormat "detailed"

# JSON output (for scripts/CI)
.\scripts\unused-css-detector.ps1 -OutputFormat "json"
```

### Custom Exclude Patterns
```powershell
# Exclude specific patterns
.\scripts\unused-css-detector.ps1 -ExcludePatterns @("utility-*", "temp-*", "debug-*")
```

### Automated Deletion
```powershell
# Safe preview (dry run) - shows what would be deleted
.\scripts\unused-css-detector.ps1 -DeleteUnused

# Actually delete unused classes with automatic backups
.\scripts\unused-css-detector.ps1 -DeleteUnused -DryRun:$false -CreateBackup

# Interactive deletion - asks for confirmation for each file
.\scripts\unused-css-detector.ps1 -DeleteUnused -DryRun:$false -Interactive

# Delete without backups (not recommended)
.\scripts\unused-css-detector.ps1 -DeleteUnused -DryRun:$false -CreateBackup:$false
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `StylesPath` | Path to SCSS files directory | `"./src/styles"` |
| `ComponentsPath` | Path to search for JS/JSX files | `"./src"` |
| `ExcludePatterns` | Array of patterns to exclude | Common utility patterns |
| `OutputFormat` | Output format: `"summary"`, `"detailed"`, or `"json"` | `"summary"` |
| `DeleteUnused` | Enable deletion mode | `$false` |
| `DryRun` | Preview deletions without making changes | `$true` (when DeleteUnused is true) |
| `CreateBackup` | Create backup files before deletion | `$true` (when DeleteUnused is true) |
| `Interactive` | Ask for confirmation before each file deletion | `$false` |

## What It Detects

### SCSS Patterns
- Direct classes: `.admin-dashboard`, `.sidebar`
- BEM elements: `&__header` → `.parent__header`
- BEM modifiers: `&--active` → `.parent--active`
- Nested selectors

### JavaScript Patterns
- `className="class-name"`
- `className="class1 class2"`
- `className={"dynamic-class"}`
- `className={variableWithString}`

## Example Output

### Summary Format
```
🔍 CSS Unused Class Detector
===============================
📁 Scanning SCSS files in: ./src/styles
✅ Found 45 SCSS files
📊 Total unique CSS classes found: 324
🚫 Excluded 12 classes matching patterns
🔎 Searching for class usage in: ./src
✅ Used classes: 298
⚠️ Unused classes: 14

🗑️ UNUSED CLASSES:
   • .old-button
   • .deprecated-modal
   • .unused-wrapper
```

### Detailed Format
```
🗑️ UNUSED CLASSES (by file):

📄 src/styles/features/admin/_admin.scss
   • .old-sidebar
   • .deprecated-header

📄 src/styles/features/forms/_form-manager.scss
   • .unused-input-group
   • .old-validation-error
```

## Important Notes

⚠️ **Review Before Deletion**: Some classes might be:
- Used in dynamic class generation
- Applied via CSS-in-JS libraries
- Reserved for future features
- Used in HTML templates or external files

🛡️ **Safety Features**:
- **Dry Run Default**: Deletion mode defaults to dry-run for safety
- **Automatic Backups**: Creates timestamped backup files before deletion
- **Confirmation Required**: Requires typing "DELETE" for non-interactive bulk deletion
- **Interactive Mode**: Allows per-file confirmation
- **Error Handling**: Continues processing other files if one fails

🔄 **Backup Files**: When created, backup files use the format:
```
original-file.scss.backup_20231215_143022
```

💡 **Best Practices**:
1. Always run with `-DeleteUnused` first (dry run) to preview changes
2. Use `-CreateBackup` for safety (enabled by default)
3. Consider `-Interactive` mode for selective deletion
4. Test your application after deletion to ensure nothing breaks

## Requirements

- PowerShell 5.1+ or PowerShell Core 6+
- Read access to your project files 