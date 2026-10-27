-- Schema smoke test. Run against a database that has V1 and V2 applied:
--   psql -d complaints -v ON_ERROR_STOP=1 -f schema_smoke_test.sql
-- It loads one complete valid complaint chain, then checks that bad data is
-- rejected by the constraints that are meant to reject it, and accepted where
-- the validator (not the database) is meant to catch the problem.
-- Everything runs inside a transaction that is rolled back at the end.

BEGIN;

-- ---------- 1. A complete valid chain loads ----------
INSERT INTO customer VALUES ('CUS-000001','Test Customer','t1@example.test','9000000001','Pune','STANDARD',false,'2026-01-01T00:00:00Z');
INSERT INTO support_agent VALUES ('AGT-0001','Test Agent','a1@example.test','CARE','AGENT',false,true,'2026-01-01T00:00:00Z');
INSERT INTO support_agent VALUES ('AGT-0002','Test Lead','a2@example.test','CARE','TEAM_LEAD',true,true,'2026-01-01T00:00:00Z');
INSERT INTO product VALUES ('PRD-0001','SKU-1','Test Kettle','Kitchen',1500.00,true,'2026-01-01T00:00:00Z');
INSERT INTO customer_order VALUES ('ORD-2026-000001','CUS-000001','2026-02-01T00:00:00Z','2026-02-05','2026-02-09T00:00:00Z','DELIVERED',3000.00,'INR');
INSERT INTO order_item VALUES ('ORD-2026-000001',1,'PRD-0001',2,1500.00,3000.00);
INSERT INTO complaint VALUES ('CMP-2026-000001','CUS-000001','ORD-2026-000001','PRD-0001',NULL,'WEB','COMPLAINT','CAT06','MEDIUM','NEUTRAL',
  'Late delivery','The order arrived late.',false,false,false,false,0,'P4',15,'{"ISSUE_LATE_DELIVERY":15}','v1.3.2','CLOSED',
  '2026-02-10T00:00:00Z','2026-02-11T00:00:00Z','2026-02-12T00:00:00Z');
INSERT INTO complaint_message VALUES ('MSG-CMP-2026-000001-001','CMP-2026-000001',1,'CUSTOMER','CUS-000001','WEB','Late',  '2026-02-10T00:00:00Z');
INSERT INTO complaint_message VALUES ('MSG-CMP-2026-000001-002','CMP-2026-000001',2,'SYSTEM',NULL,'WEB','Received','2026-02-10T00:01:00Z');
INSERT INTO status_event VALUES ('STE-CMP-2026-000001-001','CMP-2026-000001',1,NULL,'NEW',NULL,'2026-02-10T00:00:00Z','created');
INSERT INTO status_event VALUES ('STE-CMP-2026-000001-002','CMP-2026-000001',2,'NEW','CLASSIFIED',NULL,'2026-02-10T00:01:00Z',NULL);
INSERT INTO assignment VALUES ('ASG-CMP-2026-000001-01','CMP-2026-000001',1,'AGT-0001','CARE','STANDARD','INITIAL','2026-02-10T00:02:00Z',NULL);
INSERT INTO sla_clock VALUES ('SLA-CMP-2026-000001','CMP-2026-000001','P4',24,168,'2026-02-10T00:00:00Z','2026-02-11T00:00:00Z','2026-02-17T00:00:00Z','2026-02-10T05:00:00Z',0,'STOPPED','2026-02-12T00:00:00Z');
INSERT INTO sla_pause_event VALUES ('PAU-CMP-2026-000001-01','SLA-CMP-2026-000001',1,'2026-02-10T06:00:00Z','2026-02-10T08:00:00Z','AWAITING_CUSTOMER');
INSERT INTO escalation_event VALUES ('ESC-CMP-2026-000001-C1-L1','CMP-2026-000001',1,'L1','2026-02-14T00:00:00Z',75.0,'AGT-0002');
INSERT INTO resolution VALUES ('RES-CMP-2026-000001','CMP-2026-000001',1,'APOLOGY','AGT-0001','2026-02-11T00:00:00Z',0,NULL,NULL,'Apologised');
INSERT INTO survey VALUES ('SRV-CMP-2026-000001','RES-CMP-2026-000001','CMP-2026-000001','2026-02-13T00:00:00Z','2026-02-13T01:00:00Z',4,'ok');

-- ---------- 2. Things the DATABASE must reject ----------
CREATE TEMP TABLE results (test text, expected text, outcome text);

-- Helpers. The probe statement is always rolled back; the outcome is held in a
-- variable (variables survive the rollback) and recorded afterwards, so a wrong
-- outcome can never disappear silently.
CREATE FUNCTION probe(label text, expected text, stmt text) RETURNS void AS $$
DECLARE accepted boolean := false; err text;
BEGIN
  BEGIN
    EXECUTE stmt;
    accepted := true;
    RAISE EXCEPTION 'rollback_probe';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'rollback_probe' THEN err := SQLERRM; END IF;
  END;
  INSERT INTO results VALUES (label, expected,
    CASE WHEN accepted THEN 'accepted' ELSE 'rejected' END);
END $$ LANGUAGE plpgsql;

CREATE FUNCTION expect_fail(label text, stmt text) RETURNS void AS $$
  SELECT probe(label, 'rejected', stmt) $$ LANGUAGE sql;
CREATE FUNCTION expect_ok(label text, stmt text) RETURNS void AS $$
  SELECT probe(label, 'accepted', stmt) $$ LANGUAGE sql;

-- ID formats
SELECT expect_fail('bad customer id format',   $q$INSERT INTO customer VALUES ('CUS-1','x','x1@example.test','1','Pune','STANDARD',false,now())$q$);
SELECT expect_fail('bad complaint id format',  $q$UPDATE complaint SET complaint_id='CMP-26-1' WHERE complaint_id='CMP-2026-000001'$q$);
-- Foreign keys: complaint with a customer that does not exist
SELECT expect_fail('complaint with unknown customer (FK)',
  $q$INSERT INTO complaint VALUES ('CMP-2026-000002','CUS-999999',NULL,NULL,NULL,'WEB','COMPLAINT','CAT06','MEDIUM','NEUTRAL','s','d',false,false,false,false,0,'P4',15,'{}','v1.3.2','NEW','2026-02-10T00:00:00Z',NULL,NULL)$q$);
-- Enums and ranges
SELECT expect_fail('invalid priority level P5',  $q$UPDATE complaint SET priority_code='P5' WHERE complaint_id='CMP-2026-000001'$q$);
SELECT expect_fail('invalid status value',       $q$UPDATE complaint SET status='DONE' WHERE complaint_id='CMP-2026-000001'$q$);
SELECT expect_fail('survey score 6',             $q$UPDATE survey SET score=6 WHERE survey_id='SRV-CMP-2026-000001'$q$);
SELECT expect_fail('negative order total',       $q$UPDATE customer_order SET total_amount=-1 WHERE order_id='ORD-2026-000001'$q$);
-- Arithmetic on the bridge table
SELECT expect_fail('order line total != qty x price', $q$UPDATE order_item SET line_total=1 WHERE order_id='ORD-2026-000001'$q$);
-- Uniqueness and history shape
SELECT expect_fail('duplicate message sequence', $q$INSERT INTO complaint_message VALUES ('MSG-CMP-2026-000001-009','CMP-2026-000001',1,'CUSTOMER','CUS-000001','WEB','dup',now())$q$);
SELECT expect_fail('second SLA clock for one complaint', $q$INSERT INTO sla_clock VALUES ('SLA-CMP-2026-000009','CMP-2026-000001','P4',24,168,now(),now(),now(),NULL,0,'RUNNING',NULL)$q$);
SELECT expect_fail('assignment ends before it starts',   $q$UPDATE assignment SET ended_at='2026-01-01T00:00:00Z' WHERE complaint_id='CMP-2026-000001'$q$);
SELECT expect_fail('complaint is its own parent',        $q$UPDATE complaint SET parent_complaint_id=complaint_id WHERE complaint_id='CMP-2026-000001'$q$);
SELECT expect_fail('system message with a sender',       $q$INSERT INTO complaint_message VALUES ('MSG-CMP-2026-000001-003','CMP-2026-000001',3,'SYSTEM','CUS-000001','WEB','x',now())$q$);
SELECT expect_fail('score without response time',        $q$UPDATE survey SET responded_at=NULL WHERE survey_id='SRV-CMP-2026-000001'$q$);
SELECT expect_fail('keyword type CATEGORY without category', $q$INSERT INTO keyword_rule VALUES (9999,'CATEGORY',NULL,'zzz')$q$);

-- ---------- 3. Things the DATABASE must ACCEPT (the validator catches them) ----------
-- These are the injected-anomaly shapes; rejecting them here would make them undetectable by the validator.
SELECT expect_ok('resolution before complaint was created',
  $q$UPDATE resolution SET resolved_at='2026-01-01T00:00:00Z' WHERE complaint_id='CMP-2026-000001'$q$);
SELECT expect_ok('survey sent before complaint closed',
  $q$UPDATE survey SET sent_at='2026-02-01T00:00:00Z' WHERE complaint_id='CMP-2026-000001'$q$);
SELECT expect_ok('SLA pause while status is not AWAITING_CUSTOMER',
  $q$INSERT INTO sla_pause_event VALUES ('PAU-CMP-2026-000001-02','SLA-CMP-2026-000001',2,'2026-02-10T12:00:00Z',NULL,'AWAITING_CUSTOMER')$q$);
SELECT expect_ok('safety issue stored with a low priority',
  $q$UPDATE complaint SET is_safety_issue=true, priority_code='P4' WHERE complaint_id='CMP-2026-000001'$q$);
SELECT expect_ok('repeat issue not linked (parent is null)',
  $q$INSERT INTO complaint VALUES ('CMP-2026-000003','CUS-000001','ORD-2026-000001','PRD-0001',NULL,'WEB','COMPLAINT','CAT06','MEDIUM','NEUTRAL','s','d',false,false,false,false,0,'P4',15,'{}','v1.3.2','NEW','2026-02-20T00:00:00Z',NULL,NULL)$q$);

-- ---------- 4. Reference data sanity ----------
INSERT INTO results SELECT 'priority bands cover scores 0..infinity with no gap',
  'true',
  (SELECT (min(min_score)=0
       AND bool_and(next_min IS NULL OR max_score + 1 = next_min)
       AND count(*) = 4)::text
   FROM (SELECT priority_code, min_score, max_score,
                lag(min_score) OVER (ORDER BY min_score DESC) AS next_min
         FROM priority_band) b);
INSERT INTO results SELECT 'exactly 10 categories',        '10', (SELECT count(*)::text FROM category);
INSERT INTO results SELECT 'exactly 4 priority levels',    '4',  (SELECT count(*)::text FROM priority_level);
INSERT INTO results SELECT 'every category has a team',    '0',  (SELECT count(*)::text FROM category WHERE team_code IS NULL);
INSERT INTO results SELECT 'SLA hours are P1 1/24, P4 24/168', 'true',
  (SELECT (bool_and(CASE priority_code WHEN 'P1' THEN response_hours=1 AND resolution_hours=24
                                       WHEN 'P4' THEN response_hours=24 AND resolution_hours=168 ELSE true END))::text FROM sla_matrix);

-- ---------- Report ----------
SELECT test, expected, outcome, CASE WHEN outcome = expected THEN 'PASS' ELSE 'FAIL' END AS result
FROM results ORDER BY 4 DESC, 1;

DO $$
DECLARE bad int; total int;
BEGIN
  SELECT count(*) INTO total FROM results;
  SELECT count(*) INTO bad FROM results WHERE outcome <> expected;
  IF total <> 25 THEN RAISE EXCEPTION 'expected 25 results but found % (a test is missing)', total; END IF;
  IF bad > 0 THEN RAISE EXCEPTION '% smoke test(s) failed', bad; END IF;
  RAISE NOTICE 'ALL % SMOKE TESTS PASSED', total;
END $$;

ROLLBACK;
