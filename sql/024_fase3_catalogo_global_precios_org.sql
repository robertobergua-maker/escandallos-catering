-- =============================================================================
-- 024_fase3_catalogo_global_precios_org.sql
-- Fase 3 — Catálogo global / precios e ingredientes privados por organización.
-- =============================================================================
-- ⚠️  SEGURIDAD ALIMENTARIA: este script modifica las políticas de
--    ingrediente_alergenos y añade protecciones sobre alergenos_revisados.
--    Ver secciones C, D y D2.
--
-- DECISIONES DE SAMIRA (definitivas para esta fase):
--   • Precios propios e ingredientes privados: solo los gestiona el GERENTE.
--   • Los alérgenos de un ingrediente privado los declara su organización.
--   • Propuestas al catálogo común: quedan para una fase posterior.
--   • Los ingredientes privados NO se borran directamente: se desactivan.
--     Un trigger bloquea el DELETE si el código aparece en receta_ingredientes.
--   • alergenos_revisados solo se cambia vía marcar_alergenos_revisados().
--     Un trigger impide el UPDATE directo de las columnas de revisión.
--
-- RESUMEN DE CAMBIOS:
--   A. RLS inventario: select por membresía; insert/update solo gerente (privados).
--      Prohibición de INSERT directo de privados: solo via crear_ingrediente_privado.
--   B. inventario_org: write solo gerente.
--   C. ⚠️  RLS ingrediente_alergenos: solo gerente/admin escribe.
--   D. ⚠️  Columnas alergenos_revisados + trigger protección escritura directa.
--   D2. Trigger _trg_inventario_revisado_on_alergenos_delete: si se borra un
--       alérgeno de un privado, alergenos_revisados vuelve a false.
--   E. crear_ingrediente_privado (SECURITY DEFINER, lock anti-race, slug con guiones).
--   E2. Trigger _trg_inventario_privado_no_borrar: bloquea DELETE si está en uso.
--   E3. Trigger _trg_inventario_privado_no_cambiar_codigo: bloquea renombrado.
--   F. DROP de resolver_precio/merma_ingrediente.
--   G. [COMENTADO] Vaciado de precios del catálogo global.
--   H. Tests SQL al final.
--   marcar_alergenos_revisados (SECURITY DEFINER, único punto de escritura).
--
-- Requisitos previos: 022 (Fase 1), 023 (Fase 2).
-- Reversible: ejecutar 024_rollback.sql.
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ===========================================================================
-- A. RLS: inventario
--    Políticas actuales eliminadas (fuente: politicas_actuales.csv):
--      "Usuarios autenticados pueden leer ingredientes" (SELECT authenticated true)
--      inventario_select_authenticated (SELECT authenticated true — duplicado)
--      inventario_select_invitado      (SELECT anon true)
--      inventario_insert_authenticated (INSERT authenticated with check true)
--    Nuevas:
--      select: catálogo global O miembro org O admin
--      select anon: solo global
--      insert/update/delete privado: solo gerente de la org
--      insert/update/delete global: solo admin
-- ===========================================================================

drop policy if exists "Usuarios autenticados pueden leer ingredientes" on public.inventario;
drop policy if exists inventario_select_authenticated                   on public.inventario;
drop policy if exists inventario_select_invitado                       on public.inventario;
drop policy if exists inventario_insert_authenticated                  on public.inventario;
drop policy if exists inventario_update_org                            on public.inventario;
drop policy if exists inventario_delete_org                            on public.inventario;
drop policy if exists inventario_insert_gerente_o_admin               on public.inventario;
drop policy if exists inventario_update_gerente_o_admin               on public.inventario;
drop policy if exists inventario_delete_gerente_o_admin               on public.inventario;
drop policy if exists inventario_admin_all                             on public.inventario;

create policy inventario_select_authenticated
  on public.inventario for select to authenticated
  using (
    organizacion_id is null
    or public.es_miembro_org(organizacion_id)
    or public.es_admin_app(auth.uid())
  );

create policy inventario_select_invitado
  on public.inventario for select to anon
  using (organizacion_id is null);

-- INSERT privado: SOLO via crear_ingrediente_privado (SECURITY DEFINER).
-- La política solo permite INSERT global al admin. Los privados no son
-- alcanzables desde un INSERT directo de autenticados; crear_ingrediente_privado
-- es SECURITY DEFINER y no depende de esta política.
create policy inventario_insert_gerente_o_admin
  on public.inventario for insert to authenticated
  with check (
    organizacion_id is null and public.es_admin_app(auth.uid())
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

-- DELETE privado: bloqueado si está en uso (trigger E2); solo gerente puede intentarlo.
create policy inventario_delete_gerente_o_admin
  on public.inventario for delete to authenticated
  using (
    (organizacion_id is null     and public.es_admin_app(auth.uid()))
    or
    (organizacion_id is not null and public.es_gerente_org(organizacion_id))
  );

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
-- B. RLS: inventario_org — write solo gerente
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
--    Tras verificar que Samirarte usa correctamente inventario_org.
--    Ver reglas.md: decisión obligatoria antes de la primera org externa.
--    IRREVERSIBLE sin copia de seguridad previa.
-- ===========================================================================
/*
update public.inventario
set
  precio_unidad = null, merma = null, proveedor_precio = null,
  formato_compra = null, cantidad_formato_compra = null,
  unidad_formato_compra = null, precio_formato_compra = null,
  url_precio = null, observaciones_precio = null
where organizacion_id is null;
*/


-- ===========================================================================
-- C. ⚠️  RLS: ingrediente_alergenos
--    SEGURIDAD ALIMENTARIA.
--    Políticas eliminadas (CSV + 021):
--      ingrediente_alergenos_insert_authenticated (with check true)
--      ingrediente_alergenos_select_authenticated
--      ingrediente_alergenos_select_invitado
--      ingrediente_alergenos_admin_all
--    Políticas nuevas: select por membresía; write global solo admin;
--    write privado solo gerente via EXISTS sobre inventario.
-- ===========================================================================

drop policy if exists ingrediente_alergenos_insert_authenticated     on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_select_authenticated     on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_select_invitado          on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_admin_all                on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_insert_gerente_o_admin   on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_update_gerente_o_admin   on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_delete_gerente_o_admin   on public.ingrediente_alergenos;

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

create policy ingrediente_alergenos_select_invitado
  on public.ingrediente_alergenos for select to anon
  using (
    exists (
      select 1 from public.inventario i
      where i.codigo = ingrediente_alergenos.codigo_ingrediente
        and i.organizacion_id is null
    )
  );

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

create policy ingrediente_alergenos_admin_all
  on public.ingrediente_alergenos for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- D. ⚠️  COLUMNAS DE REVISIÓN DE ALÉRGENOS
-- ===========================================================================

alter table public.inventario
  add column if not exists alergenos_revisados     boolean     not null default false,
  add column if not exists alergenos_revisados_por uuid        references auth.users(id) on delete set null,
  add column if not exists alergenos_revisados_at  timestamptz;

comment on column public.inventario.alergenos_revisados
  is 'True cuando el gerente ha declarado los alérgenos (≥1 en ingrediente_alergenos '
     'o explícitamente "ninguno"). Para catálogo global: siempre true.';

-- Ingredientes globales ya revisados de partida
update public.inventario
  set alergenos_revisados = true
  where organizacion_id is null;


-- ===========================================================================
-- D2. ⚠️  TRIGGER: proteger escritura directa de alergenos_revisados
--     Solo marcar_alergenos_revisados() puede cambiar estas columnas.
--     La función usa SET LOCAL escandallos.revisando_alergenos = '1'
--     (análogo al mecanismo del trigger de facturas en 026).
-- ===========================================================================

create or replace function public._trg_inventario_protect_revisado()
returns trigger
language plpgsql
-- SECURITY INVOKER: current_user refleja el rol real del llamador.
set search_path = public
as $$
declare
  v_flag text := current_setting('escandallos.revisando_alergenos', true);
begin
  if tg_op = 'INSERT' then
    -- Solo para ingredientes privados (organizacion_id NOT NULL).
    -- Los ingredientes globales que cree el admin no se ven afectados.
    -- crear_ingrediente_privado (SECURITY DEFINER, current_user=postgres) no entra aquí.
    if current_user in ('anon', 'authenticated') and new.organizacion_id is not null then
      new.alergenos_revisados     := false;
      new.alergenos_revisados_por := null;
      new.alergenos_revisados_at  := null;
    end if;
    return new;
  end if;

  -- UPDATE: bloquear cambio directo de las columnas de revisión
  if tg_op = 'UPDATE' then
    if current_user in ('anon', 'authenticated') then
      if (new.alergenos_revisados    is distinct from old.alergenos_revisados    or
          new.alergenos_revisados_por is distinct from old.alergenos_revisados_por or
          new.alergenos_revisados_at  is distinct from old.alergenos_revisados_at)
         and coalesce(v_flag, '') <> '1' then
        raise exception
          'alergenos_revisados solo puede modificarse vía marcar_alergenos_revisados().';
      end if;
    end if;
    return new;
  end if;

  return new;
end;
$$;

revoke execute on function public._trg_inventario_protect_revisado() from public, anon;

drop trigger if exists trg_inventario_protect_revisado on public.inventario;
create trigger trg_inventario_protect_revisado
  before insert or update on public.inventario
  for each row execute function public._trg_inventario_protect_revisado();


-- ===========================================================================
-- D3. ⚠️  TRIGGER: si se borra un alérgeno de un privado → revisado = false
-- ===========================================================================

create or replace function public._trg_alergenos_delete_reset_revisado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Solo aplica a ingredientes privados (organizacion_id NOT NULL)
  -- Usa SET LOCAL para saltar el trigger de protección
  perform set_config('escandallos.revisando_alergenos', '1', true);
  update public.inventario
    set alergenos_revisados     = false,
        alergenos_revisados_por = null,
        alergenos_revisados_at  = null
    where codigo          = old.codigo_ingrediente
      and organizacion_id is not null;
  return old;
end;
$$;

revoke execute on function public._trg_alergenos_delete_reset_revisado() from public, anon;

drop trigger if exists trg_alergenos_delete_reset_revisado on public.ingrediente_alergenos;
create trigger trg_alergenos_delete_reset_revisado
  after delete on public.ingrediente_alergenos
  for each row execute function public._trg_alergenos_delete_reset_revisado();

comment on function public._trg_alergenos_delete_reset_revisado()
  is '⚠️ Si se borra un alérgeno de un ingrediente privado, alergenos_revisados '
     'vuelve a false hasta que el gerente vuelva a revisarlos.';


-- ===========================================================================
-- E. FUNCIÓN: crear_ingrediente_privado
--    • pg_advisory_xact_lock: evita condición de carrera al calcular el seq.
--    • substring(...from ''(-\d+)$'') + filtro por organizacion_id:
--      funciona correctamente con slugs que contienen guiones.
--    • No expone RLS al llamador (SECURITY DEFINER + verificación explícita).
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

  select slug into v_slug
  from public.organizaciones where id = p_org_id;

  if v_slug is null then
    raise exception 'Organización no encontrada (id: %).', p_org_id;
  end if;

  v_prefix := 'P-' || v_slug || '-';

  -- Lock a nivel de transacción para evitar concurrencia en el mismo org
  perform pg_advisory_xact_lock(hashtext(p_org_id::text));

  -- Calcular siguiente número extrayendo el sufijo numérico final.
  -- substring(codigo from '-(\d+)$') extrae el número tras el último guión,
  -- lo que funciona incluso si v_slug contiene guiones.
  select coalesce(
    max(
      nullif(
        substring(codigo from '-(\d+)$'),
        ''
      )::integer
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
  is 'Crea ingrediente privado con código P-<slug>-NNNN. '
     'Lock anti-race. Solo gerentes. alergenos_revisados = false hasta revisión.';


-- ===========================================================================
-- E2. TRIGGER: bloquear DELETE de privado si está en receta_ingredientes
--     receta_ingredientes.codigo_ingrediente no tiene FK → no hay cascade.
--     El trigger protege contra borrados silenciosos que dejan ingredientes
--     sin nombre y sin alérgenos en las recetas.
-- ===========================================================================

create or replace function public._trg_inventario_privado_no_borrar()
returns trigger
language plpgsql
-- SECURITY INVOKER: current_user real
set search_path = public
as $$
declare
  v_en_uso integer;
begin
  if old.organizacion_id is null then
    -- Ingredientes globales: no aplica esta restricción
    return old;
  end if;

  select count(*) into v_en_uso
  from public.receta_ingredientes
  where codigo_ingrediente = old.codigo;

  if v_en_uso > 0 then
    raise exception
      'No se puede borrar el ingrediente privado "%" (código %): '
      'aparece en % receta(s). Quítalo primero de las recetas que lo usan.',
      old.descripcion, old.codigo, v_en_uso;
  end if;

  return old;
end;
$$;

revoke execute on function public._trg_inventario_privado_no_borrar() from public, anon;

drop trigger if exists trg_inventario_privado_no_borrar on public.inventario;
create trigger trg_inventario_privado_no_borrar
  before delete on public.inventario
  for each row execute function public._trg_inventario_privado_no_borrar();

comment on function public._trg_inventario_privado_no_borrar()
  is 'Bloquea el borrado de un ingrediente privado si aparece en alguna receta. '
     'Usar desactivación (activo=false) en su lugar.';


-- ===========================================================================
-- E3. TRIGGER: prohibir cambio de código de un ingrediente privado
-- ===========================================================================

create or replace function public._trg_inventario_privado_no_cambiar_codigo()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.organizacion_id is not null
     and new.codigo is distinct from old.codigo
     and current_user in ('anon', 'authenticated') then
    raise exception
      'No se puede cambiar el código de un ingrediente privado (% → %). '
      'Los códigos son inmutables.', old.codigo, new.codigo;
  end if;
  return new;
end;
$$;

revoke execute on function public._trg_inventario_privado_no_cambiar_codigo() from public, anon;

drop trigger if exists trg_inventario_privado_no_cambiar_codigo on public.inventario;
create trigger trg_inventario_privado_no_cambiar_codigo
  before update on public.inventario
  for each row execute function public._trg_inventario_privado_no_cambiar_codigo();


-- ===========================================================================
-- FUNCIÓN: marcar_alergenos_revisados
--    Único punto de escritura de alergenos_revisados / _por / _at.
--    Verifica: es_gerente_org + (≥1 alérgeno OR p_sin_alergenos=true).
--    Usa SET LOCAL para pasar el trigger de protección.
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

  -- Contar alérgenos declarados
  select count(*) into v_n_alergenos
  from public.ingrediente_alergenos
  where codigo_ingrediente = p_codigo;

  if v_n_alergenos = 0 and not p_sin_alergenos then
    raise exception
      'Declara al menos un alérgeno o confirma que no contiene ninguno de los '
      '14 alérgenos (p_sin_alergenos = true).';
  end if;

  -- Autorizar el UPDATE de las columnas protegidas en esta transacción
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
-- F. ELIMINAR resolver_precio y resolver_merma
-- ===========================================================================

drop function if exists public.resolver_precio_ingrediente(text, uuid);
drop function if exists public.resolver_merma_ingrediente(text, uuid);


-- ===========================================================================
-- 3. FUNCIÓN: obtener_inventario_para_org (actualizada con alergenos_revisados)
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
-- globales_sin_revisar debe ser 0.

select policyname, cmd, roles
from pg_policies
where schemaname = 'public'
  and tablename in ('inventario','ingrediente_alergenos','inventario_org')
order by tablename, policyname;


-- ===========================================================================
-- H. TESTS DE AISLAMIENTO RLS (ejecutar manualmente, sustituir UUIDs)
-- ===========================================================================
/*
-- TEST 1: chef de Pruebas no puede crear privados ni precios
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"<uid_chef_pruebas>","role":"authenticated"}';
select public.crear_ingrediente_privado(
  (select id from public.organizaciones where slug='pruebas'), 'Test'
);  -- excepción: Solo los gerentes...
insert into public.inventario_org (organizacion_id, codigo_ingrediente, precio_unidad)
values ((select id from public.organizaciones where slug='pruebas'), 'X', 5);
-- violación RLS

-- TEST 2: anon no ve privados
set local role anon;
select count(*) from public.inventario where organizacion_id is not null;  -- 0
select count(*) from public.ingrediente_alergenos
  where codigo_ingrediente in
    (select codigo from public.inventario where organizacion_id is not null);  -- 0

-- TEST 3: Pruebas no ve datos de Samirarte
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"<uid_chef_pruebas>","role":"authenticated"}';
select count(*) from public.inventario
  where organizacion_id=(select id from public.organizaciones where slug='samirarte');  -- 0
select count(*) from public.inventario_org
  where organizacion_id=(select id from public.organizaciones where slug='samirarte');  -- 0

-- TEST 4: nadie salvo admin modifica alérgenos globales
set local "request.jwt.claims" to '{"sub":"<uid_chef_samirarte>","role":"authenticated"}';
insert into public.ingrediente_alergenos (codigo_ingrediente, alergeno_id)
values ((select codigo from public.inventario where organizacion_id is null limit 1),
        (select id from public.alergenos limit 1));  -- violación RLS

-- TEST 5: cambiar alergenos_revisados directamente → excepción
set local "request.jwt.claims" to '{"sub":"<uid_gerente_samirarte>","role":"authenticated"}';
update public.inventario set alergenos_revisados = true
  where organizacion_id=(select id from public.organizaciones where slug='samirarte')
  limit 1;  -- excepción: alergenos_revisados solo vía marcar_alergenos_revisados()

-- TEST 6: borrar privado en uso → excepción
delete from public.inventario
  where organizacion_id=(select id from public.organizaciones where slug='samirarte')
  and codigo in (select distinct codigo_ingrediente from public.receta_ingredientes)
  limit 1;  -- excepción: aparece en N receta(s)
*/

commit;
