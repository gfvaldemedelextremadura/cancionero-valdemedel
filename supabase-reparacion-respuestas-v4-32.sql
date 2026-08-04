-- Cancionero Valdemedel v4.32
-- Repara las políticas de respuestas de encuestas para usuarios autenticados y aprobados.

alter table public.event_responses
  add column if not exists user_id uuid references auth.users(id) on delete cascade;

create unique index if not exists event_responses_event_user_unique
  on public.event_responses(event_id,user_id)
  where user_id is not null;

alter table public.event_responses enable row level security;

grant select, insert, update on public.event_responses to authenticated;
revoke insert, update on public.event_responses from anon;

drop policy if exists "Componentes responden" on public.event_responses;
drop policy if exists "Componentes actualizan respuesta" on public.event_responses;
drop policy if exists "Respuestas visibles" on public.event_responses;
drop policy if exists "Miembros ven respuestas" on public.event_responses;
drop policy if exists "Miembro crea su respuesta" on public.event_responses;
drop policy if exists "Miembro actualiza su respuesta" on public.event_responses;

create policy "Miembros ven respuestas"
on public.event_responses for select to authenticated
using (public.is_approved_valdemedel_member());

create policy "Miembro crea su respuesta"
on public.event_responses for insert to authenticated
with check (
  user_id = auth.uid()
  and public.is_approved_valdemedel_member()
);

create policy "Miembro actualiza su respuesta"
on public.event_responses for update to authenticated
using (
  (user_id = auth.uid() and public.is_approved_valdemedel_member())
  or public.is_valdemedel_admin()
)
with check (
  (user_id = auth.uid() and public.is_approved_valdemedel_member())
  or public.is_valdemedel_admin()
);

notify pgrst, 'reload schema';
