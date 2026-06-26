-- Actualización automática NO supervisada de alérgenos de ingredientes.
-- Requiere tener creadas las tablas public.alergenos y public.ingrediente_alergenos.
-- Estrategia: reemplaza todas las relaciones actuales por una clasificación basada en reglas de texto.
-- La revisión fina se hará posteriormente al construir/validar recetas.

begin;

-- Copia de seguridad de las relaciones actuales antes de reemplazar.
create table if not exists public.backup_ingrediente_alergenos as
select * from public.ingrediente_alergenos where false;

insert into public.backup_ingrediente_alergenos
select * from public.ingrediente_alergenos;

-- Limpieza completa para dejar una clasificación homogénea.
delete from public.ingrediente_alergenos;

with inventario_normalizado as (
  select
    i.codigo,
    lower(translate(
      concat_ws(' ', i.codigo, i.familia, i.descripcion, i.formato_compra, i.observaciones_precio),
      'áàäâÁÀÄÂéèëêÉÈËÊíìïîÍÌÏÎóòöôÓÒÖÔúùüûÚÙÜÛñÑçÇ',
      'aaaaAAAAeeeeEEEEiiiiIIIIooooOOOOuuuuUUUUnNcC'
    )) as texto
  from public.inventario i
  where nullif(trim(i.codigo), '') is not null
), reglas as (
  select codigo, 'GLUTEN'::text as alergeno_codigo from inventario_normalizado
  where (
    texto ~ '(trigo|espelta|centeno|cebada|kamut|bulgur|cuscus|couscous|semola|seitan|panko|pan rallado|hojaldre|pasta filo|masa filo|filo|brioche|croissant|galleta|bizcocho|magdalena|pan | panes|\bpan\b|pasta|macarron|espagueti|spaghetti|tallarines|fideo)'
    or (texto ~ '\bharina\b' and texto !~ 'harina de (maiz|maíz|arroz|garbanzo|almendra|coco|avena sin gluten)')
  )
  and texto !~ 'sin gluten|gluten free'

  union all
  select codigo, 'HUEVO' from inventario_normalizado
  where texto ~ '(\bhuevo\b|\bhuevos\b|\byema\b|\byemas\b|\bclara\b|\bclaras\b|mayonesa|merengue)'
  and texto !~ 'sin huevo'

  union all
  select codigo, 'LECHE' from inventario_normalizado
  where texto ~ '(\bleche\b|lactosa|lacteo|lacteos|nata|mantequilla|queso|yogur|yogurt|mascarpone|mozzarella|parmesano|cheddar|emmental|brie|ricotta|bechamel|crema de leche)'
  and texto !~ 'sin leche|vegetal|soja|avena|almendra|coco'

  union all
  select codigo, 'FRUTOS_SECOS' from inventario_normalizado
  where texto ~ '(almendra|almendras|avellana|avellanas|nuez|nueces|pistacho|pistachos|anacardo|anacardos|pinon|pinones|piñon|piñones|pecana|macadamia|nuez de brasil|frutos secos|fruto seco)'

  union all
  select codigo, 'CACAHUETES' from inventario_normalizado
  where texto ~ '(cacahuete|cacahuetes|mani|maní|mantequilla de cacahuete)'

  union all
  select codigo, 'SOJA' from inventario_normalizado
  where texto ~ '(\bsoja\b|\bsoya\b|tofu|edamame|tamari|lecitina de soja|salsa de soja)'

  union all
  select codigo, 'PESCADO' from inventario_normalizado
  where texto ~ '(pescado|atun|atún|salmon|salmón|bacalao|merluza|anchoa|anchoas|sardina|sardinas|boqueron|boquerón|rape|dorada|lubina|trucha|caballa|bonito|sepia pescado)'

  union all
  select codigo, 'CRUSTACEOS' from inventario_normalizado
  where texto ~ '(gamba|gambas|langostino|langostinos|camaron|camarón|camarones|cigala|cigalas|bogavante|cangrejo|centollo|nécora|necora|crustaceo|crustáceo)'

  union all
  select codigo, 'MOLUSCOS' from inventario_normalizado
  where texto ~ '(mejillon|mejillón|mejillones|almeja|almejas|berberecho|berberechos|ostra|ostras|calamar|calamares|pulpo|sepia|chirla|chirlas|vieira|vieiras|molusco|moluscos)'

  union all
  select codigo, 'APIO' from inventario_normalizado
  where texto ~ '(\bapio\b|sal de apio)'

  union all
  select codigo, 'MOSTAZA' from inventario_normalizado
  where texto ~ '(mostaza|mustard)'

  union all
  select codigo, 'SESAMO' from inventario_normalizado
  where texto ~ '(sesamo|sésamo|tahini|ajonjoli|ajonjolí)'

  union all
  select codigo, 'SULFITOS' from inventario_normalizado
  where texto ~ '(sulfito|sulfitos|metabisulfito|vino|vinagre|pasas|orejones|fruta deshidratada|frutas deshidratadas|fruta seca|frutas secas)'

  union all
  select codigo, 'ALTRAMUCES' from inventario_normalizado
  where texto ~ '(altramuz|altramuces|lupino|lupin)'
), relaciones as (
  select distinct r.codigo, a.id as alergeno_id
  from reglas r
  join public.alergenos a
    on a.codigo = r.alergeno_codigo
  join public.inventario i
    on i.codigo = r.codigo
)
insert into public.ingrediente_alergenos (codigo_ingrediente, alergeno_id)
select codigo, alergeno_id
from relaciones
on conflict (codigo_ingrediente, alergeno_id) do nothing;

-- Resumen de control.
select
  a.codigo as alergeno,
  a.nombre,
  count(ia.codigo_ingrediente) as ingredientes_asignados
from public.alergenos a
left join public.ingrediente_alergenos ia
  on ia.alergeno_id = a.id
group by a.codigo, a.nombre
order by a.nombre;

-- Ingredientes sin ningún alérgeno asignado.
select count(*) as ingredientes_sin_alergenos
from public.inventario i
left join public.ingrediente_alergenos ia
  on ia.codigo_ingrediente = i.codigo
where ia.codigo_ingrediente is null;

commit;
