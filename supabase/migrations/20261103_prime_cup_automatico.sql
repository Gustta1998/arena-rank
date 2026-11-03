-- PRIME CUP: controlador automático para execução no Supabase SQL Editor
-- Requer a extensão pg_cron disponível no projeto.
-- Instalar apenas após revisão e backup. NÃO EXCLUI DADOS HISTÓRICOS.
BEGIN;
CREATE SCHEMA IF NOT EXISTS private;

CREATE OR REPLACE FUNCTION private.arena_advance_live_events()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  ev record;
  n integer;
  next_order integer;
  next_result uuid;
  t timestamptz;
  dur integer;
BEGIN
  FOR ev IN
    SELECT e.id, e.started_at, s.phase, s.phase_started_at, s.current_reveal_order
    FROM public.arena_draw_events e
    JOIN public.arena_draw_live_state s ON s.event_id=e.id
    WHERE e.status='live'
    ORDER BY e.created_at
    FOR UPDATE OF e, s SKIP LOCKED
  LOOP
    t := clock_timestamp();

    IF ev.phase='waiting' AND ev.started_at IS NOT NULL THEN
      UPDATE public.arena_draw_live_state
      SET previous_phase='waiting', phase='intro',
          phase_started_at=ev.started_at,
          phase_duration_seconds=15, updated_at=t
      WHERE event_id=ev.id;
      CONTINUE;
    END IF;

    IF ev.phase_started_at IS NULL THEN CONTINUE; END IF;

    IF ev.phase='intro' AND t>=ev.phase_started_at+interval '15 seconds' THEN
      UPDATE public.arena_draw_live_state SET
        previous_phase='intro', phase='opening_video',
        phase_started_at=ev.phase_started_at+interval '15 seconds',
        phase_duration_seconds=72, updated_at=t
      WHERE event_id=ev.id;

    ELSIF ev.phase='opening_video' AND t>=ev.phase_started_at+interval '71.37 seconds' THEN
      UPDATE public.arena_draw_live_state SET
        previous_phase='opening_video', phase='prime_cup',
        phase_started_at=ev.phase_started_at+interval '71.37 seconds',
        phase_duration_seconds=8, updated_at=t
      WHERE event_id=ev.id;

    ELSIF ev.phase='prime_cup' AND t>=ev.phase_started_at+interval '8 seconds' THEN
      SELECT MIN(reveal_order) INTO next_order
      FROM public.arena_draw_results
      WHERE event_id=ev.id AND revealed_at IS NULL;
      IF next_order IS NULL THEN
        UPDATE public.arena_draw_live_state SET
          previous_phase='prime_cup', phase='final_table',
          phase_started_at=t, phase_duration_seconds=7, updated_at=t
        WHERE event_id=ev.id;
      ELSE
        UPDATE public.arena_draw_live_state SET
          previous_phase='prime_cup', phase='suspense',
          current_reveal_order=next_order, phase_started_at=t,
          phase_duration_seconds=10, updated_at=t
        WHERE event_id=ev.id;
      END IF;

    ELSIF ev.phase='suspense' AND t>=ev.phase_started_at+interval '10 seconds' THEN
      -- Protect order and require exact 10s elapsed since suspense start.
      SELECT id INTO next_result
      FROM public.arena_draw_results
      WHERE event_id=ev.id
        AND revealed_at IS NULL
        AND reveal_order=ev.current_reveal_order
      FOR UPDATE;
      IF next_result IS NOT NULL THEN
        UPDATE public.arena_draw_results SET revealed_at=t
        WHERE id=next_result AND revealed_at IS NULL;
      END IF;
      UPDATE public.arena_draw_live_state SET
        previous_phase='suspense', phase='reveal',
        phase_started_at=t, phase_duration_seconds=4, updated_at=t
      WHERE event_id=ev.id;

    ELSIF ev.phase='reveal' AND t>=ev.phase_started_at+interval '4 seconds' THEN
      SELECT MIN(reveal_order) INTO next_order
      FROM public.arena_draw_results
      WHERE event_id=ev.id AND revealed_at IS NULL;
      IF next_order IS NULL THEN
        SELECT GREATEST(7,CEIL(COUNT(*)*1.4+3)::integer) INTO dur
        FROM public.arena_draw_results WHERE event_id=ev.id;
        UPDATE public.arena_draw_live_state SET
          previous_phase='reveal', phase='final_table',
          phase_started_at=t, phase_duration_seconds=dur, updated_at=t
        WHERE event_id=ev.id;
      ELSE
        UPDATE public.arena_draw_live_state SET
          previous_phase='reveal', phase='suspense',
          current_reveal_order=next_order,
          phase_started_at=t, phase_duration_seconds=10, updated_at=t
        WHERE event_id=ev.id;
      END IF;

    ELSIF ev.phase='final_table' AND t>=ev.phase_started_at+
        make_interval(secs=>COALESCE((
          SELECT phase_duration_seconds FROM public.arena_draw_live_state
          WHERE event_id=ev.id),7)) THEN
      UPDATE public.arena_draw_live_state SET
        previous_phase='final_table', phase='closing_video',
        phase_started_at=t, phase_duration_seconds=8, updated_at=t
      WHERE event_id=ev.id;

    ELSIF ev.phase='closing_video' AND t>=ev.phase_started_at+interval '8 seconds' THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.arena_draw_results
        WHERE event_id=ev.id AND revealed_at IS NULL
      ) THEN
        UPDATE public.arena_draw_events SET status='finished' WHERE id=ev.id;
        UPDATE public.arena_draw_live_state SET
          previous_phase='closing_video', phase='finished',
          phase_started_at=t, phase_duration_seconds=NULL, updated_at=t
        WHERE event_id=ev.id;
      END IF;
    END IF;
  END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION private.arena_advance_live_events()
FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.arena_automation_status()
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $status$
DECLARE active_job boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM cron.job
    WHERE jobname='prime-cup-auto-advance-v1' AND active
  ) INTO active_job;
  RETURN COALESCE(active_job,false);
EXCEPTION WHEN undefined_table OR insufficient_privilege THEN
  RETURN false;
END;
$status$;
REVOKE ALL ON FUNCTION public.arena_automation_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.arena_automation_status() TO authenticated;

COMMIT;

-- Ativa o agendamento de 1 segundo. Execute este bloco apenas UMA vez,
-- após confirmar que a extensão pg_cron está habilitada no Supabase.
SELECT cron.schedule(
 'prime-cup-auto-advance-v1',
 '1 second',
 $$SELECT private.arena_advance_live_events();$$
);
