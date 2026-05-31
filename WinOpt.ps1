<#
.SYNOPSIS
    WinOpt - Optimizador de Windows (versión compilada)
.NOTES
    Generado automáticamente. NO EDITAR DIRECTAMENTE.
#>

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="WinOpt" Height="450" Width="650" WindowStartupLocation="CenterScreen">
    <StackPanel>
        <GroupBox Header="Tweaks" Margin="5">
            <StackPanel>
                <CheckBox Name="chkDisableTelemetry" Content="Disable Telemetry" Margin="3"/>
                <CheckBox Name="chkDisableXbox" Content="Disable Xbox Services" Margin="3"/>
                <CheckBox Name="chkDisableHibernation" Content="Disable Hibernation" Margin="3"/>
            </StackPanel>
        </GroupBox>
        <GroupBox Header="Opciones" Margin="5">
            <CheckBox Name="chkAnalyzeOnly" Content="Modo solo análisis" Margin="3"/>
        </GroupBox>
        <Button Name="btnRunTweaks" Content="Ejecutar tweaks seleccionados" Margin="5"/>
        <GroupBox Header="Instalación de aplicaciones" Margin="5">
            <StackPanel>
                <ListBox Name="lstApps" SelectionMode="Multiple" Height="100"/>
                <Button Name="btnInstallApps" Content="Instalar seleccionadas" Margin="3"/>
            </StackPanel>
        </GroupBox>
        <GroupBox Header="Reparaciones" Margin="5">
            <StackPanel Orientation="Horizontal">
                <Button Name="btnRepairSFC" Content="SFC" Width="80" Margin="2"/>
                <Button Name="btnRepairDISM" Content="DISM" Width="80" Margin="2"/>
                <Button Name="btnRepairWU" Content="Windows Update" Width="100" Margin="2"/>
                <Button Name="btnRepairNetwork" Content="Red" Width="80" Margin="2"/>
                <Button Name="btnRepairAll" Content="Todas" Width="80" Margin="2"/>
            </StackPanel>
        </GroupBox>
        <TextBox Name="txtLog" Height="120" IsReadOnly="True" TextWrapping="Wrap" Margin="5"/>
    </StackPanel>
</Window>'@

#region core.ps1
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
#endregion

#region tweaks.ps1
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
#endregion

#region fixes.ps1
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
#endregion

#region install.ps1
# install.ps1 – Instalación de aplicaciones
function Test-WingetAvailable { try { return (Get-Command winget -ErrorAction SilentlyContinue) -ne $null } catch { $false } }
function Test-ChocoAvailable { try { return (Get-Command choco -ErrorAction SilentlyContinue) -ne $null } catch { $false } }

function Install-Package {
    param([string]$AppId, [hashtable]$AppInfo, [scriptblock]$LogFunc = $global:sync.WriteLog)
    $wingetId = $AppInfo.winget; $chocoId = $AppInfo.choco
    if (-not $wingetId -and -not $chocoId) { & $LogFunc "No hay identificador para $AppId"; return $false }
    if ($global:sync.chkAnalyzeOnly.IsChecked) { & $LogFunc "[ANALYZE] Instalaría: $AppId"; return $true }
    if ($wingetId -and (Test-WingetAvailable)) {
        & $LogFunc "Instalando $AppId mediante winget ($wingetId)"
        try {
            winget install --id $wingetId --silent --accept-package-agreements --accept-source-agreements 2>&1 | ForEach-Object { & $LogFunc $_ }
            if ($LASTEXITCODE -eq 0) { & $LogFunc "✅ Instalación exitosa: $AppId"; return $true }
        } catch { & $LogFunc "❌ Winget falló para ${AppId}: $_" }
    }
    if ($chocoId -and (Test-ChocoAvailable)) {
        & $LogFunc "Instalando $AppId mediante Chocolatey ($chocoId)"
        try {
            choco install $chocoId -y --no-progress 2>&1 | ForEach-Object { & $LogFunc $_ }
            if ($LASTEXITCODE -eq 0) { & $LogFunc "✅ Instalación exitosa mediante Chocolatey: $AppId"; return $true }
        } catch { & $LogFunc "❌ Chocolatey falló para ${AppId}: $_" }
    }
    & $LogFunc "❌ No se pudo instalar $AppId"
    return $false
}

function Install-MultipleApps {
    param([string[]]$AppNames, [scriptblock]$LogFunc = $global:sync.WriteLog)
    $appsFile = Join-Path $global:sync.ConfigPath "applications.json"
    if (-not (Test-Path $appsFile)) { & $LogFunc "No se encontró applications.json"; return }
    try { $appsConfig = Get-Content $appsFile -Raw | ConvertFrom-Json } catch { & $LogFunc "Error al leer applications.json: $_"; return }
    foreach ($app in $AppNames) {
        $appInfo = $appsConfig.$app
        if ($appInfo) { Install-Package -AppId $app -AppInfo $appInfo -LogFunc $LogFunc }
        else { & $LogFunc "Aplicación '$app' no definida en applications.json" }
    }
}
#endregion

#region cli.ps1
# cli.ps1 – Modo línea de comandos
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
#endregion

#region gui.ps1
# gui.ps1 – Lógica de la interfaz gráfica
Add-Type -AssemblyName PresentationFramework, System.Windows.Forms

function Show-WinOptGUI {
    $reader = [System.Xml.XmlReader]::Create((New-Object System.IO.StringReader($xaml)))
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    $global:sync.Window = $window

    $global:sync.chkDisableTelemetry = $window.FindName("chkDisableTelemetry")
    $global:sync.chkDisableXbox      = $window.FindName("chkDisableXbox")
    $global:sync.chkDisableHibernation = $window.FindName("chkDisableHibernation")
    $global:sync.chkAnalyzeOnly      = $window.FindName("chkAnalyzeOnly")
    $global:sync.btnRunTweaks        = $window.FindName("btnRunTweaks")
    $global:sync.lstApps             = $window.FindName("lstApps")
    $global:sync.btnInstallApps      = $window.FindName("btnInstallApps")
    $global:sync.btnRepairSFC        = $window.FindName("btnRepairSFC")
    $global:sync.btnRepairDISM       = $window.FindName("btnRepairDISM")
    $global:sync.btnRepairWU         = $window.FindName("btnRepairWU")
    $global:sync.btnRepairNetwork    = $window.FindName("btnRepairNetwork")
    $global:sync.btnRepairAll        = $window.FindName("btnRepairAll")
    $global:sync.txtLog              = $window.FindName("txtLog")

    $global:sync.GUILog = {
        param($Message)
        $global:sync.txtLog.Dispatcher.Invoke([Action]{
            $global:sync.txtLog.AppendText("$Message`n")
            $global:sync.txtLog.ScrollToEnd()
        })
    }
    $global:sync.WriteLog = $global:sync.GUILog

    # Cargar configuración
    $tweaksFile = Join-Path $global:sync.ConfigPath "tweaks.json"
    if (Test-Path $tweaksFile) {
        try { $global:sync.tweaksConfig = Get-Content $tweaksFile -Raw | ConvertFrom-Json } catch { $global:sync.tweaksConfig = @{} }
    } else { $global:sync.tweaksConfig = @{} }
    $appsFile = Join-Path $global:sync.ConfigPath "applications.json"
    if (Test-Path $appsFile) {
        try { $appsConfig = Get-Content $appsFile -Raw | ConvertFrom-Json } catch { $appsConfig = @{} }
        foreach ($key in $appsConfig.PSObject.Properties.Name) { $global:sync.lstApps.Items.Add($key) }
    }

    # Evento tweaks
    $global:sync.btnRunTweaks.Add_Click({
        $selected = @()
        if ($global:sync.chkDisableTelemetry.IsChecked)   { $selected += "WPFTweaksTelemetry" }
        if ($global:sync.chkDisableXbox.IsChecked)        { $selected += "WPFTweaksXbox" }
        if ($global:sync.chkDisableHibernation.IsChecked) { $selected += "WPFTweaksDisableHibernation" }
        foreach ($tweakId in $selected) {
            $tweakDef = $global:sync.tweaksConfig.$tweakId
            if ($tweakDef) { Invoke-TweakAction -TweakId $tweakId -TweakDef $tweakDef -LogFunc $global:sync.WriteLog }
            else { & $global:sync.WriteLog "ADVERTENCIA: Tweak '$tweakId' no definido en JSON" }
        }
    })

    # Evento instalación
    $global:sync.btnInstallApps.Add_Click({
        $selected = $global:sync.lstApps.SelectedItems | ForEach-Object { $_.Content }
        if ($selected.Count -eq 0) { & $global:sync.WriteLog "No se seleccionó ninguna aplicación."; return }
        & $global:sync.WriteLog "Instalando: $($selected -join ', ')"
        Install-MultipleApps -AppNames $selected -LogFunc $global:sync.WriteLog
    })

    # Eventos reparaciones
    $global:sync.btnRepairSFC.Add_Click({ Repair-SFC })
    $global:sync.btnRepairDISM.Add_Click({ Repair-DISM })
    $global:sync.btnRepairWU.Add_Click({ Repair-WindowsUpdate })
    $global:sync.btnRepairNetwork.Add_Click({ Repair-Network })
    $global:sync.btnRepairAll.Add_Click({ Repair-All })

    $window.ShowDialog() | Out-Null
}
#endregion

Show-WinOptGUI