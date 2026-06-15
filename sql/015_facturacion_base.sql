-- 015_facturacion_base.sql
-- Preparacion base del modulo de facturacion interna de Samirarte.
--
-- IMPORTANTE:
-- - Este modulo prepara una estructura operativa para clientes, facturas y lineas.
-- - No certifica cumplimiento VERI*FACTU.
-- - No sustituye una revision fiscal ni legal.
-- - La adaptacion legal completa se hara en una fase posterior.
-- - No activa RLS para facturacion; se preparara en una fase separada.

create table if not exists public.clientes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  nombre text not null,
  tipo_cliente text,
  nif_cif text,
  email text,
  telefono text,
  direccion text,
  codigo_postal text,
  ciudad text,
  provincia text,
  pais text default 'España',
  observaciones text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.facturas (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  cliente_id uuid references public.clientes(id) on delete set null,
  numero_factura text,
  tipo_documento text default 'factura',
  estado text default 'borrador',
  fecha_emision date default current_date,
  fecha_vencimiento date,
  concepto text,
  base_imponible numeric(12,2) default 0,
  iva_pct numeric(8,2) default 21,
  iva_importe numeric(12,2) default 0,
  retencion_pct numeric(8,2) default 0,
  retencion_importe numeric(12,2) default 0,
  total numeric(12,2) default 0,
  metodo_pago text,
  estado_cobro text default 'pendiente',
  notas text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.factura_lineas (
  id uuid primary key default gen_random_uuid(),
  factura_id uuid not null references public.facturas(id) on delete cascade,
  origen_tipo text,
  origen_id uuid,
  descripcion text not null,
  cantidad numeric(12,3) default 1,
  unidad text default 'ud',
  precio_unitario numeric(12,4) default 0,
  descuento_pct numeric(8,2) default 0,
  base_linea numeric(12,2) default 0,
  iva_pct numeric(8,2) default 21,
  iva_linea numeric(12,2) default 0,
  total_linea numeric(12,2) default 0,
  orden integer default 0,
  created_at timestamptz default now()
);

create index if not exists idx_clientes_user_id
on public.clientes(user_id);

create index if not exists idx_clientes_nombre
on public.clientes(nombre);

create index if not exists idx_facturas_user_id
on public.facturas(user_id);

create index if not exists idx_facturas_cliente_id
on public.facturas(cliente_id);

create index if not exists idx_facturas_numero_factura
on public.facturas(numero_factura);

create index if not exists idx_factura_lineas_factura_id
on public.factura_lineas(factura_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_clientes_set_updated_at on public.clientes;
create trigger trg_clientes_set_updated_at
before update on public.clientes
for each row
execute function public.set_updated_at();

drop trigger if exists trg_facturas_set_updated_at on public.facturas;
create trigger trg_facturas_set_updated_at
before update on public.facturas
for each row
execute function public.set_updated_at();

comment on table public.clientes is 'Clientes del modulo de facturacion interna de Samirarte.';
comment on table public.facturas is 'Cabecera de documentos de facturacion interna. No certifica cumplimiento VERI*FACTU.';
comment on table public.factura_lineas is 'Lineas de facturas, presupuestos o documentos rectificativos.';
comment on column public.facturas.tipo_documento is 'Tipo recomendado: presupuesto, factura o factura_rectificativa.';
comment on column public.facturas.estado is 'Estado recomendado: borrador, emitida, cobrada o anulada.';
comment on column public.facturas.estado_cobro is 'Estado operativo de cobro, por ejemplo pendiente, parcial o cobrado.';
comment on column public.factura_lineas.origen_tipo is 'Origen futuro de la linea: manual, menu, evento, receta u otro.';
comment on column public.factura_lineas.origen_id is 'Identificador futuro del origen relacionado, si existe.';
