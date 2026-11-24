-- CALI.LAAD · configuración de la base de datos en Supabase
-- Pégalo en Supabase → SQL Editor → New query → Run. Solo hace falta una vez.

create table if not exists public.sesiones (
  id         text primary key,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  fecha      date not null,
  datos      jsonb not null,
  creado     timestamptz not null default now()
);

create index if not exists sesiones_user_fecha on public.sesiones (user_id, fecha);

-- Cada usuario solo ve, crea, cambia y borra sus propias sesiones
alter table public.sesiones enable row level security;

create policy "ver mis sesiones"    on public.sesiones for select using (auth.uid() = user_id);
create policy "crear mis sesiones"  on public.sesiones for insert with check (auth.uid() = user_id);
create policy "cambiar mis sesiones" on public.sesiones for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "borrar mis sesiones" on public.sesiones for delete using (auth.uid() = user_id);

-- ============================================================
-- Datos agregados («big data») · solo de quien lo aceptó al crear la cuenta
-- El consentimiento se guarda en los datos de la cuenta: estadistica = true
-- ============================================================

-- Estadística semanal de la comunidad: medias, mínimos y máximos.
-- Solo semanas con 5 personas o más, para que nadie sea identificable.
create or replace function public.comunidad_semanal()
returns table (semana date, personas int, sesiones int,
               ladau_media numeric, ladau_min numeric, ladau_max numeric,
               inol_media numeric, inol_min numeric, inol_max numeric)
language sql security definer set search_path = public as $$
  with s as (
    select date_trunc('week', x.fecha)::date as semana, x.user_id,
           (x.datos->>'ladau')::numeric as ladau, (x.datos->>'inol')::numeric as inol
    from public.sesiones x
    join auth.users u on u.id = x.user_id
    where coalesce((u.raw_user_meta_data->>'estadistica')::boolean, false)
  ), por_persona as (
    select semana, user_id, sum(ladau) as ladau, sum(inol) as inol, count(*) as n
    from s group by semana, user_id
  )
  select semana, count(*)::int, sum(n)::int,
         round(avg(ladau),1), round(min(ladau),1), round(max(ladau),1),
         round(avg(inol),2), round(min(inol),2), round(max(inol),2)
  from por_persona group by semana having count(*) >= 5 order by semana;
$$;
revoke all on function public.comunidad_semanal() from public;
grant execute on function public.comunidad_semanal() to authenticated;

-- Para el autor (desde el SQL Editor de Supabase): sesiones anónimas de quien aceptó.
-- Sin correo ni id real: cada persona aparece con un código que no permite identificarla.
create or replace view public.datos_investigacion as
  select md5(x.user_id::text || 'calilaad') as persona, x.fecha,
         (x.datos->>'ladau')::numeric as ladau, (x.datos->>'base')::numeric as base,
         (x.datos->>'inol')::numeric as inol, (x.datos->>'nSeries')::int as series,
         (x.datos->>'fallos')::int as fallos, (x.datos->>'cerca')::int as cerca_fallo,
         x.datos->'prog' as progresion, x.datos->'series' as detalle_series, x.datos->'weights' as pesas
  from public.sesiones x join auth.users u on u.id = x.user_id
  where coalesce((u.raw_user_meta_data->>'estadistica')::boolean, false);
revoke all on public.datos_investigacion from anon, authenticated;

-- ============================================================
-- PARTE 2 · Pago único (4,99 €) y permisos (22 nov 2026)
-- Pégala también en el SQL Editor y pulsa Run. Se puede repetir sin romper nada.
-- ============================================================

-- Perfil de cada cuenta: si ha pagado o no.
create table if not exists public.perfiles (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  pagado     boolean not null default false,
  pagado_en  timestamptz,
  plataforma text,          -- 'lemonsqueezy' o 'stripe'
  pedido     text,          -- número de pedido de la plataforma
  creado     timestamptz not null default now()
);
alter table public.perfiles enable row level security;

-- Cada persona puede LEER su perfil. Nadie puede crearlo, cambiarlo ni borrarlo desde la web:
-- solo la función de pagos del servidor (con la clave secreta, que nunca sale de Supabase).
drop policy if exists "ver mi perfil" on public.perfiles;
create policy "ver mi perfil" on public.perfiles for select using (auth.uid() = user_id);
revoke insert, update, delete on public.perfiles from anon, authenticated;

-- Al crear una cuenta se crea su perfil (sin pagar).
create or replace function public.crear_perfil() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfiles (user_id) values (new.id) on conflict do nothing;
  return new;
end $$;
drop trigger if exists al_crear_cuenta on auth.users;
create trigger al_crear_cuenta after insert on auth.users
  for each row execute function public.crear_perfil();
insert into public.perfiles (user_id) select id from auth.users on conflict do nothing;

-- Límite gratuito: 5 sesiones guardadas. Con el pago, sin límite.
create or replace function public.puede_guardar() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select pagado from public.perfiles where user_id = auth.uid()), false)
      or (select count(*) from public.sesiones where user_id = auth.uid()) < 5;
$$;
revoke all on function public.puede_guardar() from public;
grant execute on function public.puede_guardar() to authenticated;

-- Crear una sesión nueva exige que sea tuya Y que te quede hueco (cambiar una que ya existe, siempre se puede).
drop policy if exists "crear mis sesiones" on public.sesiones;
create policy "crear mis sesiones" on public.sesiones for insert
  with check (auth.uid() = user_id and public.puede_guardar());

-- Estado de mi cuenta para la web: pagado y sesiones usadas.
create or replace function public.mi_estado() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'pagado', coalesce((select pagado from public.perfiles where user_id = auth.uid()), false),
    'usadas', (select count(*) from public.sesiones where user_id = auth.uid()),
    'gratis', 5);
$$;
revoke all on function public.mi_estado() from public;
grant execute on function public.mi_estado() to authenticated;

-- Derecho de supresión (RGPD, art. 17): cada persona puede borrar su cuenta y todo lo suyo.
-- Borra el usuario; sesiones y perfil se borran en cascada. Las facturas quedan en la plataforma de pago.
create or replace function public.borrar_mi_cuenta() returns void
language sql security definer set search_path = public, auth as $$
  delete from auth.users where id = auth.uid();
$$;
revoke all on function public.borrar_mi_cuenta() from public;
grant execute on function public.borrar_mi_cuenta() to authenticated;

-- Nadie sin cuenta puede leer ni escribir nada.
revoke all on public.sesiones from anon;
revoke all on public.perfiles from anon;

-- ============================================================
-- PARTE 3 · Plan, deportistas y ajustes de cada cuenta (24 nov 2026)
-- Pégala también en el SQL Editor y pulsa Run. Se puede repetir sin romper nada.
-- Guarda el modo de uso, la carpeta de deportistas y el plan de cada uno,
-- para que cada persona los tenga en el móvil, el ordenador o donde entrene.
-- ============================================================
create table if not exists public.ajustes (
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  id          text not null,            -- 'cfg', 'a_<deportista>', 'p_<deportista>'
  datos       jsonb not null,
  actualizado timestamptz not null default now(),
  primary key (user_id, id)
);
alter table public.ajustes enable row level security;
drop policy if exists "mis ajustes" on public.ajustes;
create policy "mis ajustes" on public.ajustes for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
revoke all on public.ajustes from anon;

-- Para el autor: marcar tu propia cuenta como pagada (cambia el correo por el tuyo y pulsa Run).
-- update public.perfiles set pagado = true, pagado_en = now(), plataforma = 'autor'
--   where user_id = (select id from auth.users where email = 'tu-correo@ejemplo.com');
