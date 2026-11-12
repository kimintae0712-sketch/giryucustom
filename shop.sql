-- 기류 편집툴 DB (Supabase SQL Editor에 통째로 붙여넣고 Run)
-- supabase.sql을 먼저 실행한 뒤에 실행하세요. (public.is_admin() 함수와 review-photos 저장소를 써요)
-- 여러 번 실행해도 안전해요.

-- 1) 사이트 설정: 공지 배너, 상품 가격·설명 ----------------------------------------
-- key 'notice'  → {"on": true, "text": "공지 문구"}
-- key 'tiers'   → {"0": {"price": 15000, "lead": "설명"}, "1": {...}, "2": {...}}
create table if not exists public.site_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.site_settings enable row level security;

drop policy if exists site_settings_read on public.site_settings;
create policy site_settings_read on public.site_settings
  for select to anon, authenticated
  using (true);

drop policy if exists site_settings_admin on public.site_settings;
create policy site_settings_admin on public.site_settings
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- 2) 소품 상품 ----------------------------------------------------------------
create table if not exists public.shop_items (
  id bigint generated always as identity primary key,
  name text not null check (char_length(name) between 1 and 40),
  price int not null check (price >= 0 and price <= 10000000),
  description text not null default '' check (char_length(description) <= 1000),
  photos text[] not null default '{}',
  status text not null default 'on' check (status in ('on', 'soldout', 'hidden')),
  sort int not null default 0,
  created_at timestamptz not null default now()
);
alter table public.shop_items enable row level security;

-- 방문자는 숨김이 아닌 상품만 볼 수 있고, 관리자는 전부 볼 수 있어요.
drop policy if exists shop_items_read on public.shop_items;
create policy shop_items_read on public.shop_items
  for select to anon, authenticated
  using (status <> 'hidden' or public.is_admin());

drop policy if exists shop_items_admin on public.shop_items;
create policy shop_items_admin on public.shop_items
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- 상품 사진은 후기 사진 저장소(review-photos)의 shop/ 폴더에 올려요. (관리자 업로드 권한은 supabase.sql에 이미 있어요)
