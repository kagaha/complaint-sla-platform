-- =============================================================================
-- V1: Core schema for the Complaint Management and SLA Enforcement Platform
-- Source of truth for rules: docs/RULES_AND_ASSUMPTIONS.md (v1.3.2)
-- Source of truth for fields: docs/DATA_DICTIONARY.md
--
-- Design principles
--   1. Every table has a primary key; IDs follow the documented formats and are
--      enforced with CHECK constraints (zero padded, immutable).
--   2. Every relationship is a foreign key.
--   3. History is append-only: state changes are new rows in event tables.
--   4. Cross-row and date-order rules (resolution after complaint, survey after
--      closure, SLA pause only while AWAITING_CUSTOMER, ...) are NOT database
--      constraints. They are checked by the validator so that injected anomalies
--      can be detected, measured and reported.
--   5. Enumerations use CHECK constraints on text (simple for JPA).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Reference / rule tables
-- -----------------------------------------------------------------------------

CREATE TABLE team (
    team_code    VARCHAR(20)  PRIMARY KEY,
    name         VARCHAR(60)  NOT NULL UNIQUE,
    description  VARCHAR(200)
);

CREATE TABLE category (
    category_code     CHAR(5)      PRIMARY KEY CHECK (category_code ~ '^CAT[0-9]{2}$'),
    name              VARCHAR(60)  NOT NULL UNIQUE,
    default_severity  VARCHAR(10)  NOT NULL CHECK (default_severity IN ('CRITICAL','HIGH','MEDIUM','LOW')),
    team_code         VARCHAR(20)  NOT NULL REFERENCES team(team_code)
);

CREATE TABLE priority_level (
    priority_code  CHAR(2)      PRIMARY KEY CHECK (priority_code IN ('P1','P2','P3','P4')),
    name           VARCHAR(10)  NOT NULL UNIQUE CHECK (name IN ('CRITICAL','HIGH','MEDIUM','LOW')),
    sort_rank      SMALLINT     NOT NULL UNIQUE      -- 1 = most urgent
);

-- Score band that maps a total score to a priority level (effective dated).
CREATE TABLE priority_band (
    priority_code   CHAR(2)  NOT NULL REFERENCES priority_level(priority_code),
    effective_from  DATE     NOT NULL,
    effective_to    DATE,
    min_score       INTEGER  NOT NULL,
    max_score       INTEGER,                         -- NULL = no upper limit
    PRIMARY KEY (priority_code, effective_from),
    CHECK (max_score IS NULL OR max_score >= min_score),
    CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

-- SLA matrix: time limits per priority (effective dated). Units: hours.
CREATE TABLE sla_matrix (
    priority_code    CHAR(2)  NOT NULL REFERENCES priority_level(priority_code),
    effective_from   DATE     NOT NULL,
    effective_to     DATE,
    response_hours   INTEGER  NOT NULL CHECK (response_hours > 0),
    resolution_hours INTEGER  NOT NULL CHECK (resolution_hours > 0),
    PRIMARY KEY (priority_code, effective_from),
    CHECK (resolution_hours >= response_hours),
    CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

-- Escalation thresholds, as a percentage of the resolution SLA elapsed.
CREATE TABLE escalation_rule (
    level_code      CHAR(2)      PRIMARY KEY CHECK (level_code IN ('L1','L2','L3')),
    threshold_pct   INTEGER      NOT NULL UNIQUE CHECK (threshold_pct > 0),
    action          VARCHAR(80)  NOT NULL,
    target_role     VARCHAR(20)  NOT NULL CHECK (target_role IN ('TEAM_LEAD','MANAGER','HEAD_OPS'))
);

-- One row per scoring factor. Points add up; floor_priority is a guaranteed
-- minimum priority (P4 means "no guaranteed minimum").
-- exclusive_group: only the highest-scoring factor of a group applies.
CREATE TABLE priority_rule (
    rule_code        VARCHAR(30)  NOT NULL,
    effective_from   DATE         NOT NULL,
    effective_to     DATE,
    description      VARCHAR(200) NOT NULL,
    condition_text   VARCHAR(200) NOT NULL,
    points           INTEGER      NOT NULL,
    floor_priority   CHAR(2)      NOT NULL REFERENCES priority_level(priority_code),
    exclusive_group  VARCHAR(20),
    active           BOOLEAN      NOT NULL DEFAULT TRUE,
    rule_version     VARCHAR(10)  NOT NULL,
    PRIMARY KEY (rule_code, effective_from),
    CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

-- Keyword lists used by the deterministic classifier.
CREATE TABLE keyword_rule (
    keyword_id     INTEGER      PRIMARY KEY,
    keyword_type   VARCHAR(20)  NOT NULL CHECK (keyword_type IN ('CATEGORY','SAFETY','LEGAL','INFORMATION','DOUBLE_CHARGE')),
    category_code  CHAR(5)      REFERENCES category(category_code),
    keyword        VARCHAR(60)  NOT NULL,
    UNIQUE (keyword_type, category_code, keyword),
    CHECK ((keyword_type = 'CATEGORY') = (category_code IS NOT NULL))
);

-- -----------------------------------------------------------------------------
-- People
-- -----------------------------------------------------------------------------

CREATE TABLE customer (
    customer_id    VARCHAR(10)   PRIMARY KEY CHECK (customer_id ~ '^CUS-[0-9]{6}$'),
    full_name      VARCHAR(100)  NOT NULL,
    email          VARCHAR(120)  NOT NULL UNIQUE,
    phone          VARCHAR(20),
    city           VARCHAR(60)   NOT NULL,
    tier           VARCHAR(10)   NOT NULL DEFAULT 'STANDARD' CHECK (tier IN ('STANDARD','SILVER','GOLD','PREMIUM')),
    is_vulnerable  BOOLEAN       NOT NULL DEFAULT FALSE,   -- synthetic flag only
    created_at     TIMESTAMPTZ   NOT NULL
);

CREATE TABLE support_agent (
    agent_id   VARCHAR(10)   PRIMARY KEY CHECK (agent_id ~ '^AGT-[0-9]{4}$'),
    full_name  VARCHAR(100)  NOT NULL,
    email      VARCHAR(120)  NOT NULL UNIQUE,
    team_code  VARCHAR(20)   NOT NULL REFERENCES team(team_code),
    role       VARCHAR(10)   NOT NULL CHECK (role IN ('AGENT','TEAM_LEAD','MANAGER','HEAD_OPS')),
    is_senior  BOOLEAN       NOT NULL DEFAULT FALSE,
    active     BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ   NOT NULL
);

-- Application login (Spring Security). Roles map to the five primary actors.
CREATE TABLE app_user (
    user_id        INTEGER       PRIMARY KEY,
    username       VARCHAR(40)   NOT NULL UNIQUE,
    password_hash  VARCHAR(100)  NOT NULL,
    role           VARCHAR(20)   NOT NULL CHECK (role IN ('REQUESTER','PROCESS_OWNER','APPROVER','ANALYST','ADMIN')),
    agent_id       VARCHAR(10)   REFERENCES support_agent(agent_id),
    enabled        BOOLEAN       NOT NULL DEFAULT TRUE
);

-- -----------------------------------------------------------------------------
-- Products and orders
-- -----------------------------------------------------------------------------

CREATE TABLE product (
    product_id          VARCHAR(10)    PRIMARY KEY CHECK (product_id ~ '^PRD-[0-9]{4}$'),
    sku                 VARCHAR(20)    NOT NULL UNIQUE,
    name                VARCHAR(120)   NOT NULL,
    product_family      VARCHAR(40)    NOT NULL,
    unit_price          NUMERIC(12,2)  NOT NULL CHECK (unit_price > 0),
    is_safety_critical  BOOLEAN        NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ    NOT NULL
);

CREATE TABLE customer_order (
    order_id               VARCHAR(15)    PRIMARY KEY CHECK (order_id ~ '^ORD-2026-[0-9]{6}$'),
    customer_id            VARCHAR(10)    NOT NULL REFERENCES customer(customer_id),
    order_date             TIMESTAMPTZ    NOT NULL,
    expected_delivery_date DATE           NOT NULL,
    delivered_at           TIMESTAMPTZ,                     -- NULL = not delivered (missing or in transit)
    status                 VARCHAR(12)    NOT NULL CHECK (status IN ('PLACED','SHIPPED','DELIVERED','CANCELLED','LOST')),
    total_amount           NUMERIC(12,2)  NOT NULL CHECK (total_amount >= 0),   -- must equal SUM(order_item.line_total)
    currency               CHAR(3)        NOT NULL DEFAULT 'INR' CHECK (currency = 'INR')
);

-- Bridge table: Order N:M Product
CREATE TABLE order_item (
    order_id    VARCHAR(15)    NOT NULL REFERENCES customer_order(order_id),
    line_no     SMALLINT       NOT NULL CHECK (line_no > 0),
    product_id  VARCHAR(10)    NOT NULL REFERENCES product(product_id),
    quantity    INTEGER        NOT NULL CHECK (quantity > 0),
    unit_price  NUMERIC(12,2)  NOT NULL CHECK (unit_price > 0),
    line_total  NUMERIC(12,2)  NOT NULL,
    PRIMARY KEY (order_id, line_no),
    UNIQUE (order_id, product_id),
    CHECK (line_total = quantity * unit_price)
);

-- -----------------------------------------------------------------------------
-- Complaints
-- -----------------------------------------------------------------------------

CREATE TABLE complaint (
    complaint_id         VARCHAR(15)   PRIMARY KEY CHECK (complaint_id ~ '^CMP-2026-[0-9]{6}$'),
    customer_id          VARCHAR(10)   NOT NULL REFERENCES customer(customer_id),
    order_id             VARCHAR(15)   REFERENCES customer_order(order_id),      -- optional
    product_id           VARCHAR(10)   REFERENCES product(product_id),           -- optional
    parent_complaint_id  VARCHAR(15)   REFERENCES complaint(complaint_id),       -- repeat complaint link
    channel              VARCHAR(12)   NOT NULL CHECK (channel IN ('WEB','EMAIL','PHONE','CHAT','APP','SOCIAL_MEDIA')),
    request_type         VARCHAR(20)   NOT NULL CHECK (request_type IN ('COMPLAINT','INFORMATION_REQUEST')),
    category_code        CHAR(5)       NOT NULL REFERENCES category(category_code),
    severity             VARCHAR(10)   NOT NULL CHECK (severity IN ('CRITICAL','HIGH','MEDIUM','LOW')),
    sentiment            VARCHAR(13)   NOT NULL CHECK (sentiment IN ('VERY_NEGATIVE','NEGATIVE','NEUTRAL')),
    subject              VARCHAR(150)  NOT NULL,
    description          TEXT          NOT NULL,
    is_safety_issue      BOOLEAN       NOT NULL DEFAULT FALSE,
    is_legal_threat      BOOLEAN       NOT NULL DEFAULT FALSE,
    is_repeat            BOOLEAN       NOT NULL DEFAULT FALSE,
    is_reopened          BOOLEAN       NOT NULL DEFAULT FALSE,
    reopen_count         SMALLINT      NOT NULL DEFAULT 0 CHECK (reopen_count >= 0),
    priority_code        CHAR(2)       NOT NULL REFERENCES priority_level(priority_code),
    priority_score       INTEGER       NOT NULL CHECK (priority_score >= 0),
    priority_breakdown   JSONB         NOT NULL,                  -- factors applied, points, floors
    rule_version         VARCHAR(10)   NOT NULL,
    status               VARCHAR(20)   NOT NULL CHECK (status IN
                           ('NEW','CLASSIFIED','ASSIGNED','IN_PROGRESS','AWAITING_CUSTOMER','RESOLVED','CLOSED','REOPENED')),
    created_at           TIMESTAMPTZ   NOT NULL,
    resolved_at          TIMESTAMPTZ,
    closed_at            TIMESTAMPTZ,
    CHECK (parent_complaint_id IS NULL OR parent_complaint_id <> complaint_id)
);

CREATE TABLE complaint_message (
    message_id    VARCHAR(30)  PRIMARY KEY CHECK (message_id ~ '^MSG-CMP-2026-[0-9]{6}-[0-9]{3}$'),
    complaint_id  VARCHAR(15)  NOT NULL REFERENCES complaint(complaint_id),
    seq           SMALLINT     NOT NULL CHECK (seq > 0),
    sender_type   VARCHAR(10)  NOT NULL CHECK (sender_type IN ('CUSTOMER','AGENT','SYSTEM')),
    sender_id     VARCHAR(10),                                   -- customer_id or agent_id; NULL for SYSTEM
    channel       VARCHAR(12)  NOT NULL CHECK (channel IN ('WEB','EMAIL','PHONE','CHAT','APP','SOCIAL_MEDIA')),
    body          TEXT         NOT NULL,
    sent_at       TIMESTAMPTZ  NOT NULL,
    UNIQUE (complaint_id, seq),
    CHECK ((sender_type = 'SYSTEM') = (sender_id IS NULL))
);

-- Append-only lifecycle history. complaint.status mirrors the latest event.
CREATE TABLE status_event (
    event_id      VARCHAR(30)  PRIMARY KEY CHECK (event_id ~ '^STE-CMP-2026-[0-9]{6}-[0-9]{3}$'),
    complaint_id  VARCHAR(15)  NOT NULL REFERENCES complaint(complaint_id),
    seq           SMALLINT     NOT NULL CHECK (seq > 0),
    from_status   VARCHAR(20)  CHECK (from_status IN
                    ('NEW','CLASSIFIED','ASSIGNED','IN_PROGRESS','AWAITING_CUSTOMER','RESOLVED','CLOSED','REOPENED')),
    to_status     VARCHAR(20)  NOT NULL CHECK (to_status IN
                    ('NEW','CLASSIFIED','ASSIGNED','IN_PROGRESS','AWAITING_CUSTOMER','RESOLVED','CLOSED','REOPENED')),
    changed_by    VARCHAR(10),                                   -- agent_id or NULL for system
    changed_at    TIMESTAMPTZ  NOT NULL,
    reason        VARCHAR(200),
    UNIQUE (complaint_id, seq),
    CHECK (from_status IS NULL OR from_status <> to_status)
);

-- Ownership history: a reassignment closes the old row (ended_at) and adds a new one.
CREATE TABLE assignment (
    assignment_id  VARCHAR(30)  PRIMARY KEY CHECK (assignment_id ~ '^ASG-CMP-2026-[0-9]{6}-[0-9]{2}$'),
    complaint_id   VARCHAR(15)  NOT NULL REFERENCES complaint(complaint_id),
    seq            SMALLINT     NOT NULL CHECK (seq > 0),
    agent_id       VARCHAR(10)  NOT NULL REFERENCES support_agent(agent_id),
    team_code      VARCHAR(20)  NOT NULL REFERENCES team(team_code),
    queue          VARCHAR(10)  NOT NULL CHECK (queue IN ('SENIOR','STANDARD')),
    reason         VARCHAR(12)  NOT NULL CHECK (reason IN ('INITIAL','REASSIGNED','ESCALATED','REOPENED')),
    assigned_at    TIMESTAMPTZ  NOT NULL,
    ended_at       TIMESTAMPTZ,
    UNIQUE (complaint_id, seq),
    CHECK (ended_at IS NULL OR ended_at >= assigned_at)
);

-- -----------------------------------------------------------------------------
-- SLA clock and escalation
-- -----------------------------------------------------------------------------

CREATE TABLE sla_clock (
    sla_id               VARCHAR(30)  PRIMARY KEY CHECK (sla_id ~ '^SLA-CMP-2026-[0-9]{6}$'),
    complaint_id         VARCHAR(15)  NOT NULL UNIQUE REFERENCES complaint(complaint_id),
    priority_code        CHAR(2)      NOT NULL REFERENCES priority_level(priority_code),
    response_hours       INTEGER      NOT NULL CHECK (response_hours > 0),
    resolution_hours     INTEGER      NOT NULL CHECK (resolution_hours > 0),
    started_at           TIMESTAMPTZ  NOT NULL,
    response_due_at      TIMESTAMPTZ  NOT NULL,
    resolution_due_at    TIMESTAMPTZ  NOT NULL,   -- started_at + resolution_hours + total paused time
    first_response_at    TIMESTAMPTZ,
    total_paused_minutes INTEGER      NOT NULL DEFAULT 0 CHECK (total_paused_minutes >= 0),
    state                VARCHAR(10)  NOT NULL CHECK (state IN ('RUNNING','PAUSED','STOPPED')),
    stopped_at           TIMESTAMPTZ
);

CREATE TABLE sla_pause_event (
    pause_id      VARCHAR(40)  PRIMARY KEY CHECK (pause_id ~ '^PAU-CMP-2026-[0-9]{6}-[0-9]{2}$'),
    sla_id        VARCHAR(30)  NOT NULL REFERENCES sla_clock(sla_id),
    seq           SMALLINT     NOT NULL CHECK (seq > 0),
    paused_at     TIMESTAMPTZ  NOT NULL,
    resumed_at    TIMESTAMPTZ,
    reason        VARCHAR(40)  NOT NULL DEFAULT 'AWAITING_CUSTOMER',
    UNIQUE (sla_id, seq)
);

CREATE TABLE escalation_event (
    escalation_id   VARCHAR(40)  PRIMARY KEY CHECK (escalation_id ~ '^ESC-CMP-2026-[0-9]{6}-C[0-9]-L[1-3]$'),
    complaint_id    VARCHAR(15)  NOT NULL REFERENCES complaint(complaint_id),
    cycle_no        SMALLINT     NOT NULL DEFAULT 1 CHECK (cycle_no > 0),   -- increases on reopen
    level_code      CHAR(2)      NOT NULL REFERENCES escalation_rule(level_code),
    triggered_at    TIMESTAMPTZ  NOT NULL,
    elapsed_pct     NUMERIC(6,1) NOT NULL CHECK (elapsed_pct > 0),
    notified_agent  VARCHAR(10)  REFERENCES support_agent(agent_id),
    UNIQUE (complaint_id, cycle_no, level_code)
);

-- -----------------------------------------------------------------------------
-- Resolution and survey
-- -----------------------------------------------------------------------------

CREATE TABLE resolution (
    resolution_id    VARCHAR(30)    PRIMARY KEY CHECK (resolution_id ~ '^RES-CMP-2026-[0-9]{6}(-[0-9]+)?$'),
    complaint_id     VARCHAR(15)    NOT NULL REFERENCES complaint(complaint_id),
    cycle_no         SMALLINT       NOT NULL DEFAULT 1 CHECK (cycle_no > 0),
    resolution_type  VARCHAR(20)    NOT NULL CHECK (resolution_type IN
                       ('REFUND','REPLACEMENT','REPAIR','REDELIVERY','APOLOGY','INFORMATION_PROVIDED','NO_ACTION')),
    resolved_by      VARCHAR(10)    NOT NULL REFERENCES support_agent(agent_id),
    resolved_at      TIMESTAMPTZ    NOT NULL,
    refund_amount    NUMERIC(12,2)  NOT NULL DEFAULT 0 CHECK (refund_amount >= 0),
    approved_by      VARCHAR(10)    REFERENCES support_agent(agent_id),   -- required by the validator when refund is large
    approved_at      TIMESTAMPTZ,
    summary          VARCHAR(300)   NOT NULL,
    UNIQUE (complaint_id, cycle_no)
);

CREATE TABLE survey (
    survey_id      VARCHAR(30)  PRIMARY KEY CHECK (survey_id ~ '^SRV-CMP-2026-[0-9]{6}(-[0-9]+)?$'),
    resolution_id  VARCHAR(30)  NOT NULL UNIQUE REFERENCES resolution(resolution_id),
    complaint_id   VARCHAR(15)  NOT NULL REFERENCES complaint(complaint_id),
    sent_at        TIMESTAMPTZ  NOT NULL,
    responded_at   TIMESTAMPTZ,
    score          SMALLINT     CHECK (score BETWEEN 1 AND 5),
    comment        VARCHAR(300),
    CHECK ((responded_at IS NULL) = (score IS NULL))
);

-- -----------------------------------------------------------------------------
-- Validator output (what the checker found). The answer key, ground_truth.csv,
-- is deliberately NOT stored here and is never read by the validator.
-- -----------------------------------------------------------------------------

CREATE TABLE data_quality_issue (
    issue_id     BIGINT        PRIMARY KEY,
    run_id       VARCHAR(40)   NOT NULL,
    entity       VARCHAR(30)   NOT NULL,
    record_id    VARCHAR(40),
    check_name   VARCHAR(40)   NOT NULL,
    detail       VARCHAR(300)  NOT NULL,
    detected_at  TIMESTAMPTZ   NOT NULL
);

-- -----------------------------------------------------------------------------
-- Indexes for the queries the app and validator run most
-- -----------------------------------------------------------------------------

CREATE INDEX idx_order_customer        ON customer_order(customer_id);
CREATE INDEX idx_order_item_product    ON order_item(product_id);
CREATE INDEX idx_complaint_customer    ON complaint(customer_id, created_at);
CREATE INDEX idx_complaint_order       ON complaint(order_id);
CREATE INDEX idx_complaint_product     ON complaint(product_id, created_at);
CREATE INDEX idx_complaint_parent      ON complaint(parent_complaint_id);
CREATE INDEX idx_complaint_queue       ON complaint(status, priority_code);
CREATE INDEX idx_message_complaint     ON complaint_message(complaint_id, seq);
CREATE INDEX idx_status_complaint      ON status_event(complaint_id, seq);
CREATE INDEX idx_assignment_agent      ON assignment(agent_id, ended_at);
CREATE INDEX idx_pause_sla             ON sla_pause_event(sla_id);
CREATE INDEX idx_escalation_complaint  ON escalation_event(complaint_id);
CREATE INDEX idx_resolution_complaint  ON resolution(complaint_id);
CREATE INDEX idx_survey_complaint      ON survey(complaint_id);
CREATE INDEX idx_dqi_run               ON data_quality_issue(run_id, check_name);
