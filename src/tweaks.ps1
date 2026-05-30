# tweaks.ps1 – Backup, restore, test y aplicación de tweaks
function Backup-Tweak {
    param([string]$TweakId, $TweakDef)
    $backupFile = Join-Path $global:sync.BackupPath "$TweakId.json"
    $data = @{}
    if ($TweakDef.registry) {
        $data.registry = @()
        foreach ($reg in $TweakDef.registry) {
            $current = Get-ItemProperty -Path $reg.path -Name $reg.name -ErrorAction SilentlyContinue
            $data.registry += @{ path = $reg.path; name = $reg.name; value = $current.$($reg.name); type = $reg.type }
        }
    }
    if ($TweakDef.service) {
        $data.service = @()
        foreach ($svc in $TweakDef.service) {
            $service = Get-Service -Name $svc.name -ErrorAction SilentlyContinue
            $data.service += @{ name = $svc.name; startupType = $service.StartType }
        }
    }
    if ($data.Count -gt 0) { $data | ConvertTo-Json | Set-Content $backupFile -Encoding UTF8 }
}

function Restore-Tweak {
    param([string]$TweakId)
    $backupFile = Join-Path $global:sync.BackupPath "$TweakId.json"
    if (-not (Test-Path $backupFile)) { return $false }
    $backup = Get-Content $backupFile -Raw | ConvertFrom-Json
    if ($backup.registry) {
        foreach ($reg in $backup.registry) {
            try {
                if ($reg.value -eq $null) { Remove-ItemProperty -Path $reg.path -Name $reg.name -Force -ErrorAction SilentlyContinue }
                else { Set-ItemProperty -Path $reg.path -Name $reg.name -Value $reg.value -Type $reg.type -Force }
            } catch { }
        }
    }
    if ($backup.service) {
        foreach ($svc in $backup.service) {
            try { Set-Service -Name $svc.name -StartupType $svc.startupType -ErrorAction SilentlyContinue } catch { }
        }
    }
    Remove-Item $backupFile -Force
    return $true
}

function Test-TweakApplied {
    param($TweakDef)
    if ($TweakDef.registry) {
        foreach ($reg in $TweakDef.registry) {
            $current = Get-ItemProperty -Path $reg.path -Name $reg.name -ErrorAction SilentlyContinue
            if ($null -eq $current -or $current.$($reg.name) -ne $reg.value) { return $false }
        }
    }
    if ($TweakDef.service) {
        foreach ($svc in $TweakDef.service) {
            $service = Get-Service -Name $svc.name -ErrorAction SilentlyContinue
            if ($service.StartType -ne $svc.startupType) { return $false }
        }
    }
    return $true
}

function Invoke-TweakAction {
    param([string]$TweakId, $TweakDef, [scriptblock]$LogFunc = $global:sync.WriteLog)
    if ($global:sync.chkAnalyzeOnly.IsChecked) {
        & $LogFunc "[ANALYZE] Se aplicaría: $TweakId - $($TweakDef.content)"
        return $true
    }
    if (Test-TweakApplied -TweakDef $TweakDef) {
        & $LogFunc "Tweak $TweakId ya aplicado. Saltando."
        return $true
    }
    Backup-Tweak -TweakId $TweakId -TweakDef $TweakDef
    if ($TweakDef.registry) {
        foreach ($reg in $TweakDef.registry) {
            try {
                if (-not (Test-Path $reg.path)) { New-Item -Path $reg.path -Force | Out-Null }
                Set-ItemProperty -Path $reg.path -Name $reg.name -Value $reg.value -Type $reg.type -Force
                & $LogFunc "  Registry: $($reg.path)\$($reg.name) = $($reg.value)"
            } catch { & $LogFunc "  Error registry: $_" }
        }
    }
    if ($TweakDef.service) {
        foreach ($svc in $TweakDef.service) {
            try {
                Stop-Service $svc.name -Force -ErrorAction SilentlyContinue
                Set-Service $svc.name -StartupType $svc.startupType -ErrorAction SilentlyContinue
                & $LogFunc "  Service: $($svc.name) -> $($svc.startupType)"
            } catch { & $LogFunc "  Error service: $_" }
        }
    }
    if ($TweakDef.invokeScript) {
        try { Invoke-Expression $TweakDef.invokeScript; & $LogFunc "  InvokeScript ejecutado" } catch { & $LogFunc "  Error script: $_" }
    }
    return $true
}
