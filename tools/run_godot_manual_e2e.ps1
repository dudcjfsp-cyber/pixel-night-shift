[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string] $SessionId,

    [switch] $Editor,

    [ValidatePattern('^res://.+\.gd$')]
    [string] $ScriptPath = '',

    [string] $CaptureDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ('PixelNightShift.GodotManualErrorMode' -as [type])) {
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;

namespace PixelNightShift
{
    public static class GodotManualErrorMode
    {
        [DllImport("kernel32.dll")]
        public static extern uint SetErrorMode(uint mode);
    }
}
'@
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sessionRoot = Join-Path $projectRoot ".godot\manual-e2e-runtime\$SessionId"
$logRoot = Join-Path $sessionRoot 'logs'
$isolatedAppData = Join-Path $sessionRoot 'Roaming'
$isolatedLocalAppData = Join-Path $sessionRoot 'Local'
$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA

New-Item -ItemType Directory -Force -Path $isolatedAppData, $isolatedLocalAppData, $logRoot | Out-Null

$godotCommand = Get-Command godot -ErrorAction Stop
$installDirectory = Split-Path -Parent $godotCommand.Source
$guiExecutables = @(
    Get-ChildItem -LiteralPath $installDirectory -Filter 'Godot*.exe' -File |
        Where-Object { $_.Name -notlike '*_console.exe' }
)
if ($guiExecutables.Count -ne 1) {
    throw "Expected exactly one Godot GUI executable in '$installDirectory'."
}

$mutex = [System.Threading.Mutex]::new(
    $false,
    'Local\PixelNightShiftGodotHeadless'
)
$mutexAcquired = $false
$previousErrorMode = [uint32] 0
$errorModeSet = $false

try {
    try {
        $mutexAcquired = $mutex.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        $mutexAcquired = $true
    }
    if (-not $mutexAcquired) {
        throw 'Another Pixel Night Shift Godot validation process is already running.'
    }

    $env:APPDATA = $isolatedAppData
    $env:LOCALAPPDATA = $isolatedLocalAppData

    # Suppress native crash dialogs while preserving the Godot process exit code and log.
    $previousErrorMode = [PixelNightShift.GodotManualErrorMode]::SetErrorMode(0x8003)
    $errorModeSet = $true
    $logPath = Join-Path $logRoot 'godot.log'
    $godotArguments = @('--path', $projectRoot, '--log-file', $logPath)
    if ($Editor) {
        $godotArguments += '--editor'
    }
    if (-not [string]::IsNullOrWhiteSpace($ScriptPath)) {
        $godotArguments += @('--script', $ScriptPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($CaptureDirectory)) {
        if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
            throw 'CaptureDirectory requires ScriptPath.'
        }
        if (-not [System.IO.Path]::IsPathRooted($CaptureDirectory)) {
            throw 'CaptureDirectory must be an absolute path.'
        }
        $godotArguments += @(
            '--',
            '--opening-e2e-only',
            "--capture-dir=$CaptureDirectory"
        )
    }
    $process = Start-Process `
        -FilePath $guiExecutables[0].FullName `
        -ArgumentList $godotArguments `
        -PassThru `
        -Wait
    if ($process.ExitCode -ne 0) {
        throw "Godot exited with code $($process.ExitCode). Log: $logPath"
    }
}
finally {
    $env:APPDATA = $originalAppData
    $env:LOCALAPPDATA = $originalLocalAppData
    if ($errorModeSet) {
        [PixelNightShift.GodotManualErrorMode]::SetErrorMode($previousErrorMode) | Out-Null
    }
    if ($mutexAcquired) {
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
}
