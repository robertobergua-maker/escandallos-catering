-- Limpieza de campos abiertos previos
alter table public.inventario
  drop column if exists alergenos;

alter table public.receta_ingredientes
  drop column if exists alergenos;

alter table public.recetas
  drop column if exists alergenos;

-- Catálogo normalizado de alérgenos
create table if not exists public.alergenos (
  id uuid primary key default gen_random_uuid(),
  codigo text unique not null,
  nombre text not null,
  descripcion text,
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.alergenos (codigo, nombre)
values
  ('GLUTEN', 'Gluten'),
  ('CRUSTACEOS', 'Crustáceos'),
  ('HUEVO', 'Huevo'),
  ('PESCADO', 'Pescado'),
  ('CACAHUETES', 'Cacahuetes'),
  ('SOJA', 'Soja'),
  ('LECHE', 'Leche'),
  ('FRUTOS_SECOS', 'Frutos secos'),
  ('APIO', 'Apio'),
  ('MOSTAZA', 'Mostaza'),
  ('SESAMO', 'Sésamo'),
  ('SULFITOS', 'Sulfitos'),
  ('ALTRAMUCES', 'Altramuces'),
  ('MOLUSCOS', 'Moluscos')
on conflict (codigo) do update
set nombre = excluded.nombre;

-- Relación normalizada ingrediente <-> alérgeno
create table if not exists public.ingrediente_alergenos (
  id uuid primary key default gen_random_uuid(),
  codigo_ingrediente text not null,
  alergeno_id uuid not null,
  created_at timestamptz not null default now(),

  constraint ingrediente_alergenos_codigo_ingrediente_fkey
    foreign key (codigo_ingrediente)
    references public.inventario(codigo)
    on update cascade
    on delete cascade,

  constraint ingrediente_alergenos_alergeno_id_fkey
    foreign key (alergeno_id)
    references public.alergenos(id)
    on delete cascade,

  constraint ingrediente_alergenos_unique
    unique (codigo_ingrediente, alergeno_id)
);

create index if not exists idx_ingrediente_alergenos_codigo
  on public.ingrediente_alergenos (codigo_ingrediente);

create index if not exists idx_ingrediente_alergenos_alergeno
  on public.ingrediente_alergenos (alergeno_id);

-- Validación esperada: debe devolver 14
select count(*) as total_alergenos from public.alergenos;
