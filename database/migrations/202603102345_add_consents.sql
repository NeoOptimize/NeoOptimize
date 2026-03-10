alter table public.clients
    add column if not exists last_location jsonb,
    add column if not exists consent_accepted boolean not null default false,
    add column if not exists consent_accepted_at timestamptz,
    add column if not exists consent_updated_at timestamptz,
    add column if not exists consent_telemetry boolean not null default true,
    add column if not exists consent_diagnostics boolean not null default true,
    add column if not exists consent_maintenance boolean not null default true,
    add column if not exists consent_remote_control boolean not null default false,
    add column if not exists consent_auto_execution boolean not null default false,
    add column if not exists consent_location boolean not null default false,
    add column if not exists consent_camera boolean not null default false;

create table if not exists public.consent_logs (
    id uuid primary key default gen_random_uuid(),
    client_id uuid not null references public.clients (id) on delete cascade,
    accepted boolean not null default false,
    telemetry boolean not null default true,
    diagnostics boolean not null default true,
    maintenance boolean not null default true,
    remote_control boolean not null default false,
    auto_execution boolean not null default false,
    location boolean not null default false,
    camera boolean not null default false,
    recorded_at timestamptz not null default timezone('utc', now())
);
