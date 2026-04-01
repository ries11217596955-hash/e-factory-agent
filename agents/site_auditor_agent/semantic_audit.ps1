
function Test-SkipSemanticChecks {
    param($Page)

    if (-not $Page.is_publishable) { return $true }
    if ([string]::IsNullOrWhiteSpace($Page.route)) { return $true }
    if ($Page.page_type -like 'special_*') { return $true }
    if ($Page.page_type -eq 'disabled_template') { return $true }
    return $false
}

function Invoke-SemanticAudit {
    param($Inventory)

    $issues = @()
    $pages = @($Inventory | Where-Object { $_.is_publishable })

    foreach ($p in $pages) {
        if (Test-SkipSemanticChecks -Page $p) { continue }

        if (-not $p.title) {
            $issues += [PSCustomObject]@{
                type = 'TITLE_MISSING'
                severity = 'P1'
                file = $p.file
                route = $p.route
                likely_fix = 'add title or first H1'
            }
        }
        elseif ($p.title.Length -lt 12) {
            $issues += [PSCustomObject]@{
                type = 'TITLE_TOO_SHORT'
                severity = 'P3'
                file = $p.file
                route = $p.route
                value = $p.title
                likely_fix = 'expand title for clarity'
            }
        }
        elseif ($p.title.Length -gt 70) {
            $issues += [PSCustomObject]@{
                type = 'TITLE_TOO_LONG'
                severity = 'P3'
                file = $p.file
                route = $p.route
                value = $p.title
                likely_fix = 'shorten title'
            }
        }

        if (-not $p.description) {
            $issues += [PSCustomObject]@{
                type = 'META_DESC_MISSING'
                severity = 'P2'
                file = $p.file
                route = $p.route
                likely_fix = 'add description or excerpt'
            }
        }
        elseif ($p.description.Length -lt 50) {
            $issues += [PSCustomObject]@{
                type = 'META_DESC_TOO_SHORT'
                severity = 'P3'
                file = $p.file
                route = $p.route
                value = $p.description
                likely_fix = 'expand description'
            }
        }
        elseif ($p.description.Length -gt 190) {
            $issues += [PSCustomObject]@{
                type = 'META_DESC_TOO_LONG'
                severity = 'P3'
                file = $p.file
                route = $p.route
                value = $p.description
                likely_fix = 'shorten description'
            }
        }
    }

    $dupeGroups = $pages |
        Where-Object { -not (Test-SkipSemanticChecks -Page $_) } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.title) } |
        Group-Object -Property title |
        Where-Object { $_.Count -gt 1 }
    foreach ($grp in $dupeGroups) {
        foreach ($item in $grp.Group) {
            $issues += [PSCustomObject]@{
                type = 'TITLE_DUPLICATE'
                severity = 'P2'
                file = $item.file
                route = $item.route
                value = $grp.Name
                likely_fix = 'differentiate page title'
            }
        }
    }

    return $issues
}
