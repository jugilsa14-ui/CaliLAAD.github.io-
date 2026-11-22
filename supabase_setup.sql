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
