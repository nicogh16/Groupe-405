-- ============================================================================
-- 1. EXTENSIONS, SCHÉMAS ET TYPES
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "pg_cron";
CREATE EXTENSION IF NOT EXISTS "pg_net";
CREATE EXTENSION IF NOT EXISTS "pgmq";

CREATE SCHEMA IF NOT EXISTS private;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS mv;
CREATE SCHEMA IF NOT EXISTS dashboard_view;
CREATE SCHEMA IF NOT EXISTS view;

CREATE TYPE public.section_id AS ENUM (
  'dashboard', 'statistics', 'promotions', 'cashregisters', 'restaurants', 'articles', 'offers', 'members', 'polls'
);

CREATE TYPE public.user_role AS ENUM (
  'utilisateur', 'caissier', 'administrateur', 'marketing', 'membre', 'superadmin'
);

-- ============================================================================
-- 2. SOUS-FONCTIONS UTILES (Dépendances)
-- ============================================================================

CREATE OR REPLACE FUNCTION private.current_week_menu_url_from_jsonb(menus jsonb)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  week_monday date;
  week_sunday date;
  elem jsonb;
  sdate date;
  edate date;
  url text;
  best_url text;
  best_start date;
  has_dates boolean;
BEGIN
  IF menus IS NULL OR jsonb_typeof(menus) <> 'array' OR jsonb_array_length(menus) = 0 THEN
    RETURN '';
  END IF;

  week_monday := date_trunc('week', current_date)::date;
  week_sunday := week_monday + 6;
  best_url := NULL;
  best_start := NULL;

  FOR elem IN SELECT * FROM jsonb_array_elements(menus)
  LOOP
    url := elem->>'url';
    IF url IS NULL OR trim(url) = '' THEN
      CONTINUE;
    END IF;

    BEGIN
      sdate := (elem->>'start_date')::date;
    EXCEPTION WHEN OTHERS THEN
      sdate := NULL;
    END;
    BEGIN
      edate := (elem->>'end_date')::date;
    EXCEPTION WHEN OTHERS THEN
      edate := NULL;
    END;

    has_dates := (sdate IS NOT NULL OR edate IS NOT NULL);

    IF has_dates THEN
      IF (sdate IS NULL OR sdate <= week_sunday) AND (edate IS NULL OR edate >= week_monday) THEN
        IF best_start IS NULL OR (sdate IS NOT NULL AND sdate > best_start) THEN
          best_start := sdate;
          best_url := url;
        END IF;
      END IF;
    ELSE
      IF best_url IS NULL THEN
        best_url := url;
      END IF;
    END IF;
  END LOOP;

  IF best_url IS NOT NULL THEN
    RETURN best_url;
  END IF;

  FOR elem IN SELECT * FROM jsonb_array_elements(menus)
  LOOP
    url := elem->>'url';
    IF url IS NOT NULL AND trim(url) <> '' AND elem->>'start_date' IS NULL AND elem->>'end_date' IS NULL THEN
      RETURN url;
    END IF;
  END LOOP;

  RETURN '';
END;
$$;

CREATE OR REPLACE FUNCTION private.validate_notification_settings(p_settings jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_settings IS NULL THEN
        RETURN NULL;
    END IF;

    IF jsonb_typeof(p_settings) <> 'object' THEN
        RAISE EXCEPTION 'notification_settings doit être un objet JSON';
    END IF;

    RETURN p_settings;
END;
$$;

CREATE OR REPLACE FUNCTION private.validate_user_field(p_field_name text, p_field_value text, p_operation text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_cleaned text;
    v_user_local text;
    v_user_domain text;
    v_normalized_local text;
BEGIN
    IF p_field_value IS NULL THEN
        RETURN NULL;
    END IF;

    v_cleaned := trim(p_field_value);

    CASE p_field_name
        WHEN 'email' THEN
            IF v_cleaned !~ '^[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$' THEN
                RAISE EXCEPTION 'Format email invalide: %', v_cleaned;
            END IF;

            v_cleaned := lower(v_cleaned);
            v_user_local := lower(split_part(v_cleaned, '@', 1));
            v_user_domain := lower(split_part(v_cleaned, '@', 2));
            v_normalized_local := split_part(v_user_local, '+', 1);

            IF v_normalized_local ~ '(^|[\._\-])(test|espion|fake|dummy|admin|root|superuser|spam|trash|bot|robot|temp|tmp|guest|support|staff|mod|dev|null|undefined|anonymous|user|junk|webmaster)([\._\-]|$)' THEN
                RAISE EXCEPTION 'Nom d''utilisateur interdit ou suspect.';
            END IF;

            IF v_user_domain IN ('polymtl.ca', 'etud.polymtl.ca', 'umontreal.ca', 'hec.ca', 'mcgill.ca', 'gmail.com', 'outlook.com', 'hotmail.com') THEN
                RETURN v_cleaned;
            END IF;

            IF EXISTS (SELECT 1 FROM private.disposable_emails WHERE domain = v_user_domain) THEN
                RAISE EXCEPTION 'Les emails jetables sont interdits sur MyFidelity.';
            END IF;

            RETURN v_cleaned;

        WHEN 'name' THEN
            IF length(v_cleaned) < 2 THEN RAISE EXCEPTION 'Le nom doit contenir au moins 2 caractères'; END IF;
            IF length(v_cleaned) > 100 THEN RAISE EXCEPTION 'Le nom ne peut pas dépasser 100 caractères'; END IF;
            IF v_cleaned ~ '[<>]' THEN RAISE EXCEPTION 'Caractères interdits détectés (XSS): < ou >'; END IF;
            IF v_cleaned ~* '(--|;)' THEN RAISE EXCEPTION 'Caractères suspects détectés (SQL injection): -- ou ;'; END IF;

            v_cleaned := regexp_replace(v_cleaned, '[\._\-]', ' ', 'g');
            v_cleaned := regexp_replace(v_cleaned, '[^a-zA-ZÀ-ÿ\s]', '', 'g');
            v_cleaned := trim(regexp_replace(v_cleaned, '\s+', ' ', 'g'));

            IF length(v_cleaned) < 2 THEN RAISE EXCEPTION 'Le nom après nettoyage est trop court (min 2 caractères)'; END IF;
            RETURN left(v_cleaned, 100);

        WHEN 'avatar_url' THEN
            IF v_cleaned !~ '^https?://' AND v_cleaned !~ '^/[^/]' AND v_cleaned !~ '^[a-zA-Z0-9_\-]+\.(avif|png|jpg|jpeg|webp)$' THEN
                RAISE EXCEPTION 'Format URL avatar invalide: %', v_cleaned;
            END IF;
            IF v_cleaned ~ '[<>"]' THEN RAISE EXCEPTION 'Caractères interdits dans URL avatar (XSS)'; END IF;
            RETURN v_cleaned;

        ELSE
            IF v_cleaned ~ '[<>]' THEN RAISE EXCEPTION 'Caractères interdits détectés (XSS) dans %: < ou >', p_field_name; END IF;
            IF v_cleaned ~* '(--|;)' THEN RAISE EXCEPTION 'Caractères suspects détectés (SQL injection) dans %: -- ou ;', p_field_name; END IF;
            RETURN v_cleaned;
    END CASE;
END;
$$;

CREATE OR REPLACE FUNCTION private.log_user_security_event(p_operation text, p_user_id uuid, p_old_data jsonb, p_new_data jsonb, p_changed_fields text[])
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_event_details jsonb;
BEGIN
  v_event_details := jsonb_build_object(
    'operation', p_operation,
    'user_id', p_user_id,
    'changed_by', auth.uid(),
    'changed_fields', COALESCE(p_changed_fields, ARRAY[]::text[]),
    'timestamp', now()
  );

  RAISE NOTICE '[SECURITY_AUDIT] user=% operation=% target_user=% fields=% old=% new=%',
    auth.uid(), p_operation, p_user_id, p_changed_fields, p_old_data, p_new_data;
END;
$$;

-- ============================================================================
-- 3. FONCTIONS DE TRIGGERS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION mv.refresh_mv_offers()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv.mv_offers;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION mv.refresh_mv_restaurants()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv.mv_restaurants;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION private.trg_sync_restaurant_menu_url()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.restaurant_menu_url := private.current_week_menu_url_from_jsonb(COALESCE(NEW.restaurant_menu_url_jsonb, '[]'::jsonb));
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.check_points_modification_allowed()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.points = OLD.points THEN
        RETURN NEW;
    END IF;
    
    IF NEW.status = 'valide' OR OLD.status = 'valide' THEN
        RETURN NEW;
    END IF;
    
    BEGIN
        IF current_setting('role', true) = 'service_role' THEN
            RETURN NEW;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    
    RAISE EXCEPTION 'Modification directe de points interdite. Utilisez les fonctions autorisées.';
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION audit.recalculate_user_points_on_transaction_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id uuid;
    v_recalculated_points integer;
BEGIN
    IF TG_NAME IS NULL THEN RAISE EXCEPTION 'Accès refusé'; END IF;
    
    v_user_id := COALESCE(NEW.user_id, OLD.user_id);
    
    SELECT COALESCE(SUM(points), 0) INTO v_recalculated_points
    FROM private.transactions
    WHERE user_id = v_user_id AND status = 'valide';
    
    UPDATE private.users
    SET points = v_recalculated_points
    WHERE id = v_user_id;
    
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION audit.verify_transaction_points_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_item jsonb;
    v_item_name text;
    v_item_qty integer;
    v_item_type text;
    v_points_gained integer := 0;
    v_points_spent integer := 0;
    v_recalculated integer;
    v_difference integer;
    v_severity text;
    v_original_points integer;
BEGIN
    IF TG_NAME IS NULL THEN RAISE EXCEPTION 'Accès refusé'; END IF;
    
    IF TG_OP = 'INSERT' THEN v_original_points := NEW.points;
    ELSIF TG_OP = 'UPDATE' THEN v_original_points := NEW.points;
    ELSE v_original_points := NEW.points; END IF;
    
    IF TG_OP = 'INSERT' THEN
        IF NEW.status != 'valide' THEN RETURN NEW; END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.status != 'valide' AND OLD.status != 'valide' THEN RETURN NEW; END IF;
    END IF;
    
    IF NEW.items IS NOT NULL AND jsonb_typeof(NEW.items) = 'array' THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(NEW.items)
        LOOP
            v_item_name := v_item->>'id';
            v_item_qty := COALESCE((v_item->>'qty')::integer, 1);
            v_item_type := COALESCE(v_item->>'type', 'article');
            
            IF v_item_type IN ('article', 'ecogeste') THEN
                v_points_gained := v_points_gained + COALESCE((SELECT points FROM private.articles WHERE name = v_item_name LIMIT 1), 0) * v_item_qty;
            END IF;
            
            IF v_item_type = 'offer' THEN
                v_points_spent := v_points_spent + COALESCE((SELECT ABS(points) FROM private.offers WHERE title = v_item_name LIMIT 1), 0) * v_item_qty;
            END IF;
        END LOOP;
    END IF;
    
    v_recalculated := v_points_gained - v_points_spent;
    v_difference := v_recalculated - v_original_points;
    
    IF ABS(v_difference) > 0 THEN
        IF ABS(v_difference) <= 10 THEN v_severity := 'medium';
        ELSIF ABS(v_difference) <= 50 THEN v_severity := 'high';
        ELSE v_severity := 'critical'; END IF;
        
        NEW.points := v_recalculated;
        
        INSERT INTO audit.transaction_points_anomalies (transaction_id, user_id, stored_points, recalculated_points, points_difference, severity, status)
        VALUES (NEW.id, NEW.user_id, CASE WHEN TG_OP = 'UPDATE' THEN OLD.points ELSE NEW.points END, v_recalculated, v_difference, v_severity, 'corrige_auto')
        ON CONFLICT (transaction_id) DO UPDATE SET
            stored_points = CASE WHEN TG_OP = 'UPDATE' THEN OLD.points ELSE NEW.points END,
            recalculated_points = v_recalculated, points_difference = v_difference, severity = v_severity, status = 'corrige_auto', detected_at = now();
            
        RAISE WARNING '[SECURITY_ALERT] Anomalie de points détectée et CORRIGÉE - Transaction: %', NEW.id;
    END IF;
    
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION audit.verify_user_points_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_recalculated_points integer;
    v_difference integer;
    v_severity text;
    v_original_points integer;
BEGIN
    IF TG_NAME IS NULL THEN RAISE EXCEPTION 'Accès refusé'; END IF;
    
    v_original_points := COALESCE(NEW.points, 0);
    
    SELECT COALESCE(SUM(points), 0) INTO v_recalculated_points
    FROM private.transactions WHERE user_id = NEW.id AND status = 'valide';
    
    v_difference := v_recalculated_points - v_original_points;
    
    IF ABS(v_difference) > 0 THEN
        IF ABS(v_difference) <= 10 THEN v_severity := 'medium';
        ELSIF ABS(v_difference) <= 50 THEN v_severity := 'high';
        ELSE v_severity := 'critical'; END IF;
        
        NEW.points := v_recalculated_points;
        
        INSERT INTO audit.user_points_anomalies (user_id, stored_points, recalculated_points, points_difference, severity, status)
        VALUES (NEW.id, CASE WHEN TG_OP = 'UPDATE' THEN OLD.points ELSE v_original_points END, v_recalculated_points, v_difference, v_severity, 'corrige_auto')
        ON CONFLICT (user_id) DO UPDATE SET
            stored_points = CASE WHEN TG_OP = 'UPDATE' THEN OLD.points ELSE v_original_points END,
            recalculated_points = v_recalculated_points, points_difference = v_difference, severity = v_severity, status = 'corrige_auto', detected_at = now();
            
        RAISE WARNING '[SECURITY_ALERT] Anomalie de points utilisateur détectée et CORRIGÉE - User: %', NEW.id;
    END IF;
    
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.auto_activate_poll_on_time()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.is_active = false 
     AND NEW.starts_at IS NOT NULL 
     AND NEW.ends_at IS NOT NULL
     AND NEW.starts_at <= now() 
     AND NEW.ends_at > now() THEN
    NEW.is_active := true;
    RAISE NOTICE '[auto_activate_poll] Sondage % activé automatiquement', NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trigger_send_activation_notification()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_url text;
  v_key text;
  v_entity_type text;
  v_entity_id uuid;
  v_request_id bigint;
BEGIN
  IF TG_TABLE_NAME = 'promotions' THEN
    v_entity_type := 'promotion';
    v_entity_id := NEW.id;
    IF NEW.start_date IS NULL OR NEW.end_date IS NULL OR NEW.start_date > now() OR NEW.end_date <= now() THEN RETURN NEW; END IF;
  ELSIF TG_TABLE_NAME = 'polls' THEN
    v_entity_type := 'poll';
    v_entity_id := NEW.id;
    IF NEW.is_active IS NOT TRUE OR NEW.starts_at IS NULL OR NEW.ends_at IS NULL OR NEW.starts_at > now() OR NEW.ends_at <= now() THEN RETURN NEW; END IF;
  ELSE
    RETURN NEW;
  END IF;

  IF EXISTS (SELECT 1 FROM public.entity_activation_notifications WHERE entity_type = v_entity_type AND entity_id = v_entity_id) THEN
    RETURN NEW;
  END IF;

  BEGIN
    SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'activation_notifications_project_url' LIMIT 1;
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'activation_notifications_service_role_key' LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
  END;

  IF v_url IS NOT NULL AND trim(v_url) != '' AND v_key IS NOT NULL AND trim(v_key) != '' THEN
    BEGIN
      SELECT net.http_post(
        url := trim(v_url) || '/functions/v1/send-activation-notifications',
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || trim(v_key)),
        body := '{}'::jsonb
      ) INTO v_request_id;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '[trigger] Erreur HTTP: %', SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.tr_validate_and_log_users()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_changed_fields text[] := ARRAY[]::text[];
    v_old_data jsonb;
    v_new_data jsonb;
BEGIN
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.email IS DISTINCT FROM OLD.email) THEN
        NEW.email := private.validate_user_field('email', NEW.email, TG_OP);
    END IF;

    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.name IS DISTINCT FROM OLD.name) THEN
        IF NEW.name IS NOT NULL THEN NEW.name := private.validate_user_field('name', NEW.name, TG_OP); END IF;
    END IF;

    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.avatar_url IS DISTINCT FROM OLD.avatar_url) THEN
        IF NEW.avatar_url IS NOT NULL THEN NEW.avatar_url := private.validate_user_field('avatar_url', NEW.avatar_url, TG_OP); END IF;
    END IF;

    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.notification_settings IS DISTINCT FROM OLD.notification_settings) THEN
        IF NEW.notification_settings IS NOT NULL THEN NEW.notification_settings := private.validate_notification_settings(NEW.notification_settings); END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW.role IS NULL THEN NEW.role := 'utilisateur'::public.user_role; END IF;
    ELSIF TG_OP = 'UPDATE' AND NEW.role IS DISTINCT FROM OLD.role THEN
        BEGIN
            PERFORM NEW.role::text::public.user_role;
        EXCEPTION WHEN invalid_text_representation THEN
            RAISE EXCEPTION 'Rôle invalide: %', NEW.role;
        END;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW.points IS NULL THEN NEW.points := 0; ELSIF NEW.points < 0 OR NEW.points > 100000 THEN RAISE EXCEPTION 'Points invalides'; END IF;
    ELSIF TG_OP = 'UPDATE' AND NEW.points IS DISTINCT FROM OLD.points THEN
        IF NEW.points < 0 OR NEW.points > 100000 THEN RAISE EXCEPTION 'Points invalides'; END IF;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF NEW.role IS DISTINCT FROM OLD.role THEN v_changed_fields := array_append(v_changed_fields, 'role'); END IF;
        IF NEW.is_active IS DISTINCT FROM OLD.is_active THEN v_changed_fields := array_append(v_changed_fields, 'is_active'); END IF;
        IF ABS(COALESCE(NEW.points, 0) - COALESCE(OLD.points, 0)) > 100 THEN v_changed_fields := array_append(v_changed_fields, 'points'); END IF;

        IF array_length(v_changed_fields, 1) > 0 THEN
            v_old_data := jsonb_build_object('role', OLD.role, 'is_active', OLD.is_active, 'points', OLD.points);
            v_new_data := jsonb_build_object('role', NEW.role, 'is_active', NEW.is_active, 'points', NEW.points);
            PERFORM private.log_user_security_event('UPDATE', NEW.id, v_old_data, v_new_data, v_changed_fields);
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- ============================================================================
-- 4. TABLES, VUES ET TRIGGERS
-- ============================================================================

create table public.activation_notification_config (
  entity_type text not null,
  entity_id uuid not null,
  title text not null,
  body text not null,
  created_at timestamp with time zone not null default now(),
  constraint activation_notification_config_pkey primary key (entity_type, entity_id),
  constraint activation_notification_config_entity_type_check check (
    (
      entity_type = any (array['promotion'::text, 'poll'::text])
    )
  )
) TABLESPACE pg_default;

create table public.entity_activation_notifications (
  id uuid not null default gen_random_uuid (),
  entity_type text not null,
  entity_id uuid not null,
  sent_at timestamp with time zone not null default now(),
  constraint entity_activation_notifications_pkey primary key (id),
  constraint entity_activation_notifications_entity_type_entity_id_key unique (entity_type, entity_id),
  constraint entity_activation_notifications_entity_type_check check (
    (
      entity_type = any (array['promotion'::text, 'poll'::text])
    )
  )
) TABLESPACE pg_default;

create table public.notification_action_settings (
  action_id text not null,
  enabled boolean not null default true,
  updated_at timestamp with time zone not null default now(),
  constraint notification_action_settings_pkey primary key (action_id)
) TABLESPACE pg_default;

create table public.section_visibility (
  id uuid not null default gen_random_uuid (),
  section public.section_id not null,
  visible_for text[] null default '{administrateur,superadmin}'::text[],
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  updated_by uuid null,
  constraint section_visibility_pkey primary key (id),
  constraint section_visibility_updated_by_fkey foreign KEY (updated_by) references auth.users (id)
) TABLESPACE pg_default;

create unique INDEX IF not exists section_visibility_section_key on public.section_visibility using btree (section) TABLESPACE pg_default;
create index IF not exists idx_section_visibility_updated_by on public.section_visibility using btree (updated_by) TABLESPACE pg_default;

create trigger update_section_visibility_updated_at BEFORE
update on section_visibility for EACH row
execute FUNCTION update_updated_at_column ();

create table private.faq (
  id uuid not null default gen_random_uuid (),
  question text not null,
  answer text not null,
  language text not null default 'fr'::text,
  category text not null default 'general'::text,
  constraint faq_pkey primary key (id)
) TABLESPACE pg_default;

create materialized view public.mv_faq as
select
  question,
  answer,
  language,
  category
from
  private.faq;

create table private.errors (
  id uuid not null default gen_random_uuid (),
  message text not null,
  stack text null,
  context text null,
  user_id uuid null,
  route text null,
  timestamp timestamp with time zone not null default now(),
  constraint errors_pkey primary key (id)
) TABLESPACE pg_default;

create table private.disposable_emails (
  domain text not null,
  created_at timestamp with time zone null default now(),
  constraint disposable_emails_pkey primary key (domain)
) TABLESPACE pg_default;

create table private.articles_categories (
  id bigint generated by default as identity not null,
  categories text null,
  constraint article_categorie_pkey primary key (id)
) TABLESPACE pg_default;

create table private.articles (
  id uuid not null default gen_random_uuid (),
  name text not null,
  calories integer null,
  points integer not null,
  image text not null,
  price numeric(10, 2) null,
  category text null,
  isbestseller boolean not null default false,
  islowco2 boolean not null default false,
  badges text[] GENERATED ALWAYS as (
    array_remove(
      array[
        case
          when isbestseller then 'Best-seller'::text
          else null::text
        end,
        case
          when islowco2 then 'Low CO2'::text
          else null::text
        end
      ],
      null::text
    )
  ) STORED,
  allergens text[] null,
  description text null,
  co2_ranking text null,
  is_ecogeste boolean not null default false,
  restaurant_ids uuid[] null,
  categorie text null,
  constraint articles_pkey primary key (id)
) TABLESPACE pg_default;

create table private.feedback (
  id uuid not null default gen_random_uuid (),
  user_id uuid null,
  category text not null,
  comments text not null,
  created_at timestamp with time zone null default now(),
  constraint feedback_pkey primary key (id)
) TABLESPACE pg_default;

create table private.notification_tokens (
  id uuid not null default gen_random_uuid (),
  user_id uuid not null,
  notification_token text not null,
  device_type text not null,
  last_seen timestamp with time zone null default now(),
  created_at timestamp with time zone null default now(),
  constraint notification_tokens_v2_pkey primary key (id),
  constraint notification_tokens_v2_notification_token_key unique (notification_token),
  constraint notification_tokens_v2_user_id_fkey foreign KEY (user_id) references auth.users (id) on delete CASCADE,
  constraint notification_tokens_v2_device_type_check check (
    (
      device_type = any (array['ios'::text, 'android'::text])
    )
  )
) TABLESPACE pg_default;

create index IF not exists idx_notification_tokens_user_id on private.notification_tokens using btree (user_id) TABLESPACE pg_default;

create table private.offers (
  id uuid not null default extensions.uuid_generate_v4 (),
  title text not null,
  description text null,
  expiry_date timestamp with time zone null,
  is_premium boolean null default false,
  image text null,
  points integer null,
  is_active boolean not null default true,
  restaurant_ids uuid[] not null default array[]::uuid[],
  context_tags text[] null default '{}'::text[],
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  constraint offers_pkey primary key (id)
) TABLESPACE pg_default;

create trigger trg_refresh_mv_offers
after INSERT
or DELETE
or update on private.offers for EACH STATEMENT
execute FUNCTION mv.refresh_mv_offers ();

create table private.polls (
  id uuid not null default gen_random_uuid (),
  title text not null,
  description text null,
  question text not null,
  target_audience jsonb null default '{}'::jsonb,
  starts_at timestamp with time zone not null,
  ends_at timestamp with time zone not null,
  is_active boolean not null default true,
  image_url text null,
  notif_sent boolean not null default false,
  constraint polls_pkey primary key (id)
) TABLESPACE pg_default;

create table private.poll_options (
  id uuid not null default gen_random_uuid (),
  poll_id uuid not null,
  option_text text not null,
  option_order integer not null,
  constraint poll_options_pkey primary key (id),
  constraint poll_options_poll_id_fkey foreign KEY (poll_id) references private.polls (id) on delete CASCADE
) TABLESPACE pg_default;

create index IF not exists idx_poll_options_poll_id on private.poll_options using btree (poll_id) TABLESPACE pg_default;

create table private.users (
  id uuid not null default auth.uid (),
  email text not null,
  name text null,
  avatar_url text null,
  points integer null default 0,
  role public.user_role null default 'utilisateur'::user_role,
  is_active boolean null default true,
  notification_settings jsonb null default '{"horaires": true, "sondages": true, "promotions": true, "recompenses": true, "systemUpdates": true, "newRestaurants": true, "asapAnnouncements": true}'::jsonb,
  created_at timestamp with time zone null,
  last_activation_email_sent timestamp with time zone null,
  constraint users_pkey primary key (id),
  constraint users_email_key unique (email),
  constraint valid_name_for_new_users check (
    (
      (role <> 'utilisateur'::user_role)
      or (name is null)
      or (length(TRIM(both from name)) = 0)
      or ((length(TRIM(both from name)) >= 2) and (length(TRIM(both from name)) <= 100))
    )
  ),
  constraint valid_points_for_all check (
    (points >= 0) and (points <= 10000)
  )
) TABLESPACE pg_default;

create table private.poll_votes (
  id uuid not null default gen_random_uuid (),
  poll_id uuid not null,
  option_id uuid not null,
  user_id uuid not null,
  constraint poll_votes_pkey primary key (id),
  constraint unique_vote_per_user_per_poll unique (poll_id, user_id),
  constraint poll_votes_option_id_fkey foreign KEY (option_id) references private.poll_options (id) on delete CASCADE,
  constraint poll_votes_poll_id_fkey foreign KEY (poll_id) references private.polls (id) on delete CASCADE,
  constraint poll_votes_user_id_fkey foreign KEY (user_id) references private.users (id) on delete CASCADE
) TABLESPACE pg_default;

create index IF not exists idx_poll_votes_option_id on private.poll_votes using btree (option_id) TABLESPACE pg_default;
create index IF not exists idx_poll_votes_user_id on private.poll_votes using btree (user_id) TABLESPACE pg_default;

create trigger trigger_auto_activate_poll_insert BEFORE INSERT on private.polls for EACH row when (
  new.starts_at is not null
  and new.ends_at is not null
  and new.starts_at <= now()
  and new.ends_at > now()
  and new.is_active = false
)
execute FUNCTION auto_activate_poll_on_time ();

create trigger trigger_auto_activate_poll_update BEFORE
update OF starts_at, ends_at, is_active on private.polls for EACH row when (
  new.starts_at is not null
  and new.ends_at is not null
  and new.starts_at <= now()
  and new.ends_at > now()
  and new.is_active = false
  and (old.is_active = false or old.starts_at > now())
)
execute FUNCTION auto_activate_poll_on_time ();

create trigger trigger_poll_activation_notification_insert
after INSERT on private.polls for EACH row when (
  new.is_active = true
  and new.starts_at is not null
  and new.ends_at is not null
  and new.starts_at <= now()
  and new.ends_at > now()
)
execute FUNCTION trigger_send_activation_notification ();

create trigger trigger_poll_activation_notification_update
after update OF is_active, starts_at, ends_at on private.polls for EACH row when (
  new.is_active = true
  and new.starts_at is not null
  and new.ends_at is not null
  and new.starts_at <= now()
  and new.ends_at > now()
  and (
    old.is_active = false
    or old.starts_at is null
    or old.ends_at is null
    or old.starts_at > now()
    or old.ends_at <= now()
  )
)
execute FUNCTION trigger_send_activation_notification ();

create table private.promotions (
  id uuid not null default gen_random_uuid (),
  title text not null,
  description text null,
  image_url text null,
  start_date timestamp with time zone not null,
  end_date timestamp with time zone not null,
  color character varying(7) null default '#FF8A65'::character varying,
  notif_sent boolean not null default false,
  constraint promotions_pkey primary key (id)
) TABLESPACE pg_default;

create trigger trigger_promotion_activation_notification_insert
after INSERT on private.promotions for EACH row when (
  new.start_date is not null
  and new.end_date is not null
  and new.start_date <= now()
  and new.end_date > now()
)
execute FUNCTION trigger_send_activation_notification ();

create trigger trigger_promotion_activation_notification_update
after update OF start_date, end_date on private.promotions for EACH row when (
  new.start_date is not null
  and new.end_date is not null
  and new.start_date <= now()
  and new.end_date > now()
  and (
    old.start_date is null
    or old.end_date is null
    or old.start_date > now()
    or old.end_date <= now()
  )
)
execute FUNCTION trigger_send_activation_notification ();

create table private.restaurants (
  id uuid not null default extensions.uuid_generate_v4 (),
  name text not null,
  description text null,
  image_url text null,
  location text null,
  is_new boolean null default false,
  boosted boolean null default false,
  schedule jsonb null,
  special_hours jsonb null,
  categories text[] null,
  status text null default ''::text,
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null,
  restaurant_menu_url text null,
  restaurant_menu_url_jsonb jsonb null default '[]'::jsonb,
  constraint restaurants_pkey primary key (id),
  constraint restaurants_name_key unique (name)
) TABLESPACE pg_default;

create trigger on_restaurants_update BEFORE
update on private.restaurants for EACH row
execute FUNCTION private.set_updated_at ();

create trigger sync_restaurant_menu_url_trigger BEFORE INSERT
or update OF restaurant_menu_url_jsonb on private.restaurants for EACH row
execute FUNCTION private.trg_sync_restaurant_menu_url ();

create trigger trg_refresh_mv_restaurants
after INSERT
or DELETE
or update on private.restaurants for EACH STATEMENT
execute FUNCTION mv.refresh_mv_restaurants ();

create table private.transactions (
  id uuid not null default extensions.uuid_generate_v4 (),
  user_id uuid not null,
  date timestamp with time zone not null default timezone ('utc'::text, now()),
  restaurant_id uuid null,
  items jsonb null,
  total numeric null,
  points integer null,
  status text not null default 'en_attente'::text,
  calories integer null,
  used_offers text[] null default '{}'::text[],
  cash_register_id uuid null,
  constraint transactions_pkey primary key (id),
  constraint transactions_restaurant_id_fkey foreign KEY (restaurant_id) references private.restaurants (id),
  constraint transactions_user_id_fkey foreign KEY (user_id) references private.users (id) on delete CASCADE,
  constraint check_used_offers_is_array check (
    ((used_offers is null) or (array_length(used_offers, 1) >= 0))
  )
) TABLESPACE pg_default;

create index IF not exists idx_transactions_restaurant_id on private.transactions using btree (restaurant_id) TABLESPACE pg_default;
create index IF not exists idx_transactions_user_id on private.transactions using btree (user_id) TABLESPACE pg_default;

create trigger block_direct_points_modification BEFORE
update OF points on private.transactions for EACH row when (new.points is distinct from old.points)
execute FUNCTION private.check_points_modification_allowed ();

create trigger recalculate_user_points_on_transaction_insert
after INSERT on private.transactions for EACH row when (new.status = 'valide'::text)
execute FUNCTION audit.recalculate_user_points_on_transaction_change ();

create trigger recalculate_user_points_on_transaction_update
after update OF status on private.transactions for EACH row when (
  new.status = 'valide'::text or old.status = 'valide'::text
)
execute FUNCTION audit.recalculate_user_points_on_transaction_change ();

create trigger verify_transaction_points_trigger_insert BEFORE INSERT on private.transactions for EACH row when (new.status = 'valide'::text)
execute FUNCTION audit.verify_transaction_points_trigger ();

create trigger verify_transaction_points_trigger_update BEFORE
update OF points, items, used_offers, status on private.transactions for EACH row when (
  new.status = 'valide'::text or old.status = 'valide'::text
)
execute FUNCTION audit.verify_transaction_points_trigger ();

create trigger tr_validate_and_log_users BEFORE INSERT
or update on private.users for EACH row
execute FUNCTION private.tr_validate_and_log_users ();

create trigger verify_user_points_trigger_update BEFORE
update OF points on private.users for EACH row when (new.points is distinct from old.points)
execute FUNCTION audit.verify_user_points_trigger ();

create view view.view_polls as
with
  user_votes as (
    select
      v_1.poll_id,
      o_1.option_text
    from
      private.poll_votes v_1
      join private.poll_options o_1 on o_1.id = v_1.option_id
    where
      v_1.user_id = auth.uid ()
  )
select
  p.title,
  p.description,
  p.question,
  p.ends_at,
  p.image_url,
  json_agg(
    json_build_object('option_text', o.option_text)
    order by o.option_order
  ) as options,
  count(distinct v.id) as total_votes,
  uv.poll_id is not null as has_participated,
  uv.option_text as user_vote_option
from
  private.polls p
  left join private.poll_options o on o.poll_id = p.id
  left join private.poll_votes v on v.poll_id = p.id
  left join user_votes uv on uv.poll_id = p.id
where
  p.is_active = true
  and now() >= p.starts_at
  and now() <= p.ends_at
group by
  p.title, p.description, p.question, p.ends_at, p.image_url, uv.poll_id, uv.option_text
order by
  p.title;

create view view.view_promotions as
select
  title, description, image_url, color
from private.promotions
where start_date <= now() and end_date >= now();

create materialized view mv.mv_offers as
select
  title, description, image, points, is_premium,
  (select jsonb_agg(r.name) as jsonb_agg from private.restaurants r where r.id = any (o.restaurant_ids)) as restaurant_names
from private.offers o
where is_active = true and (expiry_date is null or expiry_date > now())
order by points;

create materialized view mv.mv_restaurants as
with
  today_schedule as (
    select
      r.name, r.image_url, r.location, r.restaurant_menu_url, r.is_new, r.boosted, r.schedule, r.special_hours, r.categories, r.status,
      (EXTRACT(dow from CURRENT_DATE)::integer + 6) % 7 as today_idx,
      special_today.value as special_today
    from
      private.restaurants r
      left join lateral (
        select element.value from jsonb_array_elements(COALESCE(r.special_hours, '[]'::jsonb)) element (value)
        where (element.value ->> 'date'::text) = to_char(CURRENT_DATE::timestamp with time zone, 'YYYY-MM-DD'::text)
        limit 1
      ) special_today on true
  )
select
  name, image_url, location as text, restaurant_menu_url, special_hours, categories, status, boosted, is_new,
  case
    when special_today is not null then NULLIF(lower(special_today ->> 'open'::text), 'close'::text)
    else NULLIF(lower((schedule -> today_idx) ->> 'open'::text), 'close'::text)
  end as today_open,
  case
    when special_today is not null then NULLIF(lower(special_today ->> 'close'::text), 'close'::text)
    else NULLIF(lower((schedule -> today_idx) ->> 'close'::text), 'close'::text)
  end as today_close
from today_schedule ts
order by
  (case when boosted then 0 when is_new then 1 else 2 end), name;

create view dashboard_view.today_stats as
with
  today_base as (
    select (now() AT TIME ZONE 'UTC'::text)::date as day
  ),
  today_transactions as (
    select
      count(*) filter (where (t.status = any (array['valide'::text, 'completed'::text])) and t.date >= date_trunc('day'::text, (now() AT TIME ZONE 'UTC'::text)) and t.date < (date_trunc('day'::text, (now() AT TIME ZONE 'UTC'::text)) + '1 day'::interval)) as transactions_today,
      count(distinct t.user_id) filter (where (t.status = any (array['valide'::text, 'completed'::text])) and t.date >= date_trunc('day'::text, (now() AT TIME ZONE 'UTC'::text)) and t.date < (date_trunc('day'::text, (now() AT TIME ZONE 'UTC'::text)) + '1 day'::interval)) as clients_today,
      COALESCE(sum(case when (t.status = any (array['valide'::text, 'completed'::text])) and t.date >= date_trunc('day'::text, (now() AT TIME ZONE 'UTC'::text)) and t.date < (date_trunc('day'::text, (now() AT TIME ZONE 'UTC'::text)) + '1 day'::interval) and t.points > 0 then t.points else 0 end), 0::bigint) as points_generated_today
    from private.transactions t
  )
select tb.day, COALESCE(tt.transactions_today, 0::bigint) as transactions_today, COALESCE(tt.clients_today, 0::bigint) as clients_today, COALESCE(tt.points_generated_today, 0::bigint) as points_generated_today
from today_base tb cross join today_transactions tt;

create view dashboard_view.restaurants as
select id, name, description, image_url, location, schedule, special_hours, categories, is_new, boosted, status, created_at, updated_at
from private.restaurants r;

create view dashboard_view.promotions as
select id, title, description, image_url, start_date, end_date, color,
  case
    when start_date is null and end_date is null then true
    when start_date is null and end_date > now() then true
    when end_date is null and start_date <= now() then true
    when start_date <= now() and end_date > now() then true
    else false
  end as is_active,
  case
    when start_date is null and end_date is null then 'active'::text
    when start_date is null and end_date > now() then 'active'::text
    when end_date is null and start_date <= now() then 'active'::text
    when start_date <= now() and end_date > now() then 'active'::text
    when start_date > now() then 'scheduled'::text
    when end_date <= now() then 'expired'::text
    else 'inactive'::text
  end as status
from private.promotions p;

create view dashboard_view.polls as
select id, question, description, is_active, starts_at, ends_at
from private.polls p
where is_active = true;

create view dashboard_view.offers_usage_by_period as
with
  offer_transactions as (
    select t.date::date as transaction_date, unnest(t.used_offers)::uuid as offer_id, t.user_id, t.restaurant_id, t.status
    from private.transactions t
    where (t.status = any (array['valide'::text, 'completed'::text])) and t.used_offers is not null and array_length(t.used_offers, 1) > 0
  ),
  aggregated_data as (
    select offer_transactions.transaction_date as day, date_trunc('month'::text, offer_transactions.transaction_date::timestamp with time zone)::date as month, date_trunc('year'::text, offer_transactions.transaction_date::timestamp with time zone)::date as year, offer_transactions.offer_id, count(*) as usage_count, count(distinct offer_transactions.user_id) as unique_users, count(distinct offer_transactions.restaurant_id) as unique_restaurants
    from offer_transactions
    group by offer_transactions.transaction_date, offer_transactions.offer_id
  )
select a.day, a.month, a.year, a.offer_id, o.title as offer_title, o.is_active as offer_is_active, o.is_premium as offer_is_premium, o.points as offer_points, a.usage_count, a.unique_users, a.unique_restaurants, sum(a.usage_count) over (partition by a.offer_id, a.month) as usage_count_monthly, sum(a.unique_users) over (partition by a.offer_id, a.month) as unique_users_monthly, sum(a.usage_count) over (partition by a.offer_id, a.year) as usage_count_yearly, sum(a.unique_users) over (partition by a.offer_id, a.year) as unique_users_yearly
from aggregated_data a left join private.offers o on a.offer_id = o.id
order by a.day desc, a.usage_count desc;

create view dashboard_view.offers as
select id, title, description, image, points, expiry_date, is_active, is_premium, restaurant_ids, context_tags, created_at, updated_at,
  case when expiry_date is not null and expiry_date < now() then 'expired'::text when is_active = false then 'inactive'::text else 'active'::text end as status
from private.offers o
where is_active = true or is_active = false;

create view dashboard_view.offer_usage_stats as
select offer_id.offer_id::uuid as offer_id, count(*) as usage_count
from private.transactions t, lateral unnest(t.used_offers) offer_id (offer_id)
where (t.status = any (array['valide'::text, 'completed'::text])) and t.used_offers is not null and array_length(t.used_offers, 1) > 0
group by (offer_id.offer_id::uuid) order by (count(*)) desc;

create view dashboard_view.non_members as
select id, email, name, is_active, created_at
from private.users u
where is_active = true and role <> 'membre'::user_role and (role <> all (array['administrateur'::user_role, 'superadmin'::user_role, 'marketing'::user_role, 'caissier'::user_role]));

create view dashboard_view.members as
select id, email, name, role, avatar_url, is_active, points, notification_settings, created_at
from private.users u
where is_active = true and role = 'membre'::user_role;

create view dashboard_view.eco_gestes_usage_by_period as
with
  transactions_with_items as (
    select t.date::date as transaction_date, t.user_id, t.restaurant_id, t.status, t.items::text::jsonb as items_json
    from private.transactions t
    where t.items is not null and (t.status = any (array['valide'::text, 'completed'::text]))
  ),
  eco_geste_transactions as (
    select t.transaction_date, t.user_id, t.restaurant_id, item.value ->> 'id'::text as eco_geste_id, COALESCE((item.value ->> 'qty'::text)::integer, 1) as quantity
    from transactions_with_items t, lateral jsonb_array_elements(t.items_json) item (value)
    where (item.value ->> 'type'::text) = 'ecogeste'::text
  ),
  aggregated_data as (
    select eco_geste_transactions.transaction_date as day, date_trunc('month'::text, eco_geste_transactions.transaction_date::timestamp with time zone)::date as month, date_trunc('year'::text, eco_geste_transactions.transaction_date::timestamp with time zone)::date as year, eco_geste_transactions.eco_geste_id, count(*) as usage_count, sum(eco_geste_transactions.quantity) as total_quantity, count(distinct eco_geste_transactions.user_id) as unique_users, count(distinct eco_geste_transactions.restaurant_id) as unique_restaurants
    from eco_geste_transactions
    group by eco_geste_transactions.transaction_date, eco_geste_transactions.eco_geste_id
  )
select a.day, a.month, a.year, a.eco_geste_id as eco_geste_name, art.name as article_name, art.category as article_category, art.points as article_points, art.is_ecogeste, art.islowco2 as is_low_co2, a.usage_count, a.total_quantity, a.unique_users, a.unique_restaurants, sum(a.usage_count) over (partition by a.eco_geste_id, a.month) as usage_count_monthly, sum(a.total_quantity) over (partition by a.eco_geste_id, a.month) as total_quantity_monthly, sum(a.unique_users) over (partition by a.eco_geste_id, a.month) as unique_users_monthly, sum(a.usage_count) over (partition by a.eco_geste_id, a.year) as usage_count_yearly, sum(a.total_quantity) over (partition by a.eco_geste_id, a.year) as total_quantity_yearly, sum(a.unique_users) over (partition by a.eco_geste_id, a.year) as unique_users_yearly
from aggregated_data a left join private.articles art on a.eco_geste_id = art.name
order by a.day desc, a.usage_count desc;

create view dashboard_view.daily_stats as
with
  daily_connexions_sessions as (
    select s.created_at::date as day, count(distinct s.user_id) as active_users_sessions
    from auth.sessions s where s.created_at is not null group by (s.created_at::date)
  ),
  daily_connexions_tx as (
    select t.date::date as day, count(distinct t.user_id) as active_users_tx
    from private.transactions t where t.status = any (array['valide'::text, 'completed'::text]) group by (t.date::date)
  ),
  daily_tx as (
    select t.date::date as day, count(*) as transactions_count, COALESCE(sum(case when t.points > 0 then t.points else 0 end), 0::bigint) as points_generated, COALESCE(sum(case when t.points < 0 then - t.points else 0 end), 0::bigint) as points_spent
    from private.transactions t where t.status = any (array['valide'::text, 'completed'::text]) group by (t.date::date)
  )
select COALESCE(COALESCE(c_s.day, c_tx.day), x.day_1) as day, COALESCE(x.transactions_count, 0::bigint) as transactions_count, GREATEST(COALESCE(c_s.active_users_sessions, 0::bigint), COALESCE(c_tx.active_users_tx, 0::bigint)) as active_users, COALESCE(x.points_generated, 0::bigint) as points_generated, COALESCE(x.points_spent, 0::bigint) as points_spent
from daily_connexions_sessions c_s full join daily_connexions_tx c_tx using (day) full join daily_tx x (day_1, transactions_count, points_generated, points_spent) on COALESCE(c_s.day, c_tx.day) = x.day_1
order by (COALESCE(COALESCE(c_s.day, c_tx.day), x.day_1)) desc;

create view dashboard_view.articles as
select id, name, calories, points, image, price, category, isbestseller, islowco2, badges, allergens, description, co2_ranking, is_ecogeste, restaurant_ids
from private.articles a;

create table audit.transaction_points_anomalies (
  id uuid not null default gen_random_uuid (),
  transaction_id uuid not null,
  user_id uuid not null,
  detected_at timestamp with time zone not null default now(),
  stored_points integer not null,
  recalculated_points integer not null,
  points_difference integer not null,
  severity text not null,
  status text not null default 'a_verifier'::text,
  constraint transaction_points_anomalies_pkey primary key (id),
  constraint transaction_points_anomalies_transaction_id_key unique (transaction_id),
  constraint transaction_points_anomalies_severity_check check (severity = any (array['medium'::text, 'high'::text, 'critical'::text])),
  constraint transaction_points_anomalies_status_check check (status = any (array['a_verifier'::text, 'corrige_auto'::text, 'corrige_manuel'::text, 'ignore'::text]))
) TABLESPACE pg_default;

create table audit.user_points_anomalies (
  id uuid not null default gen_random_uuid (),
  user_id uuid not null,
  detected_at timestamp with time zone not null default now(),
  stored_points integer not null,
  recalculated_points integer not null,
  points_difference integer not null,
  severity text not null,
  status text not null default 'a_verifier'::text,
  constraint user_points_anomalies_pkey primary key (id),
  constraint user_points_anomalies_severity_check check (severity = any (array['medium'::text, 'high'::text, 'critical'::text])),
  constraint user_points_anomalies_status_check check (status = any (array['a_verifier'::text, 'corrige_auto'::text, 'corrige_manuel'::text, 'ignore'::text]))
) TABLESPACE pg_default;

create unique INDEX IF not exists idx_audit_user_points_user_id_unique on audit.user_points_anomalies using btree (user_id) TABLESPACE pg_default;
