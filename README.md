# Windows Last-Used Program Tracker

Scans installed programs from the Windows registry, estimates last-used dates from Prefetch/file timestamps, and writes a human-readable report of likely unused software.

## How to use

1. Double-click `last_used_tracker.bat`, or
2. Run PowerShell with:
```powershell
ExecutionPolicy Bypass -File .\last_used_tracker.ps1
```

## Output

- `program_usage_report.txt` in your user profile (`C:\Users\Ay\program_usage_report.txt`)

## Notes

- Threshold: `90` days in the script.
- Evidence sources: Prefetch → LastWriteTime → LastAccessTime → InstallDate fallback.
- Does not uninstall anything.

## License

MIT
