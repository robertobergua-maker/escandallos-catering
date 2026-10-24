-- =============================================================================
-- 028_prueba.sql
-- Prueba de 028_recetas_por_chef.sql. Pegar TAL CUAL en el SQL Editor de
-- Supabase. Ejecutar como postgres. Termina con ROLLBACK: no deja rastro.
-- Revisar la tabla r al final: todas las filas deben tener ok = true.
--
-- Requisito: sql/028_recetas_por_chef.sql ya aplicado.
-- Usa una organización de prueba creada dentro de la transacción y los 4
-- primeros usuarios de auth.users (gerente, chef_a, chef_b, chef_c).
-- =============================================================================

begin;

create temp table r (
  prueba             text    not null,
  resultado_esperado text    not null,
  obtenido           text,
  ok                 boolean
) on commit drop;

-- f: identificadores de usuarios y datos de prueba
create temp table f (
  clave text primary key,
  id    uuid not null
) on commit drop;

insert into f (clave, id)
select clave, id from (
  select
    case row_number() over (order by created_at)
      when 1 then 'gerente'
      when 2 then 'chef_a'
      when 3 then 'chef_b'
      when 4 then 'chef_c'
    end as clave, id
  from auth.users
  order by created_at
  limit 4
) sub where clave is not null;

grant all on r, f to authenticated, anon;

-- Organización de prueba
insert into f (clave, id) values ('org', gen_random_uuid());
insert into public.organizaciones (id, nombre, slug)
values ((select id from f where clave = 'org'), 'Prueba 028', 'prueba-028-' || substr(md5(random()::text), 1, 8));

insert into public.organizacion_miembros (organizacion_id, user_id, rol, activo)
select (select id from f where clave = 'org'), id,
       case when clave = 'gerente' then 'gerente' else 'chef' end, true
from f where clave in ('gerente', 'chef_a', 'chef_b', 'chef_c');

-- Recetas: una de cada chef A y B, una del gerente, una antigua sin propietario
insert into f (clave, id) values
  ('r_a', gen_random_uuid()), ('r_b', gen_random_uuid()),
  ('r_g', gen_random_uuid()), ('r_n', gen_random_uuid()),
  ('menu', gen_random_uuid());

insert into public.recetas (id, organizacion_id, user_id, codigo_receta, nombre)
values
  ((select id from f where clave = 'r_a'), (select id from f where clave = 'org'), (select id from f where clave = 'chef_a'),  'T028-A-' || substr(md5(random()::text), 1, 8), 'Receta de A'),
  ((select id from f where clave = 'r_b'), (select id from f where clave = 'org'), (select id from f where clave = 'chef_b'),  'T028-B-' || substr(md5(random()::text), 1, 8), 'Receta de B'),
  ((select id from f where clave = 'r_g'), (select id from f where clave = 'org'), (select id from f where clave = 'gerente'), 'T028-G-' || substr(md5(random()::text), 1, 8), 'Receta del gerente'),
  ((select id from f where clave = 'r_n'), (select id from f where clave = 'org'), null,                                       'T028-N-' || substr(md5(random()::text), 1, 8), 'Receta antigua');

insert into public.receta_ingredientes (receta_id, descripcion_ingrediente, cantidad_bruta)
values ((select id from f where clave = 'r_b'), 'Ingrediente de B', 1);

-- Menú de la organización con la receta antigua
insert into public.menus (id, organizacion_id, user_id, nombre)
values ((select id from f where clave = 'menu'), (select id from f where clave = 'org'), (select id from f where clave = 'gerente'), 'Menú prueba 028');
insert into public.menu_recetas (menu_id, receta_id)
values ((select id from f where clave = 'menu'), (select id from f where clave = 'r_n'));

-- =============================================================================
-- P01: chef_a ve su receta, no la de chef_b ni la del gerente, sí la del menú
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_a int; v_b int; v_g int; v_n int;
begin
  select id into v_uid from f where clave = 'chef_a';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  select count(*) into v_a from public.recetas where id = (select id from f where clave = 'r_a');
  select count(*) into v_b from public.recetas where id = (select id from f where clave = 'r_b');
  select count(*) into v_g from public.recetas where id = (select id from f where clave = 'r_g');
  select count(*) into v_n from public.recetas where id = (select id from f where clave = 'r_n');

  insert into r values (
    'P01 chef_a ve: propia sí, de B no, del gerente no, en menú sí',
    'a=1 b=0 g=0 n=1',
    'a=' || v_a || ' b=' || v_b || ' g=' || v_g || ' n=' || v_n,
    v_a = 1 and v_b = 0 and v_g = 0 and v_n = 1
  );
end $$;
reset role;

-- =============================================================================
-- P02: el gerente ve las 4 recetas de la organización
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_n int;
begin
  select id into v_uid from f where clave = 'gerente';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  select count(*) into v_n from public.recetas
  where organizacion_id = (select id from f where clave = 'org');

  insert into r values ('P02 gerente ve todas las recetas', '4', v_n::text, v_n = 4);
end $$;
reset role;

-- =============================================================================
-- P03: chef_a no puede editar la receta de B (0 filas) y sí la suya (1 fila)
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_b int; v_a int;
begin
  select id into v_uid from f where clave = 'chef_a';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  update public.recetas set observaciones = 'x' where id = (select id from f where clave = 'r_b');
  get diagnostics v_b = row_count;
  update public.recetas set observaciones = 'x' where id = (select id from f where clave = 'r_a');
  get diagnostics v_a = row_count;

  insert into r values (
    'P03 chef_a edita: de B no, propia sí',
    'b=0 a=1',
    'b=' || v_b || ' a=' || v_a,
    v_b = 0 and v_a = 1
  );
end $$;
reset role;

-- =============================================================================
-- P04: chef_a no puede crear una receta a nombre de chef_b
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from f where clave = 'chef_a';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    insert into public.recetas (organizacion_id, user_id, codigo_receta, nombre)
    values ((select id from f where clave = 'org'), (select id from f where clave = 'chef_b'),
            'T028-X-' || substr(md5(random()::text), 1, 8), 'Suplantación');
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P04 chef_a no crea recetas a nombre de otro',
    'exc: row-level security',
    v_err,
    v_err ilike '%row-level security%'
  );
end $$;
reset role;

-- =============================================================================
-- P05: un chef no puede conceder permisos
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from f where clave = 'chef_a';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    perform public.conceder_permisos_recetas(
      (select id from f where clave = 'org'),
      array[(select id from f where clave = 'chef_a')],
      array[(select id from f where clave = 'chef_b')],
      null, 'lectura');
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values ('P05 chef no concede permisos', 'exc: Solo el gerente', v_err, v_err ilike '%Solo el gerente%');
end $$;
reset role;

-- =============================================================================
-- P06: un chef no puede escribir directamente en receta_permisos
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from f where clave = 'chef_a';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    insert into public.receta_permisos (organizacion_id, chef_id, propietario_id, nivel)
    values ((select id from f where clave = 'org'), v_uid, (select id from f where clave = 'chef_b'), 'edicion');
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values ('P06 chef no inserta permisos directamente', 'exc: permission denied / row-level security', v_err,
                        v_err ilike '%permission denied%' or v_err ilike '%row-level security%');
end $$;
reset role;

-- =============================================================================
-- P07: el gerente concede en bloque LECTURA a chef_a y chef_c sobre las
--      recetas de chef_b
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_n int;
begin
  select id into v_uid from f where clave = 'gerente';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  v_n := public.conceder_permisos_recetas(
    (select id from f where clave = 'org'),
    array[(select id from f where clave = 'chef_a'), (select id from f where clave = 'chef_c')],
    array[(select id from f where clave = 'chef_b')],
    null, 'lectura');

  insert into r values ('P07 gerente concede lectura en bloque', '2', v_n::text, v_n = 2);
end $$;
reset role;

-- =============================================================================
-- P08: con lectura, chef_a ve la receta de B y sus ingredientes, pero no la edita
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_ver int; v_ing int; v_upd int;
begin
  select id into v_uid from f where clave = 'chef_a';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  select count(*) into v_ver from public.recetas where id = (select id from f where clave = 'r_b');
  select count(*) into v_ing from public.receta_ingredientes where receta_id = (select id from f where clave = 'r_b');
  update public.recetas set observaciones = 'y' where id = (select id from f where clave = 'r_b');
  get diagnostics v_upd = row_count;

  insert into r values (
    'P08 lectura: ve receta e ingredientes de B, no edita',
    'ver=1 ing=1 upd=0',
    'ver=' || v_ver || ' ing=' || v_ing || ' upd=' || v_upd,
    v_ver = 1 and v_ing = 1 and v_upd = 0
  );
end $$;
reset role;

-- =============================================================================
-- P09: el gerente sube a EDICION el permiso de chef_a sobre la receta de B;
--      chef_a ya puede editarla y cambiar sus ingredientes, pero no borrarla
-- =============================================================================
do $$
declare
  v_uid uuid;
begin
  select id into v_uid from f where clave = 'gerente';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  perform public.conceder_permisos_recetas(
    (select id from f where clave = 'org'),
    array[(select id from f where clave = 'chef_a')],
    null,
    array[(select id from f where clave = 'r_b')],
    'edicion');
end $$;
reset role;

do $$
declare
  v_uid uuid;
  v_upd int; v_ing int; v_del int;
begin
  select id into v_uid from f where clave = 'chef_a';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  update public.recetas set observaciones = 'z' where id = (select id from f where clave = 'r_b');
  get diagnostics v_upd = row_count;
  insert into public.receta_ingredientes (receta_id, descripcion_ingrediente, cantidad_bruta)
  values ((select id from f where clave = 'r_b'), 'Añadido por A', 1);
  get diagnostics v_ing = row_count;
  delete from public.recetas where id = (select id from f where clave = 'r_b');
  get diagnostics v_del = row_count;

  insert into r values (
    'P09 edicion: edita receta e ingredientes de B, no la borra',
    'upd=1 ing=1 del=0',
    'upd=' || v_upd || ' ing=' || v_ing || ' del=' || v_del,
    v_upd = 1 and v_ing = 1 and v_del = 0
  );
end $$;
reset role;

-- =============================================================================
-- P10: chef_c (solo lectura) sigue sin poder editar la receta de B
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_upd int;
begin
  select id into v_uid from f where clave = 'chef_c';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  update public.recetas set observaciones = 'c' where id = (select id from f where clave = 'r_b');
  get diagnostics v_upd = row_count;

  insert into r values ('P10 chef_c con lectura no edita', 'upd=0', 'upd=' || v_upd, v_upd = 0);
end $$;
reset role;

-- =============================================================================
-- P11: un chef no puede cambiar el propietario de su receta
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from f where clave = 'chef_a';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    update public.recetas set user_id = (select id from f where clave = 'chef_b')
    where id = (select id from f where clave = 'r_a');
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values ('P11 chef no cambia el propietario', 'exc: Solo el gerente', v_err, v_err ilike '%Solo el gerente%');
end $$;
reset role;

-- =============================================================================
-- P12: el gerente asigna en bloque la receta antigua a chef_c
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_n int;
  v_prop uuid;
begin
  select id into v_uid from f where clave = 'gerente';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  v_n := public.asignar_propietario_recetas(
    (select id from f where clave = 'org'),
    array[(select id from f where clave = 'r_n')],
    (select id from f where clave = 'chef_c'));
  select user_id into v_prop from public.recetas where id = (select id from f where clave = 'r_n');

  insert into r values (
    'P12 gerente asigna propietario en bloque',
    'n=1 y propietario=chef_c',
    'n=' || v_n,
    v_n = 1 and v_prop = (select id from f where clave = 'chef_c')
  );
end $$;
reset role;

-- =============================================================================
-- P13: el gerente revoca en bloque todos los permisos; chef_a deja de ver la
--      receta de B
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_n int;
begin
  select id into v_uid from f where clave = 'gerente';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  v_n := public.revocar_permisos_recetas(
    (select id from f where clave = 'org'),
    array(select id from public.receta_permisos where organizacion_id = (select id from f where clave = 'org')));

  insert into r values ('P13 gerente revoca en bloque', '3', v_n::text, v_n = 3);
end $$;
reset role;

do $$
declare
  v_uid uuid;
  v_b int;
begin
  select id into v_uid from f where clave = 'chef_a';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  select count(*) into v_b from public.recetas where id = (select id from f where clave = 'r_b');

  insert into r values ('P14 tras revocar, chef_a no ve la receta de B', '0', v_b::text, v_b = 0);
end $$;
reset role;

-- =============================================================================
-- P15: un chef solo ve sus propios permisos en receta_permisos
-- =============================================================================
do $$
declare
  v_uid uuid;
begin
  select id into v_uid from f where clave = 'gerente';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  perform public.conceder_permisos_recetas(
    (select id from f where clave = 'org'),
    array[(select id from f where clave = 'chef_a'), (select id from f where clave = 'chef_c')],
    array[(select id from f where clave = 'chef_b')],
    null, 'lectura');
end $$;
reset role;

do $$
declare
  v_uid uuid;
  v_propios int; v_ajenos int;
begin
  select id into v_uid from f where clave = 'chef_a';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  select count(*) filter (where chef_id = v_uid),
         count(*) filter (where chef_id <> v_uid)
  into v_propios, v_ajenos
  from public.receta_permisos;

  insert into r values (
    'P15 chef solo ve sus permisos',
    'propios=1 ajenos=0',
    'propios=' || v_propios || ' ajenos=' || v_ajenos,
    v_propios = 1 and v_ajenos = 0
  );
end $$;
reset role;

select * from r order by prueba;

rollback;
