-- 기류 주문조회 DB (Supabase SQL Editor에 통째로 붙여넣고 Run)
-- supabase.sql을 먼저 실행한 뒤에 실행하세요. (public.is_admin() 함수를 써요)
-- 여러 번 실행해도 안전해요.

-- 1) 주문 상태 표 -------------------------------------------------------------
-- 이름·주소·전화번호 전체는 저장하지 않아요. 조회 확인용 전화번호 뒤 4자리만 저장해요.
create table if not exists public.orders (
  order_no text primary key,
  phone_last4 text not null check (phone_last4 ~ '^[0-9]{4}$'),
  tier text not null default '',
  status text not null default 'received'
    check (status in ('received','paid','designing','making','shipped','done','canceled')),
  carrier text not null default '',
  tracking_no text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.orders enable row level security;

-- 로그인한 회원의 주문과 연결 (로그인 없이 신청한 주문은 비어 있어요)
alter table public.orders add column if not exists user_id uuid references auth.users(id) on delete set null;
create index if not exists orders_user_idx on public.orders (user_id);

-- 회원은 본인 주문만 읽을 수 있어요.
drop policy if exists orders_select_own on public.orders;
create policy orders_select_own on public.orders
  for select to authenticated
  using (user_id = auth.uid());

-- 표를 직접 읽고 쓰는 건 관리자만 가능해요. (손님은 아래 함수로만 접근)
drop policy if exists orders_admin_all on public.orders;
create policy orders_admin_all on public.orders
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create or replace function public.orders_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists orders_touch on public.orders;
create trigger orders_touch before update on public.orders
  for each row execute function public.orders_touch();

-- 2) 신청 접수 시 사이트가 호출 (접수번호 + 전화번호 뒤 4자리 + 상품명) -------------
create or replace function public.register_order(p_no text, p_last4 text, p_tier text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_no is null or p_no !~ '^[A-Za-z0-9-]{3,30}$' then return; end if;
  if p_last4 is null or p_last4 !~ '^[0-9]{4}$' then return; end if;
  insert into public.orders (order_no, phone_last4, tier, user_id)
  values (upper(p_no), p_last4, left(coalesce(p_tier, ''), 40), auth.uid())
  on conflict (order_no) do nothing;
end $$;

-- 로그인 없이 신청한 예전 주문을 내 계정에 붙이기 (접수번호 + 전화 뒤 4자리가 맞고, 주인이 없을 때만)
create or replace function public.claim_order(p_no text, p_last4 text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare n int;
begin
  if auth.uid() is null then return false; end if;
  update public.orders set user_id = auth.uid()
  where order_no = upper(trim(p_no)) and phone_last4 = trim(p_last4)
    and (user_id is null or user_id = auth.uid());
  get diagnostics n = row_count;
  return n > 0;
end $$;

-- 3) 손님 조회 (접수번호 + 전화번호 뒤 4자리가 모두 맞을 때만, 상태·송장만 돌려줘요) --
create or replace function public.track_order(p_no text, p_last4 text)
returns table (status text, carrier text, tracking_no text, tier text, created_at timestamptz, updated_at timestamptz)
language sql
security definer
set search_path = public
stable
as $$
  select o.status, o.carrier, o.tracking_no, o.tier, o.created_at, o.updated_at
  from public.orders o
  where o.order_no = upper(trim(p_no)) and o.phone_last4 = trim(p_last4)
  limit 1
$$;

revoke all on function public.register_order(text, text, text) from public;
revoke all on function public.track_order(text, text) from public;
grant execute on function public.register_order(text, text, text) to anon, authenticated;
grant execute on function public.track_order(text, text) to anon, authenticated;
revoke all on function public.claim_order(text, text) from public;
grant execute on function public.claim_order(text, text) to authenticated;
