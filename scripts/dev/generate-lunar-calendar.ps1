$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$calendar = [System.Globalization.ChineseLunisolarCalendar]::new()
$epoch = [datetime]::new(1970, 1, 1)
$rows = [System.Collections.Generic.List[object]]::new()
foreach ($year in 1901..2051) {
    $leap = $calendar.GetLeapMonth($year)
    $count = $calendar.GetMonthsInYear($year)
    foreach ($index in 1..$count) {
        $start = $calendar.ToDateTime($year, $index, 1, 0, 0, 0, 0)
        $month = $index
        if ($leap -ne 0 -and $index -ge $leap) { $month -= 1 }
        if ($index -eq $leap) { $month = -$month }
        $rows.Add(@([int]($start - $epoch).TotalDays, $year, $month))
    }
}
$directory = Join-Path $repo 'data/oracle'
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$target = Join-Path $directory 'lunar_months.json'
$lines = $rows | ForEach-Object { '  [' + ($_ -join ',') + ']' }
[IO.File]::WriteAllText($target, "[`n" + ($lines -join ",`n") + "`n]`n", [Text.UTF8Encoding]::new($false))
Write-Output "Wrote $($rows.Count) lunar month starts."
