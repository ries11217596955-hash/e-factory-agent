function New-AgentMapObject {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentBottleneck
    )

    [ordered]@{
        map_version = '1.0'
        purpose = 'Prevent drift, giant-file growth, and wrong-layer patching.'
        orchestrator = [ordered]@{
            path = 'agents/site_auditor_v2/agent.ps1'
            role = 'Orchestrates stages only; should not absorb module logic.'
        }
        flow = @(
            'ENTRY',
            'LINK_FETCH',
            'ROUTE_EXTRACTION',
            'ROUTE_SELECTION',
            'CAPTURE',
            'RECON',
            'REPORT_LAYER',
            'OUTPUT',
            'AGENT_MAP',
            'HUMAN_REPORT'
        )
        modules = @(
            [ordered]@{ path='agents/site_auditor_v2/modules/stage_link_fetch.ps1'; layer='input'; role='Base URL, HTML fetch, link signals, shallow route discovery.' }
            [ordered]@{ path='agents/site_auditor_v2/modules/stage_route_keys.ps1'; layer='routing'; role='Canonical route keys, route classification, visual target selection.' }
            [ordered]@{ path='agents/site_auditor_v2/modules/stage_capture_reconciliation.ps1'; layer='recon'; role='Prepare capture/reconciliation evidence before report layer.' }
            [ordered]@{ path='agents/site_auditor_v2/modules/surface_context.ps1'; layer='context'; role='Surface type, expectations, value satisfaction signals.' }
            [ordered]@{ path='agents/site_auditor_v2/modules/report_contract.ps1'; layer='contract'; role='Normalize finding contract and required report fields.' }
            [ordered]@{ path='agents/site_auditor_v2/modules/report_layer.ps1'; layer='decision'; role='Build system_problem, decision_summary, action_summary, human payloads, consistency lock.' }
            [ordered]@{ path='agents/site_auditor_v2/modules/report_safe_helpers.ps1'; layer='decision_helpers'; role='Safe list/null helpers for report layer.' }
            [ordered]@{ path='agents/site_auditor_v2/modules/self_build_protocol.ps1'; layer='self_diagnostic'; role='Failure class, build ladder, failure report, operator handoff.' }
            [ordered]@{ path='agents/site_auditor_v2/modules/runtime_safe.ps1'; layer='runtime'; role='Runtime safety, URI normalization, stage trace, script failure diagnostics.' }
            [ordered]@{ path='agents/site_auditor_v2/modules/util_io.ps1'; layer='io'; role='Directory and JSON output helpers.' }
            [ordered]@{ path='agents/site_auditor_v2/modules/util_json.ps1'; layer='json'; role='ISO UTC timestamp and not-implemented status helpers.' }
            [ordered]@{ path='agents/site_auditor_v2/lib/post_output.ps1'; layer='output'; role='Post-output handling and artifact copy behavior.' }
            [ordered]@{ path='agents/site_auditor_v2/lib/fail_output.ps1'; layer='failure_output'; role='Failure output contract.' }
            [ordered]@{ path='agents/site_auditor_v2/lib/decision.ps1'; layer='legacy_or_support'; role='Decision support library; verify ownership before modifying.' }
        )
        current_bottleneck = $CurrentBottleneck
        next_safe_build_move = 'SELF_DIAGNOSTIC v1 before audit capability expansion.'
        forbidden_drift = @(
            'do not turn agent.ps1 into giant runtime',
            'do not patch report_layer unless failure is proven inside report contract/check',
            'do not add benchmark/CTA/crawler features before map + self-diagnostic + operator memory feed',
            'do not treat successful run as product readiness'
        )
    }
}

function Write-AgentMapJson {
    param(
        [Parameter(Mandatory = $true)][string]$OutputDir,
        [Parameter(Mandatory = $true)][string]$RootDir,
        [string]$CurrentBottleneck = 'human_report_low_value'
    )

    $map = New-AgentMapObject -CurrentBottleneck $CurrentBottleneck
    $json = $map | ConvertTo-Json -Depth 20

    $outPath = Join-Path $OutputDir 'AGENT_MAP.json'
    $rootPath = Join-Path $RootDir 'AGENT_MAP.json'

    $json | Out-File -LiteralPath $outPath -Encoding UTF8
    $json | Out-File -LiteralPath $rootPath -Encoding UTF8

    Write-Host ("AGENT_MAP_JSON: WRITTEN " + $outPath)
}
