function Invoke-PostOutput {
    param(
        [string]$OutputDir,
        [string]$RunReportPath
    )

    if (-not (Test-Path $RunReportPath)) { return }

    $report = Get-Content $RunReportPath -Raw | ConvertFrom-Json

    $en = "SITE STATUS: $($report.status)"
    $ru = "СТАТУС САЙТА: $($report.status)"

    $en | Out-File (Join-Path $OutputDir "REPORT_EN.txt") -Encoding UTF8
    $ru | Out-File (Join-Path $OutputDir "REPORT_RU.txt") -Encoding UTF8
}
