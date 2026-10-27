# Session Summary and Project Context

Written 2026-10-26 so a new session can pick up exactly where this one stopped. Read this first, then `docs/RULES_AND_ASSUMPTIONS.md` (the single source of truth for all business rules).

## 1. The assignment

Build an end-to-end **Complaint Management and SLA Enforcement** solution: classify complaints, assign owners, enforce SLAs, track resolution and customer communication.

It has two deliverables:

1. **A seeded synthetic data generator** (most of the marks are here): 5,000 customers, 8,000 orders, 2,000 complaints, 6,000 messages, plus assignments, SLA clocks, resolutions and surveys. All outcomes come from documented rules, never independent randomness.
2. **A working web app** on top of the data that makes the workflow visible and demo-able.

Reviewer criteria (from the assignment screenshot):

| # | Criterion |
|---|---|
| 1 | Make it run: working code, clear install, configure, run and verify steps |
| 2 | Show your work: public GitHub repo, meaningful commits |
| 3 | Use LLMs transparently: submit prompt history, explain where AI helped, where it was relied on heavily, and what was personally reviewed or changed |
| 4 | Make reasoning visible: problem, assumptions, decisions, trade-offs, testing, limitations |
| - | Be ready to walk through the solution live |

## 2. Decisions made

| Topic | Decision |
|---|---|
| Frontend | React + TypeScript (Vite) |
| Backend | Java Spring Boot, Spring Data JPA, Spring Security (JWT, roles), Flyway, OpenAPI |
| Database | PostgreSQL (recommended over SQL Server because it runs easily in Docker) |
| Generator | Java, inside the same repo, deterministic (fixed seed 20261022, fixed clock 2026-10-22T00:00:00Z, no system time, stable ordering) |
| Packaging | Docker Compose |
| "Agent" | A human support agent (table row). No AI agents in the product |
| Classification | Keyword and rule based, explainable and deterministic |
| Priority levels | Exactly 4 (P1 CRITICAL, P2 HIGH, P3 MEDIUM, P4 LOW). An "INFO" level was rejected because the statement says 4 levels. Information requests use `request_type = INFORMATION_REQUEST` and are always P4 |
| SLA time | Calendar hours (24x7) |
| Data | All synthetic, no external datasets |
| Scale | `--scale starter` (10 percent) and `--scale full` use the same generator |

## 3. Final rules in brief (v1.3.2)

**Priority** = sum of factor points, then floors, then cap.

| Factor | Points | Floor |
|---|---|---|
| Safety (fire, sparks, shock, injury) | +100 | P1 |
| Legal threat | +40 | P2 |
| Issue type: Missing Order / Defective / Billing | +30 | P3 (Missing Order) else P4 |
| Issue type: Refund / Wrong Item / Late Delivery / Warranty | +15 | P3 (Wrong Item) else P4 |
| Sentiment very negative / negative / neutral | +30 / +15 / 0 | P4 |
| Order value above 50,000 / above 10,000 | +20 / +10 | P4 |
| Recurrence (same customer, product, category within 90 days) | +25 | P4 |
| Vulnerable customer | +20 | P4 |
| Reopened | +20 | P3 |
| Double or unauthorized charge | +20 | P2 |
| Order overdue more than 7 days | +15 | P2 |
| Refund pending more than 14 days | +10 | P3 |
| Product trend (5 or more complaints on a product in 7 days) | +20 | P2 |

- Bands: P1 is 100 or more or any safety issue, P2 is 60 to 99, P3 is 25 to 59, P4 is below 25. To be calibrated against generated data (target about 5 to 8 percent P1, 20 percent P2, 40 percent P3, 30 percent P4).
- **Floor** = guaranteed minimum priority. Final priority = highest of (score band, every floor that applies). A P4 floor means no minimum. Floors never lower a priority. Information requests are capped at P4.
- Factors removed on purpose: public channel, frequent complainer, rude staff report, refund amount at risk. `channel` is still stored but does not affect priority.

**SLA matrix (first response / resolution, hours):** P1 1/24, P2 4/48, P3 8/96, P4 24/168. The clock pauses only in `AWAITING_CUSTOMER`.

**Escalation:** 75 percent of the SLA is L1 (team lead), 100 percent is L2 (manager), 150 percent is L3 (head of operations). Information requests escalate only to L1.

**Lifecycle:** NEW, CLASSIFIED, ASSIGNED, IN_PROGRESS, AWAITING_CUSTOMER (loops back to IN_PROGRESS), RESOLVED, CLOSED. REOPENED is allowed from RESOLVED or CLOSED (within 14 days) and returns to IN_PROGRESS. History is append-only.

**Assignment:** category maps to a team, legal threat goes to Escalations, P1 and P2 go to the senior queue, the agent with the lowest open workload is picked, and every reassignment adds a new row.

**Survey:** only after CLOSED, score 1 to 5, driven by outcome (SLA met, not reopened gives higher scores).

**Teams:** Safety Response, Product Support, Logistics, Billing, Fulfilment, Quality, Customer Care, Escalations.

**IDs:** `CUS-000001`, `ORD-2026-000001`, `CMP-2026-000001`, `MSG-<complaint-id>-001`, `SLA-<complaint-id>`, `RES-<complaint-id>` (reopen adds -2, -3).

**Categories (10):** Product Safety Hazard, Defective Product, Missing Order, Refund Pending, Wrong Item Delivered, Late Delivery, Billing or Double Charge, Warranty Claim, Service Behaviour, General Enquiry.

**Six required anomalies (plus one extra), labelled in `ground_truth.csv`:** complaint without customer, resolution before complaint, SLA clock pauses incorrectly, repeat issue not linked, critical safety issue in a low-priority queue, survey before closure, and extra FLOOR_NOT_APPLIED. Baseline data is generated clean first, then about 1 to 2 percent of complaints are broken. The ground truth is never read by the classifier or validator. It is used afterwards for precision and recall.

## 4. Concepts clarified with the user (explain in plain language)

- **Anomalies** test whether the validator catches bad data. The generator must produce clean data first. Valid boundary and exception cases (exactly at a threshold, reopened, legal threat) are separate and need no label.
- **Floor** is a guaranteed minimum. Example: late delivery (+15) plus legal threat (+40) scores 55, which is P3, but the legal floor lifts it to P2.
- **Calm tone and legal threat are independent.** A polite, formal message can still threaten legal action. Sentiment measures tone, legal threat is keyword-flagged.
- **Starter** is the 10 percent dataset made by the same generator.
- **Why the P1 threshold is 100:** a tunable dial, calibrated on the generated data.

## 5. Repo state

Location in the workspace: `/home/claude/complaint-platform`. **It is not on GitHub yet and the workspace may not persist, so push or download it.**

```
README.md, .gitignore, docker-compose.yml (PostgreSQL only)
docs/RULES_AND_ASSUMPTIONS.md   v1.3.2
docs/AI_USAGE.md                template with a log table
docs/SESSION_SUMMARY.md         this file
docs/prompts/README.md          save the chat exports here
generator/ backend/ frontend/ data/   empty placeholders
```

Commits so far: skeleton, rules v1.1, v1.2, v1.3, v1.3.1, and the v1.3.2 wording update. Nothing has been built or run yet.

## 6. Next steps, in order

1. **Database schema, Flyway migrations and data dictionary** for all 11 entities plus bridge and event tables: Customer, Product, Order, `OrderItem` (bridge), Complaint, ComplaintMessage, Category, PriorityRule, Assignment, SLAClock (plus pause events), StatusEvent, EscalationEvent, Resolution, Survey, SupportAgent, Team. Include PK, FK, cardinality, effective dates and lifecycle states.
2. Generator: master data, then transactions, then events, then anomaly injection and `ground_truth.csv`.
3. Validator (PK, FK, enums, date order, reconciliation, lifecycle, duplicates, priority and SLA recomputation, floors) and a precision and recall report.
4. Reproducibility script: run twice with the same seed and compare row counts and SHA-256 checksums.
5. Backend APIs, rules engine, scheduled escalation job, security and roles (requester, process owner, approver, operations analyst, system administrator).
6. Frontend: executive dashboard, complaint queue with SLA timers, Complaint 360 view (timeline, "why is this P1?" breakdown), anomaly center, admin rules screen.
7. Tests, README with run and verify steps, `AI_USAGE.md` filled in with real reviews and corrections, ER diagram, demo rehearsal.

## 7. Open items    

- Keyword lists for categories, safety, legal and information requests need the user's input.
- Point weights and score bands are initial values to calibrate once data exists.
- Decide whether to add an ER diagram as an image or Mermaid in the docs.

## 8. User preferences and constraints

- Explain things in **simple, plain language** with small concrete examples. Jargon causes confusion.
- Free Claude plan only, so the AI usage evidence is the saved chat history plus `AI_USAGE.md`. The full chat still needs to be copied into `docs/prompts/01-problem-understanding.md`.
- Wants the project to look polished and be fully demo-ready, with every rule explainable live.
- Prefers fewer, more important rules over many minor ones.
- Commit regularly with meaningful messages. Commit trailers used: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` and the Claude-Session line.

## 9. How to resume

Tell the new session: "Read `docs/SESSION_SUMMARY.md` and `docs/RULES_AND_ASSUMPTIONS.md`, then continue with step 1 of the next steps (database schema and data dictionary)." If the files are gone, paste this summary and ask for the rules document to be rebuilt from section 3.
