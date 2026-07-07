# Generates a self-contained HTML system health report (system info, CPU, GPU,
# memory, storage, network, top processes, recent event-log errors, Windows
# Update status) using a Catppuccin Mocha/Latte theme that follows the
# Windows dark/light mode setting. Output is a single .html file plus two
# cat-mascot images copied alongside it.

$Config = @{
    # Output
    OutputDir           = "$env:USERPROFILE\Documents"     # Where the report (and images) are written
    OutputFile          = "System_Health_Report.html"
    CatImageDark        = "cat_bobber-dark.png"             # Mascot image shown in dark (Mocha) theme
    CatImageLight       = "cat_bobber-light.png"             # Mascot image shown in light (Latte) theme

    # Data collection
    MaxTopProcesses     = 10   # How many processes to list in the "Top Processes" table
    MaxErrorEvents      = 20   # Max System-log error/critical events to pull
    ErrorWindowHours    = 24   # Only look back this many hours for errors

    # Risk thresholds (percent) — below Green = low, below Yellow = medium, above = high
    # Used to color usage bars (RAM, disk) via Get-RiskColor
    RiskGreen           = 60
    RiskYellow          = 80

    # Catppuccin Mocha (dark) color palette. Emitted as CSS variables (see Write-Palette).
    Mocha = @{
        base     = '#1e1e2e'
        mantle   = '#181825'
        crust    = '#11111b'
        surface0 = '#313244'
        surface1 = '#45475a'
        surface2 = '#585b70'
        overlay0 = '#6c7086'
        overlay1 = '#7f849c'
        overlay2 = '#9399b2'
        subtext0 = '#a6adc8'
        subtext1 = '#bac2de'
        text     = '#cdd6f4'
        lavender = '#b4befe'
        blue     = '#89b4fa'
        mauve    = '#cba6f7'
        green    = '#a6e3a1'
        yellow   = '#f9e2af'
        peach    = '#fab387'
        red      = '#f38ba8'
        pink     = '#f5c2e7'
        toolbarBg = 'rgba(255,255,255,0.1)'
    }

    # Catppuccin Latte (light) color palette. Emitted as CSS variables (see Write-Palette).
    Latte = @{
        base     = '#eff1f5'
        mantle   = '#e6e9ef'
        crust    = '#dce0e8'
        surface0 = '#ccd0da'
        surface1 = '#bcc0cc'
        surface2 = '#acb0be'
        overlay0 = '#9ca0b0'
        overlay1 = '#8c8fa1'
        overlay2 = '#7c7f93'
        subtext0 = '#6c6f85'
        subtext1 = '#5c5f77'
        text     = '#4c4f69'
        lavender = '#7287fd'
        blue     = '#1e66f5'
        mauve    = '#8839ef'
        green    = '#40a02b'
        yellow   = '#df8e1d'
        peach    = '#fe640b'
        red      = '#d20f39'
        pink     = '#ea76cb'
        toolbarBg = 'rgba(0,0,0,0.05)'
    }
}

# Converts a palette hashtable (Mocha or Latte) into CSS custom-property
# declarations (--base, --text, --green, etc.) used inside :root / [data-theme].
function Write-Palette($p) {
    "    --base: $($p.base); --mantle: $($p.mantle); --crust: $($p.crust);"
    "    --surface0: $($p.surface0); --surface1: $($p.surface1); --surface2: $($p.surface2);"
    "    --overlay0: $($p.overlay0); --overlay1: $($p.overlay1); --overlay2: $($p.overlay2);"
    "    --subtext0: $($p.subtext0); --subtext1: $($p.subtext1); --text: $($p.text);"
    "    --lavender: $($p.lavender); --blue: $($p.blue); --mauve: $($p.mauve);"
    "    --green: $($p.green); --yellow: $($p.yellow); --peach: $($p.peach); --red: $($p.red); --pink: $($p.pink);"
    "    --toolbar-bg: $($p.toolbarBg);"
}

$outputDir = $Config.OutputDir
$outputPath = "$outputDir\$($Config.OutputFile)"

# Read the Windows setting for light vs dark apps theme to pick the palette
$isLight = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue).AppsUseLightTheme -eq 1

# Mascot images live in a shared "assets" folder two levels up from the script;
# fall back to Downloads if that folder isn't found (e.g. script run standalone)
$assetDir = if (Test-Path "$PSScriptRoot\..\..\assets") { "$PSScriptRoot\..\..\assets" } else { "$env:USERPROFILE\Downloads" }
Copy-Item -LiteralPath "$assetDir\Cat_bobber-dark.png" -Destination "$outputDir\$($Config.CatImageDark)" -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath "$assetDir\Cat_bobber-light.png" -Destination "$outputDir\$($Config.CatImageLight)" -Force -ErrorAction SilentlyContinue

$themeName = if ($isLight) { "Latte" } else { "Mocha" }

# ----- Data collection -----
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor
$mem = Get-CimInstance Win32_OperatingSystem                       # Reused for memory figures (same class as $os)
$disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"   # DriveType=3 = fixed local disks only
$net = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }
$gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1
$procs = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First $($Config.MaxTopProcesses)
$bootTime = $os.LastBootUpTime
$uptime = if ($bootTime) { (Get-Date) - $bootTime } else { [TimeSpan]0 }
# Level 1,2 = Critical and Error entries in the System log from the last ErrorWindowHours
$errors = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddHours(-$Config.ErrorWindowHours)} -MaxEvents $Config.MaxErrorEvents -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message

# VRAM: prefer nvidia-smi for accuracy, fallback to WMI
$vramGB = "Unknown"
try {
    $nvidiaOut = & nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>&1
    if ($nvidiaOut -match '^\d+') {
        $vramGB = [math]::Round([double]$matches[0] / 1024, 1)
    } else { throw "no match" }
} catch {
    if ($gpu.AdapterRAM -and $gpu.AdapterRAM -gt 0) {
        $vramGB = [math]::Round($gpu.AdapterRAM / 1GB, 1)
    }
}

# Windows Update last check
$wuLastCheck = "Unknown"
try {
    $session = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
    $searcher = $session.CreateUpdateSearcher()
    $count = $searcher.GetTotalHistoryCount()
    if ($count -gt 0) {
        $lastEntry = $searcher.QueryHistory(0, 1) | Select-Object -First 1
        if ($lastEntry -and $lastEntry.Date) {
            $wuLastCheck = $lastEntry.Date.ToString("yyyy-MM-dd HH:mm")
        }
    }
} catch {}

# Note: TotalVisibleMemorySize/FreePhysicalMemory are reported in KB, so /1MB converts to GB
$totalMem = [math]::Round($mem.TotalVisibleMemorySize / 1MB, 1)
$freeMem = [math]::Round($mem.FreePhysicalMemory / 1MB, 1)
$usedMem = [math]::Round($totalMem - $freeMem, 1)
$memPct = if ($totalMem -gt 0) { [math]::Round($usedMem / $totalMem * 100, 0) } else { 0 }

# Maps a usage percentage to a CSS color variable based on the RiskGreen/RiskYellow thresholds
function Get-RiskColor($pct) {
    if ($pct -lt $Config.RiskGreen) { return "var(--green)" }
    elseif ($pct -lt $Config.RiskYellow) { return "var(--yellow)" }
    else { return "var(--red)" }
}

$sections = @()

# Summary cards
$summaryCards = @"
        <div class="summary">
            <div class="card" style="border-left: 4px solid var(--mauve);">
                <span class="card-label">OS</span>
                <span class="card-value">$($os.Caption -replace 'Microsoft ','')</span>
                <span class="card-sub">Build $($os.BuildNumber)</span>
            </div>
            <div class="card" style="border-left: 4px solid var(--blue);">
                <span class="card-label">Uptime</span>
                <span class="card-value">$($uptime.Days)d $($uptime.Hours)h</span>
                <span class="card-sub">since $($bootTime.ToString('MMM dd, HH:mm'))</span>
            </div>
            <div class="card" style="border-left: 4px solid var(--peach);">
                <span class="card-label">CPU</span>
                <span class="card-value">$(($cpu.Name -replace '\(R\)|\(TM\)|®|™').Trim())</span>
                <span class="card-sub">$($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads</span>
            </div>
            <div class="card" style="border-left: 4px solid $(Get-RiskColor $memPct);">
                <span class="card-label">RAM</span>
                <span class="card-value">$usedMem / $totalMem GB</span>
                <div class="bar"><div class="bar-fill" style="width:${memPct}%;background:$(Get-RiskColor $memPct);"></div></div>
            </div>
"@

$diskIdx = 0
foreach ($d in $disks) {
    $total = [math]::Round($d.Size / 1GB, 1)
    $free = [math]::Round($d.FreeSpace / 1GB, 1)
    $used = [math]::Round($total - $free, 1)
    $pct = if ($total -gt 0) { [math]::Round($used / $total * 100, 0) } else { 0 }
    $label = if ($d.VolumeName) { $d.VolumeName } else { "Local Disk" }
    $summaryCards += @"
            <div class="card" style="border-left: 4px solid $(Get-RiskColor $pct);">
                <span class="card-label">$label ($($d.DeviceID))</span>
                <span class="card-value">$used / $total GB</span>
                <div class="bar"><div class="bar-fill" style="width:${pct}%;background:$(Get-RiskColor $pct);"></div></div>
            </div>
"@
}
$summaryCards += "        </div>"

# Section: System Info
$sysRows = @"
            <tr><td class="key">Hostname</td><td>$($cs.Name)</td></tr>
            <tr><td class="key">OS</td><td>$($os.Caption)</td></tr>
            <tr><td class="key">Version</td><td>$($os.Version) (Build $($os.BuildNumber))</td></tr>
            <tr><td class="key">Architecture</td><td>$($os.OSArchitecture)</td></tr>
            <tr><td class="key">Install Date</td><td>$($os.InstallDate.ToString('yyyy-MM-dd HH:mm'))</td></tr>
            <tr><td class="key">Last Boot</td><td>$($bootTime.ToString('yyyy-MM-dd HH:mm:ss'))</td></tr>
            <tr><td class="key">Uptime</td><td>$($uptime.Days) days, $($uptime.Hours) hours, $($uptime.Minutes) minutes</td></tr>
            <tr><td class="key">Manufacturer</td><td>$($cs.Manufacturer)</td></tr>
            <tr><td class="key">Model</td><td>$($cs.Model)</td></tr>
"@

# Section: Memory
$memRows = @"
            <tr><td class="key">Total</td><td>$totalMem GB</td></tr>
            <tr><td class="key">Used</td><td>$usedMem GB</td></tr>
            <tr><td class="key">Free</td><td>$freeMem GB</td></tr>
            <tr><td class="key">Usage</td><td><div class="bar" style="max-width:300px"><div class="bar-fill" style="width:${memPct}%;background:$(Get-RiskColor $memPct);"></div></div> $memPct%</td></tr>
"@

# Section: Disks
$diskRows = ""
foreach ($d in $disks) {
    $total = [math]::Round($d.Size / 1GB, 1)
    $free = [math]::Round($d.FreeSpace / 1GB, 1)
    $used = [math]::Round($total - $free, 1)
    $pct = if ($total -gt 0) { [math]::Round($used / $total * 100, 0) } else { 0 }
    $label = if ($d.VolumeName) { $d.VolumeName } else { "Local Disk" }
    $diskRows += @"
            <tr><td class="key">$label ($($d.DeviceID))</td><td><div class="bar" style="max-width:300px"><div class="bar-fill" style="width:${pct}%;background:$(Get-RiskColor $pct);"></div></div> $used / $total GB ($pct%)</td></tr>
"@
}

# Section: Network
$netRows = ""
foreach ($n in $net) {
    $netRows += @"
            <tr><td class="key">$($n.Description)</td><td>Connected</td></tr>
"@
}

# Section: GPU
$gpuRows = ""
if ($gpu) {
    $gpuRows = @"
            <tr><td class="key">GPU</td><td>$($gpu.Name)</td></tr>
            <tr><td class="key">VRAM</td><td>$vramGB GB</td></tr>
            <tr><td class="key">Driver</td><td>$($gpu.DriverVersion)</td></tr>
"@
}

# Section: Top Processes
$procRows = ""
$i = 1
foreach ($p in $procs) {
    $mb = [math]::Round($p.WorkingSet64 / 1MB, 1)
    $procRows += @"
            <tr><td>$i</td><td>$($p.Name)</td><td>$($p.ProcessName)</td><td>$mb MB</td><td>$($p.Id)</td></tr>
"@
    $i++
}

# Section: Recent Errors
$errRows = ""
if ($errors) {
    foreach ($e in $errors) {
        $msg = ($e.Message -split "`n")[0]
        if ($msg.Length -gt 150) { $msg = $msg.Substring(0,150) + "..." }
        $color = if ($e.LevelDisplayName -eq 'Critical') { "var(--red)" } else { "var(--yellow)" }
        $errRows += @"
            <tr><td style="color:$color">$($e.LevelDisplayName)</td><td>$($e.TimeCreated.ToString('MMM dd HH:mm'))</td><td>$($e.ProviderName)</td><td>$msg</td></tr>
"@
    }
} else {
    $errRows = '<tr><td colspan="4" style="text-align:center;color:var(--subtext0);">No critical errors in the last 24 hours</td></tr>'
}

# Section: Windows Update
$wuRows = "<tr><td class='key'>Last Successful Check</td><td>$wuLastCheck</td></tr>"

# ----- HTML assembly -----
# The full HTML/CSS/JS is built line-by-line into a StringBuilder for
# performance (much faster than repeated string concatenation).
$html = [System.Text.StringBuilder]::new()
[void]$html.AppendLine('<!DOCTYPE html>')
[void]$html.AppendLine("<html lang=""en"" data-theme=""$(if ($isLight) { 'latte' } else { 'mocha' })"">")
[void]$html.AppendLine('<head>')
[void]$html.AppendLine('<meta charset="UTF-8">')
[void]$html.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1.0">')
[void]$html.AppendLine("<title>System Health Report - $($cs.Name)</title>")
[void]$html.AppendLine('<style>')
# :root defaults to Mocha; [data-theme="..."] overrides let the in-page toggle
# switch palettes instantly by flipping the html element's data-theme attribute
[void]$html.AppendLine(':root {')
foreach ($line in (Write-Palette $Config.Mocha)) { [void]$html.AppendLine($line) }
[void]$html.AppendLine('}')
[void]$html.AppendLine('[data-theme="mocha"] {')
foreach ($line in (Write-Palette $Config.Mocha)) { [void]$html.AppendLine($line) }
[void]$html.AppendLine('}')
[void]$html.AppendLine('[data-theme="latte"] {')
foreach ($line in (Write-Palette $Config.Latte)) { [void]$html.AppendLine($line) }
[void]$html.AppendLine('}')
[void]$html.AppendLine('* { margin: 0; padding: 0; box-sizing: border-box; }')
[void]$html.AppendLine('html { scroll-behavior: smooth; }')
[void]$html.AppendLine("body { font-family: 'Segoe UI', -apple-system, sans-serif; background: var(--base); color: var(--text); padding: 20px; }")
[void]$html.AppendLine('')
[void]$html.AppendLine('.header { display: flex; align-items: center; padding: 12px 20px; margin-bottom: 28px; background: color-mix(in srgb, var(--mantle) 80%, transparent); backdrop-filter: blur(8px); border-radius: 12px; position: sticky; top: 0; z-index: 100; }')
[void]$html.AppendLine('.header-body { flex: 1; text-align: center; }')
[void]$html.AppendLine('h1 { font-size: 28px; font-weight: 700; color: var(--text); }')
[void]$html.AppendLine('.subtitle { color: var(--subtext0); font-size: 14px; margin-top: 6px; }')
[void]$html.AppendLine('')
[void]$html.AppendLine('h2 { font-size: 18px; font-weight: 600; margin: 32px 0 14px; padding-bottom: 8px; border-bottom: 2px solid var(--surface0); color: var(--text); display: flex; align-items: center; gap: 8px; }')
[void]$html.AppendLine('h2 .accent { display: inline-block; width: 10px; height: 10px; border-radius: 50%; background: var(--mauve); animation: pulse-dot 2s ease-in-out infinite; overflow: hidden; font-size: 0; }')
[void]$html.AppendLine('@keyframes pulse-dot { 0%,100% { opacity: 1; transform: scale(1); } 50% { opacity: 0.6; transform: scale(0.8); } }')
[void]$html.AppendLine('')
[void]$html.AppendLine('.summary { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 12px; margin-bottom: 8px; }')
[void]$html.AppendLine('.card { background: var(--mantle); border-radius: 10px; padding: 16px 18px; transition: transform 0.25s cubic-bezier(0.4,0,0.2,1), box-shadow 0.25s cubic-bezier(0.4,0,0.2,1); cursor: default; position: relative; overflow: hidden; }')
[void]$html.AppendLine('.card:hover { transform: translateY(-4px); box-shadow: 0 8px 24px rgba(0,0,0,0.2); }')
[void]$html.AppendLine(".card::after { content: ''; position: absolute; top: 0; left: 0; width: 100%; height: 100%; background: linear-gradient(135deg, transparent 60%, rgba(255,255,255,0.02)); pointer-events: none; }")
[void]$html.AppendLine('.card-label { display: block; font-size: 11px; text-transform: uppercase; letter-spacing: 0.6px; color: var(--subtext0); margin-bottom: 4px; }')
[void]$html.AppendLine('.card-value { display: block; font-size: 20px; font-weight: 700; color: var(--text); letter-spacing: -0.3px; }')
[void]$html.AppendLine('.card-sub { display: block; font-size: 12px; color: var(--overlay1); margin-top: 2px; }')
[void]$html.AppendLine('')
[void]$html.AppendLine('.bar { height: 6px; background: var(--surface0); border-radius: 4px; margin-top: 6px; overflow: hidden; }')
[void]$html.AppendLine('.bar-fill { height: 100%; border-radius: 4px; transition: width 1.2s cubic-bezier(0.4,0,0.2,1); }')
[void]$html.AppendLine('')
[void]$html.AppendLine('table { width: 100%; border-collapse: collapse; background: var(--mantle); border-radius: 10px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.06); }')
[void]$html.AppendLine('th { background: var(--surface0); color: var(--subtext1); font-size: 11px; text-transform: uppercase; letter-spacing: 0.6px; padding: 11px 14px; text-align: left; font-weight: 600; }')
[void]$html.AppendLine('td { padding: 9px 14px; border-bottom: 1px solid var(--surface0); font-size: 13px; vertical-align: top; }')
[void]$html.AppendLine('tr:last-child td { border-bottom: none; }')
[void]$html.AppendLine('tbody tr { transition: background 0.2s; }')
[void]$html.AppendLine('tbody tr:hover { background: rgba(255,255,255,0.03); }')
[void]$html.AppendLine('.key { color: var(--subtext0); white-space: nowrap; width: 180px; font-weight: 500; }')
[void]$html.AppendLine('')
[void]$html.AppendLine('.fade-section { opacity: 0; transform: translateY(20px); transition: opacity 0.6s cubic-bezier(0.4,0,0.2,1), transform 0.6s cubic-bezier(0.4,0,0.2,1); }')
[void]$html.AppendLine('.fade-section.visible { opacity: 1; transform: translateY(0); }')
[void]$html.AppendLine('')
[void]$html.AppendLine('.footer { margin-top: 40px; padding: 20px; border-top: 1px solid var(--surface0); font-size: 12px; color: var(--overlay0); text-align: center; }')
[void]$html.AppendLine('')
[void]$html.AppendLine('/* Intro */')
[void]$html.AppendLine('.intro {')
[void]$html.AppendLine('    height: 100vh; display: flex; flex-direction: column;')
[void]$html.AppendLine('    align-items: center; justify-content: center;')
[void]$html.AppendLine('    text-align: center; gap: 16px;')
[void]$html.AppendLine('}')
[void]$html.AppendLine('.intro-cat {')
[void]$html.AppendLine('    width: 200px; height: auto;')
[void]$html.AppendLine('    image-rendering: pixelated;')
[void]$html.AppendLine('}')
[void]$html.AppendLine('.intro-cat-mocha { display: block; }')
[void]$html.AppendLine('.intro-cat-latte { display: none; }')
[void]$html.AppendLine('[data-theme="latte"] .intro-cat-mocha { display: none; }')
[void]$html.AppendLine('[data-theme="latte"] .intro-cat-latte { display: block; }')
[void]$html.AppendLine('.intro h1 {')
[void]$html.AppendLine('    font-size: 32px; font-weight: 700; color: var(--text);')
[void]$html.AppendLine('    margin: 0; border: none;')
[void]$html.AppendLine('}')
[void]$html.AppendLine('.intro-body {')
[void]$html.AppendLine('    font-size: 18px; color: var(--subtext1);')
[void]$html.AppendLine('}')
[void]$html.AppendLine('.intro-scroll {')
[void]$html.AppendLine('    font-size: 14px; color: var(--overlay0);')
[void]$html.AppendLine('    margin-top: 24px; letter-spacing: 8px;')
[void]$html.AppendLine('    animation: bob 2s ease-in-out infinite;')
[void]$html.AppendLine('}')
[void]$html.AppendLine('@keyframes bob {')
[void]$html.AppendLine('    0%, 100% { transform: translateY(0); }')
[void]$html.AppendLine('    50% { transform: translateY(8px); }')
[void]$html.AppendLine('}')
[void]$html.AppendLine('')
[void]$html.AppendLine('/* Both header buttons - shared style */')
[void]$html.AppendLine('.header .sidebar-toggle,')
[void]$html.AppendLine('.header .theme-toggle {')
[void]$html.AppendLine('    width: 40px; height: 40px; border-radius: 50%;')
[void]$html.AppendLine('    background: var(--toolbar-bg); border: 2px solid var(--surface0);')
[void]$html.AppendLine('    color: var(--text); cursor: pointer;')
[void]$html.AppendLine('    flex-shrink: 0;')
[void]$html.AppendLine('    display: flex; align-items: center; justify-content: center;')
[void]$html.AppendLine('    box-shadow: 0 2px 8px rgba(0,0,0,0.15);')
[void]$html.AppendLine('    transition: opacity 0.3s ease, transform 0.2s;')
[void]$html.AppendLine('}')
[void]$html.AppendLine('.header .sidebar-toggle:hover,')
[void]$html.AppendLine('.header .theme-toggle:hover { transform: scale(1.1); }')
[void]$html.AppendLine('.header .sidebar-toggle:focus-visible {')
[void]$html.AppendLine('    outline: 2px solid var(--mauve);')
[void]$html.AppendLine('    outline-offset: 3px;')
[void]$html.AppendLine('}')
[void]$html.AppendLine('')
[void]$html.AppendLine('/* Floating mode: buttons fixed to viewport corners, out of flex flow */')
[void]$html.AppendLine('.header.floating .sidebar-toggle {')
[void]$html.AppendLine('    position: fixed;')
[void]$html.AppendLine('    top: 22px;')
[void]$html.AppendLine('    left: 40px;')
[void]$html.AppendLine('    z-index: 9999;')
[void]$html.AppendLine('}')
[void]$html.AppendLine('.header.floating .theme-toggle {')
[void]$html.AppendLine('    position: fixed;')
[void]$html.AppendLine('    top: 22px;')
[void]$html.AppendLine('    right: 40px;')
[void]$html.AppendLine('    z-index: 9999;')
[void]$html.AppendLine('}')
[void]$html.AppendLine('')
[void]$html.AppendLine('/* Docked mode: in flex flow — centered by align-items: center */')
[void]$html.AppendLine('')
[void]$html.AppendLine('/* Hide hamburger when sidebar is open */')
[void]$html.AppendLine('.sidebar.open ~ .header .sidebar-toggle { display: none; }')
[void]$html.AppendLine('')
[void]$html.AppendLine('/* Theme icon visibility */')
[void]$html.AppendLine('.theme-toggle .icon-moon { display: flex; align-items: center; justify-content: center; }')
[void]$html.AppendLine('.theme-toggle .icon-sun { display: none; align-items: center; justify-content: center; }')
[void]$html.AppendLine('[data-theme="latte"] .theme-toggle .icon-moon { display: none; }')
[void]$html.AppendLine('[data-theme="latte"] .theme-toggle .icon-sun { display: flex; }')
[void]$html.AppendLine('')
[void]$html.AppendLine('/* Sidebar */')
[void]$html.AppendLine('.sidebar {')
[void]$html.AppendLine('    position: fixed; top: 0; left: 0; height: 100%; z-index: 9998;')
[void]$html.AppendLine('    width: 220px; background: color-mix(in srgb, var(--mantle) 95%, transparent);')
[void]$html.AppendLine('    backdrop-filter: blur(10px);')
[void]$html.AppendLine('    border-right: 1px solid var(--surface0);')
[void]$html.AppendLine('    padding: 0 0 56px;')
[void]$html.AppendLine('    transform: translateX(-100%); transition: transform 0.35s cubic-bezier(0.4,0,0.2,1);')
[void]$html.AppendLine('    overflow-y: auto;')
[void]$html.AppendLine('}')
[void]$html.AppendLine('.sidebar.open { transform: translateX(0); }')
[void]$html.AppendLine('.sidebar-header {')
[void]$html.AppendLine('    position: sticky; top: 0; z-index: 2;')
[void]$html.AppendLine('    display: flex; align-items: center;')
[void]$html.AppendLine('    padding: 0 8px 0 0;')
[void]$html.AppendLine('    background: color-mix(in srgb, var(--mantle) 95%, transparent);')
[void]$html.AppendLine('    backdrop-filter: blur(10px);')
[void]$html.AppendLine('}')
[void]$html.AppendLine('.sidebar-header h3 {')
[void]$html.AppendLine('    flex: 1; padding: 16px 16px 8px; margin: 0;')
[void]$html.AppendLine('    font-size: 12px; text-transform: uppercase; letter-spacing: 1px;')
[void]$html.AppendLine('    color: var(--overlay0);')
[void]$html.AppendLine('}')
[void]$html.AppendLine('.sidebar-close {')
[void]$html.AppendLine('    width: 28px; height: 28px; border-radius: 50%;')
[void]$html.AppendLine('    border: none; background: transparent;')
[void]$html.AppendLine('    color: var(--overlay0); cursor: pointer;')
[void]$html.AppendLine('    display: flex; align-items: center; justify-content: center;')
[void]$html.AppendLine('    transition: background 0.2s, color 0.2s;')
[void]$html.AppendLine('    flex-shrink: 0;')
[void]$html.AppendLine('}')
[void]$html.AppendLine('.sidebar-close:hover {')
[void]$html.AppendLine('    background: var(--surface0); color: var(--text);')
[void]$html.AppendLine('}')
[void]$html.AppendLine('.sidebar-links {')
[void]$html.AppendLine('    padding: 0;')
[void]$html.AppendLine('}')
[void]$html.AppendLine('.sidebar a {')
[void]$html.AppendLine('    display: block; padding: 8px 16px; border-radius: 6px;')
[void]$html.AppendLine('    color: var(--subtext1); text-decoration: none; font-size: 13px;')
[void]$html.AppendLine('    transition: background 0.2s, color 0.2s;')
[void]$html.AppendLine('}')
[void]$html.AppendLine('.sidebar a:hover {')
[void]$html.AppendLine('    background: var(--surface0); color: var(--text);')
[void]$html.AppendLine('}')
[void]$html.AppendLine('.sidebar-fade {')
[void]$html.AppendLine('    position: sticky; bottom: 0; height: 32px;')
[void]$html.AppendLine('    background: linear-gradient(to bottom, transparent, color-mix(in srgb, var(--mantle) 95%, transparent));')
[void]$html.AppendLine('    pointer-events: none;')
[void]$html.AppendLine('}')
[void]$html.AppendLine('.sidebar::-webkit-scrollbar { width: 5px; }')
[void]$html.AppendLine('.sidebar::-webkit-scrollbar-track { background: transparent; }')
[void]$html.AppendLine('.sidebar::-webkit-scrollbar-thumb { background: var(--surface1); border-radius: 3px; }')
[void]$html.AppendLine('</style>')
[void]$html.AppendLine('</head>')
[void]$html.AppendLine('<body>')
# Full-screen intro/splash panel shown before the report content
[void]$html.AppendLine('<div class="intro">')
[void]$html.AppendLine("    <img src='$($Config.CatImageDark)' alt='Cat' class='intro-cat intro-cat-mocha'>")
[void]$html.AppendLine("    <img src='$($Config.CatImageLight)' alt='Cat' class='intro-cat intro-cat-latte'>")
[void]$html.AppendLine("    <h1>Hello $($env:USERNAME)</h1>")
[void]$html.AppendLine("    <p class='intro-body'>Ready to see today's system report?</p>")
[void]$html.AppendLine("    <p class='intro-scroll'>&#9660; &#9660;</p>")
[void]$html.AppendLine('</div>')
# Collapsible jump-to navigation, toggled by the hamburger button
[void]$html.AppendLine('<nav class="sidebar" id="sidebar">')
[void]$html.AppendLine('    <div class="sidebar-header">')
[void]$html.AppendLine('        <h3>Jump to</h3>')
[void]$html.AppendLine('        <button class="sidebar-close" id="sidebarClose" aria-label="Close menu">')
[void]$html.AppendLine('            <svg viewBox="0 0 24 24" width="16" height="16"><line x1="18" y1="6" x2="6" y2="18" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="6" y1="6" x2="18" y2="18" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>')
[void]$html.AppendLine('        </button>')
[void]$html.AppendLine('    </div>')
[void]$html.AppendLine('    <div class="sidebar-links">')
[void]$html.AppendLine("    <a href='#sysinfo'>System Information</a>")
[void]$html.AppendLine("    <a href='#cpu'>CPU</a>")
[void]$html.AppendLine("    <a href='#gpu'>Graphics</a>")
[void]$html.AppendLine("    <a href='#memory'>Memory</a>")
[void]$html.AppendLine("    <a href='#storage'>Storage</a>")
[void]$html.AppendLine("    <a href='#network'>Network</a>")
[void]$html.AppendLine("    <a href='#processes'>Top Processes</a>")
[void]$html.AppendLine("    <a href='#errors'>Recent Errors</a>")
[void]$html.AppendLine("    <a href='#windows-update'>Windows Update</a>")
[void]$html.AppendLine('    </div>')
[void]$html.AppendLine('    <div class="sidebar-fade"></div>')
[void]$html.AppendLine('</nav>')
[void]$html.AppendLine('<div class="header" id="header">')
[void]$html.AppendLine('<button class="sidebar-toggle" id="sidebarToggle" aria-label="Menu">')
[void]$html.AppendLine('    <svg viewBox="0 0 24 24" width="22" height="22"><line x1="3" y1="6" x2="21" y2="6" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="3" y1="12" x2="21" y2="12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="3" y1="18" x2="21" y2="18" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>')
[void]$html.AppendLine('</button>')
[void]$html.AppendLine('<div class="header-body">')
[void]$html.AppendLine('<h1>System Health Report</h1>')
[void]$html.AppendLine("<div class=""subtitle"">$($cs.Name) &middot; $(Get-Date -Format 'yyyy-MM-dd HH:mm') &middot; Catppuccin $themeName</div>")
[void]$html.AppendLine('</div>')
[void]$html.AppendLine('<button class="theme-toggle" id="themeToggle" aria-label="Toggle theme">')
[void]$html.AppendLine('    <span class="icon-moon">')
[void]$html.AppendLine('        <svg viewBox="0 0 24 24" width="22" height="22"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>')
[void]$html.AppendLine('    </span>')
[void]$html.AppendLine('    <span class="icon-sun">')
[void]$html.AppendLine('        <svg viewBox="0 0 24 24" width="22" height="22"><circle cx="12" cy="12" r="5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><line x1="12" y1="1" x2="12" y2="3" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="12" y1="21" x2="12" y2="23" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="1" y1="12" x2="3" y2="12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="21" y1="12" x2="23" y2="12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>')
[void]$html.AppendLine('    </span>')
[void]$html.AppendLine('</button>')
[void]$html.AppendLine('</div>')
[void]$html.AppendLine('')
[void]$html.AppendLine($summaryCards)
[void]$html.AppendLine('')
# Each report section below is wrapped in a .fade-section div, which the
# IntersectionObserver script (further down) fades/slides it into view on scroll
[void]$html.AppendLine('<div class="fade-section">')
[void]$html.AppendLine('<h2 id="sysinfo"><span class="accent">&#9670;</span> System Information</h2>')
[void]$html.AppendLine('<table><tbody>')
[void]$html.AppendLine($sysRows)
[void]$html.AppendLine('</tbody></table>')
[void]$html.AppendLine('</div>')
[void]$html.AppendLine('')
[void]$html.AppendLine('<div class="fade-section">')
[void]$html.AppendLine('<h2 id="cpu"><span class="accent">&#9670;</span> CPU</h2>')
[void]$html.AppendLine('<table><tbody>')
[void]$html.AppendLine('<tr><td class="key">Processor</td><td>' + (($cpu.Name -replace '\(R\)|\(TM\)|®|™').Trim()) + '</td></tr>')
[void]$html.AppendLine("<tr><td class=""key"">Cores</td><td>$($cpu.NumberOfCores) physical / $($cpu.NumberOfLogicalProcessors) logical</td></tr>")
[void]$html.AppendLine("<tr><td class=""key"">Max Clock</td><td>$($cpu.MaxClockSpeed) MHz</td></tr>")
[void]$html.AppendLine("<tr><td class=""key"">L2 Cache</td><td>$($cpu.L2CacheSize) KB</td></tr>")
[void]$html.AppendLine("<tr><td class=""key"">L3 Cache</td><td>$($cpu.L3CacheSize) KB</td></tr>")
[void]$html.AppendLine('</tbody></table>')
[void]$html.AppendLine('</div>')
[void]$html.AppendLine('')
if ($gpuRows) {
    [void]$html.AppendLine('<div class="fade-section">')
    [void]$html.AppendLine('<h2 id="gpu"><span class="accent">&#9670;</span> Graphics</h2>')
    [void]$html.AppendLine('<table><tbody>')
    [void]$html.AppendLine($gpuRows)
    [void]$html.AppendLine('</tbody></table>')
    [void]$html.AppendLine('</div>')
    [void]$html.AppendLine('')
}
[void]$html.AppendLine('<div class="fade-section">')
[void]$html.AppendLine('<h2 id="memory"><span class="accent">&#9670;</span> Memory</h2>')
[void]$html.AppendLine('<table><tbody>')
[void]$html.AppendLine($memRows)
[void]$html.AppendLine('</tbody></table>')
[void]$html.AppendLine('</div>')
[void]$html.AppendLine('')
[void]$html.AppendLine('<div class="fade-section">')
[void]$html.AppendLine('<h2 id="storage"><span class="accent">&#9670;</span> Storage</h2>')
[void]$html.AppendLine('<table><tbody>')
[void]$html.AppendLine($diskRows)
[void]$html.AppendLine('</tbody></table>')
[void]$html.AppendLine('</div>')
[void]$html.AppendLine('')
[void]$html.AppendLine('<div class="fade-section">')
[void]$html.AppendLine('<h2 id="network"><span class="accent">&#9670;</span> Network</h2>')
[void]$html.AppendLine('<table><tbody>')
[void]$html.AppendLine($netRows)
[void]$html.AppendLine('</tbody></table>')
[void]$html.AppendLine('</div>')
[void]$html.AppendLine('')
[void]$html.AppendLine('<div class="fade-section">')
[void]$html.AppendLine('<h2 id="processes"><span class="accent">&#9670;</span> Top Processes (by memory)</h2>')
[void]$html.AppendLine('<table><thead><tr><th>#</th><th>Name</th><th>File</th><th>Memory</th><th>PID</th></tr></thead><tbody>')
[void]$html.AppendLine($procRows)
[void]$html.AppendLine('</tbody></table>')
[void]$html.AppendLine('</div>')
[void]$html.AppendLine('')
[void]$html.AppendLine('<div class="fade-section">')
[void]$html.AppendLine('<h2 id="errors"><span class="accent">&#9670;</span> Recent Errors (last 24h)</h2>')
[void]$html.AppendLine('<table><thead><tr><th>Level</th><th>Time</th><th>Source</th><th>Message</th></tr></thead><tbody>')
[void]$html.AppendLine($errRows)
[void]$html.AppendLine('</tbody></table>')
[void]$html.AppendLine('</div>')
[void]$html.AppendLine('')
[void]$html.AppendLine('<div class="fade-section">')
[void]$html.AppendLine('<h2 id="windows-update"><span class="accent">&#9670;</span> Windows Update</h2>')
[void]$html.AppendLine('<table><tbody>')
[void]$html.AppendLine($wuRows)
[void]$html.AppendLine('</tbody></table>')
[void]$html.AppendLine('</div>')
[void]$html.AppendLine('')
[void]$html.AppendLine("<div class=""footer"">Generated by SystemHealthReport.ps1 &middot; Catppuccin $themeName</div>")
[void]$html.AppendLine('')
# Page behavior: fade-in sections on scroll, animate usage bars, theme toggle, sidebar nav
[void]$html.AppendLine('<script>')
[void]$html.AppendLine('const observer = new IntersectionObserver((entries) => {')
[void]$html.AppendLine('  entries.forEach(entry => {')
[void]$html.AppendLine('    if (entry.isIntersecting) {')
[void]$html.AppendLine('      entry.target.classList.add("visible");')
[void]$html.AppendLine('    }')
[void]$html.AppendLine('  });')
[void]$html.AppendLine('}, { threshold: 0.1 });')
[void]$html.AppendLine('')
[void]$html.AppendLine("document.querySelectorAll('.fade-section').forEach(el => observer.observe(el));")
[void]$html.AppendLine('')
[void]$html.AppendLine('// Animate progress bars on load')
[void]$html.AppendLine("document.querySelectorAll('.bar-fill').forEach(bar => {")
[void]$html.AppendLine('  const width = bar.style.width;')
[void]$html.AppendLine("  bar.style.width = '0%';")
[void]$html.AppendLine('  setTimeout(() => { bar.style.width = width; }, 100);')
[void]$html.AppendLine('});')
[void]$html.AppendLine('')
[void]$html.AppendLine('// Header floating/docked state')
[void]$html.AppendLine('const header = document.getElementById("header");')
[void]$html.AppendLine('function updateFloating() {')
[void]$html.AppendLine('  header.classList.toggle("floating", header.getBoundingClientRect().top > 0);')
[void]$html.AppendLine('}')
[void]$html.AppendLine('window.addEventListener("scroll", updateFloating, { passive: true });')
[void]$html.AppendLine('updateFloating();')
[void]$html.AppendLine('')
[void]$html.AppendLine('// Theme toggle')
[void]$html.AppendLine('const toggle = document.getElementById("themeToggle");')
[void]$html.AppendLine('const html = document.documentElement;')
[void]$html.AppendLine("const sub = document.querySelector('.subtitle');")
[void]$html.AppendLine("const names = { mocha: 'Mocha', latte: 'Latte' };")
[void]$html.AppendLine('toggle.addEventListener("click", () => {')
[void]$html.AppendLine("    const cur = html.getAttribute('data-theme');")
[void]$html.AppendLine("    const next = cur === 'mocha' ? 'latte' : 'mocha';")
[void]$html.AppendLine("    html.setAttribute('data-theme', next);")
[void]$html.AppendLine('    if (sub) sub.textContent = sub.textContent.replace(/Mocha|Latte/, names[next]);')
[void]$html.AppendLine('});')
[void]$html.AppendLine('')
[void]$html.AppendLine('// Sidebar')
[void]$html.AppendLine('const sidebar = document.getElementById("sidebar");')
[void]$html.AppendLine('const sClose = document.getElementById("sidebarClose");')
[void]$html.AppendLine('')
[void]$html.AppendLine('function closeSidebar() { sidebar.classList.remove("open"); }')
[void]$html.AppendLine('')
[void]$html.AppendLine('sClose.addEventListener("click", closeSidebar);')
[void]$html.AppendLine('')
[void]$html.AppendLine("sidebar.querySelectorAll('a').forEach(a => {")
[void]$html.AppendLine('    a.addEventListener("click", closeSidebar);')
[void]$html.AppendLine('});')
[void]$html.AppendLine('')
[void]$html.AppendLine('// Sidebar toggle via event delegation (stable document reference)')
[void]$html.AppendLine('document.addEventListener("click", (e) => {')
[void]$html.AppendLine('    if (e.target.closest("#sidebarToggle")) {')
[void]$html.AppendLine('        sidebar.classList.toggle("open");')
[void]$html.AppendLine('    }')
[void]$html.AppendLine('});')
[void]$html.AppendLine('')
[void]$html.AppendLine('// Close sidebar on outside click')
[void]$html.AppendLine('document.addEventListener("click", (e) => {')
[void]$html.AppendLine('    if (!sidebar.contains(e.target) && !e.target.closest("#sidebarToggle")) {')
[void]$html.AppendLine('        closeSidebar();')
[void]$html.AppendLine('    }')
[void]$html.AppendLine('});')
[void]$html.AppendLine('</script>')
[void]$html.AppendLine('</body>')
[void]$html.AppendLine('</html>')

# Write with a UTF-8 BOM so the browser reliably renders special characters/icons
[System.IO.File]::WriteAllText($outputPath, $html.ToString(), [System.Text.UTF8Encoding]::new($true))