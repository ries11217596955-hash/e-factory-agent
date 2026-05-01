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
        $records += @{
            capture_id = ("C{0:D3}" -f $i)
            route_id   = $s.route_id
            url        = $s.url
            status     = "SUCCESS"
        }
        $i++
    }

    return @{
        status = "OK"
        data = @{
            records = $records
            totals = @{
                requested = $records.Count
                succeeded = $records.Count
                failed    = 0
            }
        }
    }
}
