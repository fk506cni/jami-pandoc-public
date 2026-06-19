<#
.SYNOPSIS
    Watches the script's folder for new .docx files and auto-converts them to PDF using Microsoft Word.

.DESCRIPTION
    This script runs as a persistent watcher. When a new .docx file appears in the
    same folder as this script, it waits for the file to become accessible (handling
    Google Drive sync locks), converts it to PDF via Word COM automation, and moves
    the original .docx into a "processed" subfolder.

    Designed for use with Google Drive sync folders where .docx files are delivered
    automatically and need to be converted to PDF without manual intervention.

.NOTES
    Requires: Microsoft Word installed on the machine.

    === How to Run ===

    Method 1: Right-click and "Run with PowerShell"
      - Right-click this file in Explorer -> "Run with PowerShell"
      - Note: The window may close on errors. Method 2 is recommended.

    Method 2: From a PowerShell terminal (RECOMMENDED)
      1. Open PowerShell (or Windows Terminal)
      2. Navigate to the folder containing this script:
             cd "C:\path\to\your\folder"
      3. If you've never run PowerShell scripts before, allow execution:
             Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
      4. Run the script:
             .\watch-and-convert.ps1
      5. The script will now watch for .docx files. Press Ctrl+C to stop.

    Method 3: Create a shortcut for one-click launch
      1. Right-click on the Desktop -> New -> Shortcut
      2. Enter as location:
             powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\watch-and-convert.ps1"
      3. Name it "DOCX to PDF Watcher" and click Finish
      4. Double-click the shortcut to start watching.

    === Folder Structure ===

    Place this script in the Google Drive sync folder:

        YourFolder/
        ├── watch-and-convert.ps1    <- this script
        ├── some-document.docx       <- new files appear here
        ├── some-document.pdf        <- PDF output stays here
        ├── processed/               <- converted .docx moved here (auto-created)
        └── error/                   <- failed .docx moved here (auto-created)

    === Configuration ===

    Edit the variables in the "Configuration" region below to adjust:
      - $PollIntervalSec    : How often to check for new files (default: 5 seconds)
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
#region Configuration
# ============================================================================

$PollIntervalSec = 5     # Polling interval in seconds

#endregion

# ============================================================================
#region Helper Functions
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','OK')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $color = switch ($Level) {
        'INFO'  { 'Cyan' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
        'OK'    { 'Green' }
    }
    Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
    Write-Host "[$Level] " -NoNewline -ForegroundColor $color
    Write-Host $Message
}

function Test-FileReady {
    <#
    .SYNOPSIS
        Tests whether a file can be opened exclusively (i.e., not locked by another process).
    #>
    param([string]$Path)
    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::None
        )
        $stream.Close()
        $stream.Dispose()
        return $true
    } catch {
        return $false
    }
}

function Convert-DocxToPdf {
    <#
    .SYNOPSIS
        Converts a .docx file to PDF using Word COM automation.
        Preserves the original Open arguments (OpenAndRepair=$true).
    #>
    param([string]$DocxPath)

    $pdfPath = [System.IO.Path]::ChangeExtension($DocxPath, '.pdf')
    $word = $null
    $doc  = $null

    try {
        Write-Log "Starting Word COM..." 'INFO'
        $word = New-Object -ComObject Word.Application
        $word.Visible = $false
        $word.DisplayAlerts = 0  # wdAlertsNone

        Write-Log "Opening with repair: $(Split-Path $DocxPath -Leaf)" 'INFO'

        # Documents.Open parameters (mirrors the original batch file):
        #   FileName, ConfirmConversions, ReadOnly, AddToRecentFiles,
        #   PasswordDocument, PasswordTemplate, Revert,
        #   WritePasswordDocument, WritePasswordTemplate, Format,
        #   Encoding, Visible, OpenAndRepair
        $doc = $word.Documents.Open(
            $DocxPath,          # FileName
            $false,             # ConfirmConversions
            $false,             # ReadOnly
            $false,             # AddToRecentFiles
            '',                 # PasswordDocument
            '',                 # PasswordTemplate
            $false,             # Revert
            '',                 # WritePasswordDocument
            '',                 # WritePasswordTemplate
            0,                  # Format (wdOpenFormatAuto)
            [Type]::Missing,    # Encoding
            $false,             # Visible
            $true               # OpenAndRepair
        )

        Write-Log "Saving as PDF..." 'INFO'
        # SaveAs2 Format 17 = wdFormatPDF
        $doc.SaveAs2($pdfPath, 17)
        $doc.Close($false)

        Write-Log "PDF created: $(Split-Path $pdfPath -Leaf)" 'OK'
        return $pdfPath

    } catch {
        Write-Log "Word conversion failed: $($_.Exception.Message)" 'ERROR'
        return $null

    } finally {
        # Thorough COM cleanup to prevent orphan WINWORD.exe processes
        if ($doc) {
            try {
                [System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc) | Out-Null
            } catch { }
        }
        if ($word) {
            try {
                $word.Quit()
            } catch { }
            try {
                [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
            } catch { }
        }
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}

#endregion

# ============================================================================
#region Main
# ============================================================================

# Resolve the watch directory (= directory where this script lives)
$WatchDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProcessedDir = Join-Path $WatchDir 'processed'
$ErrorDir     = Join-Path $WatchDir 'error'

# Banner
Write-Host ''
Write-Host '========================================================' -ForegroundColor White
Write-Host '  DOCX -> PDF  Auto-Converter (Folder Watcher)' -ForegroundColor White
Write-Host '========================================================' -ForegroundColor White
Write-Host ''
Write-Log "Watch folder : $WatchDir" 'INFO'
Write-Log "Processed to : $ProcessedDir" 'INFO'
Write-Log "Error to     : $ErrorDir" 'INFO'
Write-Log "Poll interval: ${PollIntervalSec}s" 'INFO'
Write-Host ''
Write-Log "Watching for .docx files... Press Ctrl+C to stop." 'INFO'
Write-Host ''

# Helper: ensure directory exists and move file there (with collision handling)
function Move-ToFolder {
    param(
        [string]$FilePath,
        [string]$DestDir,
        [string]$Label
    )
    if (-not (Test-Path $DestDir)) {
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
        Write-Log "Created folder: $Label/" 'INFO'
    }
    $fileName = Split-Path $FilePath -Leaf
    $destPath = Join-Path $DestDir $fileName
    if (Test-Path $destPath) {
        $baseName  = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $newName   = "${baseName}_${timestamp}.docx"
        $destPath  = Join-Path $DestDir $newName
    }
    Move-Item -Path $FilePath -Destination $destPath -Force
    return (Split-Path $destPath -Leaf)
}

# --- Stateless polling loop ---
# Every cycle, scan the watch folder for ALL .docx files.
#   - Locked files  -> skip (will be retried next cycle automatically)
#   - Convert OK    -> move to processed/
#   - Convert FAIL  -> move to error/
try {
    while ($true) {
        $currentFiles = Get-ChildItem -Path $WatchDir -Filter '*.docx' -File -ErrorAction SilentlyContinue

        foreach ($file in $currentFiles) {
            # Skip temporary Word files (~$*.docx)
            if ($file.Name -like '~`$*') {
                continue
            }

            $filePath = $file.FullName

            # Check file lock (single attempt -- no blocking wait)
            if (-not (Test-FileReady -Path $filePath)) {
                Write-Log "Locked (sync in progress?): $($file.Name) -- will retry next cycle" 'WARN'
                continue
            }

            # File is ready -- process it
            Write-Host ''
            Write-Host '--------------------------------------------------------' -ForegroundColor DarkCyan
            Write-Log "Processing: $($file.Name)" 'INFO'

            $pdfResult = Convert-DocxToPdf -DocxPath $filePath

            if ($pdfResult) {
                $movedName = Move-ToFolder -FilePath $filePath -DestDir $ProcessedDir -Label 'processed'
                Write-Log "Moved docx to: processed/$movedName" 'OK'
            } else {
                $movedName = Move-ToFolder -FilePath $filePath -DestDir $ErrorDir -Label 'error'
                Write-Log "Moved failed docx to: error/$movedName" 'ERROR'
            }

            Write-Host '--------------------------------------------------------' -ForegroundColor DarkCyan
            Write-Host ''
        }

        Start-Sleep -Seconds $PollIntervalSec
    }
} finally {
    Write-Log "Watcher stopped." 'WARN'
}

#endregion
