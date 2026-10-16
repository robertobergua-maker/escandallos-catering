-- =============================================================================
-- 024_fase3_catalogo_global_precios_org.sql
-- Fase 3 — Catálogo global / precios e ingredientes privados por organización.
-- =============================================================================
-- ⚠️  SEGURIDAD ALIMENTARIA: este script modifica las políticas de
--    ingrediente_alergenos. Ver secciones C y D.
--
-- DECISIONES DE SAMIRA (definitivas para esta fase):
--   • Precios propios e ingredientes privados: solo los gestiona el GERENTE.
--   • Los alérgenos de un ingrediente privado los declara su organización,
--     a través de ingrediente_alergenos.
--   • Propuestas al catálogo común: quedan para una fase posterior.
--
-- RESUMEN DE CAMBIOS:
--   A. RLS de inventario: select anon/auth por membresía; write solo
--      gerente (privados) o admin (globales). Elimina política duplicada.
--   B. Tabla inventario_org: write solo gerente (no cualquier miembro).
--   C. ⚠️  RLS de ingrediente_alergenos: elimina insert with check(true);
--      write de globales solo admin; write de privados solo gerente de la org.
--   D. ⚠️  Columnas de revisión de alérgenos en inventario privado.
--   E. Función crear_ingrediente_privado (SECURITY DEFINER, solo gerente).
--   F. Eliminar resolver_precio_ingrediente y resolver_merma_ingrediente;
--      obtener_inventario_para_org sigue siendo la única puerta de entrada.
--   G. [COMENTADO] Vaciado de precios del catálogo global tras migrar a org.
--   H. Tests SQL al final.
--
-- Requisitos previos: 022 (Fase 1), 023 (Fase 2).
-- Reversible: ejecutar 024_rollback.sql.
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ===========================================================================
-- A. RLS: inventario
--    Fuente de verdad de las políticas actuales: politicas_actuales.csv
--    Políticas existentes que se eliminan:
--      • "Usuarios autenticados pueden leer ingredientes" (duplicado de
--        inventario_select_authenticated, rol {authenticated}, using(true))
--      • inventario_select_authenticated (select, {authenticated}, using(true))
--      • inventario_select_invitado     (select, {anon}, using(true))
--      • inventario_insert_authenticated (insert, {authenticated}, with check(true))
--      • inventario_admin_all            (ya existe desde 018; se recrea igual)
--    Políticas nuevas:
--      • select authenticated: catálogo global O miembro de la org privada O admin
--      • select anon: solo catálogo global
--      • insert/update/delete global: solo admin
--      • insert/update/delete privado: solo gerente de la org propietaria
-- ===========================================================================

drop policy if exists "Usuarios autenticados pueden leer ingredientes" on public.inventario;
drop policy if exists inventario_select_authenticated                   on public.inventario;
drop policy if exists inventario_select_invitado                       on public.inventario;
drop policy if exists inventario_insert_authenticated                  on public.inventario;
drop policy if exists inventario_update_org                            on public.inventario;
drop policy if exists inventario_delete_org                            on public.inventario;
drop policy if exists inventario_admin_all                             on public.inventario;

-- SELECT authenticated: catálogo global + ingredientes privados de las orgs del usuario
create policy inventario_select_authenticated
  on public.inventario for select to authenticated
  using (
    organizacion_id is null
    or public.es_miembro_org(organizacion_id)
    or public.es_admin_app(auth.uid())
  );

-- SELECT anon (modo invitado): solo catálogo global
create policy inventario_select_invitado
  on public.inventario for select to anon
  using (organizacion_id is null);

-- INSERT global: solo admin de plataforma
-- INSERT privado: solo gerente de la organización
create policy inventario_insert_gerente_o_admin
  on public.inventario for insert to authenticated
  with check (
    (organizacion_id is null     and public.es_admin_app(auth.uid()))
    or
    (organizacion_id is not null and public.es_gerente_org(organizacion_id))
  );

create policy inventario_update_gerente_o_admin
  on public.inventario for update to authenticated
  using (
    (organizacion_id is null     and public.es_admin_app(auth.uid()))
    or
    (organizacion_id is not null and public.es_gerente_org(organizacion_id))
  )
  with check (
    (organizacion_id is null     and public.es_admin_app(auth.uid()))
    or
    (organizacion_id is not null and public.es_gerente_org(organizacion_id))
  );

create policy inventario_delete_gerente_o_admin
  on public.inventario for delete to authenticated
  using (
    (organizacion_id is null     and public.es_admin_app(auth.uid()))
    or
    (organizacion_id is not null and public.es_gerente_org(organizacion_id))
  );

-- Admin todo: mantener para gestión de plataforma
create policy inventario_admin_all
  on public.inventario for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- 1. TABLA: inventario_org
-- ===========================================================================

create table if not exists public.inventario_org (
  id                      uuid         primary key default gen_random_uuid(),
  organizacion_id         uuid         not null
                            references public.organizaciones(id) on delete cascade,
  codigo_ingrediente      text         not null
                            references public.inventario(codigo)
                            on update cascade on delete restrict,
  precio_unidad           numeric(12,4),
  merma                   numeric(8,4),
  proveedor_precio        text,
  formato_compra          text,
  cantidad_formato_compra numeric(12,4),
  unidad_formato_compra   text,
  precio_formato_compra   numeric(12,4),
  url_precio              text,
  observaciones_precio    text,
  updated_at              timestamptz  not null default now(),
  created_at              timestamptz  not null default now(),

  constraint inventario_org_unique unique (organizacion_id, codigo_ingrediente),
  constraint inventario_org_precio_no_negativo
    check (precio_unidad is null or precio_unidad >= 0),
  constraint inventario_org_merma_rango
    check (merma is null or (merma >= 0 and merma < 1))
);

comment on table public.inventario_org
  is 'Precios y datos de proveedor propios de cada organización. '
     'NULL en un campo = usar el valor del catálogo global.';

create index if not exists idx_inventario_org_org_codigo
  on public.inventario_org (organizacion_id, codigo_ingrediente);
create index if not exists idx_inventario_org_codigo
  on public.inventario_org (codigo_ingrediente);

drop trigger if exists trg_inventario_org_set_updated_at on public.inventario_org;
create trigger trg_inventario_org_set_updated_at
  before update on public.inventario_org
  for each row execute function public.set_updated_at();


-- ===========================================================================
-- B. RLS: inventario_org
--    Write solo gerente (no cualquier miembro).
-- ===========================================================================

alter table public.inventario_org enable row level security;

drop policy if exists inventario_org_select    on public.inventario_org;
drop policy if exists inventario_org_insert    on public.inventario_org;
drop policy if exists inventario_org_update    on public.inventario_org;
drop policy if exists inventario_org_delete    on public.inventario_org;
drop policy if exists inventario_org_admin_all on public.inventario_org;

create policy inventario_org_select
  on public.inventario_org for select to authenticated
  using (public.es_miembro_org(organizacion_id));

-- Solo gerente puede crear/modificar/borrar precios propios
create policy inventario_org_insert
  on public.inventario_org for insert to authenticated
  with check (public.es_gerente_org(organizacion_id));

create policy inventario_org_update
  on public.inventario_org for update to authenticated
  using    (public.es_gerente_org(organizacion_id))
  with check (public.es_gerente_org(organizacion_id));

create policy inventario_org_delete
  on public.inventario_org for delete to authenticated
  using (public.es_gerente_org(organizacion_id));

create policy inventario_org_admin_all
  on public.inventario_org for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- 2. MIGRACIÓN DE PRECIOS: inventario → inventario_org (Samirarte)
-- ===========================================================================

do $$
declare
  v_org_id uuid;
  v_filas  integer;
begin
  select id into v_org_id from public.organizaciones where slug = 'samirarte';
  if v_org_id is null then
    raise exception 'Organización "samirarte" no encontrada. Ejecutar primero 022.';
  end if;

  insert into public.inventario_org (
    organizacion_id, codigo_ingrediente,
    precio_unidad, merma, proveedor_precio,
    formato_compra, cantidad_formato_compra, unidad_formato_compra,
    precio_formato_compra, url_precio, observaciones_precio
  )
  select
    v_org_id, i.codigo,
    nullif(i.precio_unidad, 0), nullif(i.merma, 0),
    i.proveedor_precio, i.formato_compra, i.cantidad_formato_compra,
    i.unidad_formato_compra, i.precio_formato_compra,
    i.url_precio, i.observaciones_precio
  from public.inventario i
  where i.organizacion_id is null
    and (
      coalesce(i.precio_unidad, 0) <> 0
      or i.proveedor_precio is not null
      or coalesce(i.merma, 0) <> 0
    )
  on conflict (organizacion_id, codigo_ingrediente) do nothing;

  get diagnostics v_filas = row_count;
  raise notice 'Precios migrados a inventario_org (Samirarte): % ingredientes', v_filas;
end;
$$;


-- ===========================================================================
-- G. [PENDIENTE — COMENTADO] Vaciar precios del catálogo global
--    Tras verificar que Samirarte usa correctamente inventario_org,
--    descomentar y ejecutar en una ventana de mantenimiento.
--    IRREVERSIBLE sin la copia de seguridad previa.
-- ===========================================================================
/*
update public.inventario
set
  precio_unidad           = null,
  merma                   = null,
  proveedor_precio        = null,
  formato_compra          = null,
  cantidad_formato_compra = null,
  unidad_formato_compra   = null,
  precio_formato_compra   = null,
  url_precio              = null,
  observaciones_precio    = null
where organizacion_id is null;
-- Verificar antes: SELECT COUNT(*) FROM inventario_org WHERE organizacion_id =
--   (SELECT id FROM organizaciones WHERE slug='samirarte');
-- Debe coincidir con los ingredientes que tenían precio en inventario.
*/


-- ===========================================================================
-- C. ⚠️  RLS: ingrediente_alergenos
--    SEGURIDAD ALIMENTARIA: cambio de escritura de alérgenos.
--
--    Políticas eliminadas (del CSV y 021):
--      • ingrediente_alergenos_insert_authenticated (with check true — cualquier
--        autenticado podía añadir alérgenos; demasiado permisivo)
--    Políticas nuevas:
--      • select: globales (inventario.organizacion_id IS NULL) para todos
--        autenticados y anon; privados solo para miembros de la org
--      • insert/update/delete global: solo admin
--      • insert/update/delete privado: solo gerente de la org dueña
--        (verificado via EXISTS sobre inventario)
-- ===========================================================================

drop policy if exists ingrediente_alergenos_insert_authenticated on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_select_authenticated on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_select_invitado      on public.ingrediente_alergenos;
-- ingrediente_alergenos_admin_all se mantiene; se recrea para claridad
drop policy if exists ingrediente_alergenos_admin_all            on public.ingrediente_alergenos;

-- SELECT authenticated: alérgenos de ingredientes globales O de la org del usuario
create policy ingrediente_alergenos_select_authenticated
  on public.ingrediente_alergenos for select to authenticated
  using (
    exists (
      select 1 from public.inventario i
      where i.codigo = ingrediente_alergenos.codigo_ingrediente
        and (
          i.organizacion_id is null                          -- ingrediente global
          or public.es_miembro_org(i.organizacion_id)       -- ingrediente privado propio
          or public.es_admin_app(auth.uid())
        )
    )
  );

-- SELECT anon: solo alérgenos de ingredientes globales
create policy ingrediente_alergenos_select_invitado
  on public.ingrediente_alergenos for select to anon
  using (
    exists (
      select 1 from public.inventario i
      where i.codigo = ingrediente_alergenos.codigo_ingrediente
        and i.organizacion_id is null
    )
  );

-- INSERT global: solo admin de plataforma
-- INSERT privado: solo gerente de la org dueña del ingrediente
create policy ingrediente_alergenos_insert_gerente_o_admin
  on public.ingrediente_alergenos for insert to authenticated
  with check (
    exists (
      select 1 from public.inventario i
      where i.codigo = ingrediente_alergenos.codigo_ingrediente
        and (
          (i.organizacion_id is null     and public.es_admin_app(auth.uid()))
          or
          (i.organizacion_id is not null and public.es_gerente_org(i.organizacion_id))
        )
    )
  );

create policy ingrediente_alergenos_update_gerente_o_admin
  on public.ingrediente_alergenos for update to authenticated
  using (
    exists (
      select 1 from public.inventario i
      where i.codigo = ingrediente_alergenos.codigo_ingrediente
        and (
          (i.organizacion_id is null     and public.es_admin_app(auth.uid()))
          or
          (i.organizacion_id is not null and public.es_gerente_org(i.organizacion_id))
        )
    )
  )
  with check (
    exists (
      select 1 from public.inventario i
      where i.codigo = ingrediente_alergenos.codigo_ingrediente
        and (
          (i.organizacion_id is null     and public.es_admin_app(auth.uid()))
          or
          (i.organizacion_id is not null and public.es_gerente_org(i.organizacion_id))
        )
    )
  );

create policy ingrediente_alergenos_delete_gerente_o_admin
  on public.ingrediente_alergenos for delete to authenticated
  using (
    exists (
      select 1 from public.inventario i
      where i.codigo = ingrediente_alergenos.codigo_ingrediente
        and (
          (i.organizacion_id is null     and public.es_admin_app(auth.uid()))
          or
          (i.organizacion_id is not null and public.es_gerente_org(i.organizacion_id))
        )
    )
  );

-- Admin todo
create policy ingrediente_alergenos_admin_all
  on public.ingrediente_alergenos for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- D. ⚠️  COLUMNAS DE REVISIÓN DE ALÉRGENOS en inventario (ingredientes privados)
--    SEGURIDAD ALIMENTARIA: un ingrediente privado no se puede usar en
--    recetas si alergenos_revisados = false (lo controla la app y una función).
-- ===========================================================================

alter table public.inventario
  add column if not exists alergenos_revisados     boolean     not null default false,
  add column if not exists alergenos_revisados_por uuid        references auth.users(id) on delete set null,
  add column if not exists alergenos_revisados_at  timestamptz;

comment on column public.inventario.alergenos_revisados
  is 'True cuando el gerente ha declarado los alérgenos de este ingrediente privado '
     '(al menos un alérgeno en ingrediente_alergenos, o explícitamente "ninguno"). '
     'Siempre true para ingredientes del catálogo global (gestionados por el admin).';
comment on column public.inventario.alergenos_revisados_por
  is 'user_id del gerente que marcó los alérgenos como revisados.';
comment on column public.inventario.alergenos_revisados_at
  is 'Momento en que se marcaron los alérgenos como revisados.';

-- Los ingredientes del catálogo global se marcan como revisados de partida
-- (sus alérgenos los gestiona el admin de plataforma).
update public.inventario
  set alergenos_revisados = true
  where organizacion_id is null;


-- ===========================================================================
-- E. FUNCIÓN: crear_ingrediente_privado
--    Solo el gerente puede crear ingredientes privados para su organización.
--    Genera el código automáticamente: 'P-<slug>-<NNNN>' (secuencial por org).
--    SECURITY DEFINER para poder escribir en inventario sin depender de RLS
--    del llamador (que ya verificamos explícitamente).
-- ===========================================================================

create or replace function public.crear_ingrediente_privado(
  p_org_id                uuid,
  p_descripcion           text,
  p_familia               text    default null,
  p_unidad_medida         text    default 'kg'
)
returns text   -- devuelve el código generado
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slug     text;
  v_seq      integer;
  v_codigo   text;
begin
  -- Solo gerentes pueden crear ingredientes privados
  if not (public.es_gerente_org(p_org_id) or public.es_admin_app(auth.uid())) then
    raise exception 'Solo los gerentes pueden crear ingredientes privados.';
  end if;

  if trim(coalesce(p_descripcion, '')) = '' then
    raise exception 'La descripción del ingrediente no puede estar vacía.';
  end if;

  -- Obtener slug de la organización
  select slug into v_slug
  from public.organizaciones
  where id = p_org_id;

  if v_slug is null then
    raise exception 'Organización no encontrada (id: %).', p_org_id;
  end if;

  -- Calcular siguiente secuencial para esta organización
  select coalesce(
    max(
      nullif(
        regexp_replace(codigo, '^P-[^-]+-0*(\d+)$', '\1'),
        codigo
      )::integer
    ), 0
  ) + 1
  into v_seq
  from public.inventario
  where organizacion_id = p_org_id
    and codigo ~ ('^P-' || v_slug || '-\d+$');

  v_codigo := 'P-' || v_slug || '-' || lpad(v_seq::text, 4, '0');

  insert into public.inventario (
    codigo, familia, descripcion, unidad_medida,
    organizacion_id, alergenos_revisados
  ) values (
    v_codigo, p_familia, p_descripcion, p_unidad_medida,
    p_org_id, false   -- alérgenos pendientes de declarar
  );

  return v_codigo;
end;
$$;

revoke execute on function public.crear_ingrediente_privado(uuid, text, text, text)
  from public, anon;
grant  execute on function public.crear_ingrediente_privado(uuid, text, text, text)
  to authenticated;

comment on function public.crear_ingrediente_privado(uuid, text, text, text)
  is 'Crea un ingrediente privado con código automático P-<slug>-NNNN. '
     'Solo gerentes. alergenos_revisados = false hasta que el gerente los declare.';


-- ===========================================================================
-- F. ELIMINAR resolver_precio_ingrediente y resolver_merma_ingrediente
--    Estas funciones no verificaban membresía. obtener_inventario_para_org
--    es la única puerta de entrada a precios y mermas.
-- ===========================================================================

drop function if exists public.resolver_precio_ingrediente(text, uuid);
drop function if exists public.resolver_merma_ingrediente(text, uuid);


-- ===========================================================================
-- 3. FUNCIÓN: obtener_inventario_para_org  (actualizada)
--    Incluye alergenos_revisados para que la app pueda mostrar avisos.
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
    i.codigo,
    i.familia,
    i.descripcion,
    i.unidad_medida,
    (i.organizacion_id is not null)                                    as es_privado,
    i.alergenos_revisados,
    coalesce(io.precio_unidad,            i.precio_unidad)             as precio_unidad,
    (io.precio_unidad is not null)                                     as precio_es_propio,
    coalesce(io.merma,                    i.merma)                     as merma,
    (io.merma is not null)                                             as merma_es_propia,
    coalesce(io.proveedor_precio,         i.proveedor_precio)          as proveedor_precio,
    coalesce(io.formato_compra,           i.formato_compra)            as formato_compra,
    coalesce(io.cantidad_formato_compra,  i.cantidad_formato_compra)   as cantidad_formato_compra,
    coalesce(io.unidad_formato_compra,    i.unidad_formato_compra)     as unidad_formato_compra,
    coalesce(io.precio_formato_compra,    i.precio_formato_compra)     as precio_formato_compra,
    coalesce(io.url_precio,               i.url_precio)                as url_precio,
    coalesce(io.observaciones_precio,     i.observaciones_precio)      as observaciones_precio
  from public.inventario i
  left join public.inventario_org io
         on io.codigo_ingrediente = i.codigo
        and io.organizacion_id    = p_organizacion_id
  where
    i.organizacion_id is null
    or i.organizacion_id = p_organizacion_id
  order by i.familia nulls last, i.descripcion;
end;
$$;

revoke execute on function public.obtener_inventario_para_org(uuid) from public, anon;
grant  execute on function public.obtener_inventario_para_org(uuid) to authenticated;

comment on function public.obtener_inventario_para_org(uuid)
  is 'Catálogo con precios efectivos para la organización. Incluye alergenos_revisados. '
     'Verifica membresía. Solo accesible para miembros.';


-- ===========================================================================
-- AUDITORÍA POST-MIGRACIÓN
-- ===========================================================================

select
  (select count(*) from public.inventario where organizacion_id is null)
    as ingredientes_catalogo_global,
  (select count(*) from public.inventario_org
   where organizacion_id = (select id from public.organizaciones where slug='samirarte'))
    as precios_samirarte_migrados,
  (select count(*) from public.inventario
   where organizacion_id is null and alergenos_revisados = false)
    as globales_sin_revisar;
-- globales_sin_revisar debe ser 0 (se marcaron todos como revisados arriba).

-- Verificar nuevas políticas de inventario:
select policyname, cmd, roles
from pg_policies
where schemaname = 'public' and tablename = 'inventario'
order by policyname;

-- Verificar nuevas políticas de ingrediente_alergenos:
select policyname, cmd, roles
from pg_policies
where schemaname = 'public' and tablename = 'ingrediente_alergenos'
order by policyname;


-- ===========================================================================
-- H. TESTS DE AISLAMIENTO RLS (ejecutar manualmente tras el commit)
-- ===========================================================================
-- Requisitos: org "Pruebas" activa, usuario chef de Pruebas, usuario chef de
-- Samirarte (roberto.bergua@gmail.com), usuario con rol 'usuario' (NO admin).
-- Sustituir UUIDs reales.
-- ===========================================================================
/*
-- ── TEST 1: chef de Pruebas no puede crear ingredientes privados ni precios ──
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"<uid_chef_pruebas>","role":"authenticated"}';

-- Crear ingrediente privado → debe fallar (no es gerente)
select public.crear_ingrediente_privado(
  (select id from public.organizaciones where slug='pruebas'),
  'Test privado'
);  -- excepción: Solo los gerentes pueden crear ingredientes privados.

-- Insertar precio propio → debe fallar (no es gerente)
insert into public.inventario_org (organizacion_id, codigo_ingrediente, precio_unidad)
values (
  (select id from public.organizaciones where slug='pruebas'),
  'CUALQUIER_CODIGO', 5.00
);  -- violación de política RLS

-- ── TEST 2: anon no ve ingredientes privados ──────────────────────────────
set local role anon;
select count(*) from public.inventario where organizacion_id is not null;
-- Debe devolver 0.
select count(*) from public.ingrediente_alergenos
where codigo_ingrediente in (
  select codigo from public.inventario where organizacion_id is not null
);
-- Debe devolver 0.

-- ── TEST 3: Pruebas no ve ingredientes privados ni precios de Samirarte ──
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"<uid_chef_pruebas>","role":"authenticated"}';

select count(*) from public.inventario
where organizacion_id = (select id from public.organizaciones where slug='samirarte');
-- Debe devolver 0.

select count(*) from public.inventario_org
where organizacion_id = (select id from public.organizaciones where slug='samirarte');
-- Debe devolver 0.

-- ── TEST 4: nadie salvo admin modifica alérgenos globales ─────────────────
-- Como chef (NO admin) intentar insertar alérgeno en ingrediente global:
set local "request.jwt.claims" to '{"sub":"<uid_chef_samirarte>","role":"authenticated"}';
insert into public.ingrediente_alergenos (codigo_ingrediente, alergeno_id)
values (
  (select codigo from public.inventario where organizacion_id is null limit 1),
  (select id from public.alergenos limit 1)
);  -- violación de política (no es admin ni gerente del ingrediente global)

-- Como gerente de Samirarte intentar lo mismo (gerente ≠ admin para globales):
set local "request.jwt.claims" to '{"sub":"<uid_gerente_samirarte>","role":"authenticated"}';
insert into public.ingrediente_alergenos (codigo_ingrediente, alergeno_id)
values (
  (select codigo from public.inventario where organizacion_id is null limit 1),
  (select id from public.alergenos limit 1)
);
-- Los gerentes tampoco pueden modificar ingrediente_alergenos de globales.
-- Solo admin puede.
*/


commit;
