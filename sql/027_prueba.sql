-- =============================================================================
-- 027_prueba.sql
-- Prueba de listar_miembros_org. Pegar TAL CUAL en el SQL Editor de Supabase.
-- Ejecutar como postgres. Termina con ROLLBACK: no deja rastro.
-- Revisar la tabla r al final: todas las filas deben tener ok = true.
--
-- Requisito: sql/027_listar_miembros_org.sql ya aplicado.
--
-- UUIDs de organizaciones (hardcoded):
--   Samirarte : 4bdf1328-958e-4b0b-97de-38ba157a5e2e
--   Pruebas   : 367d4642-16bc-4817-9565-a6b914d96aa9
-- =============================================================================

begin;

create temp table r (
  prueba             text    not null,
  resultado_esperado text    not null,
  obtenido           text,
  ok                 boolean
) on commit drop;

-- u: 4 primeros usuarios de auth.users → gerente/chef de cada org
create temp table u (
  clave text primary key,
  id    uuid not null
) on commit drop;

insert into u (clave, id)
select clave, id from (
  select
    case row_number() over (order by created_at)
      when 1 then 'gerente_samirarte'
      when 2 then 'chef_samirarte'
      when 3 then 'gerente_pruebas'
      when 4 then 'chef_pruebas'
    end as clave, id
  from auth.users
  order by created_at
  limit 4
) sub where clave is not null;

grant all on r, u to authenticated, anon;

-- Membresías de prueba
insert into public.organizacion_miembros (organizacion_id, user_id, rol, activo)
values ('4bdf1328-958e-4b0b-97de-38ba157a5e2e', (select id from u where clave='gerente_samirarte'), 'gerente', true)
on conflict (organizacion_id, user_id) do update set rol='gerente', activo=true;

insert into public.organizacion_miembros (organizacion_id, user_id, rol, activo)
values ('4bdf1328-958e-4b0b-97de-38ba157a5e2e', (select id from u where clave='chef_samirarte'), 'chef', true)
on conflict (organizacion_id, user_id) do update set rol='chef', activo=true;

insert into public.organizacion_miembros (organizacion_id, user_id, rol, activo)
values ('367d4642-16bc-4817-9565-a6b914d96aa9', (select id from u where clave='gerente_pruebas'), 'gerente', true)
on conflict (organizacion_id, user_id) do update set rol='gerente', activo=true;

-- =============================================================================
-- P1: el gerente de Samirarte lista sus miembros y ve emails (no solo uuid)
-- =============================================================================
do $$
declare
  v_uid       uuid;
  v_n         integer;
  v_con_email integer;
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  select count(*),
         count(*) filter (where email is not null and email <> '')
  into v_n, v_con_email
  from public.listar_miembros_org('4bdf1328-958e-4b0b-97de-38ba157a5e2e');

  insert into r values (
    'P1 gerente_samirarte lista miembros con email',
    'n>=2 y todos con email',
    'n=' || v_n || ' con_email=' || v_con_email,
    v_n >= 2 and v_con_email = v_n
  );
end $$;
reset role;

-- =============================================================================
-- P2: un CHEF (no gerente) NO puede listar los miembros
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'chef_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    perform public.listar_miembros_org('4bdf1328-958e-4b0b-97de-38ba157a5e2e');
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P2 chef NO puede listar miembros',
    'exc: Solo el gerente',
    v_err,
    v_err ilike '%Solo el gerente%'
  );
end $$;
reset role;

-- =============================================================================
-- P3: el gerente de Pruebas NO puede listar miembros de Samirarte (otra org)
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'gerente_pruebas';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    perform public.listar_miembros_org('4bdf1328-958e-4b0b-97de-38ba157a5e2e');
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P3 gerente de otra org NO lista miembros ajenos',
    'exc: Solo el gerente',
    v_err,
    v_err ilike '%Solo el gerente%'
  );
end $$;
reset role;

-- =============================================================================
-- P4: anon NO puede ejecutar la función
-- =============================================================================
do $$
declare
  v_err text := 'no lanzó excepción';
begin
  set local role anon;
  begin
    perform public.listar_miembros_org('4bdf1328-958e-4b0b-97de-38ba157a5e2e');
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P4 anon NO puede ejecutar listar_miembros_org',
    'exc / permiso denegado',
    v_err,
    v_err <> 'no lanzó excepción'
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
