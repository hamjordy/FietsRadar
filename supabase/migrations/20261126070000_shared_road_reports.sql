-- FietsRadar shared road reports
-- Run this migration in the Supabase SQL Editor or with Supabase CLI.
-- Client applications must use the publishable key only. Never ship a secret key.

create table if not exists public.road_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  report_type text not null check (
    report_type in ('danger', 'roadworks', 'obstacle', 'slippery', 'incident')
  ),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create index if not exists road_reports_expires_at_idx
  on public.road_reports (expires_at);
create index if not exists road_reports_created_at_idx
  on public.road_reports (created_at desc);

alter table public.road_reports enable row level security;

revoke all on table public.road_reports from anon, authenticated;
grant usage on schema public to authenticated;
grant select, insert, delete on table public.road_reports to authenticated;

drop policy if exists "Cyclists can read active road reports"
  on public.road_reports;
create policy "Cyclists can read active road reports"
  on public.road_reports
  for select
  to authenticated
  using (expires_at > now());

drop policy if exists "Cyclists can publish their own road reports"
  on public.road_reports;
create policy "Cyclists can publish their own road reports"
  on public.road_reports
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Cyclists can remove their recent reports"
  on public.road_reports;
drop policy if exists "Cyclists can remove their own road reports"
  on public.road_reports;
create policy "Cyclists can remove their own road reports"
  on public.road_reports
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.prepare_road_report()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  recent_count integer;
  daily_count integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required to publish a report';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(auth.uid()::text, 0)
  );

  select count(*) into recent_count
  from public.road_reports
  where user_id = auth.uid()
    and created_at > now() - interval '1 minute';

  if recent_count >= 3 then
    raise exception 'Too many road reports. Please wait before posting again.';
  end if;

  select count(*) into daily_count
  from public.road_reports
  where user_id = auth.uid()
    and created_at > now() - interval '24 hours';

  if daily_count >= 30 then
    raise exception 'Daily road report limit reached.';
  end if;

  new.user_id := auth.uid();
  new.created_at := now();
  new.expires_at := new.created_at + case new.report_type
    when 'danger' then interval '3 hours'
    when 'roadworks' then interval '24 hours'
    when 'obstacle' then interval '2 hours'
    when 'slippery' then interval '4 hours'
    when 'incident' then interval '2 hours'
    else interval '1 hour'
  end;

  return new;
end;
$$;

drop trigger if exists prepare_road_report on public.road_reports;
create trigger prepare_road_report
  before insert on public.road_reports
  for each row execute function public.prepare_road_report();

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'road_reports'
  ) then
    alter publication supabase_realtime add table public.road_reports;
  end if;
end;
$$;
