Set-StrictMode -Version Latest

function New-SafeList {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeName
    )

    return New-Object ("System.Collections.Generic.List[{0}]" -f $TypeName)
}

function New-SafeHashSet {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeName,
        [Parameter()]
        [System.Collections.IEqualityComparer]$Comparer
    )

    $genericTypeName = "System.Collections.Generic.HashSet[{0}]" -f $TypeName
    if ($null -ne $Comparer) {
        return New-Object $genericTypeName -ArgumentList (, $Comparer)
    }

    return New-Object $genericTypeName
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
