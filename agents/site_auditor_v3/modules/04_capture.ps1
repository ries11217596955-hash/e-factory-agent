function Invoke-Module04Capture {
    param(
        [Parameter(Mandatory)]$PipelineState,
        [Parameter(Mandatory)]$InputData
    )

    $selection = $InputData.selection
    $selected = @($selection.selected)

    $records = @()
    $i = 1

    foreach ($s in $selected) {
        $path = if ($s.path) { [string]$s.path } else { "/" }

        $signals = @{
            has_url = -not [string]::IsNullOrWhiteSpace([string]$s.url)
            has_route_id = -not [string]::IsNullOrWhiteSpace([string]$s.route_id)
            path_depth = @($path.Trim("/") -split "/" | Where-Object { $_ }).Count
            is_root = ($path -eq "/")
        }

        $quality = if ($signals.has_url -and $signals.has_route_id) { "BASELINE" } else { "WEAK" }

        $records += @{
            capture_id = ("C{0:D3}" -f $i)
            route_id = $s.route_id
            url = $s.url
            path = $path
            status = "SUCCESS"
            capture_method = "ROUTE_METADATA"
            content_type = "structured_route_baseline"
            evidence = @{
                route_id = $s.route_id
                url = $s.url
                path = $path
                eligible = $s.eligible
            }
            signals = $signals
            quality = $quality
        }

        $i++
    }

    $failed = @($records | Where-Object { $_.quality -eq "WEAK" }).Count
    $succeeded = @($records | Where-Object { $_.status -eq "SUCCESS" }).Count

    return @{
        status = "OK"
        data = @{
            records = $records
            totals = @{
                requested = $records.Count
                succeeded = $succeeded
                failed = $failed
            }
        }
    }
}
