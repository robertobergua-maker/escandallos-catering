-- =============================================================================
-- 024b_crear_ingrediente_privado_familia_obligatoria.sql
-- Hace obligatoria la columna familia en ingredientes privados y actualiza
-- la función crear_ingrediente_privado para exigirla.
-- =============================================================================
-- Qué hace:
--   1. Añade un CHECK en inventario que obliga a que los ingredientes privados
--      (organizacion_id IS NOT NULL) tengan familia NOT NULL.
--      No toca los ingredientes del catálogo global (pueden tener familia NULL).
--   2. Actualiza crear_ingrediente_privado(p_org, p_descripcion, p_familia, ...)
--      para lanzar una excepción clara si p_familia es NULL o vacío.
--
-- Requisitos previos: 024 aplicada.
-- Reversible: ejecutar 024b_rollback.sql.
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. CHECK: familia NOT NULL para ingredientes privados
--    Usamos NOT VALID para no bloquear la tabla al validar filas existentes;
--    validar luego con ALTER TABLE ... VALIDATE CONSTRAINT en horario de baja
--    carga si es necesario.
-- ---------------------------------------------------------------------------

alter table public.inventario
  drop constraint if exists inventario_privado_familia_obligatoria;

alter table public.inventario
  add constraint inventario_privado_familia_obligatoria
  check (
    organizacion_id is null   -- catálogo global: familia puede ser NULL
    or (familia is not null and trim(familia) <> '')
  )
  not valid;

comment on constraint inventario_privado_familia_obligatoria on public.inventario
  is 'Los ingredientes privados (organizacion_id NOT NULL) deben tener familia no vacía.';


-- ---------------------------------------------------------------------------
-- 2. Actualizar crear_ingrediente_privado: p_familia obligatorio
-- ---------------------------------------------------------------------------

create or replace function public.crear_ingrediente_privado(
  p_org_id        uuid,
  p_descripcion   text,
  p_familia       text    default null,
  p_unidad_medida text    default 'kg'
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slug   text;
  v_seq    integer;
  v_codigo text;
  v_prefix text;
begin
  if not (public.es_gerente_org(p_org_id) or public.es_admin_app(auth.uid())) then
    raise exception 'Solo los gerentes pueden crear ingredientes privados.';
  end if;

  if trim(coalesce(p_descripcion, '')) = '' then
    raise exception 'La descripción no puede estar vacía.';
  end if;

  -- Familia obligatoria para ingredientes privados
  if trim(coalesce(p_familia, '')) = '' then
    raise exception
      'La familia es obligatoria para ingredientes privados. '
      'Selecciona una familia antes de guardar.';
  end if;

  select slug into v_slug
  from public.organizaciones where id = p_org_id;

  if v_slug is null then
    raise exception 'Organización no encontrada (id: %).', p_org_id;
  end if;

  v_prefix := 'P-' || v_slug || '-';

  perform pg_advisory_xact_lock(hashtext(p_org_id::text));

  select coalesce(
    max(
      nullif(substring(codigo from '-(\d+)$'), '')::integer
    ), 0
  ) + 1
  into v_seq
  from public.inventario
  where organizacion_id = p_org_id
    and codigo like (v_prefix || '%');

  v_codigo := v_prefix || lpad(v_seq::text, 4, '0');

  insert into public.inventario (
    codigo, familia, descripcion, unidad_medida,
    organizacion_id, alergenos_revisados
  ) values (
    v_codigo, p_familia, p_descripcion, p_unidad_medida,
    p_org_id, false
  );

  return v_codigo;
end;
$$;

revoke execute on function public.crear_ingrediente_privado(uuid, text, text, text)
  from public, anon;
grant  execute on function public.crear_ingrediente_privado(uuid, text, text, text)
  to authenticated;

comment on function public.crear_ingrediente_privado(uuid, text, text, text)
  is 'Crea ingrediente privado. p_familia obligatorio. '
     'Código P-<slug>-NNNN. Lock anti-race. Solo gerentes.';


-- ---------------------------------------------------------------------------
-- AUDITORÍA
-- ---------------------------------------------------------------------------

-- Ingredientes privados sin familia (deben ser 0 si todos ya la tienen):
select count(*) as privados_sin_familia
from public.inventario
where organizacion_id is not null
  and (familia is null or trim(familia) = '');
-- Si > 0, actualizarlos manualmente antes de VALIDATE CONSTRAINT.

-- Para validar el constraint cuando todos tengan familia:
-- alter table public.inventario
--   validate constraint inventario_privado_familia_obligatoria;

commit;
