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

    # Cargar JSON
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
