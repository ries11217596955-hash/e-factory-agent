Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ContractFieldValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Object) { return $null }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) {
        return $property.Value
    }

    return $null
}

function Set-ContractFieldValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $false)]
        [object]$Value
    )

    if ($Object -is [System.Collections.IDictionary]) {
        $Object[$Name] = $Value
        return
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) {
        $property.Value = $Value
        return
    }

    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
}

function Get-ContractNonEmptyString {
    param([Parameter(Mandatory = $false)][object]$Value)

    if ($null -eq $Value) { return $null }

    $stringValue = [string]$Value
    if ([string]::IsNullOrWhiteSpace($stringValue)) {
        return $null
    }

    return $stringValue.Trim()
}

function Normalize-FindingContract {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Findings,
        [Parameter(Mandatory = $true)]
        [string]$DiagnosticPath
    )

    $requiredTopLevel = @('type', 'severity', 'title', 'description', 'recommended_action')
    $missingFieldsByFinding = New-Object System.Collections.Generic.List[object]
    $normalizedFieldsCount = 0
    $normalizedFindings = New-Object System.Collections.Generic.List[object]

    for ($index = 0; $index -lt $Findings.Count; $index++) {
        $finding = $Findings[$index]
        if ($null -eq $finding) {
            $finding = [ordered]@{}
        }

        $findingId = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $finding -Name 'finding_id')
        if ($null -eq $findingId) {
            $findingId = "finding_{0:d3}" -f ($index + 1)
        }

        $missing = New-Object System.Collections.Generic.List[string]
        $issueType = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $finding -Name 'issue_type')
        if ($null -eq $issueType) {
            $issueType = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $finding -Name 'signal_type')
        }
        if ($null -eq $issueType) {
            $issueType = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $finding -Name 'type')
        }
        if ($null -eq $issueType) {
            $issueType = 'UNSPECIFIED_FINDING'
        }

        foreach ($field in $requiredTopLevel) {
            $existing = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $finding -Name $field)
            if ($null -ne $existing) { continue }

            $fallback = ''
            switch ($field) {
                'type' { $fallback = [string]$issueType }
                'severity' {
                    $priority = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $finding -Name 'priority')
                    $fallback = if ($null -ne $priority) { $priority } else { 'NONE' }
                }
                'title' {
                    $fallback = [string]$issueType
                }
                'description' {
                    $whyItMatters = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $finding -Name 'why_it_matters')
                    $evidenceText = Get-ContractNonEmptyString -Value (Get-ContractFieldValue -Object $finding -Name 'evidence_text')
                    if ($null -ne $whyItMatters) {
                        $fallback = $whyItMatters
                    }
                    elseif ($null -ne $evidenceText) {
                        $fallback = $evidenceText
                    }
                    else {
                        $fallback = "No description provided for $issueType."
                    }
                }
                'recommended_action' {
                    $fallback = ''
                }
            }

            Set-ContractFieldValue -Object $finding -Name $field -Value $fallback
            $null = $missing.Add($field)
            $normalizedFieldsCount += 1
        }

        $evidence = Get-ContractFieldValue -Object $finding -Name 'evidence'
        if ($null -eq $evidence) {
            $evidence = [ordered]@{
                evidence_refs = @()
            }
            Set-ContractFieldValue -Object $finding -Name 'evidence' -Value $evidence
            $null = $missing.Add('evidence')
            $normalizedFieldsCount += 1
        }

        $evidenceRefs = Get-ContractFieldValue -Object $evidence -Name 'evidence_refs'
        $needsEvidenceRefs = $false
        if ($null -eq $evidenceRefs) {
            $needsEvidenceRefs = $true
        }
        elseif (-not ($evidenceRefs -is [System.Array])) {
            $evidenceRefs = @($evidenceRefs)
            $needsEvidenceRefs = $true
        }

        if ($needsEvidenceRefs) {
            Set-ContractFieldValue -Object $evidence -Name 'evidence_refs' -Value @($evidenceRefs)
            $null = $missing.Add('evidence.evidence_refs')
            $normalizedFieldsCount += 1
        }

        if ($missing.Count -gt 0) {
            $missingFieldsByFinding.Add([ordered]@{
                    finding_id = [string]$findingId
                    missing_fields = @($missing.ToArray())
                })
        }

        $normalizedFindings.Add($finding)
    }

    $diagnostic = [ordered]@{
        total_findings = [int]$Findings.Count
        missing_fields_by_finding = @($missingFieldsByFinding.ToArray())
        normalized_fields_count = [int]$normalizedFieldsCount
    }

    $diagnostic | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $DiagnosticPath -Encoding UTF8

    return [ordered]@{
        findings = @($normalizedFindings.ToArray())
        diagnostic = $diagnostic
    }
}
