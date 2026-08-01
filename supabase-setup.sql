-- CANCIONERO VALDEMEDEL · ACTUACIONES COMPARTIDAS
-- Antes de ejecutar, sustituye gfvaldemedelextremadura@gmail.com por el mismo correo
-- que has creado en Authentication > Users y que has puesto en supabase-config.js.

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

alter table public.performances enable row level security;

grant select on public.performances to anon, authenticated;
grant insert, update, delete on public.performances to authenticated;

-- Puede leer las actuaciones cualquier persona que abra la app.
drop policy if exists "Actuaciones visibles para todos" on public.performances;
create policy "Actuaciones visibles para todos"
on public.performances
for select
to anon, authenticated
using (true);

-- Solo el correo administrador puede crear, modificar o eliminar actuaciones.
drop policy if exists "Administrador crea actuaciones" on public.performances;
create policy "Administrador crea actuaciones"
on public.performances
for insert
to authenticated
with check (lower(coalesce(auth.jwt() ->> 'email', '')) = lower('gfvaldemedelextremadura@gmail.com'));

drop policy if exists "Administrador modifica actuaciones" on public.performances;
create policy "Administrador modifica actuaciones"
on public.performances
for update
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email', '')) = lower('gfvaldemedelextremadura@gmail.com'))
with check (lower(coalesce(auth.jwt() ->> 'email', '')) = lower('gfvaldemedelextremadura@gmail.com'));

drop policy if exists "Administrador elimina actuaciones" on public.performances;
create policy "Administrador elimina actuaciones"
on public.performances
for delete
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email', '')) = lower('gfvaldemedelextremadura@gmail.com'));

-- Activa los avisos en tiempo real para que los dispositivos abiertos se actualicen.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'performances'
  ) then
    alter publication supabase_realtime add table public.performances;
  end if;
end $$;
