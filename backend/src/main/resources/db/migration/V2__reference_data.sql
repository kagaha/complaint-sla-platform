-- =============================================================================
-- V2: Reference and rule data. Mirrors docs/RULES_AND_ASSUMPTIONS.md (v1.3.2).
-- If a value here changes, change the rules document and its changelog too.
-- =============================================================================

-- Teams (section 4 of the rules document)
INSERT INTO team (team_code, name, description) VALUES
 ('SAFETY',      'Safety Response',  'Product safety hazards'),
 ('PRODUCT',     'Product Support',  'Defective products and warranty claims'),
 ('LOGISTICS',   'Logistics',        'Missing and late deliveries'),
 ('BILLING',     'Billing',          'Refunds and billing issues'),
 ('FULFILMENT',  'Fulfilment',       'Wrong items delivered'),
 ('QUALITY',     'Quality',          'Service behaviour reports'),
 ('CARE',        'Customer Care',    'General enquiries and information requests'),
 ('ESCALATIONS', 'Escalations',      'Legal threats and escalated complaints');

-- Categories (10)
INSERT INTO category (category_code, name, default_severity, team_code) VALUES
 ('CAT01', 'Product Safety Hazard',     'CRITICAL', 'SAFETY'),
 ('CAT02', 'Defective Product',         'HIGH',     'PRODUCT'),
 ('CAT03', 'Missing Order',             'HIGH',     'LOGISTICS'),
 ('CAT04', 'Refund Pending',            'MEDIUM',   'BILLING'),
 ('CAT05', 'Wrong Item Delivered',      'MEDIUM',   'FULFILMENT'),
 ('CAT06', 'Late Delivery',             'MEDIUM',   'LOGISTICS'),
 ('CAT07', 'Billing or Double Charge',  'HIGH',     'BILLING'),
 ('CAT08', 'Warranty Claim',            'MEDIUM',   'PRODUCT'),
 ('CAT09', 'Service Behaviour',         'LOW',      'QUALITY'),
 ('CAT10', 'General Enquiry',           'LOW',      'CARE');

-- Priority levels (exactly 4)
INSERT INTO priority_level (priority_code, name, sort_rank) VALUES
 ('P1', 'CRITICAL', 1),
 ('P2', 'HIGH',     2),
 ('P3', 'MEDIUM',   3),
 ('P4', 'LOW',      4);

-- Score bands (section 5.3). P1 also applies to any safety issue (via the P1 floor).
INSERT INTO priority_band (priority_code, effective_from, effective_to, min_score, max_score) VALUES
 ('P1', DATE '2026-01-01', NULL, 100, NULL),
 ('P2', DATE '2026-01-01', NULL,  60,   99),
 ('P3', DATE '2026-01-01', NULL,  25,   59),
 ('P4', DATE '2026-01-01', NULL,   0,   24);

-- SLA matrix (section 6), hours
INSERT INTO sla_matrix (priority_code, effective_from, effective_to, response_hours, resolution_hours) VALUES
 ('P1', DATE '2026-01-01', NULL,  1,  24),
 ('P2', DATE '2026-01-01', NULL,  4,  48),
 ('P3', DATE '2026-01-01', NULL,  8,  96),
 ('P4', DATE '2026-01-01', NULL, 24, 168);

-- Escalation thresholds (section 7)
INSERT INTO escalation_rule (level_code, threshold_pct, action, target_role) VALUES
 ('L1',  75, 'Warning to team lead',               'TEAM_LEAD'),
 ('L2', 100, 'Breach, escalate to manager',        'MANAGER'),
 ('L3', 150, 'Escalate to head of operations',     'HEAD_OPS');

-- Priority factors (section 5.2). Floor P4 = no guaranteed minimum.
INSERT INTO priority_rule
 (rule_code, effective_from, description, condition_text, points, floor_priority, exclusive_group, rule_version) VALUES
 ('SAFETY',              DATE '2026-01-01', 'Safety issue',                       'is_safety_issue = true',                                       100, 'P1', NULL,       'v1.3.2'),
 ('LEGAL_THREAT',        DATE '2026-01-01', 'Legal threat',                       'is_legal_threat = true',                                        40, 'P2', NULL,       'v1.3.2'),
 ('ISSUE_MISSING_ORDER', DATE '2026-01-01', 'Issue type: Missing Order',          'category = CAT03',                                              30, 'P3', 'ISSUE',    'v1.3.2'),
 ('ISSUE_DEFECTIVE',     DATE '2026-01-01', 'Issue type: Defective Product',      'category = CAT02',                                              30, 'P4', 'ISSUE',    'v1.3.2'),
 ('ISSUE_BILLING',       DATE '2026-01-01', 'Issue type: Billing or Double Charge','category = CAT07',                                             30, 'P4', 'ISSUE',    'v1.3.2'),
 ('ISSUE_REFUND',        DATE '2026-01-01', 'Issue type: Refund Pending',         'category = CAT04',                                              15, 'P4', 'ISSUE',    'v1.3.2'),
 ('ISSUE_WRONG_ITEM',    DATE '2026-01-01', 'Issue type: Wrong Item Delivered',   'category = CAT05',                                              15, 'P3', 'ISSUE',    'v1.3.2'),
 ('ISSUE_LATE_DELIVERY', DATE '2026-01-01', 'Issue type: Late Delivery',          'category = CAT06',                                              15, 'P4', 'ISSUE',    'v1.3.2'),
 ('ISSUE_WARRANTY',      DATE '2026-01-01', 'Issue type: Warranty Claim',         'category = CAT08',                                              15, 'P4', 'ISSUE',    'v1.3.2'),
 ('ISSUE_OTHER',         DATE '2026-01-01', 'Issue type: Service Behaviour, General Enquiry, Product Safety Hazard', 'category in (CAT09, CAT10, CAT01)', 0, 'P4', 'ISSUE',    'v1.3.2'),
 ('SENTIMENT_VERY_NEG',  DATE '2026-01-01', 'Sentiment very negative',            'sentiment = VERY_NEGATIVE',                                     30, 'P4', 'SENTIMENT','v1.3.2'),
 ('SENTIMENT_NEGATIVE',  DATE '2026-01-01', 'Sentiment negative',                 'sentiment = NEGATIVE',                                          15, 'P4', 'SENTIMENT','v1.3.2'),
 ('SENTIMENT_NEUTRAL',   DATE '2026-01-01', 'Sentiment neutral',                  'sentiment = NEUTRAL',                                            0, 'P4', 'SENTIMENT','v1.3.2'),
 ('ORDER_VALUE_HIGH',    DATE '2026-01-01', 'Order value above 50,000',           'order total > 50000',                                           20, 'P4', 'ORDER_VALUE','v1.3.2'),
 ('ORDER_VALUE_MID',     DATE '2026-01-01', 'Order value above 10,000',           'order total > 10000',                                           10, 'P4', 'ORDER_VALUE','v1.3.2'),
 ('RECURRENCE',          DATE '2026-01-01', 'Recurrence',                         'same customer, product and category within 90 days',            25, 'P4', NULL,       'v1.3.2'),
 ('VULNERABLE',          DATE '2026-01-01', 'Vulnerable customer',                'customer.is_vulnerable = true',                                 20, 'P4', NULL,       'v1.3.2'),
 ('REOPENED',            DATE '2026-01-01', 'Reopened complaint',                 'is_reopened = true',                                            20, 'P3', NULL,       'v1.3.2'),
 ('DOUBLE_CHARGE',       DATE '2026-01-01', 'Double or unauthorized charge',      'category = CAT07 and text matches double-charge keywords',      20, 'P2', NULL,       'v1.3.2'),
 ('ORDER_OVERDUE',       DATE '2026-01-01', 'Order overdue',                      'category = CAT03 and more than 7 days past expected delivery',  15, 'P2', NULL,       'v1.3.2'),
 ('REFUND_DELAY',        DATE '2026-01-01', 'Refund delay',                       'category = CAT04 and refund pending more than 14 days',         10, 'P3', NULL,       'v1.3.2'),
 ('PRODUCT_TREND',       DATE '2026-01-01', 'Product trend',                      '5 or more complaints on the same product within 7 days (5th and later)', 20, 'P2', NULL, 'v1.3.2');

-- Initial classifier keywords (section 4). Starting lists, to be extended.
INSERT INTO keyword_rule (keyword_id, keyword_type, category_code, keyword)
SELECT row_number() OVER (ORDER BY keyword_type, category_code, keyword),
       keyword_type, category_code, keyword
FROM (VALUES
 -- safety flag (independent of the winning category)
 ('SAFETY', NULL, 'smoke'), ('SAFETY', NULL, 'fire'), ('SAFETY', NULL, 'burn'), ('SAFETY', NULL, 'shock'),
 ('SAFETY', NULL, 'sparks'), ('SAFETY', NULL, 'explode'), ('SAFETY', NULL, 'injury'), ('SAFETY', NULL, 'choking'),
 ('SAFETY', NULL, 'overheating'),
 -- legal threat flag
 ('LEGAL', NULL, 'lawyer'), ('LEGAL', NULL, 'legal notice'), ('LEGAL', NULL, 'consumer court'),
 ('LEGAL', NULL, 'sue'), ('LEGAL', NULL, 'advocate'), ('LEGAL', NULL, 'legal action'),
 -- information request markers
 ('INFORMATION', NULL, 'how do i'), ('INFORMATION', NULL, 'what is'), ('INFORMATION', NULL, 'policy'),
 ('INFORMATION', NULL, 'invoice copy'), ('INFORMATION', NULL, 'where can i'), ('INFORMATION', NULL, 'want to know'),
 -- double or unauthorized charge markers
 ('DOUBLE_CHARGE', NULL, 'charged twice'), ('DOUBLE_CHARGE', NULL, 'double charge'),
 ('DOUBLE_CHARGE', NULL, 'unauthorized'), ('DOUBLE_CHARGE', NULL, 'deducted twice'),
 -- category keywords
 ('CATEGORY', 'CAT01', 'smoke'), ('CATEGORY', 'CAT01', 'fire'), ('CATEGORY', 'CAT01', 'burn'),
 ('CATEGORY', 'CAT01', 'shock'), ('CATEGORY', 'CAT01', 'sparks'), ('CATEGORY', 'CAT01', 'explode'),
 ('CATEGORY', 'CAT01', 'injury'), ('CATEGORY', 'CAT01', 'choking'),
 ('CATEGORY', 'CAT02', 'defective'), ('CATEGORY', 'CAT02', 'broken'), ('CATEGORY', 'CAT02', 'faulty'),
 ('CATEGORY', 'CAT02', 'not working'), ('CATEGORY', 'CAT02', 'stopped working'), ('CATEGORY', 'CAT02', 'damaged'),
 ('CATEGORY', 'CAT03', 'not received'), ('CATEGORY', 'CAT03', 'never arrived'), ('CATEGORY', 'CAT03', 'missing order'),
 ('CATEGORY', 'CAT03', 'lost'), ('CATEGORY', 'CAT03', 'not delivered'),
 ('CATEGORY', 'CAT04', 'refund'), ('CATEGORY', 'CAT04', 'money back'), ('CATEGORY', 'CAT04', 'not refunded'),
 ('CATEGORY', 'CAT05', 'wrong item'), ('CATEGORY', 'CAT05', 'wrong product'), ('CATEGORY', 'CAT05', 'different item'),
 ('CATEGORY', 'CAT05', 'incorrect item'),
 ('CATEGORY', 'CAT06', 'late'), ('CATEGORY', 'CAT06', 'delayed'), ('CATEGORY', 'CAT06', 'delay'),
 ('CATEGORY', 'CAT06', 'arrived late'),
 ('CATEGORY', 'CAT07', 'charged twice'), ('CATEGORY', 'CAT07', 'double charge'), ('CATEGORY', 'CAT07', 'overcharged'),
 ('CATEGORY', 'CAT07', 'billing'), ('CATEGORY', 'CAT07', 'unauthorized'), ('CATEGORY', 'CAT07', 'wrong amount'),
 ('CATEGORY', 'CAT08', 'warranty'), ('CATEGORY', 'CAT08', 'guarantee'), ('CATEGORY', 'CAT08', 'service centre'),
 ('CATEGORY', 'CAT09', 'rude'), ('CATEGORY', 'CAT09', 'abusive'), ('CATEGORY', 'CAT09', 'unprofessional'),
 ('CATEGORY', 'CAT09', 'behaviour'), ('CATEGORY', 'CAT09', 'behavior'),
 ('CATEGORY', 'CAT10', 'enquiry'), ('CATEGORY', 'CAT10', 'question'), ('CATEGORY', 'CAT10', 'information')
) AS v(keyword_type, category_code, keyword);
