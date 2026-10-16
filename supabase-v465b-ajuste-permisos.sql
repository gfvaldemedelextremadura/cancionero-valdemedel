-- =====================================================================
-- CANCIONERO VALDEMEDEL · v4.65b · AJUSTE OPCIONAL DE PERMISOS
--
-- Supabase concede por defecto a los usuarios sin sesión (anon) permiso
-- para llamar a las funciones nuevas. No es un riesgo, porque cada función
-- comprueba quién la llama, pero así queda más limpio: solo los usuarios
-- con sesión pueden llamarlas. get_guest_performance NO se toca (la usan
-- los invitados, que no tienen sesión).
-- Es seguro ejecutarlo varias veces.
-- =====================================================================
revoke execute on function public.list_group_members() from anon;
revoke execute on function public.set_task_status(text,boolean) from anon;
revoke execute on function public.set_performance_route(text,jsonb) from anon;
revoke execute on function public.update_my_birthday(date) from anon;
