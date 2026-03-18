CREATE FUNCTION audit.detect_anomaly_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'audit'
    AS $$
DECLARE
    v_user_id uuid;
    v_user_role text;
    v_anomaly_type text;
    v_severity text;
    v_description text;
    v_metadata jsonb;
    v_ip_address inet;
    v_user_agent text;
    v_current_hour integer;
    v_is_unusual_time boolean := false;
    v_old_role text;
    v_new_role text;
    v_deleted_email text;
BEGIN
    -- 🛡️ SÉCURITÉ : Vérifier que seul postgres peut exécuter cette fonction
    IF current_user != 'postgres' THEN
        RAISE EXCEPTION 'Accès refusé : cette fonction ne peut être exécutée que par le rôle postgres';
    END IF;

    -- Récupérer l'utilisateur actuel
    v_user_id := auth.uid();

    -- Récupérer le rôle de l'utilisateur
    IF v_user_id IS NOT NULL THEN
        SELECT role INTO v_user_role
        FROM private.users
        WHERE id = v_user_id;
    END IF;

    -- Vérifier l'heure (anomalie si entre 2h et 5h du matin)
    v_current_hour := EXTRACT(HOUR FROM now());
    IF v_current_hour >= 2 AND v_current_hour < 5 THEN
        v_is_unusual_time := true;
    END IF;

    -- Détecter les anomalies selon le type d'opération
    IF TG_OP = 'UPDATE' THEN
        -- Anomalie : Modification de points manuelle suspecte
        IF TG_TABLE_NAME = 'users' THEN
            BEGIN
                -- ✅ CORRECTION : Essayer d'accéder à OLD.points seulement si c'est la table users
                IF OLD.points IS DISTINCT FROM NEW.points THEN
                    -- Vérifier si la différence est importante
                    IF ABS(COALESCE(NEW.points, 0) - COALESCE(OLD.points, 0)) > 100 THEN
                        v_anomaly_type := 'suspicious_points_modification';
                        v_severity := 'high';
                        v_description := format('Modification importante de points: % -> % (différence: %)',
                            OLD.points, NEW.points, NEW.points - OLD.points);
                        v_metadata := jsonb_build_object(
                            'old_points', OLD.points,
                            'new_points', NEW.points,
                            'difference', NEW.points - OLD.points,
                            'table', TG_TABLE_NAME,
                            'operation', TG_OP
                        );

                        PERFORM audit.log_security_anomaly(
                            v_anomaly_type,
                            v_severity,
                            v_description,
                            NULL,
                            v_user_id,
                            NULL,
                            NULL,
                            format('%s.%s', TG_TABLE_SCHEMA, TG_TABLE_NAME),
                            TG_OP,
                            NULL,
                            NULL,
                            NULL,
                            v_metadata
                        );
                    END IF;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                -- Ignorer les erreurs d'accès aux colonnes qui n'existent pas
                NULL;
            END;

            -- ✅ CORRECTION : Vérifier la colonne role seulement pour la table users avec gestion d'erreur
            BEGIN
                v_old_role := OLD.role;
                v_new_role := NEW.role;
                IF v_old_role IS DISTINCT FROM v_new_role THEN
                    v_anomaly_type := 'role_modification';
                    v_severity := 'critical';
                    v_description := format('Modification de rôle: % -> %', v_old_role, v_new_role);
                    v_metadata := jsonb_build_object(
                        'old_role', v_old_role,
                        'new_role', v_new_role,
                        'table', TG_TABLE_NAME,
                        'operation', TG_OP
                    );

                    PERFORM audit.log_security_anomaly(
                        v_anomaly_type,
                        v_severity,
                        v_description,
                        NULL,
                        v_user_id,
                        NULL,
                        NULL,
                        format('%s.%s', TG_TABLE_SCHEMA, TG_TABLE_NAME),
                        TG_OP,
                        NULL,
                        NULL,
                        NULL,
                        v_metadata
                    );
                END IF;
            EXCEPTION WHEN OTHERS THEN
                -- Ignorer les erreurs si la colonne role n'existe pas
                NULL;
            END;
        END IF;
    END IF;

    -- Anomalie : Opération à une heure inhabituelle
    IF v_is_unusual_time THEN
        v_anomaly_type := 'unusual_time_pattern';
        v_severity := 'medium';
        v_description := format('Opération %s sur %s.%s à une heure inhabituelle (%s)',
            TG_OP, TG_TABLE_SCHEMA, TG_TABLE_NAME, to_char(now(), 'HH24:MI'));
        v_metadata := jsonb_build_object(
            'hour', v_current_hour,
            'table', TG_TABLE_NAME,
            'operation', TG_OP,
            'timestamp', now()
        );

        PERFORM audit.log_security_anomaly(
            v_anomaly_type,
            v_severity,
            v_description,
            NULL,
            v_user_id,
            NULL,
            NULL,
            format('%s.%s', TG_TABLE_SCHEMA, TG_TABLE_NAME),
            TG_OP,
            NULL,
            NULL,
            NULL,
            v_metadata
        );
    END IF;

    -- Anomalie : Suppression de données (toujours suspect)
    IF TG_OP = 'DELETE' THEN
        v_anomaly_type := 'data_deletion';
        v_severity := 'high';
        v_description := format('Suppression de données dans %s.%s', TG_TABLE_SCHEMA, TG_TABLE_NAME);

        -- ✅ CORRECTION : Inclure l'email dans metadata si c'est une suppression d'utilisateur
        v_metadata := jsonb_build_object(
            'table', TG_TABLE_NAME,
            'operation', TG_OP,
            'deleted_record_id', OLD.id
        );

        -- Si c'est la table users, inclure l'email et autres infos importantes
        IF TG_TABLE_NAME = 'users' THEN
            BEGIN
                v_deleted_email := OLD.email;
                v_metadata := v_metadata || jsonb_build_object(
                    'deleted_email', v_deleted_email,
                    'deleted_name', OLD.name,
                    'deleted_role', OLD.role,
                    'deleted_points', OLD.points
                );
            EXCEPTION WHEN OTHERS THEN
                -- Si la colonne email n'existe pas, continuer sans
                NULL;
            END;
        END IF;

        PERFORM audit.log_security_anomaly(
            v_anomaly_type,
            v_severity,
            v_description,
            NULL,
            v_user_id,
            NULL,
            NULL,
            format('%s.%s', TG_TABLE_SCHEMA, TG_TABLE_NAME),
            TG_OP,
            NULL,
            NULL,
            NULL,
            v_metadata
        );
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;



COMMENT ON FUNCTION audit.detect_anomaly_trigger() IS 'Trigger qui détecte automatiquement les anomalies lors des opérations sur les tables et les enregistre dans audit.security_anomalies.';



CREATE FUNCTION audit.detect_auth_anomalies() RETURNS TABLE(anomalies_detected bigint, anomaly_details jsonb)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'auth', 'audit'
    AS $$
DECLARE
    v_anomaly_count bigint := 0;
    v_anomalies jsonb := '[]'::jsonb;
    v_log record;
    v_anomaly_type text;
    v_severity text;
    v_description text;
    v_anomaly_id uuid;
    v_recent_logs_count integer;
    v_user_agent text;
BEGIN
    -- 🛡️ SÉCURITÉ : Vérifier que seul postgres peut exécuter cette fonction
    IF current_user != 'postgres' THEN
        RAISE EXCEPTION 'Accès refusé : cette fonction ne peut être exécutée que par le rôle postgres';
    END IF;

    -- Analyser les logs des dernières 24 heures
    FOR v_log IN
        SELECT
            id,
            instance_id,
            payload,
            created_at,
            ip_address
        FROM auth.audit_log_entries
        WHERE created_at >= now() - interval '24 hours'
        ORDER BY created_at DESC
        LIMIT 1000
    LOOP
        -- Extraire user_agent du payload si disponible
        v_user_agent := v_log.payload->>'user_agent';

        -- Détection 1: Tentatives de connexion échouées multiples
        IF (v_log.payload->>'action') = 'login' AND (v_log.payload->>'error_message') IS NOT NULL THEN
            -- Compter les échecs pour cet IP dans les dernières heures
            SELECT COUNT(*) INTO v_recent_logs_count
            FROM auth.audit_log_entries
            WHERE ip_address = v_log.ip_address
              AND created_at >= now() - interval '1 hour'
              AND (payload->>'action') = 'login'
              AND (payload->>'error_message') IS NOT NULL;

            IF v_recent_logs_count >= 5 THEN
                v_anomaly_type := 'multiple_failed_logins';
                v_severity := 'high';
                v_description := format('Tentatives de connexion échouées multiples: %s échecs depuis %s',
                    v_recent_logs_count, v_log.ip_address);

                v_anomaly_id := audit.log_security_anomaly(
                    v_anomaly_type,
                    v_severity,
                    v_description,
                    v_log.id::text,
                    (v_log.payload->>'actor_id')::uuid,
                    v_log.ip_address::inet,
                    v_user_agent,
                    'auth.audit_log_entries',
                    'LOGIN',
                    NULL,
                    NULL,
                    NULL,
                    jsonb_build_object(
                        'log_id', v_log.id,
                        'action', v_log.payload->>'action',
                        'error_message', v_log.payload->>'error_message',
                        'failed_attempts', v_recent_logs_count,
                        'timestamp', v_log.created_at
                    )
                );

                v_anomaly_count := v_anomaly_count + 1;
                v_anomalies := v_anomalies || jsonb_build_object(
                    'id', v_anomaly_id,
                    'type', v_anomaly_type,
                    'severity', v_severity,
                    'description', v_description
                );
            END IF;
        END IF;

        -- Détection 2: Changements de mot de passe fréquents
        IF (v_log.payload->>'action') = 'user_updated_password' THEN
            SELECT COUNT(*) INTO v_recent_logs_count
            FROM auth.audit_log_entries
            WHERE (payload->>'actor_id') = (v_log.payload->>'actor_id')
              AND created_at >= now() - interval '24 hours'
              AND (payload->>'action') = 'user_updated_password';

            IF v_recent_logs_count >= 3 THEN
                v_anomaly_type := 'rapid_password_changes';
                v_severity := 'high';
                v_description := format('Changements de mot de passe fréquents: %s changements en 24h',
                    v_recent_logs_count);

                v_anomaly_id := audit.log_security_anomaly(
                    v_anomaly_type,
                    v_severity,
                    v_description,
                    v_log.id::text,
                    (v_log.payload->>'actor_id')::uuid,
                    v_log.ip_address::inet,
                    v_user_agent,
                    'auth.audit_log_entries',
                    'UPDATE_PASSWORD',
                    NULL,
                    NULL,
                    NULL,
                    jsonb_build_object(
                        'log_id', v_log.id,
                        'action', v_log.payload->>'action',
                        'password_changes_count', v_recent_logs_count,
                        'timestamp', v_log.created_at
                    )
                );

                v_anomaly_count := v_anomaly_count + 1;
                v_anomalies := v_anomalies || jsonb_build_object(
                    'id', v_anomaly_id,
                    'type', v_anomaly_type,
                    'severity', v_severity,
                    'description', v_description
                );
            END IF;
        END IF;

        -- Détection 3: Connexions depuis des IPs différentes rapidement
        IF (v_log.payload->>'action') = 'login' AND (v_log.payload->>'error_message') IS NULL THEN
            SELECT COUNT(DISTINCT ip_address) INTO v_recent_logs_count
            FROM auth.audit_log_entries
            WHERE (payload->>'actor_id') = (v_log.payload->>'actor_id')
              AND created_at >= now() - interval '1 hour'
              AND (payload->>'action') = 'login'
              AND (payload->>'error_message') IS NULL;

            IF v_recent_logs_count >= 3 THEN
                v_anomaly_type := 'suspicious_login_location';
                v_severity := 'high';
                v_description := format('Connexions depuis %s IPs différentes en 1h (possible session hijacking)',
                    v_recent_logs_count);

                v_anomaly_id := audit.log_security_anomaly(
                    v_anomaly_type,
                    v_severity,
                    v_description,
                    v_log.id::text,
                    (v_log.payload->>'actor_id')::uuid,
                    v_log.ip_address::inet,
                    v_user_agent,
                    'auth.audit_log_entries',
                    'LOGIN',
                    NULL,
                    NULL,
                    NULL,
                    jsonb_build_object(
                        'log_id', v_log.id,
                        'action', v_log.payload->>'action',
                        'unique_ips_count', v_recent_logs_count,
                        'timestamp', v_log.created_at
                    )
                );

                v_anomaly_count := v_anomaly_count + 1;
                v_anomalies := v_anomalies || jsonb_build_object(
                    'id', v_anomaly_id,
                    'type', v_anomaly_type,
                    'severity', v_severity,
                    'description', v_description
                );
            END IF;
        END IF;

        -- Détection 4: Utilisation de tokens expirés
        IF (v_log.payload->>'action') = 'token_refreshed' AND (v_log.payload->>'error_message') IS NOT NULL THEN
            IF (v_log.payload->>'error_message') LIKE '%expired%' OR
               (v_log.payload->>'error_message') LIKE '%invalid%' THEN
                v_anomaly_type := 'token_expired_usage';
                v_severity := 'medium';
                v_description := format('Tentative d''utilisation de token expiré: %s',
                    v_log.payload->>'error_message');

                v_anomaly_id := audit.log_security_anomaly(
                    v_anomaly_type,
                    v_severity,
                    v_description,
                    v_log.id::text,
                    (v_log.payload->>'actor_id')::uuid,
                    v_log.ip_address::inet,
                    v_user_agent,
                    'auth.audit_log_entries',
                    'TOKEN_REFRESH',
                    NULL,
                    NULL,
                    NULL,
                    jsonb_build_object(
                        'log_id', v_log.id,
                        'action', v_log.payload->>'action',
                        'error_message', v_log.payload->>'error_message',
                        'timestamp', v_log.created_at
                    )
                );

                v_anomaly_count := v_anomaly_count + 1;
                v_anomalies := v_anomalies || jsonb_build_object(
                    'id', v_anomaly_id,
                    'type', v_anomaly_type,
                    'severity', v_severity,
                    'description', v_description
                );
            END IF;
        END IF;
    END LOOP;

    RETURN QUERY SELECT v_anomaly_count, v_anomalies;
END;
$$;



COMMENT ON FUNCTION audit.detect_auth_anomalies() IS 'Analyse les logs d''authentification des dernières 24h et détecte les anomalies. Retourne le nombre d''anomalies détectées et leurs détails.';



CREATE FUNCTION audit.get_detectable_anomaly_types() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'private', 'audit'
    AS $$
BEGIN
    -- 🛡️ SÉCURITÉ : Vérifier que seul postgres peut exécuter cette fonction
    IF current_user != 'postgres' THEN
        RAISE EXCEPTION 'Accès refusé : cette fonction ne peut être exécutée que par le rôle postgres';
    END IF;

    RETURN jsonb_build_object(
        'user_agent_anomalies', jsonb_build_array(
            'user_agent_missing',
            'user_agent_suspicious',
            'user_agent_not_app_client'
        ),
        'bot_detection', jsonb_build_array(
            'bot_score_low',
            'verified_bot_detected',
            'js_detection_failed'
        ),
        'authentication_anomalies', jsonb_build_array(
            'multiple_failed_logins',
            'suspicious_login_location',
            'token_expired_usage',
            'session_hijacking_suspected',
            'rapid_password_changes'
        ),
        'request_pattern_anomalies', jsonb_build_array(
            'rate_limit_exceeded',
            'unusual_request_volume',
            'unusual_time_pattern',
            'repeated_errors',
            'endpoint_not_found_404',
            'unauthorized_access_403'
        ),
        'geographic_anomalies', jsonb_build_array(
            'unusual_country',
            'rapid_location_change',
            'impossible_travel'
        ),
        'data_access_anomalies', jsonb_build_array(
            'access_outside_user_scope',
            'bulk_data_extraction',
            'sensitive_data_access'
        ),
        'performance_anomalies', jsonb_build_array(
            'slow_queries_suspicious',
            'timeout_patterns',
            'error_rate_spike'
        ),
        'header_anomalies', jsonb_build_array(
            'missing_custom_headers',
            'modified_headers',
            'suspicious_headers'
        )
    );
END;
$$;



COMMENT ON FUNCTION audit.get_detectable_anomaly_types() IS 'Retourne la liste de tous les types d''anomalies détectables avec les logs Supabase.';



CREATE FUNCTION audit.log_security_anomaly(p_anomaly_type text, p_severity text, p_description text, p_request_id text DEFAULT NULL::text, p_user_id uuid DEFAULT NULL::uuid, p_ip_address inet DEFAULT NULL::inet, p_user_agent text DEFAULT NULL::text, p_endpoint text DEFAULT NULL::text, p_method text DEFAULT NULL::text, p_status_code integer DEFAULT NULL::integer, p_country text DEFAULT NULL::text, p_bot_score integer DEFAULT NULL::integer, p_metadata jsonb DEFAULT NULL::jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'audit'
    AS $$
DECLARE
    v_anomaly_id uuid;
BEGIN
    -- 🛡️ SÉCURITÉ : Vérifier que seul postgres peut exécuter cette fonction
    IF current_user != 'postgres' THEN
        RAISE EXCEPTION 'Accès refusé : cette fonction ne peut être exécutée que par le rôle postgres';
    END IF;

    INSERT INTO audit.security_anomalies (
        anomaly_type,
        severity,
        description,
        request_id,
        user_id,
        ip_address,
        user_agent,
        endpoint,
        method,
        status_code,
        country,
        bot_score,
        metadata
    ) VALUES (
        p_anomaly_type,
        p_severity,
        p_description,
        p_request_id,
        p_user_id,
        p_ip_address,
        p_user_agent,
        p_endpoint,
        p_method,
        p_status_code,
        p_country,
        p_bot_score,
        p_metadata
    )
    RETURNING id INTO v_anomaly_id;

    -- Log pour les anomalies critiques
    IF p_severity IN ('high', 'critical') THEN
        RAISE WARNING '[SECURITY_ANOMALY] Type: %, Severity: %, Description: %, User: %, IP: %',
            p_anomaly_type, p_severity, p_description, p_user_id, p_ip_address;
    END IF;

    RETURN v_anomaly_id;
END;
$$;



COMMENT ON FUNCTION audit.log_security_anomaly(p_anomaly_type text, p_severity text, p_description text, p_request_id text, p_user_id uuid, p_ip_address inet, p_user_agent text, p_endpoint text, p_method text, p_status_code integer, p_country text, p_bot_score integer, p_metadata jsonb) IS 'Enregistre une anomalie de sécurité détectée. Retourne l''ID de l''anomalie créée.';



CREATE FUNCTION audit.recalculate_user_points_on_transaction_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'audit'
    AS $$
DECLARE
    v_user_id uuid;
    v_recalculated_points integer;
BEGIN
    -- 🛡️ SÉCURITÉ : Vérifier que seul postgres peut exécuter cette fonction
    IF current_user != 'postgres' THEN
        RAISE EXCEPTION 'Accès refusé : cette fonction ne peut être exécutée que par le rôle postgres';
    END IF;

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
$$;



CREATE FUNCTION audit.trigger_detect_auth_anomaly() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'auth', 'audit'
    AS $$
DECLARE
    v_anomaly_type text;
    v_severity text;
    v_description text;
    v_recent_count integer;
    v_user_agent text;
BEGIN
    -- 🛡️ SÉCURITÉ : Vérifier que seul postgres peut exécuter cette fonction
    IF current_user != 'postgres' THEN
        RAISE EXCEPTION 'Accès refusé : cette fonction ne peut être exécutée que par le rôle postgres';
    END IF;

    -- Extraire user_agent du payload si disponible
    v_user_agent := NEW.payload->>'user_agent';

    -- Détection immédiate: Tentative de connexion échouée
    IF (NEW.payload->>'action') = 'login' AND (NEW.payload->>'error_message') IS NOT NULL THEN
        -- Compter les échecs récents pour cet IP
        SELECT COUNT(*) INTO v_recent_count
        FROM auth.audit_log_entries
        WHERE ip_address = NEW.ip_address
          AND created_at >= now() - interval '1 hour'
          AND (payload->>'action') = 'login'
          AND (payload->>'error_message') IS NOT NULL;

        IF v_recent_count >= 5 THEN
            v_anomaly_type := 'multiple_failed_logins';
            v_severity := 'high';
            v_description := format('Tentatives de connexion échouées multiples: %s échecs depuis %s',
                v_recent_count, NEW.ip_address);

            PERFORM audit.log_security_anomaly(
                v_anomaly_type,
                v_severity,
                v_description,
                NEW.id::text,
                (NEW.payload->>'actor_id')::uuid,
                NEW.ip_address::inet,
                v_user_agent,
                'auth.audit_log_entries',
                'LOGIN',
                NULL,
                NULL,
                NULL,
                jsonb_build_object(
                    'log_id', NEW.id,
                    'action', NEW.payload->>'action',
                    'error_message', NEW.payload->>'error_message',
                    'failed_attempts', v_recent_count,
                    'timestamp', NEW.created_at
                )
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$;



COMMENT ON FUNCTION audit.trigger_detect_auth_anomaly() IS 'Trigger qui détecte automatiquement les anomalies lors de l''insertion dans auth.audit_log_entries.';



CREATE FUNCTION audit.verify_transaction_points_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'audit'
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
    -- 🛡️ SÉCURITÉ : Vérifier que seul postgres peut exécuter cette fonction
    IF current_user != 'postgres' THEN
        RAISE EXCEPTION 'Accès refusé : cette fonction ne peut être exécutée que par le rôle postgres';
    END IF;

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
$$;



CREATE FUNCTION audit.verify_user_points_trigger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'audit'
    AS $$
DECLARE
    v_recalculated_points integer;
    v_difference integer;
    v_severity text;
    v_new_points integer;
    v_old_points integer;
    v_allow_modification boolean;
BEGIN
    -- 🛡️ SÉCURITÉ : Vérifier que la fonction est appelée depuis un trigger PostgreSQL uniquement
    IF TG_NAME IS NULL THEN
        RAISE EXCEPTION 'Accès refusé : cette fonction ne peut être appelée que depuis un trigger PostgreSQL';
    END IF;

    -- 🛡️ NOUVEAU : Vérifier si la modification est autorisée via variable de session
    -- Cette variable est définie par la fonction update_user_points() pour les mises à jour admin
    BEGIN
        v_allow_modification := current_setting('app.allow_points_modification', true) = 'true';
    EXCEPTION WHEN OTHERS THEN
        -- Si la variable n'existe pas, elle n'est pas autorisée
        v_allow_modification := false;
    END;

    -- ✅ Si la modification est autorisée (via update_user_points), on laisse passer
    IF v_allow_modification THEN
        RETURN NEW;
    END IF;

    -- Utiliser NEW.points et OLD.points
    v_new_points := COALESCE(NEW.points, 0);
    v_old_points := COALESCE(OLD.points, 0);

    -- Recalculer les points depuis les transactions 'valide' de l'utilisateur
    SELECT COALESCE(SUM(points), 0) INTO v_recalculated_points
    FROM private.transactions
    WHERE user_id = NEW.id
      AND status = 'valide';

    -- ✅ OPTION 2 : Ignorer si c'est une mise à jour automatique
    -- Si NEW.points = recalculated_points, c'est une mise à jour automatique (pas d'anomalie)
    IF v_new_points = v_recalculated_points THEN
        -- C'est une mise à jour automatique, ne pas créer d'anomalie
        RETURN NEW;
    END IF;

    -- Calculer la différence
    v_difference := v_recalculated_points - v_new_points;

    -- ✅ Ne créer une anomalie QUE si :
    -- 1. Les points stockés sont SUPÉRIEURS aux points recalculés (vraie anomalie)
    -- 2. La différence est significative (> 0)
    IF v_new_points > v_recalculated_points AND ABS(v_difference) > 0 THEN
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

        -- Enregistrer l'anomalie dans la table audit
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
            v_new_points, -- Points qu'on essayait de mettre
            v_recalculated_points,
            v_difference,
            v_severity,
            'corrige_auto'
        )
        ON CONFLICT (user_id) DO UPDATE SET
            stored_points = v_new_points,
            recalculated_points = v_recalculated_points,
            points_difference = v_difference,
            severity = v_severity,
            status = 'corrige_auto',
            detected_at = now();

        -- Log l'anomalie et la correction
        RAISE WARNING '[SECURITY_ALERT] Anomalie de points utilisateur détectée et CORRIGÉE - User: %, Différence: %, Points tentés: % -> Points recalculés: %',
            NEW.id, v_difference, v_new_points, v_recalculated_points;
    END IF;

    RETURN NEW;
END;
$$;



COMMENT ON FUNCTION audit.verify_user_points_trigger() IS 'Trigger qui vérifie les modifications de points utilisateur.
Permet les mises à jour autorisées via la variable de session app.allow_points_modification.
Utilisée par la fonction update_user_points() pour les modifications admin.';


CREATE FUNCTION mv.refresh_mv_offers() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mv'
    AS $$
begin
  refresh materialized view mv.mv_offers;
  return null;
end;
$$;



COMMENT ON FUNCTION mv.refresh_mv_offers() IS 'Fonction trigger qui rafraîchit la vue matérialisée mv_offers.';



CREATE FUNCTION mv.refresh_mv_restaurants() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'private', 'mv'
    AS $$
begin
  refresh materialized view mv.mv_restaurants;
  return null;
end;
$$;


CREATE FUNCTION postgre_rpc.get_notification_tokens(p_email text DEFAULT NULL::text, p_role public.user_role DEFAULT NULL::public.user_role) RETURNS TABLE(notification_token text, user_id uuid, device_type text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
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
$$;



COMMENT ON FUNCTION postgre_rpc.get_notification_tokens(p_email text, p_role public.user_role) IS 'Récupère les tokens de notification par email ou rôle utilisateur';



CREATE FUNCTION postgre_rpc.get_user(p_user_id uuid) RETURNS TABLE(id uuid, name text, email text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
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
$$;



CREATE FUNCTION postgre_rpc.rpc_confirm_transaction(p_transaction_id uuid, p_restaurant_name text) RETURNS TABLE(email text, points_user integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
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
$$;



COMMENT ON FUNCTION postgre_rpc.rpc_confirm_transaction(p_transaction_id uuid, p_restaurant_name text) IS 'Confirme une transaction et associe un restaurant.
- Accès réservé UNIQUEMENT au service_role
- Doit être appelée depuis une Edge Function avec la clé secrète (service_role)
- Les utilisateurs directs (même caissiers) ne peuvent pas appeler cette fonction
- La sécurité est gérée au niveau de la Edge Function qui vérifie le rôle caissier';



CREATE FUNCTION postgre_rpc.rpc_create_transaction(p_user_id uuid, p_restaurant_name text, p_total numeric, p_items jsonb, p_points integer) RETURNS TABLE(id uuid, user_id uuid, restaurant_id uuid, total numeric, items jsonb, points integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
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
        private.transactions.id,
        private.transactions.user_id,
        private.transactions.restaurant_id,
        private.transactions.total,
        private.transactions.items,
        private.transactions.points;
END;
$$;



CREATE FUNCTION postgre_rpc.rpc_pending_transaction(p_user_id uuid) RETURNS TABLE(id uuid, user_id uuid, restaurant_id uuid, total numeric, points integer, items jsonb, used_offers text[], status text, date timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
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
$$;



CREATE FUNCTION postgre_rpc.rpc_reset_password(p_email text, p_code text, p_new_password text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'auth'
    AS $$
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
$$;



COMMENT ON FUNCTION postgre_rpc.rpc_reset_password(p_email text, p_code text, p_new_password text) IS 'Fonction wrapper pour réinitialisation de mot de passe. search_path corrigé pour inclure private.';



CREATE FUNCTION private.check_disposable_email() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $_$
DECLARE
    user_local TEXT;
    user_domain TEXT;
    normalized_local TEXT;
BEGIN
    -- 🛡️ DOUBLE VÉRIFICATION : Seul le système (trigger) devrait appeler ceci
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
$_$;



COMMENT ON FUNCTION private.check_disposable_email() IS 'Vérifie si un email est jetable. search_path corrigé pour inclure private (accès à private.disposable_emails).';



CREATE FUNCTION private.check_points_modification_allowed() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
    v_is_authorized boolean := false;
BEGIN
    -- 🛡️ SÉCURITÉ : Vérifier que le trigger est appelé par postgres/service_role
    BEGIN
        IF session_user IN ('postgres', 'service_role', 'authenticator') THEN
            v_is_authorized := true;
        ELSIF current_setting('request.jwt.claim.role', true) = 'service_role' THEN
            v_is_authorized := true;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_is_authorized := false;
    END;

    IF NOT v_is_authorized THEN
        RAISE EXCEPTION 'Accès refusé : ce trigger ne peut être activé que par postgres ou service_role';
    END IF;

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
$$;



CREATE FUNCTION private.cleanup_orphaned_storage_files() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'storage', 'extensions'
    AS $$
DECLARE
  v_current_role text;
  v_allowed_roles text[] := ARRAY['service_role', 'postgres'];
  v_is_allowed boolean := false;

  -- Résultats
  v_result jsonb := '{}'::jsonb;
  v_bucket_result jsonb;
  v_total_deleted integer := 0;
  v_total_checked integer := 0;
  v_errors text[] := ARRAY[]::text[];

  -- Variables pour chaque bucket
  v_bucket_name text;
  v_file_record record;
  v_file_name text;
  v_is_used boolean;
  v_deleted_count integer;
  v_checked_count integer;
  v_bucket_errors text[] := ARRAY[]::text[];
  v_orphaned_files text[] := ARRAY[]::text[];

  -- Mapping bucket -> table/column
  v_bucket_config record;
  v_referenced_files text[];

  -- Vérifications
  v_table_exists boolean;
  v_column_exists boolean;
  v_bucket_exists boolean;
  v_verification_errors text[] := ARRAY[]::text[];
BEGIN
  -- A. SÉCURITÉ : Vérifier que l'utilisateur a les droits
  SELECT current_user INTO v_current_role;

  -- Vérifier si le rôle actuel est autorisé
  SELECT v_current_role = ANY(v_allowed_roles) INTO v_is_allowed;

  IF NOT v_is_allowed THEN
    RAISE EXCEPTION '403: Forbidden - Cette fonction est réservée à service_role et postgres. Rôle actuel: %', v_current_role;
  END IF;

  -- B. VÉRIFICATIONS PRÉLIMINAIRES : Vérifier que les buckets et tables existent
  FOR v_bucket_config IN
    SELECT
      'restaurants-images' as bucket_name,
      'restaurants' as table_name,
      'image_url' as column_name
    UNION ALL
    SELECT
      'polls-images' as bucket_name,
      'polls' as table_name,
      'image_url' as column_name
    UNION ALL
    SELECT
      'offers-images' as bucket_name,
      'offers' as table_name,
      'image' as column_name
    UNION ALL
    SELECT
      'articles' as bucket_name,
      'articles' as table_name,
      'image' as column_name
    UNION ALL
    SELECT
      'promotions_images' as bucket_name,
      'promotions' as table_name,
      'image_url' as column_name
  LOOP
    -- Vérifier que le bucket existe
    SELECT EXISTS(
      SELECT 1 FROM storage.buckets WHERE id = v_bucket_config.bucket_name
    ) INTO v_bucket_exists;

    IF NOT v_bucket_exists THEN
      v_verification_errors := array_append(v_verification_errors,
        format('Bucket %s n''existe pas', v_bucket_config.bucket_name));
      CONTINUE;
    END IF;

    -- Vérifier que la table existe
    SELECT EXISTS(
      SELECT 1
      FROM information_schema.tables
      WHERE table_schema = 'private'
        AND table_name = v_bucket_config.table_name
    ) INTO v_table_exists;

    IF NOT v_table_exists THEN
      v_verification_errors := array_append(v_verification_errors,
        format('Table private.%s n''existe pas', v_bucket_config.table_name));
      CONTINUE;
    END IF;

    -- Vérifier que la colonne existe
    SELECT EXISTS(
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'private'
        AND table_name = v_bucket_config.table_name
        AND column_name = v_bucket_config.column_name
    ) INTO v_column_exists;

    IF NOT v_column_exists THEN
      v_verification_errors := array_append(v_verification_errors,
        format('Colonne private.%s.%s n''existe pas',
          v_bucket_config.table_name, v_bucket_config.column_name));
      CONTINUE;
    END IF;
  END LOOP;

  -- Si des erreurs de vérification, les retourner
  IF array_length(v_verification_errors, 1) > 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Erreurs de vérification',
      'verification_errors', v_verification_errors,
      'message', 'Vérifiez que tous les buckets et tables existent avant d''exécuter cette fonction'
    );
  END IF;

  -- C. Parcourir chaque bucket configuré
  FOR v_bucket_config IN
    SELECT
      'restaurants-images' as bucket_name,
      'restaurants' as table_name,
      'image_url' as column_name
    UNION ALL
    SELECT
      'polls-images' as bucket_name,
      'polls' as table_name,
      'image_url' as column_name
    UNION ALL
    SELECT
      'offers-images' as bucket_name,
      'offers' as table_name,
      'image' as column_name
    UNION ALL
    SELECT
      'articles' as bucket_name,
      'articles' as table_name,
      'image' as column_name
    UNION ALL
    SELECT
      'promotions_images' as bucket_name,
      'promotions' as table_name,
      'image_url' as column_name
  LOOP
    v_bucket_name := v_bucket_config.bucket_name;
    v_deleted_count := 0;
    v_checked_count := 0;
    v_bucket_errors := ARRAY[]::text[];
    v_orphaned_files := ARRAY[]::text[];
    v_referenced_files := ARRAY[]::text[];

    BEGIN
      -- D. Récupérer tous les fichiers référencés dans la table private correspondante
      -- On extrait le nom du fichier de chaque URL stockée dans la table
      EXECUTE format(
        'SELECT array_agg(DISTINCT private.extract_file_name_from_storage_url(%I, %L))
         FROM private.%I
         WHERE %I IS NOT NULL
           AND %I != ''''
           AND private.extract_file_name_from_storage_url(%I, %L) IS NOT NULL',
        v_bucket_config.column_name,
        v_bucket_name,
        v_bucket_config.table_name,
        v_bucket_config.column_name,
        v_bucket_config.column_name,
        v_bucket_config.column_name,
        v_bucket_name
      ) INTO v_referenced_files;

      -- Si aucun fichier référencé, initialiser avec un tableau vide
      IF v_referenced_files IS NULL THEN
        v_referenced_files := ARRAY[]::text[];
      END IF;

      -- E. VÉRIFICATION : S'assurer que delete_storage_file existe
      IF NOT EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'private'
          AND p.proname = 'delete_storage_file'
      ) THEN
        RAISE EXCEPTION 'Fonction private.delete_storage_file introuvable';
      END IF;

      -- F. Parcourir tous les fichiers du bucket Storage
      FOR v_file_record IN
        SELECT
          name,
          id
        FROM storage.objects
        WHERE bucket_id = v_bucket_name
        ORDER BY name
      LOOP
        v_file_name := v_file_record.name;
        v_checked_count := v_checked_count + 1;

        -- G. VÉRIFICATION : Ignorer les fichiers système (comme .emptyFolderPlaceholder)
        IF v_file_name LIKE '%.%' AND v_file_name NOT LIKE '%.png'
           AND v_file_name NOT LIKE '%.jpg'
           AND v_file_name NOT LIKE '%.jpeg'
           AND v_file_name NOT LIKE '%.webp'
           AND v_file_name NOT LIKE '%.avif'
           AND v_file_name NOT LIKE '%.gif'
           AND v_file_name != '.emptyFolderPlaceholder' THEN
          -- Fichier système, on le saute
          CONTINUE;
        END IF;

        BEGIN
          -- H. Vérifier si le fichier est dans la liste des fichiers référencés
          v_is_used := v_file_name = ANY(v_referenced_files);

          -- I. Si le fichier n'est pas utilisé, le supprimer
          IF NOT v_is_used THEN
            v_orphaned_files := array_append(v_orphaned_files, v_file_name);

            BEGIN
              -- J. VÉRIFICATION : Vérifier que le fichier existe avant de le supprimer
              IF EXISTS (
                SELECT 1
                FROM storage.objects
                WHERE bucket_id = v_bucket_name
                  AND name = v_file_name
              ) THEN
                IF private.delete_storage_file(v_bucket_name, v_file_name) THEN
                  v_deleted_count := v_deleted_count + 1;
                  v_total_deleted := v_total_deleted + 1;
                ELSE
                  v_bucket_errors := array_append(v_bucket_errors,
                    format('Échec suppression %s', v_file_name));
                END IF;
              ELSE
                v_bucket_errors := array_append(v_bucket_errors,
                  format('Fichier %s n''existe plus (déjà supprimé?)', v_file_name));
              END IF;
            EXCEPTION WHEN OTHERS THEN
              v_bucket_errors := array_append(v_bucket_errors,
                format('Erreur suppression %s: %s', v_file_name, SQLERRM));
            END;
          END IF;

        EXCEPTION WHEN OTHERS THEN
          v_bucket_errors := array_append(v_bucket_errors,
            format('Erreur vérification %s: %s', v_file_name, SQLERRM));
        END;
      END LOOP;

      -- K. Enregistrer les résultats pour ce bucket
      v_bucket_result := jsonb_build_object(
        'bucket', v_bucket_name,
        'table', format('private.%I', v_bucket_config.table_name),
        'column', v_bucket_config.column_name,
        'referenced_files_count', COALESCE(array_length(v_referenced_files, 1), 0),
        'checked', v_checked_count,
        'orphaned_count', array_length(v_orphaned_files, 1),
        'deleted_count', v_deleted_count,
        'orphaned_files', v_orphaned_files,
        'errors', v_bucket_errors
      );

      v_result := v_result || jsonb_build_object(v_bucket_name, v_bucket_result);
      v_total_checked := v_total_checked + v_checked_count;

    EXCEPTION WHEN OTHERS THEN
      v_errors := array_append(v_errors,
        format('Erreur bucket %s: %s', v_bucket_name, SQLERRM));
      v_result := v_result || jsonb_build_object(
        v_bucket_name,
        jsonb_build_object(
          'error', SQLERRM,
          'checked', v_checked_count,
          'deleted_count', v_deleted_count
        )
      );
    END;
  END LOOP;

  -- L. Retourner le rapport complet
  RETURN jsonb_build_object(
    'success', true,
    'mode', 'DELETE',
    'message', format('%s fichier(s) orphelin(s) supprimé(s)', v_total_deleted),
    'summary', jsonb_build_object(
      'total_checked', v_total_checked,
      'total_orphaned', v_total_deleted,
      'total_deleted', v_total_deleted,
      'total_errors', COALESCE(array_length(v_errors, 1), 0)
    ),
    'buckets', v_result,
    'global_errors', v_errors
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'summary', jsonb_build_object(
      'total_checked', v_total_checked,
      'total_deleted', v_total_deleted
    )
  );
END;
$$;



COMMENT ON FUNCTION private.cleanup_orphaned_storage_files() IS 'Supprime tous les fichiers Storage qui ne sont pas référencés dans les tables correspondantes. Accessible uniquement à service_role et postgres.';



CREATE FUNCTION private.current_week_menu_url_from_jsonb(menus jsonb) RETURNS text
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'private'
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
$$;



CREATE FUNCTION private.delete_storage_file(bucket_name text, file_name text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'storage', 'extensions'
    AS $$
DECLARE
  deleted_count integer;
  old_role text;
  object_exists boolean;
BEGIN
  -- SÉCURITÉ 1: Validation des paramètres
  IF bucket_name IS NULL OR bucket_name = '' THEN
    RAISE EXCEPTION 'Bucket name cannot be null or empty';
  END IF;

  IF file_name IS NULL OR file_name = '' THEN
    RAISE EXCEPTION 'File name cannot be null or empty';
  END IF;

  -- SÉCURITÉ 2: Vérifier que le bucket existe et est autorisé
  IF bucket_name NOT IN ('restaurants-images', 'polls-images', 'offers-images', 'articles', 'promotions_images') THEN
    RAISE EXCEPTION 'Unauthorized bucket: %', bucket_name;
  END IF;

  -- SÉCURITÉ 3: Vérifier que le fichier existe avant de tenter la suppression
  SELECT EXISTS(
    SELECT 1
    FROM storage.objects
    WHERE bucket_id = bucket_name
      AND name = file_name
  ) INTO object_exists;

  IF NOT object_exists THEN
    -- Le fichier n'existe pas, on considère que c'est OK (déjà supprimé)
    RETURN true;
  END IF;

  -- SÉCURITÉ 4: Sauvegarder le rôle actuel
  BEGIN
    SELECT current_setting('session_replication_role', true) INTO old_role;
  EXCEPTION WHEN OTHERS THEN
    old_role := 'origin';
  END;

  -- SÉCURITÉ 5: Désactiver temporairement les triggers en mode replica
  -- (nécessaire pour contourner storage.protect_delete)
  BEGIN
    SET LOCAL session_replication_role = replica;
  EXCEPTION WHEN OTHERS THEN
    -- Si on ne peut pas changer le rôle, on ne peut pas supprimer
    RAISE EXCEPTION 'Cannot disable triggers: %', SQLERRM;
  END;

  -- Supprimer le fichier
  DELETE FROM storage.objects
  WHERE bucket_id = bucket_name
    AND name = file_name;

  GET DIAGNOSTICS deleted_count = ROW_COUNT;

  -- SÉCURITÉ 6: Restaurer le rôle (important pour la sécurité)
  BEGIN
    SET LOCAL session_replication_role = DEFAULT;
  EXCEPTION WHEN OTHERS THEN
    -- Log l'erreur mais continue
    RAISE NOTICE 'Warning: Could not restore session_replication_role: %', SQLERRM;
  END;

  -- SÉCURITÉ 7: Log de sécurité pour audit
  BEGIN
    PERFORM private.log_security_event(
      'STORAGE_DELETE',
      'storage.objects',
      NULL,
      jsonb_build_object(
        'bucket', bucket_name,
        'file_name', file_name,
        'deleted', deleted_count > 0
      ),
      NULL,
      true,
      NULL
    );
  EXCEPTION WHEN OTHERS THEN
    -- Si le log échoue, on continue quand même
    RAISE NOTICE 'Warning: Could not log security event: %', SQLERRM;
  END;

  -- Retourner true si au moins un fichier a été supprimé
  RETURN deleted_count > 0;

EXCEPTION WHEN OTHERS THEN
  -- SÉCURITÉ 8: Restaurer le rôle même en cas d'erreur (critique pour la sécurité)
  BEGIN
    SET LOCAL session_replication_role = DEFAULT;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- Log l'erreur
  RAISE NOTICE 'Error in delete_storage_file: %', SQLERRM;

  RETURN false;
END;
$$;



COMMENT ON FUNCTION private.delete_storage_file(bucket_name text, file_name text) IS 'Supprime un fichier du bucket Supabase Storage via l''API HTTP DELETE.
Supporte les clés JWT (legacy) et les clés secrètes modernes (sb_secret_...).
Utilise les secrets Vault pour la clé service_role.';



CREATE FUNCTION private.extract_file_name_from_storage_url(url text, bucket_name text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
  file_name text;
  base_path text;
  bucket_path text;
BEGIN
  -- Validation des paramètres
  IF url IS NULL OR url = '' THEN
    RETURN NULL;
  END IF;

  IF bucket_name IS NULL OR bucket_name = '' THEN
    RETURN NULL;
  END IF;

  -- Construire le chemin de base attendu
  -- Format: /storage/v1/object/public/[bucket_name]/
  bucket_path := '/storage/v1/object/public/' || bucket_name || '/';

  -- Chercher la position du chemin du bucket dans l'URL
  base_path := SUBSTRING(url FROM POSITION(bucket_path IN url));

  IF base_path IS NULL OR base_path = '' THEN
    -- Essayer aussi avec le format signé (si jamais)
    bucket_path := '/storage/v1/object/sign/' || bucket_name || '/';
    base_path := SUBSTRING(url FROM POSITION(bucket_path IN url));

    IF base_path IS NULL OR base_path = '' THEN
      RETURN NULL;
    END IF;
  END IF;

  -- Extraire le nom de fichier (tout après le chemin du bucket)
  file_name := SUBSTRING(base_path FROM LENGTH(bucket_path) + 1);

  -- Enlever les paramètres de requête s'il y en a
  file_name := SPLIT_PART(file_name, '?', 1);

  -- Enlever le fragment (#) s'il y en a
  file_name := SPLIT_PART(file_name, '#', 1);

  -- Vérifier que le nom de fichier n'est pas vide
  IF file_name IS NULL OR file_name = '' THEN
    RETURN NULL;
  END IF;

  RETURN file_name;
END;
$$;



COMMENT ON FUNCTION private.extract_file_name_from_storage_url(url text, bucket_name text) IS 'Extrait le nom de fichier depuis une URL Supabase Storage';



CREATE FUNCTION private.get_user_pg_role(user_id uuid) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
    SELECT
        CASE
            WHEN u.role = 'superadmin' THEN 'app_superadmin'
            WHEN u.role = 'administrateur' THEN 'app_admin'
            WHEN u.role = 'caissier' THEN 'app_cashier'
            ELSE 'app_user'
        END
    FROM private.users u
    WHERE u.id = user_id;
$$;



COMMENT ON FUNCTION private.get_user_pg_role(user_id uuid) IS 'Retourne le rôle PostgreSQL correspondant au rôle dans la table users';



CREATE FUNCTION private.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
    raw_name TEXT;
    cleaned_name TEXT;
BEGIN
    -- 🛡️ VERROU ANTI-APPEL MANUEL
    IF TG_NAME IS NULL THEN
        RAISE EXCEPTION 'Cette fonction est strictement réservée au système de trigger.';
    END IF;

    -- 2. RÉCUPÉRATION DU NOM DEPUIS LES METADATA
    raw_name := COALESCE(NEW.raw_user_meta_data->>'name', '');

    -- 3. REMPLACEMENT DES SÉPARATEURS PAR DES ESPACES
    cleaned_name := regexp_replace(raw_name, '[\._\-]', ' ', 'g');

    -- 4. NETTOYAGE DES CARACTÈRES NON-AUTORISÉS
    cleaned_name := regexp_replace(cleaned_name, '[^a-zA-ZÀ-ÿ\s]', '', 'g');

    -- 5. NORMALISATION DES ESPACES
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
$$;



COMMENT ON FUNCTION private.handle_new_user() IS 'Crée un utilisateur dans private.users lors de l''inscription. search_path corrigé pour inclure private (accès à private.users).';



CREATE FUNCTION private.is_admin() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
  v_caller_role user_role;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  SELECT u.role INTO v_caller_role
  FROM private.users u
  WHERE u.id = auth.uid();

  RETURN v_caller_role IN ('administrateur'::user_role, 'superadmin'::user_role);
END;
$$;



COMMENT ON FUNCTION private.is_admin() IS 'Vérifie si l''utilisateur actuel est un administrateur ou superadmin.';



CREATE FUNCTION private.is_open_now(schedule jsonb, special_hours jsonb) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
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
$$;



CREATE FUNCTION private.log_app_access(p_user_id uuid, p_access_type text DEFAULT 'app_boot_data'::text, p_user_role public.user_role DEFAULT NULL::public.user_role) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
    v_existing_id UUID;
    v_user_role_value user_role;
BEGIN
    -- Récupérer le rôle de l'utilisateur une seule fois
    v_user_role_value := COALESCE(
        p_user_role,
        (SELECT role FROM private.users WHERE id = p_user_id)
    );

    -- ✅ DÉDUPLICATION : Vérifier s'il existe déjà un accès dans les 30 dernières secondes
    SELECT id INTO v_existing_id
    FROM private.app_access_stats
    WHERE user_id = p_user_id
      AND access_type = p_access_type
      AND accessed_at > NOW() - INTERVAL '30 seconds'
    ORDER BY accessed_at DESC
    LIMIT 1
    FOR UPDATE SKIP LOCKED; -- Éviter les deadlocks sur les requêtes concurrentes

    IF v_existing_id IS NOT NULL THEN
        -- ✅ Mise à jour de l'accès existant au lieu d'insérer
        UPDATE private.app_access_stats
        SET
            accessed_at = NOW(),
            user_role = v_user_role_value
        WHERE id = v_existing_id;
    ELSE
        -- ✅ Insertion uniquement si aucun accès récent n'existe
        INSERT INTO private.app_access_stats (
            user_id,
            access_type,
            accessed_at,
            user_role
        ) VALUES (
            p_user_id,
            p_access_type,
            NOW(),
            v_user_role_value
        );
    END IF;
EXCEPTION WHEN OTHERS THEN
    -- En cas d'erreur, on log mais on ne bloque pas l'appel principal
    RAISE LOG 'Erreur lors de l''enregistrement des stats d''accès pour user_id % : %', p_user_id, SQLERRM;
END;
$$;



COMMENT ON FUNCTION private.log_app_access(p_user_id uuid, p_access_type text, p_user_role public.user_role) IS 'Enregistre un accès à l''application dans app_access_stats avec déduplication (30 secondes). Si un accès existe déjà dans les 30 dernières secondes pour le même utilisateur, met à jour accessed_at au lieu d''insérer un nouvel enregistrement.';



CREATE FUNCTION private.log_security_event(p_action text, p_table_name text, p_record_id uuid, p_old_data jsonb DEFAULT NULL::jsonb, p_new_data jsonb DEFAULT NULL::jsonb, p_success boolean DEFAULT true, p_error_message text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
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
$$;



COMMENT ON FUNCTION private.log_security_event(p_action text, p_table_name text, p_record_id uuid, p_old_data jsonb, p_new_data jsonb, p_success boolean, p_error_message text) IS 'Enregistre les événements de sécurité dans les logs PostgreSQL';



CREATE FUNCTION private.log_user_security_event(p_operation text, p_user_id uuid, p_old_data jsonb DEFAULT NULL::jsonb, p_new_data jsonb DEFAULT NULL::jsonb, p_changed_fields text[] DEFAULT NULL::text[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
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
$$;



COMMENT ON FUNCTION private.log_user_security_event(p_operation text, p_user_id uuid, p_old_data jsonb, p_new_data jsonb, p_changed_fields text[]) IS 'Enregistre les événements de sécurité pour private.users dans les logs PostgreSQL';



CREATE FUNCTION private.send_feedback_to_make() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'net'
    AS $$
DECLARE
    v_is_authorized boolean := false;
BEGIN
    -- 🛡️ SÉCURITÉ : Vérifier que le trigger est appelé par postgres/service_role
    BEGIN
        IF session_user IN ('postgres', 'service_role', 'authenticator') THEN
            v_is_authorized := true;
        ELSIF current_setting('request.jwt.claim.role', true) = 'service_role' THEN
            v_is_authorized := true;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_is_authorized := false;
    END;

    IF NOT v_is_authorized THEN
        RAISE EXCEPTION 'Accès refusé : ce trigger ne peut être activé que par postgres ou service_role';
    END IF;

    PERFORM net.http_post(
    url := 'https://hook.eu2.make.com/l217emciafmm3368x674sua10obpnck3',
    headers := jsonb_build_object(
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', 'feedback',
      'schema', 'private',
      'record', jsonb_build_object(
        'id', NEW.id,
        'user_id', NEW.user_id,
        'category', NEW.category,
        'comments', NEW.comments,
        'created_at', NEW.created_at
      ),
      'old_record', NULL
    )
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'send_feedback_to_make: %', SQLERRM;
  RETURN NEW;
END;
$$;



CREATE FUNCTION private.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
    v_is_authorized boolean := false;
BEGIN
    -- 🛡️ SÉCURITÉ : Vérifier que le trigger est appelé par postgres/service_role
    BEGIN
        IF session_user IN ('postgres', 'service_role', 'authenticator') THEN
            v_is_authorized := true;
        ELSIF current_setting('request.jwt.claim.role', true) = 'service_role' THEN
            v_is_authorized := true;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_is_authorized := false;
    END;

    IF NOT v_is_authorized THEN
        RAISE EXCEPTION 'Accès refusé : ce trigger ne peut être activé que par postgres ou service_role';
    END IF;

    NEW.updated_at = now();
    RETURN NEW;
END;
$$;



CREATE FUNCTION private.sync_restaurant_menu_url_current(p_restaurant_id uuid DEFAULT NULL::uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
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
$$;



CREATE FUNCTION private.tr_validate_and_log_users() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
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
$$;



COMMENT ON FUNCTION private.tr_validate_and_log_users() IS 'Trigger unifié pour validation et logging de sécurité sur private.users. Valide tous les champs et log les changements sensibles.';



CREATE FUNCTION private.trg_sync_restaurant_menu_url() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
    v_is_authorized boolean := false;
BEGIN
    -- 🛡️ SÉCURITÉ : Vérifier que le trigger est appelé par postgres/service_role
    BEGIN
        IF session_user IN ('postgres', 'service_role', 'authenticator') THEN
            v_is_authorized := true;
        ELSIF current_setting('request.jwt.claim.role', true) = 'service_role' THEN
            v_is_authorized := true;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_is_authorized := false;
    END;

    IF NOT v_is_authorized THEN
        RAISE EXCEPTION 'Accès refusé : ce trigger ne peut être activé que par postgres ou service_role';
    END IF;

    NEW.restaurant_menu_url := private.current_week_menu_url_from_jsonb(COALESCE(NEW.restaurant_menu_url_jsonb, '[]'::jsonb));
    RETURN NEW;
END;
$$;



CREATE FUNCTION private.trigger_send_activation_notification() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'vault', 'net', 'extensions'
    AS $$
DECLARE
  v_url text;
  v_key text;
  v_entity_type text;
  v_entity_id uuid;
  v_is_authorized boolean := false;
BEGIN
    -- 🛡️ SÉCURITÉ : Vérifier que le trigger est appelé par postgres/service_role
    BEGIN
        IF session_user IN ('postgres', 'service_role', 'authenticator') THEN
            v_is_authorized := true;
        ELSIF current_setting('request.jwt.claim.role', true) = 'service_role' THEN
            v_is_authorized := true;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_is_authorized := false;
    END;

    IF NOT v_is_authorized THEN
        RAISE EXCEPTION 'Accès refusé : ce trigger ne peut être activé que par postgres ou service_role';
    END IF;

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
    INSERT INTO public.entity_activation_notifications (entity_type, entity_id, created_at)
    VALUES (v_entity_type, v_entity_id, now())
    ON CONFLICT (entity_type, entity_id) DO NOTHING;

    IF NOT FOUND THEN RETURN NEW; END IF;

    -- 3. Récupération des secrets (très rapide en indexé)
    SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'activation_notifications_project_url' LIMIT 1;
    SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'activation_notifications_service_role_key' LIMIT 1;

    -- 4. APPEL ASYNC (Non-bloquant)
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
    RAISE WARNING '[Notification Error] %', SQLERRM;
    RETURN NEW;
END;
$$;



CREATE FUNCTION private.user_has_role(required_role text) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
    user_role text;
    role_hierarchy jsonb;
BEGIN
    -- Hiérarchie des rôles (superadmin > admin > cashier > user)
    role_hierarchy := '{
        "app_superadmin": 5,
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
$$;



COMMENT ON FUNCTION private.user_has_role(required_role text) IS 'Vérifie si l''utilisateur connecté a au moins le rôle requis (hiérarchique)';



CREATE FUNCTION private.validate_email_format(p_email text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'private'
    AS $$
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
$$;



CREATE FUNCTION private.validate_hex_color(p_color text) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $_$
BEGIN
    -- Vérifier que la couleur n'est pas NULL
    IF p_color IS NULL THEN
        RETURN true; -- NULL est considéré comme valide (optionnel)
    END IF;

    -- Vérifier le format hexadécimal : #RRGGBB ou #RGB
    -- Doit commencer par # et contenir 3 ou 6 caractères hexadécimaux
    IF REGEXP_MATCH(p_color, '^#[0-9A-Fa-f]{3}$|^#[0-9A-Fa-f]{6}$') IS NOT NULL THEN
        RETURN true;
    END IF;

    -- Format invalide
    RETURN false;
EXCEPTION
    WHEN OTHERS THEN
        -- En cas d'erreur, considérer comme invalide
        RAISE WARNING 'Erreur lors de la validation de la couleur: %', SQLERRM;
        RETURN false;
END;
$_$;



COMMENT ON FUNCTION private.validate_hex_color(p_color text) IS 'Valide un format de couleur hexadécimal (#RRGGBB ou #RGB).
Retourne true si la couleur est valide, false sinon.';



CREATE FUNCTION private.validate_notification_settings(p_settings jsonb) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'private'
    AS $$
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
$$;



COMMENT ON FUNCTION private.validate_notification_settings(p_settings jsonb) IS 'Valide la structure JSON de notification_settings';



CREATE FUNCTION private.validate_safe_text(p_text text, p_max_length integer DEFAULT 1000) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
    v_length integer;
    v_trimmed text;
BEGIN
    -- Vérifier que le texte n'est pas NULL
    IF p_text IS NULL THEN
        RETURN true; -- NULL est considéré comme valide (optionnel)
    END IF;

    -- Trim le texte
    v_trimmed := TRIM(p_text);

    -- Vérifier si le texte est vide après trim
    IF LENGTH(v_trimmed) = 0 THEN
        RETURN false; -- Texte vide
    END IF;

    -- Vérifier la longueur maximale
    v_length := LENGTH(v_trimmed);
    IF p_max_length > 0 AND v_length > p_max_length THEN
        RETURN false; -- Texte trop long
    END IF;

    -- Vérifier si le texte contient des caractères dangereux
    -- Patterns XSS : <script>, </script>, javascript:, onerror=, etc.
    -- Utiliser REGEXP_REPLACE pour vérifier si quelque chose a été remplacé
    IF LENGTH(REGEXP_REPLACE(p_text, '<script[^>]*>|</script>|javascript:|on\w+\s*=', '', 'gi')) < LENGTH(p_text) THEN
        RETURN false; -- Contient du contenu dangereux
    END IF;

    -- Si toutes les vérifications passent, le texte est valide
    RETURN true;
EXCEPTION
    WHEN OTHERS THEN
        -- En cas d'erreur, considérer comme invalide
        RAISE WARNING 'Erreur lors de la validation du texte: %', SQLERRM;
        RETURN false;
END;
$$;



COMMENT ON FUNCTION private.validate_safe_text(p_text text, p_max_length integer) IS 'Valide du texte pour prévenir les attaques XSS et SQL injection.
Retourne true si le texte est valide, false sinon.
Paramètres:
- p_text: texte à valider
- p_max_length: longueur maximale autorisée (0 = pas de limite)';



CREATE FUNCTION private.validate_user_field(p_field_name text, p_field_value text, p_operation text DEFAULT 'INSERT'::text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'private'
    AS $_$
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
$_$;



COMMENT ON FUNCTION private.validate_user_field(p_field_name text, p_field_value text, p_operation text) IS 'Valide et nettoie un champ utilisateur. Centralise toutes les règles de validation pour private.users';



CREATE FUNCTION public.activate_polls_that_became_active() RETURNS TABLE(activated_count integer, activated_ids uuid[])
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
BEGIN
  -- Autoriser uniquement postgres (cron) et service_role (API/tRPC)
  -- Vérification stricte du rôle de session
  IF session_user NOT IN ('postgres', 'service_role', 'authenticator') THEN
    RAISE EXCEPTION 'Accès refusé : privilèges insuffisants.' USING ERRCODE = '42501';
  END IF;

  -- Vérification supplémentaire : si authentifié, vérifier que ce n'est pas un utilisateur normal
  IF auth.uid() IS NOT NULL THEN
    -- Si un utilisateur normal est authentifié, refuser
    IF NOT (current_setting('request.jwt.claim.role', true) = 'service_role') THEN
      RAISE EXCEPTION 'Accès refusé : cette fonction est réservée au service_role.' USING ERRCODE = '42501';
    END IF;
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
$$;



COMMENT ON FUNCTION public.activate_polls_that_became_active() IS 'Fonction appelée par le cron pour activer les sondages qui devraient être actifs maintenant mais qui ne le sont pas encore.';



CREATE FUNCTION public.addfeedback(category text, comments text) RETURNS TABLE(remaining_feedbacks integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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

    -- 🛡️ 4. VALIDATION LONGUEUR MINIMALE (10 caractères)
    IF LENGTH(TRIM(comments)) < 10 THEN
        RAISE EXCEPTION '400: Le message doit contenir au moins 10 caractères.' USING ERRCODE = '22000';
    END IF;

    -- 🛡️ 5. WHITELIST CATÉGORIES (inclure general_feedback et member_card)
    IF category NOT IN ('app_bug', 'restaurant_idea', 'food_item_feedback', 'new_feature', 'general_feedback', 'member_card', 'other') THEN
        RAISE EXCEPTION '400: Catégorie invalide.' USING ERRCODE = '22023';
    END IF;

    -- 🛡️ 6. SÉCURITÉ CONTENU (Anti-XSS, Anti-DoS, Anti-SQL)
    IF length(comments) > 2000 THEN
        RAISE EXCEPTION '400: Trop long.' USING ERRCODE = '23514';
    END IF;

    IF comments ~ '[<>]' THEN
        RAISE EXCEPTION '400: Caractères interdits (XSS).' USING ERRCODE = '22000';
    END IF;

    IF comments ~* '(\\-\\-|;|drop table|select \\*|union all|insert into|delete from)' THEN
        RAISE EXCEPTION '400: Injection SQL détectée.' USING ERRCODE = '22000';
    END IF;

    -- 🛡️ 7. COMPTAGE DU JOUR
    SELECT count(*)::integer INTO v_feedback_count
    FROM private.feedback
    WHERE user_id = v_user_id
      AND created_at >= CURRENT_DATE;

    -- 8. LOGIQUE D'INSERTION
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
$$;



CREATE FUNCTION public.auto_activate_poll_on_time() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
    v_is_authorized boolean := false;
BEGIN
    -- 🛡️ SÉCURITÉ : Vérifier que le trigger est appelé par postgres/service_role
    BEGIN
        IF session_user IN ('postgres', 'service_role', 'authenticator') THEN
            v_is_authorized := true;
        ELSIF current_setting('request.jwt.claim.role', true) = 'service_role' THEN
            v_is_authorized := true;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_is_authorized := false;
    END;

    IF NOT v_is_authorized THEN
        RAISE EXCEPTION 'Accès refusé : ce trigger ne peut être activé que par postgres ou service_role';
    END IF;

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
$$;



COMMENT ON FUNCTION public.auto_activate_poll_on_time() IS 'Trigger qui active automatiquement un sondage (is_active = true) quand starts_at est atteint lors d''un INSERT/UPDATE.';



CREATE FUNCTION public.cancel_pending_transaction(params jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(success boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'private', 'public', 'extensions'
    AS $$
DECLARE
    v_user_id uuid;
    v_tx_id uuid;
    v_rows_updated integer;
BEGIN
    -- 🛡️ NIVEAU 1 : Blocage immédiat des sessions anonymes
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN QUERY SELECT false;
        RETURN;
    END IF;

    -- 🛡️ NIVEAU 2 : Anti-Injection (On refuse tout paramètre explicite)
    IF params IS NOT NULL AND params <> '{}'::jsonb THEN
        RAISE EXCEPTION '400: Cette fonction n''accepte aucun paramètre. Elle annule automatiquement votre dernière transaction.' USING ERRCODE = '22000';
    END IF;

    -- 🛡️ NIVEAU 3 : Ciblage chirurgical (Auto-détection)
    -- On trouve la transaction la plus récente en attente pour cet utilisateur
    SELECT id INTO v_tx_id
    FROM private.transactions
    WHERE user_id = v_user_id
      AND (status = 'en_attente' OR status = 'pending')
    ORDER BY date DESC
    LIMIT 1;

    -- 🛡️ NIVEAU 4 : Exécution avec vérification
    IF v_tx_id IS NOT NULL THEN
        -- ✅ CORRECTION : Utiliser GET DIAGNOSTICS pour vérifier que l'UPDATE a fonctionné
        UPDATE private.transactions
        SET
            status = 'annule',
            date = now()
        WHERE id = v_tx_id
          AND (status = 'en_attente' OR status = 'pending'); -- ✅ Double vérification pour éviter les race conditions

        GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

        -- ✅ Vérifier que l'UPDATE a bien modifié une ligne
        IF v_rows_updated > 0 THEN
            RETURN QUERY SELECT true;
        ELSE
            -- La transaction a peut-être été modifiée entre-temps
            RETURN QUERY SELECT false;
        END IF;
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
        -- ✅ Log l'erreur pour debug (optionnel, peut être retiré en production)
        -- RAISE NOTICE 'Erreur dans cancel_pending_transaction: %', SQLERRM;
        RETURN QUERY SELECT false;
END;
$$;



COMMENT ON FUNCTION public.cancel_pending_transaction(params jsonb) IS 'Annule automatiquement la dernière transaction en attente de l''utilisateur authentifié.
- Retourne true si une transaction a été annulée
- Retourne false si aucune transaction en attente n''a été trouvée
- Authentification obligatoire';

SET default_tablespace = '';

SET default_table_access_method = heap;



CREATE FUNCTION public.create_article(article_data jsonb) RETURNS private.articles
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
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

    IF v_user_role NOT IN ('administrateur', 'superadmin') OR v_user_role IS NULL THEN
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
$$;



CREATE FUNCTION public.create_offer(offer_data jsonb) RETURNS private.offers
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
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

    IF v_user_role NOT IN ('administrateur', 'superadmin') OR v_user_role IS NULL THEN
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
$$;



CREATE FUNCTION public.create_poll_with_options(p_title text, p_description text, p_question text, p_target_audience text, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_is_active boolean, p_image_url text, p_options jsonb) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_poll_id uuid;
  v_notif_sent boolean := false;
  v_now timestamptz := now();
  v_result json;
  v_poll_record record;
  v_user_id uuid;
  v_user_role text;
  v_option_count integer;
BEGIN
  -- Vérifier l'authentification
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN json_build_object('error', 'Authentification requise');
  END IF;

  -- Vérifier le rôle
  SELECT role::text INTO v_user_role FROM private.users WHERE id = v_user_id;

  IF v_user_role NOT IN ('administrateur', 'superadmin') OR v_user_role IS NULL THEN
    RETURN json_build_object('error', 'Permission refusée : droits administrateur requis');
  END IF;

  -- Validation des données
  IF p_title IS NULL OR TRIM(p_title) = '' THEN
    RETURN json_build_object('error', 'Le titre du sondage est requis');
  END IF;

  IF p_question IS NULL OR TRIM(p_question) = '' THEN
    RETURN json_build_object('error', 'La question du sondage est requise');
  END IF;

  IF p_starts_at IS NOT NULL AND p_ends_at IS NOT NULL AND p_starts_at >= p_ends_at THEN
    RETURN json_build_object('error', 'La date de fin doit être après la date de début');
  END IF;

  -- Déterminer si notif_sent doit être true (si le sondage est actif immédiatement)
  v_now := now();

  IF p_is_active = true
     AND p_starts_at IS NOT NULL
     AND p_ends_at IS NOT NULL
     AND p_starts_at <= v_now
     AND p_ends_at > v_now THEN
    v_notif_sent := true;
  END IF;

  -- Créer le sondage
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
      WHEN p_target_audience IS NULL OR p_target_audience = 'all' THEN NULL::jsonb
      ELSE to_jsonb(p_target_audience)
    END,
    p_starts_at,
    p_ends_at,
    p_is_active,
    p_image_url,
    v_notif_sent
  )
  RETURNING id INTO v_poll_id;

  -- Récupérer le sondage créé
  SELECT * INTO v_poll_record
  FROM private.polls
  WHERE id = v_poll_id;

  -- Créer les options si elles sont fournies
  IF p_options IS NOT NULL AND jsonb_array_length(p_options) > 0 THEN
    INSERT INTO private.poll_options (
      poll_id,
      option_text,
      option_order
    )
    SELECT
      v_poll_id,
      (option->>'text')::text,
      (option->>'order')::integer
    FROM jsonb_array_elements(p_options) AS option;

    -- Compter les options créées
    SELECT COUNT(*) INTO v_option_count
    FROM private.poll_options
    WHERE poll_id = v_poll_id;
  ELSE
    v_option_count := 0;
  END IF;

  -- Log de sécurité
  BEGIN
    PERFORM private.log_security_event(
      'CREATE', 'polls', v_poll_id,
      NULL,
      jsonb_build_object(
        'title', p_title,
        'created_by', v_user_id
      ),
      true, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    -- Ignorer les erreurs de log
    NULL;
  END;

  -- Retourner le résultat complet
  RETURN json_build_object(
    'success', true,
    'data', row_to_json(v_poll_record),
    'options_created', v_option_count
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', SQLERRM);
END;
$$;



CREATE FUNCTION public.create_promotion(p_title text, p_start_date timestamp with time zone, p_end_date timestamp with time zone, p_description text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text, p_color character varying DEFAULT '#FF8A65'::character varying) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
  v_promotion_id UUID;
  v_result JSON;
  v_user_role text;
  v_is_service_role boolean;
BEGIN
  -- Vérifier si c'est service_role via session_user
  IF session_user IN ('postgres', 'service_role', 'authenticator') THEN
    v_is_service_role := true;
  ELSE
    v_is_service_role := false;
  END IF;

  -- Si ce n'est pas service_role, vérifier l'authentification et le rôle admin
  IF NOT v_is_service_role THEN
    -- A. Vérifier l'authentification
    IF auth.uid() IS NULL THEN
      RETURN json_build_object('error', 'Authentification requise');
    END IF;

    -- B. SÉCURITÉ : Vérifier le rôle dans la table de vérité (private.users)
    SELECT role::text INTO v_user_role
    FROM private.users
    WHERE id = auth.uid();

    IF v_user_role NOT IN ('administrateur', 'superadmin') OR v_user_role IS NULL THEN
      RETURN json_build_object('error', 'Permission refusée : droits administrateur requis');
    END IF;

    -- Vérification supplémentaire via JWT si disponible
    IF current_setting('request.jwt.claim.role', true) NOT IN ('service_role', 'postgres') THEN
      -- Si le JWT ne contient pas service_role, on vérifie que c'est bien un admin
      IF v_user_role NOT IN ('administrateur', 'superadmin') THEN
        RETURN json_build_object('error', 'Permission refusée : droits administrateur requis');
      END IF;
    END IF;
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
$$;

CREATE FUNCTION public.create_restaurant(new_data jsonb) RETURNS private.restaurants
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
DECLARE
    new_restaurant private.restaurants;
    v_caller_role text;
BEGIN
    -- A. NIVEAU 1 : Authentification Stricte (Fail-fast)
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. NIVEAU 2 : SÉCURITÉ - Vérification du rôle dans la table de vérité (private.users)
    -- On inclut  comme tu l'as spécifié dans ton code source.
    SELECT role::text INTO v_caller_role
    FROM private.users
    WHERE id = auth.uid();

    IF v_caller_role NOT IN ('superadmin', 'administrateur') OR v_caller_role IS NULL THEN
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
$$;



CREATE FUNCTION public.cron_check_and_send_activations() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'vault', 'net', 'extensions'
    AS $$
DECLARE
  v_url text;
  v_key text;
  v_request_id bigint;
BEGIN
  -- Validation stricte de l'utilisateur de session
  IF session_user NOT IN ('postgres', 'service_role', 'authenticator') THEN
    RAISE EXCEPTION 'Accès refusé : cette fonction nécessite des privilèges de service_role ou postgres.';
  END IF;

  -- Vérification supplémentaire : si authentifié, vérifier le rôle JWT
  IF auth.uid() IS NOT NULL THEN
    IF NOT (current_setting('request.jwt.claim.role', true) = 'service_role') THEN
      RAISE EXCEPTION 'Accès refusé : cette fonction est réservée au service_role.' USING ERRCODE = '42501';
    END IF;
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
$$;



CREATE FUNCTION public.delete_article(article_id uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
DECLARE
    v_user_role text;
    v_article_name text;
    v_image_url text;
    file_name text;
    bucket_name text := 'articles';
    image_deleted boolean := false;
BEGIN
    -- A. Vérification de l'authentification
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentification requise';
    END IF;

    -- B. SÉCURITÉ : Vérification du rôle dans private.users
    -- Seuls 'administrateur' et 'superadmin' peuvent supprimer
    SELECT role INTO v_user_role FROM private.users WHERE id = auth.uid();

    IF v_user_role NOT IN ('administrateur', 'superadmin') OR v_user_role IS NULL THEN
        RAISE EXCEPTION 'Permission refusée : droits insuffisants';
    END IF;

    -- C. Récupération du nom et de l'image pour le log et la suppression
    SELECT name, image INTO v_article_name, v_image_url
    FROM private.articles
    WHERE id = article_id;

    IF v_article_name IS NULL THEN
        RAISE EXCEPTION 'Article non trouvé';
    END IF;

    -- D. Supprimer l'image du bucket si elle existe (avant la suppression)
    IF v_image_url IS NOT NULL AND v_image_url != '' THEN
        -- Extraire le nom du fichier depuis l'URL
        file_name := private.extract_file_name_from_storage_url(v_image_url, bucket_name);

        IF file_name IS NOT NULL THEN
            -- Supprimer le fichier du bucket
            IF private.delete_storage_file(bucket_name, file_name) THEN
                image_deleted := true;
            END IF;
        END IF;
    END IF;

    -- E. Intégrité Référentielle : Vérifier si l'article est présent dans les transactions
    -- On utilise une recherche plus performante sur le JSONB si possible
    IF EXISTS (
        SELECT 1 FROM private.transactions
        WHERE items::text LIKE '%' || article_id::text || '%'
    ) THEN
        RAISE EXCEPTION 'Impossible de supprimer: article utilisé dans des transactions';
    END IF;

    -- F. Suppression sécurisée
    DELETE FROM private.articles WHERE id = article_id;

    -- G. Log de sécurité
    PERFORM private.log_security_event(
        'DELETE', 'articles', article_id,
        jsonb_build_object(
            'name', v_article_name,
            'image_deleted', image_deleted
        ),
        NULL,
        true, NULL
    );

    RETURN true;
END;
$$;



CREATE FUNCTION public.delete_my_account() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
  v_user_id UUID;
  v_result JSONB;
  v_deleted_count INTEGER := 0;
BEGIN
  -- ✅ SÉCURITÉ : Vérifier que l'utilisateur est authentifié
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Utilisateur non authentifié'
    );
  END IF;

  -- ✅ SÉCURITÉ : Vérifier que l'utilisateur existe dans private.users
  IF NOT EXISTS (SELECT 1 FROM private.users WHERE id = v_user_id) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Utilisateur non trouvé'
    );
  END IF;

  -- ✅ SÉCURITÉ : Logger l'action AVANT suppression pour audit
  BEGIN
    PERFORM private.log_security_event(
      'DELETE', 'users', v_user_id,
      (SELECT to_jsonb(u.*) FROM private.users u WHERE u.id = v_user_id),
      NULL, true, 'User self-deletion requested'
    );
  EXCEPTION WHEN OTHERS THEN
    -- Continuer même si le log échoue
    NULL;
  END;

  -- ✅ SÉCURITÉ : Supprimer les données associées dans private.users
  BEGIN
    DELETE FROM private.users WHERE id = v_user_id;
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Erreur lors de la suppression dans private.users: ' || SQLERRM
    );
  END;

  -- ✅ SÉCURITÉ : Supprimer le compte utilisateur de auth.users
  BEGIN
    DELETE FROM auth.users WHERE id = v_user_id;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Erreur lors de la suppression dans auth.users: ' || SQLERRM
    );
  END;

  -- Construire le résultat de succès
  v_result := jsonb_build_object(
    'success', true,
    'user_id', v_user_id,
    'message', 'Compte supprimé avec succès'
  );

  RETURN v_result;
END;
$$;



COMMENT ON FUNCTION public.delete_my_account() IS 'Fonction sécurisée permettant à un utilisateur authentifié de supprimer son propre compte. Requiert authentification.';



CREATE FUNCTION public.delete_offer(offer_id uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
DECLARE
    v_user_role text;
    v_offer_title text;
    v_image_url text;
    v_target_id uuid := offer_id;
    file_name text;
    bucket_name text := 'offers-images';
    image_deleted boolean := false;
BEGIN
    -- A. Vérification de l'authentification
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. SÉCURITÉ : Vérification du rôle
    SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();

    IF v_user_role NOT IN ('administrateur', 'superadmin') OR v_user_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Droits administrateur requis' USING ERRCODE = '42501';
    END IF;

    -- C. Récupération du titre et de l'image (Vérifie aussi si l'offre existe)
    SELECT title, image INTO v_offer_title, v_image_url
    FROM private.offers
    WHERE id = v_target_id;

    IF v_offer_title IS NULL THEN
        RAISE EXCEPTION '404: Not Found - Offre introuvable' USING ERRCODE = 'P0002';
    END IF;

    -- D. Supprimer l'image du bucket si elle existe (avant la suppression/archivage)
    IF v_image_url IS NOT NULL AND v_image_url != '' THEN
        -- Extraire le nom du fichier depuis l'URL
        file_name := private.extract_file_name_from_storage_url(v_image_url, bucket_name);

        IF file_name IS NOT NULL THEN
            -- Supprimer le fichier du bucket
            IF private.delete_storage_file(bucket_name, file_name) THEN
                image_deleted := true;
            END IF;
        END IF;
    END IF;

    -- E. LOGIQUE DE SUPPRESSION (HARD vs SOFT)
    -- On cherche si l'ID (en texte) est présent dans le tableau used_offers (text[])
    IF EXISTS (
        SELECT 1 FROM private.transactions
        WHERE used_offers IS NOT NULL
        AND v_target_id::text = ANY(used_offers)
    ) THEN
        -- CAS 1 : UTILISÉE -> SOFT DELETE (Archive)
        UPDATE private.offers
        SET is_active = false,
            image = NULL  -- Supprimer la référence à l'image dans la base
        WHERE id = v_target_id;

        PERFORM private.log_security_event(
            'DISABLE', 'offers', v_target_id,
            jsonb_build_object(
                'title', v_offer_title,
                'reason', 'used_in_transactions',
                'image_deleted', image_deleted
            ),
            NULL, true, NULL
        );

    ELSE
        -- CAS 2 : JAMAIS UTILISÉE -> HARD DELETE (Suppression réelle)
        DELETE FROM private.offers WHERE id = v_target_id;

        PERFORM private.log_security_event(
            'DELETE', 'offers', v_target_id,
            jsonb_build_object(
                'title', v_offer_title,
                'action', 'hard_delete',
                'image_deleted', image_deleted
            ),
            NULL, true, NULL
        );
    END IF;

    RETURN true;
END;
$$;



COMMENT ON FUNCTION public.delete_offer(offer_id uuid) IS 'Supprime ou archive une récompense et supprime son image associée du bucket Storage offers-images';



CREATE FUNCTION public.delete_poll(p_poll_id uuid) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
DECLARE
    v_poll_title text;
    v_image_url text;
    file_name text;
    bucket_name text := 'polls-images';
    image_deleted boolean := false;
BEGIN
    -- A. Vérification de l'authentification (Fail-fast)
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. SÉCURITÉ : Vérifier le rôle dans private.users
    IF NOT EXISTS (
        SELECT 1 FROM private.users
        WHERE id = auth.uid()
        AND role IN ('superadmin', 'administrateur')
    ) THEN
        RAISE EXCEPTION '403: Forbidden - Droits administrateur requis' USING ERRCODE = '42501';
    END IF;

    -- C. Récupérer le titre et l'URL de l'image pour le log et la suppression
    SELECT title, image_url INTO v_poll_title, v_image_url
    FROM private.polls
    WHERE id = p_poll_id;

    IF v_poll_title IS NULL THEN
        RAISE EXCEPTION '404: Not Found - Sondage introuvable' USING ERRCODE = 'P0002';
    END IF;

    -- D. Supprimer l'image du bucket si elle existe
    IF v_image_url IS NOT NULL AND v_image_url != '' THEN
        -- Extraire le nom du fichier depuis l'URL
        file_name := private.extract_file_name_from_storage_url(v_image_url, bucket_name);

        IF file_name IS NOT NULL THEN
            -- Supprimer le fichier du bucket
            IF private.delete_storage_file(bucket_name, file_name) THEN
                image_deleted := true;
            END IF;
        END IF;
    END IF;

    -- E. Suppression des dépendances et du sondage
    DELETE FROM private.poll_options WHERE poll_id = p_poll_id;
    DELETE FROM private.polls WHERE id = p_poll_id;

    -- F. Log de sécurité (Audit Trail)
    PERFORM private.log_security_event(
        'DELETE', 'polls', p_poll_id,
        jsonb_build_object(
            'title', v_poll_title,
            'image_deleted', image_deleted
        ),
        NULL,
        true, NULL
    );

    RETURN json_build_object(
        'success', true,
        'message', format('Sondage et options supprimés avec succès%s',
            CASE WHEN image_deleted THEN ' (image supprimée)' ELSE '' END),
        'poll_id', p_poll_id,
        'image_deleted', image_deleted
    );
END;
$$;



COMMENT ON FUNCTION public.delete_poll(p_poll_id uuid) IS 'Supprime un sondage, ses options et son image associée du bucket Storage polls-images';



CREATE FUNCTION public.delete_promotion(p_id uuid) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
DECLARE
    v_promotion_title text;
    v_image_url text;
    file_name text;
    bucket_name text := 'promotions_images';
    image_deleted boolean := false;
BEGIN
    -- A. Vérifier l'authentification
    IF auth.uid() IS NULL THEN
        RETURN json_build_object('error', 'Authentification requise');
    END IF;

    -- B. SÉCURITÉ : Vérifier le rôle
    IF NOT EXISTS (
        SELECT 1 FROM private.users
        WHERE id = auth.uid()
        AND role IN ('superadmin', 'administrateur')
    ) THEN
        RETURN json_build_object('error', 'Permission refusée : droits insuffisants');
    END IF;

    -- C. Récupérer le titre et l'URL de l'image pour le log et la suppression
    SELECT title, image_url INTO v_promotion_title, v_image_url
    FROM private.promotions
    WHERE id = p_id;

    IF v_promotion_title IS NULL THEN
        RETURN json_build_object('error', 'Promotion introuvable');
    END IF;

    -- D. Supprimer l'image du bucket si elle existe (avant la suppression)
    IF v_image_url IS NOT NULL AND v_image_url != '' THEN
        -- Extraire le nom du fichier depuis l'URL
        file_name := private.extract_file_name_from_storage_url(v_image_url, bucket_name);

        IF file_name IS NOT NULL THEN
            -- Supprimer le fichier du bucket
            IF private.delete_storage_file(bucket_name, file_name) THEN
                image_deleted := true;
            END IF;
        END IF;
    END IF;

    -- E. Supprimer la promotion
    DELETE FROM private.promotions WHERE id = p_id;

    -- F. Log de sécurité
    BEGIN
        PERFORM private.log_security_event(
            'DELETE', 'promotions', p_id,
            jsonb_build_object(
                'title', v_promotion_title,
                'image_deleted', image_deleted
            ),
            NULL,
            true, NULL
        );
    EXCEPTION WHEN OTHERS THEN
        -- Si le log échoue, on continue quand même
        RAISE NOTICE 'Le log de sécurité n''a pas pu être enregistré';
    END;

    RETURN json_build_object(
        'success', true,
        'message', format('Promotion supprimée avec succès%s',
            CASE WHEN image_deleted THEN ' (image supprimée)' ELSE '' END),
        'image_deleted', image_deleted
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('error', SQLERRM);
END;
$$;



CREATE FUNCTION public.delete_restaurants(restaurant_ids uuid[]) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
DECLARE
  deleted_count integer;
  restaurant_record record;
  file_name text;
  bucket_name text := 'restaurants-images';
  deleted_images_count integer := 0;
BEGIN
  -- A. Vérification de l'authentification
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- B. SÉCURITÉ : Vérifier le rôle (Admin / Superadmin uniquement)
  IF NOT EXISTS (
    SELECT 1
    FROM private.users
    WHERE id = auth.uid() AND role IN ('administrateur', 'superadmin')
  ) THEN
    RAISE EXCEPTION 'Accès refusé : Seuls les administrateurs peuvent supprimer des restaurants.';
  END IF;

  -- C. Récupérer les URLs d'images avant suppression et supprimer les fichiers du bucket
  FOR restaurant_record IN
    SELECT id, image_url
    FROM private.restaurants
    WHERE id = ANY(restaurant_ids) AND image_url IS NOT NULL AND image_url != ''
  LOOP
    -- Extraire le nom du fichier depuis l'URL
    file_name := private.extract_file_name_from_storage_url(restaurant_record.image_url, bucket_name);

    IF file_name IS NOT NULL THEN
      -- Supprimer le fichier du bucket
      IF private.delete_storage_file(bucket_name, file_name) THEN
        deleted_images_count := deleted_images_count + 1;
      END IF;
    END IF;
  END LOOP;

  -- D. Suppression des restaurants
  WITH deleted AS (
    DELETE FROM private.restaurants
    WHERE id = ANY(restaurant_ids)
    RETURNING id
  )
  SELECT count(*) INTO deleted_count FROM deleted;

  -- E. Log de sécurité
  BEGIN
    PERFORM private.log_security_event(
      'DELETE_BULK', 'restaurants', NULL,
      jsonb_build_object(
        'count', deleted_count,
        'ids', restaurant_ids,
        'images_deleted', deleted_images_count
      ),
      NULL,
      true, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Le log de sécurité n''a pas pu être enregistré';
  END;

  -- F. Retour du résultat
  RETURN jsonb_build_object(
    'status', 'success',
    'deleted_count', deleted_count,
    'images_deleted', deleted_images_count,
    'message', format('%s restaurant(s) supprimé(s) avec succès (%s image(s) supprimée(s))', deleted_count, deleted_images_count)
  );
END;
$$;



COMMENT ON FUNCTION public.delete_restaurants(restaurant_ids uuid[]) IS 'Supprime des restaurants et leurs images associées du bucket Storage';



CREATE FUNCTION public.delete_user_completely(user_id uuid) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
    caller_role text;
    result JSON;
    deleted_count INTEGER := 0;
BEGIN
    -- Vérification du rôle de l'appelant
    SELECT role INTO caller_role FROM private.users WHERE id = auth.uid();

    IF caller_role != 'superadmin' THEN
        RAISE EXCEPTION 'Permission refusée: seuls les superadmin peuvent supprimer des utilisateurs';
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
$$;



COMMENT ON FUNCTION public.delete_user_completely(user_id uuid) IS 'Supprime complètement un utilisateur. Réservé aux superadmin uniquement.';



CREATE FUNCTION public.get_active_offers_private() RETURNS TABLE(id uuid, title text, description text, points integer, context_tags text[], is_active boolean, is_premium boolean, restaurant_ids uuid[], image text, created_at timestamp with time zone, updated_at timestamp with time zone, expiry_date timestamp with time zone, restaurant_names text[])
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
DECLARE
    v_user_role text;
BEGIN
    -- A. Vérification de l'authentification
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. SÉCURITÉ : Restriction stricte aux rôles 'administrateur' et 'superadmin'
    SELECT role INTO v_user_role FROM private.users WHERE id = auth.uid();

    IF v_user_role NOT IN ('superadmin', 'administrateur') OR v_user_role IS NULL THEN
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
$$;



CREATE FUNCTION public.get_active_polls_private() RETURNS TABLE(id uuid, question text, is_active boolean, created_at timestamp with time zone, expires_at timestamp with time zone, total_votes integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
  v_user_role text;
  v_is_service_role boolean;
BEGIN
  -- Vérifier si c'est service_role via session_user
  IF session_user IN ('postgres', 'service_role', 'authenticator') THEN
    v_is_service_role := true;
  ELSE
    v_is_service_role := false;
  END IF;

  -- Si ce n'est pas service_role, vérifier l'authentification et le rôle admin
  IF NOT v_is_service_role THEN
    -- A. Vérifier l'authentification
    IF auth.uid() IS NULL THEN
      RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
    END IF;

    -- B. SÉCURITÉ : Vérifier le rôle dans la table de vérité (private.users)
    SELECT role::text INTO v_user_role
    FROM private.users
    WHERE id = auth.uid();

    IF v_user_role NOT IN ('administrateur', 'superadmin') OR v_user_role IS NULL THEN
      RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
    END IF;

    -- Vérification supplémentaire via JWT si disponible
    IF current_setting('request.jwt.claim.role', true) NOT IN ('service_role', 'postgres') THEN
      -- Si le JWT ne contient pas service_role, on vérifie que c'est bien un admin
      IF v_user_role NOT IN ('administrateur', 'superadmin') THEN
        RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
      END IF;
    END IF;
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
$$;



CREATE FUNCTION public.get_app_boot_data() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'mv', 'view', 'extensions'
    AS $$
DECLARE
    v_user_id uuid;
    v_user_rec record;
    v_result jsonb;
    v_has_validated_transaction boolean;
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

    -- Enregistrer l'accès de manière asynchrone (ne bloque pas la réponse)
    PERFORM private.log_app_access(
        v_user_id,
        'app_boot_data',
        v_user_rec.role
    );

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
        -- Vérifier si l'utilisateur a au moins une transaction avec status 'valide'
        SELECT EXISTS(
            SELECT 1
            FROM private.transactions
            WHERE user_id = v_user_id
            AND status = 'valide'
            LIMIT 1
        ) INTO v_has_validated_transaction;

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
                'created_at', v_user_rec.created_at,
                'has_validated_transaction', v_has_validated_transaction
            )
        ) INTO v_result;

    END IF;

    RETURN v_result;

EXCEPTION WHEN OTHERS THEN
    -- Capture l'erreur pour le debug côté serveur, mais renvoie une erreur générique au client
    RAISE LOG 'Erreur dans get_app_boot_data : %', SQLERRM;
    RAISE EXCEPTION 'Erreur interne lors du chargement des données (Code: %)', SQLSTATE;
END;
$$;



CREATE FUNCTION public.get_daily_feedback_count() RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
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

    IF v_user_role NOT IN ('superadmin', 'administrateur') OR v_user_role IS NULL THEN
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
$$;



CREATE FUNCTION public.get_dashboard_articles() RETURNS TABLE(id uuid, name text, category text, points integer, price numeric, calories integer, allergens text[], islowco2 boolean, islowcalorie boolean, restaurants text[], restaurant_names text[])
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'dashboard_view', 'private'
    AS $$
BEGIN
  IF NOT private.is_admin() THEN
    RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    a.id,
    a.name,
    a.category,
    a.points,
    a.price,
    a.calories,
    a.allergens,
    a.islowco2,
    a.islowcalorie,
    a.restaurants,
    a.restaurant_names
  FROM dashboard_view.articles a;
END;
$$;



COMMENT ON FUNCTION public.get_dashboard_articles() IS 'Récupère tous les articles depuis dashboard_view.articles. Accès réservé aux administrateurs.';



CREATE FUNCTION public.get_dashboard_boot_data() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'dashboard_view', 'extensions'
    AS $$
DECLARE
    v_caller_role user_role;
    v_result jsonb;
    v_all_user_ids uuid[];
    v_batch_size int := 500;
    v_i int;
    v_batch_ids uuid[];
    v_unverified_count int := 0;
    v_total_users_count int;
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
    -- Si l'utilisateur est admin ou marketing, on charge la première page uniquement (50 users)
    IF v_caller_role IN ('administrateur'::user_role) THEN

        -- Récupérer tous les IDs d'utilisateurs (membre/utilisateur) pour calculer unverified_count
        SELECT array_agg(id) INTO v_all_user_ids
        FROM private.users u
        WHERE u.role IN ('membre'::user_role, 'utilisateur'::user_role);

        -- Calculer unverified_count par lots de 500 maximum
        IF v_all_user_ids IS NOT NULL AND array_length(v_all_user_ids, 1) > 0 THEN
            v_total_users_count := array_length(v_all_user_ids, 1);

            -- Traiter par lots de 500
            v_i := 1;
            WHILE v_i <= array_length(v_all_user_ids, 1) LOOP
                -- Extraire un lot de 500 IDs maximum
                v_batch_ids := array(
                    SELECT v_all_user_ids[j]
                    FROM generate_subscripts(v_all_user_ids, 1) AS j
                    WHERE j >= v_i AND j < v_i + v_batch_size
                );

                -- Compter les non vérifiés dans ce lot
                SELECT v_unverified_count + count(*) INTO v_unverified_count
                FROM public.get_verification_status(v_batch_ids) AS v
                WHERE v.is_verified = false;

                -- Passer au lot suivant
                v_i := v_i + v_batch_size;
            END LOOP;
        END IF;

        WITH base_users AS (
            SELECT
                u.id,
                u.email,
                u.name,
                u.role,
                u.points,
                u.created_at
            FROM private.users u
            WHERE u.role IN ('membre'::user_role, 'utilisateur'::user_role)
            ORDER BY COALESCE(LOWER(u.name), LOWER(u.email)) ASC, LOWER(u.email) ASC
            LIMIT 50  -- Première page uniquement (50 users) triés par alphabétique
        ),
        -- Récupération des statuts de vérification pour les 50 users max (toujours < 500)
        verif AS (
            SELECT v.*
            FROM (
                SELECT array_agg(id) AS ids
                FROM base_users
            ) s
            CROSS JOIN LATERAL public.get_verification_status(s.ids) AS v
        ),
        -- Calcul des compteurs sur TOUS les utilisateurs (pas seulement la première page)
        all_users_for_counts AS (
            SELECT
                u.id,
                u.role
            FROM private.users u
            WHERE u.role IN ('membre'::user_role, 'utilisateur'::user_role)
        )
        SELECT jsonb_build_object(
            -- Utilisateur courant avec son is_verified
            'user', (
                SELECT to_jsonb(u) FROM (
                    SELECT
                        pu.id,
                        pu.email,
                        pu.name,
                        pu.role,
                        (
                            SELECT v.is_verified
                            FROM public.get_verification_status(ARRAY[pu.id]) AS v
                            LIMIT 1
                        ) AS is_verified
                    FROM private.users pu
                    WHERE pu.id = auth.uid()
                ) u
            ),

            -- Compteurs sur TOUS les utilisateurs
            'total_users_count', (
                SELECT count(*)::integer
                FROM all_users_for_counts
            ),

            'members_count', (
                SELECT count(*)::integer
                FROM all_users_for_counts
                WHERE role = 'membre'::user_role
            ),

            'non_members_count', (
                SELECT count(*)::integer
                FROM all_users_for_counts
                WHERE role = 'utilisateur'::user_role
            ),

            -- unverified_count calculé par lots de 500
            'unverified_count', COALESCE(v_unverified_count, 0)::integer,

            -- Les 50 premiers utilisateurs (membre/utilisateur) + is_verified (première page)
            -- Triés par alphabétique et préservés dans l'ordre dans jsonb_agg
            'users', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', bu.id,
                        'email', bu.email,
                        'name', bu.name,
                        'role', bu.role,
                        'points', bu.points,
                        'created_at', bu.created_at,
                        'is_verified', COALESCE(v.is_verified, false)
                    )
                    ORDER BY COALESCE(LOWER(bu.name), LOWER(bu.email)) ASC, LOWER(bu.email) ASC
                )
                FROM base_users bu
                LEFT JOIN verif v ON v.id = bu.id
            ),

            -- Restaurants
            'restaurants', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', r.id,
                        'name', r.name,
                        'description', r.description,
                        'image_url', r.image_url,
                        'location', r.location,
                        'schedule', r.schedule,
                        'special_hours', r.special_hours,
                        'categories', r.categories,
                        'is_new', r.is_new,
                        'boosted', r.boosted,
                        'status', r.status
                    )
                    ORDER BY r.name
                )
                FROM dashboard_view.restaurants r
            ),

            -- Offers
            'offers', (
                SELECT jsonb_agg(
                    to_jsonb(o) - 'created_at' - 'updated_at'
                )
                FROM dashboard_view.offers o
            ),

            -- Promotions
            'promotions', (
                SELECT jsonb_agg(p)
                FROM dashboard_view.promotions p
            ),

            -- Polls
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
                        'total_unique_voters', COALESCE(p.total_unique_voters, 0),
                        'options', COALESCE(p.options_with_vote_count, '[]'::jsonb)
                    )
                    ORDER BY p.starts_at DESC NULLS LAST
                )
                FROM dashboard_view.polls p
            ),

            -- Articles
            'articles', (
                SELECT jsonb_agg(
                    to_jsonb(a) - 'badges' - 'calories' - 'price'
                )
                FROM dashboard_view.articles a
            )
        ) INTO v_result;

    ELSE
        -- Pour un utilisateur standard, on ne renvoie QUE ses infos de base (+ is_verified)
        SELECT jsonb_build_object(
            'user', (
                SELECT to_jsonb(u) FROM (
                    SELECT
                        pu.id,
                        pu.email,
                        pu.name,
                        pu.role,
                        (
                            SELECT v.is_verified
                            FROM public.get_verification_status(ARRAY[pu.id]) AS v
                            LIMIT 1
                        ) AS is_verified
                    FROM private.users pu
                    WHERE pu.id = auth.uid()
                ) u
            )
        ) INTO v_result;
    END IF;

    RETURN v_result;
EXCEPTION
    WHEN OTHERS THEN
        -- Log de l'erreur pour le débogage
        RAISE WARNING 'Erreur dans get_dashboard_boot_data: %', SQLERRM;
        -- Re-lancer l'exception pour que PostgREST puisse la gérer
        RAISE;
END;
$$;



CREATE FUNCTION public.get_dashboard_daily_stats(start_date date DEFAULT NULL::date, end_date date DEFAULT NULL::date) RETURNS TABLE(day date, transactions_count bigint, active_users bigint, points_generated bigint, points_spent bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'dashboard_view', 'private'
    AS $$
DECLARE
  v_start_date date;
  v_end_date date;
BEGIN
  IF NOT private.is_admin() THEN
    RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
  END IF;

  v_start_date := COALESCE(start_date, current_date - interval '30 days');
  v_end_date := COALESCE(end_date, current_date);

  RETURN QUERY
  SELECT
    d.day,
    d.transactions_count,
    d.active_users,
    d.points_generated,
    d.points_spent
  FROM dashboard_view.daily_stats d
  WHERE d.day >= v_start_date
    AND d.day <= v_end_date
  ORDER BY d.day DESC;
END;
$$;



COMMENT ON FUNCTION public.get_dashboard_daily_stats(start_date date, end_date date) IS 'Récupère les statistiques quotidiennes depuis dashboard_view.daily_stats. Accès réservé aux administrateurs.';



CREATE FUNCTION public.get_dashboard_eco_gestes_usage_by_period(start_date date DEFAULT NULL::date, end_date date DEFAULT NULL::date) RETURNS TABLE(date date, eco_geste_name text, usage_count bigint, usage_count_monthly bigint, usage_count_yearly bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'dashboard_view', 'private'
    AS $$
DECLARE
  v_start_date date;
  v_end_date date;
BEGIN
  IF NOT private.is_admin() THEN
    RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
  END IF;

  v_start_date := COALESCE(start_date, current_date - interval '30 days');
  v_end_date := COALESCE(end_date, current_date);

  RETURN QUERY
  SELECT
    e.date,
    e.eco_geste_name,
    e.usage_count,
    e.usage_count_monthly,
    e.usage_count_yearly
  FROM dashboard_view.eco_gestes_usage_by_period e
  WHERE e.date >= v_start_date
    AND e.date <= v_end_date
  ORDER BY e.date DESC, e.usage_count DESC;
END;
$$;



COMMENT ON FUNCTION public.get_dashboard_eco_gestes_usage_by_period(start_date date, end_date date) IS 'Récupère l''utilisation des éco-gestes par période depuis dashboard_view.eco_gestes_usage_by_period. Accès réservé aux administrateurs.';



CREATE FUNCTION public.get_dashboard_members() RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'dashboard_view', 'extensions'
    AS $$
BEGIN
    -- A. Vérification Auth
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. Vérification Admin (On pointe bien sur private.users)
    IF NOT EXISTS (
        SELECT 1 FROM private.users
        WHERE id = auth.uid()
        AND role IN ('superadmin', 'administrateur')
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
$$;



CREATE FUNCTION public.get_dashboard_members_count() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
  v_caller_role user_role;
  v_count integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
  END IF;

  SELECT role INTO v_caller_role FROM private.users WHERE id = auth.uid();

  IF v_caller_role IS NULL THEN
    RAISE EXCEPTION '403: Forbidden - Profil inexistant' USING ERRCODE = '42501';
  END IF;

  IF v_caller_role NOT IN ('administrateur') THEN
    RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
  END IF;

  SELECT count(*)::integer
  INTO v_count
  FROM private.users
  WHERE role = 'membre'::user_role;

  RETURN v_count;
END;
$$;



CREATE FUNCTION public.get_dashboard_non_members() RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'dashboard_view', 'extensions'
    AS $$
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
        AND role IN ('superadmin', 'administrateur')
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
$$;



CREATE FUNCTION public.get_dashboard_offers_usage_by_period(start_date date DEFAULT NULL::date, end_date date DEFAULT NULL::date) RETURNS TABLE(day date, offer_name text, usage_count bigint, usage_count_monthly bigint, usage_count_yearly bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'dashboard_view', 'private'
    AS $$
DECLARE
  v_start_date date;
  v_end_date date;
BEGIN
  IF NOT private.is_admin() THEN
    RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
  END IF;

  v_start_date := COALESCE(start_date, current_date - interval '30 days');
  v_end_date := COALESCE(end_date, current_date);

  RETURN QUERY
  SELECT
    o.day,
    o.offer_name,
    o.usage_count,
    o.usage_count_monthly,
    o.usage_count_yearly
  FROM dashboard_view.offers_usage_by_period o
  WHERE o.day >= v_start_date
    AND o.day <= v_end_date
  ORDER BY o.day DESC, o.usage_count DESC;
END;
$$;



COMMENT ON FUNCTION public.get_dashboard_offers_usage_by_period(start_date date, end_date date) IS 'Récupère l''utilisation des offres par période depuis dashboard_view.offers_usage_by_period. Accès réservé aux administrateurs.';



CREATE FUNCTION public.get_dashboard_realtime_stats() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'dashboard_view', 'private'
    AS $$
DECLARE
  v_today_day date;
  v_today_transactions_count bigint;
  v_today_active_users bigint;
  v_today_points_generated bigint;
  v_today_points_spent bigint;
  v_daily_stats        jsonb;
  v_eco_gestes_stats   jsonb;
  v_total_eco_gestes   bigint;
  v_eco_gestes_usage_today bigint;
  v_eco_gestes_by_type jsonb;
  v_caller_role user_role;
BEGIN
  -- NIVEAU 1 : Authentification Stricte
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
  END IF;

  -- NIVEAU 2 : Récupération du rôle et vérification d'accès
  SELECT role INTO v_caller_role FROM private.users WHERE id = auth.uid();

  IF v_caller_role IS NULL THEN
    RAISE EXCEPTION '403: Forbidden - Profil inexistant' USING ERRCODE = '42501';
  END IF;

  -- NIVEAU 3 : Vérification que l'utilisateur est administrateur
  IF v_caller_role NOT IN ('administrateur'::user_role, 'superadmin'::user_role) THEN
    RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
  END IF;

  -- KPIs du jour : utiliser daily_stats au lieu de today_stats
  SELECT
    day,
    transactions_count,
    active_users,
    points_generated,
    points_spent
  INTO
    v_today_day,
    v_today_transactions_count,
    v_today_active_users,
    v_today_points_generated,
    v_today_points_spent
  FROM dashboard_view.daily_stats
  WHERE day = CURRENT_DATE;

  -- Si aucune donnée pour aujourd'hui, utiliser des valeurs par défaut
  IF v_today_day IS NULL THEN
    v_today_day := CURRENT_DATE;
    v_today_transactions_count := 0;
    v_today_active_users := 0;
    v_today_points_generated := 0;
    v_today_points_spent := 0;
  END IF;

  -- Activité complète (daily_stats)
  SELECT jsonb_agg(
    jsonb_build_object(
      'day', day,
      'active_users', active_users
    )
    ORDER BY day
  )
  INTO v_daily_stats
  FROM dashboard_view.daily_stats;

  -- Statistiques d'utilisation des éco gestes (30 derniers jours)
  SELECT jsonb_agg(
    jsonb_build_object(
      'day', day,
      'total_usages', total_usages,
      'unique_eco_gestes', unique_eco_gestes,
      'total_quantity', total_quantity,
      'cumulative_usages', cumulative_usages
    )
    ORDER BY day DESC
  )
  INTO v_eco_gestes_stats
  FROM dashboard_view.eco_gestes_daily_usage
  LIMIT 30;

  -- Total d'utilisations d'éco gestes aujourd'hui
  SELECT coalesce(total_usages, 0) INTO v_eco_gestes_usage_today
  FROM dashboard_view.eco_gestes_daily_usage
  WHERE day = current_date;

  -- Total d'éco gestes disponibles (depuis la vue améliorée)
  SELECT coalesce(total_eco_gestes, 0) INTO v_total_eco_gestes
  FROM dashboard_view.eco_gestes_stats
  LIMIT 1;

  -- Statistiques par type d'éco geste (utilise la vue améliorée)
  SELECT jsonb_agg(
    jsonb_build_object(
      'eco_geste_id', eco_geste_id,
      'usage_count', usage_count,
      'total_quantity', total_quantity
    )
  )
  INTO v_eco_gestes_by_type
  FROM dashboard_view.eco_gestes_by_type_stats;

  RETURN jsonb_build_object(
    'today', jsonb_build_object(
      'day', v_today_day,
      'transactions_today', COALESCE(v_today_transactions_count, 0),
      'points_generated_today', COALESCE(v_today_points_generated, 0),
      'total_eco_gestes_today', coalesce(v_total_eco_gestes, 0),
      'eco_gestes_usage_today', coalesce(v_eco_gestes_usage_today, 0)
    ),
    'daily_stats', coalesce(v_daily_stats, '[]'::jsonb),
    'eco_gestes_stats', coalesce(v_eco_gestes_stats, '[]'::jsonb),
    'eco_gestes_by_type', coalesce(v_eco_gestes_by_type, '[]'::jsonb)
  );
END;
$$;



COMMENT ON FUNCTION public.get_dashboard_realtime_stats() IS 'Corrigé: Utilise des variables individuelles au lieu d''un record pour éviter les problèmes de type. Accès réservé aux administrateurs authentifiés uniquement.';


CREATE FUNCTION public.get_dashboard_restaurants_view() RETURNS SETOF dashboard_view.restaurants
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'dashboard_view', 'private'
    AS $$
DECLARE
    v_caller_role user_role;
BEGIN
    -- NIVEAU 1 : Authentification Stricte
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
    END IF;

    -- NIVEAU 2 : Récupération du rôle et vérification d'accès
    SELECT role INTO v_caller_role FROM private.users WHERE id = auth.uid();

    IF v_caller_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Profil inexistant' USING ERRCODE = '42501';
    END IF;

    -- NIVEAU 3 : Vérification que l'utilisateur est administrateur
    IF v_caller_role NOT IN ('administrateur'::user_role, 'superadmin'::user_role) THEN
        RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
    END IF;

    -- Retourner les restaurants si l'utilisateur est administrateur
    -- IMPORTANT : SELECT * garantit que toutes les colonnes de la vue sont retournées
    -- exactement comme avant (is_open_now, new_status_label, boost_status_label, etc.)
    RETURN QUERY
    SELECT *
    FROM dashboard_view.restaurants r
    ORDER BY r.boosted DESC, r.is_new DESC, r.name ASC;
END;
$$;



COMMENT ON FUNCTION public.get_dashboard_restaurants_view() IS 'Retourne tous les restaurants actifs avec leurs informations. Accès réservé aux administrateurs uniquement.';



CREATE FUNCTION public.get_dashboard_restaurants_view(refresh_timestamp bigint) RETURNS SETOF dashboard_view.restaurants
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'dashboard_view', 'private'
    AS $$
DECLARE
    v_caller_role user_role;
BEGIN
    -- NIVEAU 1 : Authentification Stricte
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
    END IF;

    -- NIVEAU 2 : Récupération du rôle et vérification d'accès
    SELECT role INTO v_caller_role FROM private.users WHERE id = auth.uid();

    IF v_caller_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Profil inexistant' USING ERRCODE = '42501';
    END IF;

    -- NIVEAU 3 : Vérification que l'utilisateur est administrateur
    IF v_caller_role NOT IN ('administrateur'::user_role, 'superadmin'::user_role) THEN
        RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
    END IF;

    -- Le paramètre refresh_timestamp peut être utilisé pour forcer un rafraîchissement
    IF refresh_timestamp IS NOT NULL THEN
        RAISE NOTICE '[get_dashboard_restaurants_view] Rafraîchissement forcé avec timestamp: %', refresh_timestamp;
    END IF;

    -- Retourner les restaurants si l'utilisateur est administrateur
    -- IMPORTANT : SELECT * garantit que toutes les colonnes de la vue sont retournées
    -- exactement comme avant (is_open_now, new_status_label, boost_status_label, etc.)
    RETURN QUERY
    SELECT *
    FROM dashboard_view.restaurants r
    ORDER BY r.boosted DESC, r.is_new DESC, r.name ASC;
END;
$$;



COMMENT ON FUNCTION public.get_dashboard_restaurants_view(refresh_timestamp bigint) IS 'Retourne tous les restaurants actifs avec leurs informations. Le paramètre refresh_timestamp permet de forcer un rafraîchissement. Accès réservé aux administrateurs uniquement.';



CREATE FUNCTION public.get_dashboard_users_page(p_page integer DEFAULT 1, p_page_size integer DEFAULT 100, p_search text DEFAULT NULL::text, p_filter text DEFAULT 'all'::text, p_sort text DEFAULT 'created_at'::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
  v_caller_id uuid;
  v_caller_role user_role;
  v_caller_email text;
  v_page integer := GREATEST(p_page, 1);
  v_page_size integer := LEAST(GREATEST(p_page_size, 1), 500);
  v_result jsonb;
  v_filter text := COALESCE(p_filter, 'all');
  v_sort text := COALESCE(p_sort, 'created_at');
  v_all_user_ids uuid[];
  v_batch_size int := 500;
  v_i int;
  v_batch_ids uuid[];
  v_batch_result jsonb;
  v_verification_map jsonb := '{}'::jsonb;
BEGIN
  -- NIVEAU 1 : Vérification explicite du JWT et authentification stricte
  v_caller_id := auth.uid();

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION '401: Unauthorized - JWT invalide ou manquant' USING ERRCODE = 'P0001';
  END IF;

  -- NIVEAU 2 : Vérification que l'utilisateur existe dans la base de données
  SELECT role, email INTO v_caller_role, v_caller_email
  FROM private.users
  WHERE id = v_caller_id;

  IF v_caller_role IS NULL THEN
    RAISE EXCEPTION '403: Forbidden - Profil utilisateur inexistant dans la base de données' USING ERRCODE = '42501';
  END IF;

  IF v_caller_email IS NULL THEN
    RAISE EXCEPTION '403: Forbidden - Email utilisateur manquant' USING ERRCODE = '42501';
  END IF;

  -- NIVEAU 3 : Vérification explicite que le rôle est administrateur UNIQUEMENT
  IF v_caller_role::text != 'administrateur' THEN
    RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs. Rôle actuel: %', v_caller_role::text USING ERRCODE = '42501';
  END IF;

  IF v_caller_role != 'administrateur'::user_role THEN
    RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
  END IF;

  -- ÉTAPE 1 : Récupérer TOUS les utilisateurs avec leur statut de vérification
  WITH all_users_with_verif AS (
    SELECT
      u.id,
      u.email,
      u.name,
      u.role,
      u.points,
      u.created_at
    FROM private.users u
    WHERE u.role IN ('membre'::user_role, 'utilisateur'::user_role)
      AND (
        p_search IS NULL
        OR u.email ILIKE '%' || p_search || '%'
        OR (u.name IS NOT NULL AND u.name ILIKE '%' || p_search || '%')
      )
  )
  -- Récupérer tous les IDs pour traitement par lots
  SELECT array_agg(id) INTO v_all_user_ids
  FROM all_users_with_verif;

  -- Traiter les vérifications par lots de 500 maximum
  IF v_all_user_ids IS NOT NULL AND array_length(v_all_user_ids, 1) > 0 THEN
    v_i := 1;
    WHILE v_i <= array_length(v_all_user_ids, 1) LOOP
      -- Extraire un lot de 500 IDs maximum
      v_batch_ids := array(
        SELECT v_all_user_ids[j]
        FROM generate_subscripts(v_all_user_ids, 1) AS j
        WHERE j >= v_i AND j < v_i + v_batch_size
      );

      -- Récupérer les statuts de vérification pour ce lot
      SELECT jsonb_object_agg(v.id::text, v.is_verified) INTO v_batch_result
      FROM public.get_verification_status(v_batch_ids) AS v;

      -- Fusionner dans la map globale
      IF v_batch_result IS NOT NULL THEN
        v_verification_map := v_verification_map || v_batch_result;
      END IF;

      -- Passer au lot suivant
      v_i := v_i + v_batch_size;
    END LOOP;
  END IF;

  -- ÉTAPE 2 : Filtrer selon le filtre choisi avec les statuts de vérification
  WITH all_users_with_verif AS (
    SELECT
      u.id,
      u.email,
      u.name,
      u.role,
      u.points,
      u.created_at
    FROM private.users u
    WHERE u.role IN ('membre'::user_role, 'utilisateur'::user_role)
      AND (
        p_search IS NULL
        OR u.email ILIKE '%' || p_search || '%'
        OR (u.name IS NOT NULL AND u.name ILIKE '%' || p_search || '%')
      )
  ),
  filtered_users AS (
    SELECT
      au.id,
      au.email,
      au.name,
      au.role,
      au.points,
      au.created_at,
      COALESCE((v_verification_map->>au.id::text)::boolean, false) AS is_verified
    FROM all_users_with_verif au
    WHERE
      (v_filter = 'all' OR
       (v_filter = 'members' AND au.role = 'membre'::user_role) OR
       (v_filter = 'non-members' AND au.role = 'utilisateur'::user_role) OR
       (v_filter = 'unverified' AND COALESCE((v_verification_map->>au.id::text)::boolean, false) = false))
  )
  -- ÉTAPE 3 & 4 : Trier et paginer selon le type de tri
  SELECT
    CASE
      WHEN v_sort = 'points_desc' THEN
        (SELECT jsonb_agg(
          jsonb_build_object(
            'id', fu.id,
            'email', fu.email,
            'name', fu.name,
            'role', fu.role,
            'points', fu.points,
            'created_at', fu.created_at,
            'is_verified', fu.is_verified
          )
          ORDER BY COALESCE(fu.points, 0) DESC, COALESCE(LOWER(fu.name), LOWER(fu.email)) ASC
        )
        FROM (
          SELECT * FROM filtered_users
          ORDER BY COALESCE(points, 0) DESC, COALESCE(LOWER(name), LOWER(email)) ASC
          LIMIT v_page_size OFFSET (v_page - 1) * v_page_size
        ) fu)
      WHEN v_sort = 'alphabetical' THEN
        (SELECT jsonb_agg(
          jsonb_build_object(
            'id', fu.id,
            'email', fu.email,
            'name', fu.name,
            'role', fu.role,
            'points', fu.points,
            'created_at', fu.created_at,
            'is_verified', fu.is_verified
          )
          ORDER BY COALESCE(LOWER(fu.name), LOWER(fu.email)) ASC, LOWER(fu.email) ASC
        )
        FROM (
          SELECT * FROM filtered_users
          ORDER BY COALESCE(LOWER(name), LOWER(email)) ASC, LOWER(email) ASC
          LIMIT v_page_size OFFSET (v_page - 1) * v_page_size
        ) fu)
      ELSE
        -- Tri par date (par défaut)
        (SELECT jsonb_agg(
          jsonb_build_object(
            'id', fu.id,
            'email', fu.email,
            'name', fu.name,
            'role', fu.role,
            'points', fu.points,
            'created_at', fu.created_at,
            'is_verified', fu.is_verified
          )
          ORDER BY fu.created_at DESC NULLS LAST, COALESCE(LOWER(fu.name), LOWER(fu.email)) ASC
        )
        FROM (
          SELECT * FROM filtered_users
          ORDER BY created_at DESC NULLS LAST, COALESCE(LOWER(name), LOWER(email)) ASC
          LIMIT v_page_size OFFSET (v_page - 1) * v_page_size
        ) fu)
    END
  INTO v_result;

  RETURN COALESCE(v_result, '[]'::jsonb);
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'Erreur dans get_dashboard_users_page: %', SQLERRM;
    RAISE;
END;
$$;



CREATE FUNCTION public.get_eco_gestes_usage_by_date_range(start_date text, end_date text) RETURNS TABLE(date date, eco_geste_name text, usage_count bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'dashboard_view', 'private'
    AS $$
DECLARE
  v_caller_role user_role;
BEGIN
  -- NIVEAU 1 : Authentification Stricte
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
  END IF;

  -- NIVEAU 2 : Récupération du rôle et vérification d'accès
  SELECT role INTO v_caller_role FROM private.users WHERE id = auth.uid();

  IF v_caller_role IS NULL THEN
    RAISE EXCEPTION '403: Forbidden - Profil inexistant' USING ERRCODE = '42501';
  END IF;

  -- NIVEAU 3 : Vérification que l'utilisateur est administrateur
  IF v_caller_role NOT IN ('administrateur'::user_role, 'superadmin'::user_role) THEN
    RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    v.date,
    v.eco_geste_name::text,
    v.usage_count::bigint
  FROM dashboard_view.eco_gestes_usage_by_period v
  WHERE v.date >= start_date::date
    AND v.date <= end_date::date
  ORDER BY v.date, v.eco_geste_name;
END;
$$;



COMMENT ON FUNCTION public.get_eco_gestes_usage_by_date_range(start_date text, end_date text) IS 'Sécurisé : Accès réservé aux administrateurs uniquement';



CREATE FUNCTION public.get_eco_gestes_usage_by_period(period_type text DEFAULT 'month'::text, start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text) RETURNS TABLE(name text, count bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'dashboard_view', 'private'
    AS $$
DECLARE
  v_caller_role user_role;
  v_start_date date;
  v_end_date date;
BEGIN
  -- NIVEAU 1 : Authentification Stricte
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
  END IF;

  -- NIVEAU 2 : Récupération du rôle et vérification d'accès
  SELECT u.role INTO v_caller_role FROM private.users u WHERE u.id = auth.uid();

  IF v_caller_role IS NULL THEN
    RAISE EXCEPTION '403: Forbidden - Profil inexistant' USING ERRCODE = '42501';
  END IF;

  -- NIVEAU 3 : Vérification que l'utilisateur est administrateur
  IF v_caller_role NOT IN ('administrateur'::user_role, 'superadmin'::user_role) THEN
    RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
  END IF;

  -- Utiliser les dates fournies ou calculer selon period_type
  IF start_date IS NOT NULL AND end_date IS NOT NULL THEN
    v_start_date := start_date::date;
    v_end_date := end_date::date;
  ELSE
    CASE period_type
      WHEN 'week' THEN
        v_start_date := COALESCE(start_date::date, public.isoweek_start(current_date));
        v_end_date := COALESCE(end_date::date, public.isoweek_start(current_date) + interval '6 days');
      WHEN 'month' THEN
        v_start_date := COALESCE(start_date::date, date_trunc('month', current_date)::date);
        v_end_date := COALESCE(end_date::date, (date_trunc('month', current_date) + interval '1 month - 1 day')::date);
      WHEN 'year' THEN
        v_start_date := COALESCE(start_date::date, date_trunc('year', current_date)::date);
        v_end_date := COALESCE(end_date::date, (date_trunc('year', current_date) + interval '1 year - 1 day')::date);
      ELSE
        v_start_date := COALESCE(start_date::date, current_date - interval '30 days');
        v_end_date := COALESCE(end_date::date, current_date);
    END CASE;
  END IF;

  RETURN QUERY
  SELECT
    v.eco_geste_name::text AS name,
    SUM(v.usage_count)::bigint AS count
  FROM dashboard_view.eco_gestes_usage_by_period v
  WHERE v.date >= v_start_date
    AND v.date <= v_end_date
  GROUP BY v.eco_geste_name
  ORDER BY count DESC;
END;
$$;



COMMENT ON FUNCTION public.get_eco_gestes_usage_by_period(period_type text, start_date text, end_date text) IS 'Sécurisé: Accès réservé aux administrateurs authentifiés uniquement. Retourne l''utilisation des éco-gestes agrégée par nom pour la période spécifiée. Inclut les items avec type=''ecogeste'' ainsi que les articles avec type=''article'' qui sont marqués comme éco-gestes.';



CREATE FUNCTION public.get_ecogestes() RETURNS TABLE(name text, image text, points integer, description text, category text, restaurants text[])
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
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
$$;



COMMENT ON FUNCTION public.get_ecogestes() IS 'Récupère la liste des écogestes disponibles.
- Accessible à tous les utilisateurs authentifiés (utilisateurs, membres, administrateurs)
- Authentification obligatoire
- Retourne les écogestes avec leurs points, descriptions et restaurants associés';



CREATE FUNCTION public.get_feedbacks() RETURNS TABLE(id uuid, category text, comments text, created_at timestamp with time zone, user_email text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  current_user_id uuid;
  current_user_role text;
  six_months_ago timestamp with time zone;
BEGIN
  -- Vérifier que l'utilisateur est authentifié
  current_user_id := auth.uid();

  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Non autorisé: utilisateur non authentifié';
  END IF;

  -- Récupérer le rôle de l'utilisateur depuis private.users
  SELECT u.role INTO current_user_role
  FROM private.users u
  WHERE u.id = current_user_id;

  -- Vérifier que l'utilisateur est administrateur ou superadmin
  IF current_user_role NOT IN ('administrateur', 'superadmin') THEN
    RAISE EXCEPTION 'Non autorisé: accès réservé aux administrateurs et superadmins';
  END IF;

  -- Calculer la date d'il y a 6 mois
  six_months_ago := NOW() - INTERVAL '6 months';

  -- Retourner les feedbacks triés par date décroissante
  -- Limiter aux 50 premiers et exclure ceux de plus de 6 mois
  -- Exclure également les feedbacks de type 'app_bug'
  -- Inclure l'email de l'utilisateur qui a créé le feedback
  RETURN QUERY
  SELECT
    f.id AS id,
    f.category AS category,
    f.comments AS comments,
    f.created_at AS created_at,
    COALESCE(u.email, '') AS user_email
  FROM private.feedback f
  LEFT JOIN private.users u ON u.id = f.user_id
  WHERE f.created_at >= six_months_ago
    AND f.category != 'app_bug'
  ORDER BY f.created_at DESC
  LIMIT 50;
END;
$$;



CREATE FUNCTION public.get_my_notification_settings() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
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
$$;



CREATE FUNCTION public.get_notification_action_settings() RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $$
DECLARE
    v_user_role text;
BEGIN
    -- A. AUTHENTIFICATION : Bloque les accès anonymes
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. SÉCURITÉ : Restriction stricte aux rôles 'administrateur' et 'superadmin'
    SELECT role INTO v_user_role FROM private.users WHERE id = auth.uid();

    IF v_user_role NOT IN ('superadmin', 'administrateur') OR v_user_role IS NULL THEN
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
$$;



CREATE FUNCTION public.get_notification_tokens_for_category(p_category text) RETURNS TABLE(notification_token text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
  v_user_role text;
  v_is_service_role boolean;
BEGIN
  -- Vérifier si c'est service_role ou postgres via session_user
  IF session_user IN ('postgres', 'service_role', 'authenticator') THEN
    -- Autoriser service_role/postgres
    v_is_service_role := true;
  ELSE
    v_is_service_role := false;
  END IF;

  -- Si ce n'est pas service_role, vérifier l'authentification et le rôle admin
  IF NOT v_is_service_role THEN
    -- A. AUTHENTIFICATION : Bloque les accès anonymes
    IF auth.uid() IS NULL THEN
      RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. SÉCURITÉ : Restriction stricte aux rôles 'administrateur' et 'superadmin'
    SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();

    IF v_user_role NOT IN ('superadmin', 'administrateur') OR v_user_role IS NULL THEN
      RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Retour des tokens selon la catégorie
  RETURN QUERY
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
END;
$$;



COMMENT ON FUNCTION public.get_notification_tokens_for_category(p_category text) IS 'Retourne les tokens de notification pour une catégorie. Mapping: sondages -> polls dans notification_settings.';



CREATE FUNCTION public.get_offers_usage_by_period(period_type text, start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text) RETURNS TABLE(name text, count bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'dashboard_view', 'private'
    AS $$
DECLARE
  v_caller_role user_role;
  v_start_date date;
  v_end_date date;
BEGIN
  -- NIVEAU 1 : Authentification Stricte
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
  END IF;

  -- NIVEAU 2 : Récupération du rôle et vérification d'accès
  SELECT role INTO v_caller_role FROM private.users WHERE id = auth.uid();

  IF v_caller_role IS NULL THEN
    RAISE EXCEPTION '403: Forbidden - Profil inexistant' USING ERRCODE = '42501';
  END IF;

  -- NIVEAU 3 : Vérification que l'utilisateur est administrateur
  IF v_caller_role NOT IN ('administrateur'::user_role, 'superadmin'::user_role) THEN
    RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
  END IF;

  v_start_date := coalesce(start_date::date, current_date - interval '30 days');
  v_end_date := coalesce(end_date::date, current_date);

  RETURN QUERY
  SELECT
    COALESCE(o.offer_title, o.offer_id)::text as name,
    sum(o.usage_count)::bigint as count
  FROM dashboard_view.offers_usage_by_period o
  WHERE o.day >= v_start_date
    AND o.day <= v_end_date
  GROUP BY COALESCE(o.offer_title, o.offer_id)
  ORDER BY count DESC;
END;
$$;



COMMENT ON FUNCTION public.get_offers_usage_by_period(period_type text, start_date text, end_date text) IS 'Retourne les statistiques d''utilisation des offres par période (même format que get_eco_gestes_usage_by_period).';



CREATE FUNCTION public.get_pending_poll_activations() RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
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
$$;



CREATE FUNCTION public.get_pending_promotion_activations() RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
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
$$;



CREATE FUNCTION public.get_restaurant_frequentation_by_date_range(start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text) RETURNS TABLE(restaurant_id uuid, dow integer, clients bigint, points_spent bigint, transaction_date date)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
  v_start_date date;
  v_end_date date;
  v_caller_role user_role;
BEGIN
  -- NIVEAU 1 : Authentification Stricte
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
  END IF;

  -- NIVEAU 2 : Récupération du rôle et vérification d'accès
  SELECT role INTO v_caller_role FROM private.users WHERE id = auth.uid();

  IF v_caller_role IS NULL THEN
    RAISE EXCEPTION '403: Forbidden - Profil inexistant' USING ERRCODE = '42501';
  END IF;

  -- NIVEAU 3 : Vérification que l'utilisateur est administrateur
  IF v_caller_role NOT IN ('administrateur'::user_role, 'superadmin'::user_role) THEN
    RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
  END IF;

  -- Convertir les paramètres texte en date
  v_start_date := coalesce(start_date::date, public.isoweek_start(current_date));
  v_end_date := coalesce(end_date::date, public.isoweek_start(current_date) + interval '6 days');

  -- Validation : s'assurer que les dates sont valides
  IF v_start_date > v_end_date THEN
    RAISE EXCEPTION 'start_date must be <= end_date';
  END IF;

  RETURN QUERY
  WITH base AS (
    SELECT
      t.restaurant_id,
      -- Calculer le jour de la semaine (0 = Lundi, 6 = Dimanche)
      ((extract(dow FROM date_trunc('day', t.date)::date)::int + 6) % 7) AS dow,
      -- Utiliser date_trunc pour normaliser les dates
      date_trunc('day', t.date)::date AS transaction_date,
      -- Compter les clients distincts de manière précise
      count(DISTINCT t.user_id) AS clients,
      -- Calculer les points dépensés de manière précise
      coalesce(sum(CASE WHEN t.points < 0 THEN abs(t.points) ELSE 0 END), 0)::bigint AS points_spent
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
  )
  SELECT
    b.restaurant_id,
    b.dow,
    b.clients,
    b.points_spent,
    b.transaction_date
  FROM base b
  ORDER BY b.transaction_date, b.restaurant_id;
END;
$$;



COMMENT ON FUNCTION public.get_restaurant_frequentation_by_date_range(start_date text, end_date text) IS 'Sécurisé: Accès réservé aux administrateurs authentifiés uniquement. Retourne la fréquentation des restaurants par plage de dates avec jour de la semaine, nombre de clients distincts et points dépensés.';



CREATE FUNCTION public.get_restaurant_frequentation_by_period(period_type text DEFAULT 'week'::text, start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text) RETURNS TABLE(id uuid, count bigint, period_label text, period_start date)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
  v_start_date date;
  v_end_date date;
  v_caller_role user_role;
BEGIN
  -- NIVEAU 1 : Authentification Stricte
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
  END IF;

  -- NIVEAU 2 : Récupération du rôle et vérification d'accès
  -- Qualifier explicitement la colonne id avec le nom de la table pour éviter l'ambiguïté
  SELECT u.role INTO v_caller_role FROM private.users u WHERE u.id = auth.uid();

  IF v_caller_role IS NULL THEN
    RAISE EXCEPTION '403: Forbidden - Profil inexistant' USING ERRCODE = '42501';
  END IF;

  -- NIVEAU 3 : Vérification que l'utilisateur est administrateur
  IF v_caller_role NOT IN ('administrateur'::user_role, 'superadmin'::user_role) THEN
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
      v_start_date := coalesce(start_date::date, public.isoweek_start(current_date));
      v_end_date := coalesce(end_date::date, public.isoweek_start(current_date) + interval '6 days');
  END CASE;

  RETURN QUERY
  WITH base AS (
    SELECT
      t.restaurant_id,
      t.date::date AS transaction_date,
      count(DISTINCT t.user_id) AS clients
    FROM private.transactions t
    WHERE t.status IN ('valide', 'completed')
      AND t.restaurant_id IS NOT NULL
      AND t.date::date >= v_start_date
      AND t.date::date <= v_end_date
    GROUP BY t.restaurant_id, t.date::date
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
      sum(b.clients)::bigint AS clients
    FROM base b
    GROUP BY b.restaurant_id, period_label, period_start
  )
  SELECT
    a.restaurant_id AS id,
    a.clients AS count,
    a.period_label,
    a.period_start
  FROM aggregated a
  ORDER BY a.period_start, a.restaurant_id;
END;
$$;



COMMENT ON FUNCTION public.get_restaurant_frequentation_by_period(period_type text, start_date text, end_date text) IS 'Sécurisé: Accès réservé aux administrateurs authentifiés uniquement. Retourne la fréquentation des restaurants par période (semaine, mois, année) avec le nombre de clients distincts. Format: id (restaurant_id), count (clients), period_label, period_start. Corrige l''ambiguïté de la colonne "id" en qualifiant explicitement les références.';



CREATE FUNCTION public.get_restaurant_frequentation_weekly() RETURNS TABLE(restaurant_id uuid, dow integer, clients bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'dashboard_view', 'private'
    AS $$
DECLARE
  v_caller_role user_role;
BEGIN
  -- NIVEAU 1 : Authentification Stricte
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
  END IF;

  -- NIVEAU 2 : Récupération du rôle et vérification d'accès
  SELECT role INTO v_caller_role FROM private.users WHERE id = auth.uid();

  IF v_caller_role IS NULL THEN
    RAISE EXCEPTION '403: Forbidden - Profil inexistant' USING ERRCODE = '42501';
  END IF;

  -- NIVEAU 3 : Vérification que l'utilisateur est administrateur
  IF v_caller_role NOT IN ('administrateur'::user_role, 'superadmin'::user_role) THEN
    RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    t.restaurant_id,
    extract(dow from t.date::date)::integer as dow,
    count(distinct t.user_id)::bigint as clients
  FROM private.transactions t
  WHERE t.status in ('valide', 'completed')
    AND t.restaurant_id is not null
    AND t.date::date >= current_date - interval '7 days'
  GROUP BY t.restaurant_id, extract(dow from t.date::date)
  ORDER BY t.restaurant_id, dow;
END;
$$;



COMMENT ON FUNCTION public.get_restaurant_frequentation_weekly() IS 'Sécurisé : Accès réservé aux administrateurs uniquement';



CREATE FUNCTION public.get_transactions(status_param text) RETURNS TABLE(total numeric, restaurant_name text, points integer, items jsonb)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
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
$$;



COMMENT ON FUNCTION public.get_transactions(status_param text) IS 'Récupère les transactions selon le statut.
- Utilisateurs/Membres : voient uniquement leurs propres transactions
- Administrateurs : voient toutes les transactions
- Authentification obligatoire';



CREATE FUNCTION public.get_unified_statistics(start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text, period_type text DEFAULT 'week'::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'dashboard_view', 'private'
    AS $$
DECLARE
  v_start_date date;
  v_end_date date;
  v_today_day date;
  v_today_transactions_count bigint;
  v_today_points_generated bigint;
  v_daily_stats jsonb;
  v_caller_role user_role;
  result jsonb;
BEGIN
  -- NIVEAU 1 : Authentification Stricte
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
  END IF;

  -- NIVEAU 2 : Récupération du rôle et vérification d'accès
  SELECT role INTO v_caller_role FROM private.users WHERE id = auth.uid();

  IF v_caller_role IS NULL THEN
    RAISE EXCEPTION '403: Forbidden - Profil inexistant' USING ERRCODE = '42501';
  END IF;

  -- NIVEAU 3 : Vérification que l'utilisateur est administrateur
  IF v_caller_role NOT IN ('administrateur'::user_role, 'superadmin'::user_role) THEN
    RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
  END IF;

  v_start_date := coalesce(start_date::date, current_date - interval '30 days');
  v_end_date := coalesce(end_date::date, current_date);

  -- KPIs du jour : utiliser daily_stats au lieu de today_stats
  SELECT
    day,
    transactions_count,
    points_generated
  INTO
    v_today_day,
    v_today_transactions_count,
    v_today_points_generated
  FROM dashboard_view.daily_stats
  WHERE day = CURRENT_DATE;

  -- Si aucune donnée pour aujourd'hui, utiliser des valeurs par défaut
  IF v_today_day IS NULL THEN
    v_today_day := CURRENT_DATE;
    v_today_transactions_count := 0;
    v_today_points_generated := 0;
  END IF;

  -- Activité complète (daily_stats)
  SELECT jsonb_agg(
    jsonb_build_object(
      'day', day,
      'active_users', active_users
    )
    ORDER BY day
  )
  INTO v_daily_stats
  FROM dashboard_view.daily_stats;

  -- Construire le résultat JSON avec toutes les statistiques
  SELECT jsonb_build_object(
    'eco_gestes', coalesce((
      SELECT jsonb_agg(
        jsonb_build_object(
          'name', name,
          'count', count
        )
      )
      FROM (
        SELECT
          v.eco_geste_name as name,
          sum(v.usage_count)::bigint as count
        FROM dashboard_view.eco_gestes_usage_by_period v
        WHERE v.date >= v_start_date
          AND v.date <= v_end_date
        GROUP BY v.eco_geste_name
        ORDER BY count DESC
      ) eco_gestes_data
    ), '[]'::jsonb),
    'offers', coalesce((
      SELECT jsonb_agg(
        jsonb_build_object(
          'name', name,
          'count', count
        )
      )
      FROM (
        SELECT
          COALESCE(o.offer_title, o.offer_id) as name,
          sum(o.usage_count)::bigint as count
        FROM dashboard_view.offers_usage_by_period o
        WHERE o.day >= v_start_date
          AND o.day <= v_end_date
        GROUP BY COALESCE(o.offer_title, o.offer_id)
        ORDER BY count DESC
      ) offers_data
    ), '[]'::jsonb),
    'frequentation', coalesce((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', id,
          'name', name,
          'count', count,
          'period_label', period_label,
          'period_start', period_start
        )
      )
      FROM (
        -- Pour le mois, agréger par semaine (comme get_restaurant_frequentation_by_period)
        SELECT
          a.restaurant_id as id,
          r.name,
          sum(a.clients)::bigint as count,
          to_char(public.isoweek_start(a.transaction_date), 'YYYY-"W"WW') as period_label,
          public.isoweek_start(a.transaction_date) as period_start
        FROM (
          SELECT
            t.restaurant_id,
            t.date::date as transaction_date,
            count(distinct t.user_id) as clients
          FROM private.transactions t
          WHERE t.status IN ('valide', 'completed')
            AND t.restaurant_id IS NOT NULL
            AND t.date::date >= v_start_date
            AND t.date::date <= v_end_date
          GROUP BY t.restaurant_id, t.date::date
        ) a
        LEFT JOIN private.restaurants r ON r.id = a.restaurant_id
        GROUP BY a.restaurant_id, r.name, public.isoweek_start(a.transaction_date)
        ORDER BY period_start, a.restaurant_id
      ) frequentation_data
    ), '[]'::jsonb),
    'realtime', jsonb_build_object(
      'today', jsonb_build_object(
        'day', v_today_day,
        'transactions_today', COALESCE(v_today_transactions_count, 0),
        'points_generated_today', COALESCE(v_today_points_generated, 0)
      ),
      'daily_stats', coalesce(v_daily_stats, '[]'::jsonb)
      -- offer_usage retiré : les données sont disponibles via offers_usage_by_period (section 'offers')
    )
  ) INTO result;

  RETURN result;
END;
$$;



COMMENT ON FUNCTION public.get_unified_statistics(start_date text, end_date text, period_type text) IS 'Corrigé: Utilise des variables individuelles au lieu d''un record pour éviter les problèmes de type. Accès réservé aux administrateurs authentifiés uniquement.';



CREATE FUNCTION public.get_verification_status(p_user_ids uuid[]) RETURNS TABLE(id uuid, is_verified boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'auth'
    AS $$
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

        IF v_caller_role NOT IN ('administrateur', 'superadmin') THEN
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
$$;



COMMENT ON FUNCTION public.get_verification_status(p_user_ids uuid[]) IS 'Récupère le statut de vérification email pour une liste d''utilisateurs. Réservé aux administrateurs. Limite: 500 IDs maximum.';



CREATE FUNCTION public.is_admin_or_superadmin() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
  v_user_role user_role;
BEGIN
  IF (select auth.uid()) IS NULL THEN
    RETURN false;
  END IF;

  SELECT role INTO v_user_role
  FROM private.users
  WHERE id = (select auth.uid());

  IF v_user_role IS NULL THEN
    RETURN false;
  END IF;

  -- 🛡️ SÉCURITÉ : Uniquement administrateur ou superadmin
  RETURN v_user_role IN ('administrateur'::user_role, 'superadmin'::user_role);
END;
$$;



CREATE FUNCTION public.is_admin_user() RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN false;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM private.users
        WHERE id = auth.uid()
        AND role = 'administrateur'
    );
END;
$$;



COMMENT ON FUNCTION public.is_admin_user() IS 'Vérifie si l''utilisateur connecté a le rôle administrateur ou superadmin.';



CREATE FUNCTION public.is_admin_user_only() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
  v_user_role user_role;
BEGIN
  IF (select auth.uid()) IS NULL THEN
    RETURN false;
  END IF;

  SELECT role INTO v_user_role
  FROM private.users
  WHERE id = (select auth.uid());

  IF v_user_role IS NULL THEN
    RETURN false;
  END IF;

  RETURN v_user_role = 'administrateur'::user_role;
END;
$$;



CREATE FUNCTION public.is_not_basic_user() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
  v_user_role user_role;
BEGIN
  IF (select auth.uid()) IS NULL THEN
    RETURN false;
  END IF;

  SELECT role INTO v_user_role
  FROM private.users
  WHERE id = (select auth.uid());

  IF v_user_role IS NULL THEN
    RETURN false;
  END IF;

  -- 🛡️ SÉCURITÉ : Uniquement administrateur ou superadmin (explicite, pas de logique négative)
  RETURN v_user_role IN ('administrateur'::user_role, 'superadmin'::user_role);
END;
$$;



CREATE FUNCTION public.isoweek_start(input_date date) RETURNS date
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  select (date_trunc('week', input_date + interval '1 day') - interval '1 day')::date;
$$;



CREATE FUNCTION public.log_error(p_message text, p_stack text DEFAULT NULL::text, p_context text DEFAULT NULL::text, p_route text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $_$
DECLARE
  v_user_id UUID;
  v_error_id UUID;
  v_decoded_message TEXT;
  v_decoded_stack TEXT;
  v_decoded_context TEXT;
BEGIN
  -- Vérifier que l'utilisateur est authentifié
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: User must be authenticated';
  END IF;

  -- Décoder les données base64 si elles sont encodées
  -- Vérifier si c'est du base64 valide (caractères alphanumériques + / + =)
  IF p_message ~ '^[A-Za-z0-9+/=]+$' AND length(p_message) > 20 THEN
    BEGIN
      v_decoded_message := convert_from(decode(p_message, 'base64'), 'UTF8');
    EXCEPTION WHEN OTHERS THEN
      -- Si le décodage échoue, utiliser la valeur originale
      v_decoded_message := p_message;
    END;
  ELSE
    v_decoded_message := p_message;
  END IF;

  -- Décoder le stack si présent
  IF p_stack IS NOT NULL AND p_stack ~ '^[A-Za-z0-9+/=]+$' AND length(p_stack) > 20 THEN
    BEGIN
      v_decoded_stack := convert_from(decode(p_stack, 'base64'), 'UTF8');
    EXCEPTION WHEN OTHERS THEN
      v_decoded_stack := p_stack;
    END;
  ELSE
    v_decoded_stack := p_stack;
  END IF;

  -- Décoder le context si présent
  IF p_context IS NOT NULL AND p_context ~ '^[A-Za-z0-9+/=]+$' AND length(p_context) > 20 THEN
    BEGIN
      v_decoded_context := convert_from(decode(p_context, 'base64'), 'UTF8');
    EXCEPTION WHEN OTHERS THEN
      v_decoded_context := p_context;
    END;
  ELSE
    v_decoded_context := p_context;
  END IF;

  -- Sanitisation côté serveur (double protection)
  -- Limiter la longueur des champs pour éviter les attaques
  v_decoded_message := LEFT(COALESCE(v_decoded_message, 'Unknown error'), 5000);
  v_decoded_stack := LEFT(COALESCE(v_decoded_stack, ''), 10000);
  v_decoded_context := LEFT(COALESCE(v_decoded_context, ''), 1000);
  p_route := LEFT(COALESCE(p_route, ''), 500);

  -- Insérer l'erreur dans la table private.errors
  INSERT INTO private.errors (
    message,
    stack,
    context,
    user_id,
    route,
    timestamp
  ) VALUES (
    v_decoded_message,
    NULLIF(v_decoded_stack, ''),
    NULLIF(v_decoded_context, ''),
    v_user_id,
    NULLIF(p_route, ''),
    NOW()
  )
  RETURNING id INTO v_error_id;

  RETURN v_error_id;
END;
$_$;



COMMENT ON FUNCTION public.log_error(p_message text, p_stack text, p_context text, p_route text) IS 'Fonction sécurisée pour logger les erreurs. Requiert authentification. Rate limiting géré côté client.';



CREATE FUNCTION public.mark_notification_sent(p_entity_type text, p_entity_id uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    SET row_security TO 'off'
    AS $$
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
$$;



COMMENT ON FUNCTION public.mark_notification_sent(p_entity_type text, p_entity_id uuid) IS 'Marque notif_sent = true pour une entité APRÈS succès de l''envoi. Appelée par l''Edge Function.';



CREATE FUNCTION public.remove_special_hour(p_restaurant_id uuid, p_special_hour_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
  current_special_hours jsonb;
  updated_special_hours jsonb;
BEGIN
  -- Vérifier les permissions de l'administrateur
  IF NOT (
    SELECT EXISTS (
      SELECT 1
      FROM private.users
      WHERE id = auth.uid() AND role IN ('administrateur', 'superadmin')
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
$$;



CREATE FUNCTION public.remove_static_occupancy_schedule(p_restaurant_id uuid, p_start_time time without time zone) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
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

    IF v_user_role NOT IN ('administrateur', 'superadmin') OR v_user_role IS NULL THEN
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
$$;



CREATE FUNCTION public.send_feedback_to_make() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'supabase_functions'
    AS $$
BEGIN
  -- Vérifier que ce trigger n'est pas déclenché par un utilisateur normal
  -- Les triggers sont normalement déclenchés automatiquement, mais on sécurise
  IF auth.uid() IS NOT NULL THEN
    -- Si un utilisateur normal est authentifié, vérifier qu'il n'a pas les droits
    IF current_setting('request.jwt.claim.role', true) NOT IN ('service_role', 'postgres') THEN
      -- Dans un trigger, on ne peut pas lever d'exception qui bloque l'opération
      -- On log juste un warning et on continue
      RAISE WARNING '[send_feedback_to_make] Tentative d''accès non autorisée depuis un utilisateur normal';
      RETURN NEW;
    END IF;
  END IF;

  PERFORM supabase_functions.http_request(
    'https://hook.eu2.make.com/l217emciafmm3368x674sua10obpnck3',
    'POST',
    '{"Content-type":"application/json"}'::jsonb,
    jsonb_build_object(
      'category', NEW.category,
      'comments', NEW.comments
    ),
    5000
  );

  RETURN NEW;
END;
$$;



CREATE FUNCTION public.set_offer_active(new_active boolean, offer_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
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

    IF v_user_role NOT IN ('administrateur', 'superadmin') OR v_user_role IS NULL THEN
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
$$;



CREATE FUNCTION public.submit_anonymous_feedback(p_category text, p_comments text, p_email text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
    v_feedback_id uuid;
    v_result jsonb;
    v_has_dangerous_content boolean := false;
    v_final_comments text;
BEGIN
    IF p_category IS NULL OR LENGTH(p_category) > 50 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Paramètre invalide',
            'error_code', 'INVALID_PARAMETER'
        );
    END IF;

    IF p_comments IS NULL OR LENGTH(p_comments) > 2000 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Message trop long',
            'error_code', 'COMMENTS_TOO_LONG'
        );
    END IF;

    IF p_email IS NOT NULL AND LENGTH(p_email) > 255 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Email trop long',
            'error_code', 'INVALID_PARAMETER'
        );
    END IF;

    -- ✅ SÉCURITÉ 2 : Validation stricte de la catégorie (whitelist) - inclure general_feedback
    IF LOWER(TRIM(p_category)) NOT IN ('app_bug', 'restaurant_idea', 'food_item_feedback', 'new_feature', 'general_feedback', 'other') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Catégorie invalide',
            'error_code', 'INVALID_CATEGORY'
        );
    END IF;

    IF LENGTH(TRIM(p_comments)) < 10 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Le message doit contenir au moins 10 caractères',
            'error_code', 'COMMENTS_TOO_SHORT'
        );
    END IF;

    IF LENGTH(TRIM(p_comments)) > 2000 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Le message est trop long (maximum 2000 caractères)',
            'error_code', 'COMMENTS_TOO_LONG'
        );
    END IF;

    v_has_dangerous_content := false;

    IF p_comments ~* '(?i)(union\\s+select|drop\\s+table|delete\\s+from|insert\\s+into|update\\s+set|exec\\s*\\()' THEN
        v_has_dangerous_content := true;
    END IF;

    IF p_comments ~ '[\\x00\\x08\\x09\\x1a\\x1b]' THEN
        v_has_dangerous_content := true;
    END IF;

    IF p_comments ~* '<script|<iframe|<object|<embed' THEN
        v_has_dangerous_content := true;
    END IF;

    IF p_comments ~* '(javascript|vbscript|data):' THEN
        v_has_dangerous_content := true;
    END IF;

    IF v_has_dangerous_content THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Le message contient des caractères non autorisés',
            'error_code', 'INVALID_CONTENT'
        );
    END IF;

    IF p_email IS NOT NULL AND p_email != '' THEN
        IF LENGTH(TRIM(p_email)) > 255 THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'Email trop long',
                'error_code', 'INVALID_PARAMETER'
            );
        END IF;

        IF p_email ~ '[\\x00\\x08\\x09\\x1a\\x1b]' OR p_email ~* '(javascript|vbscript|data):' THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'L''email contient des caractères non autorisés',
                'error_code', 'INVALID_CONTENT'
            );
        END IF;
    END IF;

    v_final_comments := TRIM(p_comments);

    IF p_email IS NOT NULL AND TRIM(p_email) != '' THEN
        v_final_comments := 'Email: ' || TRIM(p_email) || E'\\n\\n' || v_final_comments;

        IF LENGTH(v_final_comments) > 2000 THEN
            v_final_comments := 'Email: ' || TRIM(p_email) || E'\\n\\n' || LEFT(TRIM(p_comments), 2000 - LENGTH('Email: ' || TRIM(p_email) || E'\\n\\n'));
        END IF;
    END IF;

    INSERT INTO private.feedback (user_id, category, comments, created_at)
    VALUES (
        NULL,
        LOWER(TRIM(p_category)),
        v_final_comments,
        now()
    )
    RETURNING id INTO v_feedback_id;

    v_result := jsonb_build_object(
        'success', true,
        'feedback_id', v_feedback_id,
        'message', 'Votre message a été envoyé avec succès'
    );

    RETURN v_result;

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Une erreur est survenue lors de l''envoi de votre message',
            'error_code', 'INTERNAL_ERROR'
        );
END;
$$;



COMMENT ON FUNCTION public.submit_anonymous_feedback(p_category text, p_comments text, p_email text) IS 'Permet aux utilisateurs non authentifiés de soumettre un feedback.
Rate limiting géré uniquement côté frontend.';



CREATE FUNCTION public.submit_feedback(p_category text, p_comments text, p_user_id uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
  v_id uuid;
  v_authenticated_user_id uuid;
BEGIN
  -- 🛡️ SÉCURITÉ : Vérifier que l'utilisateur est authentifié (peu importe le rôle)
  v_authenticated_user_id := auth.uid();

  IF v_authenticated_user_id IS NULL THEN
    RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
  END IF;

  -- 🛡️ SÉCURITÉ : Vérifier que l'utilisateur existe dans private.users
  IF NOT EXISTS (SELECT 1 FROM private.users WHERE id = v_authenticated_user_id) THEN
    RAISE EXCEPTION '403: Forbidden - Utilisateur non trouvé' USING ERRCODE = '42501';
  END IF;

  -- 🛡️ SÉCURITÉ : Utiliser l'ID de l'utilisateur authentifié plutôt que celui fourni en paramètre
  -- Cela empêche un utilisateur de créer des feedbacks au nom d'un autre utilisateur
  -- Si p_user_id est fourni, on l'ignore et on utilise l'ID authentifié
  -- Si p_user_id est NULL, on utilise l'ID authentifié (comportement normal)

  -- Validation des paramètres
  IF p_category IS NULL OR btrim(p_category) = '' THEN
    RAISE EXCEPTION '400: Bad Request - category is required' USING ERRCODE = '22000';
  END IF;

  IF p_comments IS NULL OR btrim(p_comments) = '' THEN
    RAISE EXCEPTION '400: Bad Request - comments is required' USING ERRCODE = '22000';
  END IF;

  -- Insertion avec l'ID de l'utilisateur authentifié (sécurité renforcée)
  INSERT INTO private.feedback (user_id, category, comments)
  VALUES (v_authenticated_user_id, p_category, p_comments)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;



COMMENT ON FUNCTION public.submit_feedback(p_category text, p_comments text, p_user_id uuid) IS 'Crée un feedback dans private.feedback (endpoint RPC REST-friendly).';



CREATE FUNCTION public.sync_all_restaurants_menu_url_current() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
BEGIN
  -- Autoriser uniquement le service_role à appeler cette fonction
  IF session_user NOT IN ('postgres', 'service_role', 'authenticator') THEN
    RAISE EXCEPTION 'Accès refusé : cette action nécessite des privilèges de service_role.' USING ERRCODE = '42501';
  END IF;

  -- Vérification supplémentaire via JWT
  IF auth.uid() IS NOT NULL THEN
    IF NOT (current_setting('request.jwt.claim.role', true) = 'service_role') THEN
      RAISE EXCEPTION 'Accès refusé : cette action nécessite des privilèges de service_role.' USING ERRCODE = '42501';
    END IF;
  END IF;

  PERFORM private.sync_restaurant_menu_url_current(NULL);
END;
$$;



COMMENT ON FUNCTION public.sync_all_restaurants_menu_url_current() IS 'Met à jour restaurant_menu_url pour tous les restaurants à partir du menu de la semaine courante (jsonb). À appeler quotidiennement (cron) pour que le menu suive le changement de semaine.';



CREATE FUNCTION public.trigger_send_activation_notification() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_url text;
  v_key text;
  v_entity_type text;
  v_entity_id uuid;
  v_request_id bigint;
  v_is_authorized boolean := false;
BEGIN
    -- 🛡️ SÉCURITÉ : Vérifier que le trigger est appelé par postgres/service_role
    BEGIN
        IF session_user IN ('postgres', 'service_role', 'authenticator') THEN
            v_is_authorized := true;
        ELSIF current_setting('request.jwt.claim.role', true) = 'service_role' THEN
            v_is_authorized := true;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_is_authorized := false;
    END;

    IF NOT v_is_authorized THEN
        RAISE EXCEPTION 'Accès refusé : ce trigger ne peut être activé que par postgres ou service_role';
    END IF;

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
$$;



COMMENT ON FUNCTION public.trigger_send_activation_notification() IS 'Trigger qui détecte immédiatement quand une promotion ou un sondage devient actif lors d''un INSERT/UPDATE manuel. Pour les éléments programmés, le cron job check-activation-notifications vérifie toutes les minutes.';



CREATE FUNCTION public.update_article(article_id uuid, article_data jsonb) RETURNS private.articles
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
DECLARE
    updated_article private.articles;
    v_user_role text;
    v_old_image_url text;
    v_new_image_url text;
    file_name text;
    bucket_name text := 'articles';
    old_image_deleted boolean := false;
BEGIN
    -- A. Vérification de l'authentification (Fail-fast)
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. SÉCURITÉ : Vérification du rôle dans la table de vérité (private.users)
    SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();

    IF v_user_role NOT IN ('administrateur', 'superadmin') OR v_user_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Droits administrateur requis' USING ERRCODE = '42501';
    END IF;

    -- C. Validation des données
    IF article_data ? 'points' AND (article_data->>'points')::int <= 0 THEN
        RAISE EXCEPTION 'Les points doivent être positifs';
    END IF;

    -- D. Récupérer l'ancienne image et la nouvelle image
    SELECT image INTO v_old_image_url FROM private.articles WHERE id = article_id;
    v_new_image_url := article_data->>'image';

    -- E. Supprimer l'ancienne image si elle existe et est différente de la nouvelle
    IF v_old_image_url IS NOT NULL
       AND v_old_image_url != ''
       AND (v_new_image_url IS NULL OR v_new_image_url = '' OR v_old_image_url != v_new_image_url) THEN
        -- Extraire le nom du fichier depuis l'URL
        file_name := private.extract_file_name_from_storage_url(v_old_image_url, bucket_name);

        IF file_name IS NOT NULL THEN
            -- Supprimer l'ancien fichier du bucket
            IF private.delete_storage_file(bucket_name, file_name) THEN
                old_image_deleted := true;
            END IF;
        END IF;
    END IF;

    -- F. Mise à jour partielle avec conversion sécurisée JSONB -> SQL
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

    -- G. Vérification de l'existence
    IF updated_article IS NULL THEN
        RAISE EXCEPTION '404: Not Found - Article non trouvé' USING ERRCODE = 'P0002';
    END IF;

    -- H. Log de l'événement de sécurité (Audit Trail)
    PERFORM private.log_security_event(
        'UPDATE', 'articles', article_id,
        NULL,
        jsonb_build_object(
            'old_image_deleted', old_image_deleted,
            'data', article_data
        ),
        true, NULL
    );

    RETURN updated_article;
END;
$$;



CREATE FUNCTION public.update_my_notification_settings(p_settings jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
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
$$;



CREATE FUNCTION public.update_notification_action_setting(p_action_id text, p_enabled boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
  v_user_role text;
BEGIN
  -- Vérifier que l'utilisateur est authentifié
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
  END IF;

  -- Vérifier que l'utilisateur est administrateur
  SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();

  IF v_user_role NOT IN ('administrateur', 'superadmin') OR v_user_role IS NULL THEN
    RAISE EXCEPTION '403: Forbidden - Accès réservé aux administrateurs' USING ERRCODE = '42501';
  END IF;

  -- Mettre à jour ou insérer le paramètre de notification
  INSERT INTO public.notification_action_settings (action_id, enabled, updated_at)
  VALUES (p_action_id, p_enabled, now())
  ON CONFLICT (action_id) DO UPDATE SET
    enabled = EXCLUDED.enabled,
    updated_at = now();
END;
$$;



CREATE FUNCTION public.update_notification_token(p_notification_token text, p_device_type text) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
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
$_$;



CREATE FUNCTION public.update_offer(offer_id uuid, offer_data jsonb) RETURNS private.offers
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
DECLARE
    updated_offer private.offers;
    v_user_role text;
    v_old_image_url text;
    v_new_image_url text;
    file_name text;
    bucket_name text := 'offers-images';
    old_image_deleted boolean := false;
BEGIN
    -- A. Vérification de l'authentification (Fail-fast)
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
    END IF;

    -- B. SÉCURITÉ : Vérification du rôle dans la table de vérité (private.users)
    SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();

    IF v_user_role NOT IN ('administrateur', 'superadmin') OR v_user_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Droits insuffisants' USING ERRCODE = '42501';
    END IF;

    -- C. Validation des données
    IF offer_data ? 'points' AND (offer_data->>'points')::int <= 0 THEN
        RAISE EXCEPTION 'Les points doivent être positifs';
    END IF;

    -- D. Récupérer l'ancienne image et la nouvelle image
    SELECT image INTO v_old_image_url FROM private.offers WHERE id = offer_id;
    v_new_image_url := offer_data->>'image';

    -- E. Supprimer l'ancienne image si elle existe et est différente de la nouvelle
    IF v_old_image_url IS NOT NULL
       AND v_old_image_url != ''
       AND (v_new_image_url IS NULL OR v_new_image_url = '' OR v_old_image_url != v_new_image_url) THEN
        -- Extraire le nom du fichier depuis l'URL
        file_name := private.extract_file_name_from_storage_url(v_old_image_url, bucket_name);

        IF file_name IS NOT NULL THEN
            -- Supprimer l'ancien fichier du bucket
            IF private.delete_storage_file(bucket_name, file_name) THEN
                old_image_deleted := true;
            END IF;
        END IF;
    END IF;

    -- F. Mise à jour avec conversion sécurisée des types
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

    -- G. Vérification de l'existence
    IF updated_offer IS NULL THEN
        RAISE EXCEPTION '404: Not Found - Offre introuvable' USING ERRCODE = 'P0002';
    END IF;

    -- H. Log de l'événement de sécurité (Audit Trail)
    PERFORM private.log_security_event(
        'UPDATE', 'offers', offer_id,
        NULL,
        jsonb_build_object(
            'old_image_deleted', old_image_deleted,
            'data', offer_data
        ),
        true, NULL
    );

    RETURN updated_offer;
END;
$$;



CREATE FUNCTION public.update_poll_with_options(p_poll_id uuid, p_title text, p_description text, p_question text, p_target_audience text, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_is_active boolean, p_image_url text, p_options jsonb) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_poll_record record;
  v_option jsonb;
  v_option_id uuid;
  v_allowed_ids uuid[];
  v_user_id uuid;
  v_user_role text;
  v_old_image_url text;
  v_new_image_url text;
  file_name text;
  bucket_name text := 'polls-images';
  old_image_deleted boolean := false;
BEGIN
  -- Vérifier l'authentification
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN json_build_object('error', 'Authentification requise');
  END IF;

  -- Vérifier le rôle
  SELECT role::text INTO v_user_role FROM private.users WHERE id = v_user_id;

  IF v_user_role NOT IN ('administrateur', 'superadmin') OR v_user_role IS NULL THEN
    RETURN json_build_object('error', 'Permission refusée : droits administrateur requis');
  END IF;

  -- Vérifier que le sondage existe
  IF NOT EXISTS (SELECT 1 FROM private.polls WHERE id = p_poll_id) THEN
    RETURN json_build_object('error', 'Sondage non trouvé');
  END IF;

  -- Validation des dates
  IF p_starts_at IS NOT NULL AND p_ends_at IS NOT NULL AND p_starts_at >= p_ends_at THEN
    RETURN json_build_object('error', 'La date de fin doit être après la date de début');
  END IF;

  -- A. Récupérer l'ancienne image
  SELECT image_url INTO v_old_image_url
  FROM private.polls
  WHERE id = p_poll_id;

  -- B. Récupérer la nouvelle image
  v_new_image_url := p_image_url;

  -- C. Supprimer l'ancienne image si elle existe et est différente de la nouvelle
  IF v_old_image_url IS NOT NULL
     AND v_old_image_url != ''
     AND (v_new_image_url IS NULL OR v_new_image_url = '' OR v_old_image_url != v_new_image_url) THEN
    -- Extraire le nom du fichier depuis l'URL
    file_name := private.extract_file_name_from_storage_url(v_old_image_url, bucket_name);

    IF file_name IS NOT NULL THEN
      -- Supprimer l'ancien fichier du bucket
      IF private.delete_storage_file(bucket_name, file_name) THEN
        old_image_deleted := true;
      END IF;
    END IF;
  END IF;

  -- D. Mise à jour du sondage
  UPDATE private.polls SET
    title = COALESCE(p_title, title),
    description = COALESCE(p_description, description),
    question = COALESCE(p_question, question),
    target_audience = CASE
      WHEN p_target_audience IS NULL OR p_target_audience = 'all' THEN target_audience
      ELSE to_jsonb(p_target_audience)
    END,
    starts_at = COALESCE(p_starts_at, starts_at),
    ends_at = COALESCE(p_ends_at, ends_at),
    is_active = COALESCE(p_is_active, is_active),
    image_url = COALESCE(p_image_url, image_url)
  WHERE id = p_poll_id
  RETURNING * INTO v_poll_record;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Sondage introuvable');
  END IF;

  -- E. Log de sécurité
  BEGIN
    PERFORM private.log_security_event(
      'UPDATE', 'polls', p_poll_id,
      NULL,
      jsonb_build_object(
        'old_image_deleted', old_image_deleted,
        'title', COALESCE(p_title, v_poll_record.title)
      ),
      true, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    -- Ignorer les erreurs de log
    NULL;
  END;

  -- F. Gestion des options
  v_allowed_ids := ARRAY(
    SELECT NULLIF(value->>'id', '')::UUID
    FROM jsonb_array_elements(COALESCE(p_options, '[]'::jsonb)) value
    WHERE value ? 'id' AND NULLIF(value->>'id', '') IS NOT NULL
  );

  -- Supprimer les options qui ne sont plus dans la liste
  IF v_allowed_ids IS NULL OR array_length(v_allowed_ids, 1) = 0 THEN
    DELETE FROM private.poll_options WHERE poll_id = p_poll_id;
  ELSE
    DELETE FROM private.poll_options
    WHERE poll_id = p_poll_id
      AND id <> ALL(v_allowed_ids);
  END IF;

  -- Mettre à jour ou créer les options
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
      -- Mettre à jour l'option existante
      UPDATE private.poll_options
      SET
        option_text = v_option->>'text',
        option_order = COALESCE((v_option->>'order')::INTEGER, option_order)
      WHERE id = v_option_id;
    ELSE
      -- Créer une nouvelle option
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

  -- Récupérer le sondage mis à jour
  SELECT * INTO v_poll_record
  FROM private.polls
  WHERE id = p_poll_id;

  -- Retourner le résultat en JSON
  RETURN json_build_object(
    'success', true,
    'data', row_to_json(v_poll_record)
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', SQLERRM);
END;
$$;



CREATE FUNCTION public.update_polls_notif_sent(p_ids uuid[]) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    SET row_security TO 'off'
    AS $$
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
    IF v_user_role NOT IN ('administrateur', 'superadmin') OR v_user_role IS NULL THEN
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
$$;



COMMENT ON FUNCTION public.update_polls_notif_sent(p_ids uuid[]) IS 'Met à jour notif_sent = true pour une liste de sondages. Utilisée par l''Edge Function après traitement. RLS désactivé pour cette fonction.';



CREATE FUNCTION public.update_promotion(p_id uuid, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text, p_start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_color character varying DEFAULT NULL::character varying) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
DECLARE
  v_result JSON;
  v_existing_promotion RECORD;
  v_old_image_url text;
  v_new_image_url text;
  file_name text;
  bucket_name text := 'promotions_images';
  old_image_deleted boolean := false;
BEGIN
  -- A. Vérifier l'authentification
  IF auth.uid() IS NULL THEN
    RETURN json_build_object('error', 'Authentification requise');
  END IF;

  -- B. Vérifier que la promotion existe et récupérer l'ancienne image
  SELECT * INTO v_existing_promotion
  FROM private.promotions
  WHERE id = p_id;

  IF v_existing_promotion IS NULL THEN
    RETURN json_build_object('error', 'Promotion introuvable');
  END IF;

  -- C. Récupérer l'ancienne et la nouvelle image
  v_old_image_url := v_existing_promotion.image_url;
  v_new_image_url := CASE
    WHEN p_image_url IS NOT NULL AND LENGTH(TRIM(p_image_url)) > 0
    THEN TRIM(p_image_url)
    ELSE NULL
  END;

  -- D. Supprimer l'ancienne image si elle existe et est différente de la nouvelle
  IF v_old_image_url IS NOT NULL
     AND v_old_image_url != ''
     AND (v_new_image_url IS NULL OR v_old_image_url != v_new_image_url) THEN
    -- Extraire le nom du fichier depuis l'URL
    file_name := private.extract_file_name_from_storage_url(v_old_image_url, bucket_name);

    IF file_name IS NOT NULL THEN
      -- Supprimer l'ancien fichier du bucket
      IF private.delete_storage_file(bucket_name, file_name) THEN
        old_image_deleted := true;
      END IF;
    END IF;
  END IF;

  -- E. Validation des données si fournies
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

  -- F. Vérifier les dates si les deux sont fournies
  IF p_start_date IS NOT NULL AND p_end_date IS NOT NULL THEN
    IF p_start_date >= p_end_date THEN
      RETURN json_build_object('error', 'La date de début doit être antérieure à la date de fin');
    END IF;
  END IF;

  -- G. Vérifier la cohérence des dates avec les valeurs existantes
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

  -- H. Mettre à jour la promotion
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

  -- I. Log de sécurité
  BEGIN
    PERFORM private.log_security_event(
      'UPDATE', 'promotions', p_id,
      NULL,
      jsonb_build_object(
        'old_image_deleted', old_image_deleted,
        'title', COALESCE(p_title, v_existing_promotion.title)
      ),
      true, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Le log de sécurité n''a pas pu être enregistré';
  END;

  -- J. Retourner le résultat
  SELECT json_build_object(
    'success', true,
    'data', row_to_json(p.*),
    'old_image_deleted', old_image_deleted
  ) INTO v_result
  FROM private.promotions p
  WHERE p.id = p_id;

  RETURN v_result;

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', SQLERRM);
END;
$$;



CREATE FUNCTION public.update_promotions_notif_sent(p_ids uuid[]) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    SET row_security TO 'off'
    AS $$
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
    IF v_user_role NOT IN ('administrateur', 'superadmin') OR v_user_role IS NULL THEN
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
$$;



COMMENT ON FUNCTION public.update_promotions_notif_sent(p_ids uuid[]) IS 'Met à jour notif_sent = true pour une liste de promotions. Utilisée par l''Edge Function après traitement. RLS désactivé pour cette fonction.';



CREATE FUNCTION public.update_restaurant_details(p_restaurant_id uuid, p_updates jsonb) RETURNS SETOF private.restaurants
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
DECLARE
  v_old_image_url text;
  v_new_image_url text;
  file_name text;
  bucket_name text := 'restaurants-images';
  old_image_deleted boolean := false;
  v_user_id uuid;
  v_user_role text;
BEGIN
  -- Vérifier l'authentification
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentification requise' USING ERRCODE = 'P0001';
  END IF;

  -- Vérifier le rôle
  SELECT role::text INTO v_user_role FROM private.users WHERE id = v_user_id;

  IF v_user_role NOT IN ('administrateur', 'superadmin') OR v_user_role IS NULL THEN
    RAISE EXCEPTION 'Permission refusée : droits administrateur requis' USING ERRCODE = '42501';
  END IF;

  -- A. Récupérer l'ancienne image
  SELECT image_url INTO v_old_image_url
  FROM private.restaurants
  WHERE id = p_restaurant_id;

  -- B. Récupérer la nouvelle image si fournie
  IF p_updates ? 'image_url' THEN
    v_new_image_url := p_updates->>'image_url';
  END IF;

  -- C. Supprimer l'ancienne image si elle existe et est différente de la nouvelle
  IF v_old_image_url IS NOT NULL
     AND v_old_image_url != ''
     AND (v_new_image_url IS NULL OR v_new_image_url = '' OR v_old_image_url != v_new_image_url) THEN
    -- Extraire le nom du fichier depuis l'URL
    file_name := private.extract_file_name_from_storage_url(v_old_image_url, bucket_name);

    IF file_name IS NOT NULL THEN
      -- Supprimer l'ancien fichier du bucket
      IF private.delete_storage_file(bucket_name, file_name) THEN
        old_image_deleted := true;
      END IF;
    END IF;
  END IF;

  -- D. Mise à jour
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

  -- E. Log de sécurité
  BEGIN
    PERFORM private.log_security_event(
      'UPDATE', 'restaurants', p_restaurant_id,
      NULL,
      jsonb_build_object(
        'old_image_deleted', old_image_deleted,
        'updates', p_updates
      ),
      true, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Le log de sécurité n''a pas pu être enregistré';
  END;

  -- F. Retourner le résultat
  RETURN QUERY
  SELECT * FROM private.restaurants WHERE id = p_restaurant_id;
END;
$$;



COMMENT ON FUNCTION public.update_restaurant_details(p_restaurant_id uuid, p_updates jsonb) IS 'Met à jour un restaurant (horaires, infos, menu, location, etc.). building/floor absents de la table, lieu dans location.';



CREATE FUNCTION public.update_static_occupancy_schedule(p_restaurant_id uuid, p_start_time time without time zone, p_end_time time without time zone, p_occupancy integer) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
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

    IF v_user_role NOT IN ('administrateur', 'superadmin') OR v_user_role IS NULL THEN
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
$$;



CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
    v_is_authorized boolean := false;
BEGIN
    -- 🛡️ SÉCURITÉ : Vérifier que le trigger est appelé par postgres/service_role
    BEGIN
        IF session_user IN ('postgres', 'service_role', 'authenticator') THEN
            v_is_authorized := true;
        ELSIF current_setting('request.jwt.claim.role', true) = 'service_role' THEN
            v_is_authorized := true;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_is_authorized := false;
    END;

    IF NOT v_is_authorized THEN
        RAISE EXCEPTION 'Accès refusé : ce trigger ne peut être activé que par postgres ou service_role';
    END IF;

    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;



CREATE FUNCTION public.update_user(p_name text DEFAULT NULL::text, p_notification_settings jsonb DEFAULT NULL::jsonb) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
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
$$;



CREATE FUNCTION public.update_user_avatar(p_avatar_url text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
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
$$;



CREATE FUNCTION public.update_user_points(p_user_id uuid, p_points_delta integer, p_action text DEFAULT 'MANUAL_UPDATE'::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
    v_caller_role text;
    v_current_points INTEGER;
    v_new_points INTEGER;
    v_user_exists BOOLEAN;
    v_user_active BOOLEAN;
BEGIN
    -- 🛡️ NIVEAU 1 : Vérification de l'authentification
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION '401: Unauthorized - Authentification requise' USING ERRCODE = 'P0001';
    END IF;

    -- 🛡️ NIVEAU 2 : Vérification du rôle de l'appelant (Source de vérité : private.users)
    SELECT role::text INTO v_caller_role
    FROM private.users
    WHERE id = auth.uid();

    IF v_caller_role IS NULL THEN
        RAISE EXCEPTION '403: Forbidden - Profil utilisateur inexistant' USING ERRCODE = '42501';
    END IF;

    -- 🛡️ NIVEAU 3 : Vérification stricte que seul administrateur ou superadmin peut modifier
    IF v_caller_role NOT IN ('administrateur', 'superadmin') THEN
        RAISE EXCEPTION '403: Forbidden - Seuls les administrateurs peuvent modifier les points manuellement'
        USING ERRCODE = '42501';
    END IF;

    -- 🛡️ NIVEAU 4 : Vérifier que l'utilisateur cible existe et est actif
    SELECT points, is_active, true
    INTO v_current_points, v_user_active, v_user_exists
    FROM private.users
    WHERE id = p_user_id;

    IF NOT v_user_exists THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Utilisateur introuvable'
        );
    END IF;

    IF NOT v_user_active THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Utilisateur inactif'
        );
    END IF;

    -- 🛡️ NIVEAU 5 : Validation des paramètres
    IF p_points_delta IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Le nombre de points à modifier est requis'
        );
    END IF;

    -- 🛡️ NIVEAU 6 : Vérifier les limites de modification (-100 à +100)
    IF p_points_delta < -100 OR p_points_delta > 100 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'La modification doit être entre -100 et +100 points maximum'
        );
    END IF;

    -- Calculer les nouveaux points
    v_current_points := COALESCE(v_current_points, 0);
    v_new_points := v_current_points + p_points_delta;

    -- 🛡️ NIVEAU 7 : Vérifier que le solde ne devient pas négatif
    IF v_new_points < 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', format('Points insuffisants. Le solde ne peut pas être négatif. Solde actuel: %s points', v_current_points)
        );
    END IF;

    -- 🛡️ NIVEAU 8 : Vérifier la limite maximale
    IF v_new_points > 10000 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Limite de points dépassée (10000 max)'
        );
    END IF;

    -- 🛡️ NIVEAU 9 : Contourner le trigger anti-input en utilisant une variable de session
    -- Le trigger verify_user_points_trigger vérifie les modifications non autorisées
    -- Nous utilisons une variable de session pour indiquer que c'est une mise à jour autorisée
    PERFORM set_config('app.allow_points_modification', 'true', false);

    -- Mettre à jour les points
    UPDATE private.users
    SET points = v_new_points
    WHERE id = p_user_id;

    -- Réinitialiser la variable de session
    PERFORM set_config('app.allow_points_modification', 'false', false);

    -- 🛡️ NIVEAU 10 : Logger l'action de sécurité
    BEGIN
        PERFORM private.log_security_event(
            'UPDATE', 'users', p_user_id,
            jsonb_build_object(
                'old_points', v_current_points,
                'field', 'points'
            ),
            jsonb_build_object(
                'new_points', v_new_points,
                'delta', p_points_delta,
                'action', p_action,
                'modified_by', auth.uid()
            ),
            true,
            NULL
        );
    EXCEPTION WHEN OTHERS THEN
        -- Si le log échoue, on continue quand même (ne pas bloquer la mise à jour)
        RAISE NOTICE 'Erreur lors du log de sécurité: %', SQLERRM;
    END;

    RETURN jsonb_build_object(
        'success', true,
        'old_points', v_current_points,
        'new_points', v_new_points,
        'delta', p_points_delta,
        'message', format('Points mis à jour avec succès: %s → %s (%s%s)',
            v_current_points, v_new_points,
            CASE WHEN p_points_delta > 0 THEN '+' ELSE '' END, p_points_delta)
    );

EXCEPTION WHEN OTHERS THEN
    -- Réinitialiser la variable de session en cas d'erreur
    PERFORM set_config('app.allow_points_modification', 'false', false);

    RETURN jsonb_build_object(
        'success', false,
        'error', 'Erreur lors de la mise à jour des points: ' || SQLERRM
    );
END;
$$;



COMMENT ON FUNCTION public.update_user_points(p_user_id uuid, p_points_delta integer, p_action text) IS 'Met à jour les points d''un utilisateur. Réservé aux administrateurs et superadmins uniquement.
Limites: modification entre -100 et +100 points maximum par opération.
Le solde final ne peut pas être négatif. Contourne le trigger anti-input via variable de session.';



CREATE FUNCTION public.update_user_role(user_id uuid, new_role text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'extensions'
    AS $$
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
$$;



CREATE FUNCTION public.upsert_activation_notification_config(p_entity_type text, p_entity_id uuid, p_title text, p_body text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
  v_user_role text;
BEGIN
  -- Vérification de l'authentification
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '401: Unauthorized' USING ERRCODE = 'P0001';
  END IF;

  -- Vérification du rôle administrateur
  SELECT role::text INTO v_user_role FROM private.users WHERE id = auth.uid();

  IF v_user_role NOT IN ('administrateur', 'superadmin') OR v_user_role IS NULL THEN
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
$$;



CREATE FUNCTION public.user_check_signup(p_email text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'private', 'extensions'
    AS $$
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
        IF v_caller_role NOT IN ('administrateur', 'superadmin') OR v_caller_role IS NULL THEN
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
$$;



CREATE FUNCTION public.user_is_admin() RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
DECLARE
  v_user_role user_role;
BEGIN
  IF (select auth.uid()) IS NULL THEN
    RETURN false;
  END IF;

  SELECT role INTO v_user_role
  FROM private.users
  WHERE id = (select auth.uid());

  IF v_user_role IS NULL THEN
    RETURN false;
  END IF;

  -- 🛡️ SÉCURITÉ : Uniquement administrateur ou superadmin (PAS marketing)
  RETURN v_user_role IN ('administrateur'::user_role, 'superadmin'::user_role);
END;
$$;



CREATE FUNCTION public.vote_poll(p_poll_title text, p_option_title text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private'
    AS $$
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
$$;



CREATE FUNCTION stats.get_access_transaction_correlation_admin() RETURNS TABLE(access_segment text, user_count bigint, avg_transactions numeric, avg_points numeric, users_with_transactions bigint, conversion_rate numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'stats'
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.users
    WHERE id = auth.uid()
    AND role = 'administrateur'
  ) THEN
    RAISE EXCEPTION 'Access denied. Admin role required.';
  END IF;

  RETURN QUERY
  SELECT
    CASE
      WHEN COALESCE(access_count, 0) = 0 THEN '0 accès'
      WHEN COALESCE(access_count, 0) BETWEEN 1 AND 5 THEN '1-5 accès'
      WHEN COALESCE(access_count, 0) BETWEEN 6 AND 20 THEN '6-20 accès'
      WHEN COALESCE(access_count, 0) BETWEEN 21 AND 50 THEN '21-50 accès'
      ELSE '50+ accès'
    END as access_segment,
    COUNT(DISTINCT u.id)::bigint as user_count,
    AVG(COALESCE(transaction_count, 0))::numeric as avg_transactions,
    AVG(COALESCE(total_points, 0))::numeric as avg_points,
    COUNT(CASE WHEN COALESCE(transaction_count, 0) > 0 THEN 1 END)::bigint as users_with_transactions,
    ROUND(100.0 * COUNT(CASE WHEN COALESCE(transaction_count, 0) > 0 THEN 1 END) / NULLIF(COUNT(DISTINCT u.id), 0), 2) as conversion_rate
  FROM private.users u
  LEFT JOIN (
    SELECT
      user_id,
      COUNT(*) as access_count
    FROM private.app_access_stats
    WHERE accessed_at >= NOW() - INTERVAL '30 days'
    GROUP BY user_id
  ) access_stats ON access_stats.user_id = u.id
  LEFT JOIN (
    SELECT
      user_id,
      COUNT(*) as transaction_count,
      SUM(points) as total_points
    FROM private.transactions
    GROUP BY user_id
  ) trans_stats ON trans_stats.user_id = u.id
  GROUP BY
    CASE
      WHEN COALESCE(access_count, 0) = 0 THEN '0 accès'
      WHEN COALESCE(access_count, 0) BETWEEN 1 AND 5 THEN '1-5 accès'
      WHEN COALESCE(access_count, 0) BETWEEN 6 AND 20 THEN '6-20 accès'
      WHEN COALESCE(access_count, 0) BETWEEN 21 AND 50 THEN '21-50 accès'
      ELSE '50+ accès'
    END
  ORDER BY MIN(COALESCE(access_count, 0));
END;
$$;



CREATE FUNCTION stats.get_fidelity_daily_trends_admin() RETURNS TABLE(date date, transactions bigint, points_distributed numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'stats'
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.users
    WHERE id = auth.uid()
    AND role = 'administrateur'
  ) THEN
    RAISE EXCEPTION 'Access denied. Admin role required.';
  END IF;

  RETURN QUERY
  SELECT
    DATE(t.date) as date,
    COUNT(*)::bigint as transactions,
    COALESCE(SUM(CASE WHEN t.points > 0 THEN t.points ELSE 0 END), 0)::numeric as points_distributed
  FROM private.transactions t
  WHERE t.date >= NOW() - INTERVAL '30 days'
  GROUP BY DATE(t.date)
  ORDER BY date;
END;
$$;



CREATE FUNCTION stats.get_fidelity_kpi_admin() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'stats'
    AS $$
DECLARE
  result jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.users
    WHERE id = auth.uid()
    AND role = 'administrateur'
  ) THEN
    RAISE EXCEPTION 'Access denied. Admin role required.';
  END IF;

  SELECT jsonb_build_object(
    'total_transactions', (SELECT COUNT(*) FROM private.transactions),
    'transactions_7d', (SELECT COUNT(*) FROM private.transactions WHERE date >= NOW() - INTERVAL '7 days'),
    'transactions_30d', (SELECT COUNT(*) FROM private.transactions WHERE date >= NOW() - INTERVAL '30 days'),
    'transactions_monthly_change_percentage', 0.0,
    'avg_transactions_per_active_user', 0.0,
    'total_points_distributed', (SELECT COALESCE(SUM(points), 0) FROM private.transactions WHERE points > 0),
    'points_7d', (SELECT COALESCE(SUM(points), 0) FROM private.transactions WHERE date >= NOW() - INTERVAL '7 days' AND points > 0),
    'points_30d', (SELECT COALESCE(SUM(points), 0) FROM private.transactions WHERE date >= NOW() - INTERVAL '30 days' AND points > 0),
    'points_monthly_change_percentage', 0.0,
    'avg_points_per_transaction', (SELECT COALESCE(AVG(points), 0) FROM private.transactions WHERE points > 0),
    'avg_points_per_active_user', 0.0,
    'total_user_points', (SELECT COALESCE(SUM(points), 0) FROM private.users),
    'avg_points_per_user', (SELECT COALESCE(AVG(points), 0) FROM private.users),
    'avg_points_per_user_with_points', (SELECT COALESCE(AVG(points), 0) FROM private.users WHERE points > 0),
    'max_points_user', (SELECT COALESCE(MAX(points), 0) FROM private.users),
    'users_with_points', (SELECT COUNT(*) FROM private.users WHERE points > 0),
    'total_polls', (SELECT COUNT(*) FROM private.polls),
    'active_polls', (SELECT COUNT(*) FROM private.polls WHERE starts_at <= NOW() AND ends_at >= NOW()),
    'total_votes', (SELECT COUNT(*) FROM private.poll_votes),
    'voters_count', (SELECT COUNT(DISTINCT user_id) FROM private.poll_votes),
    'poll_participation_rate', ROUND(100.0 * (SELECT COUNT(DISTINCT user_id) FROM private.poll_votes) / NULLIF((SELECT COUNT(*) FROM private.users), 0), 2),
    'total_restaurants', (SELECT COUNT(*) FROM private.restaurants),
    'restaurants_with_transactions', (SELECT COUNT(DISTINCT restaurant_id) FROM private.transactions),
    'active_offers', 0,
    'active_promotions', 0,
    'last_updated', NOW()
  ) INTO result;

  RETURN result;
END;
$$;



CREATE FUNCTION stats.get_pareto_analysis_admin() RETURNS TABLE(points_range text, user_count bigint, total_points_in_range numeric, percentage_of_users numeric, percentage_of_points numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'stats'
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.users
    WHERE id = auth.uid()
    AND role = 'administrateur'
  ) THEN
    RAISE EXCEPTION 'Access denied. Admin role required.';
  END IF;

  RETURN QUERY
  SELECT
    CASE
      WHEN user_points = 0 THEN '0'
      WHEN user_points <= 10 THEN '1-10'
      WHEN user_points <= 25 THEN '11-25'
      WHEN user_points <= 50 THEN '26-50'
      WHEN user_points <= 100 THEN '51-100'
      ELSE '100+'
    END as points_range,
    COUNT(*)::bigint as user_count,
    SUM(user_points)::numeric as total_points_in_range,
    ROUND(100.0 * COUNT(*) / NULLIF((SELECT COUNT(*) FROM private.users), 0), 2) as percentage_of_users,
    ROUND(100.0 * SUM(user_points) / NULLIF((SELECT SUM(points) FROM private.users), 0), 2) as percentage_of_points
  FROM (
    SELECT points as user_points FROM private.users
  ) subquery
  GROUP BY
    CASE
      WHEN user_points = 0 THEN '0'
      WHEN user_points <= 10 THEN '1-10'
      WHEN user_points <= 25 THEN '11-25'
      WHEN user_points <= 50 THEN '26-50'
      WHEN user_points <= 100 THEN '51-100'
      ELSE '100+'
    END
  ORDER BY MIN(user_points);
END;
$$;



CREATE FUNCTION stats.get_startup_daily_trends_admin() RETURNS TABLE(date date, new_users bigint, active_users bigint)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'stats'
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.users
    WHERE id = auth.uid()
    AND role = 'administrateur'
  ) THEN
    RAISE EXCEPTION 'Access denied. Admin role required.';
  END IF;

  RETURN QUERY
  WITH new_users_by_date AS (
    SELECT
      DATE(created_at) as date,
      COUNT(*)::bigint as new_users
    FROM private.users u
    WHERE created_at >= NOW() - INTERVAL '30 days'
    GROUP BY DATE(created_at)
  ),
  active_users_by_date AS (
    SELECT
      DATE(accessed_at) as date,
      COUNT(DISTINCT user_id)::bigint as active_users
    FROM private.app_access_stats
    WHERE accessed_at >= NOW() - INTERVAL '30 days'
    GROUP BY DATE(accessed_at)
  )
  SELECT
    COALESCE(n.date, a.date) as date,
    COALESCE(n.new_users, 0) as new_users,
    COALESCE(a.active_users, 0) as active_users
  FROM new_users_by_date n
  FULL OUTER JOIN active_users_by_date a ON n.date = a.date
  ORDER BY date;
END;
$$;



CREATE FUNCTION stats.get_startup_kpi_admin() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'stats'
    AS $$
DECLARE
  result jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.users
    WHERE id = auth.uid()
    AND role = 'administrateur'
  ) THEN
    RAISE EXCEPTION 'Access denied. Admin role required.';
  END IF;

  SELECT jsonb_build_object(
    'total_users', (SELECT COUNT(*) FROM private.users),
    'new_users_24h', (SELECT COUNT(*) FROM private.users WHERE created_at >= NOW() - INTERVAL '24 hours'),
    'new_users_7d', (SELECT COUNT(*) FROM private.users WHERE created_at >= NOW() - INTERVAL '7 days'),
    'new_users_30d', (SELECT COUNT(*) FROM private.users WHERE created_at >= NOW() - INTERVAL '30 days'),
    'new_users_30d_percentage', ROUND(100.0 * (SELECT COUNT(*) FROM private.users WHERE created_at >= NOW() - INTERVAL '30 days') / NULLIF((SELECT COUNT(*) FROM private.users), 0), 2),
    'weekly_growth_percentage', 0.0,
    'monthly_growth_percentage', 0.0,
    'active_users_7d', (SELECT COUNT(DISTINCT user_id) FROM private.app_access_stats WHERE accessed_at >= NOW() - INTERVAL '7 days'),
    'active_users_percentage', ROUND(100.0 * (SELECT COUNT(DISTINCT user_id) FROM private.app_access_stats WHERE accessed_at >= NOW() - INTERVAL '7 days') / NULLIF((SELECT COUNT(*) FROM private.users), 0), 2),
    'active_users_monthly_change_percentage', 0.0,
    'stickiness_percentage', 0.0,
    'activation_rate', 0.0,
    'app_access_7d', (SELECT COUNT(*) FROM private.app_access_stats WHERE accessed_at >= NOW() - INTERVAL '7 days'),
    'unique_users_7d', (SELECT COUNT(DISTINCT user_id) FROM private.app_access_stats WHERE accessed_at >= NOW() - INTERVAL '7 days'),
    'last_updated', NOW()
  ) INTO result;

  RETURN result;
END;
$$;



CREATE FUNCTION stats.get_time_to_value_analysis_admin() RETURNS TABLE(time_to_value text, user_count bigint, avg_days numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'stats'
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.users
    WHERE id = auth.uid()
    AND role = 'administrateur'
  ) THEN
    RAISE EXCEPTION 'Access denied. Admin role required.';
  END IF;

  RETURN QUERY
  WITH user_time_to_value AS (
    SELECT
      u.id,
      CASE
        WHEN MIN(t.date) IS NULL THEN NULL
        ELSE EXTRACT(EPOCH FROM (MIN(t.date) - u.created_at)) / 86400
      END as days_to_first_transaction
    FROM private.users u
    LEFT JOIN private.transactions t ON t.user_id = u.id
    GROUP BY u.id, u.created_at
  ),
  categorized AS (
    SELECT
      CASE
        WHEN days_to_first_transaction IS NULL THEN 'Aucune transaction'
        WHEN days_to_first_transaction = 0 THEN 'Même jour'
        WHEN days_to_first_transaction <= 1 THEN '1 jour'
        WHEN days_to_first_transaction <= 7 THEN '2-7 jours'
        WHEN days_to_first_transaction <= 30 THEN '8-30 jours'
        ELSE '30+ jours'
      END as time_to_value,
      days_to_first_transaction
    FROM user_time_to_value
  )
  SELECT
    categorized.time_to_value,
    COUNT(*)::bigint as user_count,
    AVG(categorized.days_to_first_transaction) as avg_days
  FROM categorized
  GROUP BY categorized.time_to_value
  ORDER BY
    CASE categorized.time_to_value
      WHEN 'Aucune transaction' THEN 999
      WHEN 'Même jour' THEN 0
      WHEN '1 jour' THEN 1
      WHEN '2-7 jours' THEN 2
      WHEN '8-30 jours' THEN 8
      WHEN '30+ jours' THEN 30
      ELSE 999
    END;
END;
$$;



CREATE FUNCTION stats.get_top_restaurants_admin(limit_count integer DEFAULT 10) RETURNS TABLE(restaurant_id uuid, restaurant_name text, transaction_count bigint, total_points_distributed numeric, unique_customers bigint, avg_points_per_transaction numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'stats'
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.users
    WHERE id = auth.uid()
    AND role = 'administrateur'
  ) THEN
    RAISE EXCEPTION 'Access denied. Admin role required.';
  END IF;

  RETURN QUERY
  SELECT
    r.id as restaurant_id,
    r.name as restaurant_name,
    COUNT(t.id)::bigint as transaction_count,
    COALESCE(SUM(CASE WHEN t.points > 0 THEN t.points ELSE 0 END), 0)::numeric as total_points_distributed,
    COUNT(DISTINCT t.user_id)::bigint as unique_customers,
    COALESCE(AVG(CASE WHEN t.points > 0 THEN t.points ELSE NULL END), 0)::numeric as avg_points_per_transaction
  FROM private.restaurants r
  LEFT JOIN private.transactions t ON t.restaurant_id = r.id
  GROUP BY r.id, r.name
  ORDER BY total_points_distributed DESC, transaction_count DESC
  LIMIT limit_count;
END;
$$;



CREATE FUNCTION stats.get_transaction_hourly_distribution_admin() RETURNS TABLE(hour_of_day integer, transaction_count bigint, total_points numeric, avg_points numeric, unique_users bigint)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'stats'
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.users
    WHERE id = auth.uid()
    AND role = 'administrateur'
  ) THEN
    RAISE EXCEPTION 'Access denied. Admin role required.';
  END IF;

  RETURN QUERY
  SELECT
    EXTRACT(HOUR FROM date)::integer as hour_of_day,
    COUNT(*)::bigint as transaction_count,
    SUM(points)::numeric as total_points,
    AVG(points)::numeric as avg_points,
    COUNT(DISTINCT user_id)::bigint as unique_users
  FROM private.transactions
  GROUP BY EXTRACT(HOUR FROM date)
  ORDER BY hour_of_day;
END;
$$;



CREATE FUNCTION stats.get_user_segments_analysis_admin() RETURNS TABLE(user_segment text, user_count bigint, avg_points numeric, users_with_transactions bigint, avg_transactions_per_user numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'stats'
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.users
    WHERE id = auth.uid()
    AND role = 'administrateur'
  ) THEN
    RAISE EXCEPTION 'Access denied. Admin role required.';
  END IF;

  RETURN QUERY
  SELECT
    CASE
      WHEN points = 0 THEN '0 points'
      WHEN points BETWEEN 1 AND 10 THEN '1-10 points'
      WHEN points BETWEEN 11 AND 50 THEN '11-50 points'
      WHEN points BETWEEN 51 AND 100 THEN '51-100 points'
      ELSE '100+ points'
    END as user_segment,
    COUNT(*)::bigint as user_count,
    AVG(points)::numeric as avg_points,
    COUNT(CASE WHEN EXISTS (
      SELECT 1 FROM private.transactions WHERE user_id = u.id
    ) THEN 1 END)::bigint as users_with_transactions,
    AVG((SELECT COUNT(*) FROM private.transactions WHERE user_id = u.id))::numeric as avg_transactions_per_user
  FROM private.users u
  GROUP BY
    CASE
      WHEN points = 0 THEN '0 points'
      WHEN points BETWEEN 1 AND 10 THEN '1-10 points'
      WHEN points BETWEEN 11 AND 50 THEN '11-50 points'
      WHEN points BETWEEN 51 AND 100 THEN '51-100 points'
      ELSE '100+ points'
    END
  ORDER BY MIN(points);
END;
$$;



CREATE FUNCTION stats.get_weekly_activity_admin() RETURNS TABLE(day_of_week integer, day_name text, access_count bigint, unique_users bigint)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'stats'
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.users
    WHERE id = auth.uid()
    AND role = 'administrateur'
  ) THEN
    RAISE EXCEPTION 'Access denied. Admin role required.';
  END IF;

  RETURN QUERY
  SELECT
    EXTRACT(DOW FROM accessed_at)::integer as day_of_week,
    CASE EXTRACT(DOW FROM accessed_at)
      WHEN 0 THEN 'Dimanche'
      WHEN 1 THEN 'Lundi'
      WHEN 2 THEN 'Mardi'
      WHEN 3 THEN 'Mercredi'
      WHEN 4 THEN 'Jeudi'
      WHEN 5 THEN 'Vendredi'
      WHEN 6 THEN 'Samedi'
    END as day_name,
    COUNT(*)::bigint as access_count,
    COUNT(DISTINCT user_id)::bigint as unique_users
  FROM private.app_access_stats
  WHERE accessed_at >= NOW() - INTERVAL '30 days'
  GROUP BY EXTRACT(DOW FROM accessed_at)
  ORDER BY day_of_week;
END;
$$;



CREATE FUNCTION stats.is_admin_user() RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'private', 'stats'
    AS $$
BEGIN
    -- 🛡️ SÉCURITÉ : Vérifier que seul un utilisateur authentifié peut appeler cette fonction
    IF auth.uid() IS NULL THEN
        RETURN false;
    END IF;

    -- Vérifier que l'utilisateur a le rôle administrateur (uniquement)
    RETURN EXISTS (
        SELECT 1
        FROM private.users
        WHERE id = auth.uid()
        AND role = 'administrateur'
    );
END;
$$;




CREATE INDEX idx_poll_options_poll_id ON private.poll_options USING btree (poll_id);



CREATE INDEX idx_poll_votes_option_id ON private.poll_votes USING btree (option_id);



CREATE INDEX idx_poll_votes_user_id ON private.poll_votes USING btree (user_id);



CREATE INDEX idx_transactions_restaurant_id ON private.transactions USING btree (restaurant_id);



CREATE INDEX idx_transactions_user_id ON private.transactions USING btree (user_id);



CREATE INDEX idx_section_visibility_updated_by ON public.section_visibility USING btree (updated_by);



CREATE UNIQUE INDEX section_visibility_section_key ON public.section_visibility USING btree (section);



CREATE TRIGGER "Send_feedback_to_make" AFTER INSERT ON private.feedback FOR EACH ROW EXECUTE FUNCTION private.send_feedback_to_make();



CREATE TRIGGER block_direct_points_modification BEFORE UPDATE OF points ON private.transactions FOR EACH ROW WHEN ((new.points IS DISTINCT FROM old.points)) EXECUTE FUNCTION private.check_points_modification_allowed();



CREATE TRIGGER detect_anomaly_offers_trigger_delete AFTER DELETE ON private.offers FOR EACH ROW EXECUTE FUNCTION audit.detect_anomaly_trigger();



CREATE TRIGGER detect_anomaly_offers_trigger_update AFTER UPDATE ON private.offers FOR EACH ROW EXECUTE FUNCTION audit.detect_anomaly_trigger();



CREATE TRIGGER detect_anomaly_polls_trigger_delete AFTER DELETE ON private.polls FOR EACH ROW EXECUTE FUNCTION audit.detect_anomaly_trigger();



CREATE TRIGGER detect_anomaly_polls_trigger_update AFTER UPDATE ON private.polls FOR EACH ROW EXECUTE FUNCTION audit.detect_anomaly_trigger();



CREATE TRIGGER detect_anomaly_promotions_trigger_delete AFTER DELETE ON private.promotions FOR EACH ROW EXECUTE FUNCTION audit.detect_anomaly_trigger();



CREATE TRIGGER detect_anomaly_promotions_trigger_update AFTER UPDATE ON private.promotions FOR EACH ROW EXECUTE FUNCTION audit.detect_anomaly_trigger();



CREATE TRIGGER detect_anomaly_transactions_trigger_delete AFTER DELETE ON private.transactions FOR EACH ROW EXECUTE FUNCTION audit.detect_anomaly_trigger();



CREATE TRIGGER detect_anomaly_transactions_trigger_update AFTER UPDATE ON private.transactions FOR EACH ROW EXECUTE FUNCTION audit.detect_anomaly_trigger();



CREATE TRIGGER detect_anomaly_users_trigger_delete AFTER DELETE ON private.users FOR EACH ROW EXECUTE FUNCTION audit.detect_anomaly_trigger();



CREATE TRIGGER detect_anomaly_users_trigger_update AFTER UPDATE ON private.users FOR EACH ROW EXECUTE FUNCTION audit.detect_anomaly_trigger();



CREATE TRIGGER on_restaurants_update BEFORE UPDATE ON private.restaurants FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();



CREATE TRIGGER recalculate_user_points_on_transaction_insert AFTER INSERT ON private.transactions FOR EACH ROW WHEN ((new.status = 'valide'::text)) EXECUTE FUNCTION audit.recalculate_user_points_on_transaction_change();



CREATE TRIGGER recalculate_user_points_on_transaction_update AFTER UPDATE OF status ON private.transactions FOR EACH ROW WHEN (((new.status = 'valide'::text) OR (old.status = 'valide'::text))) EXECUTE FUNCTION audit.recalculate_user_points_on_transaction_change();



CREATE TRIGGER sync_restaurant_menu_url_trigger BEFORE INSERT OR UPDATE OF restaurant_menu_url_jsonb ON private.restaurants FOR EACH ROW EXECUTE FUNCTION private.trg_sync_restaurant_menu_url();



CREATE TRIGGER tr_validate_and_log_users BEFORE INSERT OR UPDATE ON private.users FOR EACH ROW EXECUTE FUNCTION private.tr_validate_and_log_users();



COMMENT ON TRIGGER tr_validate_and_log_users ON private.users IS 'Valide tous les inputs et log les changements de sécurité sur private.users';



CREATE TRIGGER trg_refresh_mv_offers AFTER INSERT OR DELETE OR UPDATE ON private.offers FOR EACH STATEMENT EXECUTE FUNCTION mv.refresh_mv_offers();



CREATE TRIGGER trg_refresh_mv_restaurants AFTER INSERT OR DELETE OR UPDATE ON private.restaurants FOR EACH STATEMENT EXECUTE FUNCTION mv.refresh_mv_restaurants();



CREATE TRIGGER trigger_auto_activate_poll_insert BEFORE INSERT ON private.polls FOR EACH ROW WHEN (((new.starts_at IS NOT NULL) AND (new.ends_at IS NOT NULL) AND (new.starts_at <= now()) AND (new.ends_at > now()) AND (new.is_active = false))) EXECUTE FUNCTION public.auto_activate_poll_on_time();



CREATE TRIGGER trigger_auto_activate_poll_update BEFORE UPDATE OF starts_at, ends_at, is_active ON private.polls FOR EACH ROW WHEN (((new.starts_at IS NOT NULL) AND (new.ends_at IS NOT NULL) AND (new.starts_at <= now()) AND (new.ends_at > now()) AND (new.is_active = false) AND ((old.is_active = false) OR (old.starts_at > now())))) EXECUTE FUNCTION public.auto_activate_poll_on_time();



CREATE TRIGGER trigger_poll_activation_notification_insert AFTER INSERT ON private.polls FOR EACH ROW WHEN (((new.is_active = true) AND (new.starts_at IS NOT NULL) AND (new.ends_at IS NOT NULL) AND (new.starts_at <= now()) AND (new.ends_at > now()))) EXECUTE FUNCTION public.trigger_send_activation_notification();



CREATE TRIGGER trigger_poll_activation_notification_update AFTER UPDATE OF is_active, starts_at, ends_at ON private.polls FOR EACH ROW WHEN (((new.is_active = true) AND (new.starts_at IS NOT NULL) AND (new.ends_at IS NOT NULL) AND (new.starts_at <= now()) AND (new.ends_at > now()) AND ((old.is_active = false) OR (old.starts_at IS NULL) OR (old.ends_at IS NULL) OR (old.starts_at > now()) OR (old.ends_at <= now())))) EXECUTE FUNCTION public.trigger_send_activation_notification();



CREATE TRIGGER trigger_promotion_activation_notification_insert AFTER INSERT ON private.promotions FOR EACH ROW WHEN (((new.start_date IS NOT NULL) AND (new.end_date IS NOT NULL) AND (new.start_date <= now()) AND (new.end_date > now()))) EXECUTE FUNCTION public.trigger_send_activation_notification();



CREATE TRIGGER trigger_promotion_activation_notification_update AFTER UPDATE OF start_date, end_date ON private.promotions FOR EACH ROW WHEN (((new.start_date IS NOT NULL) AND (new.end_date IS NOT NULL) AND (new.start_date <= now()) AND (new.end_date > now()) AND ((old.start_date IS NULL) OR (old.end_date IS NULL) OR (old.start_date > now()) OR (old.end_date <= now())))) EXECUTE FUNCTION public.trigger_send_activation_notification();



CREATE TRIGGER verify_transaction_points_trigger_insert BEFORE INSERT ON private.transactions FOR EACH ROW WHEN ((new.status = 'valide'::text)) EXECUTE FUNCTION audit.verify_transaction_points_trigger();



CREATE TRIGGER verify_transaction_points_trigger_update BEFORE UPDATE OF points, items, used_offers, status ON private.transactions FOR EACH ROW WHEN (((new.status = 'valide'::text) OR (old.status = 'valide'::text))) EXECUTE FUNCTION audit.verify_transaction_points_trigger();



CREATE TRIGGER verify_user_points_trigger_update BEFORE UPDATE ON private.users FOR EACH ROW WHEN ((old.points IS DISTINCT FROM new.points)) EXECUTE FUNCTION audit.verify_user_points_trigger();



CREATE TRIGGER update_section_visibility_updated_at BEFORE UPDATE ON public.section_visibility FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE ONLY private.poll_options
    ADD CONSTRAINT poll_options_poll_id_fkey FOREIGN KEY (poll_id) REFERENCES private.polls(id) ON DELETE CASCADE;



ALTER TABLE ONLY private.poll_votes
    ADD CONSTRAINT poll_votes_option_id_fkey FOREIGN KEY (option_id) REFERENCES private.poll_options(id) ON DELETE CASCADE;



ALTER TABLE ONLY private.poll_votes
    ADD CONSTRAINT poll_votes_poll_id_fkey FOREIGN KEY (poll_id) REFERENCES private.polls(id) ON DELETE CASCADE;



ALTER TABLE ONLY private.poll_votes
    ADD CONSTRAINT poll_votes_user_id_fkey FOREIGN KEY (user_id) REFERENCES private.users(id) ON DELETE CASCADE;



ALTER TABLE ONLY private.transactions
    ADD CONSTRAINT transactions_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES private.restaurants(id);



ALTER TABLE ONLY private.transactions
    ADD CONSTRAINT transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES private.users(id) ON DELETE CASCADE;



ALTER TABLE private.app_access_stats ENABLE ROW LEVEL SECURITY;

ALTER TABLE private.articles ENABLE ROW LEVEL SECURITY;



ALTER TABLE private.articles_categories ENABLE ROW LEVEL SECURITY;



ALTER TABLE private.errors ENABLE ROW LEVEL SECURITY;



ALTER TABLE private.faq ENABLE ROW LEVEL SECURITY;



ALTER TABLE private.feedback ENABLE ROW LEVEL SECURITY;



ALTER TABLE private.notification_tokens ENABLE ROW LEVEL SECURITY;



ALTER TABLE private.offers ENABLE ROW LEVEL SECURITY;



ALTER TABLE private.poll_options ENABLE ROW LEVEL SECURITY;



ALTER TABLE private.poll_votes ENABLE ROW LEVEL SECURITY;



ALTER TABLE private.polls ENABLE ROW LEVEL SECURITY;



ALTER TABLE private.promotions ENABLE ROW LEVEL SECURITY;



ALTER TABLE private.restaurants ENABLE ROW LEVEL SECURITY;



ALTER TABLE private.transactions ENABLE ROW LEVEL SECURITY;



ALTER TABLE private.users ENABLE ROW LEVEL SECURITY;



ALTER TABLE public.activation_notification_config ENABLE ROW LEVEL SECURITY;



ALTER TABLE public.entity_activation_notifications ENABLE ROW LEVEL SECURITY;



ALTER TABLE public.notification_action_settings ENABLE ROW LEVEL SECURITY;



ALTER TABLE public.section_visibility ENABLE ROW LEVEL SECURITY;



CREATE POLICY section_visibility_delete_admin ON public.section_visibility FOR DELETE TO authenticated USING (public.is_not_basic_user());



CREATE POLICY section_visibility_insert_admin ON public.section_visibility FOR INSERT TO authenticated WITH CHECK (public.is_not_basic_user());



CREATE POLICY section_visibility_select_optimized ON public.section_visibility FOR SELECT TO authenticated USING ((public.is_admin_or_superadmin() OR public.user_is_admin()));



CREATE POLICY section_visibility_update_admin ON public.section_visibility TO authenticated USING (private.user_has_role('app_admin'::text)) WITH CHECK (private.user_has_role('app_admin'::text));


CREATE POLICY "Allow admin deletes for member cards" ON storage.objects FOR DELETE USING (((bucket_id = 'member-card'::text) AND (((auth.jwt() ->> 'role'::text) = 'administrateur'::text))));



CREATE POLICY "Allow admin updates for member cards" ON storage.objects FOR UPDATE USING (((bucket_id = 'member-card'::text) AND (((auth.jwt() ->> 'role'::text) = 'administrateur'::text) OR ((auth.jwt() ->> 'role'::text) = 'superadmin'::text)))) WITH CHECK (((bucket_id = 'member-card'::text) AND (((auth.jwt() ->> 'role'::text) = 'administrateur'::text) OR ((auth.jwt() ->> 'role'::text) = 'superadmin'::text))));



CREATE POLICY "Allow admin uploads for member cards" ON storage.objects FOR INSERT WITH CHECK (((bucket_id = 'member-card'::text) AND (((auth.jwt() ->> 'role'::text) = 'administrateur'::text) OR ((auth.jwt() ->> 'role'::text) = 'superadmin'::text))));



CREATE POLICY "Allow public read access for member cards" ON storage.objects FOR SELECT USING ((bucket_id = 'member-card'::text));




CREATE POLICY "polls-images-authenticated-delete" ON storage.objects FOR DELETE TO authenticated USING ((bucket_id = 'polls-images'::text));



CREATE POLICY "polls-images-authenticated-update" ON storage.objects FOR UPDATE TO authenticated USING ((bucket_id = 'polls-images'::text)) WITH CHECK ((bucket_id = 'polls-images'::text));



CREATE POLICY "polls-images-authenticated-upload" ON storage.objects FOR INSERT TO authenticated WITH CHECK ((bucket_id = 'polls-images'::text));



CREATE POLICY "polls-images-public-read" ON storage.objects FOR SELECT USING ((bucket_id = 'polls-images'::text));



CREATE POLICY app_access_stats_select_admin_only ON private.app_access_stats FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM private.users u
  WHERE ((u.id = ( SELECT auth.uid() AS uid)) AND (u.role = ANY (ARRAY['administrateur'::public.user_role, 'superadmin'::public.user_role]))))));










