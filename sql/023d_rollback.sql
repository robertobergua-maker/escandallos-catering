-- =============================================================================
-- 023d_rollback.sql
-- Rollback de 023d: restaura el estado exacto posterior a 024/024b,
-- es decir, el admin de plataforma recupera acceso total a datos de cualquier
-- organización.
-- =============================================================================
-- Qué restaura:
--   1. Las 7 políticas *_admin_all en tablas operativas (023c).
--   2. inventario_org_admin_all.
--   3. inventario_select_authenticated con rama es_admin_app.
--   4. inventario_admin_all sin limitación a filas globales.
--   5. ingrediente_alergenos_select_authenticated con rama es_admin_app.
--   6. ingrediente_alergenos_admin_all sin limitación a globales.
--   7. crear_ingrediente_privado con excepción para admin.
--   8. marcar_alergenos_revisados con excepción para admin.
--   9. obtener_inventario_para_org con rama es_admin_app en el check.
-- =============================================================================

begin;

-- ===========================================================================
-- 1. Tablas operativas (023c) — restaurar 7 *_admin_all
-- ===========================================================================

create policy recetas_admin_all
  on public.recetas for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));

create policy receta_ingredientes_admin_all
  on public.receta_ingredientes for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));

create policy menus_admin_all
  on public.menus for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));

create policy menu_recetas_admin_all
  on public.menu_recetas for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));

create policy clientes_admin_all
  on public.clientes for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));

create policy facturas_admin_all
  on public.facturas for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));

create policy factura_lineas_admin_all
  on public.factura_lineas for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- 2. inventario_org — restaurar admin_all
-- ===========================================================================

create policy inventario_org_admin_all
  on public.inventario_org for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- 3. inventario — restaurar select con rama admin y admin_all sin restricción
-- ===========================================================================

drop policy if exists inventario_select_authenticated on public.inventario;
drop policy if exists inventario_admin_all            on public.inventario;

create policy inventario_select_authenticated
  on public.inventario for select to authenticated
  using (
    organizacion_id is null
    or public.es_miembro_org(organizacion_id)
    or public.es_admin_app(auth.uid())
  );

create policy inventario_admin_all
  on public.inventario for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- 4. ingrediente_alergenos — restaurar select con rama admin y admin_all total
-- ===========================================================================

drop policy if exists ingrediente_alergenos_select_authenticated on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_admin_all            on public.ingrediente_alergenos;

create policy ingrediente_alergenos_select_authenticated
  on public.ingrediente_alergenos for select to authenticated
  using (
    exists (
      select 1 from public.inventario i
      where i.codigo = ingrediente_alergenos.codigo_ingrediente
        and (
          i.organizacion_id is null
          or public.es_miembro_org(i.organizacion_id)
          or public.es_admin_app(auth.uid())
        )
    )
  );

create policy ingrediente_alergenos_admin_all
  on public.ingrediente_alergenos for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- 5a. crear_ingrediente_privado — restaurar con excepción para admin
-- ===========================================================================

create or replace function public.crear_ingrediente_privado(
  p_org_id        uuid,
  p_descripcion   text,
  p_familia       text  default null,
  p_unidad_medida text  default 'kg'
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

comment on function public.crear_ingrediente_privado(uuid, text, text, text)
  is 'Crea ingrediente privado con código P-<slug>-NNNN. '
     'Lock anti-race. Solo gerentes. alergenos_revisados = false hasta revisión.';


-- ===========================================================================
-- 5b. marcar_alergenos_revisados — restaurar con excepción para admin
-- ===========================================================================

create or replace function public.marcar_alergenos_revisados(
  p_codigo        text,
  p_sin_alergenos boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ingrediente record;
  v_n_alergenos integer;
begin
  select * into v_ingrediente
  from public.inventario
  where codigo = p_codigo;

  if v_ingrediente is null then
    raise exception 'Ingrediente no encontrado: %.', p_codigo;
  end if;

  if v_ingrediente.organizacion_id is null then
    raise exception 'Los alérgenos del catálogo global los gestiona el admin de plataforma.';
  end if;

  if not (public.es_gerente_org(v_ingrediente.organizacion_id) or public.es_admin_app(auth.uid())) then
    raise exception 'Solo el gerente de la organización puede marcar alérgenos como revisados.';
  end if;

  select count(*) into v_n_alergenos
  from public.ingrediente_alergenos
  where codigo_ingrediente = p_codigo;

  if v_n_alergenos = 0 and not p_sin_alergenos then
    raise exception
      'Declara al menos un alérgeno o confirma que no contiene ninguno de los '
      '14 alérgenos (p_sin_alergenos = true).';
  end if;

  set local escandallos.revisando_alergenos = '1';

  update public.inventario
    set alergenos_revisados     = true,
        alergenos_revisados_por = auth.uid(),
        alergenos_revisados_at  = now()
    where codigo = p_codigo;
end;
$$;

revoke execute on function public.marcar_alergenos_revisados(text, boolean) from public, anon;
grant  execute on function public.marcar_alergenos_revisados(text, boolean) to authenticated;

comment on function public.marcar_alergenos_revisados(text, boolean)
  is '⚠️ Único punto de escritura de alergenos_revisados. '
     'Exige ≥1 alérgeno O p_sin_alergenos=true. Solo gerente de la org.';


-- ===========================================================================
-- 6. obtener_inventario_para_org — restaurar con rama es_admin_app
-- ===========================================================================

create or replace function public.obtener_inventario_para_org(
  p_organizacion_id uuid
)
returns table (
  codigo                  text,
  familia                 text,
  descripcion             text,
  unidad_medida           text,
  es_privado              boolean,
  alergenos_revisados     boolean,
  precio_unidad           numeric,
  precio_es_propio        boolean,
  merma                   numeric,
  merma_es_propia         boolean,
  proveedor_precio        text,
  formato_compra          text,
  cantidad_formato_compra numeric,
  unidad_formato_compra   text,
  precio_formato_compra   numeric,
  url_precio              text,
  observaciones_precio    text
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
    i.codigo, i.familia, i.descripcion, i.unidad_medida,
    (i.organizacion_id is not null),
    i.alergenos_revisados,
    coalesce(io.precio_unidad,            i.precio_unidad),
    (io.precio_unidad is not null),
    coalesce(io.merma,                    i.merma),
    (io.merma is not null),
    coalesce(io.proveedor_precio,         i.proveedor_precio),
    coalesce(io.formato_compra,           i.formato_compra),
    coalesce(io.cantidad_formato_compra,  i.cantidad_formato_compra),
    coalesce(io.unidad_formato_compra,    i.unidad_formato_compra),
    coalesce(io.precio_formato_compra,    i.precio_formato_compra),
    coalesce(io.url_precio,               i.url_precio),
    coalesce(io.observaciones_precio,     i.observaciones_precio)
  from public.inventario i
  left join public.inventario_org io
         on io.codigo_ingrediente = i.codigo
        and io.organizacion_id    = p_organizacion_id
  where i.organizacion_id is null or i.organizacion_id = p_organizacion_id
  order by i.familia nulls last, i.descripcion;
end;
$$;

revoke execute on function public.obtener_inventario_para_org(uuid) from public, anon;
grant  execute on function public.obtener_inventario_para_org(uuid) to authenticated;

comment on function public.obtener_inventario_para_org(uuid)
  is 'Catálogo con precios efectivos y alergenos_revisados. '
     'Verifica membresía. Solo accesible para miembros (y admin, pre-023d).';


-- ===========================================================================
-- VERIFICACIÓN POST-ROLLBACK
-- ===========================================================================

select tablename, policyname
from pg_policies
where schemaname = 'public'
  and policyname like '%_admin_all'
  and tablename in (
    'recetas','receta_ingredientes','menus','menu_recetas',
    'clientes','facturas','factura_lineas',
    'inventario','inventario_org','ingrediente_alergenos'
  )
order by tablename;
-- Debe mostrar 10 filas (7 operativas + inventario_org + inventario + ingrediente_alergenos).

commit;
