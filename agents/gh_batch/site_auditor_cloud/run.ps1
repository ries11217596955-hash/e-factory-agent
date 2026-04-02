$ErrorActionPreference = "Stop"

$REPORT_DIR = "reports"
New-Item -ItemType Directory -Force -Path $REPORT_DIR | Out-Null

function Save-Json($path, $obj) {
    $obj | ConvertTo-Json -Depth 20 | Out-File -Encoding utf8 $path
}

function Add-Issue {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$Severity,
        [string]$Code,
        [string]$Repo,
        [string]$Path,
        [string]$Message
    )
    $List.Add([ordered]@{
        severity = $Severity
        code     = $Code
        repo     = $Repo
        path     = $Path
        message  = $Message
    }) | Out-Null
}

function Get-RepoTree {
    param(
        [string]$Repo,
        [hashtable]$Headers
    )

    $repoMetaUrl = "https://api.github.com/repos/$Repo"
    $repoMeta = Invoke-RestMethod -Uri $repoMetaUrl -Headers $Headers -Method Get
    $branch = $repoMeta.default_branch
    if (-not $branch) { $branch = "main" }

    $treeUrl = "https://api.github.com/repos/$Repo/git/trees/$branch?recursive=1"
    $tree = Invoke-RestMethod -Uri $treeUrl -Headers $Headers -Method Get
    return @{
        RepoMeta = $repoMeta
        Branch   = $branch
        Tree     = $tree.tree
    }
}

function Is-ContentPagePath {
    param([string]$Path)
    $p = $Path.ToLowerInvariant()
    if ($p -match '^src/.+\.(md|njk|html)$' -and $p -notmatch '^src/_') { return $true }
    return $false
}

function Resolve-InternalLinkCandidates {
    param([string]$Link)

    $clean = ($Link -split '[?#]')[0].Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { return @() }
    if ($clean -match '^(https?:|mailto:|tel:|#)') { return @() }
    if (-not $clean.StartsWith('/')) { return @() }

    $trim = $clean.TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($trim)) {
        return @("src/index.md","src/index.njk","src/index.html")
    }

    $c = New-Object System.Collections.Generic.List[string]
    $base = "src/$trim".TrimEnd('/')
    $c.Add($base) | Out-Null
    $c.Add("$base/index.md") | Out-Null
    $c.Add("$base/index.njk") | Out-Null
    $c.Add("$base/index.html") | Out-Null
    if ($base -notmatch '\.[A-Za-z0-9]+$') {
        $c.Add("$base.md") | Out-Null
        $c.Add("$base.njk") | Out-Null
        $c.Add("$base.html") | Out-Null
    }
    return @($c | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
}

$headers = @{
    Authorization = "token $env:GITHUB_TOKEN"
    "User-Agent"  = "site-auditor-v3"
    Accept        = "application/vnd.github+json"
}

try {
    if (-not $env:GITHUB_TOKEN) {
        throw "GITHUB_TOKEN is empty"
    }

    $reposPath = "agents/gh_batch/site_auditor_cloud/repos.fixed.json"
    if (-not (Test-Path -LiteralPath $reposPath)) {
        throw "repos.fixed.json not found: $reposPath"
    }

    $repos = Get-Content -LiteralPath $reposPath -Raw | ConvertFrom-Json

    $allIssues = New-Object System.Collections.Generic.List[object]
    $allSummaries = New-Object System.Collections.Generic.List[object]
    $allStructures = New-Object System.Collections.Generic.List[object]

    foreach ($repo in $repos) {
        try {
            $treeInfo = Get-RepoTree -Repo $repo -Headers $headers
            $tree = @($treeInfo.Tree)
            $fileItems = @($tree | Where-Object { $_.type -eq "blob" })
            $paths = @($fileItems | ForEach-Object { [string]$_.path })
            $pathSet = @{}
            foreach ($p in $paths) { $pathSet[$p.ToLowerInvariant()] = $true }

            $contentPages = @($paths | Where-Object { Is-ContentPagePath $_ })
            $posts = @($paths | Where-Object { $_ -match '^src/posts/' })
            $hubs = @($paths | Where-Object { $_ -match '^src/hubs/' })
            $workflows = @($paths | Where-Object { $_ -match '^\.github/workflows/' })

            $summary = [ordered]@{
                repo = $repo
                status = "ok"
                default_branch = $treeInfo.Branch
                file_count = $paths.Count
                content_pages = $contentPages.Count
                posts = $posts.Count
                hubs = $hubs.Count
                workflows = $workflows.Count
                timestamp = (Get-Date).ToString("s")
            }

            if ($repo -like "*/automation-kb") {
                if ($hubs.Count -eq 0) {
                    Add-Issue -List $allIssues -Severity "high" -Code "NO_HUBS" -Repo $repo -Path "" -Message "No hub pages detected under src/hubs/."
                }
                if ($posts.Count -lt 10) {
                    Add-Issue -List $allIssues -Severity "medium" -Code "LOW_POST_COUNT" -Repo $repo -Path "" -Message ("Low post count detected: {0}" -f $posts.Count)
                }
                if (-not ($pathSet.ContainsKey("src/search.njk") -or $pathSet.ContainsKey("src/search.md") -or $pathSet.ContainsKey("src/search/index.njk") -or $pathSet.ContainsKey("src/search/index.md"))) {
                    Add-Issue -List $allIssues -Severity "medium" -Code "SEARCH_PAGE_MISSING" -Repo $repo -Path "" -Message "No search page detected under src/."
                }

                $candidateInspect = @($contentPages | Select-Object -First 25)
                foreach ($pagePath in $candidateInspect) {
                    try {
                        $contentUrl = "https://raw.githubusercontent.com/$repo/$($treeInfo.Branch)/$pagePath"
                        $raw = Invoke-RestMethod -Uri $contentUrl -Headers $headers -Method Get

                        if ($raw -match '^[A-Za-z0-9+/=\r\n]{400,}$') {
                            Add-Issue -List $allIssues -Severity "high" -Code "BASE64_LIKE_CONTENT" -Repo $repo -Path $pagePath -Message "File content looks like base64/plaintext corruption."
                        }

                        if ($raw -notmatch '(?im)^\s*title\s*:') {
                            Add-Issue -List $allIssues -Severity "low" -Code "MISSING_TITLE" -Repo $repo -Path $pagePath -Message "No front-matter title detected."
                        }
                        if (($raw -notmatch '(?im)^\s*description\s*:') -and ($raw -notmatch '(?im)^\s*excerpt\s*:')) {
                            Add-Issue -List $allIssues -Severity "low" -Code "MISSING_DESCRIPTION" -Repo $repo -Path $pagePath -Message "No front-matter description/excerpt detected."
                        }

                        $rxMd = [regex]'\[[^\]]+\]\((?!https?:|mailto:|tel:|#)([^)\s]+)\)'
                        $rxHref = [regex]'href=["''](?!https?:|mailto:|tel:|#)([^"''>]+)["'']'
                        $links = New-Object System.Collections.Generic.List[string]

                        foreach ($m in $rxMd.Matches($raw)) { $links.Add($m.Groups[1].Value) | Out-Null }
                        foreach ($m in $rxHref.Matches($raw)) { $links.Add($m.Groups[1].Value) | Out-Null }

                        foreach ($lnk in @($links | Select-Object -Unique)) {
                            $candidates = @(Resolve-InternalLinkCandidates -Link $lnk)
                            if ($candidates.Count -gt 0) {
                                $exists = $false
                                foreach ($cand in $candidates) {
                                    if ($pathSet.ContainsKey($cand)) { $exists = $true; break }
                                }
                                if (-not $exists) {
                                    Add-Issue -List $allIssues -Severity "medium" -Code "BROKEN_INTERNAL_LINK" -Repo $repo -Path $pagePath -Message ("Broken internal link: {0}" -f $lnk)
                                }
                            }
                        }
                    }
                    catch {
                        Add-Issue -List $allIssues -Severity "low" -Code "CONTENT_FETCH_WARN" -Repo $repo -Path $pagePath -Message $_.Exception.Message
                    }
                }
            }

            $repoIssues = @($allIssues | Where-Object { $_.repo -eq $repo })
            $summary["issues_total"] = $repoIssues.Count
            $summary["issues_high"] = @($repoIssues | Where-Object { $_.severity -eq "high" }).Count
            $summary["issues_medium"] = @($repoIssues | Where-Object { $_.severity -eq "medium" }).Count
            $summary["issues_low"] = @($repoIssues | Where-Object { $_.severity -eq "low" }).Count

            $allSummaries.Add($summary) | Out-Null
            $allStructures.Add([ordered]@{
                repo = $repo
                sampled_paths = @($paths | Select-Object -First 100)
            }) | Out-Null
        }
        catch {
            $err = [ordered]@{
                repo = $repo
                status = "fail"
                error = $_.Exception.Message
                timestamp = (Get-Date).ToString("s")
            }
            $allSummaries.Add($err) | Out-Null
            Add-Issue -List $allIssues -Severity "high" -Code "REPO_FETCH_FAIL" -Repo $repo -Path "" -Message $_.Exception.Message
        }
    }

    Save-Json "$REPORT_DIR/summary.json" $allSummaries
    Save-Json "$REPORT_DIR/issues.json" $allIssues
    Save-Json "$REPORT_DIR/structure.json" $allStructures

    $html = New-Object System.Collections.Generic.List[string]
    $html.Add('<!doctype html><html><head><meta charset="utf-8"><title>SITE AUDIT V3</title><style>body{font-family:Arial;margin:24px;color:#222}table{border-collapse:collapse;width:100%;margin:16px 0}th,td{border:1px solid #ccc;padding:8px;text-align:left}th{background:#f4f4f4}.high{color:#b00020;font-weight:bold}.medium{color:#b26a00;font-weight:bold}.low{color:#555}.ok{color:#0a7b34;font-weight:bold}.fail{color:#b00020;font-weight:bold}code{background:#f5f5f5;padding:2px 4px}</style></head><body>') | Out-Null
    $html.Add('<h1>SITE AUDIT V3</h1>') | Out-Null
    $html.Add(("<p><b>Generated:</b> {0}</p>" -f (Get-Date).ToString("s"))) | Out-Null

    $html.Add('<h2>Summary</h2><table><tr><th>Repo</th><th>Status</th><th>Files</th><th>Pages</th><th>Posts</th><th>Hubs</th><th>Issues</th></tr>') | Out-Null
    foreach ($s in $allSummaries) {
        $statusClass = if ($s.status -eq "ok") { "ok" } else { "fail" }
        $html.Add(("<tr><td><code>{0}</code></td><td class=""{1}"">{2}</td><td>{3}</td><td>{4}</td><td>{5}</td><td>{6}</td><td>{7}</td></tr>" -f
            [System.Net.WebUtility]::HtmlEncode([string]$s.repo),
            $statusClass,
            [System.Net.WebUtility]::HtmlEncode([string]$s.status),
            $(if ($null -ne $s.file_count) { $s.file_count } else { "" }),
            $(if ($null -ne $s.content_pages) { $s.content_pages } else { "" }),
            $(if ($null -ne $s.posts) { $s.posts } else { "" }),
            $(if ($null -ne $s.hubs) { $s.hubs } else { "" }),
            $(if ($null -ne $s.issues_total) { $s.issues_total } else { [System.Net.WebUtility]::HtmlEncode([string]$s.error) })
        )) | Out-Null
    }
    $html.Add('</table>') | Out-Null

    $html.Add('<h2>Issues</h2><table><tr><th>Severity</th><th>Repo</th><th>Code</th><th>Path</th><th>Message</th></tr>') | Out-Null
    foreach ($i in $allIssues) {
        $html.Add(("<tr><td class=""{0}"">{1}</td><td><code>{2}</code></td><td>{3}</td><td><code>{4}</code></td><td>{5}</td></tr>" -f
            [System.Net.WebUtility]::HtmlEncode([string]$i.severity),
            [System.Net.WebUtility]::HtmlEncode([string]$i.severity),
            [System.Net.WebUtility]::HtmlEncode([string]$i.repo),
            [System.Net.WebUtility]::HtmlEncode([string]$i.code),
            [System.Net.WebUtility]::HtmlEncode([string]$i.path),
            [System.Net.WebUtility]::HtmlEncode([string]$i.message)
        )) | Out-Null
    }
    $html.Add('</table></body></html>') | Out-Null
    ($html -join "`n") | Out-File -Encoding utf8 "$REPORT_DIR/report.html"
}
catch {
    Save-Json "$REPORT_DIR/error.json" @{
        error = $_.Exception.Message
        timestamp = (Get-Date).ToString("s")
    }
}

if (-not (Get-ChildItem -LiteralPath $REPORT_DIR -Force | Select-Object -First 1)) {
    "EMPTY REPORT" | Out-File -Encoding utf8 "$REPORT_DIR/empty.txt"
}

exit 0
