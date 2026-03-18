

CREATE SCHEMA audit;
CREATE SCHEMA dashboard_view;
CREATE SCHEMA mv;
CREATE SCHEMA postgre_rpc;
CREATE SCHEMA private;
CREATE SCHEMA stats;
CREATE SCHEMA view;



CREATE TYPE public.section_id AS ENUM (
    'dashboard',
    'statistics',
    'promotions',
    'restaurants',
    'articles',
    'offers',
    'members',
    'polls'
);



CREATE TYPE public.user_role AS ENUM (
    'utilisateur',
    'caissier',
    'administrateur',
    'membre',
    'superadmin'
);