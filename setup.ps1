$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "===== SETUP DIMULAI ====="

# ====================== CEK ADMINISTRATOR ======================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "PERINGATAN: Jalankan PowerShell sebagai Administrator agar uninstall dan install berjalan lancar." -ForegroundColor Yellow
}

# ====================== AUTO-CLICKER (Next / Install / Uninstall / Finish) ======================
# Berjalan di proses terpisah. Hanya mengklik jendela milik installer/uninstaller,
# jadi wizard yang tidak mendukung mode silent tetap terklik otomatis.
$clickerPath = "$env:TEMP\autoclick.ps1"
@'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$procRegex = '^(unins\d*|_iu.*|_is.*|Un_A.*|Uninstall.*|helper|AntigravityIDE.*|Antigravity IDE.*|RobloxStudioInstaller.*|setup|msiexec)$'
$btnRegex  = '^(Next|Install|Uninstall|Finish|Done|Yes|OK|Continue|I Agree|Agree|Accept)\b'

$AE = [Windows.Automation.AutomationElement]
$ctBtn   = New-Object Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [Windows.Automation.ControlType]::Button)
$ctRadio = New-Object Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [Windows.Automation.ControlType]::RadioButton)
$desc = [Windows.Automation.TreeScope]::Descendants

while ($true) {
    try {
        $wins = $AE::RootElement.FindAll([Windows.Automation.TreeScope]::Children, [Windows.Automation.Condition]::TrueCondition)
        foreach ($w in $wins) {
            $pn = (Get-Process -Id $w.Current.ProcessId -ErrorAction SilentlyContinue).ProcessName
            if (-not $pn -or $pn -notmatch $procRegex) { continue }

            foreach ($r in $w.FindAll($desc, $ctRadio)) {
                if (($r.Current.Name -replace '&','') -match '^I accept') {
                    $sp = $r.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern)
                    if (-not $sp.Current.IsSelected) { $sp.Select() }
                }
            }
            foreach ($b in $w.FindAll($desc, $ctBtn)) {
                $n = $b.Current.Name -replace '&',''
                if ($b.Current.IsEnabled -and $n -match $btnRegex) {
                    $b.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
                    break
                }
            }
        }
    } catch {}
    Start-Sleep -Milliseconds 800
}
'@ | Set-Content -Path $clickerPath -Encoding UTF8

$clickerProc = Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File",$clickerPath `
    -PassThru
Write-Host "Auto-clicker aktif."

# ====================== ENABLE WINDOWS DARK MODE ======================
Write-Host "===== ENABLE DARK MODE WINDOWS ====="
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
If (!(Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name AppsUseLightTheme -Value 0
Set-ItemProperty -Path $regPath -Name SystemUsesLightTheme -Value 0
Set-ItemProperty -Path $regPath -Name ColorPrevalence -Value 0 -ErrorAction SilentlyContinue   # taskbar tidak diwarnai accent color

# Beritahu Windows bahwa tema berubah, supaya taskbar langsung ikut gelap tanpa restart Explorer
Add-Type -Namespace Win32 -Name Native -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
$result = [UIntPtr]::Zero
[Win32.Native]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, "ImmersiveColorSet", 2, 5000, [ref]$result) | Out-Null
[Win32.Native]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, "WindowsThemeElement", 2, 5000, [ref]$result) | Out-Null

# Restart Explorer sebagai cadangan (bisa ditolak di sesi RDP, tidak masalah)
try {
    Stop-Process -Name explorer -Force -ErrorAction Stop
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
} catch {
    Write-Host "Explorer tidak bisa direstart, tema diterapkan lewat broadcast. Kalau taskbar masih putih, sign out/in."
}

$desktop = [Environment]::GetFolderPath("Desktop")

# ====================== HAPUS APLIKASI ======================
function Wait-Uninstallers {
    # Uninstaller Inno/NSIS sering membuat proses anak lalu proses utama langsung selesai
    for ($i = 0; $i -lt 90; $i++) {
        $busy = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(unins\d*|_iu.*|_is.*|Un_A.*|Uninstall.*|helper|msiexec)$' -and $_.Id -ne $PID }
        # msiexec bisa tetap hidup sebagai service, jangan ditunggu terus
        $busy = $busy | Where-Object { $_.ProcessName -ne 'msiexec' }
        if (-not $busy) { break }
        Start-Sleep -Seconds 2
    }
}

function Remove-App {
    param([string]$Pattern, [string]$Label)

    Write-Host "Menghapus: $Label"
    $keys = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $apps = Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match $Pattern }

    if (-not $apps) {
        Write-Host "  Tidak terpasang, dilewati."
        return
    }

    foreach ($app in $apps) {
        try {
            $cmd = if ($app.UninstallString) { $app.UninstallString } else { $app.QuietUninstallString }
            if (-not $cmd) { Write-Host "  Tidak ada perintah uninstall untuk $($app.DisplayName)."; continue }

            if ($cmd -match "msiexec") {
                # Installer MSI (contoh: Strawberry Perl)
                if ($cmd -match "\{[0-9A-Fa-f\-]+\}") {
                    Start-Process "msiexec.exe" -ArgumentList "/x $($Matches[0]) /qn /norestart REBOOT=ReallySuppress" -Wait
                }
            } else {
                if ($cmd -match '^\s*"([^"]+)"\s*(.*)$') {
                    $exe = $Matches[1]; $uArgs = $Matches[2]
                } elseif ($cmd -match '^\s*(.+?\.exe)\s*(.*)$') {
                    $exe = $Matches[1]; $uArgs = $Matches[2]
                } else {
                    Write-Host "  Format uninstall tidak dikenali untuk $($app.DisplayName)."; continue
                }

                $name = [IO.Path]::GetFileName($exe).ToLower()
                if     ($name -like "unins*")             { $uArgs += " /VERYSILENT /SUPPRESSMSGBOXES /NORESTART" }  # Inno Setup (R, Rtools)
                elseif ($app.DisplayName -match "Chrome") { $uArgs += " --force-uninstall" }                          # Chrome
                else                                      { $uArgs += " /S" }                                         # NSIS (Firefox, Unity Hub)

                Start-Process -FilePath $exe -ArgumentList $uArgs.Trim() -Wait
            }
            Wait-Uninstallers
            Write-Host "  $($app.DisplayName) dihapus."
        } catch {
            Write-Host "  Gagal menghapus $($app.DisplayName): $_"
        }
    }
}

Write-Host "===== HAPUS APLIKASI ====="
# Tutup dulu program yang sedang berjalan supaya uninstall tidak minta konfirmasi
Stop-Process -Name chrome, firefox, "Unity Hub", Unity -Force -ErrorAction SilentlyContinue

Remove-App -Pattern "^Google Chrome$"       -Label "Google Chrome"
Remove-App -Pattern "^Mozilla Firefox"      -Label "Mozilla Firefox"
Remove-App -Pattern "^R for Windows"        -Label "R for Windows"
Remove-App -Pattern "^Rtools"               -Label "Rtools"
Remove-App -Pattern "^Strawberry Perl"      -Label "Strawberry Perl"
Remove-App -Pattern "^Unity Hub"            -Label "Unity Hub"

# ====================== INSTALL ANTIGRAVITY IDE ======================
Write-Host "===== INSTALL ANTIGRAVITY IDE ====="

$agUrl = "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/windows-x64/Antigravity%20IDE.exe"
$agInstaller = "$env:TEMP\AntigravityIDE.exe"

try {
    Invoke-WebRequest -Uri $agUrl -OutFile $agInstaller -UseBasicParsing -ErrorAction Stop
    Write-Host "Download selesai."

    # Mode silent (Inno Setup). Kalau installer tidak mendukung, auto-clicker yang menekan Next/Install/Finish.
    Start-Process $agInstaller -ArgumentList "/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /MERGETASKS=!runcode" -Wait
    Start-Sleep -Seconds 5
    Write-Host "Antigravity IDE selesai diinstall."

    Remove-Item $agInstaller -Force -ErrorAction SilentlyContinue
} catch {
    Write-Host "Gagal install Antigravity IDE: $_"
}

# Buat shortcut Antigravity
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

function Find-RobloxStudio {
    Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions" -Filter "RobloxStudioBeta.exe" -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

# Urutan: repo kamu dulu, kalau gagal (misal 404) pakai installer resmi Roblox
$robloxSources = @(
    "https://raw.githubusercontent.com/oyy-gus/setup-windows/master/installer/RobloxStudioInstaller.exe",
    "https://setup.rbxcdn.com/RobloxStudioInstaller.exe"
)
$installerPath = "$env:TEMP\RobloxStudioInstaller.exe"
$studio = Find-RobloxStudio

foreach ($url in $robloxSources) {
    if ($studio) { break }
    try {
        Write-Host "Download dari: $url"
        Invoke-WebRequest -Uri $url -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
        if ((Get-Item $installerPath).Length -lt 100000) { throw "File installer tidak valid (terlalu kecil)." }
        Write-Host "Download selesai, menginstall..."

        $p = Start-Process $installerPath -PassThru
        $p.WaitForExit(300000) | Out-Null

        for ($i = 0; $i -lt 60 -and -not $studio; $i++) {
            Start-Sleep -Seconds 5
            $studio = Find-RobloxStudio
        }
    } catch {
        Write-Host "Gagal dari sumber ini: $_"
    }
}
Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

# ====================== BUAT SHORTCUT ROBLOX ======================
Write-Host "===== BUAT SHORTCUT ROBLOX ====="

if ($studio) {
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("$desktop\Roblox Studio.lnk")
    $Shortcut.TargetPath = $studio.FullName
    $Shortcut.IconLocation = "$($studio.FullName),0"
    $Shortcut.Save()
    Write-Host "Roblox Studio terinstall, shortcut dibuat."
} else {
    Write-Host "Roblox Studio GAGAL terinstall." -ForegroundColor Red
}

# ====================== MATIKAN AUTO-CLICKER ======================
if ($clickerProc -and -not $clickerProc.HasExited) { Stop-Process -Id $clickerProc.Id -Force -ErrorAction SilentlyContinue }
Remove-Item $clickerPath -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "===== SELESAI - SEMUA SIAP DIGUNAKAN ====="
