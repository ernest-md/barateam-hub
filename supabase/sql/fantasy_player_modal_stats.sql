-- Aggregate stats for the VadeFantasy player modal.
-- Exposes only leader-level summaries for the VDBF player linked to a Baraweb profile.

drop function if exists public.get_fantasy_player_modal_stats_v1(text, text, text);
drop function if exists public.get_fantasy_player_modal_stats_v1(text, text);

create or replace function public.get_fantasy_player_modal_stats_v1(
  p_player_name text,
  p_player_slug text default null,
  p_season text default null
)
returns table (
  source_key text,
  source_label text,
  has_vdbf_player boolean,
  has_profile_link boolean,
  linked_profile_username text,
  linked_profile_display_name text,
  leader_rank integer,
  leader_code text,
  leader_name text,
  leader_image_url text,
  leader_parallel_image_url text,
  games bigint,
  wins bigint,
  winrate numeric,
  event_round_key text,
  event_round_label text,
  event_round_order integer,
  event_date date,
  tournament_name text,
  tournament_result text,
  tournament_position integer,
  tournament_player_count integer,
  tournament_top_result text
)
language sql
security definer
set search_path = public
as $$
  with input as (
    select
      public.barateam_normalize_name(p_player_name) as normalized_name,
      lower(trim(coalesce(p_player_slug, ''))) as player_slug
  ),
  matched_player as (
    select vp.id, vp.display_name, vp.normalized_name
    from public.vdbf_players vp
    cross join input i
    where vp.normalized_name = i.normalized_name
      or (
        i.player_slug <> ''
        and lower(regexp_replace(trim(coalesce(vp.display_name, '')), '[^a-z0-9]+', '-', 'g')) = i.player_slug
      )
    order by
      case when vp.normalized_name = (select normalized_name from input) then 0 else 1 end,
      vp.display_name asc
    limit 1
  ),
  profile_link as (
    select link.profile_id, link.vdbf_player_id
    from matched_player mp
    join public.profile_vdbf_players link on link.vdbf_player_id = mp.id
    limit 1
  ),
  profile_row as (
    select
      coalesce(pr.username, '') as username,
      coalesce(pr.display_name, '') as display_name
    from profile_link link
    join public.profiles pr on pr.id = link.profile_id
    limit 1
  ),
  base as (
    select
      exists(select 1 from matched_player) as has_vdbf_player,
      exists(select 1 from profile_link) as has_profile_link,
      coalesce((select username from profile_row), '') as linked_profile_username,
      coalesce((select display_name from profile_row), '') as linked_profile_display_name
  ),
  season_window as (
    select e.start_date, e.end_date
    from public.expansions e
    where regexp_replace(upper(trim(coalesce(e.name, ''))), '[^A-Z0-9]+', '', 'g')
      = regexp_replace(upper(trim(coalesce(p_season, ''))), '[^A-Z0-9]+', '', 'g')
    order by e.start_date desc
    limit 1
  ),
  baraweb_grouped as (
    select
      'baraweb'::text as source_key,
      'Baraweb SIM'::text as source_label,
      coalesce(l.code, m.player_leader)::text as leader_code,
      coalesce(l.name, m.player_leader)::text as leader_name,
      coalesce(l.image_url, '')::text as leader_image_url,
      coalesce(l.parallel_image_url, '')::text as leader_parallel_image_url,
      count(*)::bigint as games,
      count(*) filter (
        where lower(trim(coalesce(m.result, ''))) in ('won', 'win', 'victoria', 'w')
      )::bigint as wins
    from profile_link link
    join public.players p on p.profile_id = link.profile_id
    join public.matches m on m.player_id = p.id
    left join public.leaders l on l.code = m.player_leader
    where nullif(trim(coalesce(m.player_leader, '')), '') is not null
      and (
        nullif(trim(coalesce(p_season, '')), '') is null
        or exists (
          select 1
          from season_window sw
          where timezone('Europe/Madrid', m.match_date)::date between sw.start_date and sw.end_date
        )
      )
    group by
      coalesce(l.code, m.player_leader),
      coalesce(l.name, m.player_leader),
      coalesce(l.image_url, ''),
      coalesce(l.parallel_image_url, '')
  ),
  tournament_events as (
    select distinct
      th.*,
      ve.event_date as vdbf_event_date,
      ve.event_label as vdbf_event_label,
      ve.event_order as vdbf_event_order
    from matched_player mp
    join public.tournament_history th on true
    left join public.vdbf_event_results ver on ver.id = th.vdbf_event_result_id
    left join public.vdbf_events ve on ve.id = ver.event_id
    left join profile_link link on link.profile_id = th.user_id
    where ver.vdbf_player_id = mp.id
      or link.profile_id is not null
  ),
  tournament_rows as (
    select
      th.id,
      coalesce(l.code, th.player_leader_code)::text as leader_code,
      coalesce(l.name, th.player_leader_code)::text as leader_name,
      coalesce(l.image_url, '')::text as leader_image_url,
      coalesce(l.parallel_image_url, '')::text as leader_parallel_image_url,
      case
        when th.vdbf_event_date is not null then concat(coalesce(nullif(trim(p_season), ''), th.expansion, ''), ':', th.vdbf_event_date::text)
        when th.tournament_date is not null then concat(coalesce(nullif(trim(p_season), ''), th.expansion, ''), ':', th.tournament_date::text)
        else null
      end::text as event_round_key,
      coalesce(th.vdbf_event_label, th.tournament_name, th.tournament_date::text)::text as event_round_label,
      th.vdbf_event_order::integer as event_round_order,
      coalesce(th.vdbf_event_date, th.tournament_date)::date as event_date,
      th.tournament_name::text as tournament_name,
      th.final_result::text as tournament_result,
      th.final_position::integer as tournament_position,
      th.player_count::integer as tournament_player_count,
      th.top_result::text as tournament_top_result,
      case
        when substring(coalesce(th.final_result, '') from '^[[:space:]]*([0-9]+)[[:space:]]*-') is not null
          or substring(coalesce(th.final_result, '') from '-[[:space:]]*([0-9]+)') is not null then (
          coalesce(substring(coalesce(th.final_result, '') from '^[[:space:]]*([0-9]+)[[:space:]]*-')::integer, 0)
          + coalesce(substring(coalesce(th.final_result, '') from '-[[:space:]]*([0-9]+)')::integer, 0)
        )::bigint
        else count(tr.id)::bigint
      end as games,
      case
        when substring(coalesce(th.final_result, '') from '^[[:space:]]*([0-9]+)[[:space:]]*-') is not null then
          coalesce(substring(coalesce(th.final_result, '') from '^[[:space:]]*([0-9]+)[[:space:]]*-')::integer, 0)::bigint
        else count(*) filter (where tr.result = 'win')::bigint
      end as wins
    from tournament_events th
    left join public.tournament_rounds tr on tr.tournament_id = th.id
    left join public.leaders l on l.code = th.player_leader_code
    where nullif(trim(coalesce(th.player_leader_code, '')), '') is not null
    group by
      th.id,
      th.player_leader_code,
      th.vdbf_event_date,
      th.vdbf_event_label,
      th.vdbf_event_order,
      th.tournament_date,
      th.tournament_name,
      th.expansion,
      th.final_result,
      th.final_position,
      th.player_count,
      th.top_result,
      l.code,
      l.name,
      l.image_url,
      l.parallel_image_url
  ),
  tournament_grouped as (
    select
      'tournament'::text as source_key,
      'Torneos registrados'::text as source_label,
      leader_code,
      leader_name,
      leader_image_url,
      leader_parallel_image_url,
      sum(games)::bigint as games,
      sum(wins)::bigint as wins
    from tournament_rows
    group by leader_code, leader_name, leader_image_url, leader_parallel_image_url
    having sum(games) > 0
  ),
  grouped as (
    select * from baraweb_grouped
    union all
    select * from tournament_grouped
  ),
  ranked as (
    select
      g.*,
      round((g.wins::numeric / nullif(g.games::numeric, 0)) * 100, 1) as winrate,
      (row_number() over (
        partition by g.source_key
        order by
          g.games desc,
          (g.wins::numeric / nullif(g.games::numeric, 0)) desc nulls last,
          g.wins desc,
          g.leader_name asc
      ))::integer as leader_rank
    from grouped g
    where g.games > 0
  ),
  top_rows as (
    select
      r.source_key,
      r.source_label,
      b.has_vdbf_player,
      b.has_profile_link,
      b.linked_profile_username,
      b.linked_profile_display_name,
      r.leader_rank,
      r.leader_code,
      r.leader_name,
      r.leader_image_url,
      r.leader_parallel_image_url,
      r.games,
      r.wins,
      r.winrate,
      null::text as event_round_key,
      null::text as event_round_label,
      null::integer as event_round_order,
      null::date as event_date,
      null::text as tournament_name,
      null::text as tournament_result,
      null::integer as tournament_position,
      null::integer as tournament_player_count,
      null::text as tournament_top_result
    from ranked r
    cross join base b
    where (r.source_key = 'baraweb' and r.leader_rank <= 5)
      or (r.source_key = 'tournament' and r.leader_rank <= 3)
  ),
  placeholders as (
    select
      'baraweb'::text as source_key,
      'Baraweb SIM'::text as source_label,
      b.has_vdbf_player,
      b.has_profile_link,
      b.linked_profile_username,
      b.linked_profile_display_name,
      null::integer as leader_rank,
      null::text as leader_code,
      null::text as leader_name,
      null::text as leader_image_url,
      null::text as leader_parallel_image_url,
      0::bigint as games,
      0::bigint as wins,
      0::numeric as winrate,
      null::text as event_round_key,
      null::text as event_round_label,
      null::integer as event_round_order,
      null::date as event_date,
      null::text as tournament_name,
      null::text as tournament_result,
      null::integer as tournament_position,
      null::integer as tournament_player_count,
      null::text as tournament_top_result
    from base b
    where not exists (select 1 from top_rows tr where tr.source_key = 'baraweb')
    union all
    select
      'tournament'::text as source_key,
      'Torneos registrados'::text as source_label,
      b.has_vdbf_player,
      b.has_profile_link,
      b.linked_profile_username,
      b.linked_profile_display_name,
      null::integer as leader_rank,
      null::text as leader_code,
      null::text as leader_name,
      null::text as leader_image_url,
      null::text as leader_parallel_image_url,
      0::bigint as games,
      0::bigint as wins,
      0::numeric as winrate,
      null::text as event_round_key,
      null::text as event_round_label,
      null::integer as event_round_order,
      null::date as event_date,
      null::text as tournament_name,
      null::text as tournament_result,
      null::integer as tournament_position,
      null::integer as tournament_player_count,
      null::text as tournament_top_result
    from base b
    where not exists (select 1 from top_rows tr where tr.source_key = 'tournament')
  ),
  recent_rows as (
    select
      'recent'::text as source_key,
      'Jornadas recientes'::text as source_label,
      b.has_vdbf_player,
      b.has_profile_link,
      b.linked_profile_username,
      b.linked_profile_display_name,
      (row_number() over (
        order by coalesce(tr.event_round_order, 0) desc, tr.event_date desc nulls last, tr.id desc
      ))::integer as leader_rank,
      tr.leader_code,
      tr.leader_name,
      tr.leader_image_url,
      tr.leader_parallel_image_url,
      tr.games,
      tr.wins,
      round((tr.wins::numeric / nullif(tr.games::numeric, 0)) * 100, 1) as winrate,
      tr.event_round_key,
      tr.event_round_label,
      tr.event_round_order,
      tr.event_date,
      tr.tournament_name,
      tr.tournament_result,
      tr.tournament_position,
      tr.tournament_player_count,
      tr.tournament_top_result
    from tournament_rows tr
    cross join base b
    where tr.leader_code is not null
  ),
  combined as (
    select * from top_rows
    union all
    select * from placeholders
    union all
    select * from recent_rows
  )
  select *
  from combined
  order by
    case source_key when 'baraweb' then 1 when 'tournament' then 2 else 9 end,
    coalesce(leader_rank, 999),
    leader_name asc;
$$;

revoke all on function public.get_fantasy_player_modal_stats_v1(text, text, text) from public;
grant execute on function public.get_fantasy_player_modal_stats_v1(text, text, text) to authenticated;
