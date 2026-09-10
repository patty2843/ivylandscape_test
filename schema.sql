-- 艾維排班：Supabase Postgres schema + RLS
-- 先在 Supabase SQL Editor 執行本檔，再建立使用者。

create extension if not exists pgcrypto;

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  full_name text not null,
  employee_no text,
  department text,
  role text not null check (role in ('employee','manager')) default 'employee',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.schedules (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.profiles(id) on delete cascade,
  work_date date not null,
  start_time time not null,
  end_time time not null,
  shift_name text not null default '早班',
  location text,
  tools_note text,
  task_note text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(employee_id, work_date, start_time)
);

create table if not exists public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.profiles(id) on delete cascade,
  leave_type text not null,
  leave_date date not null,
  reason text,
  status text not null check (status in ('pending','approved','rejected')) default 'pending',
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists schedules_company_date_idx on public.schedules(company_id, work_date);
create index if not exists schedules_employee_date_idx on public.schedules(employee_id, work_date);
create index if not exists leaves_company_date_idx on public.leave_requests(company_id, leave_date);
create index if not exists leaves_employee_date_idx on public.leave_requests(employee_id, leave_date);

create or replace function public.my_company_id() returns uuid
language sql stable security definer set search_path=public as $$
  select company_id from public.profiles where id = auth.uid()
$$;

create or replace function public.is_manager() returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='manager' and active=true)
$$;

grant execute on function public.my_company_id() to authenticated;
grant execute on function public.is_manager() to authenticated;

alter table public.companies enable row level security;
alter table public.profiles enable row level security;
alter table public.schedules enable row level security;
alter table public.leave_requests enable row level security;

-- 公司：同公司可讀；只有主管可修改公司資料
create policy "company members read company" on public.companies for select to authenticated
using (id = public.my_company_id());
create policy "manager updates company" on public.companies for update to authenticated
using (id = public.my_company_id() and public.is_manager()) with check (id = public.my_company_id() and public.is_manager());

-- profiles：本人可讀自己；主管可讀同公司所有人。一般員工不能改 role/company_id。
create policy "profile self or manager read" on public.profiles for select to authenticated
using (id=auth.uid() or (company_id=public.my_company_id() and public.is_manager()));
create policy "manager update company profiles" on public.profiles for update to authenticated
using (company_id=public.my_company_id() and public.is_manager())
with check (company_id=public.my_company_id() and public.is_manager());

-- schedules：員工只讀自己的；主管可讀寫同公司。
create policy "employee reads own schedules" on public.schedules for select to authenticated
using (employee_id=auth.uid() or (company_id=public.my_company_id() and public.is_manager()));
create policy "manager inserts schedules" on public.schedules for insert to authenticated
with check (company_id=public.my_company_id() and public.is_manager() and created_by=auth.uid());
create policy "manager updates schedules" on public.schedules for update to authenticated
using (company_id=public.my_company_id() and public.is_manager())
with check (company_id=public.my_company_id() and public.is_manager());
create policy "manager deletes schedules" on public.schedules for delete to authenticated
using (company_id=public.my_company_id() and public.is_manager());

-- leave_requests：員工可建立/查看自己的；主管可查看與審核同公司。
create policy "employee reads own leaves" on public.leave_requests for select to authenticated
using (employee_id=auth.uid() or (company_id=public.my_company_id() and public.is_manager()));
create policy "employee creates own leaves" on public.leave_requests for insert to authenticated
with check (employee_id=auth.uid() and company_id=public.my_company_id() and status='pending');
create policy "manager reviews leaves" on public.leave_requests for update to authenticated
using (company_id=public.my_company_id() and public.is_manager())
with check (company_id=public.my_company_id() and public.is_manager());

-- Realtime
alter publication supabase_realtime add table public.schedules;
alter publication supabase_realtime add table public.leave_requests;

-- 建立公司範例（只需執行一次，並記下回傳 UUID）
-- insert into public.companies(name) values ('艾維空間景觀有限公司') returning id;

-- 建立 Auth 使用者後，在 SQL Editor 綁定 profile：
-- insert into public.profiles(id, company_id, full_name, employee_no, department, role)
-- values ('AUTH_USER_UUID', 'COMPANY_UUID', '姚尚易', 'M001', '管理部', 'manager');
