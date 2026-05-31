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