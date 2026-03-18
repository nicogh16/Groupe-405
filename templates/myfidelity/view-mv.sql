

CREATE MATERIALIZED VIEW mv.mv_offers AS
 SELECT title,
    description,
    image,
    points,
    is_premium,
    ( SELECT jsonb_agg(r.name) AS jsonb_agg
           FROM private.restaurants r
          WHERE (r.id = ANY (o.restaurant_ids))) AS restaurant_names
   FROM private.offers o
  WHERE ((is_active = true) AND ((expiry_date IS NULL) OR (expiry_date > now())))
  ORDER BY points
  WITH NO DATA;



CREATE MATERIALIZED VIEW mv.mv_restaurants AS
 WITH today_schedule AS (
         SELECT r.name,
            r.image_url,
            r.location,
            r.restaurant_menu_url,
            r.is_new,
            r.boosted,
            r.schedule,
            r.special_hours,
            r.categories,
            r.status,
            (((EXTRACT(dow FROM CURRENT_DATE))::integer + 6) % 7) AS today_idx,
            special_today.value AS special_today
           FROM (private.restaurants r
             LEFT JOIN LATERAL ( SELECT element.value
                   FROM jsonb_array_elements(COALESCE(r.special_hours, '[]'::jsonb)) element(value)
                  WHERE ((element.value ->> 'date'::text) = to_char((CURRENT_DATE)::timestamp with time zone, 'YYYY-MM-DD'::text))
                 LIMIT 1) special_today ON (true))
        )
 SELECT name,
    image_url,
    location AS text,
    restaurant_menu_url,
    special_hours,
    categories,
    status,
    boosted,
    is_new,
        CASE
            WHEN (special_today IS NOT NULL) THEN NULLIF(lower((special_today ->> 'open'::text)), 'close'::text)
            ELSE NULLIF(lower(((schedule -> today_idx) ->> 'open'::text)), 'close'::text)
        END AS today_open,
        CASE
            WHEN (special_today IS NOT NULL) THEN NULLIF(lower((special_today ->> 'close'::text)), 'close'::text)
            ELSE NULLIF(lower(((schedule -> today_idx) ->> 'close'::text)), 'close'::text)
        END AS today_close
   FROM today_schedule ts
  ORDER BY
        CASE
            WHEN boosted THEN 0
            WHEN is_new THEN 1
            ELSE 2
        END, name
  WITH NO DATA;



CREATE MATERIALIZED VIEW public.mv_faq AS
 SELECT question,
    answer,
    language,
    category
   FROM private.faq
  WITH NO DATA;



COMMENT ON MATERIALIZED VIEW public.mv_faq IS 'Vue matérialisée FAQ - Accès réservé aux utilisateurs authentifiés uniquement. L''accès anon a été révoqué pour des raisons de sécurité.';



CREATE VIEW dashboard_view.promotions WITH (security_invoker='on') AS
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
   FROM private.promotions p;



COMMENT ON VIEW dashboard_view.promotions IS 'Vue des promotions avec statut calculé';



CREATE VIEW stats.fidelity_daily_trends AS
 WITH date_series AS (
         SELECT (generate_series(date_trunc('day'::text, (now() - '30 days'::interval)), date_trunc('day'::text, now()), '1 day'::interval))::date AS date
        ), daily_transactions AS (
         SELECT date(transactions.date) AS transaction_date,
            count(*) AS transactions,
            COALESCE(sum(transactions.points), (0)::bigint) AS points_distributed
           FROM private.transactions
          WHERE ((transactions.date >= (now() - '30 days'::interval)) AND (transactions.status = 'valide'::text))
          GROUP BY (date(transactions.date))
        )
 SELECT ds.date,
    COALESCE(dt.transactions, (0)::bigint) AS transactions,
    COALESCE(dt.points_distributed, (0)::bigint) AS points_distributed
   FROM (date_series ds
     LEFT JOIN daily_transactions dt ON ((ds.date = dt.transaction_date)))
  ORDER BY ds.date DESC;



COMMENT ON VIEW stats.fidelity_daily_trends IS 'Tendances quotidiennes de fidélité (transactions et points) sur 30 jours. Accessible uniquement aux rôles postgres et service_role.';



CREATE VIEW stats.fidelity_kpi_dashboard AS
 WITH transaction_stats AS (
         SELECT count(*) AS total_transactions,
            count(
                CASE
                    WHEN (transactions.date >= (now() - '7 days'::interval)) THEN 1
                    ELSE NULL::integer
                END) AS transactions_7d,
            count(
                CASE
                    WHEN (transactions.date >= (now() - '30 days'::interval)) THEN 1
                    ELSE NULL::integer
                END) AS transactions_30d,
            count(
                CASE
                    WHEN (transactions.date >= date_trunc('month'::text, now())) THEN 1
                    ELSE NULL::integer
                END) AS transactions_current_month,
            count(
                CASE
                    WHEN ((transactions.date >= date_trunc('month'::text, (now() - '1 mon'::interval))) AND (transactions.date < date_trunc('month'::text, now()))) THEN 1
                    ELSE NULL::integer
                END) AS transactions_last_month,
            COALESCE(sum(transactions.points), (0)::bigint) AS total_points_distributed,
            COALESCE(sum(
                CASE
                    WHEN (transactions.date >= (now() - '7 days'::interval)) THEN transactions.points
                    ELSE 0
                END), (0)::bigint) AS points_7d,
            COALESCE(sum(
                CASE
                    WHEN (transactions.date >= (now() - '30 days'::interval)) THEN transactions.points
                    ELSE 0
                END), (0)::bigint) AS points_30d,
            COALESCE(sum(
                CASE
                    WHEN (transactions.date >= date_trunc('month'::text, now())) THEN transactions.points
                    ELSE 0
                END), (0)::bigint) AS points_current_month,
            COALESCE(sum(
                CASE
                    WHEN ((transactions.date >= date_trunc('month'::text, (now() - '1 mon'::interval))) AND (transactions.date < date_trunc('month'::text, now()))) THEN transactions.points
                    ELSE 0
                END), (0)::bigint) AS points_last_month,
            COALESCE(avg(transactions.points), (0)::numeric) AS avg_points_per_transaction,
            COALESCE(max(transactions.points), 0) AS max_points_transaction,
            COALESCE(min(transactions.points), 0) AS min_points_transaction,
            count(DISTINCT transactions.user_id) AS users_with_transactions,
            count(DISTINCT transactions.restaurant_id) AS restaurants_with_transactions
           FROM private.transactions
          WHERE (transactions.status = 'valide'::text)
        ), user_points_stats AS (
         SELECT COALESCE(sum(users.points), (0)::bigint) AS total_user_points,
            COALESCE(avg(users.points), (0)::numeric) AS avg_points_per_user,
            COALESCE(avg(
                CASE
                    WHEN (users.points > 0) THEN users.points
                    ELSE NULL::integer
                END), (0)::numeric) AS avg_points_per_user_with_points,
            COALESCE(max(users.points), 0) AS max_points_user,
            count(
                CASE
                    WHEN (users.points > 0) THEN 1
                    ELSE NULL::integer
                END) AS users_with_points
           FROM private.users
        ), active_users_stats AS (
         SELECT count(DISTINCT app_access_stats.user_id) AS active_users_7d
           FROM private.app_access_stats
          WHERE (app_access_stats.accessed_at >= (now() - '7 days'::interval))
        ), poll_stats AS (
         SELECT count(*) AS total_polls,
            count(
                CASE
                    WHEN ((p.is_active = true) AND (p.starts_at <= now()) AND (p.ends_at >= now())) THEN 1
                    ELSE NULL::integer
                END) AS active_polls,
            count(DISTINCT pv.user_id) AS voters_count,
            count(pv.id) AS total_votes,
                CASE
                    WHEN (count(DISTINCT pv.user_id) > 0) THEN round(((count(pv.id))::numeric / (NULLIF(count(DISTINCT pv.poll_id), 0))::numeric), 2)
                    ELSE (0)::numeric
                END AS avg_votes_per_poll
           FROM (private.polls p
             LEFT JOIN private.poll_votes pv ON ((p.id = pv.poll_id)))
        ), offers_promotions_stats AS (
         SELECT ( SELECT count(*) AS count
                   FROM private.offers) AS total_offers,
            ( SELECT count(*) AS count
                   FROM private.offers
                  WHERE (offers.is_active = true)) AS active_offers,
            ( SELECT count(*) AS count
                   FROM private.promotions) AS total_promotions,
            ( SELECT count(*) AS count
                   FROM private.promotions
                  WHERE ((promotions.start_date <= now()) AND (promotions.end_date >= now()))) AS active_promotions
           FROM ( SELECT 1 AS "?column?") dummy
        ), restaurant_stats AS (
         SELECT count(*) AS total_restaurants
           FROM private.restaurants
        )
 SELECT ts.total_transactions,
    ts.transactions_7d,
    ts.transactions_30d,
        CASE
            WHEN (ts.transactions_last_month > 0) THEN round(((((ts.transactions_current_month - ts.transactions_last_month))::numeric / (ts.transactions_last_month)::numeric) * (100)::numeric), 2)
            WHEN (ts.transactions_current_month > 0) THEN 100.0
            ELSE (0)::numeric
        END AS transactions_monthly_change_percentage,
        CASE
            WHEN (aus.active_users_7d > 0) THEN round(((ts.transactions_30d)::numeric / (aus.active_users_7d)::numeric), 2)
            ELSE (0)::numeric
        END AS avg_transactions_per_active_user,
    ts.total_points_distributed,
    ts.points_7d,
    ts.points_30d,
    ts.avg_points_per_transaction,
    ts.max_points_transaction,
    ts.min_points_transaction,
        CASE
            WHEN (ts.points_last_month > 0) THEN round(((((ts.points_current_month - ts.points_last_month))::numeric / (ts.points_last_month)::numeric) * (100)::numeric), 2)
            WHEN (ts.points_current_month > 0) THEN 100.0
            ELSE (0)::numeric
        END AS points_monthly_change_percentage,
        CASE
            WHEN (aus.active_users_7d > 0) THEN round(((ts.points_30d)::numeric / (aus.active_users_7d)::numeric), 2)
            ELSE (0)::numeric
        END AS avg_points_per_active_user,
    ups.total_user_points,
    ups.avg_points_per_user,
    ups.avg_points_per_user_with_points,
    ups.max_points_user,
    ups.users_with_points,
    ps.total_polls,
    ps.active_polls,
    ps.total_votes,
    ps.voters_count,
    ps.avg_votes_per_poll,
        CASE
            WHEN (aus.active_users_7d > 0) THEN round((((ps.voters_count)::numeric / (aus.active_users_7d)::numeric) * (100)::numeric), 2)
            ELSE (0)::numeric
        END AS poll_participation_rate,
    ops.total_offers,
    ops.active_offers,
    ops.total_promotions,
    ops.active_promotions,
    rs.total_restaurants,
    ts.restaurants_with_transactions,
    now() AS last_updated
   FROM (((((transaction_stats ts
     CROSS JOIN user_points_stats ups)
     CROSS JOIN active_users_stats aus)
     CROSS JOIN poll_stats ps)
     CROSS JOIN offers_promotions_stats ops)
     CROSS JOIN restaurant_stats rs);



COMMENT ON VIEW stats.fidelity_kpi_dashboard IS 'Vue principale KPI Fidélité : points, transactions, restaurants, sondages, offres, promotions. Accessible uniquement aux rôles postgres et service_role.';



CREATE VIEW stats.fidelity_monthly_trends AS
 WITH month_series AS (
         SELECT (generate_series(date_trunc('month'::text, (now() - '1 year'::interval)), date_trunc('month'::text, now()), '1 mon'::interval))::date AS month_start
        )
 SELECT ms.month_start,
    count(DISTINCT t.id) AS transactions,
    COALESCE(sum(t.points), (0)::bigint) AS points_distributed
   FROM (month_series ms
     LEFT JOIN private.transactions t ON (((date_trunc('month'::text, t.date) = ms.month_start) AND (t.status = 'valide'::text))))
  GROUP BY ms.month_start
  ORDER BY ms.month_start DESC;



COMMENT ON VIEW stats.fidelity_monthly_trends IS 'Tendances mensuelles de fidélité sur 12 mois. Accessible uniquement aux rôles postgres et service_role.';



CREATE VIEW stats.fidelity_top_restaurants AS
 SELECT r.id AS restaurant_id,
    r.name AS restaurant_name,
    count(t.id) AS transaction_count,
    COALESCE(sum(t.points), (0)::bigint) AS total_points_distributed,
    COALESCE(avg(t.points), (0)::numeric) AS avg_points_per_transaction,
    COALESCE(sum(t.total), (0)::numeric) AS total_amount,
    count(DISTINCT t.user_id) AS unique_customers,
    max(t.date) AS last_transaction_date
   FROM (private.restaurants r
     LEFT JOIN private.transactions t ON (((r.id = t.restaurant_id) AND (t.status = 'valide'::text))))
  GROUP BY r.id, r.name
 HAVING (count(t.id) > 0)
  ORDER BY (count(t.id)) DESC, COALESCE(sum(t.points), (0)::bigint) DESC;



COMMENT ON VIEW stats.fidelity_top_restaurants IS 'Top restaurants par transactions et points. Accessible uniquement aux rôles postgres et service_role.';



CREATE VIEW stats.fidelity_weekly_trends AS
 WITH week_series AS (
         SELECT (generate_series(date_trunc('week'::text, (now() - '56 days'::interval)), date_trunc('week'::text, now()), '7 days'::interval))::date AS week_start
        )
 SELECT ws.week_start,
    count(DISTINCT t.id) AS transactions,
    COALESCE(sum(t.points), (0)::bigint) AS points_distributed
   FROM (week_series ws
     LEFT JOIN private.transactions t ON (((date_trunc('week'::text, t.date) = ws.week_start) AND (t.status = 'valide'::text))))
  GROUP BY ws.week_start
  ORDER BY ws.week_start DESC;



COMMENT ON VIEW stats.fidelity_weekly_trends IS 'Tendances hebdomadaires de fidélité sur 8 semaines. Accessible uniquement aux rôles postgres et service_role.';



CREATE VIEW stats.startup_daily_growth AS
 WITH date_series AS (
         SELECT (generate_series(date_trunc('day'::text, (now() - '30 days'::interval)), date_trunc('day'::text, now()), '1 day'::interval))::date AS date
        ), daily_users AS (
         SELECT date(users.created_at) AS user_date,
            count(*) AS new_users
           FROM private.users
          WHERE (users.created_at >= (now() - '30 days'::interval))
          GROUP BY (date(users.created_at))
        ), daily_access AS (
         SELECT date(app_access_stats.accessed_at) AS access_date,
            count(DISTINCT app_access_stats.user_id) AS active_users,
            count(*) AS app_access_count
           FROM private.app_access_stats
          WHERE (app_access_stats.accessed_at >= (now() - '30 days'::interval))
          GROUP BY (date(app_access_stats.accessed_at))
        )
 SELECT ds.date,
    COALESCE(du.new_users, (0)::bigint) AS new_users,
    COALESCE(da.active_users, (0)::bigint) AS active_users,
    COALESCE(da.app_access_count, (0)::bigint) AS app_access_count
   FROM ((date_series ds
     LEFT JOIN daily_users du ON ((ds.date = du.user_date)))
     LEFT JOIN daily_access da ON ((ds.date = da.access_date)))
  ORDER BY ds.date DESC;



COMMENT ON VIEW stats.startup_daily_growth IS 'Tendances quotidiennes de croissance sur 30 jours. Accessible uniquement aux rôles postgres et service_role.';



CREATE VIEW stats.startup_kpi_dashboard AS
 WITH user_stats AS (
         SELECT count(*) AS total_users,
            count(
                CASE
                    WHEN (users.created_at >= (now() - '24:00:00'::interval)) THEN 1
                    ELSE NULL::integer
                END) AS new_users_24h,
            count(
                CASE
                    WHEN (users.created_at >= (now() - '7 days'::interval)) THEN 1
                    ELSE NULL::integer
                END) AS new_users_7d,
            count(
                CASE
                    WHEN (users.created_at >= (now() - '30 days'::interval)) THEN 1
                    ELSE NULL::integer
                END) AS new_users_30d,
            count(
                CASE
                    WHEN (users.created_at >= date_trunc('month'::text, now())) THEN 1
                    ELSE NULL::integer
                END) AS new_users_current_month,
            count(
                CASE
                    WHEN ((users.created_at >= date_trunc('month'::text, (now() - '1 mon'::interval))) AND (users.created_at < date_trunc('month'::text, now()))) THEN 1
                    ELSE NULL::integer
                END) AS new_users_last_month,
            count(
                CASE
                    WHEN (users.created_at >= date_trunc('week'::text, now())) THEN 1
                    ELSE NULL::integer
                END) AS new_users_current_week,
            count(
                CASE
                    WHEN ((users.created_at >= date_trunc('week'::text, (now() - '7 days'::interval))) AND (users.created_at < date_trunc('week'::text, now()))) THEN 1
                    ELSE NULL::integer
                END) AS new_users_last_week
           FROM private.users
        ), active_users_stats AS (
         SELECT count(DISTINCT app_access_stats.user_id) AS active_users_7d,
            count(DISTINCT
                CASE
                    WHEN ((app_access_stats.accessed_at >= (now() - '14 days'::interval)) AND (app_access_stats.accessed_at < (now() - '7 days'::interval))) THEN app_access_stats.user_id
                    ELSE NULL::uuid
                END) AS active_users_last_week,
            count(DISTINCT
                CASE
                    WHEN (app_access_stats.accessed_at >= date_trunc('month'::text, now())) THEN app_access_stats.user_id
                    ELSE NULL::uuid
                END) AS active_users_current_month,
            count(DISTINCT
                CASE
                    WHEN ((app_access_stats.accessed_at >= date_trunc('month'::text, (now() - '1 mon'::interval))) AND (app_access_stats.accessed_at < date_trunc('month'::text, now()))) THEN app_access_stats.user_id
                    ELSE NULL::uuid
                END) AS active_users_last_month,
            count(DISTINCT
                CASE
                    WHEN (app_access_stats.accessed_at >= (now() - '24:00:00'::interval)) THEN app_access_stats.user_id
                    ELSE NULL::uuid
                END) AS dau,
            count(DISTINCT
                CASE
                    WHEN (app_access_stats.accessed_at >= (now() - '30 days'::interval)) THEN app_access_stats.user_id
                    ELSE NULL::uuid
                END) AS mau
           FROM private.app_access_stats
          WHERE (app_access_stats.accessed_at >= (now() - '60 days'::interval))
        ), transaction_stats AS (
         SELECT count(DISTINCT transactions.user_id) AS users_with_transactions,
            count(DISTINCT
                CASE
                    WHEN (transactions.date >= (now() - '30 days'::interval)) THEN transactions.user_id
                    ELSE NULL::uuid
                END) AS activated_users_30d
           FROM private.transactions
          WHERE (transactions.status = 'valide'::text)
        ), app_access_stats AS (
         SELECT count(*) AS total_app_access,
            count(
                CASE
                    WHEN (app_access_stats.accessed_at >= (now() - '24:00:00'::interval)) THEN 1
                    ELSE NULL::integer
                END) AS app_access_24h,
            count(
                CASE
                    WHEN (app_access_stats.accessed_at >= (now() - '7 days'::interval)) THEN 1
                    ELSE NULL::integer
                END) AS app_access_7d,
            count(
                CASE
                    WHEN (app_access_stats.accessed_at >= (now() - '30 days'::interval)) THEN 1
                    ELSE NULL::integer
                END) AS app_access_30d,
            count(DISTINCT
                CASE
                    WHEN (app_access_stats.accessed_at >= (now() - '7 days'::interval)) THEN app_access_stats.user_id
                    ELSE NULL::uuid
                END) AS unique_users_7d,
            count(DISTINCT
                CASE
                    WHEN (app_access_stats.accessed_at >= (now() - '30 days'::interval)) THEN app_access_stats.user_id
                    ELSE NULL::uuid
                END) AS unique_users_30d
           FROM private.app_access_stats
        )
 SELECT us.total_users,
    us.new_users_24h,
    us.new_users_7d,
    us.new_users_30d,
        CASE
            WHEN (us.total_users > 0) THEN round((((us.new_users_30d)::numeric / (us.total_users)::numeric) * (100)::numeric), 2)
            ELSE (0)::numeric
        END AS new_users_30d_percentage,
        CASE
            WHEN (us.new_users_last_week > 0) THEN round(((((us.new_users_current_week - us.new_users_last_week))::numeric / (us.new_users_last_week)::numeric) * (100)::numeric), 2)
            WHEN (us.new_users_current_week > 0) THEN 100.0
            ELSE (0)::numeric
        END AS weekly_growth_percentage,
        CASE
            WHEN (us.new_users_last_month > 0) THEN round(((((us.new_users_current_month - us.new_users_last_month))::numeric / (us.new_users_last_month)::numeric) * (100)::numeric), 2)
            WHEN (us.new_users_current_month > 0) THEN 100.0
            ELSE (0)::numeric
        END AS monthly_growth_percentage,
    aus.active_users_7d,
    aus.dau,
    aus.mau,
        CASE
            WHEN (us.total_users > 0) THEN round((((aus.active_users_7d)::numeric / (us.total_users)::numeric) * (100)::numeric), 2)
            ELSE (0)::numeric
        END AS active_users_percentage,
        CASE
            WHEN (aus.active_users_last_month > 0) THEN round(((((aus.active_users_current_month - aus.active_users_last_month))::numeric / (aus.active_users_last_month)::numeric) * (100)::numeric), 2)
            WHEN (aus.active_users_current_month > 0) THEN 100.0
            ELSE (0)::numeric
        END AS active_users_monthly_change_percentage,
        CASE
            WHEN (aus.mau > 0) THEN round((((aus.dau)::numeric / (aus.mau)::numeric) * (100)::numeric), 2)
            ELSE (0)::numeric
        END AS stickiness_percentage,
        CASE
            WHEN (us.total_users > 0) THEN round((((ts.users_with_transactions)::numeric / (us.total_users)::numeric) * (100)::numeric), 2)
            ELSE (0)::numeric
        END AS activation_rate,
    aas.total_app_access,
    aas.app_access_24h,
    aas.app_access_7d,
    aas.app_access_30d,
    aas.unique_users_7d,
    aas.unique_users_30d,
    now() AS last_updated
   FROM (((user_stats us
     CROSS JOIN active_users_stats aus)
     CROSS JOIN transaction_stats ts)
     CROSS JOIN app_access_stats aas);



COMMENT ON VIEW stats.startup_kpi_dashboard IS 'Vue principale KPI Startup : croissance, utilisateurs, engagement, rétention. Accessible uniquement aux rôles postgres et service_role.';



CREATE VIEW stats.startup_monthly_growth AS
 WITH month_series AS (
         SELECT (generate_series(date_trunc('month'::text, (now() - '1 year'::interval)), date_trunc('month'::text, now()), '1 mon'::interval))::date AS month_start
        )
 SELECT ms.month_start,
    count(DISTINCT u.id) AS new_users,
    count(DISTINCT aas.user_id) AS active_users,
    count(DISTINCT aas.id) AS app_access_count
   FROM ((month_series ms
     LEFT JOIN private.users u ON ((date_trunc('month'::text, u.created_at) = ms.month_start)))
     LEFT JOIN private.app_access_stats aas ON ((date_trunc('month'::text, aas.accessed_at) = ms.month_start)))
  GROUP BY ms.month_start
  ORDER BY ms.month_start DESC;



COMMENT ON VIEW stats.startup_monthly_growth IS 'Tendances mensuelles de croissance sur 12 mois. Accessible uniquement aux rôles postgres et service_role.';



CREATE VIEW stats.startup_weekly_growth AS
 WITH week_series AS (
         SELECT (generate_series(date_trunc('week'::text, (now() - '56 days'::interval)), date_trunc('week'::text, now()), '7 days'::interval))::date AS week_start
        )
 SELECT ws.week_start,
    count(DISTINCT u.id) AS new_users,
    count(DISTINCT aas.user_id) AS active_users,
    count(DISTINCT aas.id) AS app_access_count
   FROM ((week_series ws
     LEFT JOIN private.users u ON ((date_trunc('week'::text, u.created_at) = ws.week_start)))
     LEFT JOIN private.app_access_stats aas ON ((date_trunc('week'::text, aas.accessed_at) = ws.week_start)))
  GROUP BY ws.week_start
  ORDER BY ws.week_start DESC;



COMMENT ON VIEW stats.startup_weekly_growth IS 'Tendances hebdomadaires de croissance sur 8 semaines. Accessible uniquement aux rôles postgres et service_role.';

CREATE VIEW view.view_polls AS
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
  ORDER BY p.title;



CREATE VIEW view.view_promotions AS
 SELECT title,
    description,
    image_url,
    color
   FROM private.promotions
  WHERE ((start_date <= now()) AND (end_date >= now()));





CREATE VIEW dashboard_view.restaurants WITH (security_invoker='on') AS
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
   FROM private.restaurants r;



COMMENT ON VIEW dashboard_view.restaurants IS 'Vue des restaurants actifs. Accès direct pour authenticated (fallback) et via la fonction RPC get_dashboard_restaurants_view() qui vérifie le rôle administrateur.';




CREATE VIEW dashboard_view.articles WITH (security_invoker='on') AS
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
   FROM private.articles a;



CREATE VIEW dashboard_view.daily_stats AS
 WITH daily_connexions_app_access AS (
         SELECT ((a.accessed_at AT TIME ZONE 'America/Montreal'::text))::date AS day,
            count(*) AS active_users_app_access
           FROM (private.app_access_stats a
             JOIN private.users u ON ((a.user_id = u.id)))
          WHERE ((a.accessed_at IS NOT NULL) AND (u.role <> 'caissier'::public.user_role))
          GROUP BY (((a.accessed_at AT TIME ZONE 'America/Montreal'::text))::date)
        ), daily_connexions_sessions AS (
         SELECT ((s.created_at AT TIME ZONE 'America/Montreal'::text))::date AS day,
            count(DISTINCT s.user_id) AS active_users_sessions
           FROM (auth.sessions s
             JOIN private.users u ON ((s.user_id = u.id)))
          WHERE ((s.created_at IS NOT NULL) AND (u.role <> 'caissier'::public.user_role) AND (NOT (((s.created_at AT TIME ZONE 'America/Montreal'::text))::date IN ( SELECT ((a.accessed_at AT TIME ZONE 'America/Montreal'::text))::date AS timezone
                   FROM (private.app_access_stats a
                     JOIN private.users u2 ON ((a.user_id = u2.id)))
                  WHERE ((a.accessed_at IS NOT NULL) AND (u2.role <> 'caissier'::public.user_role))))))
          GROUP BY (((s.created_at AT TIME ZONE 'America/Montreal'::text))::date)
        ), daily_connexions_combined AS (
         SELECT COALESCE(aa.day, s.day) AS day,
            (COALESCE(aa.active_users_app_access, (0)::bigint) + COALESCE(s.active_users_sessions, (0)::bigint)) AS active_users_combined
           FROM (daily_connexions_app_access aa
             FULL JOIN daily_connexions_sessions s USING (day))
        ), daily_connexions_tx AS (
         SELECT ((t.date AT TIME ZONE 'America/Montreal'::text))::date AS day,
            count(DISTINCT t.user_id) AS active_users_tx
           FROM (private.transactions t
             JOIN private.users u ON ((t.user_id = u.id)))
          WHERE ((t.status = 'valide'::text) AND (u.role <> 'caissier'::public.user_role))
          GROUP BY (((t.date AT TIME ZONE 'America/Montreal'::text))::date)
        ), daily_tx AS (
         SELECT ((t.date AT TIME ZONE 'America/Montreal'::text))::date AS day,
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
          WHERE (t.status = 'valide'::text)
          GROUP BY (((t.date AT TIME ZONE 'America/Montreal'::text))::date)
        )
 SELECT COALESCE(COALESCE(c.day, c_tx.day), x.day_1) AS day,
    COALESCE(x.transactions_count, (0)::bigint) AS transactions_count,
        CASE
            WHEN (c.active_users_combined > 0) THEN c.active_users_combined
            ELSE GREATEST(COALESCE(c.active_users_combined, (0)::bigint), COALESCE(c_tx.active_users_tx, (0)::bigint))
        END AS active_users,
    COALESCE(x.points_generated, (0)::bigint) AS points_generated,
    COALESCE(x.points_spent, (0)::bigint) AS points_spent
   FROM ((daily_connexions_combined c
     FULL JOIN daily_connexions_tx c_tx USING (day))
     FULL JOIN daily_tx x(day_1, transactions_count, points_generated, points_spent) ON ((COALESCE(c.day, c_tx.day) = x.day_1)))
  ORDER BY COALESCE(COALESCE(c.day, c_tx.day), x.day_1) DESC;



COMMENT ON VIEW dashboard_view.daily_stats IS 'Stats quotidiennes: active_users = nombre total d''accès depuis app_access_stats (COUNT(*), pas unique), en excluant les caissiers. Fallback sur auth.sessions ou transactions (sans caissiers). Utilise UTC pour éviter les décalages horaires.';



CREATE VIEW dashboard_view.eco_gestes_usage_by_period AS
 WITH transactions_with_items AS (
         SELECT (t.date)::date AS transaction_date,
            t.user_id,
            t.restaurant_id,
            t.status,
            ((t.items)::text)::jsonb AS items_json
           FROM private.transactions t
          WHERE ((t.items IS NOT NULL) AND (t.status = 'valide'::text))
        ), eco_geste_transactions AS (
         SELECT t.transaction_date,
            t.user_id,
            t.restaurant_id,
            (item.value ->> 'id'::text) AS eco_geste_id,
            COALESCE(((item.value ->> 'qty'::text))::integer, 1) AS quantity,
            (item.value ->> 'type'::text) AS item_type
           FROM transactions_with_items t,
            LATERAL jsonb_array_elements(t.items_json) item(value)
          WHERE (((item.value ->> 'type'::text) = 'ecogeste'::text) OR ((item.value ->> 'type'::text) = 'article'::text))
        ), aggregated_data AS (
         SELECT eco_geste_transactions.transaction_date AS date,
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
 SELECT date,
    eco_geste_id AS eco_geste_name,
    usage_count,
    sum(usage_count) OVER (PARTITION BY eco_geste_id, month) AS usage_count_monthly,
    sum(usage_count) OVER (PARTITION BY eco_geste_id, year) AS usage_count_yearly
   FROM aggregated_data a
  ORDER BY date DESC, usage_count DESC;



COMMENT ON VIEW dashboard_view.eco_gestes_usage_by_period IS 'Vue sécurisée: Accès uniquement via get_eco_gestes_usage_by_period() pour les administrateurs authentifiés.
Inclut les items avec type=''ecogeste'' ainsi que TOUS les articles avec type=''article''.';



CREATE VIEW dashboard_view.members WITH (security_invoker='on') AS
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
  WHERE ((is_active = true) AND (role = 'membre'::public.user_role));



CREATE VIEW dashboard_view.non_members WITH (security_invoker='on') AS
 SELECT id,
    email,
    name,
    is_active,
    created_at
   FROM private.users u
  WHERE ((is_active = true) AND (role <> 'membre'::public.user_role) AND (role <> ALL (ARRAY['administrateur'::public.user_role, 'superadmin'::public.user_role, 'caissier'::public.user_role])));



CREATE VIEW dashboard_view.offers WITH (security_invoker='on') AS
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
  WHERE ((is_active = true) OR (is_active = false));



COMMENT ON VIEW dashboard_view.offers IS 'Vue des offres avec statut calculé automatiquement';



CREATE VIEW dashboard_view.offers_usage_by_period AS
 WITH offers_from_items AS (
         SELECT (t.date)::date AS transaction_date,
            (item.value ->> 'id'::text) AS offer_id,
            t.user_id,
            t.restaurant_id,
            t.status,
            COALESCE(((item.value ->> 'qty'::text))::integer, 1) AS quantity
           FROM private.transactions t,
            LATERAL jsonb_array_elements(t.items) item(value)
          WHERE ((t.status = 'valide'::text) AND (t.items IS NOT NULL) AND (jsonb_typeof(t.items) = 'array'::text) AND ((item.value ->> 'type'::text) = 'offer'::text))
        ), offers_from_used_offers AS (
         SELECT (t.date)::date AS transaction_date,
            unnest(t.used_offers) AS offer_id,
            t.user_id,
            t.restaurant_id,
            t.status,
            1 AS quantity
           FROM private.transactions t
          WHERE ((t.status = 'valide'::text) AND (t.used_offers IS NOT NULL) AND (array_length(t.used_offers, 1) > 0))
        ), all_offers AS (
         SELECT offers_from_items.transaction_date,
            offers_from_items.offer_id,
            offers_from_items.user_id,
            offers_from_items.restaurant_id,
            offers_from_items.status,
            offers_from_items.quantity
           FROM offers_from_items
        UNION ALL
         SELECT offers_from_used_offers.transaction_date,
            offers_from_used_offers.offer_id,
            offers_from_used_offers.user_id,
            offers_from_used_offers.restaurant_id,
            offers_from_used_offers.status,
            offers_from_used_offers.quantity
           FROM offers_from_used_offers
        ), aggregated_data AS (
         SELECT all_offers.transaction_date AS day,
            (date_trunc('month'::text, (all_offers.transaction_date)::timestamp with time zone))::date AS month,
            (date_trunc('year'::text, (all_offers.transaction_date)::timestamp with time zone))::date AS year,
            all_offers.offer_id,
            sum(all_offers.quantity) AS usage_count,
            count(DISTINCT all_offers.user_id) AS unique_users,
            count(DISTINCT all_offers.restaurant_id) AS unique_restaurants
           FROM all_offers
          GROUP BY all_offers.transaction_date, all_offers.offer_id
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
     LEFT JOIN private.offers o ON (((o.title = a.offer_id) OR ((o.id)::text = a.offer_id))))
  ORDER BY a.day DESC, a.usage_count DESC;



COMMENT ON VIEW dashboard_view.offers_usage_by_period IS 'Vue sécurisée: Accès uniquement via get_offers_usage_by_period() pour les administrateurs authentifiés.';



CREATE VIEW dashboard_view.polls AS
 SELECT id,
    question,
    description,
    is_active,
    starts_at,
    ends_at,
    title,
    image_url,
    target_audience,
    notif_sent,
    COALESCE(( SELECT (count(DISTINCT pv.user_id))::integer AS count
           FROM (private.poll_votes pv
             JOIN private.poll_options po ON ((pv.option_id = po.id)))
          WHERE (po.poll_id = p.id)), 0) AS total_unique_voters,
    COALESCE(( SELECT jsonb_agg(jsonb_build_object('id', po.id, 'option_text', po.option_text, 'option_order', po.option_order, 'vote_count', ( SELECT (count(*))::integer AS count
                   FROM private.poll_votes pv
                  WHERE (pv.option_id = po.id))) ORDER BY po.option_order) AS jsonb_agg
           FROM private.poll_options po
          WHERE (po.poll_id = p.id)), '[]'::jsonb) AS options_with_vote_count
   FROM private.polls p;



COMMENT ON VIEW dashboard_view.polls IS 'Vue des sondages avec options et nombre de votes. Accès uniquement via la fonction RPC get_dashboard_boot_data() qui vérifie le rôle administrateur. L''accès direct est désactivé pour des raisons de sécurité.';