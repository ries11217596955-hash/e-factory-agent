$ErrorActionPreference = 'Stop'

$repos = Get-Content ./agents/site_auditor_cloud/repos.fixed.json | ConvertFrom-Json

$reportsDir = "reports"
New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null

foreach ($repo in $repos) {
    Write-Output "Auditing $repo"

    $zipUrl = "https://api.github.com/repos/$repo/zipball"
    $zipPath = "$env:TEMP\repo.zip"
    $extractPath = "$env:TEMP\repo_extract"

    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -Headers @{ Authorization = "Bearer $env:GITHUB_TOKEN" }

    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    $files = Get-ChildItem -Path $extractPath -Recurse -File
    $count = $files.Count

    $report = @{
        repo = $repo
        file_count = $count
        timestamp = (Get-Date)
    }

    $report | ConvertTo-Json | Set-Content "$reportsDir/$($repo.Replace('/','_')).json"

    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
}
