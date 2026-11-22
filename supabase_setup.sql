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
