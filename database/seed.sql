INSERT INTO resident (id, full_name, phone) VALUES
    ('RES-101', 'Анна Смирнова', '+79990000001'),
    ('RES-102', 'Илья Волков', '+79990000002'),
    ('RES-103', 'Ольга Соколова', '+79990000003');

INSERT INTO master (id, full_name, specialization, is_active) VALUES
    ('MST-201', 'Павел Орлов', 'plumbing', 1),
    ('MST-202', 'Мария Лебедева', 'electricity', 1),
    ('MST-203', 'Сергей Морозов', 'elevator', 0);

INSERT INTO service_request (
    external_request_id, resident_id, category, priority, status,
    description, complex_id, apartment_number, floor, is_emergency,
    preferred_time, assigned_master_id, version, created_at, updated_at
) VALUES
    (
        'REQ-2026-0041', 'RES-101', 'plumbing', 'high', 'CREATED',
        'Слабое давление воды на кухне', 'RC-01', '42A', 7, 0,
        '2026-09-06T10:00:00+03:00', NULL, 1,
        '2026-09-05T08:00:00Z', '2026-09-05T08:00:00Z'
    ),
    (
        'REQ-2026-0042', 'RES-102', 'plumbing', 'critical', 'ASSIGNED',
        'Протекает труба под раковиной', 'RC-01', '18', 3, 1,
        NULL, 'MST-201', 2,
        '2026-09-05T09:00:00Z', '2026-09-05T09:15:00Z'
    ),
    (
        'REQ-2026-0043', 'RES-103', 'electricity', 'medium', 'IN_PROGRESS',
        'Не работает освещение в коридоре', 'RC-02', NULL, 1, 0,
        NULL, 'MST-202', 3,
        '2026-09-04T15:00:00Z', '2026-09-05T07:30:00Z'
    ),
    (
        'REQ-2026-0044', 'RES-101', 'common_area', 'low', 'COMPLETED',
        'Повреждена ручка входной двери', 'RC-01', NULL, NULL, 0,
        NULL, NULL, 4,
        '2026-09-01T12:00:00Z', '2026-09-03T12:00:00Z'
    );

INSERT INTO request_attachment (request_id, file_name, content_type, url)
SELECT id, 'leak-01.jpg', 'image/jpeg',
       'https://files.house-service.example/REQ-2026-0042/leak-01.jpg'
FROM service_request
WHERE external_request_id = 'REQ-2026-0042';

INSERT INTO idempotency_record (
    idempotency_key, request_hash, response_status, response_body, expires_at
) VALUES (
    'OP-2026-0042',
    'sha256:example-only-not-a-real-request-hash',
    201,
    '{"request_id":2,"external_request_id":"REQ-2026-0042"}',
    '2026-09-06T09:00:00Z'
);
