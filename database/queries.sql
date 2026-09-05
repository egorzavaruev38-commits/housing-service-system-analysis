-- Q-01. Активная очередь: аварийные и старые заявки выше остальных.
SELECT
    sr.id,
    sr.external_request_id,
    sr.status,
    sr.priority,
    sr.category,
    sr.created_at
FROM service_request AS sr
WHERE sr.status IN ('CREATED', 'ASSIGNED', 'IN_PROGRESS')
ORDER BY
    CASE sr.priority
        WHEN 'critical' THEN 1
        WHEN 'high' THEN 2
        WHEN 'medium' THEN 3
        ELSE 4
    END,
    sr.created_at;

-- Q-02. Активные мастера без заявок в работе.
SELECT
    m.id,
    m.full_name,
    m.specialization
FROM master AS m
LEFT JOIN service_request AS sr
    ON sr.assigned_master_id = m.id
   AND sr.status = 'IN_PROGRESS'
WHERE m.is_active = 1
  AND sr.id IS NULL
ORDER BY m.full_name;

-- Q-03. Нагрузка активных мастеров, включая мастеров без заявок.
SELECT
    m.id,
    m.full_name,
    COUNT(sr.id) AS active_request_count,
    SUM(CASE WHEN sr.priority = 'critical' THEN 1 ELSE 0 END) AS critical_count
FROM master AS m
LEFT JOIN service_request AS sr
    ON sr.assigned_master_id = m.id
   AND sr.status IN ('ASSIGNED', 'IN_PROGRESS')
WHERE m.is_active = 1
GROUP BY m.id, m.full_name
ORDER BY active_request_count, m.full_name;

-- Q-04. История конкретной заявки.
SELECT
    sr.external_request_id,
    h.from_status,
    h.to_status,
    h.changed_by,
    h.comment,
    h.changed_at
FROM request_status_history AS h
JOIN service_request AS sr ON sr.id = h.request_id
WHERE sr.external_request_id = 'REQ-2026-0042'
ORDER BY h.changed_at, h.id;

-- Q-05. События, готовые к доставке или повтору.
SELECT
    event_id,
    aggregate_id,
    event_type,
    retry_count,
    next_attempt_at
FROM outbox_event
WHERE status = 'NEW'
  AND (next_attempt_at IS NULL OR next_attempt_at <= CURRENT_TIMESTAMP)
ORDER BY created_at
LIMIT 100;

-- Q-06. Доля заявок по статусам.
SELECT
    status,
    COUNT(*) AS request_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_percent
FROM service_request
GROUP BY status
ORDER BY request_count DESC, status;
