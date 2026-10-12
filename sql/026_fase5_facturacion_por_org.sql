-- =============================================================================
-- 026_fase5_facturacion_por_org.sql
-- Fase 5 — Facturación por organización: datos fiscales, series y numeración.
-- =============================================================================
--
-- FORMATOS DE NUMERACIÓN
-- ──────────────────────
-- Facturas:       FAC-YYYY-NNNN   contador anual, reinicia el 1 de enero
-- Rectificativas: REC-YYYY-NNNN   contador anual independiente, mismo reinicio
-- Presupuestos:   PRE-YYYY-MMDD-NNNN   contador diario (formato actual sin cambios)
--
-- Ejemplos:  FAC-2026-0001  FAC-2026-0042  REC-2026-0001  PRE-2026-1011-0005
--
-- La fecha de emisión la fija la función (current_date en Europe/Madrid).
-- El año del número de factura sale de esa fecha, no de un parámetro externo.
--
-- CONTADORES (tabla organizacion_contadores)
-- ──────────────────────────────────────────
-- Tabla en el esquema public con:
--   • RLS ACTIVADO sin ninguna política → devuelve 0 filas a authenticated/anon
--   • REVOKE ALL FROM authenticated, anon (permisos por defecto en Supabase)
-- Solo las funciones _reservar_* (SECURITY DEFINER, corren como postgres)
-- pueden leer y escribir esta tabla.
-- Los contadores viven separados de organizacion_config para que el gerente
-- nunca pueda manipularlos directamente (ni siquiera via RLS de config).
--
-- TRIGGER DE PROTECCIÓN
-- ─────────────────────
-- El trigger en facturas y presupuestos bloquea cualquier cambio de numero_*
-- o estado si current_user IN ('anon', 'authenticated').
-- Las funciones emitir_* son SECURITY DEFINER (current_user = propietario de
-- la función, habitualmente 'postgres') por lo que pasan el filtro.
-- También bloquea modificar o borrar documentos ya emitidos desde esos roles.
--
-- BORRADORES CON NÚMERO (transición)
-- ───────────────────────────────────
-- Los borradores existentes con numero_factura ya asignado se dejan intactos;
-- el trigger solo actúa sobre cambios futuros de numero_*.
-- ⚠️  CAMBIO REQUERIDO EN LA APP (Fase 5):
--   La app debe dejar de llamar a generar_numero_factura() al crear un borrador.
--   Los borradores se crean sin número. El número se asigna llamando a
--   emitir_factura() / emitir_presupuesto() en el momento de emitir.
--
-- DECISIONES DE DISEÑO
-- ────────────────────
-- • Chefs y gerentes pueden emitir documentos (es_miembro_org).
-- • La configuración (datos fiscales, logo) es solo para gerentes y admins.
-- • REVOKE execute a anon/public en todas las funciones.
--
-- Requisitos previos: 022, 023, 024 (Fases 1-3).
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ===========================================================================
-- SECCIÓN 0 — AUDITORÍA PREVIA (solo lectura)
-- Revisar el resultado ANTES de continuar con el resto del script.
-- Si los conteos muestran facturas reales emitidas en 2026, el máximo
-- existente determina el arranque de la serie. Si no hay ninguna, arranca
-- en 0001. Esta consulta no modifica nada.
-- ===========================================================================

-- Facturas y rectificativas de 2026 por tipo y estado:
select
  regexp_replace(numero_factura, '-\d+$', '')      as serie_y_anio,
  estado,
  count(*)                                         as total,
  max(
    nullif(
      regexp_replace(numero_factura, '^.*-(\d+)$', '\1'),
      numero_factura
    )::integer
  )                                                as max_numero
from public.facturas
where numero_factura ~ '^(FAC|REC)-2026-\d+$'
group by serie_y_anio, estado
order by serie_y_anio, estado;

-- Presupuestos de 2026 por estado (son filas de facturas con tipo_documento='presupuesto'):
select
  estado,
  count(*)                                         as total,
  max(
    nullif(
      regexp_replace(numero_factura, '^.*-(\d+)$', '\1'),
      numero_factura
    )::integer
  )                                                as max_numero_diario
from public.facturas
where numero_factura ~ '^PRE-2026-\d{4}-\d+$'
  and tipo_documento = 'presupuesto'
group by estado
order by estado;

-- Borradores que ya tienen número (anomalías previas; se dejan, no se tocan):
select
  tipo_documento,
  numero_factura,
  estado,
  fecha_emision
from public.facturas
where estado = 'borrador' and numero_factura is not null
order by tipo_documento, numero_factura;


-- ===========================================================================
-- 1. TABLA: organizacion_contadores
--    Esquema public, RLS activado SIN políticas + REVOKE ALL a roles externos.
--    Solo accesible por funciones SECURITY DEFINER (current_user = postgres).
-- ===========================================================================

create table if not exists public.organizacion_contadores (
  organizacion_id          uuid    primary key
                             references public.organizaciones(id) on delete cascade,

  -- Facturas: contador anual
  serie_factura            text    not null default 'FAC',
  anio_factura             integer not null default extract(year from current_date)::integer,
  siguiente_factura        integer not null default 1,

  -- Rectificativas: contador anual independiente
  serie_rectificativa      text    not null default 'REC',
  anio_rectificativa       integer not null default extract(year from current_date)::integer,
  siguiente_rectificativa  integer not null default 1,

  -- Presupuestos: contador diario
  serie_presupuesto        text    not null default 'PRE',
  fecha_presupuesto        date    not null default current_date,
  siguiente_presupuesto    integer not null default 1,

  constraint contadores_serie_factura_formato
    check (serie_factura ~ '^[A-Z0-9\-]+$'),
  constraint contadores_serie_rect_formato
    check (serie_rectificativa ~ '^[A-Z0-9\-]+$'),
  constraint contadores_serie_pres_formato
    check (serie_presupuesto ~ '^[A-Z0-9\-]+$'),
  constraint contadores_siguiente_factura_positivo
    check (siguiente_factura >= 1),
  constraint contadores_siguiente_rect_positivo
    check (siguiente_rectificativa >= 1),
  constraint contadores_siguiente_pres_positivo
    check (siguiente_presupuesto >= 1)
);

comment on table public.organizacion_contadores
  is 'Contadores de numeración de documentos por organización. '
     'Sin políticas RLS: inaccesible a authenticated/anon. '
     'Solo escriben las funciones _reservar_* (SECURITY DEFINER).';

-- RLS activado SIN ninguna política: devuelve 0 filas y rechaza escrituras
-- para cualquier rol que no sea el propietario de la función.
alter table public.organizacion_contadores enable row level security;

-- Revocar los permisos por defecto que Supabase otorga en public.
revoke all on public.organizacion_contadores from anon, authenticated;

-- El rol postgres (propietario de las funciones SECURITY DEFINER) mantiene
-- acceso completo por ser superusuario; no necesita GRANT explícito.


-- ===========================================================================
-- 2. TABLA: organizacion_config
--    Solo datos editables por el gerente: datos fiscales, logo, IVA, notas.
--    Sin contadores ni series (movidos a organizacion_contadores).
-- ===========================================================================

create table if not exists public.organizacion_config (
  organizacion_id       uuid         primary key
                          references public.organizaciones(id) on delete cascade,

  -- Datos fiscales para facturas PDF
  razon_social          text,
  nif_cif               text,
  direccion_fiscal      text,
  codigo_postal_fiscal  text,
  ciudad_fiscal         text,
  provincia_fiscal      text,
  pais_fiscal           text         default 'España',
  email_fiscal          text,
  telefono_fiscal       text,
  web                   text,

  -- Logotipo: URL pública en Supabase Storage
  logo_url              text,

  -- Configuración de factura por defecto
  tipo_iva_defecto      numeric(8,2) not null default 10,
  notas_pie_factura     text,
  condiciones_pago      text,

  updated_at            timestamptz  not null default now(),
  created_at            timestamptz  not null default now(),

  constraint org_config_iva_rango
    check (tipo_iva_defecto >= 0 and tipo_iva_defecto <= 100)
);

comment on table  public.organizacion_config
  is 'Datos fiscales, logo y configuración de facturación de cada organización. '
     'Los contadores de numeración viven en organizacion_contadores.';

drop trigger if exists trg_org_config_set_updated_at on public.organizacion_config;
create trigger trg_org_config_set_updated_at
  before update on public.organizacion_config
  for each row execute function public.set_updated_at();


-- ---------------------------------------------------------------------------
-- 2a. RLS: organizacion_config
-- ---------------------------------------------------------------------------

alter table public.organizacion_config enable row level security;

drop policy if exists org_config_select on public.organizacion_config;
create policy org_config_select
  on public.organizacion_config for select to authenticated
  using (public.es_miembro_org(organizacion_id));

drop policy if exists org_config_insert on public.organizacion_config;
create policy org_config_insert
  on public.organizacion_config for insert to authenticated
  with check (
    public.es_gerente_org(organizacion_id)
    or public.es_admin_app(auth.uid())
  );

drop policy if exists org_config_update on public.organizacion_config;
create policy org_config_update
  on public.organizacion_config for update to authenticated
  using (
    public.es_gerente_org(organizacion_id)
    or public.es_admin_app(auth.uid())
  )
  with check (
    public.es_gerente_org(organizacion_id)
    or public.es_admin_app(auth.uid())
  );

drop policy if exists org_config_delete on public.organizacion_config;
create policy org_config_delete
  on public.organizacion_config for delete to authenticated
  using (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- 3. Unicidad de numero_factura / numero_presupuesto por organización
--    Índices parciales: solo aplican donde el número no es NULL (emitidos).
-- ===========================================================================

create unique index if not exists idx_facturas_org_numero_unique
  on public.facturas (organizacion_id, numero_factura)
  where numero_factura is not null;

-- No existe idx_presupuestos_org_numero_unique: los presupuestos usan
-- idx_facturas_org_numero_unique (son filas de la misma tabla).


-- ===========================================================================
-- 4. FUNCIONES INTERNAS DE RESERVA DE NÚMERO
--    SECURITY DEFINER → current_user = postgres (propietario).
--    REVOKE a todos incluido authenticated: nadie las llama directamente.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 4a. _reservar_numero_factura
--     Contador anual. Resetea el 1 de enero (anio_factura < año de p_fecha).
--     p_tipo_doc: 'factura' (serie FAC) o 'factura_rectificativa' (serie REC).
-- ---------------------------------------------------------------------------

create or replace function public._reservar_numero_factura(
  p_organizacion_id uuid,
  p_fecha           date,   -- current_date en Europe/Madrid; lo calcula emitir_factura
  p_tipo_doc        text    -- 'factura' | 'factura_rectificativa'
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anio    integer := extract(year from p_fecha)::integer;
  v_ceros   integer := 4;
  v_numero  integer;
  v_serie   text;
begin
  if p_tipo_doc = 'factura_rectificativa' then
    -- ---- Rectificativas ----
    update public.organizacion_contadores
    set
      anio_rectificativa      = v_anio,
      siguiente_rectificativa =
        case
          when anio_rectificativa = v_anio then siguiente_rectificativa + 1
          else 2   -- año nuevo: devolvemos 1, el siguiente será 2
        end
    where organizacion_id = p_organizacion_id
    returning
      case
        when anio_rectificativa = v_anio then siguiente_rectificativa - 1
        else 1
      end,
      serie_rectificativa
    into v_numero, v_serie;
  else
    -- ---- Facturas ordinarias ----
    update public.organizacion_contadores
    set
      anio_factura      = v_anio,
      siguiente_factura =
        case
          when anio_factura = v_anio then siguiente_factura + 1
          else 2
        end
    where organizacion_id = p_organizacion_id
    returning
      case
        when anio_factura = v_anio then siguiente_factura - 1
        else 1
      end,
      serie_factura
    into v_numero, v_serie;
  end if;

  if v_numero is null then
    raise exception
      'No existe configuración de numeración para la organización (id: %). '
      'Ejecutar la migración de datos de Fase 5.', p_organizacion_id;
  end if;

  -- Formato: SERIE-YYYY-NNNN
  return v_serie || '-' || v_anio::text || '-' || lpad(v_numero::text, v_ceros, '0');
end;
$$;

revoke all     on function public._reservar_numero_factura(uuid, date, text)
  from public, anon, authenticated;

comment on function public._reservar_numero_factura(uuid, date, text)
  is 'Función interna. Reserva número de factura/rectificativa anual de forma atómica. '
     'No callable desde fuera. Formato: SERIE-YYYY-NNNN.';


-- ---------------------------------------------------------------------------
-- 4b. _reservar_numero_presupuesto
--     Contador diario. Resetea cuando cambia el día.
-- ---------------------------------------------------------------------------

create or replace function public._reservar_numero_presupuesto(
  p_organizacion_id uuid,
  p_fecha           date   -- current_date en Europe/Madrid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ceros  integer := 4;
  v_numero integer;
  v_serie  text;
begin
  update public.organizacion_contadores
  set
    fecha_presupuesto    = p_fecha,
    siguiente_presupuesto =
      case
        when fecha_presupuesto = p_fecha then siguiente_presupuesto + 1
        else 2
      end
  where organizacion_id = p_organizacion_id
  returning
    case
      when fecha_presupuesto = p_fecha then siguiente_presupuesto - 1
      else 1
    end,
    serie_presupuesto
  into v_numero, v_serie;

  if v_numero is null then
    raise exception
      'No existe configuración de numeración para la organización (id: %). '
      'Ejecutar la migración de datos de Fase 5.', p_organizacion_id;
  end if;

  -- Formato: SERIE-YYYY-MMDD-NNNN
  return v_serie
    || '-' || to_char(p_fecha, 'YYYY')
    || '-' || to_char(p_fecha, 'MMDD')
    || '-' || lpad(v_numero::text, v_ceros, '0');
end;
$$;

revoke all on function public._reservar_numero_presupuesto(uuid, date)
  from public, anon, authenticated;

comment on function public._reservar_numero_presupuesto(uuid, date)
  is 'Función interna. Reserva número de presupuesto diario de forma atómica. '
     'No callable desde fuera. Formato: SERIE-YYYY-MMDD-NNNN.';


-- ===========================================================================
-- 5. TRIGGERS DE PROTECCIÓN EN FACTURAS Y PRESUPUESTOS
--
-- Mecanismo de autorización:
--   current_user IN ('anon', 'authenticated') → operación bloqueada si afecta
--   a numero_* o a documentos ya emitidos.
--   current_user = 'postgres' (u otro propietario de las funciones SECURITY
--   DEFINER) → operación permitida.
--
-- Por qué funciona:
--   Las llamadas de la app/API llegan como rol 'authenticated' (PostgREST).
--   Las funciones emitir_* son SECURITY DEFINER; dentro de ellas
--   current_user = propietario de la función (postgres en Supabase), que
--   no está en la lista bloqueada.
--
-- Borradores con número preexistente:
--   El trigger no rechaza el estado borrador con número ya asignado
--   (esas filas se dejan intactas). Solo bloquea CAMBIOS futuros de numero_*.
-- ===========================================================================

create or replace function public._trg_proteger_factura()
returns trigger
language plpgsql
-- SECURITY INVOKER (por defecto): current_user refleja el rol real del llamador.
-- Con SECURITY DEFINER sería siempre 'postgres' y las guardas nunca actuarían.
set search_path = public
as $$
begin
  -- ── DELETE ──────────────────────────────────────────────────────────────
  if tg_op = 'DELETE' then
    if current_user in ('anon', 'authenticated')
       and old.estado in ('emitida', 'cobrada', 'anulada') then
      raise exception
        'No se puede borrar una factura en estado %. '
        'Los documentos en estado final no se pueden eliminar.', old.estado;
    end if;
    return old;
  end if;

  -- ── UPDATE ──────────────────────────────────────────────────────────────
  if tg_op = 'UPDATE' then

    -- Bloquear cambio de numero_factura desde roles de usuario
    if new.numero_factura is distinct from old.numero_factura
       and current_user in ('anon', 'authenticated') then
      raise exception
        'numero_factura solo puede asignarse mediante emitir_factura(). '
        'Los borradores no llevan número; llama a emitir_factura() para emitir.';
    end if;

    -- Bloquear cambios de estado inválidos desde roles de usuario
    if current_user in ('anon', 'authenticated') then
      -- anulada es estado final: ninguna transición permitida
      if old.estado = 'anulada' then
        raise exception
          'Una factura anulada no puede cambiar de estado ni modificarse.';
      end if;
      -- emitida/cobrada: solo pueden ir a cobrada o anulada
      if old.estado in ('emitida', 'cobrada')
         and new.estado not in ('emitida', 'cobrada', 'anulada') then
        raise exception
          'Transición de estado no permitida: % → %.', old.estado, new.estado;
      end if;
    end if;

    -- Campos inmutables en documentos en estado final (para cualquier rol)
    if old.estado in ('emitida', 'cobrada', 'anulada') then
      if new.organizacion_id is distinct from old.organizacion_id then
        raise exception 'No se puede cambiar la organización de una factura emitida.';
      end if;
      if new.cliente_id is distinct from old.cliente_id then
        raise exception 'No se puede cambiar el cliente de una factura emitida.';
      end if;
      if new.base_imponible is distinct from old.base_imponible
         or new.iva_importe  is distinct from old.iva_importe
         or new.total         is distinct from old.total then
        raise exception 'No se pueden modificar los importes de una factura emitida.';
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
  before update or delete on public.facturas
  for each row execute function public._trg_proteger_factura();

comment on function public._trg_proteger_factura()
  is 'Protege facturas y presupuestos emitidos (ambos son filas de public.facturas). '
     'SECURITY INVOKER: current_user refleja el rol real. '
     'Bloquea cambios de numero_factura y estado final '
     'cuando current_user IN (''anon'', ''authenticated''). '
     'Las funciones emitir_* corren como postgres (SECURITY DEFINER) y pasan el filtro.';

-- No existe _trg_proteger_presupuesto ni un trigger separado sobre presupuestos:
-- los presupuestos son filas de public.facturas (tipo_documento = 'presupuesto')
-- y quedan cubiertos por trg_proteger_factura. La tabla public.presupuestos
-- pertenece a la migración 019, no aplicada.


-- ===========================================================================
-- 6. FUNCIÓN: emitir_factura
--    • SELECT FOR UPDATE antes de cualquier comprobación.
--    • Fecha fijada por la función: current_timestamp AT TIME ZONE 'Europe/Madrid'.
--    • El año del número sale de esa fecha; no hay parámetro de fecha.
--    • Accesible para chefs y gerentes (es_miembro_org).
-- ===========================================================================

create or replace function public.emitir_factura(p_factura_id uuid)
returns text        -- número de factura asignado
language plpgsql
security definer
set search_path = public
as $$
declare
  v_factura record;
  v_numero  text;
  v_fecha   date;
begin
  -- Fijar la fecha de emisión en la zona horaria del negocio
  v_fecha := (current_timestamp at time zone 'Europe/Madrid')::date;

  -- Bloquear la fila para evitar doble emisión concurrente
  select f.* into v_factura
  from public.facturas f
  where f.id = p_factura_id
    and public.es_miembro_org(f.organizacion_id)
  for update;

  if not found then
    raise exception 'Factura no encontrada o sin acceso (id: %).', p_factura_id;
  end if;

  if v_factura.estado <> 'borrador' then
    raise exception
      'Solo se pueden emitir facturas en estado borrador. Estado actual: %.',
      v_factura.estado;
  end if;

  -- Los borradores con número preexistente (asignados por la app anterior)
  -- no se bloquean aquí para no romper la transición; la app nueva no generará
  -- número al crear el borrador. Ver nota en cabecera del fichero.
  if v_factura.numero_factura is not null then
    raise exception
      'Esta factura ya tiene número asignado: %. '
      'Migrar el borrador eliminando el número antes de emitir, o emitirla '
      'directamente actualizando estado a "emitida" desde la app anterior.',
      v_factura.numero_factura;
  end if;

  -- Reservar número de forma atómica
  v_numero := public._reservar_numero_factura(
    v_factura.organizacion_id,
    v_fecha,
    v_factura.tipo_documento   -- 'factura' | 'factura_rectificativa'
  );

  -- UPDATE: el trigger permite el cambio porque current_user = postgres
  update public.facturas
  set
    numero_factura = v_numero,
    estado         = 'emitida',
    fecha_emision  = v_fecha,
    updated_at     = now()
  where id = p_factura_id;

  return v_numero;
end;
$$;

revoke execute on function public.emitir_factura(uuid) from public, anon;
grant  execute on function public.emitir_factura(uuid) to authenticated;

comment on function public.emitir_factura(uuid)
  is 'Emite una factura borrador: SELECT FOR UPDATE, fecha en Europe/Madrid, '
     'número correlativo anual atómico (FAC-YYYY-NNNN o REC-YYYY-NNNN). '
     'Accesible para chefs y gerentes.';


-- ===========================================================================
-- 7. FUNCIÓN: emitir_presupuesto
--    Los presupuestos son filas de public.facturas con
--    tipo_documento = 'presupuesto'. Esta función opera sobre esa tabla.
--    El número se guarda en numero_factura (misma columna que facturas).
--    El estado pasa de 'borrador' a 'emitida' (mismo dominio de estados).
--    Contador diario PRE-YYYY-MMDD-NNNN.
-- ===========================================================================

create or replace function public.emitir_presupuesto(p_factura_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doc    record;
  v_numero text;
  v_fecha  date;
begin
  v_fecha := (current_timestamp at time zone 'Europe/Madrid')::date;

  -- Bloquear la fila; verificar que es un presupuesto de la org del llamador
  select f.* into v_doc
  from public.facturas f
  where f.id = p_factura_id
    and f.tipo_documento = 'presupuesto'
    and public.es_miembro_org(f.organizacion_id)
  for update;

  if not found then
    raise exception
      'Presupuesto no encontrado, no es de tipo presupuesto, o sin acceso (id: %).',
      p_factura_id;
  end if;

  if v_doc.estado <> 'borrador' then
    raise exception
      'Solo se pueden emitir presupuestos en estado borrador. Estado actual: %.',
      v_doc.estado;
  end if;

  if v_doc.numero_factura is not null then
    raise exception
      'Este presupuesto ya tiene número asignado: %.', v_doc.numero_factura;
  end if;

  v_numero := public._reservar_numero_presupuesto(
    v_doc.organizacion_id,
    v_fecha
  );

  -- El trigger permite este UPDATE porque current_user = postgres
  update public.facturas
  set
    numero_factura = v_numero,
    estado         = 'emitida',
    fecha_emision  = v_fecha,
    updated_at     = now()
  where id = p_factura_id;

  return v_numero;
end;
$$;

revoke execute on function public.emitir_presupuesto(uuid) from public, anon;
grant  execute on function public.emitir_presupuesto(uuid) to authenticated;

comment on function public.emitir_presupuesto(uuid)
  is 'Emite un presupuesto (fila de facturas con tipo_documento=''presupuesto''): '
     'fecha en Europe/Madrid, número correlativo diario (PRE-YYYY-MMDD-NNNN). '
     'Accesible para chefs y gerentes.';


-- ===========================================================================
-- 8. FUNCIÓN RPC: obtener_config_facturacion
--    Cualquier miembro puede leer los datos del PDF.
--    Los contadores (en organizacion_contadores) no se exponen nunca.
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
  web                   text,
  logo_url              text,
  tipo_iva_defecto      numeric,
  notas_pie_factura     text,
  condiciones_pago      text
  -- organizacion_contadores no se incluye aquí en ninguna forma
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (public.es_miembro_org(p_organizacion_id) or public.es_admin_app(auth.uid())) then
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
    oc.web,
    oc.logo_url,
    oc.tipo_iva_defecto,
    oc.notas_pie_factura,
    oc.condiciones_pago
  from public.organizacion_config oc
  join public.organizaciones o on o.id = oc.organizacion_id
  where oc.organizacion_id = p_organizacion_id;
end;
$$;

revoke execute on function public.obtener_config_facturacion(uuid) from public, anon;
grant  execute on function public.obtener_config_facturacion(uuid) to authenticated;

comment on function public.obtener_config_facturacion(uuid)
  is 'Datos fiscales de la organización para generar PDFs. '
     'No expone contadores de numeración. Accesible para cualquier miembro.';


-- ===========================================================================
-- 9. MIGRACIÓN DE DATOS: insertar Samirarte en ambas tablas
-- ===========================================================================

do $$
declare
  v_org_id              uuid;
  v_hoy                 date    := (current_timestamp at time zone 'Europe/Madrid')::date;
  v_anio                integer := extract(year from v_hoy)::integer;
  v_anio_text           text    := v_anio::text;

  -- Máximos de la serie anual FAC del año en curso
  v_max_fac             integer;
  -- Máximos de la serie anual REC del año en curso
  v_max_rec             integer;
  -- Máximos de la serie diaria PRE del día de hoy
  v_max_pre_hoy         integer;
  v_fecha_pre_hoy       text    := to_char(v_hoy, 'YYYY-MMDD');
begin
  select id into v_org_id from public.organizaciones where slug = 'samirarte';
  if v_org_id is null then
    raise exception 'Organización "samirarte" no encontrada. Ejecutar primero 022.';
  end if;

  -- ---- Máximo FAC del año en curso ----
  -- Patrón: FAC-YYYY-NNNN  (cuatro o más dígitos al final)
  select coalesce(
    max(
      nullif(
        regexp_replace(numero_factura, '^FAC-' || v_anio_text || '-0*(\d+)$', '\1'),
        numero_factura   -- si el replace no cambia nada, descartamos
      )::integer
    ), 0
  ) into v_max_fac
  from public.facturas
  where organizacion_id = v_org_id
    and numero_factura  ~ ('^FAC-' || v_anio_text || '-\d{4,}$');

  -- ---- Máximo REC del año en curso ----
  select coalesce(
    max(
      nullif(
        regexp_replace(numero_factura, '^REC-' || v_anio_text || '-0*(\d+)$', '\1'),
        numero_factura
      )::integer
    ), 0
  ) into v_max_rec
  from public.facturas
  where organizacion_id = v_org_id
    and numero_factura  ~ ('^REC-' || v_anio_text || '-\d{4,}$');

  -- ---- Máximo PRE del día de hoy (presupuestos = facturas con tipo_documento='presupuesto') ----
  select coalesce(
    max(
      nullif(
        regexp_replace(
          numero_factura,
          '^PRE-' || v_fecha_pre_hoy || '-0*(\d+)$', '\1'
        ),
        numero_factura
      )::integer
    ), 0
  ) into v_max_pre_hoy
  from public.facturas
  where organizacion_id  = v_org_id
    and tipo_documento   = 'presupuesto'
    and numero_factura   ~ ('^PRE-' || v_fecha_pre_hoy || '-\d{4,}$');

  raise notice '--- Arranque de series para Samirarte (año %, hoy %) ---', v_anio, v_hoy;
  raise notice '  FAC máximo existente: %, siguiente: %', v_max_fac, v_max_fac + 1;
  raise notice '  REC máximo existente: %, siguiente: %', v_max_rec, v_max_rec + 1;
  raise notice '  PRE hoy máximo: %, siguiente: %',       v_max_pre_hoy, v_max_pre_hoy + 1;

  -- ---- organizacion_contadores ----
  insert into public.organizacion_contadores (
    organizacion_id,
    serie_factura,        anio_factura,        siguiente_factura,
    serie_rectificativa,  anio_rectificativa,  siguiente_rectificativa,
    serie_presupuesto,    fecha_presupuesto,   siguiente_presupuesto
  ) values (
    v_org_id,
    'FAC', v_anio, v_max_fac   + 1,
    'REC', v_anio, v_max_rec   + 1,
    'PRE', v_hoy,  v_max_pre_hoy + 1
  )
  on conflict (organizacion_id) do nothing;

  -- ---- organizacion_config ----
  insert into public.organizacion_config (
    organizacion_id,
    razon_social,
    tipo_iva_defecto
  ) values (
    v_org_id,
    'Samirarte',
    10
  )
  on conflict (organizacion_id) do nothing;

end;
$$;


-- ===========================================================================
-- AUDITORÍA POST-MIGRACIÓN
-- ===========================================================================

-- Verificar contadores insertados:
-- (Esta consulta solo funciona desde el SQL Editor del dashboard de Supabase,
--  conectado como postgres. Desde la API/authenticated devuelve 0 filas.)
select
  o.nombre,
  c.serie_factura,        c.anio_factura,        c.siguiente_factura,
  c.serie_rectificativa,  c.anio_rectificativa,  c.siguiente_rectificativa,
  c.serie_presupuesto,    c.fecha_presupuesto,   c.siguiente_presupuesto
from public.organizacion_contadores c
join public.organizaciones o on o.id = c.organizacion_id;

-- Verificar config insertada:
select organizacion_id, razon_social, tipo_iva_defecto
from public.organizacion_config;

-- Confirmar que authenticated no puede leer organizacion_contadores:
-- (Ejecutar como rol authenticated; debe devolver 0 filas y sin error RLS)
-- set local role authenticated;
-- set local "request.jwt.claims" to '{"sub":"<uid>","role":"authenticated"}';
-- select * from public.organizacion_contadores;  -- 0 filas


-- ===========================================================================
-- ROLLBACK
-- ===========================================================================
/*
rollback;

drop trigger  if exists trg_proteger_factura              on public.facturas;
drop function if exists public._trg_proteger_factura();
drop function if exists public.obtener_config_facturacion(uuid);
drop function if exists public.emitir_presupuesto(uuid);
drop function if exists public.emitir_factura(uuid);
drop function if exists public._reservar_numero_presupuesto(uuid, date);
drop function if exists public._reservar_numero_factura(uuid, date, text);
drop index    if exists public.idx_facturas_org_numero_unique;
drop table    if exists public.organizacion_config;
drop table    if exists public.organizacion_contadores;
*/

commit;
