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
        'visual_capture_input.json'
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

    Write-Host ("OUTPUT_CONTRACT_FILTER: APPLIED " + $OutputDir)
}
