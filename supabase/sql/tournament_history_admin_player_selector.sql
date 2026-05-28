-- Allow admins to register and manage tournament history for other profiles.
-- For an existing database with data, run this file only.
-- Do not run tournament-history-schema.sql unless you intentionally want to reset
-- the VDBF and tournament-history tables.

begin;

drop policy if exists tournament_history_select_own on public.tournament_history;
drop policy if exists tournament_history_insert_own on public.tournament_history;
drop policy if exists tournament_history_update_own on public.tournament_history;
drop policy if exists tournament_history_delete_own on public.tournament_history;
drop policy if exists tournament_history_select_own_or_admin on public.tournament_history;
drop policy if exists tournament_history_insert_own_or_admin on public.tournament_history;
drop policy if exists tournament_history_update_own_or_admin on public.tournament_history;
drop policy if exists tournament_history_delete_own_or_admin on public.tournament_history;

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

drop policy if exists tournament_rounds_select_own on public.tournament_rounds;
drop policy if exists tournament_rounds_insert_own on public.tournament_rounds;
drop policy if exists tournament_rounds_update_own on public.tournament_rounds;
drop policy if exists tournament_rounds_delete_own on public.tournament_rounds;
drop policy if exists tournament_rounds_select_own_or_admin on public.tournament_rounds;
drop policy if exists tournament_rounds_insert_own_or_admin on public.tournament_rounds;
drop policy if exists tournament_rounds_update_own_or_admin on public.tournament_rounds;
drop policy if exists tournament_rounds_delete_own_or_admin on public.tournament_rounds;

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

commit;

notify pgrst, 'reload schema';
