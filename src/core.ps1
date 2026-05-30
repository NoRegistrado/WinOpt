# core.ps1 – Tabla sincronizada, logging, runspaces
$global:sync = [hashtable]::Synchronized(@{})
$global:sync.Jobs = @{}
$global:sync.IsRunning = $false
$global:sync.BackupPath = "$env:TEMP\WinOpt_Backups"
$global:sync.ConfigPath = (Get-Location).Path + "\config"

if (-not (Test-Path $global:sync.BackupPath)) { New-Item -Path $global:sync.BackupPath -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $global:sync.ConfigPath)) { New-Item -Path $global:sync.ConfigPath -ItemType Directory -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"
    Add-Content -Path "$env:TEMP\WinOpt.log" -Value $logLine -ErrorAction SilentlyContinue
    if ($global:sync.GUILog) {
        $global:sync.GUILog.Invoke($logLine)
    } else {
        $color = switch ($Level) { "ERROR" { "Red" } "WARNING" { "Yellow" } default { "Gray" } }
        Write-Host $logLine -ForegroundColor $color
    }
}

function Start-BackgroundJob {
    param(
        [scriptblock]$ScriptBlock,
        [string]$JobName = "BackgroundTask",
        [object[]]$ArgumentList = @()
    )
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.Open()
    $ps = [powershell]::Create().AddScript($ScriptBlock)
    if ($ArgumentList.Count -gt 0) { $ps.AddParameters($ArgumentList) | Out-Null }
    $ps.Runspace = $runspace
    $handle = $ps.BeginInvoke()
    $global:sync.Jobs[$JobName] = @{ Handle = $handle; PS = $ps; Runspace = $runspace }
}
