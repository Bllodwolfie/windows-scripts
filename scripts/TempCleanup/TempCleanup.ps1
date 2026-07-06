$cutoff = (Get-Date).AddDays(-7)
Get-ChildItem -Path $env:TEMP -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt $cutoff } |
    Remove-Item -Force -ErrorAction SilentlyContinue
