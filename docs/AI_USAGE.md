# AI Usage Disclosure

**Tool used:** Claude (free plan).

Prompt history is listed in `docs/prompts/README.md`.

This file is updated after every working session. Entries describe only work that has actually happened.

## Where AI accelerated my work

- Breaking the problem statement into two deliverables (a seeded data generator and a workflow app).
- Explaining terms such as SLA, priority floor, ground truth and anomaly injection.
- Drafting the first version of `RULES_AND_ASSUMPTIONS.md` and the repo skeleton.
- Drafting worked examples for the priority and floor rules.
- Suggesting the technology choices (for example PostgreSQL instead of SQL Server because it runs easily in Docker).

## Where I relied on AI heavily

- The first draft of the structure and wording of `RULES_AND_ASSUMPTIONS.md`.
- The initial proposal of the 21 scenarios and the suggested point weights (these were then reduced and changed by me, see below).
- Project scaffolding (README, docker-compose, .gitignore).

Later work (generator, backend, frontend) will be added here when it happens.

## What I personally reviewed, changed or validated

Decisions I made while reviewing the AI's drafts:

- I questioned the separate "category base points" step, so it was merged into the single factor table.
- I required that defective product, missing order, wrong item and late delivery carry points, because they are real problems that should not fall to the lowest priority.
- I asked that floors show **P4** instead of "none".
- I chose the P1 score threshold of **100** instead of the suggested 110.
- I asked to remove less important factors (public channel, frequent complainer, rude staff report, refund amount at risk) to keep the rules explainable.
- I asked for plainer wording in the floor examples after "calm customer with a legal threat" was confusing, and the document now defines tone and legal threat as independent checks.

Validation still to do (to be filled in with real results): reproducibility check, validator precision and recall, priority distribution calibration, unit tests for the rules engine.

## Cases where AI was wrong or needed correcting

| What the AI did | What I did |
|---|---|
| Added category base points as a separate step that duplicated the factor list | Questioned it, and it was merged into one factor table |
| Used a confusing "calm customer with a legal threat" example | Asked for clarification, and the wording was changed and definitions were added |
| Suggested a P1 threshold of 110 as an untested guess | Replaced it with 100, to be calibrated on the generated data |

## Log

| Date | Task | AI help | My review or change |
|---|---|---|---|
| 2026-10-26 | Problem analysis, rules doc v1, repo skeleton | Drafted | Reviewed, to be tuned by me |
| 2026-10-26 | Rules v1.1: category base points, scenario catalogue, floors, request_type | Drafted from my requirements | I decided that defective, missing, wrong-item and late-delivery complaints must carry points, that floors show P4 instead of none, and kept 4 priority levels |
| 2026-10-26 | Rules v1.2 and v1.3: merged base points into factors, removed minor factors, merged tables, P1 threshold 100 | Applied my decisions | I questioned the separate base-points step, chose the P1 threshold of 100, and asked to drop public channel and other minor factors |
| 2026-10-26 | Rules v1.3.1 and v1.3.2: floor examples, wording clarification, session summary | Drafted | I asked for the floor examples and the clearer wording |
| 2026-10-27 | Repo naming and structure, AI usage and prompt history files | Drafted | Reviewed |
