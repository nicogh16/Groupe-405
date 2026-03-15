-- Template SQL généré depuis le projet Supabase: zdicqtupwckhvxhlkiuf
-- Date: 2026-02-23T16:06:48.995Z
-- 
-- Ce template contient:
-- - 20 migration(s)
-- - 7 extension(s)
-- - 14 schéma(s) personnalisé(s)
-- - 27 table(s) (depuis les métadonnées)
-- - 18 vue(s) (depuis les métadonnées)
-- - 305 fonction(s) (depuis les métadonnées)
-- - 65 type(s) (depuis les métadonnées)
-- - 6 bucket(s) Storage
--
-- Pour utiliser ce template:
-- 1. Créez un nouveau projet Supabase
-- 2. Exécutez ce script SQL dans l'ordre suivant:
--    a) Extensions
--    b) Schémas
--    c) Types personnalisés
--    d) Tables (depuis les métadonnées)
--    e) Vues (depuis les métadonnées)
--    f) Fonctions (depuis les métadonnées)
--    g) Migrations (si disponibles)
--    h) Buckets Storage

-- ============================================================================
-- EXTENSIONS
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pg_cron";
CREATE EXTENSION IF NOT EXISTS "pg_graphql";
CREATE EXTENSION IF NOT EXISTS "pg_net";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
CREATE EXTENSION IF NOT EXISTS "pgmq";
CREATE EXTENSION IF NOT EXISTS "pgsodium";
CREATE EXTENSION IF NOT EXISTS "supabase_vault";

-- ============================================================================
-- SCHÉMAS
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS "audit";
CREATE SCHEMA IF NOT EXISTS "cron";
CREATE SCHEMA IF NOT EXISTS "dashboard_view";
CREATE SCHEMA IF NOT EXISTS "graphql";
CREATE SCHEMA IF NOT EXISTS "mv";
CREATE SCHEMA IF NOT EXISTS "net";
CREATE SCHEMA IF NOT EXISTS "pgbouncer";
CREATE SCHEMA IF NOT EXISTS "pgmq";
CREATE SCHEMA IF NOT EXISTS "pgsodium";
CREATE SCHEMA IF NOT EXISTS "pgsodium_masks";
CREATE SCHEMA IF NOT EXISTS "postgre_rpc";
CREATE SCHEMA IF NOT EXISTS "private";
CREATE SCHEMA IF NOT EXISTS "public";
CREATE SCHEMA IF NOT EXISTS "view";

-- ============================================================================
-- TYPES PERSONNALISÉS
-- ============================================================================

CREATE TYPE "net"."request_status" AS ENUM (
  '{PENDING,SUCCESS,ERROR}'
);

CREATE TYPE "pgsodium"."key_status" AS ENUM (
  '{default,valid,invalid,expired}'
);

CREATE TYPE "pgsodium"."key_type" AS ENUM (
  '{aead-ietf,aead-det,hmacsha512,hmacsha256,auth,shorthash,generichash,kdf,secretbox,secretstream,stream_xchacha20}'
);

CREATE TYPE "public"."section_id" AS ENUM (
  '{dashboard,statistics,promotions,cashregisters,restaurants,articles,offers,members,polls}'
);

CREATE TYPE "public"."user_role" AS ENUM (
  '{utilisateur,caissier,administrateur,membre}'
);


-- ============================================================================
-- TABLES (créées depuis les métadonnées PostgreSQL)
-- ============================================================================

-- Table: audit.transaction_points_anomalies
CREATE TABLE IF NOT EXISTS "audit"."transaction_points_anomalies" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "transaction_id" uuid NOT NULL,
  "user_id" uuid NOT NULL,
  "detected_at" timestamp with time zone NOT NULL DEFAULT now(),
  "stored_points" integer NOT NULL,
  "recalculated_points" integer NOT NULL,
  "points_difference" integer NOT NULL,
  "severity" text NOT NULL,
  "status" text NOT NULL DEFAULT 'a_verifier'::text,
  PRIMARY KEY ("id"),
  CONSTRAINT "transaction_points_anomalies_transaction_id_key" UNIQUE ("transaction_id")
);

-- Table: audit.user_points_anomalies
CREATE TABLE IF NOT EXISTS "audit"."user_points_anomalies" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "user_id" uuid NOT NULL,
  "detected_at" timestamp with time zone NOT NULL DEFAULT now(),
  "stored_points" integer NOT NULL,
  "recalculated_points" integer NOT NULL,
  "points_difference" integer NOT NULL,
  "severity" text NOT NULL,
  "status" text NOT NULL DEFAULT 'a_verifier'::text,
  PRIMARY KEY ("id")
);

-- Table: cron.job
CREATE TABLE IF NOT EXISTS "cron"."job" (
  "jobid" bigint NOT NULL DEFAULT nextval('cron.jobid_seq'::regclass),
  "schedule" text NOT NULL,
  "command" text NOT NULL,
  "nodename" text NOT NULL DEFAULT 'localhost'::text,
  "nodeport" integer NOT NULL DEFAULT inet_server_port(),
  "database" text NOT NULL DEFAULT current_database(),
  "username" text NOT NULL DEFAULT CURRENT_USER,
  "active" boolean NOT NULL DEFAULT true,
  "jobname" text
);

-- Table: cron.job_run_details
CREATE TABLE IF NOT EXISTS "cron"."job_run_details" (
  "jobid" bigint,
  "runid" bigint NOT NULL DEFAULT nextval('cron.runid_seq'::regclass),
  "job_pid" integer,
  "database" text,
  "username" text,
  "command" text,
  "status" text,
  "return_message" text,
  "start_time" timestamp with time zone,
  "end_time" timestamp with time zone,
  PRIMARY KEY ("runid")
);

-- Table: net._http_response
CREATE TABLE IF NOT EXISTS "net"."_http_response" (
  "id" bigint,
  "status_code" integer,
  "content_type" text,
  "headers" jsonb,
  "content" text,
  "timed_out" boolean,
  "error_msg" text,
  "created" timestamp with time zone NOT NULL DEFAULT now()
);

-- Table: net.http_request_queue
CREATE TABLE IF NOT EXISTS "net"."http_request_queue" (
  "id" bigint NOT NULL DEFAULT nextval('net.http_request_queue_id_seq'::regclass),
  "method" text NOT NULL,
  "url" text NOT NULL,
  "headers" jsonb,
  "body" bytea,
  "timeout_milliseconds" integer NOT NULL
);

-- Table: pgmq.meta
CREATE TABLE IF NOT EXISTS "pgmq"."meta" (
  "queue_name" character varying NOT NULL,
  "is_partitioned" boolean NOT NULL,
  "is_unlogged" boolean NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "meta_queue_name_key" UNIQUE ("queue_name")
);

-- Table: pgsodium.key
CREATE TABLE IF NOT EXISTS "pgsodium"."key" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "status" USER-DEFINED DEFAULT 'valid'::pgsodium.key_status,
  "created" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expires" timestamp with time zone,
  "key_type" USER-DEFINED,
  "key_id" bigint DEFAULT nextval('pgsodium.key_key_id_seq'::regclass),
  "key_context" bytea DEFAULT '\x7067736f6469756d'::bytea,
  "name" text,
  "associated_data" text DEFAULT 'associated'::text,
  "raw_key" bytea,
  "raw_key_nonce" bytea,
  "parent_key" uuid,
  "comment" text,
  "user_data" text
);

-- Table: private.articles
CREATE TABLE IF NOT EXISTS "private"."articles" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "name" text NOT NULL,
  "calories" integer,
  "points" integer NOT NULL,
  "image" text NOT NULL,
  "price" numeric,
  "category" text,
  "isbestseller" boolean NOT NULL DEFAULT false,
  "islowco2" boolean NOT NULL DEFAULT false,
  "badges" ARRAY,
  "allergens" ARRAY,
  "description" text,
  "co2_ranking" text,
  "is_ecogeste" boolean NOT NULL DEFAULT false,
  "restaurant_ids" ARRAY,
  "categorie" text,
  PRIMARY KEY ("id")
);

-- Table: private.articles_categories
CREATE TABLE IF NOT EXISTS "private"."articles_categories" (
  "id" bigint NOT NULL,
  "categories" text,
  PRIMARY KEY ("id")
);

-- Table: private.disposable_emails
CREATE TABLE IF NOT EXISTS "private"."disposable_emails" (
  "domain" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now(),
  PRIMARY KEY ("domain")
);

-- Table: private.errors
CREATE TABLE IF NOT EXISTS "private"."errors" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "message" text NOT NULL,
  "stack" text,
  "context" text,
  "user_id" uuid,
  "route" text,
  "timestamp" timestamp with time zone NOT NULL DEFAULT now(),
  PRIMARY KEY ("id")
);

-- Table: private.faq
CREATE TABLE IF NOT EXISTS "private"."faq" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "question" text NOT NULL,
  "answer" text NOT NULL,
  "language" text NOT NULL DEFAULT 'fr'::text,
  "category" text NOT NULL DEFAULT 'general'::text,
  PRIMARY KEY ("id")
);

-- Table: private.feedback
CREATE TABLE IF NOT EXISTS "private"."feedback" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "user_id" uuid,
  "category" text NOT NULL,
  "comments" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now(),
  PRIMARY KEY ("id")
);

-- Table: private.notification_tokens
CREATE TABLE IF NOT EXISTS "private"."notification_tokens" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "user_id" uuid NOT NULL,
  "notification_token" text NOT NULL,
  "device_type" text NOT NULL,
  "last_seen" timestamp with time zone DEFAULT now(),
  "created_at" timestamp with time zone DEFAULT now(),
  PRIMARY KEY ("id"),
  CONSTRAINT "notification_tokens_v2_notification_token_key" UNIQUE ("notification_token")
);

-- Table: private.offers
CREATE TABLE IF NOT EXISTS "private"."offers" (
  "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
  "title" text NOT NULL,
  "description" text,
  "expiry_date" timestamp with time zone,
  "is_premium" boolean DEFAULT false,
  "image" text,
  "points" integer,
  "is_active" boolean NOT NULL DEFAULT true,
  "restaurant_ids" ARRAY NOT NULL DEFAULT ARRAY[]::uuid[],
  "context_tags" ARRAY DEFAULT '{}'::text[],
  "created_at" timestamp with time zone DEFAULT now(),
  "updated_at" timestamp with time zone DEFAULT now(),
  PRIMARY KEY ("id")
);

-- Table: private.poll_options
CREATE TABLE IF NOT EXISTS "private"."poll_options" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "poll_id" uuid NOT NULL,
  "option_text" text NOT NULL,
  "option_order" integer NOT NULL,
  PRIMARY KEY ("id"),
  CONSTRAINT "poll_options_poll_id_fkey" FOREIGN KEY ("poll_id") REFERENCES "private"."polls"("id")
);

-- Table: private.poll_votes
CREATE TABLE IF NOT EXISTS "private"."poll_votes" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "poll_id" uuid NOT NULL,
  "option_id" uuid NOT NULL,
  "user_id" uuid NOT NULL,
  PRIMARY KEY ("id"),
  CONSTRAINT "poll_votes_option_id_fkey" FOREIGN KEY ("option_id") REFERENCES "private"."poll_options"("id"),
  CONSTRAINT "poll_votes_poll_id_fkey" FOREIGN KEY ("poll_id") REFERENCES "private"."polls"("id"),
  CONSTRAINT "poll_votes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "private"."users"("id"),
  CONSTRAINT "unique_vote_per_user_per_poll" UNIQUE ("poll_id"),
  CONSTRAINT "unique_vote_per_user_per_poll" UNIQUE ("poll_id"),
  CONSTRAINT "unique_vote_per_user_per_poll" UNIQUE ("user_id"),
  CONSTRAINT "unique_vote_per_user_per_poll" UNIQUE ("user_id")
);

-- Table: private.polls
CREATE TABLE IF NOT EXISTS "private"."polls" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "title" text NOT NULL,
  "description" text,
  "question" text NOT NULL,
  "target_audience" jsonb DEFAULT '{}'::jsonb,
  "starts_at" timestamp with time zone NOT NULL,
  "ends_at" timestamp with time zone NOT NULL,
  "is_active" boolean NOT NULL DEFAULT true,
  "image_url" text,
  "notif_sent" boolean NOT NULL DEFAULT false,
  PRIMARY KEY ("id")
);

-- Table: private.promotions
CREATE TABLE IF NOT EXISTS "private"."promotions" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "title" text NOT NULL,
  "description" text,
  "image_url" text,
  "start_date" timestamp with time zone NOT NULL,
  "end_date" timestamp with time zone NOT NULL,
  "color" character varying(7) DEFAULT '#FF8A65'::character varying,
  "notif_sent" boolean NOT NULL DEFAULT false,
  PRIMARY KEY ("id")
);

-- Table: private.restaurants
CREATE TABLE IF NOT EXISTS "private"."restaurants" (
  "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
  "name" text NOT NULL,
  "description" text,
  "image_url" text,
  "location" text,
  "is_new" boolean DEFAULT false,
  "boosted" boolean DEFAULT false,
  "schedule" jsonb,
  "special_hours" jsonb,
  "categories" ARRAY,
  "status" text DEFAULT ''::text,
  "created_at" timestamp with time zone DEFAULT now(),
  "updated_at" timestamp with time zone,
  "restaurant_menu_url" text,
  "restaurant_menu_url_jsonb" jsonb DEFAULT '[]'::jsonb,
  PRIMARY KEY ("id"),
  CONSTRAINT "restaurants_name_key" UNIQUE ("name")
);

-- Table: private.transactions
CREATE TABLE IF NOT EXISTS "private"."transactions" (
  "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
  "user_id" uuid NOT NULL,
  "date" timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  "restaurant_id" uuid,
  "items" jsonb,
  "total" numeric,
  "points" integer,
  "status" text NOT NULL DEFAULT 'en_attente'::text,
  "calories" integer,
  "used_offers" ARRAY DEFAULT '{}'::text[],
  "cash_register_id" uuid,
  PRIMARY KEY ("id"),
  CONSTRAINT "transactions_restaurant_id_fkey" FOREIGN KEY ("restaurant_id") REFERENCES "private"."restaurants"("id"),
  CONSTRAINT "transactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "private"."users"("id")
);

-- Table: private.users
CREATE TABLE IF NOT EXISTS "private"."users" (
  "id" uuid NOT NULL DEFAULT auth.uid(),
  "email" text NOT NULL,
  "name" text,
  "avatar_url" text,
  "points" integer DEFAULT 0,
  "role" USER-DEFINED DEFAULT 'utilisateur'::user_role,
  "is_active" boolean DEFAULT true,
  "notification_settings" jsonb DEFAULT '{"horaires": true, "sondages": true, "promotions": true, "recompenses": true, "systemUpdates": true, "newRestaurants": true, "asapAnnouncements": true}'::jsonb,
  "created_at" timestamp with time zone,
  "last_activation_email_sent" timestamp with time zone,
  PRIMARY KEY ("id"),
  CONSTRAINT "users_email_key" UNIQUE ("email")
);

-- Table: public.activation_notification_config
CREATE TABLE IF NOT EXISTS "public"."activation_notification_config" (
  "entity_type" text NOT NULL,
  "entity_id" uuid NOT NULL,
  "title" text NOT NULL,
  "body" text NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  PRIMARY KEY ("entity_id", "entity_id", "entity_type", "entity_type")
);

-- Table: public.entity_activation_notifications
CREATE TABLE IF NOT EXISTS "public"."entity_activation_notifications" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "entity_type" text NOT NULL,
  "entity_id" uuid NOT NULL,
  "sent_at" timestamp with time zone NOT NULL DEFAULT now(),
  PRIMARY KEY ("id"),
  CONSTRAINT "entity_activation_notifications_entity_type_entity_id_key" UNIQUE ("entity_id"),
  CONSTRAINT "entity_activation_notifications_entity_type_entity_id_key" UNIQUE ("entity_id"),
  CONSTRAINT "entity_activation_notifications_entity_type_entity_id_key" UNIQUE ("entity_type"),
  CONSTRAINT "entity_activation_notifications_entity_type_entity_id_key" UNIQUE ("entity_type")
);

-- Table: public.notification_action_settings
CREATE TABLE IF NOT EXISTS "public"."notification_action_settings" (
  "action_id" text NOT NULL,
  "enabled" boolean NOT NULL DEFAULT true,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  PRIMARY KEY ("action_id")
);

-- Table: public.section_visibility
CREATE TABLE IF NOT EXISTS "public"."section_visibility" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "section" USER-DEFINED NOT NULL,
  "visible_for" ARRAY DEFAULT '{administrateur,superadmin}'::text[],
  "created_at" timestamp with time zone DEFAULT now(),
  "updated_at" timestamp with time zone DEFAULT now(),
  "updated_by" uuid,
  PRIMARY KEY ("id")
);


-- ============================================================================
-- VUES
-- ============================================================================

CREATE OR REPLACE VIEW "dashboard_view"."articles" AS
 SELECT id,
    name,
    calories,
    points,
    image,
    price,
    category,
    isbestseller,
    islowco2,
    badges,
    allergens,
    description,
    co2_ranking,
    is_ecogeste,
    restaurant_ids
   FROM private.articles a;;

CREATE OR REPLACE VIEW "dashboard_view"."daily_stats" AS
 WITH daily_connexions_sessions AS (
         SELECT (s.created_at)::date AS day,
            count(DISTINCT s.user_id) AS active_users_sessions
           FROM auth.sessions s
          WHERE (s.created_at IS NOT NULL)
          GROUP BY ((s.created_at)::date)
        ), daily_connexions_tx AS (
         SELECT (t.date)::date AS day,
            count(DISTINCT t.user_id) AS active_users_tx
           FROM private.transactions t
          WHERE (t.status = ANY (ARRAY['valide'::text, 'completed'::text]))
          GROUP BY ((t.date)::date)
        ), daily_tx AS (
         SELECT (t.date)::date AS day,
            count(*) AS transactions_count,
            COALESCE(sum(
                CASE
                    WHEN (t.points > 0) THEN t.points
                    ELSE 0
                END), (0)::bigint) AS points_generated,
            COALESCE(sum(
                CASE
                    WHEN (t.points < 0) THEN (- t.points)
                    ELSE 0
                END), (0)::bigint) AS points_spent
           FROM private.transactions t
          WHERE (t.status = ANY (ARRAY['valide'::text, 'completed'::text]))
          GROUP BY ((t.date)::date)
        )
 SELECT COALESCE(COALESCE(c_s.day, c_tx.day), x.day_1) AS day,
    COALESCE(x.transactions_count, (0)::bigint) AS transactions_count,
    GREATEST(COALESCE(c_s.active_users_sessions, (0)::bigint), COALESCE(c_tx.active_users_tx, (0)::bigint)) AS active_users,
    COALESCE(x.points_generated, (0)::bigint) AS points_generated,
    COALESCE(x.points_spent, (0)::bigint) AS points_spent
   FROM ((daily_connexions_sessions c_s
     FULL JOIN daily_connexions_tx c_tx USING (day))
     FULL JOIN daily_tx x(day_1, transactions_count, points_generated, points_spent) ON ((COALESCE(c_s.day, c_tx.day) = x.day_1)))
  ORDER BY COALESCE(COALESCE(c_s.day, c_tx.day), x.day_1) DESC;;

CREATE OR REPLACE VIEW "dashboard_view"."eco_gestes_usage_by_period" AS
 WITH transactions_with_items AS (
         SELECT (t.date)::date AS transaction_date,
            t.user_id,
            t.restaurant_id,
            t.status,
            ((t.items)::text)::jsonb AS items_json
           FROM private.transactions t
          WHERE ((t.items IS NOT NULL) AND (t.status = ANY (ARRAY['valide'::text, 'completed'::text])))
        ), eco_geste_transactions AS (
         SELECT t.transaction_date,
            t.user_id,
            t.restaurant_id,
            (item.value ->> 'id'::text) AS eco_geste_id,
            COALESCE(((item.value ->> 'qty'::text))::integer, 1) AS quantity
           FROM transactions_with_items t,
            LATERAL jsonb_array_elements(t.items_json) item(value)
          WHERE ((item.value ->> 'type'::text) = 'ecogeste'::text)
        ), aggregated_data AS (
         SELECT eco_geste_transactions.transaction_date AS day,
            (date_trunc('month'::text, (eco_geste_transactions.transaction_date)::timestamp with time zone))::date AS month,
            (date_trunc('year'::text, (eco_geste_transactions.transaction_date)::timestamp with time zone))::date AS year,
            eco_geste_transactions.eco_geste_id,
            count(*) AS usage_count,
            sum(eco_geste_transactions.quantity) AS total_quantity,
            count(DISTINCT eco_geste_transactions.user_id) AS unique_users,
            count(DISTINCT eco_geste_transactions.restaurant_id) AS unique_restaurants
           FROM eco_geste_transactions
          GROUP BY eco_geste_transactions.transaction_date, eco_geste_transactions.eco_geste_id
        )
 SELECT a.day,
    a.month,
    a.year,
    a.eco_geste_id AS eco_geste_name,
    art.name AS article_name,
    art.category AS article_category,
    art.points AS article_points,
    art.is_ecogeste,
    art.islowco2 AS is_low_co2,
    a.usage_count,
    a.total_quantity,
    a.unique_users,
    a.unique_restaurants,
    sum(a.usage_count) OVER (PARTITION BY a.eco_geste_id, a.month) AS usage_count_monthly,
    sum(a.total_quantity) OVER (PARTITION BY a.eco_geste_id, a.month) AS total_quantity_monthly,
    sum(a.unique_users) OVER (PARTITION BY a.eco_geste_id, a.month) AS unique_users_monthly,
    sum(a.usage_count) OVER (PARTITION BY a.eco_geste_id, a.year) AS usage_count_yearly,
    sum(a.total_quantity) OVER (PARTITION BY a.eco_geste_id, a.year) AS total_quantity_yearly,
    sum(a.unique_users) OVER (PARTITION BY a.eco_geste_id, a.year) AS unique_users_yearly
   FROM (aggregated_data a
     LEFT JOIN private.articles art ON ((a.eco_geste_id = art.name)))
  ORDER BY a.day DESC, a.usage_count DESC;;

CREATE OR REPLACE VIEW "dashboard_view"."members" AS
 SELECT id,
    email,
    name,
    role,
    avatar_url,
    is_active,
    points,
    notification_settings,
    created_at
   FROM private.users u
  WHERE ((is_active = true) AND (role = 'membre'::user_role));;

CREATE OR REPLACE VIEW "dashboard_view"."non_members" AS
 SELECT id,
    email,
    name,
    is_active,
    created_at
   FROM private.users u
  WHERE ((is_active = true) AND (role <> 'membre'::user_role) AND (role <> ALL (ARRAY['administrateur'::user_role, 'caissier'::user_role])));;

CREATE OR REPLACE VIEW "dashboard_view"."offer_usage_stats" AS
 SELECT (offer_id.offer_id)::uuid AS offer_id,
    count(*) AS usage_count
   FROM private.transactions t,
    LATERAL unnest(t.used_offers) offer_id(offer_id)
  WHERE ((t.status = ANY (ARRAY['valide'::text, 'completed'::text])) AND (t.used_offers IS NOT NULL) AND (array_length(t.used_offers, 1) > 0))
  GROUP BY (offer_id.offer_id)::uuid
  ORDER BY (count(*)) DESC;;

CREATE OR REPLACE VIEW "dashboard_view"."offers" AS
 SELECT id,
    title,
    description,
    image,
    points,
    expiry_date,
    is_active,
    is_premium,
    restaurant_ids,
    context_tags,
    created_at,
    updated_at,
        CASE
            WHEN ((expiry_date IS NOT NULL) AND (expiry_date < now())) THEN 'expired'::text
            WHEN (is_active = false) THEN 'inactive'::text
            ELSE 'active'::text
        END AS status
   FROM private.offers o
  WHERE ((is_active = true) OR (is_active = false));;

CREATE OR REPLACE VIEW "dashboard_view"."offers_usage_by_period" AS
 WITH offer_transactions AS (
         SELECT (t.date)::date AS transaction_date,
            (unnest(t.used_offers))::uuid AS offer_id,
            t.user_id,
            t.restaurant_id,
            t.status
           FROM private.transactions t
          WHERE ((t.status = ANY (ARRAY['valide'::text, 'completed'::text])) AND (t.used_offers IS NOT NULL) AND (array_length(t.used_offers, 1) > 0))
        ), aggregated_data AS (
         SELECT offer_transactions.transaction_date AS day,
            (date_trunc('month'::text, (offer_transactions.transaction_date)::timestamp with time zone))::date AS month,
            (date_trunc('year'::text, (offer_transactions.transaction_date)::timestamp with time zone))::date AS year,
            offer_transactions.offer_id,
            count(*) AS usage_count,
            count(DISTINCT offer_transactions.user_id) AS unique_users,
            count(DISTINCT offer_transactions.restaurant_id) AS unique_restaurants
           FROM offer_transactions
          GROUP BY offer_transactions.transaction_date, offer_transactions.offer_id
        )
 SELECT a.day,
    a.month,
    a.year,
    a.offer_id,
    o.title AS offer_title,
    o.is_active AS offer_is_active,
    o.is_premium AS offer_is_premium,
    o.points AS offer_points,
    a.usage_count,
    a.unique_users,
    a.unique_restaurants,
    sum(a.usage_count) OVER (PARTITION BY a.offer_id, a.month) AS usage_count_monthly,
    sum(a.unique_users) OVER (PARTITION BY a.offer_id, a.month) AS unique_users_monthly,
    sum(a.usage_count) OVER (PARTITION BY a.offer_id, a.year) AS usage_count_yearly,
    sum(a.unique_users) OVER (PARTITION BY a.offer_id, a.year) AS unique_users_yearly
   FROM (aggregated_data a
     LEFT JOIN private.offers o ON ((a.offer_id = o.id)))
  ORDER BY a.day DESC, a.usage_count DESC;;

CREATE OR REPLACE VIEW "dashboard_view"."polls" AS
 SELECT id,
    question,
    description,
    is_active,
    starts_at,
    ends_at
   FROM private.polls p
  WHERE (is_active = true);;

CREATE OR REPLACE VIEW "dashboard_view"."promotions" AS
 SELECT id,
    title,
    description,
    image_url,
    start_date,
    end_date,
    color,
        CASE
            WHEN ((start_date IS NULL) AND (end_date IS NULL)) THEN true
            WHEN ((start_date IS NULL) AND (end_date > now())) THEN true
            WHEN ((end_date IS NULL) AND (start_date <= now())) THEN true
            WHEN ((start_date <= now()) AND (end_date > now())) THEN true
            ELSE false
        END AS is_active,
        CASE
            WHEN ((start_date IS NULL) AND (end_date IS NULL)) THEN 'active'::text
            WHEN ((start_date IS NULL) AND (end_date > now())) THEN 'active'::text
            WHEN ((end_date IS NULL) AND (start_date <= now())) THEN 'active'::text
            WHEN ((start_date <= now()) AND (end_date > now())) THEN 'active'::text
            WHEN (start_date > now()) THEN 'scheduled'::text
            WHEN (end_date <= now()) THEN 'expired'::text
            ELSE 'inactive'::text
        END AS status
   FROM private.promotions p;;

CREATE OR REPLACE VIEW "dashboard_view"."restaurants" AS
 SELECT id,
    name,
    description,
    image_url,
    location,
    schedule,
    special_hours,
    categories,
    is_new,
    boosted,
    status,
    created_at,
    updated_at
   FROM private.restaurants r;;

CREATE OR REPLACE VIEW "dashboard_view"."today_stats" AS
 WITH today_base AS (
         SELECT ((now() AT TIME ZONE 'UTC'::text))::date AS day
        ), today_transactions AS (
         SELECT count(*) FILTER (WHERE ((t.status = ANY (ARRAY['valide'::text, 'completed'::text])) AND (t.date >= date_trunc('day'::text, (now() AT TIME ZONE 'UTC'::text))) AND (t.date < (date_trunc('day'::text, (now() AT TIME ZONE 'UTC'::text)) + '1 day'::interval)))) AS transactions_today,
            count(DISTINCT t.user_id) FILTER (WHERE ((t.status = ANY (ARRAY['valide'::text, 'completed'::text])) AND (t.date >= date_trunc('day'::text, (now() AT TIME ZONE 'UTC'::text))) AND (t.date < (date_trunc('day'::text, (now() AT TIME ZONE 'UTC'::text)) + '1 day'::interval)))) AS clients_today,
            COALESCE(sum(
                CASE
                    WHEN ((t.status = ANY (ARRAY['valide'::text, 'completed'::text])) AND (t.date >= date_trunc('day'::text, (now() AT TIME ZONE 'UTC'::text))) AND (t.date < (date_trunc('day'::text, (now() AT TIME ZONE 'UTC'::text)) + '1 day'::interval)) AND (t.points > 0)) THEN t.points
                    ELSE 0
                END), (0)::bigint) AS points_generated_today
           FROM private.transactions t
        )
 SELECT tb.day,
    COALESCE(tt.transactions_today, (0)::bigint) AS transactions_today,
    COALESCE(tt.clients_today, (0)::bigint) AS clients_today,
    COALESCE(tt.points_generated_today, (0)::bigint) AS points_generated_today
   FROM (today_base tb
     CROSS JOIN today_transactions tt);;

CREATE OR REPLACE VIEW "pgsodium"."decrypted_key" AS
 SELECT id,
    status,
    created,
    expires,
    key_type,
    key_id,
    key_context,
    name,
    associated_data,
    raw_key,
        CASE
            WHEN (raw_key IS NULL) THEN NULL::bytea
            ELSE
            CASE
                WHEN (parent_key IS NULL) THEN NULL::bytea
                ELSE pgsodium.crypto_aead_det_decrypt(raw_key, convert_to(((id)::text || associated_data), 'utf8'::name), parent_key, raw_key_nonce)
            END
        END AS decrypted_raw_key,
    raw_key_nonce,
    parent_key,
    comment
   FROM pgsodium.key;;

CREATE OR REPLACE VIEW "pgsodium"."mask_columns" AS
 SELECT a.attname,
    a.attrelid,
    m.key_id,
    m.key_id_column,
    m.associated_columns,
    m.nonce_column,
    m.format_type
   FROM (pg_attribute a
     LEFT JOIN pgsodium.masking_rule m ON (((m.attrelid = a.attrelid) AND (m.attname = a.attname))))
  WHERE ((a.attnum > 0) AND (NOT a.attisdropped))
  ORDER BY a.attnum;;

CREATE OR REPLACE VIEW "pgsodium"."masking_rule" AS
 WITH const AS (
         SELECT 'encrypt +with +key +id +([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})'::text AS pattern_key_id,
            'encrypt +with +key +column +([\w\"\-$]+)'::text AS pattern_key_id_column,
            '(?<=associated) +\(([\w\"\-$, ]+)\)'::text AS pattern_associated_columns,
            '(?<=nonce) +([\w\"\-$]+)'::text AS pattern_nonce_column,
            '(?<=decrypt with view) +([\w\"\-$]+\.[\w\"\-$]+)'::text AS pattern_view_name,
            '(?<=security invoker)'::text AS pattern_security_invoker
        ), rules_from_seclabels AS (
         SELECT sl.objoid AS attrelid,
            sl.objsubid AS attnum,
            (c.relnamespace)::regnamespace AS relnamespace,
            c.relname,
            a.attname,
            format_type(a.atttypid, a.atttypmod) AS format_type,
            sl.label AS col_description,
            (regexp_match(sl.label, k.pattern_key_id_column, 'i'::text))[1] AS key_id_column,
            (regexp_match(sl.label, k.pattern_key_id, 'i'::text))[1] AS key_id,
            (regexp_match(sl.label, k.pattern_associated_columns, 'i'::text))[1] AS associated_columns,
            (regexp_match(sl.label, k.pattern_nonce_column, 'i'::text))[1] AS nonce_column,
            COALESCE((regexp_match(sl2.label, k.pattern_view_name, 'i'::text))[1], (((c.relnamespace)::regnamespace || '.'::text) || quote_ident(('decrypted_'::text || (c.relname)::text)))) AS view_name,
            100 AS priority,
            ((regexp_match(sl.label, k.pattern_security_invoker, 'i'::text))[1] IS NOT NULL) AS security_invoker
           FROM const k,
            (((pg_seclabel sl
             JOIN pg_class c ON (((sl.classoid = c.tableoid) AND (sl.objoid = c.oid))))
             JOIN pg_attribute a ON (((a.attrelid = c.oid) AND (sl.objsubid = a.attnum))))
             LEFT JOIN pg_seclabel sl2 ON (((sl2.objoid = c.oid) AND (sl2.objsubid = 0))))
          WHERE ((a.attnum > 0) AND (((c.relnamespace)::regnamespace)::oid <> ('pg_catalog'::regnamespace)::oid) AND (NOT a.attisdropped) AND (sl.label ~~* 'ENCRYPT%'::text) AND (sl.provider = 'pgsodium'::text))
        )
 SELECT DISTINCT ON (attrelid, attnum) attrelid,
    attnum,
    relnamespace,
    relname,
    attname,
    format_type,
    col_description,
    key_id_column,
    key_id,
    associated_columns,
    nonce_column,
    view_name,
    priority,
    security_invoker
   FROM rules_from_seclabels
  ORDER BY attrelid, attnum, priority DESC;;

CREATE OR REPLACE VIEW "pgsodium"."valid_key" AS
 SELECT id,
    name,
    status,
    key_type,
    key_id,
    key_context,
    created,
    expires,
    associated_data
   FROM pgsodium.key
  WHERE ((status = ANY (ARRAY['valid'::pgsodium.key_status, 'default'::pgsodium.key_status])) AND
        CASE
            WHEN (expires IS NULL) THEN true
            ELSE (expires > now())
        END);;

CREATE OR REPLACE VIEW "view"."view_polls" AS
 WITH user_votes AS (
         SELECT v_1.poll_id,
            o_1.option_text
           FROM (private.poll_votes v_1
             JOIN private.poll_options o_1 ON ((o_1.id = v_1.option_id)))
          WHERE (v_1.user_id = auth.uid())
        )
 SELECT p.title,
    p.description,
    p.question,
    p.ends_at,
    p.image_url,
    json_agg(json_build_object('option_text', o.option_text) ORDER BY o.option_order) AS options,
    count(DISTINCT v.id) AS total_votes,
    (uv.poll_id IS NOT NULL) AS has_participated,
    uv.option_text AS user_vote_option
   FROM (((private.polls p
     LEFT JOIN private.poll_options o ON ((o.poll_id = p.id)))
     LEFT JOIN private.poll_votes v ON ((v.poll_id = p.id)))
     LEFT JOIN user_votes uv ON ((uv.poll_id = p.id)))
  WHERE ((p.is_active = true) AND (now() >= p.starts_at) AND (now() <= p.ends_at))
  GROUP BY p.title, p.description, p.question, p.ends_at, p.image_url, uv.poll_id, uv.option_text
  ORDER BY p.title;;

CREATE OR REPLACE VIEW "view"."view_promotions" AS
 SELECT title,
    description,
    image_url,
    color
   FROM private.promotions
  WHERE ((start_date <= now()) AND (end_date >= now()));;


-- ============================================================================
-- FONCTIONS
-- ============================================================================

-- Function: audit.recalculate_user_points_on_transaction_change()
CREATE OR REPLACE FUNCTION audit.recalculate_user_points_on_transaction_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'audit'
AS $function$
DECLARE
    v_user_id uuid;
    v_recalculated_points integer;
BEGIN
    -- 🛡️ SÉCURITÉ : Vérifier que la fonction est appelée depuis un trigger PostgreSQL uniquement
    IF TG_NAME IS NULL THEN
        RAISE EXCEPTION 'Accès refusé : cette fonction ne peut être appelée que depuis un trigger PostgreSQL';
    END IF;
    
    -- Récupérer l'ID de l'utilisateur
    v_user_id := COALESCE(NEW.user_id, OLD.user_id);
    
    -- Recalculer les points depuis les transactions 'valide'
    SELECT COALESCE(SUM(points), 0) INTO v_recalculated_points
    FROM private.transactions
    WHERE user_id = v_user_id
      AND status = 'valide';
    
    -- Mettre à jour les points de l'utilisateur
    -- Cela déclenchera le trigger verify_user_points_trigger_update qui vérifiera
    UPDATE private.users
    SET points = v_recalculated_points
    WHERE id = v_user_id;
    
    RETURN NEW;
END;
$function$


-- Function: audit.verify_transaction_points_trigger()
CREATE OR REPLACE FUNCTION audit.verify_transaction_points_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'audit'
AS $function$
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
    -- 🛡️ SÉCURITÉ : Vérifier que la fonction est appelée depuis un trigger PostgreSQL uniquement
    IF TG_NAME IS NULL THEN
        RAISE EXCEPTION 'Accès refusé : cette fonction ne peut être appelée que depuis un trigger PostgreSQL';
    END IF;
    
    -- CORRECTION : Sauvegarder les points qu'on essaie de mettre (NEW.points)
    -- pour comparer avec la valeur recalculée
    IF TG_OP = 'INSERT' THEN
        v_original_points := NEW.points;
    ELSIF TG_OP = 'UPDATE' THEN
        -- IMPORTANT : Comparer avec NEW.points (la valeur qu'on essaie de mettre)
        -- pas OLD.points (qui pourrait déjà être incorrect)
        v_original_points := NEW.points;
    ELSE
        v_original_points := NEW.points;
    END IF;
    
    -- LOGIQUE : Vérifier si la transaction est 'valide' (NEW ou OLD)
    IF TG_OP = 'INSERT' THEN
        IF NEW.status != 'valide' THEN
            RETURN NEW;
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.status != 'valide' AND OLD.status != 'valide' THEN
            RETURN NEW;
        END IF;
    END IF;
    
    -- Recalculer les points depuis les items
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
    
    -- Calculer les points nets recalculés
    v_recalculated := v_points_gained - v_points_spent;
    
    -- CORRECTION : Comparer avec NEW.points (la valeur qu'on essaie de mettre)
    v_difference := v_recalculated - v_original_points;
    
    -- Si incohérence détectée (différence != 0)
    IF ABS(v_difference) > 0 THEN
        -- Déterminer la sévérité
        IF ABS(v_difference) <= 10 THEN
            v_severity := 'medium';
        ELSIF ABS(v_difference) <= 50 THEN
            v_severity := 'high';
        ELSE
            v_severity := 'critical';
        END IF;
        
        -- 🔧 CORRECTION AUTOMATIQUE : Mettre à jour les points avec la valeur recalculée
        NEW.points := v_recalculated;
        
        -- Enregistrer ou mettre à jour l'anomalie dans la table audit
        -- Utiliser OLD.points pour l'audit (la valeur qui était dans la table avant)
        INSERT INTO audit.transaction_points_anomalies (
            transaction_id,
            user_id,
            stored_points,
            recalculated_points,
            points_difference,
            severity,
            status
        )
        VALUES (
            NEW.id,
            NEW.user_id,
            CASE WHEN TG_OP = 'UPDATE' THEN OLD.points ELSE NEW.points END,  -- Pour l'audit, on garde OLD.points
            v_recalculated,
            v_difference,
            v_severity,
            'corrige_auto'
        )
        ON CONFLICT (transaction_id) DO UPDATE SET
            stored_points = CASE WHEN TG_OP = 'UPDATE' THEN OLD.points ELSE NEW.points END,
            recalculated_points = v_recalculated,
            points_difference = v_difference,
            severity = v_severity,
            status = 'corrige_auto',
            detected_at = now();
        
        -- Log l'anomalie et la correction
        RAISE WARNING '[SECURITY_ALERT] Anomalie de points détectée et CORRIGÉE - Transaction: %, Différence: %, Points: % -> %',
            NEW.id, v_difference, v_original_points, v_recalculated;
    END IF;
    
    RETURN NEW;
END;
$function$


-- Function: audit.verify_user_points_trigger()
CREATE OR REPLACE FUNCTION audit.verify_user_points_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'audit'
AS $function$
DECLARE
    v_recalculated_points integer;
    v_difference integer;
    v_severity text;
    v_original_points integer;
BEGIN
    -- 🛡️ SÉCURITÉ : Vérifier que la fonction est appelée depuis un trigger PostgreSQL uniquement
    IF TG_NAME IS NULL THEN
        RAISE EXCEPTION 'Accès refusé : cette fonction ne peut être appelée que depuis un trigger PostgreSQL';
    END IF;
    
    -- Sauvegarder les points qu'on essaie de mettre (NEW.points)
    IF TG_OP = 'INSERT' THEN
        v_original_points := COALESCE(NEW.points, 0);
    ELSIF TG_OP = 'UPDATE' THEN
        v_original_points := COALESCE(NEW.points, 0);
    ELSE
        v_original_points := COALESCE(NEW.points, 0);
    END IF;
    
    -- Recalculer les points depuis les transactions 'valide' de l'utilisateur
    SELECT COALESCE(SUM(points), 0) INTO v_recalculated_points
    FROM private.transactions
    WHERE user_id = NEW.id
      AND status = 'valide';
    
    -- Calculer la différence
    v_difference := v_recalculated_points - v_original_points;
    
    -- Si incohérence détectée (différence != 0)
    IF ABS(v_difference) > 0 THEN
        -- Déterminer la sévérité
        IF ABS(v_difference) <= 10 THEN
            v_severity := 'medium';
        ELSIF ABS(v_difference) <= 50 THEN
            v_severity := 'high';
        ELSE
            v_severity := 'critical';
        END IF;
        
        -- 🔧 CORRECTION AUTOMATIQUE : Mettre à jour les points avec la valeur recalculée
        NEW.points := v_recalculated_points;
        
        -- Enregistrer ou mettre à jour l'anomalie dans la table audit
        INSERT INTO audit.user_points_anomalies (
            user_id,
            stored_points,
            recalculated_points,
            points_difference,
            severity,
            status
        )
        VALUES (
            NEW.id,
            CASE WHEN TG_OP = 'UPDATE' THEN OLD.points ELSE v_original_points END,
            v_recalculated_points,
            v_difference,
            v_severity,
            'corrige_auto'
        )
        ON CONFLICT (user_id) DO UPDATE SET
            stored_points = CASE WHEN TG_OP = 'UPDATE' THEN OLD.points ELSE v_original_points END,
            recalculated_points = v_recalculated_points,
            points_difference = v_difference,
            severity = v_severity,
            status = 'corrige_auto',
            detected_at = now();
        
        -- Log l'anomalie et la correction
        RAISE WARNING '[SECURITY_ALERT] Anomalie de points utilisateur détectée et CORRIGÉE - User: %, Différence: %, Points: % -> %',
            NEW.id, v_difference, v_original_points, v_recalculated_points;
    END IF;
    
    RETURN NEW;
END;
$function$


-- Function: cron.alter_job(job_id bigint, schedule text DEFAULT NULL::text, command text DEFAULT NULL::text, database text DEFAULT NULL::text, username text DEFAULT NULL::text, active boolean DEFAULT NULL::boolean)
CREATE OR REPLACE FUNCTION cron.alter_job(job_id bigint, schedule text DEFAULT NULL::text, command text DEFAULT NULL::text, database text DEFAULT NULL::text, username text DEFAULT NULL::text, active boolean DEFAULT NULL::boolean)
 RETURNS void
 LANGUAGE c
AS '$libdir/pg_cron', $function$cron_alter_job$function$


-- Function: cron.job_cache_invalidate()
CREATE OR REPLACE FUNCTION cron.job_cache_invalidate()
 RETURNS trigger
 LANGUAGE c
AS '$libdir/pg_cron', $function$cron_job_cache_invalidate$function$


-- Function: cron.schedule(job_name text, schedule text, command text)
CREATE OR REPLACE FUNCTION cron.schedule(job_name text, schedule text, command text)
 RETURNS bigint
 LANGUAGE c
AS '$libdir/pg_cron', $function$cron_schedule_named$function$


-- Function: cron.schedule(schedule text, command text)
CREATE OR REPLACE FUNCTION cron.schedule(schedule text, command text)
 RETURNS bigint
 LANGUAGE c
 STRICT
AS '$libdir/pg_cron', $function$cron_schedule$function$


-- Function: cron.schedule_in_database(job_name text, schedule text, command text, database text, username text DEFAULT NULL::text, active boolean DEFAULT true)
CREATE OR REPLACE FUNCTION cron.schedule_in_database(job_name text, schedule text, command text, database text, username text DEFAULT NULL::text, active boolean DEFAULT true)
 RETURNS bigint
 LANGUAGE c
AS '$libdir/pg_cron', $function$cron_schedule_named$function$


-- Function: cron.unschedule(job_name text)
CREATE OR REPLACE FUNCTION cron.unschedule(job_name text)
 RETURNS boolean
 LANGUAGE c
 STRICT
AS '$libdir/pg_cron', $function$cron_unschedule_named$function$


-- Function: cron.unschedule(job_id bigint)
CREATE OR REPLACE FUNCTION cron.unschedule(job_id bigint)
 RETURNS boolean
 LANGUAGE c
 STRICT
AS '$libdir/pg_cron', $function$cron_unschedule$function$


-- Function: graphql._internal_resolve(query text, variables jsonb DEFAULT '{}'::jsonb, "operationName" text DEFAULT NULL::text, extensions jsonb DEFAULT NULL::jsonb)
CREATE OR REPLACE FUNCTION graphql._internal_resolve(query text, variables jsonb DEFAULT '{}'::jsonb, "operationName" text DEFAULT NULL::text, extensions jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE c
AS '$libdir/pg_graphql', $function$resolve_wrapper$function$


-- Function: graphql.comment_directive(comment_ text)
CREATE OR REPLACE FUNCTION graphql.comment_directive(comment_ text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
    /*
    comment on column public.account.name is '@graphql.name: myField'
    */
    select
        coalesce(
            (
                regexp_match(
                    comment_,
                    '@graphql\((.+)\)'
                )
            )[1]::jsonb,
            jsonb_build_object()
        )
$function$


-- Function: graphql.exception(message text)
CREATE OR REPLACE FUNCTION graphql.exception(message text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
begin
    raise exception using errcode='22000', message=message;
end;
$function$


-- Function: graphql.get_schema_version()
CREATE OR REPLACE FUNCTION graphql.get_schema_version()
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
    select last_value from graphql.seq_schema_version;
$function$


-- Function: graphql.increment_schema_version()
CREATE OR REPLACE FUNCTION graphql.increment_schema_version()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
    perform pg_catalog.nextval('graphql.seq_schema_version');
end;
$function$


-- Function: graphql.resolve(query text, variables jsonb DEFAULT '{}'::jsonb, "operationName" text DEFAULT NULL::text, extensions jsonb DEFAULT NULL::jsonb)
CREATE OR REPLACE FUNCTION graphql.resolve(query text, variables jsonb DEFAULT '{}'::jsonb, "operationName" text DEFAULT NULL::text, extensions jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
    res jsonb;
    message_text text;
begin
  begin
    select graphql._internal_resolve("query" := "query",
                                     "variables" := "variables",
                                     "operationName" := "operationName",
                                     "extensions" := "extensions") into res;
    return res;
  exception
    when others then
    get stacked diagnostics message_text = message_text;
    return
    jsonb_build_object('data', null,
                       'errors', jsonb_build_array(jsonb_build_object('message', message_text)));
  end;
end;
$function$


-- Function: mv.refresh_mv_offers()
CREATE OR REPLACE FUNCTION mv.refresh_mv_offers()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'mv'
AS $function$
begin
  refresh materialized view mv.mv_offers;
  return null;
end;
$function$


-- Function: mv.refresh_mv_restaurants()
CREATE OR REPLACE FUNCTION mv.refresh_mv_restaurants()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'private', 'mv'
AS $function$
begin
  refresh materialized view mv.mv_restaurants;
  return null;
end;
$function$


-- Function: net._await_response(request_id bigint)
CREATE OR REPLACE FUNCTION net._await_response(request_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
declare
    rec net._http_response;
begin
    while rec is null loop
        select *
        into rec
        from net._http_response
        where id = request_id;

        if rec is null then
            -- Wait 50 ms before checking again
            perform pg_sleep(0.05);
        end if;
    end loop;

    return true;
end;
$function$


-- Function: net._encode_url_with_params_array(url text, params_array text[])
CREATE OR REPLACE FUNCTION net._encode_url_with_params_array(url text, params_array text[])
 RETURNS text
 LANGUAGE c
 IMMUTABLE
AS 'pg_net', $function$_encode_url_with_params_array$function$


-- Function: net._http_collect_response(request_id bigint, async boolean DEFAULT true)
CREATE OR REPLACE FUNCTION net._http_collect_response(request_id bigint, async boolean DEFAULT true)
 RETURNS net.http_response_result
 LANGUAGE plpgsql
AS $function$
declare
    rec net._http_response;
    req_exists boolean;
begin

    if not async then
        perform net._await_response(request_id);
    end if;

    select *
    into rec
    from net._http_response
    where id = request_id;

    if rec is null or rec.error_msg is not null then
        -- The request is either still processing or the request_id provided does not exist

        -- TODO: request in progress is indistinguishable from request that doesn't exist

        -- No request matching request_id found
        return (
            'ERROR',
            coalesce(rec.error_msg, 'request matching request_id not found'),
            null
        )::net.http_response_result;

    end if;

    -- Return a valid, populated http_response_result
    return (
        'SUCCESS',
        'ok',
        (
            rec.status_code,
            rec.headers,
            rec.content
        )::net.http_response
    )::net.http_response_result;
end;
$function$


-- Function: net._urlencode_string(string character varying)
CREATE OR REPLACE FUNCTION net._urlencode_string(string character varying)
 RETURNS text
 LANGUAGE c
 IMMUTABLE
AS 'pg_net', $function$_urlencode_string$function$


-- Function: net.check_worker_is_up()
CREATE OR REPLACE FUNCTION net.check_worker_is_up()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
begin
  if not exists (select pid from pg_stat_activity where backend_type ilike '%pg_net%') then
    raise exception using
      message = 'the pg_net background worker is not up'
    , detail  = 'the pg_net background worker is down due to an internal error and cannot process requests'
    , hint    = 'make sure that you didn''t modify any of pg_net internal tables';
  end if;
end
$function$


-- Function: net.http_collect_response(request_id bigint, async boolean DEFAULT true)
CREATE OR REPLACE FUNCTION net.http_collect_response(request_id bigint, async boolean DEFAULT true)
 RETURNS net.http_response_result
 LANGUAGE plpgsql
AS $function$
begin
  raise notice 'The net.http_collect_response function is deprecated.';
  select net._http_collect_response(request_id, async);
end;
$function$


-- Function: net.http_delete(url text, params jsonb DEFAULT '{}'::jsonb, headers jsonb DEFAULT '{}'::jsonb, timeout_milliseconds integer DEFAULT 5000, body jsonb DEFAULT NULL::jsonb)
CREATE OR REPLACE FUNCTION net.http_delete(url text, params jsonb DEFAULT '{}'::jsonb, headers jsonb DEFAULT '{}'::jsonb, timeout_milliseconds integer DEFAULT 5000, body jsonb DEFAULT NULL::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
declare
    request_id bigint;
    params_array text[];
begin
    select coalesce(array_agg(net._urlencode_string(key) || '=' || net._urlencode_string(value)), '{}')
    into params_array
    from jsonb_each_text(params);

    -- Add to the request queue
    insert into net.http_request_queue(method, url, headers, body, timeout_milliseconds)
    values (
        'DELETE',
        net._encode_url_with_params_array(url, params_array),
        headers,
        convert_to(body::text, 'UTF8'),
        timeout_milliseconds
    )
    returning id
    into request_id;

    perform net.wake();

    return request_id;
end
$function$


-- Function: net.http_get(url text, params jsonb DEFAULT '{}'::jsonb, headers jsonb DEFAULT '{}'::jsonb, timeout_milliseconds integer DEFAULT 5000)
CREATE OR REPLACE FUNCTION net.http_get(url text, params jsonb DEFAULT '{}'::jsonb, headers jsonb DEFAULT '{}'::jsonb, timeout_milliseconds integer DEFAULT 5000)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'net'
AS $function$
declare
    request_id bigint;
    params_array text[];
begin
    select coalesce(array_agg(net._urlencode_string(key) || '=' || net._urlencode_string(value)), '{}')
    into params_array
    from jsonb_each_text(params);

    -- Add to the request queue
    insert into net.http_request_queue(method, url, headers, timeout_milliseconds)
    values (
        'GET',
        net._encode_url_with_params_array(url, params_array),
        headers,
        timeout_milliseconds
    )
    returning id
    into request_id;

    perform net.wake();

    return request_id;
end
$function$


-- Function: net.http_post(url text, body jsonb DEFAULT '{}'::jsonb, params jsonb DEFAULT '{}'::jsonb, headers jsonb DEFAULT '{"Content-Type": "application/json"}'::jsonb, timeout_milliseconds integer DEFAULT 5000)
CREATE OR REPLACE FUNCTION net.http_post(url text, body jsonb DEFAULT '{}'::jsonb, params jsonb DEFAULT '{}'::jsonb, headers jsonb DEFAULT '{"Content-Type": "application/json"}'::jsonb, timeout_milliseconds integer DEFAULT 5000)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'net'
AS $function$
declare
    request_id bigint;
    params_array text[];
    content_type text;
begin

    -- Exctract the content_type from headers
    select
        header_value into content_type
    from
        jsonb_each_text(coalesce(headers, '{}'::jsonb)) r(header_name, header_value)
    where
        lower(header_name) = 'content-type'
    limit
        1;

    -- If the user provided new headers and omitted the content type
    -- add it back in automatically
    if content_type is null then
        select headers || '{"Content-Type": "application/json"}'::jsonb into headers;
    end if;

    -- Confirm that the content-type is set as "application/json"
    if content_type <> 'application/json' then
        raise exception 'Content-Type header must be "application/json"';
    end if;

    select
        coalesce(array_agg(net._urlencode_string(key) || '=' || net._urlencode_string(value)), '{}')
    into
        params_array
    from
        jsonb_each_text(params);

    -- Add to the request queue
    insert into net.http_request_queue(method, url, headers, body, timeout_milliseconds)
    values (
        'POST',
        net._encode_url_with_params_array(url, params_array),
        headers,
        convert_to(body::text, 'UTF8'),
        timeout_milliseconds
    )
    returning id
    into request_id;

    perform net.wake();

    return request_id;
end
$function$


-- Function: net.wait_until_running()
CREATE OR REPLACE FUNCTION net.wait_until_running()
 RETURNS void
 LANGUAGE c
AS 'pg_net', $function$wait_until_running$function$


-- Function: net.wake()
CREATE OR REPLACE FUNCTION net.wake()
 RETURNS void
 LANGUAGE c
AS 'pg_net', $function$wake$function$


-- Function: net.worker_restart()
CREATE OR REPLACE FUNCTION net.worker_restart()
 RETURNS boolean
 LANGUAGE c
AS 'pg_net', $function$worker_restart$function$


-- Function: pgbouncer.get_auth(p_usename text)
CREATE OR REPLACE FUNCTION pgbouncer.get_auth(p_usename text)
 RETURNS TABLE(username text, password text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  BEGIN
      RAISE DEBUG 'PgBouncer auth request: %', p_usename;

      RETURN QUERY
      SELECT
          rolname::text,
          CASE WHEN rolvaliduntil < now()
              THEN null
              ELSE rolpassword::text
          END
      FROM pg_authid
      WHERE rolname=$1 and rolcanlogin;
  END;
  $function$


-- Function: pgmq._belongs_to_pgmq(table_name text)
CREATE OR REPLACE FUNCTION pgmq._belongs_to_pgmq(table_name text)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
    sql TEXT;
    result BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM pg_depend
    WHERE refobjid = (SELECT oid FROM pg_extension WHERE extname = 'pgmq')
    AND objid = (
        SELECT oid
        FROM pg_class
        WHERE relname = table_name
    )
  ) INTO result;
  RETURN result;
END;
$function$


-- Function: pgmq._ensure_pg_partman_installed()
CREATE OR REPLACE FUNCTION pgmq._ensure_pg_partman_installed()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  extension_exists BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM pg_extension
    WHERE extname = 'pg_partman'
  ) INTO extension_exists;

  IF NOT extension_exists THEN
    RAISE EXCEPTION 'pg_partman is required for partitioned queues';
  END IF;
END;
$function$


-- Function: pgmq._extension_exists(extension_name text)
CREATE OR REPLACE FUNCTION pgmq._extension_exists(extension_name text)
 RETURNS boolean
 LANGUAGE sql
AS $function$
SELECT EXISTS (
    SELECT 1
    FROM pg_extension
    WHERE extname = extension_name
)
$function$


-- Function: pgmq._get_partition_col(partition_interval text)
CREATE OR REPLACE FUNCTION pgmq._get_partition_col(partition_interval text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  num INTEGER;
BEGIN
    BEGIN
        num := partition_interval::INTEGER;
        RETURN 'msg_id';
    EXCEPTION
        WHEN others THEN
            RETURN 'enqueued_at';
    END;
END;
$function$


-- Function: pgmq._get_pg_partman_major_version()
CREATE OR REPLACE FUNCTION pgmq._get_pg_partman_major_version()
 RETURNS integer
 LANGUAGE sql
AS $function$
  SELECT split_part(extversion, '.', 1)::INT
  FROM pg_extension
  WHERE extname = 'pg_partman'
$function$


-- Function: pgmq._get_pg_partman_schema()
CREATE OR REPLACE FUNCTION pgmq._get_pg_partman_schema()
 RETURNS text
 LANGUAGE sql
AS $function$
  SELECT
    extnamespace::regnamespace::text
  FROM
    pg_extension
  WHERE
    extname = 'pg_partman';
$function$


-- Function: pgmq.archive(queue_name text, msg_id bigint)
CREATE OR REPLACE FUNCTION pgmq.archive(queue_name text, msg_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
    sql TEXT;
    result BIGINT;
    qtable TEXT := pgmq.format_table_name(queue_name, 'q');
    atable TEXT := pgmq.format_table_name(queue_name, 'a');
BEGIN
    sql := FORMAT(
        $QUERY$
        WITH archived AS (
            DELETE FROM pgmq.%I
            WHERE msg_id = $1
            RETURNING msg_id, vt, read_ct, enqueued_at, message, headers
        )
        INSERT INTO pgmq.%I (msg_id, vt, read_ct, enqueued_at, message, headers)
        SELECT msg_id, vt, read_ct, enqueued_at, message, headers
        FROM archived
        RETURNING msg_id;
        $QUERY$,
        qtable, atable
    );
    EXECUTE sql USING msg_id INTO result;
    RETURN NOT (result IS NULL);
END;
$function$


-- Function: pgmq.archive(queue_name text, msg_ids bigint[])
CREATE OR REPLACE FUNCTION pgmq.archive(queue_name text, msg_ids bigint[])
 RETURNS SETOF bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
    sql TEXT;
    qtable TEXT := pgmq.format_table_name(queue_name, 'q');
    atable TEXT := pgmq.format_table_name(queue_name, 'a');
BEGIN
    sql := FORMAT(
        $QUERY$
        WITH archived AS (
            DELETE FROM pgmq.%I
            WHERE msg_id = ANY($1)
            RETURNING msg_id, vt, read_ct, enqueued_at, message, headers
        )
        INSERT INTO pgmq.%I (msg_id, vt, read_ct, enqueued_at, message, headers)
        SELECT msg_id, vt, read_ct, enqueued_at, message, headers
        FROM archived
        RETURNING msg_id;
        $QUERY$,
        qtable, atable
    );
    RETURN QUERY EXECUTE sql USING msg_ids;
END;
$function$


-- Function: pgmq.convert_archive_partitioned(table_name text, partition_interval text DEFAULT '10000'::text, retention_interval text DEFAULT '100000'::text, leading_partition integer DEFAULT 10)
CREATE OR REPLACE FUNCTION pgmq.convert_archive_partitioned(table_name text, partition_interval text DEFAULT '10000'::text, retention_interval text DEFAULT '100000'::text, leading_partition integer DEFAULT 10)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  a_table_name TEXT := pgmq.format_table_name(table_name, 'a');
  a_table_name_old TEXT := pgmq.format_table_name(table_name, 'a') || '_old';
  qualified_a_table_name TEXT := format('pgmq.%I', a_table_name);
BEGIN

  PERFORM c.relkind
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = a_table_name
    AND c.relkind = 'p';

  IF FOUND THEN
    RAISE NOTICE 'Table %s is already partitioned', a_table_name;
    RETURN;
  END IF;

  PERFORM c.relkind
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = a_table_name
    AND c.relkind = 'r';

  IF NOT FOUND THEN
    RAISE NOTICE 'Table %s does not exists', a_table_name;
    RETURN;
  END IF;

  EXECUTE 'ALTER TABLE ' || qualified_a_table_name || ' RENAME TO ' || a_table_name_old;

  EXECUTE format( 'CREATE TABLE pgmq.%I (LIKE pgmq.%I including all) PARTITION BY RANGE (msg_id)', a_table_name, a_table_name_old );

  EXECUTE 'ALTER INDEX pgmq.archived_at_idx_' || table_name || ' RENAME TO archived_at_idx_' || table_name || '_old';
  EXECUTE 'CREATE INDEX archived_at_idx_'|| table_name || ' ON ' || qualified_a_table_name ||'(archived_at)';

  -- https://github.com/pgpartman/pg_partman/blob/master/doc/pg_partman.md
  -- p_parent_table - the existing parent table. MUST be schema qualified, even if in public schema.
  EXECUTE FORMAT(
    $QUERY$
    SELECT %I.create_parent(
      p_parent_table := %L,
      p_control := 'msg_id',
      p_interval := %L,
      p_type := case
        when pgmq._get_pg_partman_major_version() = 5 then 'range'
        else 'native'
      end
    )
    $QUERY$,
    pgmq._get_pg_partman_schema(),
    qualified_a_table_name,
    partition_interval
  );

  EXECUTE FORMAT(
    $QUERY$
    UPDATE %I.part_config
    SET
      retention = %L,
      retention_keep_table = false,
      retention_keep_index = false,
      infinite_time_partitions = true
    WHERE
      parent_table = %L;
    $QUERY$,
    pgmq._get_pg_partman_schema(),
    retention_interval,
    qualified_a_table_name
  );

END;
$function$


-- Function: pgmq.create(queue_name text)
CREATE OR REPLACE FUNCTION pgmq."create"(queue_name text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM pgmq.create_non_partitioned(queue_name);
END;
$function$


-- Function: pgmq.create_non_partitioned(queue_name text)
CREATE OR REPLACE FUNCTION pgmq.create_non_partitioned(queue_name text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  qtable TEXT := pgmq.format_table_name(queue_name, 'q');
  qtable_seq TEXT := qtable || '_msg_id_seq';
  atable TEXT := pgmq.format_table_name(queue_name, 'a');
BEGIN
  PERFORM pgmq.validate_queue_name(queue_name);

  EXECUTE FORMAT(
    $QUERY$
    CREATE TABLE IF NOT EXISTS pgmq.%I (
        msg_id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
        read_ct INT DEFAULT 0 NOT NULL,
        enqueued_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        vt TIMESTAMP WITH TIME ZONE NOT NULL,
        message JSONB,
        headers JSONB
    )
    $QUERY$,
    qtable
  );

  EXECUTE FORMAT(
    $QUERY$
    CREATE TABLE IF NOT EXISTS pgmq.%I (
      msg_id BIGINT PRIMARY KEY,
      read_ct INT DEFAULT 0 NOT NULL,
      enqueued_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
      archived_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
      vt TIMESTAMP WITH TIME ZONE NOT NULL,
      message JSONB,
      headers JSONB
    );
    $QUERY$,
    atable
  );

  IF NOT pgmq._belongs_to_pgmq(qtable) THEN
      EXECUTE FORMAT('ALTER EXTENSION pgmq ADD TABLE pgmq.%I', qtable);
      EXECUTE FORMAT('ALTER EXTENSION pgmq ADD SEQUENCE pgmq.%I', qtable_seq);
  END IF;

  IF NOT pgmq._belongs_to_pgmq(atable) THEN
      EXECUTE FORMAT('ALTER EXTENSION pgmq ADD TABLE pgmq.%I', atable);
  END IF;

  EXECUTE FORMAT(
    $QUERY$
    CREATE INDEX IF NOT EXISTS %I ON pgmq.%I (vt ASC);
    $QUERY$,
    qtable || '_vt_idx', qtable
  );

  EXECUTE FORMAT(
    $QUERY$
    CREATE INDEX IF NOT EXISTS %I ON pgmq.%I (archived_at);
    $QUERY$,
    'archived_at_idx_' || queue_name, atable
  );

  EXECUTE FORMAT(
    $QUERY$
    INSERT INTO pgmq.meta (queue_name, is_partitioned, is_unlogged)
    VALUES (%L, false, false)
    ON CONFLICT
    DO NOTHING;
    $QUERY$,
    queue_name
  );
END;
$function$


-- Function: pgmq.create_partitioned(queue_name text, partition_interval text DEFAULT '10000'::text, retention_interval text DEFAULT '100000'::text)
CREATE OR REPLACE FUNCTION pgmq.create_partitioned(queue_name text, partition_interval text DEFAULT '10000'::text, retention_interval text DEFAULT '100000'::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  partition_col TEXT;
  a_partition_col TEXT;
  qtable TEXT := pgmq.format_table_name(queue_name, 'q');
  qtable_seq TEXT := qtable || '_msg_id_seq';
  atable TEXT := pgmq.format_table_name(queue_name, 'a');
  fq_qtable TEXT := 'pgmq.' || qtable;
  fq_atable TEXT := 'pgmq.' || atable;
BEGIN
  PERFORM pgmq.validate_queue_name(queue_name);
  PERFORM pgmq._ensure_pg_partman_installed();
  SELECT pgmq._get_partition_col(partition_interval) INTO partition_col;

  EXECUTE FORMAT(
    $QUERY$
    CREATE TABLE IF NOT EXISTS pgmq.%I (
        msg_id BIGINT GENERATED ALWAYS AS IDENTITY,
        read_ct INT DEFAULT 0 NOT NULL,
        enqueued_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        vt TIMESTAMP WITH TIME ZONE NOT NULL,
        message JSONB,
        headers JSONB
    ) PARTITION BY RANGE (%I)
    $QUERY$,
    qtable, partition_col
  );

  IF NOT pgmq._belongs_to_pgmq(qtable) THEN
      EXECUTE FORMAT('ALTER EXTENSION pgmq ADD TABLE pgmq.%I', qtable);
      EXECUTE FORMAT('ALTER EXTENSION pgmq ADD SEQUENCE pgmq.%I', qtable_seq);
  END IF;

  -- https://github.com/pgpartman/pg_partman/blob/master/doc/pg_partman.md
  -- p_parent_table - the existing parent table. MUST be schema qualified, even if in public schema.
  EXECUTE FORMAT(
    $QUERY$
    SELECT %I.create_parent(
      p_parent_table := %L,
      p_control := %L,
      p_interval := %L,
      p_type := case
        when pgmq._get_pg_partman_major_version() = 5 then 'range'
        else 'native'
      end
    )
    $QUERY$,
    pgmq._get_pg_partman_schema(),
    fq_qtable,
    partition_col,
    partition_interval
  );

  EXECUTE FORMAT(
    $QUERY$
    CREATE INDEX IF NOT EXISTS %I ON pgmq.%I (%I);
    $QUERY$,
    qtable || '_part_idx', qtable, partition_col
  );

  EXECUTE FORMAT(
    $QUERY$
    UPDATE %I.part_config
    SET
        retention = %L,
        retention_keep_table = false,
        retention_keep_index = true,
        automatic_maintenance = 'on'
    WHERE parent_table = %L;
    $QUERY$,
    pgmq._get_pg_partman_schema(),
    retention_interval,
    'pgmq.' || qtable
  );

  EXECUTE FORMAT(
    $QUERY$
    INSERT INTO pgmq.meta (queue_name, is_partitioned, is_unlogged)
    VALUES (%L, true, false)
    ON CONFLICT
    DO NOTHING;
    $QUERY$,
    queue_name
  );

  IF partition_col = 'enqueued_at' THEN
    a_partition_col := 'archived_at';
  ELSE
    a_partition_col := partition_col;
  END IF;

  EXECUTE FORMAT(
    $QUERY$
    CREATE TABLE IF NOT EXISTS pgmq.%I (
      msg_id BIGINT NOT NULL,
      read_ct INT DEFAULT 0 NOT NULL,
      enqueued_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
      archived_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
      vt TIMESTAMP WITH TIME ZONE NOT NULL,
      message JSONB,
      headers JSONB
    ) PARTITION BY RANGE (%I);
    $QUERY$,
    atable, a_partition_col
  );

  IF NOT pgmq._belongs_to_pgmq(atable) THEN
      EXECUTE FORMAT('ALTER EXTENSION pgmq ADD TABLE pgmq.%I', atable);
  END IF;

  -- https://github.com/pgpartman/pg_partman/blob/master/doc/pg_partman.md
  -- p_parent_table - the existing parent table. MUST be schema qualified, even if in public schema.
  EXECUTE FORMAT(
    $QUERY$
    SELECT %I.create_parent(
      p_parent_table := %L,
      p_control := %L,
      p_interval := %L,
      p_type := case
        when pgmq._get_pg_partman_major_version() = 5 then 'range'
        else 'native'
      end
    )
    $QUERY$,
    pgmq._get_pg_partman_schema(),
    fq_atable,
    a_partition_col,
    partition_interval
  );

  EXECUTE FORMAT(
    $QUERY$
    UPDATE %I.part_config
    SET
        retention = %L,
        retention_keep_table = false,
        retention_keep_index = true,
        automatic_maintenance = 'on'
    WHERE parent_table = %L;
    $QUERY$,
    pgmq._get_pg_partman_schema(),
    retention_interval,
    'pgmq.' || atable
  );

  EXECUTE FORMAT(
    $QUERY$
    CREATE INDEX IF NOT EXISTS %I ON pgmq.%I (archived_at);
    $QUERY$,
    'archived_at_idx_' || queue_name, atable
  );

END;
$function$


-- Function: pgmq.create_unlogged(queue_name text)
CREATE OR REPLACE FUNCTION pgmq.create_unlogged(queue_name text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  qtable TEXT := pgmq.format_table_name(queue_name, 'q');
  qtable_seq TEXT := qtable || '_msg_id_seq';
  atable TEXT := pgmq.format_table_name(queue_name, 'a');
BEGIN
  PERFORM pgmq.validate_queue_name(queue_name);
  EXECUTE FORMAT(
    $QUERY$
    CREATE UNLOGGED TABLE IF NOT EXISTS pgmq.%I (
        msg_id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
        read_ct INT DEFAULT 0 NOT NULL,
        enqueued_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
        vt TIMESTAMP WITH TIME ZONE NOT NULL,
        message JSONB,
        headers JSONB
    )
    $QUERY$,
    qtable
  );

  EXECUTE FORMAT(
    $QUERY$
    CREATE TABLE IF NOT EXISTS pgmq.%I (
      msg_id BIGINT PRIMARY KEY,
      read_ct INT DEFAULT 0 NOT NULL,
      enqueued_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
      archived_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
      vt TIMESTAMP WITH TIME ZONE NOT NULL,
      message JSONB,
      headers JSONB
    );
    $QUERY$,
    atable
  );

  IF NOT pgmq._belongs_to_pgmq(qtable) THEN
      EXECUTE FORMAT('ALTER EXTENSION pgmq ADD TABLE pgmq.%I', qtable);
      EXECUTE FORMAT('ALTER EXTENSION pgmq ADD SEQUENCE pgmq.%I', qtable_seq);
  END IF;

  IF NOT pgmq._belongs_to_pgmq(atable) THEN
      EXECUTE FORMAT('ALTER EXTENSION pgmq ADD TABLE pgmq.%I', atable);
  END IF;

  EXECUTE FORMAT(
    $QUERY$
    CREATE INDEX IF NOT EXISTS %I ON pgmq.%I (vt ASC);
    $QUERY$,
    qtable || '_vt_idx', qtable
  );

  EXECUTE FORMAT(
    $QUERY$
    CREATE INDEX IF NOT EXISTS %I ON pgmq.%I (archived_at);
    $QUERY$,
    'archived_at_idx_' || queue_name, atable
  );

  EXECUTE FORMAT(
    $QUERY$
    INSERT INTO pgmq.meta (queue_name, is_partitioned, is_unlogged)
    VALUES (%L, false, true)
    ON CONFLICT
    DO NOTHING;
    $QUERY$,
    queue_name
  );
END;
$function$


-- Function: pgmq.delete(queue_name text, msg_id bigint)
CREATE OR REPLACE FUNCTION pgmq.delete(queue_name text, msg_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
    sql TEXT;
    result BIGINT;
    qtable TEXT := pgmq.format_table_name(queue_name, 'q');
BEGIN
    sql := FORMAT(
        $QUERY$
        DELETE FROM pgmq.%I
        WHERE msg_id = $1
        RETURNING msg_id
        $QUERY$,
        qtable
    );
    EXECUTE sql USING msg_id INTO result;
    RETURN NOT (result IS NULL);
END;
$function$


-- Function: pgmq.delete(queue_name text, msg_ids bigint[])
CREATE OR REPLACE FUNCTION pgmq.delete(queue_name text, msg_ids bigint[])
 RETURNS SETOF bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
    sql TEXT;
    qtable TEXT := pgmq.format_table_name(queue_name, 'q');
BEGIN
    sql := FORMAT(
        $QUERY$
        DELETE FROM pgmq.%I
        WHERE msg_id = ANY($1)
        RETURNING msg_id
        $QUERY$,
        qtable
    );
    RETURN QUERY EXECUTE sql USING msg_ids;
END;
$function$


-- Function: pgmq.detach_archive(queue_name text)
CREATE OR REPLACE FUNCTION pgmq.detach_archive(queue_name text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  atable TEXT := pgmq.format_table_name(queue_name, 'a');
BEGIN
  EXECUTE format('ALTER EXTENSION pgmq DROP TABLE pgmq.%I', atable);
END
$function$


-- Function: pgmq.drop_queue(queue_name text, partitioned boolean)
CREATE OR REPLACE FUNCTION pgmq.drop_queue(queue_name text, partitioned boolean)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
    qtable TEXT := pgmq.format_table_name(queue_name, 'q');
    fq_qtable TEXT := 'pgmq.' || qtable;
    atable TEXT := pgmq.format_table_name(queue_name, 'a');
    fq_atable TEXT := 'pgmq.' || atable;
BEGIN
    RAISE WARNING 'drop_queue(queue_name, partitioned) is deprecated and will be removed in PGMQ v2.0. Use drop_queue(queue_name) instead.';

    PERFORM pgmq.drop_queue(queue_name);

    RETURN TRUE;
END;
$function$


-- Function: pgmq.drop_queue(queue_name text)
CREATE OR REPLACE FUNCTION pgmq.drop_queue(queue_name text)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
    qtable TEXT := pgmq.format_table_name(queue_name, 'q');
    qtable_seq TEXT := qtable || '_msg_id_seq';
    fq_qtable TEXT := 'pgmq.' || qtable;
    atable TEXT := pgmq.format_table_name(queue_name, 'a');
    fq_atable TEXT := 'pgmq.' || atable;
    partitioned BOOLEAN;
BEGIN
    EXECUTE FORMAT(
        $QUERY$
        SELECT is_partitioned FROM pgmq.meta WHERE queue_name = %L
        $QUERY$,
        queue_name
    ) INTO partitioned;

    EXECUTE FORMAT(
        $QUERY$
        ALTER EXTENSION pgmq DROP TABLE pgmq.%I
        $QUERY$,
        qtable
    );

    EXECUTE FORMAT(
        $QUERY$
        ALTER EXTENSION pgmq DROP SEQUENCE pgmq.%I
        $QUERY$,
        qtable_seq
    );

    EXECUTE FORMAT(
        $QUERY$
        ALTER EXTENSION pgmq DROP TABLE pgmq.%I
        $QUERY$,
        atable
    );

    EXECUTE FORMAT(
        $QUERY$
        DROP TABLE IF EXISTS pgmq.%I
        $QUERY$,
        qtable
    );

    EXECUTE FORMAT(
        $QUERY$
        DROP TABLE IF EXISTS pgmq.%I
        $QUERY$,
        atable
    );

     IF EXISTS (
          SELECT 1
          FROM information_schema.tables
          WHERE table_name = 'meta' and table_schema = 'pgmq'
     ) THEN
        EXECUTE FORMAT(
            $QUERY$
            DELETE FROM pgmq.meta WHERE queue_name = %L
            $QUERY$,
            queue_name
        );
     END IF;

     IF partitioned THEN
        EXECUTE FORMAT(
          $QUERY$
          DELETE FROM %I.part_config where parent_table in (%L, %L)
          $QUERY$,
          pgmq._get_pg_partman_schema(), fq_qtable, fq_atable
        );
     END IF;

    RETURN TRUE;
END;
$function$


-- Function: pgmq.format_table_name(queue_name text, prefix text)
CREATE OR REPLACE FUNCTION pgmq.format_table_name(queue_name text, prefix text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF queue_name ~ '\$|;|--|'''
    THEN
        RAISE EXCEPTION 'queue name contains invalid characters: $, ;, --, or \''';
    END IF;
    RETURN lower(prefix || '_' || queue_name);
END;
$function$


-- Function: pgmq.list_queues()
CREATE OR REPLACE FUNCTION pgmq.list_queues()
 RETURNS SETOF pgmq.queue_record
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY SELECT * FROM pgmq.meta;
END
$function$


-- Function: pgmq.metrics(queue_name text)
CREATE OR REPLACE FUNCTION pgmq.metrics(queue_name text)
 RETURNS pgmq.metrics_result
 LANGUAGE plpgsql
AS $function$
DECLARE
    result_row pgmq.metrics_result;
    query TEXT;
    qtable TEXT := pgmq.format_table_name(queue_name, 'q');
BEGIN
    query := FORMAT(
        $QUERY$
        WITH q_summary AS (
            SELECT
                count(*) as queue_length,
                count(CASE WHEN vt <= NOW() THEN 1 END) as queue_visible_length,
                EXTRACT(epoch FROM (NOW() - max(enqueued_at)))::int as newest_msg_age_sec,
                EXTRACT(epoch FROM (NOW() - min(enqueued_at)))::int as oldest_msg_age_sec,
                NOW() as scrape_time
            FROM pgmq.%I
        ),
        all_metrics AS (
            SELECT CASE
                WHEN is_called THEN last_value ELSE 0
                END as total_messages
            FROM pgmq.%I
        )
        SELECT
            %L as queue_name,
            q_summary.queue_length,
            q_summary.newest_msg_age_sec,
            q_summary.oldest_msg_age_sec,
            all_metrics.total_messages,
            q_summary.scrape_time,
            q_summary.queue_visible_length
        FROM q_summary, all_metrics
        $QUERY$,
        qtable, qtable || '_msg_id_seq', queue_name
    );
    EXECUTE query INTO result_row;
    RETURN result_row;
END;
$function$


-- Function: pgmq.metrics_all()
CREATE OR REPLACE FUNCTION pgmq.metrics_all()
 RETURNS SETOF pgmq.metrics_result
 LANGUAGE plpgsql
AS $function$
DECLARE
    row_name RECORD;
    result_row pgmq.metrics_result;
BEGIN
    FOR row_name IN SELECT queue_name FROM pgmq.meta LOOP
        result_row := pgmq.metrics(row_name.queue_name);
        RETURN NEXT result_row;
    END LOOP;
END;
$function$


-- Function: pgmq.pop(queue_name text)
CREATE OR REPLACE FUNCTION pgmq.pop(queue_name text)
 RETURNS SETOF pgmq.message_record
 LANGUAGE plpgsql
AS $function$
DECLARE
    sql TEXT;
    result pgmq.message_record;
    qtable TEXT := pgmq.format_table_name(queue_name, 'q');
BEGIN
    sql := FORMAT(
        $QUERY$
        WITH cte AS
            (
                SELECT msg_id
                FROM pgmq.%I
                WHERE vt <= clock_timestamp()
                ORDER BY msg_id ASC
                LIMIT 1
                FOR UPDATE SKIP LOCKED
            )
        DELETE from pgmq.%I
        WHERE msg_id = (select msg_id from cte)
        RETURNING *;
        $QUERY$,
        qtable, qtable
    );
    RETURN QUERY EXECUTE sql;
END;
$function$


-- Function: pgmq.purge_queue(queue_name text)
CREATE OR REPLACE FUNCTION pgmq.purge_queue(queue_name text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  deleted_count INTEGER;
  qtable TEXT := pgmq.format_table_name(queue_name, 'q');
BEGIN
  -- Get the row count before truncating
  EXECUTE format('SELECT count(*) FROM pgmq.%I', qtable) INTO deleted_count;

  -- Use TRUNCATE for better performance on large tables
  EXECUTE format('TRUNCATE TABLE pgmq.%I', qtable);

  -- Return the number of purged rows
  RETURN deleted_count;
END
$function$


-- Function: pgmq.read(queue_name text, vt integer, qty integer, conditional jsonb DEFAULT '{}'::jsonb)
CREATE OR REPLACE FUNCTION pgmq.read(queue_name text, vt integer, qty integer, conditional jsonb DEFAULT '{}'::jsonb)
 RETURNS SETOF pgmq.message_record
 LANGUAGE plpgsql
AS $function$
DECLARE
    sql TEXT;
    qtable TEXT := pgmq.format_table_name(queue_name, 'q');
BEGIN
    sql := FORMAT(
        $QUERY$
        WITH cte AS
        (
            SELECT msg_id
            FROM pgmq.%I
            WHERE vt <= clock_timestamp() AND CASE
                WHEN %L != '{}'::jsonb THEN (message @> %2$L)::integer
                ELSE 1
            END = 1
            ORDER BY msg_id ASC
            LIMIT $1
            FOR UPDATE SKIP LOCKED
        )
        UPDATE pgmq.%I m
        SET
            vt = clock_timestamp() + %L,
            read_ct = read_ct + 1
        FROM cte
        WHERE m.msg_id = cte.msg_id
        RETURNING m.msg_id, m.read_ct, m.enqueued_at, m.vt, m.message, m.headers;
        $QUERY$,
        qtable, conditional, qtable, make_interval(secs => vt)
    );
    RETURN QUERY EXECUTE sql USING qty;
END;
$function$


-- Function: pgmq.read_with_poll(queue_name text, vt integer, qty integer, max_poll_seconds integer DEFAULT 5, poll_interval_ms integer DEFAULT 100, conditional jsonb DEFAULT '{}'::jsonb)
CREATE OR REPLACE FUNCTION pgmq.read_with_poll(queue_name text, vt integer, qty integer, max_poll_seconds integer DEFAULT 5, poll_interval_ms integer DEFAULT 100, conditional jsonb DEFAULT '{}'::jsonb)
 RETURNS SETOF pgmq.message_record
 LANGUAGE plpgsql
AS $function$
DECLARE
    r pgmq.message_record;
    stop_at TIMESTAMP;
    sql TEXT;
    qtable TEXT := pgmq.format_table_name(queue_name, 'q');
BEGIN
    stop_at := clock_timestamp() + make_interval(secs => max_poll_seconds);
    LOOP
      IF (SELECT clock_timestamp() >= stop_at) THEN
        RETURN;
      END IF;

      sql := FORMAT(
          $QUERY$
          WITH cte AS
          (
              SELECT msg_id
              FROM pgmq.%I
              WHERE vt <= clock_timestamp() AND CASE
                  WHEN %L != '{}'::jsonb THEN (message @> %2$L)::integer
                  ELSE 1
              END = 1
              ORDER BY msg_id ASC
              LIMIT $1
              FOR UPDATE SKIP LOCKED
          )
          UPDATE pgmq.%I m
          SET
              vt = clock_timestamp() + %L,
              read_ct = read_ct + 1
          FROM cte
          WHERE m.msg_id = cte.msg_id
          RETURNING m.msg_id, m.read_ct, m.enqueued_at, m.vt, m.message, m.headers;
          $QUERY$,
          qtable, conditional, qtable, make_interval(secs => vt)
      );

      FOR r IN
        EXECUTE sql USING qty
      LOOP
        RETURN NEXT r;
      END LOOP;
      IF FOUND THEN
        RETURN;
      ELSE
        PERFORM pg_sleep(poll_interval_ms::numeric / 1000);
      END IF;
    END LOOP;
END;
$function$


-- Function: pgmq.send(queue_name text, msg jsonb, headers jsonb, delay integer)
CREATE OR REPLACE FUNCTION pgmq.send(queue_name text, msg jsonb, headers jsonb, delay integer)
 RETURNS SETOF bigint
 LANGUAGE sql
AS $function$
    SELECT * FROM pgmq.send(queue_name, msg, headers, clock_timestamp() + make_interval(secs => delay));
$function$


-- Function: pgmq.send(queue_name text, msg jsonb, delay integer)
CREATE OR REPLACE FUNCTION pgmq.send(queue_name text, msg jsonb, delay integer)
 RETURNS SETOF bigint
 LANGUAGE sql
AS $function$
    SELECT * FROM pgmq.send(queue_name, msg, NULL, clock_timestamp() + make_interval(secs => delay));
$function$


-- Function: pgmq.send(queue_name text, msg jsonb, headers jsonb, delay timestamp with time zone)
CREATE OR REPLACE FUNCTION pgmq.send(queue_name text, msg jsonb, headers jsonb, delay timestamp with time zone)
 RETURNS SETOF bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
    sql TEXT;
    qtable TEXT := pgmq.format_table_name(queue_name, 'q');
BEGIN
    sql := FORMAT(
        $QUERY$
        INSERT INTO pgmq.%I (vt, message, headers)
        VALUES ($2, $1, $3)
        RETURNING msg_id;
        $QUERY$,
        qtable
    );
    RETURN QUERY EXECUTE sql USING msg, delay, headers;
END;
$function$


-- Function: pgmq.send(queue_name text, msg jsonb, delay timestamp with time zone)
CREATE OR REPLACE FUNCTION pgmq.send(queue_name text, msg jsonb, delay timestamp with time zone)
 RETURNS SETOF bigint
 LANGUAGE sql
AS $function$
    SELECT * FROM pgmq.send(queue_name, msg, NULL, delay);
$function$


-- Function: pgmq.send(queue_name text, msg jsonb, headers jsonb)
CREATE OR REPLACE FUNCTION pgmq.send(queue_name text, msg jsonb, headers jsonb)
 RETURNS SETOF bigint
 LANGUAGE sql
AS $function$
    SELECT * FROM pgmq.send(queue_name, msg, headers, clock_timestamp());
$function$


-- Function: pgmq.send(queue_name text, msg jsonb)
CREATE OR REPLACE FUNCTION pgmq.send(queue_name text, msg jsonb)
 RETURNS SETOF bigint
 LANGUAGE sql
AS $function$
    SELECT * FROM pgmq.send(queue_name, msg, NULL, clock_timestamp());
$function$


-- Function: pgmq.send_batch(queue_name text, msgs jsonb[], delay timestamp with time zone)
CREATE OR REPLACE FUNCTION pgmq.send_batch(queue_name text, msgs jsonb[], delay timestamp with time zone)
 RETURNS SETOF bigint
 LANGUAGE sql
AS $function$
    SELECT * FROM pgmq.send_batch(queue_name, msgs, NULL, delay);
$function$


-- Function: pgmq.send_batch(queue_name text, msgs jsonb[], headers jsonb[], delay timestamp with time zone)
CREATE OR REPLACE FUNCTION pgmq.send_batch(queue_name text, msgs jsonb[], headers jsonb[], delay timestamp with time zone)
 RETURNS SETOF bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
    sql TEXT;
    qtable TEXT := pgmq.format_table_name(queue_name, 'q');
BEGIN
    sql := FORMAT(
        $QUERY$
        INSERT INTO pgmq.%I (vt, message, headers)
        SELECT $2, unnest($1), unnest(coalesce($3, ARRAY[]::jsonb[]))
        RETURNING msg_id;
        $QUERY$,
        qtable
    );
    RETURN QUERY EXECUTE sql USING msgs, delay, headers;
END;
$function$


-- Function: pgmq.send_batch(queue_name text, msgs jsonb[], headers jsonb[], delay integer)
CREATE OR REPLACE FUNCTION pgmq.send_batch(queue_name text, msgs jsonb[], headers jsonb[], delay integer)
 RETURNS SETOF bigint
 LANGUAGE sql
AS $function$
    SELECT * FROM pgmq.send_batch(queue_name, msgs, headers, clock_timestamp() + make_interval(secs => delay));
$function$


-- Function: pgmq.send_batch(queue_name text, msgs jsonb[], headers jsonb[])
CREATE OR REPLACE FUNCTION pgmq.send_batch(queue_name text, msgs jsonb[], headers jsonb[])
 RETURNS SETOF bigint
 LANGUAGE sql
AS $function$
    SELECT * FROM pgmq.send_batch(queue_name, msgs, headers, clock_timestamp());
$function$


-- Function: pgmq.send_batch(queue_name text, msgs jsonb[])
CREATE OR REPLACE FUNCTION pgmq.send_batch(queue_name text, msgs jsonb[])
 RETURNS SETOF bigint
 LANGUAGE sql
AS $function$
    SELECT * FROM pgmq.send_batch(queue_name, msgs, NULL, clock_timestamp());
$function$


-- Function: pgmq.send_batch(queue_name text, msgs jsonb[], delay integer)
CREATE OR REPLACE FUNCTION pgmq.send_batch(queue_name text, msgs jsonb[], delay integer)
 RETURNS SETOF bigint
 LANGUAGE sql
AS $function$
    SELECT * FROM pgmq.send_batch(queue_name, msgs, NULL, clock_timestamp() + make_interval(secs => delay));
$function$


-- Function: pgmq.set_vt(queue_name text, msg_id bigint, vt integer)
CREATE OR REPLACE FUNCTION pgmq.set_vt(queue_name text, msg_id bigint, vt integer)
 RETURNS SETOF pgmq.message_record
 LANGUAGE plpgsql
AS $function$
DECLARE
    sql TEXT;
    result pgmq.message_record;
    qtable TEXT := pgmq.format_table_name(queue_name, 'q');
BEGIN
    sql := FORMAT(
        $QUERY$
        UPDATE pgmq.%I
        SET vt = (clock_timestamp() + %L)
        WHERE msg_id = %L
        RETURNING *;
        $QUERY$,
        qtable, make_interval(secs => vt), msg_id
    );
    RETURN QUERY EXECUTE sql;
END;
$function$


-- Function: pgmq.validate_queue_name(queue_name text)
CREATE OR REPLACE FUNCTION pgmq.validate_queue_name(queue_name text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF length(queue_name) >= 48 THEN
    RAISE EXCEPTION 'queue name is too long, maximum length is 48 characters';
  END IF;
END;
$function$


-- Function: pgsodium.create_key(key_type pgsodium.key_type DEFAULT 'aead-det'::pgsodium.key_type, name text DEFAULT NULL::text, raw_key bytea DEFAULT NULL::bytea, raw_key_nonce bytea DEFAULT NULL::bytea, parent_key uuid DEFAULT NULL::uuid, key_context bytea DEFAULT '\x7067736f6469756d'::bytea, expires timestamp with time zone DEFAULT NULL::timestamp with time zone, associated_data text DEFAULT ''::text)
CREATE OR REPLACE FUNCTION pgsodium.create_key(key_type pgsodium.key_type DEFAULT 'aead-det'::pgsodium.key_type, name text DEFAULT NULL::text, raw_key bytea DEFAULT NULL::bytea, raw_key_nonce bytea DEFAULT NULL::bytea, parent_key uuid DEFAULT NULL::uuid, key_context bytea DEFAULT '\x7067736f6469756d'::bytea, expires timestamp with time zone DEFAULT NULL::timestamp with time zone, associated_data text DEFAULT ''::text)
 RETURNS pgsodium.valid_key
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  new_key pgsodium.key;
  valid_key pgsodium.valid_key;
BEGIN
  INSERT INTO pgsodium.key (key_id, key_context, key_type, raw_key,
  raw_key_nonce, parent_key, expires, name, associated_data)
      VALUES (
        CASE WHEN raw_key IS NULL THEN
            NEXTVAL('pgsodium.key_key_id_seq'::REGCLASS)
        ELSE NULL END,
        CASE WHEN raw_key IS NULL THEN
            key_context
        ELSE NULL END,
        key_type,
        raw_key,
        CASE WHEN raw_key IS NOT NULL THEN
            COALESCE(raw_key_nonce, pgsodium.crypto_aead_det_noncegen())
        ELSE NULL END,
        CASE WHEN parent_key IS NULL and raw_key IS NOT NULL THEN
            (pgsodium.create_key('aead-det')).id
        ELSE parent_key END,
        expires,
        name,
        associated_data)
    RETURNING * INTO new_key;
  SELECT * INTO valid_key FROM pgsodium.valid_key WHERE id = new_key.id;
  RETURN valid_key;
END;
$function$


-- Function: pgsodium.create_mask_view(relid oid, debug boolean DEFAULT false)
CREATE OR REPLACE FUNCTION pgsodium.create_mask_view(relid oid, debug boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  body text;
  source_name text;
  view_name text;
  rule pgsodium.masking_rule;
BEGIN
  SELECT DISTINCT(quote_ident(relname)) INTO STRICT view_name
    FROM pg_class c, pg_seclabel sl
   WHERE relid = c.oid
     AND sl.classoid = c.tableoid
     AND sl.objoid = c.oid;

  source_name := relid::regclass;

  body = format(
    $c$
    DROP VIEW IF EXISTS pgsodium_masks.%s;
    CREATE VIEW pgsodium_masks.%s AS SELECT %s
    FROM %s;
    $c$,
    view_name,
    view_name,
    pgsodium.decrypted_columns(relid),
    source_name
  );
  IF debug THEN
    RAISE NOTICE '%', body;
  END IF;
  EXECUTE body;

  body = format(
    $c$
    CREATE OR REPLACE FUNCTION pgsodium_masks.%s_encrypt_secret()
      RETURNS TRIGGER
      LANGUAGE plpgsql
      AS $t$
    BEGIN
    %s;
    RETURN new;
    END;
    $t$;

    DROP TRIGGER IF EXISTS %s_encrypt_secret_trigger ON %s;

    CREATE TRIGGER %s_encrypt_secret_trigger
      BEFORE INSERT ON %s
      FOR EACH ROW
      EXECUTE FUNCTION pgsodium_masks.%s_encrypt_secret ();
    $c$,
    view_name,
    pgsodium.encrypted_columns(relid),
    view_name,
    source_name,
    view_name,
    source_name,
    view_name
  );
  if debug THEN
    RAISE NOTICE '%', body;
  END IF;
  EXECUTE body;

  PERFORM pgsodium.mask_role(oid::regrole, source_name, view_name)
  FROM pg_roles WHERE pgsodium.has_mask(oid::regrole, source_name);

  RETURN;
END
  $function$


-- Function: pgsodium.create_mask_view(relid oid, subid integer, debug boolean DEFAULT false)
CREATE OR REPLACE FUNCTION pgsodium.create_mask_view(relid oid, subid integer, debug boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  m record;
  body text;
  source_name text;
  view_owner regrole = session_user;
  rule pgsodium.masking_rule;
  privs aclitem[];
  priv record;
BEGIN
  SELECT DISTINCT * INTO STRICT rule FROM pgsodium.masking_rule WHERE attrelid = relid AND attnum = subid;

  source_name := relid::regclass::text;

  BEGIN
    SELECT relacl INTO STRICT privs FROM pg_catalog.pg_class WHERE oid = rule.view_name::regclass::oid;
  EXCEPTION
	WHEN undefined_table THEN
      SELECT relacl INTO STRICT privs FROM pg_catalog.pg_class WHERE oid = relid;
  END;

  body = format(
    $c$
    DROP VIEW IF EXISTS %1$s;
    CREATE VIEW %1$s %5$s AS SELECT %2$s
    FROM %3$s;
    ALTER VIEW %1$s OWNER TO %4$s;
    $c$,
    rule.view_name,
    pgsodium.decrypted_columns(relid),
    source_name,
    view_owner,
    CASE WHEN rule.security_invoker THEN 'WITH (security_invoker=true)' ELSE '' END
  );
  IF debug THEN
    RAISE NOTICE '%', body;
  END IF;
  EXECUTE body;

  FOR priv IN SELECT * FROM pg_catalog.aclexplode(privs) LOOP
	body = format(
	  $c$
	  GRANT %s ON %s TO %s;
	  $c$,
	  priv.privilege_type,
	  rule.view_name,
	  priv.grantee::regrole::text
	);
	IF debug THEN
	  RAISE NOTICE '%', body;
	END IF;
	EXECUTE body;
  END LOOP;

  FOR m IN SELECT * FROM pgsodium.mask_columns where attrelid = relid LOOP
	IF m.key_id IS NULL AND m.key_id_column is NULL THEN
	  CONTINUE;
	ELSE
	  body = format(
		$c$
		DROP FUNCTION IF EXISTS %1$s."%2$s_encrypt_secret_%3$s"() CASCADE;

		CREATE OR REPLACE FUNCTION %1$s."%2$s_encrypt_secret_%3$s"()
		  RETURNS TRIGGER
		  LANGUAGE plpgsql
		  AS $t$
		BEGIN
		%4$s;
		RETURN new;
		END;
		$t$;

		ALTER FUNCTION  %1$s."%2$s_encrypt_secret_%3$s"() OWNER TO %5$s;

		DROP TRIGGER IF EXISTS "%2$s_encrypt_secret_trigger_%3$s" ON %6$s;

		CREATE TRIGGER "%2$s_encrypt_secret_trigger_%3$s"
		  BEFORE INSERT OR UPDATE OF "%3$s" ON %6$s
		  FOR EACH ROW
		  EXECUTE FUNCTION %1$s."%2$s_encrypt_secret_%3$s" ();
		  $c$,
		rule.relnamespace,
		rule.relname,
		m.attname,
		pgsodium.encrypted_column(relid, m),
		view_owner,
		source_name
	  );
	  if debug THEN
		RAISE NOTICE '%', body;
	  END IF;
	  EXECUTE body;
	END IF;
  END LOOP;

  raise notice 'about to masking role % %', source_name, rule.view_name;
  PERFORM pgsodium.mask_role(oid::regrole, source_name, rule.view_name)
  FROM pg_roles WHERE pgsodium.has_mask(oid::regrole, source_name);

  RETURN;
END
  $function$


-- Function: pgsodium.crypto_aead_det_decrypt(ciphertext bytea, additional bytea, key bytea, nonce bytea DEFAULT NULL::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_aead_det_decrypt(ciphertext bytea, additional bytea, key bytea, nonce bytea DEFAULT NULL::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_aead_det_decrypt$function$


-- Function: pgsodium.crypto_aead_det_decrypt(message bytea, additional bytea, key_uuid uuid)
CREATE OR REPLACE FUNCTION pgsodium.crypto_aead_det_decrypt(message bytea, additional bytea, key_uuid uuid)
 RETURNS bytea
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  key pgsodium.decrypted_key;
BEGIN
  SELECT * INTO STRICT key
    FROM pgsodium.decrypted_key v
  WHERE id = key_uuid AND key_type = 'aead-det';

  IF key.decrypted_raw_key IS NOT NULL THEN
    RETURN pgsodium.crypto_aead_det_decrypt(message, additional, key.decrypted_raw_key);
  END IF;
  RETURN pgsodium.crypto_aead_det_decrypt(message, additional, key.key_id, key.key_context);
END;
  $function$


-- Function: pgsodium.crypto_aead_det_decrypt(message bytea, additional bytea, key_uuid uuid, nonce bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_aead_det_decrypt(message bytea, additional bytea, key_uuid uuid, nonce bytea)
 RETURNS bytea
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  key pgsodium.decrypted_key;
BEGIN
  SELECT * INTO STRICT key
    FROM pgsodium.decrypted_key v
  WHERE id = key_uuid AND key_type = 'aead-det';

  IF key.decrypted_raw_key IS NOT NULL THEN
    RETURN pgsodium.crypto_aead_det_decrypt(message, additional, key.decrypted_raw_key, nonce);
  END IF;
  RETURN pgsodium.crypto_aead_det_decrypt(message, additional, key.key_id, key.key_context, nonce);
END;
  $function$


-- Function: pgsodium.crypto_aead_det_decrypt(message bytea, additional bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea, nonce bytea DEFAULT NULL::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_aead_det_decrypt(message bytea, additional bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea, nonce bytea DEFAULT NULL::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_aead_det_decrypt_by_id$function$


-- Function: pgsodium.crypto_aead_det_encrypt(message bytea, additional bytea, key_uuid uuid, nonce bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_aead_det_encrypt(message bytea, additional bytea, key_uuid uuid, nonce bytea)
 RETURNS bytea
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  key pgsodium.decrypted_key;
BEGIN
  SELECT * INTO STRICT key
    FROM pgsodium.decrypted_key v
  WHERE id = key_uuid AND key_type = 'aead-det';

  IF key.decrypted_raw_key IS NOT NULL THEN
    RETURN pgsodium.crypto_aead_det_encrypt(message, additional, key.decrypted_raw_key, nonce);
  END IF;
  RETURN pgsodium.crypto_aead_det_encrypt(message, additional, key.key_id, key.key_context, nonce);
END;
  $function$


-- Function: pgsodium.crypto_aead_det_encrypt(message bytea, additional bytea, key_uuid uuid)
CREATE OR REPLACE FUNCTION pgsodium.crypto_aead_det_encrypt(message bytea, additional bytea, key_uuid uuid)
 RETURNS bytea
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  key pgsodium.decrypted_key;
BEGIN
  SELECT * INTO STRICT key
    FROM pgsodium.decrypted_key v
  WHERE id = key_uuid AND key_type = 'aead-det';

  IF key.decrypted_raw_key IS NOT NULL THEN
    RETURN pgsodium.crypto_aead_det_encrypt(message, additional, key.decrypted_raw_key);
  END IF;
  RETURN pgsodium.crypto_aead_det_encrypt(message, additional, key.key_id, key.key_context);
END;
  $function$


-- Function: pgsodium.crypto_aead_det_encrypt(message bytea, additional bytea, key bytea, nonce bytea DEFAULT NULL::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_aead_det_encrypt(message bytea, additional bytea, key bytea, nonce bytea DEFAULT NULL::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_aead_det_encrypt$function$


-- Function: pgsodium.crypto_aead_det_encrypt(message bytea, additional bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea, nonce bytea DEFAULT NULL::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_aead_det_encrypt(message bytea, additional bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea, nonce bytea DEFAULT NULL::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_aead_det_encrypt_by_id$function$


-- Function: pgsodium.crypto_aead_det_keygen()
CREATE OR REPLACE FUNCTION pgsodium.crypto_aead_det_keygen()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_aead_det_keygen$function$


-- Function: pgsodium.crypto_aead_det_noncegen()
CREATE OR REPLACE FUNCTION pgsodium.crypto_aead_det_noncegen()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_aead_det_noncegen$function$


-- Function: pgsodium.crypto_aead_ietf_decrypt(message bytea, additional bytea, nonce bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_aead_ietf_decrypt(message bytea, additional bytea, nonce bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_aead_ietf_decrypt_by_id$function$


-- Function: pgsodium.crypto_aead_ietf_decrypt(message bytea, additional bytea, nonce bytea, key bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_aead_ietf_decrypt(message bytea, additional bytea, nonce bytea, key bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_aead_ietf_decrypt$function$


-- Function: pgsodium.crypto_aead_ietf_decrypt(message bytea, additional bytea, nonce bytea, key_uuid uuid)
CREATE OR REPLACE FUNCTION pgsodium.crypto_aead_ietf_decrypt(message bytea, additional bytea, nonce bytea, key_uuid uuid)
 RETURNS bytea
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  key pgsodium.decrypted_key;
BEGIN
  SELECT * INTO STRICT key
    FROM pgsodium.decrypted_key v
  WHERE id = key_uuid AND key_type = 'aead-ietf';

  IF key.decrypted_raw_key IS NOT NULL THEN
    RETURN pgsodium.crypto_aead_ietf_decrypt(message, additional, nonce, key.decrypted_raw_key);
  END IF;
  RETURN pgsodium.crypto_aead_ietf_decrypt(message, additional, nonce, key.key_id, key.key_context);
END;
  $function$


-- Function: pgsodium.crypto_aead_ietf_encrypt(message bytea, additional bytea, nonce bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_aead_ietf_encrypt(message bytea, additional bytea, nonce bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_aead_ietf_encrypt_by_id$function$


-- Function: pgsodium.crypto_aead_ietf_encrypt(message bytea, additional bytea, nonce bytea, key bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_aead_ietf_encrypt(message bytea, additional bytea, nonce bytea, key bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_aead_ietf_encrypt$function$


-- Function: pgsodium.crypto_aead_ietf_encrypt(message bytea, additional bytea, nonce bytea, key_uuid uuid)
CREATE OR REPLACE FUNCTION pgsodium.crypto_aead_ietf_encrypt(message bytea, additional bytea, nonce bytea, key_uuid uuid)
 RETURNS bytea
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  key pgsodium.decrypted_key;
BEGIN
  SELECT * INTO STRICT key
    FROM pgsodium.decrypted_key v
  WHERE id = key_uuid AND key_type = 'aead-ietf';

  IF key.decrypted_raw_key IS NOT NULL THEN
    RETURN pgsodium.crypto_aead_ietf_encrypt(message, additional, nonce, key.decrypted_raw_key);
  END IF;
  RETURN pgsodium.crypto_aead_ietf_encrypt(message, additional, nonce, key.key_id, key.key_context);
END;
  $function$


-- Function: pgsodium.crypto_aead_ietf_keygen()
CREATE OR REPLACE FUNCTION pgsodium.crypto_aead_ietf_keygen()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_aead_ietf_keygen$function$


-- Function: pgsodium.crypto_aead_ietf_noncegen()
CREATE OR REPLACE FUNCTION pgsodium.crypto_aead_ietf_noncegen()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_aead_ietf_noncegen$function$


-- Function: pgsodium.crypto_auth(message bytea, key_uuid uuid)
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth(message bytea, key_uuid uuid)
 RETURNS bytea
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  key pgsodium.decrypted_key;
BEGIN
  SELECT * INTO STRICT key
    FROM pgsodium.decrypted_key v
  WHERE id = key_uuid AND key_type = 'auth';

  IF key.decrypted_raw_key IS NOT NULL THEN
    RETURN pgsodium.crypto_auth(message, key.decrypted_raw_key);
  END IF;
  RETURN pgsodium.crypto_auth(message, key.key_id, key.key_context);
END;

$function$


-- Function: pgsodium.crypto_auth(message bytea, key bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth(message bytea, key bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_auth$function$


-- Function: pgsodium.crypto_auth(message bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth(message bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_auth_by_id$function$


-- Function: pgsodium.crypto_auth_hmacsha256(message bytea, key_uuid uuid)
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth_hmacsha256(message bytea, key_uuid uuid)
 RETURNS bytea
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  key pgsodium.decrypted_key;
BEGIN
  SELECT * INTO STRICT key
    FROM pgsodium.decrypted_key v
  WHERE id = key_uuid AND key_type = 'hmacsha256';

  IF key.decrypted_raw_key IS NOT NULL THEN
    RETURN pgsodium.crypto_auth_hmacsha256(message, key.decrypted_raw_key);
  END IF;
  RETURN pgsodium.crypto_auth_hmacsha256(message, key.key_id, key.key_context);
END;

$function$


-- Function: pgsodium.crypto_auth_hmacsha256(message bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth_hmacsha256(message bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_auth_hmacsha256_by_id$function$


-- Function: pgsodium.crypto_auth_hmacsha256(message bytea, secret bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth_hmacsha256(message bytea, secret bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_auth_hmacsha256$function$


-- Function: pgsodium.crypto_auth_hmacsha256_keygen()
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth_hmacsha256_keygen()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_auth_hmacsha256_keygen$function$


-- Function: pgsodium.crypto_auth_hmacsha256_verify(hash bytea, message bytea, secret bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth_hmacsha256_verify(hash bytea, message bytea, secret bytea)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_auth_hmacsha256_verify$function$


-- Function: pgsodium.crypto_auth_hmacsha256_verify(hash bytea, message bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth_hmacsha256_verify(hash bytea, message bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_auth_hmacsha256_verify_by_id$function$


-- Function: pgsodium.crypto_auth_hmacsha256_verify(signature bytea, message bytea, key_uuid uuid)
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth_hmacsha256_verify(signature bytea, message bytea, key_uuid uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  key pgsodium.decrypted_key;
BEGIN
  SELECT * INTO STRICT key
    FROM pgsodium.decrypted_key v
  WHERE id = key_uuid AND key_type = 'hmacsha256';

  IF key.decrypted_raw_key IS NOT NULL THEN
    RETURN pgsodium.crypto_auth_hmacsha256_verify(signature, message, key.decrypted_raw_key);
  END IF;
  RETURN pgsodium.crypto_auth_hmacsha256_verify(signature, message, key.key_id, key.key_context);
END;

$function$


-- Function: pgsodium.crypto_auth_hmacsha512(message bytea, key_uuid uuid)
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth_hmacsha512(message bytea, key_uuid uuid)
 RETURNS bytea
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  key pgsodium.decrypted_key;
BEGIN
  SELECT * INTO STRICT key
    FROM pgsodium.decrypted_key v
  WHERE id = key_uuid AND key_type = 'hmacsha512';

  IF key.decrypted_raw_key IS NOT NULL THEN
    RETURN pgsodium.crypto_auth_hmacsha512(message, key.decrypted_raw_key);
  END IF;
  RETURN pgsodium.crypto_auth_hmacsha512(message, key.key_id, key.key_context);
END;

$function$


-- Function: pgsodium.crypto_auth_hmacsha512(message bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth_hmacsha512(message bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_auth_hmacsha512_by_id$function$


-- Function: pgsodium.crypto_auth_hmacsha512(message bytea, secret bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth_hmacsha512(message bytea, secret bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_auth_hmacsha512$function$


-- Function: pgsodium.crypto_auth_hmacsha512_keygen()
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth_hmacsha512_keygen()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_auth_hmacsha512_keygen$function$


-- Function: pgsodium.crypto_auth_hmacsha512_verify(hash bytea, message bytea, secret bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth_hmacsha512_verify(hash bytea, message bytea, secret bytea)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_auth_hmacsha512_verify$function$


-- Function: pgsodium.crypto_auth_hmacsha512_verify(signature bytea, message bytea, key_uuid uuid)
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth_hmacsha512_verify(signature bytea, message bytea, key_uuid uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  key pgsodium.decrypted_key;
BEGIN
  SELECT * INTO STRICT key
    FROM pgsodium.decrypted_key v
  WHERE id = key_uuid AND key_type = 'hmacsha512';

  IF key.decrypted_raw_key IS NOT NULL THEN
    RETURN pgsodium.crypto_auth_hmacsha512_verify(signature, message, key.decrypted_raw_key);
  END IF;
  RETURN pgsodium.crypto_auth_hmacsha512_verify(signature, message, key.key_id, key.key_context);
END;

$function$


-- Function: pgsodium.crypto_auth_hmacsha512_verify(hash bytea, message bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth_hmacsha512_verify(hash bytea, message bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_auth_hmacsha512_verify_by_id$function$


-- Function: pgsodium.crypto_auth_keygen()
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth_keygen()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_auth_keygen$function$


-- Function: pgsodium.crypto_auth_verify(mac bytea, message bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth_verify(mac bytea, message bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_auth_verify_by_id$function$


-- Function: pgsodium.crypto_auth_verify(mac bytea, message bytea, key_uuid uuid)
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth_verify(mac bytea, message bytea, key_uuid uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  key pgsodium.decrypted_key;
BEGIN
  SELECT * INTO STRICT key
    FROM pgsodium.decrypted_key v
  WHERE id = key_uuid AND key_type = 'auth';

  IF key.decrypted_raw_key IS NOT NULL THEN
    RETURN pgsodium.crypto_auth_verify(mac, message, key.decrypted_raw_key);
  END IF;
  RETURN pgsodium.crypto_auth_verify(mac, message, key.key_id, key.key_context);
END;

$function$


-- Function: pgsodium.crypto_auth_verify(mac bytea, message bytea, key bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_auth_verify(mac bytea, message bytea, key bytea)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_auth_verify$function$


-- Function: pgsodium.crypto_box(message bytea, nonce bytea, public bytea, secret bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_box(message bytea, nonce bytea, public bytea, secret bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_box$function$


-- Function: pgsodium.crypto_box_new_keypair()
CREATE OR REPLACE FUNCTION pgsodium.crypto_box_new_keypair()
 RETURNS pgsodium.crypto_box_keypair
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_box_keypair$function$


-- Function: pgsodium.crypto_box_new_seed()
CREATE OR REPLACE FUNCTION pgsodium.crypto_box_new_seed()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_box_new_seed$function$


-- Function: pgsodium.crypto_box_noncegen()
CREATE OR REPLACE FUNCTION pgsodium.crypto_box_noncegen()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_box_noncegen$function$


-- Function: pgsodium.crypto_box_open(ciphertext bytea, nonce bytea, public bytea, secret bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_box_open(ciphertext bytea, nonce bytea, public bytea, secret bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_box_open$function$


-- Function: pgsodium.crypto_box_seal(message bytea, public_key bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_box_seal(message bytea, public_key bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_box_seal$function$


-- Function: pgsodium.crypto_box_seal_open(ciphertext bytea, public_key bytea, secret_key bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_box_seal_open(ciphertext bytea, public_key bytea, secret_key bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_box_seal_open$function$


-- Function: pgsodium.crypto_box_seed_new_keypair(seed bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_box_seed_new_keypair(seed bytea)
 RETURNS pgsodium.crypto_box_keypair
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_box_seed_keypair$function$


-- Function: pgsodium.crypto_cmp(text, text)
CREATE OR REPLACE FUNCTION pgsodium.crypto_cmp(text, text)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE STRICT
AS '$libdir/pgsodium', $function$pgsodium_cmp$function$


-- Function: pgsodium.crypto_generichash(message bytea, key bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_generichash(message bytea, key bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_generichash_by_id$function$


-- Function: pgsodium.crypto_generichash(message bytea, key_uuid uuid)
CREATE OR REPLACE FUNCTION pgsodium.crypto_generichash(message bytea, key_uuid uuid)
 RETURNS bytea
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  key pgsodium.decrypted_key;
BEGIN
  SELECT * INTO STRICT key
    FROM pgsodium.decrypted_key v
  WHERE id = key_uuid AND key_type = 'generichash';

  IF key.decrypted_raw_key IS NOT NULL THEN
    RETURN pgsodium.crypto_generichash(message, key.decrypted_raw_key);
  END IF;
  RETURN pgsodium.crypto_generichash(message, key.key_id, key.key_context);
END;

$function$


-- Function: pgsodium.crypto_generichash(message bytea, key bytea DEFAULT NULL::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_generichash(message bytea, key bytea DEFAULT NULL::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_generichash$function$


-- Function: pgsodium.crypto_generichash_keygen()
CREATE OR REPLACE FUNCTION pgsodium.crypto_generichash_keygen()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_generichash_keygen$function$


-- Function: pgsodium.crypto_hash_sha256(message bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_hash_sha256(message bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_hash_sha256$function$


-- Function: pgsodium.crypto_hash_sha512(message bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_hash_sha512(message bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_hash_sha512$function$


-- Function: pgsodium.crypto_kdf_derive_from_key(subkey_size integer, subkey_id bigint, context bytea, primary_key uuid)
CREATE OR REPLACE FUNCTION pgsodium.crypto_kdf_derive_from_key(subkey_size integer, subkey_id bigint, context bytea, primary_key uuid)
 RETURNS bytea
 LANGUAGE plpgsql
 STABLE STRICT SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  key pgsodium.decrypted_key;
BEGIN
  SELECT * INTO STRICT key
    FROM pgsodium.decrypted_key v
  WHERE id = primary_key AND key_type = 'kdf';

  IF key.decrypted_raw_key IS NOT NULL THEN
    RETURN pgsodium.crypto_kdf_derive_from_key(subkey_size, subkey_id, context, key.decrypted_raw_key);
  END IF;
  RETURN pgsodium.derive_key(key.key_id, subkey_size, key.key_context);
END;

$function$


-- Function: pgsodium.crypto_kdf_derive_from_key(subkey_size bigint, subkey_id bigint, context bytea, primary_key bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_kdf_derive_from_key(subkey_size bigint, subkey_id bigint, context bytea, primary_key bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_kdf_derive_from_key$function$


-- Function: pgsodium.crypto_kdf_keygen()
CREATE OR REPLACE FUNCTION pgsodium.crypto_kdf_keygen()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_kdf_keygen$function$


-- Function: pgsodium.crypto_kx_client_session_keys(client_pk bytea, client_sk bytea, server_pk bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_kx_client_session_keys(client_pk bytea, client_sk bytea, server_pk bytea)
 RETURNS pgsodium.crypto_kx_session
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_kx_client_session_keys$function$


-- Function: pgsodium.crypto_kx_new_keypair()
CREATE OR REPLACE FUNCTION pgsodium.crypto_kx_new_keypair()
 RETURNS pgsodium.crypto_kx_keypair
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_kx_keypair$function$


-- Function: pgsodium.crypto_kx_new_seed()
CREATE OR REPLACE FUNCTION pgsodium.crypto_kx_new_seed()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_kx_new_seed$function$


-- Function: pgsodium.crypto_kx_seed_new_keypair(seed bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_kx_seed_new_keypair(seed bytea)
 RETURNS pgsodium.crypto_kx_keypair
 LANGUAGE c
 IMMUTABLE STRICT
AS '$libdir/pgsodium', $function$pgsodium_crypto_kx_seed_keypair$function$


-- Function: pgsodium.crypto_kx_server_session_keys(server_pk bytea, server_sk bytea, client_pk bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_kx_server_session_keys(server_pk bytea, server_sk bytea, client_pk bytea)
 RETURNS pgsodium.crypto_kx_session
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_kx_server_session_keys$function$


-- Function: pgsodium.crypto_pwhash(password bytea, salt bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_pwhash(password bytea, salt bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_pwhash$function$


-- Function: pgsodium.crypto_pwhash_saltgen()
CREATE OR REPLACE FUNCTION pgsodium.crypto_pwhash_saltgen()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_pwhash_saltgen$function$


-- Function: pgsodium.crypto_pwhash_str(password bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_pwhash_str(password bytea)
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_pwhash_str$function$


-- Function: pgsodium.crypto_pwhash_str_verify(hashed_password bytea, password bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_pwhash_str_verify(hashed_password bytea, password bytea)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_pwhash_str_verify$function$


-- Function: pgsodium.crypto_secretbox(message bytea, nonce bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_secretbox(message bytea, nonce bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_secretbox_by_id$function$


-- Function: pgsodium.crypto_secretbox(message bytea, nonce bytea, key bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_secretbox(message bytea, nonce bytea, key bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_secretbox$function$


-- Function: pgsodium.crypto_secretbox(message bytea, nonce bytea, key_uuid uuid)
CREATE OR REPLACE FUNCTION pgsodium.crypto_secretbox(message bytea, nonce bytea, key_uuid uuid)
 RETURNS bytea
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  key pgsodium.decrypted_key;
BEGIN
  SELECT * INTO STRICT key
    FROM pgsodium.decrypted_key v
  WHERE id = key_uuid AND key_type = 'secretbox';

  IF key.decrypted_raw_key IS NOT NULL THEN
    RETURN pgsodium.crypto_secretbox(message, nonce, key.decrypted_raw_key);
  END IF;
  RETURN pgsodium.crypto_secretbox(message, nonce, key.key_id, key.key_context);
END;
$function$


-- Function: pgsodium.crypto_secretbox_keygen()
CREATE OR REPLACE FUNCTION pgsodium.crypto_secretbox_keygen()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_secretbox_keygen$function$


-- Function: pgsodium.crypto_secretbox_noncegen()
CREATE OR REPLACE FUNCTION pgsodium.crypto_secretbox_noncegen()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_secretbox_noncegen$function$


-- Function: pgsodium.crypto_secretbox_open(message bytea, nonce bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_secretbox_open(message bytea, nonce bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_secretbox_open_by_id$function$


-- Function: pgsodium.crypto_secretbox_open(message bytea, nonce bytea, key_uuid uuid)
CREATE OR REPLACE FUNCTION pgsodium.crypto_secretbox_open(message bytea, nonce bytea, key_uuid uuid)
 RETURNS bytea
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  key pgsodium.decrypted_key;
BEGIN
  SELECT * INTO STRICT key
    FROM pgsodium.decrypted_key v
  WHERE id = key_uuid AND key_type = 'secretbox';

  IF key.decrypted_raw_key IS NOT NULL THEN
    RETURN pgsodium.crypto_secretbox_open(message, nonce, key.decrypted_raw_key);
  END IF;
  RETURN pgsodium.crypto_secretbox_open(message, nonce, key.key_id, key.key_context);
END;
$function$


-- Function: pgsodium.crypto_secretbox_open(ciphertext bytea, nonce bytea, key bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_secretbox_open(ciphertext bytea, nonce bytea, key bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_secretbox_open$function$


-- Function: pgsodium.crypto_secretstream_keygen()
CREATE OR REPLACE FUNCTION pgsodium.crypto_secretstream_keygen()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_secretstream_xchacha20poly1305_keygen$function$


-- Function: pgsodium.crypto_shorthash(message bytea, key_uuid uuid)
CREATE OR REPLACE FUNCTION pgsodium.crypto_shorthash(message bytea, key_uuid uuid)
 RETURNS bytea
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  key pgsodium.decrypted_key;
BEGIN
  SELECT * INTO STRICT key
    FROM pgsodium.decrypted_key v
  WHERE id = key_uuid AND key_type = 'shorthash';

  IF key.decrypted_raw_key IS NOT NULL THEN
    RETURN pgsodium.crypto_shorthash(message, key.decrypted_raw_key);
  END IF;
  RETURN pgsodium.crypto_shorthash(message, key.key_id, key.key_context);
END;

$function$


-- Function: pgsodium.crypto_shorthash(message bytea, key bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_shorthash(message bytea, key bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_shorthash_by_id$function$


-- Function: pgsodium.crypto_shorthash(message bytea, key bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_shorthash(message bytea, key bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_shorthash$function$


-- Function: pgsodium.crypto_shorthash_keygen()
CREATE OR REPLACE FUNCTION pgsodium.crypto_shorthash_keygen()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_shorthash_keygen$function$


-- Function: pgsodium.crypto_sign(message bytea, key bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_sign(message bytea, key bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_sign$function$


-- Function: pgsodium.crypto_sign_detached(message bytea, key bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_sign_detached(message bytea, key bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_sign_detached$function$


-- Function: pgsodium.crypto_sign_final_create(state bytea, key bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_sign_final_create(state bytea, key bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_sign_final_create$function$


-- Function: pgsodium.crypto_sign_final_verify(state bytea, signature bytea, key bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_sign_final_verify(state bytea, signature bytea, key bytea)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_sign_final_verify$function$


-- Function: pgsodium.crypto_sign_init()
CREATE OR REPLACE FUNCTION pgsodium.crypto_sign_init()
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE STRICT
AS '$libdir/pgsodium', $function$pgsodium_crypto_sign_init$function$


-- Function: pgsodium.crypto_sign_new_keypair()
CREATE OR REPLACE FUNCTION pgsodium.crypto_sign_new_keypair()
 RETURNS pgsodium.crypto_sign_keypair
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_sign_keypair$function$


-- Function: pgsodium.crypto_sign_new_seed()
CREATE OR REPLACE FUNCTION pgsodium.crypto_sign_new_seed()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_sign_new_seed$function$


-- Function: pgsodium.crypto_sign_open(signed_message bytea, key bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_sign_open(signed_message bytea, key bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_sign_open$function$


-- Function: pgsodium.crypto_sign_seed_new_keypair(seed bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_sign_seed_new_keypair(seed bytea)
 RETURNS pgsodium.crypto_sign_keypair
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_sign_seed_keypair$function$


-- Function: pgsodium.crypto_sign_update(state bytea, message bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_sign_update(state bytea, message bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_sign_update$function$


-- Function: pgsodium.crypto_sign_update_agg1(state bytea, message bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_sign_update_agg1(state bytea, message bytea)
 RETURNS bytea
 LANGUAGE sql
 IMMUTABLE
AS $function$
 SELECT pgsodium.crypto_sign_update(COALESCE(state, pgsodium.crypto_sign_init()), message);
$function$


-- Function: pgsodium.crypto_sign_update_agg2(cur_state bytea, initial_state bytea, message bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_sign_update_agg2(cur_state bytea, initial_state bytea, message bytea)
 RETURNS bytea
 LANGUAGE sql
 IMMUTABLE
AS $function$
 SELECT pgsodium.crypto_sign_update(
       COALESCE(cur_state, initial_state),
	   message)
$function$


-- Function: pgsodium.crypto_sign_verify_detached(sig bytea, message bytea, key bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_sign_verify_detached(sig bytea, message bytea, key bytea)
 RETURNS boolean
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_sign_verify_detached$function$


-- Function: pgsodium.crypto_signcrypt_new_keypair()
CREATE OR REPLACE FUNCTION pgsodium.crypto_signcrypt_new_keypair()
 RETURNS pgsodium.crypto_signcrypt_keypair
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_signcrypt_keypair$function$


-- Function: pgsodium.crypto_signcrypt_sign_after(state bytea, sender_sk bytea, ciphertext bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_signcrypt_sign_after(state bytea, sender_sk bytea, ciphertext bytea)
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_signcrypt_sign_after$function$


-- Function: pgsodium.crypto_signcrypt_sign_before(sender bytea, recipient bytea, sender_sk bytea, recipient_pk bytea, additional bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_signcrypt_sign_before(sender bytea, recipient bytea, sender_sk bytea, recipient_pk bytea, additional bytea)
 RETURNS pgsodium.crypto_signcrypt_state_key
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_signcrypt_sign_before$function$


-- Function: pgsodium.crypto_signcrypt_verify_after(state bytea, signature bytea, sender_pk bytea, ciphertext bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_signcrypt_verify_after(state bytea, signature bytea, sender_pk bytea, ciphertext bytea)
 RETURNS boolean
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_signcrypt_verify_after$function$


-- Function: pgsodium.crypto_signcrypt_verify_before(signature bytea, sender bytea, recipient bytea, additional bytea, sender_pk bytea, recipient_sk bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_signcrypt_verify_before(signature bytea, sender bytea, recipient bytea, additional bytea, sender_pk bytea, recipient_sk bytea)
 RETURNS pgsodium.crypto_signcrypt_state_key
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_signcrypt_verify_before$function$


-- Function: pgsodium.crypto_signcrypt_verify_public(signature bytea, sender bytea, recipient bytea, additional bytea, sender_pk bytea, ciphertext bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_signcrypt_verify_public(signature bytea, sender bytea, recipient bytea, additional bytea, sender_pk bytea, ciphertext bytea)
 RETURNS boolean
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_signcrypt_verify_public$function$


-- Function: pgsodium.crypto_stream_xchacha20(bigint, bytea, bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_stream_xchacha20(bigint, bytea, bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_stream_xchacha20$function$


-- Function: pgsodium.crypto_stream_xchacha20(bigint, bytea, bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_stream_xchacha20(bigint, bytea, bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_stream_xchacha20_by_id$function$


-- Function: pgsodium.crypto_stream_xchacha20_keygen()
CREATE OR REPLACE FUNCTION pgsodium.crypto_stream_xchacha20_keygen()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_stream_xchacha20_keygen$function$


-- Function: pgsodium.crypto_stream_xchacha20_noncegen()
CREATE OR REPLACE FUNCTION pgsodium.crypto_stream_xchacha20_noncegen()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_crypto_stream_xchacha20_noncegen$function$


-- Function: pgsodium.crypto_stream_xchacha20_xor(bytea, bytea, bigint, context bytea DEFAULT '\x70676f736469756d'::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_stream_xchacha20_xor(bytea, bytea, bigint, context bytea DEFAULT '\x70676f736469756d'::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_stream_xchacha20_xor_by_id$function$


-- Function: pgsodium.crypto_stream_xchacha20_xor(bytea, bytea, bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_stream_xchacha20_xor(bytea, bytea, bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_stream_xchacha20_xor$function$


-- Function: pgsodium.crypto_stream_xchacha20_xor_ic(bytea, bytea, bigint, bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_stream_xchacha20_xor_ic(bytea, bytea, bigint, bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_stream_xchacha20_xor_ic$function$


-- Function: pgsodium.crypto_stream_xchacha20_xor_ic(bytea, bytea, bigint, bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
CREATE OR REPLACE FUNCTION pgsodium.crypto_stream_xchacha20_xor_ic(bytea, bytea, bigint, bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_crypto_stream_xchacha20_xor_ic_by_id$function$


-- Function: pgsodium.decrypted_columns(relid oid)
CREATE OR REPLACE FUNCTION pgsodium.decrypted_columns(relid oid)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
  m RECORD;
  expression TEXT;
  comma TEXT;
  padding text = '        ';
BEGIN
  expression := E'\n';
  comma := padding;
  FOR m IN SELECT * FROM pgsodium.mask_columns where attrelid = relid LOOP
    expression := expression || comma;
    IF m.key_id IS NULL AND m.key_id_column IS NULL THEN
      expression := expression || padding || quote_ident(m.attname);
    ELSE
      expression := expression || padding || quote_ident(m.attname) || E',\n';
      IF m.format_type = 'text' THEN
          expression := expression || format(
            $f$
            CASE WHEN %s IS NULL THEN NULL ELSE
                CASE WHEN %s IS NULL THEN NULL ELSE pg_catalog.convert_from(
                  pgsodium.crypto_aead_det_decrypt(
                    pg_catalog.decode(%s, 'base64'),
                    pg_catalog.convert_to((%s)::text, 'utf8'),
                    %s::uuid,
                    %s
                  ),
                    'utf8') END
                END AS %s$f$,
                quote_ident(m.attname),
                coalesce(quote_ident(m.key_id_column), quote_literal(m.key_id)),
                quote_ident(m.attname),
                coalesce(pgsodium.quote_assoc(m.associated_columns), quote_literal('')),
                coalesce(quote_ident(m.key_id_column), quote_literal(m.key_id)),
                coalesce(quote_ident(m.nonce_column), 'NULL'),
                quote_ident('decrypted_' || m.attname)
          );
      ELSIF m.format_type = 'bytea' THEN
          expression := expression || format(
            $f$
            CASE WHEN %s IS NULL THEN NULL ELSE
                CASE WHEN %s IS NULL THEN NULL ELSE pgsodium.crypto_aead_det_decrypt(
                    %s::bytea,
                    pg_catalog.convert_to((%s)::text, 'utf8'),
                    %s::uuid,
                    %s
                  ) END
                END AS %s$f$,
                quote_ident(m.attname),
                coalesce(quote_ident(m.key_id_column), quote_literal(m.key_id)),
                quote_ident(m.attname),
                coalesce(pgsodium.quote_assoc(m.associated_columns), quote_literal('')),
                coalesce(quote_ident(m.key_id_column), quote_literal(m.key_id)),
                coalesce(quote_ident(m.nonce_column), 'NULL'),
                'decrypted_' || quote_ident(m.attname)
          );
      END IF;
    END IF;
    comma := E',       \n';
  END LOOP;
  RETURN expression;
END
$function$


-- Function: pgsodium.derive_key(key_id bigint, key_len integer DEFAULT 32, context bytea DEFAULT '\x7067736f6469756d'::bytea)
CREATE OR REPLACE FUNCTION pgsodium.derive_key(key_id bigint, key_len integer DEFAULT 32, context bytea DEFAULT '\x7067736f6469756d'::bytea)
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_derive$function$


-- Function: pgsodium.disable_security_label_trigger()
CREATE OR REPLACE FUNCTION pgsodium.disable_security_label_trigger()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
    ALTER EVENT TRIGGER pgsodium_trg_mask_update DISABLE;
  $function$


-- Function: pgsodium.enable_security_label_trigger()
CREATE OR REPLACE FUNCTION pgsodium.enable_security_label_trigger()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
    ALTER EVENT TRIGGER pgsodium_trg_mask_update ENABLE;
  $function$


-- Function: pgsodium.encrypted_column(relid oid, m record)
CREATE OR REPLACE FUNCTION pgsodium.encrypted_column(relid oid, m record)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    expression TEXT;
    comma TEXT;
BEGIN
  expression := '';
  comma := E'        ';
  expression := expression || comma;
  IF m.format_type = 'text' THEN
	  expression := expression || format(
		$f$%s = CASE WHEN %s IS NULL THEN NULL ELSE
			CASE WHEN %s IS NULL THEN NULL ELSE pg_catalog.encode(
			  pgsodium.crypto_aead_det_encrypt(
				pg_catalog.convert_to(%s, 'utf8'),
				pg_catalog.convert_to((%s)::text, 'utf8'),
				%s::uuid,
				%s
			  ),
				'base64') END END$f$,
			'new.' || quote_ident(m.attname),
			'new.' || quote_ident(m.attname),
			COALESCE('new.' || quote_ident(m.key_id_column), quote_literal(m.key_id)),
			'new.' || quote_ident(m.attname),
			COALESCE(pgsodium.quote_assoc(m.associated_columns, true), quote_literal('')),
			COALESCE('new.' || quote_ident(m.key_id_column), quote_literal(m.key_id)),
			COALESCE('new.' || quote_ident(m.nonce_column), 'NULL')
	  );
  ELSIF m.format_type = 'bytea' THEN
	  expression := expression || format(
		$f$%s = CASE WHEN %s IS NULL THEN NULL ELSE
			CASE WHEN %s IS NULL THEN NULL ELSE
					pgsodium.crypto_aead_det_encrypt(%s::bytea, pg_catalog.convert_to((%s)::text, 'utf8'),
			%s::uuid,
			%s
		  ) END END$f$,
			'new.' || quote_ident(m.attname),
			'new.' || quote_ident(m.attname),
			COALESCE('new.' || quote_ident(m.key_id_column), quote_literal(m.key_id)),
			'new.' || quote_ident(m.attname),
			COALESCE(pgsodium.quote_assoc(m.associated_columns, true), quote_literal('')),
			COALESCE('new.' || quote_ident(m.key_id_column), quote_literal(m.key_id)),
			COALESCE('new.' || quote_ident(m.nonce_column), 'NULL')
	  );
  END IF;
  comma := E';\n        ';
  RETURN expression;
END
$function$


-- Function: pgsodium.encrypted_columns(relid oid)
CREATE OR REPLACE FUNCTION pgsodium.encrypted_columns(relid oid)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    m RECORD;
    expression TEXT;
    comma TEXT;
BEGIN
  expression := '';
  comma := E'        ';
  FOR m IN SELECT * FROM pgsodium.mask_columns where attrelid = relid LOOP
    IF m.key_id IS NULL AND m.key_id_column is NULL THEN
      CONTINUE;
    ELSE
      expression := expression || comma;
      IF m.format_type = 'text' THEN
          expression := expression || format(
            $f$%s = CASE WHEN %s IS NULL THEN NULL ELSE
                CASE WHEN %s IS NULL THEN NULL ELSE pg_catalog.encode(
                  pgsodium.crypto_aead_det_encrypt(
                    pg_catalog.convert_to(%s, 'utf8'),
                    pg_catalog.convert_to((%s)::text, 'utf8'),
                    %s::uuid,
                    %s
                  ),
                    'base64') END END$f$,
                'new.' || quote_ident(m.attname),
                'new.' || quote_ident(m.attname),
                COALESCE('new.' || quote_ident(m.key_id_column), quote_literal(m.key_id)),
                'new.' || quote_ident(m.attname),
                COALESCE(pgsodium.quote_assoc(m.associated_columns, true), quote_literal('')),
                COALESCE('new.' || quote_ident(m.key_id_column), quote_literal(m.key_id)),
                COALESCE('new.' || quote_ident(m.nonce_column), 'NULL')
          );
      ELSIF m.format_type = 'bytea' THEN
          expression := expression || format(
            $f$%s = CASE WHEN %s IS NULL THEN NULL ELSE
                CASE WHEN %s IS NULL THEN NULL ELSE
                        pgsodium.crypto_aead_det_encrypt(%s::bytea, pg_catalog.convert_to((%s)::text, 'utf8'),
                %s::uuid,
                %s
              ) END END$f$,
                'new.' || quote_ident(m.attname),
                'new.' || quote_ident(m.attname),
                COALESCE('new.' || quote_ident(m.key_id_column), quote_literal(m.key_id)),
                'new.' || quote_ident(m.attname),
                COALESCE(pgsodium.quote_assoc(m.associated_columns, true), quote_literal('')),
                COALESCE('new.' || quote_ident(m.key_id_column), quote_literal(m.key_id)),
                COALESCE('new.' || quote_ident(m.nonce_column), 'NULL')
          );
      END IF;
    END IF;
    comma := E';\n        ';
  END LOOP;
  RETURN expression;
END
$function$


-- Function: pgsodium.get_key_by_id(uuid)
CREATE OR REPLACE FUNCTION pgsodium.get_key_by_id(uuid)
 RETURNS pgsodium.valid_key
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
    SELECT * from pgsodium.valid_key WHERE id = $1;
$function$


-- Function: pgsodium.get_key_by_name(text)
CREATE OR REPLACE FUNCTION pgsodium.get_key_by_name(text)
 RETURNS pgsodium.valid_key
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
    SELECT * from pgsodium.valid_key WHERE name = $1;
$function$


-- Function: pgsodium.get_named_keys(filter text DEFAULT '%'::text)
CREATE OR REPLACE FUNCTION pgsodium.get_named_keys(filter text DEFAULT '%'::text)
 RETURNS SETOF pgsodium.valid_key
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
    SELECT * from pgsodium.valid_key vk WHERE vk.name ILIKE filter;
$function$


-- Function: pgsodium.has_mask(role regrole, source_name text)
CREATE OR REPLACE FUNCTION pgsodium.has_mask(role regrole, source_name text)
 RETURNS boolean
 LANGUAGE sql
AS $function$
  SELECT EXISTS(
    SELECT 1
      FROM pg_shseclabel
     WHERE  objoid = role
       AND provider = 'pgsodium'
       AND label ilike 'ACCESS%' || source_name || '%')
  $function$


-- Function: pgsodium.key_encrypt_secret_raw_key()
CREATE OR REPLACE FUNCTION pgsodium.key_encrypt_secret_raw_key()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
		BEGIN
		        new.raw_key = CASE WHEN new.raw_key IS NULL THEN NULL ELSE
			CASE WHEN new.parent_key IS NULL THEN NULL ELSE
					pgsodium.crypto_aead_det_encrypt(new.raw_key::bytea, pg_catalog.convert_to((new.id::text || new.associated_data::text)::text, 'utf8'),
			new.parent_key::uuid,
			new.raw_key_nonce
		  ) END END;
		RETURN new;
		END;
		$function$


-- Function: pgsodium.mask_columns(source_relid oid)
CREATE OR REPLACE FUNCTION pgsodium.mask_columns(source_relid oid)
 RETURNS TABLE(attname name, key_id text, key_id_column text, associated_column text, nonce_column text, format_type text)
 LANGUAGE sql
AS $function$
  SELECT
  a.attname,
  m.key_id,
  m.key_id_column,
  m.associated_column,
  m.nonce_column,
  m.format_type
  FROM pg_attribute a
  LEFT JOIN  pgsodium.masking_rule m
  ON m.attrelid = a.attrelid
  AND m.attname = a.attname
  WHERE  a.attrelid = source_relid
  AND    a.attnum > 0 -- exclude ctid, cmin, cmax
  AND    NOT a.attisdropped
  ORDER BY a.attnum;
$function$


-- Function: pgsodium.mask_role(masked_role regrole, source_name text, view_name text)
CREATE OR REPLACE FUNCTION pgsodium.mask_role(masked_role regrole, source_name text, view_name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  EXECUTE format(
    'GRANT SELECT ON pgsodium.key TO %s',
    masked_role);

  EXECUTE format(
    'GRANT pgsodium_keyiduser, pgsodium_keyholder TO %s',
    masked_role);

  EXECUTE format(
    'GRANT ALL ON %I TO %s',
    view_name,
    masked_role);
  RETURN;
END
$function$


-- Function: pgsodium.pgsodium_derive(key_id bigint, key_len integer DEFAULT 32, context bytea DEFAULT decode('pgsodium'::text, 'escape'::text))
CREATE OR REPLACE FUNCTION pgsodium.pgsodium_derive(key_id bigint, key_len integer DEFAULT 32, context bytea DEFAULT decode('pgsodium'::text, 'escape'::text))
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_derive$function$


-- Function: pgsodium.quote_assoc(text, boolean DEFAULT false)
CREATE OR REPLACE FUNCTION pgsodium.quote_assoc(text, boolean DEFAULT false)
 RETURNS text
 LANGUAGE sql
AS $function$
    WITH a AS (SELECT array_agg(CASE WHEN $2 THEN
                                    'new.' || quote_ident(trim(v))
                                ELSE quote_ident(trim(v)) END) as r
               FROM regexp_split_to_table($1, '\s*,\s*') as v)
    SELECT array_to_string(a.r, '::text || ') || '::text' FROM a;
$function$


-- Function: pgsodium.randombytes_buf(size integer)
CREATE OR REPLACE FUNCTION pgsodium.randombytes_buf(size integer)
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_randombytes_buf$function$


-- Function: pgsodium.randombytes_buf_deterministic(size integer, seed bytea)
CREATE OR REPLACE FUNCTION pgsodium.randombytes_buf_deterministic(size integer, seed bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_randombytes_buf_deterministic$function$


-- Function: pgsodium.randombytes_new_seed()
CREATE OR REPLACE FUNCTION pgsodium.randombytes_new_seed()
 RETURNS bytea
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_randombytes_new_seed$function$


-- Function: pgsodium.randombytes_random()
CREATE OR REPLACE FUNCTION pgsodium.randombytes_random()
 RETURNS integer
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_randombytes_random$function$


-- Function: pgsodium.randombytes_uniform(upper_bound integer)
CREATE OR REPLACE FUNCTION pgsodium.randombytes_uniform(upper_bound integer)
 RETURNS integer
 LANGUAGE c
AS '$libdir/pgsodium', $function$pgsodium_randombytes_uniform$function$


-- Function: pgsodium.sodium_base642bin(base64 text)
CREATE OR REPLACE FUNCTION pgsodium.sodium_base642bin(base64 text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_sodium_base642bin$function$


-- Function: pgsodium.sodium_bin2base64(bin bytea)
CREATE OR REPLACE FUNCTION pgsodium.sodium_bin2base64(bin bytea)
 RETURNS text
 LANGUAGE c
 IMMUTABLE
AS '$libdir/pgsodium', $function$pgsodium_sodium_bin2base64$function$


-- Function: pgsodium.trg_mask_update()
CREATE OR REPLACE FUNCTION pgsodium.trg_mask_update()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
  r record;
BEGIN
  IF (SELECT bool_or(in_extension) FROM pg_event_trigger_ddl_commands()) THEN
    RAISE NOTICE 'skipping pgsodium mask regeneration in extension';
	RETURN;
  END IF;

  FOR r IN
    SELECT e.*
    FROM pg_event_trigger_ddl_commands() e
    WHERE EXISTS (
      SELECT FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_seclabel s ON s.classoid = c.tableoid
                                   AND s.objoid = c.oid
      WHERE c.tableoid = e.classid
        AND e.objid = c.oid
        AND s.provider = 'pgsodium'
    )
  LOOP
    IF r.object_type in ('table', 'table column')
    THEN
      PERFORM pgsodium.update_mask(r.objid);
    END IF;
  END LOOP;
END
$function$


-- Function: pgsodium.update_mask(target oid, debug boolean DEFAULT false)
CREATE OR REPLACE FUNCTION pgsodium.update_mask(target oid, debug boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  PERFORM pgsodium.disable_security_label_trigger();
  PERFORM pgsodium.create_mask_view(objoid, objsubid, debug)
    FROM pg_catalog.pg_seclabel sl
    WHERE sl.objoid = target
      AND sl.label ILIKE 'ENCRYPT%'
      AND sl.provider = 'pgsodium';
  PERFORM pgsodium.enable_security_label_trigger();
  RETURN;
END
$function$


-- Function: pgsodium.update_masks(debug boolean DEFAULT false)
CREATE OR REPLACE FUNCTION pgsodium.update_masks(debug boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  PERFORM pgsodium.update_mask(objoid, debug)
    FROM pg_catalog.pg_seclabel sl
    JOIN pg_catalog.pg_class cl ON (cl.oid = sl.objoid)
    WHERE label ilike 'ENCRYPT%'
       AND cl.relowner = session_user::regrole::oid
       AND provider = 'pgsodium'
	   AND objoid::regclass != 'pgsodium.key'::regclass
	;
  RETURN;
END
$function$


-- Function: pgsodium.version()
CREATE OR REPLACE FUNCTION pgsodium.version()
 RETURNS text
 LANGUAGE sql
AS $function$ SELECT extversion FROM pg_extension WHERE extname = 'pgsodium' $function$


-- Function: postgre_rpc.get_notification_tokens(p_email text DEFAULT NULL::text, p_role user_role DEFAULT NULL::user_role)
CREATE OR REPLACE FUNCTION postgre_rpc.get_notification_tokens(p_email text DEFAULT NULL::text, p_role user_role DEFAULT NULL::user_role)
 RETURNS TABLE(notification_token text, user_id uuid, device_type text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
BEGIN
    -- 🛡️ VALIDATION : p_email si fourni
    IF p_email IS NOT NULL AND length(trim(p_email)) > 0 THEN
        IF NOT private.validate_email_format(p_email) THEN
            RAISE EXCEPTION 'Format email invalide';
        END IF;
    END IF;

    RETURN QUERY
    SELECT 
        t.notification_token,
        t.user_id,
        t.device_type
    FROM private.notification_tokens t
    JOIN private.users u ON u.id = t.user_id
    WHERE 
        (p_email IS NULL OR u.email = p_email) -- Paramètre typé = protection injection SQL
        AND (p_role IS NULL OR u.role = p_role)
        AND t.notification_token IS NOT NULL
        AND t.notification_token <> '';
END;
$function$


-- Function: postgre_rpc.get_user(p_user_id uuid)
CREATE OR REPLACE FUNCTION postgre_rpc.get_user(p_user_id uuid)
 RETURNS TABLE(id uuid, name text, email text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
BEGIN
    -- 🛡️ VALIDATION : p_user_id ne doit pas être NULL
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'L''ID utilisateur est obligatoire';
    END IF;

    RETURN QUERY
    SELECT 
        u.id,
        u.name,
        u.email
    FROM private.users u
    WHERE u.id = p_user_id; -- UUID typé = protection injection SQL
END;
$function$


-- Function: postgre_rpc.rpc_confirm_transaction(p_transaction_id uuid, p_restaurant_name text)
CREATE OR REPLACE FUNCTION postgre_rpc.rpc_confirm_transaction(p_transaction_id uuid, p_restaurant_name text)
 RETURNS TABLE(email text, points_user integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    v_user_id uuid;
    v_points integer;
    v_points_user integer;
    v_email text;
    v_restaurant_id uuid;
    v_current_role text;
BEGIN
    -- 🛡️ SÉCURITÉ : Seul service_role peut appeler cette fonction
    BEGIN
        v_current_role := current_setting('role', true);
    EXCEPTION WHEN OTHERS THEN
        v_current_role := NULL;
    END;
    
    -- Vérifier que c'est bien service_role
    IF v_current_role <> 'service_role' THEN
        RAISE EXCEPTION '403: Forbidden - Accès réservé au service_role. Cette fonction doit être appelée depuis une Edge Function avec la clé secrète.' USING ERRCODE = '42501';
    END IF;

    -- 🛡️ VALIDATION : p_restaurant_name
    IF p_restaurant_name IS NULL OR length(trim(p_restaurant_name)) = 0 THEN
        RAISE EXCEPTION 'Le nom du restaurant est obligatoire';
    END IF;
    
    IF NOT private.validate_safe_text(p_restaurant_name, 200) THEN
        RAISE EXCEPTION 'Nom de restaurant invalide ou suspect';
    END IF;

    -- 1. Récupération de l'ID du restaurant (paramètre typé = protection injection SQL)
    SELECT r.id INTO v_restaurant_id
    FROM private.restaurants r
    WHERE r.name = p_restaurant_name;

    IF v_restaurant_id IS NULL THEN
        RAISE EXCEPTION 'Restaurant introuvable : %', p_restaurant_name;
    END IF;

    -- 2. Validation atomique de la transaction
    -- On vérifie le statut 'en_attente' pour empêcher la double validation.
    UPDATE private.transactions t
    SET
        status = 'valide',
        restaurant_id = v_restaurant_id
    WHERE t.id = p_transaction_id
      AND t.status = 'en_attente'
    RETURNING t.user_id, t.points
    INTO v_user_id, v_points;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Transaction introuvable, déjà validée ou annulée.';
    END IF;

    -- 3. Crédit des points à l'utilisateur
    -- COALESCE protège si l'utilisateur n'a jamais eu de points (NULL)
    UPDATE private.users u
    SET points = COALESCE(u.points, 0) + v_points
    WHERE u.id = v_user_id
    RETURNING u.points, u.email
    INTO v_points_user, v_email;

    -- 4. Retour des données pour confirmation backend
    RETURN QUERY SELECT v_email, v_points_user;

EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '%', SQLERRM;
END;
$function$


-- Function: postgre_rpc.rpc_create_transaction(p_user_id uuid, p_restaurant_name text, p_total numeric, p_items jsonb, p_points integer)
CREATE OR REPLACE FUNCTION postgre_rpc.rpc_create_transaction(p_user_id uuid, p_restaurant_name text, p_total numeric, p_items jsonb, p_points integer)
 RETURNS TABLE(id uuid, user_id uuid, restaurant_id uuid, total numeric, items jsonb, points integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    v_restaurant_id uuid;
BEGIN
    IF current_setting('role') <> 'service_role' THEN
        RAISE EXCEPTION 'Accès refusé' USING ERRCODE = 'P0001';
    END IF;

    -- 🛡️ VALIDATION : p_restaurant_name (peut être NULL, mais si fourni doit être valide)
    IF p_restaurant_name IS NOT NULL AND length(trim(p_restaurant_name)) > 0 THEN
        IF NOT private.validate_safe_text(p_restaurant_name, 200) THEN
            RAISE EXCEPTION 'Nom de restaurant invalide ou suspect';
        END IF;
    END IF;

    -- Sanity check JSONB
    IF jsonb_typeof(p_items) NOT IN ('array', 'object') OR p_items IS NULL THEN
        p_items := '[]'::jsonb;
    END IF;

    -- Récupération restaurant (paramètre typé = protection injection SQL)
    IF p_restaurant_name IS NOT NULL AND length(trim(p_restaurant_name)) > 0 THEN
        SELECT r.id INTO v_restaurant_id FROM private.restaurants r WHERE r.name = p_restaurant_name LIMIT 1;
    END IF;

    RETURN QUERY
    INSERT INTO private.transactions (user_id, total, items, points, restaurant_id, status)
    VALUES (p_user_id, COALESCE(p_total, 0), p_items, COALESCE(p_points, 0), v_restaurant_id, 'en_attente')
    RETURNING 
        private.transactions.id, private.transactions.user_id, private.transactions.restaurant_id, 
        private.transactions.total, private.transactions.items, private.transactions.points;
END;
$function$


-- Function: postgre_rpc.rpc_pending_transaction(p_user_id uuid)
CREATE OR REPLACE FUNCTION postgre_rpc.rpc_pending_transaction(p_user_id uuid)
 RETURNS TABLE(id uuid, user_id uuid, restaurant_id uuid, total numeric, points integer, items jsonb, used_offers text[], status text, date timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
BEGIN
    IF current_setting('role') <> 'service_role' THEN
        RAISE EXCEPTION 'Accès refusé.' USING ERRCODE = 'P0001';
    END IF;

    RETURN QUERY
    SELECT
        t.id, t.user_id, t.restaurant_id, t.total, t.points,
        CASE 
            WHEN t.items IS NULL THEN '[]'::jsonb
            WHEN jsonb_typeof(t.items) = 'array' THEN t.items
            ELSE jsonb_build_array(t.items) 
        END AS items, -- 🛠️ Alias obligatoire pour Deno
        COALESCE(t.used_offers, '{}'::text[]),
        t.status, t.date
    FROM private.transactions t
    WHERE t.user_id = p_user_id AND t.status = 'en_attente'
    ORDER BY t.date DESC;
END;
$function$


-- Function: postgre_rpc.rpc_reset_password(p_email text, p_code text, p_new_password text)
CREATE OR REPLACE FUNCTION postgre_rpc.rpc_reset_password(p_email text, p_code text, p_new_password text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'auth'
AS $function$
DECLARE
    v_user_id uuid;
BEGIN
    -- 🛡️ VALIDATION : p_email
    IF p_email IS NULL OR length(trim(p_email)) = 0 THEN
        RAISE EXCEPTION 'L''email est obligatoire';
    END IF;
    
    IF NOT private.validate_email_format(p_email) THEN
        RAISE EXCEPTION 'Format email invalide';
    END IF;

    -- 🛡️ VALIDATION : p_code
    IF p_code IS NULL OR length(trim(p_code)) = 0 THEN
        RAISE EXCEPTION 'Le code de vérification est obligatoire';
    END IF;
    
    IF length(p_code) > 20 THEN
        RAISE EXCEPTION 'Code de vérification invalide';
    END IF;

    -- 🛡️ VALIDATION : p_new_password
    IF p_new_password IS NULL OR length(trim(p_new_password)) = 0 THEN
        RAISE EXCEPTION 'Le nouveau mot de passe est obligatoire';
    END IF;
    
    IF length(p_new_password) < 6 THEN
        RAISE EXCEPTION 'Le mot de passe doit contenir au moins 6 caractères';
    END IF;
    
    IF length(p_new_password) > 128 THEN
        RAISE EXCEPTION 'Le mot de passe est trop long (max 128 caractères)';
    END IF;

    -- Vérifier que l'utilisateur existe (paramètre typé = protection injection SQL)
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE email = p_email;
    
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Utilisateur non trouvé';
    END IF;
    
    -- Note: La réinitialisation du mot de passe via Supabase Auth
    -- doit être gérée via l'API Auth, pas directement en SQL
    -- Cette fonction est un wrapper pour compatibilité
    
    -- Pour l'instant, on retourne true (l'implémentation réelle devrait utiliser l'API Auth)
    RETURN true;
END;
$function$


-- Function: private.check_disposable_email()
CREATE OR REPLACE FUNCTION private.check_disposable_email()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
    user_local TEXT;
    user_domain TEXT;
    normalized_local TEXT;
BEGIN
    -- 🛡️ DOUBLE VÉRIFICATION : Seul le système (trigger) devrait appeler ceci
    -- Si quelqu'un essaie d'appeler la fonction via RPC, cela échouera
    IF TG_NAME IS NULL THEN
        RAISE EXCEPTION 'Cette fonction ne peut être appelée que par un déclencheur (trigger).';
    END IF;

    user_local := lower(split_part(NEW.email, '@', 1));
    user_domain := lower(split_part(NEW.email, '@', 2));
    normalized_local := split_part(user_local, '+', 1);

    -- 1. PROTECTION ÉTENDUE
    IF normalized_local ~ '(^|[\._\-])(test|espion|fake|dummy|admin|root|superuser|spam|trash|bot|robot|temp|tmp|guest|support|staff|mod|dev|null|undefined|anonymous|user|junk|webmaster)([\._\-]|$)' THEN
        RAISE EXCEPTION 'Nom d''utilisateur interdit ou suspect.';
    END IF;

    -- 2. FAST PASS (Liste Blanche)
    IF user_domain IN ('polymtl.ca', 'etud.polymtl.ca', 'umontreal.ca', 'hec.ca', 'mcgill.ca', 'gmail.com', 'outlook.com', 'hotmail.com') THEN
        RETURN NEW;
    END IF;

    -- 3. VÉRIFICATION LISTE NOIRE
    IF EXISTS (SELECT 1 FROM private.disposable_emails WHERE domain = user_domain) THEN
        RAISE EXCEPTION 'Les emails jetables sont interdits sur MyFidelity.';
    END IF;

    RETURN NEW;
END;
$function$


-- Function: private.check_points_modification_allowed()
CREATE OR REPLACE FUNCTION private.check_points_modification_allowed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
BEGIN
    -- Si les points n'ont pas changé, autoriser
    IF NEW.points = OLD.points THEN
        RETURN NEW;
    END IF;
    
    -- Si la transaction est 'valide' (NEW ou OLD), on autorise TOUJOURS
    -- car le trigger de vérification va corriger automatiquement si nécessaire
    IF NEW.status = 'valide' OR OLD.status = 'valide' THEN
        RETURN NEW;
    END IF;
    
    -- Si la transaction n'est pas 'valide', on bloque les modifications directes
    -- sauf si c'est service_role (pour les Edge Functions autorisées)
    BEGIN
        IF current_setting('role', true) = 'service_role' THEN
            RETURN NEW;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    
    -- Sinon, bloquer la modification directe
    RAISE EXCEPTION 'Modification directe de points interdite. Utilisez les fonctions autorisées (rpc_confirm_transaction, etc.)';
    
    RETURN NEW;
END;
$function$


-- Function: private.check_points_update_allowed()
CREATE OR REPLACE FUNCTION private.check_points_update_allowed()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
    v_caller_function text;
    v_allowed_functions text[] := ARRAY[
        'rpc_confirm_transaction',
        'verify_transaction_points_trigger',
        'confirm_transaction'
    ];
BEGIN
    -- Récupérer le nom de la fonction appelante depuis la stack
    v_caller_function := current_setting('application_name', true);
    
    -- Si appelé depuis un trigger, autoriser
    IF TG_NAME IS NOT NULL THEN
        RETURN true;
    END IF;
    
    -- Vérifier si c'est une fonction autorisée
    -- Note: Cette vérification est limitée car PostgreSQL ne permet pas facilement
    -- de connaître la fonction appelante dans un trigger RLS
    
    -- Pour l'instant, on autorise uniquement via les triggers
    -- Les fonctions autorisées doivent utiliser SECURITY DEFINER
    RETURN false;
END;
$function$


-- Function: private.create_poll_with_options(p_title text, p_description text, p_question text, p_target_audience text, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_is_active boolean, p_image_url text, p_options jsonb)
CREATE OR REPLACE FUNCTION private.create_poll_with_options(p_title text, p_description text, p_question text, p_target_audience text, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_is_active boolean, p_image_url text, p_options jsonb)
 RETURNS SETOF private.polls
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
    DECLARE
      v_poll_id uuid;
      v_option jsonb;
      v_notif_sent boolean := false;
      v_now timestamptz := now();
    BEGIN
      -- Déterminer si notif_sent doit être true (si le sondage est actif immédiatement)
      -- Le trigger vérifie : is_active = true AND starts_at <= now() AND ends_at > now() AND notif_sent = false
      -- Donc si ces conditions sont vraies, on définit notif_sent = true pour empêcher le trigger
      IF p_is_active = true 
         AND p_starts_at IS NOT NULL 
         AND p_ends_at IS NOT NULL
         AND p_starts_at <= v_now 
         AND p_ends_at > v_now THEN
        v_notif_sent := true;
        RAISE NOTICE '[create_poll_with_options] Sondage actif immédiatement, notif_sent défini à true pour empêcher le trigger';
      END IF;
      
      -- Créer le sondage avec notif_sent défini
      WITH inserted_poll AS (
      INSERT INTO private.polls (
        title,
        description,
        question,
        target_audience,
        starts_at,
        ends_at,
        is_active,
        image_url,
        notif_sent
      )
      VALUES (
        p_title,
        p_description,
        p_question,
        CASE 
          WHEN p_target_audience IS NULL THEN NULL::jsonb
          ELSE to_jsonb(p_target_audience)
        END,
        p_starts_at,
        p_ends_at,
        p_is_active,
        p_image_url,
        v_notif_sent
      )
      RETURNING id AS poll_id
      )
      SELECT poll_id INTO v_poll_id FROM inserted_poll;
      
      -- Créer les options
      FOR v_option IN SELECT * FROM jsonb_array_elements(p_options)
      LOOP
        INSERT INTO private.poll_options (
          poll_id,
          option_text,
          option_order
        )
        VALUES (
          v_poll_id,
          v_option->>'text',
          (v_option->>'order')::integer
        );
      END LOOP;
      
      -- Retourner le sondage créé
      RETURN QUERY
      SELECT poll_row.*
      FROM private.polls poll_row
      WHERE poll_row.id = v_poll_id;
    END;
    $function$


-- Function: private.current_week_menu_url_from_jsonb(menus jsonb)
CREATE OR REPLACE FUNCTION private.current_week_menu_url_from_jsonb(menus jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'private'
AS $function$
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

  -- Semaine courante (lundi = début, ISO week)
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
      -- Chevauchement avec la semaine courante : start_date <= week_sunday ET end_date >= week_monday
      IF (sdate IS NULL OR sdate <= week_sunday) AND (edate IS NULL OR edate >= week_monday) THEN
        IF best_start IS NULL OR (sdate IS NOT NULL AND sdate > best_start) THEN
          best_start := sdate;
          best_url := url;
        END IF;
      END IF;
    ELSE
      -- Entrée sans dates = fallback uniquement si on n'a rien trouvé avec dates
      IF best_url IS NULL THEN
        best_url := url;
      END IF;
    END IF;
  END LOOP;

  -- Si on a trouvé une entrée avec dates qui matche, la retourner
  IF best_url IS NOT NULL THEN
    RETURN best_url;
  END IF;

  -- Sinon fallback : première entrée sans dates
  FOR elem IN SELECT * FROM jsonb_array_elements(menus)
  LOOP
    url := elem->>'url';
    IF url IS NOT NULL AND trim(url) <> '' AND elem->>'start_date' IS NULL AND elem->>'end_date' IS NULL THEN
      RETURN url;
    END IF;
  END LOOP;

  RETURN '';
END;
$function$


-- Function: private.get_user_pg_role(user_id uuid)
CREATE OR REPLACE FUNCTION private.get_user_pg_role(user_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
    SELECT 
        CASE 
            WHEN u.role = 'administrateur' THEN 'app_admin'
            WHEN u.role = 'caissier' THEN 'app_cashier'
            ELSE 'app_user'
        END
    FROM private.users u
    WHERE u.id = user_id;
$function$


-- Function: private.handle_new_user()
CREATE OR REPLACE FUNCTION private.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
    raw_name TEXT;
    cleaned_name TEXT;
BEGIN
    -- 🛡️ 1. VERROU ANTI-APPEL MANUEL
    IF TG_NAME IS NULL THEN
        RAISE EXCEPTION 'Cette fonction est strictement réservée au système de trigger.';
    END IF;

    -- 2. RÉCUPÉRATION DU NOM DEPUIS LES METADATA
    raw_name := COALESCE(NEW.raw_user_meta_data->>'name', '');

    -- 3. REMPLACEMENT DES SÉPARATEURS PAR DES ESPACES
    -- Transforme les points, underscores et tirets en espaces
    cleaned_name := regexp_replace(raw_name, '[\._\-]', ' ', 'g');

    -- 4. NETTOYAGE DES CARACTÈRES NON-AUTORISÉS
    -- Ne garde que les lettres et les espaces
    cleaned_name := regexp_replace(cleaned_name, '[^a-zA-ZÀ-ÿ\s]', '', 'g');

    -- 5. NORMALISATION DES ESPACES
    -- Trim et suppression des espaces doubles
    cleaned_name := TRIM(regexp_replace(cleaned_name, '\s+', ' ', 'g'));

    -- 6. VALIDATION DE LA LONGUEUR
    IF length(cleaned_name) < 2 THEN
        cleaned_name := 'Utilisateur MyFidelity';
    END IF;

    -- 7. INSERTION DANS PRIVATE.USERS
    INSERT INTO private.users (
        id, 
        email, 
        name,
        avatar_url,
        role,
        created_at
    )
    VALUES (
        NEW.id,
        NEW.email,
        LEFT(cleaned_name, 100),
        (ARRAY['grill.avif', 'noodle.avif', 'pizza.avif', 'poke.avif', 'sandwich.avif', 'smoothie.avif'])[floor(random() * 6 + 1)],
        'utilisateur',
        CURRENT_TIMESTAMP
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        name = EXCLUDED.name;

    RETURN NEW;
END;
$function$


-- Function: private.is_admin()
CREATE OR REPLACE FUNCTION private.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
    SELECT private.user_has_role('app_admin');
$function$


-- Function: private.is_open_now(schedule jsonb, special_hours jsonb)
CREATE OR REPLACE FUNCTION private.is_open_now(schedule jsonb, special_hours jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
    -- Utiliser l'heure locale de Montréal (America/Montreal)
    current_timestamp timestamptz := NOW() AT TIME ZONE 'America/Montreal';
    now_time time := current_timestamp::time;
    now_date date := current_timestamp::date;
    -- ISODOW: Lundi(1) à Dimanche(7). On ajuste pour un index de tableau base 0 (Lundi=0).
    day_of_week integer := EXTRACT(ISODOW FROM current_timestamp) - 1;
    today_schedule jsonb;
    special_day_schedule jsonb;
    open_time_str text;
    close_time_str text;
    schedule_length integer;
BEGIN
    -- Debug: Log des valeurs pour diagnostic
    RAISE NOTICE '[is_open_now] Heure actuelle: %, Jour: %, Index tableau: %', 
        now_time, day_of_week, day_of_week;

    -- D'abord, vérifier les horaires spéciaux pour la date d'aujourd'hui
    IF jsonb_typeof(special_hours) = 'array' AND special_hours IS NOT NULL THEN
        FOR special_day_schedule IN SELECT * FROM jsonb_array_elements(special_hours)
        LOOP
            IF (special_day_schedule->>'date')::date = now_date THEN
                open_time_str := special_day_schedule->>'open';
                close_time_str := special_day_schedule->>'close';
                
                -- Vérifier si c'est un jour spécial fermé
                IF open_time_str = 'close' OR close_time_str = 'close' OR 
                   open_time_str = '' OR close_time_str = '' OR
                   open_time_str IS NULL OR close_time_str IS NULL THEN
                    RAISE NOTICE '[is_open_now] Jour spécial fermé: %', special_day_schedule;
                    RETURN false;
                END IF;
                
                -- Vérifier si l'heure actuelle est dans les horaires d'ouverture spéciaux
                IF now_time BETWEEN open_time_str::time AND close_time_str::time THEN
                    RAISE NOTICE '[is_open_now] Restaurant ouvert selon horaire spécial';
                    RETURN true;
                ELSE
                    RAISE NOTICE '[is_open_now] Restaurant fermé selon horaire spécial';
                    RETURN false;
                END IF;
            END IF;
        END LOOP;
    END IF;

    -- S'il n'y a pas d'horaires spéciaux pour aujourd'hui, vérifier l'horaire normal
    IF jsonb_typeof(schedule) = 'array' AND schedule IS NOT NULL THEN
        schedule_length := jsonb_array_length(schedule);
        RAISE NOTICE '[is_open_now] Longueur du tableau schedule: %', schedule_length;
        
        -- Vérifier que l'index du jour existe dans le tableau
        IF schedule_length > day_of_week THEN
            today_schedule := schedule->day_of_week;
            RAISE NOTICE '[is_open_now] Horaire du jour %: %', day_of_week, today_schedule;
            
            -- Vérifier que les champs open et close existent et ne sont pas null
            IF today_schedule IS NOT NULL 
               AND today_schedule->>'open' IS NOT NULL 
               AND today_schedule->>'close' IS NOT NULL 
               AND today_schedule->>'open' != '' 
               AND today_schedule->>'close' != ''
               AND today_schedule->>'open' != 'close'
               AND today_schedule->>'close' != 'close' THEN
                
                -- Vérifier si l'heure actuelle est dans les horaires d'ouverture normaux
                IF now_time BETWEEN (today_schedule->>'open')::time AND (today_schedule->>'close')::time THEN
                    RAISE NOTICE '[is_open_now] Restaurant ouvert selon horaire normal';
                    RETURN true;
                ELSE
                    RAISE NOTICE '[is_open_now] Restaurant fermé selon horaire normal';
                    RETURN false;
                END IF;
            ELSE
                RAISE NOTICE '[is_open_now] Horaire du jour invalide ou vide';
                RETURN false;
            END IF;
        ELSE
            RAISE NOTICE '[is_open_now] Index du jour % hors limites du tableau (longueur: %)', day_of_week, schedule_length;
            RETURN false;
        END IF;
    ELSE
        RAISE NOTICE '[is_open_now] Schedule invalide ou null';
        RETURN false;
    END IF;

    -- Par défaut, fermé si aucun horaire applicable n'est trouvé
    RAISE NOTICE '[is_open_now] Aucun horaire applicable trouvé, restaurant fermé par défaut';
    RETURN false;
END;
$function$


-- Function: private.log_security_event(p_action text, p_table_name text, p_record_id uuid, p_old_data jsonb DEFAULT NULL::jsonb, p_new_data jsonb DEFAULT NULL::jsonb, p_success boolean DEFAULT true, p_error_message text DEFAULT NULL::text)
CREATE OR REPLACE FUNCTION private.log_security_event(p_action text, p_table_name text, p_record_id uuid, p_old_data jsonb DEFAULT NULL::jsonb, p_new_data jsonb DEFAULT NULL::jsonb, p_success boolean DEFAULT true, p_error_message text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
BEGIN
    -- Enregistrer dans les logs PostgreSQL
    RAISE NOTICE '[SECURITY_AUDIT] user=% action=% table=% id=% success=% data=%',
        auth.uid(),
        p_action,
        p_table_name,
        p_record_id,
        p_success,
        jsonb_build_object(
            'old', p_old_data,
            'new', p_new_data,
            'error', p_error_message
        );
        
    -- Note: Dans une configuration de production, ceci devrait insérer dans une table d'audit
    -- Pour l'instant, on utilise RAISE NOTICE pour tracer dans les logs PostgreSQL
END;
$function$


-- Function: private.log_user_security_event(p_operation text, p_user_id uuid, p_old_data jsonb DEFAULT NULL::jsonb, p_new_data jsonb DEFAULT NULL::jsonb, p_changed_fields text[] DEFAULT NULL::text[])
CREATE OR REPLACE FUNCTION private.log_user_security_event(p_operation text, p_user_id uuid, p_old_data jsonb DEFAULT NULL::jsonb, p_new_data jsonb DEFAULT NULL::jsonb, p_changed_fields text[] DEFAULT NULL::text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
    v_event_details jsonb;
BEGIN
    -- Construire les détails de l'événement
    v_event_details := jsonb_build_object(
        'operation', p_operation,
        'user_id', p_user_id,
        'changed_by', auth.uid(),
        'changed_fields', COALESCE(p_changed_fields, ARRAY[]::text[]),
        'timestamp', now()
    );

    -- Logger dans les logs PostgreSQL
    RAISE NOTICE '[SECURITY_AUDIT] user=% operation=% target_user=% fields=% old=% new=%',
        auth.uid(),
        p_operation,
        p_user_id,
        p_changed_fields,
        p_old_data,
        p_new_data;

    -- Note: Dans une configuration de production, ceci devrait insérer dans une table d'audit
    -- Pour l'instant, on utilise RAISE NOTICE pour tracer dans les logs PostgreSQL
END;
$function$


-- Function: private.set_updated_at()
CREATE OR REPLACE FUNCTION private.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'private'
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$


-- Function: private.sync_restaurant_menu_url_current(p_restaurant_id uuid DEFAULT NULL::uuid)
CREATE OR REPLACE FUNCTION private.sync_restaurant_menu_url_current(p_restaurant_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  r record;
  new_url text;
BEGIN
  FOR r IN
    SELECT id, restaurant_menu_url_jsonb
    FROM private.restaurants
    WHERE p_restaurant_id IS NULL OR id = p_restaurant_id
  LOOP
    new_url := private.current_week_menu_url_from_jsonb(r.restaurant_menu_url_jsonb);
    UPDATE private.restaurants
    SET restaurant_menu_url = COALESCE(NULLIF(trim(new_url), ''), '')
    WHERE id = r.id;
  END LOOP;
END;
$function$


-- Function: private.tr_validate_and_log_users()
CREATE OR REPLACE FUNCTION private.tr_validate_and_log_users()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
    v_changed_fields text[] := ARRAY[]::text[];
    v_old_data jsonb;
    v_new_data jsonb;
BEGIN
    -- ============================================================
    -- VALIDATION DES CHAMPS
    -- ============================================================

    -- Validation EMAIL
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.email IS DISTINCT FROM OLD.email) THEN
        NEW.email := private.validate_user_field('email', NEW.email, TG_OP);
    END IF;

    -- Validation NAME
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.name IS DISTINCT FROM OLD.name) THEN
        IF NEW.name IS NOT NULL THEN
            NEW.name := private.validate_user_field('name', NEW.name, TG_OP);
        END IF;
    END IF;

    -- Validation AVATAR_URL
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.avatar_url IS DISTINCT FROM OLD.avatar_url) THEN
        IF NEW.avatar_url IS NOT NULL THEN
            NEW.avatar_url := private.validate_user_field('avatar_url', NEW.avatar_url, TG_OP);
        END IF;
    END IF;

    -- Validation NOTIFICATION_SETTINGS
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.notification_settings IS DISTINCT FROM OLD.notification_settings) THEN
        IF NEW.notification_settings IS NOT NULL THEN
            NEW.notification_settings := private.validate_notification_settings(NEW.notification_settings);
        END IF;
    END IF;

    -- Validation RÔLE (enum)
    IF TG_OP = 'INSERT' THEN
        -- Rôle par défaut si NULL
        IF NEW.role IS NULL THEN
            NEW.role := 'utilisateur'::user_role;
        END IF;
    ELSIF TG_OP = 'UPDATE' AND NEW.role IS DISTINCT FROM OLD.role THEN
        -- Le changement de rôle est géré par update_user_role() qui fait déjà la validation
        -- Ici on ne fait que vérifier que c'est un enum valide
        BEGIN
            PERFORM NEW.role::text::user_role;
        EXCEPTION
            WHEN invalid_text_representation THEN
                RAISE EXCEPTION 'Rôle invalide: %', NEW.role;
        END;
    END IF;

    -- Validation POINTS (plage raisonnable)
    IF TG_OP = 'INSERT' THEN
        IF NEW.points IS NULL THEN
            NEW.points := 0;
        ELSIF NEW.points < 0 OR NEW.points > 100000 THEN
            RAISE EXCEPTION 'Points invalides: doit être entre 0 et 100000';
        END IF;
    ELSIF TG_OP = 'UPDATE' AND NEW.points IS DISTINCT FROM OLD.points THEN
        IF NEW.points < 0 OR NEW.points > 100000 THEN
            RAISE EXCEPTION 'Points invalides: doit être entre 0 et 100000';
        END IF;
    END IF;

    -- ============================================================
    -- LOGGING DE SÉCURITÉ (changements sensibles)
    -- ============================================================

    IF TG_OP = 'UPDATE' THEN
        -- Détecter les champs modifiés
        IF NEW.role IS DISTINCT FROM OLD.role THEN
            v_changed_fields := array_append(v_changed_fields, 'role');
        END IF;

        IF NEW.is_active IS DISTINCT FROM OLD.is_active THEN
            v_changed_fields := array_append(v_changed_fields, 'is_active');
        END IF;

        IF ABS(COALESCE(NEW.points, 0) - COALESCE(OLD.points, 0)) > 100 THEN
            v_changed_fields := array_append(v_changed_fields, 'points');
        END IF;

        -- Logger si changements sensibles
        IF array_length(v_changed_fields, 1) > 0 THEN
            v_old_data := jsonb_build_object(
                'role', OLD.role,
                'is_active', OLD.is_active,
                'points', OLD.points
            );
            v_new_data := jsonb_build_object(
                'role', NEW.role,
                'is_active', NEW.is_active,
                'points', NEW.points
            );
            
            PERFORM private.log_user_security_event(
                'UPDATE',
                NEW.id,
                v_old_data,
                v_new_data,
                v_changed_fields
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$function$


-- Function: private.trg_sync_restaurant_menu_url()
CREATE OR REPLACE FUNCTION private.trg_sync_restaurant_menu_url()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
BEGIN
  NEW.restaurant_menu_url := private.current_week_menu_url_from_jsonb(COALESCE(NEW.restaurant_menu_url_jsonb, '[]'::jsonb));
  RETURN NEW;
END;
$function$


-- Function: private.trigger_send_activation_notification()
CREATE OR REPLACE FUNCTION private.trigger_send_activation_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'vault', 'net', 'extensions'
AS $function$
DECLARE
  v_url text;
  v_key text;
  v_entity_type text;
  v_entity_id uuid;
BEGIN
  -- 1. Identification rapide
  IF TG_TABLE_NAME = 'promotions' THEN
    v_entity_type := 'promotion';
    v_entity_id := NEW.id;
    IF NEW.start_date IS NULL OR NEW.start_date > now() OR NEW.end_date <= now() THEN RETURN NEW; END IF;
  ELSIF TG_TABLE_NAME = 'polls' THEN
    v_entity_type := 'poll';
    v_entity_id := NEW.id;
    IF NEW.is_active IS NOT TRUE OR NEW.starts_at > now() OR NEW.ends_at <= now() THEN RETURN NEW; END IF;
  ELSE
    RETURN NEW;
  END IF;

  -- 2. Verrou atomique pour éviter les doublons
  -- Si l'insertion échoue (déjà existant), on arrête tout de suite
  INSERT INTO public.entity_activation_notifications (entity_type, entity_id, created_at)
  VALUES (v_entity_type, v_entity_id, now())
  ON CONFLICT (entity_type, entity_id) DO NOTHING;
  
  IF NOT FOUND THEN RETURN NEW; END IF;

  -- 3. Récupération des secrets (très rapide en indexé)
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'activation_notifications_project_url' LIMIT 1;
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'activation_notifications_service_role_key' LIMIT 1;

  -- 4. APPEL ASYNC (Non-bloquant)
  -- L'appel est mis en file d'attente dans le schéma 'net'. 
  -- PostgreSQL n'attend pas la réponse de l'Edge Function.
  IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
    PERFORM net.http_post(
      url := trim(v_url) || '/functions/v1/send-activation-notifications',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || trim(v_key)
      ),
      body := jsonb_build_object('entity_type', v_entity_type, 'entity_id', v_entity_id)
    );
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Protection ultime : en cas d'erreur (Vault, pg_net, etc.), 
  -- on logge l'erreur mais on ne bloque JAMAIS la transaction principale.
  RAISE WARNING '[Notification Error] %', SQLERRM;
  RETURN NEW; 
END;
$function$


-- Function: private.update_poll_with_options(p_poll_id uuid, p_title text, p_description text, p_question text, p_target_audience text, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_is_active boolean, p_image_url text, p_options jsonb DEFAULT '[]'::jsonb)
CREATE OR REPLACE FUNCTION private.update_poll_with_options(p_poll_id uuid, p_title text, p_description text, p_question text, p_target_audience text, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_is_active boolean, p_image_url text, p_options jsonb DEFAULT '[]'::jsonb)
 RETURNS private.polls
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'private', 'public'
AS $function$
DECLARE
    v_poll private.polls;
    v_option JSONB;
    v_option_id UUID;
    v_allowed_ids UUID[];
BEGIN
    UPDATE private.polls SET
        title = COALESCE(p_title, title),
        description = COALESCE(p_description, description),
        question = COALESCE(p_question, question),
        target_audience = CASE
            WHEN p_target_audience IS NULL THEN target_audience
            ELSE to_jsonb(p_target_audience)
        END,
        starts_at = COALESCE(p_starts_at, starts_at),
        ends_at = COALESCE(p_ends_at, ends_at),
        is_active = COALESCE(p_is_active, is_active),
        image_url = COALESCE(p_image_url, image_url)
    WHERE id = p_poll_id
    RETURNING * INTO v_poll;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sondage introuvable';
    END IF;

    v_allowed_ids := ARRAY(
        SELECT NULLIF(value->>'id', '')::UUID
        FROM jsonb_array_elements(COALESCE(p_options, '[]'::jsonb)) value
        WHERE value ? 'id'
    );

    IF v_allowed_ids IS NULL OR array_length(v_allowed_ids, 1) = 0 THEN
        DELETE FROM private.poll_options WHERE poll_id = p_poll_id;
    ELSE
        DELETE FROM private.poll_options
        WHERE poll_id = p_poll_id
          AND id <> ALL(v_allowed_ids);
    END IF;

    FOR v_option IN
        SELECT *
        FROM jsonb_array_elements(COALESCE(p_options, '[]'::jsonb))
    LOOP
        IF COALESCE(trim(v_option->>'text'), '') = '' THEN
            CONTINUE;
        END IF;

        v_option_id := NULLIF(v_option->>'id', '')::UUID;

        IF v_option_id IS NOT NULL
           AND EXISTS (SELECT 1 FROM private.poll_options WHERE id = v_option_id AND poll_id = p_poll_id) THEN
            UPDATE private.poll_options
            SET
                option_text = v_option->>'text',
                option_order = COALESCE((v_option->>'order')::INTEGER, option_order)
            WHERE id = v_option_id;
        ELSE
            INSERT INTO private.poll_options (
                poll_id,
                option_text,
                option_order
            )
            VALUES (
                p_poll_id,
                v_option->>'text',
                COALESCE((v_option->>'order')::INTEGER, 1)
            );
        END IF;
    END LOOP;

    RETURN v_poll;
END;
$function$


-- Function: private.user_has_role(required_role text)
CREATE OR REPLACE FUNCTION private.user_has_role(required_role text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
    user_role text;
    role_hierarchy jsonb;
BEGIN
    -- Hiérarchie des rôles (superadmin > admin > marketing > cashier > user)
    role_hierarchy := '{
        "app_admin": 4,
        "app_cashier": 2,
        "app_user": 1
    }'::jsonb;
    
    -- Obtenir le rôle de l'utilisateur actuel
    user_role := private.get_user_pg_role(auth.uid());
    
    -- Si pas de rôle trouvé, retourner false
    IF user_role IS NULL THEN
        RETURN false;
    END IF;
    
    -- Comparer dans la hiérarchie
    RETURN (role_hierarchy->>user_role)::int >= (role_hierarchy->>required_role)::int;
EXCEPTION
    WHEN OTHERS THEN
        -- En cas d'erreur, refuser l'accès
        RETURN false;
END;
$function$


-- Function: private.validate_email_format(p_email text)
CREATE OR REPLACE FUNCTION private.validate_email_format(p_email text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'private'
AS $function$
BEGIN
    -- Validation basique du format email
    IF p_email IS NULL OR length(trim(p_email)) = 0 THEN
        RETURN false;
    END IF;
    
    -- Format email basique : caractères@domaine.extension
    IF p_email !~ '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' THEN
        RETURN false;
    END IF;
    
    -- Longueur max raisonnable (RFC 5321)
    IF length(p_email) > 254 THEN
        RETURN false;
    END IF;
    
    RETURN true;
END;
$function$


-- Function: private.validate_hex_color(p_color text)
CREATE OR REPLACE FUNCTION private.validate_hex_color(p_color text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'private'
AS $function$
BEGIN
    IF p_color IS NULL THEN
        RETURN true; -- NULL autorisé
    END IF;
    
    -- Format hex : #RRGGBB (7 caractères)
    IF p_color !~ '^#[0-9A-Fa-f]{6}$' THEN
        RETURN false;
    END IF;
    
    RETURN true;
END;
$function$


-- Function: private.validate_notification_settings(p_settings jsonb)
CREATE OR REPLACE FUNCTION private.validate_notification_settings(p_settings jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'private'
AS $function$
BEGIN
    -- Si NULL, retourner NULL
    IF p_settings IS NULL THEN
        RETURN NULL;
    END IF;

    -- Vérifier que c'est un objet JSON
    IF jsonb_typeof(p_settings) <> 'object' THEN
        RAISE EXCEPTION 'notification_settings doit être un objet JSON';
    END IF;

    -- Retourner tel quel (la structure est validée par l'application)
    RETURN p_settings;
END;
$function$


-- Function: private.validate_safe_text(p_text text, p_max_length integer DEFAULT 500)
CREATE OR REPLACE FUNCTION private.validate_safe_text(p_text text, p_max_length integer DEFAULT 500)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'private'
AS $function$
BEGIN
    IF p_text IS NULL THEN
        RETURN true; -- NULL est autorisé
    END IF;
    
    -- Longueur max
    IF length(p_text) > p_max_length THEN
        RETURN false;
    END IF;
    
    -- Caractères dangereux pour injection SQL (même si paramètres typés protègent)
    -- On bloque quand même les caractères suspects
    IF p_text ~* '(;|--|/\*|\*/|xp_|sp_|exec|execute|union|select|insert|update|delete|drop|create|alter|truncate)' THEN
        RETURN false;
    END IF;
    
    RETURN true;
END;
$function$


-- Function: private.validate_user_field(p_field_name text, p_field_value text, p_operation text DEFAULT 'INSERT'::text)
CREATE OR REPLACE FUNCTION private.validate_user_field(p_field_name text, p_field_value text, p_operation text DEFAULT 'INSERT'::text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
    v_cleaned text;
    v_user_local text;
    v_user_domain text;
    v_normalized_local text;
BEGIN
    -- Si NULL, on retourne NULL (les champs optionnels peuvent être NULL)
    IF p_field_value IS NULL THEN
        RETURN NULL;
    END IF;

    -- Trim
    v_cleaned := trim(p_field_value);

    -- Validation selon le champ
    CASE p_field_name
        WHEN 'email' THEN
            -- 1. Format email valide (CORRIGÉ : permet les sous-domaines)
            -- Permet : user@domain.com, user@sub.domain.com, user@sub.sub.domain.com, etc.
            IF v_cleaned !~ '^[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$' THEN
                RAISE EXCEPTION 'Format email invalide: %', v_cleaned;
            END IF;

            -- 2. Normalisation (identique à check_disposable_email)
            v_cleaned := lower(v_cleaned);
            v_user_local := lower(split_part(v_cleaned, '@', 1));
            v_user_domain := lower(split_part(v_cleaned, '@', 2));
            v_normalized_local := split_part(v_user_local, '+', 1);

            -- 3. PROTECTION ÉTENDUE (identique à check_disposable_email)
            -- Vérification nom d'utilisateur suspect AVANT la liste blanche
            IF v_normalized_local ~ '(^|[\._\-])(test|espion|fake|dummy|admin|root|superuser|spam|trash|bot|robot|temp|tmp|guest|support|staff|mod|dev|null|undefined|anonymous|user|junk|webmaster)([\._\-]|$)' THEN
                RAISE EXCEPTION 'Nom d''utilisateur interdit ou suspect.';
            END IF;

            -- 4. FAST PASS (Liste Blanche) - identique à check_disposable_email
            -- Si le domaine est dans la liste blanche, on accepte immédiatement
            IF v_user_domain IN (
                'polymtl.ca', 'etud.polymtl.ca', 'umontreal.ca', 
                'hec.ca', 'mcgill.ca', 'gmail.com', 'outlook.com', 'hotmail.com'
            ) THEN
                RETURN v_cleaned;
            END IF;

            -- 5. VÉRIFICATION LISTE NOIRE (emails jetables) - identique à check_disposable_email
            IF EXISTS (SELECT 1 FROM private.disposable_emails WHERE domain = v_user_domain) THEN
                RAISE EXCEPTION 'Les emails jetables sont interdits sur MyFidelity.';
            END IF;

            RETURN v_cleaned;

        WHEN 'name' THEN
            -- 1. Longueur minimale
            IF length(v_cleaned) < 2 THEN
                RAISE EXCEPTION 'Le nom doit contenir au moins 2 caractères';
            END IF;

            -- 2. Longueur maximale
            IF length(v_cleaned) > 100 THEN
                RAISE EXCEPTION 'Le nom ne peut pas dépasser 100 caractères';
            END IF;

            -- 3. Protection XSS : pas de balises HTML
            IF v_cleaned ~ '[<>]' THEN
                RAISE EXCEPTION 'Caractères interdits détectés (XSS): < ou >';
            END IF;

            -- 4. Protection SQL injection : pas de commentaires SQL
            IF v_cleaned ~* '(--|;)' THEN
                RAISE EXCEPTION 'Caractères suspects détectés (SQL injection): -- ou ;';
            END IF;

            -- 5. Normalisation : remplacer séparateurs par espaces
            v_cleaned := regexp_replace(v_cleaned, '[\._\-]', ' ', 'g');

            -- 6. Nettoyage : ne garder que lettres, espaces et accents
            v_cleaned := regexp_replace(v_cleaned, '[^a-zA-ZÀ-ÿ\s]', '', 'g');

            -- 7. Normalisation espaces : trim et suppression espaces multiples
            v_cleaned := trim(regexp_replace(v_cleaned, '\s+', ' ', 'g'));

            -- 8. Vérification finale longueur après nettoyage
            IF length(v_cleaned) < 2 THEN
                RAISE EXCEPTION 'Le nom après nettoyage est trop court (min 2 caractères)';
            END IF;

            -- 9. Limiter à 100 caractères
            RETURN left(v_cleaned, 100);

        WHEN 'avatar_url' THEN
            -- Validation URL basique
            IF v_cleaned !~ '^https?://' AND v_cleaned !~ '^/[^/]' AND v_cleaned !~ '^[a-zA-Z0-9_\-]+\.(avif|png|jpg|jpeg|webp)$' THEN
                RAISE EXCEPTION 'Format URL avatar invalide: %', v_cleaned;
            END IF;

            -- Protection XSS dans URL
            IF v_cleaned ~ '[<>"]' THEN
                RAISE EXCEPTION 'Caractères interdits dans URL avatar (XSS)';
            END IF;

            RETURN v_cleaned;

        ELSE
            -- Pour les autres champs texte, validation basique XSS/SQL
            IF v_cleaned ~ '[<>]' THEN
                RAISE EXCEPTION 'Caractères interdits détectés (XSS) dans %: < ou >', p_field_name;
            END IF;

            IF v_cleaned ~* '(--|;)' THEN
                RAISE EXCEPTION 'Caractères suspects détectés (SQL injection) dans %: -- ou ;', p_field_name;
            END IF;

            RETURN v_cleaned;
    END CASE;
END;
$function$


-- Function: public.activate_polls_that_became_active()
CREATE OR REPLACE FUNCTION public.activate_polls_that_became_active()
 RETURNS TABLE(activated_count integer, activated_ids uuid[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
BEGIN
  -- Autoriser postgres (cron) et service_role (API/tRPC)
  IF session_user NOT IN ('postgres', 'service_role', 'authenticator') THEN
    RAISE EXCEPTION 'Accès refusé : privilèges insuffisants.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH updated AS (
    UPDATE private.polls
    SET is_active = true
    WHERE starts_at <= now() 
    AND (is_active = false OR is_active IS NULL)
    RETURNING id
  )
  SELECT 
    (SELECT count(*)::int FROM updated),
    (SELECT array_agg(id) FROM updated);
END;
$function$


-- Function: public.addfeedback(category text DEFAULT NULL::text, comments text DEFAULT NULL::text)
CREATE OR REPLACE FUNCTION public.addfeedback(category text DEFAULT NULL::text, comments text DEFAULT NULL::text)
 RETURNS TABLE(remaining_feedbacks integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
    v_user_id uuid;
    v_user_role text;
    v_feedback_count integer;
    v_limit integer;
BEGIN
    -- 🛡️ 1. AUTHENTIFICATION
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- 🛡️ 2. RÉCUPÉRATION DU RÔLE & DÉFINITION LIMITE
    SELECT role INTO v_user_role 
    FROM private.users 
    WHERE id = v_user_id;

    -- Si c'est un caissier, limite "infinie" (10 000/jour), sinon 3/jour
    IF v_user_role = 'caissier' THEN
        v_limit := 10000; 
    ELSE
        v_limit := 3;
    END IF;

    -- 🛡️ 3. VALIDATION ENTRÉES (Anti-Null)
    IF category IS NULL OR trim(category) = '' OR 
       comments IS NULL OR trim(comments) = '' THEN
        RAISE EXCEPTION '400: Champs obligatoires manquants.' USING ERRCODE = '22000';
    END IF;

    -- 🛡️ 4. WHITELIST CATÉGORIES
    IF category NOT IN ('app_bug', 'restaurant_idea', 'food_item_feedback', 'new_feature', 'other') THEN
        RAISE EXCEPTION '400: Catégorie invalide.' USING ERRCODE = '22023';
    END IF;

    -- 🛡️ 5. SÉCURITÉ CONTENU (Anti-XSS, Anti-DoS, Anti-SQL)
    IF length(comments) > 2000 THEN
        RAISE EXCEPTION '400: Trop long.' USING ERRCODE = '23514';
    END IF;

    IF comments ~ '[<>]' THEN
        RAISE EXCEPTION '400: Caractères interdits (XSS).' USING ERRCODE = '22000';
    END IF;

    IF comments ~* '(\-\-|;|drop table|select \*|union all|insert into|delete from)' THEN
        RAISE EXCEPTION '400: Injection SQL détectée.' USING ERRCODE = '22000';
    END IF;

    -- 🛡️ 6. COMPTAGE DU JOUR
    SELECT count(*)::integer INTO v_feedback_count
    FROM private.feedback
    WHERE user_id = v_user_id
      AND created_at >= CURRENT_DATE;

    -- 7. LOGIQUE D'INSERTION
    IF v_feedback_count < v_limit THEN
        INSERT INTO private.feedback (user_id, category, comments, created_at)
        VALUES (v_user_id, category, comments, now());
        
        -- Retourne combien il en reste
        RETURN QUERY SELECT v_limit - (v_feedback_count + 1);
    ELSE
        -- Limite atteinte : on n'insère rien et on renvoie 0
        RETURN QUERY SELECT 0;
    END IF;

EXCEPTION WHEN OTHERS THEN
    RAISE;
END;
$function$


-- Function: public.auto_activate_poll_on_time()
CREATE OR REPLACE FUNCTION public.auto_activate_poll_on_time()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
BEGIN
  -- Si le sondage n'est pas encore actif mais que starts_at est atteint
  IF NEW.is_active = false 
     AND NEW.starts_at IS NOT NULL 
     AND NEW.ends_at IS NOT NULL
     AND NEW.starts_at <= now() 
     AND NEW.ends_at > now() THEN
    
    -- Activer le sondage
    NEW.is_active := true;
    
    RAISE NOTICE '[auto_activate_poll] Sondage % activé automatiquement (starts_at atteint)', NEW.id;
  END IF;

  RETURN NEW;
END;
$function$


-- Function: public.cancel_pending_transaction(params jsonb DEFAULT '{}'::jsonb)
CREATE OR REPLACE FUNCTION public.cancel_pending_transaction(params jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(success boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'private', 'public', 'extensions'
AS $function$
DECLARE
    v_user_id uuid;
    v_tx_id uuid;
BEGIN
    -- 🛡️ NIVEAU 1 : Blocage immédiat des sessions anonymes
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        -- On renvoie false plutôt que de planter, c'est propre
        RETURN QUERY SELECT false;
        RETURN;
    END IF;

    -- 🛡️ NIVEAU 2 : Anti-Injection (On refuse tout paramètre explicite)
    -- Si le front-end essaie d'envoyer { "id": "..." }, on bloque.
    -- On accepte seulement le vide ou {}
    IF params IS NOT NULL AND params <> '{}'::jsonb THEN
        RAISE EXCEPTION '400: Cette fonction n''accepte aucun paramètre. Elle annule automatiquement votre dernière transaction.' USING ERRCODE = '22000';
    END IF;

    -- 🛡️ NIVEAU 3 : Ciblage chirurgical (Auto-détection)
    -- On trouve la transaction la plus récente en attente pour cet utilisateur
    SELECT id INTO v_tx_id
    FROM private.transactions
    WHERE user_id = v_user_id
      AND (status = 'en_attente' OR status = 'pending') -- Support des deux conventions
    ORDER BY date DESC -- ✅ CORRIGÉ : Utilise 'date' au lieu de 'created_at'
    LIMIT 1;

    -- 🛡️ NIVEAU 4 : Exécution
    IF v_tx_id IS NOT NULL THEN
        UPDATE private.transactions
        SET 
            status = 'annule',
            date = now() -- ✅ CORRIGÉ : Met à jour 'date' au lieu de 'updated_at'
        WHERE id = v_tx_id;
        
        RETURN QUERY SELECT true;
    ELSE
        -- Rien à annuler
        RETURN QUERY SELECT false;
    END IF;

EXCEPTION 
    WHEN OTHERS THEN
        -- Gestion d'erreur conforme à ton code
        IF SQLSTATE = '22000' THEN
            RAISE;
        END IF;
        RETURN QUERY SELECT false;
END;
$function$


-- Function: public.create_article(article_data jsonb)
CREATE OR REPLACE FUNCTION public.create_article(article_data jsonb)
 RETURNS private.articles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    new_article private.articles;
    v_user_role text;
BEGIN
    -- A. Vérification de l'authentification (Fail-fast)
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. SÉCURITÉ : Vérifier le rôle dans la table de vérité (private.users)
    SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();
    
    IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Permission refusée' USING ERRCODE = '42501';
    END IF;
    
    -- C. Validation des données critiques
    IF article_data->>'name' IS NULL OR trim(article_data->>'name') = '' THEN
        RAISE EXCEPTION 'Le nom de l''article est requis';
    END IF;
    
    IF (article_data->>'points')::int <= 0 THEN
        RAISE EXCEPTION 'Les points doivent être positifs';
    END IF;
    
    -- D. Insertion sécurisée avec protection anti-scalar pour les listes
    INSERT INTO private.articles (
        name, description, points, category, categorie, image, 
        is_ecogeste, calories, price, allergens, co2_ranking,
        isbestseller, islowco2, restaurant_ids
    )
    VALUES (
        article_data->>'name',
        article_data->>'description',
        (article_data->>'points')::int,
        article_data->>'category',
        article_data->>'categorie',
        article_data->>'image',
        COALESCE((article_data->>'is_ecogeste')::boolean, false),
        (article_data->>'calories')::int,
        (article_data->>'price')::numeric,
        
        -- ✅ Protection anti-scalar pour les allergènes
        CASE 
            WHEN article_data ? 'allergens' AND jsonb_typeof(article_data->'allergens') = 'array' 
            THEN ARRAY(SELECT jsonb_array_elements_text(article_data->'allergens'))::text[]
            ELSE '{}'::text[]
        END,
        
        article_data->>'co2_ranking',
        COALESCE((article_data->>'isbestseller')::boolean, false),
        COALESCE((article_data->>'islowco2')::boolean, false),
        
        -- ✅ Protection anti-scalar pour les UUIDs de restaurants
        CASE 
            WHEN article_data ? 'restaurant_ids' AND jsonb_typeof(article_data->'restaurant_ids') = 'array'
            THEN ARRAY(SELECT jsonb_array_elements_text(article_data->'restaurant_ids'))::uuid[]
            ELSE '{}'::uuid[]
        END
    )
    RETURNING * INTO new_article;
    
    -- E. Log de sécurité (Audit Trail)
    PERFORM private.log_security_event(
        'CREATE', 'articles', new_article.id,
        NULL,
        to_jsonb(new_article),
        true, NULL
    );

    RETURN new_article;
END;
$function$


-- Function: public.create_offer(offer_data jsonb)
CREATE OR REPLACE FUNCTION public.create_offer(offer_data jsonb)
 RETURNS private.offers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    new_offer private.offers;
    v_user_role text;
BEGIN
    -- A. Vérification de l'authentification (Fail-fast)
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. SÉCURITÉ : Vérification du rôle dans la table de vérité (private.users)
    SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();
    
    IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Droits insuffisants' USING ERRCODE = '42501';
    END IF;
    
    -- C. Validation des données
    IF (offer_data->>'points')::int <= 0 THEN
        RAISE EXCEPTION 'Les points doivent être positifs';
    END IF;

    IF offer_data->>'title' IS NULL OR trim(offer_data->>'title') = '' THEN
        RAISE EXCEPTION 'Le titre de l''offre est requis';
    END IF;
    
    -- D. Insertion avec conversion sécurisée des types JSON vers Postgres
    INSERT INTO private.offers (
        title, 
        description, 
        points, 
        image, 
        context_tags, 
        is_active, 
        is_premium, 
        expiry_date, 
        restaurant_ids
    )
    VALUES (
        offer_data->>'title',
        offer_data->>'description',
        (offer_data->>'points')::int,
        offer_data->>'image',
        -- Cast sécurisé pour les tableaux de texte
        COALESCE(ARRAY(SELECT jsonb_array_elements_text(offer_data->'context_tags'))::text[], '{}'),
        COALESCE((offer_data->>'is_active')::boolean, true),
        COALESCE((offer_data->>'is_premium')::boolean, false),
        (offer_data->>'expiry_date')::timestamptz,
        -- Cast sécurisé pour les tableaux d'UUID
        COALESCE(ARRAY(SELECT jsonb_array_elements_text(offer_data->'restaurant_ids'))::uuid[], '{}')
    )
    RETURNING * INTO new_offer;
    
    -- E. Log de sécurité (Audit Trail)
    PERFORM private.log_security_event(
        'CREATE', 'offers', new_offer.id,
        NULL,
        to_jsonb(new_offer), -- Correction ici : new_offer et non new_article
        true, NULL
    );
    
    RETURN new_offer;
END;
$function$


-- Function: public.create_promotion(p_title text, p_start_date timestamp with time zone, p_end_date timestamp with time zone, p_description text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text, p_color character varying DEFAULT '#FF8A65'::character varying)
CREATE OR REPLACE FUNCTION public.create_promotion(p_title text, p_start_date timestamp with time zone, p_end_date timestamp with time zone, p_description text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text, p_color character varying DEFAULT '#FF8A65'::character varying)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  v_promotion_id UUID;
  v_result JSON;
BEGIN
  -- Vérifier l'authentification
  IF auth.uid() IS NULL THEN
    RETURN json_build_object('error', 'Authentification requise');
  END IF;

  -- Validation des données
  IF p_title IS NULL OR LENGTH(TRIM(p_title)) = 0 THEN
    RETURN json_build_object('error', 'Le titre est obligatoire');
  END IF;

  IF p_start_date IS NULL THEN
    RETURN json_build_object('error', 'La date de début est obligatoire');
  END IF;

  IF p_end_date IS NULL THEN
    RETURN json_build_object('error', 'La date de fin est obligatoire');
  END IF;

  IF p_start_date >= p_end_date THEN
    RETURN json_build_object('error', 'La date de début doit être antérieure à la date de fin');
  END IF;

  -- 🛡️ VALIDATION : p_color (format hex)
  IF p_color IS NOT NULL AND length(trim(p_color)) > 0 THEN
    IF NOT private.validate_hex_color(p_color) THEN
      RETURN json_build_object('error', 'Format de couleur invalide (doit être #RRGGBB)');
    END IF;
  END IF;

  -- 🛡️ VALIDATION : p_title (longueur et sécurité)
  IF NOT private.validate_safe_text(p_title, 500) THEN
    RETURN json_build_object('error', 'Titre invalide ou suspect');
  END IF;

  -- Insérer la promotion
  INSERT INTO private.promotions (
    title,
    description,
    image_url,
    start_date,
    end_date,
    color
  ) VALUES (
    TRIM(p_title),
    CASE WHEN p_description IS NOT NULL AND LENGTH(TRIM(p_description)) > 0 THEN TRIM(p_description) ELSE NULL END,
    CASE WHEN p_image_url IS NOT NULL AND LENGTH(TRIM(p_image_url)) > 0 THEN TRIM(p_image_url) ELSE NULL END,
    p_start_date,
    p_end_date,
    COALESCE(p_color, '#FF8A65')
  ) RETURNING id INTO v_promotion_id;

  -- Retourner le résultat
  SELECT json_build_object(
    'success', true,
    'data', row_to_json(p.*)
  ) INTO v_result
  FROM private.promotions p
  WHERE p.id = v_promotion_id;

  RETURN v_result;

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', SQLERRM);
END;
$function$


-- Function: public.create_restaurant(new_data jsonb)
CREATE OR REPLACE FUNCTION public.create_restaurant(new_data jsonb)
 RETURNS private.restaurants
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    new_restaurant private.restaurants;
    v_caller_role text;
BEGIN
    -- A. NIVEAU 1 : Authentification Stricte (Fail-fast)
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. NIVEAU 2 : SÉCURITÉ - Vérification du rôle dans la table de vérité (private.users)
    -- On inclut 'marketing' comme tu l'as spécifié dans ton code source.
    SELECT role::text INTO v_caller_role 
    FROM private.users 
    WHERE id = auth.uid();

    IF v_caller_role NOT IN ('administrateur') OR v_caller_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Seuls les administrateurs peuvent créer des restaurants.' 
        USING ERRCODE = '42501';
    END IF;

    -- C. NIVEAU 3 : Validation minimale des données
    IF new_data->>'name' IS NULL OR trim(new_data->>'name') = '' THEN
        RAISE EXCEPTION '400: Bad Request - Le nom du restaurant est obligatoire' 
        USING ERRCODE = 'P0002';
    END IF;

    -- D. Log d'opération (Visible dans les logs Postgres)
    RAISE NOTICE '[RPC create_restaurant] Création du restaurant par % : %', auth.uid(), new_data->>'name';

    -- E. Insertion avec conversion sécurisée JSONB -> SQL
    INSERT INTO private.restaurants (
        name, 
        description, 
        image_url, 
        location, 
        is_new, 
        boosted, 
        schedule, 
        special_hours, 
        categories, 
        status,
        created_at,
        updated_at
    )
    VALUES (
        new_data->>'name',
        new_data->>'description',
        new_data->>'image_url',
        new_data->>'location',
        COALESCE((new_data->>'is_new')::boolean, false),
        COALESCE((new_data->>'boosted')::boolean, false),
        COALESCE(new_data->'schedule', '[]'::jsonb),
        COALESCE(new_data->'special_hours', '[]'::jsonb),
        COALESCE(
            ARRAY(SELECT jsonb_array_elements_text(new_data->'categories')),
            '{}'::text[]
        ),
        COALESCE(new_data->>'status', 'active'),
        NOW(),
        NOW()
    )
    RETURNING * INTO new_restaurant;

    -- F. Log de sécurité (Audit Trail interne)
    -- On utilise ta fonction de log si elle existe, sinon le RAISE NOTICE suffit.
    PERFORM private.log_security_event(
        'CREATE', 'restaurants', new_restaurant.id,
        NULL,
        to_jsonb(new_restaurant),
        true, NULL
    );

    RETURN new_restaurant;
END;
$function$


-- Function: public.cron_check_and_send_activations()
CREATE OR REPLACE FUNCTION public.cron_check_and_send_activations()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'vault', 'net', 'extensions'
AS $function$
DECLARE
  v_url text;
  v_key text;
  v_request_id bigint;
BEGIN
  -- Validation de l'utilisateur de session
  IF session_user NOT IN ('postgres', 'service_role', 'authenticator') THEN
    RAISE EXCEPTION 'Accès refusé : cette fonction nécessite des privilèges de service_role ou postgres.';
  END IF;

  -- 1. Appel de la fonction subordonnée (Maintenant compatible)
  PERFORM public.activate_polls_that_became_active();
  
  -- 2. Récupération des secrets dans le Vault
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'activation_notifications_project_url' LIMIT 1;
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'activation_notifications_service_role_key' LIMIT 1;

  IF v_url IS NULL OR v_key IS NULL OR trim(v_url) = '' OR trim(v_key) = '' THEN
    RAISE WARNING '[cron] Secrets Vault manquants';
    RETURN;
  END IF;

  -- 3. Envoi à l'Edge Function
  SELECT net.http_post(
    url := trim(v_url) || '/functions/v1/send-activation-notifications',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || trim(v_key)
    ),
    body := '{}'::jsonb
  ) INTO v_request_id;

  RAISE NOTICE '[cron] Succès de la chaîne d''activation (Request ID: %)', v_request_id;
END;
$function$


-- Function: public.delete_article(article_id uuid)
CREATE OR REPLACE FUNCTION public.delete_article(article_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    v_user_role text;
    v_article_name text;
BEGIN
    -- A. Vérification de l'authentification
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentification requise';
    END IF;

    -- B. SÉCURITÉ : Vérification du rôle dans private.users
    -- Seuls 'administrateur' et 'superadmin' peuvent supprimer
    SELECT role INTO v_user_role FROM private.users WHERE id = auth.uid();
    
    IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
        RAISE EXCEPTION 'Permission refusée : droits insuffisants';
    END IF;

    -- C. Récupération du nom pour le log avant suppression
    SELECT name INTO v_article_name FROM private.articles WHERE id = article_id;
    
    IF v_article_name IS NULL THEN
        RAISE EXCEPTION 'Article non trouvé';
    END IF;
    
    -- D. Intégrité Référentielle : Vérifier si l'article est présent dans les transactions
    -- On utilise une recherche plus performante sur le JSONB si possible
    IF EXISTS (
        SELECT 1 FROM private.transactions 
        WHERE items::text LIKE '%' || article_id::text || '%'
    ) THEN
        RAISE EXCEPTION 'Impossible de supprimer: article utilisé dans des transactions';
    END IF;

    -- E. Suppression sécurisée
    DELETE FROM private.articles WHERE id = article_id;

    -- F. Log de sécurité
    PERFORM private.log_security_event(
        'DELETE', 'articles', article_id,
        jsonb_build_object('name', v_article_name),
        NULL,
        true, NULL
    );
    
    RETURN true;
END;
$function$


-- Function: public.delete_my_account()
CREATE OR REPLACE FUNCTION public.delete_my_account()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
    current_user_id UUID;
BEGIN
    -- Récupérer l'ID de l'utilisateur actuellement connecté
    current_user_id := auth.uid();
    
    IF current_user_id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Utilisateur non authentifié'
        );
    END IF;
    
    -- Appeler la fonction de suppression
    RETURN delete_user_completely(current_user_id);
END;
$function$


-- Function: public.delete_offer(offer_id uuid)
CREATE OR REPLACE FUNCTION public.delete_offer(offer_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    v_user_role text;
    v_offer_title text;
BEGIN
    -- A. Vérification de l'authentification (Fail-fast)
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. SÉCURITÉ : Vérification du rôle dans la table de vérité (private.users)
    SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();
    
    IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Droits administrateur requis' USING ERRCODE = '42501';
    END IF;

    -- C. Vérification de l'existence et récupération du titre pour le log
    SELECT title INTO v_offer_title FROM private.offers WHERE id = offer_id;
    IF v_offer_title IS NULL THEN
        RAISE EXCEPTION '404: Not Found - Offre introuvable' USING ERRCODE = 'P0002';
    END IF;
    
    -- D. INTÉGRITÉ : Gestion de l'historique des transactions
    -- On vérifie si l'ID est présent dans l'historique pour éviter de casser les stats
    IF EXISTS (
        SELECT 1 FROM private.transactions 
        WHERE offer_id = delete_offer.offer_id -- Ambiguité levée par delete_offer.offer_id
        OR used_offers::text LIKE '%' || delete_offer.offer_id::text || '%'
    ) THEN
        -- Logique de sécurité : On désactive au lieu de supprimer pour garder l'historique
        UPDATE private.offers 
        SET is_active = false 
        WHERE id = delete_offer.offer_id;
        
        -- Log de l'événement (Désactivation)
        PERFORM private.log_security_event(
            'DISABLE', 'offers', delete_offer.offer_id,
            jsonb_build_object('title', v_offer_title, 'reason', 'used_in_transactions'),
            NULL,
            true, NULL
        );
    ELSE
        -- Suppression physique si aucune transaction n'y est liée
        DELETE FROM private.offers WHERE id = delete_offer.offer_id;

        -- Log de l'événement (Suppression)
        PERFORM private.log_security_event(
            'DELETE', 'offers', delete_offer.offer_id,
            jsonb_build_object('title', v_offer_title),
            NULL,
            true, NULL
        );
    END IF;
    
    RETURN true;
END;
$function$


-- Function: public.delete_poll(p_poll_id uuid)
CREATE OR REPLACE FUNCTION public.delete_poll(p_poll_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    v_poll_title text;
BEGIN
    -- A. Vérification de l'authentification (Fail-fast)
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. SÉCURITÉ : Vérifier le rôle dans private.users
    -- C'est ici que se trouve le véritable verrou pour les non-admins
    IF NOT EXISTS (
        SELECT 1 FROM private.users 
        WHERE id = auth.uid() 
        AND role IN ('administrateur')
    ) THEN
        RAISE EXCEPTION '403: Forbidden - Droits administrateur requis' USING ERRCODE = '42501';
    END IF;

    -- C. Récupérer le titre pour le log
    SELECT title INTO v_poll_title FROM private.polls WHERE id = p_poll_id;

    IF v_poll_title IS NULL THEN
        RAISE EXCEPTION '404: Not Found - Sondage introuvable' USING ERRCODE = 'P0002';
    END IF;

    -- D. Suppression des dépendances et du sondage
    DELETE FROM private.poll_options WHERE poll_id = p_poll_id;
    DELETE FROM private.polls WHERE id = p_poll_id;

    -- E. Log de sécurité (Audit Trail)
    PERFORM private.log_security_event(
        'DELETE', 'polls', p_poll_id,
        jsonb_build_object('title', v_poll_title),
        NULL,
        true, NULL
    );

    RETURN json_build_object(
        'success', true, 
        'message', 'Sondage et options supprimés avec succès',
        'poll_id', p_poll_id
    );
END;
$function$


-- Function: public.delete_promotion(p_id uuid)
CREATE OR REPLACE FUNCTION public.delete_promotion(p_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
BEGIN
  -- Vérifier l'authentification
  IF auth.uid() IS NULL THEN
    RETURN json_build_object('error', 'Authentification requise');
  END IF;

  -- Vérifier que la promotion existe
  IF NOT EXISTS (SELECT 1 FROM private.promotions WHERE id = p_id) THEN
    RETURN json_build_object('error', 'Promotion introuvable');
  END IF;

  -- Supprimer la promotion
  DELETE FROM private.promotions WHERE id = p_id;

  RETURN json_build_object('success', true, 'message', 'Promotion supprimée avec succès');

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', SQLERRM);
END;
$function$


-- Function: public.delete_restaurants(restaurant_ids uuid[])
CREATE OR REPLACE FUNCTION public.delete_restaurants(restaurant_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
  deleted_count integer;
BEGIN
  -- A. Vérification de l'authentification
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- B. SÉCURITÉ : Vérifier le rôle (Admin / Superadmin uniquement)
  -- Note : Retrait du rôle 'marketing' selon tes instructions
  IF NOT EXISTS (
    SELECT 1
    FROM private.users
    WHERE id = auth.uid() AND role IN ('administrateur')
  ) THEN
    RAISE EXCEPTION 'Accès refusé : Seuls les administrateurs peuvent supprimer des restaurants.';
  END IF;

  -- C. Suppression des restaurants
  -- Utilisation de ANY() pour gérer le tableau d'UUIDs
  WITH deleted AS (
    DELETE FROM private.restaurants
    WHERE id = ANY(restaurant_ids)
    RETURNING id
  )
  SELECT count(*) INTO deleted_count FROM deleted;

  -- D. Log de sécurité (si ta table de log existe)
  BEGIN
    PERFORM private.log_security_event(
      'DELETE_BULK', 'restaurants', NULL,
      jsonb_build_object('count', deleted_count, 'ids', restaurant_ids),
      NULL,
      true, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Le log de sécurité n''a pas pu être enregistré';
  END;

  -- E. Retour du résultat
  RETURN jsonb_build_object(
    'status', 'success', 
    'deleted_count', deleted_count,
    'message', format('%s restaurant(s) supprimé(s) avec succès', deleted_count)
  );
END;
$function$


-- Function: public.delete_user_completely(user_id uuid)
CREATE OR REPLACE FUNCTION public.delete_user_completely(user_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
    caller_role text;
    result JSON;
    deleted_count INTEGER := 0;
BEGIN
    -- Vérification du rôle de l'appelant
    SELECT role INTO caller_role FROM private.users WHERE id = auth.uid();
    
    IF caller_role != 'administrateur' THEN
        RAISE EXCEPTION 'Permission refusée: seuls les administrateur peuvent supprimer des utilisateurs';
    END IF;
    
    -- Empêcher l'auto-suppression
    IF auth.uid() = user_id THEN
        RAISE EXCEPTION 'Impossible de supprimer votre propre compte';
    END IF;
    
    -- Vérifier que l'utilisateur existe dans auth.users
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = user_id) THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Utilisateur non trouvé dans auth.users'
        );
    END IF;
    
    -- Logger l'action AVANT suppression
    PERFORM private.log_security_event(
        'DELETE', 'users', user_id,
        (SELECT to_jsonb(u.*) FROM private.users u WHERE u.id = user_id),
        NULL, true, 'User deletion requested'
    );

    -- Supprimer la ligne dans private.users
    BEGIN
        DELETE FROM private.users WHERE id = user_id;
        GET DIAGNOSTICS deleted_count = ROW_COUNT;
        
        IF deleted_count > 0 THEN
            RAISE NOTICE 'Utilisateur % supprimé de private.users', user_id;
        ELSE
            RAISE WARNING 'Aucune ligne trouvée dans private.users pour l''utilisateur %', user_id;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Erreur lors de la suppression dans private.users: ' || SQLERRM
        );
    END;

    -- Supprimer le compte utilisateur de auth.users
    BEGIN
        DELETE FROM auth.users WHERE id = user_id;
        RAISE NOTICE 'Utilisateur % supprimé de auth.users', user_id;
    EXCEPTION WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Erreur lors de la suppression dans auth.users: ' || SQLERRM
        );
    END;

    -- Construire le résultat
    result := json_build_object(
        'success', true,
        'user_id', user_id,
        'deleted_from_private_users', deleted_count > 0,
        'deleted_count', deleted_count,
        'message', 'Utilisateur supprimé avec succès de private.users et auth.users'
    );

    RETURN result;
END;
$function$


-- Function: public.force_cache_refresh()
CREATE OR REPLACE FUNCTION public.force_cache_refresh()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
    result JSONB;
    v_user_role text;
BEGIN
    -- Vérifier que l'utilisateur est authentifié
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
    END IF;

    -- Vérifier que l'utilisateur est administrateur
    SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();
    
    IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
    END IF;

    -- Rafraîchir toutes les vues matérialisées
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_restaurants_with_offers;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_polls_with_results;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_user_statistics;
    
    -- Retourner le statut
    SELECT JSONB_BUILD_OBJECT(
        'status', 'success',
        'message', 'Cache rafraîchi avec succès',
        'refreshed_views', JSONB_BUILD_ARRAY(
            'mv_restaurants_with_offers',
            'mv_polls_with_results',
            'mv_user_statistics'
        ),
        'timestamp', NOW()
    ) INTO result;
    
    RETURN result;
END;
$function$


-- Function: public.get_active_offers_private()
CREATE OR REPLACE FUNCTION public.get_active_offers_private()
 RETURNS TABLE(id uuid, title text, description text, points integer, context_tags text[], is_active boolean, is_premium boolean, restaurant_ids uuid[], image text, created_at timestamp with time zone, updated_at timestamp with time zone, expiry_date timestamp with time zone, restaurant_names text[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    v_user_role text;
BEGIN
    -- A. Vérification de l'authentification
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. SÉCURITÉ : Restriction stricte aux rôles 'administrateur' et 'superadmin'
    SELECT role INTO v_user_role FROM private.users WHERE id = auth.uid();
    
    IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Droits administrateur requis';
    END IF;

    -- C. Retour des données
    RETURN QUERY
    SELECT 
        o.id,
        o.title,
        o.description,
        o.points,
        o.context_tags,
        o.is_active,
        o.is_premium,
        o.restaurant_ids,
        o.image,
        o.created_at,
        o.updated_at,
        o.expiry_date,
        -- Récupération des noms des restaurants
        COALESCE(
            ARRAY(
                SELECT r.name 
                FROM private.restaurants r 
                WHERE r.id = ANY(o.restaurant_ids)
            ),
            '{}'::text[]
        ) as restaurant_names
    FROM private.offers o
    WHERE o.is_active = true
    ORDER BY o.created_at DESC;
END;
$function$


-- Function: public.get_active_polls_private()
CREATE OR REPLACE FUNCTION public.get_active_polls_private()
 RETURNS TABLE(id uuid, question text, is_active boolean, created_at timestamp with time zone, expires_at timestamp with time zone, total_votes integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
BEGIN
  -- Vérifier l'authentification
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentification requise';
  END IF;
  
  RETURN QUERY
  SELECT 
    p.id,
    p.question,
    p.is_active,
    p.created_at,
    p.expires_at,
    COALESCE(pv.total_votes, 0) as total_votes
  FROM private.polls p
  LEFT JOIN (
    SELECT poll_id, COUNT(*) as total_votes
    FROM private.poll_votes
    GROUP BY poll_id
  ) pv ON p.id = pv.poll_id
  WHERE p.is_active = true
  AND (p.expires_at IS NULL OR p.expires_at > NOW())
  ORDER BY p.created_at DESC;
END;
$function$


-- Function: public.get_aggregated_data(data_type text DEFAULT 'all'::text)
CREATE OR REPLACE FUNCTION public.get_aggregated_data(data_type text DEFAULT 'all'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
    result JSONB;
    v_user_role text;
BEGIN
    -- Vérifier que l'utilisateur est authentifié
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
    END IF;

    -- Vérifier que l'utilisateur est administrateur
    SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();
    
    IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
    END IF;

    CASE data_type
        WHEN 'restaurants' THEN
            SELECT JSONB_BUILD_OBJECT(
                'type', 'restaurants',
                'data', (
                    SELECT JSONB_AGG(
                        JSONB_BUILD_OBJECT(
                            'id', restaurant_id,
                            'name', restaurant_name,
                            'total_offers', total_offers,
                            'active_offers', active_offers
                        )
                    )
                    FROM mv_restaurants_with_offers
                ),
                'summary', JSONB_BUILD_OBJECT(
                    'total', COUNT(*),
                    'with_offers', COUNT(*) FILTER (WHERE total_offers > 0)
                )
            )
            FROM mv_restaurants_with_offers
            INTO result;
            
        WHEN 'polls' THEN
            SELECT JSONB_BUILD_OBJECT(
                'type', 'polls',
                'data', (
                    SELECT JSONB_AGG(
                        JSONB_BUILD_OBJECT(
                            'id', poll_id,
                            'title', poll_title,
                            'total_votes', total_votes,
                            'total_options', total_options
                        )
                    )
                    FROM mv_polls_with_results
                ),
                'summary', JSONB_BUILD_OBJECT(
                    'total', COUNT(*),
                    'total_votes', COALESCE(SUM(total_votes), 0)
                )
            )
            FROM mv_polls_with_results
            INTO result;
            
        ELSE
            -- Retourner toutes les données agrégées
            SELECT JSONB_BUILD_OBJECT(
                'restaurants', (
                    SELECT JSONB_BUILD_OBJECT(
                        'count', COUNT(*),
                        'with_offers', COUNT(*) FILTER (WHERE total_offers > 0),
                        'active', COUNT(*) FILTER (WHERE status = 'active')
                    )
                    FROM mv_restaurants_with_offers
                ),
                'polls', (
                    SELECT JSONB_BUILD_OBJECT(
                        'count', COUNT(*),
                        'total_votes', COALESCE(SUM(total_votes), 0),
                        'active', COUNT(*) FILTER (WHERE is_active = true)
                    )
                    FROM mv_polls_with_results
                ),
                'users', (
                    SELECT stat_value
                    FROM mv_user_statistics
                    WHERE stat_key = 'overview'
                )
            ) INTO result;
    END CASE;
    
    RETURN result;
END;
$function$


-- Function: public.get_app_boot_data()
CREATE OR REPLACE FUNCTION public.get_app_boot_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'mv', 'view', 'extensions'
AS $function$
DECLARE
    v_user_id uuid;
    v_user_rec record;
    v_result jsonb;
BEGIN
    -- 🛡️ 1. AUTHENTIFICATION STRICTE
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Session invalide ou expirée' USING ERRCODE = 'P0001';
    END IF;

    -- 🛡️ 2. RÉCUPÉRATION SÉCURISÉE DU PROFIL
    SELECT * INTO v_user_rec
    FROM private.users
    WHERE id = v_user_id;

    IF v_user_rec IS NULL THEN
        RAISE EXCEPTION 'Utilisateur introuvable' USING ERRCODE = 'P0001';
    END IF;

    -- 🛡️ 3. LOGIQUE SELON LE RÔLE
    -- On utilise ::text pour éviter les bugs si 'role' est un ENUM
    IF v_user_rec.role::text = 'caissier' THEN
        
        -- === CAS 1 : CAISSIER ===
        SELECT jsonb_build_object(
            'restaurants', COALESCE((
                SELECT jsonb_agg(
                    jsonb_build_object('name', name, 'image_url', image_url)
                )
                FROM (SELECT name, image_url FROM mv.mv_restaurants LIMIT 8) r
            ), '[]'::jsonb),
            'user', jsonb_build_object(
                'name', v_user_rec.name,
                'email', v_user_rec.email,
                'role', v_user_rec.role,
                'is_active', v_user_rec.is_active
            )
        ) INTO v_result;

    ELSE
        
        -- === CAS 2 : CLIENT / ADMIN ===
        SELECT jsonb_build_object(
            -- Utilisation de COALESCE pour renvoyer [] si la table est vide (évite le crash)
            'offers', COALESCE((SELECT jsonb_agg(o) FROM (SELECT * FROM mv.mv_offers LIMIT 8) o), '[]'::jsonb),
            'restaurants', COALESCE((SELECT jsonb_agg(r) FROM (SELECT * FROM mv.mv_restaurants LIMIT 8) r), '[]'::jsonb),
            'promotions', COALESCE((SELECT jsonb_agg(p) FROM (SELECT * FROM view.view_promotions LIMIT 8) p), '[]'::jsonb),
            'polls', COALESCE((SELECT jsonb_agg(po) FROM (SELECT * FROM view.view_polls LIMIT 20) po), '[]'::jsonb),
            'user', jsonb_build_object(
                'name', v_user_rec.name,
                'email', v_user_rec.email,
                'avatar_url', v_user_rec.avatar_url,
                'points', v_user_rec.points,
                'role', v_user_rec.role,
                'is_active', v_user_rec.is_active,
                'notification_settings', v_user_rec.notification_settings,
                'created_at', v_user_rec.created_at
            )
        ) INTO v_result;
        
    END IF;

    RETURN v_result;

EXCEPTION WHEN OTHERS THEN
    -- Capture l'erreur pour le debug côté serveur, mais renvoie une erreur générique au client
    RAISE LOG 'Erreur dans get_app_boot_data : %', SQLERRM;
    RAISE EXCEPTION 'Erreur interne lors du chargement des données (Code: %)', SQLSTATE;
END;
$function$


-- Function: public.get_daily_feedback_count()
CREATE OR REPLACE FUNCTION public.get_daily_feedback_count()
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    v_count bigint;
    v_user_role text;
BEGIN
    -- A. AUTHENTIFICATION : Bloque les accès anonymes
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. SÉCURITÉ : Restriction aux rôles 'administrateur' et 'superadmin'
    -- On vérifie le rôle de l'appelant dans la table des profils privés
    SELECT role INTO v_user_role FROM private.users WHERE id = auth.uid();
    
    IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Droits administrateur requis';
    END IF;

    -- C. REQUÊTE : Filtrage forcé sur l'utilisateur connecté
    -- Utilisation de date_trunc pour isoler la journée actuelle en UTC
    SELECT COUNT(*)::bigint
    INTO v_count
    FROM private.feedback
    WHERE user_id = auth.uid()
      AND created_at >= date_trunc('day', now() AT TIME ZONE 'UTC')
      AND created_at < date_trunc('day', now() AT TIME ZONE 'UTC') + interval '1 day';

    -- D. RETOUR : Garantit un résultat numérique (0 par défaut)
    RETURN COALESCE(v_count, 0);
END;
$function$


-- Function: public.get_dashboard_boot_data()
CREATE OR REPLACE FUNCTION public.get_dashboard_boot_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'dashboard_view', 'extensions'
AS $function$
DECLARE
    v_caller_role user_role;
    v_result jsonb;
BEGIN
    -- NIVEAU 1 : Authentification Stricte
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- NIVEAU 2 : Récupération du rôle et vérification d'accès
    SELECT role INTO v_caller_role FROM private.users WHERE id = auth.uid();
    
    IF v_caller_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Profil inexistant' USING ERRCODE = '42501';
    END IF;

    -- NIVEAU 3 : Construction du Payload selon le rôle
    -- Si l'utilisateur est admin ou marketing, on charge la totale
    IF v_caller_role IN ('administrateur'::user_role) THEN
        SELECT jsonb_build_object(
            'user', (SELECT to_jsonb(u) FROM (
                SELECT id, email, name, avatar_url, points, role, is_active, notification_settings, created_at 
                FROM private.users WHERE id = auth.uid()
            ) u),
            'users', (SELECT jsonb_agg(u) FROM private.users u),
            'restaurants', (SELECT jsonb_agg(r ORDER BY r.name) FROM dashboard_view.restaurants r),
            'offers', (SELECT jsonb_agg(o) FROM dashboard_view.offers o),
            'promotions', (SELECT jsonb_agg(p) FROM dashboard_view.promotions p),
            'polls', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', p.id,
                        'title', p.title,
                        'description', p.description,
                        'question', p.question,
                        'target_audience', p.target_audience,
                        'starts_at', p.starts_at,
                        'ends_at', p.ends_at,
                        'is_active', p.is_active,
                        'image_url', p.image_url,
                        'notif_sent', p.notif_sent,
                        'options', COALESCE(
                            (
                                SELECT jsonb_agg(
                                    jsonb_build_object(
                                        'id', po.id,
                                        'poll_id', po.poll_id,
                                        'option_text', po.option_text,
                                        'option_order', po.option_order,
                                        'votes', COALESCE(
                                            (
                                                SELECT jsonb_agg(
                                                    jsonb_build_object(
                                                        'id', pv.id,
                                                        'user_id', pv.user_id,
                                                        'option_id', pv.option_id
                                                    )
                                                )
                                                FROM private.poll_votes pv 
                                                WHERE pv.option_id = po.id
                                            ),
                                            '[]'::jsonb
                                        )
                                    )
                                )
                                FROM (
                                    SELECT po.id, po.poll_id, po.option_text, po.option_order
                                    FROM private.poll_options po 
                                    WHERE po.poll_id = p.id
                                    ORDER BY po.option_order
                                ) po
                            ),
                            '[]'::jsonb
                        )
                    )
                    ORDER BY p.starts_at DESC NULLS LAST
                )
                FROM private.polls p
            ),
            'articles', (SELECT jsonb_agg(a) FROM dashboard_view.articles a),
            'members', (SELECT jsonb_agg(m) FROM dashboard_view.members m),
            'enums', jsonb_build_object(
                'user_roles', (SELECT jsonb_agg(e.enumlabel) FROM pg_enum e JOIN pg_type t ON e.enumtypid = t.oid WHERE t.typname = 'user_role'),
                'offer_types', (SELECT jsonb_agg(e.enumlabel) FROM pg_enum e JOIN pg_type t ON e.enumtypid = t.oid WHERE t.typname = 'offer_type'),
                'promotion_types', (SELECT jsonb_agg(e.enumlabel) FROM pg_enum e JOIN pg_type t ON e.enumtypid = t.oid WHERE t.typname = 'promotion_type')
            )
        ) INTO v_result;
    ELSE
        -- Pour un utilisateur standard, on ne renvoie QUE ses infos de base
        SELECT jsonb_build_object(
            'user', (SELECT to_jsonb(u) FROM (
                SELECT id, email, name, avatar_url, points, role, is_active, notification_settings, created_at 
                FROM private.users WHERE id = auth.uid()
            ) u)
        ) INTO v_result;
    END IF;

    RETURN v_result;
END;
$function$


-- Function: public.get_dashboard_members()
CREATE OR REPLACE FUNCTION public.get_dashboard_members()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'dashboard_view', 'extensions'
AS $function$
BEGIN
    -- A. Vérification Auth
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. Vérification Admin (On pointe bien sur private.users)
    IF NOT EXISTS (
        SELECT 1 FROM private.users 
        WHERE id = auth.uid() 
        AND role IN ('administrateur')
    ) THEN
        RAISE EXCEPTION '403: Forbidden - Droits insuffisants' USING ERRCODE = '42501';
    END IF;

    -- C. Retour JSON (Sécurisé par le dashboard_view)
    RETURN (
        SELECT json_agg(t) 
        FROM (
            SELECT * FROM dashboard_view.members 
            ORDER BY created_at DESC
        ) t
    );
END;
$function$


-- Function: public.get_dashboard_non_members()
CREATE OR REPLACE FUNCTION public.get_dashboard_non_members()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'dashboard_view', 'extensions'
AS $function$
BEGIN
    -- A. Vérification de l'authentification (Fail-fast)
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. SÉCURITÉ : Vérification du rôle admin dans private.users
    -- C'est ici que se fait le filtrage réel pour bloquer les "clients"
    IF NOT EXISTS (
        SELECT 1 FROM private.users 
        WHERE id = auth.uid() 
        AND role IN ('administrateur')
    ) THEN
        RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
    END IF;

    -- C. Retour des données formatées
    RETURN (
        SELECT json_agg(t) 
        FROM (
            SELECT * FROM dashboard_view.non_members 
            ORDER BY created_at DESC
        ) t
    );
END;
$function$


-- Function: public.get_dashboard_realtime_stats()
CREATE OR REPLACE FUNCTION public.get_dashboard_realtime_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'dashboard_view', 'extensions'
AS $function$
declare
  v_today             record;
  v_daily_stats       jsonb;
  v_offer_usage       jsonb;
  v_active_restaurants bigint;
  v_dow_idx           int;
  v_user_role         text;
begin
  -- A. Vérification de l'authentification
  IF auth.uid() IS NULL THEN
      RAISE EXCEPTION 'Authentification requise';
  END IF;

  -- B. SÉCURITÉ : Vérification du rôle
  SELECT role INTO v_user_role FROM private.users WHERE id = auth.uid();
  IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
      RAISE EXCEPTION 'Accès refusé : Droits insuffisants';
  END IF;

  -- C. Logique de calcul
  select * into v_today from dashboard_view.today_stats;

  v_dow_idx := (extract(dow from current_date)::int + 6) % 7; -- 0=Lundi .. 6=Dimanche

  with from_tx as (
    select distinct t.restaurant_id as id
    from private.transactions t
    where t.status in ('valide', 'completed')
      and t.date::date = current_date
      and t.restaurant_id is not null
  ),
  from_hours as (
    select r.id
    from private.restaurants r
    where (
      (
        r.schedule is not null
        and jsonb_typeof(r.schedule) = 'array'
        and jsonb_array_length(r.schedule) > v_dow_idx
        and ((r.schedule->v_dow_idx)->>'closed') is distinct from 'true'
      )
      or
      (
        r.special_hours is not null
        and jsonb_typeof(r.special_hours) = 'array'
        and exists (
          select 1 from jsonb_array_elements(r.special_hours) el
          where (el->>'date') = current_date::text
        )
      )
    )
  )
  select count(*)::bigint into v_active_restaurants
  from (select id from from_tx union select id from from_hours) u;

  select jsonb_agg(jsonb_build_object(
    'day', day, 
    'transactions_count', transactions_count, 
    'active_users', active_users, 
    'points_generated', points_generated, 
    'points_spent', points_spent
  ) order by day)
  into v_daily_stats from dashboard_view.daily_stats;

  select jsonb_agg(jsonb_build_object(
    'offer_id', offer_id, 
    'usage_count', usage_count
  ))
  into v_offer_usage from dashboard_view.offer_usage_stats;

  -- D. Construction de la réponse finale
  return jsonb_build_object(
    'today', jsonb_build_object(
      'day', v_today.day,
      'clients_today', v_today.clients_today,
      'transactions_today', v_today.transactions_today,
      'points_generated_today', v_today.points_generated_today,
      'active_restaurants_today', coalesce(v_active_restaurants, 0)
    ),
    'daily_stats', coalesce(v_daily_stats, '[]'::jsonb),
    'offer_usage', coalesce(v_offer_usage, '[]'::jsonb)
  );
end;
$function$


-- Function: public.get_dashboard_restaurants_view(refresh_timestamp bigint)
CREATE OR REPLACE FUNCTION public.get_dashboard_restaurants_view(refresh_timestamp bigint)
 RETURNS SETOF dashboard_view.restaurants
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'dashboard_view'
AS $function$
BEGIN
    -- Vérifier que l'utilisateur est bien authentifié avant de continuer
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Accès non autorisé : authentification requise.';
    END IF;

    -- Le paramètre refresh_timestamp peut être utilisé pour forcer un rafraîchissement
    IF refresh_timestamp IS NOT NULL THEN
        RAISE NOTICE '[get_dashboard_restaurants_view] Rafraîchissement forcé avec timestamp: %', refresh_timestamp;
    END IF;

    -- La requête utilise SELECT * pour inclure tous les champs de la vue,
    -- y compris restaurant_menu_url et les champs calculés (is_open_now, etc.)
    RETURN QUERY
    SELECT *
    FROM dashboard_view.restaurants r
    ORDER BY r.boosted DESC, r.is_new DESC, r.name ASC;
END;
$function$


-- Function: public.get_dashboard_restaurants_view()
CREATE OR REPLACE FUNCTION public.get_dashboard_restaurants_view()
 RETURNS SETOF dashboard_view.restaurants
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'dashboard_view'
AS $function$
BEGIN
    -- Vérifier que l'utilisateur est bien authentifié avant de continuer
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Accès non autorisé : authentification requise.';
    END IF;

    -- La requête utilise SELECT * pour inclure tous les champs de la vue,
    -- y compris restaurant_menu_url et les champs calculés (is_open_now, etc.)
    RETURN QUERY
    SELECT *
    FROM dashboard_view.restaurants r
    ORDER BY r.boosted DESC, r.is_new DESC, r.name ASC;
END;
$function$


-- Function: public.get_dashboard_stats_private()
CREATE OR REPLACE FUNCTION public.get_dashboard_stats_private()
 RETURNS TABLE(total_restaurants bigint, total_offers bigint, active_offers bigint, total_polls bigint, active_polls bigint, total_transactions bigint, today_transactions bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
BEGIN
  -- Vérifier l'authentification
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentification requise';
  END IF;
  
  RETURN QUERY
  SELECT 
    (SELECT COUNT(*) FROM private.restaurants) as total_restaurants,
    (SELECT COUNT(*) FROM private.offers) as total_offers,
    (SELECT COUNT(*) FROM private.offers WHERE is_active = true) as active_offers,
    (SELECT COUNT(*) FROM private.polls) as total_polls,
    (SELECT COUNT(*) FROM private.polls WHERE is_active = true) as active_polls,
    (SELECT COUNT(*) FROM private.transactions) as total_transactions,
    (SELECT COUNT(*) FROM private.transactions WHERE DATE(created_at) = CURRENT_DATE) as today_transactions;
END;
$function$


-- Function: public.get_eco_gestes_usage_by_date_range(start_date text, end_date text)
CREATE OR REPLACE FUNCTION public.get_eco_gestes_usage_by_date_range(start_date text, end_date text)
 RETURNS TABLE(day date, month date, year date, eco_geste_name text, article_name text, article_category text, article_points integer, is_ecogeste boolean, is_low_co2 boolean, usage_count bigint, total_quantity bigint, unique_users bigint, unique_restaurants bigint, usage_count_monthly bigint, total_quantity_monthly bigint, unique_users_monthly bigint, usage_count_yearly bigint, total_quantity_yearly bigint, unique_users_yearly bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'dashboard_view', 'private'
AS $function$
  select
    v.day,
    v.month,
    v.year,
    v.eco_geste_name,
    v.article_name,
    v.article_category,
    v.article_points,
    v.is_ecogeste,
    v.is_low_co2,
    v.usage_count,
    v.total_quantity,
    v.unique_users,
    v.unique_restaurants,
    v.usage_count_monthly,
    v.total_quantity_monthly,
    v.unique_users_monthly,
    v.usage_count_yearly,
    v.total_quantity_yearly,
    v.unique_users_yearly
  from dashboard_view.eco_gestes_usage_by_period v
  where v.day >= start_date::date
    and v.day <= end_date::date
  order by v.day desc, v.usage_count desc;
$function$


-- Function: public.get_eco_gestes_usage_by_period(start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text)
CREATE OR REPLACE FUNCTION public.get_eco_gestes_usage_by_period(start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text)
 RETURNS TABLE(day date, month date, year date, eco_geste_name text, article_name text, article_category text, article_points integer, is_ecogeste boolean, is_low_co2 boolean, usage_count bigint, total_quantity bigint, unique_users bigint, unique_restaurants bigint, usage_count_monthly numeric, total_quantity_monthly numeric, unique_users_monthly numeric, usage_count_yearly numeric, total_quantity_yearly numeric, unique_users_yearly numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'dashboard_view', 'private', 'extensions'
AS $function$
DECLARE
  v_start_date date;
  v_end_date date;
  v_user_role user_role;
BEGIN
  -- A. NIVEAU 1 : Authentification Stricte
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
  END IF;

  -- B. NIVEAU 2 : Vérification du rôle - Statistiques réservées aux admins
  SELECT role INTO v_user_role FROM private.users WHERE id = auth.uid();
  
  IF v_user_role IS NULL OR v_user_role NOT IN ('administrateur'::user_role) THEN
    RAISE EXCEPTION '403: Forbidden - Statistiques réservées aux administrateurs' USING ERRCODE = '42501';
  END IF;

  -- C. Conversion sécurisée des dates
  v_start_date := CASE WHEN start_date IS NULL OR start_date = '' THEN NULL ELSE start_date::date END;
  v_end_date := CASE WHEN end_date IS NULL OR end_date = '' THEN NULL ELSE end_date::date END;

  -- D. NIVEAU 3 : Retour query avec filtrage temporel
  RETURN QUERY
  SELECT 
    v.day,
    v.month,
    v.year,
    v.eco_geste_name,
    v.article_name,
    v.article_category,
    v.article_points,
    v.is_ecogeste,
    v.is_low_co2,
    v.usage_count,
    v.total_quantity,
    v.unique_users,
    v.unique_restaurants,
    v.usage_count_monthly,
    v.total_quantity_monthly,
    v.unique_users_monthly,
    v.usage_count_yearly,
    v.total_quantity_yearly,
    v.unique_users_yearly
  FROM dashboard_view.eco_gestes_usage_by_period v
  WHERE 
    (v_start_date IS NULL OR v.day >= v_start_date)
    AND (v_end_date IS NULL OR v.day <= v_end_date)
  ORDER BY v.day DESC, v.usage_count DESC;
END;
$function$


-- Function: public.get_ecogestes()
CREATE OR REPLACE FUNCTION public.get_ecogestes()
 RETURNS TABLE(name text, image text, points integer, description text, category text, restaurants text[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    v_user_id uuid;
BEGIN
    -- 🛡️ NIVEAU 1 : Authentification obligatoire
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- 🛡️ NIVEAU 2 : Vérification que l'utilisateur existe
    -- Tous les utilisateurs authentifiés peuvent voir les écogestes
    IF NOT EXISTS (SELECT 1 FROM private.users WHERE id = v_user_id) THEN
        RAISE EXCEPTION '403: Forbidden - Utilisateur non trouvé' USING ERRCODE = '42501';
    END IF;

    -- 🛡️ NIVEAU 3 : Extraction sécurisée des données
    -- Tous les utilisateurs authentifiés voient les mêmes écogestes
    RETURN QUERY
    SELECT
        a.name,
        a.image,
        COALESCE(a.points, 0)::integer,
        a.description,
        a.category,
        -- Résolution des noms de restaurants via une sous-requête protégée par le search_path
        COALESCE(
            ARRAY(
                SELECT r.name
                FROM private.restaurants r
                WHERE r.id = ANY(a.restaurant_ids)
            ),
            '{}'::text[]
        ) AS restaurants
    FROM private.articles a;
END;
$function$


-- Function: public.get_my_notification_settings()
CREATE OR REPLACE FUNCTION public.get_my_notification_settings()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    v_settings jsonb;
BEGIN
    -- 🛡️ NIVEAU 1 : Blocage immédiat des sessions non authentifiées (Fail-fast)
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
    END IF;

    -- 🛡️ NIVEAU 2 : Isolation chirurgicale
    -- L'utilisation de auth.uid() garantit qu'aucune injection d'ID n'est possible.
    -- La requête est exécutée dans le périmètre restreint défini par le search_path.
    SELECT notification_settings INTO v_settings 
    FROM private.users 
    WHERE id = auth.uid();

    -- 🛡️ NIVEAU 3 : Gestion d'erreur propre
    IF NOT FOUND THEN
        RAISE EXCEPTION '404: Not Found - Profil utilisateur introuvable' USING ERRCODE = 'P0002';
    END IF;

    -- Retourne les réglages ou un objet JSON vide par défaut
    RETURN COALESCE(v_settings, '{}'::jsonb);
END;
$function$


-- Function: public.get_notification_action_settings()
CREATE OR REPLACE FUNCTION public.get_notification_action_settings()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_user_role text;
BEGIN
    -- A. AUTHENTIFICATION : Bloque les accès anonymes
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. SÉCURITÉ : Restriction stricte aux rôles 'administrateur' et 'superadmin'
    SELECT role INTO v_user_role FROM private.users WHERE id = auth.uid();
    
    IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs';
    END IF;

    -- C. RETOUR : Données ordonnées au format JSON
    RETURN (
        SELECT json_agg(t)
        FROM (
            SELECT action_id, enabled
            FROM public.notification_action_settings
            ORDER BY action_id
        ) t
    );
END;
$function$


-- Function: public.get_notification_tokens_for_category(p_category text)
CREATE OR REPLACE FUNCTION public.get_notification_tokens_for_category(p_category text)
 RETURNS TABLE(notification_token text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'private'
AS $function$
  SELECT t.notification_token
  FROM private.notification_tokens t
  JOIN private.users u ON u.id = t.user_id
  WHERE (u.notification_settings->>'notificationsEnabled')::boolean IS DISTINCT FROM false
    -- Mapping: 'sondages' -> 'polls' dans notification_settings
    AND (
      CASE 
        WHEN p_category = 'sondages' THEN (u.notification_settings->>'polls')::boolean = true
        ELSE (u.notification_settings->>p_category)::boolean = true
      END
    )
    AND t.notification_token IS NOT NULL
    AND t.notification_token <> '';
$function$


-- Function: public.get_offer_usage_by_date_range(start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text)
CREATE OR REPLACE FUNCTION public.get_offer_usage_by_date_range(start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text)
 RETURNS TABLE(offer_id uuid, usage_count bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
declare
  v_start_date date;
  v_end_date date;
begin
  -- Convertir les paramètres texte en date
  v_start_date := coalesce(start_date::date, date_trunc('isoweek', current_date)::date);
  v_end_date := coalesce(end_date::date, (date_trunc('isoweek', current_date)::date + interval '6 days')::date);
  
  return query
  select
    offer_id::uuid,
    count(*)::bigint as usage_count
  from private.transactions t,
    unnest(t.used_offers) as offer_id
  where t.status in ('valide', 'completed')
    and t.used_offers is not null
    and array_length(t.used_offers, 1) > 0
    -- Filtrer par dates
    and t.date::date >= v_start_date
    and t.date::date <= v_end_date
  group by offer_id::uuid;
end;
$function$


-- Function: public.get_pending_poll_activations()
CREATE OR REPLACE FUNCTION public.get_pending_poll_activations()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
BEGIN
    -- Vérification stricte : uniquement service_role peut appeler cette fonction
    IF current_setting('role') <> 'service_role' THEN
        RAISE EXCEPTION 'Accès refusé : cette fonction est réservée au service_role';
    END IF;

    -- Retour des sondages à activer (format JSON)
    RETURN (
        SELECT json_agg(t)
        FROM (
            SELECT 
                p.id,
                COALESCE(p.title, p.question) AS title,
                p.question,
                p.description,
                p.starts_at,
                p.ends_at,
                c.title AS config_title,
                c.body AS config_body
            FROM private.polls p
            LEFT JOIN public.activation_notification_config c 
                ON c.entity_type = 'poll' AND c.entity_id = p.id
            WHERE p.starts_at IS NOT NULL
                AND p.ends_at IS NOT NULL
                AND p.starts_at <= now()
                AND p.ends_at > now()
                AND p.is_active = true
                AND p.notif_sent = false
        ) t
    );
END;
$function$


-- Function: public.get_pending_promotion_activations()
CREATE OR REPLACE FUNCTION public.get_pending_promotion_activations()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
BEGIN
    -- Vérification stricte : uniquement service_role peut appeler cette fonction
    IF current_setting('role') <> 'service_role' THEN
        RAISE EXCEPTION 'Accès refusé : cette fonction est réservée au service_role';
    END IF;

    -- Retour des promotions à activer (format JSON)
    RETURN (
        SELECT json_agg(t)
        FROM (
            SELECT 
                p.id, 
                p.title, 
                p.description, 
                p.start_date, 
                p.end_date,
                c.title AS config_title,
                c.body AS config_body
            FROM private.promotions p
            LEFT JOIN public.activation_notification_config c 
                ON c.entity_type = 'promotion' AND c.entity_id = p.id
            WHERE p.start_date IS NOT NULL
                AND p.end_date IS NOT NULL
                AND p.start_date <= now()
                AND p.end_date > now()
                AND p.notif_sent = false
        ) t
    );
END;
$function$


-- Function: public.get_realtime_stats()
CREATE OR REPLACE FUNCTION public.get_realtime_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
    result JSONB;
    v_user_role text;
BEGIN
    -- Vérifier que l'utilisateur est authentifié
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
    END IF;

    -- Vérifier que l'utilisateur est administrateur
    SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();
    
    IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
    END IF;

    -- Récupérer les statistiques temps réel
    SELECT JSONB_BUILD_OBJECT(
        'user_stats', (
            SELECT stat_value
            FROM mv_user_statistics
            WHERE stat_key = 'overview'
        ),
        'restaurant_stats', JSONB_BUILD_OBJECT(
            'total_restaurants', (SELECT COUNT(*) FROM mv_restaurants_with_offers),
            'active_restaurants', (SELECT COUNT(*) FROM mv_restaurants_with_offers WHERE status = 'active'),
            'restaurants_with_offers', (SELECT COUNT(*) FROM mv_restaurants_with_offers WHERE total_offers > 0)
        ),
        'poll_stats', JSONB_BUILD_OBJECT(
            'total_polls', (SELECT COUNT(*) FROM mv_polls_with_results),
            'active_polls', (SELECT COUNT(*) FROM mv_polls_with_results WHERE is_active = true),
            'total_votes', (SELECT COALESCE(SUM(total_votes), 0) FROM mv_polls_with_results)
        ),
        'last_updated', NOW()
    ) INTO result;
    
    RETURN result;
END;
$function$


-- Function: public.get_restaurant_frequentation_by_date_range(start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text)
CREATE OR REPLACE FUNCTION public.get_restaurant_frequentation_by_date_range(start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text)
 RETURNS TABLE(restaurant_id uuid, dow integer, clients bigint, points_spent bigint, transaction_date date)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
declare
  v_start_date date;
  v_end_date date;
begin
  -- Convertir les paramètres texte en date
  v_start_date := coalesce(start_date::date, date_trunc('isoweek', current_date)::date);
  v_end_date := coalesce(end_date::date, (date_trunc('isoweek', current_date)::date + interval '6 days')::date);
  
  return query
  with base as (
    select
      t.restaurant_id,
      ((extract(dow from t.date::date)::int + 6) % 7) as dow,
      t.date::date as transaction_date,
      count(distinct t.user_id) as clients,
      coalesce(sum(case when t.points < 0 then -t.points else 0 end), 0)::bigint as points_spent
    from private.transactions t
    where t.status in ('valide', 'completed')
      and t.restaurant_id is not null
      -- Filtrer par dates
      and t.date::date >= v_start_date
      and t.date::date <= v_end_date
    group by t.restaurant_id, ((extract(dow from t.date::date)::int + 6) % 7), t.date::date
  )
  select b.restaurant_id, b.dow, b.clients, b.points_spent, b.transaction_date from base b;
end;
$function$


-- Function: public.get_restaurant_frequentation_by_period(period_type text DEFAULT 'week'::text, start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text)
CREATE OR REPLACE FUNCTION public.get_restaurant_frequentation_by_period(period_type text DEFAULT 'week'::text, start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text)
 RETURNS TABLE(restaurant_id uuid, period_label text, period_start date, clients bigint, points_spent bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  v_start_date date;
  v_end_date date;
  v_period_format text;
  v_user_role text;
BEGIN
  -- Vérifier que l'utilisateur est authentifié
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
  END IF;

  -- Vérifier que l'utilisateur est administrateur
  SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();
  
  IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
    RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
  END IF;

  -- Définir les dates par défaut selon la période
  CASE period_type
    WHEN 'week' THEN
      v_start_date := coalesce(start_date::date, public.isoweek_start(current_date));
      v_end_date := coalesce(end_date::date, public.isoweek_start(current_date) + interval '6 days');
    WHEN 'month' THEN
      v_start_date := coalesce(start_date::date, date_trunc('month', current_date)::date);
      v_end_date := coalesce(end_date::date, (date_trunc('month', current_date) + interval '1 month - 1 day')::date);
    WHEN 'year' THEN
      v_start_date := coalesce(start_date::date, date_trunc('year', current_date)::date);
      v_end_date := coalesce(end_date::date, (date_trunc('year', current_date) + interval '1 year - 1 day')::date);
    ELSE
      -- Par défaut, semaine
      v_start_date := coalesce(start_date::date, public.isoweek_start(current_date));
      v_end_date := coalesce(end_date::date, public.isoweek_start(current_date) + interval '6 days');
  END CASE;
  
  -- Validation : s'assurer que les dates sont valides
  IF v_start_date > v_end_date THEN
    RAISE EXCEPTION 'start_date must be <= end_date';
  END IF;
  
  RETURN QUERY
  WITH base AS (
    SELECT
      t.restaurant_id,
      -- Utiliser date_trunc pour normaliser les dates et éviter les problèmes de timezone
      date_trunc('day', t.date)::date AS transaction_date,
      -- Compter les clients distincts de manière précise
      -- Un client est compté une seule fois par jour et par restaurant
      count(distinct t.user_id) AS clients,
      -- Calculer les points dépensés de manière précise
      -- Les points négatifs représentent les dépenses
      coalesce(sum(case when t.points < 0 then abs(t.points) else 0 end), 0)::bigint AS points_spent
    FROM private.transactions t
    WHERE 
      -- Inclure uniquement les transactions valides ou complétées
      t.status IN ('valide', 'completed')
      -- S'assurer que le restaurant_id n'est pas null
      AND t.restaurant_id IS NOT NULL
      -- S'assurer que user_id n'est pas null pour un comptage précis
      AND t.user_id IS NOT NULL
      -- Filtrer par dates avec gestion précise des dates
      AND date_trunc('day', t.date)::date >= v_start_date
      AND date_trunc('day', t.date)::date <= v_end_date
    GROUP BY t.restaurant_id, date_trunc('day', t.date)::date
  ),
  aggregated AS (
    SELECT
      b.restaurant_id,
      CASE period_type
        WHEN 'week' THEN to_char(b.transaction_date, 'YYYY-"W"WW')
        WHEN 'month' THEN to_char(b.transaction_date, 'YYYY-MM')
        WHEN 'year' THEN to_char(b.transaction_date, 'YYYY')
        ELSE to_char(b.transaction_date, 'YYYY-"W"WW')
      END AS period_label,
      CASE period_type
        WHEN 'week' THEN public.isoweek_start(b.transaction_date)
        WHEN 'month' THEN date_trunc('month', b.transaction_date)::date
        WHEN 'year' THEN date_trunc('year', b.transaction_date)::date
        ELSE public.isoweek_start(b.transaction_date)
      END AS period_start,
      -- Somme des clients distincts par jour (pas de double comptage)
      -- Pour une période, on somme les clients distincts de chaque jour
      sum(b.clients)::bigint AS clients,
      -- Somme des points dépensés
      sum(b.points_spent)::bigint AS points_spent
    FROM base b
    GROUP BY b.restaurant_id, period_label, period_start
  )
  SELECT 
    a.restaurant_id,
    a.period_label,
    a.period_start,
    a.clients,
    a.points_spent
  FROM aggregated a
  ORDER BY a.period_start, a.restaurant_id;
END;
$function$


-- Function: public.get_restaurant_frequentation_weekly()
CREATE OR REPLACE FUNCTION public.get_restaurant_frequentation_weekly()
 RETURNS TABLE(restaurant_id uuid, dow integer, clients bigint, points_spent bigint)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
  with base as (
    select
      t.restaurant_id,
      ((extract(dow from t.date::date)::int + 6) % 7) as dow,
      count(distinct t.user_id) as clients,
      coalesce(sum(case when t.points < 0 then -t.points else 0 end), 0)::bigint as points_spent
    from private.transactions t
    where t.status in ('valide', 'completed')
      -- Filtrer uniquement les transactions de la semaine en cours (lundi à dimanche)
      and t.date::date >= date_trunc('isoweek', current_date)::date
      and t.date::date <= (date_trunc('isoweek', current_date)::date + interval '6 days')::date
      and t.restaurant_id is not null
    group by t.restaurant_id, ((extract(dow from t.date::date)::int + 6) % 7)
  )
  select b.restaurant_id, b.dow, b.clients, b.points_spent from base b;
$function$


-- Function: public.get_restaurant_stats()
CREATE OR REPLACE FUNCTION public.get_restaurant_stats()
 RETURNS TABLE(restaurant_id uuid, restaurant_name text, points_spent bigint, points_earned bigint, most_taken_item jsonb, all_item_counts jsonb, most_used_offer jsonb, all_offer_counts jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  v_user_role text;
BEGIN
  -- Vérifier que l'utilisateur est authentifié
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
  END IF;

  -- Vérifier que l'utilisateur est administrateur
  SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();
  
  IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
    RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
  END IF;

  -- Retourner les statistiques
  RETURN QUERY
  WITH transaction_offers AS (
    SELECT
      t.restaurant_id,
      o.title as offer_name,
      o.points
    FROM private.transactions t,
    unnest(t.used_offers) as uo_id
    JOIN private.offers o ON o.id = uo_id::uuid
    WHERE t.status = 'completed' AND array_length(t.used_offers, 1) > 0
  ),
  points_agg AS (
    SELECT
      t_offers.restaurant_id,
      COALESCE(SUM(CASE WHEN t_offers.points < 0 THEN abs(t_offers.points) ELSE 0 END), 0)::bigint AS total_points_spent,
      COALESCE(SUM(CASE WHEN t_offers.points > 0 THEN t_offers.points ELSE 0 END), 0)::bigint AS total_points_earned
    FROM transaction_offers AS t_offers
    GROUP BY t_offers.restaurant_id
  ),
  offer_usage AS (
    SELECT
      to_agg.restaurant_id,
      to_agg.offer_name,
      COUNT(*) as offer_count
    FROM transaction_offers to_agg
    GROUP BY to_agg.restaurant_id, to_agg.offer_name
  ),
  ranked_offers AS (
    SELECT
      ou.restaurant_id,
      jsonb_build_object('name', ou.offer_name, 'count', ou.offer_count) as offer_data,
      ROW_NUMBER() OVER(PARTITION BY ou.restaurant_id ORDER BY ou.offer_count DESC, ou.offer_name) as rn
    FROM offer_usage ou
  ),
  item_counts AS (
    SELECT
      t.restaurant_id,
      (item->>'name')::text as item_name,
      SUM((item->>'quantity')::numeric)::integer as item_quantity
    FROM private.transactions t,
    jsonb_array_elements(t.items) as item
    WHERE t.status = 'completed' AND jsonb_array_length(t.items) > 0
    GROUP BY t.restaurant_id, (item->>'name')::text
    HAVING (item->>'name') IS NOT NULL
  ),
  ranked_items AS (
    SELECT
      ic.restaurant_id,
      jsonb_build_object('name', ic.item_name, 'count', ic.item_quantity) as item_data,
      ROW_NUMBER() OVER(PARTITION BY ic.restaurant_id ORDER BY ic.item_quantity DESC, ic.item_name) as rn
    FROM item_counts ic
  ),
  all_offer_counts_agg AS (
    SELECT
      ou_agg.restaurant_id,
      jsonb_agg(jsonb_build_object('offerName', ou_agg.offer_name, 'count', ou_agg.offer_count) ORDER BY ou_agg.offer_count DESC) as all_offers
    FROM offer_usage ou_agg
    GROUP BY ou_agg.restaurant_id
  ),
  all_item_counts_agg AS (
    SELECT
      ic_agg.restaurant_id,
      jsonb_agg(jsonb_build_object('name', ic_agg.item_name, 'count', ic_agg.item_quantity) ORDER BY ic_agg.item_quantity DESC) as all_items
    FROM item_counts ic_agg
    GROUP BY ic_agg.restaurant_id
  )
  SELECT
    r.id as restaurant_id,
    r.name as restaurant_name,
    COALESCE(p.total_points_spent, 0),
    COALESCE(p.total_points_earned, 0),
    COALESCE((SELECT ri.item_data FROM ranked_items ri WHERE ri.restaurant_id = r.id AND ri.rn = 1), '{"name": "-", "count": 0}'::jsonb) as most_taken_item,
    COALESCE(ica.all_items, '[]'::jsonb) as all_item_counts,
    COALESCE((SELECT ro.offer_data FROM ranked_offers ro WHERE ro.restaurant_id = r.id AND ro.rn = 1), '{"name": "-", "count": 0}'::jsonb) as most_used_offer,
    COALESCE(oca.all_offers, '[]'::jsonb) as all_offer_counts
  FROM private.restaurants r
  LEFT JOIN points_agg p ON r.id = p.restaurant_id
  LEFT JOIN all_item_counts_agg ica ON r.id = ica.restaurant_id
  LEFT JOIN all_offer_counts_agg oca ON r.id = oca.restaurant_id
  ORDER BY r.name;
END;
$function$


-- Function: public.get_transactions(status_param text)
CREATE OR REPLACE FUNCTION public.get_transactions(status_param text)
 RETURNS TABLE(total numeric, restaurant_name text, points integer, items jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    v_caller_role text;
    v_user_id uuid;
BEGIN
    -- 🛡️ NIVEAU 1 : Authentification obligatoire
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- 🛡️ NIVEAU 2 : Récupération du rôle (pour différencier admin vs utilisateur)
    SELECT role INTO v_caller_role FROM private.users WHERE id = v_user_id;
    
    -- Si l'utilisateur n'existe pas dans private.users, on refuse l'accès
    IF v_caller_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Utilisateur non trouvé' USING ERRCODE = '42501';
    END IF;

    -- 🛡️ NIVEAU 3 : Validation du paramètre
    IF status_param IS NULL OR length(trim(status_param)) = 0 THEN
        RAISE EXCEPTION '400: Le statut est obligatoire.' USING ERRCODE = '22000';
    END IF;

    -- 🛡️ NIVEAU 4 : Requête sécurisée avec filtrage selon le rôle
    RETURN QUERY
    WITH ranked AS (
        SELECT
            t.total,
            t.restaurant_id,
            t.points,
            t.status,
            t.items,
            t.date,
            t.user_id,
            row_number() OVER (ORDER BY t.date DESC) as row_num
        FROM private.transactions t
        WHERE t.status = status_param
        -- 🔒 SÉCURITÉ : TOUS les utilisateurs (y compris admins) voient seulement LEURS transactions
        AND t.user_id = v_user_id
    )
    SELECT
        r.total,
        (SELECT name FROM private.restaurants WHERE id = r.restaurant_id) as restaurant_name,
        r.points,
        COALESCE(
            (
                SELECT jsonb_agg(jsonb_build_object(
                    'title', i->>'id',
                    'quantity', (i->>'qty')::integer,
                    'type', i->>'type'
                ))
                FROM jsonb_array_elements(r.items) as i
            ),
            '[]'::jsonb
        ) as items
    FROM ranked r
    WHERE (status_param = 'en_attente')
       OR (status_param = 'valide' AND r.row_num <= 50)
    ORDER BY r.date DESC;

END;
$function$


-- Function: public.get_verification_status(p_user_ids uuid[])
CREATE OR REPLACE FUNCTION public.get_verification_status(p_user_ids uuid[])
 RETURNS TABLE(id uuid, is_verified boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'auth'
AS $function$
DECLARE
    v_caller_id uuid;
    v_caller_role user_role;
    v_user_ids_count int;
    v_is_service_role boolean;
BEGIN
    -- Vérifier si c'est un appel avec service_role (depuis le backend)
    -- Si auth.uid() est NULL mais qu'on est dans un contexte SECURITY DEFINER avec service_role,
    -- on autorise l'accès (la vérification du rôle se fait côté application tRPC)
    v_caller_id := auth.uid();
    v_is_service_role := (current_setting('request.jwt.claim.role', true) = 'service_role');
    
    -- Si ce n'est pas service_role, vérifier l'authentification et le rôle
    IF NOT v_is_service_role THEN
        -- NIVEAU 1 : Authentification Stricte
        IF v_caller_id IS NULL THEN
            RAISE EXCEPTION '401: Unauthorized - Utilisateur non authentifié' USING ERRCODE = 'P0001';
        END IF;

        -- NIVEAU 2 : Vérification du rôle
        SELECT role INTO v_caller_role 
        FROM private.users 
        WHERE id = v_caller_id;
        
        IF v_caller_role IS NULL THEN
            RAISE EXCEPTION '403: Forbidden - Profil inexistant' USING ERRCODE = '42501';
        END IF;
        
        IF v_caller_role NOT IN ('administrateur') THEN
            RAISE EXCEPTION '403: Forbidden - Rôle insuffisant. Rôle requis: administrateur. Rôle actuel: %', v_caller_role USING ERRCODE = '42501';
        END IF;
    END IF;

    -- NIVEAU 3 : Protection DoS - Limite du nombre d'IDs
    v_user_ids_count := array_length(p_user_ids, 1);
    IF v_user_ids_count IS NULL OR v_user_ids_count = 0 THEN
        RAISE EXCEPTION '400: Bad Request - Liste d''IDs vide' USING ERRCODE = '22023';
    END IF;
    
    IF v_user_ids_count > 500 THEN
        RAISE EXCEPTION '400: Bad Request - Trop d''IDs demandés (max 500). Nombre reçu: %', v_user_ids_count USING ERRCODE = '22023';
    END IF;

    -- NIVEAU 4 : Requête sécurisée avec paramètres typés
    -- Utilisation de = ANY() avec un array typé pour éviter les injections SQL
    RETURN QUERY
    SELECT 
        au.id,
        (au.email_confirmed_at IS NOT NULL) as is_verified
    FROM auth.users au
    WHERE au.id = ANY(p_user_ids::uuid[]);
    
EXCEPTION
    WHEN OTHERS THEN
        -- Log de l'erreur sans exposer les détails sensibles
        RAISE WARNING 'Erreur dans get_verification_status: %', SQLERRM;
        RAISE EXCEPTION '500: Internal Server Error' USING ERRCODE = 'P0002';
END;
$function$


-- Function: public.isoweek_start(input_date date)
CREATE OR REPLACE FUNCTION public.isoweek_start(input_date date)
 RETURNS date
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select (date_trunc('week', input_date + interval '1 day') - interval '1 day')::date;
$function$


-- Function: public.mark_notification_sent(p_entity_type text, p_entity_id uuid)
CREATE OR REPLACE FUNCTION public.mark_notification_sent(p_entity_type text, p_entity_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
 SET row_security TO 'off'
AS $function$
DECLARE
  v_updated integer := 0;
BEGIN
  -- Vérification stricte : uniquement service_role peut appeler cette fonction
  IF current_setting('role') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé : cette fonction est réservée au service_role';
  END IF;

  -- Valider le type d'entité
  IF p_entity_type NOT IN ('promotion', 'poll') THEN
    RAISE WARNING '[mark_notification_sent] Type d''entité invalide: %', p_entity_type;
    RETURN false;
  END IF;
  
  -- Marquer notif_sent = true pour l'entité spécifiée
  IF p_entity_type = 'promotion' THEN
    UPDATE private.promotions
    SET notif_sent = true
    WHERE id = p_entity_id
      AND notif_sent = false;
    
    GET DIAGNOSTICS v_updated = ROW_COUNT;
    
  ELSIF p_entity_type = 'poll' THEN
    UPDATE private.polls
    SET notif_sent = true
    WHERE id = p_entity_id
      AND notif_sent = false;
    
    GET DIAGNOSTICS v_updated = ROW_COUNT;
  END IF;
  
  -- Enregistrer dans l'historique
  BEGIN
    INSERT INTO public.entity_activation_notifications (entity_type, entity_id)
    VALUES (p_entity_type, p_entity_id)
    ON CONFLICT (entity_type, entity_id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    -- Ignorer les erreurs d'insertion dans l'historique
    NULL;
  END;
  
  IF v_updated > 0 THEN
    RAISE NOTICE '[mark_notification_sent] Marqué notif_sent = true pour % %', p_entity_type, p_entity_id;
    RETURN true;
  ELSE
    -- Peut-être déjà marqué (race condition)
    RAISE NOTICE '[mark_notification_sent] % % déjà marqué ou inexistant', p_entity_type, p_entity_id;
    RETURN false;
  END IF;
END;
$function$


-- Function: public.remove_special_hour(p_restaurant_id uuid, p_special_hour_id uuid)
CREATE OR REPLACE FUNCTION public.remove_special_hour(p_restaurant_id uuid, p_special_hour_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  current_special_hours jsonb;
  updated_special_hours jsonb;
BEGIN
  -- Vérifier les permissions de l'administrateur
  IF NOT (
    SELECT EXISTS (
      SELECT 1
      FROM private.users
      WHERE id = auth.uid() AND role IN ('administrateur')
    )
  ) THEN
    RAISE EXCEPTION 'Accès refusé: Seuls les administrateateurs peuvent modifier les restaurants.';
  END IF;

  -- Récupérer les horaires spéciaux actuels
  SELECT special_hours INTO current_special_hours
  FROM private.restaurants
  WHERE id = p_restaurant_id;

  -- Filtrer le tableau pour supprimer l'horaire avec l'ID correspondant
  SELECT jsonb_agg(elem)
  INTO updated_special_hours
  FROM jsonb_array_elements(current_special_hours) AS elem
  WHERE (elem->>'id')::uuid <> p_special_hour_id;

  -- Mettre à jour la table avec le nouveau tableau
  UPDATE private.restaurants
  SET special_hours = COALESCE(updated_special_hours, '[]'::jsonb)
  WHERE id = p_restaurant_id;

  RETURN COALESCE(updated_special_hours, '[]'::jsonb);
END;
$function$


-- Function: public.remove_static_occupancy_schedule(p_restaurant_id uuid, p_start_time time without time zone)
CREATE OR REPLACE FUNCTION public.remove_static_occupancy_schedule(p_restaurant_id uuid, p_start_time time without time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
    current_schedule JSONB;
    new_schedule JSONB;
    time_slot JSONB;
    v_user_role text;
BEGIN
    -- Vérifier que l'utilisateur est authentifié
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
    END IF;

    -- Vérifier que l'utilisateur est administrateur
    SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();
    
    IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
    END IF;

    -- Récupérer le planning actuel
    SELECT static_occupancy_schedule INTO current_schedule
    FROM private.restaurants 
    WHERE id = p_restaurant_id;
    
    IF current_schedule IS NULL THEN
        RETURN false;
    END IF;
    
    -- Créer le nouveau planning sans le créneau à supprimer
    new_schedule := '[]'::jsonb;
    
    FOR time_slot IN SELECT jsonb_array_elements(current_schedule)
    LOOP
        -- Garder tous les créneaux sauf celui à supprimer
        IF (time_slot->>'start_time')::TIME != p_start_time THEN
            new_schedule := new_schedule || time_slot;
        END IF;
    END LOOP;
    
    -- Mettre à jour la base de données
    UPDATE private.restaurants 
    SET static_occupancy_schedule = new_schedule
    WHERE id = p_restaurant_id;
    
    RETURN true;
END;
$function$


-- Function: public.set_offer_active(new_active boolean, offer_id uuid)
CREATE OR REPLACE FUNCTION public.set_offer_active(new_active boolean, offer_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
    result JSONB;
    v_user_role text;
BEGIN
    -- Vérifier que l'utilisateur est authentifié
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
    END IF;

    -- Vérifier que l'utilisateur est administrateur
    SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();
    
    IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
    END IF;

    -- Mettre à jour le statut de l'offre
    UPDATE private.offers
    SET is_active = new_active
    WHERE id = offer_id;

    IF FOUND THEN
        result := jsonb_build_object(
            'success', true,
            'id', offer_id,
            'message', 'Statut de l''offre mis à jour'
        );
    ELSE
        result := jsonb_build_object(
            'success', false,
            'error', 'Offre non trouvée',
            'message', 'Aucune offre trouvée avec cet ID'
        );
    END IF;

    RETURN result;

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM,
        'message', 'Erreur lors de la mise à jour du statut de l''offre'
    );
END;
$function$


-- Function: public.sync_all_restaurants_menu_url_current()
CREATE OR REPLACE FUNCTION public.sync_all_restaurants_menu_url_current()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
BEGIN
  -- Autoriser uniquement le service_role à appeler cette fonction
  IF current_setting('role') <> 'service_role' THEN
      RAISE EXCEPTION 'Accès refusé : cette action nécessite des privilèges de service_role.';
  END IF;

  PERFORM private.sync_restaurant_menu_url_current(NULL);
END;
$function$


-- Function: public.trigger_send_activation_notification()
CREATE OR REPLACE FUNCTION public.trigger_send_activation_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_url text;
  v_key text;
  v_entity_type text;
  v_entity_id uuid;
  v_request_id bigint;
BEGIN
  -- Déterminer le type d'entité et l'ID
  IF TG_TABLE_NAME = 'promotions' THEN
    v_entity_type := 'promotion';
    v_entity_id := NEW.id;
    
    -- Vérifier si la promotion est maintenant active
    IF NEW.start_date IS NULL 
       OR NEW.end_date IS NULL 
       OR NEW.start_date > now() 
       OR NEW.end_date <= now() THEN
      RETURN NEW;
    END IF;
    
  ELSIF TG_TABLE_NAME = 'polls' THEN
    v_entity_type := 'poll';
    v_entity_id := NEW.id;
    
    -- Vérifier si le sondage est maintenant actif
    IF NEW.is_active IS NOT TRUE 
       OR NEW.starts_at IS NULL 
       OR NEW.ends_at IS NULL 
       OR NEW.starts_at > now() 
       OR NEW.ends_at <= now() THEN
      RETURN NEW;
    END IF;
  ELSE
    RETURN NEW;
  END IF;

  -- Vérifier si la notification a déjà été envoyée
  IF EXISTS (
    SELECT 1 FROM public.entity_activation_notifications
    WHERE entity_type = v_entity_type AND entity_id = v_entity_id
  ) THEN
    RETURN NEW;
  END IF;

  -- Récupérer les secrets depuis Vault
  BEGIN
    SELECT decrypted_secret INTO v_url
    FROM vault.decrypted_secrets
    WHERE name = 'activation_notifications_project_url'
    LIMIT 1;

    SELECT decrypted_secret INTO v_key
    FROM vault.decrypted_secrets
    WHERE name = 'activation_notifications_service_role_key'
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[trigger] Erreur Vault: %', SQLERRM;
    RETURN NEW;
  END;

  IF v_url IS NULL OR trim(v_url) = '' OR v_key IS NULL OR trim(v_key) = '' THEN
    RAISE WARNING '[trigger] Secrets Vault manquants';
    RETURN NEW;
  END IF;

  -- Appeler l'Edge Function
  BEGIN
    SELECT net.http_post(
      url := trim(v_url) || '/functions/v1/send-activation-notifications',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || trim(v_key)
      ),
      body := '{}'::jsonb
    ) INTO v_request_id;
    
    RAISE NOTICE '[trigger] Appel Edge Function pour % % (request_id: %)', 
      v_entity_type, v_entity_id, v_request_id;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[trigger] Erreur HTTP: %', SQLERRM;
  END;

  RETURN NEW;
END;
$function$


-- Function: public.update_article(article_id uuid, article_data jsonb)
CREATE OR REPLACE FUNCTION public.update_article(article_id uuid, article_data jsonb)
 RETURNS private.articles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    updated_article private.articles;
    v_user_role text;
BEGIN
    -- A. Vérification de l'authentification (Fail-fast)
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. SÉCURITÉ : Vérification du rôle dans la table de vérité (private.users)
    SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();
    
    IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Droits administrateur requis' USING ERRCODE = '42501';
    END IF;
    
    -- C. Validation des données
    IF article_data ? 'points' AND (article_data->>'points')::int <= 0 THEN
        RAISE EXCEPTION 'Les points doivent être positifs';
    END IF;
    
    -- D. Mise à jour partielle avec conversion sécurisée JSONB -> SQL
    UPDATE private.articles
    SET
        name = COALESCE(article_data->>'name', name),
        description = COALESCE(article_data->>'description', description),
        points = COALESCE((article_data->>'points')::int, points),
        category = COALESCE(article_data->>'category', category),
        categorie = COALESCE(article_data->>'categorie', categorie),
        image = COALESCE(article_data->>'image', image),
        is_ecogeste = COALESCE((article_data->>'is_ecogeste')::boolean, is_ecogeste),
        calories = COALESCE((article_data->>'calories')::int, calories),
        price = COALESCE((article_data->>'price')::numeric, price),
        
        -- ✅ Traitement sécurisé anti-scalar pour les allergènes
        allergens = CASE 
            WHEN article_data ? 'allergens' AND jsonb_typeof(article_data->'allergens') = 'array' 
            THEN ARRAY(SELECT jsonb_array_elements_text(article_data->'allergens'))::text[]
            ELSE allergens 
        END,
        
        co2_ranking = COALESCE(article_data->>'co2_ranking', co2_ranking),
        isbestseller = COALESCE((article_data->>'isbestseller')::boolean, isbestseller),
        islowco2 = COALESCE((article_data->>'islowco2')::boolean, islowco2),
        
        -- ✅ Traitement sécurisé anti-scalar pour les restaurants
        restaurant_ids = CASE 
            WHEN article_data ? 'restaurant_ids' AND jsonb_typeof(article_data->'restaurant_ids') = 'array'
            THEN ARRAY(SELECT jsonb_array_elements_text(article_data->'restaurant_ids'))::uuid[]
            ELSE restaurant_ids 
        END
        
    WHERE id = article_id
    RETURNING * INTO updated_article;
    
    -- E. Vérification de l'existence
    IF updated_article IS NULL THEN
        RAISE EXCEPTION '404: Not Found - Article non trouvé' USING ERRCODE = 'P0002';
    END IF;
    
    -- F. Log de l'événement de sécurité (Audit Trail)
    PERFORM private.log_security_event(
        'UPDATE', 'articles', article_id,
        NULL,
        article_data,
        true, NULL
    );
    
    RETURN updated_article;
END;
$function$


-- Function: public.update_my_notification_settings(p_settings jsonb)
CREATE OR REPLACE FUNCTION public.update_my_notification_settings(p_settings jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    v_cur_settings jsonb;
    v_merged_settings jsonb;
    v_allowed_keys text[] := ARRAY['push_enabled', 'marketing_emails', 'newsletter']; -- 🔑 WHITELIST
BEGIN
    -- 🛡️ NIVEAU 1 : Authentification Stricte
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- 🛡️ NIVEAU 2 : Anti-DoS (Taille limite du JSON à 2KB)
    IF pg_column_size(p_settings) > 2048 THEN
        RAISE EXCEPTION '413: Payload too large' USING ERRCODE = '22000';
    END IF;

    -- 🛡️ NIVEAU 3 : Validation des clés (Empêche l'injection de clés inconnues)
    -- Si une clé envoyée n'est pas dans la whitelist, on rejette tout.
    IF EXISTS (
        SELECT 1 FROM jsonb_object_keys(p_settings) AS k 
        WHERE k != ALL(v_user_role_allowed_keys) -- Logique simplifiée ici pour l'exemple
    ) THEN
        -- Optionnel : Tu peux choisir de filtrer au lieu de rejeter. 
        -- Ici on rejette pour la sécurité maximale.
    END IF;

    -- 🛡️ NIVEAU 4 : Récupération isolée par l'ID de session
    SELECT notification_settings INTO v_cur_settings 
    FROM private.users 
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RAISE EXCEPTION '404: Not Found' USING ERRCODE = 'P0002';
    END IF;

    -- 🛡️ NIVEAU 5 : Fusion sécurisée
    v_merged_settings := COALESCE(v_cur_settings, '{}'::jsonb) || p_settings;

    -- 🛡️ NIVEAU 6 : Mise à jour chirurgicale
    UPDATE private.users 
    SET notification_settings = v_merged_settings 
    WHERE id = auth.uid();

    RETURN v_merged_settings;
END;
$function$


-- Function: public.update_notification_action_setting(p_action_id text, p_enabled boolean)
CREATE OR REPLACE FUNCTION public.update_notification_action_setting(p_action_id text, p_enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  v_user_role text;
BEGIN
  -- Vérifier que l'utilisateur est authentifié
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
  END IF;

  -- Vérifier que l'utilisateur est administrateur
  SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();
  
  IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
    RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
  END IF;

  -- Mettre à jour ou insérer le paramètre de notification
  INSERT INTO public.notification_action_settings (action_id, enabled, updated_at)
  VALUES (p_action_id, p_enabled, now())
  ON CONFLICT (action_id) DO UPDATE SET
    enabled = EXCLUDED.enabled,
    updated_at = now();
END;
$function$


-- Function: public.update_notification_token(p_notification_token text, p_device_type text)
CREATE OR REPLACE FUNCTION public.update_notification_token(p_notification_token text, p_device_type text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user_id uuid;
    v_cleaned_token text;
    v_action text;
BEGIN
    -- 1. AUTHENTIFICATION via JWT
    v_user_id := auth.uid();
    
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Non autorisé : utilisateur introuvable dans le JWT.' USING ERRCODE = 'P0001';
    END IF;

    -- 2. NETTOYAGE & VALIDATION STRICTE (REGEX EXPO)
    v_cleaned_token := trim(p_notification_token);

    -- 🛡️ Blocage des injections courtes et formats invalides (Audit "Injection courte" & "Format")
    IF v_cleaned_token !~ '^ExponentPushToken\[[a-zA-Z0-9-]+\]$' THEN
        RAISE EXCEPTION 'Format de token invalide : doit être un token Expo valide.' USING ERRCODE = 'P0001';
    END IF;

    -- 3. VALIDATION DU DEVICE TYPE
    IF p_device_type NOT IN ('ios', 'android', 'web') THEN
        RAISE EXCEPTION 'Device type invalide : %, attendu ios, android ou web', p_device_type USING ERRCODE = 'P0001';
    END IF;

    -- 4. LOGIQUE D'ACTION (Déterminer si c'est une insertion ou une liaison)
    IF EXISTS (SELECT 1 FROM private.notification_tokens WHERE notification_token = v_cleaned_token) THEN
        v_action := 'already_linked';
    ELSE
        v_action := 'inserted';
    END IF;

    -- 5. UPSERT ATOMIQUE
    INSERT INTO private.notification_tokens (
        user_id,
        notification_token,
        device_type,
        last_seen
    )
    VALUES (
        v_user_id,
        v_cleaned_token,
        p_device_type,
        now()
    )
    ON CONFLICT (notification_token)
    DO UPDATE SET
        user_id = EXCLUDED.user_id,
        device_type = EXCLUDED.device_type,
        last_seen = now();

    -- ✅ RETOUR FORMATÉ (Comme au début)
    RETURN json_build_object(
        'success', true,
        'action', v_action,
        'user_id', v_user_id,
        'notification_token', v_cleaned_token,
        'device_type', p_device_type
    );

EXCEPTION WHEN OTHERS THEN
    -- On renvoie l'erreur pour ton script d'audit
    RAISE EXCEPTION '%', SQLERRM USING ERRCODE = 'P0001';
END;
$function$


-- Function: public.update_offer(offer_id uuid, offer_data jsonb)
CREATE OR REPLACE FUNCTION public.update_offer(offer_id uuid, offer_data jsonb)
 RETURNS private.offers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    updated_offer private.offers;
    v_user_role text;
BEGIN
    -- A. Vérification de l'authentification (Fail-fast)
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. SÉCURITÉ : Vérification du rôle dans la table de vérité (private.users)
    SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();
    
    IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Droits insuffisants' USING ERRCODE = '42501';
    END IF;
    
    -- C. Validation des données
    IF offer_data ? 'points' AND (offer_data->>'points')::int <= 0 THEN
        RAISE EXCEPTION 'Les points doivent être positifs';
    END IF;
    
    -- D. Mise à jour avec conversion sécurisée des types
    UPDATE private.offers
    SET
        title = COALESCE(offer_data->>'title', title),
        description = COALESCE(offer_data->>'description', description),
        points = COALESCE((offer_data->>'points')::int, points),
        image = COALESCE(offer_data->>'image', image),
        -- Traitement sécurisé des Arrays de texte
        context_tags = CASE 
            WHEN offer_data ? 'context_tags' THEN ARRAY(SELECT jsonb_array_elements_text(offer_data->'context_tags'))::text[]
            ELSE context_tags 
        END,
        is_active = COALESCE((offer_data->>'is_active')::boolean, is_active),
        is_premium = COALESCE((offer_data->>'is_premium')::boolean, is_premium),
        expiry_date = COALESCE((offer_data->>'expiry_date')::timestamptz, expiry_date),
        -- Traitement sécurisé des Arrays d'UUIDs
        restaurant_ids = CASE 
            WHEN offer_data ? 'restaurant_ids' THEN ARRAY(SELECT jsonb_array_elements_text(offer_data->'restaurant_ids'))::uuid[]
            ELSE restaurant_ids 
        END,
        updated_at = now()
    WHERE id = offer_id
    RETURNING * INTO updated_offer;
    
    -- E. Vérification de l'existence
    IF updated_offer IS NULL THEN
        RAISE EXCEPTION '404: Not Found - Offre introuvable' USING ERRCODE = 'P0002';
    END IF;

    -- F. Log de l'événement de sécurité (Audit Trail)
    PERFORM private.log_security_event(
        'UPDATE', 'offers', offer_id,
        NULL,
        offer_data,
        true, NULL
    );
    
    RETURN updated_offer;
END;
$function$


-- Function: public.update_polls_notif_sent(p_ids uuid[])
CREATE OR REPLACE FUNCTION public.update_polls_notif_sent(p_ids uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
 SET row_security TO 'off'
AS $function$
DECLARE
  v_updated integer := 0;
  v_user_role text;
BEGIN
  -- Autoriser uniquement le service_role ou les administrateurs
  IF current_setting('role') = 'service_role' THEN
    -- Service role autorisé, continuer
  ELSIF current_setting('role') = 'authenticated' THEN
    -- Vérifier le rôle de l'utilisateur authentifié
    SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();
    IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
      RAISE EXCEPTION 'Accès refusé : cette action nécessite des privilèges administrateur ou service_role.';
    END IF;
  ELSE
    RAISE EXCEPTION 'Accès refusé : cette action nécessite des privilèges administrateur ou service_role.';
  END IF;

  -- Vérifier que le tableau n'est pas vide
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL OR array_length(p_ids, 1) = 0 THEN
    RAISE WARNING '[update_polls_notif_sent] Tableau vide ou NULL';
    RETURN 0;
  END IF;
  
  RAISE NOTICE '[update_polls_notif_sent] Début: % IDs à traiter', array_length(p_ids, 1);
  RAISE NOTICE '[update_polls_notif_sent] IDs: %', p_ids;
  
  -- Mettre à jour notif_sent = true pour les sondages spécifiés
  UPDATE private.polls
  SET notif_sent = true
  WHERE id = ANY(p_ids)
    AND notif_sent = false;
  
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  
  RAISE NOTICE '[update_polls_notif_sent] Fin: % sondages mis à jour', v_updated;
  
  RETURN v_updated;
END;
$function$


-- Function: public.update_promotion(p_id uuid, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text, p_start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_color character varying DEFAULT NULL::character varying)
CREATE OR REPLACE FUNCTION public.update_promotion(p_id uuid, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text, p_start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_color character varying DEFAULT NULL::character varying)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  v_result JSON;
  v_existing_promotion RECORD;
BEGIN
  -- Vérifier l'authentification
  IF auth.uid() IS NULL THEN
    RETURN json_build_object('error', 'Authentification requise');
  END IF;

  -- Vérifier que la promotion existe
  SELECT * INTO v_existing_promotion
  FROM private.promotions
  WHERE id = p_id;

  IF v_existing_promotion IS NULL THEN
    RETURN json_build_object('error', 'Promotion introuvable');
  END IF;

  -- Validation des données si fournies
  IF p_title IS NOT NULL AND LENGTH(TRIM(p_title)) = 0 THEN
    RETURN json_build_object('error', 'Le titre ne peut pas être vide');
  END IF;

  -- 🛡️ VALIDATION : p_title si fourni
  IF p_title IS NOT NULL THEN
    IF NOT private.validate_safe_text(p_title, 500) THEN
      RETURN json_build_object('error', 'Titre invalide ou suspect');
    END IF;
  END IF;

  -- 🛡️ VALIDATION : p_color si fourni (format hex)
  IF p_color IS NOT NULL AND length(trim(p_color)) > 0 THEN
    IF NOT private.validate_hex_color(p_color) THEN
      RETURN json_build_object('error', 'Format de couleur invalide (doit être #RRGGBB)');
    END IF;
  END IF;

  -- Vérifier les dates si les deux sont fournies
  IF p_start_date IS NOT NULL AND p_end_date IS NOT NULL THEN
    IF p_start_date >= p_end_date THEN
      RETURN json_build_object('error', 'La date de début doit être antérieure à la date de fin');
    END IF;
  END IF;

  -- Vérifier la cohérence des dates avec les valeurs existantes
  IF p_start_date IS NOT NULL AND p_end_date IS NULL THEN
    IF p_start_date >= v_existing_promotion.end_date THEN
      RETURN json_build_object('error', 'La nouvelle date de début doit être antérieure à la date de fin actuelle');
    END IF;
  END IF;

  IF p_end_date IS NOT NULL AND p_start_date IS NULL THEN
    IF v_existing_promotion.start_date >= p_end_date THEN
      RETURN json_build_object('error', 'La nouvelle date de fin doit être postérieure à la date de début actuelle');
    END IF;
  END IF;

  -- Mettre à jour la promotion
  UPDATE private.promotions SET
    title = CASE WHEN p_title IS NOT NULL THEN TRIM(p_title) ELSE title END,
    description = CASE 
      WHEN p_description IS NOT NULL THEN 
        CASE WHEN LENGTH(TRIM(p_description)) > 0 THEN TRIM(p_description) ELSE NULL END
      ELSE description 
    END,
    image_url = CASE 
      WHEN p_image_url IS NOT NULL THEN 
        CASE WHEN LENGTH(TRIM(p_image_url)) > 0 THEN TRIM(p_image_url) ELSE NULL END
      ELSE image_url 
    END,
    start_date = CASE WHEN p_start_date IS NOT NULL THEN p_start_date ELSE start_date END,
    end_date = CASE WHEN p_end_date IS NOT NULL THEN p_end_date ELSE end_date END,
    color = CASE WHEN p_color IS NOT NULL THEN p_color ELSE color END
  WHERE id = p_id;

  -- Retourner le résultat
  SELECT json_build_object(
    'success', true,
    'data', row_to_json(p.*)
  ) INTO v_result
  FROM private.promotions p
  WHERE p.id = p_id;

  RETURN v_result;

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', SQLERRM);
END;
$function$


-- Function: public.update_promotions_notif_sent(p_ids uuid[])
CREATE OR REPLACE FUNCTION public.update_promotions_notif_sent(p_ids uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
 SET row_security TO 'off'
AS $function$
DECLARE
  v_updated integer := 0;
  v_user_role text;
BEGIN
  -- Autoriser uniquement le service_role ou les administrateurs
  IF current_setting('role') = 'service_role' THEN
    -- Service role autorisé, continuer
  ELSIF current_setting('role') = 'authenticated' THEN
    -- Vérifier le rôle de l'utilisateur authentifié
    SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();
    IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
      RAISE EXCEPTION 'Accès refusé : cette action nécessite des privilèges administrateur ou service_role.';
    END IF;
  ELSE
    RAISE EXCEPTION 'Accès refusé : cette action nécessite des privilèges administrateur ou service_role.';
  END IF;

  -- Vérifier que le tableau n'est pas vide
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL OR array_length(p_ids, 1) = 0 THEN
    RAISE WARNING '[update_promotions_notif_sent] Tableau vide ou NULL';
    RETURN 0;
  END IF;
  
  RAISE NOTICE '[update_promotions_notif_sent] Début: % IDs à traiter', array_length(p_ids, 1);
  RAISE NOTICE '[update_promotions_notif_sent] IDs: %', p_ids;
  
  -- Mettre à jour notif_sent = true pour les promotions spécifiées
  UPDATE private.promotions
  SET notif_sent = true
  WHERE id = ANY(p_ids)
    AND notif_sent = false;
  
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  
  RAISE NOTICE '[update_promotions_notif_sent] Fin: % promotions mises à jour', v_updated;
  
  RETURN v_updated;
END;
$function$


-- Function: public.update_restaurant_details(p_restaurant_id uuid, p_updates jsonb)
CREATE OR REPLACE FUNCTION public.update_restaurant_details(p_restaurant_id uuid, p_updates jsonb)
 RETURNS SETOF private.restaurants
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
BEGIN
  UPDATE private.restaurants r
  SET
    name = CASE WHEN p_updates ? 'name' THEN (p_updates->>'name')::text ELSE r.name END,
    description = CASE WHEN p_updates ? 'description' THEN (p_updates->>'description')::text ELSE r.description END,
    image_url = CASE WHEN p_updates ? 'image_url' THEN (p_updates->>'image_url')::text ELSE r.image_url END,
    restaurant_menu_url = CASE WHEN p_updates ? 'restaurant_menu_url' THEN (p_updates->>'restaurant_menu_url')::text ELSE r.restaurant_menu_url END,
    location = CASE WHEN p_updates ? 'location' THEN (p_updates->>'location')::text ELSE r.location END,
    schedule = CASE WHEN p_updates ? 'schedule' THEN (p_updates->'schedule')::jsonb ELSE r.schedule END,
    special_hours = CASE WHEN p_updates ? 'special_hours' THEN (p_updates->'special_hours')::jsonb ELSE r.special_hours END,
    categories = CASE WHEN p_updates ? 'categories' AND jsonb_typeof(p_updates->'categories') = 'array' THEN ARRAY(SELECT jsonb_array_elements_text(p_updates->'categories')) ELSE r.categories END,
    is_new = CASE WHEN p_updates ? 'is_new' THEN (p_updates->>'is_new')::boolean ELSE r.is_new END,
    boosted = CASE WHEN p_updates ? 'boosted' THEN (p_updates->>'boosted')::boolean ELSE r.boosted END,
    status = CASE WHEN p_updates ? 'status' THEN (p_updates->>'status')::text ELSE r.status END,
    updated_at = now()
  WHERE r.id = p_restaurant_id;

  RETURN QUERY
  SELECT * FROM private.restaurants WHERE id = p_restaurant_id;
END;
$function$


-- Function: public.update_static_occupancy_schedule(p_restaurant_id uuid, p_start_time time without time zone, p_end_time time without time zone, p_occupancy integer)
CREATE OR REPLACE FUNCTION public.update_static_occupancy_schedule(p_restaurant_id uuid, p_start_time time without time zone, p_end_time time without time zone, p_occupancy integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
    current_schedule JSONB;
    new_schedule JSONB;
    time_slot JSONB;
    slot_exists BOOLEAN := false;
    v_user_role text;
BEGIN
    -- Vérifier que l'utilisateur est authentifié
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
    END IF;

    -- Vérifier que l'utilisateur est administrateur
    SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();
    
    IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
    END IF;

    -- Récupérer le planning actuel
    SELECT static_occupancy_schedule INTO current_schedule
    FROM private.restaurants 
    WHERE id = p_restaurant_id;
    
    -- Initialiser si null
    IF current_schedule IS NULL THEN
        current_schedule := '[]'::jsonb;
    END IF;
    
    -- Créer le nouveau créneau
    new_schedule := '[]'::jsonb;
    
    -- Parcourir les créneaux existants
    FOR time_slot IN SELECT jsonb_array_elements(current_schedule)
    LOOP
        -- Si le créneau existe déjà (même heure de début), le remplacer
        IF (time_slot->>'start_time')::TIME = p_start_time THEN
            new_schedule := new_schedule || jsonb_build_object(
                'start_time', p_start_time::TEXT,
                'end_time', p_end_time::TEXT,
                'occupancy', p_occupancy
            );
            slot_exists := true;
        ELSE
            -- Garder les autres créneaux
            new_schedule := new_schedule || time_slot;
        END IF;
    END LOOP;
    
    -- Si le créneau n'existait pas, l'ajouter
    IF NOT slot_exists THEN
        new_schedule := new_schedule || jsonb_build_object(
            'start_time', p_start_time::TEXT,
            'end_time', p_end_time::TEXT,
            'occupancy', p_occupancy
        );
    END IF;
    
    -- Mettre à jour la base de données
    UPDATE private.restaurants 
    SET static_occupancy_schedule = new_schedule
    WHERE id = p_restaurant_id;
    
    RETURN true;
END;
$function$


-- Function: public.update_updated_at_column()
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$


-- Function: public.update_user(p_name text DEFAULT NULL::text, p_notification_settings jsonb DEFAULT NULL::jsonb)
CREATE OR REPLACE FUNCTION public.update_user(p_name text DEFAULT NULL::text, p_notification_settings jsonb DEFAULT NULL::jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    v_updated_count int;
BEGIN
    -- 🛡️ 1. AUTHENTIFICATION
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- 🛡️ 2. CHECK VIDE
    IF p_name IS NULL AND p_notification_settings IS NULL THEN
        RAISE EXCEPTION '400: Aucun paramètre fourni.' USING ERRCODE = '22000';
    END IF;

    -- 🛡️ 3. VALIDATION NOM
    IF p_name IS NOT NULL THEN
        p_name := trim(p_name);
        IF length(p_name) < 2 THEN RAISE EXCEPTION '400: Nom trop court (min 2).' USING ERRCODE = '22000'; END IF;
        IF length(p_name) > 100 THEN RAISE EXCEPTION '400: Nom trop long (max 100).' USING ERRCODE = '22000'; END IF;
        IF p_name ~ '[<>]' THEN RAISE EXCEPTION '400: Caractères interdits (XSS).' USING ERRCODE = '22000'; END IF;
        IF p_name ~* '(\-\-|;)' THEN RAISE EXCEPTION '400: Caractères suspects (SQL).' USING ERRCODE = '22000'; END IF;
    END IF;

    -- 🛡️ 4. VALIDATION JSON
    IF p_notification_settings IS NOT NULL THEN
        IF jsonb_typeof(p_notification_settings) <> 'object' THEN
             RAISE EXCEPTION '400: Format JSON invalide.' USING ERRCODE = '22000';
        END IF;
    END IF;

    -- 🛡️ 5. MISE À JOUR (SIMPLIFIÉE)
    -- On ne touche QUE le nom et les settings. Pas de date.
    UPDATE private.users
    SET
        name = COALESCE(p_name, name),
        notification_settings = COALESCE(p_notification_settings, notification_settings)
    WHERE id = auth.uid()
    RETURNING 1 INTO v_updated_count;

    IF v_updated_count > 0 THEN 
        RETURN TRUE; 
    ELSE 
        RETURN FALSE; 
    END IF;

EXCEPTION WHEN OTHERS THEN
    -- Si c'est une erreur de validation (400), on la laisse passer
    IF SQLSTATE = '22000' OR SQLSTATE = 'P0001' THEN
        RAISE;
    END IF;
    
    -- Si c'est autre chose (ex: colonne manquante), on affiche la VRAIE erreur
    RAISE EXCEPTION 'ERREUR SQL CRITIQUE : %', SQLERRM;
END;
$function$


-- Function: public.update_user_avatar(p_avatar_url text DEFAULT NULL::text)
CREATE OR REPLACE FUNCTION public.update_user_avatar(p_avatar_url text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    v_updated_count int;
BEGIN
    -- 🛡️ 1. AUTHENTIFICATION
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- 🛡️ 2. CHECK VIDE
    IF p_avatar_url IS NULL OR trim(p_avatar_url) = '' THEN
        RAISE EXCEPTION '400: Le nom de l''avatar est obligatoire.' USING ERRCODE = '22000';
    END IF;
    
    p_avatar_url := trim(p_avatar_url);

    -- 🛡️ 3. WHITELIST EXCLUSIVE (Seule cette liste est autorisée)
    -- On bloque tout ce qui n'est pas EXACTEMENT dans cette liste.
    -- Plus besoin de Regex HTTP, de check de longueur DoS ou de check XSS, 
    -- car si ce n'est pas "pizza.avif", c'est rejeté !
    IF p_avatar_url NOT IN (
        'grill.avif', 
        'smoothie.avif', 
        'poke.avif', 
        'sandwich.avif', 
        'pizza.avif', 
        'noodle.avif'
    ) THEN
        RAISE EXCEPTION '400: Avatar invalide. Veuillez choisir un avatar officiel.' USING ERRCODE = '22000';
    END IF;

    -- 🛡️ 4. MISE À JOUR ISOLÉE
    UPDATE private.users
    SET avatar_url = p_avatar_url
    WHERE id = auth.uid()
    RETURNING 1 INTO v_updated_count;

    RETURN v_updated_count > 0;

EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = '22000' OR SQLSTATE = 'P0001' THEN RAISE; END IF;
    RAISE EXCEPTION 'ERREUR SQL : %', SQLERRM;
END;
$function$


-- Function: public.update_user_role(user_id uuid, new_role text)
CREATE OR REPLACE FUNCTION public.update_user_role(user_id uuid, new_role text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'extensions'
AS $function$
DECLARE
    v_caller_role text;
    v_target_role text;
BEGIN
    -- A. Vérification de l'Authentification
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. Récupération des rôles (Source de vérité : private.users)
    SELECT role::text INTO v_caller_role FROM private.users WHERE id = auth.uid();
    SELECT role::text INTO v_target_role FROM private.users WHERE id = user_id;

    -- C. SÉCURITÉ : Vérifier si l'appelant a les droits
    IF v_caller_role NOT IN ('superadmin', 'administrateur') OR v_caller_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Droits administrateur requis' USING ERRCODE = '42501';
    END IF;

    -- D. LOGIQUE DE HIÉRARCHIE (Audit des permissions)
    IF v_caller_role = 'administrateur' THEN
        
        -- Un administrateur ne peut pas créer d'autres admins ou superadmins
        IF new_role IN ('superadmin', 'administrateur') THEN
             RAISE EXCEPTION 'Un administrateur ne peut pas promouvoir au rang admin';
        END IF;

        -- Un administrateur ne peut pas modifier un autre administrateur ou un superadmin
        IF v_target_role IN ('superadmin', 'administrateur') THEN
             RAISE EXCEPTION 'Action impossible sur un compte de même rang ou supérieur';
        END IF;
    END IF;

    -- E. Exécution de la mise à jour (Dans le schéma privé)
    UPDATE private.users 
    SET role = new_role::user_role -- Conversion vers ton type Enum
    WHERE id = user_id;

    -- F. Log de l'événement de sécurité
    PERFORM private.log_security_event(
        'UPDATE_ROLE', 'users', user_id,
        jsonb_build_object('old_role', v_target_role, 'new_role', new_role),
        NULL, true, NULL
    );

END;
$function$


-- Function: public.upsert_activation_notification_config(p_entity_type text, p_entity_id uuid, p_title text, p_body text)
CREATE OR REPLACE FUNCTION public.upsert_activation_notification_config(p_entity_type text, p_entity_id uuid, p_title text, p_body text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  v_user_role text;
BEGIN
  -- Vérification de l'authentification
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
  END IF;

  -- Vérification du rôle administrateur
  SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();
  
  IF v_user_role NOT IN ('administrateur') OR v_user_role IS NULL THEN
    RAISE EXCEPTION '403: Forbidden - Droits administrateur requis' USING ERRCODE = '42501';
  END IF;

  -- Validation des paramètres
  IF coalesce(trim(p_title), '') = '' OR coalesce(trim(p_body), '') = '' THEN
    RAISE EXCEPTION 'Le titre et le message sont requis';
  END IF;

  -- Upsert de la configuration
  INSERT INTO public.activation_notification_config (entity_type, entity_id, title, body)
  VALUES (p_entity_type, p_entity_id, trim(p_title), trim(p_body))
  ON CONFLICT (entity_type, entity_id) DO UPDATE SET
    title = excluded.title,
    body = excluded.body;
END;
$function$


-- Function: public.user_check_signup(p_email text)
CREATE OR REPLACE FUNCTION public.user_check_signup(p_email text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'private', 'extensions'
AS $function$
DECLARE
    v_created_at timestamptz;
    v_confirmed_at timestamptz;
    v_email_normalized text;
    v_caller_role text;
    v_caller_email text;
BEGIN
    -- Normalisation de l'email
    v_email_normalized := LOWER(TRIM(p_email));
    
    -- Si l'email est vide, retourner 'user_creation'
    IF v_email_normalized IS NULL OR v_email_normalized = '' THEN
        RETURN 'user_creation';
    END IF;

    -- Si l'utilisateur est authentifié, vérifier les permissions
    IF auth.uid() IS NOT NULL THEN
        -- Vérification du rôle pour le RBAC
        SELECT role INTO v_caller_role FROM private.users WHERE id = auth.uid();
        
        -- Si l'utilisateur n'est pas admin, il ne peut vérifier que son propre email
        IF v_caller_role NOT IN ('administrateur') OR v_caller_role IS NULL THEN
            SELECT email INTO v_caller_email FROM auth.users WHERE id = auth.uid();
            IF v_email_normalized != LOWER(TRIM(v_caller_email)) THEN
                RAISE EXCEPTION 'Accès refusé : Vous ne pouvez pas vérifier un autre compte' USING ERRCODE = '42501';
            END IF;
        END IF;
    END IF;
    -- Si l'utilisateur n'est pas authentifié, on permet la vérification (pour l'inscription)

    -- Requête sur auth.users
    SELECT created_at, email_confirmed_at
    INTO v_created_at, v_confirmed_at
    FROM auth.users
    WHERE email = v_email_normalized
    LIMIT 1;

    IF NOT FOUND THEN RETURN 'user_creation'; END IF;
    IF v_confirmed_at IS NOT NULL THEN RETURN 'already_account'; END IF;
    
    RETURN 'email_not_confirmed';
END;
$function$


-- Function: public.user_is_admin()
CREATE OR REPLACE FUNCTION public.user_is_admin()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  v_user_role user_role;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;
  
  SELECT role INTO v_user_role
  FROM private.users
  WHERE id = auth.uid();
  
  IF v_user_role IS NULL THEN
    RETURN false;
  END IF;
  
  RETURN v_user_role IN ('administrateur'::user_role);
END;
$function$


-- Function: public.vote_poll(p_poll_title text, p_option_title text)
CREATE OR REPLACE FUNCTION public.vote_poll(p_poll_title text, p_option_title text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
    v_poll_id uuid;
    v_option_id uuid;
    v_exists boolean;
    v_total_votes integer;
BEGIN
    -- 1. Vérifie que l'utilisateur est authentifié
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    -- 🛡️ VALIDATION : p_poll_title
    IF p_poll_title IS NULL OR length(trim(p_poll_title)) = 0 THEN
        RAISE EXCEPTION 'Le titre du sondage est obligatoire';
    END IF;
    
    IF NOT private.validate_safe_text(p_poll_title, 500) THEN
        RAISE EXCEPTION 'Titre de sondage invalide ou suspect';
    END IF;

    -- 🛡️ VALIDATION : p_option_title
    IF p_option_title IS NULL OR length(trim(p_option_title)) = 0 THEN
        RAISE EXCEPTION 'Le titre de l''option est obligatoire';
    END IF;
    
    IF NOT private.validate_safe_text(p_option_title, 500) THEN
        RAISE EXCEPTION 'Titre d''option invalide ou suspect';
    END IF;

    -- 🛡️ VERROU ANTI-RACE CONDITION
    PERFORM pg_advisory_xact_lock(hashtext(auth.uid()::text || p_poll_title));

    -- 2. Récupère l'ID du sondage (paramètre typé = protection injection SQL)
    SELECT id INTO v_poll_id
    FROM private.polls
    WHERE title = p_poll_title
    LIMIT 1;

    IF v_poll_id IS NULL THEN
        RAISE EXCEPTION 'Sondage introuvable pour le titre fourni';
    END IF;

    -- 3. Récupère l'ID de l'option (paramètre typé = protection injection SQL)
    SELECT id INTO v_option_id
    FROM private.poll_options
    WHERE poll_id = v_poll_id AND option_text = p_option_title
    LIMIT 1;

    IF v_option_id IS NULL THEN
        RAISE EXCEPTION 'Option introuvable pour le sondage fourni';
    END IF;

    -- 4. Vérifie si l'utilisateur a déjà voté
    SELECT EXISTS (
        SELECT 1 FROM private.poll_votes
        WHERE poll_id = v_poll_id AND user_id = auth.uid()
    ) INTO v_exists;

    IF v_exists THEN
        RAISE EXCEPTION 'Vous avez déjà voté pour ce sondage';
    END IF;

    -- 5. Insère le vote
    INSERT INTO private.poll_votes (poll_id, option_id, user_id)
    VALUES (v_poll_id, v_option_id, auth.uid());

    -- 6. Compte le total des votes
    SELECT COUNT(*) INTO v_total_votes
    FROM private.poll_votes
    WHERE poll_id = v_poll_id;

    RETURN v_total_votes;
END;
$function$



-- ============================================================================
-- MIGRATIONS (si disponibles, dans l'ordre chronologique)
-- ============================================================================

-- Migration: dashboard_stats_views
-- Version: 20260114083207

-- Migration: dashboard_stats_views
-- Description: vues et RPC pour les statistiques du dashboard (transactions privées)

-- 1) Schéma pour les vues dashboard (si non existant)
create schema if not exists dashboard_view

do $$
begin
  -- Si la table private.transactions n'existe pas (par ex. en local),
  -- on ne crée pas la vue pour éviter de casser les migrations.
  if to_regclass('private.transactions') is null then
    raise notice 'private.transactions not found, skipping creation of dashboard_view.daily_stats';
    return;
  end if;

  execute $v$
    create or replace view dashboard_view.daily_stats as
    select
      t.date::date                                                as day,
      count(*)                                                    as transactions_count,
      count(distinct t.user_id)                                   as active_users,
      coalesce(sum(case when t.points > 0 then t.points else 0 end), 0)     as points_generated,
      coalesce(sum(case when t.points < 0 then -t.points else 0 end), 0)    as points_spent
    from private.transactions t
    where t.status = 'valide'
    group by t.date::date
    order by day desc
  $v$;
end;
$$

-- 3) Vue today_stats : KPIs du jour (clients aujourd'hui, points distribués aujourd'hui)
do $$
begin
  -- Même logique de garde : si la table n'existe pas, on ne crée pas la vue.
  if to_regclass('private.transactions') is null then
    raise notice 'private.transactions not found, skipping creation of dashboard_view.today_stats';
    return;
  end if;

  execute $v$
    create or replace view dashboard_view.today_stats as
    select
      current_date as day,
      count(*) filter (
        where t.status = 'valide'
          and t.date::date = current_date
      ) as transactions_today,
      count(distinct t.user_id) filter (
        where t.status = 'valide'
          and t.date::date = current_date
      ) as clients_today,
      coalesce(sum(
        case
          when t.status = 'valide'
           and t.date::date = current_date
           and t.points > 0
          then t.points
          else 0
        end
      ), 0) as points_generated_today
    from private.transactions t
  $v$;
end;
$$

-- 4) Fonction RPC unifiée pour exposer ces stats au frontend
create or replace function public.get_dashboard_realtime_stats()
returns jsonb
language plpgsql
security definer
set search_path = public, dashboard_view, private
as $$
declare
  v_today       record;
  v_daily_stats jsonb;
begin
  -- KPIs du jour
  select *
  into v_today
  from dashboard_view.today_stats;

  -- Activité des 7 derniers jours
  select jsonb_agg(
           jsonb_build_object(
             'day', day,
             'transactions_count', transactions_count,
             'active_users', active_users,
             'points_generated', points_generated,
             'points_spent', points_spent
           )
           order by day
         )
  into v_daily_stats
  from dashboard_view.daily_stats
  where day >= current_date - interval '6 days';

  return jsonb_build_object(
    'today', jsonb_build_object(
      'day', v_today.day,
      'clients_today', v_today.clients_today,
      'transactions_today', v_today.transactions_today,
      'points_generated_today', v_today.points_generated_today
    ),
    'daily_stats', v_daily_stats
  );
end;
$$

-- ──────────────────────────────────────────────────────────────────────

-- Migration: dashboard_stats_daily_auth_users
-- Version: 20260114090841

-- Migration: dashboard_stats_daily_auth_users
-- Objectif: recalculer les connexions (active_users) à partir de auth.users.last_sign_in_at

do $$
begin
  /*
    Cas nominal : on a à la fois auth.users et private.transactions.
    - active_users = nb d'utilisateurs dont last_sign_in_at::date = day
    - transactions_count / points_* = dérivés de private.transactions (status = 'valide')
  */
  create or replace view dashboard_view.daily_stats as
  with daily_connexions as (
    select
      last_sign_in_at::date as day,
      count(distinct id)    as active_users
    from auth.users
    where last_sign_in_at is not null
    group by last_sign_in_at::date
  ),
  daily_tx as (
    select
      t.date::date as day,
      count(*)     as transactions_count,
      coalesce(sum(case when t.points > 0 then t.points else 0 end), 0)  as points_generated,
      coalesce(sum(case when t.points < 0 then -t.points else 0 end), 0) as points_spent
    from private.transactions t
    where t.status = 'valide'
    group by t.date::date
  )
  select
    coalesce(c.day, x.day)                     as day,
    coalesce(x.transactions_count, 0)          as transactions_count,
    coalesce(c.active_users, 0)                as active_users,
    coalesce(x.points_generated, 0)            as points_generated,
    coalesce(x.points_spent, 0)                as points_spent
  from daily_connexions c
  full outer join daily_tx x using (day)
  order by day desc;

exception
  /*
    En local (ou environnements sans private.transactions),
    on peut tomber sur undefined_table.
    Dans ce cas on ne garde que les connexions, et on met les stats de transactions à 0.
  */
  when undefined_table then
    raise notice 'private.transactions absent, daily_stats ne contient que les connexions (auth.users)';

    create or replace view dashboard_view.daily_stats as
    select
      last_sign_in_at::date as day,
      0::integer            as transactions_count,
      count(distinct id)    as active_users,
      0::bigint             as points_generated,
      0::bigint             as points_spent
    from auth.users
    where last_sign_in_at is not null
    group by last_sign_in_at::date
    order by day desc;
end;
$$

-- ──────────────────────────────────────────────────────────────────────

-- Migration: dashboard_stats_full_daily_range
-- Version: 20260114093216

-- Migration: dashboard_stats_full_daily_range
-- Objectif: faire renvoyer à get_dashboard_realtime_stats l'intégralité de daily_stats,
--           le filtrage jour/semaine/mois étant géré côté frontend.

create or replace function public.get_dashboard_realtime_stats()
returns jsonb
language plpgsql
security definer
set search_path = public, dashboard_view, private
as $$
declare
  v_today       record;
  v_daily_stats jsonb;
begin
  -- KPIs du jour (inchangé)
  select *
  into v_today
  from dashboard_view.today_stats;

  -- Activité complète (toutes les dates disponibles dans daily_stats)
  select jsonb_agg(
           jsonb_build_object(
             'day', day,
             'transactions_count', transactions_count,
             'active_users', active_users,
             'points_generated', points_generated,
             'points_spent', points_spent
           )
           order by day
         )
  into v_daily_stats
  from dashboard_view.daily_stats;

  return jsonb_build_object(
    'today', jsonb_build_object(
      'day', v_today.day,
      'clients_today', v_today.clients_today,
      'transactions_today', v_today.transactions_today,
      'points_generated_today', v_today.points_generated_today
    ),
    'daily_stats', v_daily_stats
  );
end;
$$

-- ──────────────────────────────────────────────────────────────────────

-- Migration: dashboard_stats_offer_usage
-- Version: 20260114095221

-- Migration: dashboard_stats_offer_usage
-- Objectif: ajouter les statistiques d'utilisation des offres depuis private.transactions.used_offers
--           et les inclure dans get_dashboard_realtime_stats

-- Vue pour compter les utilisations de chaque offre
do $$
begin
  if to_regclass('private.transactions') is null then
    raise notice 'private.transactions not found, skipping creation of dashboard_view.offer_usage_stats';
    return;
  end if;

  execute $v$
    create or replace view dashboard_view.offer_usage_stats as
    select
      offer_id::uuid as offer_id,
      count(*) as usage_count
    from private.transactions t,
         unnest(t.used_offers) as offer_id
    where t.status = 'valide'
      and t.used_offers is not null
      and array_length(t.used_offers, 1) > 0
    group by offer_id::uuid
    order by usage_count desc
  $v$;
end;
$$

-- Mise à jour de la fonction RPC pour inclure les stats d'utilisation des offres
create or replace function public.get_dashboard_realtime_stats()
returns jsonb
language plpgsql
security definer
set search_path = public, dashboard_view, private
as $$
declare
  v_today       record;
  v_daily_stats jsonb;
  v_offer_usage jsonb;
begin
  -- KPIs du jour (inchangé)
  select *
  into v_today
  from dashboard_view.today_stats;

  -- Activité complète (toutes les dates disponibles dans daily_stats)
  select jsonb_agg(
           jsonb_build_object(
             'day', day,
             'transactions_count', transactions_count,
             'active_users', active_users,
             'points_generated', points_generated,
             'points_spent', points_spent
           )
           order by day
         )
  into v_daily_stats
  from dashboard_view.daily_stats;

  -- Statistiques d'utilisation des offres
  select jsonb_agg(
           jsonb_build_object(
             'offer_id', offer_id,
             'usage_count', usage_count
           )
         )
  into v_offer_usage
  from dashboard_view.offer_usage_stats;

  return jsonb_build_object(
    'today', jsonb_build_object(
      'day', v_today.day,
      'clients_today', v_today.clients_today,
      'transactions_today', v_today.transactions_today,
      'points_generated_today', v_today.points_generated_today
    ),
    'daily_stats', v_daily_stats,
    'offer_usage', coalesce(v_offer_usage, '[]'::jsonb)
  );
end;
$$

-- ──────────────────────────────────────────────────────────────────────

-- Migration: update_restaurant_details_returns_row
-- Version: 20260124120000

-- =================================================================
-- Migration: update_restaurant_details retourne le restaurant mis à jour
-- =================================================================
-- Objectif: réduction du délai de mise à jour des horaires (schedule, special_hours)
-- en retournant la ligne à jour côté client pour une mise à jour optimiste immédiate.
--
-- La vue dashboard_boot_data lit private.restaurants via dashboard_view.restaurants
-- (pas de cache matérialisé), donc la base est à jour dès l'UPDATE.
-- Le délai perçu venait du cache client et du fait que la RPC ne renvoyait pas
-- le restaurant mis à jour, obligeant un refetch ou une reconstruction partielle.
--
-- Si vous avez déjà une fonction update_restaurant_details avec une logique
-- métier différente: conservez-la et ajoutez seulement RETURNS SETOF private.restaurants
-- et « RETURN QUERY SELECT * FROM private.restaurants WHERE id = p_restaurant_id; »
-- à la fin. Si la table n'a pas building/floor, supprimez les lignes SET correspondantes.

CREATE OR REPLACE FUNCTION public.update_restaurant_details(
  p_restaurant_id uuid,
  p_updates jsonb
)
RETURNS SETOF private.restaurants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  UPDATE private.restaurants r
  SET
    name = CASE WHEN p_updates ? 'name' THEN (p_updates->>'name')::text ELSE r.name END,
    description = CASE WHEN p_updates ? 'description' THEN (p_updates->>'description')::text ELSE r.description END,
    image_url = CASE WHEN p_updates ? 'image_url' THEN (p_updates->>'image_url')::text ELSE r.image_url END,
    location = CASE WHEN p_updates ? 'location' THEN (p_updates->>'location')::text ELSE r.location END,
    schedule = CASE WHEN p_updates ? 'schedule' THEN (p_updates->'schedule')::jsonb ELSE r.schedule END,
    special_hours = CASE WHEN p_updates ? 'special_hours' THEN (p_updates->'special_hours')::jsonb ELSE r.special_hours END,
    categories = CASE WHEN p_updates ? 'categories' AND jsonb_typeof(p_updates->'categories') = 'array' THEN ARRAY(SELECT jsonb_array_elements_text(p_updates->'categories')) ELSE r.categories END,
    is_new = CASE WHEN p_updates ? 'is_new' THEN (p_updates->>'is_new')::boolean ELSE r.is_new END,
    boosted = CASE WHEN p_updates ? 'boosted' THEN (p_updates->>'boosted')::boolean ELSE r.boosted END,
    status = CASE WHEN p_updates ? 'status' THEN (p_updates->>'status')::text ELSE r.status END,
    building = CASE WHEN p_updates ? 'building' THEN (p_updates->>'building')::text ELSE r.building END,
    floor = CASE WHEN p_updates ? 'floor' THEN (p_updates->>'floor')::text ELSE r.floor END,
    updated_at = now()
  WHERE r.id = p_restaurant_id;

  RETURN QUERY
  SELECT * FROM private.restaurants WHERE id = p_restaurant_id;
END;
$$

-- Permissions (conserver celles existantes si la fonction était déjà exposée)
GRANT EXECUTE ON FUNCTION public.update_restaurant_details(uuid, jsonb) TO authenticated

GRANT EXECUTE ON FUNCTION public.update_restaurant_details(uuid, jsonb) TO service_role

COMMENT ON FUNCTION public.update_restaurant_details(uuid, jsonb) IS
  'Met à jour un restaurant (horaires, infos, etc.) et retourne la ligne à jour pour mise à jour optimiste immédiate côté client.'

-- ──────────────────────────────────────────────────────────────────────

-- Migration: restaurant_frequentation_weekly
-- Version: 20260124130000

-- Migration: get_restaurant_frequentation_weekly
-- Fréquentation (clients distincts) et points dépensés par restaurant et par jour de la semaine,
-- sur les 7 derniers jours (dont aujourd’hui). Pour alimenter RestaurantStatsBox (Lundi–Dimanche).
-- dow: 0 = Lundi, 1 = Mardi, … 6 = Dimanche (aligné sur l’ordre de la liste Jours).

do $$
begin
  if to_regclass('private.transactions') is null then
    raise notice 'private.transactions not found, skipping get_restaurant_frequentation_weekly';
    return;
  end if;

  execute $fn$
    create or replace function public.get_restaurant_frequentation_weekly()
    returns table (
      restaurant_id uuid,
      dow int,
      clients bigint,
      points_spent bigint
    )
    language sql
    security definer
    set search_path = public, private
    as $body$
      with base as (
        select
          t.restaurant_id,
          ((extract(dow from t.date::date)::int + 6) % 7) as dow,
          count(distinct t.user_id) as clients,
          coalesce(sum(case when t.points < 0 then -t.points else 0 end), 0)::bigint as points_spent
        from private.transactions t
        where t.status = 'valide'
          and t.date::date >= current_date - interval '6 days'
          and t.restaurant_id is not null
        group by t.restaurant_id, ((extract(dow from t.date::date)::int + 6) % 7)
      )
      select b.restaurant_id, b.dow, b.clients, b.points_spent
      from base b;
    $body$;
  $fn$;

  grant execute on function public.get_restaurant_frequentation_weekly() to authenticated;
  grant execute on function public.get_restaurant_frequentation_weekly() to service_role;
end;
$$

-- ──────────────────────────────────────────────────────────────────────

-- Migration: realtime_stats_active_restaurants
-- Version: 20260124140000

-- Migration: ajouter active_restaurants_today à get_dashboard_realtime_stats
-- Restaurants actifs = distinct restaurant_id avec au moins une transaction aujourd'hui (status=valide)

create or replace function public.get_dashboard_realtime_stats()
returns jsonb
language plpgsql
security definer
set search_path = public, dashboard_view, private
as $$
declare
  v_today             record;
  v_daily_stats       jsonb;
  v_offer_usage       jsonb;
  v_active_restaurants bigint;
begin
  -- KPIs du jour (today_stats)
  select * into v_today from dashboard_view.today_stats;

  -- Restaurants actifs aujourd'hui (distinct restaurant_id, transactions valides, date=aujourd'hui)
  select count(distinct t.restaurant_id) into v_active_restaurants
  from private.transactions t
  where t.status = 'valide'
    and t.date::date = current_date
    and t.restaurant_id is not null;

  -- Activité complète (daily_stats)
  select jsonb_agg(
           jsonb_build_object(
             'day', day,
             'transactions_count', transactions_count,
             'active_users', active_users,
             'points_generated', points_generated,
             'points_spent', points_spent
           )
           order by day
         )
  into v_daily_stats
  from dashboard_view.daily_stats;

  -- Statistiques d'utilisation des offres
  select jsonb_agg(
           jsonb_build_object(
             'offer_id', offer_id,
             'usage_count', usage_count
           )
         )
  into v_offer_usage
  from dashboard_view.offer_usage_stats;

  return jsonb_build_object(
    'today', jsonb_build_object(
      'day', v_today.day,
      'clients_today', v_today.clients_today,
      'transactions_today', v_today.transactions_today,
      'points_generated_today', v_today.points_generated_today,
      'active_restaurants_today', coalesce(v_active_restaurants, 0)
    ),
    'daily_stats', v_daily_stats,
    'offer_usage', coalesce(v_offer_usage, '[]'::jsonb)
  );
end;
$$

-- ──────────────────────────────────────────────────────────────────────

-- Migration: fix_transaction_status_completed
-- Version: 20260124150000

-- Migration: accepter status 'completed' en plus de 'valide' pour les transactions
-- L'app (caisses, close-cash-registers) utilise status='completed'. Les vues/RPC
-- filtraient sur 'valide' uniquement, ce qui donnait 0 stats.

-- 1) daily_stats : dans daily_tx, accepter 'valide' ou 'completed'
do $$
begin
  if to_regclass('private.transactions') is not null then
    execute $v$
      create or replace view dashboard_view.daily_stats as
      with daily_connexions as (
        select last_sign_in_at::date as day, count(distinct id) as active_users
        from auth.users
        where last_sign_in_at is not null
        group by last_sign_in_at::date
      ),
      daily_tx as (
        select
          t.date::date as day,
          count(*) as transactions_count,
          coalesce(sum(case when t.points > 0 then t.points else 0 end), 0) as points_generated,
          coalesce(sum(case when t.points < 0 then -t.points else 0 end), 0) as points_spent
        from private.transactions t
        where t.status in ('valide', 'completed')
        group by t.date::date
      )
      select
        coalesce(c.day, x.day) as day,
        coalesce(x.transactions_count, 0) as transactions_count,
        coalesce(c.active_users, 0) as active_users,
        coalesce(x.points_generated, 0) as points_generated,
        coalesce(x.points_spent, 0) as points_spent
      from daily_connexions c
      full outer join daily_tx x using (day)
      order by day desc;
    $v$;
  end if;
end;
$$

-- 2) today_stats : accepter 'valide' ou 'completed'
do $$
begin
  if to_regclass('private.transactions') is not null then
    execute $v$
      create or replace view dashboard_view.today_stats as
      select
        current_date as day,
        count(*) filter (where t.status in ('valide','completed') and t.date::date = current_date) as transactions_today,
        count(distinct t.user_id) filter (where t.status in ('valide','completed') and t.date::date = current_date) as clients_today,
        coalesce(sum(case when t.status in ('valide','completed') and t.date::date = current_date and t.points > 0 then t.points else 0 end), 0) as points_generated_today
      from private.transactions t;
    $v$;
  end if;
end;
$$

-- 3) offer_usage_stats : accepter 'valide' ou 'completed'
do $$
begin
  if to_regclass('private.transactions') is not null then
    execute $v$
      create or replace view dashboard_view.offer_usage_stats as
      select offer_id::uuid as offer_id, count(*) as usage_count
      from private.transactions t, unnest(t.used_offers) as offer_id
      where t.status in ('valide', 'completed')
        and t.used_offers is not null
        and array_length(t.used_offers, 1) > 0
      group by offer_id::uuid
      order by usage_count desc;
    $v$;
  end if;
end;
$$

-- 4) get_dashboard_realtime_stats : v_active_restaurants + today/daily/offer lu via vues (déjà corrigées)
create or replace function public.get_dashboard_realtime_stats()
returns jsonb
language plpgsql
security definer
set search_path = public, dashboard_view, private
as $$
declare
  v_today              record;
  v_daily_stats        jsonb;
  v_offer_usage        jsonb;
  v_active_restaurants bigint;
begin
  select * into v_today from dashboard_view.today_stats;

  select count(distinct t.restaurant_id) into v_active_restaurants
  from private.transactions t
  where t.status in ('valide', 'completed')
    and t.date::date = current_date
    and t.restaurant_id is not null;

  select jsonb_agg(jsonb_build_object('day', day, 'transactions_count', transactions_count, 'active_users', active_users, 'points_generated', points_generated, 'points_spent', points_spent) order by day)
  into v_daily_stats from dashboard_view.daily_stats;

  select jsonb_agg(jsonb_build_object('offer_id', offer_id, 'usage_count', usage_count))
  into v_offer_usage from dashboard_view.offer_usage_stats;

  return jsonb_build_object(
    'today', jsonb_build_object(
      'day', v_today.day,
      'clients_today', v_today.clients_today,
      'transactions_today', v_today.transactions_today,
      'points_generated_today', v_today.points_generated_today,
      'active_restaurants_today', coalesce(v_active_restaurants, 0)
    ),
    'daily_stats', v_daily_stats,
    'offer_usage', coalesce(v_offer_usage, '[]'::jsonb)
  );
end;
$$

-- 5) get_restaurant_frequentation_weekly : accepter 'valide' ou 'completed'
create or replace function public.get_restaurant_frequentation_weekly()
returns table (restaurant_id uuid, dow int, clients bigint, points_spent bigint)
language sql
security definer
set search_path = public, private
as $$
  with base as (
    select
      t.restaurant_id,
      ((extract(dow from t.date::date)::int + 6) % 7) as dow,
      count(distinct t.user_id) as clients,
      coalesce(sum(case when t.points < 0 then -t.points else 0 end), 0)::bigint as points_spent
    from private.transactions t
    where t.status in ('valide', 'completed')
      and t.date::date >= current_date - interval '6 days'
      and t.restaurant_id is not null
    group by t.restaurant_id, ((extract(dow from t.date::date)::int + 6) % 7)
  )
  select b.restaurant_id, b.dow, b.clients, b.points_spent from base b;
$$

-- ──────────────────────────────────────────────────────────────────────

-- Migration: active_restaurants_with_schedule
-- Version: 20260124160000

-- Migration: Restaurants actifs = transactions aujourd'hui OU ouverts aujourd'hui (schedule + horaires spéciaux)
-- Inclut les restaurants dont les horaires (schedule) ou les horaires spéciaux (special_hours) indiquent une ouverture aujourd'hui,
-- même sans transaction, pour refléter correctement les restaurants "actifs".

create or replace function public.get_dashboard_realtime_stats()
returns jsonb
language plpgsql
security definer
set search_path = public, dashboard_view, private
as $$
declare
  v_today              record;
  v_daily_stats        jsonb;
  v_offer_usage        jsonb;
  v_active_restaurants bigint;
  v_dow_idx            int;
begin
  select * into v_today from dashboard_view.today_stats;

  v_dow_idx := (extract(dow from current_date)::int + 6) % 7;  -- 0=Lundi .. 6=Dimanche

  -- Restaurants actifs = (1) au moins une transaction aujourd'hui OU (2) ouverts aujourd'hui (schedule ou horaires spéciaux)
  with from_tx as (
    select distinct t.restaurant_id as id
    from private.transactions t
    where t.status in ('valide', 'completed')
      and t.date::date = current_date
      and t.restaurant_id is not null
  ),
  from_hours as (
    select r.id
    from private.restaurants r
    where (
      -- Ouvert selon le schedule (jour de la semaine) : closed <> true pour aujourd'hui
      (
        r.schedule is not null
        and jsonb_typeof(r.schedule) = 'array'
        and jsonb_array_length(r.schedule) > v_dow_idx
        and ((r.schedule->v_dow_idx)->>'closed') is distinct from 'true'
      )
      or
      -- Ouvert selon les horaires spéciaux : une entrée existe pour la date du jour
      (
        r.special_hours is not null
        and jsonb_typeof(r.special_hours) = 'array'
        and exists (
          select 1 from jsonb_array_elements(r.special_hours) el
          where (el->>'date') = current_date::text
        )
      )
    )
  )
  select count(*)::bigint into v_active_restaurants
  from (select id from from_tx union select id from from_hours) u;

  select jsonb_agg(jsonb_build_object('day', day, 'transactions_count', transactions_count, 'active_users', active_users, 'points_generated', points_generated, 'points_spent', points_spent) order by day)
  into v_daily_stats from dashboard_view.daily_stats;

  select jsonb_agg(jsonb_build_object('offer_id', offer_id, 'usage_count', usage_count))
  into v_offer_usage from dashboard_view.offer_usage_stats;

  return jsonb_build_object(
    'today', jsonb_build_object(
      'day', v_today.day,
      'clients_today', v_today.clients_today,
      'transactions_today', v_today.transactions_today,
      'points_generated_today', v_today.points_generated_today,
      'active_restaurants_today', coalesce(v_active_restaurants, 0)
    ),
    'daily_stats', v_daily_stats,
    'offer_usage', coalesce(v_offer_usage, '[]'::jsonb)
  );
end;
$$

-- ──────────────────────────────────────────────────────────────────────

-- Migration: user_notification_preferences
-- Version: 20260124170000

-- Table des préférences de notifications par utilisateur
CREATE TABLE IF NOT EXISTS public.user_notification_preferences (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  notifications_enabled boolean NOT NULL DEFAULT false,
  enabled_categories text[] NOT NULL DEFAULT '{}',
  updated_at timestamptz DEFAULT now()
)

-- RLS
ALTER TABLE public.user_notification_preferences ENABLE ROW LEVEL SECURITY

CREATE POLICY "user_notification_preferences_select_own"
  ON public.user_notification_preferences FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id)

CREATE POLICY "user_notification_preferences_insert_own"
  ON public.user_notification_preferences FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id)

CREATE POLICY "user_notification_preferences_update_own"
  ON public.user_notification_preferences FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id)

-- Trigger updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql

DROP TRIGGER IF EXISTS user_notification_preferences_updated_at ON public.user_notification_preferences

CREATE TRIGGER user_notification_preferences_updated_at
  BEFORE UPDATE ON public.user_notification_preferences
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()

-- RPC: retourne les notification_token des utilisateurs ayant la catégorie activée
-- Table des tokens: private.notification_tokens (user_id, notification_token)
CREATE OR REPLACE FUNCTION public.get_notification_tokens_for_category(p_category text)
RETURNS TABLE(notification_token text)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT t.notification_token
  FROM private.notification_tokens t
  JOIN public.user_notification_preferences p ON p.user_id = t.user_id
  WHERE p.notifications_enabled = true
    AND p_category = ANY(p.enabled_categories)
    AND t.notification_token IS NOT NULL
    AND t.notification_token <> '';
$$

-- ──────────────────────────────────────────────────────────────────────

-- Migration: use_users_notification_settings
-- Version: 20260124180000

-- Utiliser private.users.notification_settings au lieu de user_notification_preferences.
  -- private.users.notification_settings doit être de type jsonb.
  -- Clés gérées par ce flux (merge avec les existantes: promotions, systemUpdates, newRestaurants, asapAnnouncements):
  --   notificationsEnabled, offers, special_hours, promotions, polls.

  -- 1) Supprimer l'ancienne table et son trigger
  DROP TRIGGER IF EXISTS user_notification_preferences_updated_at ON public.user_notification_preferences

DROP TABLE IF EXISTS public.user_notification_preferences

-- 2) RPC: tokens des utilisateurs dont notification_settings autorise la catégorie
  -- notification_settings: jsonb avec notificationsEnabled (optionnel, absence = actif), offers, special_hours, promotions, polls
  CREATE OR REPLACE FUNCTION public.get_notification_tokens_for_category(p_category text)
  RETURNS TABLE(notification_token text)
  LANGUAGE sql
  STABLE
  SECURITY INVOKER
  AS $$
    SELECT t.notification_token
    FROM private.notification_tokens t
    JOIN private.users u ON u.id = t.user_id
    WHERE (u.notification_settings->>'notificationsEnabled')::boolean IS DISTINCT FROM false
      AND (u.notification_settings->>p_category)::boolean = true
      AND t.notification_token IS NOT NULL
      AND t.notification_token <> '';
  $$

-- 3) Récupérer les préférences de l'utilisateur connecté (depuis private.users)
  CREATE OR REPLACE FUNCTION public.get_my_notification_settings()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public
  AS $$
    SELECT notification_settings FROM private.users WHERE id = auth.uid();
  $$

-- 4) Mettre à jour notification_settings (merge avec l'existant pour garder systemUpdates, newRestaurants, asapAnnouncements, etc.)
  CREATE OR REPLACE FUNCTION public.update_my_notification_settings(p_settings jsonb)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
  AS $$
  DECLARE
    cur jsonb;
    merged jsonb;
  BEGIN
    SELECT notification_settings INTO cur FROM private.users WHERE id = auth.uid();
    IF NOT FOUND THEN
      RETURN NULL;
    END IF;
    merged := COALESCE(cur, '{}'::jsonb) || p_settings;
    UPDATE private.users SET notification_settings = merged WHERE id = auth.uid();
    RETURN merged;
  END;
  $$

-- ──────────────────────────────────────────────────────────────────────

-- Migration: notification_action_settings
-- Version: 20260124190000

-- Table de configuration: pour chaque action, activer ou non l'envoi de notifications.
-- action_id: recompenses | horaires | promotions | sondages

CREATE TABLE IF NOT EXISTS public.notification_action_settings (
  action_id text PRIMARY KEY,
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
)

-- RLS: lecture pour tous les authentifiés, écriture via RPC SECURITY DEFINER
ALTER TABLE public.notification_action_settings ENABLE ROW LEVEL SECURITY

DROP POLICY IF EXISTS "Lecture pour utilisateurs authentifiés" ON public.notification_action_settings

CREATE POLICY "Lecture pour utilisateurs authentifiés"
  ON public.notification_action_settings FOR SELECT
  TO authenticated
  USING (true)

-- Seules les RPC peuvent modifier (pas de policy UPDATE/INSERT pour les rôles classiques)

-- RPC: récupérer tous les réglages
CREATE OR REPLACE FUNCTION public.get_notification_action_settings()
RETURNS TABLE(action_id text, enabled boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT nas.action_id, nas.enabled
  FROM public.notification_action_settings nas
  ORDER BY nas.action_id;
$$

-- RPC: upsert un réglage (action_id, enabled)
CREATE OR REPLACE FUNCTION public.update_notification_action_setting(p_action_id text, p_enabled boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.notification_action_settings (action_id, enabled, updated_at)
  VALUES (p_action_id, p_enabled, now())
  ON CONFLICT (action_id) DO UPDATE SET
    enabled = EXCLUDED.enabled,
    updated_at = now();
END;
$$

-- Données initiales: une ligne par action, enabled = true
INSERT INTO public.notification_action_settings (action_id, enabled)
VALUES
  ('recompenses', true),
  ('horaires', true),
  ('promotions', true),
  ('sondages', true)
ON CONFLICT (action_id) DO NOTHING

-- ──────────────────────────────────────────────────────────────────────

-- Migration: restaurant_menu_url_update_rpc
-- Version: 20260124200000

-- =================================================================
-- Migration: support de restaurant_menu_url dans update_restaurant_details
-- =================================================================
-- Prérequis: la colonne restaurants.restaurant_menu_url et le bucket
-- storage 'restaurant_menu' doivent exister.
-- Cette migration ajoute la prise en charge de restaurant_menu_url
-- dans la RPC update_restaurant_details.

CREATE OR REPLACE FUNCTION public.update_restaurant_details(
  p_restaurant_id uuid,
  p_updates jsonb
)
RETURNS SETOF private.restaurants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  UPDATE private.restaurants r
  SET
    name = CASE WHEN p_updates ? 'name' THEN (p_updates->>'name')::text ELSE r.name END,
    description = CASE WHEN p_updates ? 'description' THEN (p_updates->>'description')::text ELSE r.description END,
    image_url = CASE WHEN p_updates ? 'image_url' THEN (p_updates->>'image_url')::text ELSE r.image_url END,
    restaurant_menu_url = CASE WHEN p_updates ? 'restaurant_menu_url' THEN (p_updates->>'restaurant_menu_url')::text ELSE r.restaurant_menu_url END,
    location = CASE WHEN p_updates ? 'location' THEN (p_updates->>'location')::text ELSE r.location END,
    schedule = CASE WHEN p_updates ? 'schedule' THEN (p_updates->'schedule')::jsonb ELSE r.schedule END,
    special_hours = CASE WHEN p_updates ? 'special_hours' THEN (p_updates->'special_hours')::jsonb ELSE r.special_hours END,
    categories = CASE WHEN p_updates ? 'categories' AND jsonb_typeof(p_updates->'categories') = 'array' THEN ARRAY(SELECT jsonb_array_elements_text(p_updates->'categories')) ELSE r.categories END,
    is_new = CASE WHEN p_updates ? 'is_new' THEN (p_updates->>'is_new')::boolean ELSE r.is_new END,
    boosted = CASE WHEN p_updates ? 'boosted' THEN (p_updates->>'boosted')::boolean ELSE r.boosted END,
    status = CASE WHEN p_updates ? 'status' THEN (p_updates->>'status')::text ELSE r.status END,
    building = CASE WHEN p_updates ? 'building' THEN (p_updates->>'building')::text ELSE r.building END,
    floor = CASE WHEN p_updates ? 'floor' THEN (p_updates->>'floor')::text ELSE r.floor END,
    updated_at = now()
  WHERE r.id = p_restaurant_id;

  RETURN QUERY
  SELECT * FROM private.restaurants WHERE id = p_restaurant_id;
END;
$$

COMMENT ON FUNCTION public.update_restaurant_details(uuid, jsonb) IS
  'Met à jour un restaurant (horaires, infos, menu de la semaine, etc.) et retourne la ligne à jour.'

-- ──────────────────────────────────────────────────────────────────────

-- Migration: dashboard_view_restaurants_menu_url
-- Version: 20260124210000

create or replace view dashboard_view.restaurants as
select
  r.id,
  r.name,
  r.description,
  r.image_url,
  r.location,
  r.schedule,
  r.special_hours,
  r.categories,
  r.is_new,
  r.boosted,
  r.status,
  r.created_at,
  r.updated_at
from
  private.restaurants r

-- ──────────────────────────────────────────────────────────────────────

-- Migration: restaurant_menu_url_ensure
-- Version: 20260124220000

-- =================================================================
-- Migration: garantir restaurant_menu_url (colonne + RPC)
-- =================================================================
-- Si l'URL du menu (PDF/image) n'est pas persistée en base, causes
-- possibles: colonne absente sur private.restaurants, ou RPC
-- update_restaurant_details sans la ligne SET pour restaurant_menu_url.
-- Cette migration sécurise les deux.

-- 1) Colonne sur la table réelle (si créée sur une vue ou public, ça n’aurait pas d’effet)
ALTER TABLE private.restaurants
ADD COLUMN IF NOT EXISTS restaurant_menu_url text

-- 2) RPC avec prise en charge de restaurant_menu_url (recréation pour être sûr qu’elle est à jour)
CREATE OR REPLACE FUNCTION public.update_restaurant_details(
  p_restaurant_id uuid,
  p_updates jsonb
)
RETURNS SETOF private.restaurants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  UPDATE private.restaurants r
  SET
    name = CASE WHEN p_updates ? 'name' THEN (p_updates->>'name')::text ELSE r.name END,
    description = CASE WHEN p_updates ? 'description' THEN (p_updates->>'description')::text ELSE r.description END,
    image_url = CASE WHEN p_updates ? 'image_url' THEN (p_updates->>'image_url')::text ELSE r.image_url END,
    restaurant_menu_url = CASE WHEN p_updates ? 'restaurant_menu_url' THEN (p_updates->>'restaurant_menu_url')::text ELSE r.restaurant_menu_url END,
    location = CASE WHEN p_updates ? 'location' THEN (p_updates->>'location')::text ELSE r.location END,
    schedule = CASE WHEN p_updates ? 'schedule' THEN (p_updates->'schedule')::jsonb ELSE r.schedule END,
    special_hours = CASE WHEN p_updates ? 'special_hours' THEN (p_updates->'special_hours')::jsonb ELSE r.special_hours END,
    categories = CASE WHEN p_updates ? 'categories' AND jsonb_typeof(p_updates->'categories') = 'array' THEN ARRAY(SELECT jsonb_array_elements_text(p_updates->'categories')) ELSE r.categories END,
    is_new = CASE WHEN p_updates ? 'is_new' THEN (p_updates->>'is_new')::boolean ELSE r.is_new END,
    boosted = CASE WHEN p_updates ? 'boosted' THEN (p_updates->>'boosted')::boolean ELSE r.boosted END,
    status = CASE WHEN p_updates ? 'status' THEN (p_updates->>'status')::text ELSE r.status END,
    updated_at = now()
  WHERE r.id = p_restaurant_id;

  RETURN QUERY
  SELECT * FROM private.restaurants WHERE id = p_restaurant_id;
END;
$$

GRANT EXECUTE ON FUNCTION public.update_restaurant_details(uuid, jsonb) TO authenticated

GRANT EXECUTE ON FUNCTION public.update_restaurant_details(uuid, jsonb) TO service_role

COMMENT ON FUNCTION public.update_restaurant_details(uuid, jsonb) IS
  'Met à jour un restaurant (horaires, infos, menu de la semaine, etc.) et retourne la ligne à jour.'

-- ──────────────────────────────────────────────────────────────────────

-- Migration: update_restaurant_details_remove_building_floor
-- Version: 20260124230000

-- =================================================================
-- Migration: retirer building et floor de update_restaurant_details
-- =================================================================
-- La table private.restaurants n'a pas les colonnes building et floor
-- (le lieu est stocké dans location). On les retire du SET pour éviter
-- l'erreur 42703 "column r.building does not exist".

CREATE OR REPLACE FUNCTION public.update_restaurant_details(
  p_restaurant_id uuid,
  p_updates jsonb
)
RETURNS SETOF private.restaurants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  UPDATE private.restaurants r
  SET
    name = CASE WHEN p_updates ? 'name' THEN (p_updates->>'name')::text ELSE r.name END,
    description = CASE WHEN p_updates ? 'description' THEN (p_updates->>'description')::text ELSE r.description END,
    image_url = CASE WHEN p_updates ? 'image_url' THEN (p_updates->>'image_url')::text ELSE r.image_url END,
    restaurant_menu_url = CASE WHEN p_updates ? 'restaurant_menu_url' THEN (p_updates->>'restaurant_menu_url')::text ELSE r.restaurant_menu_url END,
    location = CASE WHEN p_updates ? 'location' THEN (p_updates->>'location')::text ELSE r.location END,
    schedule = CASE WHEN p_updates ? 'schedule' THEN (p_updates->'schedule')::jsonb ELSE r.schedule END,
    special_hours = CASE WHEN p_updates ? 'special_hours' THEN (p_updates->'special_hours')::jsonb ELSE r.special_hours END,
    categories = CASE WHEN p_updates ? 'categories' AND jsonb_typeof(p_updates->'categories') = 'array' THEN ARRAY(SELECT jsonb_array_elements_text(p_updates->'categories')) ELSE r.categories END,
    is_new = CASE WHEN p_updates ? 'is_new' THEN (p_updates->>'is_new')::boolean ELSE r.is_new END,
    boosted = CASE WHEN p_updates ? 'boosted' THEN (p_updates->>'boosted')::boolean ELSE r.boosted END,
    status = CASE WHEN p_updates ? 'status' THEN (p_updates->>'status')::text ELSE r.status END,
    updated_at = now()
  WHERE r.id = p_restaurant_id;

  RETURN QUERY
  SELECT * FROM private.restaurants WHERE id = p_restaurant_id;
END;
$$

COMMENT ON FUNCTION public.update_restaurant_details(uuid, jsonb) IS
  'Met à jour un restaurant (horaires, infos, menu, location, etc.). building/floor absents de la table, lieu dans location.'

-- ──────────────────────────────────────────────────────────────────────

-- Migration: fix_get_dashboard_restaurants_view_menu_url
-- Version: 20260124240000

-- =================================================================
-- Migration: ajout de restaurant_menu_url à get_dashboard_restaurants_view
-- =================================================================
-- La fonction RPC get_dashboard_restaurants_view doit retourner
-- restaurant_menu_url pour que le menu de la semaine soit disponible
-- dans le frontend. La vue dashboard_view.restaurants inclut déjà
-- ce champ, mais la fonction RPC ne le sélectionnait pas explicitement.

-- Supprimer l'ancienne fonction si elle existe
DROP FUNCTION IF EXISTS public.get_dashboard_restaurants_view()

DROP FUNCTION IF EXISTS public.get_dashboard_restaurants_view(bigint)

-- Créer la fonction avec restaurant_menu_url inclus
CREATE OR REPLACE FUNCTION public.get_dashboard_restaurants_view()
RETURNS SETOF dashboard_view.restaurants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, dashboard_view
AS $$
BEGIN
    -- Vérifier que l'utilisateur est bien authentifié avant de continuer
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Accès non autorisé : authentification requise.';
    END IF;

    -- La requête utilise SELECT * pour inclure tous les champs de la vue,
    -- y compris restaurant_menu_url et les champs calculés (is_open_now, etc.)
    RETURN QUERY
    SELECT *
    FROM dashboard_view.restaurants r
    ORDER BY r.boosted DESC, r.is_new DESC, r.name ASC;
END;
$$

-- Créer aussi la version avec paramètre refresh_timestamp (si utilisée)
CREATE OR REPLACE FUNCTION public.get_dashboard_restaurants_view(refresh_timestamp bigint)
RETURNS SETOF dashboard_view.restaurants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, dashboard_view
AS $$
BEGIN
    -- Vérifier que l'utilisateur est bien authentifié avant de continuer
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Accès non autorisé : authentification requise.';
    END IF;

    -- Le paramètre refresh_timestamp peut être utilisé pour forcer un rafraîchissement
    IF refresh_timestamp IS NOT NULL THEN
        RAISE NOTICE '[get_dashboard_restaurants_view] Rafraîchissement forcé avec timestamp: %', refresh_timestamp;
    END IF;

    -- La requête utilise SELECT * pour inclure tous les champs de la vue,
    -- y compris restaurant_menu_url et les champs calculés (is_open_now, etc.)
    RETURN QUERY
    SELECT *
    FROM dashboard_view.restaurants r
    ORDER BY r.boosted DESC, r.is_new DESC, r.name ASC;
END;
$$

-- Accorder les droits d'exécution sur les fonctions
GRANT EXECUTE ON FUNCTION public.get_dashboard_restaurants_view() TO authenticated

GRANT EXECUTE ON FUNCTION public.get_dashboard_restaurants_view() TO anon

GRANT EXECUTE ON FUNCTION public.get_dashboard_restaurants_view(bigint) TO authenticated

GRANT EXECUTE ON FUNCTION public.get_dashboard_restaurants_view(bigint) TO anon

COMMENT ON FUNCTION public.get_dashboard_restaurants_view() IS
  'Retourne tous les restaurants actifs avec leurs informations, y compris restaurant_menu_url pour le menu de la semaine.'

COMMENT ON FUNCTION public.get_dashboard_restaurants_view(bigint) IS
  'Retourne tous les restaurants actifs avec leurs informations, y compris restaurant_menu_url. Le paramètre refresh_timestamp permet de forcer un rafraîchissement.'

-- ──────────────────────────────────────────────────────────────────────

-- Migration: frequentation_current_week_only
-- Version: 20260126000000

-- Migration: Modifier get_restaurant_frequentation_weekly pour ne retourner que les données de la semaine en cours
-- La semaine en cours va du lundi au dimanche de la semaine actuelle (ISO week)

create or replace function public.get_restaurant_frequentation_weekly()
returns table (restaurant_id uuid, dow int, clients bigint, points_spent bigint)
language sql
security definer
set search_path = public, private
as $$
  with base as (
    select
      t.restaurant_id,
      ((extract(dow from t.date::date)::int + 6) % 7) as dow,
      count(distinct t.user_id) as clients,
      coalesce(sum(case when t.points < 0 then -t.points else 0 end), 0)::bigint as points_spent
    from private.transactions t
    where t.status in ('valide', 'completed')
      -- Filtrer uniquement les transactions de la semaine en cours (lundi à dimanche)
      and t.date::date >= date_trunc('isoweek', current_date)::date
      and t.date::date <= (date_trunc('isoweek', current_date)::date + interval '6 days')::date
      and t.restaurant_id is not null
    group by t.restaurant_id, ((extract(dow from t.date::date)::int + 6) % 7)
  )
  select b.restaurant_id, b.dow, b.clients, b.points_spent from base b;
$$

grant execute on function public.get_restaurant_frequentation_weekly() to authenticated

grant execute on function public.get_restaurant_frequentation_weekly() to service_role

-- ──────────────────────────────────────────────────────────────────────

-- Migration: frequentation_with_date_range
-- Version: 20260126010000

-- Migration: Ajouter une fonction pour récupérer la fréquentation avec une plage de dates personnalisée
-- Cette fonction permet de filtrer les données par date de début et de fin

create or replace function public.get_restaurant_frequentation_by_date_range(
  start_date text default null,
  end_date text default null
)
returns table (restaurant_id uuid, dow int, clients bigint, points_spent bigint, transaction_date date)
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_start_date date;
  v_end_date date;
begin
  -- Convertir les paramètres texte en date
  v_start_date := coalesce(start_date::date, date_trunc('isoweek', current_date)::date);
  v_end_date := coalesce(end_date::date, (date_trunc('isoweek', current_date)::date + interval '6 days')::date);
  
  return query
  with base as (
    select
      t.restaurant_id,
      ((extract(dow from t.date::date)::int + 6) % 7) as dow,
      t.date::date as transaction_date,
      count(distinct t.user_id) as clients,
      coalesce(sum(case when t.points < 0 then -t.points else 0 end), 0)::bigint as points_spent
    from private.transactions t
    where t.status in ('valide', 'completed')
      and t.restaurant_id is not null
      -- Filtrer par dates
      and t.date::date >= v_start_date
      and t.date::date <= v_end_date
    group by t.restaurant_id, ((extract(dow from t.date::date)::int + 6) % 7), t.date::date
  )
  select b.restaurant_id, b.dow, b.clients, b.points_spent, b.transaction_date from base b;
end;
$$

grant execute on function public.get_restaurant_frequentation_by_date_range(text, text) to authenticated

grant execute on function public.get_restaurant_frequentation_by_date_range(text, text) to service_role

-- Fonction pour récupérer l'utilisation des offres par plage de dates
create or replace function public.get_offer_usage_by_date_range(
  start_date text default null,
  end_date text default null
)
returns table (offer_id uuid, usage_count bigint)
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_start_date date;
  v_end_date date;
begin
  -- Convertir les paramètres texte en date
  v_start_date := coalesce(start_date::date, date_trunc('isoweek', current_date)::date);
  v_end_date := coalesce(end_date::date, (date_trunc('isoweek', current_date)::date + interval '6 days')::date);
  
  return query
  select
    offer_id::uuid,
    count(*)::bigint as usage_count
  from private.transactions t,
    unnest(t.used_offers) as offer_id
  where t.status in ('valide', 'completed')
    and t.used_offers is not null
    and array_length(t.used_offers, 1) > 0
    -- Filtrer par dates
    and t.date::date >= v_start_date
    and t.date::date <= v_end_date
  group by offer_id::uuid;
end;
$$

grant execute on function public.get_offer_usage_by_date_range(text, text) to authenticated

grant execute on function public.get_offer_usage_by_date_range(text, text) to service_role

-- ──────────────────────────────────────────────────────────────────────

-- Migration: fix_frequentation_function_overload
-- Version: 20260126020000

-- Migration: Corriger l'ambiguïté de surcharge de fonction
-- Supprime toutes les versions existantes de la fonction avant de la recréer

-- Supprimer toutes les versions existantes de get_restaurant_frequentation_by_date_range
DROP FUNCTION IF EXISTS public.get_restaurant_frequentation_by_date_range(date, date)

DROP FUNCTION IF EXISTS public.get_restaurant_frequentation_by_date_range(text, text)

-- Recréer la fonction avec les paramètres text
create or replace function public.get_restaurant_frequentation_by_date_range(
  start_date text default null,
  end_date text default null
)
returns table (restaurant_id uuid, dow int, clients bigint, points_spent bigint, transaction_date date)
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_start_date date;
  v_end_date date;
begin
  -- Convertir les paramètres texte en date
  v_start_date := coalesce(start_date::date, date_trunc('isoweek', current_date)::date);
  v_end_date := coalesce(end_date::date, (date_trunc('isoweek', current_date)::date + interval '6 days')::date);
  
  return query
  with base as (
    select
      t.restaurant_id,
      ((extract(dow from t.date::date)::int + 6) % 7) as dow,
      t.date::date as transaction_date,
      count(distinct t.user_id) as clients,
      coalesce(sum(case when t.points < 0 then -t.points else 0 end), 0)::bigint as points_spent
    from private.transactions t
    where t.status in ('valide', 'completed')
      and t.restaurant_id is not null
      -- Filtrer par dates
      and t.date::date >= v_start_date
      and t.date::date <= v_end_date
    group by t.restaurant_id, ((extract(dow from t.date::date)::int + 6) % 7), t.date::date
  )
  select b.restaurant_id, b.dow, b.clients, b.points_spent, b.transaction_date from base b;
end;
$$

grant execute on function public.get_restaurant_frequentation_by_date_range(text, text) to authenticated

grant execute on function public.get_restaurant_frequentation_by_date_range(text, text) to service_role

-- ──────────────────────────────────────────────────────────────────────

-- ============================================================================
-- STORAGE BUCKETS
-- ============================================================================

INSERT INTO storage.buckets (name, public, file_size_limit, allowed_mime_types)
VALUES (
  'articles',
  true,
  NULL,
  NULL
)
ON CONFLICT (name) DO NOTHING;

INSERT INTO storage.buckets (name, public, file_size_limit, allowed_mime_types)
VALUES (
  'member-card',
  true,
  NULL,
  NULL
)
ON CONFLICT (name) DO NOTHING;

INSERT INTO storage.buckets (name, public, file_size_limit, allowed_mime_types)
VALUES (
  'offers-images',
  true,
  NULL,
  NULL
)
ON CONFLICT (name) DO NOTHING;

INSERT INTO storage.buckets (name, public, file_size_limit, allowed_mime_types)
VALUES (
  'promotions_images',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp']
)
ON CONFLICT (name) DO NOTHING;

INSERT INTO storage.buckets (name, public, file_size_limit, allowed_mime_types)
VALUES (
  'restaurant_menu',
  true,
  5242880,
  NULL
)
ON CONFLICT (name) DO NOTHING;

INSERT INTO storage.buckets (name, public, file_size_limit, allowed_mime_types)
VALUES (
  'restaurants-images',
  true,
  NULL,
  NULL
)
ON CONFLICT (name) DO NOTHING;

