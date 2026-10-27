# Rules and Assumptions (v1.3.2)

This document is the single source of truth for every business rule. The generator, the rules engine, the validator and the UI must all follow it. Nothing here is random: every priority, deadline, escalation and status is derived from these rules.

## 1. Scope and assumptions

| # | Assumption | Reason |
|---|---|---|
| A1 | "Agent" means a human support agent (a row in `support_agent`), not an AI agent. | Problem statement wording: "assign team/agent". |
| A2 | All data is synthetic. Names, emails and phones are fake. The vulnerable-customer flag is synthetic only. | Lawful use guidance. |
| A3 | Currency is INR. Order value bands are in INR. | Local context. |
| A4 | SLA time is measured in **calendar hours** (24x7 support). | Simpler, fully reproducible. Business-hours SLA is listed as a future improvement. |
| A5 | The generator uses a fixed seed `20261022` and a fixed "as of" clock `2026-10-22T00:00:00Z`. System time is never used. | Reproducibility. |
| A6 | Classification is keyword and rule based, not ML. | Explainable and deterministic. |
| A7 | History is append-only. State changes are new event rows. Nothing is overwritten. | Traceability requirement. |
| A8 | External datasets are not used. Everything is generated. | Avoids licensing risk. |
| A9 | There are exactly **4 priority levels** (P1 to P4). Information requests are modelled with `request_type`, not as a fifth level. | The statement asks for 4 priority levels. |
| A10 | Priority floors only raise a priority, never lower it. The only cap is for information requests (always P4). | Keeps the rules simple and predictable. |

## 2. Volumes (baseline, parameterised by `--scale`)

| Entity | Full | Starter (10 percent) |
|---|---|---|
| Customers | 5,000 | 500 |
| Orders | 8,000 | 800 |
| Complaints | 2,000 | 200 |
| Messages | 6,000 | 600 |
| Categories | 10 | 10 |
| Priority levels | 4 | 4 |

Starter and full use the same generator code. Only the scale parameter differs.

## 3. ID conventions

| Entity | Format | Example |
|---|---|---|
| Customer | `CUS-######` | CUS-000001 |
| Order | `ORD-2026-######` | ORD-2026-000001 |
| Complaint | `CMP-2026-######` | CMP-2026-000001 |
| Message | `MSG-<complaint-id>-###` | MSG-CMP-2026-000001-001 |
| SLA clock | `SLA-<complaint-id>` | SLA-CMP-2026-000001 |
| Resolution | `RES-<complaint-id>` (reopen adds `-2`, `-3`) | RES-CMP-2026-000001 |

IDs are zero padded, immutable, and referenced exactly the same in every file.

## 4. Categories (10)

| Code | Category | Default severity | Team |
|---|---|---|---|
| CAT01 | Product Safety Hazard | CRITICAL | Safety Response |
| CAT02 | Defective Product | HIGH | Product Support |
| CAT03 | Missing Order | HIGH | Logistics |
| CAT04 | Refund Pending | MEDIUM | Billing |
| CAT05 | Wrong Item Delivered | MEDIUM | Fulfilment |
| CAT06 | Late Delivery | MEDIUM | Logistics |
| CAT07 | Billing or Double Charge | HIGH | Billing |
| CAT08 | Warranty Claim | MEDIUM | Product Support |
| CAT09 | Service Behaviour | LOW | Quality |
| CAT10 | General Enquiry | LOW | Customer Care |

A complaint with a legal threat is routed to the **Escalations** team regardless of category.

### Classification rule
1. Scan complaint text (lower case) for keywords per category, in the order CAT01 to CAT10.
2. The category with the most keyword hits wins. Ties are broken by the lower category code (so safety wins ties).
3. No hits means CAT10.
4. Safety keywords (smoke, fire, burn, shock, sparks, explode, injury, choking) set `is_safety_issue = true` regardless of the winning category.
5. Legal keywords (lawyer, legal notice, consumer court, sue, advocate) set `is_legal_threat = true`.
6. `request_type` is `INFORMATION_REQUEST` only when the category is CAT10, there are information keywords (how, what is, policy, invoice copy, where can I) and there are no problem, safety or legal keywords. Otherwise it is `COMPLAINT`.

## 5. Priority rule

Priority is decided in three steps. Rule values are stored in the `priority_rule` table (with effective dates) so the admin can change them without code changes.

### 5.1 Request type

| request_type | Meaning | Handling |
|---|---|---|
| COMPLAINT | Something went wrong | Full flow: priority steps below, SLA, escalation up to L3, survey |
| INFORMATION_REQUEST | A question, no problem reported | Always **P4** (capped). Escalation only up to L1. Survey optional |

The steps below apply to `COMPLAINT` records.

### 5.2 Step 1: add up the factor points

There is no separate starting score. Priority comes only from the factors below, and every factor that applies adds its points.

Each factor also has a **floor**: a guaranteed minimum priority. A floor of **P4** means no guaranteed minimum, because P4 is already the lowest level.

| Factor | Condition | Points | Floor |
|---|---|---|---|
| Safety | `is_safety_issue` (fire, sparks, shock, injury) | +100 | **P1** |
| Legal threat | `is_legal_threat` | +40 | **P2** |
| Issue type: Missing Order | category CAT03 | +30 | **P3** |
| Issue type: Defective Product | category CAT02 | +30 | P4 |
| Issue type: Billing or Double Charge | category CAT07 | +30 | P4 |
| Issue type: Refund Pending | category CAT04 | +15 | P4 |
| Issue type: Wrong Item Delivered | category CAT05 | +15 | **P3** |
| Issue type: Late Delivery | category CAT06 | +15 | P4 |
| Issue type: Warranty Claim | category CAT08 | +15 | P4 |
| Issue type: Service Behaviour, General Enquiry, Product Safety Hazard | categories CAT09, CAT10, CAT01 | 0 | P4 |
| Sentiment | VERY_NEGATIVE / NEGATIVE / NEUTRAL | +30 / +15 / 0 | P4 |
| Order value | above 50,000 / above 10,000 | +20 / +10 | P4 |
| Recurrence | same customer, same product and same category within 90 days | +25 | P4 |
| Vulnerable customer | `is_vulnerable` | +20 | P4 |
| Reopened | complaint was reopened | +20 | **P3** |
| Double or unauthorized charge | Billing category, text mentions a double or unauthorized charge | +20 | **P2** |
| Order overdue | Missing Order, more than 7 days past expected delivery | +15 | **P2** |
| Refund delay | Refund Pending, pending more than 14 days | +10 | **P3** |
| Product trend | 5 or more complaints on the same product within 7 days (applies to the 5th and later) | +20 | **P2** |

Notes:
- Product Safety Hazard scores 0 as an issue type because the safety factor already covers it.
- A legal threat is routed to the Escalations team. A product trend raises a product alert for the Product Support team.
- `channel` is stored on every complaint but does not affect priority.

Definitions:
- **Late delivery**: the order was delivered after the promised delivery date. A **missing order** never arrived at all.
- **Neutral (calm) sentiment**: the message tone has no angry or distressed wording. It scores 0 points.
- **Legal threat**: the text mentions legal action (lawyer, legal notice, consumer court, sue, advocate). It is flagged by keywords, **independent of tone**. A polite, formal message can still contain a legal threat, and that is the case where the score alone would under-rate the complaint and the floor protects it.

### 5.3 Step 2: score to priority

**score = sum of all factor points that apply**

| Priority | Name | Score |
|---|---|---|
| P1 | CRITICAL | 100 or more, **or any safety issue** |
| P2 | HIGH | 60 to 99 |
| P3 | MEDIUM | 25 to 59 |
| P4 | LOW | below 25 |

The bands are the starting values. They are calibrated against the generated data (target spread: about 5 to 8 percent P1, 20 percent P2, 40 percent P3, 30 percent P4) and every change is recorded in the changelog.

### 5.4 Step 3: floors and cap

**Final priority = the highest of (priority from the score, every floor that applies).**

- A floor only raises a priority, never lowers it.
- If several floors apply, the highest one wins.
- The only cap is for information requests: they are always P4.

**How a floor works, step by step**

Levels from highest to lowest: P1, P2, P3, P4. A floor of P2 means the complaint can end up P2 or P1, but never P3 or P4.

*Example A: the floor lifts the priority.* The order arrived after the promised date (a late delivery). The customer writes in a polite, formal tone (neutral sentiment, 0 points) but says: "I will take this to consumer court". The tone is calm, yet the message still contains a legal threat, because tone and legal threat are separate checks.

| Step | Result |
|---|---|
| Late delivery (issue type) | +15 |
| Legal threat | +40 |
| Score | 55 |
| Priority from the score (25 to 59) | P3 |
| Floor for legal threat | P2 |
| **Final priority** | **P2** (the floor raised it from P3) |

*Example B: several floors apply, the highest wins.* A wrong item is delivered. The customer writes in a polite, formal tone (neutral sentiment) and mentions legal action.

| Step | Result |
|---|---|
| Score: wrong item +15, legal threat +40 | 55 |
| Priority from the score | P3 |
| Floors that apply | P3 (wrong item), P2 (legal threat) |
| Highest floor | P2 |
| **Final priority** | **P2** |

*Example C: the floor never lowers the priority.* A missing order, very negative customer, vulnerable customer, order above 50,000 and a repeat complaint.

| Step | Result |
|---|---|
| Score: 30 + 30 + 20 + 20 + 25 | 125 |
| Priority from the score (100 or more) | P1 |
| Floor for Missing Order | P3 |
| **Final priority** | **P1** (the floor is lower than the score, so it changes nothing) |

*Example D: no floor applies.* A late delivery, neutral sentiment, order of 2,000. The score is 15, which is P4. The only floor is P4, which means no guaranteed minimum, so the final priority is **P4**.

### 5.5 Worked examples

| Case | Calculation | Result |
|---|---|---|
| Kettle sparks, very negative customer | 100 + 30 = 130, safety floor P1 | **P1 CRITICAL** |
| Defective product, very negative, order above 50,000, repeat complaint | 30 + 30 + 20 + 25 = 105 | **P1 CRITICAL** |
| Defective product, neutral, order 2,000 | 30 | **P3 MEDIUM** |
| Late delivery, neutral, order 2,000 | 15 | **P4 LOW** |
| Late delivery, negative (+15), order 12,000 (+10), repeat (+25), vulnerable (+20) | 15 + 15 + 10 + 25 + 20 = 85 | **P2 HIGH** |
| Late delivery, polite and formal tone (neutral), legal threat | 15 + 40 = 55 gives P3, but the legal floor is P2 | **P2 HIGH** |
| "What is your return policy?" | information request, capped | **P4 LOW** |

### 5.6 What is stored for every complaint

`request_type`, `category_code`, `severity`, `priority` (final), `priority_score`, `priority_breakdown` (each factor that applied and its points, floors applied) and `rule_version`. This lets the UI answer "why is this P1?" and lets the validator recompute the priority from the rules.

## 6. SLA matrix (hours)

| Priority | First response | Resolution |
|---|---|---|
| P1 | 1 | 24 |
| P2 | 4 | 48 |
| P3 | 8 | 96 |
| P4 | 24 | 168 |

- `response_due = created_at + response_hours`
- `resolution_due = created_at + resolution_hours + total_paused_hours`
- The clock **pauses only** when status is `AWAITING_CUSTOMER` and resumes when the customer replies. Any pause outside this status is invalid (anomaly).
- Information requests use the P4 row.

## 7. Escalation thresholds

Measured as elapsed active SLA time divided by the resolution SLA.

| Threshold | Action | Escalation level |
|---|---|---|
| 75 percent | Warning to team lead | L1 |
| 100 percent | Breach, escalate to manager | L2 |
| 150 percent | Escalate to head of operations | L3 |

Each escalation is an append-only event with timestamp and level. Information requests escalate only up to L1.

## 8. Lifecycle (allowed transitions)

```
NEW -> CLASSIFIED -> ASSIGNED -> IN_PROGRESS -> RESOLVED -> CLOSED
IN_PROGRESS <-> AWAITING_CUSTOMER
RESOLVED -> REOPENED -> IN_PROGRESS
CLOSED   -> REOPENED -> IN_PROGRESS   (within 14 days of closure)
```

Anything else is an invalid transition and is reported by the validator. A reopen creates a new resolution cycle and re-runs the priority rule with the reopened factor. The earlier resolution, messages and assignments are kept.

## 9. Assignment rule

1. Category maps to a team (see the table in section 4). A legal threat overrides this and goes to Escalations.
2. P1 and P2 go to the senior queue. P3 and P4 go to the standard queue.
3. Within the team, pick the agent with the lowest open workload. Ties are broken by agent ID.
4. Every reassignment adds a new `assignment` row and closes the previous one with `ended_at`.

## 10. Survey rule

A survey is created only **after** `CLOSED`. The score is from 1 to 5. The distribution is driven by outcome: SLA met, not reopened and a fast resolution give higher scores. Breached or reopened complaints give lower scores. Surveys for information requests are optional.

## 11. Injected anomalies (ground truth)

Baseline data is generated clean first. About 1 to 2 percent of complaints are then altered, one anomaly per affected complaint, and labelled in `ground_truth.csv`.

| issue_type | What is injected | How the validator detects it |
|---|---|---|
| COMPLAINT_NO_CUSTOMER | `customer_id` set to a non-existent ID | FK check |
| RESOLUTION_BEFORE_COMPLAINT | `resolved_at` earlier than `created_at` | Date ordering check |
| SLA_PAUSE_INCORRECT | Pause event while status is not AWAITING_CUSTOMER | Clock vs status events |
| REPEAT_NOT_LINKED | Same customer, product and category within 90 days but `parent_complaint_id` is null | Recurrence scan |
| SAFETY_LOW_PRIORITY | Safety issue assigned to P3 or P4 queue | Safety vs priority check |
| SURVEY_BEFORE_CLOSURE | `survey_at` earlier than `closed_at` | Date ordering check |
| FLOOR_NOT_APPLIED (extra, not required by the statement) | A floor scenario (for example legal threat) left below its floor | Recompute priority from rules and compare |

The ground truth is **never** read by the classifier, rules engine or validator. It is only used afterwards to compute precision and recall.

## 12. Validation checks

Primary key uniqueness, foreign key integrity, allowed enums, date ordering, arithmetic reconciliation (order total equals sum of items), lifecycle transitions, duplicate detection, priority and SLA reproducibility from the rules (score recomputed and compared with the stored value), floors honoured, information requests always P4, and status events reconciling with the final complaint state.

## 13. Known limitations (v1.3)

- Calendar-hour SLA only, no holidays or business hours.
- Keyword classification will miss unusual wording.
- Sentiment is assigned by generator rules, not by NLP.
- Single currency and single time zone (UTC stored, IST shown).
- Point weights and bands are initial values, to be calibrated on the generated data.

## 14. Changelog

| Version | Date | Change |
|---|---|---|
| v1.3.2 | 2026-10-26 | Replaced "calm customer" wording with "polite, formal tone (neutral sentiment)" in the floor examples and added definitions for late delivery, neutral sentiment and legal threat. |
| v1.3.1 | 2026-10-26 | Added four worked floor examples (A to D) to section 5.4. |
| v1.3 | 2026-10-26 | Removed less important factors (public channel, frequent complainer, rude staff report, refund amount at risk). Merged the factor table and the scenario catalogue into one table with a Floor column. P1 score threshold set to 100 and the P2 band is now 60 to 99. |
| v1.2 | 2026-10-26 | Removed the separate category base-points step. Issue type is now an ordinary factor in the single factor list, with the same point values. Scenario table has one Points column. |
| v1.1 | 2026-10-26 | Added category base points, 21-scenario catalogue with floors, `request_type` for information requests (still 4 priority levels), new factors (legal, channel, reopened, frequent complainer, product trend, refund, overdue), new score bands, extra anomaly FLOOR_NOT_APPLIED. |
| v1.0 | 2026-10-26 | First version: 5 priority factors, SLA matrix, escalation, lifecycle, anomalies. |
