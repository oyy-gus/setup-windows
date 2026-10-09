Write-Host "===== SETUP DIMULAI ====="

# ====================== ENABLE WINDOWS DARK MODE ======================
Write-Host "===== ENABLE DARK MODE WINDOWS ====="
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
If (!(Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name AppsUseLightTheme -Value 0
Set-ItemProperty -Path $regPath -Name SystemUsesLightTheme -Value 0
Stop-Process -Name explorer -Force
Start-Sleep -Seconds 2
Start-Process explorer.exe

$desktop = [Environment]::GetFolderPath("Desktop")

# ====================== INSTALL ANTIGRAVITY IDE ======================
Write-Host "===== INSTALL ANTIGRAVITY IDE ====="

$agUrl = "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/windows-x64/Antigravity%20IDE.exe"
$agInstaller = "$env:TEMP\AntigravityIDE.exe"

try {
    Invoke-WebRequest -Uri $agUrl -OutFile $agInstaller
    Write-Host "Download selesai."

    Start-Process $agInstaller -Wait
    Write-Host "Antigravity IDE selesai diinstall."

    Remove-Item $agInstaller -Force
} catch {
    Write-Host "Gagal install Antigravity IDE: $_"
}

# Buat shortcut Antigravity (cek beberapa lokasi umum)
$agExe = $null
$searchRoots = @("$env:LOCALAPPDATA\Programs", "$env:ProgramFiles", "${env:ProgramFiles(x86)}")
foreach ($root in $searchRoots) {
    if (Test-Path $root) {
        $found = Get-ChildItem -Path $root -Directory -Filter "Antigravity*" -ErrorAction SilentlyContinue |
            ForEach-Object { Get-ChildItem -Path $_.FullName -Filter "Antigravity*.exe" -File -ErrorAction SilentlyContinue } |
            Where-Object { $_.Name -notmatch "unins|update|setup" } |
            Select-Object -First 1
        if ($found) { $agExe = $found.FullName; break }
    }
}

if ($agExe) {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("$desktop\Antigravity IDE.lnk")
    $Shortcut.TargetPath = $agExe
    $Shortcut.IconLocation = "$agExe,0"
    $Shortcut.Save()
    Write-Host "Shortcut Antigravity IDE dibuat."
} else {
    Write-Host "Lokasi Antigravity tidak ditemukan, shortcut dilewati."
}

# ====================== INSTALL DISCORD ======================
Write-Host "===== INSTALL DISCORD ====="
winget install --id Discord.Discord --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity

# ====================== INSTALL ROBLOX STUDIO ======================
Write-Host "===== INSTALL ROBLOX STUDIO ====="

$robloxUrl = "https://raw.githubusercontent.com/oyy-gus/setup-windows/master/installer/RobloxStudioInstaller.exe"
$installerPath = "$env:TEMP\RobloxStudioInstaller.exe"

try {
    Invoke-WebRequest -Uri $robloxUrl -OutFile $installerPath
    Write-Host "Download selesai."

    Start-Process $installerPath -Wait

    Write-Host "Roblox Studio selesai diinstall."

    Remove-Item $installerPath -Force
} catch {
    Write-Host "Gagal install Roblox Studio: $_"
}

# ====================== BUAT SHORTCUT ROBLOX ======================
Write-Host "===== BUAT SHORTCUT ROBLOX ====="

$robloxFolder = "$env:LOCALAPPDATA\Roblox\Versions"

if (Test-Path $robloxFolder) {
    $latest = Get-ChildItem $robloxFolder | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $studioExe = "$($latest.FullName)\RobloxStudioBeta.exe"
    $shortcutRBX = "$desktop\Roblox Studio.lnk"

    if (Test-Path $studioExe) {
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($shortcutRBX)
        $Shortcut.TargetPath = $studioExe
        $Shortcut.IconLocation = "$studioExe,0"
        $Shortcut.Save()

        Write-Host "Shortcut Roblox Studio dibuat."
    } else {
        Write-Host "File RobloxStudioBeta.exe tidak ditemukan!"
    }
} else {
    Write-Host "Folder Roblox tidak ditemukan!"
}

Write-Host ""
Write-Host "===== SELESAI - SEMUA SIAP DIGUNAKAN ====="
