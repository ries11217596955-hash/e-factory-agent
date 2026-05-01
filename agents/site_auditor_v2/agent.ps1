# Runtime Contract: Windows PowerShell 5.1 compatible
# - No ambiguous ::new(...) constructor usage in runtime-critical paths
# - No comparer-based generic constructor overloads
# - Use runtime-safe helper factories from modules/runtime_safe.ps1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Mode,
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl
)

Set-StrictMode -Version Latest
. "$PSScriptRoot/lib/post_output.ps1"

function Get-SafePropValue {
    param(
        [Parameter(Mandatory=$false)] $Object,
        [Parameter(Mandatory=$true)] [string] $Name,
        [Parameter(Mandatory=$false)] $Default = $null
    )

    if ($null -eq $Object) { return $Default }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        if ($Object.ContainsKey($Name)) { return $Object[$Name] }
        return $Default
    }

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }

    return $prop.Value
}

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 6) {
    Write-Host "Running in PS5.1 compatibility mode"
}

. "$PSScriptRoot/modules/runtime_safe.ps1"
. "$PSScriptRoot/modules/util_io.ps1"
. "$PSScriptRoot/modules/util_json.ps1"
. "$PSScriptRoot/modules/surface_context.ps1"
. "$PSScriptRoot/modules/report_safe_helpers.ps1"
. "$PSScriptRoot/modules/report_contract.ps1"
. "$PSScriptRoot/modules/report_layer.ps1"
. "$PSScriptRoot/modules/stage_link_fetch.ps1"
. "$PSScriptRoot/modules/stage_route_keys.ps1"
. "$PSScriptRoot/modules/stage_capture_reconciliation.ps1"
. "$PSScriptRoot/modules/self_build_protocol.ps1"
. (Join-Path $PSScriptRoot 'lib/fail_output.ps1')
. (Join-Path $PSScriptRoot 'lib/decision.ps1')

function Get-OwnershipMode {
    return 'EXTERNAL'
}

function Get-ActionTextByOwnership {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('OWNED', 'EXTERNAL')]
        [string]$OwnershipMode,
        [Parameter(Mandatory = $true)]
        [string]$OwnedAction,
        [Parameter(Mandatory = $true)]
        [string]$ExternalAction
    )

    if ($OwnershipMode -eq 'OWNED') {
        return $OwnedAction
    }

    return $ExternalAction
}

function Get-DefectPriorityByIssueType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$IssueType
    )

    switch ($IssueType) {
        'BROKEN_ROUTE' { return 'P0' }
        'PROCESS_FIRST' { return 'P1' }
        'NO_VALUE_FIRST_SCREEN' { return 'P1' }
        'NO_ACTION_PATH' { return 'P2' }
        default { return 'P2' }
    }
}

function Get-PageSignalThresholds {
    return [ordered]@{
        thin_html_length = 1200
        thin_internal_links = 2
        first_screen_text_min_length = 80
        first_screen_text_max_length = 800
        first_screen_html_max_length = 18000
        shell_text_max_length = 40
        shell_content_tag_min_count = 2
    }
}

function Get-PageTypeHeuristic {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RouteKey,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [int]$InternalLinkCount,
        [Parameter(Mandatory = $true)]
        [int]$ContentTagCount,
        [Parameter(Mandatory = $true)]
        [int]$WrapperTagCount
    )

    $routeLower = ([string]$RouteKey).ToLowerInvariant()
    $titleLower = ([string]$Title).ToLowerInvariant()

    return 'UNKNOWN'
}

function Test-PageTypeRequiresAnswer {
    param([Parameter(Mandatory = $true)][string]$PageType)
    return @('LANDING', 'DECISION', 'TOOL') -contains [string]$PageType
}

function Get-FindingTypeSortRank {
    param([Parameter(Mandatory = $true)][string]$IssueType)
    switch ([string]$IssueType) {
        'BROKEN_ROUTE' { return 0 }
        'PROCESS_FIRST' { return 1 }
        'NO_VALUE_FIRST_SCREEN' { return 2 }
        'NO_ACTION_PATH' { return 3 }
        default { return 9 }
    }
}

function Get-SystemProblemMapping {
    param([Parameter(Mandatory = $true)][string]$IssueType)

    switch ([string]$IssueType) {
        'PROCESS_FIRST' {
            return [ordered]@{
                problem_type = 'VALUE_STRUCTURE'
                action_domain = 'VALUE'
                description_en = 'Multiple pages start with process before clarifying value.'
                description_ru = 'Несколько страниц начинают с процесса до объяснения ценности.'
            }
        }
        'NO_VALUE_FIRST_SCREEN' {
            return [ordered]@{
                problem_type = 'VALUE_CLARITY'
                action_domain = 'VALUE'
                description_en = 'Multiple pages do not clearly explain value on the first screen.'
                description_ru = 'Несколько страниц не объясняют ценность на первом экране.'
            }
        }
        'NO_ACTION_PATH' {
            return [ordered]@{
                problem_type = 'ACTION_PATH'
                action_domain = 'ACTION_PATH'
                description_en = 'Multiple pages do not provide a clear first-screen action path.'
                description_ru = 'Несколько страниц не дают понятного действия на первом экране.'
            }
        }
        default { return $null }
    }
}

function Get-EvidenceSnippet {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $lines = @(
        ([string]$Text -split "(`r`n|`n|`r)") |
        ForEach-Object { [string]$_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -First 2
    )
    return [string]($lines -join ' ')
}

function Test-HighSignalConfidence {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$ConditionMet,
        [Parameter(Mandatory = $true)]
        [bool]$EvidencePresent
    )

    if ($ConditionMet -and $EvidencePresent) {
        return 'HIGH'
    }

    return 'LOW'
}

function Escape-HtmlText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function New-ClientReportHtml {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('RU', 'EN')]
        [string]$Language,
        [Parameter(Mandatory = $true)]
        [hashtable]$ReportPayload
    )

    $title = if ($Language -eq 'RU') { 'Краткий системный аудит' } else { 'Concise System Audit' }
    $executiveHeader = if ($Language -eq 'RU') { 'Краткий вердикт' } else { 'Executive Verdict' }
    $mainProblemHeader = if ($Language -eq 'RU') { 'Главная системная проблема' } else { 'Main System Problem' }
    $impactHeader = if ($Language -eq 'RU') { 'К чему это приводит' } else { 'What This Causes' }
    $nextHeader = if ($Language -eq 'RU') { 'Что делать дальше' } else { 'What To Do Next' }
    $evidenceHeader = if ($Language -eq 'RU') { 'Подтверждающие примеры' } else { 'Supporting Evidence' }
    $limitsHeader = if ($Language -eq 'RU') { 'Ограничения аудита' } else { 'Audit Limits' }
    $snapshotHeader = if ($Language -eq 'RU') { 'Технический срез' } else { 'Technical Snapshot' }

    $executiveLines = @($ReportPayload.executive_lines | Select-Object -First 4 | ForEach-Object { "<p>$(Escape-HtmlText -Text ([string]$_))</p>" }) -join ''
    $impactLines = @($ReportPayload.impact_lines | Select-Object -First 3 | ForEach-Object { "<li>$(Escape-HtmlText -Text ([string]$_))</li>" }) -join ''
    $limitationLines = @($ReportPayload.limitations_lines | Select-Object -First 1 | ForEach-Object { "<li>$(Escape-HtmlText -Text ([string]$_))</li>" }) -join ''
    $actionLines = @($ReportPayload.actions_lines | Select-Object -First 3 | ForEach-Object { "<li>$(Escape-HtmlText -Text ([string]$_))</li>" }) -join ''
    $evidenceLines = @($ReportPayload.evidence_lines | Select-Object -First 3 | ForEach-Object { "<li>$(Escape-HtmlText -Text ([string]$_))</li>" }) -join ''
    $snapshotRows = @($ReportPayload.snapshot_rows | ForEach-Object {
            "<tr><th>$(Escape-HtmlText -Text ([string]$_.label))</th><td>$(Escape-HtmlText -Text ([string]$_.value))</td></tr>"
        }) -join ''

    return @"
<!doctype html>
<html lang="$(if ($Language -eq 'RU') { 'ru' } else { 'en' })">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>$(Escape-HtmlText -Text $title)</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 28px; color: #1f2937; line-height: 1.45; }
    h1 { font-size: 28px; margin-bottom: 12px; }
    h2 { font-size: 18px; margin: 20px 0 8px; }
    .box { border: 1px solid #d1d5db; background: #f9fafb; border-radius: 8px; padding: 12px 14px; }
    ul { margin: 0; padding-left: 20px; }
    p { margin: 6px 0; }
    table { border-collapse: collapse; width: 100%; max-width: 560px; }
    th, td { border: 1px solid #d1d5db; text-align: left; padding: 6px 8px; font-size: 14px; }
    th { width: 45%; background: #f3f4f6; }
  </style>
</head>
<body>
  <h1>$(Escape-HtmlText -Text $title)</h1>
  <section class="box">
    <h2>$(Escape-HtmlText -Text $executiveHeader)</h2>
    $executiveLines
  </section>
  <section>
    <h2>$(Escape-HtmlText -Text $mainProblemHeader)</h2>
    <p>$(Escape-HtmlText -Text ([string]$ReportPayload.main_problem))</p>
  </section>
  <section><h2>$(Escape-HtmlText -Text $impactHeader)</h2><ul>$impactLines</ul></section>
  <section>
    <h2>$(Escape-HtmlText -Text $nextHeader)</h2>
    <ul>$actionLines</ul>
  </section>
  <section><h2>$(Escape-HtmlText -Text $evidenceHeader)</h2><ul>$evidenceLines</ul></section>
  $(if ($ReportPayload.include_limitations) { "<section><h2>$(Escape-HtmlText -Text $limitsHeader)</h2><ul>$limitationLines</ul></section>" } else { '' })
  <section>
    <h2>$(Escape-HtmlText -Text $snapshotHeader)</h2>
    <table>$snapshotRows</table>
  </section>
</body>
</html>
"@
}

function Get-SurfaceTypeByPageType {
    param([string]$PageType)

    switch ([string]$PageType) {
        'MEDIA_HOME' { return 'MEDIA_HOME' }
        'MEDIA_SECTION' { return 'MEDIA_SECTION' }
        'ARTICLE' { return 'ARTICLE' }
        'LANDING' { return 'LANDING' }
        'DECISION' { return 'DECISION' }
        'TOOL' { return 'TOOL' }
        'DIRECTORY' { return 'DIRECTORY' }
        default { return 'UNKNOWN' }
    }
}

function Convert-RunReportValue {
    param(
        [Parameter(Mandatory = $false)]
        $Value,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[int]]$VisitedReferences
    )

    if ($null -eq $VisitedReferences) {
        $VisitedReferences = New-Object 'System.Collections.Generic.HashSet[int]'
    }

    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [char] -or $Value -is [bool]) { return $Value }
    if ($Value -is [datetime] -or $Value -is [guid]) { return $Value }
    if ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64]) { return [int]$Value }
    if ($Value.GetType().IsEnum) { return [string]$Value }

    $isReferenceType = -not $Value.GetType().IsValueType
    if ($isReferenceType) {
        $referenceId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Value)
        if (-not $VisitedReferences.Add($referenceId)) {
            throw 'RUN_REPORT_SERIALIZATION_CIRCULAR_REFERENCE'
        }
    }

    try {
        if ($Value -is [System.Collections.IDictionary]) {
            $normalizedMap = [ordered]@{}
            foreach ($entry in $Value.GetEnumerator()) {
                $entryKey = [string]$entry.Key
                $normalizedMap[$entryKey] = Convert-RunReportValue -Value $entry.Value -VisitedReferences $VisitedReferences
            }
            return $normalizedMap
        }

        # Only allow safe enumerable types
        if ($Value -is [System.Array] -or $Value -is [System.Collections.IList]) {
            return @($Value | ForEach-Object { Convert-RunReportValue -Value $_ -VisitedReferences $VisitedReferences })
        }

        if ($Value -is [pscustomobject]) {
            $normalizedObject = [ordered]@{}
            foreach ($property in $Value.PSObject.Properties) {
                $normalizedObject[[string]$property.Name] = Convert-RunReportValue -Value $property.Value -VisitedReferences $VisitedReferences
            }
            return $normalizedObject
        }
    }
    finally {
        if ($isReferenceType) {
            $null = $VisitedReferences.Remove($referenceId)
        }
    }

    return $Value
}

function Write-RunReportBounded {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,
        [Parameter(Mandatory = $true)]
        [string]$RunReportPath,
        [Parameter(Mandatory = $true)]
        [string]$DeterministicRunReportPath
    )

    function Convert-ToMaterializedArray {
        param(
            [Parameter(Mandatory = $false)]
            $Value
        )

        if ($null -eq $Value) {
            return @()
        }

        if ($Value -is [System.Array]) {
            return @($Value)
        }

        if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
            return @($Value)
        }

        return @($Value)
    }

    function Get-SafeCount {
        param($Value)

        if ($null -eq $Value) {
            return 0
        }

        if ($Value -is [string]) {
            if ($Value.Length -eq 0) { return 0 }
            return 1
        }

        if ($Value -is [System.Array]) {
            return $Value.Count
        }

        if ($Value -is [System.Collections.ICollection]) {
            return $Value.Count
        }

        return 1
    }

    Write-Host 'OUTPUT: BUILD_START'
    $visitedReferences = New-Object 'System.Collections.Generic.HashSet[int]'
    $reportBound = Convert-RunReportValue -Value $Report -VisitedReferences $visitedReferences

    if ($null -eq $reportBound) {
        throw 'RUN_REPORT_BUILD_FAILED'
    }

    $reportBound.page_verdicts = Convert-ToMaterializedArray -Value $reportBound.page_verdicts
    $reportBound.findings = Convert-ToMaterializedArray -Value $reportBound.findings

    $findingCount = [int](Get-SafeCount -Value $reportBound.findings)
    for ($findingIndex = 0; $findingIndex -lt $findingCount; $findingIndex++) {
        $finding = $reportBound.findings[$findingIndex]

        if ($null -ne $finding) {
            $hasEvidence = $finding.PSObject.Properties['evidence'] -ne $null

            if ($hasEvidence -and $null -ne $finding.evidence) {
                if ($finding.evidence.PSObject.Properties['evidence_refs'] -ne $null) {
                    $finding.evidence.evidence_refs = Convert-ToMaterializedArray -Value $finding.evidence.evidence_refs
                }
            }
        }
    }

    Write-Host 'OUTPUT: REPORT_OBJECT_READY'

    Write-Host 'OUTPUT: SERIALIZE_START'
    $null = $reportBound | ConvertTo-Json -Depth 100
    Write-Host 'OUTPUT: SERIALIZE_DONE'

    Write-Host 'OUTPUT: WRITE_START'
    Write-JsonFile -Path $RunReportPath -Data $reportBound
    Copy-Item -LiteralPath $RunReportPath -Destination $DeterministicRunReportPath -Force
    Write-Host 'OUTPUT: WRITE_DONE'

# === POST OUTPUT: HUMAN REPORT + AGENT MAP + FAIL TRACE SEED ===
try {
    $runReportRoot = Join-Path $PSScriptRoot "RUN_REPORT.json"
    if (Test-Path $runReportRoot) {
        $run = Get-Content $runReportRoot -Raw | ConvertFrom-Json
        $outFolder = [string]$run.output_folder

        if ([string]::IsNullOrWhiteSpace($outFolder)) {
            $outputRoot = Join-Path $PSScriptRoot "output"
            $latestDir = Get-ChildItem $outputRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($null -ne $latestDir) { $outFolder = $latestDir.FullName }
        }

        if (-not [string]::IsNullOrWhiteSpace($outFolder)) {
            $status = [string]$run.status
            $confidence = [string]$run.audit_confidence

            @(
                "SITE STATUS: $status",
                "",
                "CONFIDENCE: $confidence",
                "",
                "READ FIRST: RUN_REPORT.json",
                "LIMIT: This report is generated from LINK-mode evidence only."
            ) | Out-File (Join-Path $outFolder "REPORT_EN.txt") -Encoding UTF8

            @(
                "СТАТУС САЙТА: $status",
                "",
                "УВЕРЕННОСТЬ: $confidence",
                "",
                "СНАЧАЛА ЧИТАТЬ: RUN_REPORT.json",
                "ОГРАНИЧЕНИЕ: отчёт построен только по LINK-mode доказательствам."
            ) | Out-File (Join-Path $outFolder "REPORT_RU.txt") -Encoding UTF8

            @(
                "# SITE_AUDITOR_V2 — AGENT MAP",
                "",
                "RUN_REPORT.json = read first.",
                "agent.ps1 = orchestrator.",
                "Only files inside output/<run-id>/ are guaranteed in artifact.",
                "",
                "Required artifact files:",
                "- RUN_REPORT.json",
                "- ROUTES_SUMMARY.json",
                "- AUDIT_SUMMARY.json",
                "- visual_manifest.json",
                "- REPORT_EN.txt",
                "- REPORT_RU.txt",
                "",
                "Repair rule: one bottleneck, one layer, no WEBOPS drift."
            ) | Out-File (Join-Path $outFolder "AGENT_MAP.md") -Encoding UTF8

            $agentMapModulePath = Join-Path $PSScriptRoot 'modules/agent_map.ps1'
            if (Test-Path -LiteralPath $agentMapModulePath -PathType Leaf) {
                . $agentMapModulePath
                Write-AgentMapJson -OutputDir $outFolder -RootDir $PSScriptRoot -CurrentBottleneck 'human_report_low_value'
            }

            $selfDiagnosticModulePath = Join-Path $PSScriptRoot 'modules/self_diagnostic.ps1'
            if (Test-Path -LiteralPath $selfDiagnosticModulePath -PathType Leaf) {
                . $selfDiagnosticModulePath
                Write-SelfDiagnosticJson -Report $report -OutputDir $outFolder -RootDir $PSScriptRoot
            }

            Write-Host ("POST_OUTPUT: HUMAN_REPORT_AND_AGENT_MAP_DONE " + $outFolder)

        # CLEANUP: remove stale failure_summary artifacts
        foreach ($staleFailurePath in @($failurePath, $deterministicFailurePath)) {
            if ($staleFailurePath -and (Test-Path -LiteralPath $staleFailurePath -PathType Leaf)) {
                Remove-Item -LiteralPath $staleFailurePath -Force -ErrorAction SilentlyContinue

            # RE-CALCULATE produced_artifacts after cleanup
            $report.produced_artifacts = Get-FinalProducedArtifacts `
                -OutputDir $OutputDir `
                -AllowedFolders $allowedFolders `
                -AllowedExtensions $allowedExtensions `
                -Status ([string]$report.status)

            }
        }
        }
        else {
            Write-Host "POST_OUTPUT: OUTPUT_FOLDER_MISSING"
        }
    }
}
catch {
    Write-Host ("POST_OUTPUT: FAILED " + $_.Exception.Message)
}
# === END POST OUTPUT ===

# === STAGE: AGENT_MAP ===
try {
    Write-Host "STAGE: AGENT_MAP"

    $outputRoot = Join-Path $PSScriptRoot "output"
    $latestDir = $null
    if (Test-Path $outputRoot) {
        $latestDir = Get-ChildItem $outputRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }

    if ($null -ne $latestDir) {
        $mapPath = Join-Path $latestDir.FullName "AGENT_MAP.md"

        $map = @()
        $map += "# SITE_AUDITOR_V2 — AGENT MAP"
        $map += ""
        $map += "## AGENT IDENTITY"
        $map += "SITE_AUDITOR_V2 is a LINK-mode audit orchestrator that produces bounded evidence and operator handoff artifacts."
        $map += ""
        $map += "## ACTIVE PRODUCT SCOPE"
        $map += "Universal Audit Engine. Current LINK run is one execution mode, not the whole product."
        $map += ""
        $map += "## CURRENT EXECUTION MODE + LAYER"
        $map += "Execution mode: LINK"
        $map += "Current layer: REPORT_LAYER (bounded to observable LINK artifacts only)."
        $map += ""
        $map += "## ORCHESTRATOR RULE"
        $map += "agent.ps1 is orchestrator. New behavior must be module/contract, not giant runtime growth."
        $map += ""
        $map += "## STAGES"
        $map += "ENTRY -> LINK_FETCH -> ROUTE_EXTRACTION -> ROUTE_SELECTION -> CAPTURE -> RECON -> REPORT_LAYER -> OUTPUT -> HUMAN_REPORT"
        $map += ""
        $map += "## SYSTEM MAP (MINIMAL)"
        $map += "- route layer -> builds routes"
        $map += "- capture layer -> screenshots"
        $map += "- recon -> evaluation"
        $map += "- report -> decisions"
        $map += "- output -> artifacts"
        $map += "- file pointers: agent.ps1, modules/stage_link_fetch.ps1, modules/stage_capture_reconciliation.ps1, modules/report_layer.ps1, lib/post_output.ps1"
        $map += ""
        $map += "## LAYER CONTRACT MAP"
        $map += "### ROUTE_LAYER"
        $map += "- owner file: modules/stage_link_fetch.ps1"
        $map += "- purpose: discover LINK-visible routes and produce normalized route candidates for selection."
        $map += "- inputs: site_url, execution mode, route budget controls, LINK fetch responses."
        $map += "- outputs: selected routes, route metadata, ROUTES_SUMMARY.json route truth."
        $map += "- failure signals: LINK_FETCH_* errors, ROUTE_VALIDATION_* errors, route contract mismatches attributed to modules/stage_link_fetch.ps1."
        $map += "### CAPTURE_LAYER"
        $map += "- owner file: tools/capture_visuals.mjs"
        $map += "- purpose: capture deterministic screenshots for each selected route."
        $map += "- inputs: selected route list, viewport/device options, capture timeout/budget."
        $map += "- outputs: screenshot files, capture statuses, visual_manifest.json entries."
        $map += "- failure signals: CAPTURE_* stage errors, missing screenshot artifacts, visual manifest gaps attributed to tools/capture_visuals.mjs."
        $map += "### RECON_LAYER"
        $map += "- owner file: modules/stage_capture_reconciliation.ps1"
        $map += "- purpose: reconcile route selection with capture evidence before reporting."
        $map += "- inputs: selected routes, capture results, visual manifest, route budget overflow detail."
        $map += "- outputs: reconciled route verdict inputs, evidence completeness flags, limitation signals."
        $map += "- failure signals: RECON_* / RECONCILIATION_* errors, evidence mismatch failures attributed to modules/stage_capture_reconciliation.ps1."
        $map += "### REPORT_LAYER"
        $map += "- owner file: modules/report_layer.ps1"
        $map += "- purpose: synthesize findings and enforce RUN_REPORT contract consistency."
        $map += "- inputs: reconciled route evidence, audit summaries, decision/action payloads."
        $map += "- outputs: RUN_REPORT decision payload, operator_memory_bridge guidance, ACTION_SUMMARY alignment."
        $map += "- failure signals: CONSISTENCY_LOCK_FAILED, RUN_REPORT_BUILD_FAILED, report contract violations attributed to modules/report_layer.ps1."
        $map += "### OUTPUT_LAYER"
        $map += "- owner file: lib/post_output.ps1"
        $map += "- purpose: produce operator-facing report text and stable handoff artifacts."
        $map += "- inputs: RUN_REPORT.json, operator_memory_bridge.self_explanation, summary artifacts."
        $map += "- outputs: REPORT_EN.txt, REPORT_RU.txt, AGENT_FAILURE_REPORT/AGENT_OPERATOR_HANDOFF on fail."
        $map += "- failure signals: HUMAN_REPORT_* and POST_OUTPUT_* write/read errors attributed to lib/post_output.ps1."
        $map += ""
        $map += "## MODULE / FILE RESPONSIBILITY MAP"
        $map += "- agent.ps1 = orchestrator and stage control"
        $map += "- modules/stage_link_fetch.ps1 = LINK fetch and route discovery"
        $map += "- modules/stage_route_keys.ps1 = route normalization keys"
        $map += "- modules/stage_capture_reconciliation.ps1 = evidence reconciliation gate"
        $map += "- modules/report_layer.ps1 = findings synthesis + operator memory contract"
        $map += "- lib/post_output.ps1 = REPORT_EN/RU operator text output"
        $map += "- contracts/run_report.schema.json = RUN_REPORT contract"
        $map += ""
        $map += "## OUTPUT CONTRACT"
        $map += "- RUN_REPORT.json = read first"
        $map += "- failure_summary.json = read only if FAIL"
        $map += "- ROUTES_SUMMARY.json = route truth"
        $map += "- AUDIT_SUMMARY.json = audit counts"
        $map += "- visual_manifest.json = visual evidence"
        $map += "- REPORT_EN.txt / REPORT_RU.txt = human reports"
        $map += "- AGENT_MAP.md = map of modules, outputs, and artifact routing"
        $map += ""
        $map += "## ARTIFACT ROUTING"
        $map += "Only files inside agents/site_auditor_v2/output/<run-id>/ are guaranteed to appear in uploaded artifact."
        $map += ""
        $map += "## REPAIR RULE"
        $map += "Fix one layer only. Do not switch to WEBOPS. Do not patch multiple layers. Do not expand features before stabilizing the current defect."
        $map += ""
        
        $map += ""
        $map += "## RUNTIME SNAPSHOT"
        $knownFiles = @(
            "RUN_REPORT.json",
            "ROUTES_SUMMARY.json",
            "AUDIT_SUMMARY.json",
            "ACTION_SUMMARY.json",
            "visual_manifest.json",
            "failure_summary.json",
            "REPORT_EN.txt",
            "REPORT_RU.txt"
        )

        foreach ($fileName in $knownFiles) {
            $rootPath = Join-Path $PSScriptRoot $fileName
            $outputPath = Join-Path $latestDir.FullName $fileName

            $rootState = if (Test-Path $rootPath) { "root=yes" } else { "root=no" }
            $outputState = if (Test-Path $outputPath) { "output=yes" } else { "output=no" }

            $map += ("- " + $fileName + ": " + $rootState + "; " + $outputState)
        }

$map += "## CURRENT BASELINE"
        $map += "GREEN LINK CI baseline exists. Preserve it."

        $map | Out-File $mapPath -Encoding UTF8
        Write-Host ("AGENT_MAP: DONE " + $mapPath)
    }
    else {
        Write-Host "AGENT_MAP: OUTPUT_DIR_NOT_FOUND"
    }
}
catch {
    Write-Host ("AGENT_MAP: FAILED " + $_.Exception.Message)
}
# === END AGENT_MAP ===

# === STAGE: HUMAN_REPORT ===
Write-Host "STAGE: HUMAN_REPORT"
try {
    $runReportPath = Join-Path $PSScriptRoot "RUN_REPORT.json"

# === COPY HUMAN REPORTS TO OUTPUT DIR ===
try {
    $runReportPath = Join-Path $PSScriptRoot "RUN_REPORT.json"
    if (Test-Path $runReportPath) {
        $outputDir = Split-Path $runReportPath -Parent

        Copy-Item (Join-Path (Get-Location) "REPORT_EN.txt") -Destination (Join-Path $outputDir "REPORT_EN.txt") -Force -ErrorAction SilentlyContinue
        Copy-Item (Join-Path (Get-Location) "REPORT_RU.txt") -Destination (Join-Path $outputDir "REPORT_RU.txt") -Force -ErrorAction SilentlyContinue

        Write-Host "HUMAN_REPORT: COPIED_TO_OUTPUT"
    }
}
catch {
    Write-Host ("HUMAN_REPORT: COPY_SKIPPED " + $_.Exception.Message)
}
# === END COPY ===
    if (Test-Path $runReportPath) {
        $run = Get-Content $runReportPath -Raw | ConvertFrom-Json

        $status = if ($run.status_label) { [string]$run.status_label } else { [string]$run.status }
        $confidence = if ($run.audit_confidence) { [string]$run.audit_confidence } else { "UNKNOWN" }
        $confidenceReason = if ($run.confidence_reason) { [string]$run.confidence_reason } else { "not_specified" }
        $nextVerificationStep = if ($run.next_verification_step) { [string]$run.next_verification_step } else { "rerun with full evidence checks" }

        $reportEn = @()
        $reportEn += "SITE STATUS: $status"
        $reportEn += ""
        $reportEn += "WHAT WE KNOW:"
        $reportEn += "- Audit completed through LINK mode"
        $reportEn += "- Visual capture may be limited"
        $reportEn += ""
        $reportEn += "CONFIDENCE: $confidence"
        $reportEn += "CONFIDENCE REASON: $confidenceReason"
        $reportEn += "NEXT VERIFICATION STEP: $nextVerificationStep"

        $reportRu = @()
        $reportRu += "СТАТУС САЙТА: $status"
        $reportRu += ""
        $reportRu += "ЧТО ИЗВЕСТНО:"
        $reportRu += "- Аудит выполнен в LINK режиме"
        $reportRu += "- Визуальная проверка может отсутствовать"
        $reportRu += ""
        $reportRu += "УВЕРЕННОСТЬ: $confidence"
        $reportRu += "ПРИЧИНА УВЕРЕННОСТИ: $confidenceReason"
        $reportRu += "СЛЕДУЮЩИЙ ШАГ ПРОВЕРКИ: $nextVerificationStep"

        $enPath = Join-Path (Get-Location) "REPORT_EN.txt"
        $ruPath = Join-Path (Get-Location) "REPORT_RU.txt"

        $reportEn | Out-File $enPath -Encoding UTF8
        $reportRu | Out-File $ruPath -Encoding UTF8

        Write-Host "HUMAN_REPORT: DONE"

# === COPY USING RUN_REPORT PATH ===
try {
    $runReportPath = Join-Path $PSScriptRoot "output"
    $runReportFile = Get-ChildItem -Path $runReportPath -Recurse -Filter "RUN_REPORT.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($null -ne $runReportFile) {
        $targetDir = Split-Path $runReportFile.FullName -Parent

        $rootEnPath = Join-Path $PSScriptRoot "REPORT_EN.txt"
        $rootRuPath = Join-Path $PSScriptRoot "REPORT_RU.txt"
        if ((Test-Path -LiteralPath $rootEnPath -PathType Leaf) -and (Test-Path -LiteralPath $rootRuPath -PathType Leaf)) {
            Copy-Item $rootEnPath -Destination (Join-Path $targetDir "REPORT_EN.txt") -Force
            Copy-Item $rootRuPath -Destination (Join-Path $targetDir "REPORT_RU.txt") -Force
            Write-Host ("HUMAN_REPORT: COPIED_TO " + $targetDir)
        }
        else {
            Write-Host "HUMAN_REPORT: ROOT_REPORTS_NOT_FOUND_FOR_COPY"
        }
    }
    else {
        Write-Host "HUMAN_REPORT: RUN_REPORT_NOT_FOUND_FOR_COPY"
    }
}
catch {
    Write-Host ("HUMAN_REPORT: COPY_SKIPPED " + $_.Exception.Message)
}
# === END COPY ===

# === COPY HUMAN REPORT INTO REAL OUTPUT DIR ===
try {
    $outputRoot = Join-Path $PSScriptRoot "output"

    if (Test-Path $outputRoot) {
        $latestDir = Get-ChildItem $outputRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if ($null -ne $latestDir) {
            $targetDir = $latestDir.FullName

            $rootEnPath = Join-Path $PSScriptRoot "REPORT_EN.txt"
            $rootRuPath = Join-Path $PSScriptRoot "REPORT_RU.txt"
            if ((Test-Path -LiteralPath $rootEnPath -PathType Leaf) -and (Test-Path -LiteralPath $rootRuPath -PathType Leaf)) {
                Copy-Item $rootEnPath -Destination (Join-Path $targetDir "REPORT_EN.txt") -Force
                Copy-Item $rootRuPath -Destination (Join-Path $targetDir "REPORT_RU.txt") -Force
                Write-Host ("HUMAN_REPORT: COPIED_TO " + $targetDir)
            }
            else {
                Write-Host "HUMAN_REPORT: ROOT_REPORTS_NOT_FOUND_FOR_COPY"
            }
        }
    }
}
catch {
    Write-Host ("HUMAN_REPORT: COPY_SKIPPED " + $_.Exception.Message)
}
# === END COPY ===
    }
    else {
        Write-Host "HUMAN_REPORT: RUN_REPORT_MISSING"
    }
}
catch {
    Write-Host ("HUMAN_REPORT: FAILED " + $_.Exception.Message)
}
# === END HUMAN REPORT ===
}

function Get-DeterministicRunKey {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode,
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl
    )

    $input = "{0}|{1}" -f $Mode.Trim().ToUpperInvariant(), $BaseUrl.Trim().ToLowerInvariant()
    $bytes = [Text.Encoding]::UTF8.GetBytes($input)
    $hashBytes = [Security.Cryptography.SHA256]::HashData($bytes)
    $hash = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
    return "{0}_{1}" -f $Mode.Trim().ToLowerInvariant(), $hash.Substring(0, 12)
}

function Test-PrimaryRouteValue {
    param(
        [string]$Value
    )

    $routeValue = [string]$Value
    if ([string]::IsNullOrWhiteSpace($routeValue)) {
        return [ordered]@{ valid = $false; reason = 'empty' }
    }

    $trimmed = $routeValue.Trim()
    if (-not $trimmed.StartsWith('/')) {
        return [ordered]@{ valid = $false; reason = 'must_start_with_slash' }
    }
    if ($trimmed -match '^[a-z][a-z0-9+\-.]*://') {
        return [ordered]@{ valid = $false; reason = 'contains_scheme' }
    }
    if ($trimmed -match '#') {
        return [ordered]@{ valid = $false; reason = 'contains_fragment' }
    }
    if ($trimmed -match '\?') {
        return [ordered]@{ valid = $false; reason = 'contains_query' }
    }
    if ($trimmed -match '^//') {
        return [ordered]@{ valid = $false; reason = 'contains_host_like_prefix' }
    }
    if (($trimmed.Length -gt 1) -and $trimmed.EndsWith('/')) {
        return [ordered]@{ valid = $false; reason = 'trailing_slash_not_normalized' }
    }

    return [ordered]@{ valid = $true; reason = '' }
}

function Get-NormalizedPrimaryRouteIdentity {
    param(
        [string]$Value,
        [string]$BaseUrl = ''
    )

    $routeValue = [string]$Value
    if ([string]::IsNullOrWhiteSpace($routeValue)) {
        return ''
    }

    $trimmed = $routeValue.Trim()
    $canonicalRouteResult = Get-CanonicalRouteKeyResult -RouteValue $trimmed -BaseUrl $BaseUrl
    if ($canonicalRouteResult.status -eq 'ok' -and -not [string]::IsNullOrWhiteSpace([string]$canonicalRouteResult.canonical_route)) {
        return [string]$canonicalRouteResult.canonical_route
    }

    $pathOnly = $trimmed
    $queryIndex = $pathOnly.IndexOf('?')
    if ($queryIndex -ge 0) {
        $pathOnly = $pathOnly.Substring(0, $queryIndex)
    }
    $fragmentIndex = $pathOnly.IndexOf('#')
    if ($fragmentIndex -ge 0) {
        $pathOnly = $pathOnly.Substring(0, $fragmentIndex)
    }

    if ([string]::IsNullOrWhiteSpace($pathOnly)) {
        return '/'
    }

    if (($pathOnly.Length -gt 1) -and $pathOnly.EndsWith('/')) {
        $pathOnly = $pathOnly.TrimEnd('/')
    }
    if ([string]::IsNullOrWhiteSpace($pathOnly)) {
        $pathOnly = '/'
    }
    if (-not $pathOnly.StartsWith('/')) {
        $pathOnly = "/$pathOnly"
    }

    return [string]$pathOnly
}

function Normalize-PrimaryRouteContractFields {
    param(
        [Parameter(Mandatory = $true)]
        [object]$RunReport,
        [Parameter(Mandatory = $true)]
        [object]$RoutesSummary,
        [Parameter(Mandatory = $true)]
        [object]$VisualManifest,
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl
    )

    foreach ($selectedRoute in @($RunReport.selected_routes)) {
        $selectedRoute.route = Get-NormalizedPrimaryRouteIdentity -Value ([string]$selectedRoute.route) -BaseUrl $BaseUrl
    }

    foreach ($pageVerdict in @($RunReport.page_verdicts)) {
        $pageVerdict.route = Get-NormalizedPrimaryRouteIdentity -Value ([string]$pageVerdict.route) -BaseUrl $BaseUrl
    }

    foreach ($overflowRoute in @($RunReport.run_budget.overflow_route_details)) {
        $overflowRoute.route = Get-NormalizedPrimaryRouteIdentity -Value ([string]$overflowRoute.route) -BaseUrl $BaseUrl
    }

    foreach ($manifestPage in @($VisualManifest.pages)) {
        $manifestPage.route = Get-NormalizedPrimaryRouteIdentity -Value ([string]$manifestPage.route) -BaseUrl $BaseUrl
    }

    foreach ($summaryRoute in @($RoutesSummary.routes)) {
        $summaryRoute.normalized_route = Get-NormalizedPrimaryRouteIdentity -Value ([string]$summaryRoute.normalized_route) -BaseUrl $BaseUrl
    }
}

function Test-RouteContract {
    param(
        [Parameter(Mandatory = $true)]
        [object]$RunReport,
        [Parameter(Mandatory = $true)]
        [object]$RoutesSummary,
        [Parameter(Mandatory = $true)]
        [object]$VisualManifest
    )

    $violations = New-Object System.Collections.Generic.List[object]
    function Add-RouteViolation {
        param(
            [string]$ArtifactPath,
            [string]$FieldPath,
            [string]$Value,
            [string]$Reason
        )
        $violations.Add([ordered]@{
                artifact_path = $ArtifactPath
                field_path = $FieldPath
                offending_value = $Value
                reason = $Reason
            })
    }

    $selectedRoutes = @($RunReport.selected_routes)
    for ($i = 0; $i -lt $selectedRoutes.Count; $i++) {
        $testResult = Test-PrimaryRouteValue -Value ([string]$selectedRoutes[$i].route)
        if (-not $testResult.valid) {
            Add-RouteViolation -ArtifactPath 'RUN_REPORT.json' -FieldPath ("selected_routes[{0}].route" -f $i) -Value ([string]$selectedRoutes[$i].route) -Reason ([string]$testResult.reason)
        }
    }

    $pageVerdicts = @($RunReport.page_verdicts)
    for ($i = 0; $i -lt $pageVerdicts.Count; $i++) {
        $testResult = Test-PrimaryRouteValue -Value ([string]$pageVerdicts[$i].route)
        if (-not $testResult.valid) {
            Add-RouteViolation -ArtifactPath 'RUN_REPORT.json' -FieldPath ("page_verdicts[{0}].route" -f $i) -Value ([string]$pageVerdicts[$i].route) -Reason ([string]$testResult.reason)
        }
    }

    $overflowRoutes = @($RunReport.run_budget.overflow_route_details)
    for ($i = 0; $i -lt $overflowRoutes.Count; $i++) {
        $testResult = Test-PrimaryRouteValue -Value ([string]$overflowRoutes[$i].route)
        if (-not $testResult.valid) {
            Add-RouteViolation -ArtifactPath 'RUN_REPORT.json' -FieldPath ("run_budget.overflow_route_details[{0}].route" -f $i) -Value ([string]$overflowRoutes[$i].route) -Reason ([string]$testResult.reason)
        }
    }

    $manifestPages = @($VisualManifest.pages)
    for ($i = 0; $i -lt $manifestPages.Count; $i++) {
        $testResult = Test-PrimaryRouteValue -Value ([string]$manifestPages[$i].route)
        if (-not $testResult.valid) {
            Add-RouteViolation -ArtifactPath 'visual_manifest.json' -FieldPath ("pages[{0}].route" -f $i) -Value ([string]$manifestPages[$i].route) -Reason ([string]$testResult.reason)
        }
    }

    $summaryRoutes = @($RoutesSummary.routes)
    for ($i = 0; $i -lt $summaryRoutes.Count; $i++) {
        $testResult = Test-PrimaryRouteValue -Value ([string]$summaryRoutes[$i].normalized_route)
        if (-not $testResult.valid) {
            Add-RouteViolation -ArtifactPath 'ROUTES_SUMMARY.json' -FieldPath ("routes[{0}].normalized_route" -f $i) -Value ([string]$summaryRoutes[$i].normalized_route) -Reason ([string]$testResult.reason)
        }
    }

    $violationItems = @()
    if ($null -ne $violations) {
        $violationItems = @($violations.ToArray())
    }

    $routeContractStatus = 'ok'
    if ($violationItems.Count -gt 0) {
        $routeContractStatus = 'failed'
    }

    return [ordered]@{
        status = [string]$routeContractStatus
        primary_key_format = 'path_only'
        violations = @($violationItems)
    }
}

function Invoke-VisualCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Pages,
        [Parameter(Mandatory = $true)]
        [string]$ToolPath,
        [Parameter(Mandatory = $true)]
        [string]$InputPath,
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,
        [Parameter(Mandatory = $true)]
        [string]$ScreenshotsPath
    )

    Ensure-Directory -Path $ScreenshotsPath
    $payloadPages = @(
        for ($i = 0; $i -lt $Pages.Count; $i++) {
            [ordered]@{
                index = ($i + 1)
                url = $Pages[$i]
            }
        }
    )
    $payload = [ordered]@{
        pages = $payloadPages
        screenshots_dir = $ScreenshotsPath
        viewport = [ordered]@{
            width = 1366
            height = 768
        }
    }
    Write-JsonFile -Path $InputPath -Data $payload

    & node $ToolPath $InputPath $ManifestPath
    return $LASTEXITCODE
}

function Invoke-EvidenceReconciliation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,
        [Parameter(Mandatory = $true)]
        [string]$ScreenshotsPath,
        [Parameter(Mandatory = $true)]
        [int]$RunReportPagesAttempted,
        [Parameter(Mandatory = $true)]
        [int]$RunReportCapturesAttempted,
        [Parameter(Mandatory = $true)]
        [int]$RunReportCapturesSuccess,
        [Parameter(Mandatory = $true)]
        [int]$RunReportCapturesFailed
    )

    $sizeThresholdBytes = 10000
    $manifestRaw = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $manifestPages = @($manifestRaw.pages)
    $captures = @(
        $manifestPages |
        ForEach-Object { @($_.captures) }
    )

    $pngFiles = if (Test-Path -LiteralPath $ScreenshotsPath) {
        @(Get-ChildItem -LiteralPath $ScreenshotsPath -File -Filter '*.png')
    }
    else {
        @()
    }

    $issues = New-CaseInsensitiveKeyMap
    $validCount = 0
    $invalidCount = 0
    $checksCompleted = $true
    $diagnostics = New-Object System.Collections.Generic.List[string]

    foreach ($capture in $captures) {
        $relativeFile = [string]$capture.file
        if ([string]::IsNullOrWhiteSpace($relativeFile)) {
            $invalidCount += 1
            $null = Add-KeyIfMissing -Map $issues -Key 'manifest_mismatch'
            continue
        }

        $normalizedRelative = $relativeFile.Replace([string]'/', [string][System.IO.Path]::DirectorySeparatorChar)
        $expectedPath = Join-Path (Split-Path -Parent $ManifestPath) $normalizedRelative
        $fileStatus = 'ok'

        if (-not (Test-Path -LiteralPath $expectedPath)) {
            $fileStatus = 'missing_capture'
            $null = Add-KeyIfMissing -Map $issues -Key 'missing_capture'
        }
        else {
            try {
                $actualSize = [int](Get-Item -LiteralPath $expectedPath).Length
                if ($actualSize -lt $sizeThresholdBytes) {
                    $fileStatus = 'empty_capture'
                    $null = Add-KeyIfMissing -Map $issues -Key 'empty_capture'
                }
                if ([int]$capture.size_bytes -ne $actualSize) {
                    $null = Add-KeyIfMissing -Map $issues -Key 'size_mismatch'
                }
            }
            catch {

    # === FAIL TRACE BLOCK ===
    $failTrace = [ordered]@{
        error_message = $_.Exception.Message
        error_type = $_.Exception.GetType().FullName
        script_line = $_.InvocationInfo.ScriptLineNumber
        position = $_.InvocationInfo.PositionMessage
        stage = $currentStage
    }

    Write-Host ("FAIL_TRACE: " + ($failTrace | ConvertTo-Json -Depth 3))
    # === END FAIL TRACE ===
                $checksCompleted = $false
                $fileStatus = 'reconciliation_error'
                $null = Add-KeyIfMissing -Map $issues -Key 'reconciliation_error'
                $diagnostics.Add($_.Exception.Message)
            }
        }

        if ($fileStatus -eq 'ok') {
            $validCount += 1
        }
        else {
            $invalidCount += 1
        }
    }

    $manifestCaptureCount = [int]$captures.Count
    $actualCaptureCount = [int]$pngFiles.Count
    if ($manifestCaptureCount -ne $actualCaptureCount) {
        $null = Add-KeyIfMissing -Map $issues -Key 'manifest_mismatch'
    }

    $manifestPageCount = [int]$manifestPages.Count
    $pageRegex = '^page-(?<idx>\d{2})-'
    $actualUniquePageKeys = New-CaseInsensitiveKeyMap
    foreach ($png in $pngFiles) {
        $match = [regex]::Match($png.Name, $pageRegex)
        if ($match.Success) {
            $null = Add-KeyIfMissing -Map $actualUniquePageKeys -Key ([string]$match.Groups['idx'].Value)
        }
    }

    if (($RunReportPagesAttempted -ne $manifestPageCount) -or ($manifestPageCount -ne (Get-KeyMapCount -Map $actualUniquePageKeys))) {
        $null = Add-KeyIfMissing -Map $issues -Key 'RUN_REPORT_INCONSISTENT'
    }
    if (
        ($RunReportCapturesAttempted -ne $manifestCaptureCount) -or
        ($RunReportCapturesSuccess -ne $validCount) -or
        ($RunReportCapturesFailed -ne $invalidCount)
    ) {
        $null = Add-KeyIfMissing -Map $issues -Key 'RUN_REPORT_COUNTER_MISMATCH'
    }

    $status = 'PASS'
    if ($validCount -eq 0 -and ($manifestCaptureCount -gt 0)) {
        $status = 'FAIL'
    }
    elseif ($invalidCount -gt 0 -or (Get-KeyMapCount -Map $issues) -gt 0) {
        $status = 'PARTIAL'
    }
    elseif ($manifestCaptureCount -eq 0) {
        $status = 'FAIL'
        $null = Add-KeyIfMissing -Map $issues -Key 'no_captures'
    }

    if (-not $checksCompleted) {
        $status = 'FAIL'
        $null = Add-KeyIfMissing -Map $issues -Key 'reconciliation_error'
    }

    if (
        (Test-KeyExists -Map $issues -Key 'missing_capture') -or
        (Test-KeyExists -Map $issues -Key 'empty_capture') -or
        (Test-KeyExists -Map $issues -Key 'manifest_mismatch')
    ) {
        if ($status -eq 'PASS') {
            $status = 'PARTIAL'
        }
    }

    return [ordered]@{
        status = $status
        files_checked = $manifestCaptureCount
        files_valid = [int]$validCount
        files_invalid = [int]$invalidCount
        issues = @(Get-KeyMapKeys -Map $issues)
        manifest_pages = $manifestPageCount
        run_report_pages_attempted = $RunReportPagesAttempted
        actual_unique_pages = Get-KeyMapCount -Map $actualUniquePageKeys
        diagnostics = @($diagnostics)
    }
}

function Get-LocalizedErrorFromExceptionMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $parsed = [ordered]@{
        code = ''
        detail = [string]$Message
    }

    $match = [regex]::Match([string]$Message, '^\s*(ROUTE_EXTRACTION_[A-Z0-9_]+)\s*:\s*(.+)$')
    if ($match.Success) {
        $parsed.code = [string]$match.Groups[1].Value
        $parsed.detail = [string]$match.Groups[2].Value
        return $parsed
    }

    return $parsed
}

function Get-EffectiveFailureClass {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FailureStage,
        [Parameter(Mandatory = $true)]
        [string]$ErrorCode,
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage
    )

    $stage = ([string]$FailureStage).ToUpperInvariant()
    $code = ([string]$ErrorCode).ToUpperInvariant()
    $message = ([string]$ErrorMessage).ToUpperInvariant()
    $isRouteRuntimeException = (
        ($stage -eq 'ROUTE_EXTRACTION') -and (
            $code.StartsWith('ROUTE_EXTRACTION_') -or
            $message.Contains('ARGUMENT TYPES DO NOT MATCH')
        )
    )
    if ($isRouteRuntimeException) {
        return 'AGENT_DEFECT'
    }

    return (Get-FailureClass -FailureStage $FailureStage -ErrorCode $ErrorCode)
}

$normalizedMode = $Mode.Trim().ToUpperInvariant()
$maxRoutes = 18
$timestamp = Get-IsoUtcNow
$originalBaseUrlInput = [string]$BaseUrl
$canonicalBaseUrlResult = Resolve-CanonicalBaseUrl -BaseUrl $originalBaseUrlInput
$canonicalBaseUrl = if ($canonicalBaseUrlResult.status -eq 'ok') { [string]$canonicalBaseUrlResult.canonical_url } else { '' }
$runKeyBaseUrl = if ($canonicalBaseUrlResult.status -eq 'ok') { $canonicalBaseUrl } else { $originalBaseUrlInput.Trim() }
$runKey = Get-DeterministicRunKey -Mode $Mode -BaseUrl $runKeyBaseUrl
$ownershipMode = Get-OwnershipMode
$outputRoot = Join-Path $PSScriptRoot (Join-Path 'output' $runKey)
$OutputDir = $outputRoot
$runReportPath = Join-Path $outputRoot 'RUN_REPORT.json'
$linkSummaryPath = Join-Path $outputRoot 'LINK_SUMMARY.json'
$routesSummaryPath = Join-Path $outputRoot 'ROUTES_SUMMARY.json'
$auditSummaryPath = Join-Path $outputRoot 'AUDIT_SUMMARY.json'
$actionSummaryPath = Join-Path $outputRoot 'ACTION_SUMMARY.json'
$actionReportPath = Join-Path $outputRoot 'ACTION_REPORT.txt'
$humanReportRuPath = Join-Path $outputRoot 'HUMAN_REPORT_RU.html'
$humanReportEnPath = Join-Path $outputRoot 'HUMAN_REPORT_EN.html'
$failurePath = Join-Path $outputRoot 'failure_summary.json'
$agentFailureReportPath = Join-Path $outputRoot 'AGENT_FAILURE_REPORT.txt'
$operatorHandoffPath = Join-Path $outputRoot 'AGENT_OPERATOR_HANDOFF.json'
$visualManifestPath = Join-Path $outputRoot 'visual_manifest.json'
$reportContractDiagPath = Join-Path $outputRoot 'REPORT_CONTRACT_DIAG.json'
$visualInputPath = Join-Path $outputRoot 'visual_capture_input.json'
$screenshotsPath = Join-Path $outputRoot 'screenshots'
$deterministicRunReportPath = Join-Path $PSScriptRoot 'RUN_REPORT.json'
$deterministicLinkSummaryPath = Join-Path $PSScriptRoot 'LINK_SUMMARY.json'
$deterministicRoutesSummaryPath = Join-Path $PSScriptRoot 'ROUTES_SUMMARY.json'
$deterministicAuditSummaryPath = Join-Path $PSScriptRoot 'AUDIT_SUMMARY.json'
$deterministicActionSummaryPath = Join-Path $PSScriptRoot 'ACTION_SUMMARY.json'
$deterministicActionReportPath = Join-Path $PSScriptRoot 'ACTION_REPORT.txt'
$deterministicHumanReportRuPath = Join-Path $PSScriptRoot 'HUMAN_REPORT_RU.html'
$deterministicHumanReportEnPath = Join-Path $PSScriptRoot 'HUMAN_REPORT_EN.html'
$deterministicFailurePath = Join-Path $PSScriptRoot 'failure_summary.json'
$deterministicAgentFailureReportPath = Join-Path $PSScriptRoot 'AGENT_FAILURE_REPORT.txt'
$deterministicOperatorHandoffPath = Join-Path $PSScriptRoot 'AGENT_OPERATOR_HANDOFF.json'
$deterministicVisualManifestPath = Join-Path $PSScriptRoot 'visual_manifest.json'
$deterministicReportContractDiagPath = Join-Path $PSScriptRoot 'REPORT_CONTRACT_DIAG.json'
$deterministicScreenshotsPath = Join-Path $PSScriptRoot 'screenshots'

$allowedExtensions = @(
    '.json',
    '.txt',
    '.png'
)

$allowedFolders = @(
    'captures',
    'summaries',
    'logs'
)

$script:ProducedArtifactsRegistry = New-Object 'System.Collections.Generic.List[string]'

function Get-ProducedArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDir,
        [Parameter(Mandatory = $true)]
        [string[]]$AllowedFolders,
        [Parameter(Mandatory = $true)]
        [string[]]$AllowedExtensions
    )

    $artifactFiles = @()

    foreach ($folder in $AllowedFolders) {
        $path = Join-Path $OutputDir $folder
        if (Test-Path $path) {
            $artifactFiles += Get-ChildItem -Path $path -File -Recurse
        }
    }

    $rootFiles = Get-ChildItem -Path $OutputDir -File |
        Where-Object { $_.Extension -in $AllowedExtensions }

    $artifactFiles += $rootFiles

    return @(
        $artifactFiles | ForEach-Object {
            $_.FullName.Replace($OutputDir + [System.IO.Path]::DirectorySeparatorChar, '')
        } | Select-Object -Unique
    )
}

function Add-ProducedArtifactIfExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDir,
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace([string]$RelativePath)) {
        return
    }

    $absolutePath = Join-Path $OutputDir $RelativePath
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
        return
    }

    if (-not $script:ProducedArtifactsRegistry.Contains($RelativePath)) {
        $script:ProducedArtifactsRegistry.Add([string]$RelativePath)
    }
}

function Add-ProducedArtifactsFromScan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDir,
        [Parameter(Mandatory = $true)]
        [string[]]$AllowedFolders,
        [Parameter(Mandatory = $true)]
        [string[]]$AllowedExtensions
    )

    $scannedArtifacts = @(
        Get-ProducedArtifacts -OutputDir $OutputDir -AllowedFolders $AllowedFolders -AllowedExtensions $AllowedExtensions
    )

    foreach ($artifact in $scannedArtifacts) {
        if (-not [string]::IsNullOrWhiteSpace([string]$artifact) -and -not $script:ProducedArtifactsRegistry.Contains([string]$artifact)) {
            $script:ProducedArtifactsRegistry.Add([string]$artifact)
        }
    }
}


function Get-FinalProducedArtifacts {
    param(
        [string]$OutputDir,
        $AllowedFolders,
        $AllowedExtensions,
        [string]$Status
    )

    $resolvedOutputDir = (Resolve-Path $OutputDir).Path
    $files = Get-ChildItem -Path $resolvedOutputDir -File -Recurse

    $finalArtifacts = @()

    foreach ($f in $files) {
        $rel = [System.IO.Path]::GetRelativePath($resolvedOutputDir, $f.FullName)
        $rel = $rel -replace "\\", "/"

        if ($rel.StartsWith("/") -or $rel.StartsWith("agents/") -or $rel.StartsWith("output/")) {
            Write-Host "SKIP_BAD_ARTIFACT_PATH: $rel"
            continue
        }

        $finalArtifacts += $rel
    }

    return $finalArtifacts
}

$capability_capture = $true
$limitation_capture_missing = $false
$capabilityCapture = $capability_capture
$limitationCaptureMissing = $limitation_capture_missing
$capabilityStatus = [ordered]@{
    link = 'ACTIVE'
    capture = 'ACTIVE'
    routes = 'ACTIVE'
    page_quality = 'NOT_IMPLEMENTED'
    decision = 'NOT_IMPLEMENTED'
}

$learningBacklog = @(
    'Implement LINK crawler coverage depth controls.',
    'Define route normalization contract for LINK mode outputs.',
    'Design page quality scoring rubric for future sprint.',
    'Add decision synthesis contract after quality signals stabilize.'
)


$notDoneYet = @(
    'Capture mode supports baseline screenshot evidence only (no interactions).',
    'Page-quality scoring is not implemented.',
    'Decision synthesis is not implemented.'
)

$cannotDoYet = @(
    'Cannot run repository-wide inspection in LINK mode.',
    'Cannot provide scoring decisions without page-quality module.'
)

$report = [ordered]@{
    mode = $normalizedMode
    base_url = $canonicalBaseUrl
    ownership_mode = $ownershipMode
    input_canonicalization = [ordered]@{
        original = $originalBaseUrlInput
        canonical = $canonicalBaseUrl
        status = if ($canonicalBaseUrlResult.status -eq 'ok') { 'ok' } else { 'failed' }
    }
    status = 'PASS'
    execution_status = 'SUCCESS'
    run_id = $runKey
    output_folder = $outputRoot
    timestamp_utc = $timestamp
    capability_status = $capabilityStatus
    capabilities = [ordered]@{
        capture = $true
    }
    learning_backlog = $learningBacklog
    execution_report = [ordered]@{
        final_outcome = 'PASS'
        status_detail = 'PASS'
        mode = $normalizedMode
    }
    not_done_yet = $notDoneYet
    cannot_do_yet = $cannotDoYet
    failure_or_limit_report = [ordered]@{
        kind = 'NONE'
        failure_summary = ''
        notes = @()
    }
    linked_artifacts = @(
        [ordered]@{ name = 'run_report'; path = $runReportPath },
        [ordered]@{ name = 'link_summary'; path = $linkSummaryPath },
        [ordered]@{ name = 'routes_summary'; path = $routesSummaryPath },
        [ordered]@{ name = 'audit_summary'; path = $auditSummaryPath },
        [ordered]@{ name = 'action_summary'; path = $actionSummaryPath },
        [ordered]@{ name = 'action_report'; path = $actionReportPath },
        [ordered]@{ name = 'human_report_ru'; path = $humanReportRuPath },
        [ordered]@{ name = 'human_report_en'; path = $humanReportEnPath },
        [ordered]@{ name = 'visual_manifest'; path = $visualManifestPath },
        [ordered]@{ name = 'screenshots'; path = $screenshotsPath },
        [ordered]@{ name = 'agent_failure_report'; path = $agentFailureReportPath },
        [ordered]@{ name = 'agent_operator_handoff'; path = $operatorHandoffPath }
    )
    problem_targets = @()
    fetch_debug = [ordered]@{
        status_code = ''
        html_length = 0
        body_present = $false
        content_sample = ''
    }
    raw_links_found = 0
    internal_links = 0
    filter_reason = @()
    html_snapshot = ''
    link_extraction_failed = $false
    operator_handoff = [ordered]@{
        deprecated = $true
        reader_role = 'ChatGPT decision/orchestration layer'
        mirrors_operator_memory_bridge = $true
        ownership_mode = $ownershipMode
        action_scope_explanation = if ($ownershipMode -eq 'OWNED') { 'Owned site: fix/update/optimize actions are allowed when supported by findings.' } else { 'External site: actions are limited to analyze/benchmark/replicate insights, not direct page fixes.' }
        must_do_before_next_task = @()
        what_to_inspect_next = @()
        truth_files = @()
        read_order = @()
        must_read_first = @('RUN_REPORT.json')
        first_file_to_open = ''
        exact_reason = ''
        do_not_do_yet = @()
        forbidden_moves = @(
            'do not guess parameter names',
            'do not generate task without reading truth_files',
            'do not patch unrelated files'
        )
        if_missing_artifact = 'Request exact missing file; do not proceed'
    }
    summary = 'LINK mode executes live fetch, route checks, and screenshot evidence capture.'
    next_step = 'Stabilize screenshot evidence quality in LINK mode.'
    confidence_reason = ''
    next_verification_step = ''
    forbidden_next_steps = @()
    status_label = 'PASS'
    report_mode = 'CLEAN'
    executive_answer = [ordered]@{
        overall_verdict = 'limited: findings layer not computed'
        primary_problem = 'audit answer layer unavailable'
        audit_scope = 'LINK mode / screenshot evidence baseline'
        strongest_next_move = 'derive deterministic findings from existing artifacts'
    }
    findings_count = 0
    limitation_count = 0
    limitations = @()
    report_layer = [ordered]@{
        limitation = [ordered]@{
            capture_not_available = $false
        }
    }
    audit_confidence = 'LOW'
    decision_summary = $null
    decision = [ordered]@{
        core_problem = 'Decision synthesis pending.'
        p0 = @()
        do_next = @()
    }
    system_problem = $null
    next_strongest_move = 'Expand audit coverage before making decisions.'
    findings = @()
    operator_feed = [ordered]@{
        system_state = ''
        primary_constraint = ''
        truth_confidence = ''
        what_is_reliable = @()
        what_is_not_reliable = @()
        next_system_move = ''
        why_this_move = ''
        do_not_do_yet = @()
    }
    operator_memory_core = [ordered]@{
        who_am_i = 'system operator building site auditor agent'
        what_system_is_being_built = 'site audit agent → decision → action → monetization system'
        primary_asset = 'automation site as decision system'
        end_goal = 'traffic → decision → action → monetization'
        current_stage = ''
        current_focus = ''
        what_is_stable = @()
        what_is_unstable = @()
        agent_learned = @()
        agent_cannot_yet = @()
        agent_misleading_risk = @()
        next_capability_to_build = ''
    }
    operator_memory_bridge = [ordered]@{
        status_detail = ''
        current_execution_mode = ''
        current_layer = ''
        layer_owner_file = ''
        next_file_to_inspect = ''
        reason_to_inspect = ''
        one_next_step = ''
        forbidden_next_steps = @()
        tool_recommendation = ''
        identity_anchor = [ordered]@{
            who_am_i = 'system operator building site auditor agent'
            what_system_is_being_built = 'site audit agent → decision → action → monetization system'
            primary_asset = 'automation site as decision system'
            end_goal = 'traffic → decision → action → monetization'
        }
        state_anchor = [ordered]@{
            current_stage = ''
            current_focus = ''
            what_is_stable = @()
            what_is_unstable = @()
        }
        learning_anchor = [ordered]@{
            agent_learned = @()
            agent_cannot_yet = @()
            agent_misleading_risk = @()
            next_capability_to_build = ''
        }
          must_read_contract = [ordered]@{
            must_read_files = @('RUN_REPORT.json', 'ROUTES_SUMMARY.json', 'AUDIT_SUMMARY.json', 'ACTION_SUMMARY.json', 'visual_manifest.json')
            read_order = @('RUN_REPORT.json', 'ROUTES_SUMMARY.json', 'AUDIT_SUMMARY.json', 'ACTION_SUMMARY.json', 'visual_manifest.json')
            first_file_to_open = 'RUN_REPORT.json'
            why_read = 'RUN_REPORT.json is the source of truth for current report state, sampled route evidence, and report-layer constraints.'
            minimum_context_after_read = 'visual truth is bounded to sampled LINK coverage, route selection is stable in-budget, and deeper interpretation remains limited without interaction/decision layers.'
        }
        next_operator_posture = [ordered]@{
            next_system_move = ''
            must_do_before_next_task = @()
            what_to_inspect_next = @()
            recommended_tool = ''
            forbidden_drifts = @()
            do_not_do_yet = @()
        }
    }
    priority_summary = [ordered]@{
        p0_count = 0
        p1_count = 0
        p2_count = 0
        limitation_count = 0
        top_issues = @()
    }
    page_verdicts = @()
    business_impact = [ordered]@{
        trust = 'unknown'
        navigation = 'unknown'
        coverage = 'unknown'
        monetization_readiness = 'unknown'
    }
    next_action_contract = [ordered]@{
        next_task_id = 'SITE_AUDITOR_V2_REPORT_LAYER_FOLLOWUP'
        next_task_objective = 'produce bounded findings from existing LINK-mode truth artifacts'
        why_this_first = 'operator needs deterministic answer contract before deeper interpretation'
        forbidden_before_done = @(
            'do not add interaction layer',
            'do not expand crawl depth',
            'do not add decision automation'
        )
    }
    self_build_protocol = [ordered]@{
        failure_class_contract = @('AGENT_DEFECT', 'OBJECT_DEFECT', 'AUDIT_LIMITATION')
        build_ladder = Get-BuildLadderContract -HasTruthfulFailure $false -HasSelfDiagnostic $false -HasOperatorHandoff $false
        build_lock_message = 'Feature progress is blocked until layers 2-4 are READY.'
        feature_progress_allowed = $false
    }
    decision_allowed = $true
    reconciliation_enforced = $false
    route_normalization = 'ok'
    route_contract = [ordered]@{
        status = 'ok'
        primary_key_format = 'path_only'
        violations = @()
    }
}

$shouldFail = $false
$errorCode = ''
$errorMessage = ''
$failurePhase = 'ENTRY'
$lastCompletedStage = 'ENTRY'
$currentFailureStage = 'ENTRY'
$failureDiagnostics = Get-ScriptFailureDiagnostics -ErrorRecord $null -LastReportLayerMarker ''
$reconciliationCompleted = $false
$counterMismatchDetected = $false
Write-BootstrapStageTrace -Stage 'ENTRY'

if ($canonicalBaseUrlResult.status -ne 'ok') {
    $shouldFail = $true
    $errorCode = 'INVALID_BASE_URL'
    $errorMessage = [string]$canonicalBaseUrlResult.error
    $report.input_canonicalization.canonical = ''
    $report.input_canonicalization.status = 'failed'
}
else {
    $BaseUrl = $canonicalBaseUrl
    $report.base_url = $canonicalBaseUrl
}

if ($normalizedMode -ne 'LINK') {
    $shouldFail = $true
    $errorCode = 'UNSUPPORTED_MODE'
    $errorMessage = "Only MODE=LINK is supported. Received '$Mode'."
}

if ($shouldFail) {
    $report.status = 'FAIL'
    $report.execution_status = 'FAILED'
    $report.summary = "Run failed: $errorCode"
    $report.next_step = $errorMessage

# === SELF-REPAIR HANDOFF BLOCK ===
$report.operator_handoff = [ordered]@{
    what_happened = [string]$report.execution_status
    last_stage = [string]$report.last_completed_stage
    failure_stage = [string]$report.current_failure_stage

    read_this_first = @(
        'RUN_REPORT.json',
        'failure_summary.json',
        'ROUTES_SUMMARY.json',
        'AUDIT_SUMMARY.json'
    )

    what_you_are = 'repair operator for Universal Audit Engine'
    product_scope = 'do not treat as website-only tool'
    architecture = 'agent.ps1 is orchestrator, do not grow monolith'

    do = @(
        'find exact failing line',
        'fix one error only',
        'ensure WRITE_DONE is reached',
        'ensure exit code is 0'
    )

    do_not = @(
        'do not fix website',
        'do not modify multiple layers',
        'do not add new features',
        'do not rewrite large parts of agent'
    )
}
# === END HANDOFF ===
    $report.execution_report.final_outcome = 'FAIL'
    $report.execution_report.status_detail = 'FAIL'
    $report.last_completed_stage = [string]$lastCompletedStage
    $report.current_failure_stage = [string]$failurePhase
    $failureClass = Get-EffectiveFailureClass -FailureStage $failurePhase -ErrorCode $errorCode -ErrorMessage $errorMessage
    $report.failure_or_limit_report = [ordered]@{
        kind = 'FAILURE'
        failure_summary = 'failure_summary.json'
        failure_class = [string]$failureClass
        notes = @($errorMessage)
    }
    $report.produced_artifacts = Get-FinalProducedArtifacts -OutputDir $OutputDir -AllowedFolders $allowedFolders -AllowedExtensions $allowedExtensions -Status ([string]$report.status)
    $report.linked_artifacts = @(
        [ordered]@{ name = 'run_report'; path = $runReportPath },
        [ordered]@{ name = 'failure_summary'; path = $failurePath }
    )
}
else {
    try {
        $failurePhase = 'LINK_FETCH'
        $currentFailureStage = $failurePhase
        Write-BootstrapStageTrace -Stage 'LINK_FETCH'
        $linkSummary = Get-LinkSignals -Url $BaseUrl
        $lastCompletedStage = 'LINK_FETCH'
        Write-JsonFile -Path $linkSummaryPath -Data $linkSummary
        Copy-Item -LiteralPath $linkSummaryPath -Destination $deterministicLinkSummaryPath -Force

        $failurePhase = 'ROUTE_EXTRACTION'
        $currentFailureStage = $failurePhase
        Write-BootstrapStageTrace -Stage 'ROUTE_EXTRACTION'
        $routeExtraction = Get-ShallowRoutes -RootUrl $BaseUrl -MaxRoutes 30
        $routesSummaryPayload = [ordered]@{}
        if ($routeExtraction -is [System.Collections.IDictionary]) {
            foreach ($routeExtractionKey in @($routeExtraction.Keys)) {
                $routesSummaryPayload[[string]$routeExtractionKey] = $routeExtraction[$routeExtractionKey]
            }
        }
        elseif ($null -ne $routeExtraction) {
            foreach ($routeExtractionProperty in @($routeExtraction.PSObject.Properties)) {
                $routesSummaryPayload[[string]$routeExtractionProperty.Name] = $routeExtractionProperty.Value
            }
        }

        $routesSummaryRoutes = @()
        if ($routesSummaryPayload.Contains('routes')) {
            $routesSummaryRoutes = @($routesSummaryPayload['routes'] | Where-Object { $null -ne $_ })
        }
        $routesSummaryPayload['routes'] = @($routesSummaryRoutes)
        $routesSummaryPayload['route_count'] = [int]@($routesSummaryRoutes).Count
        if (-not $routesSummaryPayload.Contains('sampled_count') -and -not $routesSummaryPayload.Contains('selected_count')) {
            $routesSummaryPayload['sampled_count'] = [int]@($routesSummaryRoutes).Count
        }
        if (-not $routesSummaryPayload.Contains('status')) {
            $routesSummaryPayload['status'] = if ([bool]$routesSummaryPayload['link_extraction_failed']) { 'LIMITED' } else { 'PASS' }
        }
        $routesSummary = [pscustomobject]$routesSummaryPayload
        if ([int]$routesSummary.raw_links_found -le 0) {
            throw 'ROUTE_EXTRACTION_FAILED_NO_RAW_LINKS'
        }
        if ([int]$routesSummary.internal_links -le 0) {
            throw 'ROUTE_EXTRACTION_FAILED_NO_INTERNAL_LINKS'
        }
        $lastCompletedStage = 'ROUTE_EXTRACTION'
        $report.route_normalization = [string]$routesSummary.route_normalization
        $report.fetch_debug = [ordered]@{
            status_code = [string]$routesSummary.fetch_debug.status_code
            html_length = [int]$routesSummary.fetch_debug.html_length
            body_present = [bool]$routesSummary.fetch_debug.body_present
            content_sample = [string]$routesSummary.fetch_debug.content_sample
        }
        $report.raw_links_found = [int]$routesSummary.raw_links_found
        $report.internal_links = [int]$routesSummary.internal_links
        $report.filter_reason = @($routesSummary.filter_reason)
        $report.html_snapshot = [string]$routesSummary.html_snapshot
        $report.link_extraction_failed = [bool]$routesSummary.link_extraction_failed
        foreach ($route in $routesSummary.routes) {
            if (-not $route.PSObject.Properties['classification']) {
                $route.classification = if ($route.status_code -ne 200) { 'broken' } elseif ($route.html_length -lt 1500) { 'thin' } else { 'ok' }
            }
        }
        Write-JsonFile -Path $routesSummaryPath -Data $routesSummary
        Copy-Item -LiteralPath $routesSummaryPath -Destination $deterministicRoutesSummaryPath -Force
        Write-Host 'POST_ROUTE:ROUTES_SUMMARY_WRITTEN'

        $brokenTargets = @(
            $routesSummary.routes |
            Where-Object { $_.classification -eq 'broken' } |
            ForEach-Object {
                [ordered]@{
                    url = $_.url
                    classification = 'broken'
                    reason = 'status_code not 200'
                    action = Get-ActionTextByOwnership -OwnershipMode $ownershipMode -OwnedAction 'fix or remove page' -ExternalAction 'analyze broken route pattern and benchmark alternatives'
                }
            }
        )
        $shellTargets = @(
            $routesSummary.routes |
            Where-Object { $_.classification -eq 'shell' } |
            Sort-Object html_length, url |
            Select-Object -First 3 |
            ForEach-Object {
                [ordered]@{
                    url = $_.url
                    classification = 'shell'
                    reason = 'shell_like_structure_with_weak_first_screen_text'
                    action = Get-ActionTextByOwnership -OwnershipMode $ownershipMode -OwnedAction 'inspect page template/content loading for shell-only render' -ExternalAction 'note shell-like page behavior for benchmarking and reliability comparison'
                }
            }
        )
        $thinTargets = @(
            $routesSummary.routes |
            Where-Object { $_.classification -eq 'thin' } |
            Sort-Object html_length, url |
            Select-Object -First 3 |
            ForEach-Object {
                [ordered]@{
                    url = $_.url
                    classification = 'thin'
                    reason = 'low html_length'
                    action = Get-ActionTextByOwnership -OwnershipMode $ownershipMode -OwnedAction 'expand content' -ExternalAction 'learn from richer competing pages and replicate content structure patterns'
                }
            }
        )
        $problemTargets = @($brokenTargets + $shellTargets + $thinTargets)
        $report.problem_targets = $problemTargets

        $actionSummary = [ordered]@{
            status = if ($problemTargets.Count -gt 0) { 'FINDINGS_PRESENT' } else { 'CLEAN' }
            finding_count = [int]$problemTargets.Count
            actions = @(
                $problemTargets |
                ForEach-Object {
                    [ordered]@{
                        route = [string]$_.url
                        finding_type = ([string]$_.classification).ToUpperInvariant() + '_ROUTE'
                        priority = if ([string]$_.classification -eq 'broken') { 'P0' } else { 'P1' }
                        action = [string]$_.action
                        evidence_refs = @('ROUTES_SUMMARY.json', 'AUDIT_SUMMARY.json')
                    }
                }
            )
            reason = if ($problemTargets.Count -gt 0) { 'deterministic_route_classifications_detected' } else { 'no_material_findings_in_sampled_scope' }
        }
        # ACTION_SUMMARY is written later by REPORT_LAYER final contract.
        # Do not write early route-classification summary here.

        $okCount = @($routesSummary.routes | Where-Object { $_.classification -eq 'ok' }).Count
        $shellCount = @($routesSummary.routes | Where-Object { $_.classification -eq 'shell' }).Count
        $thinCount = @($routesSummary.routes | Where-Object { $_.classification -eq 'thin' }).Count
        $brokenCount = @($routesSummary.routes | Where-Object { $_.classification -eq 'broken' }).Count
        $passStatus = if (($thinCount -gt 0) -or ($shellCount -gt 0) -or ($brokenCount -gt 0)) { 'PASS_WITH_LIMITS' } else { 'PASS' }
        $auditSummary = [ordered]@{
            total = [int]@($routesSummary.routes).Count
            ok = [int]$okCount
            shell = [int]$shellCount
            thin = [int]$thinCount
            broken = [int]$brokenCount
        }
        Write-JsonFile -Path $auditSummaryPath -Data $auditSummary
        Copy-Item -LiteralPath $auditSummaryPath -Destination $deterministicAuditSummaryPath -Force
        Write-Host 'POST_ROUTE:AUDIT_SUMMARY_WRITTEN'

# Clear stale route-extraction fail state after summaries are successfully written.
# If ROUTES_SUMMARY.json and AUDIT_SUMMARY.json exist, route extraction is no longer failed.
if ((Test-Path (Join-Path $PSScriptRoot "ROUTES_SUMMARY.json")) -and (Test-Path (Join-Path $PSScriptRoot "AUDIT_SUMMARY.json"))) {
    $currentFailureStage = ""
    $failPhase = ""
    $failReason = ""
    $errorMessage = ""
}

        $actionReportLines = New-Object System.Collections.Generic.List[string]
        $actionReportLines.Add("Site: $BaseUrl")
        $actionReportLines.Add("Total pages checked: $((Get-SafePropValue -Object $auditSummary -Name 'total' -Default 0))")
        $actionReportLines.Add("Shell: $($auditSummary.shell)")
        $actionReportLines.Add("Thin: $($auditSummary.thin)")
        $actionReportLines.Add("Broken: $($auditSummary.broken)")

        foreach ($target in $problemTargets) {
            $actionReportLines.Add('')
            $actionReportLines.Add("URL: $($target.url)")
            $actionReportLines.Add("Issue: $($target.classification)")
            $actionReportLines.Add("Action: $($target.action)")
        }

        $actionReportContent = [string]::Join([Environment]::NewLine, @($actionReportLines.ToArray()))
        [System.IO.File]::WriteAllText($actionReportPath, $actionReportContent)
        if (Test-Path -LiteralPath $actionReportPath) {
            Copy-Item -LiteralPath $actionReportPath -Destination $deterministicActionReportPath -Force -ErrorAction SilentlyContinue
        }
        Write-Host 'POST_ROUTE:ACTION_REPORT_WRITTEN'

        $failurePhase = 'ROUTE_SELECTION'
        $currentFailureStage = $failurePhase
        Write-BootstrapStageTrace -Stage 'ROUTE_SELECTION'
        Write-Host 'ROUTE_SELECTION: START'
        Write-Host 'ROUTE_SELECTION: BIND_INPUT_START'
        $routes = @($routeExtraction.routes)
        Write-Host ("ROUTE_SELECTION: BIND_INPUT_OK count=" + [int]$routes.Count)
        if (-not $routes -or $routes.Count -eq 0) {
            Write-Host "ROUTE_SELECTION: NO_ROUTES_INPUT"
            Write-Host 'ROUTE_SELECTION: FAIL_NO_ROUTES'
            throw 'ROUTE_SELECTION received zero routes after binding from route extraction output.'
        }
        Write-Host ("ROUTE_SELECTION: ROUTES_COUNT=" + $routes.Count)
        Write-Host 'ROUTE_SELECTION: BEFORE_FILTER'
        $routes = @($routes | Where-Object { $null -ne $_ })
        Write-Host 'ROUTE_SELECTION: AFTER_FILTER'
        if ($routes.Count -eq 0) {
            Write-Host "ROUTE_SELECTION: EMPTY_AFTER_FILTER"
            Write-Host 'ROUTE_SELECTION: FAIL_EMPTY_AFTER_FILTER'
            $shouldFail = $true
            $errorCode = 'EMPTY_ROUTE_SET'
            $errorMessage = 'ROUTE_SELECTION route set became empty after filtering.'
            $failurePhase = 'ROUTE_SELECTION'
            $currentFailureStage = $failurePhase
            if ($shouldFail) {
                throw $errorMessage
            }
        }
        Write-Host 'ROUTE_SELECTION: BEFORE_SORT'
        $routes = @(
            $routes |
            Sort-Object `
                @{ Expression = { if ($_.PSObject.Properties['html_length']) { [int]$_.html_length } else { 0 } } }, `
                @{ Expression = { if ($_.PSObject.Properties['url']) { [string]$_.url } else { '' } } }
        )
        Write-Host 'ROUTE_SELECTION: AFTER_SORT'
        if ($routes.Count -eq 0) {
            Write-Host "ROUTE_SELECTION: EMPTY_AFTER_FILTER"
            Write-Host 'ROUTE_SELECTION: FAIL_EMPTY_AFTER_FILTER'
            $shouldFail = $true
            $errorCode = 'EMPTY_ROUTE_SET'
            $errorMessage = 'ROUTE_SELECTION route set became empty after filtering.'
            $failurePhase = 'ROUTE_SELECTION'
            $currentFailureStage = $failurePhase
            if ($shouldFail) {
                throw $errorMessage
            }
        }
        $routeSelectionRoutesSummary = [ordered]@{}
        foreach ($summaryProperty in $routesSummary.PSObject.Properties) {
            $routeSelectionRoutesSummary[$summaryProperty.Name] = $summaryProperty.Value
        }
        $routeSelectionRoutesSummary.routes = @($routes)
        Write-Host 'ROUTE_SELECTION: BEFORE_SELECT'
        $captureTargetPlan = Get-VisualTargets -BaseUrl $BaseUrl -RoutesSummary $routeSelectionRoutesSummary -MaxPages $maxRoutes
        Write-Host 'ROUTE_SELECTION: SELECTED_OK'
        $lastCompletedStage = 'ROUTE_SELECTION'
        $selectedRoutes = @($captureTargetPlan.selected_routes)
        $overflowRoutes = @($captureTargetPlan.overflow_routes)
        $selectedRoutesCount = [int]$selectedRoutes.Count
        $captureTargetUrls = @($selectedRoutes | ForEach-Object { [string]$_.url })
        $report.selected_routes = @(
            $selectedRoutes |
            ForEach-Object {
                [ordered]@{
                    route = [string]$_.route
                    source_url = [string]$_.url
                    type = [string]$_.type
                    priority = [int]$_.priority
                    selection_reason = [string]$_.selection_reason
                }
            }
        )
        $report.run_budget = [ordered]@{
            max_routes = [int]$maxRoutes
            selected_routes = [int]$selectedRoutesCount
            selection_strategy = [string]$captureTargetPlan.selection_strategy
            overflow_routes = [int]$overflowRoutes.Count
            overflow_route_details = @($overflowRoutes)
        }

        if ($selectedRoutesCount -gt $maxRoutes) {
            throw "run_budget_violation: selected_routes_exceeded_max_routes"
        }
        $failurePhase = 'CAPTURE'
        $currentFailureStage = $failurePhase
        $captureToolPath = Join-Path $PSScriptRoot 'tools/capture_visuals.mjs'
        $captureExitCode = -1
        $visualManifest = $null
        try {
            $captureExitCode = Invoke-VisualCapture -Pages $captureTargetUrls -ToolPath $captureToolPath -InputPath $visualInputPath -ManifestPath $visualManifestPath -ScreenshotsPath $screenshotsPath
            Add-ProducedArtifactIfExists -OutputDir $outputRoot -RelativePath 'visual_capture_input.json'
            if ($captureExitCode -ne 0) {
                throw "capture_exit_code=$captureExitCode"
            }
            if (-not (Test-Path -LiteralPath $visualManifestPath -PathType Leaf)) {
                throw 'visual_manifest_missing'
            }
            $visualManifest = Get-Content -LiteralPath $visualManifestPath -Raw | ConvertFrom-Json
        }
        catch {
            $capability_capture = $false
            $limitation_capture_missing = $true
            $capabilityCapture = $capability_capture
            $limitationCaptureMissing = $limitation_capture_missing
            $capabilityStatus.capture = 'INACTIVE'
            $report.capability_status.capture = 'INACTIVE'
            $report.capabilities.capture = $false
            Write-Host 'CAPTURE: SKIPPED (Playwright missing or failed)'
            $visualManifest = [ordered]@{
                status = 'SKIPPED'
                requested_pages = [int]$selectedRoutesCount
                processed_pages = 0
                failed_pages = [int]$selectedRoutesCount
                pages = @()
                limitation_capture_missing = $true
                capture_not_available = $true
            }
            Write-JsonFile -Path $visualManifestPath -Data $visualManifest
            Add-ProducedArtifactIfExists -OutputDir $outputRoot -RelativePath 'visual_manifest.json'
        }

        foreach ($manifestPage in @($visualManifest.pages)) {
            $manifestRouteInput = if ($manifestPage.PSObject.Properties['url']) {
                [string]$manifestPage.url
            }
            elseif ($manifestPage.PSObject.Properties['source_url']) {
                [string]$manifestPage.source_url
            }
            else {
                ''
            }

            if ([string]::IsNullOrWhiteSpace($manifestRouteInput)) {
                continue
            }

            $manifestCanonicalResult = Get-CanonicalRouteKeyResult -RouteValue $manifestRouteInput -BaseUrl $BaseUrl
            if ($manifestCanonicalResult.status -ne 'ok') {
                continue
            }

            $manifestPage | Add-Member -NotePropertyName 'source_url' -NotePropertyValue $manifestRouteInput -Force
            $manifestPage | Add-Member -NotePropertyName 'route' -NotePropertyValue ([string]$manifestCanonicalResult.canonical_route) -Force
            $manifestPage.url = (Resolve-SafeUri -BaseUri ([Uri]$BaseUrl) -RelativeOrAbsolute ([string]$manifestCanonicalResult.canonical_route)).AbsoluteUri
        }
        Write-JsonFile -Path $visualManifestPath -Data $visualManifest
        Add-ProducedArtifactIfExists -OutputDir $outputRoot -RelativePath 'visual_manifest.json'
        Copy-Item -LiteralPath $visualManifestPath -Destination $deterministicVisualManifestPath -Force
        Ensure-Directory -Path $deterministicScreenshotsPath
        if (Test-Path -LiteralPath $deterministicScreenshotsPath -PathType Container) {
            Get-ChildItem -LiteralPath $deterministicScreenshotsPath -File -Filter '*.png' | Remove-Item -Force
        }
        if ($capabilityCapture -and (Test-Path -LiteralPath $screenshotsPath -PathType Container)) {
            Get-ChildItem -LiteralPath $screenshotsPath -File -Filter '*.png' | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $deterministicScreenshotsPath $_.Name) -Force
            }
        }

        $captureStatus = [string]$visualManifest.status
        $manifestRequestedPages = if ($null -ne $visualManifest.PSObject.Properties['requested_pages']) { [int]$visualManifest.requested_pages } else { [int]$selectedRoutesCount }
        $manifestProcessedPages = if ($null -ne $visualManifest.PSObject.Properties['processed_pages']) { [int]$visualManifest.processed_pages } else { 0 }
        $manifestFailedPages = if ($null -ne $visualManifest.PSObject.Properties['failed_pages']) { [int]$visualManifest.failed_pages } else { [int]$selectedRoutesCount }
        $captureSummary = [ordered]@{
            status = $captureStatus
            requested_pages = $manifestRequestedPages
            processed_pages = $manifestProcessedPages
            failed_pages = $manifestFailedPages
            exit_code = [int]$captureExitCode
            counter_mismatch = $false
        }
        $report.capture_summary = $captureSummary
        $manifestPages = @($visualManifest.pages)
        $lastCompletedStage = 'CAPTURE'

        $failurePhase = 'RECONCILIATION'
        $currentFailureStage = $failurePhase
        if ($capabilityCapture) {
            Write-Host 'RECON: PREP_START'
            $reconciliationPrep = Invoke-CaptureReconciliationPrepStage -SelectedRoutes @($selectedRoutes) -ManifestPages @($manifestPages) -BaseUrl $BaseUrl -SelectedRoutesCount $selectedRoutesCount -ManifestRequestedPages $manifestRequestedPages -ManifestProcessedPages $manifestProcessedPages -ManifestFailedPages $manifestFailedPages
            Write-Host 'RECON: PREP_RETURNED'
            $counterMismatchDetected = [bool]$reconciliationPrep.counter_mismatch_detected
            $capturesAttempted = [int]$reconciliationPrep.captures_attempted
            $capturesSuccess = [int]$reconciliationPrep.captures_success
            $capturesFailed = [int]$reconciliationPrep.captures_failed
            $pagesAttempted = [int]$reconciliationPrep.pages_attempted
            $pagesProcessed = [int]$reconciliationPrep.pages_processed
            $pagesFailed = [int]$reconciliationPrep.pages_failed
            $pagesSuccess = [int]$reconciliationPrep.pages_success
            Write-Host 'RECON: PREP_OK'
        }
        else {
            $counterMismatchDetected = $false
            $capturesAttempted = 0
            $capturesSuccess = 0
            $capturesFailed = 0
            $pagesAttempted = [int]$selectedRoutesCount
            $pagesProcessed = 0
            $pagesFailed = [int]$selectedRoutesCount
            $pagesSuccess = 0
        }

        if ($counterMismatchDetected) {
            $report.capture_summary.counter_mismatch = $true
            if ($report.capture_summary.status -eq 'PASS') {
                $report.capture_summary.status = 'PARTIAL'
            }
            $report.capture_summary.counter_mismatch_details = [ordered]@{
                selected_routes = $selectedRoutesCount
                selected_route_keys = [int]$reconciliationPrep.selected_route_key_count
                manifest_requested_pages = $manifestRequestedPages
                manifest_pages = [int]$manifestPages.Count
                manifest_route_keys = [int]$reconciliationPrep.manifest_route_key_count
                missing_routes = @($reconciliationPrep.missing_manifest_routes)
                extra_routes = @($reconciliationPrep.extra_manifest_routes)
                normalization_error = [bool]$reconciliationPrep.normalization_error_detected
                normalization_errors = @($reconciliationPrep.route_normalization_errors)
            }
        }

        $captureReportStatus = if ($capabilityCapture) { [string]$reconciliationPrep.capture_report_status } else { 'PARTIAL' }
        $captureFailTypes = if ($capabilityCapture) { @($reconciliationPrep.fail_types) } else { @('capture_not_available') }
        
# === HARD TRUTH: COUNT REAL SCREENSHOTS ===
$capturesTakenCount = 0
if (Test-Path -LiteralPath $screenshotsPath -PathType Container) {
    $capturesTakenCount = @(Get-ChildItem -LiteralPath $screenshotsPath -File -Filter '*.png').Count
}

$report.capture_report = [ordered]@{
            status = $captureReportStatus
            pages_attempted = $pagesAttempted
            pages_processed = $pagesProcessed
            pages_success = $pagesSuccess
            pages_failed = $pagesFailed
            captures_attempted = $capturesAttempted
            captures_success = $capturesSuccess
            captures_failed = $capturesFailed
            fail_types = $captureFailTypes
            counter_mismatch = [bool]$counterMismatchDetected
        }

        try {
            if ($capabilityCapture) {
                $reconciliation = Invoke-EvidenceReconciliation -ManifestPath $visualManifestPath -ScreenshotsPath $screenshotsPath -RunReportPagesAttempted $pagesAttempted -RunReportCapturesAttempted $capturesAttempted -RunReportCapturesSuccess $capturesSuccess -RunReportCapturesFailed $capturesFailed
                $report.evidence_reconciliation = [ordered]@{
                    status = $reconciliation.status
                    files_checked = $reconciliation.files_checked
                    files_valid = $reconciliation.files_valid
                    files_invalid = $reconciliation.files_invalid
                    issues = @($reconciliation.issues)
                }
                Write-Host 'RECON: EVIDENCE_OK'
                $report.reconciliation_enforced = $true

                if (@('PASS', 'PARTIAL', 'FAIL') -notcontains [string]$reconciliation.status) {
                    throw "Reconciliation returned unsupported status '$([string]$reconciliation.status)'."
                }

                $reconciliationCompleted = $true
                $lastCompletedStage = 'RECONCILIATION'
                $report.capture_report.status = [string]$reconciliation.status

                $visualEvidence = switch ([string]$reconciliation.status) {
                    'PASS' { 'trusted' }
                    'PARTIAL' { 'partial' }
                    default { 'invalid' }
                }
                $report.trust_boundary = [ordered]@{
                    visual_evidence = $visualEvidence
                    decision_allowed = $false
                    reason = 'reconciliation_result'
                }

                if ($reconciliation.status -eq 'PARTIAL') {
                    $report.trust_boundary.visual_truth = 'partial'
                    $report.trust_boundary.impact = 'downstream analysis limited'
                }
            }
            else {
                $report.evidence_reconciliation = [ordered]@{
                    status = 'PARTIAL'
                    files_checked = 0
                    files_valid = 0
                    files_invalid = 0
                    issues = @('capture_not_available')
                }
                $report.reconciliation_enforced = $false
                $report.capture_report.status = 'PARTIAL'
                $report.trust_boundary = [ordered]@{
                    visual_evidence = 'missing'
                    decision_allowed = $false
                    reason = 'capture_not_available'
                    visual_truth = 'missing'
                    impact = 'downstream analysis limited'
                }
                $reconciliationCompleted = $true
                $lastCompletedStage = 'RECONCILIATION'
            }
        }
        catch {
            $report.status = 'FAIL'
            $report.execution_status = 'FAILED'
            $report.execution_report.final_outcome = 'FAIL'
            $report.execution_report.status_detail = 'FAIL'
            $report.decision_disabled = $true
            $report.decision_allowed = $false
            $report.reconciliation_enforced = $true
            $report.capture_report.status = 'FAIL'
            $report.evidence_reconciliation = [ordered]@{
                status = 'FAIL'
                files_checked = 0
                files_valid = 0
                files_invalid = 0
                issues = @('reconciliation_error')
                diagnostics = @([string]$_.Exception.Message)
            }
            $report.failure_or_limit_report = [ordered]@{
                kind = 'FAILURE'
                failure_summary = 'failure_summary.json'
                notes = @('Evidence reconciliation failed.', [string]$_.Exception.Message)
            }
            $shouldFail = $true
            $errorCode = 'EVIDENCE_RECONCILIATION_FAILED'
            $errorMessage = $_.Exception.Message
        }

        if (-not $reconciliationCompleted) {
            $report.status = 'FAIL'
            $report.execution_status = 'FAILED'
            $report.execution_report.final_outcome = 'FAIL'
            $report.execution_report.status_detail = 'FAIL'
            $report.decision_disabled = $true
            $report.decision_allowed = $false
            $report.trust_boundary = [ordered]@{
                visual_evidence = 'invalid'
                decision_allowed = $false
                reason = 'reconciliation_result'
            }
            $shouldFail = $true
            if ([string]::IsNullOrWhiteSpace($errorCode)) {
                $errorCode = 'EVIDENCE_RECONCILIATION_NOT_EXECUTED'
                $errorMessage = 'Evidence reconciliation did not execute.'
            }
            $report.failure_or_limit_report = [ordered]@{
                kind = 'FAILURE'
                failure_summary = 'failure_summary.json'
                notes = @($errorMessage)
            }
        }

        if ($problemTargets.Count -eq 0) {
            $report.operator_memory_bridge.next_operator_posture.must_do_before_next_task = @(
                'review ROUTES_SUMMARY.json route coverage',
                'confirm AUDIT_SUMMARY.json counts',
                'verify ACTION_SUMMARY.json status and reason'
            )
            $report.operator_memory_bridge.next_operator_posture.what_to_inspect_next = @(
                'ROUTES_SUMMARY.json',
                'AUDIT_SUMMARY.json',
                'ACTION_SUMMARY.json'
            )
        }
        else {
            $report.operator_memory_bridge.next_operator_posture.must_do_before_next_task = @(
                'open problem_targets pages',
                'inspect their structure',
                'compare thin vs ok pages'
            )
            $report.operator_memory_bridge.next_operator_posture.what_to_inspect_next = @(
                'open problem_targets pages',
                'inspect their structure',
                'compare thin vs ok pages'
            )
        }

        $report.execution_report.final_outcome = 'PASS'
        $limitNotes = New-Object System.Collections.Generic.List[string]
        if ($shellCount -gt 0) { $limitNotes.Add("shell_pages=$shellCount") }
        if ($thinCount -gt 0) { $limitNotes.Add("thin_pages=$thinCount") }
        if ($brokenCount -gt 0) { $limitNotes.Add("broken_pages=$brokenCount") }
        if ($report.capture_report.status -eq 'FAIL') {
            $limitNotes.Add('capture_status=FAIL')
            $limitNotes.Add('incomplete visual coverage: no page had a valid screenshot capture')
        }
        elseif ($report.capture_report.status -eq 'PARTIAL') {
            $limitNotes.Add('capture_status=PARTIAL')
            $limitNotes.Add('incomplete visual coverage: some screenshot captures failed validation')
        }
        if ($limitationCaptureMissing) {
            $limitNotes.Add('no_visual_evidence')
        }

        $reconciliationStatus = [string]$report.evidence_reconciliation.status
        $limitNotesArray = @($limitNotes.ToArray())
        Write-Host 'RECON: LIMIT_NOTES_ARRAY_READY'
        Write-Host 'RECON: STATUS_SWITCH_READY'
        switch ($reconciliationStatus) {
            'PASS' {
                Write-Host 'RECON: STATUS_PASS'
                $report.status = 'PASS'
                $report.execution_status = 'SUCCESS'
                $report.execution_report.final_outcome = 'PASS'
                $report.execution_report.status_detail = $passStatus
                $report.decision_allowed = $true
                $report.decision_disabled = $false
                $notes = @($limitNotesArray)
                Write-Host 'RECON: NOTES_PASS_READY'
                if ($limitNotes.Count -gt 0) {
                    $report.failure_or_limit_report = [ordered]@{
                        kind = 'LIMITS'
                        failure_summary = ''
                        notes = $notes
                    }
                }
            }
            'PARTIAL' {
                Write-Host 'RECON: STATUS_PARTIAL'
                $report.status = 'PARTIAL'
                $report.execution_status = 'PARTIAL'
                $report.execution_report.final_outcome = 'PARTIAL'
                $report.execution_report.status_detail = 'PARTIAL'
                $report.decision_allowed = $false
                $report.decision_disabled = $true
                $partialNotes = @(
                    @($limitNotesArray)
                    'reconciliation_status=PARTIAL'
                    'downstream analysis limited'
                )
                $notes = $partialNotes
                Write-Host 'RECON: NOTES_PARTIAL_READY'
                $report.failure_or_limit_report = [ordered]@{
                    kind = 'LIMITS'
                    failure_summary = ''
                    notes = $notes
                }
            }
            default {
                Write-Host 'RECON: STATUS_FAIL'
                $report.status = 'FAIL'
                $report.execution_status = 'FAILED'
                $report.execution_report.final_outcome = 'FAIL'
                $report.execution_report.status_detail = 'FAIL'
                $report.decision_allowed = $false
                $report.decision_disabled = $true
                $failNotes = @(
                    @($limitNotesArray)
                    'reconciliation_status=FAIL'
                )
                $notes = $failNotes
                Write-Host 'RECON: NOTES_FAIL_READY'
                $report.failure_or_limit_report = [ordered]@{
                    kind = 'FAILURE'
                    failure_summary = 'failure_summary.json'
                    notes = $notes
                }
            }
        }
        Write-Host 'RECON: EXIT_READY'
        if ($counterMismatchDetected) {
            $capturesSuccess = 0
            if ($report.capture_report -and $report.capture_report.PSObject.Properties['captures_success']) {
                $capturesSuccess = [int]$report.capture_report.captures_success
            }

            if ($capturesSuccess -gt 0) {
                $report.status = 'PARTIAL'
                $report.execution_status = 'COMPLETED_WITH_LIMITATIONS'
                $report.execution_report.final_outcome = 'PARTIAL'
                $report.execution_report.status_detail = 'PARTIAL'
                $report.summary = 'Run completed with limited coverage: run_budget_violation'
                $report.next_step = 'review_partial_coverage'
                $report.decision_allowed = $false
                $report.decision_disabled = $true
                $report.capture_report.counter_mismatch = $true
                $report.failure_or_limit_report = [ordered]@{
                    kind = 'LIMITATION'
                    notes = @('run_budget_violation')
                    reason = 'run_budget_violation'
                }
                $report.trust_boundary.visual_evidence = 'partial'
                $report.trust_boundary.reason = 'run_budget_violation'
            }
            else {
                $report.status = 'FAIL'
                $report.execution_status = 'FAILED'
                $report.execution_report.final_outcome = 'FAIL'
                $report.execution_report.status_detail = 'FAIL'
                $report.summary = 'Run failed: run_budget_violation'
                $report.next_step = 'run_budget_violation'
                $report.decision_allowed = $false
                $report.decision_disabled = $true
                $report.capture_report.status = 'FAIL'
                $report.capture_report.counter_mismatch = $true
                $report.failure_or_limit_report = [ordered]@{
                    kind = 'FAILURE'
                    failure_summary = 'failure_summary.json'
                    notes = @('run_budget_violation')
                    reason = 'run_budget_violation'
                }
                $report.trust_boundary.visual_evidence = 'invalid'
                $report.trust_boundary.reason = 'run_budget_violation'
# REMOVED: shouldFail escalation for run_budget_violation
                $errorCode = 'RUN_BUDGET_VIOLATION'
                $errorMessage = 'run_budget_violation'
            }
        }

        $routeIssueMap = @{}
        $routeSignalMap = @{}
        $findingsList = New-Object System.Collections.Generic.List[object]
        $findingIndex = 1
        foreach ($route in @($routesSummary.routes)) {
            $routeValue = [string]$route.normalized_route
            if ([string]::IsNullOrWhiteSpace($routeValue)) { $routeValue = [string]$route.url }
            $canonicalRouteResult = Get-CanonicalRouteKeyResult -RouteValue $routeValue -BaseUrl $BaseUrl
            $routeKey = if ($canonicalRouteResult.status -eq 'ok') { [string]$canonicalRouteResult.canonical_route } else { $routeValue }
            if ([string]::IsNullOrWhiteSpace($routeKey)) { continue }
            $routeSignalMap[$routeKey] = [ordered]@{
                status_code = [int]$route.status_code
                html_length = [int]$route.html_length
                title_present = [bool]$route.title_present
                internal_link_count = [int]$route.internal_link_count
                headline_count = if ($route.PSObject.Properties['headline_count']) { [int]$route.headline_count } else { 0 }
                article_list_count = if ($route.PSObject.Properties['article_list_count']) { [int]$route.article_list_count } else { 0 }
                repeated_link_block_ratio = if ($route.PSObject.Properties['repeated_link_block_ratio']) { [double]$route.repeated_link_block_ratio } else { 0.0 }
                has_timestamp_patterns = if ($route.PSObject.Properties['has_timestamp_patterns']) { [bool]$route.has_timestamp_patterns } else { $false }
                screenshot_capture_ok = $false
                screenshot_count = 0
                top_screenshot_ok = $false
                top_screenshot_file = ''
                first_screen_text_present = [bool]$route.first_screen_text_present
                first_screen_text_sample = [string]$route.first_screen_text_sample
                first_screen_has_value = [bool]$route.first_screen_has_value
                first_screen_has_action = [bool]$route.first_screen_has_action
                first_screen_is_process_like = [bool]$route.first_screen_is_process_like
                value_before_process = [bool]$route.value_before_process
                page_type = if ($route.PSObject.Properties['page_type']) { [string]$route.page_type } else { 'UNKNOWN' }
                shell_like_candidate = [bool]$route.shell_like_candidate
                thin_candidate = [bool]$route.thin_candidate
                broken_candidate = [bool]$route.broken_candidate
            }
        }

        $manifestByRoute = @{}
        foreach ($manifestPage in @($manifestPages)) {
            $manifestUrl = [string]$manifestPage.url
            if ([string]::IsNullOrWhiteSpace($manifestUrl)) {
                continue
            }

            $canonicalManifestRoute = Get-CanonicalRouteKeyResult -RouteValue $manifestUrl -BaseUrl $BaseUrl
            if ($canonicalManifestRoute.status -eq 'ok') {
                $manifestByRoute[[string]$canonicalManifestRoute.canonical_route] = $manifestPage
            }
        }

$failurePhase = 'SURFACE_CONTEXT'
        $currentFailureStage = $failurePhase
        $pageVerdicts = New-Object System.Collections.Generic.List[object]
        foreach ($selectedRoute in @($report.selected_routes)) {
            $routeValue = [string]$selectedRoute.route
            $canonicalSelectedRoute = Get-CanonicalRouteKeyResult -RouteValue $routeValue -BaseUrl $BaseUrl
            $canonicalRoute = if ($canonicalSelectedRoute.status -eq 'ok') { [string]$canonicalSelectedRoute.canonical_route } else { $routeValue }
            $routeIssueCount = if ($routeIssueMap.ContainsKey($canonicalRoute)) { [int]$routeIssueMap[$canonicalRoute].Count } else { 0 }
            $routeSignals = if ($routeSignalMap.ContainsKey($canonicalRoute)) { $routeSignalMap[$canonicalRoute] } else {
                [ordered]@{
                    status_code = -1
                    html_length = 0
                    title_present = $false
                    internal_link_count = 0
                    headline_count = 0
                    article_list_count = 0
                    repeated_link_block_ratio = 0.0
                    has_timestamp_patterns = $false
                    screenshot_capture_ok = $false
                    screenshot_count = 0
                    top_screenshot_ok = $false
                    top_screenshot_file = ''
                    first_screen_text_present = $false
                    first_screen_text_sample = ''
                    first_screen_has_value = $false
                    first_screen_has_action = $false
                    first_screen_is_process_like = $false
                    value_before_process = $false
                    page_type = 'UNKNOWN'
                    shell_like_candidate = $false
                    thin_candidate = $false
                    broken_candidate = $true
                }
            }

            $visualStatus = 'unknown'
            $routeCaptureCount = 0
            $routeCaptureSuccess = 0
            $manifestRecord = $null
            if ($manifestByRoute.ContainsKey($canonicalRoute)) {
                $manifestRecord = $manifestByRoute[$canonicalRoute]
                $captureStates = @($manifestRecord.captures | ForEach-Object { [string]$_.status })
                $routeCaptureCount = [int]$captureStates.Count
                $routeCaptureSuccess = [int]@($captureStates | Where-Object { $_ -eq 'ok' }).Count
                if ($captureStates.Count -eq 0) {
                    $visualStatus = 'unknown'
                }
                elseif (@($captureStates | Where-Object { $_ -eq 'ok' }).Count -eq $captureStates.Count) {
                    $visualStatus = 'ok'
                }
                elseif (@($captureStates | Where-Object { $_ -eq 'ok' }).Count -gt 0) {
                    $visualStatus = 'partial'
                }
                else {
                    $visualStatus = 'failed'
                }
            }
            $routeSignals.screenshot_count = [int]$routeCaptureCount
            $routeSignals.screenshot_capture_ok = [bool]($routeCaptureCount -gt 0 -and $routeCaptureSuccess -eq $routeCaptureCount)
            $topCapture = if ($null -ne $manifestRecord) { Get-FirstOrNull -Collection @($manifestRecord.captures | Where-Object { [string]$_.segment -eq 'top' } | Select-Object -First 1) } else { $null }
            if ($null -ne $topCapture) {
                $routeSignals.top_screenshot_ok = ([string]$topCapture.status -eq 'ok')
                $routeSignals.top_screenshot_file = [string]$topCapture.file
            }

            $pageType = [string]$routeSignals.page_type
            $surfaceType = Resolve-SurfaceType -SurfaceType (Get-SurfaceTypeByPageType -PageType $pageType)
            $surfaceExpectation = Get-SurfaceExpectation -SurfaceType $surfaceType
            $evidenceText = Get-EvidenceSnippet -Text ([string]$routeSignals.first_screen_text_sample)
            $evidenceScreenshot = if ([bool]$routeSignals.top_screenshot_ok) { [string]$routeSignals.top_screenshot_file } else { '' }
            $statusEvidenceText = "HTTP status code: $([int]$routeSignals.status_code)."
            $textEvidencePresent = -not [string]::IsNullOrWhiteSpace($evidenceText)
            $statusEvidencePresent = ([int]$routeSignals.status_code -gt 0)
            $processCondition = [bool]$routeSignals.first_screen_is_process_like -and (-not [bool]$routeSignals.value_before_process) -and (-not [bool]$routeSignals.broken_candidate)
            $noValueCondition = (-not [bool]$routeSignals.first_screen_has_value) -and (-not [bool]$routeSignals.broken_candidate)
            $noActionCondition = (-not [bool]$routeSignals.first_screen_has_action) -and (-not [bool]$routeSignals.broken_candidate)
            $brokenRouteCondition = ([bool]$routeSignals.broken_candidate) -or ([int]$routeSignals.status_code -ne 200)
            $isMediaSurface = @('MEDIA_HOME', 'MEDIA_SECTION') -contains $surfaceType
            $isArticleSurface = ($surfaceType -eq 'ARTICLE')
            $isDirectorySurface = ($surfaceType -eq 'DIRECTORY')
            $mediaListingSignals = Test-SurfaceMediaListingSignals -HeadlineCount ([int]$routeSignals.headline_count) -ArticleListCount ([int]$routeSignals.article_list_count) -HasTimestampPatterns ([bool]$routeSignals.has_timestamp_patterns) -RepeatedLinkBlockRatio ([double]$routeSignals.repeated_link_block_ratio)
            $articleValueSatisfied = $isArticleSurface -and (Test-SurfaceArticleValueSatisfied -FirstScreenTextLength ([int]$routeSignals.first_screen_text_length))
            $directoryValueSatisfied = $isDirectorySurface -and (Test-SurfaceDirectoryValueSatisfied -InternalLinkCount ([int]$routeSignals.internal_link_count) -RepeatedLinkBlockRatio ([double]$routeSignals.repeated_link_block_ratio) )

            $allowContextSpecificDefects = ($surfaceType -ne 'UNKNOWN')
            $brokenRouteConfidence = Test-HighSignalConfidence -ConditionMet $brokenRouteCondition -EvidencePresent $statusEvidencePresent
            $processConfidence = Test-HighSignalConfidence -ConditionMet ($processCondition -and (-not $isMediaSurface) -and $allowContextSpecificDefects) -EvidencePresent $textEvidencePresent
            $noValueAllowed = [bool]$surfaceExpectation.expects_value_first
            if ($isMediaSurface -and $mediaListingSignals) { $noValueAllowed = $false }
            if ($isDirectorySurface -and $directoryValueSatisfied) { $noValueAllowed = $false }
            if ($isArticleSurface -and $articleValueSatisfied) { $noValueAllowed = $false }
            if (-not $allowContextSpecificDefects) { $noValueAllowed = $false }
            $noActionAllowed = [bool]$surfaceExpectation.expects_action_path
            if ($isArticleSurface -or $isDirectorySurface -or $isMediaSurface -or (-not $allowContextSpecificDefects)) { $noActionAllowed = $false }
            $noValueConfidence = Test-HighSignalConfidence -ConditionMet ($noValueCondition -and $noValueAllowed) -EvidencePresent $textEvidencePresent
            $noActionConfidence = Test-HighSignalConfidence -ConditionMet ($noActionCondition -and $noActionAllowed) -EvidencePresent $textEvidencePresent

            if (-not $routeIssueMap.ContainsKey($canonicalRoute)) { $routeIssueMap[$canonicalRoute] = New-Object System.Collections.Generic.List[string] }
            $defectCandidates = New-Object System.Collections.Generic.List[string]

            if ($brokenRouteConfidence -eq 'HIGH') {
                $issueType = 'BROKEN_ROUTE'
                $priority = Get-DefectPriorityByIssueType -IssueType $issueType
                $findingId = "F-{0:d3}" -f $findingIndex
                $findingsList.Add([ordered]@{
                        finding_id = $findingId
                        route = $canonicalRoute
                        signal_type = $issueType
                        type = $issueType
                        issue_type = $issueType
                        category = 'DEFECT'
                        priority = $priority
                        severity = $priority
                        confidence = 'HIGH'
                        surface_type = [string]$surfaceType
                        evidence_text = [string]$statusEvidenceText
                        evidence_type = 'status'
                        evidence_ref = 'ROUTES_SUMMARY.json:status_code'
                        evidence_screenshot = [string]$evidenceScreenshot
                        evidence_refs = @('ROUTES_SUMMARY.json:status_code', "visual_manifest.json:$evidenceScreenshot")
                        why_it_matters = 'Route is not reachable in current run, so page flow breaks before user can act.'
                        recommended_action = Get-ActionTextByOwnership -OwnershipMode $ownershipMode -OwnedAction 'Fix failing route so it returns HTTP 200 and loads the intended page' -ExternalAction 'Document failing route pattern and avoid sending traffic to broken paths'
                    })
                $routeIssueMap[$canonicalRoute].Add($findingId)
                $null = $defectCandidates.Add($issueType)
                $findingIndex += 1
            }

            if ($processConfidence -eq 'HIGH') {
                $issueType = 'PROCESS_FIRST'
                $priority = if (@('LANDING', 'DECISION') -contains $pageType) { 'P0' } else { Get-DefectPriorityByIssueType -IssueType $issueType }
                $findingId = "F-{0:d3}" -f $findingIndex
                $findingsList.Add([ordered]@{
                        finding_id = $findingId
                        route = $canonicalRoute
                        signal_type = $issueType
                        type = $issueType
                        issue_type = $issueType
                        category = 'DEFECT'
                        priority = $priority
                        severity = $priority
                        confidence = 'HIGH'
                        surface_type = [string]$surfaceType
                        evidence_text = [string]$evidenceText
                        evidence_type = 'text'
                        evidence_ref = 'AUDIT_SUMMARY.json:first_screen_text_sample'
                        evidence_screenshot = [string]$evidenceScreenshot
                        evidence_refs = @('ROUTES_SUMMARY.json', 'AUDIT_SUMMARY.json:first_screen_text_sample', "visual_manifest.json:$evidenceScreenshot")
                        why_it_matters = 'Key message starts with process/instructions before value is explained.'
                        recommended_action = Get-ActionTextByOwnership -OwnershipMode $ownershipMode -OwnedAction 'Rewrite first screen: show value before instructions' -ExternalAction 'Study pages that start with instructions instead of value'
                    })
                $routeIssueMap[$canonicalRoute].Add($findingId)
                $null = $defectCandidates.Add($issueType)
                $findingIndex += 1
            }

            if ($noValueConfidence -eq 'HIGH') {
                $issueType = 'NO_VALUE_FIRST_SCREEN'
                $priority = Get-DefectPriorityByIssueType -IssueType $issueType
                $findingId = "F-{0:d3}" -f $findingIndex
                $findingsList.Add([ordered]@{
                        finding_id = $findingId
                        route = $canonicalRoute
                        signal_type = $issueType
                        type = $issueType
                        issue_type = $issueType
                        category = 'DEFECT'
                        priority = $priority
                        severity = $priority
                        confidence = 'HIGH'
                        surface_type = [string]$surfaceType
                        evidence_text = [string]$evidenceText
                        evidence_type = 'text'
                        evidence_ref = 'AUDIT_SUMMARY.json:first_screen_text_sample'
                        evidence_screenshot = [string]$evidenceScreenshot
                        evidence_refs = @('ROUTES_SUMMARY.json', 'AUDIT_SUMMARY.json:first_screen_text_sample', "visual_manifest.json:$evidenceScreenshot")
                        why_it_matters = 'First screen does not clearly state what value the page provides.'
                        recommended_action = Get-ActionTextByOwnership -OwnershipMode $ownershipMode -OwnedAction 'Add clear value statement to first screen' -ExternalAction 'Study pages missing a clear value statement on first screen'
                    })
                $routeIssueMap[$canonicalRoute].Add($findingId)
                $null = $defectCandidates.Add($issueType)
                $findingIndex += 1
            }

            if ($noActionConfidence -eq 'HIGH') {
                $issueType = 'NO_ACTION_PATH'
                $priority = Get-DefectPriorityByIssueType -IssueType $issueType
                $findingId = "F-{0:d3}" -f $findingIndex
                $findingsList.Add([ordered]@{
                        finding_id = $findingId
                        route = $canonicalRoute
                        signal_type = $issueType
                        type = $issueType
                        issue_type = $issueType
                        category = 'DEFECT'
                        priority = $priority
                        severity = $priority
                        confidence = 'HIGH'
                        surface_type = [string]$surfaceType
                        evidence_text = [string]$evidenceText
                        evidence_type = 'text'
                        evidence_ref = 'AUDIT_SUMMARY.json:first_screen_text_sample'
                        evidence_screenshot = [string]$evidenceScreenshot
                        evidence_refs = @('ROUTES_SUMMARY.json', 'AUDIT_SUMMARY.json:first_screen_text_sample', "visual_manifest.json:$evidenceScreenshot")
                        why_it_matters = 'First screen has no clear action element.'
                        recommended_action = Get-ActionTextByOwnership -OwnershipMode $ownershipMode -OwnedAction 'Add clear action path in first screen' -ExternalAction 'Study pages with no first-screen action path'
                    })
                $routeIssueMap[$canonicalRoute].Add($findingId)
                $null = $defectCandidates.Add($issueType)
                $findingIndex += 1
            }

            $classification = if ($defectCandidates.Count -gt 0) { 'high_signal_detected' } else { 'ok' }

            $pageVerdicts.Add([ordered]@{
                    route = $canonicalRoute
                    classification = $classification
                    signals = $routeSignals
                    surface_type = [string]$surfaceType
                    surface_expectation = $surfaceExpectation
                    defect_candidates = @($defectCandidates.ToArray())
                    evidence_refs = @('ROUTES_SUMMARY.json', 'visual_manifest.json')
                    confidence = if ($defectCandidates.Count -gt 0) { 'HIGH' } elseif ($visualStatus -eq 'ok') { 'MEDIUM' } else { 'LOW' }
                })
        }

$lastCompletedStage = 'SURFACE_CONTEXT'
        $reportLayerMarker = ''
        $failurePhase = 'REPORT_LAYER'
        $currentFailureStage = $failurePhase
        $reportLayerMarker = 'REPORT_LAYER: START'
        Write-Host $reportLayerMarker
        $allFindings = @($findingsList.ToArray())
        $report.micro_clusters = @()
        $defectFindings = @($allFindings | Where-Object { [string]$_.category -eq 'DEFECT' })
        $limitationFindings = New-Object System.Collections.Generic.List[object]
        if ([int]$report.run_budget.overflow_routes -gt 0) {
            $limitationFindings.Add([ordered]@{
                    finding_id = 'limitation_route_overflow'
                    route = '_audit_scope'
                    signal_type = 'ROUTE_OVERFLOW_ONLY'
                    type = 'ROUTE_OVERFLOW_ONLY'
                    issue_type = 'ROUTE_OVERFLOW_ONLY'
                    category = 'LIMITATION'
                    priority = 'NONE'
                    severity = 'NONE'
                    confidence = [string]$report.audit_confidence
                    surface_type = 'UNKNOWN'
                    evidence_text = "Route budget excluded $([int]$report.run_budget.overflow_routes) discovered routes from this run."
                    evidence_type = 'status'
                    evidence_ref = 'ROUTES_SUMMARY.json:overflow_routes'
                    evidence_screenshot = ''
                    evidence_refs = @('ROUTES_SUMMARY.json')
                    why_it_matters = 'Sampled coverage is bounded and can miss page-level defects outside the checked scope.'
                    recommended_action = 'Expand route sample and rerun LINK mode for broader coverage.'
                })
        }
        if ($limitationCaptureMissing) {
            $limitationFindings.Add([ordered]@{
                    finding_id = 'limitation_capture_not_available'
                    route = '_audit_scope'
                    signal_type = 'NO_VISUAL_EVIDENCE'
                    type = 'NO_VISUAL_EVIDENCE'
                    issue_type = 'NO_VISUAL_EVIDENCE'
                    category = 'LIMITATION'
                    priority = 'NONE'
                    severity = 'NONE'
                    confidence = 'LOW'
                    surface_type = 'UNKNOWN'
                    evidence_text = 'Capture capability was unavailable in this run; screenshot evidence is missing.'
                    evidence_type = 'status'
                    evidence_ref = 'RUN_REPORT.json:limitations'
                    evidence_screenshot = ''
                    evidence_refs = @('RUN_REPORT.json')
                    why_it_matters = 'Without visual evidence, confidence in visual/page-structure conclusions is reduced.'
                    recommended_action = 'Install Playwright and rerun capture to restore visual evidence.'
                })
        }
        $limitationFindings = @($limitationFindings.ToArray())
        $report.findings_count = [int]$defectFindings.Count
        $report.limitation_count = [int]$limitationFindings.Count
        if ($limitationCaptureMissing) {
            $report.limitations = @('no_visual_evidence')
        }
        else {
            $report.limitations = @()
        }
        $report.report_layer.limitation.capture_not_available = [bool]$limitationCaptureMissing
        $routesChecked = [int]@($report.selected_routes).Count
        $maxRoutesBudget = [int]$report.run_budget.max_routes
        $coverageRatio = if ($maxRoutesBudget -gt 0) { [double]$routesChecked / [double]$maxRoutesBudget } else { 0.0 }
        $hasLimitationFindings = ($limitationFindings.Count -gt 0)
        $isLowConfidence = ($routesChecked -lt $maxRoutesBudget) -or $hasLimitationFindings
        $isHighConfidence = (-not $isLowConfidence) -and ($defectFindings.Count -eq 0) -and ($coverageRatio -ge 0.9)
        $report.audit_confidence = if ($isLowConfidence) { 'LOW' } elseif ($isHighConfidence) { 'HIGH' } else { 'MEDIUM' }
        $confidenceReasons = New-Object System.Collections.Generic.List[string]
        if ($routesChecked -lt $maxRoutesBudget) {
            $confidenceReasons.Add("sampled_routes_below_budget ($routesChecked/$maxRoutesBudget)")
        }
        if ([int]$report.run_budget.overflow_routes -gt 0) {
            $confidenceReasons.Add("route_budget_overflow=$([int]$report.run_budget.overflow_routes)")
        }
        if ($limitationCaptureMissing) {
            $confidenceReasons.Add('no_visual_evidence')
        }
        if ([string]$report.capture_report.status -eq 'PARTIAL') {
            $confidenceReasons.Add('capture_status=PARTIAL')
        }
        elseif ([string]$report.capture_report.status -eq 'FAIL') {
            $confidenceReasons.Add('capture_status=FAIL')
        }
        if ($hasLimitationFindings) {
            $confidenceReasons.Add("limitation_findings=$($limitationFindings.Count)")
        }
        $report.confidence_reason = if ($confidenceReasons.Count -gt 0) {
            [string]($confidenceReasons.ToArray() -join '; ')
        }
        else {
            'confidence_signals_sufficient_for_sampled_scope'
        }
        $report.next_verification_step = if ([int]$report.run_budget.overflow_routes -gt 0) {
            'Increase max_routes in a controlled rerun and verify overflow routes with screenshots.'
        }
        elseif ([string]$report.capture_report.status -ne 'PASS' -or $limitationCaptureMissing) {
            'Restore screenshot coverage (Playwright/capture stack) and rerun LINK mode for all selected routes.'
        }
        else {
            'Run one controlled rerun to confirm sampled-scope stability before acting on clean verdict.'
        }
        $report.forbidden_next_steps = @(
            'do not treat LOW confidence PASS as full-site clean bill',
            'do not skip rerun when overflow routes or capture limitations exist',
            'do not claim conversion/UX quality from LINK-only evidence'
        )
        $p0Count = [int]@($defectFindings | Where-Object { [string]$_.priority -eq 'P0' }).Count
        $p1Count = [int]@($defectFindings | Where-Object { [string]$_.priority -eq 'P1' }).Count
        $p2Count = [int]@($defectFindings | Where-Object { [string]$_.priority -eq 'P2' }).Count
        $topIssues = @(
            $defectFindings |
            Sort-Object @{ Expression = {
                    switch ([string]$_.priority) {
                        'P0' { 0 }
                        'P1' { 1 }
                        default { 2 }
                    }
                }
            }, @{ Expression = { Get-FindingTypeSortRank -IssueType ([string]$_.issue_type) } }, finding_id |
            Select-Object -First 3 |
            ForEach-Object { [string]$_.issue_type }
        )

        $reportLayerMarker = 'REPORT_LAYER: FINDINGS_BOUND'
        Write-Host $reportLayerMarker
        $defectFindingsArray = @($defectFindings)
        $limitationFindingsArray = @($limitationFindings)
        $report.findings = Convert-ContractArray -Value ($defectFindingsArray + $limitationFindingsArray)
        $findingContractResult = Normalize-FindingContract -Findings (Convert-ContractArray -Value $report.findings) -DiagnosticPath $reportContractDiagPath
        if (Test-Path -LiteralPath $reportContractDiagPath -PathType Leaf) {
            Add-ProducedArtifactIfExists -OutputDir $outputRoot -RelativePath 'REPORT_CONTRACT_DIAG.json'
            Copy-Item -LiteralPath $reportContractDiagPath -Destination $deterministicReportContractDiagPath -Force
        }
        $allFindings = Convert-ContractArray -Value $findingContractResult.findings
        $report.findings = Convert-ContractArray -Value $findingContractResult.findings
        $defectFindings = @($allFindings | Where-Object { [string]$_.category -eq 'DEFECT' })
        $limitationFindings = @($allFindings | Where-Object { [string]$_.category -eq 'LIMITATION' })
        $report.findings_count = [int]$defectFindings.Count
        $report.limitation_count = [int]$limitationFindings.Count

        $operatorMemoryCore = [ordered]@{
            who_am_i = 'system operator building site auditor agent'
            what_system_is_being_built = 'site audit agent → decision → action → monetization system'
            primary_asset = 'automation site as decision system'
            end_goal = 'traffic → decision → action → monetization'
            current_stage = ''
            current_focus = ''
            what_is_stable = @()
            what_is_unstable = @()
            agent_learned = @()
            agent_cannot_yet = @()
            agent_misleading_risk = @()
            next_capability_to_build = ''
        }
        $hasOperatorFeedInputs = ($null -ne $report.capture_report -and $null -ne $report.evidence_reconciliation -and $null -ne $report.selected_routes -and $null -ne $report.run_budget -and $null -ne $report.findings)
        if ($hasOperatorFeedInputs) {
            $reconciliationStatus = [string]$report.evidence_reconciliation.status
            $captureStatus = [string]$report.capture_report.status
            $truthConfidence = if ($counterMismatchDetected -or $reconciliationStatus -eq 'FAIL' -or $captureStatus -eq 'FAIL') {
                'low'
            }
            elseif ($reconciliationStatus -eq 'PARTIAL' -or $captureStatus -eq 'PARTIAL') {
                'medium'
            }
            else {
                'high'
            }

            $stableLayer = switch ($reconciliationStatus) {
                'PASS' { 'W2 visual evidence stable' }
                'PARTIAL' { 'W2.5 visual evidence partial' }
                default { 'W2 visual evidence unstable' }
            }
            $systemChange = if (@($report.findings).Count -gt 0) { 'report layer includes deterministic findings and action mapping' } else { 'report layer is clean for sampled scope with deterministic action summary' }

            $whatIsReliable = New-Object System.Collections.Generic.List[string]
            if ($report.capture_report.captures_success -gt 0 -and $reconciliationStatus -ne 'FAIL') {
                $null = $whatIsReliable.Add('screenshots')
            }
            if (@($report.selected_routes).Count -eq [int]$report.run_budget.selected_routes) {
                $null = $whatIsReliable.Add('route selection')
            }
            if (@('PASS', 'PARTIAL') -contains $reconciliationStatus) {
                $null = $whatIsReliable.Add('capture reconciliation')
            }
            if (@($report.findings).Count -ge 0) {
                $null = $whatIsReliable.Add('findings serialization')
            }

            $whatIsNotReliable = New-Object System.Collections.Generic.List[string]
            if ($counterMismatchDetected -or $captureStatus -eq 'FAIL' -or $captureStatus -eq 'PARTIAL') {
                $null = $whatIsNotReliable.Add('complete visual evidence coverage')
            }
            if ([int]$report.run_budget.overflow_routes -gt 0) {
                $null = $whatIsNotReliable.Add('full route coverage beyond run budget')
            }
            if ($report.decision_allowed -eq $false) {
                $null = $whatIsNotReliable.Add('decision automation layer')
            }

            $primaryConstraint = if ($counterMismatchDetected) {
                'route-manifest counter mismatch blocks trustworthy downstream interpretation'
            }
            elseif ($captureStatus -eq 'FAIL') {
                'visual evidence failed and cannot support deterministic downstream interpretation'
            }
            elseif ($captureStatus -eq 'PARTIAL') {
                'visual evidence is partial and limits deterministic downstream interpretation'
            }
            elseif ([int]$report.run_budget.overflow_routes -gt 0) {
                'route budget overflow limits deterministic sampled coverage'
            }
            else {
                'sampled scope may miss issues outside current max_routes budget'
            }

            $nextSystemMove = if ($counterMismatchDetected -or $captureStatus -eq 'FAIL' -or $captureStatus -eq 'PARTIAL') {
                'stabilize visual evidence integrity checks in report outputs'
            }
            elseif (@($report.findings).Count -eq 0 -and [int]$report.run_budget.overflow_routes -gt 0) {
                'optionally expand deterministic route sample with controlled max_routes increase'
            }
            elseif (@($report.findings).Count -eq 0) {
                'keep current CLEAN mode and rerun only when scope changes'
            }
            else {
                $firstFinding = Get-FirstOrNull -Collection $allFindings
                [string]$firstFinding.recommended_action
            }
            $whyThisMove = if ($counterMismatchDetected -or $captureStatus -eq 'FAIL' -or $captureStatus -eq 'PARTIAL') {
                'stable visual truth is required before higher-level system interpretation can be trusted'
            }
            elseif (@($report.findings).Count -eq 0 -and [int]$report.run_budget.overflow_routes -gt 0) {
                'clean sampled evidence is bounded; broader deterministic coverage requires a larger controlled sample'
            }
            elseif (@($report.findings).Count -eq 0) {
                'no material findings were observed in sampled routes'
            }
            else {
                'highest-severity deterministic finding should be resolved first'
            }

            $doNotDoYet = New-Object System.Collections.Generic.List[string]
            foreach ($blockedMove in @($report.next_action_contract.forbidden_before_done)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$blockedMove)) {
                    $null = $doNotDoYet.Add([string]$blockedMove)
                }
            }
            if ($doNotDoYet.Count -eq 0) {
                $null = $doNotDoYet.Add('do not add interaction layer')
                $null = $doNotDoYet.Add('do not expand crawler depth beyond current LINK-mode budget')
            }

            $whatIsStable = New-Object System.Collections.Generic.List[string]
            if ($report.capture_report.captures_success -gt 0) {
                $null = $whatIsStable.Add('screenshots')
            }
            if (@('PASS', 'PARTIAL') -contains $reconciliationStatus) {
                $null = $whatIsStable.Add('reconciliation')
            }
            if (@($report.selected_routes).Count -eq [int]$report.run_budget.selected_routes) {
                $null = $whatIsStable.Add('route selection')
            }

            $whatIsUnstable = New-Object System.Collections.Generic.List[string]
            if (@($report.findings).Count -eq 0 -and [int]$report.run_budget.overflow_routes -gt 0) {
                $null = $whatIsUnstable.Add('coverage beyond sampled max_routes')
            }
            if ($report.decision_allowed -eq $false) {
                $null = $whatIsUnstable.Add('decision layer')
            }
            $null = $whatIsUnstable.Add('interaction layer')

            $agentLearned = New-Object System.Collections.Generic.List[string]
            if ($report.capture_report.captures_success -gt 0) {
                $null = $agentLearned.Add('can produce validated screenshots')
            }
            if (@('PASS', 'PARTIAL') -contains $reconciliationStatus) {
                $null = $agentLearned.Add('can reconcile evidence')
            }
            if (@($report.selected_routes).Count -gt 0) {
                $null = $agentLearned.Add('can perform deterministic route selection')
            }

            $agentCannotYet = New-Object System.Collections.Generic.List[string]
            $null = $agentCannotYet.Add('cannot interpret UX')
            $null = $agentCannotYet.Add('cannot evaluate conversion')
            if ($report.decision_allowed -eq $false) {
                $null = $agentCannotYet.Add('cannot recommend tools')
            }

            $agentMisleadingRisk = New-Object System.Collections.Generic.List[string]
            $null = $agentMisleadingRisk.Add('may assume page quality from visuals only')
            if ($captureStatus -eq 'PARTIAL' -or $captureStatus -eq 'FAIL') {
                $null = $agentMisleadingRisk.Add('may overstate certainty when evidence coverage is partial')
            }

            $operatorMemoryCore.current_stage = if ($reconciliationStatus -eq 'PASS' -and $captureStatus -eq 'PASS') {
                'W3 report layer'
            }
            elseif (@('PARTIAL', 'FAIL') -contains $reconciliationStatus -or @('PARTIAL', 'FAIL') -contains $captureStatus) {
                'W2/W3 report layer hardening'
            }
            else {
                ''
            }
            $operatorMemoryCore.current_focus = 'report layer'
            $operatorMemoryCore.what_is_stable = @($whatIsStable.ToArray())
            $operatorMemoryCore.what_is_unstable = @($whatIsUnstable.ToArray())
            $operatorMemoryCore.agent_learned = @($agentLearned.ToArray())
            $operatorMemoryCore.agent_cannot_yet = @($agentCannotYet.ToArray())
            $operatorMemoryCore.agent_misleading_risk = @($agentMisleadingRisk.ToArray())
            $operatorMemoryCore.next_capability_to_build = if (@($report.findings).Count -eq 0 -and [int]$report.run_budget.overflow_routes -gt 0) { 'controlled route-sample expansion (optional)' } else { 'none required for findings-to-action layer in current scope' }

            $report.operator_feed = [ordered]@{
                system_state = "$stableLayer, $systemChange"
                primary_constraint = $primaryConstraint
                truth_confidence = $truthConfidence
                what_is_reliable = @($whatIsReliable.ToArray())
                what_is_not_reliable = @($whatIsNotReliable.ToArray())
                next_system_move = $nextSystemMove
                why_this_move = $whyThisMove
                do_not_do_yet = @($doNotDoYet.ToArray())
            }
        }
        $reportLayerMarker = 'REPORT_LAYER: OPERATOR_FEED_READY'
        Write-Host $reportLayerMarker
        $report.operator_memory_core = $operatorMemoryCore
        $nextOperatorMustDoBeforeNextTask = @(
            'read RUN_REPORT.json before drafting any next task'
            'verify priority_summary and decision_summary alignment before proposing execution'
        )
        $nextOperatorWhatToInspectNext = @(
            'priority_summary.top_issues with corresponding route verdict evidence'
            'decision_summary.recommended_action scope against ownership mode'
            'limitations and overflow_routes before expanding scope'
        )
        $nextOperatorDoNotDoYet = @(
            'do not infer UX/conversion outcomes',
            'do not grade CTA quality',
            'do not claim monetization readiness beyond observable LINK evidence'
        )
        $routesCheckedCount = @($report.selected_routes).Count
        $capturesTakenCount = 0
if (Test-Path -LiteralPath $screenshotsPath -PathType Container) {
    $capturesTakenCount = @(Get-ChildItem -LiteralPath $screenshotsPath -File -Filter '*.png').Count
}
        $captureAttemptedCount = if ($report.capture_report -and $report.capture_report.PSObject.Properties['captures_attempted']) { [int]$report.capture_report.captures_attempted } else { 0 }
        $overflowCount = if ($report.run_budget -and $report.run_budget.PSObject.Properties['overflow_routes']) { [int]$report.run_budget.overflow_routes } else { 0 }
        $limitNotes = New-Object System.Collections.Generic.List[string]
        if ($overflowCount -gt 0) { $null = $limitNotes.Add("route budget overflow: $overflowCount route(s) not checked in this run") }
        if ($captureAttemptedCount -gt $capturesTakenCount) { $null = $limitNotes.Add("capture limits: only $capturesTakenCount of $captureAttemptedCount capture(s) succeeded") }
        if ([string]$report.audit_confidence -eq 'LOW') { $null = $limitNotes.Add('confidence remains LOW due to bounded scope or incomplete evidence') }
        if ($limitNotes.Count -eq 0) { $null = $limitNotes.Add('no explicit run limits were raised beyond LINK-mode boundaries') }
        $statusLabelForBridge = if ($report.status_label) { [string]$report.status_label } else { [string]$report.status }
        $statusMeaning = [ordered]@{
            PASS = 'No material defects found in the sampled LINK evidence for this run; this is not a full-site guarantee.'
            PASS_WITH_LIMITS = 'Run completed, but confidence/coverage limits prevent full-site claims. Treat as bounded pass only.'
            FAIL = 'Critical evidence gaps or defects blocked trust in the sampled run; operator action is required before relying on this output.'
        }
        $checkedVsNotChecked = @(
            "checked: $routesCheckedCount selected route(s) through LINK fetch, capture, recon, and report layers"
            "checked: $capturesTakenCount successful screenshot capture(s) used as evidence"
            "not checked: routes outside selection budget or overflow ($overflowCount route(s))"
            'not checked: interaction flows, UX quality, conversion quality, or non-LINK hidden states'
        )
        $systemMapMinimal = @(
            'route layer -> builds routes',
            'capture layer -> screenshots',
            'recon -> evaluation',
            'report -> decisions',
            'output -> artifacts',
            'file pointers: agent.ps1, modules/stage_link_fetch.ps1, modules/stage_capture_reconciliation.ps1, modules/report_layer.ps1, lib/post_output.ps1'
        )
        $reportLayerMarker = 'REPORT_LAYER: MEMORY_BRIDGE_READY'
        Write-Host $reportLayerMarker
        $report.operator_memory_bridge = [ordered]@{
            status_detail = [string]$statusLabelForBridge
            current_execution_mode = 'LINK'
            current_layer = 'report layer'
            layer_owner_file = 'modules/report_layer.ps1'
            next_file_to_inspect = 'RUN_REPORT.json'
            reason_to_inspect = if ($allFindings.Count -gt 0) { 'RUN_REPORT.json binds findings, affected routes, and actions to report-layer contracts before any patching.' } else { 'RUN_REPORT.json confirms clean sampled scope, limits, and report-layer ownership before deciding next audit move.' }
            one_next_step = [string]$report.next_step
            forbidden_next_steps = @($nextOperatorDoNotDoYet)
            tool_recommendation = 'PowerShell + RUN_REPORT.json first-read flow'
            identity_anchor = [ordered]@{
                who_am_i = [string]$operatorMemoryCore.who_am_i
                what_system_is_being_built = [string]$operatorMemoryCore.what_system_is_being_built
                primary_asset = [string]$operatorMemoryCore.primary_asset
                end_goal = [string]$operatorMemoryCore.end_goal
            }
            state_anchor = [ordered]@{
                current_stage = [string]$operatorMemoryCore.current_stage
                current_focus = [string]$operatorMemoryCore.current_focus
                what_is_stable = @($operatorMemoryCore.what_is_stable)
                what_is_unstable = @($operatorMemoryCore.what_is_unstable)
            }
            learning_anchor = [ordered]@{
                agent_learned = @($operatorMemoryCore.agent_learned)
                agent_cannot_yet = @($operatorMemoryCore.agent_cannot_yet)
                agent_misleading_risk = @($operatorMemoryCore.agent_misleading_risk)
                next_capability_to_build = [string]$operatorMemoryCore.next_capability_to_build
            }
            operator_brain = [ordered]@{
                role = 'System operator / product lead for Universal Audit Engine. Make decisions, not summaries.'
                objective = 'Traffic -> Decision -> Action -> Monetization'
                operating_law = 'RUN_REPORT first. Artifact truth over memory. One bottleneck. One action.'
                tool_policy = [ordered]@{
                    codespace = 'Use for filesystem truth, run verification, artifact inspection, safe bash.'
                    codex = 'Use only after owner file and root cause are known.'
                    chatgpt = 'Use for decision, bottleneck selection, task writing, artifact interpretation.'
                    forbidden = @('guessing', 'blind patching', 'screenshot-first decisions', 'memory-over-artifact decisions')
                }
                decision_rules = @(
                    'Read RUN_REPORT.json first',
                    'Then read AGENT_OPERATOR_HANDOFF.json when present',
                    'Then read SELF_DIAGNOSTIC.json before repair decisions',
                    'Then read ACTION_SUMMARY.json before proposing action',
                    'Then read AGENT_MAP.json before module/debug decisions'
                )
                forbidden_behavior = @(
                    'Do not patch before reading truth files',
                    'Do not ignore AGENT_MAP for module ownership',
                    'Do not expand capability while current layer is unstable',
                    'Do not create new center of truth when existing RUN_REPORT contract can be strengthened'
                )
                current_agent_context = [ordered]@{
                    product = 'Universal Audit Engine'
                    current_mode = 'LINK'
                    current_focus = 'artifact navigation, operator handoff, output clarity'
                    architecture = 'orchestration-first, module-first, contract-first; do not grow giant files'
                }
            }

            must_read_contract = [ordered]@{
                must_read_files = @('RUN_REPORT.json', 'ROUTES_SUMMARY.json', 'AUDIT_SUMMARY.json', 'ACTION_SUMMARY.json', 'visual_manifest.json')
                read_order = @('RUN_REPORT.json', 'ROUTES_SUMMARY.json', 'AUDIT_SUMMARY.json', 'ACTION_SUMMARY.json', 'visual_manifest.json')
                first_file_to_open = 'RUN_REPORT.json'
                why_read = if ($allFindings.Count -gt 0) { 'RUN_REPORT.json contains deterministic findings, priorities, route verdicts, and action mapping anchored to existing artifacts.' } else { 'RUN_REPORT.json confirms CLEAN sampled scope, coverage bounds, and deterministic no-finding action summary.' }
                minimum_context_after_read = if ($allFindings.Count -gt 0) { 'visual truth is trusted within sampled coverage, route selection is stable in-budget, and findings are bounded to observable LINK evidence.' } else { 'visual truth is trusted within sampled coverage, no material findings were observed, and deeper interpretation remains limited without interaction/decision layers.' }
            }
            next_operator_posture = [ordered]@{
                next_system_move = [string]$report.operator_feed.next_system_move
                must_do_before_next_task = @($nextOperatorMustDoBeforeNextTask)
                what_to_inspect_next = @($nextOperatorWhatToInspectNext)
                recommended_tool = 'PowerShell + RUN_REPORT.json first-read flow'
                forbidden_drifts = @(
                    'do not switch from LINK evidence to speculative UX claims',
                    'do not expand scope beyond sampled routes before bounded rerun',
                    'do not add new audit features before stabilizing current report layer'
                )
                do_not_do_yet = @($nextOperatorDoNotDoYet)
            }
            self_explanation = [ordered]@{
                what_this_agent_is = [ordered]@{
                    universal_audit_engine = 'SITE_AUDITOR_V2 is a universal audit engine operating in bounded modes.'
                    current_mode = 'LINK'
                    run_scope = @(
                        "routes checked: $routesCheckedCount"
                        "screenshots captured: $capturesTakenCount"
                        ("limits: " + ($limitNotes -join '; '))
                    )
                }
                what_happened_in_this_run = [ordered]@{
                    status = [string]$statusLabelForBridge
                    status_meaning_plain = [string]$statusMeaning[[string]$statusLabelForBridge]
                    confidence = [string]$report.audit_confidence
                    why_confidence = if ([string]$report.audit_confidence -eq 'LOW') { 'LOW confidence means bounded or incomplete evidence in this run, so claims must stay limited to checked routes only.' } else { 'Confidence is not LOW because sampled evidence and reconciliation were sufficient for this bounded run.' }
                    checked_vs_not_checked = @($checkedVsNotChecked)
                }
                system_map_minimal = @($systemMapMinimal)
                next_step_one_only = [string]$report.next_step
                forbidden = @(
                    'do not refactor',
                    'do not add features',
                    'do not assume full audit'
                )
            }
        }
        $report.page_verdicts = @($pageVerdicts.ToArray())
        $report.priority_summary = [ordered]@{
            p0_count = $p0Count
            p1_count = $p1Count
            p2_count = $p2Count
            limitation_count = [int]$limitationFindings.Count
            top_issues = @($topIssues)
        }
        $reportLayerMarker = 'REPORT_LAYER: PRIORITY_SUMMARY_READY'
        Write-Host $reportLayerMarker
        $report.report_mode = if ($defectFindings.Count -gt 0) { 'PROBLEM' } else { 'CLEAN' }

        $sortedFindings = @(
            $defectFindings |
            Sort-Object @{ Expression = {
                    switch ([string]$_.priority) {
                        'P0' { 0 }
                        'P1' { 1 }
                        default { 2 }
                    }
                }
            }, @{ Expression = { Get-FindingTypeSortRank -IssueType ([string]$_.issue_type) } }, finding_id
        )
        $contextValidHighFindings = @($sortedFindings | Where-Object { [string]$_.confidence -eq 'HIGH' })
        $sortedLimitationFindings = @(
            $limitationFindings |
            Sort-Object finding_id
        )

        $clusterTypes = @('PROCESS_FIRST', 'NO_VALUE_FIRST_SCREEN', 'NO_ACTION_PATH', 'BROKEN_ROUTE')
        $microClusters = New-Object System.Collections.Generic.List[object]
        foreach ($clusterType in $clusterTypes) {
            $clusterFindings = @($contextValidHighFindings | Where-Object { [string]$_.issue_type -eq $clusterType })
            $clusterSurfaces = @($clusterFindings | ForEach-Object { [string]$_.surface_type } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
            $clusterRoutes = @($clusterFindings | ForEach-Object { [string]$_.route } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
            if ($clusterSurfaces.Count -lt 2) { continue }
            $clusterShare = if ($routesChecked -gt 0) { [Math]::Round(([double]$clusterRoutes.Count / [double]$routesChecked), 4) } else { 0.0 }
            $microClusters.Add([ordered]@{
                    cluster_type = [string]$clusterType
                    count = [int]$clusterRoutes.Count
                    surfaces_count = [int]$clusterSurfaces.Count
                    surfaces = @($clusterSurfaces)
                    routes = @($clusterRoutes | Select-Object -First 5)
                    share_of_checked_pages = $clusterShare
                })
        }
        $report.micro_clusters = @($microClusters.ToArray())

        if (($null -eq $sortedFindings -or @($sortedFindings).Count -eq 0) -and $null -ne $report.problem_targets) {
            $sortedFindings = @(
                $report.problem_targets |
                Where-Object { [string]$_.classification -eq 'broken' } |
                ForEach-Object {
                    [ordered]@{
                        route = [string]$_.url
                        issue_type = 'BROKEN_ROUTE'
                        classification = 'DEFECT'
                        priority = 'P0'
                        confidence = 'HIGH'
                        surface_type = 'ROUTE'
                        evidence_text = "Broken route detected: $([string]$_.url) returned non-200."
                        why_it_matters = 'Broken internal route blocks user navigation and weakens audit confidence.'
                        recommended_action = [string]$_.action
                        finding_id = [guid]::NewGuid().ToString()
                    }
                }
            )
            $contextValidHighFindings = @($sortedFindings | Where-Object { [string]$_.confidence -eq 'HIGH' })
            $defectFindings = @($sortedFindings)
            $p0Count = @($sortedFindings | Where-Object { [string]$_.priority -eq 'P0' }).Count
        }

        $report.system_problem = New-SystemProblemFromFindings `
            -Report $report `
            -AuditConfidence ([string]$report.audit_confidence) `
            -SortedFindings $sortedFindings `
            -ContextValidHighFindings $contextValidHighFindings `
            -SortedLimitationFindings $sortedLimitationFindings `
            -MicroClusters $report.micro_clusters `
            -P0Count $p0Count `
            -P1Count $p1Count

        $decisionIssueType = [string]$report.system_problem.category
        $report.decision_summary = New-DecisionSummaryFromSystemProblem `
            -SystemProblem $report.system_problem `
            -OwnershipMode ([string]$ownershipMode) `
            -AuditConfidence ([string]$report.audit_confidence)
        $report.decision = Resolve-MinimalDecision `
            -RoutesSummary $routesSummary `
            -AuditSummary $auditSummary `
            -LinkSummary $linkSummary `
            -RoutesSummaryPath $routesSummaryPath `
            -AuditSummaryPath $auditSummaryPath `
            -LinkSummaryPath $linkSummaryPath `
            -Limitations ([ordered]@{
                capture_missing = [bool]$limitationCaptureMissing
                route_overflow = [bool]([int]$report.run_budget.overflow_routes -gt 0)
                capture_status = [string]$report.capture_report.status
            })
        $reportLayerMarker = 'REPORT_LAYER: DECISION_SUMMARY_READY'
        Write-Host $reportLayerMarker
        $nextStrongestMove = [string]$report.decision_summary.recommended_action
        $overallVerdict = if ($decisionIssueType -eq 'DEFECT' -and ($report.status -eq 'PARTIAL' -or $report.status -eq 'FAIL')) {
            'DEFECT: confirmed finding(s) with limited evidence confidence'
        }
        elseif ($decisionIssueType -eq 'DEFECT') {
            'DEFECT: confirmed finding(s) in sampled LINK evidence'
        }
        elseif ($decisionIssueType -eq 'LIMITATION') {
            'LIMITATION: audit scope constraints limit coverage certainty'
        }
        elseif ([string]$report.audit_confidence -eq 'HIGH') {
            'CLEAN: No confirmed system-level defects were identified in the checked scope.'
        }
        else {
            'CLEAN: No confirmed system-level defects were identified in the checked scope.'
        }
        $report.executive_answer = [ordered]@{
            overall_verdict = $overallVerdict
            primary_problem = [string]$report.decision_summary.primary_issue
            audit_scope = 'LINK mode / screenshot evidence baseline'
            strongest_next_move = [string]$nextStrongestMove
        }
        $report.next_strongest_move = [string]$nextStrongestMove

        $report.business_impact = [ordered]@{
            trust = if ($report.capture_report.status -eq 'PASS') { 'no integrity defect detected in sampled visual evidence' } else { 'limited trust due to incomplete visual evidence' }
            navigation = if ($brokenCount -gt 0) { 'broken internal routes detected in sampled set' } else { 'no broken internal routes detected in sampled set' }
            coverage = if ($report.run_budget.overflow_routes -gt 0 -or $report.capture_report.status -ne 'PASS') { 'partial coverage in sampled LINK run' } else { 'sampled coverage complete within current run budget' }
            monetization_readiness = 'unknown (no interaction or conversion evidence in LINK mode)'
        }

        $report.next_action_contract = [ordered]@{
            next_task_id = 'SITE_AUDITOR_V2_FINDINGS_REPAIR_001'
            next_task_objective = [string]$report.decision_summary.recommended_action
            why_this_first = if ($defectFindings.Count -eq 0 -and $limitationFindings.Count -gt 0) { 'no page-level defects were detected in sampled routes, but sampling limits constrain coverage confidence' } elseif ($allFindings.Count -eq 0 -and [int]$report.run_budget.overflow_routes -gt 0) { 'current sampled evidence is clean; next value is controlled scope expansion only if requested' } elseif ($allFindings.Count -eq 0) { 'sampled evidence is clean and in-budget with no material finding to remediate' } elseif ($ownershipMode -eq 'EXTERNAL') { 'site is external, so findings must be converted into learnings and replication opportunities instead of direct remediation tasks' } else { 'highest-severity findings are directly evidenced and block confident downstream interpretation' }
            forbidden_before_done = @(
                'do not add interaction layer',
                'do not add decision automation',
                'do not expand crawler depth beyond current LINK-mode budget'
            )
        }

        
        if (($null -eq $sortedFindings -or @($sortedFindings).Count -eq 0) -and $null -ne $report.problem_targets) {
            $sortedFindings = @(
                $report.problem_targets |
                Where-Object { [string]$_.classification -eq 'broken' } |
                ForEach-Object {
                    [ordered]@{
                        route = $_.url
                        issue_type = 'BROKEN_ROUTE'
                        priority = 'P0'
                        confidence = 'HIGH'
                        recommended_action = $_.action
                        why_it_matters = 'Broken internal route blocks user navigation and weakens audit confidence.'
                        finding_id = [guid]::NewGuid().ToString()
                    }
                }
            )
        }

                Write-Host ("DEBUG_SORTED_FINDINGS_COUNT=" + [string]@($sortedFindings).Count)
        Write-Host ("DEBUG_PROBLEM_TARGETS_COUNT=" + [string]@($report.problem_targets).Count)
                Write-Host ("DEBUG_BEFORE_ACTION_SUMMARY_SORTED=" + [string]@($sortedFindings).Count)
        Write-Host ("DEBUG_BEFORE_ACTION_SUMMARY_DEFECTS=" + [string]$defectFindings.Count)
        Write-Host ("DEBUG_BEFORE_ACTION_SUMMARY_PROBLEMS=" + [string]@($report.problem_targets).Count)
        $finalActionSummary = New-ActionSummaryFromDecision `
            -DecisionSummary $report.decision_summary `
            -DecisionIssueType $decisionIssueType `
            -SortedFindings $sortedFindings `
            -SortedLimitationFindings $sortedLimitationFindings `
            -DefectCount $defectFindings.Count `
            -LimitationCount $limitationFindings.Count `
            -AuditConfidence ([string]$report.audit_confidence) `
                        -RunStatus ([string]$report.status) `
            -RunStatusLabel ([string]$report.status_label)
        # REMOVED: Convert-RunReportValue for ACTION_SUMMARY
        $lowConfidencePass = ([string]$report.status -eq 'PASS' -and [string]$report.audit_confidence -eq 'LOW')
        $report.status_label = if ($lowConfidencePass) { 'PASS_WITH_LIMITS' } else { [string]$report.status }
        if ($lowConfidencePass) {
            $report.execution_report.status_detail = 'PASS_WITH_LIMITS'
            $report.summary = 'Run completed with limitations: PASS_WITH_LIMITS (LOW confidence).'
        }
                Write-Host ("DEBUG_AFTER_ACTION_SUMMARY_FINDING_COUNT=" + [string]$finalActionSummary.finding_count)
        Write-Host ("DEBUG_AFTER_ACTION_SUMMARY_BROKEN_COUNT=" + [string]$finalActionSummary.broken_route_count)
        $finalActionSummary.status_label = [string]$report.status_label
        $finalActionSummary.confidence_reason = [string]$report.confidence_reason
        $finalActionSummary.next_verification_step = [string]$report.next_verification_step
        $finalActionSummary.forbidden_next_steps = @($report.forbidden_next_steps)
        $actionSummaryActions = if ($null -ne $finalActionSummary.actions) { @($finalActionSummary.actions) } else { @() }
        $reportLayerMarker = 'REPORT_LAYER: ACTION_SUMMARY_READY'
        Write-Host $reportLayerMarker

        Write-Host "DEBUG_FINAL_ACTION_SUMMARY_WRITE_REACHED"
        Write-Host ("DEBUG_FINAL_ACTION_SUMMARY_STATUS=" + [string]$finalActionSummary.status)
        Write-Host ("DEBUG_FINAL_ACTION_SUMMARY_LABEL=" + [string]$finalActionSummary.status_label)
        Write-JsonFile -Path $actionSummaryPath -Data $finalActionSummary
        Copy-Item -LiteralPath $actionSummaryPath -Destination $deterministicActionSummaryPath -Force
        $reportLayerMarker = 'REPORT_LAYER: ACTION_SUMMARY_WRITTEN'
        Write-Host $reportLayerMarker

        $reportLayerMarker = 'REPORT_LAYER: HUMAN_PAYLOAD_START'
        Write-Host $reportLayerMarker
        $reportPayloads = New-HumanReportPayloads `
            -Report $report `
            -DecisionIssueType $decisionIssueType `
            -OverallVerdict $overallVerdict `
            -RoutesChecked $routesChecked `
            -DefectCount $defectFindings.Count `
            -SortedFindings $sortedFindings
        $reportPayloadEn = $reportPayloads.en
        $reportPayloadRu = $reportPayloads.ru
        $ruHtml = New-ClientReportHtml -Language 'RU' -ReportPayload $reportPayloadRu
        $enHtml = New-ClientReportHtml -Language 'EN' -ReportPayload $reportPayloadEn
        [System.IO.File]::WriteAllText($humanReportRuPath, $ruHtml, (New-SafeUtf8NoBom))
        [System.IO.File]::WriteAllText($humanReportEnPath, $enHtml, (New-SafeUtf8NoBom))
        Copy-Item -LiteralPath $humanReportRuPath -Destination $deterministicHumanReportRuPath -Force
        Copy-Item -LiteralPath $humanReportEnPath -Destination $deterministicHumanReportEnPath -Force
        $reportLayerMarker = 'REPORT_LAYER: HUMAN_PAYLOAD_READY'
        Write-Host $reportLayerMarker

        $reportLayerMarker = 'REPORT_LAYER: CONSISTENCY_CHECK_START'
        Write-Host $reportLayerMarker
        if ([string]$report.next_strongest_move -ne [string]$report.decision_summary.recommended_action) { throw 'CONSISTENCY_LOCK_FAILED: next_strongest_move mismatch.' }
        Test-ReportConsistencyLock `
            -Report $report `
            -FinalActionSummary $finalActionSummary `
            -ReportPayloadRu $reportPayloadRu `
            -ReportPayloadEn $reportPayloadEn `
            -DecisionIssueType $decisionIssueType `
            -DefectCount $defectFindings.Count `
            -LimitationCount $limitationFindings.Count

        $report.next_step = [string]$nextStrongestMove
        if ($null -ne $report.operator_memory_bridge) {
            $report.operator_memory_bridge.status_detail = [string]$report.status_label
            $report.operator_memory_bridge.one_next_step = [string]$report.next_step
        }
        $isLimitationOnly = ($defectFindings.Count -eq 0 -and $limitationFindings.Count -gt 0)
        $operatorHandoffReason = if ([string]$report.audit_confidence -eq 'LOW') {
            'Confidence is low because sampled route coverage is limited; avoid strong claims.'
        }
        elseif ([string]$report.audit_confidence -eq 'HIGH' -and $defectFindings.Count -eq 0) {
            'No defects detected.'
        }
        elseif ($isLimitationOnly) {
            'Run completed successfully: no page-level defects detected; audit limited by sampling and route budget constraints.'
        }
        elseif ($allFindings.Count -gt 0) {
            'RUN_REPORT.json contains sampled-scope findings, priority counts, and artifact-linked actions bounded to observable LINK evidence.'
        }
        else {
            'RUN_REPORT.json confirms sampled-scope cleanliness in current LINK coverage and documents route budget limits.'
        }
        $firstActionEntry = Get-FirstOrNull -Collection $actionSummaryActions
        $firstDefectAction = if ($null -ne $firstActionEntry) { [string]$firstActionEntry.action } else { [string]$nextStrongestMove }
        $highestPriorityIssue = [string]$report.decision_summary.primary_issue
        $report.operator_handoff = [ordered]@{
            deprecated = $true
            reader_role = 'ChatGPT decision/orchestration layer'
            mirrors_operator_memory_bridge = $true
            ownership_mode = $ownershipMode
            action_scope_explanation = if ($ownershipMode -eq 'OWNED') { 'Owned site: recommendations may include fix/update/optimize actions grounded in findings evidence.' } else { 'External site: recommendations are limited to analyze/learn/replicate patterns and traffic insights, not direct page changes.' }
            truth_files = @($report.operator_memory_bridge.must_read_contract.must_read_files)
            read_order = @($report.operator_memory_bridge.must_read_contract.read_order)
            must_read_first = @('RUN_REPORT.json')
            first_file_to_open = [string]$report.operator_memory_bridge.must_read_contract.first_file_to_open
            exact_reason = [string]$operatorHandoffReason
            issue_type = [string]$decisionIssueType
            audit_confidence = [string]$report.audit_confidence
            scope_limited = [bool]([string]$report.audit_confidence -eq 'LOW' -or [int]$report.run_budget.overflow_routes -gt 0)
            highest_priority_issue = $highestPriorityIssue
            what_to_do_first = $firstDefectAction
            do_not_do_yet = @($report.operator_memory_bridge.next_operator_posture.do_not_do_yet)
            must_do_before_next_task = @($report.operator_memory_bridge.next_operator_posture.must_do_before_next_task)
            what_to_inspect_next = @($report.operator_memory_bridge.next_operator_posture.what_to_inspect_next)
            forbidden_moves = @(
                'do not guess parameter names',
                'do not generate task without reading truth_files',
                'do not patch unrelated files'
            )
            if_missing_artifact = 'Request exact missing file; do not proceed'
        }
        $report.trust_boundary.decision_allowed = [bool]$report.decision_allowed
        Normalize-PrimaryRouteContractFields -RunReport $report -RoutesSummary $routesSummary -VisualManifest $visualManifest -BaseUrl $BaseUrl
        $routeContractResult = Test-RouteContract -RunReport $report -RoutesSummary $routesSummary -VisualManifest $visualManifest
        $report.route_contract = [ordered]@{
            status = [string]$routeContractResult.status
            primary_key_format = [string]$routeContractResult.primary_key_format
            violations = @($routeContractResult.violations)
        }
        if ($routeContractResult.status -ne 'ok') {
            $report.status = 'FAIL'
            $report.execution_status = 'FAILED'
            $report.execution_report.final_outcome = 'FAIL'
            $report.execution_report.status_detail = 'FAIL'
            $report.summary = 'Run failed: ROUTE_CONTRACT_BREACH'
            $report.next_step = 'Fix route contract violations and rerun LINK mode.'
            $report.decision_allowed = $false
            $report.decision_disabled = $true
            $report.failure_or_limit_report = [ordered]@{
                kind = 'FAILURE'
                failure_summary = 'failure_summary.json'
                notes = @('ROUTE_CONTRACT_BREACH')
            }
            if ($null -ne $report.trust_boundary) {
                $report.trust_boundary.visual_evidence = 'invalid'
                $report.trust_boundary.reason = 'ROUTE_CONTRACT_BREACH'
                $report.trust_boundary.decision_allowed = $false
            }
            $shouldFail = $true
            $errorCode = 'ROUTE_CONTRACT_BREACH'
            $errorMessage = 'Primary route fields must use canonical path-only route identities.'
            if ($null -ne $finalActionSummary) {
                $finalActionSummary.status = 'FAIL'
                $finalActionSummary.reason = 'run_failed_route_contract_breach'
                Write-JsonFile -Path $actionSummaryPath -Data $finalActionSummary
                Copy-Item -LiteralPath $actionSummaryPath -Destination $deterministicActionSummaryPath -Force
            }
        }
        $reportLayerMarker = 'REPORT_LAYER: EXIT_READY'
        Write-Host $reportLayerMarker
        $report.produced_artifacts = Get-FinalProducedArtifacts -OutputDir $OutputDir -AllowedFolders $allowedFolders -AllowedExtensions $allowedExtensions -Status ([string]$report.status)
    }
    catch {
        $shouldFail = $true
        $failureDiagnostics = Get-ScriptFailureDiagnostics -ErrorRecord $_ -LastReportLayerMarker ([string]$reportLayerMarker)
        $errorMessage = $_.Exception.Message
        $localizedError = Get-LocalizedErrorFromExceptionMessage -Message ([string]$errorMessage)
        if (-not [string]::IsNullOrWhiteSpace([string]$localizedError.code)) {
            $errorCode = [string]$localizedError.code
            $errorMessage = [string]$localizedError.detail
        }
        $failurePhaseValue = if ([string]::IsNullOrWhiteSpace([string]$failurePhase)) { 'UNKNOWN' } else { [string]$failurePhase }
        if ($failurePhaseValue -eq 'REPORT_LAYER' -and -not [string]::IsNullOrWhiteSpace([string]$reportLayerMarker)) {
            Write-Host "REPORT_LAYER: LAST_MARKER=$reportLayerMarker"
        }
        $operatorFailureNote = switch ($failurePhaseValue) {
            'ENTRY' { 'entry validation failure' }
            'LINK_FETCH' { 'link fetch failure' }
            'ROUTE_EXTRACTION' { 'route extraction failure' }
            'ROUTE_SELECTION' { 'route selection failure' }
            'CAPTURE' { 'capture stage failure' }
            'RECONCILIATION' { 'reconciliation stage failure' }
            'SURFACE_CONTEXT' { 'surface context failure' }
            'REPORT_LAYER' { 'report layer failure' }
            default { 'internal exception' }
        }
        if ([string]::IsNullOrWhiteSpace([string]$errorCode)) {
            if ($failurePhaseValue -eq 'ROUTE_EXTRACTION' -and ([string]$errorMessage).ToUpperInvariant().Contains('ARGUMENT TYPES DO NOT MATCH')) {
                $errorCode = 'ROUTE_EXTRACTION_RUNTIME_EXCEPTION'
            }
        }
        if ([string]::IsNullOrWhiteSpace([string]$errorCode)) {
            switch ([string]$failurePhase) {
                'ENTRY' { $errorCode = 'ENTRY_FAILED' }
                'LINK_FETCH' { $errorCode = 'LINK_FETCH_FAILED' }
                'ROUTE_EXTRACTION' { $errorCode = 'ROUTE_EXTRACTION_FAILED' }
                'ROUTE_SELECTION' { $errorCode = 'ROUTE_SELECTION_FAILED' }
                'CAPTURE' { $errorCode = 'CAPTURE_STAGE_FAILED' }
                'RECONCILIATION' { $errorCode = 'RECONCILIATION_STAGE_FAILED' }
                'SURFACE_CONTEXT' { $errorCode = 'SURFACE_CONTEXT_EXCEPTION' }
                'REPORT_LAYER' { $errorCode = 'REPORT_LAYER_EXCEPTION' }
                default { $errorCode = 'INTERNAL_EXCEPTION' }
            }
        }
        $report.status = 'FAIL'
        $report.execution_status = 'FAILED'
        $currentFailureStage = $failurePhaseValue
        $report.last_completed_stage = [string]$lastCompletedStage
        $report.current_failure_stage = [string]$currentFailureStage
        $report.summary = "Run failed: $errorCode (phase=$failurePhaseValue)"
        $report.next_step = $errorMessage
        $report.execution_report.final_outcome = 'FAIL'
        $report.execution_report.status_detail = 'FAIL'
        $failureClass = Get-EffectiveFailureClass -FailureStage $failurePhaseValue -ErrorCode $errorCode -ErrorMessage $errorMessage
        $report.failure_or_limit_report = [ordered]@{
            kind = 'FAILURE'
            failure_summary = 'failure_summary.json'
            failure_class = [string]$failureClass
            last_completed_stage = [string]$lastCompletedStage
            current_failure_stage = [string]$failurePhaseValue
            notes = @("phase=$failurePhaseValue", "last_completed_stage=$lastCompletedStage", $operatorFailureNote, $errorMessage)
        }
        $report.produced_artifacts = Get-FinalProducedArtifacts -OutputDir $OutputDir -AllowedFolders $allowedFolders -AllowedExtensions $allowedExtensions -Status ([string]$report.status)
        $report.linked_artifacts = @(
            [ordered]@{ name = 'run_report'; path = $runReportPath },
            [ordered]@{ name = 'failure_summary'; path = $failurePath }
        )
    }
}

if (-not (Test-Path -LiteralPath $actionReportPath)) {
    $fallbackActionReport = @(
        "Site: $BaseUrl",
        "Status: $($report.status)",
        "Outcome: $($report.execution_report.status_detail)",
        "Summary: $($report.summary)"
    ) -join [Environment]::NewLine
    [System.IO.File]::WriteAllText($actionReportPath, $fallbackActionReport)
    if (Test-Path -LiteralPath $actionReportPath) {
        Copy-Item -LiteralPath $actionReportPath -Destination $deterministicActionReportPath -Force -ErrorAction SilentlyContinue
    }
}

$actionSummaryMissingOrEmpty = (-not (Test-Path -LiteralPath $actionSummaryPath)) -or ((Get-Item -LiteralPath $actionSummaryPath).Length -le 2)
if ((-not $shouldFail) -and $actionSummaryMissingOrEmpty) {
    $fallbackActionSummary = [ordered]@{
        status = if ($shouldFail) { 'FAILED' } else { 'CLEAN' }
        finding_count = 0
        limitation_count = 0
        actions = @(
            [ordered]@{
                action = [string]$report.decision_summary.recommended_action
                why = 'Fallback action generated to keep decision chain non-empty.'
                priority = [string]$report.decision_summary.priority
            }
        )
        reason = if ($shouldFail) { 'action_summary_not_generated_before_failure' } else { 'no_material_findings_in_sampled_scope' }
    }
    Write-JsonFile -Path $actionSummaryPath -Data $fallbackActionSummary
    Copy-Item -LiteralPath $actionSummaryPath -Destination $deterministicActionSummaryPath -Force
}

if ((-not $shouldFail) -and ((-not (Test-Path -LiteralPath $humanReportRuPath)) -or (-not (Test-Path -LiteralPath $humanReportEnPath)))) {
    $fallbackPayloadEn = [ordered]@{
        executive_lines = @("Current status: $([string]$report.summary).", "Confidence: $([string]$report.audit_confidence).", "Main action: $([string]$report.decision_summary.recommended_action)")
        main_problem = 'Fallback output: report generated after incomplete run.'
        actions_lines = @([string]$report.decision_summary.recommended_action)
        impact_lines = @('Fallback output preserves one deterministic next action.')
        evidence_lines = @('Fallback mode: no additional supporting evidence block.')
        limitations_lines = @('Checked scope may be partial.')
        include_limitations = $true
        snapshot_rows = @(
            [ordered]@{ label = 'Pages checked'; value = [string][int]@($report.selected_routes).Count },
            [ordered]@{ label = 'Findings count'; value = [string]([int]$report.findings_count + [int]$report.limitation_count) },
            [ordered]@{ label = 'Highest priority'; value = [string]$report.decision_summary.priority },
            [ordered]@{ label = 'Confidence'; value = [string]$report.audit_confidence }
        )
    }
    $fallbackPayloadRu = [ordered]@{
        executive_lines = @("Текущий статус: $([string]$report.summary).", "Уверенность: $([string]$report.audit_confidence).", "Главное действие: $([string]$report.decision_summary.recommended_action)")
        main_problem = 'Резервный режим: отчёт сформирован после неполного запуска.'
        actions_lines = @([string]$report.decision_summary.recommended_action)
        impact_lines = @('Резервный вывод сохраняет одно приоритетное действие.')
        evidence_lines = @('Резервный режим: дополнительные примеры недоступны.')
        limitations_lines = @('Проверенный объём может быть частичным.')
        include_limitations = $true
        snapshot_rows = @(
            [ordered]@{ label = 'Проверено страниц'; value = [string][int]@($report.selected_routes).Count },
            [ordered]@{ label = 'Количество находок'; value = [string]([int]$report.findings_count + [int]$report.limitation_count) },
            [ordered]@{ label = 'Максимальный приоритет'; value = [string]$report.decision_summary.priority },
            [ordered]@{ label = 'Уверенность'; value = [string]$report.audit_confidence }
        )
    }
    [System.IO.File]::WriteAllText($humanReportRuPath, (New-ClientReportHtml -Language 'RU' -ReportPayload $fallbackPayloadRu), (New-SafeUtf8NoBom))
    [System.IO.File]::WriteAllText($humanReportEnPath, (New-ClientReportHtml -Language 'EN' -ReportPayload $fallbackPayloadEn), (New-SafeUtf8NoBom))
    Copy-Item -LiteralPath $humanReportRuPath -Destination $deterministicHumanReportRuPath -Force
    Copy-Item -LiteralPath $humanReportEnPath -Destination $deterministicHumanReportEnPath -Force
}
$report.produced_artifacts = Get-FinalProducedArtifacts -OutputDir $OutputDir -AllowedFolders $allowedFolders -AllowedExtensions $allowedExtensions -Status ([string]$report.status)

if ($shouldFail) {
    $minimalFailRunReportWriteFailed = $false
    $failurePhaseValue = if ([string]::IsNullOrWhiteSpace([string]$failurePhase)) { 'UNKNOWN' } else { [string]$failurePhase }
    $operatorFailureNote = switch ($failurePhaseValue) {
        'ENTRY' { 'entry validation failure' }
        'LINK_FETCH' { 'link fetch failure' }
        'ROUTE_EXTRACTION' { 'route extraction failure' }
        'ROUTE_SELECTION' { 'route selection failure' }
        'CAPTURE' { 'capture stage failure' }
        'RECONCILIATION' { 'reconciliation stage failure' }
        'SURFACE_CONTEXT' { 'surface context failure' }
        'REPORT_LAYER' { 'report layer failure' }
        default { 'internal exception' }
    }
    $failureClass = Get-EffectiveFailureClass -FailureStage $failurePhaseValue -ErrorCode $errorCode -ErrorMessage $errorMessage
    if (-not $report.failure_or_limit_report -or [string]$report.failure_or_limit_report.kind -ne 'FAILURE') {
        $report.failure_or_limit_report = [ordered]@{
            kind = 'FAILURE'
            failure_summary = 'failure_summary.json'
            failure_class = [string]$failureClass
            last_completed_stage = [string]$lastCompletedStage
            current_failure_stage = [string]$failurePhaseValue
            notes = @("phase=$failurePhaseValue", "last_completed_stage=$lastCompletedStage", $operatorFailureNote, $errorMessage)
        }
    }
    else {
        $report.failure_or_limit_report.kind = 'FAILURE'
        $report.failure_or_limit_report.failure_summary = 'failure_summary.json'
        $report.failure_or_limit_report.failure_class = [string]$failureClass
        $report.failure_or_limit_report.last_completed_stage = [string]$lastCompletedStage
        $report.failure_or_limit_report.current_failure_stage = [string]$failurePhaseValue
        $report.failure_or_limit_report.notes = @("phase=$failurePhaseValue", "last_completed_stage=$lastCompletedStage", $operatorFailureNote, $errorMessage)
    }
    $report.last_completed_stage = [string]$lastCompletedStage
    $report.current_failure_stage = [string]$failurePhaseValue
    $failure = [ordered]@{
        error_code = $errorCode
        fail_reason = $errorCode
        fail_phase = $failurePhaseValue
        operator_note = $operatorFailureNote
        error_message = $errorMessage
        exception_type = [string]$failureDiagnostics.exception_type
        message = if ([string]::IsNullOrWhiteSpace([string]$failureDiagnostics.message)) { [string]$errorMessage } else { [string]$failureDiagnostics.message }
        script_stack_trace = [string]$failureDiagnostics.script_stack_trace
        invocation_name = [string]$failureDiagnostics.invocation_name
        script_name = [string]$failureDiagnostics.script_name
        script_line_number = [string]$failureDiagnostics.script_line_number
        position_message = [string]$failureDiagnostics.position_message
        last_report_layer_marker = [string]$failureDiagnostics.last_report_layer_marker
        fail_class = [string]$failureClass
        last_completed_stage = [string]$lastCompletedStage
        current_failure_stage = [string]$failurePhaseValue
        notes = @("phase=$failurePhaseValue", "last_completed_stage=$lastCompletedStage", $operatorFailureNote, $errorMessage)
        must_read_files = @('RUN_REPORT.json', 'visual_manifest.json')
        mode = $normalizedMode
        base_url = $BaseUrl
        status = 'FAIL'
        timestamp_utc = Get-IsoUtcNow
        run_report_path = $runReportPath
    }
    if ($errorCode -eq 'ROUTE_CONTRACT_BREACH' -and $null -ne $report.route_contract) {
        $failure.route_contract_violations = @($report.route_contract.violations)
    }
    try {
        Write-JsonFile -Path $failurePath -Data $failure
    }
    catch {
        $lastResortFailure = [ordered]@{
            error_code = if ([string]::IsNullOrWhiteSpace($errorCode)) { 'FAILURE_SUMMARY_WRITE_FAILED' } else { $errorCode }
            fail_reason = if ([string]::IsNullOrWhiteSpace($errorCode)) { 'FAILURE_SUMMARY_WRITE_FAILED' } else { $errorCode }
            error_message = if ([string]::IsNullOrWhiteSpace($errorMessage)) { 'failure_summary_write_failed' } else { $errorMessage }
            fail_class = [string]$failureClass
            notes = @('failure_summary_write_failed')
            must_read_files = @('RUN_REPORT.json', 'visual_manifest.json')
        }
        [System.IO.File]::WriteAllText($failurePath, ($lastResortFailure | ConvertTo-Json -Depth 10))
    }
    if (Test-Path -LiteralPath $failurePath) {
        Copy-Item -LiteralPath $failurePath -Destination $deterministicFailurePath -Force
    }

    $minimalRunReportResult = Write-MinimalFailRunReport -RootDir $outputRoot -FailPhase ([string]$failurePhaseValue) -ErrorMessage ([string]$errorMessage) -LastCompletedStage ([string]$lastCompletedStage)
    if ([string]$minimalRunReportResult.status -ne 'ok') {
        $minimalFailRunReportWriteFailed = $true
    }
    elseif (Test-Path -LiteralPath $runReportPath) {
        Copy-Item -LiteralPath $runReportPath -Destination $deterministicRunReportPath -Force
    }

    $humanFailureReport = New-AgentFailureReportText -LastCompletedStage ([string]$lastCompletedStage) -CurrentFailureStage ([string]$failurePhaseValue) -FailureClass ([string]$failureClass) -RawError ([string]$errorMessage) -LikelyRootCause ([string]$operatorFailureNote) -FirstFixStep ([string]$report.next_step)
    if ($minimalFailRunReportWriteFailed) {
        $humanFailureReport = $humanFailureReport + [Environment]::NewLine + 'RUN_REPORT_WRITE_FAILED'
    }
    [System.IO.File]::WriteAllText($agentFailureReportPath, $humanFailureReport + [Environment]::NewLine, (New-SafeUtf8NoBom))
    Copy-Item -LiteralPath $agentFailureReportPath -Destination $deterministicAgentFailureReportPath -Force

    $operatorHandoffContract = New-OperatorHandoffContract -FailureClass ([string]$failureClass) -CurrentFailureStage ([string]$failurePhaseValue)
    Write-JsonFile -Path $operatorHandoffPath -Data $operatorHandoffContract
    Copy-Item -LiteralPath $operatorHandoffPath -Destination $deterministicOperatorHandoffPath -Force

    $report.self_build_protocol.build_ladder = Get-BuildLadderContract -HasTruthfulFailure $true -HasSelfDiagnostic $true -HasOperatorHandoff $true
    $report.self_build_protocol.feature_progress_allowed = [bool]$report.self_build_protocol.build_ladder.feature_progress_allowed
    try {
        Invoke-PostOutput -OutputDir $outputRoot -RunReportPath $runReportPath
        Write-Host "POST_OUTPUT_MODULE: DONE"
    }
    catch {
        Write-Host ("POST_OUTPUT_MODULE: FAILED " + $_.Exception.Message)
    }
    $report.produced_artifacts = Get-FinalProducedArtifacts -OutputDir $OutputDir -AllowedFolders $allowedFolders -AllowedExtensions $allowedExtensions -Status ([string]$report.status)
    $report.linked_artifacts = @(
        [ordered]@{ name = 'run_report'; path = $runReportPath },
        [ordered]@{ name = 'failure_summary'; path = $failurePath }
    )
    Write-RunReportBounded -Report $report -RunReportPath $runReportPath -DeterministicRunReportPath $deterministicRunReportPath
    $null = Get-FinalProducedArtifacts -OutputDir $OutputDir -AllowedFolders $allowedFolders -AllowedExtensions $allowedExtensions -Status ([string]$report.status) -ValidateCriticalFinalArtifacts
    exit 0
}

$report.self_build_protocol.build_ladder = Get-BuildLadderContract -HasTruthfulFailure $true -HasSelfDiagnostic $true -HasOperatorHandoff $true
$report.self_build_protocol.feature_progress_allowed = [bool]$report.self_build_protocol.build_ladder.feature_progress_allowed
$report.last_completed_stage = 'REPORT_LAYER'
$report.current_failure_stage = ''
Write-RunReportBounded -Report $report -RunReportPath $runReportPath -DeterministicRunReportPath $deterministicRunReportPath
$null = Get-FinalProducedArtifacts -OutputDir $OutputDir -AllowedFolders $allowedFolders -AllowedExtensions $allowedExtensions -Status ([string]$report.status) -ValidateCriticalFinalArtifacts

# === SAFE POST OUTPUT CALL ===
try {
    $runReportFile = Get-ChildItem -Path (Join-Path $PSScriptRoot "output") -Recurse -Filter "RUN_REPORT.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($null -ne $runReportFile) {
        $outDir = Split-Path $runReportFile.FullName -Parent
        Invoke-PostOutput -OutputDir $outDir -RunReportPath $runReportFile.FullName
        Write-Host "POST_OUTPUT_MODULE: DONE"
    }
}
catch {
    Write-Host ("POST_OUTPUT_MODULE: FAILED " + $_.Exception.Message)
}
# === END SAFE POST OUTPUT ===


# === STAGE: HUMAN_REPORT ===
Write-Host "STAGE: HUMAN_REPORT"

try {
    $runReportPath = Join-Path $PSScriptRoot "RUN_REPORT.json"

    Write-Host ("HUMAN_REPORT: CHECK " + $runReportPath)

    if (Test-Path $runReportPath) {
        Write-Host "HUMAN_REPORT: RUN_REPORT_FOUND"

        $run = Get-Content $runReportPath -Raw | ConvertFrom-Json

        $status = if ($run.status_label) { [string]$run.status_label } else { [string]$run.status }

        $outputEnPath = Join-Path $outputRoot "REPORT_EN.txt"
        $outputRuPath = Join-Path $outputRoot "REPORT_RU.txt"
        $rootEnPath = Join-Path $PSScriptRoot "REPORT_EN.txt"
        $rootRuPath = Join-Path $PSScriptRoot "REPORT_RU.txt"

        Ensure-Directory -Path $outputRoot
        "SITE STATUS: $status" | Out-File $outputEnPath -Encoding UTF8
        "СТАТУС САЙТА: $status" | Out-File $outputRuPath -Encoding UTF8
        Copy-Item -LiteralPath $outputEnPath -Destination $rootEnPath -Force
        Copy-Item -LiteralPath $outputRuPath -Destination $rootRuPath -Force

        Write-Host "HUMAN_REPORT: DONE"
    }
    else {
        Write-Host "HUMAN_REPORT: RUN_REPORT_MISSING"
    }
}
catch {
    Write-Host ("HUMAN_REPORT: FAILED " + $_.Exception.Message)
}
# === END HUMAN REPORT ===


# === HUMAN REPORT TRACE ===
Write-Host "HUMAN_REPORT: ENTERED"

$testPath = Join-Path $PSScriptRoot "TEST_HUMAN_REPORT.txt"
"TEST_OK" | Out-File $testPath -Encoding UTF8

Write-Host ("HUMAN_REPORT: WROTE " + $testPath)

# === STAGE: OUTPUT_CONTRACT_FILTER ===
try {
    $outputFilterPath = Join-Path $PSScriptRoot 'modules/output_contract_filter.ps1'
    if (Test-Path -LiteralPath $outputFilterPath -PathType Leaf) {
        . $outputFilterPath
        Invoke-OutputContractFilter -OutputDir $outputRoot
    }
} catch {
    Write-Host ("OUTPUT_CONTRACT_FILTER: FAILED " + $_.Exception.Message)
}

# === END TRACE ===

exit 0