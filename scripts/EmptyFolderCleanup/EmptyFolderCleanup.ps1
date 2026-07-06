$path = "C:\Users\nekdo\Downloads"
if (Test-Path -LiteralPath $path) {
    do {
        $empty = Get-ChildItem -LiteralPath $path -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0
            }
        $empty | Remove-Item -Force -ErrorAction SilentlyContinue
    } while ($empty)
}
