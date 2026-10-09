-- Adds a web link to tasks, used for assignments imported from Canvas.
-- Safe to run more than once.
alter table public.tasks add column if not exists link text;

alter table public.tasks drop constraint if exists tasks_link_check;
alter table public.tasks add constraint tasks_link_check
  check (link is null or (char_length(link) <= 2000 and link ~* '^https?://'));
