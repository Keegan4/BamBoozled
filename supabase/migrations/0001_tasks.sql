-- BamBoozled sync schema.
-- Each user only ever sees their own rows (row level security).
-- Clients merge with last-write-wins on updated_at, and pull changes using
-- server_updated_at, which the server sets so device clocks don't matter.

create table public.categories (
  user_id           uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  id                text        not null,
  name              text        not null check (char_length(name) between 1 and 40),
  color_value       bigint      not null,
  sort_order        integer     not null default 0,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, id)
);

create table public.tasks (
  user_id           uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  id                text        not null,
  title             text        not null check (char_length(title) between 1 and 200),
  due_at            timestamptz not null,
  priority          smallint    not null check (priority between 1 and 4),
  category_id       text        not null,
  estimate_minutes  integer     check (estimate_minutes is null or estimate_minutes > 0),
  notes             text,
  repeat            smallint    not null default 0 check (repeat between 0 and 3),
  completed_at      timestamptz,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, id)
);

create index categories_pull_idx on public.categories (user_id, server_updated_at);
create index tasks_pull_idx on public.tasks (user_id, server_updated_at);

-- Stamp server_updated_at on every write, and ignore stale writes: if an
-- offline device pushes an older version of a row, the newer one is kept.
create or replace function public.bamboozled_stamp_row()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return old;
  end if;
  new.server_updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger categories_stamp before insert or update on public.categories
  for each row execute function public.bamboozled_stamp_row();
create trigger tasks_stamp before insert or update on public.tasks
  for each row execute function public.bamboozled_stamp_row();

-- Row level security: users can only read and write their own rows.
alter table public.categories enable row level security;
alter table public.tasks enable row level security;

create policy "Own categories" on public.categories
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Own tasks" on public.tasks
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Realtime notifications so the other device updates within seconds.
alter publication supabase_realtime add table public.categories, public.tasks;
