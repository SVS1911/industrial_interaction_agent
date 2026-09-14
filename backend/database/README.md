# Database

`agent28_synthetic_database.sql` is the database source of truth for this backend.

It creates the Agent 28 development database with the PostgreSQL schemas, tables, Agent 28
extensions, views, functions, triggers, synthetic data, agent outputs, human-review records,
alerts, evidence and KPI data defined by the source SQL.

Run it only against an empty development database.


The dedicated `engagement.guest_lecture` table and `engagement.v_guest_lecture_register` view are defined in `agent28_synthetic_database.sql`; no separate guest-lecture migration is required.
