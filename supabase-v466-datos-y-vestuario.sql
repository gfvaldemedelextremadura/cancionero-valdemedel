-- =====================================================================
-- CANCIONERO VALDEMEDEL · v4.66 · DATOS PERSONALES Y PRÉSTAMOS DE VESTUARIO
--
-- 1. Cada miembro guarda nombre, apellidos, género y teléfono.
--    El teléfono y el género solo los ven la dirección y la persona
--    responsable de vestuario (y cada uno los suyos).
-- 2. Vestuario: una persona responsable (la elige el administrador),
--    las directoras de baile y los administradores lo gestionan.
--    Préstamos con devolución que confirma la responsable; al confirmar,
--    la prenda vuelve sola al stock del grupo.
--
-- ORDEN: ejecutar DESPUÉS de supabase-v465-organizacion.sql.
-- Es seguro ejecutarlo varias veces. No borra datos: las prendas que ya
-- tenían a alguien asignado se convierten en préstamos.
-- =====================================================================

-- ---------- Datos personales ----------
alter table public.member_profiles add column if not exists first_name text not null default '';
alter table public.member_profiles add column if not exists last_name text not null default '';
alter table public.member_profiles add column if not exists gender text;
alter table public.member_profiles add column if not exists phone text not null default '';
alter table public.member_profiles drop constraint if exists member_profiles_gender_check;
alter table public.member_profiles add constraint member_profiles_gender_check check (gender is null or gender in ('female','male','other'));

create or replace function public.update_my_details(p_first text, p_last text, p_gender text, p_phone text)
returns void language plpgsql security definer set search_path=public as $$
declare f text := trim(coalesce(p_first,'')); l text := trim(coalesce(p_last,'')); ph text := trim(coalesce(p_phone,''));
begin
  if auth.uid() is null then raise exception 'Inicia sesión'; end if;
  if char_length(f) < 2 or char_length(f) > 60 then raise exception 'Escribe tu nombre'; end if;
  if char_length(l) < 2 or char_length(l) > 80 then raise exception 'Escribe tus apellidos'; end if;
  if p_gender is null or p_gender not in ('female','male','other') then raise exception 'Elige el género'; end if;
  if ph !~ '^[0-9 +().-]{9,20}$' then raise exception 'Escribe un teléfono válido'; end if;
  update public.member_profiles
     set first_name=f, last_name=l, gender=p_gender, phone=ph, full_name=f||' '||l, updated_at=now()
   where user_id=auth.uid();
end $$;
revoke all on function public.update_my_details(text,text,text,text) from public;
revoke execute on function public.update_my_details(text,text,text,text) from anon;
grant execute on function public.update_my_details(text,text,text,text) to authenticated;

-- ---------- Responsable de vestuario ----------
-- Se guarda en group_settings con la clave 'wardrobe_manager' = {"user_id": "..."}
create or replace function public.is_wardrobe_manager()
returns boolean language sql stable security definer set search_path=public as $$
  select lower(coalesce(auth.jwt()->>'email','')) = lower('gfvaldemedelextremadura@gmail.com')
      or exists(
        select 1 from public.member_profiles p
        where p.user_id=auth.uid() and p.active and p.approval_status='approved'
          and ( p.role in ('admin_total','dance_director')
                or p.user_id::text = (select s.value->>'user_id' from public.group_settings s where s.key='wardrobe_manager') )
      );
$$;
revoke all on function public.is_wardrobe_manager() from public;
revoke execute on function public.is_wardrobe_manager() from anon;
grant execute on function public.is_wardrobe_manager() to authenticated;

-- ---------- Lista de miembros (se amplía) ----------
drop function if exists public.list_group_members();
create function public.list_group_members()
returns table(user_id uuid, full_name text, first_name text, last_name text, member_type text, role text,
              gender text, phone text, birthday_md text, my_birthday date)
language sql stable security definer set search_path=public as $$
  select p.user_id,
         coalesce(nullif(trim(p.first_name||' '||p.last_name),''), nullif(p.full_name,''), split_part(p.email,'@',1)),
         p.first_name, p.last_name, p.member_type, p.role,
         case when p.user_id=auth.uid() or public.is_valdemedel_manager() or public.is_wardrobe_manager() then p.gender end,
         case when p.user_id=auth.uid() or public.is_valdemedel_manager() or public.is_wardrobe_manager() then p.phone end,
         case when p.birthday is null then null else to_char(p.birthday,'MM-DD') end,
         case when p.user_id=auth.uid() then p.birthday end
  from public.member_profiles p
  where p.active and p.approval_status='approved'
    and (public.is_approved_valdemedel_member() or public.is_valdemedel_admin())
  order by 2;
$$;
revoke all on function public.list_group_members() from public;
revoke execute on function public.list_group_members() from anon;
grant execute on function public.list_group_members() to authenticated;

-- Mis propios datos (también para quien está pendiente de aprobación)
create or replace function public.get_my_details()
returns table(first_name text, last_name text, gender text, phone text)
language sql stable security definer set search_path=public as $$
  select p.first_name, p.last_name, p.gender, p.phone from public.member_profiles p where p.user_id=auth.uid();
$$;
revoke all on function public.get_my_details() from public;
revoke execute on function public.get_my_details() from anon;
grant execute on function public.get_my_details() to authenticated;

-- ---------- Prendas (stock) ----------
alter table public.wardrobe_items add column if not exists in_repair integer not null default 0;
alter table public.wardrobe_items drop constraint if exists wardrobe_items_in_repair_check;
alter table public.wardrobe_items add constraint wardrobe_items_in_repair_check check (in_repair >= 0);
drop policy if exists "Vestuario propio o dirección" on public.wardrobe_items;
drop policy if exists "Dirección gestiona vestuario" on public.wardrobe_items;
drop policy if exists "Vestuario visible para miembros" on public.wardrobe_items;
drop policy if exists "Responsable gestiona vestuario" on public.wardrobe_items;
create policy "Vestuario visible para miembros" on public.wardrobe_items for select to authenticated
  using (public.is_approved_valdemedel_member() or public.is_valdemedel_admin());
create policy "Responsable gestiona vestuario" on public.wardrobe_items for all to authenticated
  using (public.is_wardrobe_manager()) with check (public.is_wardrobe_manager());

-- ---------- Préstamos ----------
create table if not exists public.wardrobe_loans (
  id text primary key,
  item_id text not null references public.wardrobe_items(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  member_name text not null default '',
  quantity integer not null default 1 check (quantity > 0),
  status text not null default 'lent' check (status in ('lent','return_requested','returned')),
  notes text not null default '',
  lent_at timestamptz not null default now(),
  lent_by uuid default auth.uid(),
  return_requested_at timestamptz,
  returned_at timestamptz,
  confirmed_by uuid,
  return_condition text check (return_condition is null or return_condition in ('ok','repair','lost')),
  updated_at timestamptz not null default now()
);
alter table public.wardrobe_loans enable row level security;
revoke all on public.wardrobe_loans from anon;
grant select, insert, update, delete on public.wardrobe_loans to authenticated;
drop policy if exists "Préstamos propios o responsable" on public.wardrobe_loans;
create policy "Préstamos propios o responsable" on public.wardrobe_loans for select to authenticated
  using (public.is_wardrobe_manager() or (user_id=auth.uid() and public.is_approved_valdemedel_member()));
drop policy if exists "Responsable gestiona préstamos" on public.wardrobe_loans;
create policy "Responsable gestiona préstamos" on public.wardrobe_loans for all to authenticated
  using (public.is_wardrobe_manager()) with check (public.is_wardrobe_manager());

-- Prestar una prenda (comprueba que haya unidades disponibles)
create or replace function public.lend_wardrobe_item(p_item text, p_user uuid, p_qty integer, p_notes text)
returns public.wardrobe_loans language plpgsql security definer set search_path=public as $$
declare it public.wardrobe_items; lent integer; avail integer; nm text; l public.wardrobe_loans;
begin
  if not public.is_wardrobe_manager() then raise exception 'Solo la responsable de vestuario puede prestar prendas'; end if;
  if p_qty is null or p_qty < 1 then raise exception 'Cantidad no válida'; end if;
  select * into it from public.wardrobe_items where id=p_item for update;
  if not found then raise exception 'La prenda no existe'; end if;
  select coalesce(sum(quantity),0) into lent from public.wardrobe_loans where item_id=p_item and status in ('lent','return_requested');
  avail := it.quantity - it.in_repair - lent;
  if p_qty > avail then raise exception 'Solo quedan % disponibles', greatest(avail,0); end if;
  select coalesce(nullif(trim(first_name||' '||last_name),''), nullif(full_name,''), split_part(email,'@',1)) into nm
    from public.member_profiles where user_id=p_user and active and approval_status='approved';
  if nm is null then raise exception 'Esa persona no es un miembro aprobado'; end if;
  insert into public.wardrobe_loans(id,item_id,user_id,member_name,quantity,notes)
  values ('loan-'||replace(gen_random_uuid()::text,'-',''), p_item, p_user, nm, p_qty, coalesce(p_notes,''))
  returning * into l;
  return l;
end $$;

-- El componente avisa de que ya lo ha devuelto
create or replace function public.request_wardrobe_return(p_loan text)
returns public.wardrobe_loans language plpgsql security definer set search_path=public as $$
declare l public.wardrobe_loans;
begin
  select * into l from public.wardrobe_loans where id=p_loan for update;
  if not found then raise exception 'El préstamo no existe'; end if;
  if l.user_id is distinct from auth.uid() then raise exception 'Este préstamo no es tuyo'; end if;
  if l.status <> 'lent' then raise exception 'Este préstamo ya está devuelto o pendiente de confirmar'; end if;
  update public.wardrobe_loans set status='return_requested', return_requested_at=now(), updated_at=now()
   where id=p_loan returning * into l;
  return l;
end $$;

-- La responsable confirma la devolución y el estado; la prenda vuelve al stock
create or replace function public.confirm_wardrobe_return(p_loan text, p_condition text, p_notes text)
returns public.wardrobe_loans language plpgsql security definer set search_path=public as $$
declare l public.wardrobe_loans;
begin
  if not public.is_wardrobe_manager() then raise exception 'Solo la responsable de vestuario puede confirmar devoluciones'; end if;
  if p_condition not in ('ok','repair','lost') then raise exception 'Estado no válido'; end if;
  select * into l from public.wardrobe_loans where id=p_loan for update;
  if not found then raise exception 'El préstamo no existe'; end if;
  if l.status = 'returned' then raise exception 'Esta devolución ya está confirmada'; end if;
  update public.wardrobe_loans
     set status='returned', returned_at=now(), confirmed_by=auth.uid(), return_condition=p_condition,
         notes=case when coalesce(p_notes,'')='' then notes else trim(both ' ' from notes||' · '||p_notes) end, updated_at=now()
   where id=p_loan returning * into l;
  if p_condition='repair' then
    update public.wardrobe_items set in_repair=in_repair+l.quantity, updated_at=now() where id=l.item_id;
  elsif p_condition='lost' then
    update public.wardrobe_items set quantity=greatest(quantity-l.quantity,0), in_repair=least(in_repair,greatest(quantity-l.quantity,0)), updated_at=now() where id=l.item_id;
  end if;
  return l;
end $$;

-- Prendas arregladas vuelven a estar disponibles
create or replace function public.mark_wardrobe_repaired(p_item text, p_qty integer)
returns public.wardrobe_items language plpgsql security definer set search_path=public as $$
declare it public.wardrobe_items;
begin
  if not public.is_wardrobe_manager() then raise exception 'Solo la responsable de vestuario'; end if;
  update public.wardrobe_items set in_repair=greatest(in_repair-greatest(coalesce(p_qty,1),1),0), updated_at=now()
   where id=p_item returning * into it;
  if not found then raise exception 'La prenda no existe'; end if;
  return it;
end $$;

revoke all on function public.lend_wardrobe_item(text,uuid,integer,text) from public;
revoke all on function public.request_wardrobe_return(text) from public;
revoke all on function public.confirm_wardrobe_return(text,text,text) from public;
revoke all on function public.mark_wardrobe_repaired(text,integer) from public;
revoke execute on function public.lend_wardrobe_item(text,uuid,integer,text) from anon;
revoke execute on function public.request_wardrobe_return(text) from anon;
revoke execute on function public.confirm_wardrobe_return(text,text,text) from anon;
revoke execute on function public.mark_wardrobe_repaired(text,integer) from anon;
grant execute on function public.lend_wardrobe_item(text,uuid,integer,text) to authenticated;
grant execute on function public.request_wardrobe_return(text) to authenticated;
grant execute on function public.confirm_wardrobe_return(text,text,text) to authenticated;
grant execute on function public.mark_wardrobe_repaired(text,integer) to authenticated;

-- ---------- Paso de las prendas asignadas al nuevo sistema ----------
insert into public.wardrobe_loans(id,item_id,user_id,member_name,quantity,notes,lent_at)
select 'loan-mig-'||w.id, w.id, w.holder_id, w.holder_name, greatest(w.quantity,1), 'Asignada antes de la v4.66', w.updated_at
  from public.wardrobe_items w
 where w.holder_id is not null
   and not exists (select 1 from public.wardrobe_loans l where l.id='loan-mig-'||w.id);
update public.wardrobe_items set holder_id=null, holder_name='' where holder_id is not null;
update public.wardrobe_items set in_repair=quantity, status='ok' where status='repair' and in_repair=0;
update public.wardrobe_items set quantity=0, status='ok', notes=trim(both ' ' from notes||' · Marcada como perdida antes de la v4.66') where status='lost';

-- Ajuste de permisos de la v4.65 (por si no se ejecutó el script opcional)
revoke execute on function public.set_task_status(text,boolean) from anon;
revoke execute on function public.set_performance_route(text,jsonb) from anon;
revoke execute on function public.update_my_birthday(date) from anon;

notify pgrst, 'reload schema';
