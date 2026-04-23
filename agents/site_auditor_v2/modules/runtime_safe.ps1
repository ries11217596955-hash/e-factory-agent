Set-StrictMode -Version Latest

function New-SafeList {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeName
    )

    return New-Object ("System.Collections.Generic.List[{0}]" -f $TypeName)
}

function New-CaseInsensitiveKeyMap {
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

function Resolve-SafeUriBuilder {
    param(
        [Parameter(Mandatory = $true)]
        [Object]$Source
    )

    return New-Object System.UriBuilder -ArgumentList $Source
}

function Resolve-SafeUriJoin {
    param(
        [Parameter(Mandatory = $true)]
        [Uri]$BaseUri,
        [Parameter(Mandatory = $true)]
        [string]$RelativeOrAbsolute
    )

    return New-Object System.Uri -ArgumentList $BaseUri, $RelativeOrAbsolute
}
