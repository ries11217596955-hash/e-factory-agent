# =========================
# SAFE NORMALIZERS
# =========================

function Convert-ToStringArray {
    param($input)
    if (-not $input) { return @() }
    return @($input | ForEach-Object { [string]$_ })
}

function Normalize-TreeItems {
    param($items)
    if (-not $items) { return @() }
    return @($items | ForEach-Object { $_ })
}

# =========================
# WRITE REPORT
# =========================

function Save-Json {
    param($path, $data)
    $json = $data | ConvertTo-Json -Depth 10
    $json | Out-File -Encoding utf8 $path
}

function Ensure-ReportsDir {
    if (-not (Test-Path "reports")) {
        New-Item -ItemType Directory -Path "reports" | Out-Null
    }
}

# =========================
# CORE ENTRY
# =========================

function Invoke-SiteAuditor {
    param(
        $RepoList,
        $Token
    )

    Ensure-ReportsDir

    $RepoList = Convert-ToStringArray $RepoList
    $results = @()

    foreach ($repo in $RepoList) {

        Write-Host "AUDIT REPO: $repo"

        $treeItems = @()

        try {
            $repoUrl = "https://api.github.com/repos/$repo"
            $repoMeta = Invoke-RestMethod -Uri $repoUrl -Headers @{ Authorization = "token $Token" }

            $branch = $repoMeta.default_branch
            $branchData = Invoke-RestMethod -Uri "$repoUrl/branches/$branch" -Headers @{ Authorization = "token $Token" }

            $treeSha = $branchData.commit.commit.tree.sha

            $treeUrl = "$repoUrl/git/trees/$treeSha?recursive=1"
            $tree = Invoke-RestMethod -Uri $treeUrl -Headers @{ Authorization = "token $Token" }

            $treeItems = Normalize-TreeItems $tree.tree
        }
        catch {
            Write-Host "FETCH FAILED: $repo"
            continue
        }

        $audit = Get-AuditV2 -Repo $repo -TreeItems $treeItems
        $results += $audit
    }

    # =========================
    # SAVE REPORTS
    # =========================

    $summary = @{
        repos_total = $RepoList.Count
        repos_processed = $results.Count
        audit_version = "v2"
        status = if ($results.Count -gt 0) { "PASS_AUDIT_V2" } else { "FAIL_RUNTIME" }
    }

    Save-Json "reports/audit_result.json" $results
    Save-Json "reports/pipeline-summary.json" $summary

    $summary.status | Out-File "reports/final-status.json"

    "SITE AUDIT REPORT" | Out-File "reports/REPORT.txt"
    $results | Out-File "reports/REPORT.txt" -Append

    return $results
}

# =========================
# AUDIT V2
# =========================

function Get-AuditV2 {
    param(
        $Repo,
        $TreeItems
    )

    if (-not $TreeItems) { $TreeItems = @() }

    $TreeItems = Normalize-TreeItems $TreeItems

    $pagePaths = Get-PagePaths $TreeItems
    $hubMap = Get-HubMap $pagePaths
    $orphanPages = Get-OrphanPages $pagePaths
    $emptyDirs = Get-EmptyDirectories $TreeItems

    return @{
        repo = $Repo
        page_count = $pagePaths.Count
        orphan_count = $orphanPages.Count
        empty_dirs = $emptyDirs.Count
        audit_version = "v2"
    }
}

# =========================
# HELPERS
# =========================

function Get-PagePaths {
    param($TreeItems)
    $TreeItems = Normalize-TreeItems $TreeItems

    return @(
        $TreeItems |
        Where-Object { $_.path -match "\.(md|html)$" } |
        ForEach-Object { $_.path }
    )
}

function Get-HubMap {
    param($PagePaths)
    $PagePaths = Convert-ToStringArray $PagePaths

    $map = @{}

    foreach ($p in $PagePaths) {
        if ($p -match "^hubs/") {
            $parts = $p.Split('/')
            if ($parts.Count -gt 1) {
                $hub = $parts[1]
                if (-not $map.ContainsKey($hub)) { $map[$hub] = @() }
                $map[$hub] += $p
            }
        }
    }

    return $map
}

function Get-OrphanPages {
    param($PagePaths)
    $PagePaths = Convert-ToStringArray $PagePaths

    return @(
        $PagePaths |
        Where-Object { $_ -notmatch "^hubs/" }
    )
}

function Get-EmptyDirectories {
    param($TreeItems)
    $TreeItems = Normalize-TreeItems $TreeItems

    $dirs = @(
        $TreeItems |
        Where-Object { $_.type -eq "tree" } |
        ForEach-Object { $_.path }
    )

    $files = @(
        $TreeItems |
        Where-Object { $_.type -eq "blob" } |
        ForEach-Object { $_.path }
    )

    $empty = @()

    foreach ($d in $dirs) {
        $hasFile = $false

        foreach ($f in $files) {
            if ($f.StartsWith("$d/")) {
                $hasFile = $true
                break
            }
        }

        if (-not $hasFile) {
            $empty += $d
        }
    }

    return $empty
}
