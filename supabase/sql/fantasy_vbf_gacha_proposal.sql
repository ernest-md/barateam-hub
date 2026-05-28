-- VaDeFantasy / VaDeGacha proposal
-- Date: 2026-05-21
--
-- Goal:
-- - Server-authoritative gacha pulls paid with fantasy_vbf_teams.coins.
-- - Mixed rewards: skins, equipment and berries.
-- - Team inventory, skin assignment, 3 equipment slots per roster player.
-- - Effect catalog prepared for a future scoring/market rules engine.
--
-- This file is intentionally additive. It does not replace fantasy-vbf-schema.sql.

begin;

create table if not exists public.fantasy_vbf_gacha_banners (
  id uuid primary key default gen_random_uuid(),
  season text not null references public.fantasy_vbf_seasons(season) on delete cascade,
  code text not null,
  name text not null,
  description text not null default '',
  single_cost integer not null check (single_cost >= 0),
  multi_cost integer not null check (multi_cost >= 0),
  pity_limit integer not null default 60 check (pity_limit >= 0),
  pity_rarity text not null default 'legendary' check (pity_rarity in ('epic', 'legendary', 'mythic')),
  active boolean not null default true,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (season, code)
);

create table if not exists public.fantasy_vbf_gacha_items (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  kind text not null check (kind in ('skin', 'equipment', 'berries')),
  rarity text not null check (rarity in ('common', 'rare', 'epic', 'legendary', 'mythic')),
  slot text check (
    slot is null
    or slot in ('head', 'back', 'hands', 'legs', 'accessory', 'support', 'offensive', 'defensive', 'utility')
  ),
  target_player_slug text,
  target_rule text not null default 'any' check (target_rule in ('any', 'player', 'captain', 'active', 'bench')),
  asset_path text,
  effect_summary text not null default '',
  duplicate_compensation_coins integer not null default 0 check (duplicate_compensation_coins >= 0),
  stackable boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (
    (kind in ('skin', 'berries') and slot is null)
    or (kind = 'equipment' and slot is not null)
  ),
  check (
    (target_rule = 'player' and nullif(btrim(target_player_slug), '') is not null)
    or (target_rule <> 'player')
  )
);

alter table public.fantasy_vbf_gacha_items
  drop constraint if exists fantasy_vbf_gacha_items_kind_check,
  drop constraint if exists fantasy_vbf_gacha_items_slot_check,
  drop constraint if exists fantasy_vbf_gacha_items_kind_slot_check,
  drop constraint if exists fantasy_vbf_gacha_items_target_player_check,
  drop constraint if exists fantasy_vbf_gacha_items_check,
  drop constraint if exists fantasy_vbf_gacha_items_check1;

alter table public.fantasy_vbf_gacha_items
  add constraint fantasy_vbf_gacha_items_kind_check
    check (kind in ('skin', 'equipment', 'berries')),
  add constraint fantasy_vbf_gacha_items_slot_check
    check (
      slot is null
      or slot in ('head', 'back', 'hands', 'legs', 'accessory', 'support', 'offensive', 'defensive', 'utility')
    ),
  add constraint fantasy_vbf_gacha_items_kind_slot_check
    check (
      (kind in ('skin', 'berries') and slot is null)
      or (kind = 'equipment' and slot is not null)
    ),
  add constraint fantasy_vbf_gacha_items_target_player_check
    check (
      (target_rule = 'player' and nullif(btrim(target_player_slug), '') is not null)
      or (target_rule <> 'player')
    );

create table if not exists public.fantasy_vbf_gacha_banner_items (
  banner_id uuid not null references public.fantasy_vbf_gacha_banners(id) on delete cascade,
  item_id uuid not null references public.fantasy_vbf_gacha_items(id) on delete cascade,
  weight numeric(12,4) not null check (weight > 0),
  featured boolean not null default false,
  min_pity integer not null default 0 check (min_pity >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  primary key (banner_id, item_id)
);

create table if not exists public.fantasy_vbf_gacha_pity_state (
  season text not null references public.fantasy_vbf_seasons(season) on delete cascade,
  team_id uuid not null references public.fantasy_vbf_teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  banner_id uuid not null references public.fantasy_vbf_gacha_banners(id) on delete cascade,
  pity_counter integer not null default 0 check (pity_counter >= 0),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (season, team_id, banner_id)
);

create table if not exists public.fantasy_vbf_gacha_pulls (
  id uuid primary key default gen_random_uuid(),
  season text not null references public.fantasy_vbf_seasons(season) on delete cascade,
  team_id uuid not null references public.fantasy_vbf_teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  banner_id uuid not null references public.fantasy_vbf_gacha_banners(id) on delete restrict,
  pull_count integer not null check (pull_count in (1, 10)),
  cost integer not null check (cost >= 0),
  client_request_id uuid not null,
  created_at timestamptz not null default timezone('utc', now()),
  unique (team_id, client_request_id)
);

create table if not exists public.fantasy_vbf_gacha_owned_items (
  id uuid primary key default gen_random_uuid(),
  season text not null references public.fantasy_vbf_seasons(season) on delete cascade,
  team_id uuid not null references public.fantasy_vbf_teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid not null references public.fantasy_vbf_gacha_items(id) on delete restrict,
  source_pull_id uuid references public.fantasy_vbf_gacha_pulls(id) on delete set null,
  acquired_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.fantasy_vbf_gacha_pull_rewards (
  id uuid primary key default gen_random_uuid(),
  pull_id uuid not null references public.fantasy_vbf_gacha_pulls(id) on delete cascade,
  position integer not null check (position > 0),
  item_id uuid not null references public.fantasy_vbf_gacha_items(id) on delete restrict,
  owned_item_id uuid references public.fantasy_vbf_gacha_owned_items(id) on delete set null,
  rarity text not null check (rarity in ('common', 'rare', 'epic', 'legendary', 'mythic')),
  pity_before integer not null default 0 check (pity_before >= 0),
  pity_after integer not null default 0 check (pity_after >= 0),
  duplicate boolean not null default false,
  compensation_coins integer not null default 0 check (compensation_coins >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  unique (pull_id, position)
);

create table if not exists public.fantasy_vbf_gacha_skin_assignments (
  season text not null references public.fantasy_vbf_seasons(season) on delete cascade,
  team_id uuid not null references public.fantasy_vbf_teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  player_slug text not null,
  owned_item_id uuid not null references public.fantasy_vbf_gacha_owned_items(id) on delete cascade,
  assigned_at timestamptz not null default timezone('utc', now()),
  primary key (season, team_id, player_slug),
  unique (season, owned_item_id)
);

create table if not exists public.fantasy_vbf_gacha_equipped_items (
  season text not null references public.fantasy_vbf_seasons(season) on delete cascade,
  team_id uuid not null references public.fantasy_vbf_teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  player_slug text not null,
  slot_index integer not null check (slot_index between 1 and 3),
  owned_item_id uuid not null references public.fantasy_vbf_gacha_owned_items(id) on delete cascade,
  equipped_at timestamptz not null default timezone('utc', now()),
  primary key (season, team_id, player_slug, slot_index),
  unique (season, owned_item_id)
);

create table if not exists public.fantasy_vbf_gacha_effects (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  trigger_key text not null check (
    trigger_key in (
      'round_scoring',
      'market_buy',
      'market_sell',
      'clause_buy',
      'weekly_reward',
      'attendance'
    )
  ),
  modifier_type text not null check (
    modifier_type in ('flat', 'percent', 'multiply', 'set_flag')
  ),
  value numeric(12,4) not null default 0,
  stacking_rule text not null default 'add' check (
    stacking_rule in ('add', 'highest_only', 'unique_code', 'none')
  ),
  config jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.fantasy_vbf_gacha_item_effects (
  item_id uuid not null references public.fantasy_vbf_gacha_items(id) on delete cascade,
  effect_id uuid not null references public.fantasy_vbf_gacha_effects(id) on delete cascade,
  params jsonb not null default '{}'::jsonb,
  primary key (item_id, effect_id)
);

create table if not exists public.fantasy_vbf_gacha_effect_logs (
  id uuid primary key default gen_random_uuid(),
  season text not null references public.fantasy_vbf_seasons(season) on delete cascade,
  round_key text,
  team_id uuid not null references public.fantasy_vbf_teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  player_slug text,
  owned_item_id uuid references public.fantasy_vbf_gacha_owned_items(id) on delete set null,
  effect_code text not null,
  trigger_key text not null,
  delta numeric(12,4) not null default 0,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists fantasy_vbf_gacha_banners_active_idx
  on public.fantasy_vbf_gacha_banners (season, active, starts_at, ends_at);

create index if not exists fantasy_vbf_gacha_items_kind_idx
  on public.fantasy_vbf_gacha_items (kind, rarity, active);

create index if not exists fantasy_vbf_gacha_owned_team_idx
  on public.fantasy_vbf_gacha_owned_items (season, team_id, acquired_at desc);

create index if not exists fantasy_vbf_gacha_owned_item_idx
  on public.fantasy_vbf_gacha_owned_items (season, item_id, acquired_at desc);

create index if not exists fantasy_vbf_gacha_pulls_team_idx
  on public.fantasy_vbf_gacha_pulls (season, team_id, created_at desc);

create index if not exists fantasy_vbf_gacha_rewards_pull_idx
  on public.fantasy_vbf_gacha_pull_rewards (pull_id, position);

create index if not exists fantasy_vbf_gacha_equipped_player_idx
  on public.fantasy_vbf_gacha_equipped_items (season, team_id, player_slug);

create index if not exists fantasy_vbf_gacha_effect_logs_team_idx
  on public.fantasy_vbf_gacha_effect_logs (season, team_id, round_key, created_at desc);

create or replace function public.fantasy_vbf_gacha_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists fantasy_vbf_gacha_banners_touch_updated_at on public.fantasy_vbf_gacha_banners;
create trigger fantasy_vbf_gacha_banners_touch_updated_at
before update on public.fantasy_vbf_gacha_banners
for each row execute function public.fantasy_vbf_gacha_touch_updated_at();

drop trigger if exists fantasy_vbf_gacha_items_touch_updated_at on public.fantasy_vbf_gacha_items;
create trigger fantasy_vbf_gacha_items_touch_updated_at
before update on public.fantasy_vbf_gacha_items
for each row execute function public.fantasy_vbf_gacha_touch_updated_at();

create or replace function public.fantasy_vbf_gacha_pull_result(p_pull_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'pull_id', p.id,
    'season', p.season,
    'team_id', p.team_id,
    'banner_code', b.code,
    'pull_count', p.pull_count,
    'cost', p.cost,
    'balance', t.coins,
    'pity', coalesce(ps.pity_counter, 0),
    'created_at', p.created_at,
    'rewards', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'position', pr.position,
          'owned_item_id', pr.owned_item_id,
          'item_id', i.id,
          'code', i.code,
          'name', i.name,
          'kind', i.kind,
          'rarity', i.rarity,
          'slot', i.slot,
          'target_player_slug', i.target_player_slug,
          'target_rule', i.target_rule,
          'asset_path', i.asset_path,
          'effect_summary', i.effect_summary,
          'duplicate', pr.duplicate,
          'compensation_coins', pr.compensation_coins,
          'pity_before', pr.pity_before,
          'pity_after', pr.pity_after
        )
        order by pr.position
      ) filter (where pr.id is not null),
      '[]'::jsonb
    )
  )
  from public.fantasy_vbf_gacha_pulls p
  join public.fantasy_vbf_teams t on t.id = p.team_id
  join public.fantasy_vbf_gacha_banners b on b.id = p.banner_id
  left join public.fantasy_vbf_gacha_pity_state ps
    on ps.season = p.season
   and ps.team_id = p.team_id
   and ps.banner_id = p.banner_id
  left join public.fantasy_vbf_gacha_pull_rewards pr on pr.pull_id = p.id
  left join public.fantasy_vbf_gacha_items i on i.id = pr.item_id
  where p.id = p_pull_id
  group by p.id, b.code, t.coins, ps.pity_counter;
$$;

create or replace function public.fantasy_vbf_gacha_pull(
  p_season text,
  p_banner_code text,
  p_count integer,
  p_client_request_id uuid default gen_random_uuid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_team public.fantasy_vbf_teams%rowtype;
  v_banner public.fantasy_vbf_gacha_banners%rowtype;
  v_pity public.fantasy_vbf_gacha_pity_state%rowtype;
  v_item public.fantasy_vbf_gacha_items%rowtype;
  v_pull_id uuid;
  v_existing_pull_id uuid;
  v_owned_item_id uuid;
  v_cost integer;
  v_position integer;
  v_pity_before integer;
  v_pity_after integer;
  v_force_high boolean;
  v_duplicate boolean;
  v_compensation integer;
begin
  if v_user is null then
    raise exception 'Not authenticated';
  end if;

  if p_count not in (1, 10) then
    raise exception 'Invalid pull count: %', p_count;
  end if;

  select gp.id
    into v_existing_pull_id
  from public.fantasy_vbf_gacha_pulls gp
  where gp.client_request_id = p_client_request_id
    and gp.user_id = v_user
  limit 1;

  if v_existing_pull_id is not null then
    return public.fantasy_vbf_gacha_pull_result(v_existing_pull_id);
  end if;

  select *
    into v_team
  from public.fantasy_vbf_teams
  where season = p_season
    and user_id = v_user
  for update;

  if not found then
    raise exception 'Fantasy team not found for season %', p_season;
  end if;

  select *
    into v_banner
  from public.fantasy_vbf_gacha_banners
  where season = p_season
    and code = p_banner_code
    and active = true
    and (starts_at is null or starts_at <= timezone('utc', now()))
    and (ends_at is null or ends_at > timezone('utc', now()))
  limit 1;

  if not found then
    raise exception 'Gacha banner not available: %', p_banner_code;
  end if;

  v_cost := case when p_count = 10 then v_banner.multi_cost else v_banner.single_cost end;

  if v_team.coins < v_cost then
    raise exception 'Not enough berries';
  end if;

  insert into public.fantasy_vbf_gacha_pity_state (season, team_id, user_id, banner_id, pity_counter)
  values (p_season, v_team.id, v_user, v_banner.id, 0)
  on conflict (season, team_id, banner_id) do nothing;

  select *
    into v_pity
  from public.fantasy_vbf_gacha_pity_state
  where season = p_season
    and team_id = v_team.id
    and banner_id = v_banner.id
  for update;

  update public.fantasy_vbf_teams
     set coins = coins - v_cost,
         updated_at = timezone('utc', now())
   where id = v_team.id;

  insert into public.fantasy_vbf_gacha_pulls (
    season,
    team_id,
    user_id,
    banner_id,
    pull_count,
    cost,
    client_request_id
  )
  values (
    p_season,
    v_team.id,
    v_user,
    v_banner.id,
    p_count,
    v_cost,
    p_client_request_id
  )
  returning id into v_pull_id;

  for v_position in 1..p_count loop
    v_pity_before := coalesce(v_pity.pity_counter, 0);
    v_force_high := v_banner.pity_limit > 0 and (v_pity_before + 1) >= v_banner.pity_limit;

    with pool as (
      select i.*, bi.weight
      from public.fantasy_vbf_gacha_banner_items bi
      join public.fantasy_vbf_gacha_items i on i.id = bi.item_id
      where bi.banner_id = v_banner.id
        and i.active = true
        and (
          not v_force_high
          or (v_banner.pity_rarity = 'mythic' and i.rarity = 'mythic')
          or (v_banner.pity_rarity = 'legendary' and i.rarity in ('legendary', 'mythic'))
          or (v_banner.pity_rarity = 'epic' and i.rarity in ('epic', 'legendary', 'mythic'))
          or bi.min_pity > 0
        )
    ),
    prepared as (
      select
        pool.*,
        sum(pool.weight) over (order by pool.weight desc, pool.id) as cumulative_weight,
        sum(pool.weight) over () as total_weight
      from pool
    ),
    draw as (
      select random() as r
    )
    select
      id, code, name, kind, rarity, slot, target_player_slug, target_rule,
      asset_path, effect_summary, duplicate_compensation_coins, stackable,
      active, created_at, updated_at
      into v_item
    from prepared, draw
    where prepared.cumulative_weight >= draw.r * prepared.total_weight
    order by prepared.cumulative_weight
    limit 1;

    if v_item.id is null then
      with pool as (
        select i.*, bi.weight
        from public.fantasy_vbf_gacha_banner_items bi
        join public.fantasy_vbf_gacha_items i on i.id = bi.item_id
        where bi.banner_id = v_banner.id
          and i.active = true
      ),
      prepared as (
        select
          pool.*,
          sum(pool.weight) over (order by pool.weight desc, pool.id) as cumulative_weight,
          sum(pool.weight) over () as total_weight
        from pool
      ),
      draw as (
        select random() as r
      )
      select
        id, code, name, kind, rarity, slot, target_player_slug, target_rule,
        asset_path, effect_summary, duplicate_compensation_coins, stackable,
        active, created_at, updated_at
        into v_item
      from prepared, draw
      where prepared.cumulative_weight >= draw.r * prepared.total_weight
      order by prepared.cumulative_weight
      limit 1;
    end if;

    if v_item.id is null then
      raise exception 'Banner % has no active gacha items', p_banner_code;
    end if;

    v_owned_item_id := null;
    v_duplicate := false;

    if v_item.kind = 'berries' then
      v_compensation := greatest(0, v_item.duplicate_compensation_coins);
    else
      v_duplicate := exists (
        select 1
        from public.fantasy_vbf_gacha_owned_items oi
        where oi.season = p_season
          and oi.team_id = v_team.id
          and oi.item_id = v_item.id
      );

      v_compensation := case
        when v_duplicate and not v_item.stackable then v_item.duplicate_compensation_coins
        else 0
      end;

      insert into public.fantasy_vbf_gacha_owned_items (
        season,
        team_id,
        user_id,
        item_id,
        source_pull_id
      )
      values (
        p_season,
        v_team.id,
        v_user,
        v_item.id,
        v_pull_id
      )
      returning id into v_owned_item_id;
    end if;

    if v_compensation > 0 then
      update public.fantasy_vbf_teams
         set coins = coins + v_compensation,
             updated_at = timezone('utc', now())
       where id = v_team.id;
    end if;

    v_pity_after := case
      when v_banner.pity_rarity = 'mythic' and v_item.rarity = 'mythic' then 0
      when v_banner.pity_rarity = 'legendary' and v_item.rarity in ('legendary', 'mythic') then 0
      when v_banner.pity_rarity = 'epic' and v_item.rarity in ('epic', 'legendary', 'mythic') then 0
      else v_pity_before + 1
    end;

    insert into public.fantasy_vbf_gacha_pull_rewards (
      pull_id,
      position,
      item_id,
      owned_item_id,
      rarity,
      pity_before,
      pity_after,
      duplicate,
      compensation_coins
    )
    values (
      v_pull_id,
      v_position,
      v_item.id,
      v_owned_item_id,
      v_item.rarity,
      v_pity_before,
      v_pity_after,
      v_duplicate,
      v_compensation
    );

    v_pity.pity_counter := v_pity_after;
  end loop;

  update public.fantasy_vbf_gacha_pity_state
     set pity_counter = v_pity.pity_counter,
         updated_at = timezone('utc', now())
   where season = p_season
     and team_id = v_team.id
     and banner_id = v_banner.id;

  return public.fantasy_vbf_gacha_pull_result(v_pull_id);
end;
$$;

create or replace function public.fantasy_vbf_gacha_apply_skin(
  p_season text,
  p_player_slug text,
  p_owned_item_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_team public.fantasy_vbf_teams%rowtype;
  v_roster public.fantasy_vbf_roster_players%rowtype;
  v_item public.fantasy_vbf_gacha_items%rowtype;
begin
  if v_user is null then
    raise exception 'Not authenticated';
  end if;

  select *
    into v_team
  from public.fantasy_vbf_teams
  where season = p_season
    and user_id = v_user
  for update;

  if not found then
    raise exception 'Fantasy team not found';
  end if;

  select *
    into v_roster
  from public.fantasy_vbf_roster_players rp
  where rp.season = p_season
    and rp.team_id = v_team.id
    and rp.player_slug = p_player_slug;

  if not found then
    raise exception 'Player is not in your roster';
  end if;

  select i.*
    into v_item
  from public.fantasy_vbf_gacha_owned_items oi
  join public.fantasy_vbf_gacha_items i on i.id = oi.item_id
  where oi.id = p_owned_item_id
    and oi.season = p_season
    and oi.team_id = v_team.id
    and oi.user_id = v_user;

  if not found or v_item.kind <> 'skin' then
    raise exception 'Owned item is not a skin';
  end if;

  if v_item.target_rule = 'player' and v_item.target_player_slug <> p_player_slug then
    raise exception 'Skin cannot be assigned to this player';
  end if;

  insert into public.fantasy_vbf_gacha_skin_assignments (
    season,
    team_id,
    user_id,
    player_slug,
    owned_item_id,
    assigned_at
  )
  values (
    p_season,
    v_team.id,
    v_user,
    p_player_slug,
    p_owned_item_id,
    timezone('utc', now())
  )
  on conflict (season, team_id, player_slug)
  do update set
    owned_item_id = excluded.owned_item_id,
    assigned_at = excluded.assigned_at;

  return jsonb_build_object(
    'ok', true,
    'player_slug', p_player_slug,
    'owned_item_id', p_owned_item_id,
    'item_code', v_item.code
  );
end;
$$;

create or replace function public.fantasy_vbf_gacha_remove_skin(
  p_season text,
  p_player_slug text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_team_id uuid;
begin
  if v_user is null then
    raise exception 'Not authenticated';
  end if;

  select id
    into v_team_id
  from public.fantasy_vbf_teams
  where season = p_season
    and user_id = v_user;

  if v_team_id is null then
    raise exception 'Fantasy team not found';
  end if;

  delete from public.fantasy_vbf_gacha_skin_assignments
  where season = p_season
    and team_id = v_team_id
    and user_id = v_user
    and player_slug = p_player_slug;

  return jsonb_build_object('ok', true, 'player_slug', p_player_slug);
end;
$$;

create or replace function public.fantasy_vbf_gacha_equip_item(
  p_season text,
  p_player_slug text,
  p_owned_item_id uuid,
  p_slot_index integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_team public.fantasy_vbf_teams%rowtype;
  v_roster public.fantasy_vbf_roster_players%rowtype;
  v_item public.fantasy_vbf_gacha_items%rowtype;
begin
  if v_user is null then
    raise exception 'Not authenticated';
  end if;

  if p_slot_index not between 1 and 3 then
    raise exception 'Invalid equipment slot';
  end if;

  select *
    into v_team
  from public.fantasy_vbf_teams
  where season = p_season
    and user_id = v_user
  for update;

  if not found then
    raise exception 'Fantasy team not found';
  end if;

  select rp.*
    into v_roster
  from public.fantasy_vbf_roster_players rp
  where rp.season = p_season
    and rp.team_id = v_team.id
    and rp.player_slug = p_player_slug;

  if not found then
    raise exception 'Player is not in your roster';
  end if;

  select i.*
    into v_item
  from public.fantasy_vbf_gacha_owned_items oi
  join public.fantasy_vbf_gacha_items i on i.id = oi.item_id
  where oi.id = p_owned_item_id
    and oi.season = p_season
    and oi.team_id = v_team.id
    and oi.user_id = v_user;

  if not found or v_item.kind <> 'equipment' then
    raise exception 'Owned item is not equipment';
  end if;

  if v_item.target_rule = 'player' and v_item.target_player_slug <> p_player_slug then
    raise exception 'Equipment cannot be assigned to this player';
  end if;

  if v_item.target_rule = 'captain' and coalesce(v_team.captain_player_slug, '') <> p_player_slug then
    raise exception 'Equipment can only be assigned to your captain';
  end if;

  if v_item.target_rule = 'active' and coalesce(v_roster.lineup_slot, 'active') = 'bench' then
    raise exception 'Equipment can only be assigned to an active player';
  end if;

  if v_item.target_rule = 'bench' and coalesce(v_roster.lineup_slot, 'active') <> 'bench' then
    raise exception 'Equipment can only be assigned to a bench player';
  end if;

  delete from public.fantasy_vbf_gacha_equipped_items
  where season = p_season
    and team_id = v_team.id
    and owned_item_id = p_owned_item_id;

  insert into public.fantasy_vbf_gacha_equipped_items (
    season,
    team_id,
    user_id,
    player_slug,
    slot_index,
    owned_item_id,
    equipped_at
  )
  values (
    p_season,
    v_team.id,
    v_user,
    p_player_slug,
    p_slot_index,
    p_owned_item_id,
    timezone('utc', now())
  )
  on conflict (season, team_id, player_slug, slot_index)
  do update set
    owned_item_id = excluded.owned_item_id,
    equipped_at = excluded.equipped_at;

  return jsonb_build_object(
    'ok', true,
    'player_slug', p_player_slug,
    'slot_index', p_slot_index,
    'owned_item_id', p_owned_item_id,
    'item_code', v_item.code
  );
end;
$$;

create or replace function public.fantasy_vbf_gacha_unequip_item(
  p_season text,
  p_player_slug text,
  p_slot_index integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_team_id uuid;
begin
  if v_user is null then
    raise exception 'Not authenticated';
  end if;

  select id
    into v_team_id
  from public.fantasy_vbf_teams
  where season = p_season
    and user_id = v_user;

  if v_team_id is null then
    raise exception 'Fantasy team not found';
  end if;

  delete from public.fantasy_vbf_gacha_equipped_items
  where season = p_season
    and team_id = v_team_id
    and user_id = v_user
    and player_slug = p_player_slug
    and slot_index = p_slot_index;

  return jsonb_build_object(
    'ok', true,
    'player_slug', p_player_slug,
    'slot_index', p_slot_index
  );
end;
$$;

alter table public.fantasy_vbf_gacha_banners enable row level security;
alter table public.fantasy_vbf_gacha_items enable row level security;
alter table public.fantasy_vbf_gacha_banner_items enable row level security;
alter table public.fantasy_vbf_gacha_pity_state enable row level security;
alter table public.fantasy_vbf_gacha_pulls enable row level security;
alter table public.fantasy_vbf_gacha_pull_rewards enable row level security;
alter table public.fantasy_vbf_gacha_owned_items enable row level security;
alter table public.fantasy_vbf_gacha_skin_assignments enable row level security;
alter table public.fantasy_vbf_gacha_equipped_items enable row level security;
alter table public.fantasy_vbf_gacha_effects enable row level security;
alter table public.fantasy_vbf_gacha_item_effects enable row level security;
alter table public.fantasy_vbf_gacha_effect_logs enable row level security;

drop policy if exists fantasy_vbf_gacha_banners_select_all on public.fantasy_vbf_gacha_banners;
create policy fantasy_vbf_gacha_banners_select_all
  on public.fantasy_vbf_gacha_banners for select
  using (true);

drop policy if exists fantasy_vbf_gacha_items_select_all on public.fantasy_vbf_gacha_items;
create policy fantasy_vbf_gacha_items_select_all
  on public.fantasy_vbf_gacha_items for select
  using (true);

drop policy if exists fantasy_vbf_gacha_banner_items_select_all on public.fantasy_vbf_gacha_banner_items;
create policy fantasy_vbf_gacha_banner_items_select_all
  on public.fantasy_vbf_gacha_banner_items for select
  using (true);

drop policy if exists fantasy_vbf_gacha_effects_select_all on public.fantasy_vbf_gacha_effects;
create policy fantasy_vbf_gacha_effects_select_all
  on public.fantasy_vbf_gacha_effects for select
  using (true);

drop policy if exists fantasy_vbf_gacha_item_effects_select_all on public.fantasy_vbf_gacha_item_effects;
create policy fantasy_vbf_gacha_item_effects_select_all
  on public.fantasy_vbf_gacha_item_effects for select
  using (true);

drop policy if exists fantasy_vbf_gacha_pity_select_own_or_admin on public.fantasy_vbf_gacha_pity_state;
create policy fantasy_vbf_gacha_pity_select_own_or_admin
  on public.fantasy_vbf_gacha_pity_state for select
  using (auth.uid() = user_id or public.is_admin(auth.uid()));

drop policy if exists fantasy_vbf_gacha_pulls_select_own_or_admin on public.fantasy_vbf_gacha_pulls;
create policy fantasy_vbf_gacha_pulls_select_own_or_admin
  on public.fantasy_vbf_gacha_pulls for select
  using (auth.uid() = user_id or public.is_admin(auth.uid()));

drop policy if exists fantasy_vbf_gacha_rewards_select_own_or_admin on public.fantasy_vbf_gacha_pull_rewards;
create policy fantasy_vbf_gacha_rewards_select_own_or_admin
  on public.fantasy_vbf_gacha_pull_rewards for select
  using (
    exists (
      select 1
      from public.fantasy_vbf_gacha_pulls p
      where p.id = pull_id
        and (p.user_id = auth.uid() or public.is_admin(auth.uid()))
    )
  );

drop policy if exists fantasy_vbf_gacha_owned_select_own_or_admin on public.fantasy_vbf_gacha_owned_items;
create policy fantasy_vbf_gacha_owned_select_own_or_admin
  on public.fantasy_vbf_gacha_owned_items for select
  using (auth.uid() = user_id or public.is_admin(auth.uid()));

drop policy if exists fantasy_vbf_gacha_skins_select_all on public.fantasy_vbf_gacha_skin_assignments;
create policy fantasy_vbf_gacha_skins_select_all
  on public.fantasy_vbf_gacha_skin_assignments for select
  using (true);

drop policy if exists fantasy_vbf_gacha_equipped_select_all on public.fantasy_vbf_gacha_equipped_items;
create policy fantasy_vbf_gacha_equipped_select_all
  on public.fantasy_vbf_gacha_equipped_items for select
  using (true);

drop policy if exists fantasy_vbf_gacha_effect_logs_select_own_or_admin on public.fantasy_vbf_gacha_effect_logs;
create policy fantasy_vbf_gacha_effect_logs_select_own_or_admin
  on public.fantasy_vbf_gacha_effect_logs for select
  using (auth.uid() = user_id or public.is_admin(auth.uid()));

revoke all on public.fantasy_vbf_gacha_banners from public;
revoke all on public.fantasy_vbf_gacha_items from public;
revoke all on public.fantasy_vbf_gacha_banner_items from public;
revoke all on public.fantasy_vbf_gacha_pity_state from public;
revoke all on public.fantasy_vbf_gacha_pulls from public;
revoke all on public.fantasy_vbf_gacha_pull_rewards from public;
revoke all on public.fantasy_vbf_gacha_owned_items from public;
revoke all on public.fantasy_vbf_gacha_skin_assignments from public;
revoke all on public.fantasy_vbf_gacha_equipped_items from public;
revoke all on public.fantasy_vbf_gacha_effects from public;
revoke all on public.fantasy_vbf_gacha_item_effects from public;
revoke all on public.fantasy_vbf_gacha_effect_logs from public;

grant select on public.fantasy_vbf_gacha_banners to anon, authenticated;
grant select on public.fantasy_vbf_gacha_items to anon, authenticated;
grant select on public.fantasy_vbf_gacha_banner_items to anon, authenticated;
grant select on public.fantasy_vbf_gacha_effects to anon, authenticated;
grant select on public.fantasy_vbf_gacha_item_effects to anon, authenticated;
grant select on public.fantasy_vbf_gacha_skin_assignments to anon, authenticated;
grant select on public.fantasy_vbf_gacha_equipped_items to anon, authenticated;

grant select on public.fantasy_vbf_gacha_pity_state to authenticated;
grant select on public.fantasy_vbf_gacha_pulls to authenticated;
grant select on public.fantasy_vbf_gacha_pull_rewards to authenticated;
grant select on public.fantasy_vbf_gacha_owned_items to authenticated;
grant select on public.fantasy_vbf_gacha_effect_logs to authenticated;

revoke all on function public.fantasy_vbf_gacha_pull_result(uuid) from public;
revoke all on function public.fantasy_vbf_gacha_pull(text, text, integer, uuid) from public;
revoke all on function public.fantasy_vbf_gacha_apply_skin(text, text, uuid) from public;
revoke all on function public.fantasy_vbf_gacha_remove_skin(text, text) from public;
revoke all on function public.fantasy_vbf_gacha_equip_item(text, text, uuid, integer) from public;
revoke all on function public.fantasy_vbf_gacha_unequip_item(text, text, integer) from public;

grant execute on function public.fantasy_vbf_gacha_pull(text, text, integer, uuid) to authenticated;
grant execute on function public.fantasy_vbf_gacha_apply_skin(text, text, uuid) to authenticated;
grant execute on function public.fantasy_vbf_gacha_remove_skin(text, text) to authenticated;
grant execute on function public.fantasy_vbf_gacha_equip_item(text, text, uuid, integer) to authenticated;
grant execute on function public.fantasy_vbf_gacha_unequip_item(text, text, integer) to authenticated;

-- Seed mock OP15. Edit freely before running in production.

insert into public.fantasy_vbf_gacha_banners (
  season,
  code,
  name,
  description,
  single_cost,
  multi_cost,
  pity_limit,
  pity_rarity,
  active
)
values (
  'OP15',
  'mixed-op15',
  'VaDeGacha B1',
  'Banner 1 con equipables, skins y bolsas de berries.',
  12000,
  100000,
  60,
  'mythic',
  true
)
on conflict (season, code) do update set
  name = excluded.name,
  description = excluded.description,
  single_cost = excluded.single_cost,
  multi_cost = excluded.multi_cost,
  pity_limit = excluded.pity_limit,
  pity_rarity = excluded.pity_rarity,
  active = excluded.active,
  updated_at = timezone('utc', now());

insert into public.fantasy_vbf_gacha_items (
  code,
  name,
  kind,
  rarity,
  slot,
  target_player_slug,
  target_rule,
  asset_path,
  effect_summary,
  duplicate_compensation_coins,
  stackable,
  active
)
values
  ('eq-of-br-01', 'Aura Púrpura', 'equipment', 'common', 'offensive', null, 'any', 'VDG/EQ-OF-BR-01.png', 'Suma +4 si juega lila', 0, false, true),
  ('eq-of-br-02', 'Bendición del Amarillo', 'equipment', 'common', 'offensive', null, 'any', 'VDG/EQ-OF-BR-02.png', 'Suma +4 si juega amarillo', 0, false, true),
  ('eq-of-br-03', 'Furia Roja', 'equipment', 'common', 'offensive', null, 'any', 'VDG/EQ-OF-BR-03.png', 'Suma +4 si juega rojo', 0, false, true),
  ('eq-of-br-04', 'Voluntad Oscura', 'equipment', 'common', 'offensive', null, 'any', 'VDG/EQ-OF-BR-04.png', 'Suma +4 si juega negro', 0, false, true),
  ('eq-of-pl-01', 'Racha del Tryhard', 'equipment', 'rare', 'offensive', null, 'any', 'VDG/EQ-OF-PL-01.png', 'Suma +2 puntos por torneo seguido jugado.', 0, false, true),
  ('eq-of-pl-02', 'Premio al Desaparecido', 'equipment', 'rare', 'offensive', null, 'any', 'VDG/EQ-OF-PL-02.png', 'Suma +2 puntos por cada jornada no asistida seguida', 0, false, true),
  ('eq-of-or-01', 'Entrada al Top Cut', 'equipment', 'legendary', 'offensive', null, 'any', 'VDG/EQ-OF-OR-01.png', 'Si el jugador hace top 8, +8 puntos.', 0, false, true),
  ('eq-of-di-01', 'Corona del Carry', 'equipment', 'mythic', 'offensive', null, 'any', 'VDG/EQ-OF-DI-01.png', 'Las victorias del jugador suman +4 puntos.', 0, false, true),
  ('eq-de-br-01', 'Seguro Antiderrota', 'equipment', 'common', 'defensive', null, 'any', 'VDG/EQ-DE-BR-01.png', 'Una derrota no resta puntos por jornada.', 0, false, true),
  ('eq-de-br-02', 'Excusa Perfecta', 'equipment', 'common', 'defensive', null, 'any', 'VDG/EQ-DE-BR-02.png', 'Si no asiste al torneo +5 puntos.', 0, false, true),
  ('eq-de-br-03', 'Combo de Nakamas', 'equipment', 'common', 'defensive', null, 'any', 'VDG/EQ-DE-BR-03.png', 'Si todos los miembros activos de la jornada son del mismo equipo, suma +4 puntos.', 0, false, true),
  ('eq-de-pl-01', 'Blindaje Anticláusula', 'equipment', 'rare', 'defensive', null, 'any', 'VDG/EQ-DE-PL-01.png', 'Si te hacen clausulazo, recibes x2 de su valor.', 0, false, true),
  ('eq-de-pl-02', 'Banquillo de Lujo', 'equipment', 'rare', 'defensive', null, 'any', 'VDG/EQ-DE-PL-02.png', 'Si el jugador es suplente, suma +2 punto a la jornada.', 0, false, true),
  ('eq-de-pl-03', 'Paracaídas del Top 16', 'equipment', 'rare', 'defensive', null, 'any', 'VDG/EQ-DE-PL-03.png', 'Si queda por debajo del top 16, suma +4 puntos.', 0, false, true),
  ('eq-de-or-01', 'Escudo del Perdedor', 'equipment', 'legendary', 'defensive', null, 'any', 'VDG/EQ-DE-OR-01.png', 'Las derrotas de este jugador no restan puntos.', 0, false, true),
  ('eq-de-or-02', 'Candado Antimercado', 'equipment', 'legendary', 'defensive', null, 'any', 'VDG/EQ-DE-OR-02.png', 'Jugador protegido a clausula de miercoles a viernes.', 0, false, true),
  ('eq-me-br-01', 'Apuesta Offmeta', 'equipment', 'common', 'utility', null, 'any', 'VDG/EQ-ME-BR-01.png', 'Suma +2 si juega un lider offmeta.', 0, false, true),
  ('eq-me-br-02', 'Pacto Shichibukai', 'equipment', 'common', 'utility', null, 'any', 'VDG/EQ-ME-BR-02.png', 'Suma +2 puntos si juega un Sichibukai.', 0, false, true),
  ('eq-me-br-03', 'Marca del Yonkou', 'equipment', 'common', 'utility', null, 'any', 'VDG/EQ-ME-BR-03.png', 'Suma +2 puntos si juega un Yonkou.', 0, false, true),
  ('eq-me-pl-01', 'Humillación Rentable', 'equipment', 'rare', 'utility', null, 'any', 'VDG/EQ-ME-PL-01.png', 'Si queda por debajo de top 20, +10 puntos.', 0, false, true),
  ('eq-me-pl-02', 'Maldición del Suplente', 'equipment', 'rare', 'utility', null, 'any', 'VDG/EQ-ME-PL-02.png', 'Si es suplente, al resto de jugadores les resta una derrota.', 0, false, true),
  ('eq-me-pl-03', 'Derrota Productiva', 'equipment', 'rare', 'utility', null, 'any', 'VDG/EQ-ME-PL-03.png', 'Si no ha ganado ninguna partida, suma +4 por derrota.', 0, false, true),
  ('eq-me-or-01', 'Buff Barateamer', 'equipment', 'legendary', 'utility', null, 'any', 'VDG/EQ-ME-OR-01.png', 'Suma +3 puntos por cada Barateamer.', 0, false, true),
  ('eq-me-or-02', 'Bendición Laboomer', 'equipment', 'legendary', 'utility', null, 'any', 'VDG/EQ-ME-OR-02.png', 'Suma +3 puntos por cada Laboomer.', 0, false, true),
  ('sk-br-01', 'Semidimoni', 'skin', 'common', null, null, 'any', 'VDG/SK-BR-01.png', 'Suma +2 puntos por jornada.', 0, false, true),
  ('sk-br-02', 'Joselu', 'skin', 'common', null, null, 'any', 'VDG/SK-BR-02.png', 'Suma +2 puntos por jornada.', 0, false, true),
  ('sk-pl-01', 'Romo', 'skin', 'rare', null, null, 'any', 'VDG/SK-PL-01.png', 'Suma +3 puntos por jornada.', 0, false, true),
  ('sk-pl-02', 'Sicari', 'skin', 'rare', null, null, 'any', 'VDG/SK-PL-02.png', 'Suma +3 puntos por jornada.', 0, false, true),
  ('sk-pl-03', 'Xavisu', 'skin', 'rare', null, null, 'any', 'VDG/SK-PL-03.png', 'Suma +3 puntos por jornada.', 0, false, true),
  ('sk-or-01', 'Humano', 'skin', 'legendary', null, null, 'any', 'VDG/SK-OR-01.png', 'Suma +4 puntos por jornada.', 0, false, true),
  ('sk-or-02', 'Cojinho', 'skin', 'legendary', null, null, 'any', 'VDG/SK-OR-02.png', 'Suma +4 puntos por jornada.', 0, false, true),
  ('sk-di-01', 'Charko', 'skin', 'mythic', null, null, 'any', 'VDG/SK-DI-01.png', 'Suma +5 puntos por jornada. Si no ha perdido ninguna partida, duplica la puntuación.', 0, false, true),
  ('be-br-01', 'Bolsa de Berries', 'berries', 'common', null, null, 'any', 'berries.png', '5000 Berries', 5000, true, true),
  ('be-br-02', 'Bolsa de Berries', 'berries', 'common', null, null, 'any', 'berries.png', '5000 Berries', 5000, true, true),
  ('be-pl-01', 'Bolsa de Berries', 'berries', 'rare', null, null, 'any', 'berries.png', '12000 Berries', 12000, true, true),
  ('be-or-01', 'Bolsa de Berries', 'berries', 'legendary', null, null, 'any', 'berries.png', '50000 Berries', 50000, true, true)
on conflict (code) do update set
  name = excluded.name,
  kind = excluded.kind,
  rarity = excluded.rarity,
  slot = excluded.slot,
  target_player_slug = excluded.target_player_slug,
  target_rule = excluded.target_rule,
  asset_path = excluded.asset_path,
  effect_summary = excluded.effect_summary,
  duplicate_compensation_coins = excluded.duplicate_compensation_coins,
  stackable = excluded.stackable,
  active = excluded.active,
  updated_at = timezone('utc', now());

with banner as (
  select id
  from public.fantasy_vbf_gacha_banners
  where season = 'OP15'
    and code = 'mixed-op15'
)
delete from public.fantasy_vbf_gacha_banner_items bi
using banner
where bi.banner_id = banner.id;

with banner as (
  select id
  from public.fantasy_vbf_gacha_banners
  where season = 'OP15'
    and code = 'mixed-op15'
),
weights(code, weight, featured) as (
  values
    ('eq-of-br-01', 4.2857, false),
    ('eq-of-br-02', 4.2857, false),
    ('eq-of-br-03', 4.2857, false),
    ('eq-of-br-04', 4.2857, false),
    ('eq-of-pl-01', 2.3333, false),
    ('eq-of-pl-02', 2.3333, false),
    ('eq-of-or-01', 1.2500, true),
    ('eq-of-di-01', 1.0000, true),
    ('eq-de-br-01', 4.2857, false),
    ('eq-de-br-02', 4.2857, false),
    ('eq-de-br-03', 4.2857, false),
    ('eq-de-pl-01', 2.3333, false),
    ('eq-de-pl-02', 2.3333, false),
    ('eq-de-pl-03', 2.3333, false),
    ('eq-de-or-01', 1.2500, true),
    ('eq-de-or-02', 1.2500, true),
    ('eq-me-br-01', 4.2857, false),
    ('eq-me-br-02', 4.2857, false),
    ('eq-me-br-03', 4.2857, false),
    ('eq-me-pl-01', 2.3333, false),
    ('eq-me-pl-02', 2.3333, false),
    ('eq-me-pl-03', 2.3333, false),
    ('eq-me-or-01', 1.2500, true),
    ('eq-me-or-02', 1.2500, true),
    ('sk-br-01', 4.2857, false),
    ('sk-br-02', 4.2857, false),
    ('sk-pl-01', 2.3333, false),
    ('sk-pl-02', 2.3333, false),
    ('sk-pl-03', 2.3333, false),
    ('sk-or-01', 1.2500, true),
    ('sk-or-02', 1.2500, true),
    ('sk-di-01', 1.0000, true),
    ('be-br-01', 4.2857, false),
    ('be-br-02', 4.2857, false),
    ('be-pl-01', 2.3333, false),
    ('be-or-01', 1.2500, true)
)
insert into public.fantasy_vbf_gacha_banner_items (banner_id, item_id, weight, featured)
select banner.id, item.id, weights.weight, weights.featured
from banner
join weights on true
join public.fantasy_vbf_gacha_items item on item.code = weights.code
on conflict (banner_id, item_id) do update set
  weight = excluded.weight,
  featured = excluded.featured;

-- B1 effects are descriptive only for now. The executable effect tables remain
-- available for the later rules engine, but B1 items are not linked to effects.
delete from public.fantasy_vbf_gacha_item_effects ie
using public.fantasy_vbf_gacha_items item
where ie.item_id = item.id
  and item.code in (
    'eq-of-br-01', 'eq-of-br-02', 'eq-of-br-03', 'eq-of-br-04',
    'eq-of-pl-01', 'eq-of-pl-02', 'eq-of-or-01', 'eq-of-di-01',
    'eq-de-br-01', 'eq-de-br-02', 'eq-de-br-03',
    'eq-de-pl-01', 'eq-de-pl-02', 'eq-de-pl-03', 'eq-de-or-01', 'eq-de-or-02',
    'eq-me-br-01', 'eq-me-br-02', 'eq-me-br-03',
    'eq-me-pl-01', 'eq-me-pl-02', 'eq-me-pl-03', 'eq-me-or-01', 'eq-me-or-02',
    'sk-br-01', 'sk-br-02', 'sk-pl-01', 'sk-pl-02', 'sk-pl-03',
    'sk-or-01', 'sk-or-02', 'sk-di-01',
    'be-br-01', 'be-br-02', 'be-pl-01', 'be-or-01'
  );

commit;

-- Suggested frontend RPC calls:
--
-- select public.fantasy_vbf_gacha_pull('OP15', 'mixed-op15', 1, gen_random_uuid());
-- select public.fantasy_vbf_gacha_pull('OP15', 'mixed-op15', 10, gen_random_uuid());
-- select public.fantasy_vbf_gacha_apply_skin('OP15', 'ernest', '<owned_item_uuid>');
-- select public.fantasy_vbf_gacha_equip_item('OP15', 'ernest', '<owned_item_uuid>', 1);
-- select public.fantasy_vbf_gacha_unequip_item('OP15', 'ernest', 1);
