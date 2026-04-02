
$ErrorActionPreference = "Stop"

$reportsDir = "reports"
New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null

$reposPath = "./agents/gh_batch/site_auditor_cloud/repos.fixed.json"
if (-not (Test-Path -LiteralPath $reposPath)) {
    "repos.fixed.json not found: $reposPath" | Set-Content "$reportsDir/bootstrap.error.txt"
    exit 1
}

$repos = Get-Content -LiteralPath $reposPath -Raw | ConvertFrom-Json

function New-WorkDir {
    param([string]$BaseName)
    $root = Join-Path $PWD "tmp_site_auditor"
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $path = Join-Path $root $BaseName
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    return $path
}

function Get-RepoRoot {
    param([string]$ExtractPath)
    $dirs = @(Get-ChildItem -LiteralPath $ExtractPath -Directory -Force)
    if ($dirs.Count -eq 1) { return $dirs[0].FullName }
    return $ExtractPath
}

function Get-RelativePaths {
    param([string]$RootPath)

    $files = @(Get-ChildItem -LiteralPath $RootPath -Recurse -File -Force)
    $rows = @()

    foreach ($f in $files) {
        $base = [System.IO.Path]::GetFullPath($RootPath)
        if (-not $base.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $base += [System.IO.Path]::DirectorySeparatorChar
        }
        $full = [System.IO.Path]::GetFullPath($f.FullName)
        $rel = $full.Substring($base.Length) -replace '\\','/'
        $rows += [pscustomobject]@{
            RelativePath = $rel
            FullPath     = $f.FullName
            Length       = [int64]$f.Length
        }
    }

    return @($rows)
}

function Test-ContentPagePath {
    param([string]$RelPath)
    $p = $RelPath.ToLowerInvariant()
    if ($p -match '^src/(posts|hubs|pages)/.+\.(md|html|njk)$') { return $true }
    if ($p -match '^src/.+\.(md|html|njk)$' -and $p -notmatch '^src/_') { return $true }
    return $false
}

function Get-TitleAndDescriptionFlags {
    param([string]$FilePath)

    $raw = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8
    $hasTitle = $false
    $hasDescription = $false

    if ($raw -match '(?ms)^---\s*(.*?)\s*---') {
        $fm = $Matches[1]
        if ($fm -match '(?im)^\s*title\s*:') { $hasTitle = $true }
        if ($fm -match '(?im)^\s*description\s*:') { $hasDescription = $true }
        if (-not $hasDescription -and $fm -match '(?im)^\s*excerpt\s*:') { $hasDescription = $true }
    }

    return [pscustomobject]@{
        HasTitle = $hasTitle
        HasDescription = $hasDescription
    }
}

function Get-InternalLinks {
    param(
        [string]$RawText,
        [string]$SourceRelPath
    )

    $links = New-Object System.Collections.Generic.List[string]

    $rx1 = [regex]'\[[^\]]+\]\((?!https?:|mailto:|tel:|#)([^)\s]+)\)'
    $rx2 = [regex]'href=["''](?!https?:|mailto:|tel:|#)([^"''>]+)["'']'

    foreach ($m in $rx1.Matches($RawText)) {
        $links.Add($m.Groups[1].Value) | Out-Null
    }
    foreach ($m in $rx2.Matches($RawText)) {
        $links.Add($m.Groups[1].Value) | Out-Null
    }

    return @($links | Select-Object -Unique)
}

function Resolve-SiteLinkCandidatePaths {
    param([string]$Link)

    $candidatePaths = New-Object System.Collections.Generic.List[string]
    $clean = ($Link -split '[?#]')[0].Trim()

    if ([string]::IsNullOrWhiteSpace($clean)) { return @() }

    if ($clean.StartsWith('/')) {
        $trim = $clean.TrimStart('/')
        if ([string]::IsNullOrWhiteSpace($trim)) {
            $candidatePaths.Add("src/index.md") | Out-Null
            $candidatePaths.Add("src/index.html") | Out-Null
            $candidatePaths.Add("src/index.njk") | Out-Null
            return @($candidatePaths | Select-Object -Unique)
        }

        $candidatePaths.Add(("src/{0}" -f $trim.TrimEnd('/'))) | Out-Null
        $candidatePaths.Add(("src/{0}/index.md" -f $trim.TrimEnd('/'))) | Out-Null
        $candidatePaths.Add(("src/{0}/index.html" -f $trim.TrimEnd('/'))) | Out-Null
        $candidatePaths.Add(("src/{0}/index.njk" -f $trim.TrimEnd('/'))) | Out-Null

        if ($trim -notmatch '\.[A-Za-z0-9]+$') {
            $candidatePaths.Add(("src/{0}.md" -f $trim.TrimEnd('/'))) | Out-Null
            $candidatePaths.Add(("src/{0}.html" -f $trim.TrimEnd('/'))) | Out-Null
            $candidatePaths.Add(("src/{0}.njk" -f $trim.TrimEnd('/'))) | Out-Null
        }
    }

    return @($candidatePaths | ForEach-Object { ($_ -replace '\\','/').ToLowerInvariant() } | Select-Object -Unique)
}

function Add-Issue {
    param(
        [System.Collections.Generic.List[object]]$Issues,
        [string]$Repo,
        [string]$Severity,
        [string]$Code,
        [string]$Path,
        [string]$Message
    )

    $Issues.Add([ordered]@{
        repo = $Repo
        severity = $Severity
        code = $Code
        path = $Path
        message = $Message
    }) | Out-Null
}

function ConvertTo-HtmlSafe {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

$allIssues = New-Object System.Collections.Generic.List[object]
$repoSummaries = New-Object System.Collections.Generic.List[object]

foreach ($repo in $repos) {
    Write-Output "Auditing $repo"

    $safeName = $repo.Replace('/','_')
    $repoWorkDir = New-WorkDir -BaseName $safeName
    $zipPath = Join-Path $repoWorkDir "repo.zip"
    $extractPath = Join-Path $repoWorkDir "repo_extract"

    try {
        $zipUrl = "https://api.github.com/repos/$repo/zipball"

        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -Headers @{
            Authorization = "Bearer $env:GITHUB_TOKEN"
            "User-Agent"  = "github-actions"
            Accept        = "application/vnd.github+json"
        }

        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

        $repoRoot = Get-RepoRoot -ExtractPath $extractPath
        $rows = @(Get-RelativePaths -RootPath $repoRoot)
        $relSet = @{}
        foreach ($row in $rows) {
            $relSet[$row.RelativePath.ToLowerInvariant()] = $true
        }

        $contentRows = @($rows | Where-Object { Test-ContentPagePath -RelPath $_.RelativePath })
        $postCount = @($rows | Where-Object { $_.RelativePath -match '^src/posts/' }).Count
        $hubCount  = @($rows | Where-Object { $_.RelativePath -match '^src/hubs/' }).Count
        $workflowCount = @($rows | Where-Object { $_.RelativePath -match '^\.github/workflows/' }).Count

        $incoming = @{}
        foreach ($cr in $contentRows) {
            $incoming[$cr.RelativePath.ToLowerInvariant()] = 0
        }

        foreach ($cr in $contentRows) {
            $raw = Get-Content -LiteralPath $cr.FullPath -Raw -Encoding UTF8
            $td = Get-TitleAndDescriptionFlags -FilePath $cr.FullPath

            if (-not $td.HasTitle) {
                Add-Issue -Issues $allIssues -Repo $repo -Severity "medium" -Code "MISSING_TITLE" -Path $cr.RelativePath -Message "Content page has no front-matter title."
            }
            if (-not $td.HasDescription) {
                Add-Issue -Issues $allIssues -Repo $repo -Severity "low" -Code "MISSING_DESCRIPTION" -Path $cr.RelativePath -Message "Content page has no front-matter description/excerpt."
            }

            $links = @(Get-InternalLinks -RawText $raw -SourceRelPath $cr.RelativePath)
            foreach ($lnk in $links) {
                $candidates = @(Resolve-SiteLinkCandidatePaths -Link $lnk)
                if ($candidates.Count -gt 0) {
                    $exists = $false
                    foreach ($cand in $candidates) {
                        if ($relSet.ContainsKey($cand)) {
                            $exists = $true
                            if ($incoming.ContainsKey($cand)) {
                                $incoming[$cand] = [int]$incoming[$cand] + 1
                            }
                            break
                        }
                    }
                    if (-not $exists) {
                        Add-Issue -Issues $allIssues -Repo $repo -Severity "high" -Code "BROKEN_INTERNAL_LINK" -Path $cr.RelativePath -Message ("Internal link target not found: {0}" -f $lnk)
                    }
                }
            }
        }

        foreach ($cr in $contentRows) {
            $key = $cr.RelativePath.ToLowerInvariant()
            if ($incoming.ContainsKey($key)) {
                $count = [int]$incoming[$key]
                $allowRoot = $cr.RelativePath -match '^src/(index\.(md|html|njk)|search\.(md|html|njk)|start-here|tools|news|hubs/)'
                if ($count -eq 0 -and -not $allowRoot) {
                    Add-Issue -Issues $allIssues -Repo $repo -Severity "medium" -Code "ORPHAN_PAGE" -Path $cr.RelativePath -Message "Content page has no detected inbound internal links."
                }
            }
        }

        if ($repo -like "*/automation-kb") {
            $base64Candidates = @($rows | Where-Object {
                $_.RelativePath -match '^src/.+\.(md|html|njk|xml|txt)$' -and $_.Length -gt 100
            } | Select-Object -First 30)

            foreach ($bc in $base64Candidates) {
                try {
                    $raw = Get-Content -LiteralPath $bc.FullPath -Raw -Encoding UTF8
                    if ($raw -match '^[A-Za-z0-9+/=\r\n]{200,}$') {
                        Add-Issue -Issues $allIssues -Repo $repo -Severity "high" -Code "BASE64_LIKE_CONTENT" -Path $bc.RelativePath -Message "File looks like base64/plaintext corruption."
                    }
                }
                catch {}
            }
        }

        $repoIssues = @($allIssues | Where-Object { $_.repo -eq $repo })

        $summary = [ordered]@{
            repo = $repo
            status = "OK"
            file_count = $rows.Count
            content_pages = $contentRows.Count
            posts = $postCount
            hubs = $hubCount
            workflows = $workflowCount
            issues_total = $repoIssues.Count
            issues_high = @($repoIssues | Where-Object { $_.severity -eq "high" }).Count
            issues_medium = @($repoIssues | Where-Object { $_.severity -eq "medium" }).Count
            issues_low = @($repoIssues | Where-Object { $_.severity -eq "low" }).Count
            sampled_paths = @($rows | Select-Object -First 50 -ExpandProperty RelativePath)
            timestamp = (Get-Date).ToString("s")
        }

        $repoSummaries.Add($summary) | Out-Null
        $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $reportsDir "$safeName.json") -Encoding UTF8
    }
    catch {
        $err = [ordered]@{
            repo = $repo
            status = "FAIL"
            error = $_.Exception.Message
            timestamp = (Get-Date).ToString("s")
        }

        $repoSummaries.Add($err) | Out-Null
        $err | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $reportsDir "$safeName.error.json") -Encoding UTF8
        Add-Issue -Issues $allIssues -Repo $repo -Severity "high" -Code "REPO_FETCH_FAIL" -Path "" -Message $_.Exception.Message
    }
    finally {
        if (Test-Path -LiteralPath $repoWorkDir) {
            Remove-Item -LiteralPath $repoWorkDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$summaryPath = Join-Path $reportsDir "summary.json"
$issuesPath = Join-Path $reportsDir "issues.json"
$structurePath = Join-Path $reportsDir "structure.json"
$htmlPath = Join-Path $reportsDir "report.html"

$summaryObj = [ordered]@{
    generated_at = (Get-Date).ToString("s")
    repo_count = $repoSummaries.Count
    repos_ok = @($repoSummaries | Where-Object { $_.status -eq "OK" }).Count
    repos_fail = @($repoSummaries | Where-Object { $_.status -eq "FAIL" }).Count
    issues_total = $allIssues.Count
    issues_high = @($allIssues | Where-Object { $_.severity -eq "high" }).Count
    issues_medium = @($allIssues | Where-Object { $_.severity -eq "medium" }).Count
    issues_low = @($allIssues | Where-Object { $_.severity -eq "low" }).Count
}

$summaryObj | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
@($allIssues) | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $issuesPath -Encoding UTF8
@($repoSummaries) | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $structurePath -Encoding UTF8

$htmlRows = New-Object System.Collections.Generic.List[string]
$htmlRows.Add('<!doctype html>') | Out-Null
$htmlRows.Add('<html><head><meta charset="utf-8"><title>SITE AUDIT REPORT</title><style>body{font-family:Arial,sans-serif;margin:24px;color:#222}table{border-collapse:collapse;width:100%;margin:16px 0}th,td{border:1px solid #ccc;padding:8px;text-align:left}th{background:#f4f4f4}.high{color:#b00020;font-weight:bold}.medium{color:#b26a00;font-weight:bold}.low{color:#555}.ok{color:#0a7b34;font-weight:bold}.fail{color:#b00020;font-weight:bold}code{background:#f5f5f5;padding:2px 4px}</style></head><body>') | Out-Null
$htmlRows.Add('<h1>SITE AUDIT REPORT</h1>') | Out-Null
$htmlRows.Add(("<p><b>Generated:</b> {0}</p>" -f (ConvertTo-HtmlSafe $summaryObj.generated_at))) | Out-Null
$htmlRows.Add(("<p><b>Repos:</b> {0} | <b>OK:</b> {1} | <b>FAIL:</b> {2}</p>" -f $summaryObj.repo_count, $summaryObj.repos_ok, $summaryObj.repos_fail)) | Out-Null
$htmlRows.Add(("<p><b>Issues:</b> total {0} | high {1} | medium {2} | low {3}</p>" -f $summaryObj.issues_total, $summaryObj.issues_high, $summaryObj.issues_medium, $summaryObj.issues_low)) | Out-Null)

$htmlRows.Add('<h2>Repository Summary</h2><table><tr><th>Repo</th><th>Status</th><th>Files</th><th>Content Pages</th><th>Posts</th><th>Hubs</th><th>Issues</th></tr>') | Out-Null
foreach ($r in $repoSummaries) {
    $statusClass = if ($r.status -eq "OK") { "ok" } else { "fail" }
    $htmlRows.Add(("<tr><td><code>{0}</code></td><td class=""{1}"">{2}</td><td>{3}</td><td>{4}</td><td>{5}</td><td>{6}</td><td>{7}</td></tr>" -f
        (ConvertTo-HtmlSafe $r.repo),
        $statusClass,
        (ConvertTo-HtmlSafe $r.status),
        $(if ($null -ne $r.file_count) { $r.file_count } else { "" }),
        $(if ($null -ne $r.content_pages) { $r.content_pages } else { "" }),
        $(if ($null -ne $r.posts) { $r.posts } else { "" }),
        $(if ($null -ne $r.hubs) { $r.hubs } else { "" }),
        $(if ($null -ne $r.issues_total) { $r.issues_total } else { (ConvertTo-HtmlSafe $r.error) })
    )) | Out-Null
}
$htmlRows.Add('</table>') | Out-Null

$htmlRows.Add('<h2>Issues</h2><table><tr><th>Severity</th><th>Repo</th><th>Code</th><th>Path</th><th>Message</th></tr>') | Out-Null
foreach ($i in $allIssues) {
    $sev = [string]$i.severity
    $htmlRows.Add(("<tr><td class=""{0}"">{1}</td><td><code>{2}</code></td><td>{3}</td><td><code>{4}</code></td><td>{5}</td></tr>" -f
        $sev,
        (ConvertTo-HtmlSafe $sev),
        (ConvertTo-HtmlSafe $i.repo),
        (ConvertTo-HtmlSafe $i.code),
        (ConvertTo-HtmlSafe $i.path),
        (ConvertTo-HtmlSafe $i.message)
    )) | Out-Null
}
$htmlRows.Add('</table>') | Out-Null

$htmlRows.Add('</body></html>') | Out-Null
$htmlRows -join "`n" | Set-Content -LiteralPath $htmlPath -Encoding UTF8

if (-not (Get-ChildItem -LiteralPath $reportsDir -Force | Select-Object -First 1)) {
    "EMPTY REPORT" | Set-Content -LiteralPath "$reportsDir/empty.txt" -Encoding UTF8
}
