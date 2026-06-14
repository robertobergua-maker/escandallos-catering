alter table public.inventario
  add column if not exists unidad_medida text default 'kg',
  add column if not exists cantidad_formato_compra numeric(12,4),
  add column if not exists unidad_formato_compra text,
  add column if not exists precio_formato_compra numeric(12,4);

update public.inventario
set precio_formato_compra = precio_original
where precio_formato_compra is null
  and precio_original is not null;

update public.inventario
set unidad_formato_compra = unidad_original
where nullif(trim(unidad_formato_compra), '') is null
  and nullif(trim(unidad_original), '') is not null;

update public.inventario
set unidad_medida = 'kg'
where nullif(trim(unidad_medida), '') is null;
