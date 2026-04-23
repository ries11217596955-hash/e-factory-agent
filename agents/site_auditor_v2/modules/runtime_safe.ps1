Set-StrictMode -Version Latest

function New-SafeList {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeName
    )

    return New-Object ("System.Collections.Generic.List[{0}]" -f $TypeName)
}

function New-CaseInsensitiveKeyMap {
    # CONTRACT: this structure is a case-insensitive key-map (normalized-string -> value),
    # not a HashSet. Callers must use Add-KeyIfMissing/Test-KeyExists/Get-KeyMapKeys/Get-KeyMapCount
    # and must not call raw .Add(value)/.Contains(value) methods directly.
    return @{}
}

function Get-NormalizedKey {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Key
    )

    return $Key.Trim().ToLowerInvariant()
}

function Add-KeyIfMissing {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Map,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Key,
        [Parameter()]
        [Object]$Value = $true
    )

    $normalizedKey = Get-NormalizedKey -Key $Key
    if ([string]::IsNullOrWhiteSpace($normalizedKey)) {
        return $false
    }

    if ($Map.ContainsKey($normalizedKey)) {
        return $false
    }

    $Map[$normalizedKey] = $Value
    return $true
}

function Test-KeyExists {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Map,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Key
    )

    return $Map.ContainsKey((Get-NormalizedKey -Key $Key))
}

function Get-KeyMapKeys {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Map
    )

    return @($Map.Keys)
}

function Get-KeyMapCount {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Map
    )

    return [int]$Map.Count
}

function New-SafeUtf8NoBom {
    return New-Object System.Text.UTF8Encoding -ArgumentList $false
}

function ConvertTo-SafeAbsoluteUri {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$UriText
    )

    $candidate = $null
    if (-not [Uri]::TryCreate($UriText, [UriKind]::Absolute, [ref]$candidate) -or $null -eq $candidate) {
        throw "invalid absolute uri: $UriText"
    }

    return $candidate
}

function Resolve-SafeUri {
    param(
        [Parameter(Mandatory = $true)]
        [Uri]$BaseUri,
        [Parameter(Mandatory = $true)]
        [string]$RelativeOrAbsolute
    )

    $href = [string]$RelativeOrAbsolute
    if (-not [string]::IsNullOrWhiteSpace($href)) {
        $href = $href.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($href)) {
        throw "invalid uri reference: $RelativeOrAbsolute"
    }

    if ($href.StartsWith('#')) {
        throw "anchor-only uri reference: $RelativeOrAbsolute"
    }

    if ($href -match '^(?i)(mailto|tel|javascript):') {
        throw "unsupported scheme uri reference: $RelativeOrAbsolute"
    }

    $candidate = $null
    if ($href -match '^[a-z][a-z0-9+\-.]*:') {
        if (-not [Uri]::TryCreate($href, [UriKind]::Absolute, [ref]$candidate) -or $null -eq $candidate) {
            throw "invalid uri reference: $RelativeOrAbsolute"
        }

        if ($candidate.Scheme -notin @('http', 'https')) {
            throw "unsupported scheme uri reference: $RelativeOrAbsolute"
        }

        return $candidate
    }

    $reference = $href
    if ($href.StartsWith('//')) {
        $reference = "{0}:{1}" -f $BaseUri.Scheme, $href
    }

    if (-not [Uri]::TryCreate($BaseUri, $reference, [ref]$candidate) -or $null -eq $candidate) {
        throw "invalid uri reference: $RelativeOrAbsolute"
    }

    if ($candidate.Scheme -notin @('http', 'https')) {
        throw "unsupported scheme uri reference: $RelativeOrAbsolute"
    }

    return $candidate
}

function Get-NormalizedAbsoluteUriString {
    param(
        [Parameter(Mandatory = $true)]
        [Uri]$Uri,
        [string]$Path,
        [string]$Query = '',
        [string]$Fragment = ''
    )

    $safePath = if ([string]::IsNullOrWhiteSpace([string]$Path)) { '/' } else { [string]$Path }
    if (-not $safePath.StartsWith('/')) {
        $safePath = "/$safePath"
    }

    $builder = [System.Text.StringBuilder]::new()
    $null = $builder.Append($Uri.Scheme)
    $null = $builder.Append('://')
    $null = $builder.Append($Uri.Authority)
    $null = $builder.Append($safePath)

    if (-not [string]::IsNullOrWhiteSpace([string]$Query)) {
        $trimmedQuery = ([string]$Query).TrimStart('?')
        if (-not [string]::IsNullOrWhiteSpace($trimmedQuery)) {
            $null = $builder.Append('?')
            $null = $builder.Append($trimmedQuery)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Fragment)) {
        $trimmedFragment = ([string]$Fragment).TrimStart('#')
        if (-not [string]::IsNullOrWhiteSpace($trimmedFragment)) {
            $null = $builder.Append('#')
            $null = $builder.Append($trimmedFragment)
        }
    }

    return [string]$builder.ToString()
}

function Write-BootstrapStageTrace {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Stage
    )

    Write-Host "STAGE: $Stage"
}
