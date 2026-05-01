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
        switch ([string]$g.severity) {
            "CRITICAL" { $critical++ }
            "HIGH"     { $high++ }
            "MEDIUM"   { $medium++ }
            "LOW"      { $low++ }
        }
    }

    $verdict = if ($critical -gt 0 -or $high -gt 0) { "FAIL" } else { "PASS" }
    $score = [Math]::Max(0, 100 - ($critical*40 + $high*20 + $medium*10 + $low*5))

    $whatWorked = @()
    foreach ($key in @("input","route_audit","selection","capture","reconcile")) {
        if ($PipelineState.ContainsKey($key)) {
            $whatWorked += $key
        }
    }

    $whatFailed = @()
    $limitations = @()
    $evidenceGaps = @()

    if ($gaps.Count -gt 0) {
        foreach ($g in $gaps) {
            $evidenceGaps += @{
                code = [string]$g.code
                severity = [string]$g.severity
                route_id = [string]$g.route_id
            }
        }
        $limitations += "coverage gaps exist"
    }

    $routesSelected = 0
    if ($PipelineState.selection -and $PipelineState.selection.totals) {
        $routesSelected = [int]$PipelineState.selection.totals.selected
    }

    $capturesSucceeded = 0
    if ($PipelineState.capture -and $PipelineState.capture.totals) {
        $capturesSucceeded = [int]$PipelineState.capture.totals.succeeded
    }

    if ($routesSelected -eq 0) {
        $limitations += "no selected routes"
        $whatFailed += "selection produced no targets"
    }

    if ($routesSelected -gt 0 -and $capturesSucceeded -eq 0) {
        $limitations += "no successful captures"
        $whatFailed += "capture produced no evidence"
    }

    $confidence = "HIGH"
    if ($limitations.Count -gt 0) { $confidence = "MEDIUM" }
    if ($routesSelected -eq 0 -or ($routesSelected -gt 0 -and $capturesSucceeded -eq 0)) { $confidence = "LOW" }

    $failedStage = $null
    if ($whatFailed.Count -gt 0) {
        $failedStage = [string]$whatFailed[0]
    }

    $nextDebugStep = if ($failedStage) {
        "Inspect " + $failedStage + " output in pipeline state"
    } else {
        "No debug step required for current smoke run"
    }

    $nextBuildStep = if ($limitations.Count -gt 0) {
        "Strengthen evidence generation before expanding input modes"
    } else {
        "Add self_build capability posture to 06_decision"
    }

    return @{
        status = "OK"
        data = @{
            audit_verdict = $verdict
            score = $score
            data_quality = if ($confidence -eq "HIGH") { "COMPLETE" } else { "PARTIAL" }
            finding_counts = @{
                critical = $critical
                high = $high
                medium = $medium
                low = $low
            }
            self_diagnostic = @{
                failed_stage = $failedStage
                what_worked = $whatWorked
                what_failed = $whatFailed
                limitations = $limitations
                evidence_gaps = $evidenceGaps
                confidence = $confidence
                next_debug_step = $nextDebugStep
                next_build_step = $nextBuildStep
                forbidden_next_steps = @(
                    "do not add ZIP/REPO/PROMPT modes before self_build exists",
                    "do not claim strong PASS without evidence coverage",
                    "do not add new modules without RUN_REPORT next_step alignment"
                )
            }
        }
    }
}
