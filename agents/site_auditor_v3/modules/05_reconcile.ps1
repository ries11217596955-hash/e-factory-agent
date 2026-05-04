function New-FindingAction {
    param(
        [Parameter(Mandatory)]$Finding
    )

    $code = [string]$Finding.code

    if ($code -eq "LOW_ROUTE_COVERAGE") {
        return @{
            action_id = "expand_route_coverage"
            priority = "high"
            action = "Add more eligible routes before judging the site."
            target_module = "route_audit"
            why = "The audit cannot make reliable conclusions from too few routes."
            acceptance = "routes_discovered > 1 and coverage gaps = 0"
        }
    }

    if ($code -eq "NO_CAPTURE") {
        return @{
            action_id = "restore_capture"
            priority = "critical"
            action = "Restore successful capture records before decision."
            target_module = "capture"
            why = "No evidence was captured."
            acceptance = "captures_succeeded > 0"
        }
    }

    if ($code -eq "VISUAL_CAPTURE_FAILED") {
        return @{
            action_id = "repair_visual_capture"
            priority = "high"
            action = "Fix visual capture for failed routes."
            target_module = "visual_capture"
            why = "Visual evidence is required for UX and conversion checks."
            acceptance = "visual_capture.totals.failed = 0"
        }
    }

    if ($code -eq "MISSING_H1") {
        return @{
            action_id = "add_clear_page_heading"
            priority = "medium"
            action = "Add or expose a clear H1 heading for the page."
            target_module = "content"
            why = "A missing H1 weakens page clarity and intent recognition."
            acceptance = "has_h1 = true"
        }
    }

    if ($code -eq "NO_CTA_SIGNAL") {
        return @{
            action_id = "add_visible_action"
            priority = "medium"
            action = "Add a visible next action or CTA."
            target_module = "conversion"
            why = "A page without an action does not move the user forward."
            acceptance = "has_cta = true"
        }
    }

    return @{
        action_id = "review_finding"
        priority = "medium"
        action = "Review finding and map it to a concrete fix."
        target_module = "reconcile"
        why = "Finding has no specific action mapping yet."
        acceptance = "finding has mapped action_id"
    }
}

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

        if ($null -eq $match -or @($match).Count -eq 0) {
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

    if ($PipelineState.visual_capture -and $PipelineState.visual_capture.totals.failed -gt 0) {
        $findings += @{
            type = "medium"
            code = "VISUAL_CAPTURE_FAILED"
            message = "One or more visual captures failed"
        }
    }

    if ($PipelineState.visual_capture -and $PipelineState.visual_capture.visual_records) {
        foreach ($v in @($PipelineState.visual_capture.visual_records)) {
            if ($v.status -eq "SUCCESS" -and -not $v.signals.has_h1) {
                $findings += @{
                    type = "medium"
                    code = "MISSING_H1"
                    message = "Page has no visible H1 signal"
                    route_id = $v.route_id
                }
            }
            if ($v.status -eq "SUCCESS" -and -not $v.signals.has_cta) {
                $findings += @{
                    type = "low"
                    code = "NO_CTA_SIGNAL"
                    message = "Page has no basic CTA signal"
                    route_id = $v.route_id
                }
            }
        }
    }

    $findingActions = @()
    foreach ($f in @($findings)) {
        $findingActions += New-FindingAction -Finding $f
    }

    return @{
        status = "OK"
        data = @{
            coverage = $coverage
            gaps = $gaps
            evidence_quality = @{
                status = $qualityFlag
                low_quality_count = $lowQuality
            }
            status = "READY"
            findings = $findings
            finding_actions = $findingActions
        }
    }
}
