# Словарь данных

## service_request

| Поле | Тип | Обязательность | Правило |
|---|---|---|---|
| `id` | integer | Да | Внутренний идентификатор |
| `external_request_id` | string | Да | Уникален, без крайних пробелов |
| `resident_id` | string | Да | Ссылка на жителя |
| `category` | enum | Да | `plumbing`, `electricity`, `elevator`, `security`, `common_area`, `other` |
| `priority` | enum | Да | `low`, `medium`, `high`, `critical` |
| `status` | enum | Да | Значение из жизненного цикла |
| `description` | string | Да | Непустое описание до 2000 символов на уровне API |
| `complex_id` | string | Да | Внешний ID жилого комплекса |
| `apartment_number` | string | Нет | Отсутствует для общей территории |
| `floor` | integer | Нет | Допускает подземные этажи от -5 |
| `is_emergency` | boolean | Да | В SQLite хранится как 0 или 1 |
| `preferred_time` | datetime | Нет | ISO 8601 с часовым поясом |
| `assigned_master_id` | string | Нет | Ссылка на активного мастера |
| `version` | integer | Да | Начинается с 1, растет при изменении |
| `created_at` | datetime | Да | UTC |
| `updated_at` | datetime | Да | UTC |

## request_status_history

Запись создается для начального состояния и каждого перехода. `changed_by` хранит технический ID субъекта, а `comment` — основание ручного действия без чувствительных данных.

## outbox_event

`payload` — валидный JSON. `event_id` используется получателем для дедупликации. `retry_count` и `next_attempt_at` управляют повторной доставкой.

## idempotency_record

`request_hash` вычисляется из нормализованного тела. `response_body` хранит минимальный результат, достаточный для безопасного повтора. Записи удаляются по политике хранения.
