\
$ErrorActionPreference = "Stop"

$reportsDir = "reports"
New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null

$reposPath = "./agents/gh_batch/site_auditor_cloud/repos.fixed.json"
if (-not (Test-Path -LiteralPath $reposPath)) {
    "repos.fixed.json not found: $reposPath" | Set-Content "$reportsDir/bootstrap.error.txt"
    exit 1
}

$repos = Get-Content -LiteralPath $reposPath -Raw | ConvertFrom-Json

$workDir = Join-Path $PWD "tmp_site_auditor"
New-Item -ItemType Directory -Force -Path $workDir | Out-Null

foreach ($repo in $repos) {
    Write-Output "Auditing $repo"

    $safeName = $repo.Replace('/','_')
    $repoWorkDir = Join-Path $workDir $safeName
    $zipPath = Join-Path $repoWorkDir "repo.zip"
    $extractPath = Join-Path $repoWorkDir "repo_extract"

    try {
        if (Test-Path -LiteralPath $repoWorkDir) {
            Remove-Item -LiteralPath $repoWorkDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Force -Path $repoWorkDir | Out-Null

        $zipUrl = "https://api.github.com/repos/$repo/zipball"

        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -Headers @{
            Authorization = "Bearer $env:GITHUB_TOKEN"
            "User-Agent"  = "github-actions"
            Accept        = "application/vnd.github+json"
        }

        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

        $allDirs = @(Get-ChildItem -LiteralPath $extractPath -Directory -Force)
        $repoRoot = $extractPath
        if ($allDirs.Count -eq 1) {
            $repoRoot = $allDirs[0].FullName
        }

        $files = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Force)
        $topFiles = @($files | ForEach-Object {
            $base = [System.IO.Path]::GetFullPath($repoRoot)
            $full = [System.IO.Path]::GetFullPath($_.FullName)
            if (-not $base.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
                $base += [System.IO.Path]::DirectorySeparatorChar
            }
            $rel = $full.Substring($base.Length) -replace '\\','/'
            $rel
        } | Select-Object -First 50)

        $report = [ordered]@{
            repo = $repo
            status = "OK"
            file_count = $files.Count
            sampled_paths = $topFiles
            timestamp = (Get-Date).ToString("s")
        }

        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $reportsDir "$safeName.json") -Encoding UTF8
    }
    catch {
        $err = [ordered]@{
            repo = $repo
            status = "FAIL"
            error = $_.Exception.Message
            timestamp = (Get-Date).ToString("s")
        }

        $err | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $reportsDir "$safeName.error.json") -Encoding UTF8
    }
    finally {
        if (Test-Path -LiteralPath $repoWorkDir) {
            Remove-Item -LiteralPath $repoWorkDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if (-not (Get-ChildItem -LiteralPath $reportsDir -Force | Select-Object -First 1)) {
    "EMPTY REPORT" | Set-Content -LiteralPath "$reportsDir/empty.txt" -Encoding UTF8
}
