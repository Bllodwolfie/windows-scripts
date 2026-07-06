$source = "C:\Users\nekdo\Downloads"
$cutoff = (Get-Date).AddDays(-7)
$logDir = "C:\Users\nekdo\Documents\Script_Logs"
$logFile = Join-Path $logDir "CleanupLog.txt"

$null = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue

$deleteExts = @('.zip', '.rar', '.7z', '.ttf', '.otf', '.exe', '.msi')

$categories = @{
    "C:\Users\nekdo\Music\Misc"              = @('.aac', '.aiff', '.alac', '.ape', '.dsf', '.flac', '.m4a', '.m4b', '.mid', '.midi', '.mp3', '.oga', '.ogg', '.opus', '.wav', '.wma')
    "C:\Users\nekdo\Videos\Misc"             = @('.3gp', '.asf', '.avi', '.flv', '.m2ts', '.m4v', '.mkv', '.mov', '.mp4', '.mpeg', '.mpg', '.ogv', '.ts', '.vob', '.webm', '.wmv')
    "C:\Users\nekdo\Pictures\Misc"           = @('.avif', '.bmp', '.cr2', '.dng', '.eps', '.gif', '.heic', '.heif', '.ico', '.jpeg', '.jpg', '.nef', '.png', '.psd', '.raw', '.svg', '.tif', '.tiff', '.webp')
    "C:\Users\nekdo\Documents\Modeling"      = @('.3dm', '.3ds', '.3mf', '.blend', '.c4d', '.dae', '.dxf', '.fbx', '.glb', '.gltf', '.iges', '.igs', '.lwo', '.lxo', '.max', '.mb', '.ma', '.obj', '.ply', '.skp', '.sldasm', '.sldprt', '.step', '.stp', '.stl', '.usdz', '.vrml', '.wrl', '.x3d')
    "C:\Users\nekdo\Documents\Spreadsheets"  = @('.csv', '.numbers', '.ods', '.tsv', '.xls', '.xlsb', '.xlsm', '.xlsx', '.xlt', '.xltm', '.xltx', '.xlw')
    "C:\Users\nekdo\Documents\Presentations" = @('.key', '.odp', '.pps', '.ppsx', '.ppt', '.pptm', '.pptx', '.pot', '.potm', '.potx')
    "C:\Users\nekdo\Documents\Text"          = @('.doc', '.docb', '.docm', '.docx', '.dot', '.dotm', '.dotx', '.epub', '.log', '.md', '.msg', '.odt', '.pdf', '.rtf', '.tex', '.txt', '.wpd', '.wps')
    "C:\Users\nekdo\Documents\Configuration" = @('.cfg', '.conf', '.config', '.edmx', '.env', '.hjson', '.ics', '.inc', '.inf', '.ini', '.ipynb', '.json', '.jsonc', '.nfo', '.plist', '.properties', '.reg', '.resx', '.sql', '.strings', '.template', '.tmpl', '.toml', '.vdf', '.xaml', '.xml', '.xsd', '.xslt', '.yaml', '.yml')
}

$extMap = @{}
foreach ($dest in $categories.Keys) {
    foreach ($ext in $categories[$dest]) {
        $extMap[$ext] = $dest
    }
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"[$timestamp] Cleanup started" | Out-File -FilePath $logFile -Append -Encoding utf8

Get-ChildItem -LiteralPath $source -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff } | ForEach-Object {
    $ext = $_.Extension.ToLower()
    $name = $_.Name

    if ($deleteExts -contains $ext) {
        try {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            "[$timestamp] DELETED : $name" | Out-File -FilePath $logFile -Append -Encoding utf8
        } catch {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            "[$timestamp] ERROR   : Failed to delete $name : $_" | Out-File -FilePath $logFile -Append -Encoding utf8
        }
        return
    }

    if ($extMap.ContainsKey($ext)) {
        $destDir = $extMap[$ext]
        try {
            $null = New-Item -ItemType Directory -Path $destDir -Force -ErrorAction Stop
            Move-Item -LiteralPath $_.FullName -Destination $destDir -Force -ErrorAction Stop
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            "[$timestamp] MOVED   : $name -> $destDir" | Out-File -FilePath $logFile -Append -Encoding utf8
        } catch {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            "[$timestamp] ERROR   : Failed to move $name to $destDir : $_" | Out-File -FilePath $logFile -Append -Encoding utf8
        }
    } else {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "[$timestamp] SKIPPED : $name (unrecognized extension: $ext)" | Out-File -FilePath $logFile -Append -Encoding utf8
    }
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"[$timestamp] Cleanup finished" | Out-File -FilePath $logFile -Append -Encoding utf8
