-- Minimal stand-in for the parts of Supabase that 0001_tasks.sql relies on, so the
-- migration can be tested on a plain PostgreSQL server (locally and in CI).
-- Never run this against a real Supabase project.

create schema if not exists auth;

create table auth.users (id uuid primary key);

-- Supabase reads the signed-in user from the request's JWT claims; the stub reads a
-- session setting instead, which the tests change with set_config().
create or replace function auth.uid() returns uuid
language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
end
$$;

grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end
$$;
