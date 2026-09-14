-- =====================================================================
--  AGENT 28 — INDUSTRY INTERACTION AGENT
--  agent28_synthetic_database.sql
--
--  ONE FILE that builds a complete, separate development database for
--  Agent 28 and fills it with realistic SYNTHETIC data.
--
--  WHAT IS INSIDE
--    Part 1  Extensions, 13 schemas, audit + session helper functions
--    Part 2  62 tables copied from the organiser's schema_full.sql — only the
--            ones Agent 28 reads or writes (core, people, identity, curriculum,
--            academics, research, engagement, placement, studentlife,
--            governance, quality, knowledge, agentops)
--    Part 3  Agent 28 objects: 4 extended tables, 8 new tables, 2 triggers,
--            10 views (identical to agent28_001_schema.sql)
--    Part 4  Institution, departments, calendar, faculty, users, 630 students,
--            18 courses (Agent 2 content), offerings and lesson plans
--    Part 5  30 partners, 42 companies, contacts, expertise, senior alumni,
--            40 MoUs with documents, extraction results and deliverables
--    Part 6  Agent registry and runs, ~200 industry activities, course
--            alignment, events, offers, internships, alumni, student feedback
--    Part 7  What the agent produced: evidence links, deliverable status,
--            monthly health snapshots, alerts, follow-ups, target-partner
--            recommendations with human review, accreditation evidence, KPIs
--    Part 8  Roles and grants;  Part 9  row-count summary
--
--  HOW TO RUN (pick one)
--    Local PostgreSQL 14+ :
--        createdb agent28_dev
--        psql -d agent28_dev -v ON_ERROR_STOP=1 -f agent28_synthetic_database.sql
--    Supabase / Neon :
--        create a NEW project (or a new Neon branch/database), open the SQL
--        editor, paste this file and run it — or run the psql command above
--        with the project's DIRECT connection string (not the pooler).
--    Run it on an EMPTY database. It is one transaction: it either loads
--    completely or changes nothing.
--
--  DEVIATIONS FROM THE ORGANISER'S SCHEMA (deliberate, for a standalone dev DB)
--    * core.set_row_audit() uses nullif(current_setting('app.user_id', true), '')
--      so audited writes do not fail on pooled connections.
--    * research.project.proposal_id and agentops.alert.risk_flag_id keep their
--      columns but not their FKs (research.proposal and agentops.risk_flag are
--      outside Agent 28's scope). Re-add the FKs when merging into the platform.
--    * Row-level security policies of the organiser's file are not included
--      (none of them protect an Agent 28 table).
--    * ALTER DEFAULT PRIVILEGES is added so tables you create later get grants.
--
--  DATA IS FICTIONAL. Names, companies, e-mails (*.example), phone numbers and
--  documents are invented. Accreditation criteria use placeholder codes.
--  Demo "today" = 2026-09-11. Views that use current_date will shift slightly
--  if you load or query the data later; stored alerts and snapshots will not.
--
--  To rebuild from scratch in the same database, first run:
--    DROP SCHEMA IF EXISTS core, people, identity, curriculum, academics, research,
--      engagement, placement, studentlife, governance, quality, knowledge, agentops CASCADE;
-- =====================================================================


BEGIN;

DO $$
BEGIN
  IF to_regclass('engagement.industry_partner') IS NOT NULL THEN
    RAISE EXCEPTION 'This database already contains Agent 28 tables. Use an empty database, or run the DROP SCHEMA statement from the file header first.';
  END IF;
END $$;

-- =====================================================================
-- PART 1 — FOUNDATION: extensions, schemas, platform helper functions
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid() on PG12; core from PG13
CREATE EXTENSION IF NOT EXISTS pg_trgm;    -- trigram similarity for partner / topic matching

-- Only the domain schemas Agent 28 touches (same names as the universal schema).
CREATE SCHEMA IF NOT EXISTS core;         -- institution, calendar, code lists
CREATE SCHEMA IF NOT EXISTS people;       -- person, faculty, student
CREATE SCHEMA IF NOT EXISTS identity;     -- users, roles, consent
CREATE SCHEMA IF NOT EXISTS curriculum;   -- Agent 2 course content
CREATE SCHEMA IF NOT EXISTS academics;    -- offerings and lesson plans (current teaching)
CREATE SCHEMA IF NOT EXISTS research;     -- sponsored projects / consultancy
CREATE SCHEMA IF NOT EXISTS engagement;   -- Agent 28 home
CREATE SCHEMA IF NOT EXISTS placement;    -- Agents 49-52 (internships, offers, alumni)
CREATE SCHEMA IF NOT EXISTS studentlife;  -- generic action items
CREATE SCHEMA IF NOT EXISTS governance;   -- compliance frameworks
CREATE SCHEMA IF NOT EXISTS quality;      -- feedback, accreditation evidence, KPIs
CREATE SCHEMA IF NOT EXISTS knowledge;    -- MoU documents and extraction
CREATE SCHEMA IF NOT EXISTS agentops;     -- agent registry, runs, outputs, alerts

-- Row audit trigger. Same as the universal core.set_row_audit() EXCEPT for
-- nullif(..., ''): the universal version raises "invalid input syntax for type
-- uuid" on pooled connections after any SET LOCAL app.user_id (reproduced).
CREATE OR REPLACE FUNCTION core.set_row_audit() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_at := COALESCE(NEW.created_at, now());
    NEW.created_by := COALESCE(NEW.created_by, nullif(current_setting('app.user_id', true), '')::uuid);
  END IF;
  NEW.updated_at := now();
  NEW.updated_by := nullif(current_setting('app.user_id', true), '')::uuid;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

-- Helper: attach audit columns + trigger to a table (verbatim from the universal schema)
CREATE OR REPLACE FUNCTION core.add_audit_columns(p_table regclass) RETURNS void AS $$
DECLARE t text := p_table::text;
BEGIN
  EXECUTE format('ALTER TABLE %s
      ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
      ADD COLUMN IF NOT EXISTS created_by uuid,
      ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now(),
      ADD COLUMN IF NOT EXISTS updated_by uuid', t);
  EXECUTE format('DROP TRIGGER IF EXISTS trg_audit ON %s', t);
  EXECUTE format('CREATE TRIGGER trg_audit BEFORE INSERT OR UPDATE ON %s
      FOR EACH ROW EXECUTE FUNCTION core.set_row_audit()', t);
END; $$ LANGUAGE plpgsql;

-- Session-context helpers (verbatim from the universal 11_security_rls.sql).
-- The backend sets, per transaction:  SET LOCAL app.user_id / app.role_codes / app.dept_scope / app.agent_code
CREATE OR REPLACE FUNCTION identity.current_user_id() RETURNS uuid AS $$
  SELECT nullif(current_setting('app.user_id', true), '')::uuid
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION identity.has_role(p_role text) RETURNS boolean AS $$
  SELECT p_role = ANY (string_to_array(coalesce(current_setting('app.role_codes', true), ''), ','))
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION identity.dept_scope() RETURNS uuid[] AS $$
  SELECT CASE
    WHEN coalesce(current_setting('app.dept_scope', true), '') = '' THEN ARRAY[]::uuid[]
    ELSE string_to_array(current_setting('app.dept_scope', true), ',')::uuid[]
  END
$$ LANGUAGE sql STABLE;
-- PART 2 — UNIVERSAL TABLES USED BY AGENT 28
CREATE TABLE core.institution (
    institution_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code             text NOT NULL UNIQUE,
    name             text NOT NULL,
    type             text NOT NULL CHECK (type IN ('UNIVERSITY','AUTONOMOUS','AFFILIATED','DEEMED')),
    affiliating_body text,
    aishe_code       text,
    address          jsonb,
    is_active        boolean NOT NULL DEFAULT true
);

CREATE TABLE core.department (
    department_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES core.institution,
    code           text NOT NULL,
    name           text NOT NULL,
    short_name     text,
    type           text NOT NULL DEFAULT 'ACADEMIC'
                   CHECK (type IN ('ACADEMIC','SUPPORT','ADMINISTRATIVE')),
    hod_faculty_id uuid,                       -- FK added after people.faculty exists
    established_on date,
    is_active      boolean NOT NULL DEFAULT true,
    UNIQUE (institution_id, code)
);

CREATE TABLE core.academic_year (
    academic_year_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id   uuid NOT NULL REFERENCES core.institution,
    label            text NOT NULL,             -- '2025-26'
    start_date       date NOT NULL,
    end_date         date NOT NULL,
    is_current       boolean NOT NULL DEFAULT false,
    UNIQUE (institution_id, label),
    CHECK (end_date > start_date)
);

CREATE TABLE core.term (
    term_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    academic_year_id uuid NOT NULL REFERENCES core.academic_year,
    term_no          smallint NOT NULL CHECK (term_no BETWEEN 1 AND 3),
    label            text NOT NULL,             -- 'ODD 2025-26'
    parity           text NOT NULL CHECK (parity IN ('ODD','EVEN','SUMMER')),
    start_date       date NOT NULL,
    end_date         date NOT NULL,
    instruction_end  date,
    status           text NOT NULL DEFAULT 'PLANNED'
                     CHECK (status IN ('PLANNED','ACTIVE','INSTRUCTION_CLOSED','RESULTS_PUBLISHED','CLOSED')),
    UNIQUE (academic_year_id, term_no)
);

CREATE TABLE core.calendar_event (
    calendar_event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    academic_year_id  uuid NOT NULL REFERENCES core.academic_year,
    department_id     uuid REFERENCES core.department,   -- null = institution-wide
    event_date        date NOT NULL,
    end_date          date,
    title             text NOT NULL,
    event_type        text NOT NULL CHECK (event_type IN
                      ('HOLIDAY','EXAM','INSTRUCTION','EVENT','VACATION','REGISTRATION')),
    blocks_instruction boolean NOT NULL DEFAULT false
);

CREATE INDEX idx_calendar_event_date ON core.calendar_event (academic_year_id, event_date);

CREATE TABLE core.code_list (
    code_list_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code         text NOT NULL UNIQUE,   -- 'COURSE_CATEGORY','LEAVE_TYPE','FEE_HEAD'...
    name         text NOT NULL,
    description  text
);

CREATE TABLE core.code_value (
    code_value_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code_list_id  uuid NOT NULL REFERENCES core.code_list ON DELETE CASCADE,
    code          text NOT NULL,
    label         text NOT NULL,
    sort_order    smallint NOT NULL DEFAULT 0,
    attributes    jsonb,
    is_active     boolean NOT NULL DEFAULT true,
    UNIQUE (code_list_id, code)
);

SELECT core.add_audit_columns('core.institution');

SELECT core.add_audit_columns('core.department');

SELECT core.add_audit_columns('core.academic_year');

SELECT core.add_audit_columns('core.term');

CREATE TABLE people.person (
    person_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id   uuid NOT NULL REFERENCES core.institution,
    full_name        text NOT NULL,
    given_name       text,
    family_name      text,
    date_of_birth    date,
    gender           text CHECK (gender IN ('M','F','O','UNDISCLOSED')),
    primary_email    text,
    primary_phone    text,
    photo_ref        text,
    nationality      text,
    address          jsonb,
    social_category  text,
    is_differently_abled boolean DEFAULT false,
    mother_tongue    text,
    is_active        boolean NOT NULL DEFAULT true,
    merged_into      uuid REFERENCES people.person   -- duplicate resolution
);

CREATE INDEX idx_person_email ON people.person (lower(primary_email));

CREATE INDEX idx_person_name_trgm ON people.person USING gin (full_name gin_trgm_ops);

COMMENT ON COLUMN people.person.social_category IS
  'Statutory reporting and fairness auditing only. Must never be an input feature to any '
  'agentops model, nor a filter in placement.job matching. See agentops.fairness_audit.';

CREATE TABLE people.student (
    student_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id        uuid NOT NULL UNIQUE REFERENCES people.person,
    admission_no     text NOT NULL,
    roll_no          text NOT NULL,
    register_no      text,                 -- university register number
    batch_id         uuid NOT NULL,        -- FK added in 03_curriculum
    admission_date   date NOT NULL,
    admission_category text,               -- CONVENER / MANAGEMENT / LATERAL / NRI
    entry_qualification jsonb,             -- board, marks, rank
    current_section_id uuid,               -- FK added in 03_curriculum
    current_year_of_study smallint,
    status           text NOT NULL DEFAULT 'ACTIVE'
                     CHECK (status IN ('ACTIVE','DETAINED','ON_LEAVE','DISCONTINUED',
                                       'TRANSFERRED','GRADUATED','DEBARRED')),
    status_changed_on date,
    graduation_date  date,
    UNIQUE (admission_no),
    UNIQUE (roll_no)
);

CREATE INDEX idx_student_batch ON people.student (batch_id, status);

CREATE TABLE people.faculty (
    faculty_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id      uuid NOT NULL UNIQUE REFERENCES people.person,
    employee_no    text NOT NULL UNIQUE,
    department_id  uuid NOT NULL REFERENCES core.department,
    designation    text NOT NULL,          -- ASSISTANT_PROFESSOR / ASSOCIATE / PROFESSOR
    cadre          text,                   -- used by governance.compliance (cadre ratio)
    employment_type text NOT NULL DEFAULT 'REGULAR'
                    CHECK (employment_type IN ('REGULAR','CONTRACT','ADJUNCT','VISITING','EMERITUS')),
    highest_qualification text,
    is_phd_holder  boolean NOT NULL DEFAULT false,
    phd_awarded_on date,
    date_of_joining date NOT NULL,
    date_of_leaving date,
    is_research_supervisor boolean NOT NULL DEFAULT false,
    status         text NOT NULL DEFAULT 'ACTIVE'
                   CHECK (status IN ('ACTIVE','ON_LEAVE','DEPUTED','RESIGNED','RETIRED'))
);

CREATE INDEX idx_faculty_dept ON people.faculty (department_id, status);

ALTER TABLE core.department
  ADD CONSTRAINT fk_dept_hod FOREIGN KEY (hod_faculty_id) REFERENCES people.faculty;

CREATE TABLE identity.app_user (
    user_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id      uuid UNIQUE REFERENCES people.person,
    username       text NOT NULL UNIQUE,
    email          text NOT NULL,
    auth_provider  text NOT NULL DEFAULT 'SSO',
    is_active      boolean NOT NULL DEFAULT true,
    is_service_account boolean NOT NULL DEFAULT false,
    last_login_at  timestamptz
);

CREATE TABLE identity.role (
    role_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code        text NOT NULL UNIQUE,   -- STUDENT, FACULTY, MENTOR, HOD, DEAN, COE,
    name        text NOT NULL,
    description text,
    is_system   boolean NOT NULL DEFAULT false
);

CREATE TABLE identity.user_role (
    user_role_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid NOT NULL REFERENCES identity.app_user ON DELETE CASCADE,
    role_id      uuid NOT NULL REFERENCES identity.role,
    scope_type   text NOT NULL DEFAULT 'SELF'
                 CHECK (scope_type IN ('SELF','SECTION','COURSE_OFFERING','PROGRAMME',
                                       'DEPARTMENT','CAMPUS','INSTITUTION')),
    scope_id     uuid,                  -- null when scope_type = SELF or INSTITUTION
    valid_from   date NOT NULL DEFAULT current_date,
    valid_to     date,
    granted_by   uuid REFERENCES identity.app_user,
    UNIQUE (user_id, role_id, scope_type, scope_id, valid_from)
);

CREATE INDEX idx_user_role_lookup ON identity.user_role (user_id, valid_from, valid_to);

CREATE TABLE identity.consent (
    consent_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id    uuid NOT NULL REFERENCES people.person ON DELETE CASCADE,
    purpose_code text NOT NULL,          -- 'ALUMNI_CONTACT','PUBLICITY_PHOTO','PARENT_SHARING'
    is_granted   boolean NOT NULL,
    granted_at   timestamptz NOT NULL DEFAULT now(),
    withdrawn_at timestamptz,
    evidence_ref text,
    UNIQUE (person_id, purpose_code, granted_at)
);

SELECT core.add_audit_columns('people.person');

SELECT core.add_audit_columns('people.student');

SELECT core.add_audit_columns('people.faculty');

SELECT core.add_audit_columns('identity.app_user');

SELECT core.add_audit_columns('identity.user_role');

CREATE TABLE curriculum.programme (
    programme_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES core.institution,
    department_id  uuid NOT NULL REFERENCES core.department,
    code           text NOT NULL,
    name           text NOT NULL,
    level          text NOT NULL CHECK (level IN ('UG','PG','PHD','DIPLOMA','INTEGRATED')),
    degree         text NOT NULL,                 -- 'B.Tech','M.Tech','MBA'
    specialisation text,
    duration_years numeric(3,1) NOT NULL,
    total_terms    smallint NOT NULL,
    sanctioned_intake smallint,
    is_active      boolean NOT NULL DEFAULT true,
    UNIQUE (institution_id, code)
);

CREATE TABLE curriculum.regulation (
    regulation_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES core.institution,
    code           text NOT NULL,                 -- 'R23'
    name           text NOT NULL,
    effective_from_admission_year smallint NOT NULL,
    effective_to_admission_year   smallint,
    approved_on    date,
    approving_body text,
    status         text NOT NULL DEFAULT 'DRAFT'
                   CHECK (status IN ('DRAFT','APPROVED','ACTIVE','SUPERSEDED','WITHDRAWN')),
    superseded_by  uuid REFERENCES curriculum.regulation,
    document_ref   uuid,                          -- knowledge.document
    UNIQUE (institution_id, code)
);

CREATE TABLE curriculum.batch (
    batch_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    programme_id   uuid NOT NULL REFERENCES curriculum.programme,
    regulation_id  uuid NOT NULL REFERENCES curriculum.regulation,
    admission_year smallint NOT NULL,
    label          text NOT NULL,                 -- '2023-27 CSE'
    expected_graduation_year smallint,
    status         text NOT NULL DEFAULT 'ACTIVE'
                   CHECK (status IN ('ACTIVE','GRADUATED','CLOSED')),
    UNIQUE (programme_id, admission_year)
);

CREATE TABLE curriculum.section (
    section_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id       uuid NOT NULL REFERENCES curriculum.batch,
    code           text NOT NULL,                 -- 'A','B','CSE-1'
    year_of_study  smallint NOT NULL CHECK (year_of_study BETWEEN 1 AND 6),
    strength       smallint,
    class_advisor_faculty_id uuid REFERENCES people.faculty,
    is_active      boolean NOT NULL DEFAULT true,
    UNIQUE (batch_id, code, year_of_study)
);

ALTER TABLE people.student
  ADD CONSTRAINT fk_student_batch FOREIGN KEY (batch_id) REFERENCES curriculum.batch,
  ADD CONSTRAINT fk_student_section FOREIGN KEY (current_section_id) REFERENCES curriculum.section;

CREATE TABLE curriculum.course (
    course_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES core.institution,
    owning_department_id uuid NOT NULL REFERENCES core.department,
    title         text NOT NULL,
    short_title   text,
    is_active     boolean NOT NULL DEFAULT true
);

CREATE TABLE curriculum.course_version (
    course_version_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id      uuid NOT NULL REFERENCES curriculum.course,
    regulation_id  uuid NOT NULL REFERENCES curriculum.regulation,
    programme_id   uuid NOT NULL REFERENCES curriculum.programme,
    course_code    text NOT NULL,                 -- 'CS301'
    term_no        smallint NOT NULL CHECK (term_no BETWEEN 1 AND 12),
    year_of_study  smallint NOT NULL,
    course_category text NOT NULL,                -- must match regulation_norm categories
    course_type    text NOT NULL CHECK (course_type IN
                   ('THEORY','LAB','THEORY_WITH_LAB','PROJECT','INTERNSHIP','SEMINAR',
                    'MOOC','AUDIT','MANDATORY_NON_CREDIT')),
    is_elective    boolean NOT NULL DEFAULT false,
    elective_group text,
    credits        numeric(4,1) NOT NULL,
    lecture_hours  smallint NOT NULL DEFAULT 0,
    tutorial_hours smallint NOT NULL DEFAULT 0,
    practical_hours smallint NOT NULL DEFAULT 0,
    total_contact_hours smallint GENERATED ALWAYS AS
                   (lecture_hours + tutorial_hours + practical_hours) STORED,
    internal_max_marks smallint NOT NULL DEFAULT 40,
    external_max_marks smallint NOT NULL DEFAULT 60,
    pass_min_internal  smallint,
    pass_min_external  smallint,
    pass_min_total     smallint,
    syllabus_document_ref uuid,                   -- knowledge.document
    status         text NOT NULL DEFAULT 'ACTIVE'
                   CHECK (status IN ('DRAFT','ACTIVE','SUPERSEDED','WITHDRAWN')),
    UNIQUE (regulation_id, programme_id, course_code)
);

CREATE INDEX idx_cv_lookup ON curriculum.course_version (regulation_id, programme_id, term_no);

CREATE TABLE curriculum.course_unit (
    course_unit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_version_id uuid NOT NULL REFERENCES curriculum.course_version ON DELETE CASCADE,
    unit_no       smallint NOT NULL,
    title         text NOT NULL,
    description   text,
    notional_hours smallint,
    UNIQUE (course_version_id, unit_no)
);

CREATE TABLE curriculum.course_topic (
    course_topic_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_unit_id  uuid NOT NULL REFERENCES curriculum.course_unit ON DELETE CASCADE,
    seq_no          smallint NOT NULL,
    title           text NOT NULL,
    parent_topic_id uuid REFERENCES curriculum.course_topic,   -- sub-topics
    notional_hours  numeric(3,1),
    UNIQUE (course_unit_id, seq_no)
);

CREATE TABLE curriculum.course_outcome (
    course_outcome_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_version_id uuid NOT NULL REFERENCES curriculum.course_version ON DELETE CASCADE,
    co_no          smallint NOT NULL,
    statement      text NOT NULL,
    bloom_level    smallint CHECK (bloom_level BETWEEN 1 AND 6),
    target_level   numeric(3,2),                  -- institutional attainment target
    UNIQUE (course_version_id, co_no)
);

SELECT core.add_audit_columns('curriculum.programme');

SELECT core.add_audit_columns('curriculum.regulation');

SELECT core.add_audit_columns('curriculum.course_version');

SELECT core.add_audit_columns('curriculum.course_outcome');

CREATE TABLE academics.course_offering (
    course_offering_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_version_id  uuid NOT NULL REFERENCES curriculum.course_version,
    term_id            uuid NOT NULL REFERENCES core.term,
    section_id         uuid NOT NULL REFERENCES curriculum.section,
    department_id      uuid NOT NULL REFERENCES core.department,
    enrolled_count     smallint,
    delivery_mode      text NOT NULL DEFAULT 'OFFLINE'
                       CHECK (delivery_mode IN ('OFFLINE','ONLINE','BLENDED')),
    status             text NOT NULL DEFAULT 'PLANNED'
                       CHECK (status IN ('PLANNED','ACTIVE','COMPLETED','CANCELLED')),
    UNIQUE (course_version_id, term_id, section_id)
);

CREATE INDEX idx_offering_term ON academics.course_offering (term_id, department_id);

CREATE TABLE academics.lesson_plan (
    lesson_plan_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_offering_id uuid NOT NULL UNIQUE REFERENCES academics.course_offering ON DELETE CASCADE,
    prepared_by_faculty_id uuid NOT NULL REFERENCES people.faculty,
    total_planned_sessions smallint,
    buffer_sessions smallint DEFAULT 0,
    status      text NOT NULL DEFAULT 'DRAFT'
                CHECK (status IN ('DRAFT','SUBMITTED','APPROVED','REVISED')),
    approved_by uuid REFERENCES identity.app_user,
    approved_at timestamptz
);

CREATE TABLE academics.lesson_plan_session (
    lesson_plan_session_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    lesson_plan_id  uuid NOT NULL REFERENCES academics.lesson_plan ON DELETE CASCADE,
    seq_no          smallint NOT NULL,
    planned_date    date,
    course_topic_id uuid REFERENCES curriculum.course_topic,
    course_unit_id  uuid REFERENCES curriculum.course_unit,
    course_outcome_id uuid REFERENCES curriculum.course_outcome,
    teaching_method text CHECK (teaching_method IN
                    ('LECTURE','TUTORIAL','DEMO','PROBLEM_SOLVING','FLIPPED','SEMINAR',
                     'LAB','CASE_STUDY','GUEST','BUFFER','REVISION')),
    resource_ref    text,
    UNIQUE (lesson_plan_id, seq_no)
);

SELECT core.add_audit_columns('academics.course_offering');

CREATE TABLE research.funding_agency (
    funding_agency_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code text NOT NULL UNIQUE,           -- DST, ANRF, SERB, MEITY, DRDO, AICTE, UGC
    name text NOT NULL,
    agency_type text CHECK (agency_type IN ('CENTRAL','STATE','INDUSTRY','INTERNATIONAL','NGO')),
    portal_url text
);

CREATE TABLE research.project (
    project_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_id  uuid /* FK to research.proposal omitted: outside Agent 28 subset */,
    funding_agency_id uuid REFERENCES research.funding_agency,
    title        text NOT NULL,
    sanction_no  text,
    pi_faculty_id uuid NOT NULL REFERENCES people.faculty,
    sanctioned_amount numeric(14,2),
    received_amount numeric(14,2),
    start_date   date, end_date date,
    project_type text CHECK (project_type IN ('RESEARCH','CONSULTANCY','SEED','INDUSTRY','INTERNATIONAL')),
    status       text NOT NULL DEFAULT 'ACTIVE'
                 CHECK (status IN ('SANCTIONED','ACTIVE','EXTENDED','COMPLETED','TERMINATED'))
);

CREATE TABLE engagement.event (
    event_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES core.institution,
    department_id uuid REFERENCES core.department,
    event_type   text NOT NULL CHECK (event_type IN
                 ('CONFERENCE','FDP','WORKSHOP','SEMINAR','WEBINAR','STTP','BOOTCAMP','HACKATHON')),
    title        text NOT NULL,
    from_date    date NOT NULL, to_date date NOT NULL,
    mode         text CHECK (mode IN ('OFFLINE','ONLINE','HYBRID')),
    coordinator_faculty_id uuid REFERENCES people.faculty,
    funding_source text,
    budget_sanctioned numeric(12,2),
    expenditure  numeric(12,2),
    participant_target smallint,
    status       text NOT NULL DEFAULT 'PROPOSED'
                 CHECK (status IN ('PROPOSED','APPROVED','OPEN','ONGOING','COMPLETED','CANCELLED')),
    report_ref   uuid,
    CHECK (to_date >= from_date)
);

CREATE TABLE engagement.industry_partner (
    industry_partner_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES core.institution,
    name       text NOT NULL,
    sector     text,
    website    text,
    contact_person text, contact_email text, contact_phone text,
    relationship_owner_faculty_id uuid REFERENCES people.faculty,
    engagement_score numeric(5,2),
    last_activity_on date,
    status     text NOT NULL DEFAULT 'ACTIVE'
               CHECK (status IN ('PROSPECT','ACTIVE','DORMANT','CONCLUDED')),
    UNIQUE (institution_id, name)
);

CREATE TABLE engagement.mou (
    mou_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    industry_partner_id uuid REFERENCES engagement.industry_partner,
    partner_name text NOT NULL,
    partner_type text CHECK (partner_type IN ('INDUSTRY','UNIVERSITY','RESEARCH_LAB','NGO','GOVERNMENT','INTERNATIONAL')),
    title      text NOT NULL,
    scope      text,
    signed_on  date NOT NULL,
    valid_from date, valid_until date,
    owner_faculty_id uuid REFERENCES people.faculty,
    document_ref uuid,
    status     text NOT NULL DEFAULT 'ACTIVE'
               CHECK (status IN ('DRAFT','ACTIVE','EXPIRED','RENEWED','TERMINATED')),
    renewal_alert_days smallint DEFAULT 90
);

CREATE TABLE engagement.mou_deliverable (
    mou_deliverable_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    mou_id     uuid NOT NULL REFERENCES engagement.mou ON DELETE CASCADE,
    description text NOT NULL,
    deliverable_type text,
    target_count smallint,
    achieved_count smallint NOT NULL DEFAULT 0,
    due_date   date,
    status     text NOT NULL DEFAULT 'PENDING'
               CHECK (status IN ('PENDING','IN_PROGRESS','ACHIEVED','NOT_ACHIEVED'))
);

CREATE TABLE engagement.industry_activity (
    industry_activity_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    industry_partner_id uuid REFERENCES engagement.industry_partner,
    mou_id     uuid REFERENCES engagement.mou,
    department_id uuid REFERENCES core.department,
    activity_type text NOT NULL CHECK (activity_type IN
               ('INDUSTRY_VISIT','GUEST_LECTURE','EXPERT_TALK','SPONSORED_PROJECT',
                'INTERNSHIP_DRIVE','FACULTY_EXCHANGE','LAB_SUPPORT','CONSULTANCY')),
    title      text NOT NULL,
    activity_date date NOT NULL,
    course_version_id uuid REFERENCES curriculum.course_version,  -- topical alignment
    participant_count smallint,
    feedback_summary text,
    evidence_ref uuid
);

SELECT core.add_audit_columns('research.project');

SELECT core.add_audit_columns('engagement.event');

SELECT core.add_audit_columns('engagement.mou');

CREATE TABLE studentlife.action_item (
    action_item_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    source_schema text NOT NULL,
    source_table  text NOT NULL,
    source_id     uuid NOT NULL,
    description   text NOT NULL,
    owner_user_id uuid REFERENCES identity.app_user,
    due_date      date,
    priority      text CHECK (priority IN ('LOW','MEDIUM','HIGH','URGENT')),
    status        text NOT NULL DEFAULT 'OPEN'
                  CHECK (status IN ('OPEN','IN_PROGRESS','COMPLETED','DEFERRED','DROPPED')),
    closed_on     date,
    closure_note  text
);

CREATE INDEX idx_action_owner ON studentlife.action_item (owner_user_id, status, due_date);

CREATE INDEX idx_action_source ON studentlife.action_item (source_table, source_id);

CREATE TABLE placement.company (
    company_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES core.institution,
    name text NOT NULL, sector text, website text,
    tier text CHECK (tier IN ('SUPER_DREAM','DREAM','CORE','MASS','STARTUP')),
    hr_contact_name text, hr_contact_email text, hr_contact_phone text,
    industry_partner_id uuid REFERENCES engagement.industry_partner,
    alumni_connect_person_id uuid REFERENCES people.person,
    UNIQUE (institution_id, name)
);

CREATE TABLE placement.job_opening (
    job_opening_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES placement.company,
    academic_year_id uuid NOT NULL REFERENCES core.academic_year,
    role_title text NOT NULL,
    opening_type text NOT NULL CHECK (opening_type IN ('FULL_TIME','INTERNSHIP','INTERN_PPO','PART_TIME')),
    job_description text,
    required_skills text[], preferred_skills text[],
    eligibility jsonb NOT NULL,          -- {min_cgpa, max_backlogs, programmes[], gap_years}
    ctc_min numeric(12,2), ctc_max numeric(12,2),
    locations text[],
    positions_open smallint,
    drive_date date, application_deadline date,
    status text NOT NULL DEFAULT 'ANNOUNCED'
           CHECK (status IN ('ANNOUNCED','OPEN','CLOSED','DRIVE_COMPLETED','CANCELLED'))
);

COMMENT ON COLUMN placement.job_opening.eligibility IS
  'Eligibility is a hard filter and must reference academic criteria only. Filtering or '
  'ranking on gender, caste, religion or region — directly or by proxy — is prohibited '
  'and audited by agentops.fairness_audit.';

CREATE TABLE placement.offer (
    offer_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES people.student,
    company_id uuid NOT NULL REFERENCES placement.company,
    job_opening_id uuid REFERENCES placement.job_opening,
    role_title text, ctc numeric(12,2), location text,
    offer_date date NOT NULL,
    is_ppo boolean NOT NULL DEFAULT false,
    joining_date date,
    status text NOT NULL DEFAULT 'OFFERED'
           CHECK (status IN ('OFFERED','ACCEPTED','DECLINED','REVOKED','JOINED'))
);

CREATE INDEX idx_offer_student ON placement.offer (student_id, offer_date);

CREATE TABLE placement.internship (
    internship_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES people.student,
    company_id uuid REFERENCES placement.company,
    company_name text NOT NULL,
    domain text,
    from_date date NOT NULL, to_date date NOT NULL,
    mode text CHECK (mode IN ('ONSITE','REMOTE','HYBRID')),
    stipend numeric(10,2),
    source text CHECK (source IN ('INSTITUTION','STUDENT_SOURCED','ALUMNI','MOU')),
    legitimacy_verified boolean NOT NULL DEFAULT false,
    verified_by_user_id uuid REFERENCES identity.app_user,
    faculty_mentor_id uuid REFERENCES people.faculty,
    industry_supervisor text,
    is_credit_bearing boolean NOT NULL DEFAULT false,
    course_version_id uuid REFERENCES curriculum.course_version,
    final_grade text,
    converted_to_ppo boolean NOT NULL DEFAULT false,
    status text NOT NULL DEFAULT 'PROPOSED'
           CHECK (status IN ('PROPOSED','APPROVED','ONGOING','COMPLETED','DISCONTINUED')),
    CHECK (to_date >= from_date)
);

CREATE TABLE placement.internship_evaluation (
    internship_evaluation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    internship_id uuid NOT NULL REFERENCES placement.internship ON DELETE CASCADE,
    evaluator_type text NOT NULL CHECK (evaluator_type IN ('INDUSTRY','FACULTY_MENTOR','PANEL')),
    evaluation_stage text CHECK (evaluation_stage IN ('MID_TERM','FINAL','REPORT','PRESENTATION')),
    score numeric(5,2), max_score numeric(5,2),
    criteria_scores jsonb,
    remarks text,
    evaluated_on date
);

CREATE TABLE placement.alumni (
    alumni_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id uuid NOT NULL UNIQUE REFERENCES people.person,
    student_id uuid REFERENCES people.student,
    programme_id uuid REFERENCES curriculum.programme,
    graduation_year smallint NOT NULL,
    current_organisation text, current_designation text, sector text,
    location text, linkedin_url text,
    higher_study_institution text,
    outcome_category text CHECK (outcome_category IN ('EMPLOYED','HIGHER_STUDIES','ENTREPRENEUR','OTHER','UNKNOWN')),
    engagement_level text CHECK (engagement_level IN ('ACTIVE','OCCASIONAL','DORMANT','UNREACHABLE')),
    contact_consent boolean NOT NULL DEFAULT false,
    publicity_consent boolean NOT NULL DEFAULT false,
    last_updated_on date, updated_via text
);

CREATE INDEX idx_alumni_year ON placement.alumni (graduation_year, programme_id);

CREATE TABLE placement.alumni_contribution (
    alumni_contribution_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    alumni_id uuid NOT NULL REFERENCES placement.alumni ON DELETE CASCADE,
    contribution_type text NOT NULL CHECK (contribution_type IN
              ('GUEST_LECTURE','MENTORING','PLACEMENT_REFERRAL','INTERNSHIP_HOST',
               'FINANCIAL','EQUIPMENT','SCHOLARSHIP_FUNDING','COLLABORATION')),
    description text,
    contributed_on date,
    value numeric(12,2),
    acknowledged boolean NOT NULL DEFAULT false
);

SELECT core.add_audit_columns('placement.job_opening');

SELECT core.add_audit_columns('placement.offer');

SELECT core.add_audit_columns('placement.internship');

SELECT core.add_audit_columns('placement.alumni');

CREATE TABLE governance.compliance_framework (
    compliance_framework_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code text NOT NULL UNIQUE,           -- AICTE, UGC, NBA, NAAC, NIRF, UNIVERSITY
    name text NOT NULL,
    version text,
    effective_from date
);

CREATE TABLE quality.kpi_definition (
    kpi_definition_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES core.institution,
    code text NOT NULL,
    name text NOT NULL,
    domain text NOT NULL CHECK (domain IN
        ('ACADEMIC','STUDENT_OUTCOME','RESEARCH','FACULTY','INFRASTRUCTURE',
         'GOVERNANCE','FINANCE','PLACEMENT','OUTREACH','SAFETY')),
    definition text NOT NULL,
    formula text NOT NULL,
    unit text,
    source_agent text,
    source_query text,
    target_value numeric(14,4),
    direction text CHECK (direction IN ('HIGHER_BETTER','LOWER_BETTER','TARGET_RANGE')),
    frequency text CHECK (frequency IN ('DAILY','WEEKLY','MONTHLY','TERM','ANNUAL')),
    framework_mapping jsonb,             -- {NAAC:'2.6.3', NIRF:'GO', NBA:'4.2'}
    owner_role_id uuid REFERENCES identity.role,
    is_active boolean NOT NULL DEFAULT true,
    UNIQUE (institution_id, code)
);

COMMENT ON TABLE quality.kpi_definition IS
  'The single definition of every institutional metric. Ranking submissions, accreditation '
  'submissions and internal dashboards must all read from here, or the same figure will be '
  'reported three different ways.';

CREATE TABLE quality.kpi_value (
    kpi_value_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    kpi_definition_id uuid NOT NULL REFERENCES quality.kpi_definition,
    scope_type text NOT NULL CHECK (scope_type IN ('INSTITUTION','DEPARTMENT','PROGRAMME','BATCH')),
    scope_id uuid,
    period_start date NOT NULL, period_end date NOT NULL,
    value numeric(14,4),
    target_value numeric(14,4),
    previous_value numeric(14,4),
    variance_pct numeric(8,2),
    trend text CHECK (trend IN ('IMPROVING','STABLE','DETERIORATING')),
    status text CHECK (status IN ('ON_TARGET','BELOW_TARGET','ABOVE_TARGET','NO_DATA')),
    computed_at timestamptz NOT NULL DEFAULT now(),
    computed_by_agent text,
    validated_by_user_id uuid REFERENCES identity.app_user,
    validated_at timestamptz,
    UNIQUE (kpi_definition_id, scope_type, scope_id, period_start, period_end)
);

CREATE INDEX idx_kpi_value_period ON quality.kpi_value (kpi_definition_id, period_end DESC);

CREATE TABLE quality.accreditation_criterion (
    accreditation_criterion_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    compliance_framework_id uuid NOT NULL REFERENCES governance.compliance_framework,
    code text NOT NULL,
    parent_id uuid REFERENCES quality.accreditation_criterion,
    title text NOT NULL,
    weightage numeric(6,2),
    evidence_specification text,
    responsible_role_id uuid REFERENCES identity.role,
    UNIQUE (compliance_framework_id, code)
);

CREATE TABLE quality.evidence_item (
    evidence_item_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    accreditation_criterion_id uuid REFERENCES quality.accreditation_criterion,
    title text NOT NULL,
    evidence_type text CHECK (evidence_type IN ('REPORT','CERTIFICATE','MINUTES','PHOTO','DATA_EXPORT','LETTER','PUBLICATION')),
    period_start date, period_end date,
    document_ref uuid,
    source_schema text, source_table text, source_id uuid,   -- traceability
    generated_by_agent text,
    content_hash text,                   -- tamper evidence
    approved_by_user_id uuid REFERENCES identity.app_user,
    approved_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_evidence_criterion ON quality.evidence_item (accreditation_criterion_id, period_end);

CREATE TABLE quality.feedback_instrument (
    feedback_instrument_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES core.institution,
    name text NOT NULL,
    audience text NOT NULL CHECK (audience IN ('STUDENT','FACULTY','ALUMNI','PARENT','EMPLOYER','PEER')),
    purpose text CHECK (purpose IN ('COURSE_FEEDBACK','FACULTY_FEEDBACK','CURRICULUM','FACILITIES','EXIT','EMPLOYER')),
    term_id uuid REFERENCES core.term,
    questions jsonb NOT NULL,
    is_anonymous boolean NOT NULL DEFAULT true,
    opens_on date, closes_on date,
    status text NOT NULL DEFAULT 'DRAFT'
);

CREATE TABLE quality.feedback_response (
    feedback_response_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    feedback_instrument_id uuid NOT NULL REFERENCES quality.feedback_instrument ON DELETE CASCADE,
    respondent_token text,               -- hashed; not linkable back when anonymous
    target_type text CHECK (target_type IN ('COURSE_OFFERING','FACULTY','PROGRAMME','INSTITUTION')),
    target_id uuid,
    answers jsonb NOT NULL,
    submitted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_feedback_target ON quality.feedback_response (target_type, target_id);

CREATE TABLE knowledge.document (
    document_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id uuid NOT NULL REFERENCES core.institution,
    title text NOT NULL,
    document_class text NOT NULL CHECK (document_class IN
        ('POLICY','CIRCULAR','SYLLABUS','REGULATION','MINUTES','REPORT','CERTIFICATE',
         'MARKS_CARD','APPLICATION_DOC','MOU','MANUAL','FAQ','OTHER')),
    mime_type text,
    storage_uri text NOT NULL,
    content_hash text NOT NULL,
    page_count smallint,
    language text,
    version text,
    effective_from date, effective_to date,
    supersedes_id uuid REFERENCES knowledge.document,
    owner_role_id uuid REFERENCES identity.role,
    sensitivity text NOT NULL DEFAULT 'NORMAL'
        CHECK (sensitivity IN ('PUBLIC','NORMAL','SENSITIVE','RESTRICTED')),
    is_retrievable_by_agents boolean NOT NULL DEFAULT true,
    review_due_on date,
    uploaded_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (content_hash)
);

COMMENT ON COLUMN knowledge.document.is_retrievable_by_agents IS
  'Retrieval agents may only cite documents where this is true AND sensitivity permits the '
  'requesting role. Question papers, counselling notes and disciplinary files are excluded.';

CREATE TABLE knowledge.document_chunk (
    document_chunk_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id uuid NOT NULL REFERENCES knowledge.document ON DELETE CASCADE,
    seq_no integer NOT NULL,
    heading_path text,                   -- for precise citation, e.g. '4 > 4.2 > 4.2.1'
    page_no smallint,
    chunk_text text NOT NULL,
    token_count smallint,
    UNIQUE (document_id, seq_no)
);

CREATE INDEX idx_chunk_text_trgm ON knowledge.document_chunk USING gin (chunk_text gin_trgm_ops);

CREATE TABLE knowledge.chunk_embedding (
    chunk_embedding_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_chunk_id uuid NOT NULL REFERENCES knowledge.document_chunk ON DELETE CASCADE,
    model text NOT NULL,
    dimensions smallint NOT NULL,
    embedding real[] NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (document_chunk_id, model)
);

CREATE TABLE knowledge.extraction_job (
    extraction_job_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id uuid REFERENCES knowledge.document,
    source_uri text,
    detected_document_type text,
    extraction_method text CHECK (extraction_method IN ('TEXT','OCR','TABLE','HYBRID')),
    status text NOT NULL DEFAULT 'QUEUED'
           CHECK (status IN ('QUEUED','RUNNING','COMPLETED','FAILED','NEEDS_REVIEW')),
    started_at timestamptz, finished_at timestamptz,
    error_detail text
);

CREATE TABLE knowledge.extracted_field (
    extracted_field_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    extraction_job_id uuid NOT NULL REFERENCES knowledge.extraction_job ON DELETE CASCADE,
    field_name text NOT NULL,
    raw_value text,
    normalised_value text,
    confidence numeric(4,3) NOT NULL,
    page_no smallint, bounding_box jsonb,
    verification_status text NOT NULL DEFAULT 'AUTO'
           CHECK (verification_status IN ('AUTO','NEEDS_REVIEW','VERIFIED','CORRECTED','REJECTED')),
    corrected_value text,
    verified_by_user_id uuid REFERENCES identity.app_user,
    verified_at timestamptz,
    UNIQUE (extraction_job_id, field_name)
);

COMMENT ON COLUMN knowledge.extracted_field.confidence IS
  'Below the configured threshold the field must be routed to NEEDS_REVIEW and must not '
  'enter an academic or financial record. A transposed digit in a roll number attaches one '
  'student''s result to another.';

SELECT core.add_audit_columns('quality.kpi_definition');

SELECT core.add_audit_columns('quality.kpi_value');

SELECT core.add_audit_columns('knowledge.document');

CREATE TABLE agentops.agent (
    agent_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code text NOT NULL UNIQUE,            -- 'A11_ATTENDANCE_ANALYSIS'
    agent_no smallint,                    -- 1..72, maps to the catalogue
    name text NOT NULL,
    domain text NOT NULL,
    agent_class smallint NOT NULL CHECK (agent_class IN (1,2,3)),
    scope_statement text NOT NULL,
    out_of_scope text,
    reasoning_policy text NOT NULL CHECK (reasoning_policy IN
        ('RETRIEVE_ONLY','COMPUTE','RECOMMEND','ACT_WITH_APPROVAL')),
    requires_human_approval boolean NOT NULL DEFAULT false,
    escalation_rule text,
    owner_user_id uuid REFERENCES identity.app_user,
    version text NOT NULL DEFAULT '1.0',
    status text NOT NULL DEFAULT 'DEVELOPMENT'
           CHECK (status IN ('DEVELOPMENT','PILOT','ACTIVE','SUSPENDED','RETIRED')),
    deployed_on date
);

COMMENT ON COLUMN agentops.agent.owner_user_id IS
  'Every agent needs a named human owner responsible for its accuracy, knowledge base '
  'currency and escalations. Agents without owners degrade silently.';

CREATE TABLE agentops.agent_tool (
    agent_tool_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id uuid NOT NULL REFERENCES agentops.agent ON DELETE CASCADE,
    tool_name text NOT NULL,
    resource_schema text,
    resource_object text,
    access_mode text NOT NULL CHECK (access_mode IN ('READ','WRITE','EXECUTE','EXTERNAL_API')),
    row_scope_rule text,                  -- e.g. 'own_offerings','department','self'
    UNIQUE (agent_id, tool_name, resource_schema, resource_object)
);

CREATE TABLE agentops.agent_run (
    agent_run_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id uuid NOT NULL REFERENCES agentops.agent,
    agent_version text NOT NULL,
    trigger_type text NOT NULL CHECK (trigger_type IN ('USER','SCHEDULED','EVENT','CHAINED')),
    parent_run_id uuid REFERENCES agentops.agent_run,   -- orchestration chains
    invoked_by_user_id uuid REFERENCES identity.app_user,
    effective_role_id uuid REFERENCES identity.role,
    scope jsonb,                          -- term, department, offering, student set
    request_text text,
    started_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    latency_ms integer,
    token_input integer, token_output integer, cost_estimate numeric(10,4),
    status text NOT NULL DEFAULT 'RUNNING'
           CHECK (status IN ('RUNNING','SUCCEEDED','FAILED','PARTIAL','BLOCKED')),
    failure_reason text
);

CREATE INDEX idx_run_agent_time ON agentops.agent_run (agent_id, started_at DESC);

CREATE TABLE agentops.agent_run_input (
    agent_run_input_id bigserial PRIMARY KEY,
    agent_run_id uuid NOT NULL REFERENCES agentops.agent_run ON DELETE CASCADE,
    source_schema text NOT NULL,
    source_table text NOT NULL,
    source_id uuid,
    record_count integer,
    filter_expression text
);

CREATE TABLE agentops.agent_output (
    agent_output_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_run_id uuid NOT NULL REFERENCES agentops.agent_run ON DELETE CASCADE,
    output_type text NOT NULL CHECK (output_type IN
        ('ANSWER','REPORT','RECOMMENDATION','CLASSIFICATION','PREDICTION','ALERT','DRAFT','ACTION_PROPOSAL')),
    subject_type text,                    -- STUDENT, FACULTY, COURSE_OFFERING, DEPARTMENT
    subject_id uuid,
    payload jsonb NOT NULL,
    reasoning_summary text,               -- shown to the user; the "show your working" rule
    citations jsonb,                      -- document/clause references for retrieval agents
    interpretation jsonb,                 -- metric, filters, period applied (Agent 63 rule)
    confidence numeric(4,3),
    requires_approval boolean NOT NULL DEFAULT false,
    approval_status text NOT NULL DEFAULT 'NOT_REQUIRED'
           CHECK (approval_status IN ('NOT_REQUIRED','PENDING','APPROVED','MODIFIED','REJECTED','EXPIRED')),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_output_subject ON agentops.agent_output (subject_type, subject_id, created_at DESC);

CREATE INDEX idx_output_pending ON agentops.agent_output (approval_status) WHERE approval_status = 'PENDING';

CREATE TABLE agentops.human_review (
    human_review_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_output_id uuid NOT NULL REFERENCES agentops.agent_output ON DELETE CASCADE,
    reviewer_user_id uuid NOT NULL REFERENCES identity.app_user,
    decision text NOT NULL CHECK (decision IN ('APPROVE','MODIFY','REJECT','ESCALATE')),
    modified_payload jsonb,
    reason text,
    reason_category text,                 -- WRONG_DATA, WRONG_LOGIC, MISSING_CONTEXT, POLICY
    reviewed_at timestamptz NOT NULL DEFAULT now(),
    time_to_review_seconds integer
);

CREATE TABLE agentops.alert (
    alert_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_user_id uuid NOT NULL REFERENCES identity.app_user,
    agent_id uuid REFERENCES agentops.agent,
    risk_flag_id uuid /* FK to agentops.risk_flag omitted: outside Agent 28 subset */,
    severity text NOT NULL CHECK (severity IN ('INFO','WARNING','URGENT','CRITICAL')),
    title text NOT NULL,
    body text,
    channel text CHECK (channel IN ('IN_APP','EMAIL','SMS','WHATSAPP','PUSH','PHONE')),
    created_at timestamptz NOT NULL DEFAULT now(),
    delivered_at timestamptz, read_at timestamptz, actioned_at timestamptz,
    escalated_at timestamptz,
    escalated_to_user_id uuid REFERENCES identity.app_user
);

CREATE INDEX idx_alert_unread ON agentops.alert (recipient_user_id, created_at DESC)
  WHERE read_at IS NULL;

CREATE TABLE agentops.model_version (
    model_version_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id uuid NOT NULL REFERENCES agentops.agent,
    version text NOT NULL,
    model_type text,                      -- LOGISTIC, GBM, RULE_BASED, LLM_PROMPT
    feature_list jsonb NOT NULL,
    excluded_features jsonb,              -- explicitly prohibited inputs, e.g. social_category
    training_period_start date, training_period_end date,
    training_cohorts text[],
    holdout_accuracy numeric(5,4),
    holdout_precision numeric(5,4), holdout_recall numeric(5,4),
    false_positive_rate numeric(5,4),
    validated_on date,
    approved_by_user_id uuid REFERENCES identity.app_user,
    status text NOT NULL DEFAULT 'CANDIDATE'
           CHECK (status IN ('CANDIDATE','VALIDATED','ACTIVE','DEPRECATED','WITHDRAWN')),
    UNIQUE (agent_id, version)
);

COMMENT ON COLUMN agentops.model_version.excluded_features IS
  'Prohibited inputs are declared, not merely omitted, so that a later change reintroducing '
  'a protected attribute or its proxy is visible in review.';

CREATE TABLE agentops.schedule (
    schedule_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id uuid NOT NULL REFERENCES agentops.agent,
    cron_expression text NOT NULL,
    scope jsonb,
    push_to_role_id uuid REFERENCES identity.role,
    response_expected_hours smallint,
    is_active boolean NOT NULL DEFAULT true,
    last_run_at timestamptz, next_run_at timestamptz
);

SELECT core.add_audit_columns('agentops.agent');

SELECT core.add_audit_columns('agentops.model_version');

CREATE VIEW quality.v_kpi_latest AS
SELECT DISTINCT ON (kd.code, kv.scope_type, kv.scope_id)
       kd.code, kd.name, kd.domain, kd.unit, kd.direction,
       kv.scope_type, kv.scope_id, kv.period_start, kv.period_end,
       kv.value, kv.target_value, kv.variance_pct, kv.trend, kv.status,
       kv.validated_at IS NOT NULL AS is_validated,
       kd.framework_mapping
FROM quality.kpi_value kv
JOIN quality.kpi_definition kd ON kd.kpi_definition_id = kv.kpi_definition_id
WHERE kd.is_active
ORDER BY kd.code, kv.scope_type, kv.scope_id, kv.period_end DESC;
-- =====================================================================
-- PART 3 — AGENT 28 DATABASE OBJECTS
-- (identical to agent28_001_schema.sql, sections 1-4)
-- =====================================================================
-- =====================================================================
-- PART 3.1 — AGENT 28 EXTENSIONS TO ITS OWNED TABLES
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1.1 engagement.industry_partner  (partner register)
-- ---------------------------------------------------------------------
-- Universal file attaches audit columns to engagement.event / mou /
-- outreach_activity but NOT to industry_partner. Use the organiser's own helper.
SELECT core.add_audit_columns('engagement.industry_partner');

ALTER TABLE engagement.industry_partner
  ADD CONSTRAINT ck_ip_engagement_score
      CHECK (engagement_score IS NULL OR engagement_score BETWEEN 0 AND 100);

COMMENT ON COLUMN engagement.industry_partner.sector IS
  'Agent 28: must hold a core.code_value.code from code_list INDUSTRY_SECTOR, the same vocabulary '
  'placement.company.sector must use, or sector gap analysis is meaningless.';
COMMENT ON COLUMN engagement.industry_partner.engagement_score IS
  'Agent 28: cache of the latest engagement.partner_health_snapshot.health_score (0-100). '
  'The snapshot table is authoritative.';
COMMENT ON COLUMN engagement.industry_partner.contact_person IS
  'Agent 28: legacy single-contact cache. Authoritative contacts are engagement.partner_contact; '
  'keep this in step with the active primary contact.';

-- Case-insensitive duplicate guard ("Infosys" vs "INFOSYS"); the universal UNIQUE is case-sensitive.
CREATE UNIQUE INDEX uq_ip_institution_lower_name ON engagement.industry_partner (institution_id, lower(name));
CREATE INDEX idx_ip_status        ON engagement.industry_partner (institution_id, status);
CREATE INDEX idx_ip_sector        ON engagement.industry_partner (institution_id, sector);
CREATE INDEX idx_ip_owner         ON engagement.industry_partner (relationship_owner_faculty_id);
CREATE INDEX idx_ip_name_trgm     ON engagement.industry_partner USING gin (name gin_trgm_ops);

-- ---------------------------------------------------------------------
-- 1.2 engagement.mou
-- ---------------------------------------------------------------------
ALTER TABLE engagement.mou
  ADD COLUMN extraction_job_id uuid REFERENCES knowledge.extraction_job,
  ADD CONSTRAINT fk_mou_document FOREIGN KEY (document_ref) REFERENCES knowledge.document,
  ADD CONSTRAINT ck_mou_validity
      CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until >= valid_from),
  ADD CONSTRAINT ck_mou_industry_partner
      CHECK (partner_type IS DISTINCT FROM 'INDUSTRY' OR industry_partner_id IS NOT NULL),
  ADD CONSTRAINT ck_mou_renewal_alert_days
      CHECK (renewal_alert_days IS NULL OR renewal_alert_days BETWEEN 0 AND 730),
  -- super-key so industry_activity can prove its (mou, partner) pair is consistent
  ADD CONSTRAINT uq_mou_id_partner UNIQUE (mou_id, industry_partner_id);

COMMENT ON COLUMN engagement.mou.extraction_job_id IS
  'Agent 28: the knowledge.extraction_job whose VERIFIED/CORRECTED extracted_field rows populated '
  'valid_from, valid_until, scope and the deliverables. Provenance for every digitised MoU.';

CREATE INDEX idx_mou_partner  ON engagement.mou (industry_partner_id, valid_until);
CREATE INDEX idx_mou_expiry   ON engagement.mou (valid_until) WHERE status = 'ACTIVE';
CREATE INDEX idx_mou_owner    ON engagement.mou (owner_faculty_id);
CREATE UNIQUE INDEX uq_mou_document ON engagement.mou (document_ref) WHERE document_ref IS NOT NULL;
CREATE UNIQUE INDEX uq_mou_partner_title_signed
  ON engagement.mou (industry_partner_id, lower(title), signed_on) WHERE industry_partner_id IS NOT NULL;

-- ---------------------------------------------------------------------
-- 1.3 engagement.mou_deliverable  (each committed deliverable = trackable item)
-- ---------------------------------------------------------------------
SELECT core.add_audit_columns('engagement.mou_deliverable');

ALTER TABLE engagement.mou_deliverable
  ADD COLUMN recurrence text NOT NULL DEFAULT 'MOU_TERM'
      CHECK (recurrence IN ('ONE_TIME','PER_TERM','PER_YEAR','MOU_TERM')),
  ADD COLUMN source_text    text,
  ADD COLUMN source_page_no smallint CHECK (source_page_no IS NULL OR source_page_no > 0),
  ADD CONSTRAINT ck_mdl_type CHECK (deliverable_type IS NULL OR deliverable_type IN
      ('GUEST_LECTURE','EXPERT_TALK','INDUSTRY_VISIT','SPONSORED_PROJECT','INTERNSHIP','PLACEMENT',
       'FACULTY_EXCHANGE','LAB_SUPPORT','CONSULTANCY','TRAINING_PROGRAMME','EVENT','CURRICULUM_INPUT','OTHER')),
  ADD CONSTRAINT ck_mdl_counts CHECK ((target_count IS NULL OR target_count >= 0) AND achieved_count >= 0);

COMMENT ON COLUMN engagement.mou_deliverable.achieved_count IS
  'Agent 28: maintained by trigger = SUM(contributed_count) of CONFIRMED rows in '
  'engagement.mou_deliverable_fulfilment. Do not write directly.';
COMMENT ON COLUMN engagement.mou_deliverable.source_text IS
  'Verbatim commitment clause from the MoU document (citation for the tracked item).';

CREATE INDEX idx_mdl_mou      ON engagement.mou_deliverable (mou_id, status);
CREATE INDEX idx_mdl_open_due ON engagement.mou_deliverable (due_date) WHERE status IN ('PENDING','IN_PROGRESS');

-- ---------------------------------------------------------------------
-- 1.4 engagement.industry_activity  (guest lectures, visits, projects, exchanges, lab support, consultancy)
-- ---------------------------------------------------------------------
SELECT core.add_audit_columns('engagement.industry_activity');

ALTER TABLE engagement.industry_activity
  ADD COLUMN status text NOT NULL DEFAULT 'CONDUCTED'
      CHECK (status IN ('PLANNED','CONFIRMED','CONDUCTED','POSTPONED','CANCELLED')),
  ADD COLUMN end_date date,
  ADD COLUMN mode text CHECK (mode IN ('OFFLINE','ONLINE','HYBRID')),
  ADD COLUMN outcome_summary text,
  ADD COLUMN support_value numeric(14,2) CHECK (support_value IS NULL OR support_value >= 0),
  ADD COLUMN research_project_id uuid REFERENCES research.project,
  ADD CONSTRAINT fk_ia_evidence_document FOREIGN KEY (evidence_ref) REFERENCES knowledge.document,
  ADD CONSTRAINT fk_ia_mou_partner FOREIGN KEY (mou_id, industry_partner_id)
      REFERENCES engagement.mou (mou_id, industry_partner_id),
  ADD CONSTRAINT ck_ia_counterparty CHECK (industry_partner_id IS NOT NULL OR mou_id IS NOT NULL),
  ADD CONSTRAINT ck_ia_dates CHECK (end_date IS NULL OR end_date >= activity_date),
  ADD CONSTRAINT ck_ia_participants CHECK (participant_count IS NULL OR participant_count >= 0),
  ADD CONSTRAINT ck_ia_project_type
      CHECK (research_project_id IS NULL OR activity_type IN ('SPONSORED_PROJECT','CONSULTANCY'));

COMMENT ON COLUMN engagement.industry_activity.status IS
  'Agent 28: default CONDUCTED preserves the original meaning of the table (a record of an activity). '
  'PLANNED/CONFIRMED rows make the activity calendar and course-aligned scheduling possible.';
COMMENT ON COLUMN engagement.industry_activity.course_version_id IS
  'Universal column retained. Agent 28 keeps it equal to the is_primary row in '
  'engagement.activity_course_alignment, which is authoritative for course/unit/topic alignment.';
COMMENT ON COLUMN engagement.industry_activity.research_project_id IS
  'For SPONSORED_PROJECT / CONSULTANCY: the authoritative financial/project record stays in research.project.';

CREATE INDEX idx_ia_partner_date ON engagement.industry_activity (industry_partner_id, activity_date DESC);
CREATE INDEX idx_ia_mou          ON engagement.industry_activity (mou_id) WHERE mou_id IS NOT NULL;
CREATE INDEX idx_ia_dept_date    ON engagement.industry_activity (department_id, activity_date DESC);
CREATE INDEX idx_ia_calendar     ON engagement.industry_activity (activity_date, status);
CREATE INDEX idx_ia_course_version ON engagement.industry_activity (course_version_id) WHERE course_version_id IS NOT NULL;
CREATE INDEX idx_ia_research_project ON engagement.industry_activity (research_project_id) WHERE research_project_id IS NOT NULL;

-- =====================================================================
-- PART 3.2 — FEEDBACK VOCABULARY + PLACEMENT/QUALITY INDEXES
-- =====================================================================

-- 2A. Widen feedback vocabularies so student feedback on an industry interaction
--     reuses the platform feedback infrastructure instead of a parallel table.
ALTER TABLE quality.feedback_response DROP CONSTRAINT IF EXISTS feedback_response_target_type_check;
ALTER TABLE quality.feedback_response ADD CONSTRAINT feedback_response_target_type_check
  CHECK (target_type IN ('COURSE_OFFERING','FACULTY','PROGRAMME','INSTITUTION','INDUSTRY_ACTIVITY'));

ALTER TABLE quality.feedback_instrument DROP CONSTRAINT IF EXISTS feedback_instrument_purpose_check;
ALTER TABLE quality.feedback_instrument ADD CONSTRAINT feedback_instrument_purpose_check
  CHECK (purpose IN ('COURSE_FEEDBACK','FACULTY_FEEDBACK','CURRICULUM','FACILITIES','EXIT','EMPLOYER',
                     'INDUSTRY_INTERACTION'));

-- 2B. Non-semantic performance indexes on other domains' tables (no behaviour change).
--     Justification in spec section 17. Announce to the placement / quality owners.
CREATE INDEX IF NOT EXISTS idx_company_industry_partner ON placement.company (industry_partner_id)
  WHERE industry_partner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_company_sector        ON placement.company (institution_id, sector);
CREATE INDEX IF NOT EXISTS idx_offer_company_date    ON placement.offer (company_id, offer_date);
CREATE INDEX IF NOT EXISTS idx_internship_company_date ON placement.internship (company_id, from_date);
CREATE INDEX IF NOT EXISTS idx_job_opening_company   ON placement.job_opening (company_id, academic_year_id);
CREATE INDEX IF NOT EXISTS idx_evidence_source       ON quality.evidence_item (source_schema, source_table, source_id);

-- =====================================================================
-- PART 3.3 — NEW AGENT 28 TABLES
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3.1 engagement.partner_contact — many contact persons per partner.
--     The human is a people.person row (identity resolved once, platform-wide);
--     this row is the person's relationship with one partner.
-- ---------------------------------------------------------------------
CREATE TABLE engagement.partner_contact (
    partner_contact_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    industry_partner_id uuid NOT NULL REFERENCES engagement.industry_partner ON DELETE CASCADE,
    person_id           uuid NOT NULL REFERENCES people.person,
    designation         text,
    organisation_unit   text,
    contact_role        text NOT NULL DEFAULT 'OTHER'
                        CHECK (contact_role IN ('SPOC','HR','TECHNICAL','LEADERSHIP','ALUMNI_CHAMPION','OTHER')),
    work_email          text,
    work_phone          text,
    is_primary          boolean NOT NULL DEFAULT false,
    valid_from          date NOT NULL DEFAULT current_date,
    valid_to            date,
    CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT uq_pc_id_partner UNIQUE (partner_contact_id, industry_partner_id)
);
SELECT core.add_audit_columns('engagement.partner_contact');

CREATE UNIQUE INDEX uq_pc_active_person ON engagement.partner_contact (industry_partner_id, person_id)
  WHERE valid_to IS NULL;
CREATE UNIQUE INDEX uq_pc_one_primary   ON engagement.partner_contact (industry_partner_id)
  WHERE is_primary AND valid_to IS NULL;
CREATE UNIQUE INDEX uq_pc_active_email  ON engagement.partner_contact (industry_partner_id, lower(work_email))
  WHERE work_email IS NOT NULL AND valid_to IS NULL;
CREATE INDEX idx_pc_person ON engagement.partner_contact (person_id);

COMMENT ON TABLE engagement.partner_contact IS
  'Agent 28. work_email/work_phone are relationship-scoped (they change when the person changes employer) '
  'and are therefore not duplicates of people.person.primary_email/primary_phone.';

-- ---------------------------------------------------------------------
-- 3.2 engagement.partner_expertise — what the partner (or a named contact) can teach.
--     Mirrors the people.faculty_expertise pattern. Input to course matching.
-- ---------------------------------------------------------------------
CREATE TABLE engagement.partner_expertise (
    partner_expertise_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    industry_partner_id  uuid NOT NULL REFERENCES engagement.industry_partner ON DELETE CASCADE,
    partner_contact_id   uuid,
    area                 text NOT NULL,
    description          text,
    evidence_source      text NOT NULL DEFAULT 'DECLARED'
                         CHECK (evidence_source IN ('DECLARED','MOU_SCOPE','PAST_ACTIVITY','CONTACT_PROFILE','PUBLIC_PROFILE')),
    confidence           numeric(4,3) CHECK (confidence BETWEEN 0 AND 1),
    is_active            boolean NOT NULL DEFAULT true,
    -- a contact-level expertise row must belong to a contact OF THIS partner
    CONSTRAINT fk_pe_contact_partner FOREIGN KEY (partner_contact_id, industry_partner_id)
        REFERENCES engagement.partner_contact (partner_contact_id, industry_partner_id) ON DELETE CASCADE
);
SELECT core.add_audit_columns('engagement.partner_expertise');

CREATE UNIQUE INDEX uq_pe_area ON engagement.partner_expertise
  (industry_partner_id, COALESCE(partner_contact_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(area));
CREATE INDEX idx_pe_area_trgm ON engagement.partner_expertise USING gin (area gin_trgm_ops);
CREATE INDEX idx_pe_contact   ON engagement.partner_expertise (partner_contact_id) WHERE partner_contact_id IS NOT NULL;

-- ---------------------------------------------------------------------
-- 3.3 engagement.industry_activity_person — resource persons, hosts,
--     coordinators and participants of an activity (N:M activity <-> person).
-- ---------------------------------------------------------------------
CREATE TABLE engagement.industry_activity_person (
    industry_activity_id uuid NOT NULL REFERENCES engagement.industry_activity ON DELETE CASCADE,
    person_id            uuid NOT NULL REFERENCES people.person,
    participation_role   text NOT NULL CHECK (participation_role IN
                         ('RESOURCE_PERSON','INDUSTRY_HOST','FACULTY_COORDINATOR',
                          'FACULTY_PARTICIPANT','STUDENT_PARTICIPANT')),
    attended             boolean,
    PRIMARY KEY (industry_activity_id, person_id, participation_role)
);
CREATE INDEX idx_iap_person ON engagement.industry_activity_person (person_id);

-- ---------------------------------------------------------------------
-- 3.4 engagement.activity_course_alignment — "the interaction reinforces what
--     is being taught": activity <-> course version / unit / topic / offering.
-- ---------------------------------------------------------------------
CREATE TABLE engagement.activity_course_alignment (
    activity_course_alignment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    industry_activity_id   uuid NOT NULL REFERENCES engagement.industry_activity ON DELETE CASCADE,
    course_version_id      uuid NOT NULL REFERENCES curriculum.course_version,
    course_unit_id         uuid REFERENCES curriculum.course_unit ON DELETE SET NULL,
    course_topic_id        uuid REFERENCES curriculum.course_topic ON DELETE SET NULL,
    course_offering_id     uuid REFERENCES academics.course_offering ON DELETE SET NULL,
    lesson_plan_session_id uuid REFERENCES academics.lesson_plan_session ON DELETE SET NULL,
    partner_expertise_id   uuid REFERENCES engagement.partner_expertise ON DELETE SET NULL,
    is_primary             boolean NOT NULL DEFAULT false,
    alignment_source       text NOT NULL CHECK (alignment_source IN ('AGENT_SUGGESTED','USER_DECLARED')),
    match_score            numeric(5,2) CHECK (match_score BETWEEN 0 AND 100),
    match_rationale        text,
    status                 text NOT NULL DEFAULT 'SUGGESTED' CHECK (status IN ('SUGGESTED','CONFIRMED','REJECTED')),
    agent_run_id           uuid REFERENCES agentops.agent_run,
    confirmed_by_user_id   uuid REFERENCES identity.app_user,
    confirmed_at           timestamptz,
    CHECK (alignment_source <> 'AGENT_SUGGESTED' OR agent_run_id IS NOT NULL),
    CHECK (status <> 'CONFIRMED' OR confirmed_at IS NOT NULL)
);

CREATE UNIQUE INDEX uq_aca_target ON engagement.activity_course_alignment
  (industry_activity_id, course_version_id,
   COALESCE(course_unit_id,  '00000000-0000-0000-0000-000000000000'::uuid),
   COALESCE(course_topic_id, '00000000-0000-0000-0000-000000000000'::uuid));
CREATE UNIQUE INDEX uq_aca_one_primary ON engagement.activity_course_alignment (industry_activity_id)
  WHERE is_primary AND status <> 'REJECTED';
CREATE INDEX idx_aca_course_version ON engagement.activity_course_alignment (course_version_id, status);
CREATE INDEX idx_aca_offering ON engagement.activity_course_alignment (course_offering_id) WHERE course_offering_id IS NOT NULL;
CREATE INDEX idx_aca_topic    ON engagement.activity_course_alignment (course_topic_id)    WHERE course_topic_id IS NOT NULL;

-- Curriculum hierarchy integrity (unit ∈ version, topic ∈ unit, offering ∈ version,
-- lesson-plan session ∈ offering). The curriculum tables expose no composite keys,
-- so declarative composite FKs are impossible without altering curriculum.*.
-- Validation fires only when a reference is set/changed to a non-null value, so
-- ON DELETE SET NULL cascades from curriculum never fail.
CREATE OR REPLACE FUNCTION engagement.validate_course_alignment() RETURNS trigger AS $$
BEGIN
  IF NEW.course_topic_id IS NOT NULL AND NEW.course_unit_id IS NULL
     AND (TG_OP = 'INSERT' OR NEW.course_topic_id IS DISTINCT FROM OLD.course_topic_id) THEN
    RAISE EXCEPTION 'course_topic_id requires course_unit_id' USING ERRCODE = '23514';
  END IF;

  IF NEW.course_unit_id IS NOT NULL AND (TG_OP = 'INSERT'
       OR NEW.course_unit_id IS DISTINCT FROM OLD.course_unit_id
       OR NEW.course_version_id IS DISTINCT FROM OLD.course_version_id) THEN
    IF NOT EXISTS (SELECT 1 FROM curriculum.course_unit u
                    WHERE u.course_unit_id = NEW.course_unit_id
                      AND u.course_version_id = NEW.course_version_id) THEN
      RAISE EXCEPTION 'course_unit % is not part of course_version %', NEW.course_unit_id, NEW.course_version_id
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF NEW.course_topic_id IS NOT NULL AND (TG_OP = 'INSERT'
       OR NEW.course_topic_id IS DISTINCT FROM OLD.course_topic_id
       OR NEW.course_unit_id IS DISTINCT FROM OLD.course_unit_id) THEN
    IF NOT EXISTS (SELECT 1 FROM curriculum.course_topic t
                    WHERE t.course_topic_id = NEW.course_topic_id
                      AND t.course_unit_id = NEW.course_unit_id) THEN
      RAISE EXCEPTION 'course_topic % is not part of course_unit %', NEW.course_topic_id, NEW.course_unit_id
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF NEW.course_offering_id IS NOT NULL AND (TG_OP = 'INSERT'
       OR NEW.course_offering_id IS DISTINCT FROM OLD.course_offering_id
       OR NEW.course_version_id IS DISTINCT FROM OLD.course_version_id) THEN
    IF NOT EXISTS (SELECT 1 FROM academics.course_offering o
                    WHERE o.course_offering_id = NEW.course_offering_id
                      AND o.course_version_id = NEW.course_version_id) THEN
      RAISE EXCEPTION 'course_offering % is not an offering of course_version %', NEW.course_offering_id, NEW.course_version_id
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF NEW.lesson_plan_session_id IS NOT NULL AND (TG_OP = 'INSERT'
       OR NEW.lesson_plan_session_id IS DISTINCT FROM OLD.lesson_plan_session_id
       OR NEW.course_offering_id IS DISTINCT FROM OLD.course_offering_id) THEN
    IF NEW.course_offering_id IS NULL OR NOT EXISTS (
         SELECT 1 FROM academics.lesson_plan_session s
         JOIN academics.lesson_plan lp ON lp.lesson_plan_id = s.lesson_plan_id
        WHERE s.lesson_plan_session_id = NEW.lesson_plan_session_id
          AND lp.course_offering_id = NEW.course_offering_id) THEN
      RAISE EXCEPTION 'lesson_plan_session % does not belong to course_offering %', NEW.lesson_plan_session_id, NEW.course_offering_id
        USING ERRCODE = '23514';
    END IF;
  END IF;

  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_alignment_validate
  BEFORE INSERT OR UPDATE ON engagement.activity_course_alignment
  FOR EACH ROW EXECUTE FUNCTION engagement.validate_course_alignment();

-- ---------------------------------------------------------------------
-- 3.5 engagement.mou_deliverable_fulfilment — which authoritative records
--     count toward which committed deliverable. Typed nullable FKs + CHECK,
--     the same pattern the universal schema uses in research.publication_author.
--     Agent 28 links to Agent 49/50/51 records; it never copies them.
-- ---------------------------------------------------------------------
CREATE TABLE engagement.mou_deliverable_fulfilment (
    mou_deliverable_fulfilment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    mou_deliverable_id   uuid NOT NULL REFERENCES engagement.mou_deliverable ON DELETE CASCADE,
    industry_activity_id uuid REFERENCES engagement.industry_activity ON DELETE CASCADE,
    internship_id        uuid REFERENCES placement.internship  ON DELETE CASCADE,
    job_opening_id       uuid REFERENCES placement.job_opening ON DELETE CASCADE,
    offer_id             uuid REFERENCES placement.offer       ON DELETE CASCADE,
    event_id             uuid REFERENCES engagement.event      ON DELETE CASCADE,
    evidence_type        text GENERATED ALWAYS AS (
                           CASE WHEN industry_activity_id IS NOT NULL THEN 'INDUSTRY_ACTIVITY'
                                WHEN internship_id        IS NOT NULL THEN 'INTERNSHIP'
                                WHEN job_opening_id       IS NOT NULL THEN 'JOB_OPENING'
                                WHEN offer_id             IS NOT NULL THEN 'OFFER'
                                WHEN event_id             IS NOT NULL THEN 'EVENT' END) STORED,
    contributed_count    smallint NOT NULL DEFAULT 1 CHECK (contributed_count > 0),
    link_source          text NOT NULL CHECK (link_source IN ('AGENT_SUGGESTED','USER_DECLARED')),
    status               text NOT NULL DEFAULT 'SUGGESTED' CHECK (status IN ('SUGGESTED','CONFIRMED','REJECTED')),
    match_rationale      text,
    agent_run_id         uuid REFERENCES agentops.agent_run,
    confirmed_by_user_id uuid REFERENCES identity.app_user,
    confirmed_at         timestamptz,
    CONSTRAINT ck_mdf_exactly_one_evidence
        CHECK (num_nonnulls(industry_activity_id, internship_id, job_opening_id, offer_id, event_id) = 1),
    CHECK (link_source <> 'AGENT_SUGGESTED' OR agent_run_id IS NOT NULL),
    CHECK (status <> 'CONFIRMED' OR confirmed_at IS NOT NULL),
    UNIQUE (mou_deliverable_id, industry_activity_id),
    UNIQUE (mou_deliverable_id, internship_id),
    UNIQUE (mou_deliverable_id, job_opening_id),
    UNIQUE (mou_deliverable_id, offer_id),
    UNIQUE (mou_deliverable_id, event_id)
);
-- FK-side indexes: a delete in placement.* / engagement.* cascades here.
CREATE INDEX idx_mdf_activity   ON engagement.mou_deliverable_fulfilment (industry_activity_id) WHERE industry_activity_id IS NOT NULL;
CREATE INDEX idx_mdf_internship ON engagement.mou_deliverable_fulfilment (internship_id)        WHERE internship_id IS NOT NULL;
CREATE INDEX idx_mdf_job        ON engagement.mou_deliverable_fulfilment (job_opening_id)       WHERE job_opening_id IS NOT NULL;
CREATE INDEX idx_mdf_offer      ON engagement.mou_deliverable_fulfilment (offer_id)             WHERE offer_id IS NOT NULL;
CREATE INDEX idx_mdf_event      ON engagement.mou_deliverable_fulfilment (event_id)             WHERE event_id IS NOT NULL;

-- Keep mou_deliverable.achieved_count equal to the confirmed evidence.
-- SECURITY DEFINER so a cascade triggered by another agent's role does not need
-- UPDATE rights on engagement.mou_deliverable.
CREATE OR REPLACE FUNCTION engagement.refresh_deliverable_achieved_count() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, engagement AS $$
DECLARE v_ids uuid[] := ARRAY[]::uuid[];
BEGIN
  IF TG_OP IN ('INSERT','UPDATE') THEN v_ids := v_ids || NEW.mou_deliverable_id; END IF;
  IF TG_OP IN ('UPDATE','DELETE') THEN v_ids := v_ids || OLD.mou_deliverable_id; END IF;
  UPDATE engagement.mou_deliverable d
     SET achieved_count = COALESCE((
           SELECT sum(f.contributed_count)
             FROM engagement.mou_deliverable_fulfilment f
            WHERE f.mou_deliverable_id = d.mou_deliverable_id
              AND f.status = 'CONFIRMED'), 0)
   WHERE d.mou_deliverable_id = ANY (v_ids);
  RETURN NULL;
END; $$;

CREATE TRIGGER trg_fulfilment_achieved_count
  AFTER INSERT OR UPDATE OR DELETE ON engagement.mou_deliverable_fulfilment
  FOR EACH ROW EXECUTE FUNCTION engagement.refresh_deliverable_achieved_count();

-- ---------------------------------------------------------------------
-- 3.6 engagement.mou_renewal — renewal discussion lifecycle and MoU lineage.
--     Required to answer "MoUs approaching expiry WITHOUT renewal discussion".
-- ---------------------------------------------------------------------
CREATE TABLE engagement.mou_renewal (
    mou_renewal_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    mou_id                  uuid NOT NULL REFERENCES engagement.mou ON DELETE CASCADE,
    initiated_on            date NOT NULL DEFAULT current_date,
    initiated_by_faculty_id uuid REFERENCES people.faculty,
    partner_contact_id      uuid REFERENCES engagement.partner_contact ON DELETE SET NULL,
    status                  text NOT NULL DEFAULT 'DISCUSSION_INITIATED'
                            CHECK (status IN ('DISCUSSION_INITIATED','NEGOTIATING','DRAFT_SHARED','APPROVED_INTERNALLY',
                                              'SIGNED','DECLINED_BY_PARTNER','DECLINED_BY_INSTITUTION','LAPSED')),
    target_sign_by          date,
    successor_mou_id        uuid UNIQUE REFERENCES engagement.mou,
    closed_on               date,
    notes                   text,
    CHECK (successor_mou_id IS NULL OR successor_mou_id <> mou_id),
    CHECK (status <> 'SIGNED' OR successor_mou_id IS NOT NULL),
    CHECK ((status IN ('DISCUSSION_INITIATED','NEGOTIATING','DRAFT_SHARED','APPROVED_INTERNALLY')) = (closed_on IS NULL)),
    CHECK (closed_on IS NULL OR closed_on >= initiated_on)
);
SELECT core.add_audit_columns('engagement.mou_renewal');

CREATE UNIQUE INDEX uq_mou_renewal_one_open ON engagement.mou_renewal (mou_id)
  WHERE status IN ('DISCUSSION_INITIATED','NEGOTIATING','DRAFT_SHARED','APPROVED_INTERNALLY');
CREATE INDEX idx_mou_renewal_mou ON engagement.mou_renewal (mou_id, initiated_on DESC);

-- ---------------------------------------------------------------------
-- 3.7 engagement.partner_health_snapshot — engagement health history.
--     Same rationale the universal schema gives for academics.coverage_snapshot:
--     the history is itself the reportable artefact. Formula = agentops.model_version.
-- ---------------------------------------------------------------------
CREATE TABLE engagement.partner_health_snapshot (
    partner_health_snapshot_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    industry_partner_id   uuid NOT NULL REFERENCES engagement.industry_partner ON DELETE CASCADE,
    as_of_date            date NOT NULL,
    model_version_id      uuid NOT NULL REFERENCES agentops.model_version,
    agent_run_id          uuid REFERENCES agentops.agent_run,
    health_score          numeric(5,2) NOT NULL CHECK (health_score BETWEEN 0 AND 100),
    health_band           text NOT NULL CHECK (health_band IN ('STRONG','STABLE','AT_RISK','DORMANT')),
    is_dormant            boolean NOT NULL,
    components            jsonb NOT NULL,      -- {component: {normalised: 0..1, weight: w, contribution: x}}
    last_activity_on      date,
    days_since_last_activity integer CHECK (days_since_last_activity IS NULL OR days_since_last_activity >= 0),
    activities_12m        smallint NOT NULL DEFAULT 0 CHECK (activities_12m >= 0),
    internships_12m       smallint NOT NULL DEFAULT 0 CHECK (internships_12m >= 0),
    offers_12m            smallint NOT NULL DEFAULT 0 CHECK (offers_12m >= 0),
    active_mou_count      smallint NOT NULL DEFAULT 0 CHECK (active_mou_count >= 0),
    deliverables_due      smallint NOT NULL DEFAULT 0 CHECK (deliverables_due >= 0),
    deliverables_achieved smallint NOT NULL DEFAULT 0 CHECK (deliverables_achieved >= 0),
    avg_feedback_rating   numeric(3,2) CHECK (avg_feedback_rating BETWEEN 1 AND 5),
    mous_expiring_without_renewal smallint NOT NULL DEFAULT 0 CHECK (mous_expiring_without_renewal >= 0),
    computed_at           timestamptz NOT NULL DEFAULT now(),
    CHECK (jsonb_typeof(components) = 'object'),
    CHECK (health_band <> 'DORMANT' OR is_dormant),
    UNIQUE (industry_partner_id, as_of_date, model_version_id)
);
CREATE INDEX idx_phs_partner_latest ON engagement.partner_health_snapshot (industry_partner_id, as_of_date DESC);
CREATE INDEX idx_phs_band ON engagement.partner_health_snapshot (as_of_date, health_band);

-- ---------------------------------------------------------------------
-- 3.8 engagement.partner_alumni_link (SHOULD-HAVE) — resolved alumni <-> partner
--     links. placement.alumni.current_organisation is free text; this table stores
--     the verified resolution, not a copy of alumni data.
-- ---------------------------------------------------------------------
CREATE TABLE engagement.partner_alumni_link (
    industry_partner_id  uuid NOT NULL REFERENCES engagement.industry_partner ON DELETE CASCADE,
    alumni_id            uuid NOT NULL REFERENCES placement.alumni ON DELETE CASCADE,
    match_method         text NOT NULL CHECK (match_method IN
                         ('PARTNER_CONTACT','COMPANY_ALUMNI_CONNECT','ORGANISATION_NAME_MATCH','MANUAL')),
    match_confidence     numeric(4,3) CHECK (match_confidence BETWEEN 0 AND 1),
    status               text NOT NULL DEFAULT 'SUGGESTED' CHECK (status IN ('SUGGESTED','CONFIRMED','REJECTED')),
    agent_run_id         uuid REFERENCES agentops.agent_run,
    confirmed_by_user_id uuid REFERENCES identity.app_user,
    confirmed_at         timestamptz,
    PRIMARY KEY (industry_partner_id, alumni_id),
    CHECK (status <> 'CONFIRMED' OR confirmed_at IS NOT NULL)
);
CREATE INDEX idx_pal_alumni ON engagement.partner_alumni_link (alumni_id);

-- =====================================================================
-- PART 3.4 — AGENT 28 VIEWS (read layer). "Agents query views, not base tables, so that
-- metric definitions live in one place" — universal 12_views.sql convention.
-- =====================================================================

-- Every partner-attributable event across agents, without copying any of it.
CREATE VIEW engagement.v_partner_activity_ledger AS
SELECT COALESCE(ia.industry_partner_id, m.industry_partner_id) AS industry_partner_id,
       'INDUSTRY_ACTIVITY'::text AS source_type,
       ia.activity_type          AS event_type,
       ia.industry_activity_id   AS source_id,
       ia.activity_date          AS event_date,
       ia.title,
       ia.department_id,
       ia.participant_count::integer AS headcount,
       ia.status,
       (ia.status = 'CONDUCTED')  AS is_realised
FROM engagement.industry_activity ia
LEFT JOIN engagement.mou m ON m.mou_id = ia.mou_id
UNION ALL
SELECT c.industry_partner_id, 'INTERNSHIP', 'INTERNSHIP', i.internship_id, i.from_date,
       COALESCE(i.domain, 'Internship'), pr.department_id, 1, i.status,
       (i.status IN ('APPROVED','ONGOING','COMPLETED'))
FROM placement.internship i
JOIN placement.company c   ON c.company_id = i.company_id
JOIN people.student s      ON s.student_id = i.student_id
JOIN curriculum.batch b    ON b.batch_id = s.batch_id
JOIN curriculum.programme pr ON pr.programme_id = b.programme_id
WHERE c.industry_partner_id IS NOT NULL
UNION ALL
SELECT c.industry_partner_id, 'JOB_OPENING', j.opening_type, j.job_opening_id,
       COALESCE(j.drive_date, j.application_deadline, j.created_at::date),
       j.role_title, NULL::uuid, j.positions_open::integer, j.status,
       (j.status IN ('OPEN','CLOSED','DRIVE_COMPLETED'))
FROM placement.job_opening j
JOIN placement.company c ON c.company_id = j.company_id
WHERE c.industry_partner_id IS NOT NULL
UNION ALL
SELECT c.industry_partner_id, 'OFFER', CASE WHEN o.is_ppo THEN 'PPO' ELSE 'OFFER' END, o.offer_id, o.offer_date,
       COALESCE(o.role_title, 'Offer'), pr.department_id, 1, o.status,
       (o.status IN ('OFFERED','ACCEPTED','JOINED'))
FROM placement.offer o
JOIN placement.company c   ON c.company_id = o.company_id
JOIN people.student s      ON s.student_id = o.student_id
JOIN curriculum.batch b    ON b.batch_id = s.batch_id
JOIN curriculum.programme pr ON pr.programme_id = b.programme_id
WHERE c.industry_partner_id IS NOT NULL;

COMMENT ON VIEW engagement.v_partner_activity_ledger IS
  'Agent 28 engagement history. Internship/offer/opening rows remain owned by the placement agents; '
  'attribution is through placement.company.industry_partner_id. No student identifiers are exposed.';

-- Deliverable tracker: confirmed evidence is the truth; achieved_count is a cache.
CREATE VIEW engagement.v_deliverable_status AS
SELECT d.mou_deliverable_id, d.mou_id, m.industry_partner_id,
       d.description, d.deliverable_type, d.recurrence,
       d.target_count,
       f.confirmed_count          AS achieved_count,
       f.suggested_count          AS links_awaiting_confirmation,
       d.due_date, d.status,
       CASE WHEN d.target_count > 0
            THEN round(100.0 * LEAST(f.confirmed_count, d.target_count) / d.target_count, 2) END AS achievement_pct,
       CASE WHEN m.valid_from IS NOT NULL AND m.valid_until > m.valid_from
            THEN round(100.0 * GREATEST(0, LEAST(current_date, m.valid_until) - m.valid_from)
                       / (m.valid_until - m.valid_from), 2) END AS mou_elapsed_pct,
       COALESCE(d.status IN ('PENDING','IN_PROGRESS') AND d.due_date < current_date, false) AS is_overdue,
       (d.achieved_count <> f.confirmed_count) AS count_cache_mismatch,
       d.source_text, d.source_page_no
FROM engagement.mou_deliverable d
JOIN engagement.mou m ON m.mou_id = d.mou_id
CROSS JOIN LATERAL (
    SELECT COALESCE(sum(x.contributed_count) FILTER (WHERE x.status = 'CONFIRMED'), 0)::integer AS confirmed_count,
           count(*) FILTER (WHERE x.status = 'SUGGESTED')::integer AS suggested_count
    FROM engagement.mou_deliverable_fulfilment x
    WHERE x.mou_deliverable_id = d.mou_deliverable_id
) f;

-- MoU tracker with expiry / renewal flags.
CREATE VIEW engagement.v_mou_tracker AS
SELECT m.mou_id, m.industry_partner_id,
       COALESCE(ip.name, m.partner_name) AS partner_name,
       m.partner_type, m.title, m.scope, m.signed_on, m.valid_from, m.valid_until, m.status,
       CASE WHEN m.status = 'ACTIVE' AND m.valid_until < current_date
            THEN 'EXPIRED_NOT_RECORDED' ELSE m.status END                      AS effective_status,
       (m.valid_until - current_date)                                          AS days_to_expiry,
       COALESCE(m.renewal_alert_days, 90)                                      AS renewal_alert_days,
       r.mou_renewal_id AS open_renewal_id,
       r.status         AS open_renewal_status,
       (m.status = 'ACTIVE' AND m.valid_until IS NOT NULL
        AND m.valid_until - current_date <= COALESCE(m.renewal_alert_days, 90)) AS in_renewal_window,
       (m.status = 'ACTIVE' AND m.valid_until IS NOT NULL
        AND m.valid_until - current_date <= COALESCE(m.renewal_alert_days, 90)
        AND r.mou_renewal_id IS NULL)                                          AS expiring_without_renewal,
       ds.deliverables_total, ds.deliverables_achieved, ds.deliverables_overdue, ds.weighted_achievement_pct,
       ac.activities_conducted, ac.last_activity_on,
       m.owner_faculty_id, m.document_ref, m.extraction_job_id
FROM engagement.mou m
LEFT JOIN engagement.industry_partner ip ON ip.industry_partner_id = m.industry_partner_id
LEFT JOIN LATERAL (
    SELECT rr.mou_renewal_id, rr.status
    FROM engagement.mou_renewal rr
    WHERE rr.mou_id = m.mou_id
      AND rr.status IN ('DISCUSSION_INITIATED','NEGOTIATING','DRAFT_SHARED','APPROVED_INTERNALLY')
    ORDER BY rr.initiated_on DESC LIMIT 1
) r ON true
LEFT JOIN LATERAL (
    SELECT count(*)::integer                                       AS deliverables_total,
           count(*) FILTER (WHERE v.status = 'ACHIEVED')::integer  AS deliverables_achieved,
           count(*) FILTER (WHERE v.is_overdue)::integer           AS deliverables_overdue,
           round(100.0 * sum(LEAST(v.achieved_count, v.target_count)) FILTER (WHERE v.target_count > 0)
                 / nullif(sum(v.target_count) FILTER (WHERE v.target_count > 0), 0), 2) AS weighted_achievement_pct
    FROM engagement.v_deliverable_status v
    WHERE v.mou_id = m.mou_id
) ds ON true
LEFT JOIN LATERAL (
    SELECT count(*) FILTER (WHERE a.status = 'CONDUCTED')::integer AS activities_conducted,
           max(a.activity_date) FILTER (WHERE a.status = 'CONDUCTED') AS last_activity_on
    FROM engagement.industry_activity a
    WHERE a.mou_id = m.mou_id
) ac ON true;

-- Latest health snapshot per partner.
CREATE VIEW engagement.v_partner_health_latest AS
SELECT DISTINCT ON (s.industry_partner_id) s.*
FROM engagement.partner_health_snapshot s
ORDER BY s.industry_partner_id, s.as_of_date DESC, s.computed_at DESC;

-- Partner register.
CREATE VIEW engagement.v_partner_register AS
SELECT ip.industry_partner_id, ip.institution_id, ip.name, ip.sector,
       sec.label AS sector_label, ip.website, ip.status,
       ip.relationship_owner_faculty_id, owner_p.full_name AS relationship_owner_name,
       owner_f.department_id AS relationship_owner_department_id,
       pc.partner_contact_id AS primary_contact_id,
       pc_p.full_name        AS primary_contact_name,
       pc.designation        AS primary_contact_designation,
       COALESCE(pc.work_email, pc_p.primary_email) AS primary_contact_email,
       COALESCE(pc.work_phone, pc_p.primary_phone) AS primary_contact_phone,
       (SELECT count(*) FROM engagement.partner_contact c
         WHERE c.industry_partner_id = ip.industry_partner_id AND c.valid_to IS NULL)::integer AS active_contacts,
       (SELECT count(*) FROM engagement.mou mm
         WHERE mm.industry_partner_id = ip.industry_partner_id AND mm.status = 'ACTIVE')::integer AS active_mous,
       (SELECT max(l.event_date) FROM engagement.v_partner_activity_ledger l
         WHERE l.industry_partner_id = ip.industry_partner_id
           AND l.is_realised AND l.event_date <= current_date) AS last_activity_on,
       h.health_score, h.health_band, h.is_dormant, h.as_of_date AS health_as_of
FROM engagement.industry_partner ip
LEFT JOIN (core.code_value sec
           JOIN core.code_list sl ON sl.code_list_id = sec.code_list_id AND sl.code = 'INDUSTRY_SECTOR')
       ON sec.code = ip.sector
LEFT JOIN people.faculty owner_f ON owner_f.faculty_id = ip.relationship_owner_faculty_id
LEFT JOIN people.person  owner_p ON owner_p.person_id = owner_f.person_id
LEFT JOIN engagement.partner_contact pc
       ON pc.industry_partner_id = ip.industry_partner_id AND pc.is_primary AND pc.valid_to IS NULL
LEFT JOIN people.person pc_p ON pc_p.person_id = pc.person_id
LEFT JOIN engagement.v_partner_health_latest h ON h.industry_partner_id = ip.industry_partner_id;

-- Activity calendar with course alignment, resource persons, feedback volume and
-- academic-calendar clashes (holidays / exams / instruction blocks).
CREATE VIEW engagement.v_activity_calendar AS
SELECT ia.industry_activity_id, ia.activity_date,
       COALESCE(ia.end_date, ia.activity_date) AS end_date,
       ia.activity_type, ia.status, ia.title, ia.mode,
       COALESCE(ia.industry_partner_id, m.industry_partner_id) AS industry_partner_id,
       ip.name AS partner_name, ia.mou_id,
       ia.department_id, d.code AS department_code,
       pa.course_version_id AS primary_course_version_id, cv.course_code, c.title AS course_title,
       pa.course_topic_id   AS primary_course_topic_id,
       (SELECT string_agg(p.full_name, ', ' ORDER BY p.full_name)
          FROM engagement.industry_activity_person ap
          JOIN people.person p ON p.person_id = ap.person_id
         WHERE ap.industry_activity_id = ia.industry_activity_id
           AND ap.participation_role = 'RESOURCE_PERSON') AS resource_persons,
       (SELECT count(*) FROM quality.feedback_response fr
         WHERE fr.target_type = 'INDUSTRY_ACTIVITY' AND fr.target_id = ia.industry_activity_id)::integer AS feedback_responses,
       (SELECT array_agg(ce.event_type || ': ' || ce.title ORDER BY ce.event_date)
          FROM core.calendar_event ce
          JOIN core.academic_year ay ON ay.academic_year_id = ce.academic_year_id
         WHERE ay.institution_id = d.institution_id
           AND (ce.department_id IS NULL OR ce.department_id = ia.department_id)
           AND ce.event_date <= COALESCE(ia.end_date, ia.activity_date)
           AND COALESCE(ce.end_date, ce.event_date) >= ia.activity_date
           AND (ce.blocks_instruction OR ce.event_type IN ('HOLIDAY','EXAM','VACATION'))) AS calendar_clashes
FROM engagement.industry_activity ia
LEFT JOIN engagement.mou m ON m.mou_id = ia.mou_id
LEFT JOIN engagement.industry_partner ip ON ip.industry_partner_id = COALESCE(ia.industry_partner_id, m.industry_partner_id)
LEFT JOIN core.department d ON d.department_id = ia.department_id
LEFT JOIN engagement.activity_course_alignment pa
       ON pa.industry_activity_id = ia.industry_activity_id AND pa.is_primary AND pa.status <> 'REJECTED'
LEFT JOIN curriculum.course_version cv ON cv.course_version_id = pa.course_version_id
LEFT JOIN curriculum.course c ON c.course_id = cv.course_id;

-- Student feedback per interaction (reuses quality.feedback_response).
-- ASSUMPTION: the INDUSTRY_INTERACTION instrument stores a 1-5 answer under key 'overall_rating'.
CREATE VIEW engagement.v_activity_feedback_summary AS
SELECT fr.target_id AS industry_activity_id,
       count(*)::integer AS responses,
       round(avg((fr.answers->>'overall_rating')::numeric)
             FILTER (WHERE fr.answers->>'overall_rating' ~ '^[1-5]$'), 2) AS avg_overall_rating,
       min(fr.submitted_at) AS first_response_at,
       max(fr.submitted_at) AS last_response_at
FROM quality.feedback_response fr
WHERE fr.target_type = 'INDUSTRY_ACTIVITY'
GROUP BY fr.target_id;

-- Placement sectors vs partnership sectors, per institution and academic year.
CREATE VIEW engagement.v_sector_gap AS
WITH placed AS (
    SELECT ay.institution_id, ay.academic_year_id, COALESCE(c.sector, 'UNMAPPED') AS sector,
           count(*) AS accepted_offers
    FROM placement.offer o
    JOIN placement.company c ON c.company_id = o.company_id
    JOIN core.academic_year ay ON ay.institution_id = c.institution_id
                              AND o.offer_date BETWEEN ay.start_date AND ay.end_date
    WHERE o.status IN ('ACCEPTED','JOINED')
    GROUP BY 1, 2, 3
), interned AS (
    SELECT ay.institution_id, ay.academic_year_id, COALESCE(c.sector, 'UNMAPPED') AS sector,
           count(*) AS internships
    FROM placement.internship i
    JOIN people.student s ON s.student_id = i.student_id
    JOIN people.person  p ON p.person_id = s.person_id
    LEFT JOIN placement.company c ON c.company_id = i.company_id
    JOIN core.academic_year ay ON ay.institution_id = p.institution_id
                              AND i.from_date BETWEEN ay.start_date AND ay.end_date
    WHERE i.status IN ('APPROVED','ONGOING','COMPLETED')
    GROUP BY 1, 2, 3
), engaged AS (
    SELECT ay.institution_id, ay.academic_year_id, COALESCE(ip.sector, 'UNMAPPED') AS sector,
           count(DISTINCT ip.industry_partner_id) AS engaged_partners,
           count(DISTINCT m.mou_id)               AS mous_in_force
    FROM engagement.industry_partner ip
    JOIN core.academic_year ay ON ay.institution_id = ip.institution_id
    LEFT JOIN engagement.mou m
           ON m.industry_partner_id = ip.industry_partner_id
          AND m.status IN ('ACTIVE','RENEWED','EXPIRED')
          AND COALESCE(m.valid_from, m.signed_on) <= ay.end_date
          AND (m.valid_until IS NULL OR m.valid_until >= ay.start_date)
    WHERE m.mou_id IS NOT NULL
       OR EXISTS (SELECT 1 FROM engagement.industry_activity a
                  WHERE a.industry_partner_id = ip.industry_partner_id
                    AND a.status = 'CONDUCTED'
                    AND a.activity_date BETWEEN ay.start_date AND ay.end_date)
    GROUP BY 1, 2, 3
), keys AS (
    SELECT institution_id, academic_year_id, sector FROM placed
    UNION SELECT institution_id, academic_year_id, sector FROM interned
    UNION SELECT institution_id, academic_year_id, sector FROM engaged
)
SELECT k.institution_id, k.academic_year_id, ay.label AS academic_year, k.sector,
       COALESCE(pl.accepted_offers, 0)  AS accepted_offers,
       COALESCE(it.internships, 0)      AS internships,
       COALESCE(en.engaged_partners, 0) AS engaged_partners,
       COALESCE(en.mous_in_force, 0)    AS mous_in_force,
       round(100.0 * COALESCE(pl.accepted_offers, 0)
             / nullif(sum(COALESCE(pl.accepted_offers, 0)) OVER w, 0), 2) AS placement_share_pct,
       round(100.0 * COALESCE(en.engaged_partners, 0)
             / nullif(sum(COALESCE(en.engaged_partners, 0)) OVER w, 0), 2) AS partnership_share_pct,
       round(100.0 * COALESCE(pl.accepted_offers, 0) / nullif(sum(COALESCE(pl.accepted_offers, 0)) OVER w, 0)
           - 100.0 * COALESCE(en.engaged_partners, 0) / nullif(sum(COALESCE(en.engaged_partners, 0)) OVER w, 0), 2)
             AS gap_pct_points   -- > 0 : students go to this sector more than partnerships cover it
FROM keys k
JOIN core.academic_year ay ON ay.academic_year_id = k.academic_year_id
LEFT JOIN placed   pl ON (pl.institution_id, pl.academic_year_id, pl.sector) = (k.institution_id, k.academic_year_id, k.sector)
LEFT JOIN interned it ON (it.institution_id, it.academic_year_id, it.sector) = (k.institution_id, k.academic_year_id, k.sector)
LEFT JOIN engaged  en ON (en.institution_id, en.academic_year_id, en.sector) = (k.institution_id, k.academic_year_id, k.sector)
WINDOW w AS (PARTITION BY k.institution_id, k.academic_year_id);

-- Candidate features for target-partner recommendation (the ranking itself is agent output).
CREATE VIEW engagement.v_target_partner_candidates AS
SELECT c.company_id, c.institution_id, c.name AS company_name, c.sector, c.tier,
       c.industry_partner_id, ip.status AS partner_status,
       x.accepted_offers_3y, x.internships_3y, x.openings_3y,
       (c.alumni_connect_person_id IS NOT NULL) AS has_alumni_connect,
       (SELECT count(*) FROM placement.alumni a
         WHERE a.contact_consent
           AND lower(btrim(a.current_organisation)) = lower(btrim(c.name)))::integer AS consenting_alumni_name_match
FROM placement.company c
LEFT JOIN engagement.industry_partner ip ON ip.industry_partner_id = c.industry_partner_id
CROSS JOIN LATERAL (
    SELECT (SELECT count(*) FROM placement.offer o
             WHERE o.company_id = c.company_id AND o.status IN ('ACCEPTED','JOINED')
               AND o.offer_date >= current_date - 1095)::integer AS accepted_offers_3y,
           (SELECT count(*) FROM placement.internship i
             WHERE i.company_id = c.company_id AND i.status IN ('APPROVED','ONGOING','COMPLETED')
               AND i.from_date >= current_date - 1095)::integer AS internships_3y,
           (SELECT count(*) FROM placement.job_opening j
             WHERE j.company_id = c.company_id AND j.status <> 'CANCELLED'
               AND COALESCE(j.drive_date, j.application_deadline, j.created_at::date) >= current_date - 1095)::integer AS openings_3y
) x
WHERE c.industry_partner_id IS NULL
   OR ip.status IN ('PROSPECT','DORMANT','CONCLUDED');

-- Accreditation evidence generated from engagement records (reuses quality.evidence_item).
CREATE VIEW engagement.v_accreditation_evidence AS
SELECT ei.evidence_item_id, cf.code AS framework_code, ac.code AS criterion_code, ac.title AS criterion_title,
       ei.title, ei.evidence_type, ei.period_start, ei.period_end, ei.document_ref,
       ei.source_table, ei.source_id, ei.generated_by_agent, ei.content_hash,
       ei.approved_by_user_id, ei.approved_at, ei.created_at
FROM quality.evidence_item ei
LEFT JOIN quality.accreditation_criterion ac ON ac.accreditation_criterion_id = ei.accreditation_criterion_id
LEFT JOIN governance.compliance_framework cf ON cf.compliance_framework_id = ac.compliance_framework_id
WHERE ei.source_schema = 'engagement';
-- =====================================================================
-- PART 4 — SYNTHETIC MASTER DATA
-- Everything below is FICTIONAL. Institution, companies, people, e-mail
-- addresses (*.example) and documents are invented for development only.
-- IDs are deterministic: md5('<kind>:<key>')::uuid, so the same load always
-- produces the same primary keys (handy for tests and API fixtures).
-- Demo "today" is 2026-09-11; expiry / dormancy flags are designed around it.
-- =====================================================================

-- deterministic helpers (session-temporary; they vanish when the load session ends)
CREATE FUNCTION pg_temp.uid(k text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT md5(k)::uuid $$;
CREATE FUNCTION pg_temp.rnd(k text) RETURNS numeric LANGUAGE sql IMMUTABLE AS
$$ SELECT ('x' || substr(md5(k), 1, 8))::bit(32)::bigint / 4294967296.0 $$;
CREATE FUNCTION pg_temp.pick(arr text[], k text) RETURNS text LANGUAGE sql IMMUTABLE AS
$$ SELECT arr[1 + floor(pg_temp.rnd(k) * array_length(arr, 1))::int] $$;

-- stamp created_by/updated_by with the agent service account during the load
SELECT set_config('app.user_id', md5('user:svc.agent28'), true);

-- ---------------------------------------------------------------------
-- 4.1 Institution, departments, academic calendar
-- ---------------------------------------------------------------------
INSERT INTO core.institution (institution_id, code, name, type, affiliating_body, aishe_code, address)
VALUES (pg_temp.uid('inst:DIET'), 'DIET', 'Demo Institute of Engineering and Technology', 'AUTONOMOUS',
        'Demo State Technological University', 'C-00000',
        '{"city":"Hyderabad","state":"Telangana","country":"IN","note":"synthetic"}');

INSERT INTO core.department (department_id, institution_id, code, name, short_name, type, established_on)
SELECT pg_temp.uid('dept:' || d.code), pg_temp.uid('inst:DIET'), d.code, d.name, d.code, d.type, d.est::date
FROM (VALUES
  ('CSE',  'Computer Science and Engineering',          'ACADEMIC', '2001-07-01'),
  ('IT',   'Information Technology',                    'ACADEMIC', '2002-07-01'),
  ('ECE',  'Electronics and Communication Engineering', 'ACADEMIC', '2001-07-01'),
  ('EEE',  'Electrical and Electronics Engineering',    'ACADEMIC', '2001-07-01'),
  ('MECH', 'Mechanical Engineering',                    'ACADEMIC', '2004-07-01'),
  ('CIVIL','Civil Engineering',                         'ACADEMIC', '2006-07-01'),
  ('IIIC', 'Industry Institute Interaction Cell',       'SUPPORT',  '2012-07-01'),
  ('TPC',  'Training and Placement Cell',               'SUPPORT',  '2005-07-01')
) AS d(code, name, type, est);

INSERT INTO core.academic_year (academic_year_id, institution_id, label, start_date, end_date, is_current)
SELECT pg_temp.uid('ay:' || y.label), pg_temp.uid('inst:DIET'), y.label, y.s::date, y.e::date, y.cur
FROM (VALUES ('2024-25','2024-06-01','2025-05-31',false),
             ('2025-26','2025-06-01','2026-05-31',false),
             ('2026-27','2026-06-01','2027-05-31',true)) AS y(label, s, e, cur);

INSERT INTO core.term (term_id, academic_year_id, term_no, label, parity, start_date, end_date, instruction_end, status)
SELECT pg_temp.uid('term:' || t.label), pg_temp.uid('ay:' || t.ay), t.no, t.label, t.parity, t.s::date, t.e::date, t.ie::date, t.status
FROM (VALUES
  ('2024-25', 1, 'ODD 2024-25',  'ODD',  '2024-07-01','2024-11-30','2024-11-05','CLOSED'),
  ('2024-25', 2, 'EVEN 2024-25', 'EVEN', '2024-12-16','2025-05-10','2025-04-15','CLOSED'),
  ('2025-26', 1, 'ODD 2025-26',  'ODD',  '2025-07-01','2025-11-30','2025-11-05','CLOSED'),
  ('2025-26', 2, 'EVEN 2025-26', 'EVEN', '2025-12-15','2026-05-09','2026-04-14','CLOSED'),
  ('2026-27', 1, 'ODD 2026-27',  'ODD',  '2026-07-01','2026-11-30','2026-11-06','ACTIVE'),
  ('2026-27', 2, 'EVEN 2026-27', 'EVEN', '2026-12-14','2027-05-08','2027-04-13','PLANNED')
) AS t(ay, no, label, parity, s, e, ie, status);

INSERT INTO core.calendar_event (calendar_event_id, academic_year_id, department_id, event_date, end_date, title, event_type, blocks_instruction)
SELECT pg_temp.uid('cal:' || c.ay || ':' || c.title), pg_temp.uid('ay:' || c.ay), NULL, c.s::date, c.e::date, c.title, c.kind, c.blocks
FROM (VALUES
  ('2024-25','Independence Day','2024-08-15',NULL,'HOLIDAY',true),
  ('2024-25','Mid-term examinations (odd)','2024-09-16','2024-09-21','EXAM',true),
  ('2024-25','Gandhi Jayanti','2024-10-02',NULL,'HOLIDAY',true),
  ('2024-25','Deepavali break','2024-10-31','2024-11-02','HOLIDAY',true),
  ('2024-25','End-semester examinations (odd)','2024-11-11','2024-11-26','EXAM',true),
  ('2024-25','Mid-term examinations (even)','2025-02-17','2025-02-22','EXAM',true),
  ('2024-25','End-semester examinations (even)','2025-04-21','2025-05-06','EXAM',true),
  ('2024-25','Summer vacation','2025-05-12','2025-06-28','VACATION',true),
  ('2025-26','Independence Day','2025-08-15',NULL,'HOLIDAY',true),
  ('2025-26','Mid-term examinations (odd)','2025-09-15','2025-09-20','EXAM',true),
  ('2025-26','Gandhi Jayanti','2025-10-02',NULL,'HOLIDAY',true),
  ('2025-26','Deepavali break','2025-10-20','2025-10-22','HOLIDAY',true),
  ('2025-26','End-semester examinations (odd)','2025-11-10','2025-11-25','EXAM',true),
  ('2025-26','Mid-term examinations (even)','2026-02-16','2026-02-21','EXAM',true),
  ('2025-26','End-semester examinations (even)','2026-04-20','2026-05-05','EXAM',true),
  ('2025-26','Summer vacation','2026-05-11','2026-06-27','VACATION',true),
  ('2026-27','Independence Day','2026-08-15',NULL,'HOLIDAY',true),
  ('2026-27','Mid-term examinations (odd)','2026-09-14','2026-09-19','EXAM',true),
  ('2026-27','Gandhi Jayanti','2026-10-02',NULL,'HOLIDAY',true),
  ('2026-27','Deepavali break','2026-11-07','2026-11-09','HOLIDAY',true),
  ('2026-27','End-semester examinations (odd)','2026-11-10','2026-11-25','EXAM',true),
  ('2026-27','Industry Day (institution event)','2026-10-16',NULL,'EVENT',false)
) AS c(ay, title, s, e, kind, blocks);

-- ---------------------------------------------------------------------
-- 4.2 Sector vocabulary (shared by industry_partner.sector and placement.company.sector)
-- ---------------------------------------------------------------------
INSERT INTO core.code_list (code_list_id, code, name, description)
VALUES (pg_temp.uid('codelist:INDUSTRY_SECTOR'), 'INDUSTRY_SECTOR', 'Industry sector',
        'Single sector vocabulary for engagement.industry_partner.sector AND placement.company.sector. attributes.aliases[] holds raw spellings mapped to the code.');

INSERT INTO core.code_value (code_value_id, code_list_id, code, label, sort_order, attributes)
SELECT pg_temp.uid('sector:' || v.code), pg_temp.uid('codelist:INDUSTRY_SECTOR'), v.code, v.label, v.ord, v.attr::jsonb
FROM (VALUES
  ('IT_SERVICES',          'IT services and consulting',               10, '{"aliases":["IT","Software Services","ITES"]}'),
  ('SOFTWARE_PRODUCT',     'Software products and SaaS',               20, '{"aliases":["Product","SaaS","AI product"]}'),
  ('BFSI',                 'Banking, financial services, insurance',   30, '{"aliases":["Banking","Finance","FinTech","Insurance"]}'),
  ('CONSULTING_ANALYTICS', 'Management consulting and analytics',      40, '{"aliases":["Analytics","Consulting","Data Science"]}'),
  ('ELECTRONICS_SEMICON',  'Electronics and semiconductors',           50, '{"aliases":["VLSI","Embedded","Electronics"]}'),
  ('TELECOM',              'Telecom and networking',                   60, '{"aliases":["Telecommunications","Networking"]}'),
  ('ENERGY_POWER',         'Energy and power',                         70, '{"aliases":["Power","Renewables","Solar"]}'),
  ('AUTOMOTIVE',           'Automotive and EV',                        80, '{"aliases":["Auto","EV","Automobile"]}'),
  ('CORE_MECHANICAL',      'Core mechanical, manufacturing and automation', 90, '{"aliases":["Manufacturing","Mechanical","Automation"]}'),
  ('CONSTRUCTION_INFRA',   'Construction and infrastructure',         100, '{"aliases":["Civil","Infrastructure","Real Estate"]}'),
  ('PHARMA_HEALTHCARE',    'Pharma, medtech and healthcare',          110, '{"aliases":["Pharma","Healthcare","MedTech"]}'),
  ('GOVERNMENT_PSU',       'Government and public sector undertakings',120, '{"aliases":["PSU","Public Sector","Government"]}'),
  ('OTHER',                'Other',                                   999, '{"aliases":["E-commerce","Retail"]}')
) AS v(code, label, ord, attr);

-- ---------------------------------------------------------------------
-- 4.3 People: faculty (6 per academic department + Dean + IQAC), cell staff
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_first(n int, name text, g text) ON COMMIT DROP;
INSERT INTO t_first SELECT row_number() OVER (), x.name, x.g FROM (VALUES
 ('Aarav','M'),('Ananya','F'),('Vikram','M'),('Priya','F'),('Rohan','M'),('Kavya','F'),('Arjun','M'),('Sneha','F'),
 ('Karthik','M'),('Divya','F'),('Rahul','M'),('Meera','F'),('Siddharth','M'),('Lakshmi','F'),('Nikhil','M'),('Pooja','F'),
 ('Aditya','M'),('Swathi','F'),('Harsha','M'),('Neha','F'),('Varun','M'),('Bhavana','F'),('Sai','M'),('Keerthi','F'),
 ('Manoj','M'),('Anjali','F'),('Suresh','M'),('Deepika','F'),('Ravi','M'),('Shruti','F'),('Kiran','M'),('Harini','F'),
 ('Pranav','M'),('Nandini','F'),('Abhishek','M'),('Revathi','F'),('Tarun','M'),('Sowmya','F'),('Gautam','M'),('Ishita','F'),
 ('Yash','M'),('Tanvi','F'),('Imran','M'),('Farah','F'),('Joseph','M'),('Sarah','F'),('Harpreet','M'),('Simran','F')
) AS x(name, g);
CREATE TEMP TABLE t_last(n int, name text) ON COMMIT DROP;
INSERT INTO t_last SELECT row_number() OVER (), x.name FROM (VALUES
 ('Reddy'),('Sharma'),('Iyer'),('Nair'),('Rao'),('Kulkarni'),('Menon'),('Patel'),('Gupta'),('Varma'),('Pillai'),('Joshi'),
 ('Deshmukh'),('Naidu'),('Chatterjee'),('Banerjee'),('Krishnan'),('Srinivasan'),('Bhat'),('Hegde'),('Mishra'),('Agarwal'),
 ('Khan'),('Fernandes'),('Thomas'),('Singh'),('Chowdary'),('Prasad'),('Mukherjee'),('Shetty')
) AS x(name);

-- person name generator: deterministic by key
CREATE FUNCTION pg_temp.fname(k text) RETURNS text LANGUAGE sql STABLE AS
$$ SELECT name FROM t_first WHERE n = 1 + floor(pg_temp.rnd('fn:' || k) * 48)::int $$;
CREATE FUNCTION pg_temp.fgender(k text) RETURNS text LANGUAGE sql STABLE AS
$$ SELECT g FROM t_first WHERE n = 1 + floor(pg_temp.rnd('fn:' || k) * 48)::int $$;
CREATE FUNCTION pg_temp.lname(k text) RETURNS text LANGUAGE sql STABLE AS
$$ SELECT name FROM t_last WHERE n = 1 + floor(pg_temp.rnd('ln:' || k) * 30)::int $$;

CREATE TEMP TABLE t_faculty ON COMMIT DROP AS
SELECT d.code AS dept, s.i,
       'fac:' || d.code || ':' || s.i AS k,
       CASE WHEN s.i = 1 THEN 'PROFESSOR' WHEN s.i IN (2,3) THEN 'ASSOCIATE_PROFESSOR' ELSE 'ASSISTANT_PROFESSOR' END AS designation
FROM (VALUES ('CSE'),('IT'),('ECE'),('EEE'),('MECH'),('CIVIL')) AS d(code)
CROSS JOIN generate_series(1, 6) AS s(i)
UNION ALL SELECT 'EEE', 7, 'fac:DEAN', 'PROFESSOR'      -- Dean (Academics & Industry Relations)
UNION ALL SELECT 'CSE', 7, 'fac:IQAC', 'PROFESSOR';     -- IQAC coordinator

INSERT INTO people.person (person_id, institution_id, full_name, given_name, family_name, gender, primary_email)
SELECT pg_temp.uid('person:' || f.k), pg_temp.uid('inst:DIET'),
       'Dr. ' || pg_temp.fname(f.k) || ' ' || pg_temp.lname(f.k), pg_temp.fname(f.k), pg_temp.lname(f.k), pg_temp.fgender(f.k),
       lower(pg_temp.fname(f.k) || '.' || pg_temp.lname(f.k) || '.' || f.dept || f.i) || '@diet.example'
FROM t_faculty f;

INSERT INTO people.faculty (faculty_id, person_id, employee_no, department_id, designation, cadre, employment_type,
                            highest_qualification, is_phd_holder, date_of_joining, is_research_supervisor, status)
SELECT pg_temp.uid(f.k), pg_temp.uid('person:' || f.k), 'DIET-' || f.dept || '-' || lpad(f.i::text, 2, '0'),
       pg_temp.uid('dept:' || f.dept), f.designation,
       CASE f.designation WHEN 'PROFESSOR' THEN 'PROFESSOR' WHEN 'ASSOCIATE_PROFESSOR' THEN 'ASSOCIATE' ELSE 'ASSISTANT' END,
       'REGULAR', CASE WHEN f.designation = 'ASSISTANT_PROFESSOR' AND f.i > 5 THEN 'M.Tech' ELSE 'Ph.D' END,
       NOT (f.designation = 'ASSISTANT_PROFESSOR' AND f.i > 5),
       ('2008-06-01'::date + (floor(pg_temp.rnd('doj:' || f.k) * 5000))::int),
       f.designation = 'PROFESSOR', 'ACTIVE'
FROM t_faculty f;

UPDATE core.department d SET hod_faculty_id = pg_temp.uid('fac:' || d.code || ':1')
WHERE d.code IN ('CSE','IT','ECE','EEE','MECH','CIVIL');

-- non-faculty cell staff
INSERT INTO people.person (person_id, institution_id, full_name, given_name, family_name, gender, primary_email)
VALUES
 (pg_temp.uid('person:staff:iiic_head'), pg_temp.uid('inst:DIET'), 'Arvind Nair',     'Arvind', 'Nair',     'M', 'head.iiic@diet.example'),
 (pg_temp.uid('person:staff:iiic_exec'), pg_temp.uid('inst:DIET'), 'Sneha Kulkarni',  'Sneha',  'Kulkarni', 'F', 'industry.cell@diet.example'),
 (pg_temp.uid('person:staff:tpo'),       pg_temp.uid('inst:DIET'), 'Rahul Verma',     'Rahul',  'Verma',    'M', 'tpo@diet.example');

-- ---------------------------------------------------------------------
-- 4.4 Identity: roles, users, scoped role assignments
-- ---------------------------------------------------------------------
INSERT INTO identity.role (role_id, code, name, description, is_system)
SELECT pg_temp.uid('role:' || r.code), r.code, r.name, r.descr, r.sys
FROM (VALUES
  ('STUDENT','Student','Student user',true),
  ('FACULTY','Faculty','Teaching faculty',true),
  ('HOD','Head of Department','Department scope',true),
  ('DEAN','Dean','Institution scope',true),
  ('IQAC','IQAC Coordinator','Quality and accreditation',true),
  ('PLACEMENT','Training and Placement Officer','Placement cell',true),
  ('INDUSTRY_RELATIONS','Industry Relations Cell','Partner register, MoUs, deliverables, industry activities (Agent 28 primary user)',false),
  ('ADMIN','Administrator','Platform administration',true),
  ('SYSTEM','System / agent service','Service accounts used by agents',true)
) AS r(code, name, descr, sys);

INSERT INTO identity.app_user (user_id, person_id, username, email, auth_provider, is_active, is_service_account, last_login_at)
SELECT pg_temp.uid('user:' || u.username), u.person_id, u.username, u.email, u.auth, true, u.svc, u.last_login::timestamptz
FROM (
  SELECT 'hod.' || lower(d.code) AS username, pg_temp.uid('person:fac:' || d.code || ':1') AS person_id,
         'hod.' || lower(d.code) || '@diet.example' AS email, 'SSO' AS auth, false AS svc, '2026-09-10 17:20+05:30' AS last_login
  FROM (VALUES ('CSE'),('IT'),('ECE'),('EEE'),('MECH'),('CIVIL')) AS d(code)
  UNION ALL SELECT 'dean.academics', pg_temp.uid('person:fac:DEAN'), 'dean@diet.example', 'SSO', false, '2026-09-11 09:05+05:30'
  UNION ALL SELECT 'iqac.coordinator', pg_temp.uid('person:fac:IQAC'), 'iqac@diet.example', 'SSO', false, '2026-09-09 11:40+05:30'
  UNION ALL SELECT 'iiic.head', pg_temp.uid('person:staff:iiic_head'), 'head.iiic@diet.example', 'SSO', false, '2026-09-11 10:12+05:30'
  UNION ALL SELECT 'iiic.exec', pg_temp.uid('person:staff:iiic_exec'), 'industry.cell@diet.example', 'SSO', false, '2026-09-11 10:30+05:30'
  UNION ALL SELECT 'tpo', pg_temp.uid('person:staff:tpo'), 'tpo@diet.example', 'SSO', false, '2026-09-10 15:02+05:30'
  UNION ALL SELECT 'svc.agent28', NULL, 'svc.agent28@diet.example', 'SERVICE', true, NULL
  UNION ALL SELECT 'admin', NULL, 'admin@diet.example', 'LOCAL', false, '2026-09-01 08:00+05:30'
) AS u;

INSERT INTO identity.user_role (user_role_id, user_id, role_id, scope_type, scope_id, valid_from)
SELECT pg_temp.uid('ur:' || x.username || ':' || x.role), pg_temp.uid('user:' || x.username), pg_temp.uid('role:' || x.role),
       x.scope_type, x.scope_id, '2024-06-01'
FROM (
  SELECT 'hod.' || lower(d.code) AS username, 'HOD' AS role, 'DEPARTMENT' AS scope_type, pg_temp.uid('dept:' || d.code) AS scope_id
  FROM (VALUES ('CSE'),('IT'),('ECE'),('EEE'),('MECH'),('CIVIL')) AS d(code)
  UNION ALL SELECT 'hod.' || lower(d.code), 'FACULTY', 'DEPARTMENT', pg_temp.uid('dept:' || d.code)
  FROM (VALUES ('CSE'),('IT'),('ECE'),('EEE'),('MECH'),('CIVIL')) AS d(code)
  UNION ALL SELECT 'dean.academics', 'DEAN', 'INSTITUTION', NULL
  UNION ALL SELECT 'iqac.coordinator', 'IQAC', 'INSTITUTION', NULL
  UNION ALL SELECT 'iiic.head', 'INDUSTRY_RELATIONS', 'INSTITUTION', NULL
  UNION ALL SELECT 'iiic.exec', 'INDUSTRY_RELATIONS', 'INSTITUTION', NULL
  UNION ALL SELECT 'tpo', 'PLACEMENT', 'INSTITUTION', NULL
  UNION ALL SELECT 'svc.agent28', 'SYSTEM', 'INSTITUTION', NULL
  UNION ALL SELECT 'admin', 'ADMIN', 'INSTITUTION', NULL
) AS x;

-- ---------------------------------------------------------------------
-- 4.5 Curriculum: regulations, programmes, batches, sections
-- ---------------------------------------------------------------------
INSERT INTO curriculum.regulation (regulation_id, institution_id, code, name, effective_from_admission_year, effective_to_admission_year, approved_on, approving_body, status)
VALUES (pg_temp.uid('reg:R20'), pg_temp.uid('inst:DIET'), 'R20', 'Regulation 2020', 2020, 2022, '2020-06-15', 'Academic Council', 'SUPERSEDED'),
       (pg_temp.uid('reg:R23'), pg_temp.uid('inst:DIET'), 'R23', 'Regulation 2023', 2023, NULL,  '2023-05-20', 'Academic Council', 'ACTIVE');
UPDATE curriculum.regulation SET superseded_by = pg_temp.uid('reg:R23') WHERE code = 'R20';

INSERT INTO curriculum.programme (programme_id, institution_id, department_id, code, name, level, degree, specialisation, duration_years, total_terms, sanctioned_intake)
SELECT pg_temp.uid('prog:' || p.dept), pg_temp.uid('inst:DIET'), pg_temp.uid('dept:' || p.dept), 'BTECH-' || p.dept, p.name, 'UG', 'B.Tech', NULL, 4, 8, p.intake
FROM (VALUES ('CSE','B.Tech Computer Science and Engineering',180), ('IT','B.Tech Information Technology',120),
             ('ECE','B.Tech Electronics and Communication Engineering',120), ('EEE','B.Tech Electrical and Electronics Engineering',60),
             ('MECH','B.Tech Mechanical Engineering',60), ('CIVIL','B.Tech Civil Engineering',60)) AS p(dept, name, intake);

INSERT INTO curriculum.batch (batch_id, programme_id, regulation_id, admission_year, label, expected_graduation_year, status)
SELECT pg_temp.uid('batch:' || p.dept || ':' || y.yr), pg_temp.uid('prog:' || p.dept),
       pg_temp.uid(CASE WHEN y.yr >= 2023 THEN 'reg:R23' ELSE 'reg:R20' END), y.yr,
       y.yr || '-' || right((y.yr + 4)::text, 2) || ' ' || p.dept, y.yr + 4,
       CASE WHEN y.yr + 4 <= 2026 THEN 'GRADUATED' ELSE 'ACTIVE' END
FROM (VALUES ('CSE'),('IT'),('ECE'),('EEE'),('MECH'),('CIVIL')) AS p(dept)
CROSS JOIN (VALUES (2021),(2022),(2023)) AS y(yr);

INSERT INTO curriculum.section (section_id, batch_id, code, year_of_study, strength, class_advisor_faculty_id, is_active)
SELECT pg_temp.uid('sec:' || p.dept || ':' || y.yr), pg_temp.uid('batch:' || p.dept || ':' || y.yr), 'A', 4, 35,
       pg_temp.uid('fac:' || p.dept || ':' || (4 + (y.yr - 2021))), y.yr = 2023
FROM (VALUES ('CSE'),('IT'),('ECE'),('EEE'),('MECH'),('CIVIL')) AS p(dept)
CROSS JOIN (VALUES (2021),(2022),(2023)) AS y(yr);

-- ---------------------------------------------------------------------
-- 4.6 Students: 35 per programme per batch (630). Batches 2021 and 2022 graduated.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_student ON COMMIT DROP AS
SELECT p.dept, y.yr, s.i, 'stu:' || p.dept || ':' || y.yr || ':' || s.i AS k
FROM (VALUES ('CSE'),('IT'),('ECE'),('EEE'),('MECH'),('CIVIL')) AS p(dept)
CROSS JOIN (VALUES (2021),(2022),(2023)) AS y(yr)
CROSS JOIN generate_series(1, 35) AS s(i);

INSERT INTO people.person (person_id, institution_id, full_name, given_name, family_name, gender, date_of_birth, primary_email)
SELECT pg_temp.uid('person:' || t.k), pg_temp.uid('inst:DIET'),
       pg_temp.fname(t.k) || ' ' || pg_temp.lname(t.k), pg_temp.fname(t.k), pg_temp.lname(t.k), pg_temp.fgender(t.k),
       make_date(t.yr - 18, 1 + floor(pg_temp.rnd('dobm:' || t.k) * 12)::int, 1 + floor(pg_temp.rnd('dobd:' || t.k) * 28)::int),
       lower(t.yr || t.dept || lpad(t.i::text, 3, '0')) || '@students.diet.example'
FROM t_student t;

INSERT INTO people.student (student_id, person_id, admission_no, roll_no, register_no, batch_id, admission_date, admission_category,
                            current_section_id, current_year_of_study, status, status_changed_on, graduation_date)
SELECT pg_temp.uid(t.k), pg_temp.uid('person:' || t.k),
       'ADM' || t.yr || t.dept || lpad(t.i::text, 3, '0'),
       right(t.yr::text, 2) || 'D1A' || CASE t.dept WHEN 'CSE' THEN '05' WHEN 'IT' THEN '12' WHEN 'ECE' THEN '04' WHEN 'EEE' THEN '02' WHEN 'MECH' THEN '03' ELSE '01' END || lpad(t.i::text, 2, '0'),
       NULL, pg_temp.uid('batch:' || t.dept || ':' || t.yr), make_date(t.yr, 8, 16),
       CASE WHEN pg_temp.rnd('cat:' || t.k) < 0.7 THEN 'CONVENER' ELSE 'MANAGEMENT' END,
       pg_temp.uid('sec:' || t.dept || ':' || t.yr), 4,
       CASE WHEN t.yr <= 2022 THEN 'GRADUATED' ELSE 'ACTIVE' END,
       CASE WHEN t.yr <= 2022 THEN make_date(t.yr + 4, 6, 15) END,
       CASE WHEN t.yr <= 2022 THEN make_date(t.yr + 4, 6, 15) END
FROM t_student t;

-- ---------------------------------------------------------------------
-- 4.7 Courses (Agent 2 content): 3 final-year industry-facing courses per department,
--     each with 3 units x 3 topics, in both R20 and R23 versions.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_topic (dept text, ccode text, ctitle text, unit_no int, unit_title text, seq int, topic text) ON COMMIT DROP;
INSERT INTO t_topic VALUES
 ('CSE','CS701','Cloud Computing',1,'Virtualisation and Containers',1,'Hypervisors and virtual machines'),
 ('CSE','CS701','Cloud Computing',1,'Virtualisation and Containers',2,'Docker containers'),
 ('CSE','CS701','Cloud Computing',1,'Virtualisation and Containers',3,'Kubernetes orchestration'),
 ('CSE','CS701','Cloud Computing',2,'Cloud Services and Architecture',1,'Serverless computing'),
 ('CSE','CS701','Cloud Computing',2,'Cloud Services and Architecture',2,'Microservices architecture'),
 ('CSE','CS701','Cloud Computing',2,'Cloud Services and Architecture',3,'Multi-cloud and hybrid cloud'),
 ('CSE','CS701','Cloud Computing',3,'Cloud Security and DevOps',1,'Identity and access management'),
 ('CSE','CS701','Cloud Computing',3,'Cloud Security and DevOps',2,'CI/CD pipelines'),
 ('CSE','CS701','Cloud Computing',3,'Cloud Security and DevOps',3,'Infrastructure as code'),
 ('CSE','CS702','Machine Learning',1,'Supervised Learning',1,'Regression models'),
 ('CSE','CS702','Machine Learning',1,'Supervised Learning',2,'Classification and decision trees'),
 ('CSE','CS702','Machine Learning',1,'Supervised Learning',3,'Model evaluation metrics'),
 ('CSE','CS702','Machine Learning',2,'Deep Learning',1,'Neural network fundamentals'),
 ('CSE','CS702','Machine Learning',2,'Deep Learning',2,'Convolutional neural networks'),
 ('CSE','CS702','Machine Learning',2,'Deep Learning',3,'Transformers and large language models'),
 ('CSE','CS702','Machine Learning',3,'MLOps',1,'Model deployment and serving'),
 ('CSE','CS702','Machine Learning',3,'MLOps',2,'Feature engineering pipelines'),
 ('CSE','CS702','Machine Learning',3,'MLOps',3,'Model monitoring and drift'),
 ('CSE','CS703','Big Data Analytics',1,'Distributed Storage',1,'Hadoop distributed file system'),
 ('CSE','CS703','Big Data Analytics',1,'Distributed Storage',2,'Data lakes and lakehouses'),
 ('CSE','CS703','Big Data Analytics',1,'Distributed Storage',3,'NoSQL databases'),
 ('CSE','CS703','Big Data Analytics',2,'Distributed Processing',1,'Apache Spark'),
 ('CSE','CS703','Big Data Analytics',2,'Distributed Processing',2,'Stream processing with Kafka'),
 ('CSE','CS703','Big Data Analytics',2,'Distributed Processing',3,'Real-time analytics dashboards'),
 ('CSE','CS703','Big Data Analytics',3,'Data Governance',1,'Data quality management'),
 ('CSE','CS703','Big Data Analytics',3,'Data Governance',2,'Data privacy and DPDP compliance'),
 ('CSE','CS703','Big Data Analytics',3,'Data Governance',3,'Business intelligence reporting'),
 ('IT','IT701','Cyber Security',1,'Network Security',1,'Firewalls and intrusion detection'),
 ('IT','IT701','Cyber Security',1,'Network Security',2,'VPN and secure protocols'),
 ('IT','IT701','Cyber Security',1,'Network Security',3,'Zero trust networking'),
 ('IT','IT701','Cyber Security',2,'Application Security',1,'OWASP top ten vulnerabilities'),
 ('IT','IT701','Cyber Security',2,'Application Security',2,'Secure software development'),
 ('IT','IT701','Cyber Security',2,'Application Security',3,'Penetration testing methods'),
 ('IT','IT701','Cyber Security',3,'Security Operations',1,'Security operations centre workflows'),
 ('IT','IT701','Cyber Security',3,'Security Operations',2,'Incident response'),
 ('IT','IT701','Cyber Security',3,'Security Operations',3,'Digital forensics'),
 ('IT','IT702','Full Stack Development',1,'Front End Engineering',1,'React component design'),
 ('IT','IT702','Full Stack Development',1,'Front End Engineering',2,'Responsive web design'),
 ('IT','IT702','Full Stack Development',1,'Front End Engineering',3,'Web accessibility'),
 ('IT','IT702','Full Stack Development',2,'Back End Engineering',1,'REST API design'),
 ('IT','IT702','Full Stack Development',2,'Back End Engineering',2,'Authentication and authorisation'),
 ('IT','IT702','Full Stack Development',2,'Back End Engineering',3,'Database design for web applications'),
 ('IT','IT702','Full Stack Development',3,'Deployment and Operations',1,'Containerised deployment'),
 ('IT','IT702','Full Stack Development',3,'Deployment and Operations',2,'Performance optimisation'),
 ('IT','IT702','Full Stack Development',3,'Deployment and Operations',3,'Application monitoring'),
 ('IT','IT703','Financial Technology Systems',1,'Digital Payments',1,'UPI and payment gateways'),
 ('IT','IT703','Financial Technology Systems',1,'Digital Payments',2,'Card payment networks'),
 ('IT','IT703','Financial Technology Systems',1,'Digital Payments',3,'Payment fraud detection'),
 ('IT','IT703','Financial Technology Systems',2,'Banking Technology',1,'Core banking systems'),
 ('IT','IT703','Financial Technology Systems',2,'Banking Technology',2,'Credit risk analytics'),
 ('IT','IT703','Financial Technology Systems',2,'Banking Technology',3,'Regulatory technology'),
 ('IT','IT703','Financial Technology Systems',3,'Emerging FinTech',1,'Blockchain and distributed ledgers'),
 ('IT','IT703','Financial Technology Systems',3,'Emerging FinTech',2,'Algorithmic trading'),
 ('IT','IT703','Financial Technology Systems',3,'Emerging FinTech',3,'Insurance technology'),
 ('ECE','EC701','VLSI Design',1,'Digital IC Design',1,'CMOS logic design'),
 ('ECE','EC701','VLSI Design',1,'Digital IC Design',2,'RTL design with Verilog'),
 ('ECE','EC701','VLSI Design',1,'Digital IC Design',3,'Logic synthesis'),
 ('ECE','EC701','VLSI Design',2,'Physical Design',1,'Floorplanning and placement'),
 ('ECE','EC701','VLSI Design',2,'Physical Design',2,'Clock tree synthesis'),
 ('ECE','EC701','VLSI Design',2,'Physical Design',3,'Static timing analysis'),
 ('ECE','EC701','VLSI Design',3,'Verification and Test',1,'Functional verification with UVM'),
 ('ECE','EC701','VLSI Design',3,'Verification and Test',2,'Design for testability'),
 ('ECE','EC701','VLSI Design',3,'Verification and Test',3,'FPGA prototyping'),
 ('ECE','EC702','Embedded Systems',1,'Microcontrollers',1,'ARM Cortex-M architecture'),
 ('ECE','EC702','Embedded Systems',1,'Microcontrollers',2,'Peripheral interfacing'),
 ('ECE','EC702','Embedded Systems',1,'Microcontrollers',3,'Real-time operating systems'),
 ('ECE','EC702','Embedded Systems',2,'IoT Systems',1,'Wireless sensor networks'),
 ('ECE','EC702','Embedded Systems',2,'IoT Systems',2,'IoT communication protocols'),
 ('ECE','EC702','Embedded Systems',2,'IoT Systems',3,'Edge computing'),
 ('ECE','EC702','Embedded Systems',3,'Automotive and Medical Electronics',1,'CAN and LIN vehicle buses'),
 ('ECE','EC702','Embedded Systems',3,'Automotive and Medical Electronics',2,'Functional safety ISO 26262'),
 ('ECE','EC702','Embedded Systems',3,'Automotive and Medical Electronics',3,'Medical device electronics'),
 ('ECE','EC703','Wireless and 5G Communication',1,'Wireless Fundamentals',1,'Radio propagation'),
 ('ECE','EC703','Wireless and 5G Communication',1,'Wireless Fundamentals',2,'OFDM modulation'),
 ('ECE','EC703','Wireless and 5G Communication',1,'Wireless Fundamentals',3,'MIMO systems'),
 ('ECE','EC703','Wireless and 5G Communication',2,'5G Networks',1,'5G NR architecture'),
 ('ECE','EC703','Wireless and 5G Communication',2,'5G Networks',2,'Network slicing'),
 ('ECE','EC703','Wireless and 5G Communication',2,'5G Networks',3,'Open RAN'),
 ('ECE','EC703','Wireless and 5G Communication',3,'Vision and Sensing',1,'Machine vision systems'),
 ('ECE','EC703','Wireless and 5G Communication',3,'Vision and Sensing',2,'Satellite communication'),
 ('ECE','EC703','Wireless and 5G Communication',3,'Vision and Sensing',3,'Antenna design'),
 ('EEE','EE701','Power Electronics and Drives',1,'Converters',1,'DC-DC converters'),
 ('EEE','EE701','Power Electronics and Drives',1,'Converters',2,'Inverters and PWM techniques'),
 ('EEE','EE701','Power Electronics and Drives',1,'Converters',3,'Power quality'),
 ('EEE','EE701','Power Electronics and Drives',2,'Electric Drives',1,'Induction motor drives'),
 ('EEE','EE701','Power Electronics and Drives',2,'Electric Drives',2,'BLDC motor control'),
 ('EEE','EE701','Power Electronics and Drives',2,'Electric Drives',3,'Vector control'),
 ('EEE','EE701','Power Electronics and Drives',3,'EV Power Systems',1,'Battery management systems'),
 ('EEE','EE701','Power Electronics and Drives',3,'EV Power Systems',2,'EV charging infrastructure'),
 ('EEE','EE701','Power Electronics and Drives',3,'EV Power Systems',3,'Battery testing and validation'),
 ('EEE','EE702','Renewable Energy Systems',1,'Solar Energy',1,'Solar PV systems'),
 ('EEE','EE702','Renewable Energy Systems',1,'Solar Energy',2,'Maximum power point tracking'),
 ('EEE','EE702','Renewable Energy Systems',1,'Solar Energy',3,'Solar plant design'),
 ('EEE','EE702','Renewable Energy Systems',2,'Wind, Hydro and Storage',1,'Wind energy conversion'),
 ('EEE','EE702','Renewable Energy Systems',2,'Wind, Hydro and Storage',2,'Small hydro power systems'),
 ('EEE','EE702','Renewable Energy Systems',2,'Wind, Hydro and Storage',3,'Energy storage systems'),
 ('EEE','EE702','Renewable Energy Systems',3,'Grid Integration',1,'Power transmission and grid codes'),
 ('EEE','EE702','Renewable Energy Systems',3,'Grid Integration',2,'Smart grid technologies'),
 ('EEE','EE702','Renewable Energy Systems',3,'Grid Integration',3,'Energy management systems'),
 ('EEE','EE703','Industrial Automation',1,'Control Systems',1,'PLC programming'),
 ('EEE','EE703','Industrial Automation',1,'Control Systems',2,'SCADA systems'),
 ('EEE','EE703','Industrial Automation',1,'Control Systems',3,'Distributed control systems'),
 ('EEE','EE703','Industrial Automation',2,'Industrial Networks',1,'Industrial IoT'),
 ('EEE','EE703','Industrial Automation',2,'Industrial Networks',2,'OPC UA'),
 ('EEE','EE703','Industrial Automation',2,'Industrial Networks',3,'Modbus and Profibus'),
 ('EEE','EE703','Industrial Automation',3,'Industry 4.0',1,'Digital twins'),
 ('EEE','EE703','Industrial Automation',3,'Industry 4.0',2,'Predictive maintenance'),
 ('EEE','EE703','Industrial Automation',3,'Industry 4.0',3,'Robotic process integration'),
 ('MECH','ME701','Automotive Engineering',1,'Powertrain',1,'IC engine systems'),
 ('MECH','ME701','Automotive Engineering',1,'Powertrain',2,'Electric vehicle powertrain'),
 ('MECH','ME701','Automotive Engineering',1,'Powertrain',3,'Transmission systems'),
 ('MECH','ME701','Automotive Engineering',2,'Vehicle Dynamics',1,'Suspension and steering'),
 ('MECH','ME701','Automotive Engineering',2,'Vehicle Dynamics',2,'Braking systems'),
 ('MECH','ME701','Automotive Engineering',2,'Vehicle Dynamics',3,'Vehicle safety'),
 ('MECH','ME701','Automotive Engineering',3,'Automotive Manufacturing',1,'Automotive assembly lines'),
 ('MECH','ME701','Automotive Engineering',3,'Automotive Manufacturing',2,'Lightweight materials'),
 ('MECH','ME701','Automotive Engineering',3,'Automotive Manufacturing',3,'Aerospace components manufacturing'),
 ('MECH','ME702','Additive Manufacturing',1,'Processes',1,'Fused deposition modelling'),
 ('MECH','ME702','Additive Manufacturing',1,'Processes',2,'Selective laser sintering'),
 ('MECH','ME702','Additive Manufacturing',1,'Processes',3,'Metal additive manufacturing'),
 ('MECH','ME702','Additive Manufacturing',2,'Design',1,'Design for additive manufacturing'),
 ('MECH','ME702','Additive Manufacturing',2,'Design',2,'Topology optimisation'),
 ('MECH','ME702','Additive Manufacturing',2,'Design',3,'Generative design'),
 ('MECH','ME702','Additive Manufacturing',3,'Applications',1,'Rapid prototyping'),
 ('MECH','ME702','Additive Manufacturing',3,'Applications',2,'Tooling and fixtures'),
 ('MECH','ME702','Additive Manufacturing',3,'Applications',3,'Reverse engineering with 3D scanning'),
 ('MECH','ME703','Industrial Robotics',1,'Kinematics and Programming',1,'Robot kinematics'),
 ('MECH','ME703','Industrial Robotics',1,'Kinematics and Programming',2,'Trajectory planning'),
 ('MECH','ME703','Industrial Robotics',1,'Kinematics and Programming',3,'Robot programming'),
 ('MECH','ME703','Industrial Robotics',2,'Perception',1,'Machine vision for robots'),
 ('MECH','ME703','Industrial Robotics',2,'Perception',2,'Force sensing'),
 ('MECH','ME703','Industrial Robotics',2,'Perception',3,'Collaborative robots'),
 ('MECH','ME703','Industrial Robotics',3,'Applications',1,'Welding robots'),
 ('MECH','ME703','Industrial Robotics',3,'Applications',2,'Material handling automation'),
 ('MECH','ME703','Industrial Robotics',3,'Applications',3,'Warehouse robotics'),
 ('CIVIL','CE701','Construction Project Management',1,'Planning',1,'Project scheduling with CPM and PERT'),
 ('CIVIL','CE701','Construction Project Management',1,'Planning',2,'Cost estimation'),
 ('CIVIL','CE701','Construction Project Management',1,'Planning',3,'Contract management'),
 ('CIVIL','CE701','Construction Project Management',2,'Building Information Modelling',1,'Building information modelling'),
 ('CIVIL','CE701','Construction Project Management',2,'Building Information Modelling',2,'4D and 5D BIM'),
 ('CIVIL','CE701','Construction Project Management',2,'Building Information Modelling',3,'Clash detection'),
 ('CIVIL','CE701','Construction Project Management',3,'Execution',1,'Construction safety'),
 ('CIVIL','CE701','Construction Project Management',3,'Execution',2,'Quality control on site'),
 ('CIVIL','CE701','Construction Project Management',3,'Execution',3,'Lean construction'),
 ('CIVIL','CE702','Advanced Structural Design',1,'Analysis',1,'Finite element analysis'),
 ('CIVIL','CE702','Advanced Structural Design',1,'Analysis',2,'Seismic design'),
 ('CIVIL','CE702','Advanced Structural Design',1,'Analysis',3,'Wind load analysis'),
 ('CIVIL','CE702','Advanced Structural Design',2,'Design',1,'Prestressed concrete'),
 ('CIVIL','CE702','Advanced Structural Design',2,'Design',2,'Steel structures'),
 ('CIVIL','CE702','Advanced Structural Design',2,'Design',3,'Sustainable construction materials'),
 ('CIVIL','CE702','Advanced Structural Design',3,'Practice',1,'Structural analysis software'),
 ('CIVIL','CE702','Advanced Structural Design',3,'Practice',2,'Design codes and standards'),
 ('CIVIL','CE702','Advanced Structural Design',3,'Practice',3,'Structural health monitoring'),
 ('CIVIL','CE703','Transportation and Smart Infrastructure',1,'Highways',1,'Pavement design'),
 ('CIVIL','CE703','Transportation and Smart Infrastructure',1,'Highways',2,'Traffic engineering'),
 ('CIVIL','CE703','Transportation and Smart Infrastructure',1,'Highways',3,'Metro rail systems'),
 ('CIVIL','CE703','Transportation and Smart Infrastructure',2,'Smart Cities',1,'Intelligent transportation systems'),
 ('CIVIL','CE703','Transportation and Smart Infrastructure',2,'Smart Cities',2,'Urban mobility planning'),
 ('CIVIL','CE703','Transportation and Smart Infrastructure',2,'Smart Cities',3,'GIS for infrastructure'),
 ('CIVIL','CE703','Transportation and Smart Infrastructure',3,'Sustainability',1,'Green buildings'),
 ('CIVIL','CE703','Transportation and Smart Infrastructure',3,'Sustainability',2,'Water resource management'),
 ('CIVIL','CE703','Transportation and Smart Infrastructure',3,'Sustainability',3,'Environmental impact assessment');

INSERT INTO curriculum.course (course_id, institution_id, owning_department_id, title, short_title)
SELECT DISTINCT pg_temp.uid('course:' || ccode), pg_temp.uid('inst:DIET'), pg_temp.uid('dept:' || dept), ctitle, ccode
FROM t_topic;

INSERT INTO curriculum.course_version (course_version_id, course_id, regulation_id, programme_id, course_code, term_no, year_of_study,
       course_category, course_type, is_elective, elective_group, credits, lecture_hours, tutorial_hours, practical_hours,
       internal_max_marks, external_max_marks, status)
SELECT pg_temp.uid('cv:' || r.code || ':' || c.ccode), pg_temp.uid('course:' || c.ccode), pg_temp.uid('reg:' || r.code),
       pg_temp.uid('prog:' || c.dept), CASE r.code WHEN 'R23' THEN c.ccode ELSE replace(c.ccode, '7', '8') END, 7, 4,
       'PEC', 'THEORY', true, c.dept || '-PE-IV', 3, 3, 0, 0, 30, 70,
       CASE r.code WHEN 'R23' THEN 'ACTIVE' ELSE 'SUPERSEDED' END
FROM (SELECT DISTINCT dept, ccode FROM t_topic) c
CROSS JOIN (VALUES ('R20'),('R23')) AS r(code);

INSERT INTO curriculum.course_unit (course_unit_id, course_version_id, unit_no, title, notional_hours)
SELECT DISTINCT pg_temp.uid('unit:' || r.code || ':' || t.ccode || ':' || t.unit_no), pg_temp.uid('cv:' || r.code || ':' || t.ccode),
       t.unit_no, t.unit_title, 12
FROM t_topic t CROSS JOIN (VALUES ('R20'),('R23')) AS r(code);

INSERT INTO curriculum.course_topic (course_topic_id, course_unit_id, seq_no, title, notional_hours)
SELECT pg_temp.uid('topic:' || r.code || ':' || t.ccode || ':' || t.unit_no || ':' || t.seq),
       pg_temp.uid('unit:' || r.code || ':' || t.ccode || ':' || t.unit_no), t.seq, t.topic, 4
FROM t_topic t CROSS JOIN (VALUES ('R20'),('R23')) AS r(code);

INSERT INTO curriculum.course_outcome (course_outcome_id, course_version_id, co_no, statement, bloom_level, target_level)
SELECT DISTINCT pg_temp.uid('co:' || r.code || ':' || t.ccode || ':' || t.unit_no), pg_temp.uid('cv:' || r.code || ':' || t.ccode),
       t.unit_no, 'Apply the concepts of ' || lower(t.unit_title) || ' to industry-scale problems', 3, 2.00
FROM t_topic t CROSS JOIN (VALUES ('R20'),('R23')) AS r(code);

-- Offerings: odd term of each academic year for the final-year batch of that year
INSERT INTO academics.course_offering (course_offering_id, course_version_id, term_id, section_id, department_id, enrolled_count, delivery_mode, status)
SELECT pg_temp.uid('off:' || o.ay || ':' || c.ccode),
       pg_temp.uid('cv:' || o.reg || ':' || c.ccode), pg_temp.uid('term:ODD ' || o.ay),
       pg_temp.uid('sec:' || c.dept || ':' || o.batch), pg_temp.uid('dept:' || c.dept), 35, 'OFFLINE', o.status
FROM (SELECT DISTINCT dept, ccode FROM t_topic) c
CROSS JOIN (VALUES ('2024-25','R20',2021,'COMPLETED'), ('2025-26','R20',2022,'COMPLETED'), ('2026-27','R23',2023,'ACTIVE')) AS o(ay, reg, batch, status);

-- Lesson plans for the current term: 9 topics + 1 GUEST slot + revision; weekly from 6 Jul 2026
INSERT INTO academics.lesson_plan (lesson_plan_id, course_offering_id, prepared_by_faculty_id, total_planned_sessions, buffer_sessions, status, approved_at)
SELECT pg_temp.uid('lp:2026-27:' || c.ccode), pg_temp.uid('off:2026-27:' || c.ccode),
       pg_temp.uid('fac:' || c.dept || ':' || (2 + right(c.ccode, 1)::int)), 11, 1, 'APPROVED', '2026-07-01 12:00+05:30'
FROM (SELECT DISTINCT dept, ccode FROM t_topic) c;

INSERT INTO academics.lesson_plan_session (lesson_plan_session_id, lesson_plan_id, seq_no, planned_date, course_topic_id, course_unit_id, course_outcome_id, teaching_method, resource_ref)
SELECT pg_temp.uid('lps:2026-27:' || t.ccode || ':' || s.seq),
       pg_temp.uid('lp:2026-27:' || t.ccode), s.seq, DATE '2026-07-06' + (s.seq::int - 1) * 7,
       pg_temp.uid('topic:R23:' || t.ccode || ':' || t.unit_no || ':' || t.seq),
       pg_temp.uid('unit:R23:' || t.ccode || ':' || t.unit_no),
       pg_temp.uid('co:R23:' || t.ccode || ':' || t.unit_no),
       CASE WHEN s.is_guest THEN 'GUEST' WHEN t.seq = 3 THEN 'CASE_STUDY' ELSE 'LECTURE' END,
       CASE WHEN s.is_guest THEN 'Industry expert session (to be matched by Agent 28)' END
FROM (
  SELECT t.*, row_number() OVER (PARTITION BY t.ccode ORDER BY t.unit_no, t.seq) AS rn FROM t_topic t
) t
CROSS JOIN LATERAL (
  -- the 7th topic of every course (week 12, 21 Sep 2026, after mid-terms) is reserved as a GUEST slot
  SELECT CASE WHEN t.rn <= 6 THEN t.rn WHEN t.rn = 7 THEN 12 ELSE t.rn END AS seq,
         (t.rn = 7) AS is_guest
) s;

INSERT INTO academics.lesson_plan_session (lesson_plan_session_id, lesson_plan_id, seq_no, planned_date, teaching_method)
SELECT pg_temp.uid('lps:2026-27:' || c.ccode || ':' || x.seq), pg_temp.uid('lp:2026-27:' || c.ccode), x.seq,
       DATE '2026-07-06' + (x.seq - 1) * 7, x.method
FROM (SELECT DISTINCT ccode FROM t_topic) c
CROSS JOIN (VALUES (7,'REVISION'), (10,'BUFFER'), (11,'BUFFER')) AS x(seq, method);
-- =====================================================================
-- PART 5 — PARTNERS, COMPANIES, CONTACTS, ALUMNI, MoUs, DOCUMENTS, DELIVERABLES
-- =====================================================================

-- ---------------------------------------------------------------------
-- 5.1 Partner master (drives every generated activity)
--   intensity = conducted activities per year; act_start/act_end bound the
--   activity history (act_end controls recency and therefore dormancy);
--   quality = mean student rating; mix = weighted activity-type mix.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_partner (
  key text PRIMARY KEY, name text, sector text, dept text, dept2 text, status text, domain text,
  intensity numeric, act_start date, act_end date, quality numeric, mix text, since date
) ON COMMIT DROP;
INSERT INTO t_partner VALUES
 ('NIMBUS',      'Nimbus CloudWorks Pvt Ltd',          'IT_SERVICES',          'CSE',  'IT',   'ACTIVE',    'nimbuscloudworks', 10, '2024-06-17','2026-09-08', 4.4, 'GUEST_LECTURE:4,EXPERT_TALK:2,INDUSTRY_VISIT:2,INTERNSHIP_DRIVE:1,LAB_SUPPORT:1', '2021-07-10'),
 ('KODEVISTA',   'KodeVista Software Labs',            'SOFTWARE_PRODUCT',     'IT',   'CSE',  'ACTIVE',    'kodevista',         7, '2024-06-20','2026-08-28', 4.2, 'GUEST_LECTURE:3,EXPERT_TALK:2,INDUSTRY_VISIT:1,INTERNSHIP_DRIVE:1,FACULTY_EXCHANGE:1', '2020-12-01'),
 ('DATASUTRA',   'DataSutra Analytics LLP',            'CONSULTING_ANALYTICS', 'CSE',  'IT',   'ACTIVE',    'datasutra',         5, '2024-06-24','2026-07-30', 4.0, 'GUEST_LECTURE:3,EXPERT_TALK:2,CONSULTANCY:1,SPONSORED_PROJECT:1', '2023-11-01'),
 ('SECUREGRID',  'SecureGrid Cyber Defence',           'IT_SERVICES',          'IT',   'CSE',  'ACTIVE',    'securegrid',        5, '2024-06-26','2026-08-20', 3.9, 'GUEST_LECTURE:2,EXPERT_TALK:3,INDUSTRY_VISIT:1,INTERNSHIP_DRIVE:1', '2023-10-05'),
 ('PAYSETU',     'PaySetu Payments Pvt Ltd',           'BFSI',                 'IT',   'CSE',  'ACTIVE',    'paysetu',           4, '2025-04-10','2026-08-25', 4.1, 'GUEST_LECTURE:2,EXPERT_TALK:2,SPONSORED_PROJECT:1,INTERNSHIP_DRIVE:1', '2025-03-10'),
 ('SILICONDELTA','Silicon Delta Semiconductors',       'ELECTRONICS_SEMICON',  'ECE',  'EEE',  'ACTIVE',    'silicondelta',      7, '2024-06-18','2026-09-04', 4.3, 'GUEST_LECTURE:3,LAB_SUPPORT:2,FACULTY_EXCHANGE:1,INDUSTRY_VISIT:1,SPONSORED_PROJECT:1', '2022-06-01'),
 ('VOLTEDGE',    'VoltEdge Embedded Systems',          'ELECTRONICS_SEMICON',  'ECE',  'EEE',  'ACTIVE',    'voltedge',          2, '2024-09-20','2026-02-10', 3.1, 'GUEST_LECTURE:2,INDUSTRY_VISIT:1', '2021-08-01'),
 ('TARANG',      'Tarang Telecom Networks',            'TELECOM',              'ECE',  'CSE',  'ACTIVE',    'tarangtelecom',     3, '2024-06-25','2025-12-18', 3.6, 'GUEST_LECTURE:2,INDUSTRY_VISIT:1,EXPERT_TALK:1', '2023-12-01'),
 ('SURYAGRID',   'Suryagrid Renewables',               'ENERGY_POWER',         'EEE',  'CIVIL','ACTIVE',    'suryagrid',         4, '2024-06-27','2026-08-12', 4.0, 'INDUSTRY_VISIT:2,GUEST_LECTURE:2,INTERNSHIP_DRIVE:1', '2020-03-01'),
 ('DYNAMOTIVE',  'Dynamotive EV Drives',               'AUTOMOTIVE',           'EEE',  'MECH', 'ACTIVE',    'dynamotive',        6, '2024-11-20','2026-09-02', 4.3, 'GUEST_LECTURE:2,INDUSTRY_VISIT:1,LAB_SUPPORT:1,SPONSORED_PROJECT:1,INTERNSHIP_DRIVE:1', '2024-11-05'),
 ('AUTOMAXIS',   'Automaxis Industrial Controls',      'CORE_MECHANICAL',      'EEE',  'MECH', 'ACTIVE',    'automaxis',         3, '2024-06-28','2026-02-26', 3.7, 'GUEST_LECTURE:2,LAB_SUPPORT:1,INDUSTRY_VISIT:1', '2023-09-20'),
 ('KAVERIYAN',   'Kaveriyan Motors',                   'AUTOMOTIVE',           'MECH', 'EEE',  'ACTIVE',    'kaveriyanmotors',   7, '2024-06-19','2026-09-09', 4.2, 'INDUSTRY_VISIT:3,GUEST_LECTURE:2,INTERNSHIP_DRIVE:1,FACULTY_EXCHANGE:1', '2021-12-01'),
 ('FORGEPRINT',  'ForgePrint Additive Technologies',   'CORE_MECHANICAL',      'MECH', 'CIVIL','ACTIVE',    'forgeprint',        3, '2024-07-02','2026-04-08', 3.8, 'GUEST_LECTURE:2,LAB_SUPPORT:1,CONSULTANCY:1', '2023-07-15'),
 ('ROBONEST',    'RoboNest Automation',                'CORE_MECHANICAL',      'MECH', 'EEE',  'ACTIVE',    'robonest',          4, '2025-02-15','2026-08-18', 4.0, 'GUEST_LECTURE:2,INDUSTRY_VISIT:1,EXPERT_TALK:1', '2025-01-10'),
 ('SHILPAKAR',   'Shilpakar Infra Projects',           'CONSTRUCTION_INFRA',   'CIVIL','MECH', 'ACTIVE',    'shilpakarinfra',    4, '2024-07-05','2026-08-22', 3.9, 'INDUSTRY_VISIT:3,GUEST_LECTURE:1,INTERNSHIP_DRIVE:1', '2021-06-10'),
 ('BIMCRAFT',    'BIMCraft Design Studio',             'CONSTRUCTION_INFRA',   'CIVIL','MECH', 'ACTIVE',    'bimcraft',          2, '2024-08-20','2026-04-02', 3.4, 'GUEST_LECTURE:2,EXPERT_TALK:1', '2024-08-10'),
 ('PATHIK',      'Pathik Urban Mobility Corporation',  'GOVERNMENT_PSU',       'CIVIL','EEE',  'ACTIVE',    'pathikmobility',    2, '2024-07-08','2025-02-10', 3.5, 'INDUSTRY_VISIT:1,EXPERT_TALK:1', '2022-10-01'),
 ('AROGYA',      'Arogya MedTech Devices',             'PHARMA_HEALTHCARE',    'ECE',  'EEE',  'ACTIVE',    'arogyamedtech',     3, '2026-03-05','2026-08-26', 4.1, 'GUEST_LECTURE:1,INDUSTRY_VISIT:1,SPONSORED_PROJECT:1', '2026-02-01'),
 ('QUANTLOOM',   'QuantLoom AI Labs',                  'SOFTWARE_PRODUCT',     'CSE',  'IT',   'ACTIVE',    'quantloom',         8, '2025-07-21','2026-09-07', 4.6, 'GUEST_LECTURE:3,EXPERT_TALK:3,SPONSORED_PROJECT:1,INTERNSHIP_DRIVE:1', '2025-07-01'),
 ('NETRA',       'Netra Vision Systems',               'ELECTRONICS_SEMICON',  'ECE',  'CSE',  'ACTIVE',    'netravision',       4, '2024-06-21','2026-07-24', 3.9, 'GUEST_LECTURE:2,LAB_SUPPORT:1,INDUSTRY_VISIT:1', '2024-03-10'),
 ('SAMYUTA',     'Samyuta Power Transmission Ltd',     'GOVERNMENT_PSU',       'EEE',  'CIVIL','ACTIVE',    'samyutapower',      3, '2024-07-01','2026-08-05', 3.8, 'INDUSTRY_VISIT:2,FACULTY_EXCHANGE:1', '2023-05-01'),
 ('ZENITHSOFT',  'Zenith Softech Services',            'IT_SERVICES',          'CSE',  'IT',   'CONCLUDED', 'zenithsoftech',     2, '2024-07-15','2025-06-20', 3.3, 'GUEST_LECTURE:1,INTERNSHIP_DRIVE:1', '2021-09-01'),
 ('GREENBRICK',  'Greenbrick Materials',               'CONSTRUCTION_INFRA',   'CIVIL','MECH', 'CONCLUDED', 'greenbrick',        0, NULL, NULL, NULL, NULL, '2022-01-20'),
 ('PRAVAH',      'Pravah Hydro Systems',               'ENERGY_POWER',         'EEE',  'CIVIL','DORMANT',   'pravahhydro',       1, '2024-07-10','2024-10-15', 3.6, 'INDUSTRY_VISIT:1', '2022-04-01'),
 ('AEROFAB',     'AeroFab Components',                 'CORE_MECHANICAL',      'MECH', 'EEE',  'DORMANT',   'aerofab',           1, '2024-07-12','2024-12-10', 3.7, 'GUEST_LECTURE:1,INDUSTRY_VISIT:1', '2022-11-01'),
 ('EKATVA',      'Ekatva Bank Digital',                'BFSI',                 'IT',   'CSE',  'PROSPECT',  'ekatvabank',        0, NULL, NULL, NULL, NULL, '2026-08-25'),
 ('LEDGERLEAF',  'LedgerLeaf Fintech',                 'BFSI',                 'IT',   'CSE',  'PROSPECT',  'ledgerleaf',        0, NULL, NULL, 4.3, NULL, '2026-06-15'),
 ('CLEARVIEW',   'Clearview Consulting Group',         'CONSULTING_ANALYTICS', 'CSE',  'IT',   'PROSPECT',  'clearviewconsulting',0,NULL, NULL, NULL, NULL, '2026-05-20'),
 ('HELIX',       'Helix Pharma Research',              'PHARMA_HEALTHCARE',    'ECE',  'CSE',  'PROSPECT',  'helixpharma',       0, NULL, NULL, NULL, NULL, '2026-04-02'),
 ('ORBITAL',     'Orbital SatCom',                     'TELECOM',              'ECE',  'EEE',  'PROSPECT',  'orbitalsatcom',     0, NULL, NULL, NULL, NULL, '2026-08-01');

INSERT INTO engagement.industry_partner (industry_partner_id, institution_id, name, sector, website, relationship_owner_faculty_id, status, created_at)
SELECT pg_temp.uid('partner:' || p.key), pg_temp.uid('inst:DIET'), p.name, p.sector, 'https://www.' || p.domain || '.example',
       pg_temp.uid('fac:' || p.dept || ':' || (2 + floor(pg_temp.rnd('owner:' || p.key) * 3))::int), p.status, p.since::timestamptz
FROM t_partner p;

-- ---------------------------------------------------------------------
-- 5.2 Placement companies (placement domain). 24 linked to partners, 18 not.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_company (key text PRIMARY KEY, name text, sector text, tier text, partner_key text, w numeric, ctc numeric) ON COMMIT DROP;
INSERT INTO t_company
SELECT p.key, p.name, p.sector, x.tier, p.key, x.w, x.ctc
FROM t_partner p JOIN (VALUES
 ('NIMBUS','DREAM',8,900000),('KODEVISTA','DREAM',5,1100000),('DATASUTRA','DREAM',3,1000000),('SECUREGRID','CORE',3,750000),
 ('PAYSETU','DREAM',3,1050000),('SILICONDELTA','SUPER_DREAM',3,1600000),('VOLTEDGE','CORE',2,650000),('TARANG','CORE',1,600000),
 ('SURYAGRID','CORE',2,600000),('DYNAMOTIVE','CORE',3,750000),('AUTOMAXIS','CORE',2,550000),('KAVERIYAN','CORE',4,650000),
 ('FORGEPRINT','STARTUP',1,500000),('ROBONEST','STARTUP',1,550000),('SHILPAKAR','MASS',3,450000),('BIMCRAFT','STARTUP',1,480000),
 ('AROGYA','STARTUP',1,700000),('QUANTLOOM','SUPER_DREAM',3,1800000),('NETRA','CORE',2,700000),('SAMYUTA','CORE',1,800000),
 ('ZENITHSOFT','MASS',4,400000),('LEDGERLEAF','DREAM',2,1200000),('CLEARVIEW','DREAM',2,1150000),('EKATVA','DREAM',2,1000000)
) AS x(key, tier, w, ctc) ON x.key = p.key;
INSERT INTO t_company VALUES
 ('MERIDIAN',  'Meridian Capital Services',       'BFSI',                 'DREAM', NULL, 7, 1100000),
 ('SUVARNA',   'Suvarna Finance and Insurance',   'BFSI',                 'MASS',  NULL, 6, 520000),
 ('NORTHSTAR', 'Northstar Risk Analytics',        'BFSI',                 'DREAM', NULL, 4, 1000000),
 ('BRIGHTPATH','Brightpath Consulting',           'CONSULTING_ANALYTICS', 'DREAM', NULL, 5, 1200000),
 ('INSIGHTFUL','Insightful Metrics Pvt Ltd',      'CONSULTING_ANALYTICS', 'CORE',  NULL, 4, 800000),
 ('INFINITUM', 'Infinitum Tech Services',         'IT_SERVICES',          'MASS',  NULL, 12, 400000),
 ('CRESTLINE', 'Crestline Digital',               'IT_SERVICES',          'MASS',  NULL, 9, 420000),
 ('APEXBYTE',  'Apex Byte Solutions',             'IT_SERVICES',          'MASS',  NULL, 7, 450000),
 ('LOOPWISE',  'Loopwise SaaS',                   'SOFTWARE_PRODUCT',     'DREAM', NULL, 3, 1300000),
 ('CURELINK',  'CureLink Health Systems',         'PHARMA_HEALTHCARE',    'CORE',  NULL, 3, 650000),
 ('CHIPSMITH', 'Chipsmith Design Services',       'ELECTRONICS_SEMICON',  'CORE',  NULL, 2, 750000),
 ('PRECISIO',  'Precisio Engineering',            'CORE_MECHANICAL',      'CORE',  NULL, 2, 520000),
 ('SETU',      'Setu Builders',                   'CONSTRUCTION_INFRA',   'MASS',  NULL, 2, 400000),
 ('SIGNALWAVE','Signalwave Networks',             'TELECOM',              'CORE',  NULL, 1, 620000),
 ('TEJAS',     'Tejas Solar EPC',                 'ENERGY_POWER',         'CORE',  NULL, 1, 560000),
 ('RATHI',     'Rathi Auto Components',           'AUTOMOTIVE',           'MASS',  NULL, 2, 420000),
 ('STATEPOWER','State Power Utility Corporation', 'GOVERNMENT_PSU',       'CORE',  NULL, 1, 750000),
 ('KIRANACART','Kirana Cart Commerce',            'OTHER',                'DREAM', NULL, 3, 950000);

INSERT INTO placement.company (company_id, institution_id, name, sector, website, tier, hr_contact_name, hr_contact_email, industry_partner_id)
SELECT pg_temp.uid('company:' || c.key), pg_temp.uid('inst:DIET'), c.name, c.sector,
       'https://www.' || lower(c.key) || '.example', c.tier,
       pg_temp.fname('hr:' || c.key) || ' ' || pg_temp.lname('hr:' || c.key),
       'campus.hiring@' || lower(c.key) || '.example',
       CASE WHEN c.partner_key IS NOT NULL THEN pg_temp.uid('partner:' || c.partner_key) END
FROM t_company c;

-- ---------------------------------------------------------------------
-- 5.3 Senior alumni (graduated 2012-2020) — the people who connect partners.
--     current_organisation is free text with realistic spelling variants.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_senior_alumni ON COMMIT DROP AS
SELECT i, 'alum:senior:' || i AS k,
       (ARRAY['CSE','IT','ECE','EEE','MECH','CIVIL'])[1 + (i % 6)] AS dept,
       2012 + (i % 9) AS grad_year,
       (ARRAY[
         'Nimbus CloudWorks','NIMBUS CLOUDWORKS PVT LTD','KodeVista Software Labs Pvt. Ltd.','DataSutra Analytics',
         'Meridian Capital','MERIDIAN CAPITAL SERVICES LTD','Meridian Capital Services','Suvarna Finance & Insurance',
         'Northstar Risk Analytics','Brightpath Consulting Group','Brightpath Consulting','Insightful Metrics',
         'Silicon Delta Semiconductors','Silicon Delta Semi','VoltEdge Embedded','Kaveriyan Motors Ltd',
         'Dynamotive EV Drives','Shilpakar Infra Projects','QuantLoom AI Labs','Infinitum Tech Services',
         'Crestline Digital','Loopwise','CureLink Health Systems','Samyuta Power Transmission','Tarang Telecom',
         'Higher studies abroad','Own startup','Suryagrid Renewables','Netra Vision Systems','Clearview Consulting Group'
       ])[1 + ((i * 7) % 30)] AS org
FROM generate_series(1, 60) AS i;

INSERT INTO people.person (person_id, institution_id, full_name, given_name, family_name, gender, primary_email)
SELECT pg_temp.uid('person:' || a.k), pg_temp.uid('inst:DIET'),
       pg_temp.fname(a.k) || ' ' || pg_temp.lname(a.k), pg_temp.fname(a.k), pg_temp.lname(a.k), pg_temp.fgender(a.k),
       lower(pg_temp.fname(a.k) || '.' || pg_temp.lname(a.k) || a.grad_year) || '@alumni.diet.example'
FROM t_senior_alumni a;

INSERT INTO placement.alumni (alumni_id, person_id, student_id, programme_id, graduation_year, current_organisation, current_designation,
                              sector, location, linkedin_url, higher_study_institution, outcome_category, engagement_level,
                              contact_consent, publicity_consent, last_updated_on, updated_via)
SELECT pg_temp.uid(a.k), pg_temp.uid('person:' || a.k), NULL, pg_temp.uid('prog:' || a.dept), a.grad_year,
       CASE WHEN a.org IN ('Higher studies abroad','Own startup') THEN NULL ELSE a.org END,
       CASE WHEN a.org = 'Higher studies abroad' THEN NULL
            WHEN a.org = 'Own startup' THEN 'Founder'
            ELSE (ARRAY['Engineering Manager','Senior Architect','Director – Delivery','Principal Engineer','Vice President','Lead Data Scientist','Program Manager'])[1 + (a.i % 7)] END,
       CASE WHEN a.org ILIKE '%meridian%' OR a.org ILIKE '%suvarna%' OR a.org ILIKE '%northstar%' THEN 'BFSI'
            WHEN a.org ILIKE '%brightpath%' OR a.org ILIKE '%insightful%' OR a.org ILIKE '%datasutra%' OR a.org ILIKE '%clearview%' THEN 'CONSULTING_ANALYTICS'
            WHEN a.org ILIKE '%silicon%' OR a.org ILIKE '%voltedge%' OR a.org ILIKE '%netra%' THEN 'ELECTRONICS_SEMICON'
            WHEN a.org ILIKE '%kaveriyan%' OR a.org ILIKE '%dynamotive%' THEN 'AUTOMOTIVE'
            WHEN a.org ILIKE '%shilpakar%' THEN 'CONSTRUCTION_INFRA'
            WHEN a.org ILIKE '%quantloom%' OR a.org ILIKE '%kodevista%' OR a.org ILIKE '%loopwise%' THEN 'SOFTWARE_PRODUCT'
            WHEN a.org ILIKE '%curelink%' THEN 'PHARMA_HEALTHCARE'
            WHEN a.org ILIKE '%samyuta%' THEN 'GOVERNMENT_PSU'
            WHEN a.org ILIKE '%tarang%' THEN 'TELECOM'
            WHEN a.org ILIKE '%suryagrid%' THEN 'ENERGY_POWER'
            WHEN a.org IN ('Higher studies abroad','Own startup') THEN NULL
            ELSE 'IT_SERVICES' END,
       (ARRAY['Bengaluru','Hyderabad','Pune','Chennai','Mumbai','Gurugram','Singapore','Dubai'])[1 + (a.i % 8)],
       'https://www.linkedin.example/in/' || lower(pg_temp.fname(a.k) || '-' || pg_temp.lname(a.k)) || '-' || a.i,
       CASE WHEN a.org = 'Higher studies abroad' THEN 'Technical University (synthetic)' END,
       CASE WHEN a.org = 'Higher studies abroad' THEN 'HIGHER_STUDIES' WHEN a.org = 'Own startup' THEN 'ENTREPRENEUR' ELSE 'EMPLOYED' END,
       (ARRAY['ACTIVE','OCCASIONAL','OCCASIONAL','DORMANT'])[1 + (a.i % 4)],
       (a.i % 3) <> 0, (a.i % 4) = 0, DATE '2026-03-01' + (a.i % 150), 'ALUMNI_PORTAL'
FROM t_senior_alumni a;

-- company alumni connects: most senior consenting alumnus whose organisation matches the company name
UPDATE placement.company c
SET alumni_connect_person_id = m.person_id
FROM (
  SELECT DISTINCT ON (c2.company_id) c2.company_id, al.person_id
  FROM placement.company c2
  JOIN placement.alumni al ON al.student_id IS NULL AND al.contact_consent
   AND similarity(lower(al.current_organisation), lower(c2.name)) > 0.6
  ORDER BY c2.company_id, al.graduation_year, al.person_id
) m
WHERE m.company_id = c.company_id;

-- ---------------------------------------------------------------------
-- 5.4 Partner contacts (people.person + engagement.partner_contact)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_contact ON COMMIT DROP AS
SELECT p.key AS partner, r.n, 'contact:' || p.key || ':' || r.n AS k, r.role, r.designation, r.is_primary,
       r.vf::date AS valid_from, r.vt::date AS valid_to, p.domain
FROM t_partner p
CROSS JOIN (VALUES
  (1, 'SPOC',      'Head – University Relations', true,  '2024-06-01', NULL),
  (2, 'TECHNICAL', 'Principal Engineer',          false, '2024-06-01', NULL),
  (3, 'HR',        'Talent Acquisition Lead',     false, '2024-06-01', NULL)
) AS r(n, role, designation, is_primary, vf, vt)
WHERE r.n < 3 OR p.intensity >= 5;

-- history: contacts who left (the relationship must survive people changing jobs)
UPDATE t_contact SET valid_to = '2025-03-31', is_primary = false WHERE partner = 'NIMBUS' AND n = 1;
INSERT INTO t_contact VALUES ('NIMBUS', 4, 'contact:NIMBUS:4', 'SPOC', 'Director – Campus Programs', true, '2025-04-01', NULL, 'nimbuscloudworks');
UPDATE t_contact SET valid_to = '2026-01-15', is_primary = false WHERE partner = 'TARANG' AND n = 1;   -- no replacement: a dormancy cause
UPDATE t_contact SET valid_to = '2026-05-31' WHERE partner = 'DATASUTRA' AND n = 2;

INSERT INTO people.person (person_id, institution_id, full_name, given_name, family_name, gender, primary_email, primary_phone)
SELECT pg_temp.uid('person:' || c.k), pg_temp.uid('inst:DIET'),
       pg_temp.fname(c.k) || ' ' || pg_temp.lname(c.k), pg_temp.fname(c.k), pg_temp.lname(c.k), pg_temp.fgender(c.k),
       lower(pg_temp.fname(c.k)) || lower(left(pg_temp.lname(c.k), 1)) || (100 + floor(pg_temp.rnd('mail:' || c.k) * 900))::int || '@mail.example',
       '+91-9' || lpad((floor(pg_temp.rnd('ph:' || c.k) * 1000000000))::bigint::text, 9, '0')
FROM t_contact c;

INSERT INTO engagement.partner_contact (partner_contact_id, industry_partner_id, person_id, designation, organisation_unit, contact_role,
                                        work_email, work_phone, is_primary, valid_from, valid_to)
SELECT pg_temp.uid(c.k), pg_temp.uid('partner:' || c.partner), pg_temp.uid('person:' || c.k), c.designation,
       CASE c.role WHEN 'SPOC' THEN 'Campus Relations' WHEN 'HR' THEN 'Talent Acquisition' ELSE 'Engineering' END,
       c.role, lower(pg_temp.fname(c.k) || '.' || pg_temp.lname(c.k)) || '@' || c.domain || '.example',
       '+91-40-' || lpad((floor(pg_temp.rnd('wph:' || c.k) * 100000000))::bigint::text, 8, '0'),
       c.is_primary, c.valid_from, c.valid_to
FROM t_contact c;

-- senior alumni who are contacts at partners (ALUMNI_CHAMPION)
INSERT INTO engagement.partner_contact (partner_contact_id, industry_partner_id, person_id, designation, organisation_unit, contact_role,
                                        work_email, is_primary, valid_from)
SELECT DISTINCT ON (ip.industry_partner_id)
       pg_temp.uid('contact:alumni:' || ip.industry_partner_id || ':' || al.person_id), ip.industry_partner_id, al.person_id,
       al.current_designation, 'Alumni Network', 'ALUMNI_CHAMPION',
       lower(replace(pe.full_name, ' ', '.')) || '@' || tp.domain || '.example', false, '2025-01-01'
FROM placement.alumni al
JOIN people.person pe ON pe.person_id = al.person_id
JOIN engagement.industry_partner ip ON similarity(lower(al.current_organisation), lower(ip.name)) > 0.6
JOIN t_partner tp ON pg_temp.uid('partner:' || tp.key) = ip.industry_partner_id
WHERE al.student_id IS NULL AND al.contact_consent AND ip.status IN ('ACTIVE','PROSPECT')
ORDER BY ip.industry_partner_id, al.graduation_year;

-- legacy inline contact columns kept in step with the active primary contact
UPDATE engagement.industry_partner ip
SET contact_person = pe.full_name, contact_email = pc.work_email, contact_phone = pc.work_phone
FROM engagement.partner_contact pc JOIN people.person pe ON pe.person_id = pc.person_id
WHERE pc.industry_partner_id = ip.industry_partner_id AND pc.is_primary AND pc.valid_to IS NULL;

-- consent to hold contact data (purpose code is an implementation decision)
INSERT INTO identity.consent (consent_id, person_id, purpose_code, is_granted, granted_at, evidence_ref)
SELECT pg_temp.uid('consent:' || pc.partner_contact_id), pc.person_id, 'INDUSTRY_CONTACT', true,
       pc.valid_from::timestamptz, 'Contact sheet annexed to MoU / business card exchange'
FROM engagement.partner_contact pc
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 5.5 Partner expertise (what each partner can teach) — input to course matching
-- ---------------------------------------------------------------------
INSERT INTO engagement.partner_expertise (partner_expertise_id, industry_partner_id, partner_contact_id, area, description, evidence_source, confidence)
SELECT pg_temp.uid('exp:' || e.partner || ':' || e.area), pg_temp.uid('partner:' || e.partner),
       CASE WHEN e.ord = 1 AND tc.k IS NOT NULL THEN pg_temp.uid(tc.k) END,
       e.area, 'Hands-on industry practice in ' || lower(e.area),
       CASE WHEN e.ord = 1 THEN 'CONTACT_PROFILE' WHEN e.ord = 2 THEN 'MOU_SCOPE' ELSE 'PAST_ACTIVITY' END,
       CASE WHEN e.ord = 3 THEN 0.780 END
FROM (VALUES
 ('NIMBUS',1,'Kubernetes orchestration'),('NIMBUS',2,'Serverless computing'),('NIMBUS',3,'CI/CD pipelines'),('NIMBUS',4,'Infrastructure as code'),
 ('KODEVISTA',1,'React component design'),('KODEVISTA',2,'REST API design'),('KODEVISTA',3,'Application monitoring'),
 ('DATASUTRA',1,'Apache Spark'),('DATASUTRA',2,'Business intelligence reporting'),('DATASUTRA',3,'Model monitoring and drift'),('DATASUTRA',4,'Credit risk analytics'),
 ('SECUREGRID',1,'Security operations centre workflows'),('SECUREGRID',2,'Penetration testing methods'),('SECUREGRID',3,'Zero trust networking'),('SECUREGRID',4,'Identity and access management'),
 ('PAYSETU',1,'UPI and payment gateways'),('PAYSETU',2,'Payment fraud detection'),('PAYSETU',3,'Regulatory technology'),
 ('SILICONDELTA',1,'RTL design with Verilog'),('SILICONDELTA',2,'Static timing analysis'),('SILICONDELTA',3,'Functional verification with UVM'),
 ('VOLTEDGE',1,'ARM Cortex-M firmware'),('VOLTEDGE',2,'Real-time operating systems'),('VOLTEDGE',3,'IoT communication protocols'),
 ('TARANG',1,'5G NR architecture'),('TARANG',2,'Open RAN'),('TARANG',3,'Network slicing'),
 ('SURYAGRID',1,'Solar plant design'),('SURYAGRID',2,'Maximum power point tracking'),('SURYAGRID',3,'Energy storage systems'),
 ('DYNAMOTIVE',1,'Battery management systems'),('DYNAMOTIVE',2,'BLDC motor control'),('DYNAMOTIVE',3,'EV charging infrastructure'),('DYNAMOTIVE',4,'Battery testing and validation'),
 ('AUTOMAXIS',1,'PLC programming'),('AUTOMAXIS',2,'SCADA systems'),('AUTOMAXIS',3,'Industrial IoT'),
 ('KAVERIYAN',1,'Automotive assembly lines'),('KAVERIYAN',2,'Electric vehicle powertrain'),('KAVERIYAN',3,'Vehicle safety'),('KAVERIYAN',4,'Braking systems'),
 ('FORGEPRINT',1,'Metal additive manufacturing'),('FORGEPRINT',2,'Topology optimisation'),('FORGEPRINT',3,'Rapid prototyping'),
 ('ROBONEST',1,'Robot programming'),('ROBONEST',2,'Collaborative robots'),('ROBONEST',3,'Warehouse robotics'),
 ('SHILPAKAR',1,'Construction safety'),('SHILPAKAR',2,'Project scheduling with CPM and PERT'),('SHILPAKAR',3,'Quality control on site'),
 ('BIMCRAFT',1,'Building information modelling'),('BIMCRAFT',2,'4D and 5D BIM'),('BIMCRAFT',3,'Clash detection'),
 ('PATHIK',1,'Metro rail systems'),('PATHIK',2,'Urban mobility planning'),('PATHIK',3,'Intelligent transportation systems'),
 ('AROGYA',1,'Medical device electronics'),('AROGYA',2,'Embedded firmware for medical devices'),
 ('QUANTLOOM',1,'Transformers and large language models'),('QUANTLOOM',2,'Model deployment and serving'),('QUANTLOOM',3,'Feature engineering pipelines'),
 ('NETRA',1,'Machine vision systems'),('NETRA',2,'Convolutional neural networks'),('NETRA',3,'Edge computing'),
 ('SAMYUTA',1,'Power transmission and grid codes'),('SAMYUTA',2,'Smart grid technologies'),('SAMYUTA',3,'SCADA systems'),
 ('ZENITHSOFT',1,'Microservices architecture'),('ZENITHSOFT',2,'Database design for web applications'),
 ('GREENBRICK',1,'Sustainable construction materials'),('GREENBRICK',2,'Green buildings'),
 ('PRAVAH',1,'Small hydro power systems'),
 ('AEROFAB',1,'Aerospace components manufacturing'),('AEROFAB',2,'CNC machining'),
 ('EKATVA',1,'Core banking systems'),('EKATVA',2,'Digital banking platforms'),
 ('LEDGERLEAF',1,'Blockchain and distributed ledgers'),('LEDGERLEAF',2,'Algorithmic trading'),
 ('CLEARVIEW',1,'Business intelligence reporting'),('CLEARVIEW',2,'Management consulting'),
 ('HELIX',1,'Clinical data analytics'),
 ('ORBITAL',1,'Satellite communication'),('ORBITAL',2,'Antenna design')
) AS e(partner, ord, area)
LEFT JOIN t_contact tc ON tc.partner = e.partner AND tc.role = 'TECHNICAL' AND tc.valid_to IS NULL;

-- ---------------------------------------------------------------------
-- 5.6 MoUs (40) with documents, extraction provenance and deliverables
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_mou (
  key text PRIMARY KEY, partner text, partner_name text, partner_type text, title text, scope text,
  signed_on date, valid_from date, valid_until date, status text, alert_days int, deliverables text, owner_dept text
) ON COMMIT DROP;
INSERT INTO t_mou VALUES
 ('M01','NIMBUS',NULL,'INDUSTRY','Industry-Academia Collaboration Agreement','Guest lectures, internships and campus recruitment for cloud engineering roles','2021-07-10','2021-08-01','2024-07-31','RENEWED',90,'GUEST_LECTURE:6,INTERNSHIP:15,PLACEMENT:12','CSE'),
 ('M02','NIMBUS',NULL,'INDUSTRY','Industry-Academia Collaboration Agreement (Renewal 2024)','Cloud curriculum support, guest lectures, data-centre visits, internships, recruitment and faculty training','2024-07-20','2024-08-01','2027-07-31','ACTIVE',90,'GUEST_LECTURE:10,INDUSTRY_VISIT:4,INTERNSHIP:25,PLACEMENT:20,TRAINING_PROGRAMME:2','CSE'),
 ('M38','NIMBUS',NULL,'INDUSTRY','Cloud Lab Sponsorship Agreement','Sponsorship of a 60-seat cloud computing laboratory with credits and trainer support','2025-01-10','2025-01-15','2026-10-31','ACTIVE',90,'LAB_SUPPORT:1,TRAINING_PROGRAMME:1','CSE'),
 ('M30','KODEVISTA',NULL,'INDUSTRY','Campus Connect MoU','Guest lectures and summer internships in product engineering','2020-12-01','2021-01-01','2023-12-31','RENEWED',90,'GUEST_LECTURE:4,INTERNSHIP:10','IT'),
 ('M03','KODEVISTA',NULL,'INDUSTRY','Product Engineering Talent Partnership','Full-stack curriculum inputs, guest lectures, faculty immersion, internships and hiring','2024-01-15','2024-02-01','2027-01-31','ACTIVE',90,'GUEST_LECTURE:8,FACULTY_EXCHANGE:2,INTERNSHIP:15,PLACEMENT:10','IT'),
 ('M04','DATASUTRA',NULL,'INDUSTRY','Analytics Centre of Excellence MoU','Big data and analytics lectures, sponsored analytics projects, consultancy and internships','2023-11-01','2023-11-15','2026-11-14','ACTIVE',90,'GUEST_LECTURE:6,SPONSORED_PROJECT:2,CONSULTANCY:1,INTERNSHIP:8','CSE'),
 ('M05','SECUREGRID',NULL,'INDUSTRY','Cyber Security Skilling MoU','Expert talks on security operations, SOC visits, internships and a capture-the-flag event','2023-10-05','2023-10-15','2026-10-14','ACTIVE',90,'EXPERT_TALK:6,INDUSTRY_VISIT:3,INTERNSHIP:10,TRAINING_PROGRAMME:1','IT'),
 ('M06','PAYSETU',NULL,'INDUSTRY','FinTech Innovation Lab MoU','Digital payments lectures, sponsored fintech projects, internships and recruitment','2025-03-10','2025-04-01','2028-03-31','ACTIVE',90,'GUEST_LECTURE:6,SPONSORED_PROJECT:2,INTERNSHIP:10,PLACEMENT:8','IT'),
 ('M07','SILICONDELTA',NULL,'INDUSTRY','VLSI Design Centre MoU','EDA tool licences, VLSI lectures and internships','2022-06-01','2022-06-15','2025-06-14','RENEWED',90,'LAB_SUPPORT:1,GUEST_LECTURE:6,INTERNSHIP:10','ECE'),
 ('M08','SILICONDELTA',NULL,'INDUSTRY','VLSI Design Centre MoU – Phase II','EDA licences, verification lab upgrade, lectures, faculty immersion, internships and sponsored chip projects','2025-06-10','2025-06-15','2028-06-14','ACTIVE',90,'LAB_SUPPORT:2,GUEST_LECTURE:9,FACULTY_EXCHANGE:2,INTERNSHIP:12,SPONSORED_PROJECT:2','ECE'),
 ('M36','SILICONDELTA',NULL,'INDUSTRY','Chip Design Internship Addendum','Additional six-month design internships and a verification STTP','2026-03-01','2026-03-15','2027-03-14','ACTIVE',90,'INTERNSHIP:6,TRAINING_PROGRAMME:1','ECE'),
 ('M39','VOLTEDGE',NULL,'INDUSTRY','Embedded Training MoU','Embedded systems lectures and internships','2021-08-01','2021-08-01','2024-07-31','RENEWED',90,'GUEST_LECTURE:3,INTERNSHIP:5','ECE'),
 ('M09','VOLTEDGE',NULL,'INDUSTRY','Embedded Systems Training MoU','Firmware and RTOS lectures, factory visits, internships and a hands-on workshop','2024-09-01','2024-09-15','2027-09-14','ACTIVE',90,'GUEST_LECTURE:6,INDUSTRY_VISIT:3,INTERNSHIP:10,TRAINING_PROGRAMME:1','ECE'),
 ('M10','TARANG',NULL,'INDUSTRY','5G Skills Partnership','5G and Open RAN lectures, network operations centre visits and internships','2023-12-01','2024-01-01','2026-12-31','ACTIVE',120,'GUEST_LECTURE:6,INDUSTRY_VISIT:3,INTERNSHIP:6','ECE'),
 ('M31','SURYAGRID',NULL,'INDUSTRY','Solar Energy Training MoU','Solar plant visits and internships','2020-03-01','2020-03-01','2024-02-29','RENEWED',90,'INDUSTRY_VISIT:4,INTERNSHIP:8','EEE'),
 ('M11','SURYAGRID',NULL,'INDUSTRY','Renewable Energy Internship MoU','Solar and storage plant visits, lectures and internships','2024-02-20','2024-03-01','2027-02-28','ACTIVE',90,'INDUSTRY_VISIT:6,GUEST_LECTURE:4,INTERNSHIP:12','EEE'),
 ('M12','DYNAMOTIVE',NULL,'INDUSTRY','EV Powertrain Collaboration','EV drives lectures, battery lab support, sponsored projects, internships and hiring','2024-11-05','2024-11-15','2027-11-14','ACTIVE',90,'GUEST_LECTURE:6,LAB_SUPPORT:1,SPONSORED_PROJECT:2,INTERNSHIP:15,PLACEMENT:6','EEE'),
 ('M40','DYNAMOTIVE',NULL,'INDUSTRY','Battery Testing Lab Support Agreement','Loan of battery cyclers and test chambers for one year','2025-09-01','2025-09-01','2026-08-31','ACTIVE',60,'LAB_SUPPORT:1','EEE'),
 ('M13','AUTOMAXIS',NULL,'INDUSTRY','Industrial Automation Lab MoU','PLC/SCADA lab kits, automation lectures, plant visits and internships','2023-09-20','2023-10-01','2026-09-30','ACTIVE',90,'LAB_SUPPORT:1,GUEST_LECTURE:6,INDUSTRY_VISIT:3,INTERNSHIP:8','EEE'),
 ('M14','KAVERIYAN',NULL,'INDUSTRY','Automotive Skills and Placement MoU','Plant visits and campus recruitment','2021-12-01','2022-01-01','2024-12-31','RENEWED',90,'INDUSTRY_VISIT:6,PLACEMENT:10','MECH'),
 ('M15','KAVERIYAN',NULL,'INDUSTRY','Automotive Skills and Placement MoU (Renewal)','Assembly-plant visits, EV powertrain lectures, faculty immersion, internships and recruitment','2024-12-15','2025-01-01','2027-12-31','ACTIVE',90,'INDUSTRY_VISIT:8,GUEST_LECTURE:6,FACULTY_EXCHANGE:2,INTERNSHIP:20,PLACEMENT:12','MECH'),
 ('M16','FORGEPRINT',NULL,'INDUSTRY','Additive Manufacturing Centre MoU','Metal 3D printer access, lectures, consultancy and internships','2023-07-15','2023-08-01','2026-07-31','ACTIVE',90,'LAB_SUPPORT:1,GUEST_LECTURE:6,CONSULTANCY:2,INTERNSHIP:6','MECH'),
 ('M17','ROBONEST',NULL,'INDUSTRY','Robotics Training MoU','Robot programming lectures, warehouse automation visits and internships','2025-01-10','2025-02-01','2028-01-31','ACTIVE',90,'GUEST_LECTURE:6,INDUSTRY_VISIT:3,INTERNSHIP:6','MECH'),
 ('M37','SHILPAKAR',NULL,'INDUSTRY','Site Training MoU 2021','Construction site visits and internships','2021-06-10','2021-07-01','2024-06-30','RENEWED',90,'INDUSTRY_VISIT:6,INTERNSHIP:10','CIVIL'),
 ('M18','SHILPAKAR',NULL,'INDUSTRY','Construction Site Training MoU','Site visits, safety lectures, internships and recruitment','2024-06-15','2024-07-01','2027-06-30','ACTIVE',90,'INDUSTRY_VISIT:9,GUEST_LECTURE:3,INTERNSHIP:15,PLACEMENT:8','CIVIL'),
 ('M19','BIMCRAFT',NULL,'INDUSTRY','BIM Skills MoU','BIM lectures, workshops/FDPs and internships','2024-08-10','2024-08-15','2026-12-15','ACTIVE',90,'GUEST_LECTURE:6,TRAINING_PROGRAMME:2,INTERNSHIP:5','CIVIL'),
 ('M20','PATHIK',NULL,'INDUSTRY','Urban Mobility Research MoU','Metro depot visits, expert talks and a sponsored mobility study','2022-10-01','2022-10-15','2025-10-14','EXPIRED',90,'INDUSTRY_VISIT:4,EXPERT_TALK:4,SPONSORED_PROJECT:1','CIVIL'),
 ('M21','AROGYA',NULL,'INDUSTRY','MedTech Device Innovation MoU','Sponsored medical-electronics projects, lectures and internships','2026-02-01','2026-02-15','2029-02-14','ACTIVE',90,'SPONSORED_PROJECT:2,GUEST_LECTURE:6,INTERNSHIP:6','ECE'),
 ('M22','QUANTLOOM',NULL,'INDUSTRY','Applied AI Research and Internship MoU','Applied AI lectures and expert talks, sponsored research projects, internships and hiring','2025-07-01','2025-07-15','2028-07-14','ACTIVE',90,'GUEST_LECTURE:9,EXPERT_TALK:6,SPONSORED_PROJECT:3,INTERNSHIP:15,PLACEMENT:6','CSE'),
 ('M23','NETRA',NULL,'INDUSTRY','Machine Vision Lab MoU','Vision camera kits, lectures, plant visits and internships','2024-03-10','2024-03-15','2027-03-14','ACTIVE',90,'LAB_SUPPORT:1,GUEST_LECTURE:6,INDUSTRY_VISIT:3,INTERNSHIP:8','ECE'),
 ('M24','SAMYUTA',NULL,'INDUSTRY','Power Transmission Apprenticeship MoU','Substation visits, faculty deputation and apprenticeships','2023-05-01','2023-05-15','2028-05-14','ACTIVE',90,'INDUSTRY_VISIT:10,FACULTY_EXCHANGE:3,INTERNSHIP:20','EEE'),
 ('M25','ZENITHSOFT',NULL,'INDUSTRY','Software Services Training MoU','Lectures, internships and mass recruitment','2021-09-01','2021-09-15','2025-09-14','EXPIRED',90,'GUEST_LECTURE:8,PLACEMENT:30,INTERNSHIP:10','CSE'),
 ('M26','GREENBRICK',NULL,'INDUSTRY','Sustainable Materials MoU','Sponsored materials research and lectures (terminated by mutual consent)','2022-01-20','2022-02-01','2025-01-31','TERMINATED',90,'SPONSORED_PROJECT:2,GUEST_LECTURE:4','CIVIL'),
 ('M27','PRAVAH',NULL,'INDUSTRY','Hydro Systems Internship MoU','Hydro plant visits and internships','2022-04-01','2022-04-15','2025-04-14','EXPIRED',90,'INDUSTRY_VISIT:6,INTERNSHIP:6','EEE'),
 ('M28','AEROFAB',NULL,'INDUSTRY','Aerospace Components MoU','Lectures, shop-floor visits and internships','2022-11-01','2022-11-15','2025-11-14','EXPIRED',90,'GUEST_LECTURE:6,INDUSTRY_VISIT:3,INTERNSHIP:6','MECH'),
 ('M29','EKATVA',NULL,'INDUSTRY','Digital Banking Talent MoU','Core banking lectures, internships and recruitment (draft under review)','2026-08-25','2026-09-01','2029-08-31','DRAFT',90,'GUEST_LECTURE:6,INTERNSHIP:15,PLACEMENT:10','IT'),
 ('M32',NULL,'Demo State Technological University – Centre for Advanced Computing','UNIVERSITY','Academic Collaboration MoU','Faculty exchange, joint FDPs and curriculum review','2024-05-01','2024-05-01','2029-04-30','ACTIVE',180,'FACULTY_EXCHANGE:4,TRAINING_PROGRAMME:3,CURRICULUM_INPUT:1','CSE'),
 ('M33',NULL,'National Remote Sensing Research Laboratory (synthetic)','RESEARCH_LAB','Geospatial Research MoU','Joint sponsored projects and researcher exchange','2025-01-15','2025-01-15','2030-01-14','ACTIVE',180,'SPONSORED_PROJECT:2,FACULTY_EXCHANGE:2','CIVIL'),
 ('M34',NULL,'State Skill Development Mission (synthetic)','GOVERNMENT','Skill Certification MoU','Certification drives and train-the-trainer programmes','2023-06-01','2023-06-15','2026-06-14','ACTIVE',90,'TRAINING_PROGRAMME:6','EEE'),
 ('M35',NULL,'Nordhavn University of Applied Sciences (synthetic)','INTERNATIONAL','International Exchange MoU','Faculty exchange and curriculum benchmarking','2025-09-01','2025-09-01','2030-08-31','ACTIVE',180,'FACULTY_EXCHANGE:4,CURRICULUM_INPUT:1','MECH');

-- documents (knowledge.document) for each signed MoU
INSERT INTO knowledge.document (document_id, institution_id, title, document_class, mime_type, storage_uri, content_hash, page_count,
                                language, version, effective_from, effective_to, owner_role_id, sensitivity, is_retrievable_by_agents, uploaded_at)
SELECT pg_temp.uid('doc:mou:' || m.key), pg_temp.uid('inst:DIET'),
       'MoU – ' || COALESCE(p.name, m.partner_name) || ' – ' || m.title, 'MOU', 'application/pdf',
       'storage://mou-documents/' || lower(m.key) || '-' || COALESCE(lower(m.partner), 'noninds') || '.pdf',
       'md5:' || md5('mou-document:' || m.key),
       6 + (length(m.deliverables) % 7), 'en', '1.0', m.valid_from, m.valid_until,
       pg_temp.uid('role:INDUSTRY_RELATIONS'), 'SENSITIVE', true,
       (CASE WHEN m.signed_on < '2025-09-01' THEN DATE '2025-09-02' + (right(m.key, 2)::int % 20) ELSE m.signed_on + 3 END)::timestamptz
FROM t_mou m LEFT JOIN t_partner p ON p.key = m.partner;

-- extraction jobs: historic MoUs were digitised in a September 2025 backfill; new ones on upload
INSERT INTO knowledge.extraction_job (extraction_job_id, document_id, source_uri, detected_document_type, extraction_method, status, started_at, finished_at, error_detail)
SELECT pg_temp.uid('xjob:' || m.key), pg_temp.uid('doc:mou:' || m.key), d.storage_uri, 'MOU',
       CASE WHEN m.signed_on < '2022-01-01' THEN 'OCR' ELSE 'HYBRID' END,
       CASE WHEN m.key = 'M29' THEN 'NEEDS_REVIEW' ELSE 'COMPLETED' END,
       d.uploaded_at + interval '2 minutes', d.uploaded_at + interval '5 minutes', NULL
FROM t_mou m JOIN knowledge.document d ON d.document_id = pg_temp.uid('doc:mou:' || m.key);

-- a failed first attempt on a scanned 2020 MoU (kept for provenance realism)
INSERT INTO knowledge.extraction_job (extraction_job_id, document_id, source_uri, detected_document_type, extraction_method, status, started_at, finished_at, error_detail)
SELECT pg_temp.uid('xjob:M31:failed'), pg_temp.uid('doc:mou:M31'), 'storage://mou-documents/m31-suryagrid.pdf', 'UNKNOWN', 'TEXT', 'FAILED',
       '2025-09-05 10:00+05:30', '2025-09-05 10:01+05:30', 'No text layer found; retry with OCR';

-- extracted fields: header fields + one group per deliverable
CREATE TEMP TABLE t_mou_deliv ON COMMIT DROP AS
SELECT m.key AS mou, d.ord, split_part(d.item, ':', 1) AS dtype, split_part(d.item, ':', 2)::int AS target
FROM t_mou m
CROSS JOIN LATERAL unnest(string_to_array(m.deliverables, ',')) WITH ORDINALITY AS d(item, ord);

INSERT INTO knowledge.extracted_field (extracted_field_id, extraction_job_id, field_name, raw_value, normalised_value, confidence, page_no,
                                       verification_status, corrected_value, verified_by_user_id, verified_at)
SELECT pg_temp.uid('xf:' || f.mou || ':' || f.field), pg_temp.uid('xjob:' || f.mou), f.field, f.raw, f.norm, f.conf, f.page,
       CASE WHEN f.mou = 'M29' AND f.conf < 0.85 THEN 'NEEDS_REVIEW'
            WHEN f.conf < 0.85 THEN 'CORRECTED'
            WHEN f.conf < 0.93 THEN 'VERIFIED'
            ELSE 'AUTO' END,
       CASE WHEN f.mou <> 'M29' AND f.conf < 0.85 THEN f.norm END,
       CASE WHEN f.mou <> 'M29' AND f.conf < 0.93 THEN pg_temp.uid('user:iiic.exec') END,
       CASE WHEN f.mou <> 'M29' AND f.conf < 0.93 THEN d.uploaded_at + interval '1 day' END
FROM (
  SELECT m.key AS mou, x.field, x.raw, x.norm, x.page,
         round((0.78 + pg_temp.rnd('conf:' || m.key || x.field) * 0.215)::numeric, 3) AS conf
  FROM t_mou m
  CROSS JOIN LATERAL (VALUES
    ('partner_name', COALESCE((SELECT name FROM t_partner WHERE key = m.partner), m.partner_name), COALESCE((SELECT name FROM t_partner WHERE key = m.partner), m.partner_name), 1),
    ('title',        m.title, m.title, 1),
    ('signed_on',    to_char(m.signed_on, 'FMDDth FMMonth YYYY'), m.signed_on::text, 1),
    ('valid_from',   to_char(m.valid_from, 'FMDDth FMMonth YYYY'), m.valid_from::text, 1),
    ('valid_until',  to_char(m.valid_until, 'FMDDth FMMonth YYYY'), m.valid_until::text, 5),
    ('scope',        m.scope, m.scope, 2)
  ) AS x(field, raw, norm, page)
  UNION ALL
  SELECT d.mou, 'deliverable[' || d.ord || '].' || y.part, y.raw, y.norm, 3 + (d.ord % 2),
         round((0.76 + pg_temp.rnd('conf:' || d.mou || d.ord || y.part) * 0.235)::numeric, 3)
  FROM t_mou_deliv d
  CROSS JOIN LATERAL (VALUES
    ('type',         lower(replace(d.dtype, '_', ' ')), d.dtype),
    ('target_count', d.target::text || CASE WHEN d.target = 1 THEN ' (one)' ELSE '' END, d.target::text)
  ) AS y(part, raw, norm)
) f
JOIN knowledge.document d ON d.document_id = pg_temp.uid('doc:mou:' || f.mou);

-- document chunks (clause text for retrieval / citation)
INSERT INTO knowledge.document_chunk (document_chunk_id, document_id, seq_no, heading_path, page_no, chunk_text, token_count)
SELECT pg_temp.uid('chunk:' || m.key || ':' || c.seq), pg_temp.uid('doc:mou:' || m.key), c.seq, c.heading, c.page, c.body,
       (length(c.body) / 4)::smallint
FROM t_mou m
LEFT JOIN t_partner p ON p.key = m.partner
CROSS JOIN LATERAL (VALUES
  (1, '1 Parties', 1, 'This Memorandum of Understanding is entered into on ' || to_char(m.signed_on, 'FMDD FMMonth YYYY') ||
      ' between Demo Institute of Engineering and Technology ("the Institute") and ' || COALESCE(p.name, m.partner_name) || ' ("the Partner").'),
  (2, '2 Scope of collaboration', 2, 'The parties agree to collaborate on the following: ' || m.scope || '.'),
  (3, '3 Commitments of the Partner', 3, (
      SELECT string_agg(format('3.%s The Partner shall %s.', d.ord,
             CASE d.dtype
               WHEN 'GUEST_LECTURE'      THEN format('deliver %s guest lectures aligned to the Institute''s curriculum', d.target)
               WHEN 'EXPERT_TALK'        THEN format('conduct %s expert talks by senior practitioners', d.target)
               WHEN 'INDUSTRY_VISIT'     THEN format('host %s industry visits for students', d.target)
               WHEN 'INTERNSHIP'         THEN format('offer internships to at least %s students', d.target)
               WHEN 'PLACEMENT'          THEN format('conduct campus recruitment resulting in at least %s offers', d.target)
               WHEN 'LAB_SUPPORT'        THEN format('provide laboratory equipment or software support in %s instalment(s)', d.target)
               WHEN 'FACULTY_EXCHANGE'   THEN format('host %s faculty members for industry immersion', d.target)
               WHEN 'TRAINING_PROGRAMME' THEN format('conduct %s faculty development or certification programme(s)', d.target)
               WHEN 'SPONSORED_PROJECT'  THEN format('sponsor %s student or faculty project(s)', d.target)
               WHEN 'CONSULTANCY'        THEN format('engage the Institute for %s consultancy assignment(s)', d.target)
               WHEN 'CURRICULUM_INPUT'   THEN format('review elective course content %s time(s) per year', d.target)
               ELSE format('deliver %s item(s) of type %s', d.target, d.dtype) END), ' ' ORDER BY d.ord)
      FROM t_mou_deliv d WHERE d.mou = m.key)),
  (4, '5 Term and renewal', 5, 'This MoU is valid from ' || to_char(m.valid_from, 'FMDD FMMonth YYYY') || ' to ' || to_char(m.valid_until, 'FMDD FMMonth YYYY') ||
      '. Renewal shall be discussed not later than ' || m.alert_days || ' days before expiry. Either party may terminate with ninety days'' written notice.')
) AS c(seq, heading, page, body);

INSERT INTO engagement.mou (mou_id, industry_partner_id, partner_name, partner_type, title, scope, signed_on, valid_from, valid_until,
                            owner_faculty_id, document_ref, status, renewal_alert_days, extraction_job_id)
SELECT pg_temp.uid('mou:' || m.key),
       CASE WHEN m.partner IS NOT NULL THEN pg_temp.uid('partner:' || m.partner) END,
       COALESCE(p.name, m.partner_name), m.partner_type, m.title, m.scope, m.signed_on, m.valid_from, m.valid_until,
       pg_temp.uid('fac:' || m.owner_dept || ':' || (2 + floor(pg_temp.rnd('mowner:' || m.key) * 3))::int),
       pg_temp.uid('doc:mou:' || m.key), m.status, m.alert_days, pg_temp.uid('xjob:' || m.key)
FROM t_mou m LEFT JOIN t_partner p ON p.key = m.partner;

INSERT INTO engagement.mou_deliverable (mou_deliverable_id, mou_id, description, deliverable_type, target_count, due_date, status,
                                        recurrence, source_text, source_page_no)
SELECT pg_temp.uid('deliv:' || d.mou || ':' || d.dtype), pg_temp.uid('mou:' || d.mou),
       CASE d.dtype
         WHEN 'GUEST_LECTURE'      THEN d.target || ' guest lectures over the MoU term'
         WHEN 'EXPERT_TALK'        THEN d.target || ' expert talks over the MoU term'
         WHEN 'INDUSTRY_VISIT'     THEN d.target || ' industry visits for students'
         WHEN 'INTERNSHIP'         THEN 'Internships for ' || d.target || ' students'
         WHEN 'PLACEMENT'          THEN 'At least ' || d.target || ' campus offers'
         WHEN 'LAB_SUPPORT'        THEN 'Laboratory support: ' || d.target || ' instalment(s)'
         WHEN 'FACULTY_EXCHANGE'   THEN d.target || ' faculty industry-immersion placements'
         WHEN 'TRAINING_PROGRAMME' THEN d.target || ' FDP / certification programme(s)'
         WHEN 'SPONSORED_PROJECT'  THEN d.target || ' sponsored project(s)'
         WHEN 'CONSULTANCY'        THEN d.target || ' consultancy assignment(s)'
         WHEN 'CURRICULUM_INPUT'   THEN 'Annual elective curriculum review'
       END,
       d.dtype, d.target,
       CASE WHEN d.dtype = 'LAB_SUPPORT' AND d.target = 1 THEN LEAST(m.valid_from + 180, m.valid_until) END,
       'PENDING',
       CASE WHEN d.dtype = 'LAB_SUPPORT' AND d.target = 1 THEN 'ONE_TIME'
            WHEN d.dtype = 'CURRICULUM_INPUT' THEN 'PER_YEAR' ELSE 'MOU_TERM' END,
       (SELECT substring(c.chunk_text FROM '3\.' || d.ord || ' (The Partner shall [^.]*)')
          FROM knowledge.document_chunk c WHERE c.document_chunk_id = pg_temp.uid('chunk:' || d.mou || ':3')),
       3
FROM t_mou_deliv d JOIN t_mou m ON m.key = d.mou;

-- renewal discussions and lineage
INSERT INTO engagement.mou_renewal (mou_renewal_id, mou_id, initiated_on, initiated_by_faculty_id, partner_contact_id, status, target_sign_by, successor_mou_id, closed_on, notes)
SELECT pg_temp.uid('renewal:' || r.mou), pg_temp.uid('mou:' || r.mou), r.init::date, m.owner_faculty_id,
       (SELECT pc.partner_contact_id FROM engagement.partner_contact pc
         WHERE pc.industry_partner_id = m.industry_partner_id AND pc.contact_role = 'SPOC' ORDER BY pc.valid_from DESC LIMIT 1),
       r.status, r.target::date, CASE WHEN r.succ IS NOT NULL THEN pg_temp.uid('mou:' || r.succ) END, r.closed::date, r.notes
FROM (VALUES
  ('M01','2024-05-02','SIGNED','2024-07-31','M02','2024-07-20','Renewed with expanded recruitment and faculty-training commitments.'),
  ('M30','2023-10-10','SIGNED','2023-12-31','M03','2024-01-15','Renewed as a product-engineering talent partnership.'),
  ('M07','2025-03-15','SIGNED','2025-06-14','M08','2025-06-10','Phase II adds verification lab upgrade and sponsored chip projects.'),
  ('M14','2024-10-01','SIGNED','2024-12-31','M15','2024-12-15','Renewal adds EV powertrain lectures and internships.'),
  ('M31','2023-12-01','SIGNED','2024-02-29','M11','2024-02-20','Renewed; storage plant visits added.'),
  ('M37','2024-04-01','SIGNED','2024-06-30','M18','2024-06-15','Renewed with safety lectures and recruitment.'),
  ('M39','2024-06-15','SIGNED','2024-08-31','M09','2024-09-01','Renewed after a two-month gap.'),
  ('M05','2026-07-20','NEGOTIATING','2026-10-10',NULL,NULL,'Partner wants to add a paid SOC analyst certification; legal reviewing liability clause.'),
  ('M40','2026-08-05','DISCUSSION_INITIATED','2026-09-30',NULL,NULL,'Equipment loan ended 31 Aug; partner open to extension if utilisation report is shared.'),
  ('M20','2025-08-01','LAPSED','2025-10-14',NULL,'2025-10-14','No response from partner after nodal officer transfer.'),
  ('M25','2025-06-10','DECLINED_BY_PARTNER','2025-09-14',NULL,'2025-08-20','Partner restructured campus hiring; declined renewal.')
) AS r(mou, init, status, target, succ, closed, notes)
JOIN engagement.mou m ON m.mou_id = pg_temp.uid('mou:' || r.mou);
-- =====================================================================
-- PART 6 — AGENT REGISTRY, INDUSTRY ACTIVITIES, COURSE ALIGNMENT,
--          PLACEMENT / INTERNSHIP / ALUMNI DATA, STUDENT FEEDBACK
-- =====================================================================

-- ---------------------------------------------------------------------
-- 6.1 Agent 28 registry, tools, health formula, schedule, run history
-- ---------------------------------------------------------------------
INSERT INTO agentops.agent (agent_id, code, agent_no, name, domain, agent_class, scope_statement, out_of_scope, reasoning_policy,
                            requires_human_approval, escalation_rule, owner_user_id, version, status, deployed_on)
VALUES (pg_temp.uid('agent:A28'), 'A28_INDUSTRY_INTERACTION', 28, 'Industry Interaction Agent', 'ENGAGEMENT', 2,
        'Maintains the industry partner register, digitised MoUs and committed deliverables, industry activities, engagement health, dormancy and MoU-expiry flags, course-aligned interaction planning, sector gap and target-partner analysis, and industry-interaction accreditation evidence.',
        'Does not own placement, internship, alumni, curriculum or research-project records; links to them only.',
        'RECOMMEND', true,
        'Dormant partner or MoU expiring without renewal discussion -> alert relationship owner and industry cell; unacknowledged after 7 days -> escalate to Dean.',
        pg_temp.uid('user:iiic.head'), '1.2', 'ACTIVE', '2024-06-15');

INSERT INTO agentops.agent_tool (agent_tool_id, agent_id, tool_name, resource_schema, resource_object, access_mode, row_scope_rule)
SELECT pg_temp.uid('tool:' || t.tool_name), pg_temp.uid('agent:A28'), t.tool_name, t.rs, t.ro, t.mode, t.scope
FROM (VALUES
  ('partner_register_rw',  'engagement', 'industry_partner',           'WRITE', 'institution'),
  ('partner_contact_rw',   'engagement', 'partner_contact',            'WRITE', 'institution'),
  ('partner_expertise_rw', 'engagement', 'partner_expertise',          'WRITE', 'institution'),
  ('mou_rw',               'engagement', 'mou',                        'WRITE', 'institution'),
  ('mou_deliverable_rw',   'engagement', 'mou_deliverable',            'WRITE', 'institution'),
  ('mou_fulfilment_rw',    'engagement', 'mou_deliverable_fulfilment', 'WRITE', 'institution'),
  ('mou_renewal_rw',       'engagement', 'mou_renewal',                'WRITE', 'institution'),
  ('activity_rw',          'engagement', 'industry_activity',          'WRITE', 'department'),
  ('activity_person_rw',   'engagement', 'industry_activity_person',   'WRITE', 'department'),
  ('course_alignment_rw',  'engagement', 'activity_course_alignment',  'WRITE', 'department'),
  ('health_snapshot_w',    'engagement', 'partner_health_snapshot',    'WRITE', 'institution'),
  ('alumni_link_rw',       'engagement', 'partner_alumni_link',        'WRITE', 'institution'),
  ('company_partner_link', 'placement',  'company.industry_partner_id','WRITE', 'institution'),
  ('curriculum_read',      'curriculum', 'course|course_version|course_unit|course_topic|course_outcome', 'READ', 'institution'),
  ('offering_read',        'academics',  'course_offering|lesson_plan|lesson_plan_session', 'READ', 'department'),
  ('placement_read',       'placement',  'company|job_opening|offer|internship|internship_evaluation|alumni|alumni_contribution', 'READ', 'institution'),
  ('research_project_read','research',   'project|funding_agency', 'READ', 'institution'),
  ('mou_documents',        'knowledge',  'document|document_chunk|extraction_job|extracted_field', 'WRITE', 'document_class=MOU'),
  ('feedback_rw',          'quality',    'feedback_instrument|feedback_response', 'WRITE', 'target_type=INDUSTRY_ACTIVITY'),
  ('evidence_w',           'quality',    'evidence_item|kpi_value', 'WRITE', 'source_schema=engagement'),
  ('calendar_read',        'core',       'calendar_event|academic_year|term', 'READ', 'institution'),
  ('agentops_w',           'agentops',   'agent_run|agent_run_input|agent_output|alert', 'WRITE', 'self'),
  ('action_item_w',        'studentlife','action_item', 'WRITE', 'source_schema=engagement')
) AS t(tool_name, rs, ro, mode, scope);

INSERT INTO agentops.model_version (model_version_id, agent_id, version, model_type, feature_list, excluded_features,
                                    training_period_start, training_period_end, validated_on, approved_by_user_id, status)
VALUES (pg_temp.uid('model:health-1.0'), pg_temp.uid('agent:A28'), 'health-1.0', 'RULE_BASED',
 '{
   "score_range": [0, 100],
   "window_days": 365,
   "dormancy_days": 180,
   "components": {
     "recency":              {"weight": 0.25, "rule": "1 - min(days_since_last_realised_event, 365) / 365"},
     "activity_volume":      {"weight": 0.20, "rule": "min(conducted_activities_12m, 6) / 6"},
     "deliverable_progress": {"weight": 0.25, "rule": "min(1, confirmed_achievement_ratio / max(mou_elapsed_ratio, 0.25)) over MoUs in force"},
     "student_outcomes":     {"weight": 0.20, "rule": "min(internships_12m + accepted_offers_12m, 20) / 20"},
     "feedback":             {"weight": 0.10, "rule": "(avg_overall_rating - 1) / 4; 0.5 when no feedback"}
   },
   "bands": {"STRONG": ">= 75", "STABLE": ">= 50", "AT_RISK": "< 50", "DORMANT": "is_dormant overrides score"}
 }',
 '{"note": "Subject is an organisation; no person-level protected attributes are used."}',
 '2024-06-01', '2025-08-31', '2025-09-20', pg_temp.uid('user:dean.academics'), 'ACTIVE');

-- Agent 1 Gemini-backed MoU intelligence model.
INSERT INTO agentops.model_version (model_version_id, agent_id, version, model_type, feature_list, excluded_features, validated_on, status)
SELECT gen_random_uuid(), a.agent_id, 'mou-1.0', 'LLM_PROMPT',
       jsonb_build_object('provider','Google Gemini','model_env','GEMINI_MODEL','purpose','Semantic extraction and evidence citation from MoU source text','structured_output',true,'deterministic_reconciliation',true),
       jsonb_build_object('note','LLM does not write engagement tables directly; authoritative database facts are reconciled after extraction.'),
       NULL, 'ACTIVE'
FROM agentops.agent a
WHERE a.code = 'A28_INDUSTRY_INTERACTION' AND a.status = 'ACTIVE'
  AND NOT EXISTS (SELECT 1 FROM agentops.model_version mv WHERE mv.agent_id = a.agent_id AND mv.version = 'mou-1.0');

-- Agent 4 deterministic recommendation model.
INSERT INTO agentops.model_version (model_version_id, agent_id, version, model_type, feature_list, excluded_features, validated_on, status)
SELECT gen_random_uuid(), a.agent_id, 'recommendation-1.0', 'RULE_BASED',
       '{"purpose":"Deterministic partner-level industry interaction recommendations","priority_bands":["CRITICAL","HIGH","MEDIUM","LOW"]}'::jsonb,
       '{"note":"No protected personal attributes are used. Student-level identifiers are not used in recommendation outputs."}'::jsonb,
       NULL, 'ACTIVE'
FROM agentops.agent a
WHERE a.code = 'A28_INDUSTRY_INTERACTION' AND a.status = 'ACTIVE'
  AND NOT EXISTS (SELECT 1 FROM agentops.model_version mv WHERE mv.agent_id = a.agent_id AND mv.version = 'recommendation-1.0');

INSERT INTO agentops.schedule (schedule_id, agent_id, cron_expression, scope, push_to_role_id, response_expected_hours, is_active, last_run_at, next_run_at)
VALUES (pg_temp.uid('schedule:A28:monthly'), pg_temp.uid('agent:A28'), '30 1 L * *',
        '{"sweep": ["health_snapshot","dormancy","mou_expiry","deliverable_risk","fulfilment_matching"]}',
        pg_temp.uid('role:INDUSTRY_RELATIONS'), 72, true, '2026-09-11 07:00+05:30', '2026-09-30 07:00+05:30');

CREATE TEMP TABLE t_run (key text PRIMARY KEY, run_at timestamptz, trigger_type text, job text, invoked_by text, parent text) ON COMMIT DROP;
INSERT INTO t_run VALUES
 ('match:2024-07-01', '2024-07-01 08:00+05:30', 'EVENT', 'COURSE_MATCHING', NULL, NULL),
 ('match:2024-12-16', '2024-12-16 08:00+05:30', 'EVENT', 'COURSE_MATCHING', NULL, NULL),
 ('match:2025-07-01', '2025-07-01 08:00+05:30', 'EVENT', 'COURSE_MATCHING', NULL, NULL),
 ('backfill:2025-09-01', '2025-09-01 10:00+05:30', 'USER', 'MOU_BACKFILL_AND_EVIDENCE_LINKING', 'iiic.head', NULL),
 ('match:2025-12-15', '2025-12-15 08:00+05:30', 'EVENT', 'COURSE_MATCHING', NULL, NULL),
 ('match:2026-07-01', '2026-07-01 08:00+05:30', 'EVENT', 'COURSE_MATCHING', NULL, NULL),
 ('match:2026-09-01', '2026-09-01 08:00+05:30', 'EVENT', 'COURSE_MATCHING', NULL, NULL),
 ('target:2026-09-08', '2026-09-08 11:30+05:30', 'USER', 'TARGET_PARTNER_ANALYSIS', 'iiic.head', NULL),
 ('alumni:2026-09-08', '2026-09-08 11:32+05:30', 'CHAINED', 'ALUMNI_PARTNER_RESOLUTION', NULL, 'target:2026-09-08');
INSERT INTO t_run
SELECT 'sweep:' || d::date, (d::date + time '07:00') AT TIME ZONE 'Asia/Kolkata', 'SCHEDULED', 'MONTHLY_HEALTH_SWEEP', NULL, NULL
FROM (SELECT (date_trunc('month', m) + interval '1 month - 1 day') AS d
      FROM generate_series('2025-09-01'::date, '2026-08-01'::date, interval '1 month') AS m) x;
INSERT INTO t_run VALUES ('sweep:2026-09-11', '2026-09-11 07:00+05:30', 'USER', 'MONTHLY_HEALTH_SWEEP', 'iiic.exec', NULL);

INSERT INTO agentops.agent_run (agent_run_id, agent_id, agent_version, trigger_type, parent_run_id, invoked_by_user_id, effective_role_id,
                                scope, request_text, started_at, finished_at, latency_ms, token_input, token_output, cost_estimate, status)
SELECT pg_temp.uid('run:' || r.key), pg_temp.uid('agent:A28'), CASE WHEN r.run_at < '2025-09-01' THEN '1.0' WHEN r.run_at < '2026-06-01' THEN '1.1' ELSE '1.2' END,
       r.trigger_type, CASE WHEN r.parent IS NOT NULL THEN pg_temp.uid('run:' || r.parent) END,
       CASE WHEN r.invoked_by IS NOT NULL THEN pg_temp.uid('user:' || r.invoked_by) END,
       CASE WHEN r.invoked_by IS NOT NULL THEN pg_temp.uid('role:INDUSTRY_RELATIONS') ELSE pg_temp.uid('role:SYSTEM') END,
       jsonb_build_object('institution_id', pg_temp.uid('inst:DIET'), 'job', r.job,
                          'as_of_date', (r.run_at AT TIME ZONE 'Asia/Kolkata')::date),
       CASE r.job WHEN 'TARGET_PARTNER_ANALYSIS' THEN 'Which companies should we approach for new partnerships this year?'
                  WHEN 'MOU_BACKFILL_AND_EVIDENCE_LINKING' THEN 'Digitise all signed MoUs and link existing activity evidence to deliverables.'
                  WHEN 'MONTHLY_HEALTH_SWEEP' THEN CASE WHEN r.invoked_by IS NOT NULL THEN 'Refresh partner health before the IIIC review meeting.' END END,
       r.run_at, r.run_at + interval '1 second' * (20 + floor(pg_temp.rnd('lat:' || r.key) * 140)),
       (20000 + floor(pg_temp.rnd('lat:' || r.key) * 140000))::int,
       CASE WHEN r.job IN ('TARGET_PARTNER_ANALYSIS','COURSE_MATCHING','MOU_BACKFILL_AND_EVIDENCE_LINKING') THEN (40000 + floor(pg_temp.rnd('tin:' || r.key) * 60000))::int END,
       CASE WHEN r.job IN ('TARGET_PARTNER_ANALYSIS','COURSE_MATCHING','MOU_BACKFILL_AND_EVIDENCE_LINKING') THEN (5000 + floor(pg_temp.rnd('tout:' || r.key) * 9000))::int END,
       CASE WHEN r.job IN ('TARGET_PARTNER_ANALYSIS','COURSE_MATCHING','MOU_BACKFILL_AND_EVIDENCE_LINKING') THEN round((0.2 + pg_temp.rnd('cost:' || r.key) * 0.9)::numeric, 4) END,
       'SUCCEEDED'
FROM t_run r;

-- ---------------------------------------------------------------------
-- 6.2 Industry activities (generated from the partner master)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_mix ON COMMIT DROP AS
SELECT p.key AS partner, split_part(x.item, ':', 1) AS atype, split_part(x.item, ':', 2)::int AS w
FROM t_partner p CROSS JOIN LATERAL unnest(string_to_array(p.mix, ',')) AS x(item)
WHERE p.mix IS NOT NULL;

CREATE TEMP TABLE t_act (k text PRIMARY KEY, partner text, mou_key text, atype text, dt date, end_dt date, status text, dept text, planned boolean) ON COMMIT DROP;

-- past activities, evenly spread across each partner's active window, last one pinned to act_end
WITH slots AS (
  SELECT p.key AS partner, p.dept, p.dept2, p.act_start, p.act_end, g.k,
         GREATEST(1, round(p.intensity * (p.act_end - p.act_start) / 365.0))::int AS n
  FROM t_partner p
  CROSS JOIN LATERAL generate_series(1, GREATEST(1, round(p.intensity * (p.act_end - p.act_start) / 365.0))::int) AS g(k)
  WHERE p.intensity > 0 AND p.act_start IS NOT NULL
), dated AS (
  SELECT s.*,
         CASE WHEN s.k = s.n THEN s.act_end
              ELSE LEAST(s.act_end - 1, GREATEST(s.act_start,
                   s.act_start + floor((s.k - 0.5) * (s.act_end - s.act_start) / s.n + (pg_temp.rnd('jit:' || s.partner || s.k) - 0.5) * 20)::int)) END AS d0
  FROM slots s
), shifted AS (   -- move activities out of institution-wide exam / holiday / vacation blocks
  SELECT d.*, COALESCE((
           SELECT COALESCE(ce.end_date, ce.event_date) + 2
           FROM core.calendar_event ce
           WHERE ce.blocks_instruction AND d.d0 BETWEEN ce.event_date AND COALESCE(ce.end_date, ce.event_date)
           ORDER BY ce.event_date LIMIT 1), d.d0) AS d1
  FROM dated d
)
INSERT INTO t_act (k, partner, atype, dt, status, dept, planned)
SELECT 'act:' || s.partner || ':' || s.k, s.partner, t.atype,
       CASE WHEN s.k = s.n THEN s.d1 ELSE LEAST(s.d1 + CASE WHEN extract(dow FROM s.d1) = 0 THEN 1 ELSE 0 END, s.act_end) END,
       CASE WHEN s.k <> s.n AND t.atype IN ('GUEST_LECTURE','EXPERT_TALK','INDUSTRY_VISIT') AND pg_temp.rnd('st:' || s.partner || s.k) < 0.04 THEN 'CANCELLED'
            WHEN s.k <> s.n AND t.atype IN ('GUEST_LECTURE','EXPERT_TALK','INDUSTRY_VISIT') AND pg_temp.rnd('st:' || s.partner || s.k) < 0.06 THEN 'POSTPONED'
            ELSE 'CONDUCTED' END,
       CASE WHEN pg_temp.rnd('dp:' || s.partner || s.k) < 0.8 THEN s.dept ELSE s.dept2 END,
       false
FROM shifted s
CROSS JOIN LATERAL (
  SELECT m.atype FROM (
    SELECT atype, sum(w) OVER (ORDER BY atype) AS cum, sum(w) OVER () AS tot FROM t_mix WHERE partner = s.partner
  ) m
  WHERE m.cum > pg_temp.rnd('ty:' || s.partner || ':' || s.k) * m.tot
  ORDER BY m.cum LIMIT 1
) t;

-- upcoming activities (the activity calendar): six partners fill the lesson-plan GUEST slot on 21 Sep 2026
INSERT INTO t_act (k, partner, atype, dt, status, dept, planned)
SELECT 'act:' || p.key || ':plan' || g.j, p.key,
       CASE WHEN g.j = 1 AND p.key IN ('QUANTLOOM','SECUREGRID','SILICONDELTA','DYNAMOTIVE','KAVERIYAN','SHILPAKAR') THEN 'GUEST_LECTURE'
            ELSE (SELECT m.atype FROM (SELECT atype, sum(w) OVER (ORDER BY atype) AS cum, sum(w) OVER () AS tot FROM t_mix WHERE partner = p.key) m
                  WHERE m.cum > pg_temp.rnd('pty:' || p.key || g.j) * m.tot ORDER BY m.cum LIMIT 1) END,
       CASE WHEN g.j = 1 AND p.key IN ('QUANTLOOM','SECUREGRID','SILICONDELTA','DYNAMOTIVE','KAVERIYAN','SHILPAKAR') THEN DATE '2026-09-21'
            WHEN g.j = 1 THEN DATE '2026-09-22' + floor(pg_temp.rnd('pd:' || p.key) * 40)::int
            ELSE DATE '2026-10-19' + floor(pg_temp.rnd('pd2:' || p.key) * 45)::int END,
       CASE WHEN g.j = 1 AND p.key IN ('QUANTLOOM','SECUREGRID','SILICONDELTA','DYNAMOTIVE','KAVERIYAN','SHILPAKAR') THEN 'CONFIRMED'
            WHEN pg_temp.rnd('pst:' || p.key || g.j) < 0.5 THEN 'CONFIRMED' ELSE 'PLANNED' END,
       p.dept, true
FROM t_partner p
CROSS JOIN LATERAL generate_series(1, CASE WHEN p.intensity >= 6 THEN 2 ELSE 1 END) AS g(j)
WHERE p.status = 'ACTIVE' AND p.intensity >= 3 AND p.act_end >= '2026-07-01';

-- a prospect with an expert talk but no MoU yet, and activities under non-industry MoUs
INSERT INTO t_act (k, partner, mou_key, atype, dt, end_dt, status, dept, planned) VALUES
 ('act:LEDGERLEAF:1', 'LEDGERLEAF', NULL, 'EXPERT_TALK',     '2026-07-10', NULL,         'CONDUCTED', 'IT',   false),
 ('act:M32:1',        NULL,         'M32', 'FACULTY_EXCHANGE','2025-05-19', '2025-06-13', 'CONDUCTED', 'CSE',  false),
 ('act:M32:2',        NULL,         'M32', 'FACULTY_EXCHANGE','2026-05-18', '2026-06-12', 'CONDUCTED', 'IT',   false),
 ('act:M35:1',        NULL,         'M35', 'FACULTY_EXCHANGE','2026-06-01', '2026-06-26', 'CONDUCTED', 'MECH', false),
 ('act:M33:1',        NULL,         'M33', 'SPONSORED_PROJECT','2025-03-03', NULL,        'CONDUCTED', 'CIVIL',false);

-- attach the MoU in force on the activity date (latest signed); multi-week exchanges get an end date
UPDATE t_act a
SET mou_key = (SELECT m.key FROM t_mou m
               WHERE m.partner = a.partner AND m.status <> 'DRAFT'
                 AND m.signed_on <= a.dt AND a.dt BETWEEN m.valid_from AND m.valid_until
               -- prefer the MoU that actually commits to this kind of activity, then the newest
               ORDER BY EXISTS (SELECT 1 FROM t_mou_deliv d WHERE d.mou = m.key AND d.dtype = ANY (
                          CASE a.atype WHEN 'GUEST_LECTURE' THEN ARRAY['GUEST_LECTURE','EXPERT_TALK']
                                       WHEN 'EXPERT_TALK' THEN ARRAY['EXPERT_TALK','GUEST_LECTURE']
                                       WHEN 'INTERNSHIP_DRIVE' THEN ARRAY['INTERNSHIP']
                                       ELSE ARRAY[a.atype] END)) DESC,
                        m.valid_from DESC LIMIT 1),
    end_dt = CASE WHEN a.atype = 'FACULTY_EXCHANGE' THEN a.dt + 20
                  WHEN a.atype = 'INDUSTRY_VISIT' AND pg_temp.rnd('ev2:' || a.k) < 0.2 THEN a.dt + 1 END
WHERE a.partner IS NOT NULL;

-- best curriculum match per activity: expertise area vs topic title (pg_trgm similarity)
CREATE TEMP TABLE t_match ON COMMIT DROP AS
SELECT DISTINCT ON (a.k)
       a.k, c.short_title AS ccode, cv.course_version_id, u.course_unit_id, t.course_topic_id, t.title AS topic_title,
       e.partner_expertise_id, e.area, similarity(lower(e.area), lower(t.title)) AS sim,
       CASE WHEN a.dt >= '2026-06-01' THEN '2026-27' WHEN a.dt >= '2025-06-01' THEN '2025-26' ELSE '2024-25' END AS ay
FROM t_act a
JOIN engagement.partner_expertise e ON e.industry_partner_id = pg_temp.uid('partner:' || a.partner)
JOIN curriculum.course c ON c.owning_department_id = pg_temp.uid('dept:' || a.dept)
JOIN curriculum.course_version cv ON cv.course_id = c.course_id
 AND cv.regulation_id = pg_temp.uid(CASE WHEN a.dt >= '2026-06-01' THEN 'reg:R23' ELSE 'reg:R20' END)
JOIN curriculum.course_unit u ON u.course_version_id = cv.course_version_id
JOIN curriculum.course_topic t ON t.course_unit_id = u.course_unit_id
WHERE a.atype IN ('GUEST_LECTURE','EXPERT_TALK','INDUSTRY_VISIT','SPONSORED_PROJECT','CONSULTANCY')
ORDER BY a.k, round(similarity(lower(e.area), lower(t.title))::numeric, 2) DESC,
         -- tie-break: a topic the current lesson plan reserves for a GUEST session
         EXISTS (SELECT 1 FROM academics.lesson_plan_session s
                 WHERE s.course_topic_id = t.course_topic_id AND s.teaching_method = 'GUEST' AND a.dt >= '2026-07-01') DESC,
         t.course_topic_id;

-- research projects for sponsored projects and consultancy
INSERT INTO research.funding_agency (funding_agency_id, code, name, agency_type, portal_url)
SELECT DISTINCT pg_temp.uid('agency:' || COALESCE(a.partner, a.mou_key)), 'IND-' || COALESCE(a.partner, a.mou_key),
       COALESCE(p.name, m.partner_name), CASE WHEN a.partner IS NULL THEN 'CENTRAL' ELSE 'INDUSTRY' END, NULL
FROM t_act a LEFT JOIN t_partner p ON p.key = a.partner LEFT JOIN t_mou m ON m.key = a.mou_key
WHERE a.atype IN ('SPONSORED_PROJECT','CONSULTANCY') AND a.status = 'CONDUCTED';

INSERT INTO research.project (project_id, proposal_id, funding_agency_id, title, sanction_no, pi_faculty_id, sanctioned_amount, received_amount,
                              start_date, end_date, project_type, status)
SELECT pg_temp.uid('project:' || a.k), NULL, pg_temp.uid('agency:' || COALESCE(a.partner, a.mou_key)),
       CASE a.atype WHEN 'CONSULTANCY' THEN 'Consultancy: ' ELSE 'Sponsored project: ' END || COALESCE(mt.topic_title, mt.area, 'geospatial analytics for urban drainage'),
       upper(COALESCE(a.partner, a.mou_key)) || '/' || to_char(a.dt, 'YYYY') || '/' || lpad((floor(pg_temp.rnd('sn:' || a.k) * 900) + 100)::int::text, 3, '0'),
       pg_temp.uid('fac:' || a.dept || ':' || (1 + floor(pg_temp.rnd('pi:' || a.k) * 3))::int),
       round(CASE a.atype WHEN 'CONSULTANCY' THEN 150000 + pg_temp.rnd('amt:' || a.k) * 650000 ELSE 300000 + pg_temp.rnd('amt:' || a.k) * 1200000 END, -3),
       round(CASE a.atype WHEN 'CONSULTANCY' THEN 150000 + pg_temp.rnd('amt:' || a.k) * 650000 ELSE 300000 + pg_temp.rnd('amt:' || a.k) * 1200000 END
             * CASE WHEN a.dt + 365 < DATE '2026-09-11' THEN 1 ELSE 0.6 END, -3),
       a.dt, a.dt + 365,
       CASE a.atype WHEN 'CONSULTANCY' THEN 'CONSULTANCY' ELSE 'INDUSTRY' END,
       CASE WHEN a.dt + 365 < DATE '2026-09-11' THEN 'COMPLETED' ELSE 'ACTIVE' END
FROM t_act a LEFT JOIN t_match mt ON mt.k = a.k
WHERE a.atype IN ('SPONSORED_PROJECT','CONSULTANCY') AND a.status = 'CONDUCTED';

-- activity report documents (evidence) for most conducted activities
INSERT INTO knowledge.document (document_id, institution_id, title, document_class, mime_type, storage_uri, content_hash, page_count,
                                language, owner_role_id, sensitivity, is_retrievable_by_agents, uploaded_at)
SELECT pg_temp.uid('doc:report:' || a.k), pg_temp.uid('inst:DIET'),
       'Activity report – ' || a.atype || ' – ' || COALESCE(a.partner, a.mou_key) || ' – ' || a.dt,
       'REPORT', 'application/pdf', 'storage://activity-reports/' || replace(a.k, ':', '-') || '.pdf',
       'md5:' || md5('report:' || a.k), 2 + floor(pg_temp.rnd('pg:' || a.k) * 6)::int, 'en',
       pg_temp.uid('role:INDUSTRY_RELATIONS'), 'NORMAL', true, (a.dt + 3)::timestamptz
FROM t_act a
WHERE a.status = 'CONDUCTED' AND a.dt <= '2026-09-06'
  AND (a.atype IN ('SPONSORED_PROJECT','CONSULTANCY','LAB_SUPPORT') OR pg_temp.rnd('rep:' || a.k) < 0.7);

INSERT INTO engagement.industry_activity (industry_activity_id, industry_partner_id, mou_id, department_id, activity_type, title, activity_date,
       course_version_id, participant_count, feedback_summary, evidence_ref, status, end_date, mode, outcome_summary, support_value, research_project_id, created_at)
SELECT pg_temp.uid(a.k),
       CASE WHEN a.partner IS NOT NULL THEN pg_temp.uid('partner:' || a.partner) END,
       CASE WHEN a.mou_key IS NOT NULL THEN pg_temp.uid('mou:' || a.mou_key) END,
       pg_temp.uid('dept:' || a.dept), a.atype,
       CASE a.atype
         WHEN 'GUEST_LECTURE'     THEN 'Guest lecture: ' || COALESCE(CASE WHEN mt.sim >= 0.2 THEN mt.topic_title END, mt.area, 'industry practice') || ' in practice'
         WHEN 'EXPERT_TALK'       THEN 'Expert talk: ' || COALESCE(CASE WHEN mt.sim >= 0.2 THEN mt.topic_title END, mt.area, 'careers in ' || lower(replace(COALESCE(p.sector, 'industry'), '_', ' ')))
         WHEN 'INDUSTRY_VISIT'    THEN 'Industry visit to ' || p.name || COALESCE(' – ' || CASE WHEN mt.sim >= 0.2 THEN mt.topic_title END, '')
         WHEN 'INTERNSHIP_DRIVE'  THEN p.name || ' internship drive ' || extract(year FROM a.dt)
         WHEN 'FACULTY_EXCHANGE'  THEN 'Faculty industry immersion at ' || COALESCE(p.name, m.partner_name)
         WHEN 'LAB_SUPPORT'       THEN p.name || ' laboratory support: ' || (ARRAY['licences and cloud credits','test equipment','training kits','software subscriptions'])[1 + floor(pg_temp.rnd('ls:' || a.k) * 4)::int]
         WHEN 'SPONSORED_PROJECT' THEN 'Sponsored project: ' || COALESCE(mt.topic_title, mt.area, 'geospatial analytics for urban drainage')
         WHEN 'CONSULTANCY'       THEN 'Consultancy for ' || p.name || ': ' || COALESCE(mt.topic_title, mt.area)
       END,
       a.dt,
       CASE WHEN mt.sim >= 0.2 THEN mt.course_version_id END,
       CASE a.atype
         WHEN 'GUEST_LECTURE' THEN 40 + floor(pg_temp.rnd('pc:' || a.k) * 80)::int
         WHEN 'EXPERT_TALK' THEN 30 + floor(pg_temp.rnd('pc:' || a.k) * 70)::int
         WHEN 'INDUSTRY_VISIT' THEN 25 + floor(pg_temp.rnd('pc:' || a.k) * 40)::int
         WHEN 'INTERNSHIP_DRIVE' THEN 60 + floor(pg_temp.rnd('pc:' || a.k) * 100)::int
         WHEN 'FACULTY_EXCHANGE' THEN 1 + floor(pg_temp.rnd('pc:' || a.k) * 2)::int
         WHEN 'SPONSORED_PROJECT' THEN 3 + floor(pg_temp.rnd('pc:' || a.k) * 6)::int
       END * CASE WHEN a.status = 'CONDUCTED' THEN 1 ELSE NULL END,
       NULL,
       CASE WHEN d.document_id IS NOT NULL THEN d.document_id END,
       CASE WHEN a.planned THEN a.status ELSE a.status END,
       a.end_dt,
       CASE WHEN a.atype = 'GUEST_LECTURE' AND pg_temp.rnd('md:' || a.k) < 0.2 THEN 'ONLINE'
            WHEN a.atype = 'EXPERT_TALK' AND pg_temp.rnd('md:' || a.k) < 0.5 THEN 'ONLINE'
            WHEN a.atype IN ('GUEST_LECTURE','EXPERT_TALK') AND pg_temp.rnd('md2:' || a.k) < 0.1 THEN 'HYBRID'
            ELSE 'OFFLINE' END,
       CASE WHEN a.status <> 'CONDUCTED' THEN
              CASE a.status WHEN 'CANCELLED' THEN 'Cancelled: resource person unavailable; not rescheduled.'
                            WHEN 'POSTPONED' THEN 'Postponed at partner''s request; to be rescheduled.' END
            ELSE CASE a.atype
              WHEN 'GUEST_LECTURE'     THEN 'Session linked to ' || COALESCE(mt.ccode, 'the elective') || '; two mini-project problem statements shared with the course faculty.'
              WHEN 'EXPERT_TALK'       THEN 'Talk on current industry practice; partner offered to review capstone ideas.'
              WHEN 'INDUSTRY_VISIT'    THEN 'Students observed live operations and safety practices; visit report submitted by coordinator.'
              WHEN 'INTERNSHIP_DRIVE'  THEN 'Drive conducted on campus; shortlisted candidates recorded by the placement cell.'
              WHEN 'FACULTY_EXCHANGE'  THEN 'Faculty member completed immersion; one laboratory exercise redesigned around industry workflow.'
              WHEN 'LAB_SUPPORT'       THEN 'Support received and installed; utilisation log started.'
              WHEN 'SPONSORED_PROJECT' THEN 'Project sanctioned; student team formed under a faculty PI.'
              WHEN 'CONSULTANCY'       THEN 'Assignment delivered; report accepted by partner.'
            END END,
       CASE WHEN a.atype = 'LAB_SUPPORT' AND a.status = 'CONDUCTED' THEN round(150000 + pg_temp.rnd('sv:' || a.k) * 2350000, -3) END,
       CASE WHEN a.atype IN ('SPONSORED_PROJECT','CONSULTANCY') AND a.status = 'CONDUCTED' THEN pg_temp.uid('project:' || a.k) END,
       (LEAST(a.dt, DATE '2026-09-10') - CASE WHEN a.planned THEN 25 ELSE 0 END)::timestamptz
FROM t_act a
LEFT JOIN t_partner p ON p.key = a.partner
LEFT JOIN t_mou m ON m.key = a.mou_key
LEFT JOIN t_match mt ON mt.k = a.k
LEFT JOIN knowledge.document d ON d.document_id = pg_temp.uid('doc:report:' || a.k);

-- course alignment rows (Agent 28 suggestions, confirmed by the HoD for past activities)
INSERT INTO engagement.activity_course_alignment (activity_course_alignment_id, industry_activity_id, course_version_id, course_unit_id, course_topic_id,
       course_offering_id, lesson_plan_session_id, partner_expertise_id, is_primary, alignment_source, match_score, match_rationale, status,
       agent_run_id, confirmed_by_user_id, confirmed_at)
SELECT pg_temp.uid('align:' || a.k), pg_temp.uid(a.k), mt.course_version_id,
       CASE WHEN mt.sim >= 0.2 THEN mt.course_unit_id END,
       CASE WHEN mt.sim >= 0.2 THEN mt.course_topic_id END,
       CASE WHEN a.dt BETWEEN tm.start_date AND tm.end_date THEN pg_temp.uid('off:' || mt.ay || ':' || mt.ccode) END,
       CASE WHEN mt.ay = '2026-27' AND a.dt BETWEEN tm.start_date AND tm.end_date THEN (
            SELECT s.lesson_plan_session_id FROM academics.lesson_plan_session s
            WHERE s.lesson_plan_id = pg_temp.uid('lp:2026-27:' || mt.ccode) AND s.course_topic_id = mt.course_topic_id AND s.teaching_method = 'GUEST') END,
       mt.partner_expertise_id,
       mt.sim >= 0.2,
       'AGENT_SUGGESTED',
       round((mt.sim * 100)::numeric, 2),
       CASE WHEN mt.sim >= 0.2
            THEN format('Partner expertise "%s" matches %s topic "%s" (trigram similarity %s)%s.', mt.area, mt.ccode, mt.topic_title, round(mt.sim::numeric, 2),
                        CASE WHEN a.dt BETWEEN tm.start_date AND tm.end_date THEN ', taught in ' || tm.label ELSE ', outside the teaching term' END)
            ELSE format('Weak match: best available topic "%s" in %s (similarity %s). Rejected by department.', mt.topic_title, mt.ccode, round(mt.sim::numeric, 2)) END,
       CASE WHEN mt.sim < 0.2 THEN 'REJECTED'
            WHEN a.planned AND a.dt <> '2026-09-21' THEN 'SUGGESTED'
            ELSE 'CONFIRMED' END,
       pg_temp.uid('run:' || (SELECT r.key FROM t_run r WHERE r.job = 'COURSE_MATCHING' AND (r.run_at AT TIME ZONE 'Asia/Kolkata')::date <= GREATEST(a.dt - 20, DATE '2024-07-01') ORDER BY r.run_at DESC LIMIT 1)),
       CASE WHEN mt.sim < 0.2 OR NOT a.planned OR a.dt = '2026-09-21' THEN pg_temp.uid('user:hod.' || lower(a.dept)) END,
       CASE WHEN mt.sim < 0.2 OR NOT a.planned OR a.dt = '2026-09-21'
            THEN (GREATEST(LEAST(a.dt - 10, DATE '2026-09-03'), DATE '2024-07-02'))::timestamptz END
FROM t_act a
JOIN t_match mt ON mt.k = a.k
JOIN core.term tm ON tm.term_id = pg_temp.uid('term:ODD ' || mt.ay);

-- activity participants: resource persons, hosts, coordinators, faculty on exchange
CREATE TEMP TABLE t_act_contact ON COMMIT DROP AS
SELECT a.k, a.atype, a.dt, a.status, a.dept,
       (SELECT pc.person_id FROM engagement.partner_contact pc
         WHERE pc.industry_partner_id = pg_temp.uid('partner:' || a.partner) AND pc.contact_role = 'TECHNICAL'
           AND pc.valid_from <= a.dt AND (pc.valid_to IS NULL OR pc.valid_to >= a.dt) LIMIT 1) AS tech,
       (SELECT pc.person_id FROM engagement.partner_contact pc
         WHERE pc.industry_partner_id = pg_temp.uid('partner:' || a.partner) AND pc.contact_role = 'SPOC'
           AND pc.valid_from <= a.dt AND (pc.valid_to IS NULL OR pc.valid_to >= a.dt) LIMIT 1) AS spoc,
       (SELECT pc.person_id FROM engagement.partner_contact pc
         WHERE pc.industry_partner_id = pg_temp.uid('partner:' || a.partner) AND pc.contact_role = 'HR' LIMIT 1) AS hr,
       (SELECT pc.person_id FROM engagement.partner_contact pc
         WHERE pc.industry_partner_id = pg_temp.uid('partner:' || a.partner) AND pc.contact_role = 'ALUMNI_CHAMPION'
           AND pc.valid_from <= a.dt LIMIT 1) AS alum
FROM t_act a WHERE a.partner IS NOT NULL;

INSERT INTO engagement.industry_activity_person (industry_activity_id, person_id, participation_role, attended)
SELECT DISTINCT ON (x.act, x.person, x.role) x.act, x.person, x.role, x.attended
FROM (
  SELECT pg_temp.uid(c.k) AS act,
         CASE WHEN c.alum IS NOT NULL AND pg_temp.rnd('alrp:' || c.k) < 0.3 THEN c.alum ELSE COALESCE(c.tech, c.spoc) END AS person,
         'RESOURCE_PERSON' AS role,
         CASE c.status WHEN 'CONDUCTED' THEN true WHEN 'CANCELLED' THEN false END AS attended
  FROM t_act_contact c WHERE c.atype IN ('GUEST_LECTURE','EXPERT_TALK') AND COALESCE(c.tech, c.spoc) IS NOT NULL
  UNION ALL
  SELECT pg_temp.uid(c.k), COALESCE(c.spoc, c.tech), 'INDUSTRY_HOST', CASE c.status WHEN 'CONDUCTED' THEN true WHEN 'CANCELLED' THEN false END
  FROM t_act_contact c WHERE c.atype IN ('INDUSTRY_VISIT','FACULTY_EXCHANGE','LAB_SUPPORT') AND COALESCE(c.spoc, c.tech) IS NOT NULL
  UNION ALL
  SELECT pg_temp.uid(c.k), COALESCE(c.hr, c.spoc), 'INDUSTRY_HOST', CASE c.status WHEN 'CONDUCTED' THEN true END
  FROM t_act_contact c WHERE c.atype = 'INTERNSHIP_DRIVE' AND COALESCE(c.hr, c.spoc) IS NOT NULL
) x WHERE x.person IS NOT NULL;

INSERT INTO engagement.industry_activity_person (industry_activity_id, person_id, participation_role, attended)
SELECT pg_temp.uid(a.k), pg_temp.uid('person:fac:' || a.dept || ':' || (2 + floor(pg_temp.rnd('coord:' || a.k) * 5))::int), 'FACULTY_COORDINATOR',
       CASE a.status WHEN 'CONDUCTED' THEN true WHEN 'CANCELLED' THEN false END
FROM t_act a WHERE a.atype <> 'FACULTY_EXCHANGE';

INSERT INTO engagement.industry_activity_person (industry_activity_id, person_id, participation_role, attended)
SELECT DISTINCT pg_temp.uid(a.k), pg_temp.uid('person:fac:' || a.dept || ':' || (3 + floor(pg_temp.rnd('fx:' || a.k || g.i) * 4))::int), 'FACULTY_PARTICIPANT', true
FROM t_act a CROSS JOIN generate_series(1, 2) AS g(i)
WHERE a.atype = 'FACULTY_EXCHANGE' AND (g.i = 1 OR pg_temp.rnd('fx2:' || a.k) < 0.4);

-- senior alumni who delivered sessions also appear as alumni contributions (Agent 52 data; double counting is avoided by person_id)
INSERT INTO placement.alumni_contribution (alumni_contribution_id, alumni_id, contribution_type, description, contributed_on, value, acknowledged)
SELECT pg_temp.uid('contrib:gl:' || iap.industry_activity_id), al.alumni_id, 'GUEST_LECTURE',
       'Delivered: ' || ia.title, ia.activity_date, NULL, ia.activity_date < '2026-06-01'
FROM engagement.industry_activity_person iap
JOIN engagement.industry_activity ia ON ia.industry_activity_id = iap.industry_activity_id AND ia.status = 'CONDUCTED'
JOIN placement.alumni al ON al.person_id = iap.person_id
WHERE iap.participation_role = 'RESOURCE_PERSON';

INSERT INTO placement.alumni_contribution (alumni_contribution_id, alumni_id, contribution_type, description, contributed_on, value, acknowledged)
SELECT pg_temp.uid('contrib:' || a.k || ':' || g.i), pg_temp.uid(a.k),
       (ARRAY['MENTORING','PLACEMENT_REFERRAL','INTERNSHIP_HOST','FINANCIAL','EQUIPMENT','SCHOLARSHIP_FUNDING','COLLABORATION'])[1 + ((a.i + g.i) % 7)],
       (ARRAY['Mentored final-year project team','Referred students for campus hiring','Hosted interns in own team','Donation to department development fund',
              'Donated test equipment to laboratory','Funded merit scholarship','Co-authored applied research paper with faculty'])[1 + ((a.i + g.i) % 7)],
       DATE '2024-08-01' + floor(pg_temp.rnd('cdate:' || a.k || g.i) * 750)::int,
       CASE WHEN (a.i + g.i) % 7 IN (3,4,5) THEN round(25000 + pg_temp.rnd('cval:' || a.k || g.i) * 175000, -3) END,
       pg_temp.rnd('ack:' || a.k || g.i) < 0.7
FROM t_senior_alumni a CROSS JOIN generate_series(1, 2) AS g(i)
WHERE (a.i % 3) <> 0 AND (g.i = 1 OR a.i % 5 = 0);

-- ---------------------------------------------------------------------
-- 6.3 Events co-organised with partners (evidence for TRAINING_PROGRAMME deliverables)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_event (key text PRIMARY KEY, mou text, etype text, title text, s date, e date, dept text, target int) ON COMMIT DROP;
INSERT INTO t_event VALUES
 ('E01','M02','BOOTCAMP','Cloud-Native Bootcamp (with Nimbus CloudWorks)','2025-01-20','2025-01-24','CSE',120),
 ('E02','M02','FDP','Kubernetes for Educators FDP (with Nimbus CloudWorks)','2026-06-01','2026-06-05','CSE',40),
 ('E03','M38','WORKSHOP','Cloud Lab Inauguration Workshop','2025-02-10','2025-02-10','CSE',80),
 ('E04','M05','HACKATHON','Capture-the-Flag Hackathon (with SecureGrid)','2025-03-08','2025-03-09','IT',150),
 ('E05','M36','STTP','VLSI Verification STTP (with Silicon Delta)','2026-05-18','2026-05-29','ECE',45),
 ('E06','M09','WORKSHOP','Embedded Systems Hands-on Workshop (with VoltEdge)','2025-01-10','2025-01-10','ECE',60),
 ('E07','M19','WORKSHOP','BIM for Engineers Workshop (with BIMCraft)','2024-10-05','2024-10-05','CIVIL',70),
 ('E08','M19','FDP','Digital Construction FDP (with BIMCraft)','2025-06-09','2025-06-13','CIVIL',35),
 ('E09','M32','FDP','Advanced Computing FDP (with Demo State Technological University)','2025-06-02','2025-06-06','CSE',50),
 ('E10','M34','WORKSHOP','Skill Mission Certification Drive','2024-08-20','2024-08-22','EEE',200),
 ('E11','M34','FDP','Skill Mission Train-the-Trainer Programme','2025-07-14','2025-07-18','EEE',40),
 ('E12','M22','HACKATHON','GenAI Hackathon (with QuantLoom AI Labs)','2026-02-21','2026-02-22','CSE',180);

INSERT INTO engagement.event (event_id, institution_id, department_id, event_type, title, from_date, to_date, mode, coordinator_faculty_id,
                              funding_source, budget_sanctioned, expenditure, participant_target, status, report_ref)
SELECT pg_temp.uid('event:' || e.key), pg_temp.uid('inst:DIET'), pg_temp.uid('dept:' || e.dept), e.etype, e.title, e.s, e.e, 'OFFLINE',
       pg_temp.uid('fac:' || e.dept || ':' || (2 + floor(pg_temp.rnd('ecoord:' || e.key) * 5))::int),
       'Partner sponsored', round(50000 + pg_temp.rnd('eb:' || e.key) * 250000, -3), round(40000 + pg_temp.rnd('eb:' || e.key) * 230000, -3),
       e.target, 'COMPLETED', NULL
FROM t_event e;

-- ---------------------------------------------------------------------
-- 6.4 Placement: offers, job openings, internships, evaluations, recent-graduate alumni
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_prog_sector (dept text, sector text, w numeric) ON COMMIT DROP;
INSERT INTO t_prog_sector VALUES
 ('CSE','IT_SERVICES',30),('CSE','SOFTWARE_PRODUCT',20),('CSE','BFSI',18),('CSE','CONSULTING_ANALYTICS',18),('CSE','OTHER',6),('CSE','TELECOM',2),('CSE','PHARMA_HEALTHCARE',4),('CSE','ELECTRONICS_SEMICON',2),
 ('IT','IT_SERVICES',32),('IT','SOFTWARE_PRODUCT',14),('IT','BFSI',26),('IT','CONSULTING_ANALYTICS',16),('IT','OTHER',8),('IT','PHARMA_HEALTHCARE',4),
 ('ECE','ELECTRONICS_SEMICON',26),('ECE','IT_SERVICES',28),('ECE','TELECOM',8),('ECE','CONSULTING_ANALYTICS',10),('ECE','BFSI',10),('ECE','PHARMA_HEALTHCARE',8),('ECE','SOFTWARE_PRODUCT',6),('ECE','AUTOMOTIVE',4),
 ('EEE','ENERGY_POWER',16),('EEE','AUTOMOTIVE',20),('EEE','CORE_MECHANICAL',10),('EEE','IT_SERVICES',25),('EEE','GOVERNMENT_PSU',8),('EEE','ELECTRONICS_SEMICON',7),('EEE','BFSI',14),
 ('MECH','AUTOMOTIVE',28),('MECH','CORE_MECHANICAL',24),('MECH','IT_SERVICES',22),('MECH','CONSULTING_ANALYTICS',10),('MECH','BFSI',10),('MECH','GOVERNMENT_PSU',3),('MECH','CONSTRUCTION_INFRA',3),
 ('CIVIL','CONSTRUCTION_INFRA',42),('CIVIL','GOVERNMENT_PSU',12),('CIVIL','IT_SERVICES',20),('CIVIL','CONSULTING_ANALYTICS',12),('CIVIL','BFSI',9),('CIVIL','ENERGY_POWER',5);

-- which final-year batches each company could recruit from (MoU start / conclusion)
CREATE TEMP TABLE t_company_batch ON COMMIT DROP AS
SELECT c.key, b.yr
FROM t_company c CROSS JOIN (VALUES (2021),(2022),(2023)) AS b(yr)
WHERE NOT (c.key = 'ZENITHSOFT' AND b.yr > 2021)
  AND NOT (c.key = 'TARANG' AND b.yr > 2021)          -- Tarang stopped recruiting: part of its dormancy story
  AND NOT (c.key IN ('AROGYA','EKATVA','LEDGERLEAF','CLEARVIEW') AND b.yr < 2023)
  AND NOT (c.key IN ('QUANTLOOM','PAYSETU','ROBONEST') AND b.yr < 2022);

CREATE TEMP TABLE t_pool ON COMMIT DROP AS
WITH w AS (
  SELECT ps.dept, cb.yr, c.key AS company, c.partner_key,
         ps.w * c.w / sum(c.w) OVER (PARTITION BY ps.dept, cb.yr, c.sector) AS wt_offer
  FROM t_prog_sector ps
  JOIN t_company c ON c.sector = ps.sector
  JOIN t_company_batch cb ON cb.key = c.key
)
SELECT dept, yr, company, partner_key,
       (sum(wt_offer) OVER (PARTITION BY dept, yr ORDER BY company) - wt_offer) / sum(wt_offer) OVER (PARTITION BY dept, yr) AS lo,
       sum(wt_offer) OVER (PARTITION BY dept, yr ORDER BY company) / sum(wt_offer) OVER (PARTITION BY dept, yr) AS hi,
       (sum(wt_offer * CASE WHEN partner_key IS NOT NULL THEN 3 ELSE 1 END) OVER (PARTITION BY dept, yr ORDER BY company)
         - wt_offer * CASE WHEN partner_key IS NOT NULL THEN 3 ELSE 1 END)
         / sum(wt_offer * CASE WHEN partner_key IS NOT NULL THEN 3 ELSE 1 END) OVER (PARTITION BY dept, yr) AS ilo,
       sum(wt_offer * CASE WHEN partner_key IS NOT NULL THEN 3 ELSE 1 END) OVER (PARTITION BY dept, yr ORDER BY company)
         / sum(wt_offer * CASE WHEN partner_key IS NOT NULL THEN 3 ELSE 1 END) OVER (PARTITION BY dept, yr) AS ihi
FROM w;

CREATE TEMP TABLE t_offer ON COMMIT DROP AS
SELECT s.k AS student, s.dept, s.yr, p.company,
       CASE s.yr WHEN 2021 THEN DATE '2024-08-01' + floor(pg_temp.rnd('od:' || s.k) * 240)::int
                 WHEN 2022 THEN DATE '2025-08-01' + floor(pg_temp.rnd('od:' || s.k) * 240)::int
                 ELSE DATE '2026-07-15' + floor(pg_temp.rnd('od:' || s.k) * 52)::int END AS offer_date,
       CASE s.yr WHEN 2021 THEN '2024-25' WHEN 2022 THEN '2025-26' ELSE '2026-27' END AS ay,
       pg_temp.rnd('ost:' || s.k) AS r_status
FROM t_student s
JOIN t_pool p ON p.dept = s.dept AND p.yr = s.yr
 AND pg_temp.rnd('oc:' || s.k) >= p.lo AND pg_temp.rnd('oc:' || s.k) < p.hi
WHERE pg_temp.rnd('placed:' || s.k) < CASE s.yr WHEN 2021 THEN 0.80 WHEN 2022 THEN 0.76 ELSE 0.38 END
                                     - CASE WHEN s.dept IN ('MECH','CIVIL') THEN 0.12 ELSE 0 END;

INSERT INTO placement.job_opening (job_opening_id, company_id, academic_year_id, role_title, opening_type, job_description, required_skills,
                                   preferred_skills, eligibility, ctc_min, ctc_max, locations, positions_open, drive_date, application_deadline, status)
SELECT pg_temp.uid('job:ft:' || o.company || ':' || o.ay), pg_temp.uid('company:' || o.company), pg_temp.uid('ay:' || o.ay),
       CASE c.sector WHEN 'BFSI' THEN 'Graduate Analyst' WHEN 'CONSULTING_ANALYTICS' THEN 'Business Analyst' WHEN 'SOFTWARE_PRODUCT' THEN 'Software Engineer'
                     WHEN 'IT_SERVICES' THEN 'Associate Software Engineer' WHEN 'ELECTRONICS_SEMICON' THEN 'Design Engineer Trainee'
                     WHEN 'CONSTRUCTION_INFRA' THEN 'Graduate Engineer Trainee (Civil)' WHEN 'AUTOMOTIVE' THEN 'Graduate Engineer Trainee'
                     ELSE 'Graduate Engineer Trainee' END,
       'FULL_TIME', 'Campus recruitment for the ' || right(o.ay, 5) || ' graduating batch (synthetic).',
       CASE c.sector WHEN 'BFSI' THEN ARRAY['SQL','Python','Statistics'] WHEN 'CONSULTING_ANALYTICS' THEN ARRAY['SQL','Excel','Communication']
                     WHEN 'ELECTRONICS_SEMICON' THEN ARRAY['Verilog','Digital design'] WHEN 'CONSTRUCTION_INFRA' THEN ARRAY['AutoCAD','Estimation']
                     WHEN 'AUTOMOTIVE' THEN ARRAY['CAD','Manufacturing processes'] ELSE ARRAY['Programming fundamentals','Problem solving'] END,
       ARRAY['Internship experience'],
       jsonb_build_object('min_cgpa', 6.5, 'max_backlogs', 0, 'programmes', jsonb_agg(DISTINCT 'BTECH-' || o.dept)),
       round(c.ctc * 0.95, -3), round(c.ctc * 1.15, -3), ARRAY['Hyderabad','Bengaluru'],
       count(*) + 2, min(o.offer_date) - 10, min(o.offer_date) - 15,
       CASE WHEN o.ay = '2026-27' AND min(o.offer_date) - 10 >= DATE '2026-09-01' THEN 'CLOSED' ELSE 'DRIVE_COMPLETED' END
FROM t_offer o JOIN t_company c ON c.key = o.company
GROUP BY o.company, o.ay, c.sector, c.ctc;

INSERT INTO placement.offer (offer_id, student_id, company_id, job_opening_id, role_title, ctc, location, offer_date, is_ppo, joining_date, status)
SELECT pg_temp.uid('offer:' || o.student), pg_temp.uid(o.student), pg_temp.uid('company:' || o.company), pg_temp.uid('job:ft:' || o.company || ':' || o.ay),
       j.role_title, round(c.ctc * (0.95 + pg_temp.rnd('ctc:' || o.student) * 0.2), -3),
       (ARRAY['Hyderabad','Bengaluru','Pune','Chennai'])[1 + floor(pg_temp.rnd('loc:' || o.student) * 4)::int],
       o.offer_date, false,
       CASE WHEN o.yr = 2021 THEN DATE '2025-07-15' WHEN o.yr = 2022 THEN DATE '2026-07-20' ELSE DATE '2027-07-19' END,
       CASE o.yr
         WHEN 2021 THEN CASE WHEN o.r_status < 0.05 THEN 'DECLINED' WHEN o.r_status < 0.06 THEN 'REVOKED' ELSE 'JOINED' END
         WHEN 2022 THEN CASE WHEN o.r_status < 0.06 THEN 'DECLINED' WHEN o.r_status < 0.30 THEN 'ACCEPTED' ELSE 'JOINED' END
         ELSE CASE WHEN o.r_status < 0.03 THEN 'DECLINED' WHEN o.r_status < 0.20 THEN 'OFFERED' ELSE 'ACCEPTED' END END
FROM t_offer o
JOIN t_company c ON c.key = o.company
JOIN placement.job_opening j ON j.job_opening_id = pg_temp.uid('job:ft:' || o.company || ':' || o.ay);

-- internships: summer 2025 (batch 2022), summer 2026 (batch 2023), and semester internships now running
CREATE TEMP TABLE t_intern ON COMMIT DROP AS
SELECT s.k AS student, s.dept, s.yr, x.kind,
       CASE WHEN pg_temp.rnd('isrc:' || s.k || x.kind) < 0.08 THEN NULL ELSE p.company END AS company,
       x.f AS from_date, x.t AS to_date
FROM t_student s
JOIN (VALUES (2022, 'summer', DATE '2025-05-19', DATE '2025-07-18', 0.52),
             (2023, 'summer', DATE '2026-05-18', DATE '2026-07-17', 0.55),
             (2023, 'semester', DATE '2026-08-03', DATE '2026-11-27', 0.06)) AS x(yr, kind, f, t, prob) ON x.yr = s.yr
JOIN t_pool p ON p.dept = s.dept AND p.yr = s.yr
 AND pg_temp.rnd('ic:' || s.k || x.kind) >= p.ilo AND pg_temp.rnd('ic:' || s.k || x.kind) < p.ihi
WHERE pg_temp.rnd('intern:' || s.k || x.kind) < x.prob;

INSERT INTO placement.internship (internship_id, student_id, company_id, company_name, domain, from_date, to_date, mode, stipend, source,
       legitimacy_verified, verified_by_user_id, faculty_mentor_id, industry_supervisor, is_credit_bearing, course_version_id, final_grade,
       converted_to_ppo, status)
SELECT pg_temp.uid('intern:' || i.student || ':' || i.kind), pg_temp.uid(i.student),
       CASE WHEN i.company IS NOT NULL THEN pg_temp.uid('company:' || i.company) END,
       COALESCE(c.name, (ARRAY['Local startup (unregistered)','Freelance web project','Family business – digital operations','NGO technology volunteering'])[1 + floor(pg_temp.rnd('sname:' || i.student) * 4)::int]),
       CASE i.dept WHEN 'CSE' THEN (ARRAY['Cloud engineering','Data engineering','Machine learning','Backend development'])[1 + floor(pg_temp.rnd('dom:' || i.student) * 4)::int]
                   WHEN 'IT' THEN (ARRAY['Full-stack development','Cyber security','FinTech analytics'])[1 + floor(pg_temp.rnd('dom:' || i.student) * 3)::int]
                   WHEN 'ECE' THEN (ARRAY['VLSI verification','Embedded firmware','Machine vision','Telecom networks'])[1 + floor(pg_temp.rnd('dom:' || i.student) * 4)::int]
                   WHEN 'EEE' THEN (ARRAY['EV power electronics','Solar plant operations','Industrial automation'])[1 + floor(pg_temp.rnd('dom:' || i.student) * 3)::int]
                   WHEN 'MECH' THEN (ARRAY['Automotive assembly','Additive manufacturing','Robotics'])[1 + floor(pg_temp.rnd('dom:' || i.student) * 3)::int]
                   ELSE (ARRAY['Site execution','BIM modelling','Transportation planning'])[1 + floor(pg_temp.rnd('dom:' || i.student) * 3)::int] END,
       i.from_date, i.to_date,
       CASE WHEN pg_temp.rnd('imode:' || i.student) < 0.75 THEN 'ONSITE' WHEN pg_temp.rnd('imode:' || i.student) < 0.9 THEN 'HYBRID' ELSE 'REMOTE' END,
       CASE WHEN i.company IS NULL THEN 0 ELSE round(c.ctc / 60 * (0.8 + pg_temp.rnd('stip:' || i.student) * 0.4), -3) END,
       CASE WHEN i.company IS NULL THEN 'STUDENT_SOURCED'
            WHEN c.partner_key IS NOT NULL AND EXISTS (
                 SELECT 1 FROM t_mou m JOIN t_mou_deliv d ON d.mou = m.key AND d.dtype = 'INTERNSHIP'
                 WHERE m.partner = c.partner_key AND m.status <> 'DRAFT' AND i.from_date BETWEEN m.valid_from AND m.valid_until) THEN 'MOU'
            WHEN c.partner_key IS NULL AND pg_temp.rnd('alsrc:' || i.student) < 0.15 THEN 'ALUMNI'
            ELSE 'INSTITUTION' END,
       i.company IS NOT NULL OR pg_temp.rnd('legit:' || i.student) < 0.5,
       CASE WHEN i.company IS NOT NULL OR pg_temp.rnd('legit:' || i.student) < 0.5 THEN pg_temp.uid('user:tpo') END,
       pg_temp.uid('fac:' || i.dept || ':' || (2 + floor(pg_temp.rnd('mentor:' || i.student) * 5))::int),
       CASE WHEN i.company IS NOT NULL THEN pg_temp.fname('sup:' || i.company || i.dept) || ' ' || pg_temp.lname('sup:' || i.company || i.dept) END,
       i.kind = 'semester', NULL,
       CASE WHEN i.kind = 'summer' THEN (ARRAY['A+','A','A','B+','O'])[1 + floor(pg_temp.rnd('grade:' || i.student || i.kind) * 5)::int] END,
       i.kind = 'summer' AND i.yr = 2022 AND c.partner_key IS NOT NULL AND pg_temp.rnd('ppo:' || i.student) < 0.12,
       CASE WHEN i.kind = 'semester' THEN 'ONGOING'
            WHEN i.yr = 2022 AND pg_temp.rnd('disc:' || i.student) < 0.03 THEN 'DISCONTINUED'
            ELSE 'COMPLETED' END
FROM t_intern i LEFT JOIN t_company c ON c.key = i.company;

INSERT INTO placement.job_opening (job_opening_id, company_id, academic_year_id, role_title, opening_type, job_description, required_skills,
                                   eligibility, ctc_min, ctc_max, locations, positions_open, drive_date, application_deadline, status)
SELECT pg_temp.uid('job:intern:' || c.key || ':' || extract(year FROM i.from_date)), pg_temp.uid('company:' || c.key),
       pg_temp.uid(CASE WHEN extract(year FROM i.from_date) = 2025 THEN 'ay:2024-25' ELSE 'ay:2025-26' END),
       'Summer Intern', 'INTERNSHIP', 'Eight-week summer internship (synthetic).', ARRAY['Fundamentals of ' || lower(replace(c.sector, '_', ' '))],
       '{"min_cgpa": 6.0, "max_backlogs": 1}', NULL, NULL, ARRAY['Hyderabad'], count(*) + 1,
       min(i.from_date) - 60, min(i.from_date) - 75, 'DRIVE_COMPLETED'
FROM t_intern i JOIN t_company c ON c.key = i.company
WHERE i.kind = 'summer'
GROUP BY c.key, c.sector, extract(year FROM i.from_date);

INSERT INTO placement.internship_evaluation (internship_evaluation_id, internship_id, evaluator_type, evaluation_stage, score, max_score, criteria_scores, remarks, evaluated_on)
SELECT pg_temp.uid('ieval:' || it.internship_id || ':' || ev.t), it.internship_id, ev.t, 'FINAL',
       LEAST(98, GREATEST(45, round((52 + COALESCE(tp.quality, 3.9) * 9 + (pg_temp.rnd('isc:' || it.internship_id || ev.t) - 0.5) * 16)::numeric, 0))),
       100,
       jsonb_build_object('technical', 6 + floor(pg_temp.rnd('ct:' || it.internship_id) * 4), 'communication', 6 + floor(pg_temp.rnd('cc:' || it.internship_id) * 4),
                          'ownership', 6 + floor(pg_temp.rnd('co:' || it.internship_id) * 4)),
       CASE ev.t WHEN 'INDUSTRY' THEN 'Industry supervisor evaluation' ELSE 'Faculty mentor evaluation of report and presentation' END,
       it.to_date + 7
FROM placement.internship it
LEFT JOIN placement.company pc ON pc.company_id = it.company_id
LEFT JOIN t_partner tp ON pg_temp.uid('partner:' || tp.key) = pc.industry_partner_id
CROSS JOIN (VALUES ('INDUSTRY'),('FACULTY_MENTOR')) AS ev(t)
WHERE it.status = 'COMPLETED' AND (ev.t = 'FACULTY_MENTOR' OR it.company_id IS NOT NULL);

-- recent graduates become alumni (Agent 52 record); organisation = joined/accepted employer
INSERT INTO placement.alumni (alumni_id, person_id, student_id, programme_id, graduation_year, current_organisation, current_designation, sector,
                              location, outcome_category, engagement_level, contact_consent, publicity_consent, last_updated_on, updated_via)
SELECT pg_temp.uid('alum:' || s.k), pg_temp.uid('person:' || s.k), pg_temp.uid(s.k), pg_temp.uid('prog:' || s.dept), s.yr + 4,
       CASE WHEN o.status IN ('JOINED','ACCEPTED') THEN c.name END,
       CASE WHEN o.status IN ('JOINED','ACCEPTED') THEN o.role_title END,
       CASE WHEN o.status IN ('JOINED','ACCEPTED') THEN c.sector END,
       CASE WHEN o.status IN ('JOINED','ACCEPTED') THEN o.location END,
       CASE WHEN o.status IN ('JOINED','ACCEPTED') THEN 'EMPLOYED'
            WHEN pg_temp.rnd('hs:' || s.k) < 0.45 THEN 'HIGHER_STUDIES'
            WHEN pg_temp.rnd('hs:' || s.k) < 0.55 THEN 'ENTREPRENEUR' ELSE 'UNKNOWN' END,
       CASE WHEN s.yr = 2022 THEN 'ACTIVE' ELSE (ARRAY['ACTIVE','OCCASIONAL','DORMANT'])[1 + floor(pg_temp.rnd('eng:' || s.k) * 3)::int] END,
       pg_temp.rnd('consent:' || s.k) < 0.6, pg_temp.rnd('pub:' || s.k) < 0.3,
       make_date(s.yr + 4, 7, 1), 'EXIT_SURVEY'
FROM t_student s
LEFT JOIN placement.offer o ON o.student_id = pg_temp.uid(s.k)
LEFT JOIN placement.company c ON c.company_id = o.company_id
WHERE s.yr IN (2021, 2022);

-- ---------------------------------------------------------------------
-- 6.5 Student feedback on industry interactions (quality.feedback_*)
-- ---------------------------------------------------------------------
INSERT INTO quality.feedback_instrument (feedback_instrument_id, institution_id, name, audience, purpose, term_id, questions, is_anonymous, opens_on, closes_on, status)
VALUES (pg_temp.uid('instrument:industry'), pg_temp.uid('inst:DIET'), 'Industry interaction feedback', 'STUDENT', 'INDUSTRY_INTERACTION', NULL,
 '[{"key":"overall_rating","type":"scale_1_5","text":"Overall usefulness of this session"},
   {"key":"course_relevance","type":"scale_1_5","text":"How well did it reinforce what you are studying?"},
   {"key":"would_recommend","type":"boolean","text":"Would you recommend inviting this partner again?"},
   {"key":"comments","type":"text","text":"What should we change?"}]',
 true, '2024-06-01', NULL, 'ACTIVE');

INSERT INTO quality.feedback_response (feedback_response_id, feedback_instrument_id, respondent_token, target_type, target_id, answers, submitted_at)
SELECT pg_temp.uid('fb:' || a.k || ':' || g.i), pg_temp.uid('instrument:industry'), md5('respondent:' || a.k || ':' || g.i),
       'INDUSTRY_ACTIVITY', ia.industry_activity_id,
       jsonb_strip_nulls(jsonb_build_object(
         'overall_rating', LEAST(5, GREATEST(1, round(p.quality + (pg_temp.rnd('r1:' || a.k || g.i) - 0.5) * 2.4)))::int::text,
         'course_relevance', LEAST(5, GREATEST(1, round(p.quality + CASE WHEN ia.course_version_id IS NOT NULL THEN 0.2 ELSE -0.7 END
                                                        + (pg_temp.rnd('r2:' || a.k || g.i) - 0.5) * 2.6)))::int::text,
         'would_recommend', pg_temp.rnd('r3:' || a.k || g.i) < (p.quality - 2.2) / 2.5,
         'comments', CASE WHEN pg_temp.rnd('r4:' || a.k || g.i) < 0.18 THEN
                (ARRAY['More hands-on demo time please','Very relevant to our elective','Slides were too theoretical','Great real-world examples',
                       'Please share the recording','Session started late','Would like a follow-up workshop','Helped with my project idea'])[1 + floor(pg_temp.rnd('r5:' || a.k || g.i) * 8)::int] END)),
       (a.dt + 1 + floor(pg_temp.rnd('r6:' || a.k || g.i) * 4)::int + time '10:00' + interval '1 minute' * floor(pg_temp.rnd('r7:' || a.k || g.i) * 600)) AT TIME ZONE 'Asia/Kolkata'
FROM t_act a
JOIN t_partner p ON p.key = a.partner
JOIN engagement.industry_activity ia ON ia.industry_activity_id = pg_temp.uid(a.k)
CROSS JOIN LATERAL generate_series(1, LEAST(40, GREATEST(8, round(COALESCE(ia.participant_count, 20) * 0.3)))::int) AS g(i)
WHERE a.status = 'CONDUCTED' AND a.atype IN ('GUEST_LECTURE','EXPERT_TALK','INDUSTRY_VISIT')
  AND a.dt + 1 + floor(pg_temp.rnd('r6:' || a.k || g.i) * 4)::int <= DATE '2026-09-11';

UPDATE engagement.industry_activity ia
SET feedback_summary = format('%s student responses; average rating %s/5; relevance to course %s/5.%s',
                              f.n, f.avg_overall, f.avg_rel, COALESCE(' Most frequent comment: "' || f.top_comment || '".', ''))
FROM (
  SELECT fr.target_id, count(*) AS n,
         round(avg((fr.answers->>'overall_rating')::numeric), 2) AS avg_overall,
         round(avg((fr.answers->>'course_relevance')::numeric), 2) AS avg_rel,
         mode() WITHIN GROUP (ORDER BY fr.answers->>'comments') FILTER (WHERE fr.answers ? 'comments') AS top_comment
  FROM quality.feedback_response fr WHERE fr.target_type = 'INDUSTRY_ACTIVITY'
  GROUP BY fr.target_id
) f
WHERE f.target_id = ia.industry_activity_id;
-- =====================================================================
-- PART 7 — DERIVED DATA (what Agent 28 itself would have produced)
--   evidence links, deliverable status, alumni resolution, monthly health
--   snapshots, alerts and follow-ups, target-partner recommendations,
--   accreditation evidence and KPI values. Computed from the data above,
--   so every number is consistent with the underlying records.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 7.1 Deliverable fulfilment links (activities, MoU internships, offers, events)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_link (
  deliverable_id uuid, activity_id uuid, internship_id uuid, offer_id uuid, event_id uuid,
  ev_date date, rationale text, link_source text
) ON COMMIT DROP;

INSERT INTO t_link (deliverable_id, activity_id, ev_date, rationale, link_source)
SELECT DISTINCT ON (ia.industry_activity_id) d.mou_deliverable_id, ia.industry_activity_id, ia.activity_date,
       format('Conducted %s under the same MoU counts toward "%s".', lower(replace(ia.activity_type, '_', ' ')), d.description),
       'AGENT_SUGGESTED'
FROM engagement.industry_activity ia
JOIN engagement.mou_deliverable d ON d.mou_id = ia.mou_id
JOIN (VALUES ('GUEST_LECTURE','GUEST_LECTURE',1), ('GUEST_LECTURE','EXPERT_TALK',2),
             ('EXPERT_TALK','EXPERT_TALK',1), ('EXPERT_TALK','GUEST_LECTURE',2),
             ('INDUSTRY_VISIT','INDUSTRY_VISIT',1), ('FACULTY_EXCHANGE','FACULTY_EXCHANGE',1),
             ('LAB_SUPPORT','LAB_SUPPORT',1), ('SPONSORED_PROJECT','SPONSORED_PROJECT',1),
             ('CONSULTANCY','CONSULTANCY',1)) AS map(atype, dtype, pref)
  ON map.atype = ia.activity_type AND map.dtype = d.deliverable_type
WHERE ia.status = 'CONDUCTED'
ORDER BY ia.industry_activity_id, map.pref;

INSERT INTO t_link (deliverable_id, internship_id, ev_date, rationale, link_source)
SELECT DISTINCT ON (i.internship_id) d.mou_deliverable_id, i.internship_id, i.from_date,
       format('MoU-sourced internship at %s starting %s, within MoU validity.', c.name, i.from_date), 'AGENT_SUGGESTED'
FROM placement.internship i
JOIN placement.company c ON c.company_id = i.company_id AND c.industry_partner_id IS NOT NULL
JOIN engagement.mou m ON m.industry_partner_id = c.industry_partner_id AND m.status <> 'DRAFT'
 AND i.from_date BETWEEN m.valid_from AND m.valid_until
JOIN engagement.mou_deliverable d ON d.mou_id = m.mou_id AND d.deliverable_type = 'INTERNSHIP'
WHERE i.source = 'MOU' AND i.status IN ('ONGOING','COMPLETED')
ORDER BY i.internship_id, m.valid_from DESC;

INSERT INTO t_link (deliverable_id, offer_id, ev_date, rationale, link_source)
SELECT DISTINCT ON (o.offer_id) d.mou_deliverable_id, o.offer_id, o.offer_date,
       format('Accepted campus offer from %s dated %s, within MoU validity.', c.name, o.offer_date), 'AGENT_SUGGESTED'
FROM placement.offer o
JOIN placement.company c ON c.company_id = o.company_id AND c.industry_partner_id IS NOT NULL
JOIN engagement.mou m ON m.industry_partner_id = c.industry_partner_id AND m.status <> 'DRAFT'
 AND o.offer_date BETWEEN m.valid_from AND m.valid_until
JOIN engagement.mou_deliverable d ON d.mou_id = m.mou_id AND d.deliverable_type = 'PLACEMENT'
WHERE o.status IN ('ACCEPTED','JOINED')
ORDER BY o.offer_id, m.valid_from DESC;

INSERT INTO t_link (deliverable_id, event_id, ev_date, rationale, link_source)
SELECT d.mou_deliverable_id, pg_temp.uid('event:' || e.key), e.s,
       format('%s co-organised with the partner; recorded by the industry cell.', e.title), 'USER_DECLARED'
FROM t_event e
JOIN engagement.mou_deliverable d ON d.mou_id = pg_temp.uid('mou:' || e.mou) AND d.deliverable_type = 'TRAINING_PROGRAMME';

INSERT INTO engagement.mou_deliverable_fulfilment (mou_deliverable_fulfilment_id, mou_deliverable_id, industry_activity_id, internship_id, offer_id, event_id,
       contributed_count, link_source, status, match_rationale, agent_run_id, confirmed_by_user_id, confirmed_at)
SELECT pg_temp.uid('fulfil:' || l.deliverable_id || ':' || COALESCE(l.activity_id, l.internship_id, l.offer_id, l.event_id)),
       l.deliverable_id, l.activity_id, l.internship_id, l.offer_id, l.event_id, 1, l.link_source,
       CASE WHEN l.ev_date <= '2026-08-15' THEN 'CONFIRMED' ELSE 'SUGGESTED' END,
       l.rationale,
       CASE WHEN l.link_source = 'AGENT_SUGGESTED' THEN
         pg_temp.uid('run:' || CASE WHEN l.ev_date < '2025-09-01' THEN 'backfill:2025-09-01'
                                    ELSE (SELECT r.key FROM t_run r WHERE r.job = 'MONTHLY_HEALTH_SWEEP'
                                           AND (r.run_at AT TIME ZONE 'Asia/Kolkata')::date >= l.ev_date ORDER BY r.run_at LIMIT 1) END) END,
       CASE WHEN l.ev_date <= '2026-08-15' THEN pg_temp.uid('user:iiic.exec') END,
       CASE WHEN l.ev_date <= '2026-08-15' THEN GREATEST(l.ev_date + 7, DATE '2025-09-03')::timestamptz END
FROM t_link l;

-- ---------------------------------------------------------------------
-- 7.2 Deliverable status (the trigger already set achieved_count)
-- ---------------------------------------------------------------------
UPDATE engagement.mou_deliverable d
SET status = CASE
      WHEN d.target_count > 0 AND d.achieved_count >= d.target_count THEN 'ACHIEVED'
      -- MoUs that ended before digitisation began: status recorded from the old paper register, no evidence rows
      WHEN m.status IN ('RENEWED','EXPIRED','TERMINATED') AND m.valid_from < '2024-01-01'
           THEN CASE WHEN pg_temp.rnd('hist:' || d.mou_deliverable_id) < 0.6 THEN 'ACHIEVED' ELSE 'NOT_ACHIEVED' END
      WHEN m.status IN ('RENEWED','EXPIRED','TERMINATED') THEN 'NOT_ACHIEVED'
      WHEN d.achieved_count > 0 THEN 'IN_PROGRESS'
      ELSE 'PENDING' END
FROM engagement.mou m
WHERE m.mou_id = d.mou_id;

-- ---------------------------------------------------------------------
-- 7.3 Alumni <-> partner resolution (Agent 52 records, Agent 28 links)
-- ---------------------------------------------------------------------
INSERT INTO engagement.partner_alumni_link (industry_partner_id, alumni_id, match_method, match_confidence, status, agent_run_id, confirmed_by_user_id, confirmed_at)
SELECT DISTINCT ON (pc.industry_partner_id, al.alumni_id) pc.industry_partner_id, al.alumni_id, 'PARTNER_CONTACT', 1.000, 'CONFIRMED',
       pg_temp.uid('run:alumni:2026-09-08'), pg_temp.uid('user:iiic.exec'), '2026-09-09 10:00+05:30'
FROM engagement.partner_contact pc JOIN placement.alumni al ON al.person_id = pc.person_id;

INSERT INTO engagement.partner_alumni_link (industry_partner_id, alumni_id, match_method, match_confidence, status, agent_run_id, confirmed_by_user_id, confirmed_at)
SELECT ip.industry_partner_id, al.alumni_id,
       'ORGANISATION_NAME_MATCH',
       round(similarity(lower(al.current_organisation), lower(ip.name))::numeric, 3),
       CASE WHEN lower(al.current_organisation) = lower(ip.name) THEN 'CONFIRMED' ELSE 'SUGGESTED' END,
       pg_temp.uid('run:alumni:2026-09-08'),
       CASE WHEN lower(al.current_organisation) = lower(ip.name) THEN pg_temp.uid('user:iiic.exec') END,
       CASE WHEN lower(al.current_organisation) = lower(ip.name) THEN '2026-09-09 10:05+05:30'::timestamptz END
FROM placement.alumni al
JOIN engagement.industry_partner ip ON similarity(lower(al.current_organisation), lower(ip.name)) >= 0.6
ON CONFLICT (industry_partner_id, alumni_id) DO NOTHING;

-- ---------------------------------------------------------------------
-- 7.4 Monthly engagement-health snapshots (formula = agentops.model_version health-1.0)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_fulfil_ev ON COMMIT DROP AS
SELECT f.mou_deliverable_id, f.contributed_count, f.status,
       COALESCE(ia.activity_date, it.from_date, o.offer_date, j.drive_date, e.from_date) AS ev_date
FROM engagement.mou_deliverable_fulfilment f
LEFT JOIN engagement.industry_activity ia ON ia.industry_activity_id = f.industry_activity_id
LEFT JOIN placement.internship it ON it.internship_id = f.internship_id
LEFT JOIN placement.offer o ON o.offer_id = f.offer_id
LEFT JOIN placement.job_opening j ON j.job_opening_id = f.job_opening_id
LEFT JOIN engagement.event e ON e.event_id = f.event_id;

CREATE TEMP TABLE t_ledger ON COMMIT DROP AS
SELECT industry_partner_id, event_date FROM engagement.v_partner_activity_ledger WHERE is_realised;

CREATE TEMP TABLE t_snap ON COMMIT DROP AS
WITH runs AS (
  SELECT key, run_at, (run_at AT TIME ZONE 'Asia/Kolkata')::date AS d FROM t_run WHERE job = 'MONTHLY_HEALTH_SWEEP'
), base AS (
  SELECT r.key AS run_key, r.run_at, r.d, ip.industry_partner_id AS pid, ip.created_at::date AS since,
         (SELECT max(l.event_date) FROM t_ledger l WHERE l.industry_partner_id = ip.industry_partner_id AND l.event_date <= r.d) AS last_on,
         (SELECT count(*) FROM engagement.industry_activity a
           WHERE a.industry_partner_id = ip.industry_partner_id AND a.status = 'CONDUCTED'
             AND a.activity_date > r.d - 365 AND a.activity_date <= r.d) AS act12,
         (SELECT count(*) FROM placement.internship i JOIN placement.company c ON c.company_id = i.company_id
           WHERE c.industry_partner_id = ip.industry_partner_id AND i.status IN ('APPROVED','ONGOING','COMPLETED')
             AND i.from_date > r.d - 365 AND i.from_date <= r.d) AS int12,
         (SELECT count(*) FROM placement.offer o JOIN placement.company c ON c.company_id = o.company_id
           WHERE c.industry_partner_id = ip.industry_partner_id AND o.status IN ('ACCEPTED','JOINED')
             AND o.offer_date > r.d - 365 AND o.offer_date <= r.d) AS off12,
         mo.active_mous, mo.ach_ratio, mo.elapsed, mo.deliv_due, mo.deliv_ach,
         (SELECT count(*) FROM engagement.mou m
           WHERE m.industry_partner_id = ip.industry_partner_id AND m.status <> 'DRAFT'
             AND m.valid_from <= r.d AND m.valid_until >= r.d
             AND m.valid_until - r.d <= COALESCE(m.renewal_alert_days, 90)
             AND NOT EXISTS (SELECT 1 FROM engagement.mou_renewal rr WHERE rr.mou_id = m.mou_id AND rr.initiated_on <= r.d)) AS expiring_wo,
         (SELECT round(avg((fr.answers->>'overall_rating')::numeric), 2)
            FROM quality.feedback_response fr
            JOIN engagement.industry_activity a ON a.industry_activity_id = fr.target_id
           WHERE fr.target_type = 'INDUSTRY_ACTIVITY' AND a.industry_partner_id = ip.industry_partner_id
             AND (fr.submitted_at AT TIME ZONE 'Asia/Kolkata')::date <= r.d
             AND (fr.submitted_at AT TIME ZONE 'Asia/Kolkata')::date > r.d - 365) AS avg_rating
  FROM runs r
  CROSS JOIN engagement.industry_partner ip
  LEFT JOIN LATERAL (
    SELECT count(DISTINCT m.mou_id) AS active_mous,
           sum(LEAST(COALESCE(ev.ach, 0), dl.target_count)) FILTER (WHERE dl.target_count > 0)::numeric
             / NULLIF(sum(dl.target_count) FILTER (WHERE dl.target_count > 0), 0) AS ach_ratio,
           avg(GREATEST(0, LEAST(1, (r.d - m.valid_from)::numeric / NULLIF(m.valid_until - m.valid_from, 0)))) AS elapsed,
           count(dl.mou_deliverable_id) AS deliv_due,
           count(*) FILTER (WHERE dl.target_count > 0 AND COALESCE(ev.ach, 0) >= dl.target_count) AS deliv_ach
    FROM engagement.mou m
    JOIN engagement.mou_deliverable dl ON dl.mou_id = m.mou_id
    LEFT JOIN LATERAL (
      SELECT sum(fe.contributed_count) AS ach FROM t_fulfil_ev fe
      WHERE fe.mou_deliverable_id = dl.mou_deliverable_id AND fe.status = 'CONFIRMED' AND fe.ev_date <= r.d
    ) ev ON true
    WHERE m.industry_partner_id = ip.industry_partner_id AND m.status <> 'DRAFT'
      AND m.valid_from <= r.d AND (m.valid_until IS NULL OR m.valid_until >= r.d)
  ) mo ON true
  WHERE ip.status IN ('ACTIVE','DORMANT') AND ip.created_at::date <= r.d
), comp AS (
  SELECT b.*,
         CASE WHEN b.last_on IS NULL THEN 0 ELSE GREATEST(0, 1 - LEAST(b.d - b.last_on, 365) / 365.0) END AS c_recency,
         LEAST(b.act12, 6) / 6.0 AS c_volume,
         CASE WHEN COALESCE(b.active_mous, 0) = 0 OR b.ach_ratio IS NULL THEN 0 ELSE LEAST(1, b.ach_ratio / GREATEST(b.elapsed, 0.25)) END AS c_progress,
         LEAST(b.int12 + b.off12, 20) / 20.0 AS c_outcomes,
         CASE WHEN b.avg_rating IS NULL THEN 0.5 ELSE (b.avg_rating - 1) / 4 END AS c_feedback,
         (b.d - COALESCE(b.last_on, b.since)) > 180 AS dormant
  FROM base b
)
SELECT c.*,
       round(100 * (0.25 * c.c_recency + 0.20 * c.c_volume + 0.25 * c.c_progress + 0.20 * c.c_outcomes + 0.10 * c.c_feedback), 2) AS score
FROM comp c;

INSERT INTO engagement.partner_health_snapshot (partner_health_snapshot_id, industry_partner_id, as_of_date, model_version_id, agent_run_id,
       health_score, health_band, is_dormant, components, last_activity_on, days_since_last_activity, activities_12m, internships_12m, offers_12m,
       active_mou_count, deliverables_due, deliverables_achieved, avg_feedback_rating, mous_expiring_without_renewal, computed_at)
SELECT pg_temp.uid('snap:' || s.pid || ':' || s.d), s.pid, s.d, pg_temp.uid('model:health-1.0'), pg_temp.uid('run:' || s.run_key),
       s.score,
       CASE WHEN s.dormant THEN 'DORMANT' WHEN s.score >= 75 THEN 'STRONG' WHEN s.score >= 50 THEN 'STABLE' ELSE 'AT_RISK' END,
       s.dormant,
       jsonb_build_object(
         'recency',              jsonb_build_object('normalised', round(s.c_recency, 3),  'weight', 0.25, 'contribution', round(25 * s.c_recency, 2)),
         'activity_volume',      jsonb_build_object('normalised', round(s.c_volume, 3),   'weight', 0.20, 'contribution', round(20 * s.c_volume, 2)),
         'deliverable_progress', jsonb_build_object('normalised', round(s.c_progress, 3), 'weight', 0.25, 'contribution', round(25 * s.c_progress, 2),
                                                    'achievement_ratio', round(s.ach_ratio, 3), 'mou_elapsed_ratio', round(s.elapsed, 3)),
         'student_outcomes',     jsonb_build_object('normalised', round(s.c_outcomes, 3), 'weight', 0.20, 'contribution', round(20 * s.c_outcomes, 2)),
         'feedback',             jsonb_build_object('normalised', round(s.c_feedback, 3), 'weight', 0.10, 'contribution', round(10 * s.c_feedback, 2))),
       s.last_on, s.d - s.last_on, s.act12, s.int12, s.off12, COALESCE(s.active_mous, 0), COALESCE(s.deliv_due, 0), COALESCE(s.deliv_ach, 0),
       s.avg_rating, s.expiring_wo, s.run_at + interval '40 seconds'
FROM t_snap s;

UPDATE engagement.industry_partner ip
SET engagement_score = h.health_score, last_activity_on = h.last_activity_on
FROM engagement.partner_health_snapshot h
WHERE h.industry_partner_id = ip.industry_partner_id AND h.as_of_date = '2026-09-11';

-- ---------------------------------------------------------------------
-- 7.5 Alerts, approval proposals and follow-up tasks from the 11 Sep 2026 sweep
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_alert (
  kind text, subject_type text, subject_id uuid, title text, body text, severity text, payload jsonb,
  owner_dept text, proposal jsonb, task text, task_owner text, task_due date, task_priority text, task_status text
) ON COMMIT DROP;

-- (a) dormant partners still marked ACTIVE
INSERT INTO t_alert
SELECT 'DORMANT_PARTNER', 'INDUSTRY_PARTNER', ip.industry_partner_id,
       'Dormant partnership: ' || ip.name,
       format('No realised engagement with %s for %s days (last: %s). %s active MoU(s). Health score %s.',
              ip.name, COALESCE(h.days_since_last_activity::text, 'n/a'), COALESCE(h.last_activity_on::text, 'never'), h.active_mou_count, h.health_score),
       'WARNING',
       jsonb_build_object('partner', ip.name, 'last_activity_on', h.last_activity_on, 'days_since_last_activity', h.days_since_last_activity,
                          'active_mou_count', h.active_mou_count, 'health_score', h.health_score,
                          'active_primary_contact', EXISTS (SELECT 1 FROM engagement.partner_contact pc
                                                            WHERE pc.industry_partner_id = ip.industry_partner_id AND pc.is_primary AND pc.valid_to IS NULL)),
       (SELECT d.code FROM people.faculty f JOIN core.department d ON d.department_id = f.department_id WHERE f.faculty_id = ip.relationship_owner_faculty_id),
       jsonb_build_object('table', 'engagement.industry_partner', 'id', ip.industry_partner_id, 'set', jsonb_build_object('status', 'DORMANT')),
       'Re-engage ' || ip.name || ': confirm the current SPOC and propose one activity this term', 'iiic.exec', DATE '2026-09-25', 'HIGH',
       CASE WHEN ip.name ILIKE 'Tarang%' THEN 'IN_PROGRESS' ELSE 'OPEN' END
FROM engagement.industry_partner ip
JOIN engagement.partner_health_snapshot h ON h.industry_partner_id = ip.industry_partner_id AND h.as_of_date = '2026-09-11'
WHERE h.is_dormant AND ip.status = 'ACTIVE';

-- (b) MoUs inside the renewal window with no renewal discussion
INSERT INTO t_alert
SELECT 'MOU_EXPIRING_NO_RENEWAL', 'MOU', m.mou_id,
       'MoU expiring in ' || (m.valid_until - DATE '2026-09-11') || ' days without renewal discussion: ' || m.partner_name,
       format('"%s" with %s expires on %s. No renewal discussion has been recorded (alert window %s days).', m.title, m.partner_name, m.valid_until, m.renewal_alert_days),
       CASE WHEN m.valid_until - DATE '2026-09-11' <= 30 THEN 'URGENT' ELSE 'WARNING' END,
       jsonb_build_object('mou', m.title, 'partner', m.partner_name, 'valid_until', m.valid_until, 'days_to_expiry', m.valid_until - DATE '2026-09-11',
                          'deliverables_open', (SELECT count(*) FROM engagement.mou_deliverable d WHERE d.mou_id = m.mou_id AND d.status IN ('PENDING','IN_PROGRESS'))),
       (SELECT d.code FROM people.faculty f JOIN core.department d ON d.department_id = f.department_id WHERE f.faculty_id = m.owner_faculty_id),
       NULL,
       'Initiate renewal discussion: ' || m.title || ' (' || m.partner_name || ')', 'iiic.head',
       GREATEST(m.valid_until - 14, DATE '2026-09-14'),
       CASE WHEN m.valid_until - DATE '2026-09-11' <= 30 THEN 'URGENT' ELSE 'HIGH' END, 'OPEN'
FROM engagement.mou m
WHERE m.status = 'ACTIVE' AND m.valid_until >= DATE '2026-09-11'
  AND m.valid_until - DATE '2026-09-11' <= COALESCE(m.renewal_alert_days, 90)
  AND NOT EXISTS (SELECT 1 FROM engagement.mou_renewal r WHERE r.mou_id = m.mou_id
                  AND r.status IN ('DISCUSSION_INITIATED','NEGOTIATING','DRAFT_SHARED','APPROVED_INTERNALLY'));

-- (c) MoUs past valid_until but still recorded as ACTIVE
INSERT INTO t_alert
SELECT 'MOU_EXPIRED_NOT_RECORDED', 'MOU', m.mou_id,
       'MoU expired but still ACTIVE: ' || m.partner_name,
       format('"%s" ended on %s (%s days ago) but its status is ACTIVE.%s', m.title, m.valid_until, DATE '2026-09-11' - m.valid_until,
              CASE WHEN EXISTS (SELECT 1 FROM engagement.mou_renewal r WHERE r.mou_id = m.mou_id AND r.closed_on IS NULL)
                   THEN ' A renewal discussion is open.' ELSE ' No renewal discussion exists.' END),
       'URGENT',
       jsonb_build_object('mou', m.title, 'partner', m.partner_name, 'valid_until', m.valid_until),
       (SELECT d.code FROM people.faculty f JOIN core.department d ON d.department_id = f.department_id WHERE f.faculty_id = m.owner_faculty_id),
       jsonb_build_object('table', 'engagement.mou', 'id', m.mou_id, 'set', jsonb_build_object('status', 'EXPIRED')),
       'Record status of expired MoU: ' || m.title, 'iiic.exec', DATE '2026-09-15', 'MEDIUM', 'OPEN'
FROM engagement.mou m
WHERE m.status = 'ACTIVE' AND m.valid_until < DATE '2026-09-11';

-- (d) deliverables at risk: most of the MoU term used, little confirmed evidence
INSERT INTO t_alert
SELECT 'DELIVERABLE_AT_RISK', 'MOU_DELIVERABLE', v.mou_deliverable_id,
       'Deliverable at risk: ' || m.partner_name || ' – ' || v.description,
       format('%s%% of the MoU term has elapsed but only %s of %s committed items are evidenced.', round(v.mou_elapsed_pct), v.achieved_count, v.target_count),
       'WARNING',
       jsonb_build_object('mou', m.title, 'deliverable', v.description, 'target', v.target_count, 'achieved', v.achieved_count,
                          'mou_elapsed_pct', v.mou_elapsed_pct),
       (SELECT d.code FROM people.faculty f JOIN core.department d ON d.department_id = f.department_id WHERE f.faculty_id = m.owner_faculty_id),
       NULL, NULL, NULL, NULL, NULL, NULL
FROM engagement.v_deliverable_status v
JOIN engagement.mou m ON m.mou_id = v.mou_id AND m.status = 'ACTIVE' AND m.valid_until >= DATE '2026-09-11'
WHERE v.status IN ('PENDING','IN_PROGRESS') AND v.target_count > 0
  AND (DATE '2026-09-11' - m.valid_from)::numeric / NULLIF(m.valid_until - m.valid_from, 0) >= 0.6
  AND v.achieved_count::numeric / v.target_count < 0.35;

-- (e) extraction waiting for human review
INSERT INTO t_alert
SELECT 'EXTRACTION_REVIEW', 'MOU', m.mou_id, 'MoU extraction needs review: ' || m.partner_name,
       format('%s extracted field(s) are below the confidence threshold for "%s". The MoU stays DRAFT until they are verified.',
              (SELECT count(*) FROM knowledge.extracted_field xf WHERE xf.extraction_job_id = m.extraction_job_id AND xf.verification_status = 'NEEDS_REVIEW'), m.title),
       'INFO', jsonb_build_object('mou', m.title, 'extraction_job_id', m.extraction_job_id), 'IT', NULL,
       'Verify low-confidence fields for draft MoU: ' || m.title, 'iiic.exec', DATE '2026-09-16', 'MEDIUM', 'OPEN'
FROM engagement.mou m WHERE m.status = 'DRAFT';

INSERT INTO agentops.agent_output (agent_output_id, agent_run_id, output_type, subject_type, subject_id, payload, reasoning_summary, citations,
                                   interpretation, confidence, requires_approval, approval_status, created_at)
SELECT pg_temp.uid('out:alert:' || a.kind || ':' || a.subject_id), pg_temp.uid('run:sweep:2026-09-11'), 'ALERT', a.subject_type, a.subject_id,
       a.payload || jsonb_build_object('alert_kind', a.kind), a.body,
       CASE WHEN a.subject_type = 'MOU' THEN jsonb_build_array(jsonb_build_object('document_id', (SELECT document_ref FROM engagement.mou WHERE mou_id = a.subject_id), 'clause', '5 Term and renewal')) END,
       jsonb_build_object('as_of_date', '2026-09-11', 'model_version', 'health-1.0', 'dormancy_days', 180),
       0.920, false, 'NOT_REQUIRED', '2026-09-11 07:01+05:30'
FROM t_alert a;

INSERT INTO agentops.agent_output (agent_output_id, agent_run_id, output_type, subject_type, subject_id, payload, reasoning_summary, confidence,
                                   requires_approval, approval_status, created_at)
SELECT pg_temp.uid('out:proposal:' || a.kind || ':' || a.subject_id), pg_temp.uid('run:sweep:2026-09-11'), 'ACTION_PROPOSAL', a.subject_type, a.subject_id,
       jsonb_build_object('proposed_change', a.proposal), 'Proposed status change following: ' || a.title, 0.880, true, 'PENDING', '2026-09-11 07:01+05:30'
FROM t_alert a WHERE a.proposal IS NOT NULL;

INSERT INTO agentops.alert (alert_id, recipient_user_id, agent_id, risk_flag_id, severity, title, body, channel, created_at, delivered_at, read_at, actioned_at)
SELECT pg_temp.uid('alert:' || a.kind || ':' || a.subject_id || ':' || u.username), pg_temp.uid('user:' || u.username), pg_temp.uid('agent:A28'), NULL,
       a.severity, a.title, a.body, CASE WHEN a.severity = 'URGENT' AND u.username = 'iiic.head' THEN 'EMAIL' ELSE 'IN_APP' END,
       '2026-09-11 07:02+05:30', '2026-09-11 07:02+05:30',
       CASE WHEN pg_temp.rnd('read:' || a.subject_id || u.username) < 0.5 THEN '2026-09-11 10:15+05:30'::timestamptz END,
       CASE WHEN a.task_status = 'IN_PROGRESS' AND u.username = 'iiic.head' THEN '2026-09-11 11:00+05:30'::timestamptz END
FROM t_alert a
CROSS JOIN LATERAL (VALUES ('iiic.head'), ('hod.' || lower(COALESCE(a.owner_dept, 'cse')))) AS u(username)
WHERE a.kind <> 'EXTRACTION_REVIEW' OR u.username = 'iiic.head';

-- an earlier dormancy alert that was read, not actioned, and escalated to the Dean
INSERT INTO agentops.alert (alert_id, recipient_user_id, agent_id, severity, title, body, channel, created_at, delivered_at, read_at, escalated_at, escalated_to_user_id)
SELECT pg_temp.uid('alert:escalated:' || ip.industry_partner_id), pg_temp.uid('user:iiic.head'), pg_temp.uid('agent:A28'), 'WARNING',
       'Dormant partnership: ' || ip.name,
       format('No realised engagement with %s since %s.', ip.name, h.last_activity_on),
       'IN_APP', '2026-08-31 07:02+05:30', '2026-08-31 07:02+05:30', '2026-09-01 09:40+05:30', '2026-09-07 07:00+05:30', pg_temp.uid('user:dean.academics')
FROM engagement.industry_partner ip
JOIN engagement.partner_health_snapshot h ON h.industry_partner_id = ip.industry_partner_id AND h.as_of_date = '2026-08-31' AND h.is_dormant
WHERE ip.name ILIKE 'Tarang%';

INSERT INTO studentlife.action_item (action_item_id, source_schema, source_table, source_id, description, owner_user_id, due_date, priority, status, closed_on, closure_note)
SELECT pg_temp.uid('task:' || a.kind || ':' || a.subject_id), 'engagement',
       CASE a.subject_type WHEN 'INDUSTRY_PARTNER' THEN 'industry_partner' WHEN 'MOU' THEN 'mou' ELSE 'mou_deliverable' END,
       a.subject_id, a.task, pg_temp.uid('user:' || a.task_owner), a.task_due, a.task_priority, a.task_status, NULL, NULL
FROM t_alert a WHERE a.task IS NOT NULL;

INSERT INTO studentlife.action_item (action_item_id, source_schema, source_table, source_id, description, owner_user_id, due_date, priority, status, closed_on, closure_note)
SELECT pg_temp.uid('task:renewal:' || r.mou_renewal_id), 'engagement', 'mou_renewal', r.mou_renewal_id,
       'Take renewal forward: ' || m.title || ' (' || m.partner_name || ') – ' || lower(replace(r.status, '_', ' ')),
       pg_temp.uid('user:iiic.head'), r.target_sign_by, 'HIGH',
       CASE WHEN r.closed_on IS NULL THEN 'IN_PROGRESS' ELSE 'COMPLETED' END,
       r.closed_on, CASE WHEN r.closed_on IS NOT NULL THEN r.notes END
FROM engagement.mou_renewal r JOIN engagement.mou m ON m.mou_id = r.mou_id
WHERE r.initiated_on >= '2025-06-01';

-- ---------------------------------------------------------------------
-- 7.6 Target-partner recommendations (8 Sep 2026) with human review
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_target ON COMMIT DROP AS
WITH gap AS (
  SELECT sector, gap_pct_points FROM engagement.v_sector_gap
  WHERE academic_year = '2025-26' AND institution_id = pg_temp.uid('inst:DIET')
), feat AS (
  SELECT c.company_id, c.name, c.sector, c.tier, c.industry_partner_id, ip.status AS partner_status, c.alumni_connect_person_id,
         (SELECT count(*) FROM placement.offer o WHERE o.company_id = c.company_id AND o.status IN ('ACCEPTED','JOINED') AND o.offer_date >= DATE '2026-09-08' - 1095) AS offers_3y,
         (SELECT count(*) FROM placement.internship i WHERE i.company_id = c.company_id AND i.from_date >= DATE '2026-09-08' - 1095) AS internships_3y,
         (SELECT count(*) FROM placement.alumni al WHERE al.contact_consent AND similarity(lower(al.current_organisation), lower(c.name)) >= 0.6) AS consenting_alumni,
         COALESCE(g.gap_pct_points, 0) AS sector_gap
  FROM placement.company c
  LEFT JOIN engagement.industry_partner ip ON ip.industry_partner_id = c.industry_partner_id
  LEFT JOIN gap g ON g.sector = c.sector
  WHERE c.industry_partner_id IS NULL OR ip.status = 'PROSPECT'
), scored AS (
  SELECT f.*,
         round(45 * f.offers_3y::numeric / NULLIF(max(f.offers_3y) OVER (), 0)
             + 15 * f.internships_3y::numeric / NULLIF(max(f.internships_3y) OVER (), 0)
             + 25 * GREATEST(f.sector_gap, 0) / NULLIF(max(GREATEST(f.sector_gap, 0)) OVER (), 0)
             + 15 * LEAST(f.consenting_alumni, 5) / 5.0, 2) AS score
  FROM feat f
)
SELECT s.*, row_number() OVER (ORDER BY s.score DESC, s.name) AS rnk FROM scored s;

DELETE FROM t_target WHERE rnk > 6;

ALTER TABLE t_target ADD COLUMN decision text;
UPDATE t_target t SET decision = x.decision
FROM (
  SELECT company_id,
         CASE WHEN tier = 'MASS' THEN 'REJECT'
              WHEN row_number() OVER (PARTITION BY tier = 'MASS' ORDER BY rnk) <= 2 THEN 'APPROVE'
              WHEN row_number() OVER (PARTITION BY tier = 'MASS' ORDER BY rnk) = 3 THEN 'MODIFY'
              ELSE NULL END AS decision
  FROM t_target
) x WHERE x.company_id = t.company_id;

INSERT INTO agentops.agent_output (agent_output_id, agent_run_id, output_type, subject_type, subject_id, payload, reasoning_summary, interpretation,
                                   confidence, requires_approval, approval_status, created_at)
SELECT pg_temp.uid('out:target:' || t.company_id), pg_temp.uid('run:target:2026-09-08'), 'RECOMMENDATION', 'COMPANY', t.company_id,
       jsonb_build_object('rank', t.rnk, 'company', t.name, 'sector', t.sector, 'tier', t.tier, 'score', t.score,
                          'features', jsonb_build_object('accepted_offers_3y', t.offers_3y, 'internships_3y', t.internships_3y,
                                                         'consenting_alumni', t.consenting_alumni, 'sector_gap_pct_points_2025_26', t.sector_gap),
                          'suggested_contact', (SELECT full_name FROM people.person WHERE person_id = t.alumni_connect_person_id),
                          'suggested_first_step', CASE WHEN t.alumni_connect_person_id IS NOT NULL THEN 'Warm introduction through the alumni connect'
                                                       ELSE 'Invite for an expert talk before proposing an MoU' END),
       format('%s hired %s of our students in three years and sits in %s, where placements exceed partnership coverage by %s percentage points.',
              t.name, t.offers_3y, lower(replace(t.sector, '_', ' ')), t.sector_gap),
       jsonb_build_object('metric', 'target_partner_score', 'window', '3 years to 2026-09-08', 'gap_year', '2025-26',
                          'weights', jsonb_build_object('offers', 45, 'internships', 15, 'sector_gap', 25, 'alumni', 15)),
       0.800, true,
       CASE t.decision WHEN 'APPROVE' THEN 'APPROVED' WHEN 'MODIFY' THEN 'MODIFIED' WHEN 'REJECT' THEN 'REJECTED' ELSE 'PENDING' END,
       '2026-09-08 11:33+05:30'
FROM t_target t;

INSERT INTO agentops.human_review (human_review_id, agent_output_id, reviewer_user_id, decision, modified_payload, reason, reason_category, reviewed_at, time_to_review_seconds)
SELECT pg_temp.uid('review:' || t.company_id), pg_temp.uid('out:target:' || t.company_id), pg_temp.uid('user:iiic.head'), t.decision,
       CASE WHEN t.decision = 'MODIFY' THEN jsonb_build_object('suggested_first_step', 'Approach jointly with the TPO after the December placement season') END,
       CASE t.decision
         WHEN 'APPROVE' THEN 'Strong recruiter in an under-partnered sector; approach this term.'
         WHEN 'MODIFY'  THEN 'Good fit, but timing clashes with their campus drive; defer outreach.'
         WHEN 'REJECT'  THEN 'Mass recruiter already engaged directly by the placement cell; an MoU adds little.' END,
       CASE t.decision WHEN 'REJECT' THEN 'POLICY' WHEN 'MODIFY' THEN 'MISSING_CONTEXT' END,
       '2026-09-09 16:20+05:30', 104400 + (t.rnk * 311)
FROM t_target t WHERE t.decision IS NOT NULL;

-- approved non-partner companies become PROSPECT partners (the output of the human decision)
INSERT INTO engagement.industry_partner (industry_partner_id, institution_id, name, sector, website, relationship_owner_faculty_id, status, created_at)
SELECT pg_temp.uid('partner:target:' || t.company_id), pg_temp.uid('inst:DIET'), t.name, t.sector, c.website,
       pg_temp.uid('fac:' || CASE WHEN t.sector IN ('BFSI') THEN 'IT' ELSE 'CSE' END || ':2'), 'PROSPECT', '2026-09-09 17:00+05:30'
FROM t_target t JOIN placement.company c ON c.company_id = t.company_id
WHERE t.decision = 'APPROVE' AND t.industry_partner_id IS NULL;

UPDATE placement.company c SET industry_partner_id = pg_temp.uid('partner:target:' || t.company_id)
FROM t_target t WHERE t.company_id = c.company_id AND t.decision = 'APPROVE' AND t.industry_partner_id IS NULL;

INSERT INTO engagement.partner_contact (partner_contact_id, industry_partner_id, person_id, designation, organisation_unit, contact_role, is_primary, valid_from)
SELECT pg_temp.uid('contact:target:' || t.company_id), pg_temp.uid('partner:target:' || t.company_id), t.alumni_connect_person_id,
       al.current_designation, 'Alumni Network', 'ALUMNI_CHAMPION', true, '2026-09-09'
FROM t_target t JOIN placement.alumni al ON al.person_id = t.alumni_connect_person_id
WHERE t.decision = 'APPROVE' AND t.industry_partner_id IS NULL AND t.alumni_connect_person_id IS NOT NULL;

-- ---------------------------------------------------------------------
-- 7.7 Accreditation evidence (placeholder framework — replace codes from the official manual)
-- ---------------------------------------------------------------------
INSERT INTO governance.compliance_framework (compliance_framework_id, code, name, version, effective_from)
VALUES (pg_temp.uid('fw:DEMO_ACCR'), 'DEMO_ACCR', 'Demo accreditation framework (placeholder criteria – map to NAAC/NBA manual codes)', 'demo-1', '2024-06-01');

INSERT INTO quality.accreditation_criterion (accreditation_criterion_id, compliance_framework_id, code, parent_id, title, weightage, evidence_specification, responsible_role_id)
SELECT pg_temp.uid('crit:' || c.code), pg_temp.uid('fw:DEMO_ACCR'), c.code, NULL, c.title, c.w, c.spec, pg_temp.uid('role:' || c.role)
FROM (VALUES
  ('IND-1', 'Functional MoUs with industry',                     20, 'MoU register with at least one conducted activity or evidenced deliverable per MoU per year', 'INDUSTRY_RELATIONS'),
  ('IND-2', 'Industry-supported academic activities',            25, 'Guest lectures, expert talks, visits and faculty immersion with reports and attendance', 'INDUSTRY_RELATIONS'),
  ('IND-3', 'Internships and projects through industry linkage', 25, 'Internships, sponsored projects and consultancy with partner confirmation', 'PLACEMENT'),
  ('IND-4', 'Industry support for laboratories',                 15, 'Equipment, software or lab sponsorship with value and installation proof', 'INDUSTRY_RELATIONS'),
  ('IND-5', 'Stakeholder feedback on industry interaction',      15, 'Student feedback analysis and actions taken', 'IQAC')
) AS c(code, title, w, spec, role);

INSERT INTO quality.evidence_item (evidence_item_id, accreditation_criterion_id, title, evidence_type, period_start, period_end, document_ref,
                                   source_schema, source_table, source_id, generated_by_agent, content_hash, approved_by_user_id, approved_at, created_at)
SELECT pg_temp.uid('evidence:' || ia.industry_activity_id), pg_temp.uid('crit:' || CASE
         WHEN ia.activity_type IN ('GUEST_LECTURE','EXPERT_TALK','INDUSTRY_VISIT','FACULTY_EXCHANGE') THEN 'IND-2'
         WHEN ia.activity_type = 'LAB_SUPPORT' THEN 'IND-4' ELSE 'IND-3' END),
       ia.title, 'REPORT', ay.start_date, ay.end_date, ia.evidence_ref, 'engagement', 'industry_activity', ia.industry_activity_id,
       'A28_INDUSTRY_INTERACTION', d.content_hash,
       CASE WHEN ay.label = '2024-25' OR (ay.label = '2025-26' AND pg_temp.rnd('appr:' || ia.industry_activity_id) < 0.7) THEN pg_temp.uid('user:iqac.coordinator') END,
       CASE WHEN ay.label = '2024-25' THEN '2025-07-30 15:00+05:30'::timestamptz
            WHEN ay.label = '2025-26' AND pg_temp.rnd('appr:' || ia.industry_activity_id) < 0.7 THEN '2026-07-28 15:00+05:30'::timestamptz END,
       (ia.activity_date + 5)::timestamptz
FROM engagement.industry_activity ia
JOIN knowledge.document d ON d.document_id = ia.evidence_ref
JOIN core.academic_year ay ON ia.activity_date BETWEEN ay.start_date AND ay.end_date
WHERE ia.status = 'CONDUCTED';

INSERT INTO quality.evidence_item (evidence_item_id, accreditation_criterion_id, title, evidence_type, period_start, period_end, source_schema, source_table,
                                   source_id, generated_by_agent, content_hash, approved_by_user_id, approved_at, created_at)
SELECT pg_temp.uid('evidence:' || x.code || ':' || ay.label), pg_temp.uid('crit:' || x.code), x.title || ' ' || ay.label, 'DATA_EXPORT',
       ay.start_date, ay.end_date, 'engagement', x.tbl, NULL, 'A28_INDUSTRY_INTERACTION', md5('export:' || x.code || ay.label),
       CASE WHEN ay.label <> '2026-27' THEN pg_temp.uid('user:iqac.coordinator') END,
       CASE WHEN ay.label <> '2026-27' THEN (ay.end_date + 60)::timestamptz END,
       CASE WHEN ay.label = '2026-27' THEN '2026-09-11 07:05+05:30'::timestamptz ELSE (ay.end_date + 30)::timestamptz END
FROM core.academic_year ay
CROSS JOIN (VALUES ('IND-1', 'Functional MoU register', 'mou'), ('IND-5', 'Industry interaction feedback analysis', 'industry_activity')) AS x(code, title, tbl);

-- ---------------------------------------------------------------------
-- 7.8 Industry-interaction KPIs per academic year (quality.kpi_*)
-- ---------------------------------------------------------------------
INSERT INTO quality.kpi_definition (kpi_definition_id, institution_id, code, name, domain, definition, formula, unit, source_agent, source_query,
                                    target_value, direction, frequency, framework_mapping, owner_role_id)
SELECT pg_temp.uid('kpi:' || k.code), pg_temp.uid('inst:DIET'), k.code, k.name, k.domain, k.def, k.formula, k.unit, 'A28_INDUSTRY_INTERACTION', k.src,
       k.target, 'HIGHER_BETTER', 'ANNUAL', '{"DEMO_ACCR": "IND"}', pg_temp.uid('role:INDUSTRY_RELATIONS')
FROM (VALUES
  ('IND_FUNCTIONAL_MOU_PCT', 'Functional industry MoUs', 'OUTREACH', 'Share of industry MoUs in force during the year with at least one conducted activity or confirmed evidence',
     '100 * functional_mous / mous_in_force', '%', 'engagement.mou + mou_deliverable_fulfilment + industry_activity', 80),
  ('IND_ACTIVITIES_PER_PARTNER', 'Activities per engaged partner', 'OUTREACH', 'Conducted industry activities divided by partners with an MoU in force',
     'conducted_activities / partners_with_mou', 'count', 'engagement.industry_activity', 4),
  ('IND_MOU_INTERNSHIPS', 'Internships through MoUs', 'PLACEMENT', 'Internships started in the year with source = MOU',
     'count(internship where source = MOU)', 'count', 'placement.internship', 80),
  ('IND_PARTNER_OFFER_SHARE', 'Offers from partner companies', 'PLACEMENT', 'Share of accepted/joined offers made by companies linked to an industry partner',
     '100 * partner_offers / all_offers', '%', 'placement.offer + placement.company', 40),
  ('IND_AVG_FEEDBACK', 'Student rating of industry interactions', 'OUTREACH', 'Mean overall rating (1-5) of industry interactions',
     'avg(answers.overall_rating)', 'rating', 'quality.feedback_response', 4)
) AS k(code, name, domain, def, formula, unit, src, target);

CREATE TEMP TABLE t_kpi ON COMMIT DROP AS
SELECT ay.label, ay.start_date, ay.end_date, x.code, x.val
FROM core.academic_year ay
CROSS JOIN LATERAL (VALUES
  ('IND_FUNCTIONAL_MOU_PCT', (
     SELECT round(100.0 * count(*) FILTER (WHERE EXISTS (
                SELECT 1 FROM engagement.industry_activity a WHERE a.mou_id = m.mou_id AND a.status = 'CONDUCTED'
                  AND a.activity_date BETWEEN ay.start_date AND LEAST(ay.end_date, DATE '2026-09-11'))
              OR EXISTS (SELECT 1 FROM t_fulfil_ev fe JOIN engagement.mou_deliverable d ON d.mou_deliverable_id = fe.mou_deliverable_id
                          WHERE d.mou_id = m.mou_id AND fe.status = 'CONFIRMED' AND fe.ev_date BETWEEN ay.start_date AND ay.end_date))
            / NULLIF(count(*), 0), 2)
     FROM engagement.mou m
     WHERE m.partner_type = 'INDUSTRY' AND m.status <> 'DRAFT' AND m.valid_from <= LEAST(ay.end_date, DATE '2026-09-11') AND m.valid_until >= ay.start_date)),
  ('IND_ACTIVITIES_PER_PARTNER', (
     SELECT round((SELECT count(*) FROM engagement.industry_activity a WHERE a.status = 'CONDUCTED' AND a.industry_partner_id IS NOT NULL
                     AND a.activity_date BETWEEN ay.start_date AND ay.end_date)::numeric
                  / NULLIF(count(DISTINCT m.industry_partner_id), 0), 2)
     FROM engagement.mou m
     WHERE m.industry_partner_id IS NOT NULL AND m.status <> 'DRAFT' AND m.valid_from <= LEAST(ay.end_date, DATE '2026-09-11') AND m.valid_until >= ay.start_date)),
  ('IND_MOU_INTERNSHIPS', (SELECT count(*)::numeric FROM placement.internship i WHERE i.source = 'MOU' AND i.from_date BETWEEN ay.start_date AND ay.end_date)),
  ('IND_PARTNER_OFFER_SHARE', (
     SELECT round(100.0 * count(*) FILTER (WHERE c.industry_partner_id IS NOT NULL AND c.name NOT IN (SELECT name FROM t_target WHERE decision = 'APPROVE'))
                  / NULLIF(count(*), 0), 2)
     FROM placement.offer o JOIN placement.company c ON c.company_id = o.company_id
     WHERE o.status IN ('ACCEPTED','JOINED') AND o.offer_date BETWEEN ay.start_date AND ay.end_date)),
  ('IND_AVG_FEEDBACK', (
     SELECT round(avg((fr.answers->>'overall_rating')::numeric), 2) FROM quality.feedback_response fr
     WHERE fr.target_type = 'INDUSTRY_ACTIVITY' AND (fr.submitted_at AT TIME ZONE 'Asia/Kolkata')::date BETWEEN ay.start_date AND ay.end_date))
) AS x(code, val);

INSERT INTO quality.kpi_value (kpi_value_id, kpi_definition_id, scope_type, scope_id, period_start, period_end, value, target_value, previous_value,
                               variance_pct, trend, status, computed_at, computed_by_agent, validated_by_user_id, validated_at)
SELECT pg_temp.uid('kpival:' || k.code || ':' || k.label), pg_temp.uid('kpi:' || k.code), 'INSTITUTION', pg_temp.uid('inst:DIET'),
       k.start_date, k.end_date, k.val, kd.target_value, p.val,
       CASE WHEN p.val IS NOT NULL AND p.val <> 0 THEN round(100 * (k.val - p.val) / p.val, 2) END,
       CASE WHEN p.val IS NULL OR k.label = '2026-27' THEN NULL WHEN k.val > p.val * 1.03 THEN 'IMPROVING' WHEN k.val < p.val * 0.97 THEN 'DETERIORATING' ELSE 'STABLE' END,
       CASE WHEN k.val IS NULL THEN 'NO_DATA' WHEN k.val >= kd.target_value THEN 'ON_TARGET' ELSE 'BELOW_TARGET' END,
       CASE WHEN k.label = '2026-27' THEN '2026-09-11 07:06+05:30'::timestamptz ELSE (k.end_date + 15)::timestamptz END,
       'A28_INDUSTRY_INTERACTION',
       CASE WHEN k.label <> '2026-27' THEN pg_temp.uid('user:iqac.coordinator') END,
       CASE WHEN k.label <> '2026-27' THEN (k.end_date + 45)::timestamptz END
FROM t_kpi k
JOIN quality.kpi_definition kd ON kd.kpi_definition_id = pg_temp.uid('kpi:' || k.code)
LEFT JOIN t_kpi p ON p.code = k.code AND p.end_date = k.start_date - 1;

-- ---------------------------------------------------------------------
-- 7.9 Provenance of the latest sweep (agentops.agent_run_input)
-- ---------------------------------------------------------------------
INSERT INTO agentops.agent_run_input (agent_run_id, source_schema, source_table, source_id, record_count, filter_expression)
SELECT pg_temp.uid('run:sweep:2026-09-11'), x.s, x.t, NULL, x.n, x.f
FROM (VALUES
  ('engagement', 'industry_partner',            (SELECT count(*) FROM engagement.industry_partner WHERE status IN ('ACTIVE','DORMANT')), 'status IN (ACTIVE, DORMANT)'),
  ('engagement', 'industry_activity',           (SELECT count(*) FROM engagement.industry_activity WHERE status = 'CONDUCTED'), 'status = CONDUCTED'),
  ('engagement', 'mou',                         (SELECT count(*) FROM engagement.mou WHERE status <> 'DRAFT'), 'status <> DRAFT'),
  ('engagement', 'mou_deliverable_fulfilment',  (SELECT count(*) FROM engagement.mou_deliverable_fulfilment WHERE status = 'CONFIRMED'), 'status = CONFIRMED'),
  ('placement',  'internship',                  (SELECT count(*) FROM placement.internship WHERE company_id IS NOT NULL), 'company_id IS NOT NULL'),
  ('placement',  'offer',                       (SELECT count(*) FROM placement.offer WHERE status IN ('ACCEPTED','JOINED')), 'status IN (ACCEPTED, JOINED)'),
  ('quality',    'feedback_response',           (SELECT count(*) FROM quality.feedback_response WHERE target_type = 'INDUSTRY_ACTIVITY'), 'target_type = INDUSTRY_ACTIVITY')
) AS x(s, t, n, f);
-- =====================================================================
-- PART 8 — APPLICATION ROLES AND GRANTS
-- Same role names as the universal schema. Default privileges are added so
-- tables you create later during development are granted automatically
-- (the universal file lacks this — see spec risk R2).
-- =====================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_readwrite') THEN CREATE ROLE app_readwrite NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_readonly')  THEN CREATE ROLE app_readonly  NOLOGIN; END IF;
END $$;

GRANT USAGE ON SCHEMA core, people, identity, curriculum, academics, research, engagement, placement, studentlife,
      governance, quality, knowledge, agentops TO app_readwrite, app_readonly;

GRANT SELECT ON ALL TABLES IN SCHEMA core, people, identity, curriculum, academics, research, engagement, placement, studentlife,
      governance, quality, knowledge, agentops TO app_readonly;

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA core, people, identity, curriculum, academics, research, engagement, placement,
      studentlife, governance, quality, knowledge, agentops TO app_readwrite;

GRANT DELETE ON engagement.industry_activity_person TO app_readwrite;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA agentops TO app_readwrite;   -- agent_run_input.bigserial

ALTER DEFAULT PRIVILEGES IN SCHEMA core, people, identity, curriculum, academics, research, engagement, placement, studentlife,
      governance, quality, knowledge, agentops GRANT SELECT ON TABLES TO app_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA core, people, identity, curriculum, academics, research, engagement, placement, studentlife,
      governance, quality, knowledge, agentops GRANT SELECT, INSERT, UPDATE ON TABLES TO app_readwrite;

COMMIT;

-- =====================================================================
-- PART 9 — LOAD SUMMARY (read-only; safe to re-run any time)
-- =====================================================================
SELECT t.table_name AS "table", t.row_count AS "rows"
FROM (
  SELECT 'engagement.industry_partner' AS table_name, (SELECT count(*) FROM engagement.industry_partner) AS row_count, 1 AS ord
  UNION ALL SELECT 'engagement.partner_contact', (SELECT count(*) FROM engagement.partner_contact), 2
  UNION ALL SELECT 'engagement.partner_expertise', (SELECT count(*) FROM engagement.partner_expertise), 3
  UNION ALL SELECT 'engagement.mou', (SELECT count(*) FROM engagement.mou), 4
  UNION ALL SELECT 'engagement.mou_deliverable', (SELECT count(*) FROM engagement.mou_deliverable), 5
  UNION ALL SELECT 'engagement.mou_deliverable_fulfilment', (SELECT count(*) FROM engagement.mou_deliverable_fulfilment), 6
  UNION ALL SELECT 'engagement.mou_renewal', (SELECT count(*) FROM engagement.mou_renewal), 7
  UNION ALL SELECT 'engagement.industry_activity', (SELECT count(*) FROM engagement.industry_activity), 8
  UNION ALL SELECT 'engagement.industry_activity_person', (SELECT count(*) FROM engagement.industry_activity_person), 9
  UNION ALL SELECT 'engagement.activity_course_alignment', (SELECT count(*) FROM engagement.activity_course_alignment), 10
  UNION ALL SELECT 'engagement.partner_health_snapshot', (SELECT count(*) FROM engagement.partner_health_snapshot), 11
  UNION ALL SELECT 'engagement.partner_alumni_link', (SELECT count(*) FROM engagement.partner_alumni_link), 12
  UNION ALL SELECT 'engagement.event', (SELECT count(*) FROM engagement.event), 13
  UNION ALL SELECT 'placement.company', (SELECT count(*) FROM placement.company), 14
  UNION ALL SELECT 'placement.offer', (SELECT count(*) FROM placement.offer), 15
  UNION ALL SELECT 'placement.internship', (SELECT count(*) FROM placement.internship), 16
  UNION ALL SELECT 'placement.alumni', (SELECT count(*) FROM placement.alumni), 17
  UNION ALL SELECT 'people.student', (SELECT count(*) FROM people.student), 18
  UNION ALL SELECT 'people.faculty', (SELECT count(*) FROM people.faculty), 19
  UNION ALL SELECT 'curriculum.course_topic', (SELECT count(*) FROM curriculum.course_topic), 20
  UNION ALL SELECT 'knowledge.document', (SELECT count(*) FROM knowledge.document), 21
  UNION ALL SELECT 'knowledge.extracted_field', (SELECT count(*) FROM knowledge.extracted_field), 22
  UNION ALL SELECT 'quality.feedback_response', (SELECT count(*) FROM quality.feedback_response), 23
  UNION ALL SELECT 'quality.evidence_item', (SELECT count(*) FROM quality.evidence_item), 24
  UNION ALL SELECT 'agentops.agent_run', (SELECT count(*) FROM agentops.agent_run), 25
  UNION ALL SELECT 'agentops.agent_output', (SELECT count(*) FROM agentops.agent_output), 26
  UNION ALL SELECT 'agentops.alert', (SELECT count(*) FROM agentops.alert), 27
) t ORDER BY t.ord;

-- =====================================================================
-- PART 10 — QUERIES TO TRY (Agent 28 outputs; all read from views)
-- =====================================================================
-- Partner register with health:
--   SELECT name, status, health_band, health_score, last_activity_on, primary_contact_name
--   FROM engagement.v_partner_register ORDER BY health_score DESC NULLS LAST;
-- MoUs expiring without a renewal discussion, or expired but still ACTIVE:
--   SELECT partner_name, title, valid_until, days_to_expiry, effective_status, open_renewal_status
--   FROM engagement.v_mou_tracker WHERE expiring_without_renewal ORDER BY days_to_expiry;
-- Did each MoU produce anything? (deliverable evidence):
--   SELECT m.partner_name, d.description, d.target_count, d.achieved_count, d.achievement_pct, d.status
--   FROM engagement.v_deliverable_status d JOIN engagement.mou m USING (mou_id) ORDER BY m.partner_name;
-- Upcoming activity calendar with exam/holiday clashes and the course topic it reinforces:
--   SELECT activity_date, activity_type, status, partner_name, course_code, calendar_clashes
--   FROM engagement.v_activity_calendar WHERE activity_date >= DATE '2026-09-11' ORDER BY activity_date;
-- Sector gap (placements vs partnerships) and target-partner candidates:
--   SELECT * FROM engagement.v_sector_gap WHERE academic_year = '2025-26' ORDER BY gap_pct_points DESC;
--   SELECT payload->>'rank' AS rank, payload->>'company' AS company, approval_status
--   FROM agentops.agent_output WHERE output_type = 'RECOMMENDATION' ORDER BY 1;
-- Health history of one partner:
--   SELECT as_of_date, health_score, health_band, components FROM engagement.partner_health_snapshot
--   WHERE industry_partner_id = md5('partner:TARANG')::uuid ORDER BY as_of_date;
-- Open alerts and follow-ups for the industry cell head:
--   SELECT severity, title, read_at FROM agentops.alert WHERE recipient_user_id = md5('user:iiic.head')::uuid ORDER BY created_at DESC;
--   SELECT description, due_date, priority, status FROM studentlife.action_item WHERE source_schema = 'engagement' ORDER BY due_date;
-- Accreditation evidence and KPIs:
--   SELECT criterion_code, title, period_start, approved_at FROM engagement.v_accreditation_evidence ORDER BY period_start, criterion_code;
--   SELECT code, value, target_value, status FROM quality.v_kpi_latest;
--
-- Deterministic IDs you can use in tests:  md5('partner:NIMBUS')::uuid, md5('mou:M04')::uuid,
--   md5('user:iiic.head')::uuid, md5('dept:CSE')::uuid, md5('agent:A28')::uuid, md5('inst:DIET')::uuid
