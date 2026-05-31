# fixes.ps1 – Reparaciones del sistema
function Repair-SFC {
    if ($global:sync.chkAnalyzeOnly.IsChecked) { & $global:sync.WriteLog "[ANALYZE] Se ejecutaría sfc /scannow"; return }
    & $global:sync.WriteLog "Ejecutando SFC /SCANNOW..."
    try { $output = sfc /scannow 2>&1; $output | ForEach-Object { & $global:sync.WriteLog $_ } } catch { & $global:sync.WriteLog "❌ Error en SFC: $_" }
}
function Repair-DISM {
    if ($global:sync.chkAnalyzeOnly.IsChecked) { & $global:sync.WriteLog "[ANALYZE] Se ejecutaría DISM /RestoreHealth"; return }
    & $global:sync.WriteLog "Ejecutando DISM /RestoreHealth..."
    try { $output = dism /online /cleanup-image /restorehealth 2>&1; $output | ForEach-Object { & $global:sync.WriteLog $_ } } catch { & $global:sync.WriteLog "❌ Error en DISM: $_" }
}
function Repair-WindowsUpdate {
    if ($global:sync.chkAnalyzeOnly.IsChecked) { & $global:sync.WriteLog "[ANALYZE] Se repararía Windows Update"; return }
    & $global:sync.WriteLog "Reparando Windows Update..."
    try {
        Stop-Service wuauserv, bits, cryptsvc, trustedinstaller -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:SYSTEMROOT\SoftwareDistribution" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:SYSTEMROOT\System32\catroot2" -Recurse -Force -ErrorAction SilentlyContinue
        Start-Service wuauserv, bits, cryptsvc, trustedinstaller -ErrorAction SilentlyContinue
        & $global:sync.WriteLog "✅ Windows Update reparado."
    } catch { & $global:sync.WriteLog "❌ Error reparando Windows Update: $_" }
}
function Repair-Network {
    if ($global:sync.chkAnalyzeOnly.IsChecked) { & $global:sync.WriteLog "[ANALYZE] Se repararía la red"; return }
    & $global:sync.WriteLog "Reparando red..."
    try {
        netsh winsock reset
        ipconfig /release
        ipconfig /renew
        ipconfig /flushdns
        & $global:sync.WriteLog "✅ Red reparada. Se recomienda reiniciar."
    } catch { & $global:sync.WriteLog "❌ Error reparando red: $_" }
}
function Repair-All {
    Repair-DISM; Repair-SFC; Repair-WindowsUpdate; Repair-Network
}