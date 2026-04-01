# UPDATED RUN_BATCH.ps1 (v2 - NO_EFFECT fixed hard)

# ONLY CHANGE: NO_EFFECT is treated as PASS (idempotent)

# ... (shortened header)

# INSERT ONLY CRITICAL PATCH BLOCK BELOW (core logic part)

if (-not $result['apply_changed']) {
    New-ResultTerminal -Result $result `
        -Status 'PASS' `
        -OutcomeClass 'PASS' `
        -ReasonCode 'NO_EFFECT_OK' `
        -ExecutionMode 'AUTO_APPLY' `
        -Message 'Batch valid but produced no changes (idempotent).'

    Write-RunReport -Result $result
    exit 0
}

# keep rest of original file unchanged
