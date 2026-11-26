-- Allow report owners to mark their shared reports as resolved.
alter table public.road_reports
  add column if not exists is_resolved boolean not null default false,
  add column if not exists resolved_at timestamptz;

grant update (is_resolved, resolved_at) on public.road_reports to authenticated;

drop policy if exists "Cyclists can resolve their own road reports"
  on public.road_reports;
create policy "Cyclists can resolve their own road reports"
  on public.road_reports
  for update
  to authenticated
  using (user_id = (select auth.uid()) and is_resolved = false)
  with check (user_id = (select auth.uid()) and is_resolved = true);

create or replace function public.stamp_resolved_road_report()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.is_resolved and not old.is_resolved then
    new.resolved_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists stamp_resolved_road_report on public.road_reports;
create trigger stamp_resolved_road_report
  before update of is_resolved on public.road_reports
  for each row execute function public.stamp_resolved_road_report();
