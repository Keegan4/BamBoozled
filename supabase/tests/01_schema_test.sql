-- Tests for supabase/migrations/0001_tasks.sql. Run after 00_supabase_stub.sql and the
-- migration:  psql -v ON_ERROR_STOP=1 -f 01_schema_test.sql
-- Any failed check raises an exception, which stops psql with a non-zero exit code.

create or replace function pg_temp.check(ok boolean, what text) returns void
language plpgsql as $$
begin
  if ok is not true then
    raise exception 'FAILED: %', what;
  end if;
  raise notice 'ok - %', what;
end
$$;

-- Two people with their own accounts.
insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222');

grant select, insert, update, delete on public.tasks, public.categories to authenticated;

-- ---- Structure ----
select pg_temp.check(
  (select relrowsecurity from pg_class where oid = 'public.tasks'::regclass),
  'row level security is on for tasks');
select pg_temp.check(
  (select relrowsecurity from pg_class where oid = 'public.categories'::regclass),
  'row level security is on for categories');
select pg_temp.check(
  (select count(*) = 2 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename in ('tasks', 'categories')),
  'tasks and categories are published for realtime');
select pg_temp.check(
  (select count(*) = 2 from pg_trigger where tgname in ('tasks_stamp', 'categories_stamp') and not tgisinternal),
  'a stamping trigger exists on each table');

-- ---- Writes by user 1 ----
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

insert into public.tasks (id, title, due_at, priority, category_id, created_at, updated_at)
values ('t1', 'Mark essays', '2026-10-09 09:00+00', 3, 'teaching', '2026-10-08 01:00+00', '2026-10-08 01:00+00');

select pg_temp.check(
  (select user_id = auth.uid() from public.tasks where id = 't1'),
  'user_id defaults to the signed-in user');
select pg_temp.check(
  (select server_updated_at is not null from public.tasks where id = 't1'),
  'server_updated_at is stamped on insert');

-- A newer edit is accepted and re-stamped.
create temp table stamps as select server_updated_at as first_stamp from public.tasks where id = 't1';
grant select on stamps to authenticated;
update public.tasks set title = 'Mark 3A essays', updated_at = '2026-10-08 02:00+00' where id = 't1';
select pg_temp.check(
  (select title = 'Mark 3A essays' from public.tasks where id = 't1'),
  'a newer edit is applied');
select pg_temp.check(
  (select t.server_updated_at > s.first_stamp from public.tasks t, stamps s where t.id = 't1'),
  'a newer edit gets a later server_updated_at');

-- A stale edit (older updated_at, e.g. from a device that was offline) is ignored.
update public.tasks set title = 'STALE', updated_at = '2026-10-08 00:30+00' where id = 't1';
select pg_temp.check(
  (select title = 'Mark 3A essays' and updated_at = '2026-10-08 02:00+00' from public.tasks where id = 't1'),
  'a stale edit does not overwrite a newer row');

-- Upsert as the app does it (insert ... on conflict do update) keeps the same rule.
insert into public.tasks (id, title, due_at, priority, category_id, created_at, updated_at)
values ('t1', 'STALE UPSERT', '2026-10-09 09:00+00', 3, 'teaching', '2026-10-08 01:00+00', '2026-10-08 01:15+00')
on conflict (user_id, id) do update set title = excluded.title, updated_at = excluded.updated_at;
select pg_temp.check(
  (select title = 'Mark 3A essays' from public.tasks where id = 't1'),
  'a stale upsert does not overwrite a newer row');

-- Soft delete is just another update.
update public.tasks set deleted_at = '2026-10-08 03:00+00', updated_at = '2026-10-08 03:00+00' where id = 't1';
select pg_temp.check(
  (select deleted_at is not null from public.tasks where id = 't1'),
  'soft delete is stored');

insert into public.categories (id, name, color_value, updated_at)
values ('exams', 'Exams', 4294960249, '2026-10-08 01:00+00');
select pg_temp.check(
  (select count(*) = 1 from public.categories where user_id = auth.uid()),
  'user 1 can create a category');

-- ---- Validation ----
do $$
begin
  begin
    insert into public.tasks (id, title, due_at, priority, category_id, created_at, updated_at)
    values ('bad1', 'x', now(), 9, 'general', now(), now());
    raise exception 'FAILED: priority 9 was accepted';
  exception when check_violation then
    raise notice 'ok - priority outside 1-4 is rejected';
  end;
  begin
    insert into public.tasks (id, title, due_at, priority, category_id, created_at, updated_at)
    values ('bad2', '', now(), 2, 'general', now(), now());
    raise exception 'FAILED: empty title was accepted';
  exception when check_violation then
    raise notice 'ok - empty title is rejected';
  end;
  begin
    insert into public.tasks (id, title, due_at, priority, category_id, repeat, created_at, updated_at)
    values ('bad3', 'x', now(), 2, 'general', 7, now(), now());
    raise exception 'FAILED: repeat 7 was accepted';
  exception when check_violation then
    raise notice 'ok - repeat outside 0-3 is rejected';
  end;
  begin
    insert into public.tasks (id, title, due_at, priority, category_id, estimate_minutes, created_at, updated_at)
    values ('bad4', 'x', now(), 2, 'general', 0, now(), now());
    raise exception 'FAILED: zero estimate was accepted';
  exception when check_violation then
    raise notice 'ok - zero estimate is rejected';
  end;
end
$$;

-- ---- Isolation: user 2 cannot see or touch user 1's rows ----
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);

select pg_temp.check((select count(*) = 0 from public.tasks), 'user 2 sees none of user 1''s tasks');
select pg_temp.check((select count(*) = 0 from public.categories), 'user 2 sees none of user 1''s categories');

update public.tasks set title = 'HACKED' where id = 't1';
delete from public.tasks where id = 't1';

do $$
begin
  begin
    insert into public.tasks (user_id, id, title, due_at, priority, category_id, created_at, updated_at)
    values ('11111111-1111-1111-1111-111111111111', 'spoof', 'x', now(), 2, 'general', now(), now());
    raise exception 'FAILED: user 2 inserted a row as user 1';
  exception when insufficient_privilege then
    raise notice 'ok - user 2 cannot insert rows for user 1';
  end;
end
$$;

-- The same id is allowed for a different user (ids are only unique per user).
insert into public.tasks (id, title, due_at, priority, category_id, created_at, updated_at)
values ('t1', 'My own t1', now(), 2, 'general', now(), now());
select pg_temp.check((select count(*) = 1 from public.tasks), 'user 2 can reuse an id');

-- ---- Signed-out access ----
reset role;
set role anon;
select set_config('request.jwt.claim.sub', '', false);
do $$
declare
  n bigint;
begin
  begin
    select count(*) into n from public.tasks;
    -- Supabase grants anon table access by default, so RLS shows it zero rows;
    -- a plain PostgreSQL server refuses outright. Either is fine; seeing rows is not.
    if n > 0 then
      raise exception 'FAILED: anon could read % tasks', n;
    end if;
    raise notice 'ok - signed-out visitors see no tasks';
  exception when insufficient_privilege then
    raise notice 'ok - signed-out visitors cannot read tasks';
  end;
end
$$;

-- ---- Everything above is still intact for user 1 ----
reset role;
select pg_temp.check(
  (select title = 'Mark 3A essays' from public.tasks where user_id = '11111111-1111-1111-1111-111111111111' and id = 't1'),
  'user 2''s attempts did not change user 1''s task');
