-- Tests for supabase/migrations/0002_task_link.sql. Run after 01_schema_test.sql.

create or replace function pg_temp.check(ok boolean, what text) returns void
language plpgsql as $$
begin
  if ok is not true then
    raise exception 'FAILED: %', what;
  end if;
  raise notice 'ok - %', what;
end
$$;

reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);

insert into public.tasks (id, title, due_at, priority, category_id, created_at, updated_at, link)
values ('canvas-event-assignment-1', 'Essay 2', '2026-10-15 15:59+00', 2, 'canvas-course-en1101e',
        '2026-10-09 01:00+00', '2026-10-09 01:00+00', 'https://canvas.nus.edu.sg/courses/55/assignments/1');
select pg_temp.check(
  (select link = 'https://canvas.nus.edu.sg/courses/55/assignments/1' from public.tasks where id = 'canvas-event-assignment-1'),
  'a task can carry a web link');

insert into public.tasks (id, title, due_at, priority, category_id, created_at, updated_at)
values ('no-link', 'Plain task', '2026-10-15 15:59+00', 2, 'general', '2026-10-09 01:00+00', '2026-10-09 01:00+00');
select pg_temp.check(
  (select link is null from public.tasks where id = 'no-link'),
  'the link is optional');

do $$
begin
  begin
    update public.tasks set link = 'javascript:alert(1)', updated_at = '2026-10-09 02:00+00' where id = 'no-link';
    raise exception 'FAILED: a non-web link was accepted';
  exception when check_violation then
    raise notice 'ok - only http(s) links are accepted';
  end;
end
$$;

reset role;
select pg_temp.check(
  (select count(*) = 1 from information_schema.columns where table_name = 'tasks' and column_name = 'link'),
  'running the migration again does not add a second column');
