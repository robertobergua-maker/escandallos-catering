-- =============================================================================
-- 026_rollback.sql
-- Rollback completo de 026_facturacion_por_org.sql.
-- =============================================================================

begin;

-- 1. Triggers
drop trigger if exists trg_proteger_factura on public.facturas;
drop trigger if exists trg_proteger_factura_lineas_ins on public.factura_lineas;
drop trigger if exists trg_proteger_factura_lineas_upd on public.factura_lineas;
drop trigger if exists trg_proteger_factura_lineas_del on public.factura_lineas;
drop trigger if exists trg_org_config_set_updated_at on public.organizacion_config;

-- 2. Funciones
drop function if exists public.obtener_config_facturacion(uuid);
drop function if exists public.crear_rectificativa(uuid);
drop function if exists public.emitir_documento(uuid);
drop function if exists public._reservar_numero_documento(uuid, text, date);
drop function if exists public._trg_proteger_factura();
drop function if exists public._trg_proteger_factura_lineas();

-- 3. Índice único
drop index if exists public.idx_facturas_org_numero_unique;

-- 4. Columnas de facturas (snapshot emisor + snapshot cliente + rectificativa)
alter table public.facturas drop column if exists emisor_razon_social;
alter table public.facturas drop column if exists emisor_nif;
alter table public.facturas drop column if exists emisor_direccion;
alter table public.facturas drop column if exists emisor_cp_ciudad;
alter table public.facturas drop column if exists emisor_provincia;
alter table public.facturas drop column if exists emisor_pais;
alter table public.facturas drop column if exists emisor_email;
alter table public.facturas drop column if exists emisor_telefono;
alter table public.facturas drop column if exists emisor_logo;
alter table public.facturas drop column if exists emisor_logo_mime;
alter table public.facturas drop column if exists emisor_notas_pie;
alter table public.facturas drop column if exists cliente_snapshot_nombre;
alter table public.facturas drop column if exists cliente_snapshot_nif;
alter table public.facturas drop column if exists cliente_snapshot_direccion;
alter table public.facturas drop column if exists cliente_snapshot_cp;
alter table public.facturas drop column if exists cliente_snapshot_ciudad;
alter table public.facturas drop column if exists cliente_snapshot_provincia;
alter table public.facturas drop column if exists cliente_snapshot_pais;
alter table public.facturas drop column if exists cliente_snapshot_email;
alter table public.facturas drop column if exists factura_rectificada_id;

-- 5. Tabla organizacion_config
drop table if exists public.organizacion_config;

-- 6. Tabla organizacion_contadores
drop table if exists public.organizacion_contadores;

-- Verificación: tablas eliminadas (0 filas)
select count(*) as tablas_eliminadas
from pg_tables
where schemaname = 'public'
  and tablename in ('organizacion_config', 'organizacion_contadores');

commit;
