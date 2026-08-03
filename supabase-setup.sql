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
