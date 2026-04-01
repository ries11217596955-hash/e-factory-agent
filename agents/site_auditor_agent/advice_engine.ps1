function Invoke-AdviceEngine {
    param(
        [string]$ReportDir,
        [string]$TargetConfigPath
    )

    function Load-JsonSafe {
        param([string]$Path)
        if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
        if (!(Test-Path -LiteralPath $Path)) { return $null }
        try {
            return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
        }
        catch {
            return $null
        }
    }

    function Add-Item {
        param([System.Collections.ArrayList]$Bucket, [object]$Item)
        $null = $Bucket.Add($Item)
    }

    function Test-IgnoredRoute {
        param([string]$Route, [object]$InventoryItem)

        if ([string]::IsNullOrWhiteSpace($Route)) { return $true }
        $r = $Route.ToLowerInvariant()
        if ($r -in @('/404.html','/404/','/search.json','/site.webmanifest','/sitemap.xml')) { return $true }
        if ($r -like '/feeds/*') { return $true }
        if ($r -eq '/tags/' -or $r -like '/tags/*') { return $true }
        if ($r -eq '/search/' -or $r -like '/search/*') { return $true }

        if ($null -ne $InventoryItem) {
            try { if ($InventoryItem.is_publishable -eq $false) { return $true } } catch {}
            try { if ($InventoryItem.content_role -eq 'service_or_debug' -or $InventoryItem.content_role -eq 'service_or_special_page') { return $true } } catch {}
        }

        return $false
    }

    function New-RepairIssue {
        param(
            [string]$Type,
            [string]$Severity,
            [string]$Scope,
            [string]$Why,
            [string]$ActionType,
            [string]$ActionTarget,
            [string]$Instruction,
            [object[]]$AffectedItems,
            [hashtable]$Extra
        )

        $obj = [ordered]@{
            type = $Type
            severity = $Severity
            scope = $Scope
            why = $Why
            affected_count = @($AffectedItems).Count
            action = [ordered]@{
                type = $ActionType
                target = $ActionTarget
                instruction = $Instruction
            }
            affected_items = @($AffectedItems)
        }

        if ($null -ne $Extra) {
            foreach ($k in $Extra.Keys) {
                if (-not $obj.Contains($k)) {
                    $obj[$k] = $Extra[$k]
                }
            }
        }

        return [PSCustomObject]$obj
    }

    function Get-FamilyFromRoute {
        param([string]$Route)
        if ([string]::IsNullOrWhiteSpace($Route)) { return 'root' }
        $trimmed = $Route.Trim('/')
        if ([string]::IsNullOrWhiteSpace($trimmed)) { return 'root' }
        $parts = @($trimmed -split '/' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if (@($parts).Count -eq 0) { return 'root' }
        return $parts[0].ToLowerInvariant()
    }

    function Split-ItemsIntoChunks {
        param([object[]]$Items, [int]$ChunkSize)

        $result = New-Object System.Collections.ArrayList
        if ($ChunkSize -lt 1) { $ChunkSize = 20 }

        if (@($Items).Count -le $ChunkSize) {
            $null = $result.Add(@($Items))
            return @($result)
        }

        for ($i = 0; $i -lt $Items.Count; $i += $ChunkSize) {
            $upper = [Math]::Min($i + $ChunkSize - 1, $Items.Count - 1)
            $chunk = @()
            for ($j = $i; $j -le $upper; $j++) {
                $chunk += $Items[$j]
            }
            $null = $result.Add($chunk)
        }
        return @($result)
    }

    if (!(Test-Path -LiteralPath $ReportDir)) {
        New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
    }

    $target = Load-JsonSafe -Path $TargetConfigPath
    $inventory = @((Load-JsonSafe -Path (Join-Path $ReportDir "01_INVENTORY.json")))
    $semanticIssues = @((Load-JsonSafe -Path (Join-Path $ReportDir "02_SEMANTIC_ISSUES.json")))
    $brokenLinks = @((Load-JsonSafe -Path (Join-Path $ReportDir "03_BROKEN_LINKS.json")))
    $orphans = @((Load-JsonSafe -Path (Join-Path $ReportDir "04_ORPHAN_PAGES.json")))
    $renderAudit = @((Load-JsonSafe -Path (Join-Path $ReportDir "06_RENDER_AUDIT.json")))
    $targetAlignment = Load-JsonSafe -Path (Join-Path $ReportDir "08_TARGET_ALIGNMENT.json")
    $stageAssessment = Load-JsonSafe -Path (Join-Path $ReportDir "09_STAGE_ASSESSMENT.json")
    $metrics = Load-JsonSafe -Path (Join-Path $ReportDir "10_METRICS.json")

    $inventoryMap = @{}
    foreach ($item in @($inventory)) {
        $route = $null
        try { $route = $item.route } catch {}
        if (-not [string]::IsNullOrWhiteSpace($route)) {
            $inventoryMap[$route] = $item
        }
    }

    $issues = New-Object System.Collections.ArrayList
    $suppressed = New-Object System.Collections.ArrayList
    $priorityList = New-Object System.Collections.ArrayList

    # P0: required routes missing
    foreach ($route in @($targetAlignment.missing_required_routes)) {
        if ([string]::IsNullOrWhiteSpace($route)) { continue }
        Add-Item -Bucket $issues -Item (
            New-RepairIssue `
                -Type "missing_required_route" `
                -Severity "P0" `
                -Scope $route `
                -Why "Required route from the target model is absent, so the site misses a critical navigational or hub page." `
                -ActionType "create_or_restore_route" `
                -ActionTarget $route `
                -Instruction "Create or restore this required route and ensure it is included in the generated site." `
                -AffectedItems @([PSCustomObject]@{ route = $route }) `
                -Extra @{}
        )
    }

    # P0/P1: render failures
    foreach ($item in @($renderAudit)) {
        $status = $null; $route = $null; $reason = $null
        try { $status = $item.status } catch {}
        try { $route = $item.route } catch {}
        try { $reason = $item.reason } catch {}

        if ($status -eq 'OK') { continue }
        $inv = $null
        if ($inventoryMap.ContainsKey($route)) { $inv = $inventoryMap[$route] }
        if (Test-IgnoredRoute -Route $route -InventoryItem $inv) { continue }

        $sev = "P1"
        if ($null -ne $target -and @($target.required_routes) -contains $route) { $sev = "P0" }

        Add-Item -Bucket $issues -Item (
            New-RepairIssue `
                -Type "render_failure" `
                -Severity $sev `
                -Scope $route `
                -Why "This route failed render validation and can break visibility, trust, or crawlability." `
                -ActionType "fix_render_chain" `
                -ActionTarget $route `
                -Instruction "Open the route template chain, inspect the generated output, and resolve the render failure before content cleanup." `
                -AffectedItems @([PSCustomObject]@{ route = $route; status = $status; reason = $reason; status_code = $item.status_code }) `
                -Extra @{}
        )
    }

    # P1: cluster gaps
    foreach ($cluster in @($targetAlignment.required_clusters)) {
        if ($null -eq $cluster) { continue }

        if ($cluster.actual_pages -lt $cluster.min_pages) {
            Add-Item -Bucket $issues -Item (
                New-RepairIssue `
                    -Type "cluster_underfilled" `
                    -Severity "P1" `
                    -Scope "$($cluster.cluster_id)" `
                    -Why "This required cluster does not have enough publishable pages to meet the target model." `
                    -ActionType "expand_cluster" `
                    -ActionTarget "$($cluster.cluster_id)" `
                    -Instruction "Publish additional pages in this cluster until the minimum page target is reached." `
                    -AffectedItems @([PSCustomObject]@{ cluster_id = $cluster.cluster_id; actual_pages = $cluster.actual_pages; min_pages = $cluster.min_pages }) `
                    -Extra @{}
            )
        }

        if (-not $cluster.hub_present) {
            $hubRoute = "/$($cluster.cluster_id)/"
            Add-Item -Bucket $issues -Item (
                New-RepairIssue `
                    -Type "cluster_hub_missing" `
                    -Severity "P1" `
                    -Scope "$($cluster.cluster_id)" `
                    -Why "This cluster has no detected hub page, which weakens navigation and internal linking." `
                    -ActionType "create_cluster_hub" `
                    -ActionTarget $hubRoute `
                    -Instruction "Create or restore the hub route for this cluster and connect member pages to it." `
                    -AffectedItems @([PSCustomObject]@{ cluster_id = $cluster.cluster_id; expected_hub = $hubRoute }) `
                    -Extra @{}
            )
        }
    }

    # P1/P2: orphan grouping
    $orphanGroups = @{}
    foreach ($item in @($orphans)) {
        $route = $null
        try { $route = $item.route } catch {}
        if ([string]::IsNullOrWhiteSpace($route)) { continue }

        $inv = $null
        if ($inventoryMap.ContainsKey($route)) { $inv = $inventoryMap[$route] }
        if (Test-IgnoredRoute -Route $route -InventoryItem $inv) {
            Add-Item -Bucket $suppressed -Item ([PSCustomObject]@{ type = "orphan_page"; route = $route; reason = "ignored_route_or_non_publishable" })
            continue
        }

        $family = Get-FamilyFromRoute -Route $route
        $groupKey = $family
        $severity = "P2"
        $scope = $family
        $instruction = "Add internal links from a relevant hub, index, or navigation block to the affected routes."

        $clusterId = $null; $pageType = $null
        try { $clusterId = $inv.cluster_id } catch {}
        try { $pageType = $inv.page_type } catch {}

        if (-not [string]::IsNullOrWhiteSpace($clusterId)) {
            $groupKey = "cluster:" + $clusterId
            $scope = "cluster:" + $clusterId
            $severity = "P1"
            $instruction = "Add links from the cluster hub or adjacent cluster pages to these orphan routes."
        }
        elseif ($pageType -eq 'hub') {
            $groupKey = "hub:" + $family
            $scope = "hub:" + $family
            $severity = "P1"
            $instruction = "Restore navigation links to these hub routes from main navigation or section index pages."
        }

        if (-not $orphanGroups.ContainsKey($groupKey)) {
            $orphanGroups[$groupKey] = [ordered]@{
                severity = $severity
                scope = $scope
                instruction = $instruction
                items = New-Object System.Collections.ArrayList
            }
        }

        Add-Item -Bucket $orphanGroups[$groupKey].items -Item ([PSCustomObject]@{
            route = $route
            file = $item.file
            cluster_id = $clusterId
            page_type = $pageType
        })
    }

    foreach ($groupKey in $orphanGroups.Keys) {
        $group = $orphanGroups[$groupKey]
        $items = @($group.items | Sort-Object route)
        $chunkSize = 15
        if ($group.scope -like 'cluster:*') { $chunkSize = 20 }
        $chunks = Split-ItemsIntoChunks -Items $items -ChunkSize $chunkSize
        $chunkIndex = 1

        foreach ($chunk in @($chunks)) {
            $scope = $group.scope
            if (@($chunks).Count -gt 1) { $scope = $scope + "#batch-" + $chunkIndex }

            Add-Item -Bucket $issues -Item (
                New-RepairIssue `
                    -Type "orphan_group" `
                    -Severity $group.severity `
                    -Scope $scope `
                    -Why "These publishable routes have no meaningful internal inbound links and are weakly discoverable." `
                    -ActionType "add_internal_links_batch" `
                    -ActionTarget $scope `
                    -Instruction $group.instruction `
                    -AffectedItems @($chunk) `
                    -Extra @{ batch_index = $chunkIndex; batch_total = @($chunks).Count }
            )
            $chunkIndex++
        }
    }

    # P1/P2: broken links grouped by source route
    $brokenBySource = @{}
    foreach ($item in @($brokenLinks)) {
        $sourceRoute = $null; $targetRoute = $null; $badLink = $null; $issueType = $null
        try { $sourceRoute = $item.source_route } catch {}
        try { $targetRoute = $item.target_route } catch {}
        try { $badLink = $item.bad_link } catch {}
        try { $issueType = $item.issue_type } catch {}

        if ($issueType -eq 'TEMPLATE_EXPRESSION_NOT_RENDERED') {
            Add-Item -Bucket $suppressed -Item ([PSCustomObject]@{ type = "broken_link"; route = $sourceRoute; reason = "template_expression" })
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($badLink) -and ($badLink -match '^\{\{.*\}\}$')) {
            Add-Item -Bucket $suppressed -Item ([PSCustomObject]@{ type = "broken_link"; route = $sourceRoute; reason = "template_expression" })
            continue
        }

        $inv = $null
        if ($inventoryMap.ContainsKey($sourceRoute)) { $inv = $inventoryMap[$sourceRoute] }
        if (Test-IgnoredRoute -Route $sourceRoute -InventoryItem $inv) {
            Add-Item -Bucket $suppressed -Item ([PSCustomObject]@{ type = "broken_link"; route = $sourceRoute; reason = "ignored_source_route" })
            continue
        }

        $classification = "internal"
        $severity = "P1"
        if (-not [string]::IsNullOrWhiteSpace($badLink) -and ($badLink -match '^(http|https)://')) {
            $classification = "external"
            $severity = "P2"
        }
        elseif ([string]::IsNullOrWhiteSpace($targetRoute)) {
            $classification = "unresolved"
            $severity = "P2"
        }

        if ([string]::IsNullOrWhiteSpace($sourceRoute)) { $sourceRoute = "unknown_source" }

        if (-not $brokenBySource.ContainsKey($sourceRoute)) {
            $brokenBySource[$sourceRoute] = [ordered]@{
                severity = $severity
                classification = $classification
                items = New-Object System.Collections.ArrayList
            }
        }

        if ($severity -eq "P1") { $brokenBySource[$sourceRoute].severity = "P1" }
        if ($classification -eq "internal") { $brokenBySource[$sourceRoute].classification = "internal" }

        Add-Item -Bucket $brokenBySource[$sourceRoute].items -Item ([PSCustomObject]@{
            source_route = $sourceRoute
            target_route = $targetRoute
            bad_link = $badLink
            issue_type = $issueType
            classification = $classification
        })
    }

    foreach ($sourceRoute in $brokenBySource.Keys) {
        $group = $brokenBySource[$sourceRoute]
        $instruction = "Edit this source page and replace or remove the broken links listed below."
        if ($group.classification -eq "internal") {
            $instruction = "Edit this source page and point the broken internal links to valid routes or create the missing targets."
        }

        Add-Item -Bucket $issues -Item (
            New-RepairIssue `
                -Type "broken_link_group" `
                -Severity $group.severity `
                -Scope $sourceRoute `
                -Why "Multiple broken links on one source page should be fixed in a single edit pass." `
                -ActionType "edit_source_page_links" `
                -ActionTarget $sourceRoute `
                -Instruction $instruction `
                -AffectedItems @($group.items) `
                -Extra @{ classification = $group.classification }
        )
    }

    # P2: semantic issues grouped lightly
    if (@($semanticIssues).Count -gt 0) {
        $semanticCandidates = @()
        foreach ($s in @($semanticIssues)) {
            $route = $null
            try { $route = $s.route } catch {}
            if ($inventoryMap.ContainsKey($route)) {
                $inv = $inventoryMap[$route]
                if (Test-IgnoredRoute -Route $route -InventoryItem $inv) { continue }
            }
            $semanticCandidates += $s
        }

        if (@($semanticCandidates).Count -gt 0) {
            $chunks = Split-ItemsIntoChunks -Items @($semanticCandidates) -ChunkSize 15
            $idx = 1
            foreach ($chunk in @($chunks)) {
                Add-Item -Bucket $issues -Item (
                    New-RepairIssue `
                        -Type "semantic_issue_group" `
                        -Severity "P2" `
                        -Scope ("semantic#batch-" + $idx) `
                        -Why "These pages have content-quality or metadata issues that matter after routing and render issues are resolved." `
                        -ActionType "improve_page_semantics" `
                        -ActionTarget ("semantic#batch-" + $idx) `
                        -Instruction "Improve titles, descriptions, structure, and content signals for the affected pages in this batch." `
                        -AffectedItems @($chunk) `
                        -Extra @{ batch_index = $idx; batch_total = @($chunks).Count }
                )
                $idx++
            }
        }
    }

    $ordered = @(
        @($issues | Where-Object { $_.severity -eq "P0" }),
        @($issues | Where-Object { $_.severity -eq "P1" }),
        @($issues | Where-Object { $_.severity -eq "P2" }),
        @($issues | Where-Object { $_.severity -notin @("P0","P1","P2") })
    ) | ForEach-Object { $_ }

    $priority = 1
    foreach ($issue in @($ordered)) {
        Add-Item -Bucket $priorityList -Item ([PSCustomObject]@{
            priority = $priority
            severity = $issue.severity
            type = $issue.type
            scope = $issue.scope
            action = $issue.action.type
            target = $issue.action.target
        })
        $priority++
    }

    $executiveSummary = [ordered]@{
        build_stage = $null
        inventory_total = $null
        publishable_pages = $null
        top_3_actions = @($priorityList | Select-Object -First 3)
        p0_count = @($ordered | Where-Object { $_.severity -eq "P0" }).Count
        p1_count = @($ordered | Where-Object { $_.severity -eq "P1" }).Count
        p2_count = @($ordered | Where-Object { $_.severity -eq "P2" }).Count
    }
    if ($stageAssessment) {
        try { $executiveSummary.build_stage = $stageAssessment.build_stage } catch {}
    }
    if ($metrics) {
        try { $executiveSummary.inventory_total = $metrics.inventory_total } catch {}
        try { $executiveSummary.publishable_pages = $metrics.publishable_pages } catch {}
    }

    $summary = [ordered]@{
        generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        total = @($ordered).Count
        by_severity = [ordered]@{
            P0 = @($ordered | Where-Object { $_.severity -eq "P0" }).Count
            P1 = @($ordered | Where-Object { $_.severity -eq "P1" }).Count
            P2 = @($ordered | Where-Object { $_.severity -eq "P2" }).Count
        }
        build_stage = $executiveSummary.build_stage
        suppressed_count = @($suppressed).Count
        executive_summary = $executiveSummary
        execution_order = $priorityList
        suppressed = $suppressed
        issues = $ordered
    }

    ([PSCustomObject]$summary | ConvertTo-Json -Depth 12) | Out-File -LiteralPath (Join-Path $ReportDir "11_HOW_TO_FIX.json") -Encoding utf8

    $text = @()
    $text += "SITE AUDIT EXECUTIVE SUMMARY"
    $text += "Build Stage: $($executiveSummary.build_stage)"
    $text += "Inventory Total: $($executiveSummary.inventory_total)"
    $text += "Publishable Pages: $($executiveSummary.publishable_pages)"
    $text += "P0: $($executiveSummary.p0_count) | P1: $($executiveSummary.p1_count) | P2: $($executiveSummary.p2_count)"
    $text += ""
    $text += "TOP ACTIONS:"
    foreach ($a in @($executiveSummary.top_3_actions)) {
        $text += ("[{0}] {1} | {2} | {3}" -f $a.priority, $a.severity, $a.type, $a.target)
    }
    ($text -join [Environment]::NewLine) | Out-File -LiteralPath (Join-Path $ReportDir "11A_EXECUTIVE_SUMMARY.txt") -Encoding utf8
}

# --- v3.6 Operator Mode additions ---
$priorityFile = Join-Path $reportDir "00_PRIORITY_ACTIONS.txt"
@"
STEP 1 (P0)
- Fix broken routes

STEP 2 (P1)
- Restore internal links

STEP 3 (P2)
- Cleanup external links
"@ | Out-File $priorityFile -Encoding utf8

$topIssuesFile = Join-Path $reportDir "01_TOP_ISSUES.txt"
@"
TOP ISSUES:
1. Broken routes
2. Missing internal links
3. Orphan pages
4. External issues
"@ | Out-File $topIssuesFile -Encoding utf8

$summaryFile = Join-Path $reportDir "11A_EXECUTIVE_SUMMARY.txt"
@"
EXECUTIVE SUMMARY:
Critical routing and linking issues detected.
"@ | Out-File $summaryFile -Encoding utf8

# --- end v3.6 ---
