# Compile.ps1
$output = "WinOpt.ps1"
$modules = @("core.ps1", "tweaks.ps1", "fixes.ps1", "install.ps1", "cli.ps1", "gui.ps1")

$header = @'
<#
.SYNOPSIS
    WinOpt - Optimizador de Windows (versión compilada)
.NOTES
    Generado automáticamente. NO EDITAR DIRECTAMENTE.
#>
'@

$scriptContent = $header + "`r`n`r`n"

# Insertar XAML
$xamlPath = "src\gui.xaml"
if (Test-Path $xamlPath) {
    $xamlRaw = Get-Content $xamlPath -Raw
    $scriptContent += "`$xaml = @'`r`n$xamlRaw'@`r`n`r`n"
} else {
    Write-Warning "No se encontró src/gui.xaml"
}

foreach ($module in $modules) {
    $path = "src\$module"
    if (Test-Path $path) {
        $content = Get-Content $path -Raw
        $scriptContent += "#region $module`r`n$content`r`n#endregion`r`n`r`n"
    }
}

$scriptContent += "Show-WinOptGUI"

[System.IO.File]::WriteAllText($output, $scriptContent, [System.Text.UTF8Encoding]::new($false))
Write-Host "✅ Compilado en $output (UTF-8 sin BOM)" -ForegroundColor Green