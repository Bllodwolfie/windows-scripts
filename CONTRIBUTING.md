# Contributing

1. Fork the repo.
2. Create a feature branch (`git checkout -b feature/my-thing`).
3. Make your changes.
4. Test your script — each `.ps1` should be self-contained and idempotent.
5. Commit with a clear message (`git commit -m "Add feature X"`).
6. Push (`git push origin feature/my-thing`) and open a Pull Request.

## Style

- One script per folder under `scripts/`.
- Avoid external dependencies (no modules to install).
- Use `$PSScriptRoot` for relative paths if the script needs assets.
- Use `-ErrorAction SilentlyContinue` for non-critical failures.
