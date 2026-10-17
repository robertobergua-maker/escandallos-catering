-- =============================================================================
-- 024b_rollback.sql
-- Rollback de 024b: elimina el CHECK de familia y restaura
-- crear_ingrediente_privado sin la validación de familia.
-- =============================================================================

begin;

-- Eliminar constraint
alter table public.inventario
  drop constraint if exists inventario_privado_familia_obligatoria;

-- Restaurar función sin validación de familia
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

  select slug into v_slug
  from public.organizaciones where id = p_org_id;

  if v_slug is null then
    raise exception 'Organización no encontrada (id: %).', p_org_id;
  end if;

  v_prefix := 'P-' || v_slug || '-';

  perform pg_advisory_xact_lock(hashtext(p_org_id::text));

  select coalesce(
    max(nullif(substring(codigo from '-(\d+)$'), '')::integer), 0
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

commit;
