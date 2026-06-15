-- 016_facturacion_rls.sql
-- Seguridad RLS para el modulo de facturacion.
--
-- IMPORTANTE:
-- - No se hace migracion automatica de datos.
-- - Los registros antiguos con user_id null no seran visibles con RLS estricto.
-- - factura_lineas hereda la seguridad desde facturas mediante factura_id.
-- - Revisar y probar en un entorno seguro antes de ejecutar en el inventario real.

alter table public.clientes enable row level security;
alter table public.facturas enable row level security;
alter table public.factura_lineas enable row level security;

drop policy if exists clientes_select_own on public.clientes;
create policy clientes_select_own
on public.clientes
for select
using (user_id = auth.uid());

drop policy if exists clientes_insert_own on public.clientes;
create policy clientes_insert_own
on public.clientes
for insert
with check (user_id = auth.uid());

drop policy if exists clientes_update_own on public.clientes;
create policy clientes_update_own
on public.clientes
for update
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists clientes_delete_own on public.clientes;
create policy clientes_delete_own
on public.clientes
for delete
using (user_id = auth.uid());

drop policy if exists facturas_select_own on public.facturas;
create policy facturas_select_own
on public.facturas
for select
using (user_id = auth.uid());

drop policy if exists facturas_insert_own on public.facturas;
create policy facturas_insert_own
on public.facturas
for insert
with check (user_id = auth.uid());

drop policy if exists facturas_update_own on public.facturas;
create policy facturas_update_own
on public.facturas
for update
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists facturas_delete_own on public.facturas;
create policy facturas_delete_own
on public.facturas
for delete
using (user_id = auth.uid());

drop policy if exists factura_lineas_select_own on public.factura_lineas;
create policy factura_lineas_select_own
on public.factura_lineas
for select
using (
  exists (
    select 1
    from public.facturas
    where public.facturas.id = factura_lineas.factura_id
      and public.facturas.user_id = auth.uid()
  )
);

drop policy if exists factura_lineas_insert_own on public.factura_lineas;
create policy factura_lineas_insert_own
on public.factura_lineas
for insert
with check (
  exists (
    select 1
    from public.facturas
    where public.facturas.id = factura_lineas.factura_id
      and public.facturas.user_id = auth.uid()
  )
);

drop policy if exists factura_lineas_update_own on public.factura_lineas;
create policy factura_lineas_update_own
on public.factura_lineas
for update
using (
  exists (
    select 1
    from public.facturas
    where public.facturas.id = factura_lineas.factura_id
      and public.facturas.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.facturas
    where public.facturas.id = factura_lineas.factura_id
      and public.facturas.user_id = auth.uid()
  )
);

drop policy if exists factura_lineas_delete_own on public.factura_lineas;
create policy factura_lineas_delete_own
on public.factura_lineas
for delete
using (
  exists (
    select 1
    from public.facturas
    where public.facturas.id = factura_lineas.factura_id
      and public.facturas.user_id = auth.uid()
  )
);
