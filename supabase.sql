-- 기류 회원·후기 DB 설계 (Supabase SQL Editor에 통째로 붙여넣고 Run)
-- 여러 번 실행해도 안전하도록 만들었어요.

-- 1) 프로필 -------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null default '',
  is_admin boolean not null default false,
  agreed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- 관리자인지 확인하는 함수 (RLS 안에서 자기 자신을 다시 조회해도 무한 반복되지 않게 security definer)
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
$$;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_admin());

-- 본인 프로필만 수정 가능하고, is_admin 값은 스스로 바꿀 수 없어요.
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and is_admin = public.is_admin());

-- 가입하면 프로필을 자동으로 만들어요 (닉네임·동의 여부는 가입 화면에서 전달)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, nickname, agreed_at)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'nickname', ''), split_part(coalesce(new.email, ''), '@', 1)),
    case when (new.raw_user_meta_data->>'agreed') = 'true' then now() else null end
  )
  on conflict (id) do nothing;
  return new;
end
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 2) 후기 -----------------------------------------------------------------
create table if not exists public.reviews (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete set null,
  nickname text not null,
  rating int not null check (rating between 1 and 5),
  product int not null check (product between 0 and 2),   -- 0 베이직 · 1 스탠다드 · 2 프리미엄
  option_text text not null default '',
  content text not null check (char_length(content) between 5 and 1000),
  photos text[] not null default '{}',
  order_no text not null default '',        -- 신청 완료 화면의 접수번호 (관리자만 확인)
  consent_sns boolean not null default false, -- 사이트·인스타 소개 동의
  status text not null default 'pending' check (status in ('pending', 'approved', 'hidden')),
  source text not null default 'site' check (source in ('site', 'manual')),
  created_at timestamptz not null default now()
);
alter table public.reviews enable row level security;

-- 본인 후기 + 관리자만 원본 표를 읽을 수 있어요. (일반 방문자는 아래 reviews_public 뷰로만 조회)
drop policy if exists reviews_select on public.reviews;
create policy reviews_select on public.reviews
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- 로그인한 회원은 '확인 대기' 상태로만 등록할 수 있어요.
drop policy if exists reviews_insert_own on public.reviews;
create policy reviews_insert_own on public.reviews
  for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending' and source = 'site');

-- 본인 후기는 삭제할 수 있어요.
drop policy if exists reviews_delete_own on public.reviews;
create policy reviews_delete_own on public.reviews
  for delete to authenticated
  using (user_id = auth.uid());

-- 관리자는 모든 후기를 수정·삭제·직접 등록할 수 있어요.
drop policy if exists reviews_admin_all on public.reviews;
create policy reviews_admin_all on public.reviews
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- 게시된 후기만, 개인정보(user_id·접수번호) 없이 공개하는 뷰
create or replace view public.reviews_public as
  select id, nickname, rating, product, option_text, content, photos, created_at
  from public.reviews
  where status = 'approved';
grant select on public.reviews_public to anon, authenticated;

-- 3) 후기 사진 저장소 --------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('review-photos', 'review-photos', true)
on conflict (id) do nothing;

drop policy if exists review_photos_read on storage.objects;
create policy review_photos_read on storage.objects
  for select using (bucket_id = 'review-photos');

-- 회원은 자기 폴더(내 id)에만 올릴 수 있어요.
drop policy if exists review_photos_upload_own on storage.objects;
create policy review_photos_upload_own on storage.objects
  for insert to authenticated
  with check (bucket_id = 'review-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists review_photos_admin on storage.objects;
create policy review_photos_admin on storage.objects
  for all to authenticated
  using (bucket_id = 'review-photos' and public.is_admin())
  with check (bucket_id = 'review-photos' and public.is_admin());

-- 4) 내 계정을 관리자로 지정 ----------------------------------------------------
-- 먼저 사이트에서 회원가입(이메일 인증)을 끝낸 뒤, 아래 문장의 이메일을 바꿔서 한 번만 실행하세요.
-- update public.profiles set is_admin = true
--   where id = (select id from auth.users where email = '여기에-가입한-이메일');
