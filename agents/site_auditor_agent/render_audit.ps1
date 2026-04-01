function Get-CanonicalFromHtml {
    param([string]$Html)

    if ([string]::IsNullOrWhiteSpace($Html)) { return $null }
    $m = [regex]::Match($Html, '<link[^>]+rel=["'']canonical["''][^>]+href=["'']([^"'']+)["'']', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return $null
}

function Get-TitleFromHtml {
    param([string]$Html)

    if ([string]::IsNullOrWhiteSpace($Html)) { return $null }
    $m = [regex]::Match($Html, '<title>(.*?)</title>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($m.Success) { return ($m.Groups[1].Value -replace '\s+',' ').Trim() }
    return $null
}

function Get-DescriptionFromHtml {
    param([string]$Html)

    if ([string]::IsNullOrWhiteSpace($Html)) { return $null }
    $m = [regex]::Match($Html, '<meta[^>]+name=["'']description["''][^>]+content=["'']([^"'']+)["'']', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return $null
}

function Invoke-RenderAudit {
    param(
        $Inventory,
        [object]$Config
    )

    $pages = @($Inventory | Where-Object { $_.is_publishable })
    $timeoutSec = [int]$Config.render_timeout_sec
    if ($timeoutSec -lt 5) { $timeoutSec = 20 }

    $maxPages = [int]$Config.max_render_pages
    if ($maxPages -lt 1) { $maxPages = 100 }

    $results = @()

    foreach ($item in ($pages | Select-Object -First $maxPages)) {
        try {
            $resp = Invoke-WebRequest -Uri $item.full_url -UseBasicParsing -TimeoutSec $timeoutSec
            $html = $resp.Content
            $statusCode = [int]$resp.StatusCode
            $finalUrl = $resp.BaseResponse.ResponseUri.AbsoluteUri

            $results += [PSCustomObject]@{
                route            = $item.route
                full_url         = $item.full_url
                status_code      = $statusCode
                final_url        = $finalUrl
                title_live       = Get-TitleFromHtml -Html $html
                description_live = Get-DescriptionFromHtml -Html $html
                canonical_live   = Get-CanonicalFromHtml -Html $html
                status           = $(if ($statusCode -ge 200 -and $statusCode -lt 400) { 'OK' } else { 'FAILED' })
            }
        }
        catch {
            $statusCode = $null
            try {
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
            } catch {}
            $results += [PSCustomObject]@{
                route            = $item.route
                full_url         = $item.full_url
                status_code      = $statusCode
                final_url        = $null
                title_live       = $null
                description_live = $null
                canonical_live   = $null
                status           = 'FAILED'
                reason           = $_.Exception.Message
            }
        }
    }

    return $results
}
