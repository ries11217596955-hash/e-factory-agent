function Invoke-Module05Reconcile {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $selection = $InputData.selection
    $capture   = $InputData.capture

    $selected = @($selection.selected)
    $records  = @($capture.records)

    $coverage = @()
    $gaps = @()

    foreach ($s in $selected) {
        $match = $records | Where-Object { $_.route_id -eq $s.route_id }

        if ($null -eq $match -or $match.Count -eq 0) {
            $coverage += @{
                route_id = $s.route_id
                coverage_status = "NONE"
            }

            $gaps += @{
                code = "MISSING_CAPTURE"
                severity = "HIGH"
                route_id = $s.route_id
            }
        }
        else {
            $coverage += @{
                route_id = $s.route_id
                coverage_status = "FULL"
            }
        }
    }

    
    # === EVIDENCE QUALITY CHECK ===
    $lowQuality = 0

    foreach ($c in $PipelineState.capture.records) {
        if (-not $c.url -or $c.status -ne "SUCCESS") {
            $lowQuality++
        }
    }

    $qualityFlag = "GOOD"
    if ($lowQuality -gt 0) {
        $qualityFlag = "WEAK"
    }

    return @{
        status = "OK"
        data = @{
            coverage = $coverage
            gaps     = $gaps
            evidence_quality = @{
                status = $qualityFlag
                low_quality_count = $lowQuality
            }
            status   = "READY"
        }
    }
}
