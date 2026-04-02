$ErrorActionPreference = "Stop"

$reportsDir = "reports"
New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null

$repos = Get-Content ./agents/gh_batch/site_auditor_cloud/repos.fixed.json | ConvertFrom-Json

foreach ($repo in $repos) {
    Write-Output "Auditing $repo"

    try {
        $zipUrl = "https://api.github.com/repos/$repo/zipball"
        $zipPath = "$env:TEMP/repo.zip"
        $extractPath = "$env:TEMP/repo_extract"

        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -Headers @{
            Authorization = "Bearer $env:GITHUB_TOKEN"
            "User-Agent" = "github-actions"
        }

        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

        $files = Get-ChildItem -Path $extractPath -Recurse -File
        $count = $files.Count

        $report = @{
            repo = $repo
            file_count = $count
            status = "OK"
            timestamp = (Get-Date)
        }

        $report | ConvertTo-Json | Set-Content "$reportsDir/$($repo.Replace('/','_')).json"

        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    catch {
        $err = @{
            repo = $repo
            status = "FAIL"
            error = $_.Exception.Message
            timestamp = (Get-Date)
        }

        $err | ConvertTo-Json | Set-Content "$reportsDir/$($repo.Replace('/','_')).error.json"
    }
}

# гарантируем хотя бы один файл
if (-not (Get-ChildItem $reportsDir)) {
    "EMPTY REPORT" | Set-Content "$reportsDir/empty.txt"
}
