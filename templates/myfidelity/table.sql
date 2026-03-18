CREATE TABLE private.articles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    calories integer,
    points integer NOT NULL,
    image text NOT NULL,
    price numeric(10,2),
    category text,
    isbestseller boolean DEFAULT false NOT NULL,
    islowco2 boolean DEFAULT false NOT NULL,
    badges text[] GENERATED ALWAYS AS (array_remove(ARRAY[
CASE
    WHEN isbestseller THEN 'Best-seller'::text
    ELSE NULL::text
END,
CASE
    WHEN islowco2 THEN 'Low CO2'::text
    ELSE NULL::text
END], NULL::text)) STORED,
    allergens text[],
    description text,
    co2_ranking text,
    is_ecogeste boolean DEFAULT false NOT NULL,
    restaurant_ids uuid[],
    categorie text
);



COMMENT ON TABLE private.articles IS 'RLS activé. Accès uniquement via fonctions RPC SECURITY DEFINER.';


CREATE TABLE private.offers (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    title text NOT NULL,
    description text,
    expiry_date timestamp with time zone,
    is_premium boolean DEFAULT false,
    image text,
    points integer,
    is_active boolean DEFAULT true NOT NULL,
    restaurant_ids uuid[] DEFAULT ARRAY[]::uuid[] NOT NULL,
    context_tags text[] DEFAULT '{}'::text[],
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);



COMMENT ON TABLE private.offers IS 'RLS activé. Accès uniquement via fonctions RPC SECURITY DEFINER.';



CREATE TABLE private.restaurants (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    description text,
    image_url text,
    location text,
    is_new boolean DEFAULT false,
    boosted boolean DEFAULT false,
    schedule jsonb,
    special_hours jsonb,
    categories text[],
    status text DEFAULT ''::text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    restaurant_menu_url text,
    restaurant_menu_url_jsonb jsonb DEFAULT '[]'::jsonb
);



COMMENT ON TABLE private.restaurants IS 'RLS activé. Accès uniquement via fonctions RPC SECURITY DEFINER.';


CREATE TABLE private.app_access_stats (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    access_type text DEFAULT 'app_boot_data'::text NOT NULL,
    accessed_at timestamp with time zone DEFAULT now() NOT NULL,
    user_role public.user_role,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);



COMMENT ON TABLE private.app_access_stats IS 'Statistiques d''accès à l''application. Enregistre chaque appel à get_app_boot_data. Accessible uniquement aux administrateurs.';



COMMENT ON COLUMN private.app_access_stats.access_type IS 'Type d''accès (ex: app_boot_data, dashboard_boot_data, etc.)';



COMMENT ON COLUMN private.app_access_stats.accessed_at IS 'Date et heure de l''accès';


CREATE TABLE private.transactions (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    date timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    restaurant_id uuid,
    items jsonb,
    total numeric,
    points integer,
    status text DEFAULT 'en_attente'::text NOT NULL,
    calories integer,
    used_offers text[] DEFAULT '{}'::text[],
    cash_register_id uuid,
    CONSTRAINT check_used_offers_is_array CHECK (((used_offers IS NULL) OR (array_length(used_offers, 1) >= 0)))
);



CREATE TABLE private.users (
    id uuid DEFAULT auth.uid() NOT NULL,
    email text NOT NULL,
    name text,
    avatar_url text,
    points integer DEFAULT 0,
    role public.user_role DEFAULT 'utilisateur'::public.user_role,
    is_active boolean DEFAULT true,
    notification_settings jsonb DEFAULT '{"horaires": true, "sondages": true, "promotions": true, "recompenses": true, "systemUpdates": true, "newRestaurants": true, "asapAnnouncements": true}'::jsonb,
    created_at timestamp with time zone,
    last_activation_email_sent timestamp with time zone,
    CONSTRAINT valid_name_for_new_users CHECK (((role <> 'utilisateur'::public.user_role) OR (name IS NULL) OR (length(TRIM(BOTH FROM name)) = 0) OR ((length(TRIM(BOTH FROM name)) >= 2) AND (length(TRIM(BOTH FROM name)) <= 100)))),
    CONSTRAINT valid_points_for_all CHECK (((points >= 0) AND (points <= 10000)))
);



COMMENT ON TABLE private.users IS 'RLS activé. Utilisateurs voient leur propre profil, admins voient tout.';



CREATE TABLE private.poll_options (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    poll_id uuid NOT NULL,
    option_text text NOT NULL,
    option_order integer NOT NULL
);



CREATE TABLE private.poll_votes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    poll_id uuid NOT NULL,
    option_id uuid NOT NULL,
    user_id uuid NOT NULL
);



CREATE TABLE private.polls (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    description text,
    question text NOT NULL,
    target_audience jsonb DEFAULT '{}'::jsonb,
    starts_at timestamp with time zone NOT NULL,
    ends_at timestamp with time zone NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    image_url text,
    notif_sent boolean DEFAULT false NOT NULL
);



COMMENT ON TABLE private.polls IS 'RLS activé. Accès lecture pour authentifiés, écriture via RPC.';



COMMENT ON COLUMN private.polls.notif_sent IS 'Indique si la notification d''activation a été envoyée pour ce sondage. false = pas encore envoyé, true = déjà envoyé.';



CREATE TABLE private.promotions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    description text,
    image_url text,
    start_date timestamp with time zone NOT NULL,
    end_date timestamp with time zone NOT NULL,
    color character varying(7) DEFAULT '#FF8A65'::character varying,
    notif_sent boolean DEFAULT false NOT NULL
);



COMMENT ON COLUMN private.promotions.notif_sent IS 'Indique si la notification d''activation a été envoyée pour cette promotion. false = pas encore envoyé, true = déjà envoyé.';




CREATE TABLE private.articles_categories (
    id bigint NOT NULL,
    categories text
);



ALTER TABLE private.articles_categories ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME private.article_categorie_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE private.disposable_emails (
    domain text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);



CREATE TABLE private.errors (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    message text NOT NULL,
    stack text,
    context text,
    user_id uuid,
    route text,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL
);



CREATE TABLE private.faq (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    question text NOT NULL,
    answer text NOT NULL,
    language text DEFAULT 'fr'::text NOT NULL,
    category text DEFAULT 'general'::text NOT NULL
);



CREATE TABLE private.feedback (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    category text NOT NULL,
    comments text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);



CREATE TABLE private.notification_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    notification_token text NOT NULL,
    device_type text NOT NULL,
    last_seen timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT notification_tokens_v2_device_type_check CHECK ((device_type = ANY (ARRAY['ios'::text, 'android'::text])))
);



CREATE TABLE public.activation_notification_config (
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT activation_notification_config_entity_type_check CHECK ((entity_type = ANY (ARRAY['promotion'::text, 'poll'::text])))
);



COMMENT ON TABLE public.activation_notification_config IS 'Message personnalisé à envoyer quand une promotion/sondage passe en actif. Enregistré via la modale "Programmer une notification".';



CREATE TABLE public.entity_activation_notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    sent_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT entity_activation_notifications_entity_type_check CHECK ((entity_type = ANY (ARRAY['promotion'::text, 'poll'::text])))
);



COMMENT ON TABLE public.entity_activation_notifications IS 'Trace les notifications envoyées lorsqu''une promotion ou un sondage passe en statut actif. Évite les doublons.';





CREATE TABLE public.notification_action_settings (
    action_id text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);



CREATE TABLE public.section_visibility (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    section public.section_id NOT NULL,
    visible_for text[] DEFAULT '{administrateur,superadmin}'::text[],
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    updated_by uuid
);







CREATE TABLE audit.security_anomalies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    detected_at timestamp with time zone DEFAULT now(),
    anomaly_type text NOT NULL,
    severity text NOT NULL,
    description text NOT NULL,
    request_id text,
    user_id uuid,
    ip_address inet,
    user_agent text,
    endpoint text,
    method text,
    status_code integer,
    country text,
    bot_score integer,
    metadata jsonb,
    resolved boolean DEFAULT false,
    resolved_at timestamp with time zone,
    resolved_by uuid,
    notes text,
    CONSTRAINT security_anomalies_severity_check CHECK ((severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])))
);



COMMENT ON TABLE audit.security_anomalies IS 'Table d''anomalies de sécurité. Accès lecture réservé aux admins via RPC. Accès écriture uniquement via fonctions RPC SECURITY DEFINER.';



CREATE TABLE audit.transaction_points_anomalies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    transaction_id uuid NOT NULL,
    user_id uuid NOT NULL,
    detected_at timestamp with time zone DEFAULT now() NOT NULL,
    stored_points integer NOT NULL,
    recalculated_points integer NOT NULL,
    points_difference integer NOT NULL,
    severity text NOT NULL,
    status text DEFAULT 'a_verifier'::text NOT NULL,
    CONSTRAINT transaction_points_anomalies_severity_check CHECK ((severity = ANY (ARRAY['medium'::text, 'high'::text, 'critical'::text]))),
    CONSTRAINT transaction_points_anomalies_status_check CHECK ((status = ANY (ARRAY['a_verifier'::text, 'corrige_auto'::text, 'corrige_manuel'::text, 'ignore'::text])))
);



COMMENT ON COLUMN audit.transaction_points_anomalies.status IS 'Statut de l''anomalie : a_verifier (à vérifier manuellement), corrige_auto (corrigée automatiquement), corrige_manuel (corrigée manuellement), ignore (ignorée)';



CREATE TABLE audit.user_points_anomalies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    detected_at timestamp with time zone DEFAULT now() NOT NULL,
    stored_points integer NOT NULL,
    recalculated_points integer NOT NULL,
    points_difference integer NOT NULL,
    severity text NOT NULL,
    status text DEFAULT 'a_verifier'::text NOT NULL,
    CONSTRAINT user_points_anomalies_severity_check CHECK ((severity = ANY (ARRAY['medium'::text, 'high'::text, 'critical'::text]))),
    CONSTRAINT user_points_anomalies_status_check CHECK ((status = ANY (ARRAY['a_verifier'::text, 'corrige_auto'::text, 'corrige_manuel'::text, 'ignore'::text])))
);



COMMENT ON COLUMN audit.user_points_anomalies.status IS 'Statut de l''anomalie : a_verifier (à vérifier manuellement), corrige_auto (corrigée automatiquement), corrige_manuel (corrigée manuellement), ignore (ignorée)';

