# Deletes screenshots older than CutoffDays from the Pictures\Screenshots folder.
# Non-recursive: only touches files directly in TargetDir.

$Config = @{
    TargetDir  = "$env:USERPROFILE\Pictures\Screenshots"  # Folder to clean
    CutoffDays = 7                                          # Delete files older than this many days
}

$path   = $Config.TargetDir
$cutoff = (Get-Date).AddDays(-$Config.CutoffDays)

Get-ChildItem -Path $path -File | Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force
