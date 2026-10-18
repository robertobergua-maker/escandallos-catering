-- =============================================================================
-- 023d_admin_solo_por_invitacion.sql
-- Retira el acceso especial del admin de plataforma a datos de organizaciones
-- de las que no es miembro. Cubre las tablas operativas (023c) y todo lo
-- añadido por la Fase 3 (024/024b).
-- =============================================================================
-- ⚠️  CUÁNDO EJECUTAR:
--   OBLIGATORIO antes de dar de alta la primera organización EXTERNA a Samirarte.
--   Si se ejecuta después, el admin ya habrá podido ver datos ajenos.
--
--   Orden recomendado:
--     1. Ejecutar este script.
--     2. Verificar que es_admin_app() sigue funcionando para el panel de
--        administración (organizaciones, usuarios_app, invitaciones).
--        Esas tablas tienen sus propias políticas independientes (punto 6).
--     3. El admin que necesite gestionar datos de una organización debe ser
--        invitado a ella como 'gerente' con crear_invitacion().
--
-- Qué hace (en orden):
--   1. Tablas operativas (023c): DROP de las 7 políticas *_admin_all.
--   2. inventario_org: DROP de inventario_org_admin_all.
--   3. inventario: narrowing de inventario_select_authenticated e
--      inventario_admin_all (limitado a filas globales).
--   4. ingrediente_alergenos: quitar rama admin del SELECT; admin_all limitado
--      a alérgenos de ingredientes globales.
--   5. Funciones crear_ingrediente_privado y marcar_alergenos_revisados:
--      reemplazar para que solo acepten gerentes (quitar la excepción admin).
--   6. obtener_inventario_para_org: quitar "or es_admin_app()" del check.
--
-- Qué NO cambia (panel de administración sigue funcionando):
--   • Tablas: organizaciones, organizacion_miembros, usuarios_app,
--     invitaciones, alergenos.
--   • Políticas de esas tablas (admin puede crear orgs, ver miembros, invitar).
--   • Triggers de protección (inventario_protect_revisado, etc.).
--   • Funciones es_admin_app(), es_miembro_org(), es_gerente_org().
--   • crear_invitacion(): el admin puede invitar al primer gerente de una org.
--
-- Reversible: ejecutar 023d_rollback.sql.
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ===========================================================================
-- 1. TABLAS OPERATIVAS (023c) — DROP de las 7 políticas *_admin_all
-- ===========================================================================

drop policy if exists recetas_admin_all              on public.recetas;
drop policy if exists receta_ingredientes_admin_all  on public.receta_ingredientes;
drop policy if exists menus_admin_all                on public.menus;
drop policy if exists menu_recetas_admin_all         on public.menu_recetas;
drop policy if exists clientes_admin_all             on public.clientes;
drop policy if exists facturas_admin_all             on public.facturas;
drop policy if exists factura_lineas_admin_all       on public.factura_lineas;


-- ===========================================================================
-- 2. inventario_org — DROP de inventario_org_admin_all
-- ===========================================================================

drop policy if exists inventario_org_admin_all on public.inventario_org;


-- ===========================================================================
-- 3. inventario — narrowing de select y admin_all
--
--    Estado actual (post-024):
--      inventario_select_authenticated: global OR es_miembro_org OR es_admin_app
--      inventario_admin_all:            es_admin_app (acceso total, incluye privados)
--
--    Estado nuevo:
--      inventario_select_authenticated: global OR es_miembro_org
--      inventario_admin_all:            es_admin_app AND organizacion_id IS NULL
--                                       (solo catálogo global)
-- ===========================================================================

drop policy if exists inventario_select_authenticated on public.inventario;
drop policy if exists inventario_admin_all            on public.inventario;

-- SELECT: catálogo global para todos; privados solo para miembros.
create policy inventario_select_authenticated
  on public.inventario for select to authenticated
  using (
    organizacion_id is null
    or public.es_miembro_org(organizacion_id)
  );

-- Admin: solo catálogo global (ingredientes con organizacion_id IS NULL).
create policy inventario_admin_all
  on public.inventario for all to authenticated
  using    (organizacion_id is null and public.es_admin_app(auth.uid()))
  with check (organizacion_id is null and public.es_admin_app(auth.uid()));


-- ===========================================================================
-- 4. ingrediente_alergenos — narrowing de select y admin_all
--
--    Estado actual (post-024):
--      ingrediente_alergenos_select_authenticated:
--          EXISTS(inventario WHERE ... (global OR miembro OR admin))
--      ingrediente_alergenos_admin_all: es_admin_app (acceso total)
--
--    Estado nuevo:
--      select: solo global O miembro (sin rama admin)
--      admin_all: limitado a alérgenos de ingredientes globales
-- ===========================================================================

drop policy if exists ingrediente_alergenos_select_authenticated on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_admin_all            on public.ingrediente_alergenos;

-- SELECT: alérgenos globales para todos autenticados; privados solo miembros.
create policy ingrediente_alergenos_select_authenticated
  on public.ingrediente_alergenos for select to authenticated
  using (
    exists (
      select 1 from public.inventario i
      where i.codigo = ingrediente_alergenos.codigo_ingrediente
        and (
          i.organizacion_id is null
          or public.es_miembro_org(i.organizacion_id)
        )
    )
  );

-- Admin: solo alérgenos de ingredientes del catálogo global.
create policy ingrediente_alergenos_admin_all
  on public.ingrediente_alergenos for all to authenticated
  using (
    public.es_admin_app(auth.uid())
    and exists (
      select 1 from public.inventario i
      where i.codigo = ingrediente_alergenos.codigo_ingrediente
        and i.organizacion_id is null
    )
  )
  with check (
    public.es_admin_app(auth.uid())
    and exists (
      select 1 from public.inventario i
      where i.codigo = ingrediente_alergenos.codigo_ingrediente
        and i.organizacion_id is null
    )
  );


-- ===========================================================================
-- 5a. crear_ingrediente_privado — quitar excepción para admin
--     Solo gerentes de la org pueden crear ingredientes privados.
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
  -- Solo gerentes (sin excepción para admin de plataforma)
  if not public.es_gerente_org(p_org_id) then
    raise exception 'Solo los gerentes de la organización pueden crear ingredientes privados.';
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
     'Lock anti-race. Solo gerentes (sin excepción admin tras 023d). '
     'alergenos_revisados = false hasta revisión.';


-- ===========================================================================
-- 5b. marcar_alergenos_revisados — quitar excepción para admin
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

  -- Solo gerente de la org (sin excepción para admin de plataforma)
  if not public.es_gerente_org(v_ingrediente.organizacion_id) then
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
     'Exige ≥1 alérgeno O p_sin_alergenos=true. '
     'Solo gerente de la org (sin excepción admin tras 023d).';


-- ===========================================================================
-- 6. obtener_inventario_para_org — quitar rama es_admin_app del check
--    Solo miembros de la org pueden llamar a esta función.
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
  -- Solo miembros (sin excepción para admin de plataforma)
  if not public.es_miembro_org(p_organizacion_id) then
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
     'Solo miembros de la org (sin excepción admin tras 023d).';


-- ===========================================================================
-- VERIFICACIÓN
-- ===========================================================================

-- 1. Ninguna política *_admin_all irrestricta en tablas operativas:
select tablename, policyname, qual
from pg_policies
where schemaname = 'public'
  and tablename in (
    'recetas','receta_ingredientes','menus','menu_recetas',
    'clientes','facturas','factura_lineas',
    'inventario_org'
  )
  and policyname like '%_admin_all';
-- Debe devolver 0 filas.

-- 2. inventario_admin_all ahora tiene condición sobre organizacion_id:
select policyname, qual
from pg_policies
where schemaname = 'public' and tablename = 'inventario'
  and policyname = 'inventario_admin_all';
-- qual debe contener "organizacion_id is null".

-- 3. ingrediente_alergenos_admin_all tiene EXISTS sobre globales:
select policyname, qual
from pg_policies
where schemaname = 'public' and tablename = 'ingrediente_alergenos'
  and policyname = 'ingrediente_alergenos_admin_all';
-- qual debe contener "organizacion_id is null".


-- ===========================================================================
-- PRUEBA DE AISLAMIENTO (se deshace sola al terminar la transacción del test)
-- Ejecutar en el SQL Editor de Supabase, en una transacción que se revierte.
-- Sustituir uid_rayssesamira9 por el UUID real del admin.
-- ===========================================================================
/*
begin;

-- Simular sesión del admin (rayssesamira9)
set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"<uid_rayssesamira9>","role":"authenticated"}';

-- A) Admin NO ve recetas, clientes ni facturas de Pruebas (0 filas):
select count(*) as recetas_pruebas from public.recetas
  where organizacion_id = (select id from public.organizaciones where slug='pruebas');

select count(*) as clientes_pruebas from public.clientes
  where organizacion_id = (select id from public.organizaciones where slug='pruebas');

-- B) Admin NO ve precios propios ni ingredientes privados de Pruebas (0 filas):
select count(*) as precios_pruebas from public.inventario_org
  where organizacion_id = (select id from public.organizaciones where slug='pruebas');

select count(*) as privados_pruebas from public.inventario
  where organizacion_id = (select id from public.organizaciones where slug='pruebas');

-- C) Admin NO puede llamar a obtener_inventario_para_org(Pruebas) → excepción:
select * from public.obtener_inventario_para_org(
  (select id from public.organizaciones where slug='pruebas')
);  -- excepción: Sin acceso a la organización indicada.

-- D) Admin SÍ puede ver organizaciones y miembros de Pruebas:
select nombre, slug, activa from public.organizaciones
  where slug = 'pruebas';  -- debe devolver 1 fila

select user_id, rol, activo from public.organizacion_miembros
  where organizacion_id = (select id from public.organizaciones where slug='pruebas');
-- debe devolver los miembros de Pruebas

rollback;  -- la prueba no deja rastro
*/

commit;
