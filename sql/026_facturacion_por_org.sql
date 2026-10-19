-- =============================================================================
-- 026_facturacion_por_org.sql
-- Fase 5 — Facturación por organización: numeración anual, datos del emisor
-- por org, logo por org, snapshot al emitir, trigger de protección, rectificativas.
-- =============================================================================
--
-- DECISIONES DE SAMIRA (no cambiar):
--   1. Numeración anual por org y tipo: FAC-AAAA-NNNN, REC-AAAA-NNNN,
--      PRE-AAAA-NNNN. Contador independiente por org/tipo/año, reinicia 1 de enero.
--      El año sale de fecha_emision (Europe/Madrid).
--   2. Solo el GERENTE emite (asigna número y pasa a 'emitida').
--      Los chefs pueden crear/editar BORRADORES (sin número).
--   3. Un documento EMITIDO es inalterable: no editar contenido, importes,
--      cliente, fecha ni número, ni borrar. Solo emitida→cobrada (cualquier
--      tipo) y emitida→anulada (SOLO presupuestos). Una factura emitida no se
--      anula: se corrige con rectificativa. Garantizado por TRIGGER de BD.
--   4. Datos del emisor por organización en organizacion_config (razón social,
--      NIF, dirección, logo bytea, IVA def., pie de factura). Sin razón social,
--      NIF y dirección completos NO se puede emitir.
--
-- SIN BYPASS DE ADMIN (respeta 023d): ningún es_admin_app en políticas.
-- Solo gerente de la org gestiona config y emite.
--
-- Requisitos previos: 022, 023a, 023c, 023d, 024, 024b, 025, 025b, 025c.
-- Reversible: 026_rollback.sql.
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ===========================================================================
-- 0. AUDITORÍA PREVIA (solo lectura)
-- ===========================================================================

-- Documentos por org, tipo, estado y formato de número:
select
  organizacion_id,
  tipo_documento,
  estado,
  count(*)                                    as total,
  max(numero_factura)                          as ultimo_numero
from public.facturas
group by organizacion_id, tipo_documento, estado
order by organizacion_id, tipo_documento, estado;

-- Borradores con número (anomalía previa; se dejan intactos):
select id, tipo_documento, numero_factura, estado, fecha_emision
from public.facturas
where estado = 'borrador' and numero_factura is not null
order by tipo_documento, numero_factura;


-- ===========================================================================
-- 1. TABLA: organizacion_contadores
--    PK compuesta (organizacion_id, tipo_documento, anio).
--    RLS activado SIN políticas + REVOKE ALL: inaccesible salvo SECURITY DEFINER.
-- ===========================================================================

create table if not exists public.organizacion_contadores (
  organizacion_id  uuid        not null
                      references public.organizaciones(id) on delete cascade,
  tipo_documento   text        not null,   -- 'factura' | 'factura_rectificativa' | 'presupuesto'
  anio             integer     not null,
  ultimo_numero    integer     not null default 0,

  primary key (organizacion_id, tipo_documento, anio),

  constraint contadores_tipo_check
    check (tipo_documento in ('factura', 'factura_rectificativa', 'presupuesto')),
  constraint contadores_ultimo_no_negativo
    check (ultimo_numero >= 0)
);

comment on table public.organizacion_contadores
  is 'Contadores de numeración anual por org/tipo/año. '
     'RLS sin políticas: inaccesible a authenticated/anon. '
     'Solo escriben funciones SECURITY DEFINER.';

alter table public.organizacion_contadores enable row level security;
revoke all on public.organizacion_contadores from anon, authenticated;


-- ===========================================================================
-- 2. TABLA: organizacion_config
--    Datos fiscales + logo (bytea) por organización.
--    RLS: select para miembros, insert/update solo gerente. Sin delete.
-- ===========================================================================

create table if not exists public.organizacion_config (
  organizacion_id       uuid      primary key
                          references public.organizaciones(id) on delete cascade,

  razon_social          text,
  nif_cif               text,
  direccion_fiscal      text,
  codigo_postal_fiscal  text,
  ciudad_fiscal         text,
  provincia_fiscal      text,
  pais_fiscal           text      default 'España',
  email_fiscal          text,
  telefono_fiscal       text,

  logo                  bytea,    -- PNG/JPG/WEBP, máx 300 KB (validado por la app)
  logo_mime             text,    -- 'image/png' | 'image/jpeg' | 'image/webp'

  tipo_iva_defecto      numeric(8,2) not null default 21,
  notas_pie_factura     text,

  updated_at            timestamptz not null default now(),
  created_at            timestamptz not null default now(),

  constraint org_config_iva_rango
    check (tipo_iva_defecto >= 0 and tipo_iva_defecto <= 100),
  -- Logo: máximo 300 KB y solo PNG/JPG/WEBP
  constraint org_config_logo_tamano
    check (logo is null or octet_length(logo) <= 307200),
  constraint org_config_logo_mime
    check (logo_mime is null or logo_mime in ('image/png', 'image/jpeg', 'image/webp'))
);

comment on table public.organizacion_config
  is 'Datos fiscales, logo y configuración de facturación de cada organización. '
     'Logo en bytea (sin Storage). Solo gerente edita. Sin delete.';

alter table public.organizacion_config enable row level security;

drop trigger if exists trg_org_config_set_updated_at on public.organizacion_config;
create trigger trg_org_config_set_updated_at
  before update on public.organizacion_config
  for each row execute function public.set_updated_at();

-- RLS: select para miembros de la org
drop policy if exists org_config_select on public.organizacion_config;
create policy org_config_select
  on public.organizacion_config for select to authenticated
  using (public.es_miembro_org(organizacion_id));

-- Insert: solo gerente de la org
drop policy if exists org_config_insert on public.organizacion_config;
create policy org_config_insert
  on public.organizacion_config for insert to authenticated
  with check (public.es_gerente_org(organizacion_id));

-- Update: solo gerente de la org
drop policy if exists org_config_update on public.organizacion_config;
create policy org_config_update
  on public.organizacion_config for update to authenticated
  using (public.es_gerente_org(organizacion_id))
  with check (public.es_gerente_org(organizacion_id));

-- Sin política DELETE: la config no se puede borrar.


-- ===========================================================================
-- 3. ALTER facturas: columnas snapshot del emisor + rectificativa
-- ===========================================================================

alter table public.facturas
  -- Snapshot del EMISOR al emitir (NULL en borradores)
  add column if not exists emisor_razon_social    text,
  add column if not exists emisor_nif             text,
  add column if not exists emisor_direccion       text,
  add column if not exists emisor_cp_ciudad      text,
  add column if not exists emisor_provincia       text,
  add column if not exists emisor_pais            text,
  add column if not exists emisor_email           text,
  add column if not exists emisor_telefono        text,
  add column if not exists emisor_logo            bytea,
  add column if not exists emisor_logo_mime       text,
  add column if not exists emisor_notas_pie       text,
  -- Snapshot del CLIENTE al emitir (NULL en borradores)
  add column if not exists cliente_snapshot_nombre     text,
  add column if not exists cliente_snapshot_nif        text,
  add column if not exists cliente_snapshot_direccion  text,
  add column if not exists cliente_snapshot_cp         text,
  add column if not exists cliente_snapshot_ciudad     text,
  add column if not exists cliente_snapshot_provincia  text,
  add column if not exists cliente_snapshot_pais       text,
  add column if not exists cliente_snapshot_email      text,
  -- Enlace de rectificativa
  add column if not exists factura_rectificada_id uuid
    references public.facturas(id) on delete set null;

comment on column public.facturas.emisor_razon_social
  is 'Snapshot de la razón social del emisor al emitir. NULL en borradores.';
comment on column public.facturas.emisor_logo
  is 'Snapshot del logo del emisor (bytea) al emitir. NULL en borradores.';
comment on column public.facturas.cliente_snapshot_nombre
  is 'Snapshot del cliente al emitir (inmutable). NULL en borradores; '
     'los borradores usan la ficha actual del cliente.';
comment on column public.facturas.factura_rectificada_id
  is 'FK a la factura original que rectifica (solo tipo factura_rectificativa).';


-- ===========================================================================
-- 4. NORMALIZAR BORRADORES ANTIGUOS + ÍNDICE ÚNICO
-- ===========================================================================

-- Los borradores de la app anterior se guardaban con un número diario ya
-- asignado. En el nuevo modelo los borradores NO llevan número (se asigna al
-- emitir). Antes de crear el índice único, limpiamos el número de todos los
-- borradores para que no bloqueen el índice ni se confundan con emitidos.
-- La auditoría de la sección 0 lista estos documentos. Los documentos ya
-- emitidos/cobrados/anulados conservan su número tal cual.
update public.facturas
set numero_factura = null
where estado = 'borrador'
  and numero_factura is not null;

-- Índice único: un número no puede repetirse dentro de una organización.
create unique index if not exists idx_facturas_org_numero_unique
  on public.facturas (organizacion_id, numero_factura)
  where numero_factura is not null;


-- ===========================================================================
-- 5. FUNCIÓN INTERNA: _reservar_numero_documento
--    Contador anual por org/tipo/año. SECURITY DEFINER. REVOKE a todos.
--    pg_advisory_xact_lock para atomicidad entre sesiones concurrentes.
-- ===========================================================================

create or replace function public._reservar_numero_documento(
  p_organizacion_id uuid,
  p_tipo_documento  text,
  p_fecha           date
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anio    integer := extract(year from p_fecha)::integer;
  v_numero  integer;
  v_prefijo text;
begin
  -- Prefijo según tipo
  v_prefijo := case p_tipo_documento
    when 'factura'               then 'FAC'
    when 'factura_rectificativa' then 'REC'
    when 'presupuesto'           then 'PRE'
  end;
  if v_prefijo is null then
    raise exception 'Tipo de documento no soportado: %', p_tipo_documento;
  end if;

  -- Lock exclusivo por org+tipo+año (estable y único)
  perform pg_advisory_xact_lock(
    hashtext(p_organizacion_id::text || '|' || p_tipo_documento || '|' || v_anio::text)
  );

  -- Upsert del contador: si no existe la fila para este año, crearla con 1
  insert into public.organizacion_contadores (organizacion_id, tipo_documento, anio, ultimo_numero)
  values (p_organizacion_id, p_tipo_documento, v_anio, 1)
  on conflict (organizacion_id, tipo_documento, anio)
  do update set ultimo_numero = public.organizacion_contadores.ultimo_numero + 1
  returning ultimo_numero into v_numero;

  return v_prefijo || '-' || v_anio::text || '-' || lpad(v_numero::text, 4, '0');
end;
$$;

revoke all on function public._reservar_numero_documento(uuid, text, date)
  from public, anon, authenticated;

comment on function public._reservar_numero_documento(uuid, text, date)
  is 'Función interna. Reserva número anual por org/tipo/año atómicamente. '
     'Formato: PREFIJO-AAAA-NNNN. No callable directamente.';


-- ===========================================================================
-- 6. FUNCIÓN: emitir_documento
--    Solo gerente. Exige estado 'borrador', sin número, config fiscal completa.
--    Reserva número, asigna fecha_emision = hoy Madrid, estado 'emitida',
--    guarda snapshot del emisor (incluido logo).
--    Devuelve el número asignado.
-- ===========================================================================

create or replace function public.emitir_documento(
  p_factura_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doc        record;
  v_config     record;
  v_cli        record;
  v_numero     text;
  v_fecha      date;
  v_n_lineas   integer;
  v_base       numeric;
  v_iva        numeric;
  v_total      numeric;
begin
  -- Fecha de emisión en zona horaria del negocio
  v_fecha := (current_timestamp at time zone 'Europe/Madrid')::date;

  -- Bloquear la fila y verificar acceso del gerente
  select f.* into v_doc
  from public.facturas f
  where f.id = p_factura_id
  for update;

  if not found then
    raise exception 'Documento no encontrado (id: %).', p_factura_id;
  end if;

  -- Solo el gerente de la org puede emitir
  if not public.es_gerente_org(v_doc.organizacion_id) then
    raise exception 'Solo el gerente de la organización puede emitir documentos.';
  end if;

  if v_doc.estado <> 'borrador' then
    raise exception 'Solo se pueden emitir documentos en estado borrador. Estado actual: %.', v_doc.estado;
  end if;

  if v_doc.numero_factura is not null then
    raise exception 'Este documento ya tiene número asignado: %.', v_doc.numero_factura;
  end if;

  -- Las facturas y rectificativas exigen cliente
  if v_doc.tipo_documento in ('factura', 'factura_rectificativa')
     and v_doc.cliente_id is null then
    raise exception 'Una factura o rectificativa debe tener cliente antes de emitirse.';
  end if;

  -- Exigir al menos una línea
  select count(*),
         coalesce(sum(base_linea), 0),
         coalesce(sum(iva_linea), 0),
         coalesce(sum(total_linea), 0)
  into v_n_lineas, v_base, v_iva, v_total
  from public.factura_lineas
  where factura_id = p_factura_id;

  if v_n_lineas = 0 then
    raise exception 'El documento no tiene líneas. Añade al menos una línea antes de emitir.';
  end if;

  -- Validar que los totales de cabecera cuadran con la suma de líneas (tol. 0,01 €).
  -- Nota: el total de cabecera resta la retención; la suma de líneas no la incluye,
  -- por eso se compara base + IVA de líneas contra base_imponible + iva_importe.
  if abs(coalesce(v_doc.base_imponible, 0) - v_base) > 0.01
     or abs(coalesce(v_doc.iva_importe, 0) - v_iva) > 0.01
     or abs((coalesce(v_doc.base_imponible, 0) + coalesce(v_doc.iva_importe, 0)
             - coalesce(v_doc.retencion_importe, 0)) - coalesce(v_doc.total, 0)) > 0.01 then
    raise exception
      'Los totales del documento no cuadran con las líneas '
      '(base líneas: %, IVA líneas: %; cabecera base: %, IVA: %, total: %). '
      'Vuelve a guardar el documento para recalcular.',
      round(v_base, 2), round(v_iva, 2),
      round(coalesce(v_doc.base_imponible, 0), 2),
      round(coalesce(v_doc.iva_importe, 0), 2),
      round(coalesce(v_doc.total, 0), 2);
  end if;

  -- Cargar config fiscal de la org
  select * into v_config
  from public.organizacion_config
  where organizacion_id = v_doc.organizacion_id;

  -- Exigir config fiscal completa
  if v_config is null
     or coalesce(v_config.razon_social, '') = ''
     or coalesce(v_config.nif_cif, '') = ''
     or coalesce(v_config.direccion_fiscal, '') = ''
  then
    raise exception
      'Faltan datos fiscales del emisor (razón social, NIF/CIF y dirección son obligatorios). '
      'Configúralos en Gerente → Datos de la organización antes de emitir.';
  end if;

  -- Cargar el cliente para el snapshot (si hay)
  select * into v_cli
  from public.clientes
  where id = v_doc.cliente_id;

  -- El cliente, si lo hay, debe pertenecer a la misma organización que el documento
  if v_doc.cliente_id is not null
     and (v_cli is null or v_cli.organizacion_id <> v_doc.organizacion_id) then
    raise exception 'El cliente no pertenece a esta organización.';
  end if;

  -- Reservar número
  v_numero := public._reservar_numero_documento(
    v_doc.organizacion_id,
    v_doc.tipo_documento,
    v_fecha
  );

  -- Emitir: número, fecha, estado, snapshot del emisor y snapshot del cliente
  update public.facturas
  set
    numero_factura            = v_numero,
    estado                    = 'emitida',
    fecha_emision             = v_fecha,
    -- Snapshot emisor
    emisor_razon_social       = v_config.razon_social,
    emisor_nif                = v_config.nif_cif,
    emisor_direccion          = v_config.direccion_fiscal,
    emisor_cp_ciudad          = coalesce(v_config.codigo_postal_fiscal, '') || ' ' || coalesce(v_config.ciudad_fiscal, ''),
    emisor_provincia          = v_config.provincia_fiscal,
    emisor_pais               = coalesce(v_config.pais_fiscal, 'España'),
    emisor_email              = v_config.email_fiscal,
    emisor_telefono           = v_config.telefono_fiscal,
    emisor_logo               = v_config.logo,
    emisor_logo_mime          = v_config.logo_mime,
    emisor_notas_pie          = v_config.notas_pie_factura,
    -- Snapshot cliente (NULL si el documento no tiene cliente, p.ej. presupuesto)
    cliente_snapshot_nombre    = v_cli.nombre,
    cliente_snapshot_nif       = v_cli.nif_cif,
    cliente_snapshot_direccion = v_cli.direccion,
    cliente_snapshot_cp        = v_cli.codigo_postal,
    cliente_snapshot_ciudad    = v_cli.ciudad,
    cliente_snapshot_provincia = v_cli.provincia,
    cliente_snapshot_pais      = v_cli.pais,
    cliente_snapshot_email     = v_cli.email,
    updated_at                 = now()
  where id = p_factura_id;

  return v_numero;
end;
$$;

revoke execute on function public.emitir_documento(uuid) from public, anon;
grant  execute on function public.emitir_documento(uuid) to authenticated;

comment on function public.emitir_documento(uuid)
  is 'Emite un documento borrador: solo gerente, exige config fiscal completa, '
     'reserva número anual, guarda snapshot del emisor. Devuelve el número.';


-- ===========================================================================
-- 7. FUNCIÓN: crear_rectificativa
--    Crea un borrador tipo factura_rectificativa enlazado a una factura
--    emitida/cobrada de la misma org. Solo gerente.
--    Copia cliente, líneas e importes de la original para facilitar la edición.
-- ===========================================================================

create or replace function public.crear_rectificativa(
  p_factura_original uuid
)
returns uuid   -- id del nuevo borrador rectificativo
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orig    record;
  v_nuevo_id uuid;
  v_linea    record;
  v_config   record;
  v_org      uuid;
begin
  -- Cargar y bloquear la original
  select f.* into v_orig
  from public.facturas f
  where f.id = p_factura_original
  for update;

  if not found then
    raise exception 'Factura original no encontrada (id: %).', p_factura_original;
  end if;

  v_org := v_orig.organizacion_id;

  -- Solo el gerente de la org puede crear rectificativa
  if not public.es_gerente_org(v_org) then
    raise exception 'Solo el gerente de la organización puede crear rectificativas.';
  end if;

  -- La original debe ser una factura (no presupuesto) emitida o cobrada
  if v_orig.tipo_documento <> 'factura' then
    raise exception 'Solo se pueden rectificar facturas, no presupuestos.';
  end if;
  if v_orig.estado not in ('emitida', 'cobrada') then
    raise exception 'Solo se pueden rectificar facturas emitidas o cobradas. Estado actual: %.', v_orig.estado;
  end if;

  -- Crear el borrador rectificativo
  insert into public.facturas (
    organizacion_id, user_id,
    cliente_id, tipo_documento, estado,
    concepto, base_imponible, iva_pct, iva_importe,
    retencion_pct, retencion_importe, total,
    metodo_pago, estado_cobro, notas,
    factura_rectificada_id
  )
  select
    v_org,
    auth.uid(),
    v_orig.cliente_id,
    'factura_rectificativa',
    'borrador',
    'Rectificativa de ' || coalesce(v_orig.numero_factura, ''),
    v_orig.base_imponible,
    v_orig.iva_pct,
    v_orig.iva_importe,
    v_orig.retencion_pct,
    v_orig.retencion_importe,
    v_orig.total,
    v_orig.metodo_pago,
    'pendiente',
    v_orig.notas,
    v_orig.id
  returning id into v_nuevo_id;

  -- Copiar las líneas de la original
  insert into public.factura_lineas (
    factura_id, origen_tipo, origen_id, descripcion,
    cantidad, unidad, precio_unitario, descuento_pct,
    base_linea, iva_pct, iva_linea, total_linea, orden
  )
  select
    v_nuevo_id, origen_tipo, origen_id, descripcion,
    cantidad, unidad, precio_unitario, descuento_pct,
    base_linea, iva_pct, iva_linea, total_linea, orden
  from public.factura_lineas
  where factura_id = p_factura_original
  order by orden;

  return v_nuevo_id;
end;
$$;

revoke execute on function public.crear_rectificativa(uuid) from public, anon;
grant  execute on function public.crear_rectificativa(uuid) to authenticated;

comment on function public.crear_rectificativa(uuid)
  is 'Crea un borrador rectificativo enlazado a una factura emitida/cobrada. '
     'Solo gerente. Copia cliente, líneas e importes de la original.';


-- ===========================================================================
-- 8. TRIGGER: trg_proteger_factura
--    SECURITY INVOKER: current_user refleja el rol real.
--    Bloquea a authenticated/anon:
--      - Cambio de numero_factura
--      - Cambios en documentos no-borrador salvo transiciones permitidas
--      - DELETE de no-borradores
--    Transiciones permitidas: emitida→cobrada (cualquier tipo),
--      emitida→anulada (SOLO presupuestos).
--    emitir_documento y crear_rectificativa corren como postgres (SECURITY DEFINER).
-- ===========================================================================

create or replace function public._trg_proteger_factura()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_es_usuario boolean := current_user in ('anon', 'authenticated');
  v_rect       record;
  v_old_json   jsonb;
  v_new_json   jsonb;
  v_permitidas text[] := array['estado', 'estado_cobro', 'metodo_pago', 'updated_at'];
begin
  -- =========================================================================
  -- INSERT (P1): desde roles de usuario solo se crean BORRADORES limpios.
  -- Las funciones SECURITY DEFINER (emitir_documento, crear_rectificativa,
  -- corren como postgres) no pasan por estas restricciones.
  -- =========================================================================
  if tg_op = 'INSERT' then
    if v_es_usuario then
      if coalesce(new.estado, 'borrador') <> 'borrador' then
        raise exception 'Solo se pueden crear documentos en estado borrador (recibido: %).', new.estado;
      end if;
      if new.numero_factura is not null then
        raise exception 'Un borrador no puede llevar número; se asigna con emitir_documento().';
      end if;
      -- Los snapshots de emisor y cliente solo los rellena emitir_documento()
      if new.emisor_razon_social is not null or new.emisor_nif is not null
         or new.emisor_direccion is not null or new.emisor_cp_ciudad is not null
         or new.emisor_provincia is not null or new.emisor_pais is not null
         or new.emisor_email is not null or new.emisor_telefono is not null
         or new.emisor_logo is not null or new.emisor_logo_mime is not null
         or new.emisor_notas_pie is not null then
        raise exception 'Los datos del emisor (emisor_*) solo se rellenan al emitir.';
      end if;
      if new.cliente_snapshot_nombre is not null or new.cliente_snapshot_nif is not null
         or new.cliente_snapshot_direccion is not null or new.cliente_snapshot_cp is not null
         or new.cliente_snapshot_ciudad is not null or new.cliente_snapshot_provincia is not null
         or new.cliente_snapshot_pais is not null or new.cliente_snapshot_email is not null then
        raise exception 'El snapshot del cliente (cliente_snapshot_*) solo se rellena al emitir.';
      end if;
      -- Si enlaza una rectificativa, validar la factura original
      if new.factura_rectificada_id is not null then
        select * into v_rect from public.facturas where id = new.factura_rectificada_id;
        if not found then
          raise exception 'La factura rectificada no existe.';
        end if;
        if v_rect.organizacion_id <> new.organizacion_id then
          raise exception 'La factura rectificada debe ser de la misma organización.';
        end if;
        if v_rect.tipo_documento <> 'factura' or v_rect.estado not in ('emitida', 'cobrada') then
          raise exception 'Solo se puede rectificar una factura emitida o cobrada.';
        end if;
      end if;
    end if;
    return new;
  end if;

  -- =========================================================================
  -- DELETE: no-borradores no se borran desde roles de usuario
  -- =========================================================================
  if tg_op = 'DELETE' then
    if v_es_usuario and old.estado in ('emitida', 'cobrada', 'anulada') then
      raise exception
        'No se puede borrar un documento en estado %. Solo los borradores se pueden eliminar.', old.estado;
    end if;
    return old;
  end if;

  -- =========================================================================
  -- UPDATE (P2): lista blanca. postgres (SECURITY DEFINER) pasa libre.
  -- =========================================================================
  if tg_op = 'UPDATE' then
    if not v_es_usuario then
      return new;   -- emitir_documento / crear_rectificativa operan sin trabas
    end if;

    -- numero_factura nunca cambia desde la app
    if new.numero_factura is distinct from old.numero_factura then
      raise exception 'numero_factura solo puede asignarse mediante emitir_documento().';
    end if;

    -- ── BORRADOR ───────────────────────────────────────────────────────────
    if old.estado = 'borrador' then
      -- Un borrador solo puede seguir siendo borrador desde la app.
      -- (pasar a emitida/cobrada/anulada SOLO vía emitir_documento, que es postgres)
      if new.estado <> 'borrador' then
        raise exception
          'Un borrador solo cambia de estado mediante emitir_documento(). '
          'Transición % → % no permitida desde la aplicación.', old.estado, new.estado;
      end if;
      -- No se pueden rellenar los snapshots desde la app
      if new.emisor_razon_social is not null or new.emisor_nif is not null
         or new.emisor_direccion is not null or new.emisor_logo is not null
         or new.cliente_snapshot_nombre is not null or new.cliente_snapshot_nif is not null then
        raise exception 'Los datos de snapshot (emisor_*/cliente_snapshot_*) solo se rellenan al emitir.';
      end if;
      -- No se puede convertir a/desde rectificativa rompiendo el enlace
      if new.tipo_documento is distinct from old.tipo_documento then
        if new.tipo_documento = 'factura_rectificativa' or old.tipo_documento = 'factura_rectificativa' then
          raise exception 'No se puede cambiar el tipo a/desde factura_rectificativa en un borrador.';
        end if;
      end if;
      if new.factura_rectificada_id is distinct from old.factura_rectificada_id then
        raise exception 'No se puede cambiar el enlace de rectificativa de un borrador.';
      end if;
      return new;
    end if;

    -- ── NO-BORRADOR (emitida / cobrada / anulada): LISTA BLANCA ─────────────
    -- Solo se permiten cambios en: estado, estado_cobro, metodo_pago, updated_at.
    -- Cualquier otra diferencia entre new y old se rechaza.
    v_old_json := to_jsonb(old) - v_permitidas;
    v_new_json := to_jsonb(new) - v_permitidas;
    if v_old_json is distinct from v_new_json then
      raise exception
        'Un documento en estado % es inmutable: solo se permiten cambios de estado, '
        'estado_cobro y método de pago.', old.estado;
    end if;

    -- Máquina de estados
    if new.estado is distinct from old.estado then
      -- anulada y cobrada son finales
      if old.estado = 'anulada' then
        raise exception 'Un documento anulado no puede cambiar de estado.';
      end if;
      if old.estado = 'cobrada' then
        raise exception 'Un documento cobrado no puede cambiar de estado.';
      end if;
      -- emitida → cobrada (cualquier tipo) o → anulada (SOLO presupuestos)
      if old.estado = 'emitida' then
        if new.estado = 'cobrada' then
          null;
        elsif new.estado = 'anulada' and old.tipo_documento = 'presupuesto' then
          null;
        else
          raise exception
            'Transición no permitida: % → %. '
            'Una factura emitida no se anula: corrígela con una rectificativa. '
            'Un presupuesto emitido solo puede pasar a cobrado o anulado.',
            old.estado, new.estado;
        end if;
      end if;
      -- El cambio a cobrada/anulada solo lo puede hacer el GERENTE de la org
      if new.estado in ('cobrada', 'anulada')
         and not public.es_gerente_org(old.organizacion_id) then
        raise exception 'Solo el gerente de la organización puede marcar como % un documento.', new.estado;
      end if;
    end if;

    return new;
  end if;

  return new;
end;
$$;

revoke execute on function public._trg_proteger_factura() from public, anon;

drop trigger if exists trg_proteger_factura on public.facturas;
create trigger trg_proteger_factura
  before insert or update or delete on public.facturas
  for each row execute function public._trg_proteger_factura();


-- ===========================================================================
-- 9. TRIGGER: trg_proteger_factura_lineas
--    Bloquea INSERT/UPDATE/DELETE de líneas si la factura padre no es borrador
--    (salvo postgres / SECURITY DEFINER).
-- ===========================================================================

create or replace function public._trg_proteger_factura_lineas()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_estado text;
  v_factura_id uuid;
begin
  v_factura_id := case tg_op
    when 'INSERT' then new.factura_id
    when 'UPDATE' then new.factura_id
    when 'DELETE' then old.factura_id
  end;

  select estado into v_estado
  from public.facturas
  where id = v_factura_id;

  if v_estado is null then
    -- La factura padre no existe: dejar que RLS o la FK manejen el error
    return coalesce(new, old);
  end if;

  if v_estado <> 'borrador' and current_user in ('anon', 'authenticated') then
    raise exception
      'No se pueden modificar las líneas de un documento en estado %.', v_estado;
  end if;

  return coalesce(new, old);
end;
$$;

revoke execute on function public._trg_proteger_factura_lineas() from public, anon;

drop trigger if exists trg_proteger_factura_lineas_ins on public.factura_lineas;
create trigger trg_proteger_factura_lineas_ins
  before insert on public.factura_lineas
  for each row execute function public._trg_proteger_factura_lineas();

drop trigger if exists trg_proteger_factura_lineas_upd on public.factura_lineas;
create trigger trg_proteger_factura_lineas_upd
  before update on public.factura_lineas
  for each row execute function public._trg_proteger_factura_lineas();

drop trigger if exists trg_proteger_factura_lineas_del on public.factura_lineas;
create trigger trg_proteger_factura_lineas_del
  before delete on public.factura_lineas
  for each row execute function public._trg_proteger_factura_lineas();


-- ===========================================================================
-- 10. FUNCIÓN: obtener_config_facturacion
--     Devuelve datos fiscales + logo de la org para el PDF y la app.
--     Solo miembros de la org.
-- ===========================================================================

create or replace function public.obtener_config_facturacion(
  p_organizacion_id uuid
)
returns table (
  organizacion_id       uuid,
  nombre_org            text,
  razon_social          text,
  nif_cif               text,
  direccion_fiscal      text,
  codigo_postal_fiscal  text,
  ciudad_fiscal         text,
  provincia_fiscal      text,
  pais_fiscal           text,
  email_fiscal          text,
  telefono_fiscal       text,
  logo                  bytea,
  logo_mime             text,
  tipo_iva_defecto      numeric,
  notas_pie_factura     text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.es_miembro_org(p_organizacion_id) then
    raise exception 'Sin acceso a la organización indicada.';
  end if;

  return query
  select
    oc.organizacion_id,
    o.nombre,
    oc.razon_social,
    oc.nif_cif,
    oc.direccion_fiscal,
    oc.codigo_postal_fiscal,
    oc.ciudad_fiscal,
    oc.provincia_fiscal,
    oc.pais_fiscal,
    oc.email_fiscal,
    oc.telefono_fiscal,
    oc.logo,
    oc.logo_mime,
    oc.tipo_iva_defecto,
    oc.notas_pie_factura
  from public.organizacion_config oc
  join public.organizaciones o on o.id = oc.organizacion_id
  where oc.organizacion_id = p_organizacion_id;
end;
$$;

revoke execute on function public.obtener_config_facturacion(uuid) from public, anon;
grant  execute on function public.obtener_config_facturacion(uuid) to authenticated;

comment on function public.obtener_config_facturacion(uuid)
  is 'Datos fiscales + logo de la org para PDF/app. Solo miembros.';


-- ===========================================================================
-- 11. MIGRACIÓN DE DATOS: Samirarte
--     Solo inserta la fila en organizacion_config y organizacion_contadores
--     si no existe ya. El logo lo subirá Samira desde la app (Gerente →
--     Datos de la organización).
-- ===========================================================================

do $$
declare
  v_org_id uuid;
  v_anio  integer := extract(year from (current_timestamp at time zone 'Europe/Madrid')::date)::integer;
begin
  select id into v_org_id from public.organizaciones where slug = 'samirarte';
  if v_org_id is null then
    raise exception 'Organización "samirarte" no encontrada. Ejecutar primero 022.';
  end if;

  -- Config fiscal (sin logo; Samira lo subirá desde la app)
  insert into public.organizacion_config (organizacion_id, razon_social, nif_cif, direccion_fiscal, tipo_iva_defecto)
  values (v_org_id, 'Samirarte', '', '', 10)
  on conflict (organizacion_id) do nothing;

  -- Contadores para el año en curso (arrancan en 0; la primera emisión pondrá 1)
  insert into public.organizacion_contadores (organizacion_id, tipo_documento, anio, ultimo_numero)
  values
    (v_org_id, 'factura',               v_anio, 0),
    (v_org_id, 'factura_rectificativa',  v_anio, 0),
    (v_org_id, 'presupuesto',            v_anio, 0)
  on conflict do nothing;
end $$;


-- ===========================================================================
-- AUDITORÍA POST-MIGRACIÓN
-- ===========================================================================

-- Tablas creadas:
select tablename from pg_tables
where schemaname = 'public' and tablename in ('organizacion_config', 'organizacion_contadores');

-- Columnas añadidas a facturas:
select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'facturas'
  and column_name like 'emisor_%' or column_name = 'factura_rectificada_id'
order by column_name;

-- Funciones creadas:
select proname from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in ('_reservar_numero_documento', 'emitir_documento',
                  'crear_rectificativa', 'obtener_config_facturacion',
                  '_trg_proteger_factura', '_trg_proteger_factura_lineas')
order by proname;

-- Triggers creados:
select tgname from pg_trigger
where tgrelid in (
  'public.facturas'::regclass, 'public.factura_lineas'::regclass
) and not tgisinternal
order by tgname;

-- Config de Samirarte:
select organizacion_id, razon_social, nif_cif, direccion_fiscal, logo is not null as tiene_logo
from public.organizacion_config;

commit;
