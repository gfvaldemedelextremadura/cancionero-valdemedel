-- =====================================================================
-- CANCIONERO VALDEMEDEL · v4.65 · ORGANIZACIÓN (FASE C)
--
-- Tablas y funciones nuevas para:
--   · Tareas con responsable y fecha            (group_tasks)
--   · Asistencia a ensayos                      (event_attendance)
--   · Vestuario: prendas, tallas, quién las tiene (wardrobe_items)
--   · Hoja de ruta de cada actuación            (performances.route)
--   · Cumpleaños (opcional, lo pone cada uno)   (member_profiles.birthday)
--   · Datos del grupo, p. ej. fecha de fundación (group_settings)
--
-- Privacidad: nada de esto se puede leer sin sesión. Los componentes ven
-- sus propias tareas, prendas y asistencia; la dirección lo ve todo.
-- Los cumpleaños se comparten solo como día y mes, sin el año.
--
-- ORDEN: ejecutar DESPUÉS de supabase-v464-privacidad.sql.
-- Es seguro ejecutarlo varias veces. No borra datos.
-- =====================================================================

-- ---------- Tareas ----------
create table if not exists public.group_tasks (
  id text primary key,
  title text not null check (char_length(title) between 1 and 200),
  notes text not null default '',
  due_date date,
  assignee_id uuid references auth.users(id) on delete set null,
  assignee_name text not null default '',
  status text not null default 'pending' check (status in ('pending','done')),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  done_at timestamptz
);
alter table public.group_tasks enable row level security;
revoke all on public.group_tasks from anon;
grant select, insert, update, delete on public.group_tasks to authenticated;
drop policy if exists "Tareas visibles para miembros" on public.group_tasks;
create policy "Tareas visibles para miembros" on public.group_tasks for select to authenticated
  using (public.is_approved_valdemedel_member() or public.is_valdemedel_admin());
drop policy if exists "Dirección gestiona tareas" on public.group_tasks;
create policy "Dirección gestiona tareas" on public.group_tasks for all to authenticated
  using (public.is_valdemedel_manager()) with check (public.is_valdemedel_manager());

-- El responsable de una tarea (o la dirección) la marca como hecha o pendiente.
create or replace function public.set_task_status(p_id text, p_done boolean)
returns public.group_tasks language plpgsql security definer set search_path=public as $$
declare t public.group_tasks;
begin
  select * into t from public.group_tasks where id=p_id;
  if not found then raise exception 'La tarea no existe'; end if;
  if not (public.is_valdemedel_manager() or (t.assignee_id=auth.uid() and public.is_approved_valdemedel_member())) then
    raise exception 'No puedes cambiar esta tarea';
  end if;
  update public.group_tasks
     set status=case when p_done then 'done' else 'pending' end,
         done_at=case when p_done then now() else null end,
         updated_at=now()
   where id=p_id returning * into t;
  return t;
end $$;
revoke all on function public.set_task_status(text,boolean) from public;
grant execute on function public.set_task_status(text,boolean) to authenticated;

-- ---------- Asistencia a ensayos ----------
create table if not exists public.event_attendance (
  event_id text not null references public.group_events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  member_name text not null default '',
  status text not null check (status in ('present','absent','excused')),
  marked_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  primary key (event_id, user_id)
);
alter table public.event_attendance enable row level security;
revoke all on public.event_attendance from anon;
grant select, insert, update, delete on public.event_attendance to authenticated;
drop policy if exists "Asistencia propia o dirección" on public.event_attendance;
create policy "Asistencia propia o dirección" on public.event_attendance for select to authenticated
  using (public.is_valdemedel_manager() or (user_id=auth.uid() and public.is_approved_valdemedel_member()));
drop policy if exists "Dirección pasa lista" on public.event_attendance;
create policy "Dirección pasa lista" on public.event_attendance for all to authenticated
  using (public.is_valdemedel_manager()) with check (public.is_valdemedel_manager());

-- ---------- Vestuario ----------
create table if not exists public.wardrobe_items (
  id text primary key,
  name text not null check (char_length(name) between 1 and 160),
  category text not null default '',
  size text not null default '',
  quantity integer not null default 1 check (quantity >= 0),
  holder_id uuid references auth.users(id) on delete set null,
  holder_name text not null default '',
  status text not null default 'ok' check (status in ('ok','repair','lost')),
  notes text not null default '',
  updated_at timestamptz not null default now()
);
alter table public.wardrobe_items enable row level security;
revoke all on public.wardrobe_items from anon;
grant select, insert, update, delete on public.wardrobe_items to authenticated;
drop policy if exists "Vestuario propio o dirección" on public.wardrobe_items;
create policy "Vestuario propio o dirección" on public.wardrobe_items for select to authenticated
  using (public.is_valdemedel_manager() or (holder_id=auth.uid() and public.is_approved_valdemedel_member()));
drop policy if exists "Dirección gestiona vestuario" on public.wardrobe_items;
create policy "Dirección gestiona vestuario" on public.wardrobe_items for all to authenticated
  using (public.is_valdemedel_manager()) with check (public.is_valdemedel_manager());

-- ---------- Hoja de ruta de cada actuación ----------
alter table public.performances add column if not exists route jsonb not null default '{}'::jsonb;
create or replace function public.set_performance_route(p_id text, p_route jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb;
begin
  if not public.is_valdemedel_manager() then raise exception 'Solo la dirección puede editar la hoja de ruta'; end if;
  update public.performances set route=coalesce(p_route,'{}'::jsonb), updated_at=now() where id=p_id returning route into r;
  if not found then raise exception 'La actuación no existe'; end if;
  return r;
end $$;
revoke all on function public.set_performance_route(text,jsonb) from public;
grant execute on function public.set_performance_route(text,jsonb) to authenticated;

-- ---------- Cumpleaños y lista de miembros ----------
alter table public.member_profiles add column if not exists birthday date;
create or replace function public.update_my_birthday(new_birthday date)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_approved_valdemedel_member() then raise exception 'Solo miembros aprobados'; end if;
  update public.member_profiles set birthday=new_birthday, updated_at=now() where user_id=auth.uid();
end $$;
revoke all on function public.update_my_birthday(date) from public;
grant execute on function public.update_my_birthday(date) to authenticated;

-- Lista de miembros aprobados (sin correos). Cumpleaños solo como MM-DD.
create or replace function public.list_group_members()
returns table(user_id uuid, full_name text, member_type text, role text, birthday_md text, my_birthday date)
language sql stable security definer set search_path=public as $$
  select p.user_id, coalesce(nullif(p.full_name,''), split_part(p.email,'@',1)), p.member_type, p.role,
         case when p.birthday is null then null else to_char(p.birthday,'MM-DD') end,
         case when p.user_id=auth.uid() then p.birthday else null end
  from public.member_profiles p
  where p.active and p.approval_status='approved'
    and (public.is_approved_valdemedel_member() or public.is_valdemedel_admin())
  order by 2;
$$;
revoke all on function public.list_group_members() from public;
grant execute on function public.list_group_members() to authenticated;

-- ---------- Datos del grupo ----------
create table if not exists public.group_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.group_settings enable row level security;
revoke all on public.group_settings from anon;
grant select, insert, update, delete on public.group_settings to authenticated;
drop policy if exists "Datos del grupo visibles para miembros" on public.group_settings;
create policy "Datos del grupo visibles para miembros" on public.group_settings for select to authenticated
  using (public.is_approved_valdemedel_member() or public.is_valdemedel_admin());
drop policy if exists "Administrador edita datos del grupo" on public.group_settings;
create policy "Administrador edita datos del grupo" on public.group_settings for all to authenticated
  using (public.is_valdemedel_admin()) with check (public.is_valdemedel_admin());

-- Que PostgREST vea las tablas y columnas nuevas sin esperar.
notify pgrst, 'reload schema';
