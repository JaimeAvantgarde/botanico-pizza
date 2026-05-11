-- =====================================================
-- Row Level Security (RLS)
-- =====================================================
-- - Carta: lectura pública (anon), escritura solo admin auth.
-- - Pedidos: anon NO puede leer ni insertar directo (solo vía función crear_pedido).
-- - Admin auth (rol authenticated): CRUD completo.
-- - service_role bypass total (para seeds).

-- Activar RLS en todas
alter table mesas        enable row level security;
alter table categorias   enable row level security;
alter table platos       enable row level security;
alter table pedidos      enable row level security;
alter table config       enable row level security;

-- ---------------------------------------------------------------
-- MESAS — solo admin lee/escribe; cliente no toca (el token va al revés)
-- ---------------------------------------------------------------
drop policy if exists "mesas_admin_all" on mesas;
create policy "mesas_admin_all"
  on mesas for all
  to authenticated
  using (true) with check (true);

-- ---------------------------------------------------------------
-- CATEGORÍAS — lectura pública, escritura solo admin
-- ---------------------------------------------------------------
drop policy if exists "cat_read_anon" on categorias;
create policy "cat_read_anon"
  on categorias for select
  to anon, authenticated
  using (true);

drop policy if exists "cat_admin_write" on categorias;
create policy "cat_admin_write"
  on categorias for all
  to authenticated
  using (true) with check (true);

-- ---------------------------------------------------------------
-- PLATOS — lectura pública (solo activos), escritura solo admin
-- ---------------------------------------------------------------
drop policy if exists "platos_read_anon" on platos;
create policy "platos_read_anon"
  on platos for select
  to anon, authenticated
  using (activo = true or auth.role() = 'authenticated');

drop policy if exists "platos_admin_write" on platos;
create policy "platos_admin_write"
  on platos for all
  to authenticated
  using (true) with check (true);

-- ---------------------------------------------------------------
-- PEDIDOS — anon NO acceso directo (solo vía función crear_pedido).
--            Admin auth: select/update completo.
-- ---------------------------------------------------------------
drop policy if exists "pedidos_admin_read" on pedidos;
create policy "pedidos_admin_read"
  on pedidos for select
  to authenticated
  using (true);

drop policy if exists "pedidos_admin_update" on pedidos;
create policy "pedidos_admin_update"
  on pedidos for update
  to authenticated
  using (true) with check (true);

-- Permite SELECT del pedido recién creado vía RPC para mostrar confirmación al cliente.
-- (La función crear_pedido se ejecuta como security definer, así que esto solo
--  importa para que el cliente pueda hacer realtime a su propio pedido.)
drop policy if exists "pedidos_self_anon" on pedidos;
create policy "pedidos_self_anon"
  on pedidos for select
  to anon
  using (false);  -- por defecto bloqueado; cambiamos a true por pedido_id concreto si quisiéramos
                  -- pero para realtime del cliente, el frontend filtra por id y la lectura
                  -- se hace vía RPC pública get_estado_pedido (definida abajo).

-- ---------------------------------------------------------------
-- CONFIG — lectura pública (horario), escritura admin
-- ---------------------------------------------------------------
drop policy if exists "config_read_anon" on config;
create policy "config_read_anon"
  on config for select
  to anon, authenticated
  using (true);

drop policy if exists "config_admin_write" on config;
create policy "config_admin_write"
  on config for all
  to authenticated
  using (true) with check (true);

-- =====================================================
-- Permitir que anon ejecute las funciones públicas
-- =====================================================
grant execute on function crear_pedido(smallint, text, jsonb, numeric, text) to anon, authenticated;
grant execute on function validar_mesa(smallint, text) to anon, authenticated;

-- =====================================================
-- Función pública para que el cliente consulte el estado de SU pedido
-- (recibe el id devuelto por crear_pedido)
-- =====================================================
create or replace function get_estado_pedido(p_id uuid)
returns table (id uuid, estado text, total numeric, created_at timestamptz)
language sql
security definer
set search_path = public
as $$
  select id, estado, total, created_at
  from pedidos
  where id = p_id
$$;

grant execute on function get_estado_pedido(uuid) to anon, authenticated;
