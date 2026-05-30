# cli.ps1 – Modo línea de comandos (implementación completa)
if ($Tweaks -or $InstallApps -or $AnalyzeOnly -or $RestoreFromBackup -or $Silent -or $NoRestart -or $Force) {
    Write-Host "WinOpt - Modo CLI" -ForegroundColor Cyan
    Write-Log "Parámetros: Tweaks='$Tweaks', InstallApps='$InstallApps', AnalyzeOnly=$AnalyzeOnly"
    if ($AnalyzeOnly) { $global:sync.chkAnalyzeOnly = $true }
    if ($RestoreFromBackup) { Write-Log "Restaurando desde backup: $RestoreFromBackup"; exit 0 }
    # Cargar configuraciones
    $presetsFile = Join-Path $global:sync.ConfigPath "preset.json"
    $tweaksFile = Join-Path $global:sync.ConfigPath "tweaks.json"
    $appsFile = Join-Path $global:sync.ConfigPath "applications.json"
    if ($Tweaks -and (Test-Path $presetsFile) -and (Test-Path $tweaksFile)) {
        $presets = Get-Content $presetsFile -Raw | ConvertFrom-Json
        $allTweaks = Get-Content $tweaksFile -Raw | ConvertFrom-Json
        $tweakIds = $presets.$Tweaks
        if ($tweakIds) {
            foreach ($tweakId in $tweakIds) {
                $tweakDef = $allTweaks.$tweakId
                if ($tweakDef) { Invoke-TweakAction -TweakId $tweakId -TweakDef $tweakDef -LogFunc { Write-Log $_ } }
                else { Write-Log "ADVERTENCIA: Tweak '$tweakId' no definido en JSON" -Level "WARNING" }
            }
        } else { Write-Log "Preset '$Tweaks' no encontrado" -Level "ERROR" }
    }
    if ($InstallApps -and (Test-Path $appsFile)) {
        $apps = $InstallApps -split ','
        Install-MultipleApps -AppNames $apps -LogFunc { Write-Log $_ }
    }
    if (-not $NoRestart -and -not $AnalyzeOnly) {
        $restartChoice = if ($Silent) { "Y" } else { Read-Host "¿Reiniciar ahora? (Y/N)" }
        if ($restartChoice -eq "Y") { Restart-Computer -Force }
    }
    exit 0
}
