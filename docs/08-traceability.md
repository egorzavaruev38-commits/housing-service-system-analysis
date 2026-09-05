# Матрица трассировки

| Цель | Требования | API | Данные | Проверка |
|---|---|---|---|---|
| Единая регистрация | BR-01, FR-01, FR-02 | `POST /requests` | `service_request` | AC-01, AC-04 |
| Защита от дублей | BR-02, FR-03, FR-04 | `Idempotency-Key` | `idempotency_record` | AC-02, AC-03 |
| Прозрачный статус | BR-03, FR-05, FR-08, FR-09 | `GET /requests/{id}`, `PATCH /requests/{id}/status` | `request_status_history` | AC-07, AC-08 |
| Надежные уведомления | BR-04, FR-10, NFR-03 | События outbox | `outbox_event` | AC-09 |
| Диагностика | BR-05, FR-12, NFR-06 | `X-Correlation-ID`, `Error` | correlation ID в событиях | Проверка формата ошибки |
| Конкурентность | FR-08, NFR-05 | `If-Match` | `service_request.version` | AC-06 |
| Управление очередью | FR-06, FR-07 | `GET /requests`, назначение | `master`, `service_request` | AC-10, SQL Q-01..Q-04 |
