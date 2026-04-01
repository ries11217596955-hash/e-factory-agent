GH_BATCH SMARTFIX PATCH

Что нового:
1. Безопасный старт с fallback логом.
2. Safe Auto-Fix для простых ошибок:
   - smart quotes -> ASCII
   - trailing comma в JSON
   - табы -> 2 пробела для yaml/front matter
3. Plaintext guard против base64-поломки.
4. Post-commit verify по HEAD и blob SHA.
5. RUN_REPORT_*.json рядом с TXT-отчётом.

Запуск:
- Обычный: powershell -ExecutionPolicy Bypass -File .\RUN_BATCH.ps1
- Preview: powershell -ExecutionPolicy Bypass -File .\RUN_BATCH.ps1 -WhatIfOnly
- Без автофикса: powershell -ExecutionPolicy Bypass -File .\RUN_BATCH.ps1 -NoAutoFix
