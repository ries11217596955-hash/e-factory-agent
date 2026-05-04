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

    
    # === BASIC FINDING DETECTION ===
    $findings = @()

    if ($PipelineState.capture.totals.succeeded -eq 0) {
        $findings += @{
            type = "critical"
            code = "NO_CAPTURE"
            message = "No successful captures"
        }
    }

    if ($PipelineState.route_audit.totals.discovered -le 1) {
        $findings += @{
            type = "medium"
            code = "LOW_ROUTE_COVERAGE"
            message = "Only one route discovered"
        }
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
            findings = $findings
        }
    }
}
