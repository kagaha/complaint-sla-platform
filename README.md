# Complaint Management and SLA Enforcement Platform

**Repository name:** `complaint-sla-platform`

Classify complaints, assign owners, enforce SLAs, and track resolution and customer communication, on top of a reproducible synthetic dataset.

**Stack:** React + TypeScript (frontend), Java Spring Boot + Spring Data JPA + Spring Security (backend), PostgreSQL (database), Docker Compose.

> Status: skeleton. See `docs/RULES_AND_ASSUMPTIONS.md` for every business rule.

## Repository layout

```
complaint-sla-platform/
├── README.md
├── docker-compose.yml
├── .gitignore
├── docs/
│   ├── RULES_AND_ASSUMPTIONS.md   all business rules (v1.3.2)
│   ├── SESSION_SUMMARY.md         project context for resuming work
│   ├── AI_USAGE.md                AI disclosure
│   └── prompts/                   saved prompt history
├── generator/                     seeded data generator, anomaly injector, validator
├── backend/                       Spring Boot application
├── frontend/                      React + TypeScript application
└── data/                          exported CSV / JSON / SQL, ground_truth.csv, validation summary
```

## Quick start (planned)

```bash
docker compose up --build
# frontend: http://localhost:5173
# backend:  http://localhost:8080  (Swagger at /swagger-ui.html)
```

Generate data (planned):

```bash
./generator/run.sh --seed 20261022 --scale full
```

Prove reproducibility (planned):

```bash
./generator/verify_reproducibility.sh
```

## Build plan

1. Rules and assumptions (done)
2. Schema, migrations, data dictionary
3. Generator, baseline data, anomaly injection, ground truth
4. Validator and reproducibility check
5. Backend APIs, rules engine, security
6. Frontend: dashboard, queue, complaint 360 view
7. Tests, polish, demo rehearsal

## AI usage

See `docs/AI_USAGE.md` and `docs/prompts/`.
