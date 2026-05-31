-- =====================================================
-- Botánico Pizza — Esquema base (Supabase Postgres)
-- =====================================================
-- Ejecutar en Supabase Dashboard → SQL Editor
-- Orden: 01_schema.sql → 02_rls.sql → 03_seed_carta.sql → 04_seed_mesas.sql

-- Extensiones
create extension if not exists "pgcrypto";

-- =====================================================
-- TABLAS
-- =====================================================

-- Mesas (14 fijas)
create table if not exists mesas (
  id smallint primary key check (id between 1 and 99),
  token text unique not null,
  activa boolean not null default true,
  created_at timestamptz not null default now()
);

-- Categorías de la carta
create table if not exists categorias (
  id text primary key,                    -- 'pizzas-novedades', 'pasta', etc.
  nombre text not null,
  orden smallint not null default 0
);

-- Platos
create table if not exists platos (
  id uuid primary key default gen_random_uuid(),
  categoria_id text not null references categorias(id) on delete restrict,
  nombre text not null,
  descripcion text,
  precio numeric(6,2) not null check (precio >= 0),
  tag text,                               -- 'Novedad', 'De la casa', etc.
  tag_popular boolean not null default false,
  imagen text,                            -- URL relativa o nula
  activo boolean not null default true,
  orden smallint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_platos_categoria on platos(categoria_id, orden);
create index if not exists idx_platos_activo on platos(activo) where activo = true;

-- Pedidos
create table if not exists pedidos (
  id uuid primary key default gen_random_uuid(),
  mesa_id smallint not null references mesas(id),
  estado text not null default 'nuevo'
    check (estado in ('nuevo','preparando','servido','cancelado')),
  total numeric(7,2) not null check (total >= 0),
  items jsonb not null,                   -- [{plato_id, nombre, precio, cantidad, nota, subtotal}]
  num_items smallint not null,
  ip_hash text,                           -- hash de la IP del cliente (rate limit)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_pedidos_mesa_estado on pedidos(mesa_id, estado);
create index if not exists idx_pedidos_created on pedidos(created_at desc);
create index if not exists idx_pedidos_estado on pedidos(estado) where estado in ('nuevo','preparando');

-- Configuración general (horario, IVA, mensajes...)
create table if not exists config (
  clave text primary key,
  valor jsonb not null,
  updated_at timestamptz not null default now()
);

-- =====================================================
-- TRIGGERS — updated_at automático
-- =====================================================
create or replace function set_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_platos_updated on platos;
create trigger trg_platos_updated before update on platos
  for each row execute function set_updated_at();

drop trigger if exists trg_pedidos_updated on pedidos;
create trigger trg_pedidos_updated before update on pedidos
  for each row execute function set_updated_at();

-- =====================================================
-- FUNCIÓN: validar token de mesa antes de aceptar pedido
-- =====================================================
-- Devuelve true si el token coincide con el de la mesa y está activa,
-- y no hay otro pedido en estado 'nuevo' o 'preparando' para esa mesa
-- desde hace menos de 30 minutos (rate limit blando).
create or replace function validar_mesa(p_mesa smallint, p_token text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean;
begin
  select exists(
    select 1 from mesas
    where id = p_mesa and token = p_token and activa = true
  ) into v_ok;
  return coalesce(v_ok, false);
end;
$$;

-- =====================================================
-- FUNCIÓN: insertar pedido validando token (única vía pública)
-- =====================================================
create or replace function crear_pedido(
  p_mesa smallint,
  p_token text,
  p_items jsonb,
  p_total numeric,
  p_ip_hash text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_count smallint;
  v_recent smallint;
begin
  -- Valida token de mesa
  if not validar_mesa(p_mesa, p_token) then
    raise exception 'TOKEN_INVALIDO';
  end if;

  -- Valida items
  if jsonb_array_length(p_items) = 0 then
    raise exception 'PEDIDO_VACIO';
  end if;
  if jsonb_array_length(p_items) > 50 then
    raise exception 'DEMASIADOS_ITEMS';
  end if;

  -- Rate limit: máx 3 pedidos por mesa en últimos 10 min
  select count(*) into v_recent
  from pedidos
  where mesa_id = p_mesa
    and created_at > now() - interval '10 minutes';
  if v_recent >= 3 then
    raise exception 'RATE_LIMIT';
  end if;

  -- num_items = suma de cantidades
  select coalesce(sum((it->>'cantidad')::int), 0)::smallint
  into v_count
  from jsonb_array_elements(p_items) it;

  insert into pedidos (mesa_id, items, total, num_items, ip_hash)
  values (p_mesa, p_items, p_total, v_count, p_ip_hash)
  returning id into v_id;

  return v_id;
end;
$$;

-- =====================================================
-- VISTAS — para consumo público de la carta
-- =====================================================
create or replace view carta_publica as
select
  c.id as categoria_id,
  c.nombre as categoria_nombre,
  c.orden as categoria_orden,
  p.id as plato_id,
  p.nombre,
  p.descripcion,
  p.precio,
  p.tag,
  p.tag_popular,
  p.imagen,
  p.orden as plato_orden
from categorias c
left join platos p on p.categoria_id = c.id and p.activo = true
order by c.orden, p.orden, p.nombre;

comment on view carta_publica is 'Carta filtrada por activos, accesible públicamente';
