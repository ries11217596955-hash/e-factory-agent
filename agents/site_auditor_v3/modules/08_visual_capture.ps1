function Get-PageHtml {
    param([string]$Url)
    try {
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
        return $resp.Content
    } catch {
        return $null
    }
}

function Extract-VisualSignals {
    param([string]$Html)

    if (-not $Html) {
        return @{
            has_title = $false
            has_h1 = $false
            has_images = $false
            word_count = 0
            has_cta = $false
        }
    }

    return @{
        has_title = ($Html -match "<title>")
        has_h1 = ($Html -match "<h1")
        has_images = ($Html -match "<img")
        word_count = (($Html -replace "<[^>]+>", " ") -split "\s+" | Where-Object { $_ }).Count
        has_cta = ($Html -match "buy|start|signup|try")
    }
}

function Invoke-Module08VisualCapture {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $records = @($PipelineState.capture.records)
    $visual = @()
    $i = 1

    foreach ($r in $records) {
        $html = Get-PageHtml -Url $r.url
        $signals = Extract-VisualSignals -Html $html

        $visual += @{
            visual_id = ("V{0:D3}" -f $i)
            route_id = $r.route_id
            url = $r.url
            status = if ($html) { "SUCCESS" } else { "FAIL" }
            capture_method = "HTTP_HTML"
            signals = $signals
            quality = if ($html) { "BASELINE" } else { "WEAK" }
        }

        $i++
    }

    $success = @($visual | Where-Object { $_.status -eq "SUCCESS" }).Count

    return @{
        status = "OK"
        data = @{
            visual_records = $visual
            totals = @{
                requested = $visual.Count
                succeeded = $success
                failed = ($visual.Count - $success)
            }
        }
    }
}
