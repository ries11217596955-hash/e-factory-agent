function Get-FirstOrNull {
    param(
        [Parameter(Mandatory = $false)]
        [object]$Collection
    )

    $items = @($Collection)
    if ($items.Count -eq 0) {
        return $null
    }

    return $items | Select-Object -First 1
}

function Test-HasItems {
    param(
        [Parameter(Mandatory = $false)]
        [object]$Collection
    )

    return (@($Collection).Count -gt 0)
}

function Resolve-RepresentativeExamples {
    param(
        [Parameter(Mandatory = $false)]
        [object]$Examples,
        [int]$MaxItems = 3,
        [string]$FallbackRoute = '_none',
        [string]$FallbackSurface = 'UNKNOWN',
        [string]$FallbackEvidence = 'No representative example in sampled scope.'
    )

    $safeExamples = @($Examples | Select-Object -First $MaxItems)
    if ($safeExamples.Count -gt 0) {
        return @($safeExamples)
    }

    return @([ordered]@{
            route = [string]$FallbackRoute
            surface_type = [string]$FallbackSurface
            evidence = [string]$FallbackEvidence
        })
}

function Resolve-DominantSurface {
    param(
        [Parameter(Mandatory = $false)]
        [object]$PageVerdicts
    )

    $dominantSurface = @(
        @($PageVerdicts) |
        Group-Object -Property surface_type |
        Sort-Object -Property Count -Descending |
        Select-Object -First 1
    )
    $firstSurface = Get-FirstOrNull -Collection $dominantSurface
    if ($null -eq $firstSurface -or [string]::IsNullOrWhiteSpace([string]$firstSurface.Name)) {
        return 'UNKNOWN'
    }

    return Resolve-SurfaceType -SurfaceType ([string]$firstSurface.Name)
}
