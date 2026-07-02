@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
title Last Used Program Tracker for Windows
echo.
echo ========================================
echo   Last Used Program Tracker
echo ========================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "& {
    $ErrorActionPreference = 'SilentlyContinue'
    $reportPath = \"$env:USERPROFILE\\program_usage_report.txt\"
    $prefetchDir = 'C:\Windows\Prefetch'
    if (-not (Test-Path $prefetchDir)) { $prefetchDir = \"$env:SystemRoot\Prefetch\" }
    $threshold = 90

    function Parse-InstallDate($s) {
        if (-not $s -or $s.Length -ne 8) { return $null }
        try { return [datetime]::ParseExact($s,'yyyyMMdd',$null) } catch { return $null }
    }

    function Get-RegistryPrograms {
        $roots = @(
            @{ Root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' },
            @{ Root = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall' },
            @{ Root = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' }
        )
        $list = @()
        foreach ($r in $roots) {
            if (-not (Test-Path $r.Root)) { continue }
            Get-ChildItem $r.Root -ErrorAction SilentlyContinue | ForEach-Object {
                $dn = (Get-ItemProperty -Path $_.PSPath -Name DisplayName -ErrorAction SilentlyContinue).DisplayName
                if (-not $dn) { return }
                $list += [pscustomobject]@{
                    Name = $dn
                    InstallDate = (Get-ItemProperty -Path $_.PSPath -Name InstallDate -ErrorAction SilentlyContinue).InstallDate
                    InstallLocation = (Get-ItemProperty -Path $_.PSPath -Name InstallLocation -ErrorAction SilentlyContinue).InstallLocation
                    DisplayIcon = (Get-ItemProperty -Path $_.PSPath -Name DisplayIcon -ErrorAction SilentlyContinue).DisplayIcon
                    UninstallString = (Get-ItemProperty -Path $_.PSPath -Name UninstallString -ErrorAction SilentlyContinue).UninstallString
                }
            }
        }
        return $list
    }

    function Normalize-Icon($raw) {
        if (-not $raw) { return '' }
        $raw = $raw.Trim().Trim('\"')
        if ($raw.Contains(',')) { $raw = $raw.Split(',')[0] }
        if ($raw.ToLower().EndsWith('.exe')) { return $raw }
        return ''
    }

    function Find-MainExe($dir) {
        if (-not $dir -or -not (Test-Path $dir -PathType Container)) { return '' }
        $candidates = @()
        Get-ChildItem -Path $dir -Filter *.exe -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $rel = $_.FullName.Substring($dir.Length)
            if ((($rel.Split('\') | Measure-Object).Count -le 2)) {
                $candidates += $_.FullName
            }
        }
        if (-not $candidates) { return '' }
        return ($candidates | Sort-Object -Property Length -Descending | Select-Object -First 1)
    }

    function Get-FileEvidence($path) {
        if (-not $path -or -not (Test-Path $path)) { return $null,$null }
        try {
            $f = Get-Item $path
            return $f.LastWriteTime, $f.LastAccessTime
        } catch { return $null,$null }
    }

    function Get-PrefetchEvidence($path) {
        if (-not $path -or -not (Test-Path $path)) { return $null }
        $base = Split-Path $path -LeafBase
        $pf = Get-ChildItem $prefetchDir -Filter \"${base}*.pf\" -ErrorAction SilentlyContinue
        if (-not $pf) { return $null }
        try { return ($pf | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime } catch { return $null }
    }

    $programs = Get-RegistryPrograms | Sort-Object Name -Unique
    $now = Get-Date
    $results = @()

    foreach ($p in $programs) {
        $exe = Normalize-Icon $p.DisplayIcon
        if (-not $exe -and $p.InstallLocation) { $exe = Find-MainExe $p.InstallLocation }
        $mtime,$atime = Get-FileEvidence $exe
        $pf = Get-PrefetchEvidence $exe
        $inst = Parse-InstallDate $p.InstallDate

        $last = $null; $ev = @()
        if ($pf)     { $last = $pf; $ev += 'Prefetch' }
        if ($mtime -and ($last -eq $null -or $mtime -gt $last)) { $last = $mtime; $ev += 'FileMTime' }
        if ($atime -and ($last -eq $null -or $atime -gt $last)) { $last = $atime; $ev += 'FileATime' }
        if ($last -eq $null -and $inst)                       { $last = $inst; $ev += 'InstallDate' }

        $days = $null
        if ($last) { $days = [math]::Floor((($now - $last).TotalDays)) }

        $results += [pscustomobject]@{
            Name = $p.Name
            LastUsed = $last
            DaysSince = $days
            Evidence = ($ev -join ', '); Path = $exe
            Uninstall = $p.UninstallString
            InstallDate = $inst
        }
    }

    $results = $results | Sort-Object { if ($_.DaysSince -eq $null) { -9999 } else { -$_.DaysSince } }, Name

    $lines = @()
    $lines += 'Installed Programs Usage Report'
    $lines += \"Generated: $now\"
    $lines += \"Unused threshold: $threshold days\"
    $lines += ('=' * 80)
    $unused = @(); $used = @()

    foreach ($item in $results) {
        if ($item.DaysSince -eq $null) {
            $flag = '[NO USAGE DATA]'; $unused += $item
        } elseif ($item.DaysSince -gt $threshold) {
            $flag = \"[UNUSED $($item.DaysSince) days]\"; $unused += $item
        } else {
            $flag = \"[USED $($item.DaysSince) days ago]\"; $used += $item
        }
        $lu = if ($item.LastUsed) { $item.LastUsed.ToString('yyyy-MM-dd') } else { 'Unknown' }
        $ev = if ($item.Evidence) { $item.Evidence } else { 'Unknown' }
        $lines += \"\"
        $lines += $item.Name
        $lines += \"  Last used: $lu $flag\"
        $lines += \"  Evidence: $ev\"
        $lines += \"  Path: $($item.Path)\"
    }

    $lines += ('=' * 80)
    $lines += \"\"
    $lines += \"Total programs: $($results.Count)\"
    $lines += \"Consider removing: $($unused.Count)\"
    $lines += \"Recently used: $($used.Count)\"
    $lines += \"\"
    $lines += 'Recommendations:'
    $lines += ' - Review the UNUSED items above. If you no longer need them, uninstall via Settings or Control Panel.'
    $lines += ' - This tool uses heuristics; not all programs have reliable last-used data.'

    $lines | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host \"Report saved to: $reportPath\"
    Write-Host \"Potentially unused programs: $($unused.Count)\"
    $unused | Select-Object -First 20 | ForEach-Object {
        $suffix = if ($_.DaysSince -ne $null) { \" ($($_.DaysSince) days)\" } else { '' }
        Write-Host \" - $($_.Name)$suffix\"
    }
    pause
}" 2>&1
endlocal
