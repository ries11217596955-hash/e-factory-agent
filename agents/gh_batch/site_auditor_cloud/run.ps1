$ErrorActionPreference = "Stop"

$REPORT_DIR = "reports"
New-Item -ItemType Directory -Force -Path $REPORT_DIR | Out-Null

function Save-Json($path, $obj) {
    $obj | ConvertTo-Json -Depth 10 | Out-File -Encoding utf8 $path
}

try {
    $token = $env:GITHUB_TOKEN
    if (-not $token) {
        throw "GITHUB_TOKEN is empty"
    }

    $repos = Get-Content "agents/gh_batch/site_auditor_cloud/repos.fixed.json" | ConvertFrom-Json

    $results = @()

    foreach ($repo in $repos) {
        try {
            $url = "https://api.github.com/repos/$repo"
            $headers = @{
                Authorization = "token $token"
                "User-Agent" = "site-auditor"
            }

            $resp = Invoke-RestMethod -Uri $url -Headers $headers -Method Get

            $results += @{
                repo = $repo
                status = "ok"
                stars = $resp.stargazers_count
            }
        }
        catch {
            $results += @{
                repo = $repo
                status = "error"
                message = $_.Exception.Message
            }
        }
    }

    Save-Json "$REPORT_DIR/summary.json" $results
}
catch {
    Save-Json "$REPORT_DIR/error.json" @{
        error = $_.Exception.Message
    }
}

exit 0
