-- Barateam Hub - historial de torneos hibrido.
-- IMPORTANTE: esta version elimina las tablas del boceto anterior.
-- NO ejecutar en una base con datos reales: borra historial, vinculos VDBF,
-- eventos y resultados antes de recrear las tablas.
--
-- Para una base existente usa los parches incrementales de supabase/sql/.
-- Si de verdad quieres hacer un reset destructivo, ejecuta antes:
--   set app.allow_tournament_history_reset = 'on';

do $$
begin
  if coalesce(current_setting('app.allow_tournament_history_reset', true), '') <> 'on' then
    raise exception 'Script destructivo bloqueado: usa supabase/sql/tournament_history_admin_player_selector.sql en una base con datos. Para reset intencionado, ejecuta set app.allow_tournament_history_reset = ''on'' antes.';
  end if;
end;
$$;

alter table public.leaders
  add column if not exists alias text null;

create or replace function public.barateam_is_admin(p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = p_user_id
      and p.app_role = 'admin'
  )
$$;

create or replace function public.barateam_normalize_name(p_value text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(trim(coalesce(p_value, '')), '\s+', ' ', 'g'))
$$;

drop table if exists public.tournament_rounds cascade;
drop table if exists public.tournament_history cascade;
drop table if exists public.profile_vdbf_players cascade;
drop table if exists public.vdbf_event_results cascade;
drop table if exists public.vdbf_events cascade;
drop table if exists public.vdbf_players cascade;

create table public.vdbf_players (
  id uuid primary key default gen_random_uuid(),
  display_name text not null,
  normalized_name text not null,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint vdbf_players_normalized_key unique (normalized_name)
);

create table public.vdbf_events (
  id uuid primary key default gen_random_uuid(),
  source text not null default 'vdbf',
  season text not null,
  event_order integer not null,
  event_date date null,
  event_label text not null,
  event_meta text null,
  player_count integer null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint vdbf_events_source_season_order_key unique (source, season, event_order),
  constraint vdbf_events_player_count_chk check (player_count is null or player_count > 0)
);

create table public.vdbf_event_results (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.vdbf_events(id) on delete cascade,
  vdbf_player_id uuid not null references public.vdbf_players(id) on delete cascade,
  raw_points numeric null,
  result_label text null,
  wins integer null,
  losses integer null,
  final_position integer null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint vdbf_event_results_unique_player_event unique (event_id, vdbf_player_id),
  constraint vdbf_event_results_wins_chk check (wins is null or wins >= 0),
  constraint vdbf_event_results_losses_chk check (losses is null or losses >= 0),
  constraint vdbf_event_results_position_chk check (final_position is null or final_position > 0)
);

create table public.profile_vdbf_players (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  vdbf_player_id uuid not null unique references public.vdbf_players(id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.tournament_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  source text not null default 'manual',
  vdbf_event_result_id uuid null references public.vdbf_event_results(id) on delete cascade,
  tournament_date date null,
  tournament_name text null,
  expansion text null,
  player_leader_code text null references public.leaders(code) on delete restrict,
  final_result text null,
  final_position integer null,
  player_count integer null,
  top_result text null,
  notes text null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint tournament_history_source_chk check (source in ('manual', 'vdbf')),
  constraint tournament_history_vdbf_source_chk check (
    (source = 'manual' and vdbf_event_result_id is null)
    or (source = 'vdbf' and vdbf_event_result_id is not null)
  ),
  constraint tournament_history_unique_vdbf_result unique (user_id, vdbf_event_result_id),
  constraint tournament_history_position_chk check (final_position is null or final_position > 0),
  constraint tournament_history_player_count_chk check (player_count is null or player_count > 0),
  constraint tournament_history_position_count_chk check (
    final_position is null
    or player_count is null
    or final_position <= player_count
  )
);

create table public.tournament_rounds (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournament_history(id) on delete cascade,
  round_number integer not null,
  opponent_name text null,
  opponent_leader_code text null references public.leaders(code) on delete set null,
  result text not null,
  die_roll_result text null,
  play_order text null,
  notes text null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint tournament_rounds_round_number_chk check (round_number > 0),
  constraint tournament_rounds_result_chk check (result in ('win', 'loss')),
  constraint tournament_rounds_die_roll_chk check (die_roll_result is null or die_roll_result in ('won', 'lost')),
  constraint tournament_rounds_play_order_chk check (play_order is null or play_order in ('first', 'second')),
  constraint tournament_rounds_unique_round unique (tournament_id, round_number)
);

create index vdbf_events_season_date_idx on public.vdbf_events (season, event_date desc nulls last, event_order desc);
create index vdbf_event_results_player_idx on public.vdbf_event_results (vdbf_player_id);
create index tournament_history_user_date_idx on public.tournament_history (user_id, tournament_date desc nulls last, created_at desc);
create index tournament_history_vdbf_result_idx on public.tournament_history (vdbf_event_result_id);
create index tournament_history_player_leader_idx on public.tournament_history (player_leader_code);
create index tournament_rounds_tournament_idx on public.tournament_rounds (tournament_id, round_number);
create index tournament_rounds_opponent_leader_idx on public.tournament_rounds (opponent_leader_code);

create or replace function public.set_tournament_history_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

create trigger vdbf_players_updated_at
before update on public.vdbf_players
for each row execute function public.set_tournament_history_updated_at();

create trigger vdbf_events_updated_at
before update on public.vdbf_events
for each row execute function public.set_tournament_history_updated_at();

create trigger vdbf_event_results_updated_at
before update on public.vdbf_event_results
for each row execute function public.set_tournament_history_updated_at();

create trigger profile_vdbf_players_updated_at
before update on public.profile_vdbf_players
for each row execute function public.set_tournament_history_updated_at();

create trigger tournament_history_updated_at
before update on public.tournament_history
for each row execute function public.set_tournament_history_updated_at();

create trigger tournament_rounds_updated_at
before update on public.tournament_rounds
for each row execute function public.set_tournament_history_updated_at();

alter table public.vdbf_players enable row level security;
alter table public.vdbf_events enable row level security;
alter table public.vdbf_event_results enable row level security;
alter table public.profile_vdbf_players enable row level security;
alter table public.tournament_history enable row level security;
alter table public.tournament_rounds enable row level security;

drop policy if exists profiles_select_vdbf_admin on public.profiles;
create policy profiles_select_vdbf_admin on public.profiles
for select to authenticated
using (id = auth.uid() or public.barateam_is_admin(auth.uid()));

create policy vdbf_players_select_auth on public.vdbf_players
for select to authenticated using (true);

create policy vdbf_players_manage_admin on public.vdbf_players
for all to authenticated
using (public.barateam_is_admin(auth.uid()))
with check (public.barateam_is_admin(auth.uid()));

create policy vdbf_events_select_auth on public.vdbf_events
for select to authenticated using (true);

create policy vdbf_events_manage_admin on public.vdbf_events
for all to authenticated
using (public.barateam_is_admin(auth.uid()))
with check (public.barateam_is_admin(auth.uid()));

create policy vdbf_event_results_select_linked_or_admin on public.vdbf_event_results
for select to authenticated
using (
  public.barateam_is_admin(auth.uid())
  or exists (
    select 1
    from public.profile_vdbf_players link
    where link.profile_id = auth.uid()
      and link.vdbf_player_id = vdbf_event_results.vdbf_player_id
  )
);

create policy vdbf_event_results_manage_admin on public.vdbf_event_results
for all to authenticated
using (public.barateam_is_admin(auth.uid()))
with check (public.barateam_is_admin(auth.uid()));

create policy profile_vdbf_players_select_own_or_admin on public.profile_vdbf_players
for select to authenticated
using (profile_id = auth.uid() or public.barateam_is_admin(auth.uid()));

create policy profile_vdbf_players_manage_admin on public.profile_vdbf_players
for all to authenticated
using (public.barateam_is_admin(auth.uid()))
with check (public.barateam_is_admin(auth.uid()));

create policy tournament_history_select_own_or_admin on public.tournament_history
for select to authenticated
using (user_id = auth.uid() or public.barateam_is_admin(auth.uid()));

create policy tournament_history_insert_own_or_admin on public.tournament_history
for insert to authenticated
with check (
  (user_id = auth.uid() or public.barateam_is_admin(auth.uid()))
  and (
    source = 'manual'
    or exists (
      select 1
      from public.vdbf_event_results ver
      join public.profile_vdbf_players link on link.vdbf_player_id = ver.vdbf_player_id
      where ver.id = tournament_history.vdbf_event_result_id
        and link.profile_id = tournament_history.user_id
    )
  )
);

create policy tournament_history_update_own_or_admin on public.tournament_history
for update to authenticated
using (user_id = auth.uid() or public.barateam_is_admin(auth.uid()))
with check (
  (user_id = auth.uid() or public.barateam_is_admin(auth.uid()))
  and (
    source = 'manual'
    or exists (
      select 1
      from public.vdbf_event_results ver
      join public.profile_vdbf_players link on link.vdbf_player_id = ver.vdbf_player_id
      where ver.id = tournament_history.vdbf_event_result_id
        and link.profile_id = tournament_history.user_id
    )
  )
);

create policy tournament_history_delete_own_or_admin on public.tournament_history
for delete to authenticated
using (user_id = auth.uid() or public.barateam_is_admin(auth.uid()));

create policy tournament_rounds_select_own_or_admin on public.tournament_rounds
for select to authenticated
using (
  exists (
    select 1
    from public.tournament_history th
    where th.id = tournament_rounds.tournament_id
      and (th.user_id = auth.uid() or public.barateam_is_admin(auth.uid()))
  )
);

create policy tournament_rounds_insert_own_or_admin on public.tournament_rounds
for insert to authenticated
with check (
  exists (
    select 1
    from public.tournament_history th
    where th.id = tournament_rounds.tournament_id
      and (th.user_id = auth.uid() or public.barateam_is_admin(auth.uid()))
  )
);

create policy tournament_rounds_update_own_or_admin on public.tournament_rounds
for update to authenticated
using (
  exists (
    select 1
    from public.tournament_history th
    where th.id = tournament_rounds.tournament_id
      and (th.user_id = auth.uid() or public.barateam_is_admin(auth.uid()))
  )
)
with check (
  exists (
    select 1
    from public.tournament_history th
    where th.id = tournament_rounds.tournament_id
      and (th.user_id = auth.uid() or public.barateam_is_admin(auth.uid()))
  )
);

create policy tournament_rounds_delete_own_or_admin on public.tournament_rounds
for delete to authenticated
using (
  exists (
    select 1
    from public.tournament_history th
    where th.id = tournament_rounds.tournament_id
      and (th.user_id = auth.uid() or public.barateam_is_admin(auth.uid()))
  )
);

grant execute on function public.barateam_is_admin(uuid) to authenticated;
grant execute on function public.barateam_normalize_name(text) to anon, authenticated;
grant select on public.profiles to authenticated;
grant select, insert, update, delete on public.vdbf_players to authenticated;
grant select, insert, update, delete on public.vdbf_events to authenticated;
grant select, insert, update, delete on public.vdbf_event_results to authenticated;
grant select, insert, update, delete on public.profile_vdbf_players to authenticated;
grant select, insert, update, delete on public.tournament_history to authenticated;
grant select, insert, update, delete on public.tournament_rounds to authenticated;

notify pgrst, 'reload schema';
