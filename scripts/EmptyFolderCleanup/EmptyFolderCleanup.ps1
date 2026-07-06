# Recursively removes empty folders under TargetDir.
# Loops repeatedly because deleting a folder can leave its now-empty parent
# behind, which needs another pass to catch.

$Config = @{
    TargetDir = "$env:USERPROFILE\Downloads"  # Root folder to scan for empty subfolders
}

$path = $Config.TargetDir
if (Test-Path -LiteralPath $path) {
    do {
        # Find all subfolders (recursively) that currently contain zero items
        $empty = Get-ChildItem -LiteralPath $path -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0
            }
        $empty | Remove-Item -Force -ErrorAction SilentlyContinue
    } while ($empty)  # Repeat until a pass finds no more empty folders
}
