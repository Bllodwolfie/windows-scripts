# Sorts and cleans up the Downloads folder:
#   - Files older than CutoffDays with an extension in DeleteExts are deleted outright.
#   - Files older than CutoffDays with an extension listed under Categories are
#     moved into the matching destination folder (created if missing).
#   - Files with an unrecognized extension are left in place and logged as skipped.
# All actions are appended to LogFile for auditing.

$Config = @{
    SourceDir    = "$env:USERPROFILE\Downloads"                       # Folder to clean up
    CutoffDays   = 7                                                  # Only touch files older than this
    LogDir       = "$env:USERPROFILE\Documents\Script_Logs"
    LogFile      = "CleanupLog.txt"

    # Extensions to delete outright (installers, archives, fonts, etc.)
    DeleteExts   = @('.zip', '.rar', '.7z', '.ttf', '.otf', '.exe', '.msi')

    # Destination folder -> list of extensions routed there.
    # Add/remove extensions or destinations here to change sorting behavior.
    Categories   = @{
        "$env:USERPROFILE\Music\Misc"              = @('.aac', '.aiff', '.alac', '.ape', '.dsf', '.flac', '.m4a', '.m4b', '.mid', '.midi', '.mp3', '.oga', '.ogg', '.opus', '.wav', '.wma')
        "$env:USERPROFILE\Videos\Misc"             = @('.3gp', '.asf', '.avi', '.flv', '.m2ts', '.m4v', '.mkv', '.mov', '.mp4', '.mpeg', '.mpg', '.ogv', '.ts', '.vob', '.webm', '.wmv')
        "$env:USERPROFILE\Pictures\Misc"           = @('.avif', '.bmp', '.cr2', '.dng', '.eps', '.gif', '.heic', '.heif', '.ico', '.jpeg', '.jpg', '.nef', '.png', '.psd', '.raw', '.svg', '.tif', '.tiff', '.webp')
        "$env:USERPROFILE\Documents\Modeling"      = @('.3dm', '.3ds', '.3mf', '.blend', '.c4d', '.dae', '.dxf', '.fbx', '.glb', '.gltf', '.iges', '.igs', '.lwo', '.lxo', '.max', '.mb', '.ma', '.obj', '.ply', '.skp', '.sldasm', '.sldprt', '.step', '.stp', '.stl', '.usdz', '.vrml', '.wrl', '.x3d')
        "$env:USERPROFILE\Documents\Spreadsheets"  = @('.csv', '.numbers', '.ods', '.tsv', '.xls', '.xlsb', '.xlsm', '.xlsx', '.xlt', '.xltm', '.xltx', '.xlw')
        "$env:USERPROFILE\Documents\Presentations" = @('.key', '.odp', '.pps', '.ppsx', '.ppt', '.pptm', '.pptx', '.pot', '.potm', '.potx')
        "$env:USERPROFILE\Documents\Text"          = @('.doc', '.docb', '.docm', '.docx', '.dot', '.dotm', '.dotx', '.epub', '.log', '.md', '.msg', '.odt', '.pdf', '.rtf', '.tex', '.txt', '.wpd', '.wps')
        "$env:USERPROFILE\Documents\Configuration" = @('.cfg', '.conf', '.config', '.edmx', '.env', '.hjson', '.ics', '.inc', '.inf', '.ini', '.ipynb', '.json', '.jsonc', '.nfo', '.plist', '.properties', '.reg', '.resx', '.sql', '.strings', '.template', '.tmpl', '.toml', '.vdf', '.xaml', '.xml', '.xsd', '.xslt', '.yaml', '.yml')
    }
}

$source  = $Config.SourceDir
$cutoff  = (Get-Date).AddDays(-$Config.CutoffDays)
$logDir  = $Config.LogDir
$logFile = Join-Path $Config.LogDir $Config.LogFile
$deleteExts = $Config.DeleteExts
$categories = $Config.Categories

$null = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue

# Flatten Categories into a lookup table: extension -> destination folder
# (built once up front so each file only needs a single hashtable lookup)
$extMap = @{}
foreach ($dest in $categories.Keys) {
    foreach ($ext in $categories[$dest]) {
        $extMap[$ext] = $dest
    }
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"[$timestamp] Cleanup started" | Out-File -FilePath $logFile -Append -Encoding utf8

# Process every file in Downloads that's older than the cutoff
Get-ChildItem -LiteralPath $source -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff } | ForEach-Object {
    $ext = $_.Extension.ToLower()
    $name = $_.Name

    # Case 1: extension is on the delete list -> remove the file
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

    # Case 2: extension maps to a category folder -> move it there
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
        # Case 3: extension not recognized anywhere -> leave it alone, just log it
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "[$timestamp] SKIPPED : $name (unrecognized extension: $ext)" | Out-File -FilePath $logFile -Append -Encoding utf8
    }
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"[$timestamp] Cleanup finished" | Out-File -FilePath $logFile -Append -Encoding utf8
