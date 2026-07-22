[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $GodotArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ('PixelNightShift.GodotProcessErrorMode' -as [type])) {
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;

namespace PixelNightShift
{
    public static class GodotProcessErrorMode
    {
        [DllImport("kernel32.dll")]
        public static extern uint SetErrorMode(uint mode);
    }
}
'@
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runtimeRoot = Join-Path $projectRoot '.godot\headless-runtime'
$logRoot = Join-Path $projectRoot '.godot\headless-logs'
$mutex = [System.Threading.Mutex]::new($false, 'Local\PixelNightShiftGodotHeadless')
$mutexAcquired = $false
$exitCode = 1
$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA
$previousErrorMode = [uint32] 0
$errorModeSet = $false

try {
    # Suppress native fault dialogs while preserving the child process exit code and log.
    $previousErrorMode = [PixelNightShift.GodotProcessErrorMode]::SetErrorMode(0x8003)
    $errorModeSet = $true
    try {
        $mutexAcquired = $mutex.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        $mutexAcquired = $true
    }
    if (-not $mutexAcquired) {
        throw 'Another Pixel Night Shift Godot headless process is already running.'
    }

    $godotCommand = Get-Command godot -ErrorAction Stop
    $installDirectory = Split-Path -Parent $godotCommand.Source
    $consoleExecutables = @(
        Get-ChildItem -LiteralPath $installDirectory -Filter 'Godot*_console.exe' -File
    )
    if ($consoleExecutables.Count -ne 1) {
        throw "Expected exactly one Godot console executable in '$installDirectory'."
    }

    New-Item -ItemType Directory -Force -Path $runtimeRoot, $logRoot | Out-Null
    $env:APPDATA = Join-Path $runtimeRoot 'Roaming'
    $env:LOCALAPPDATA = Join-Path $runtimeRoot 'Local'
    New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:LOCALAPPDATA | Out-Null

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $logPath = Join-Path $logRoot "godot-$timestamp-$PID.log"
    & $consoleExecutables[0].FullName `
        '--headless' `
        '--path' $projectRoot `
        '--log-file' $logPath `
        @GodotArguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        [Console]::Error.WriteLine("Godot exited with code $exitCode. Log: $logPath")
    }
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    $exitCode = 1
}
finally {
    $env:APPDATA = $originalAppData
    $env:LOCALAPPDATA = $originalLocalAppData
    if ($errorModeSet) {
        [PixelNightShift.GodotProcessErrorMode]::SetErrorMode($previousErrorMode) | Out-Null
    }
    if ($mutexAcquired) {
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
}

exit $exitCode
