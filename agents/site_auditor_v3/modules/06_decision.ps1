function Invoke-Module06Decision {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $reconcile = $InputData.reconcile
    $coverage  = @($reconcile.coverage)
    $gaps      = @($reconcile.gaps)

    $critical = 0
    $high = 0
    $medium = 0
    $low = 0

    foreach ($g in $gaps) {
        switch ($g.severity) {
            "CRITICAL" { $critical++ }
            "HIGH"     { $high++ }
            "MEDIUM"   { $medium++ }
            "LOW"      { $low++ }
        }
    }

    if ($critical -gt 0 -or $high -gt 0) {
        $verdict = "FAIL"
    }
    else {
        $verdict = "PASS"
    }

    $score = [Math]::Max(0, 100 - ($critical*40 + $high*20 + $medium*10 + $low*5))

    return @{
        status = "OK"
        data = @{
            audit_verdict = $verdict
            score = $score
            data_quality = "COMPLETE"
            finding_counts = @{
                critical = $critical
                high = $high
                medium = $medium
                low = $low
            }
        }
    }
}
