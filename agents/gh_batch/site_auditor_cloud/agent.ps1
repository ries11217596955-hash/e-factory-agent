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
# CORE ENTRY
# =========================

function Invoke-SiteAuditor {
    param(
        $RepoList,
        $Token
    )

    $RepoList = Convert-ToStringArray $RepoList

    $results = @()

    foreach ($repo in $RepoList) {

        Write-Host "AUDIT REPO: $repo"

        # --- FETCH TREE ---
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

        # --- AUDIT V2 ---
        $audit = Get-AuditV2 -Repo $repo -TreeItems $treeItems

        $results += $audit
    }

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

                if (-not $map.ContainsKey($hub)) {
                    $map[$hub] = @()
                }

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
