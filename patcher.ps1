param([string]$Game = "", [switch]$Uninstall)
$ErrorActionPreference = 'Stop'

function Get-SHA256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Copy-StreamBytes($Source, $Destination, [long]$Count) {
    $buffer = New-Object byte[] (1024 * 1024)
    while ($Count -gt 0) {
        $read = $Source.Read($buffer, 0, [int][Math]::Min([long]$buffer.Length, $Count))
        if ($read -le 0) { throw 'Unexpected end of game file.' }
        $Destination.Write($buffer, 0, $read)
        $Count -= $read
    }
}

$temporary = $null
try {
    $manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($Game) {
        if (Test-Path -LiteralPath $Game -PathType Container) {
            $Game = Join-Path $Game $manifest.original_name
        }
        $target = (Resolve-Path -LiteralPath $Game).Path
    } else {
        $folders = @($PSScriptRoot, (Split-Path $PSScriptRoot -Parent), (Get-Location).Path) | Select-Object -Unique
        $found = @()
        foreach ($folder in $folders) {
            foreach ($item in (Get-ChildItem -LiteralPath $folder -Filter '*.exe' -File)) {
                if ($item.Length -ne $manifest.original_size -and $item.Length -ne $manifest.patched_size -and $item.Length -notin @($manifest.previous_patched_sizes)) { continue }
                $hash = Get-SHA256 $item.FullName
                if ($hash -eq $manifest.original_sha256 -or $hash -eq $manifest.patched_sha256 -or $hash -in @($manifest.previous_patched_sha256)) { $found += $item.FullName }
            }
        }
        $found = @($found | Select-Object -Unique)
        if ($found.Count -eq 1) {
            $target = $found[0]
        } else {
            Add-Type -AssemblyName System.Windows.Forms
            $dialog = New-Object System.Windows.Forms.OpenFileDialog
            $dialog.Title = 'Select Peg Champ game executable'
            $dialog.Filter = 'Game executable (*.exe)|*.exe'
            if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw 'Cancelled. No changes made.' }
            $target = $dialog.FileName
            $dialog.Dispose()
        }
    }
    $currentHash = Get-SHA256 $target
    $backup = $target + '.jpmod-original'
    $upgrading = !$Uninstall -and $currentHash -in @($manifest.previous_patched_sha256)
    if ($Uninstall) {
        if ($currentHash -eq $manifest.original_sha256) { Write-Host 'Already restored.'; exit 0 }
        if ($currentHash -ne $manifest.patched_sha256 -and $currentHash -notin @($manifest.previous_patched_sha256)) { throw 'Different game version or another modification. No changes made.' }
        if (!(Test-Path -LiteralPath $backup) -or (Get-SHA256 $backup) -ne $manifest.original_sha256) {
            throw 'A matching original backup was not found. No changes made.'
        }
        $expectedHash = $manifest.original_sha256
    } else {
        if ($currentHash -eq $manifest.patched_sha256) { Write-Host 'Japanese mod is already installed.'; exit 0 }
        if ($currentHash -ne $manifest.original_sha256 -and !$upgrading) { throw 'Different game version or another modification. No changes made.' }
        $payload = Join-Path $PSScriptRoot $manifest.tail_file
        if ((Get-SHA256 $payload) -ne $manifest.tail_sha256) { throw 'Patch data is damaged. Extract the ZIP again.' }
        if ((Test-Path -LiteralPath $backup) -and (Get-SHA256 $backup) -ne $manifest.original_sha256) {
            throw 'A different backup already exists. It will not be overwritten.'
        }
        if ($upgrading -and !(Test-Path -LiteralPath $backup)) { throw 'Updating requires the original .jpmod-original backup. No changes made.' }
        $expectedHash = $manifest.patched_sha256
    }
    $temporary = $target + '.jpmod-' + [Guid]::NewGuid().ToString('N') + '.tmp'
    if ($Uninstall) {
        [System.IO.File]::Copy($backup, $temporary, $false)
    } else {
        $sourcePath = $target
        if ($upgrading) { $sourcePath = $backup }
        $source = [System.IO.File]::OpenRead($sourcePath)
        $output = [System.IO.File]::Create($temporary)
        try {
            Copy-StreamBytes $source $output ([long]$manifest.prefix_length)
            $tail = [System.IO.File]::OpenRead($payload)
            try { $tail.CopyTo($output) } finally { $tail.Dispose() }
            foreach ($edit in $manifest.edits) {
                $bytes = New-Object byte[] ($edit.hex.Length / 2)
                for ($index = 0; $index -lt $bytes.Length; $index++) {
                    $bytes[$index] = [Convert]::ToByte($edit.hex.Substring($index * 2, 2), 16)
                }
                $null = $output.Seek([long]$edit.offset, [System.IO.SeekOrigin]::Begin)
                $output.Write($bytes, 0, $bytes.Length)
            }
        } finally { $source.Dispose(); $output.Dispose() }
    }
    if ((Get-SHA256 $temporary) -ne $expectedHash) { throw 'Output verification failed. The game file was not changed.' }
    if (!$Uninstall -and !(Test-Path -LiteralPath $backup)) {
        [System.IO.File]::Copy($target, $backup, $false)
        if ((Get-SHA256 $backup) -ne $manifest.original_sha256) { throw 'Backup verification failed. The game file was not changed.' }
    }
    [System.IO.File]::Replace($temporary, $target, $null)
    $temporary = $null
    if ($Uninstall) { Write-Host 'Original game restored.' }
    else { Write-Host 'Japanese mod installed. Select English / US flag in the game.' }
    exit 0
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if ($temporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -LiteralPath $temporary }
}
