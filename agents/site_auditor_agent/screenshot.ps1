function Get-AvailableBrowserPath {
    $candidates = @(
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe",
        "$env:LocalAppData\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
        "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
    )

    foreach ($path in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) { return $path }
    }

    foreach ($cmdName in @('msedge.exe','chrome.exe')) {
        $cmd = Get-Command $cmdName -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
            return $cmd.Source
        }
    }

    return $null
}

function Invoke-ScreenshotCapture {
    param(
        $Inventory,
        $RenderAudit,
        [string]$WorkPath,
        [int]$MaxScreenshots
    )

    if (-not $MaxScreenshots -or $MaxScreenshots -lt 1) { $MaxScreenshots = 5 }

    $browser = Get-AvailableBrowserPath
    if (-not $browser) {
        return @([PSCustomObject]@{
            status = 'SKIPPED_BROWSER_NOT_FOUND'
            reason = 'BROWSER_NOT_FOUND'
        })
    }

    $shotDir = Join-Path $WorkPath 'screens'
    $stderrDir = Join-Path $WorkPath 'screen_err'
    if (Test-Path -LiteralPath $shotDir) { Remove-Item -LiteralPath $shotDir -Recurse -Force }
    if (Test-Path -LiteralPath $stderrDir) { Remove-Item -LiteralPath $stderrDir -Recurse -Force }
    New-Item -ItemType Directory -Path $shotDir -Force | Out-Null
    New-Item -ItemType Directory -Path $stderrDir -Force | Out-Null

    $renderOk = @{}
    foreach ($r in @($RenderAudit)) {
        if ($r.route) { $renderOk[$r.route] = ($r.status -eq 'OK') }
    }

    $targets = @($Inventory | Where-Object { $_.is_publishable } | Select-Object -First $MaxScreenshots)
    $results = @()

    foreach ($item in $targets) {
        if ($renderOk.ContainsKey($item.route) -and -not $renderOk[$item.route]) {
            $results += [PSCustomObject]@{
                route      = $item.route
                full_url   = $item.full_url
                local_path = $null
                status     = 'SKIPPED_HTTP_FAIL'
            }
            continue
        }

        $safeName = (($item.route -replace '[\\/:*?"<>|]','_').Trim('_'))
        if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'home' }
        $outFile = Join-Path $shotDir ($safeName + '.png')
        $errFile = Join-Path $stderrDir ($safeName + '.stderr.txt')

        try {
            & $browser `
                --headless `
                --disable-gpu `
                --hide-scrollbars `
                --window-size=1440,2200 `
                --disable-extensions `
                --disable-background-networking `
                --screenshot=$outFile `
                $item.full_url 2> $errFile | Out-Null

            $ok = Test-Path -LiteralPath $outFile
            $stderrText = ''
            if (Test-Path -LiteralPath $errFile) {
                $stderrText = (Get-Content -LiteralPath $errFile -Raw -Encoding UTF8)
            }

            $results += [PSCustomObject]@{
                route         = $item.route
                full_url      = $item.full_url
                local_path    = $(if($ok){$outFile}else{$null})
                status        = $(if($ok){'OK'}else{'FAILED'})
                stderr_noise  = $(if([string]::IsNullOrWhiteSpace($stderrText)){'NO'}else{'YES'})
                stderr_file   = $(if(Test-Path -LiteralPath $errFile){$errFile}else{$null})
            }
        }
        catch {
            $results += [PSCustomObject]@{
                route      = $item.route
                full_url   = $item.full_url
                local_path = $null
                status     = 'FAILED'
                reason     = $_.Exception.Message
            }
        }
    }

    return $results
}
