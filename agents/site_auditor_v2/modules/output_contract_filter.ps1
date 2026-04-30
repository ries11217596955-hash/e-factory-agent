function Invoke-OutputContractFilter {
    param(
        [Parameter(Mandatory = $true)][string]$OutputDir
    )

    $allowedFiles = @(
        'RUN_REPORT.json',
        'SELF_DIAGNOSTIC.json',
        'AGENT_MAP.json',
        'AGENT_MAP.md',
        'ACTION_SUMMARY.json',
        'AUDIT_SUMMARY.json',
        'LINK_SUMMARY.json',
        'ROUTES_SUMMARY.json',
        'visual_manifest.json',
        'visual_capture_input.json',
        'HUMAN_REPORT_RU.html',
        'HUMAN_REPORT_EN.html'
    )

    $allowedDirs = @('screenshots')

    Get-ChildItem -LiteralPath $OutputDir -Force | ForEach-Object {
        if ($_.PSIsContainer) {
            if ($allowedDirs -notcontains $_.Name) {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        } else {
            if ($allowedFiles -notcontains $_.Name) {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }


    $runReportPath = Join-Path $OutputDir 'RUN_REPORT.json'
    if (Test-Path -LiteralPath $runReportPath -PathType Leaf) {
        try {
            $runReport = Get-Content -LiteralPath $runReportPath -Raw | ConvertFrom-Json
            $cleanArtifacts = @()
            Get-ChildItem -LiteralPath $OutputDir -Force | ForEach-Object {
                if ($_.PSIsContainer) {
                    if ($allowedDirs -contains $_.Name) {
                        $cleanArtifacts += $_.Name
                    }
                } else {
                    if ($allowedFiles -contains $_.Name) {
                        $cleanArtifacts += $_.Name
                    }
                }
            }
            $runReport.produced_artifacts = @($cleanArtifacts | Sort-Object)
            $runReport | ConvertTo-Json -Depth 100 | Out-File -LiteralPath $runReportPath -Encoding UTF8
            Write-Host "OUTPUT_CONTRACT_FILTER: RUN_REPORT_REWRITTEN_AFTER_FILTER"
        } catch {
            Write-Host ("OUTPUT_CONTRACT_FILTER: RUN_REPORT_REWRITE_FAILED " + $_.Exception.Message)
        }
    }

    Write-Host ("OUTPUT_CONTRACT_FILTER: APPLIED " + $OutputDir)
}
