-- =============================================================================
-- 026_emitir_documento.sql
-- Versión de public.emitir_documento(uuid) YA APLICADA en la base de datos.
--
-- Respecto a la versión original de 026_facturacion_por_org.sql añade:
--   · Ajuste de fecha_vencimiento a la fecha de emisión si era anterior
--     (no se rechaza la emisión por ese descuadre menor).
--   · Validación de que el cliente, si lo hay, pertenece a la misma
--     organización que el documento.
--
-- Es un CREATE OR REPLACE idempotente: se puede volver a aplicar sin efectos
-- secundarios. Requiere que 026_facturacion_por_org.sql ya esté aplicado
-- (tablas, columnas snapshot y _reservar_numero_documento).
--
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

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

  -- Emitir: número, fecha, estado, snapshot del emisor y snapshot del cliente.
  -- Si la fecha de vencimiento es anterior a la de emisión, se AJUSTA a la fecha
  -- de emisión (no se rechaza) para no bloquear la emisión por un descuadre menor.
  update public.facturas
  set
    numero_factura            = v_numero,
    estado                    = 'emitida',
    fecha_emision             = v_fecha,
    fecha_vencimiento         = case
                                  when fecha_vencimiento is not null
                                       and fecha_vencimiento < v_fecha
                                  then v_fecha
                                  else fecha_vencimiento
                                end,
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
     'exige cliente de la org para factura/rectificativa, >=1 línea y totales '
     'cuadrados; guarda snapshot de emisor y cliente; ajusta fecha_vencimiento '
     'a la fecha de emisión si era anterior. Devuelve el número.';

commit;
