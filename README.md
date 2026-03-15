# E-Factory Agent Repo

Назначение: отдельный репозиторий кода и базовой структуры локального агента E-Factory.

Базовые контуры:
- `agent/` — описание роли и точки входа агента
- `inbox/` — контракты входящих batch-каналов
- `runtime/` — runtime-state и служебные указатели
- `scripts/` — PowerShell-скрипты агента
- `config/` — конфиги маршрутизации и валидации
- `logs/` — логи выполнения
- `templates/` — шаблоны batch/job-файлов
- `docs/` — архитектурные заметки
- `tests/` — будущие smoke/fixture тесты

Три канала:
- `INBOX_SITE`
- `INBOX_MEMORY`
- `INBOX_AGENT`
