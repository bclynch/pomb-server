begin;

drop schema if exists pomb, pomb_private cascade;
drop role if exists pomb_admin, pomb_anonymous, pomb_account;

create schema pomb;
create schema pomb_private;

alter default privileges revoke execute on functions from public;

-- *******************************************************************
-- *********************** Audit Trigger *****************************
-- *******************************************************************
CREATE EXTENSION IF NOT EXISTS hstore;
--
-- Audited data. Lots of information is available, it's just a matter of how much
-- you really want to record. See:
--
--   http://www.postgresql.org/docs/9.1/static/functions-info.html
--
-- Remember, every column you add takes up more audit table space and slows audit
-- inserts.
--
-- Every index you add has a big impact too, so avoid adding indexes to the
-- audit table unless you REALLY need them. The hstore GIST indexes are
-- particularly expensive.
--
-- It is sometimes worth copying the audit table, or a coarse subset of it that
-- you're interested in, into a temporary table where you CREATE any useful
-- indexes and do your analysis.
--
CREATE TABLE pomb.logged_actions (
    event_id bigserial primary key,
    table_name text not null,
    account_id integer,
    session_user_name text,
    action_tstamp_tx TIMESTAMP WITH TIME ZONE NOT NULL,
    client_addr inet,
    action TEXT NOT NULL CHECK (action IN ('I','D','U', 'T')),
    row_data hstore,
    changed_fields hstore
);

REVOKE ALL ON pomb.logged_actions FROM public;

COMMENT ON TABLE pomb.logged_actions IS 'History of auditable actions on audited tables, from pomb_private.if_modified_func()';
COMMENT ON COLUMN pomb.logged_actions.event_id IS 'Unique identifier for each auditable event';
COMMENT ON COLUMN pomb.logged_actions.table_name IS 'Non-schema-qualified table name of table event occured in';
COMMENT ON COLUMN pomb.logged_actions.account_id IS 'User performing the action';
COMMENT ON COLUMN pomb.logged_actions.session_user_name IS 'Login / session user whose statement caused the audited event';
COMMENT ON COLUMN pomb.logged_actions.action_tstamp_tx IS 'Transaction start timestamp for tx in which audited event occurred';
COMMENT ON COLUMN pomb.logged_actions.client_addr IS 'IP address of client that issued query. Null for unix domain socket.';
COMMENT ON COLUMN pomb.logged_actions.action IS 'Action type; I = insert, D = delete, U = update, T = truncate';
COMMENT ON COLUMN pomb.logged_actions.row_data IS 'Record value. Null for statement-level trigger. For INSERT this is the new tuple. For DELETE and UPDATE it is the old tuple.';
COMMENT ON COLUMN pomb.logged_actions.changed_fields IS 'New values of fields changed by UPDATE. Null except for row-level UPDATE events.';

CREATE OR REPLACE FUNCTION pomb_private.if_modified_func() RETURNS TRIGGER AS $body$
DECLARE
    audit_row pomb.logged_actions;
    include_values boolean;
    log_diffs boolean;
    h_old hstore;
    h_new hstore;
    excluded_cols text[] = ARRAY[]::text[];
BEGIN
    IF TG_WHEN <> 'AFTER' THEN
        RAISE EXCEPTION 'pomb_private.if_modified_func() may only run as an AFTER trigger';
    END IF;

    audit_row = ROW(
        nextval('pomb.logged_actions_event_id_seq'), -- event_id
        TG_TABLE_NAME::text,                          -- table_name
        current_setting('jwt.claims.account_id', true)::integer, -- account_id
        session_user::text,                           -- session_user_name
        current_timestamp,                            -- action_tstamp_tx
        inet_client_addr(),                           -- client_addr
        substring(TG_OP,1,1),                         -- action
        NULL, NULL                                   -- row_data, changed_fields
        );

    IF TG_ARGV[1] IS NOT NULL THEN
        excluded_cols = TG_ARGV[1]::text[];
    END IF;
    
    IF (TG_OP = 'UPDATE' AND TG_LEVEL = 'ROW') THEN
        audit_row.row_data = hstore(OLD.*) - excluded_cols;
        audit_row.changed_fields =  (hstore(NEW.*) - audit_row.row_data) - excluded_cols;
        IF audit_row.changed_fields = hstore('') THEN
            -- All changed fields are ignored. Skip this update.
            RETURN NULL;
        END IF;
    ELSIF (TG_OP = 'DELETE' AND TG_LEVEL = 'ROW') THEN
        audit_row.row_data = hstore(OLD.*) - excluded_cols;
    ELSIF (TG_OP = 'INSERT' AND TG_LEVEL = 'ROW') THEN
        audit_row.row_data = hstore(NEW.*) - excluded_cols;
    ELSE
        RAISE EXCEPTION '[pomb_private.if_modified_func] - Trigger func added as trigger for unhandled case: %, %',TG_OP, TG_LEVEL;
        RETURN NULL;
    END IF;
    INSERT INTO pomb.logged_actions VALUES (audit_row.*);
    RETURN NULL;
END;
$body$
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public;


COMMENT ON FUNCTION pomb_private.if_modified_func() IS $body$
Track changes to a table at the statement and/or row level.

Optional parameters to trigger in CREATE TRIGGER call:

param 0: boolean, whether to log the query text. Default 't'.

param 1: text[], columns to ignore in updates. Default [].

         Updates to ignored cols are omitted from changed_fields.

         Updates with only ignored cols changed are not inserted
         into the audit log.

         Almost all the processing work is still done for updates
         that ignored. If you need to save the load, you need to use
         WHEN clause on the trigger instead.

         No warning or error is issued if ignored_cols contains columns
         that do not exist in the target table. This lets you specify
         a standard set of ignored columns.

There is no parameter to disable logging of values. Add this trigger as
a 'FOR EACH STATEMENT' rather than 'FOR EACH ROW' trigger if you do not
want to log row values.

Note that the user name logged is the login role for the session. The audit trigger
cannot obtain the active role because it is reset by the SECURITY DEFINER invocation
of the audit trigger its self.
$body$;



CREATE OR REPLACE FUNCTION pomb.audit_table(target_table regclass, audit_rows boolean, audit_query_text boolean, ignored_cols text[]) RETURNS void AS $body$
DECLARE
  stm_targets text = 'INSERT OR UPDATE OR DELETE OR TRUNCATE';
  _q_txt text;
  _ignored_cols_snip text = '';
BEGIN
    EXECUTE 'DROP TRIGGER IF EXISTS audit_trigger_row ON ' || quote_ident(target_table::TEXT);
    EXECUTE 'DROP TRIGGER IF EXISTS audit_trigger_stm ON ' || quote_ident(target_table::TEXT);

    IF audit_rows THEN
        IF array_length(ignored_cols,1) > 0 THEN
            _ignored_cols_snip = ', ' || quote_literal(ignored_cols);
        END IF;
        _q_txt = 'CREATE TRIGGER audit_trigger_row AFTER INSERT OR UPDATE OR DELETE ON ' || 
                 quote_ident(target_table::TEXT) || 
                 ' FOR EACH ROW EXECUTE PROCEDURE pomb_private.if_modified_func(' ||
                 quote_literal(audit_query_text) || _ignored_cols_snip || ');';
        RAISE NOTICE '%',_q_txt;
        EXECUTE _q_txt;
        stm_targets = 'TRUNCATE';
    ELSE
    END IF;

    _q_txt = 'CREATE TRIGGER audit_trigger_stm AFTER ' || stm_targets || ' ON ' ||
             target_table ||
             ' FOR EACH STATEMENT EXECUTE PROCEDURE pomb_private.if_modified_func('||
             quote_literal(audit_query_text) || ');';
    RAISE NOTICE '%',_q_txt;
    EXECUTE _q_txt;

END;
$body$
language 'plpgsql';

COMMENT ON FUNCTION pomb.audit_table(regclass, boolean, boolean, text[]) IS $body$
Add auditing support to a table.

Arguments:
   target_table:     Table name, schema qualified if not on search_path
   audit_rows:       Record each row change, or only audit at a statement level
   audit_query_text: Record the text of the client query that triggered the audit event?
   ignored_cols:     Columns to exclude from update diffs, ignore updates that change only ignored cols.
$body$;

-- Pg doesn't allow variadic calls with 0 params, so provide a wrapper
CREATE OR REPLACE FUNCTION pomb.audit_table(target_table regclass, audit_rows boolean, audit_query_text boolean) RETURNS void AS $body$
SELECT pomb.audit_table($1, $2, $3, ARRAY[]::text[]);
$body$ LANGUAGE SQL;

-- And provide a convenience call wrapper for the simplest case
-- of row-level logging with no excluded cols and query logging enabled.
--
CREATE OR REPLACE FUNCTION pomb.audit_table(target_table regclass) RETURNS void AS $body$
SELECT pomb.audit_table($1, BOOLEAN 't', BOOLEAN 't');
$body$ LANGUAGE 'sql';

COMMENT ON FUNCTION pomb.audit_table(regclass) IS $body$
Add auditing support to the given table. Row-level changes will be logged with full client query text. No cols are ignored.
$body$;

create table pomb.account (
  id                   serial primary key,
  username             text unique not null check (char_length(username) < 80),
  first_name           text check (char_length(first_name) < 80),
  last_name            text check (char_length(last_name) < 100),
  profile_photo        text,
  hero_photo           text,
  city                 text check (char_length(first_name) < 80),
  country              text check (char_length(first_name) < 80),
  auto_update_location boolean not null default true,
  user_status          text check (char_length(first_name) < 300),
  created_at           bigint default (extract(epoch from now()) * 1000),
  updated_at           timestamp default now()
);

CREATE TRIGGER account_INSERT_UPDATE_DELETE
AFTER INSERT OR UPDATE OR DELETE ON pomb.account
FOR EACH ROW EXECUTE PROCEDURE pomb_private.if_modified_func();

insert into pomb.account (username, first_name, last_name, profile_photo, city, country, user_status, auto_update_location) values
  ('teeth-creep', 'Ms', 'D', 'https://laze-app.s3.amazonaws.com/19243203_10154776689779211_34706076750698170_o-w250-1509052127322.jpg', 'London', 'UK', 'Living the dream', true);

comment on table pomb.account is 'Table with POMB users';
comment on column pomb.account.id is 'Primary id for account';
comment on column pomb.account.username is 'username of account';
comment on column pomb.account.first_name is 'First name of account';
comment on column pomb.account.last_name is 'Last name of account';
comment on column pomb.account.profile_photo is 'Profile photo of account';
comment on column pomb.account.hero_photo is 'Hero photo of account';
comment on column pomb.account.city is 'Current city';
comment on column pomb.account.country is 'Current country';
comment on column pomb.account.auto_update_location is 'Toggle to update location on juncture creation';
comment on column pomb.account.user_status is 'Current status';
comment on column pomb.account.created_at is 'When account created';
comment on column pomb.account.updated_at is 'When account last updated';

alter table pomb.account enable row level security;

create table pomb.trip (
  id                  serial primary key,
  user_id             integer not null references pomb.account(id) on delete cascade,
  name                text not null check (char_length(name) < 256),
  description         text check (char_length(name) < 2400),
  start_date          bigint not null,
  end_date            bigint,
  start_lat           decimal not null,
  start_lon           decimal not null,
  created_at          bigint default (extract(epoch from now()) * 1000),
  updated_at          timestamp default now()
);

CREATE TRIGGER trip_INSERT_UPDATE_DELETE
AFTER INSERT OR UPDATE OR DELETE ON pomb.trip
FOR EACH ROW EXECUTE PROCEDURE pomb_private.if_modified_func();

insert into pomb.trip (user_id, name, description, start_date, end_date, start_lat, start_lon) values
  (1, 'Cool Trip', '<p><em><span style="font-size: 24px;">Lorem ipsum dolor sit amet, consectetur adipiscing elit. Morbi sit amet pharetra magna. Nulla pretium, ligula eu ullamcorper volutpat, libero diam malesuada est, vel euismod sapien turpis bibendum nulla. Donec tincidunt sed mauris et auctor. Curabitur malesuada lectus id elit vehicula efficitur.</span></em></p><h2>Section 1</h2><p><em><span style="font-size: 18px;">Lorem ipsum dolor sit amet, consectetur adipiscing elit. Morbi sit amet pharetra magna. Nulla pretium, ligula eu ullamcorper volutpat, libero diam malesuada est, vel euismod sapien turpis bibendum nulla. Donec tincidunt sed mauris et auctor. Curabitur malesuada lectus id elit vehicula efficitur.</span></em></p><h2>Section 2</h2><p><em><span style="font-size: 18px;">Lorem ipsum dolor sit amet, consectetur adipiscing elit. Morbi sit amet pharetra magna. Nulla pretium, ligula eu ullamcorper volutpat, libero diam malesuada est, vel euismod sapien turpis bibendum nulla. Donec tincidunt sed mauris et auctor. Curabitur malesuada lectus id elit vehicula efficitur.</span></em></p><h2>Section 3</h2><p><em><span style="font-size: 18px;">Lorem ipsum dolor sit amet, consectetur adipiscing elit. Morbi sit amet pharetra magna. Nulla pretium, ligula eu ullamcorper volutpat, libero diam malesuada est, vel euismod sapien turpis bibendum nulla. Donec tincidunt sed mauris et auctor. Curabitur malesuada lectus id elit vehicula efficitur.</span></em></p>', 1508274574542, 1548282774542, 37.7749, -122.4194),
  (1, 'Neat Trip', null, 1408274574542, 1448274574542, 6.2442, -75.5812);

comment on table pomb.trip is 'Table with POMB trips';
comment on column pomb.trip.id is 'Primary id for trip';
comment on column pomb.trip.user_id is 'User id who created trip';
comment on column pomb.trip.name is 'Name of trip';
comment on column pomb.trip.description is 'Description of trip';
comment on column pomb.trip.start_date is 'Start date of trip';
comment on column pomb.trip.end_date is 'End date of trip';
comment on column pomb.trip.start_lat is 'Starting point latitude of trip';
comment on column pomb.trip.start_lon is 'Starting poiht longitude of trip';
comment on column pomb.trip.created_at is 'When trip created';
comment on column pomb.trip.updated_at is 'When trip last updated';

alter table pomb.trip enable row level security;

create table pomb.juncture (
  id                  serial primary key,
  user_id             integer not null references pomb.account(id) on delete cascade,
  trip_id             integer not null references pomb.trip(id) on delete cascade,
  name                text not null check (char_length(name) < 256),
  arrival_date        bigint not null,
  description         text check (char_length(name) < 1200),
  lat                 decimal not null,
  lon                 decimal not null,
  city                text,
  country             text,
  is_draft            boolean,
  marker_img          text,
  created_at          bigint default (extract(epoch from now()) * 1000),
  updated_at          timestamp default now()
);

CREATE TRIGGER juncture_INSERT_UPDATE_DELETE
AFTER INSERT OR UPDATE OR DELETE ON pomb.juncture
FOR EACH ROW EXECUTE PROCEDURE pomb_private.if_modified_func();

insert into pomb.juncture (user_id, trip_id, name, arrival_date, description, lat, lon, city, country, is_draft, marker_img) values
  (1, 1, 'Day 1', 1508274574542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 36.9741, -122.0308, 'Santa Cruz', 'US', false, 'https://packonmyback.s3.amazonaws.com/WP_20150721_08_47_08_Pro__highres-marker-1515559581861.png'),
  (1, 1, 'Day 2', 1508274774542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 37.7749, -122.4194, 'San Francisco', 'US', true, 'https://packonmyback.s3.amazonaws.com/WP_20150721_08_47_08_Pro__highres-marker-1515559581861.png'),
  (1, 1, 'Day 3', 1508278774542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 37.9735, -122.5311, 'San Rafael', 'US', false, 'https://packonmyback.s3.amazonaws.com/WP_20150721_08_47_08_Pro__highres-marker-1515559581861.png'),
  (1, 1, 'Day 4', 1508278874542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 38.4741, -119.0308, 'Whichman', 'US', false, 'https://packonmyback.s3.amazonaws.com/WP_20150721_08_47_08_Pro__highres-marker-1515559581861.png'),
  (1, 1, 'Day 5', 1528279074542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 38.7749, -118.4194, 'Walter Lake', 'US', false, 'https://packonmyback.s3.amazonaws.com/WP_20150721_08_47_08_Pro__highres-marker-1515559581861.png'),
  (1, 1, 'Day 6', 1528279874542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 39.9735, -110.5311, 'Myron', 'US', false, null),
  (1, 1, 'Day 7', 1538280574542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 40.9741, -108.0308, 'Baggs', 'US', false, 'https://packonmyback.s3.amazonaws.com/WP_20150721_08_47_08_Pro__highres-marker-1515559581861.png'),
  (1, 1, 'Day 8', 1538281674542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 41.7749, -108.4194, 'Rock Springs', 'US', false, 'https://packonmyback.s3.amazonaws.com/WP_20150721_08_47_08_Pro__highres-marker-1515559581861.png'),
  (1, 1, 'Day 9', 1548282774542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 39.9735, -114.5311, 'Cherry Creek', 'US', false, null),
  (1, 2, 'So it begins', 1408274584542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 4.7110, -74.0721, 'Medellin', 'CO', false, 'https://packonmyback.s3.amazonaws.com/WP_20150721_08_47_08_Pro__highres-marker-1515559581861.png');

comment on table pomb.juncture is 'Table with POMB junctures';
comment on column pomb.juncture.id is 'Primary id for juncture';
comment on column pomb.juncture.user_id is 'User id who created juncture';
comment on column pomb.juncture.trip_id is 'Trip id juncture belongs to';
comment on column pomb.juncture.name is 'Name of juncture';
comment on column pomb.juncture.arrival_date is 'Date of juncture';
comment on column pomb.juncture.description is 'Description of the juncture';
comment on column pomb.juncture.lat is 'Latitude of the juncture';
comment on column pomb.juncture.lon is 'Longitude of the juncture';
comment on column pomb.juncture.city is 'City of the juncture';
comment on column pomb.juncture.country is 'Country code of the juncture';
comment on column pomb.juncture.is_draft is 'Whether the juncture should be published or not';
comment on column pomb.juncture.marker_img is 'Image to be used for markers on our map';
comment on column pomb.juncture.created_at is 'When juncture created';
comment on column pomb.juncture.updated_at is 'When juncture last updated';

alter table pomb.juncture enable row level security;

create table pomb.post (
  id                  serial primary key,
  author              integer not null references pomb.account(id) on delete cascade,
  title               text not null check (char_length(title) < 200),
  subtitle            text not null check (char_length(title) < 300),
  content             text not null,
  trip_id              integer references pomb.trip(id) on delete cascade,
  juncture_id          integer references pomb.juncture(id) on delete cascade,
  is_draft            boolean not null,
  is_scheduled        boolean not null,
  scheduled_date      bigint,
  is_published        boolean not null,
  published_date      bigint,
  created_at          bigint default (extract(epoch from now()) * 1000),
  updated_at          timestamp default now()
);

CREATE TRIGGER post_INSERT_UPDATE_DELETE
AFTER INSERT OR UPDATE OR DELETE ON pomb.post
FOR EACH ROW EXECUTE PROCEDURE pomb_private.if_modified_func();

insert into pomb.post (author, title, subtitle, content, trip_id, juncture_id, is_draft, is_scheduled, scheduled_date, is_published, published_date) values
  (1, 'Explore The World', 'Neat Info', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 1, 1, false, false, null, true, 1495726380000),
  (1, 'Lose Your Way? Find a Beer', 'No Bud Light though', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 1, 1, false, false, null, true, 1295726380000),
  (1, 'Sports through the lense of global culture', 'Its not all football out there', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 2, 1, true, false, null, false, null),
  (1, 'Riding the Silk Road', 'Bets way to see central asia. You will love it for sure. Going to see so much stuff. Should be great. Follow along as some dipshit does some stuff out in the desert and he is like. Whoa. Hot dog what a story we are going to have to share.Should be great', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', null, null, false, false, null, true, 1095726380000),
  (1, 'Why You Should Go', 'Because youre a wimp', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 1, 2, false, true, 1895726380000, false, null),
  (1, 'Getting Over Some BS', 'Get under some broad', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 1, 3, false, false, null, true, 1195726380000),
  (1, 'Food Finds From Your Moms House', 'Tastes good man', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 1, 1, true, false, null, false, null),
  (1, 'Finding Peace', 'Dont even have to India', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 1, 5, false, false, null, true, 1395726380000),
  (1, 'Scaling the Sky', 'Beat boredom with these journeys', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 2, 1, false, true, 1995726380000, false, null),
  (1, 'Cars, Trains, and Gangs', 'Staying safe on the road is harder than you thought', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 1, 4, false, false, null, true, 1495727380000),
  (1, 'Love Your Life', 'Schmarmy garbage', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 1, 4, false, false, null, true, 1490726380000),
  (1, 'Another Blog Post', 'You better check this shit out', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 1, 2, false, true, 1995726380000, false, null),
  (1, 'Through the Looking Glass', 'Bring your spectacles', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 1, 7, false, false, null, true, 1298726380000);

comment on table pomb.post is 'Table with POMB posts';
comment on column pomb.post.id is 'Primary id for post';
comment on column pomb.post.title is 'Title of the post';
comment on column pomb.post.subtitle is 'Subtitle of post';
comment on column pomb.post.content is 'Content of post';
comment on column pomb.post.is_draft is 'Post is a draft';
comment on column pomb.post.is_scheduled is 'Post is scheduled';
comment on column pomb.post.scheduled_date is 'Date post is scheduled';
comment on column pomb.post.is_published is 'Post is published';
comment on column pomb.post.published_date is 'Date post is published';
comment on column pomb.post.created_at is 'When post created';
comment on column pomb.post.updated_at is 'Last updated date';

alter table pomb.post enable row level security;

create table pomb.post_tag (
  name                text primary key,
  tag_description     text
);

CREATE TRIGGER post_tag_INSERT_UPDATE_DELETE
AFTER INSERT OR UPDATE OR DELETE ON pomb.post_tag
FOR EACH ROW EXECUTE PROCEDURE pomb_private.if_modified_func();

insert into pomb.post_tag (name, tag_description) values
  ('colombia', 'What was once a haven for drugs and violence, Colombia has become a premiere destination for those who seek adventure, beauty, and intrepid charm.'),
  ('buses', 'No easier way to see a place than with your fellow man then round and round'),
  ('diving', 'Underneath the surf is a whole world to explore, find it.'),
  ('camping', 'Have no fear, the camping hub is here. Learn tips for around the site, checkout cool spots, and find how to make the most of your time in the outdoors.'),
  ('food', 'There are few things better than exploring the food on offer throughout the world and in your backyard. The food hub has you covered to find your next craving.'),
  ('sports', 'Theres more than just NFL football out there, lets see what is in store.'),
  ('drinks', 'From fire water, to fine wine, to whiskey from the barrel. Spirits a-plenty to sate any thirst.'),
  ('nightlife', 'Thumping beats, starry sights, and friendly people make a night on the town an integral part of any journey.');

comment on table pomb.post_tag is 'Table with post tags available';
comment on column pomb.post_tag.name is 'Name of the post tag and primary id';
comment on column pomb.post_tag.tag_description is 'Description of the post tag';

alter table pomb.post_tag enable row level security;

create table pomb.post_to_tag ( --one to many
  id                 serial primary key,
  post_id            integer not null references pomb.post(id) on delete cascade,
  post_tag_id        text not null references pomb.post_tag(name) on delete cascade
);

insert into pomb.post_to_tag (post_id, post_tag_id) values
  (1, 'colombia'),
  (1, 'camping'),
  (2, 'diving'),
  (3, 'colombia'),
  (3, 'diving'),
  (3, 'food'),
  (4, 'sports'),
  (4, 'diving'),
  (5, 'camping'),
  (5, 'drinks'),
  (6, 'camping'),
  (7, 'camping'),
  (8, 'colombia'),
  (9, 'colombia'),
  (10, 'drinks'),
  (11, 'nightlife'),
  (11, 'food'),
  (12, 'nightlife'),
  (12, 'diving'),
  (13, 'camping'),
  (13, 'food'),
  (13, 'nightlife');

comment on table pomb.post_to_tag is 'Join table for tags on a post';
comment on column pomb.post_to_tag.id is 'Id of the row';
comment on column pomb.post_to_tag.post_id is 'Id of the post';
comment on column pomb.post_to_tag.post_tag_id is 'Name of the post tag';

create table pomb.coords (
  id                  serial primary key,
  juncture_id         integer not null references pomb.juncture(id) on delete cascade,
  lat                 decimal not null,
  lon                 decimal not null,
  elevation           decimal,
  coord_time          timestamp
);

CREATE TRIGGER coords_INSERT_UPDATE_DELETE
AFTER INSERT OR UPDATE OR DELETE ON pomb.coords
FOR EACH ROW EXECUTE PROCEDURE pomb_private.if_modified_func();

comment on table pomb.coords is 'Table with POMB juncture coordinates';
comment on column pomb.coords.id is 'Primary id for coordinates';
comment on column pomb.coords.juncture_id is 'Foreign key to referred juncture';
comment on column pomb.coords.lat is 'Latitude of coords';
comment on column pomb.coords.lon is 'Longitude of coords';
comment on column pomb.coords.elevation is 'Elevation of coords';
comment on column pomb.coords.coord_time is 'Timestamp of coords';

create table pomb.email_list (
  id                  serial primary key,
  email               text not null unique check (char_length(email) < 256),
  created_at          bigint default (extract(epoch from now()) * 1000)
);

CREATE TRIGGER email_list_INSERT_UPDATE_DELETE
AFTER INSERT OR UPDATE OR DELETE ON pomb.email_list
FOR EACH ROW EXECUTE PROCEDURE pomb_private.if_modified_func();

comment on table pomb.email_list is 'Table with POMB list of emails';
comment on column pomb.email_list.id is 'Primary id for email';
comment on column pomb.email_list.email is 'Email of user';
comment on column pomb.email_list.created_at is 'When email created';

-- Limiting choices for type field on image
create type pomb.image_type as enum (
  'leadLarge',
  'leadSmall',
  'gallery',
  'banner'
);

create table pomb.image (
  id                  serial primary key,
  trip_id             integer references pomb.trip(id) on delete cascade,
  juncture_id         integer references pomb.juncture(id) on delete cascade,
  post_id             integer references pomb.post(id) on delete cascade,
  user_id             integer not null references pomb.account(id) on delete cascade,
  type                pomb.image_type not null,
  url                 text not null,
  title               text check (char_length(title) < 80),
  description         text,
  created_at          bigint default (extract(epoch from now()) * 1000),
  updated_at          timestamp default now()
);

CREATE TRIGGER image_INSERT_UPDATE_DELETE
AFTER INSERT OR UPDATE OR DELETE ON pomb.image
FOR EACH ROW EXECUTE PROCEDURE pomb_private.if_modified_func();

insert into pomb.image (trip_id, juncture_id, post_id, user_id, type, url, title, description) values
  (1, 1, 1, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Colombia commentary'),
  (1, 2, 2, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Biking Bizness'),
  (null, null, 3, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Hiking is neat'),
  (1, 1, 4, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Camping is fun'),
  (null, null, 5, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Food is dope'),
  (null, null, 6, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Travel is lame'),
  (null, null, 7, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 8, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 9, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 10, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 11, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 12, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 13, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Gear snob'),
  (1, 1, 1, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Colombia commentary'),
  (1, 2, 2, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Biking Bizness'),
  (null, null, 3, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Hiking is neat'),
  (1, 1, 4, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Camping is fun'),
  (null, null, 5, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Food is dope'),
  (null, null, 6, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Travel is lame'),
  (null, null, 7, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 8, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 9, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 10, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 11, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 12, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 13, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Gear snob'),
  (1, 1, 1, 1, 'gallery', 'https://d15shllkswkct0.cloudfront.net/wp-content/blogs.dir/1/files/2015/03/1200px-Hommik_Viru_rabas.jpg', null, 'A beautiful vista accented by your mom'),
  (1, 1, 1, 1, 'gallery', 'https://upload.wikimedia.org/wikipedia/commons/c/ce/Lower_Yellowstone_Fall-1200px.jpg', null, 'A beautiful vista accented by your mom'),
  (1, 1, 1, 1, 'gallery', 'http://www.ningalooreefdive.com/wp-content/uploads/2014/01/coralbay-3579-1200px-wm-1.png', null, 'A beautiful vista accented by your mom'),
  (1, 1, 1, 1, 'gallery', 'http://richard-western.co.uk/wp-content/uploads/2015/06/4.-PG9015-30-1200px.jpg', null, 'A beautiful vista accented by your mom'),
  (1, 1, 1, 1, 'gallery', 'http://www.ningalooreefdive.com/wp-content/uploads/2014/10/coralbay-4077-1200px-wm.png', null, 'A beautiful vista accented by your mom'),
  (1, 1, 1, 1, 'gallery', 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/51/Sign_of_Brno_University_of_Technology_at_building_in_Brno%2C_Kr%C3%A1lovo_Pole.jpg/1200px-Sign_of_Brno_University_of_Technology_at_building_in_Brno%2C_Kr%C3%A1lovo_Pole.jpg', null, 'A beautiful vista accented by your mom'),
  (null, null, 3, 1, 'gallery', 'https://d15shllkswkct0.cloudfront.net/wp-content/blogs.dir/1/files/2015/03/1200px-Hommik_Viru_rabas.jpg', null, 'A beautiful vista accented by your mom'),
  (null, null, 3, 1, 'gallery', 'https://d15shllkswkct0.cloudfront.net/wp-content/blogs.dir/1/files/2015/03/1200px-Hommik_Viru_rabas.jpg', null, 'A beautiful vista accented by your mom'),
  (1, null, null, 1, 'banner', 'https://www.yosemitehikes.com/images/wallpaper/yosemitehikes.com-bridalveil-winter-1200x800.jpg', null, null),
  (1, null, null, 1, 'banner', 'https://lonelyplanetimages.imgix.net/a/g/hi/t/4ad86c274b7e632de388dcaca5236ca8-asia.jpg', null, null),
  (1, null, null, 1, 'banner', 'https://lonelyplanetimages.imgix.net/a/g/hi/t/1dd17a448edb6c7ced392c6a7ea1c0ac-asia.jpg', null, null),
  (1, null, null, 1, 'banner', 'https://lonelyplanetimages.imgix.net/a/g/hi/t/b3960ccbee8a59ce113d0cce9f53f283-asia.jpg', null, null),
  (1, 1, null, 1, 'gallery', 'https://d15shllkswkct0.cloudfront.net/wp-content/blogs.dir/1/files/2015/03/1200px-Hommik_Viru_rabas.jpg', null, null),
  (1, 1, null, 1, 'gallery', 'https://upload.wikimedia.org/wikipedia/commons/c/ce/Lower_Yellowstone_Fall-1200px.jpg', null, null),
  (1, 1, null, 1, 'gallery', 'http://www.ningalooreefdive.com/wp-content/uploads/2014/01/coralbay-3579-1200px-wm-1.png', null, null),
  (1, 2, null, 1, 'gallery', 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/51/Sign_of_Brno_University_of_Technology_at_building_in_Brno%2C_Kr%C3%A1lovo_Pole.jpg/1200px-Sign_of_Brno_University_of_Technology_at_building_in_Brno%2C_Kr%C3%A1lovo_Pole.jpg', null, null),
  (1, 3, null, 1, 'gallery', 'https://d15shllkswkct0.cloudfront.net/wp-content/blogs.dir/1/files/2015/03/1200px-Hommik_Viru_rabas.jpg', null, null),
  (1, 3, null, 1, 'gallery', 'http://www.ningalooreefdive.com/wp-content/uploads/2014/01/coralbay-3579-1200px-wm-1.png', null, null);

comment on table pomb.image is 'Table with site images';
comment on column pomb.image.id is 'Primary id for the photo';
comment on column pomb.image.trip_id is 'Primary id of trip its related to';
comment on column pomb.image.juncture_id is 'Primary id of juncture its related to';
comment on column pomb.image.post_id is 'Primary id of post its related to';
comment on column pomb.image.user_id is 'Primary id of user who uploaded image';
comment on column pomb.image.type is 'Type of image';
comment on column pomb.image.url is 'Link to image';
comment on column pomb.image.title is 'Title of image';
comment on column pomb.image.description is 'Description of image';
comment on column pomb.image.created_at is 'Time image created at';
comment on column pomb.image.updated_at is 'Time image updated at';

alter table pomb.image enable row level security;

create table pomb.like (
  id                  serial primary key,
  trip_id             integer references pomb.trip(id) on delete cascade,
  juncture_id         integer references pomb.juncture(id) on delete cascade,
  post_id             integer references pomb.post(id) on delete cascade,
  image_id            integer references pomb.image(id) on delete cascade,
  user_id             integer not null references pomb.account(id) on delete cascade,
  created_at          bigint default (extract(epoch from now()) * 1000)
);

CREATE TRIGGER like_INSERT_UPDATE_DELETE
AFTER INSERT OR UPDATE OR DELETE ON pomb.like
FOR EACH ROW EXECUTE PROCEDURE pomb_private.if_modified_func();

insert into pomb.like (trip_id, juncture_id, post_id, image_id, user_id) values
  (1, null, null, null, 1),
  (null, 1, null, null, 1),
  (null, null, 1, null, 1),
  (null, null, null, 1, 1);

comment on table pomb.like is 'Table with likes for various site assets';
comment on column pomb.like.id is 'Primary id for the like';
comment on column pomb.like.trip_id is 'Primary id of trip its related to';
comment on column pomb.like.juncture_id is 'Primary id of juncture its related to';
comment on column pomb.like.post_id is 'Primary id of post its related to';
comment on column pomb.like.post_id is 'Primary id of image its related to';
comment on column pomb.like.user_id is 'Primary id of user who liked asset';
comment on column pomb.like.created_at is 'Time like created at';

alter table pomb.like enable row level security;

create table pomb.track (
  id                  serial primary key,
  user_id             integer not null references pomb.account(id) on delete cascade,
  track_user_id       integer not null references pomb.account(id) on delete cascade,
  created_at          bigint default (extract(epoch from now()) * 1000)
);

CREATE TRIGGER track_INSERT_UPDATE_DELETE
AFTER INSERT OR UPDATE OR DELETE ON pomb.track
FOR EACH ROW EXECUTE PROCEDURE pomb_private.if_modified_func();

comment on table pomb.track is 'Table with connection between users to track/follow other users';
comment on column pomb.track.id is 'Primary id for the track';
comment on column pomb.track.user_id is 'Primary id of user who is going to track';
comment on column pomb.track.track_user_id is 'Primary id user who will be tracked';
comment on column pomb.track.created_at is 'Time track created at';

alter table pomb.track enable row level security;

create table pomb.config (
  id                  serial primary key,
  primary_color       text not null check (char_length(primary_color) < 20),
  secondary_color     text not null check (char_length(secondary_color) < 20),
  tagline             text not null check (char_length(tagline) < 80),
  hero_banner         text not null,
  featured_story_1    integer not null references pomb.post(id),
  featured_story_2    integer not null references pomb.post(id),
  featured_story_3    integer not null references pomb.post(id),
  featured_trip_1     integer not null references pomb.trip(id),
  updated_at          timestamp default now()
);

CREATE TRIGGER config_INSERT_UPDATE_DELETE
AFTER INSERT OR UPDATE OR DELETE ON pomb.config
FOR EACH ROW EXECUTE PROCEDURE pomb_private.if_modified_func();

insert into pomb.config (primary_color, secondary_color, tagline, hero_banner, featured_story_1, featured_story_2, featured_story_3, featured_trip_1) values
  ('#e1ff00', '#04c960', 'For wherever the road takes you', 'http://www.pinnaclepellet.com/images/1200x300-deep-forest.jpg', 4, 8, 13, 1);


CREATE TABLE pomb.country (code VARCHAR(10) NOT NULL, name VARCHAR(64) NOT NULL, PRIMARY KEY(code));

INSERT INTO pomb.country (code, name) VALUES (E'AF', E'Afghanistan');
INSERT INTO pomb.country (code, name) VALUES (E'AX', E'Åland Islands');
INSERT INTO pomb.country (code, name) VALUES (E'AL', E'Albania');
INSERT INTO pomb.country (code, name) VALUES (E'DZ', E'Algeria');
INSERT INTO pomb.country (code, name) VALUES (E'AS', E'American Samoa');
INSERT INTO pomb.country (code, name) VALUES (E'AD', E'Andorra');
INSERT INTO pomb.country (code, name) VALUES (E'AO', E'Angola');
INSERT INTO pomb.country (code, name) VALUES (E'AI', E'Anguilla');
INSERT INTO pomb.country (code, name) VALUES (E'AQ', E'Antarctica');
INSERT INTO pomb.country (code, name) VALUES (E'AG', E'Antigua & Barbuda');
INSERT INTO pomb.country (code, name) VALUES (E'AR', E'Argentina');
INSERT INTO pomb.country (code, name) VALUES (E'AM', E'Armenia');
INSERT INTO pomb.country (code, name) VALUES (E'AW', E'Aruba');
INSERT INTO pomb.country (code, name) VALUES (E'AC', E'Ascension Island');
INSERT INTO pomb.country (code, name) VALUES (E'AU', E'Australia');
INSERT INTO pomb.country (code, name) VALUES (E'AT', E'Austria');
INSERT INTO pomb.country (code, name) VALUES (E'AZ', E'Azerbaijan');
INSERT INTO pomb.country (code, name) VALUES (E'BS', E'Bahamas');
INSERT INTO pomb.country (code, name) VALUES (E'BH', E'Bahrain');
INSERT INTO pomb.country (code, name) VALUES (E'BD', E'Bangladesh');
INSERT INTO pomb.country (code, name) VALUES (E'BB', E'Barbados');
INSERT INTO pomb.country (code, name) VALUES (E'BY', E'Belarus');
INSERT INTO pomb.country (code, name) VALUES (E'BE', E'Belgium');
INSERT INTO pomb.country (code, name) VALUES (E'BZ', E'Belize');
INSERT INTO pomb.country (code, name) VALUES (E'BJ', E'Benin');
INSERT INTO pomb.country (code, name) VALUES (E'BM', E'Bermuda');
INSERT INTO pomb.country (code, name) VALUES (E'BT', E'Bhutan');
INSERT INTO pomb.country (code, name) VALUES (E'BO', E'Bolivia');
INSERT INTO pomb.country (code, name) VALUES (E'BA', E'Bosnia & Herzegovina');
INSERT INTO pomb.country (code, name) VALUES (E'BW', E'Botswana');
INSERT INTO pomb.country (code, name) VALUES (E'BR', E'Brazil');
INSERT INTO pomb.country (code, name) VALUES (E'IO', E'British Indian Ocean Territory');
INSERT INTO pomb.country (code, name) VALUES (E'VG', E'British Virgin Islands');
INSERT INTO pomb.country (code, name) VALUES (E'BN', E'Brunei');
INSERT INTO pomb.country (code, name) VALUES (E'BG', E'Bulgaria');
INSERT INTO pomb.country (code, name) VALUES (E'BF', E'Burkina Faso');
INSERT INTO pomb.country (code, name) VALUES (E'BI', E'Burundi');
INSERT INTO pomb.country (code, name) VALUES (E'KH', E'Cambodia');
INSERT INTO pomb.country (code, name) VALUES (E'CM', E'Cameroon');
INSERT INTO pomb.country (code, name) VALUES (E'CA', E'Canada');
INSERT INTO pomb.country (code, name) VALUES (E'IC', E'Canary Islands');
INSERT INTO pomb.country (code, name) VALUES (E'CV', E'Cape Verde');
INSERT INTO pomb.country (code, name) VALUES (E'BQ', E'Caribbean Netherlands');
INSERT INTO pomb.country (code, name) VALUES (E'KY', E'Cayman Islands');
INSERT INTO pomb.country (code, name) VALUES (E'CF', E'Central African Republic');
INSERT INTO pomb.country (code, name) VALUES (E'EA', E'Ceuta & Melilla');
INSERT INTO pomb.country (code, name) VALUES (E'TD', E'Chad');
INSERT INTO pomb.country (code, name) VALUES (E'CL', E'Chile');
INSERT INTO pomb.country (code, name) VALUES (E'CN', E'China');
INSERT INTO pomb.country (code, name) VALUES (E'CX', E'Christmas Island');
INSERT INTO pomb.country (code, name) VALUES (E'CC', E'Cocos (Keeling) Islands');
INSERT INTO pomb.country (code, name) VALUES (E'CO', E'Colombia');
INSERT INTO pomb.country (code, name) VALUES (E'KM', E'Comoros');
INSERT INTO pomb.country (code, name) VALUES (E'CG', E'Congo - Brazzaville');
INSERT INTO pomb.country (code, name) VALUES (E'CD', E'Congo - Kinshasa');
INSERT INTO pomb.country (code, name) VALUES (E'CK', E'Cook Islands');
INSERT INTO pomb.country (code, name) VALUES (E'CR', E'Costa Rica');
INSERT INTO pomb.country (code, name) VALUES (E'CI', E'Côte d’Ivoire');
INSERT INTO pomb.country (code, name) VALUES (E'HR', E'Croatia');
INSERT INTO pomb.country (code, name) VALUES (E'CU', E'Cuba');
INSERT INTO pomb.country (code, name) VALUES (E'CW', E'Curaçao');
INSERT INTO pomb.country (code, name) VALUES (E'CY', E'Cyprus');
INSERT INTO pomb.country (code, name) VALUES (E'CZ', E'Czechia');
INSERT INTO pomb.country (code, name) VALUES (E'DK', E'Denmark');
INSERT INTO pomb.country (code, name) VALUES (E'DG', E'Diego Garcia');
INSERT INTO pomb.country (code, name) VALUES (E'DJ', E'Djibouti');
INSERT INTO pomb.country (code, name) VALUES (E'DM', E'Dominica');
INSERT INTO pomb.country (code, name) VALUES (E'DO', E'Dominican Republic');
INSERT INTO pomb.country (code, name) VALUES (E'EC', E'Ecuador');
INSERT INTO pomb.country (code, name) VALUES (E'EG', E'Egypt');
INSERT INTO pomb.country (code, name) VALUES (E'SV', E'El Salvador');
INSERT INTO pomb.country (code, name) VALUES (E'GQ', E'Equatorial Guinea');
INSERT INTO pomb.country (code, name) VALUES (E'ER', E'Eritrea');
INSERT INTO pomb.country (code, name) VALUES (E'EE', E'Estonia');
INSERT INTO pomb.country (code, name) VALUES (E'ET', E'Ethiopia');
INSERT INTO pomb.country (code, name) VALUES (E'EZ', E'Eurozone');
INSERT INTO pomb.country (code, name) VALUES (E'FK', E'Falkland Islands');
INSERT INTO pomb.country (code, name) VALUES (E'FO', E'Faroe Islands');
INSERT INTO pomb.country (code, name) VALUES (E'FJ', E'Fiji');
INSERT INTO pomb.country (code, name) VALUES (E'FI', E'Finland');
INSERT INTO pomb.country (code, name) VALUES (E'FR', E'France');
INSERT INTO pomb.country (code, name) VALUES (E'GF', E'French Guiana');
INSERT INTO pomb.country (code, name) VALUES (E'PF', E'French Polynesia');
INSERT INTO pomb.country (code, name) VALUES (E'TF', E'French Southern Territories');
INSERT INTO pomb.country (code, name) VALUES (E'GA', E'Gabon');
INSERT INTO pomb.country (code, name) VALUES (E'GM', E'Gambia');
INSERT INTO pomb.country (code, name) VALUES (E'GE', E'Georgia');
INSERT INTO pomb.country (code, name) VALUES (E'DE', E'Germany');
INSERT INTO pomb.country (code, name) VALUES (E'GH', E'Ghana');
INSERT INTO pomb.country (code, name) VALUES (E'GI', E'Gibraltar');
INSERT INTO pomb.country (code, name) VALUES (E'GR', E'Greece');
INSERT INTO pomb.country (code, name) VALUES (E'GL', E'Greenland');
INSERT INTO pomb.country (code, name) VALUES (E'GD', E'Grenada');
INSERT INTO pomb.country (code, name) VALUES (E'GP', E'Guadeloupe');
INSERT INTO pomb.country (code, name) VALUES (E'GU', E'Guam');
INSERT INTO pomb.country (code, name) VALUES (E'GT', E'Guatemala');
INSERT INTO pomb.country (code, name) VALUES (E'GG', E'Guernsey');
INSERT INTO pomb.country (code, name) VALUES (E'GN', E'Guinea');
INSERT INTO pomb.country (code, name) VALUES (E'GW', E'Guinea-Bissau');
INSERT INTO pomb.country (code, name) VALUES (E'GY', E'Guyana');
INSERT INTO pomb.country (code, name) VALUES (E'HT', E'Haiti');
INSERT INTO pomb.country (code, name) VALUES (E'HN', E'Honduras');
INSERT INTO pomb.country (code, name) VALUES (E'HK', E'Hong Kong SAR China');
INSERT INTO pomb.country (code, name) VALUES (E'HU', E'Hungary');
INSERT INTO pomb.country (code, name) VALUES (E'IS', E'Iceland');
INSERT INTO pomb.country (code, name) VALUES (E'IN', E'India');
INSERT INTO pomb.country (code, name) VALUES (E'ID', E'Indonesia');
INSERT INTO pomb.country (code, name) VALUES (E'IR', E'Iran');
INSERT INTO pomb.country (code, name) VALUES (E'IQ', E'Iraq');
INSERT INTO pomb.country (code, name) VALUES (E'IE', E'Ireland');
INSERT INTO pomb.country (code, name) VALUES (E'IM', E'Isle of Man');
INSERT INTO pomb.country (code, name) VALUES (E'IL', E'Israel');
INSERT INTO pomb.country (code, name) VALUES (E'IT', E'Italy');
INSERT INTO pomb.country (code, name) VALUES (E'JM', E'Jamaica');
INSERT INTO pomb.country (code, name) VALUES (E'JP', E'Japan');
INSERT INTO pomb.country (code, name) VALUES (E'JE', E'Jersey');
INSERT INTO pomb.country (code, name) VALUES (E'JO', E'Jordan');
INSERT INTO pomb.country (code, name) VALUES (E'KZ', E'Kazakhstan');
INSERT INTO pomb.country (code, name) VALUES (E'KE', E'Kenya');
INSERT INTO pomb.country (code, name) VALUES (E'KI', E'Kiribati');
INSERT INTO pomb.country (code, name) VALUES (E'XK', E'Kosovo');
INSERT INTO pomb.country (code, name) VALUES (E'KW', E'Kuwait');
INSERT INTO pomb.country (code, name) VALUES (E'KG', E'Kyrgyzstan');
INSERT INTO pomb.country (code, name) VALUES (E'LA', E'Laos');
INSERT INTO pomb.country (code, name) VALUES (E'LV', E'Latvia');
INSERT INTO pomb.country (code, name) VALUES (E'LB', E'Lebanon');
INSERT INTO pomb.country (code, name) VALUES (E'LS', E'Lesotho');
INSERT INTO pomb.country (code, name) VALUES (E'LR', E'Liberia');
INSERT INTO pomb.country (code, name) VALUES (E'LY', E'Libya');
INSERT INTO pomb.country (code, name) VALUES (E'LI', E'Liechtenstein');
INSERT INTO pomb.country (code, name) VALUES (E'LT', E'Lithuania');
INSERT INTO pomb.country (code, name) VALUES (E'LU', E'Luxembourg');
INSERT INTO pomb.country (code, name) VALUES (E'MO', E'Macau SAR China');
INSERT INTO pomb.country (code, name) VALUES (E'MK', E'Macedonia');
INSERT INTO pomb.country (code, name) VALUES (E'MG', E'Madagascar');
INSERT INTO pomb.country (code, name) VALUES (E'MW', E'Malawi');
INSERT INTO pomb.country (code, name) VALUES (E'MY', E'Malaysia');
INSERT INTO pomb.country (code, name) VALUES (E'MV', E'Maldives');
INSERT INTO pomb.country (code, name) VALUES (E'ML', E'Mali');
INSERT INTO pomb.country (code, name) VALUES (E'MT', E'Malta');
INSERT INTO pomb.country (code, name) VALUES (E'MH', E'Marshall Islands');
INSERT INTO pomb.country (code, name) VALUES (E'MQ', E'Martinique');
INSERT INTO pomb.country (code, name) VALUES (E'MR', E'Mauritania');
INSERT INTO pomb.country (code, name) VALUES (E'MU', E'Mauritius');
INSERT INTO pomb.country (code, name) VALUES (E'YT', E'Mayotte');
INSERT INTO pomb.country (code, name) VALUES (E'MX', E'Mexico');
INSERT INTO pomb.country (code, name) VALUES (E'FM', E'Micronesia');
INSERT INTO pomb.country (code, name) VALUES (E'MD', E'Moldova');
INSERT INTO pomb.country (code, name) VALUES (E'MC', E'Monaco');
INSERT INTO pomb.country (code, name) VALUES (E'MN', E'Mongolia');
INSERT INTO pomb.country (code, name) VALUES (E'ME', E'Montenegro');
INSERT INTO pomb.country (code, name) VALUES (E'MS', E'Montserrat');
INSERT INTO pomb.country (code, name) VALUES (E'MA', E'Morocco');
INSERT INTO pomb.country (code, name) VALUES (E'MZ', E'Mozambique');
INSERT INTO pomb.country (code, name) VALUES (E'MM', E'Myanmar (Burma)');
INSERT INTO pomb.country (code, name) VALUES (E'NA', E'Namibia');
INSERT INTO pomb.country (code, name) VALUES (E'NR', E'Nauru');
INSERT INTO pomb.country (code, name) VALUES (E'NP', E'Nepal');
INSERT INTO pomb.country (code, name) VALUES (E'NL', E'Netherlands');
INSERT INTO pomb.country (code, name) VALUES (E'NC', E'New Caledonia');
INSERT INTO pomb.country (code, name) VALUES (E'NZ', E'New Zealand');
INSERT INTO pomb.country (code, name) VALUES (E'NI', E'Nicaragua');
INSERT INTO pomb.country (code, name) VALUES (E'NE', E'Niger');
INSERT INTO pomb.country (code, name) VALUES (E'NG', E'Nigeria');
INSERT INTO pomb.country (code, name) VALUES (E'NU', E'Niue');
INSERT INTO pomb.country (code, name) VALUES (E'NF', E'Norfolk Island');
INSERT INTO pomb.country (code, name) VALUES (E'KP', E'North Korea');
INSERT INTO pomb.country (code, name) VALUES (E'MP', E'Northern Mariana Islands');
INSERT INTO pomb.country (code, name) VALUES (E'NO', E'Norway');
INSERT INTO pomb.country (code, name) VALUES (E'OM', E'Oman');
INSERT INTO pomb.country (code, name) VALUES (E'PK', E'Pakistan');
INSERT INTO pomb.country (code, name) VALUES (E'PW', E'Palau');
INSERT INTO pomb.country (code, name) VALUES (E'PS', E'Palestinian Territories');
INSERT INTO pomb.country (code, name) VALUES (E'PA', E'Panama');
INSERT INTO pomb.country (code, name) VALUES (E'PG', E'Papua New Guinea');
INSERT INTO pomb.country (code, name) VALUES (E'PY', E'Paraguay');
INSERT INTO pomb.country (code, name) VALUES (E'PE', E'Peru');
INSERT INTO pomb.country (code, name) VALUES (E'PH', E'Philippines');
INSERT INTO pomb.country (code, name) VALUES (E'PN', E'Pitcairn Islands');
INSERT INTO pomb.country (code, name) VALUES (E'PL', E'Poland');
INSERT INTO pomb.country (code, name) VALUES (E'PT', E'Portugal');
INSERT INTO pomb.country (code, name) VALUES (E'PR', E'Puerto Rico');
INSERT INTO pomb.country (code, name) VALUES (E'QA', E'Qatar');
INSERT INTO pomb.country (code, name) VALUES (E'RE', E'Réunion');
INSERT INTO pomb.country (code, name) VALUES (E'RO', E'Romania');
INSERT INTO pomb.country (code, name) VALUES (E'RU', E'Russia');
INSERT INTO pomb.country (code, name) VALUES (E'RW', E'Rwanda');
INSERT INTO pomb.country (code, name) VALUES (E'WS', E'Samoa');
INSERT INTO pomb.country (code, name) VALUES (E'SM', E'San Marino');
INSERT INTO pomb.country (code, name) VALUES (E'ST', E'São Tomé & Príncipe');
INSERT INTO pomb.country (code, name) VALUES (E'SA', E'Saudi Arabia');
INSERT INTO pomb.country (code, name) VALUES (E'SN', E'Senegal');
INSERT INTO pomb.country (code, name) VALUES (E'RS', E'Serbia');
INSERT INTO pomb.country (code, name) VALUES (E'SC', E'Seychelles');
INSERT INTO pomb.country (code, name) VALUES (E'SL', E'Sierra Leone');
INSERT INTO pomb.country (code, name) VALUES (E'SG', E'Singapore');
INSERT INTO pomb.country (code, name) VALUES (E'SX', E'Sint Maarten');
INSERT INTO pomb.country (code, name) VALUES (E'SK', E'Slovakia');
INSERT INTO pomb.country (code, name) VALUES (E'SI', E'Slovenia');
INSERT INTO pomb.country (code, name) VALUES (E'SB', E'Solomon Islands');
INSERT INTO pomb.country (code, name) VALUES (E'SO', E'Somalia');
INSERT INTO pomb.country (code, name) VALUES (E'ZA', E'South Africa');
INSERT INTO pomb.country (code, name) VALUES (E'GS', E'South Georgia & South Sandwich Islands');
INSERT INTO pomb.country (code, name) VALUES (E'KR', E'South Korea');
INSERT INTO pomb.country (code, name) VALUES (E'SS', E'South Sudan');
INSERT INTO pomb.country (code, name) VALUES (E'ES', E'Spain');
INSERT INTO pomb.country (code, name) VALUES (E'LK', E'Sri Lanka');
INSERT INTO pomb.country (code, name) VALUES (E'BL', E'St. Barthélemy');
INSERT INTO pomb.country (code, name) VALUES (E'SH', E'St. Helena');
INSERT INTO pomb.country (code, name) VALUES (E'KN', E'St. Kitts & Nevis');
INSERT INTO pomb.country (code, name) VALUES (E'LC', E'St. Lucia');
INSERT INTO pomb.country (code, name) VALUES (E'MF', E'St. Martin');
INSERT INTO pomb.country (code, name) VALUES (E'PM', E'St. Pierre & Miquelon');
INSERT INTO pomb.country (code, name) VALUES (E'VC', E'St. Vincent & Grenadines');
INSERT INTO pomb.country (code, name) VALUES (E'SD', E'Sudan');
INSERT INTO pomb.country (code, name) VALUES (E'SR', E'Suriname');
INSERT INTO pomb.country (code, name) VALUES (E'SJ', E'Svalbard & Jan Mayen');
INSERT INTO pomb.country (code, name) VALUES (E'SZ', E'Swaziland');
INSERT INTO pomb.country (code, name) VALUES (E'SE', E'Sweden');
INSERT INTO pomb.country (code, name) VALUES (E'CH', E'Switzerland');
INSERT INTO pomb.country (code, name) VALUES (E'SY', E'Syria');
INSERT INTO pomb.country (code, name) VALUES (E'TW', E'Taiwan');
INSERT INTO pomb.country (code, name) VALUES (E'TJ', E'Tajikistan');
INSERT INTO pomb.country (code, name) VALUES (E'TZ', E'Tanzania');
INSERT INTO pomb.country (code, name) VALUES (E'TH', E'Thailand');
INSERT INTO pomb.country (code, name) VALUES (E'TL', E'Timor-Leste');
INSERT INTO pomb.country (code, name) VALUES (E'TG', E'Togo');
INSERT INTO pomb.country (code, name) VALUES (E'TK', E'Tokelau');
INSERT INTO pomb.country (code, name) VALUES (E'TO', E'Tonga');
INSERT INTO pomb.country (code, name) VALUES (E'TT', E'Trinidad & Tobago');
INSERT INTO pomb.country (code, name) VALUES (E'TA', E'Tristan da Cunha');
INSERT INTO pomb.country (code, name) VALUES (E'TN', E'Tunisia');
INSERT INTO pomb.country (code, name) VALUES (E'TR', E'Turkey');
INSERT INTO pomb.country (code, name) VALUES (E'TM', E'Turkmenistan');
INSERT INTO pomb.country (code, name) VALUES (E'TC', E'Turks & Caicos Islands');
INSERT INTO pomb.country (code, name) VALUES (E'TV', E'Tuvalu');
INSERT INTO pomb.country (code, name) VALUES (E'UM', E'U.S. Outlying Islands');
INSERT INTO pomb.country (code, name) VALUES (E'VI', E'U.S. Virgin Islands');
INSERT INTO pomb.country (code, name) VALUES (E'UG', E'Uganda');
INSERT INTO pomb.country (code, name) VALUES (E'UA', E'Ukraine');
INSERT INTO pomb.country (code, name) VALUES (E'AE', E'United Arab Emirates');
INSERT INTO pomb.country (code, name) VALUES (E'GB', E'United Kingdom');
INSERT INTO pomb.country (code, name) VALUES (E'UN', E'United Nations');
INSERT INTO pomb.country (code, name) VALUES (E'US', E'United States');
INSERT INTO pomb.country (code, name) VALUES (E'UY', E'Uruguay');
INSERT INTO pomb.country (code, name) VALUES (E'UZ', E'Uzbekistan');
INSERT INTO pomb.country (code, name) VALUES (E'VU', E'Vanuatu');
INSERT INTO pomb.country (code, name) VALUES (E'VA', E'Vatican City');
INSERT INTO pomb.country (code, name) VALUES (E'VE', E'Venezuela');
INSERT INTO pomb.country (code, name) VALUES (E'VN', E'Vietnam');
INSERT INTO pomb.country (code, name) VALUES (E'WF', E'Wallis & Futuna');
INSERT INTO pomb.country (code, name) VALUES (E'EH', E'Western Sahara');
INSERT INTO pomb.country (code, name) VALUES (E'YE', E'Yemen');
INSERT INTO pomb.country (code, name) VALUES (E'ZM', E'Zambia');
INSERT INTO pomb.country (code, name) VALUES (E'ZW', E'Zimbabwe');

CREATE TABLE pomb.user_to_country (
  id                  serial primary key,
  user_id             integer not null references pomb.account(id) on delete cascade,
  country             VARCHAR not null references pomb.country(code) on delete cascade,
  created_at          timestamp default now()
);

CREATE TRIGGER user_to_country_INSERT_UPDATE_DELETE
AFTER INSERT OR DELETE ON pomb.user_to_country
FOR EACH ROW EXECUTE PROCEDURE pomb_private.if_modified_func();

insert into pomb.user_to_country (user_id, country) values
  (1, 'CN'),
  (1, 'US'),
  (1, 'CA'),
  (1, 'AU'),
  (1, 'SA'),
  (1, 'RU');

comment on table pomb.user_to_country is 'Table with user to country one to many';
comment on column pomb.user_to_country.id is 'Id for user to country connection';
comment on column pomb.user_to_country.user_id is 'user of connection';
comment on column pomb.user_to_country.country is 'Country user has visited';
comment on column pomb.user_to_country.created_at is 'Timestamp connection created';

alter table pomb.user_to_country enable row level security;
-- *******************************************************************
-- *********************** Function Queries **************************
-- *******************************************************************
create function pomb.search_tags(query text) returns setof pomb.post_tag as $$
  select post_tag.*
  from pomb.post_tag as post_tag
  where post_tag.name ilike ('%' || query || '%')
$$ language sql stable;

comment on function pomb.search_tags(text) is 'Returns tags containing a given query term.';

-- *******************************************************************
-- ************************* Triggers ********************************
-- *******************************************************************
create function pomb_private.set_updated_at() returns trigger as $$
begin
  new.updated_at := current_timestamp;
  return new;
end;
$$ language plpgsql;

create trigger post_updated_at before update
  on pomb.post
  for each row
  execute procedure pomb_private.set_updated_at();

create trigger account_updated_at before update
  on pomb.account
  for each row
  execute procedure pomb_private.set_updated_at();

create trigger config_updated_at before update
  on pomb.config
  for each row
  execute procedure pomb_private.set_updated_at();

create trigger trip_updated_at before update
  on pomb.trip
  for each row
  execute procedure pomb_private.set_updated_at();

create trigger juncture_updated_at before update
  on pomb.juncture
  for each row
  execute procedure pomb_private.set_updated_at();

create trigger image_updated_at before update
  on pomb.image
  for each row
  execute procedure pomb_private.set_updated_at();

-- *******************************************************************
-- *********************** FTS ***************************************
-- *******************************************************************

-- Once an index is created, no further intervention is required: the system will update the index when the table is modified, and it will use the index in queries when it 
-- thinks doing so would be more efficient than a sequential table scan. But you might have to run the ANALYZE command regularly to update statistics to allow the query planner 
-- to make educated decisions. See Chapter 14 for information about how to find out whether an index is used and when and why the planner might choose not to use an index.

-- Below creates a materialized view to allow for indexing across tables

CREATE MATERIALIZED VIEW pomb.post_search_index AS
SELECT pomb.post.*,
  setweight(to_tsvector('english', pomb.post.title), 'A') || 
  setweight(to_tsvector('english', pomb.post.subtitle), 'B') ||
  setweight(to_tsvector('english', pomb.post.content), 'C') ||
  setweight(to_tsvector('english', pomb.post_tag.name), 'D') as document
FROM pomb.post
JOIN pomb.post_to_tag ON pomb.post_to_tag.post_id = pomb.post.id
JOIN pomb.post_tag ON pomb.post_tag.name = pomb.post_to_tag.post_tag_id
GROUP BY pomb.post.id, pomb.post_tag.name; 

CREATE INDEX idx_post_search ON pomb.post_search_index USING gin(document);

-- Then reindexing the search engine will be as simple as periodically running REFRESH MATERIALIZED VIEW post_search_index;

-- Trip search searches through trips && junctures

CREATE MATERIALIZED VIEW pomb.trip_search_index AS
SELECT pomb.trip.*,
  setweight(to_tsvector('english', pomb.trip.name), 'A') ||
  setweight(to_tsvector('english', pomb.juncture.name), 'B') ||
  setweight(to_tsvector('english', pomb.juncture.description), 'C') ||
  setweight(to_tsvector('english', pomb.juncture.city), 'D') ||
  setweight(to_tsvector('english', pomb.juncture.country), 'D') as document
FROM pomb.trip
JOIN pomb.juncture ON pomb.juncture.trip_id = pomb.trip.id
GROUP BY pomb.trip.id, pomb.juncture.id;

CREATE INDEX idx_trip_search ON pomb.trip_search_index USING gin(document);

CREATE MATERIALIZED VIEW pomb.account_search_index AS
SELECT pomb.account.*,
  setweight(to_tsvector('english', pomb.account.username), 'A') ||
  setweight(to_tsvector('english', pomb.account.first_name), 'B') ||
  setweight(to_tsvector('english', pomb.account.last_name), 'B') as document
FROM pomb.account;

CREATE INDEX idx_account_search ON pomb.account_search_index USING gin(document);

-- Simple (instead of english) is one of the built in search text configs that Postgres provides. simple doesn't ignore stopwords and doesn't try to find the stem of the word. 
-- With simple every group of characters separated by a space is a lexeme; the simple text search config is pratical for data like a person's name for which we may not want to find the stem of the word.

create function pomb.search_posts(query text) returns setof pomb.post_search_index as $$

  SELECT post FROM (
    SELECT DISTINCT ON(post.id) post, max(ts_rank(document, to_tsquery('english', query)))
      FROM pomb.post_search_index as post
      WHERE document @@ to_tsquery('english', query)
    GROUP BY post.id, post.*
    order by post.id, max DESC
  ) search_results
  order by search_results.max DESC;

$$ language sql stable;

comment on function pomb.search_posts(text) is 'Returns posts given a search term.';

create function pomb.search_trips(query text) returns setof pomb.trip_search_index as $$

  SELECT trip FROM (
    SELECT DISTINCT ON(trip.id) trip, max(ts_rank(document, to_tsquery('english', query)))
      FROM pomb.trip_search_index as trip
      WHERE document @@ to_tsquery('english', query)
    GROUP BY trip.id, trip.*
    order by trip.id, max DESC
  ) search_results
  order by search_results.max DESC;

$$ language sql stable;

comment on function pomb.search_trips(text) is 'Returns trips given a search term.';

create function pomb.search_accounts(query text) returns setof pomb.account_search_index as $$

  SELECT account FROM (
    SELECT DISTINCT ON(account.id) account, max(ts_rank(document, to_tsquery('english', query)))
      FROM pomb.account_search_index as account
      WHERE document @@ to_tsquery('english', query)
    GROUP BY account.id, account.*
    order by account.id, max DESC
  ) search_results
  order by search_results.max DESC;

$$ language sql stable;

comment on function pomb.search_accounts(text) is 'Returns accounts given a search term.';

-- *******************************************************************
-- ************************* Auth ************************************
-- *******************************************************************

create table pomb_private.user_account (
  account_id          integer primary key references pomb.account(id) on delete cascade,
  email               text not null unique check (email ~* '^.+@.+\..+$'),
  password_hash       text not null
);

CREATE TRIGGER user_account_INSERT_UPDATE_DELETE
AFTER INSERT OR UPDATE OR DELETE ON pomb_private.user_account
FOR EACH ROW EXECUTE PROCEDURE pomb_private.if_modified_func();

comment on table pomb_private.user_account is 'Private information about a user’s account.';
comment on column pomb_private.user_account.account_id is 'The id of the user associated with this account.';
comment on column pomb_private.user_account.email is 'The email address of the account.';
comment on column pomb_private.user_account.password_hash is 'An opaque hash of the account’s password.';

create extension if not exists "pgcrypto";

create function pomb.register_account (
  username            text,
  first_name          text,
  last_name           text,
  email               text,
  password            text
) returns pomb.account as $$
declare
  account pomb.account;
begin
  insert into pomb.account (username, first_name, last_name) values
    (username, first_name, last_name)
    returning * into account;

  insert into pomb_private.user_account (account_id, email, password_hash) values
    (account.id, email, crypt(password, gen_salt('bf')));

  return account;
end;
$$ language plpgsql strict security definer;

comment on function pomb.register_account(text, text, text, text, text) is 'Registers and creates an account for POMB.';

create function pomb.update_password(
  user_id integer,
  password text,
  new_password text
) returns boolean as $$
declare
  account pomb_private.user_account;
begin
  select a.* into account
  from pomb_private.user_account as a
  where a.account_id = $1;

  if account.password_hash = crypt(password, account.password_hash) then
    UPDATE pomb_private.user_account set password_hash = crypt(new_password, gen_salt('bf')) where pomb_private.user_account.account_id = $1;
    return true;
  else
    return false;
  end if;
end;
$$ language plpgsql strict security definer;

comment on function pomb.update_password(integer, text, text) is 'Updates the password of a user.';

create function pomb.reset_password(
  email text
) returns TEXT as $$
DECLARE account pomb_private.user_account;
DECLARE randomString TEXT;
begin
  select a.* into account
  from pomb_private.user_account as a
  where a.email = $1;

  randomString := md5(random()::text);
  -- check and see if user exists
  if account.email = email then
    UPDATE pomb_private.user_account set password_hash = crypt(randomString, gen_salt('bf')) where pomb_private.user_account.email = $1;
    return randomString;
  else
    return "user does not exist";
  end if; 
end;
$$ language plpgsql strict security definer;

comment on function pomb.reset_password(text) is 'Reset the password of a user.';

-- *******************************************************************
-- ************************* Roles ************************************
-- *******************************************************************

create role pomb_admin login password 'abc123';
GRANT ALL privileges ON ALL TABLES IN SCHEMA pomb to pomb_admin;
GRANT ALL privileges ON ALL TABLES IN SCHEMA pomb_private to pomb_admin;

create role pomb_anonymous login password 'abc123' NOINHERIT;
GRANT pomb_anonymous to pomb_admin; --Now, the pomb_admin role can control and become the pomb_anonymous role. If we did not use that GRANT, we could not change into the pomb_anonymous role in PostGraphQL.

create role pomb_account;
GRANT pomb_account to pomb_admin; --The pomb_admin role will have all of the permissions of the roles GRANTed to it. So it can do everything pomb_anonymous can do and everything pomb_usercan do.
GRANT pomb_account to pomb_anonymous; 

create type pomb.jwt_token as (
  role text,
  account_id integer
);

alter database bclynch set "jwt.claims.account_id" to '0';

create function pomb.authenticate_account(
  email text,
  password text
) returns pomb.jwt_token as $$
declare
  account pomb_private.user_account;
begin
  select a.* into account
  from pomb_private.user_account as a
  where a.email = $1;

  if account.password_hash = crypt(password, account.password_hash) then
    return ('pomb_account', account.account_id)::pomb.jwt_token;
  else
    return null;
  end if;
end;
$$ language plpgsql strict security definer;

comment on function pomb.authenticate_account(text, text) is 'Creates a JWT token that will securely identify an account and give them certain permissions.';

create function pomb.current_account() returns pomb.account as $$
  select *
  from pomb.account
  where pomb.account.id = current_setting('jwt.claims.account_id', true)::integer
$$ language sql stable;

comment on function pomb.current_account() is 'Gets the account that was identified by our JWT.';

-- *******************************************************************
-- ************************* Security *********************************
-- *******************************************************************

GRANT usage on schema pomb to pomb_anonymous, pomb_account;
GRANT usage on all sequences in schema pomb to pomb_account;

GRANT ALL on table pomb.post_to_tag to pomb_account; --ultimately needs to be policy in which only own user!
GRANT ALL ON TABLE pomb.coords TO PUBLIC; --Need to figure this out... Inserting from node
GRANT SELECT, INSERT ON TABLE pomb.email_list TO PUBLIC;

GRANT SELECT ON TABLE pomb.post_to_tag to PUBLIC;
GRANT SELECT ON TABLE pomb.country to PUBLIC;

GRANT ALL on table pomb.config to PUBLIC; -- ultimately needs to only be admin account that can mod
GRANT select on pomb.post_search_index to PUBLIC;
GRANT select on pomb.trip_search_index to PUBLIC;
GRANT select on pomb.account_search_index to PUBLIC;

GRANT execute on function pomb.register_account(text, text, text, text, text) to pomb_anonymous;
GRANT execute on function pomb.update_password(integer, text, text) to pomb_account;
GRANT execute on function pomb.reset_password(text) to pomb_anonymous, pomb_account;
GRANT execute on function pomb.authenticate_account(text, text) to pomb_anonymous;
GRANT execute on function pomb.current_account() to PUBLIC;
GRANT execute on function pomb.search_tags(text) to PUBLIC;
GRANT execute on function pomb.search_posts(text) to PUBLIC;
GRANT execute on function pomb.search_trips(text) to PUBLIC; 
GRANT execute on function pomb.search_accounts(text) to PUBLIC;  

-- ///////////////// RLS Policies ////////////////////////////////

-- Account policy
GRANT ALL ON TABLE pomb.account TO pomb_account, pomb_anonymous;
CREATE POLICY select_account ON pomb.account for SELECT TO pomb_account, pomb_anonymous
  USING (true);
CREATE POLICY insert_account ON pomb.account for INSERT TO pomb_anonymous
  WITH CHECK (true);
CREATE POLICY update_account ON pomb.account for UPDATE TO pomb_account
  USING (id = current_setting('jwt.claims.account_id')::INTEGER);
CREATE POLICY delete_account ON pomb.account for DELETE TO pomb_account
  USING (id = current_setting('jwt.claims.account_id')::INTEGER);

-- Trips policy
GRANT ALL ON TABLE pomb.trip TO pomb_account, pomb_anonymous;
CREATE POLICY select_trip ON pomb.trip for SELECT TO pomb_account, pomb_anonymous
  USING (true);
CREATE POLICY insert_trip ON pomb.trip for INSERT TO pomb_account
  WITH CHECK (user_id = current_setting('jwt.claims.account_id')::INTEGER);
CREATE POLICY update_trip ON pomb.trip for UPDATE TO pomb_account
  USING (user_id = current_setting('jwt.claims.account_id')::INTEGER);
CREATE POLICY delete_trip ON pomb.trip for DELETE TO pomb_account
  USING (user_id = current_setting('jwt.claims.account_id')::INTEGER);

-- Junctures policy
GRANT ALL ON TABLE pomb.juncture TO pomb_account, pomb_anonymous;
CREATE POLICY select_juncture ON pomb.juncture for SELECT TO pomb_account, pomb_anonymous
  USING (true);
CREATE POLICY insert_juncture ON pomb.juncture for INSERT TO pomb_account
  WITH CHECK (user_id = current_setting('jwt.claims.account_id')::INTEGER);
CREATE POLICY update_juncture ON pomb.juncture for UPDATE TO pomb_account
  USING (user_id = current_setting('jwt.claims.account_id')::INTEGER);
CREATE POLICY delete_juncture ON pomb.juncture for DELETE TO pomb_account
  USING (user_id = current_setting('jwt.claims.account_id')::INTEGER);

-- Posts policy
GRANT ALL ON TABLE pomb.post TO pomb_account, pomb_anonymous;
CREATE POLICY select_post ON pomb.post for SELECT TO pomb_account, pomb_anonymous
  USING (true);
CREATE POLICY insert_post ON pomb.post for INSERT TO pomb_account
  WITH CHECK (author = current_setting('jwt.claims.account_id')::INTEGER);
CREATE POLICY update_post ON pomb.post for UPDATE TO pomb_account
  USING (author = current_setting('jwt.claims.account_id')::INTEGER);
CREATE POLICY delete_post ON pomb.post for DELETE TO pomb_account
  USING (author = current_setting('jwt.claims.account_id')::INTEGER);

-- Images policy
GRANT ALL ON TABLE pomb.image TO pomb_account, pomb_anonymous;
CREATE POLICY select_image ON pomb.image for SELECT TO pomb_account, pomb_anonymous
  USING (true);
CREATE POLICY insert_image ON pomb.image for INSERT TO pomb_account
  WITH CHECK (user_id = current_setting('jwt.claims.account_id')::INTEGER);
CREATE POLICY update_image ON pomb.image for UPDATE TO pomb_account
  USING (user_id = current_setting('jwt.claims.account_id')::INTEGER);
CREATE POLICY delete_image ON pomb.image for DELETE TO pomb_account
  USING (user_id = current_setting('jwt.claims.account_id')::INTEGER);

-- Post tag policy
GRANT ALL ON TABLE pomb.post_tag TO pomb_account, pomb_anonymous;
CREATE POLICY select_post_tag ON pomb.post_tag for SELECT TO pomb_account, pomb_anonymous
  USING (true);
CREATE POLICY insert_post_tag ON pomb.post_tag for INSERT TO pomb_account
  WITH CHECK (true);

-- Likes policy
GRANT ALL ON TABLE pomb.like TO pomb_account, pomb_anonymous;
CREATE POLICY select_like ON pomb.like for SELECT TO pomb_account, pomb_anonymous
  USING (true);
CREATE POLICY insert_like ON pomb.like for INSERT TO pomb_account
  WITH CHECK (user_id = current_setting('jwt.claims.account_id')::INTEGER);
CREATE POLICY update_like ON pomb.like for UPDATE TO pomb_account
  USING (user_id = current_setting('jwt.claims.account_id')::INTEGER);
CREATE POLICY delete_like ON pomb.like for DELETE TO pomb_account
  USING (user_id = current_setting('jwt.claims.account_id')::INTEGER);

-- Tracking policy
GRANT ALL ON TABLE pomb.track TO pomb_account, pomb_anonymous;
CREATE POLICY select_track ON pomb.track for SELECT TO pomb_account, pomb_anonymous
  USING (true);
CREATE POLICY insert_track ON pomb.track for INSERT TO pomb_account
  WITH CHECK (user_id = current_setting('jwt.claims.account_id')::INTEGER);
CREATE POLICY update_track ON pomb.track for UPDATE TO pomb_account
  USING (user_id = current_setting('jwt.claims.account_id')::INTEGER);
CREATE POLICY delete_track ON pomb.track for DELETE TO pomb_account
  USING (user_id = current_setting('jwt.claims.account_id')::INTEGER);

-- Uset to country policy
GRANT ALL ON TABLE pomb.user_to_country TO pomb_account, pomb_anonymous;
CREATE POLICY select_user_to_country ON pomb.user_to_country for SELECT TO pomb_account, pomb_anonymous
  USING (true);
CREATE POLICY insert_user_to_country ON pomb.user_to_country for INSERT TO pomb_account
  WITH CHECK (user_id = current_setting('jwt.claims.account_id')::INTEGER);
CREATE POLICY delete_user_to_country ON pomb.user_to_country for DELETE TO pomb_account
  USING (user_id = current_setting('jwt.claims.account_id')::INTEGER);

commit;