-- =============================================================================
-- 025b_prueba.sql
-- Prueba de siguiente_codigo_receta().
--
-- CÓMO EJECUTAR:
--   Pegar TODO el script en el SQL Editor de Supabase y ejecutarlo de una vez.
--   Ejecutar como postgres (superusuario). No hay nada que sustituir.
--   El script termina con ROLLBACK: no deja rastro en la BD.
--   Revisar la tabla r al final: todas las filas deben tener ok = true.
--
-- Requisito: sql/025b_codigo_receta_global.sql ya aplicado.
-- =============================================================================

begin;

-- Tabla de resultados
create temp table r (
  prueba             text    not null,
  resultado_esperado text    not null,
  obtenido           text,
  ok                 boolean
) on commit drop;

-- Tabla de usuario de prueba: gerente de Pruebas tomado de organizacion_miembros
create temp table u (
  clave text primary key,
  id    uuid not null
) on commit drop;

insert into u (clave, id)
select 'gerente_pruebas', om.user_id
from public.organizacion_miembros om
where om.organizacion_id = '367d4642-16bc-4817-9565-a6b914d96aa9'
  and om.rol    = 'gerente'
  and om.activo = true
limit 1;

-- Si no hay gerente de Pruebas en organizacion_miembros, usar cualquier usuario
-- autenticado (la función valida solo que auth.uid() no sea null)
insert into u (clave, id)
select 'gerente_pruebas', id
from auth.users
order by created_at
limit 1
on conflict (clave) do nothing;

grant all on r, u to authenticated, anon;

-- =============================================================================
-- P1: siguiente_codigo_receta() devuelve formato REC-NNNN
-- =============================================================================
do $$
declare
  v_uid  uuid;
  v_cod  text;
  v_ok   boolean;
begin
  select id into v_uid from u where clave = 'gerente_pruebas';
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  v_cod := public.siguiente_codigo_receta();
  v_ok  := (v_cod ~ '^REC-\d{4,}$');

  insert into r values (
    'P1 siguiente_codigo_receta devuelve formato REC-NNNN',
    'formato REC-NNNN',
    coalesce(v_cod, 'null'),
    v_ok
  );
end $$;

reset role;

-- =============================================================================
-- P2: el código devuelto es mayor que el máximo REC-NNNN de Samirarte
--     (la función ve todas las orgs, no solo la del llamador)
-- =============================================================================
do $$
declare
  v_uid      uuid;
  v_cod      text;
  v_max_sam  integer;
  v_num_cod  integer;
  v_ok       boolean;
begin
  -- Máximo REC existente en Samirarte (leído como postgres, sin RLS)
  select coalesce(max(
    nullif(substring(codigo_receta from '^REC-(\d+)$'), '')::integer
  ), 0)
  into v_max_sam
  from public.recetas
  where organizacion_id = '4bdf1328-958e-4b0b-97de-38ba157a5e2e'
    and codigo_receta ~ '^REC-\d+$';

  select id into v_uid from u where clave = 'gerente_pruebas';
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  v_cod     := public.siguiente_codigo_receta();
  v_num_cod := nullif(substring(v_cod from '^REC-(\d+)$'), '')::integer;

  v_ok := (v_num_cod > v_max_sam);

  insert into r values (
    'P2 siguiente_codigo_receta > max REC de Samirarte (ve todas las orgs)',
    'codigo > max_samirarte',
    'max_samirarte=' || v_max_sam || ' codigo=' || coalesce(v_cod, 'null'),
    v_ok
  );
end $$;

reset role;

-- =============================================================================
-- P3: anon NO puede ejecutar siguiente_codigo_receta()
-- =============================================================================
do $$
declare
  v_err text := 'no lanzó excepción';
begin
  set local role anon;

  begin
    perform public.siguiente_codigo_receta();
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P3 anon NO puede ejecutar siguiente_codigo_receta',
    'permission denied o exc',
    v_err,
    v_err <> 'no lanzó excepción'
  );
end $$;

reset role;

-- =============================================================================
-- P4: dos llamadas en la misma transacción devuelven códigos distintos
--     (el lock + max en el mismo snapshot los haría iguales si no hubiera
--     insert intermedio; aquí solo verificamos que ambos son REC-NNNN válidos
--     — la unicidad real la garantiza el constraint + el lock entre sesiones)
-- =============================================================================
do $$
declare
  v_uid  uuid;
  v_cod1 text;
  v_cod2 text;
  v_ok   boolean;
begin
  select id into v_uid from u where clave = 'gerente_pruebas';
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  v_cod1 := public.siguiente_codigo_receta();
  -- Insertar una receta ficticia para que la segunda llamada vea un max mayor
  insert into public.recetas (
    organizacion_id, user_id, codigo_receta, nombre,
    raciones_base, costes_indirectos_pct, margen_beneficio_pct,
    iva_pct, coste_total, precio_venta_sin_iva, precio_venta_con_iva, activa
  )
  select
    '367d4642-16bc-4817-9565-a6b914d96aa9',
    v_uid,
    v_cod1,
    'Receta TEMP 025b prueba',
    1, 0, 0, 0, 0, 0, 0, true;

  v_cod2 := public.siguiente_codigo_receta();

  v_ok := (v_cod1 ~ '^REC-\d{4,}$')
       and (v_cod2 ~ '^REC-\d{4,}$')
       and (v_cod1 <> v_cod2);

  insert into r values (
    'P4 dos llamadas en misma transacción dan códigos distintos',
    'cod1 <> cod2 y ambos REC-NNNN',
    'cod1=' || coalesce(v_cod1,'null') || ' cod2=' || coalesce(v_cod2,'null'),
    v_ok
  );
end $$;

reset role;

-- =============================================================================
-- RESULTADO
-- =============================================================================

select prueba, resultado_esperado, obtenido, ok
from r
order by prueba;

rollback;
