param(
    [string]$Root,
    [int]$MaxFiles = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DiscoveryFiles {
    param([string]$BaseRoot, [int]$Limit)

    if ([string]::IsNullOrWhiteSpace($BaseRoot) -or -not (Test-Path $BaseRoot -PathType Container)) {
        return @()
    }

    $priorityNames = @(
        'README.md','readme.md','package.json','package-lock.json','wrangler.toml','netlify.toml',
        'vercel.json','vite.config.js','vite.config.ts','astro.config.mjs','next.config.js',
        '.env','.env.production','.env.local','_headers','site.config.js'
    )

    $priorityFiles = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    foreach ($name in $priorityNames) {
        $found = Get-ChildItem -Path $BaseRoot -Recurse -File -Filter $name -ErrorAction SilentlyContinue |
            Sort-Object FullName |
            Select-Object -First 4
        foreach ($item in $found) {
            if (-not ($priorityFiles | Where-Object { $_.FullName -eq $item.FullName })) {
                $priorityFiles.Add($item)
            }
        }
    }

    $remaining = [Math]::Max(0, $Limit - $priorityFiles.Count)
    if ($remaining -le 0) {
        return @($priorityFiles | Select-Object -First $Limit)
    }

    $fallback = Get-ChildItem -Path $BaseRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -le 200000 } |
        Sort-Object FullName |
        Select-Object -First $remaining

    return @($priorityFiles + $fallback | Group-Object FullName | ForEach-Object { $_.Group[0] } | Select-Object -First $Limit)
}

function Select-BestUrl {
    param([string[]]$Candidates)

    if (-not $Candidates -or $Candidates.Count -eq 0) { return $null }

    $ranked = $Candidates | Sort-Object {
        $url = $_
        $rank = 100
        if ($url -match '^https://') { $rank -= 20 }
        if ($url -match 'localhost|127\.0\.0\.1') { $rank += 80 }
        if ($url -match '\.pages\.dev|\.vercel\.app|\.netlify\.app') { $rank -= 10 }
        if ($url -match '^http://') { $rank += 5 }
        $rank
    }, { $_ }

    return $ranked[0]
}

$files = Get-DiscoveryFiles -BaseRoot $Root -Limit $MaxFiles
$regex = 'https?://[A-Za-z0-9\-._~:/?#\[\]@!$&''()*+,;=%]+'
$all = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

foreach ($file in $files) {
    try {
        $matches = Select-String -Path $file.FullName -Pattern $regex -AllMatches -ErrorAction Stop
        foreach ($m in $matches) {
            foreach ($mm in $m.Matches) {
                $raw = [string]$mm.Value
                $clean = $raw.Trim().TrimEnd('"',"'",')',']','}','.',',',';')
                if ($clean -match '^https?://') {
                    $all.Add($clean)
                }
            }
        }
    }
    catch {
        $warnings.Add("Skipped unreadable file: $($file.FullName)")
    }
}

$unique = @($all | Group-Object | Sort-Object Name | ForEach-Object { $_.Name })
$best = Select-BestUrl -Candidates $unique
$alternatives = @($unique | Where-Object { $_ -ne $best } | Select-Object -First 5)
if ($unique.Count -gt 1) {
    $warnings.Add("Multiple URL candidates discovered; selected '$best'.")
}

@{
    discovered_url = $best
    candidates = $unique
    alternatives = $alternatives
    scanned_files = @($files | Select-Object -ExpandProperty FullName)
    warnings = @($warnings)
} | ConvertTo-Json -Depth 6
