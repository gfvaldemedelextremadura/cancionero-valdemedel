-- =====================================================================
-- CANCIONERO VALDEMEDEL · v4.64 · PRIVACIDAD (FASE B)
--
-- Qué hace:
--   1. Crea get_guest_performance(token): el enlace de invitado lee SOLO
--      su actuación, sin poder listar las demás.
--   2. Actuaciones, eventos del grupo y avisos dejan de leerse sin sesión:
--      solo los miembros aprobados (y el administrador) pueden verlos.
--   3. Las respuestas de encuestas dejan de admitir accesos sin sesión.
--
-- Qué NO cambia:
--   - Las canciones compartidas (shared_songs) siguen siendo públicas,
--     porque los invitados necesitan las letras.
--   - Los PDF de bailarines siguen siendo públicos por su enlace.
--   - No se borra ningún dato.
--
-- ORDEN OBLIGATORIO: ejecutar SOLO cuando la app v4.64 ya esté publicada
-- (la v4.64 sabe usar get_guest_performance; las versiones anteriores no).
-- Es seguro ejecutarlo varias veces.
-- =====================================================================

-- 1) Lectura de la actuación de un invitado por su token
create or replace function public.get_guest_performance(p_token text)
returns setof public.performances
language sql stable security definer set search_path=public as $$
  select * from public.performances
  where p_token is not null and length(p_token) >= 8 and guest_token = p_token
  limit 1;
$$;
revoke all on function public.get_guest_performance(text) from public;
grant execute on function public.get_guest_performance(text) to anon, authenticated;

-- 2) Actuaciones: solo miembros aprobados
drop policy if exists "Actuaciones visibles para todos" on public.performances;
drop policy if exists "Actuaciones visibles para miembros" on public.performances;
create policy "Actuaciones visibles para miembros" on public.performances
  for select to authenticated
  using (public.is_approved_valdemedel_member() or public.is_valdemedel_admin());
revoke select on public.performances from anon;

-- 3) Eventos del grupo (ensayos y encuestas): solo miembros aprobados
drop policy if exists "Grupo eventos visibles" on public.group_events;
drop policy if exists "Grupo eventos visibles para miembros" on public.group_events;
create policy "Grupo eventos visibles para miembros" on public.group_events
  for select to authenticated
  using (public.is_approved_valdemedel_member() or public.is_valdemedel_admin());
revoke select on public.group_events from anon;

-- 4) Avisos: solo miembros aprobados
drop policy if exists "Avisos visibles" on public.group_notices;
drop policy if exists "Avisos visibles para miembros" on public.group_notices;
create policy "Avisos visibles para miembros" on public.group_notices
  for select to authenticated
  using (public.is_approved_valdemedel_member() or public.is_valdemedel_admin());
revoke select on public.group_notices from anon;

-- 5) Respuestas de encuestas: sin acceso anónimo (las políticas de miembros ya existen)
revoke select, insert, update on public.event_responses from anon;

-- ---------------------------------------------------------------------
-- COMPROBACIÓN (opcional, después de ejecutar):
--   select count(*) from public.get_guest_performance('token-que-no-existe');  -- debe dar 0
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- MARCHA ATRÁS (solo si algo falla): quitar los dos guiones de cada línea
-- y ejecutar. Vuelve a dejar la lectura pública como estaba.
-- ---------------------------------------------------------------------
-- grant select on public.performances, public.group_events, public.group_notices to anon;
-- drop policy if exists "Actuaciones visibles para todos" on public.performances;
-- create policy "Actuaciones visibles para todos" on public.performances for select to anon, authenticated using (true);
-- drop policy if exists "Grupo eventos visibles" on public.group_events;
-- create policy "Grupo eventos visibles" on public.group_events for select to anon, authenticated using (true);
-- drop policy if exists "Avisos visibles" on public.group_notices;
-- create policy "Avisos visibles" on public.group_notices for select to anon, authenticated using (true);
