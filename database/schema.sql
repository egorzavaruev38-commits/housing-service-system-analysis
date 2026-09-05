PRAGMA foreign_keys = ON;

CREATE TABLE resident (
    id TEXT PRIMARY KEY,
    full_name TEXT NOT NULL CHECK (trim(full_name) <> ''),
    phone TEXT NOT NULL CHECK (trim(phone) <> ''),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE master (
    id TEXT PRIMARY KEY,
    full_name TEXT NOT NULL CHECK (trim(full_name) <> ''),
    specialization TEXT NOT NULL CHECK (trim(specialization) <> ''),
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE service_request (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    external_request_id TEXT NOT NULL UNIQUE
        CHECK (external_request_id = trim(external_request_id) AND external_request_id <> ''),
    resident_id TEXT NOT NULL REFERENCES resident(id),
    category TEXT NOT NULL
        CHECK (category IN ('plumbing', 'electricity', 'elevator', 'security', 'common_area', 'other')),
    priority TEXT NOT NULL DEFAULT 'medium'
        CHECK (priority IN ('low', 'medium', 'high', 'critical')),
    status TEXT NOT NULL DEFAULT 'CREATED'
        CHECK (status IN ('CREATED', 'ASSIGNED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'REJECTED')),
    description TEXT NOT NULL CHECK (trim(description) <> ''),
    complex_id TEXT NOT NULL CHECK (trim(complex_id) <> ''),
    apartment_number TEXT
        CHECK (apartment_number IS NULL OR (apartment_number = trim(apartment_number) AND apartment_number <> '')),
    floor INTEGER CHECK (floor IS NULL OR floor BETWEEN -5 AND 200),
    is_emergency INTEGER NOT NULL DEFAULT 0 CHECK (is_emergency IN (0, 1)),
    preferred_time TEXT
        CHECK (preferred_time IS NULL OR (preferred_time = trim(preferred_time) AND preferred_time <> '')),
    assigned_master_id TEXT REFERENCES master(id),
    version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (is_emergency = 0 OR priority = 'critical'),
    CHECK (status NOT IN ('ASSIGNED', 'IN_PROGRESS') OR assigned_master_id IS NOT NULL)
);

CREATE TABLE request_attachment (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    request_id INTEGER NOT NULL REFERENCES service_request(id) ON DELETE CASCADE,
    file_name TEXT NOT NULL CHECK (trim(file_name) <> ''),
    content_type TEXT NOT NULL CHECK (trim(content_type) <> ''),
    url TEXT NOT NULL CHECK (url LIKE 'https://%'),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (request_id, url)
);

CREATE TABLE request_status_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    request_id INTEGER NOT NULL REFERENCES service_request(id) ON DELETE CASCADE,
    from_status TEXT,
    to_status TEXT NOT NULL,
    changed_by TEXT NOT NULL CHECK (trim(changed_by) <> ''),
    comment TEXT,
    changed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE outbox_event (
    event_id TEXT PRIMARY KEY,
    aggregate_id INTEGER NOT NULL REFERENCES service_request(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (event_type IN ('request.created', 'request.status_changed')),
    payload TEXT NOT NULL CHECK (json_valid(payload)),
    correlation_id TEXT NOT NULL CHECK (trim(correlation_id) <> ''),
    status TEXT NOT NULL DEFAULT 'NEW' CHECK (status IN ('NEW', 'SENT', 'FAILED')),
    retry_count INTEGER NOT NULL DEFAULT 0 CHECK (retry_count BETWEEN 0 AND 5),
    next_attempt_at TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sent_at TEXT
);

CREATE TABLE idempotency_record (
    idempotency_key TEXT PRIMARY KEY CHECK (trim(idempotency_key) <> ''),
    request_hash TEXT NOT NULL CHECK (trim(request_hash) <> ''),
    response_status INTEGER NOT NULL CHECK (response_status BETWEEN 200 AND 599),
    response_body TEXT NOT NULL CHECK (json_valid(response_body)),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TEXT NOT NULL
);

CREATE INDEX idx_request_queue
    ON service_request (status, priority, created_at);

CREATE INDEX idx_request_master_status
    ON service_request (assigned_master_id, status);

CREATE INDEX idx_history_request_time
    ON request_status_history (request_id, changed_at);

CREATE INDEX idx_outbox_delivery
    ON outbox_event (status, next_attempt_at, created_at);

CREATE TRIGGER trg_request_validate_transition
BEFORE UPDATE OF status ON service_request
FOR EACH ROW
WHEN OLD.status <> NEW.status
 AND NOT (
      (OLD.status = 'CREATED' AND NEW.status IN ('ASSIGNED', 'CANCELLED', 'REJECTED'))
   OR (OLD.status = 'ASSIGNED' AND NEW.status IN ('CREATED', 'IN_PROGRESS', 'CANCELLED'))
   OR (OLD.status = 'IN_PROGRESS' AND NEW.status IN ('ASSIGNED', 'COMPLETED', 'CANCELLED'))
 )
BEGIN
    SELECT RAISE(ABORT, 'INVALID_STATUS_TRANSITION');
END;

CREATE TRIGGER trg_request_history_on_create
AFTER INSERT ON service_request
FOR EACH ROW
BEGIN
    INSERT INTO request_status_history (
        request_id, from_status, to_status, changed_by, comment
    ) VALUES (
        NEW.id, NULL, NEW.status, 'system', 'Initial status'
    );
END;

CREATE TRIGGER trg_request_history_on_status_change
AFTER UPDATE OF status ON service_request
FOR EACH ROW
WHEN OLD.status <> NEW.status
BEGIN
    INSERT INTO request_status_history (
        request_id, from_status, to_status, changed_by, comment
    ) VALUES (
        NEW.id, OLD.status, NEW.status, 'system', 'Status changed'
    );
END;

CREATE TRIGGER trg_request_outbox_on_create
AFTER INSERT ON service_request
FOR EACH ROW
BEGIN
    INSERT INTO outbox_event (
        event_id, aggregate_id, event_type, payload, correlation_id
    ) VALUES (
        'evt-' || lower(hex(randomblob(16))),
        NEW.id,
        'request.created',
        json_object(
            'request_id', NEW.id,
            'external_request_id', NEW.external_request_id,
            'status', NEW.status,
            'version', NEW.version
        ),
        'seed-' || NEW.external_request_id
    );
END;

CREATE TRIGGER trg_request_outbox_on_status_change
AFTER UPDATE OF status ON service_request
FOR EACH ROW
WHEN OLD.status <> NEW.status
BEGIN
    INSERT INTO outbox_event (
        event_id, aggregate_id, event_type, payload, correlation_id
    ) VALUES (
        'evt-' || lower(hex(randomblob(16))),
        NEW.id,
        'request.status_changed',
        json_object(
            'request_id', NEW.id,
            'previous_status', OLD.status,
            'new_status', NEW.status,
            'version', NEW.version
        ),
        'status-' || NEW.external_request_id || '-' || NEW.version
    );
END;
