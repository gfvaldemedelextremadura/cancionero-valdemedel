-- CANCIONERO VALDEMEDEL · CONFIGURACIÓN SUPABASE v4.12
-- Este script es seguro para ejecutarlo varias veces y no borra actuaciones.
-- Administrador autorizado: gfvaldemedelextremadura@gmail.com

create table if not exists public.performances (
  id text primary key,
  name text not null default 'Actuación Valdemedel',
  event_date date,
  place text not null default '',
  songs jsonb not null default '[]'::jsonb,
  annotations jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Completa columnas si la tabla se creó anteriormente con otra versión.
alter table public.performances add column if not exists name text not null default 'Actuación Valdemedel';
alter table public.performances add column if not exists event_date date;
alter table public.performances add column if not exists place text not null default '';
alter table public.performances add column if not exists songs jsonb not null default '[]'::jsonb;
alter table public.performances add column if not exists annotations jsonb not null default '{}'::jsonb;
alter table public.performances add column if not exists created_at timestamptz not null default now();
alter table public.performances add column if not exists updated_at timestamptz not null default now();

alter table public.performances enable row level security;

grant usage on schema public to anon, authenticated;
grant select on public.performances to anon, authenticated;
grant insert, update, delete on public.performances to authenticated;

-- Lectura pública: cualquier compañero puede ver las actuaciones.
drop policy if exists "Actuaciones visibles para todos" on public.performances;
create policy "Actuaciones visibles para todos"
on public.performances
for select
to anon, authenticated
using (true);

-- Escritura exclusiva para el correo administrador autenticado.
drop policy if exists "Administrador crea actuaciones" on public.performances;
create policy "Administrador crea actuaciones"
on public.performances
for insert
to authenticated
with check (
  lower(coalesce(auth.jwt() ->> 'email', '')) = lower('gfvaldemedelextremadura@gmail.com')
);

drop policy if exists "Administrador modifica actuaciones" on public.performances;
create policy "Administrador modifica actuaciones"
on public.performances
for update
to authenticated
using (
  lower(coalesce(auth.jwt() ->> 'email', '')) = lower('gfvaldemedelextremadura@gmail.com')
)
with check (
  lower(coalesce(auth.jwt() ->> 'email', '')) = lower('gfvaldemedelextremadura@gmail.com')
);

drop policy if exists "Administrador elimina actuaciones" on public.performances;
create policy "Administrador elimina actuaciones"
on public.performances
for delete
to authenticated
using (
  lower(coalesce(auth.jwt() ->> 'email', '')) = lower('gfvaldemedelextremadura@gmail.com')
);

-- Mantiene updated_at al día incluso si una futura versión no lo envía.
create or replace function public.valdemedel_set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists valdemedel_performances_updated_at on public.performances;
create trigger valdemedel_performances_updated_at
before update on public.performances
for each row execute function public.valdemedel_set_updated_at();

-- Realtime queda habilitado como respaldo, aunque la app v4.12 también comprueba
-- automáticamente los cambios cada pocos segundos.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'performances'
     ) then
    alter publication supabase_realtime add table public.performances;
  end if;
end $$;

-- Pide a la Data API que recargue el esquema.
notify pgrst, 'reload schema';

-- Comprobación final. Debe devolver una fila con rls_activo = true.
select
  c.relname as tabla,
  c.relrowsecurity as rls_activo,
  (select count(*) from pg_policies p where p.schemaname='public' and p.tablename='performances') as politicas
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'performances';

-- v4.16 · Área de bailarines y PDFs
alter table public.performances add column if not exists dances jsonb not null default '[]'::jsonb;
alter table public.performances add column if not exists dance_pdf_url text not null default '';
alter table public.performances add column if not exists dance_pdf_name text not null default '';
alter table public.performances add column if not exists dance_pdf_path text not null default '';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('dance-pdfs','dance-pdfs',true,20971520,array['application/pdf'])
on conflict (id) do update set public=true,file_size_limit=20971520,allowed_mime_types=array['application/pdf'];

drop policy if exists "PDF bailarines lectura publica" on storage.objects;
create policy "PDF bailarines lectura publica" on storage.objects for select to public using (bucket_id='dance-pdfs');
drop policy if exists "Admin sube PDF bailarines" on storage.objects;
create policy "Admin sube PDF bailarines" on storage.objects for insert to authenticated with check (bucket_id='dance-pdfs' and lower(coalesce(auth.jwt()->>'email',''))=lower('gfvaldemedelextremadura@gmail.com'));
drop policy if exists "Admin actualiza PDF bailarines" on storage.objects;
create policy "Admin actualiza PDF bailarines" on storage.objects for update to authenticated using (bucket_id='dance-pdfs' and lower(coalesce(auth.jwt()->>'email',''))=lower('gfvaldemedelextremadura@gmail.com')) with check (bucket_id='dance-pdfs' and lower(coalesce(auth.jwt()->>'email',''))=lower('gfvaldemedelextremadura@gmail.com'));
drop policy if exists "Admin elimina PDF bailarines" on storage.objects;
create policy "Admin elimina PDF bailarines" on storage.objects for delete to authenticated using (bucket_id='dance-pdfs' and lower(coalesce(auth.jwt()->>'email',''))=lower('gfvaldemedelextremadura@gmail.com'));
notify pgrst, 'reload schema';

-- =========================================================
-- v4.19 · Gestión del grupo
-- Ensayos, encuestas, respuestas, avisos, logística y calendario.
-- Seguro para ejecutar varias veces. No borra datos existentes.
-- =========================================================
create table if not exists public.group_events (
  id text primary key,
  kind text not null default 'rehearsal' check (kind in ('rehearsal','performance_poll')),
  title text not null,
  event_date date,
  event_time time,
  place text not null default '',
  details text not null default '',
  clothing text not null default '',
  repertoire jsonb not null default '[]'::jsonb,
  logistics jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.event_responses (
  id text primary key,
  event_id text not null references public.group_events(id) on delete cascade,
  device_id text not null,
  member_name text not null,
  section text not null default '',
  answer text not null check (answer in ('yes','no','maybe')),
  transport text not null default '',
  seats integer not null default 0,
  notes text not null default '',
  updated_at timestamptz not null default now()
);
create table if not exists public.group_notices (
  id text primary key,
  title text not null,
  body text not null,
  event_id text,
  important boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.group_events enable row level security;
alter table public.event_responses enable row level security;
alter table public.group_notices enable row level security;
grant select on public.group_events, public.event_responses, public.group_notices to anon, authenticated;
grant insert, update on public.event_responses to anon, authenticated;
grant insert, update, delete on public.group_events, public.group_notices to authenticated;
grant delete on public.event_responses to authenticated;

drop policy if exists "Grupo eventos visibles" on public.group_events;
create policy "Grupo eventos visibles" on public.group_events for select to anon, authenticated using (true);
drop policy if exists "Admin crea eventos grupo" on public.group_events;
create policy "Admin crea eventos grupo" on public.group_events for insert to authenticated with check (lower(coalesce(auth.jwt()->>'email',''))=lower('gfvaldemedelextremadura@gmail.com'));
drop policy if exists "Admin modifica eventos grupo" on public.group_events;
create policy "Admin modifica eventos grupo" on public.group_events for update to authenticated using (lower(coalesce(auth.jwt()->>'email',''))=lower('gfvaldemedelextremadura@gmail.com')) with check (lower(coalesce(auth.jwt()->>'email',''))=lower('gfvaldemedelextremadura@gmail.com'));
drop policy if exists "Admin elimina eventos grupo" on public.group_events;
create policy "Admin elimina eventos grupo" on public.group_events for delete to authenticated using (lower(coalesce(auth.jwt()->>'email',''))=lower('gfvaldemedelextremadura@gmail.com'));

drop policy if exists "Respuestas visibles" on public.event_responses;
create policy "Respuestas visibles" on public.event_responses for select to anon, authenticated using (true);
drop policy if exists "Componentes responden" on public.event_responses;
create policy "Componentes responden" on public.event_responses for insert to anon, authenticated with check (char_length(member_name) between 2 and 120 and char_length(device_id) between 6 and 120);
drop policy if exists "Componentes actualizan respuesta" on public.event_responses;
create policy "Componentes actualizan respuesta" on public.event_responses for update to anon, authenticated using (true) with check (char_length(member_name) between 2 and 120 and char_length(device_id) between 6 and 120);
drop policy if exists "Admin elimina respuestas" on public.event_responses;
create policy "Admin elimina respuestas" on public.event_responses for delete to authenticated using (lower(coalesce(auth.jwt()->>'email',''))=lower('gfvaldemedelextremadura@gmail.com'));

drop policy if exists "Avisos visibles" on public.group_notices;
create policy "Avisos visibles" on public.group_notices for select to anon, authenticated using (true);
drop policy if exists "Admin crea avisos" on public.group_notices;
create policy "Admin crea avisos" on public.group_notices for insert to authenticated with check (lower(coalesce(auth.jwt()->>'email',''))=lower('gfvaldemedelextremadura@gmail.com'));
drop policy if exists "Admin modifica avisos" on public.group_notices;
create policy "Admin modifica avisos" on public.group_notices for update to authenticated using (lower(coalesce(auth.jwt()->>'email',''))=lower('gfvaldemedelextremadura@gmail.com')) with check (lower(coalesce(auth.jwt()->>'email',''))=lower('gfvaldemedelextremadura@gmail.com'));
drop policy if exists "Admin elimina avisos" on public.group_notices;
create policy "Admin elimina avisos" on public.group_notices for delete to authenticated using (lower(coalesce(auth.jwt()->>'email',''))=lower('gfvaldemedelextremadura@gmail.com'));

notify pgrst, 'reload schema';

-- =========================================================
-- v4.23 · Registro, aprobación y permisos por rol
-- =========================================================
-- Flujo: cualquier persona crea su cuenta; queda pendiente.
-- Solo el administrador total aprueba y asigna el rol.

create table if not exists public.member_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text unique not null,
  full_name text not null default '',
  section text not null default '',
  role text not null default 'component',
  member_type text,
  approval_status text not null default 'pending',
  active boolean not null default false,
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  approved_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

alter table public.member_profiles add column if not exists member_type text;
alter table public.member_profiles add column if not exists approval_status text not null default 'pending';
alter table public.member_profiles add column if not exists created_at timestamptz not null default now();
alter table public.member_profiles add column if not exists approved_at timestamptz;
alter table public.member_profiles add column if not exists approved_by uuid references auth.users(id);

alter table public.member_profiles drop constraint if exists member_profiles_role_check;
alter table public.member_profiles drop constraint if exists member_profiles_member_type_check;
alter table public.member_profiles drop constraint if exists member_profiles_approval_status_check;

-- Migra roles de versiones anteriores antes de aplicar las nuevas restricciones.
update public.member_profiles set role='admin_total', approval_status='approved', active=true
where lower(email)=lower('gfvaldemedelextremadura@gmail.com');
update public.member_profiles set role='component' where role in ('member','responsible');
update public.member_profiles set role='director' where role='music_director';
update public.member_profiles set role='admin_total' where role='admin';
update public.member_profiles set approval_status='approved', active=true
where approval_status='pending' and role='admin_total';

alter table public.member_profiles add constraint member_profiles_role_check check (role in ('admin_total','dance_director','director','component'));
alter table public.member_profiles add constraint member_profiles_member_type_check check (member_type is null or member_type in ('musician','dancer','staff'));
alter table public.member_profiles add constraint member_profiles_approval_status_check check (approval_status in ('pending','approved','rejected'));

alter table public.member_profiles enable row level security;
grant select on public.member_profiles to authenticated;
revoke insert, update, delete on public.member_profiles from anon, authenticated;

create or replace function public.is_valdemedel_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select lower(coalesce(auth.jwt()->>'email','')) = lower('gfvaldemedelextremadura@gmail.com')
     or exists(
       select 1 from public.member_profiles p
       where p.user_id=auth.uid() and p.active and p.approval_status='approved' and p.role='admin_total'
     );
$$;
grant execute on function public.is_valdemedel_admin() to anon, authenticated;

create or replace function public.is_approved_valdemedel_member()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.member_profiles p
    where p.user_id=auth.uid() and p.active and p.approval_status='approved'
  );
$$;
grant execute on function public.is_approved_valdemedel_member() to authenticated;

create or replace function public.sync_my_member_profile()
returns public.member_profiles language plpgsql security definer set search_path=public as $$
declare
  e text;
  n text;
  outrow public.member_profiles;
begin
  e:=lower(coalesce(auth.jwt()->>'email',''));
  if e='' then raise exception 'Debes iniciar sesión'; end if;
  n:=coalesce(auth.jwt()->'user_metadata'->>'full_name','');

  insert into public.member_profiles(user_id,email,full_name,role,approval_status,active)
  values(
    auth.uid(), e, n,
    case when e=lower('gfvaldemedelextremadura@gmail.com') then 'admin_total' else 'component' end,
    case when e=lower('gfvaldemedelextremadura@gmail.com') then 'approved' else 'pending' end,
    e=lower('gfvaldemedelextremadura@gmail.com')
  )
  on conflict(user_id) do update set
    email=e,
    full_name=case when public.member_profiles.full_name='' then n else public.member_profiles.full_name end,
    role=case when e=lower('gfvaldemedelextremadura@gmail.com') then 'admin_total' else public.member_profiles.role end,
    approval_status=case when e=lower('gfvaldemedelextremadura@gmail.com') then 'approved' else public.member_profiles.approval_status end,
    active=case when e=lower('gfvaldemedelextremadura@gmail.com') then true else public.member_profiles.active end,
    updated_at=now()
  returning * into outrow;
  return outrow;
end; $$;
grant execute on function public.sync_my_member_profile() to authenticated;

create or replace function public.update_my_member_name(new_name text)
returns public.member_profiles language plpgsql security definer set search_path=public as $$
declare outrow public.member_profiles;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  if length(trim(coalesce(new_name,'')))<2 then raise exception 'Escribe tu nombre'; end if;
  update public.member_profiles set full_name=trim(new_name),updated_at=now()
  where user_id=auth.uid() returning * into outrow;
  return outrow;
end; $$;
grant execute on function public.update_my_member_name(text) to authenticated;

-- Cada usuario ve su propio perfil. El administrador total ve todos.
drop policy if exists "Perfiles visibles para miembros" on public.member_profiles;
drop policy if exists "Usuario actualiza su perfil" on public.member_profiles;
drop policy if exists "Admin gestiona perfiles" on public.member_profiles;
drop policy if exists "Usuario ve su perfil" on public.member_profiles;
create policy "Usuario ve su perfil" on public.member_profiles for select to authenticated
using (user_id=auth.uid() or public.is_valdemedel_admin());
create policy "Admin gestiona perfiles" on public.member_profiles for all to authenticated
using (public.is_valdemedel_admin()) with check (public.is_valdemedel_admin());

-- Respuestas asociadas a usuarios aprobados.
alter table public.event_responses add column if not exists user_id uuid references auth.users(id) on delete cascade;
create unique index if not exists event_responses_event_user_unique on public.event_responses(event_id,user_id) where user_id is not null;
revoke insert, update on public.event_responses from anon;
drop policy if exists "Componentes responden" on public.event_responses;
drop policy if exists "Componentes actualizan respuesta" on public.event_responses;
drop policy if exists "Respuestas visibles" on public.event_responses;
drop policy if exists "Miembros ven respuestas" on public.event_responses;
drop policy if exists "Miembro crea su respuesta" on public.event_responses;
drop policy if exists "Miembro actualiza su respuesta" on public.event_responses;
create policy "Miembros ven respuestas" on public.event_responses for select to authenticated
using (public.is_approved_valdemedel_member());
create policy "Miembro crea su respuesta" on public.event_responses for insert to authenticated
with check (user_id=auth.uid() and public.is_approved_valdemedel_member());
create policy "Miembro actualiza su respuesta" on public.event_responses for update to authenticated
using ((user_id=auth.uid() and public.is_approved_valdemedel_member()) or public.is_valdemedel_admin())
with check ((user_id=auth.uid() and public.is_approved_valdemedel_member()) or public.is_valdemedel_admin());

notify pgrst, 'reload schema';


-- =========================================================
-- v4.23 · Permisos operativos para dirección
-- =========================================================
-- Administrador total, Directora de baile y Director pueden gestionar
-- canciones, actuaciones, ensayos, encuestas, avisos, notas y PDFs.
-- Solo Administrador total gestiona usuarios, configuración y copias.

create or replace function public.is_valdemedel_manager()
returns boolean language sql stable security definer set search_path=public as $$
  select lower(coalesce(auth.jwt()->>'email','')) = lower('gfvaldemedelextremadura@gmail.com')
     or exists(
       select 1 from public.member_profiles p
       where p.user_id=auth.uid()
         and p.active
         and p.approval_status='approved'
         and p.role in ('admin_total','dance_director','director')
     );
$$;
grant execute on function public.is_valdemedel_manager() to anon, authenticated;

-- Actuaciones
drop policy if exists "Administrador crea actuaciones" on public.performances;
drop policy if exists "Administrador modifica actuaciones" on public.performances;
drop policy if exists "Administrador elimina actuaciones" on public.performances;
create policy "Dirección crea actuaciones" on public.performances for insert to authenticated
with check (public.is_valdemedel_manager());
create policy "Dirección modifica actuaciones" on public.performances for update to authenticated
using (public.is_valdemedel_manager()) with check (public.is_valdemedel_manager());
create policy "Dirección elimina actuaciones" on public.performances for delete to authenticated
using (public.is_valdemedel_manager());

-- Ensayos, encuestas y calendario
drop policy if exists "Admin crea eventos grupo" on public.group_events;
drop policy if exists "Admin modifica eventos grupo" on public.group_events;
drop policy if exists "Admin elimina eventos grupo" on public.group_events;
create policy "Dirección crea eventos grupo" on public.group_events for insert to authenticated
with check (public.is_valdemedel_manager());
create policy "Dirección modifica eventos grupo" on public.group_events for update to authenticated
using (public.is_valdemedel_manager()) with check (public.is_valdemedel_manager());
create policy "Dirección elimina eventos grupo" on public.group_events for delete to authenticated
using (public.is_valdemedel_manager());

-- Avisos
drop policy if exists "Admin crea avisos" on public.group_notices;
drop policy if exists "Admin modifica avisos" on public.group_notices;
drop policy if exists "Admin elimina avisos" on public.group_notices;
create policy "Dirección crea avisos" on public.group_notices for insert to authenticated
with check (public.is_valdemedel_manager());
create policy "Dirección modifica avisos" on public.group_notices for update to authenticated
using (public.is_valdemedel_manager()) with check (public.is_valdemedel_manager());
create policy "Dirección elimina avisos" on public.group_notices for delete to authenticated
using (public.is_valdemedel_manager());

-- Respuestas de asistencia
drop policy if exists "Admin elimina respuestas" on public.event_responses;
create policy "Dirección elimina respuestas" on public.event_responses for delete to authenticated
using (public.is_valdemedel_manager());

-- PDFs para bailarines
drop policy if exists "Admin sube PDF bailarines" on storage.objects;
drop policy if exists "Admin actualiza PDF bailarines" on storage.objects;
drop policy if exists "Admin elimina PDF bailarines" on storage.objects;
create policy "Dirección sube PDF bailarines" on storage.objects for insert to authenticated
with check (bucket_id='dance-pdfs' and public.is_valdemedel_manager());
create policy "Dirección actualiza PDF bailarines" on storage.objects for update to authenticated
using (bucket_id='dance-pdfs' and public.is_valdemedel_manager())
with check (bucket_id='dance-pdfs' and public.is_valdemedel_manager());
create policy "Dirección elimina PDF bailarines" on storage.objects for delete to authenticated
using (bucket_id='dance-pdfs' and public.is_valdemedel_manager());

-- El administrador total conserva en exclusiva la gestión de perfiles y roles.
-- La política "Admin gestiona perfiles" sigue usando is_valdemedel_admin().

notify pgrst, 'reload schema';
