-- =============================================================================
-- 028b_bloquear_cambio_org_receta.sql
-- Trigger BEFORE UPDATE OF organizacion_id ON recetas:
-- impide que cualquier usuario autenticado cambie la organización de una
-- receta ya existente. Solo el rol service_role (sin JWT) puede hacerlo.
--
-- Motivo: la integridad multiorganización exige que una receta no cambie de
-- organización una vez creada. receta_permisos, copias y menús se vinculan
-- al organizacion_id original; si cambiara, esas referencias quedarían
-- huérfanas o apuntarían a datos de otra organización.
--
-- Reversible: 028b_rollback.sql.
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ===========================================================================
-- 1. Función del trigger
-- ===========================================================================

create or replace function public.bloquear_cambio_organizacion_receta()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- auth.uid() es NULL cuando la llamada viene de service_role o de funciones
  -- SECURITY DEFINER ejecutadas con el rol de postgres. En ese caso se permite
  -- el cambio (migraciones de datos, correcciones administrativas).
  if auth.uid() is not null
     and NEW.organizacion_id is distinct from OLD.organizacion_id
  then
    raise exception
      'No se puede cambiar la organización de una receta existente '
      '(receta id: %). Crea una copia en la organización destino.',
      OLD.id
      using errcode = 'P0001';
  end if;
  return NEW;
end;
$$;

comment on function public.bloquear_cambio_organizacion_receta()
  is 'Trigger: impide que auth.uid() != null cambie organizacion_id en recetas.';

-- ===========================================================================
-- 2. Trigger
-- ===========================================================================

drop trigger if exists trg_bloquear_cambio_org_receta on public.recetas;

create trigger trg_bloquear_cambio_org_receta
  before update of organizacion_id
  on public.recetas
  for each row
  execute function public.bloquear_cambio_organizacion_receta();

comment on trigger trg_bloquear_cambio_org_receta on public.recetas
  is 'Impide cambios de organizacion_id por usuarios autenticados (auth.uid() != null).';

-- ===========================================================================
-- AUDITORÍA
-- ===========================================================================

-- Verificar que el trigger existe (debe devolver 1 fila):
select tgname, tgenabled
from pg_trigger
where tgrelid = 'public.recetas'::regclass
  and tgname = 'trg_bloquear_cambio_org_receta';

commit;
