# Deletes files in the user's %TEMP% folder that are older than CutoffDays.
# Runs recursively; files/folders that fail to delete (locked, in-use) are silently skipped.

$Config = @{
    CutoffDays = 7   # Files older than this many days are deleted
}

$cutoff = (Get-Date).AddDays(-$Config.CutoffDays)

# Recurse through %TEMP%, keep only files older than the cutoff, delete them
Get-ChildItem -Path $env:TEMP -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt $cutoff } |
    Remove-Item -Force -ErrorAction SilentlyContinue
