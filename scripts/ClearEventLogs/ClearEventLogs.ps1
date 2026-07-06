wevtutil el | ForEach-Object { wevtutil cl $_ 2>$null }
