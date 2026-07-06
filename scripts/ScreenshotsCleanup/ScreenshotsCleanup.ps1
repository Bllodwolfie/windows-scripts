$path = "C:\Users\nekdo\Pictures\Screenshots"
$cutoff = (Get-Date).AddDays(-7)
Get-ChildItem -Path $path -File | Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force
