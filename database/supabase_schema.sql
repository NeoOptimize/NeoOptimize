create extension if not exists pgcrypto;

do $$
begin
    if not exists (select 1 from pg_type where typname = 'client_status') then
        create type public.client_status as enum (
            'pending',
            'active',
            'degraded',
            'blocked',
            'repairing',
            'retired'
        );
    end if;

    if not exists (select 1 from pg_type where typname = 'command_status') then
        create type public.command_status as enum (
            'queued',
            'retry',
            'dispatched',
            'completed',
            'failed',
            'cancelled'
        );
    end if;

    if not exists (select 1 from pg_type where typname = 'action_source') then
        create type public.action_source as enum ('ai', 'client', 'system', 'user');
    end if;

    if not exists (select 1 from pg_type where typname = 'health_state') then
        create type public.health_state as enum ('healthy', 'warning', 'critical');
    end if;
end $$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    new.updated_at = timezone('utc', now());
    return new;
end;
$$;

create table if not exists public.users (
    id uuid primary key references auth.users (id) on delete cascade,
    email text unique,
    full_name text,
    role text not null default 'member',
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.clients (
    id uuid primary key default gen_random_uuid(),
    owner_user_id uuid references public.users (id) on delete set null,
    client_api_key_hash text not null unique,
    hardware_fingerprint_hash text not null unique,
    device_name text,
    os_version text,
    app_version text,
    architecture text,
    status public.client_status not null default 'active',
    trust_score numeric(5,2) not null default 100.00 check (trust_score >= 0 and trust_score <= 100),
    last_seen_at timestamptz,
    last_heartbeat_at timestamptz,
    last_ip inet,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.telemetry_logs (
    id uuid primary key default gen_random_uuid(),
    client_id uuid not null references public.clients (id) on delete cascade,
    cpu_percent numeric(5,2),
    ram_percent numeric(5,2),
    gpu_percent numeric(5,2),
    disk_usage_percent numeric(5,2),
    disk_read_mbps numeric(10,2),
    disk_write_mbps numeric(10,2),
    network_mbps numeric(10,2),
    temperature_celsius numeric(6,2),
    process_count integer,
    alert_state text not null default 'normal',
    alert_reasons jsonb not null default '[]'::jsonb,
    snapshot jsonb not null default '{}'::jsonb,
    recorded_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.action_logs (
    id uuid primary key default gen_random_uuid(),
    client_id uuid references public.clients (id) on delete cascade,
    requested_by_user_id uuid references public.users (id) on delete set null,
    source public.action_source not null,
    action_type text not null,
    status text not null,
    summary text not null,
    correlation_id uuid not null default gen_random_uuid(),
    details jsonb not null default '{}'::jsonb,
    error_message text,
    created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.system_health (
    id uuid primary key default gen_random_uuid(),
    client_id uuid not null references public.clients (id) on delete cascade,
    overall_score smallint check (overall_score between 0 and 100),
    health_state public.health_state not null default 'healthy',
    sfc_status text,
    dism_status text,
    thermal_status text,
    integrity_status text,
    issues jsonb not null default '[]'::jsonb,
    recommendations jsonb not null default '[]'::jsonb,
    report jsonb not null default '{}'::jsonb,
    recorded_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.remote_commands (
    id uuid primary key default gen_random_uuid(),
    client_id uuid not null references public.clients (id) on delete cascade,
    requested_by_user_id uuid references public.users (id) on delete set null,
    source public.action_source not null default 'ai',
    command_name text not null,
    payload jsonb not null default '{}'::jsonb,
    status public.command_status not null default 'queued',
    priority smallint not null default 50 check (priority between 0 and 100),
    correlation_id uuid not null default gen_random_uuid(),
    requested_at timestamptz not null default timezone('utc', now()),
    claimed_at timestamptz,
    completed_at timestamptz,
    result_payload jsonb not null default '{}'::jsonb,
    error_message text
);

create table if not exists public.integrity_manifests (
    id uuid primary key default gen_random_uuid(),
    release_channel text not null default 'stable',
    app_version text not null,
    file_path text not null,
    sha256_hash char(64) not null,
    download_url text,
    is_required boolean not null default true,
    created_at timestamptz not null default timezone('utc', now()),
    unique (release_channel, app_version, file_path)
);

create index if not exists idx_clients_owner_user_id on public.clients (owner_user_id);
create index if not exists idx_clients_status on public.clients (status);
create index if not exists idx_clients_last_seen_at on public.clients (last_seen_at desc);

create index if not exists idx_telemetry_logs_client_recorded_at on public.telemetry_logs (client_id, recorded_at desc);
create index if not exists idx_action_logs_client_created_at on public.action_logs (client_id, created_at desc);
create index if not exists idx_action_logs_requested_by_user_id on public.action_logs (requested_by_user_id);
create index if not exists idx_action_logs_correlation_id on public.action_logs (correlation_id);
create index if not exists idx_system_health_client_recorded_at on public.system_health (client_id, recorded_at desc);
create index if not exists idx_remote_commands_client_status on public.remote_commands (client_id, status, priority desc, requested_at asc);
create index if not exists idx_remote_commands_requested_by_user_id on public.remote_commands (requested_by_user_id);

drop trigger if exists trg_users_updated_at on public.users;
create trigger trg_users_updated_at
before update on public.users
for each row
execute procedure public.set_updated_at();

drop trigger if exists trg_clients_updated_at on public.clients;
create trigger trg_clients_updated_at
before update on public.clients
for each row
execute procedure public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.users (id, email, full_name)
    values (
        new.id,
        new.email,
        coalesce(new.raw_user_meta_data ->> 'full_name', new.email)
    )
    on conflict (id) do update
    set email = excluded.email,
        full_name = coalesce(excluded.full_name, public.users.full_name),
        updated_at = timezone('utc', now());

    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.user_owns_client(target_client_id uuid)
returns boolean
language sql
stable
set search_path = public
as $$
    select exists (
        select 1
        from public.clients c
        where c.id = target_client_id
          and c.owner_user_id = (select auth.uid())
    );
$$;

alter table public.users enable row level security;
alter table public.clients enable row level security;
alter table public.telemetry_logs enable row level security;
alter table public.action_logs enable row level security;
alter table public.system_health enable row level security;
alter table public.remote_commands enable row level security;
alter table public.integrity_manifests enable row level security;

drop policy if exists "users can read their own profile" on public.users;
create policy "users can read their own profile"
on public.users for select
to authenticated
using (id = (select auth.uid()));

drop policy if exists "users can update their own profile" on public.users;
create policy "users can update their own profile"
on public.users for update
to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

drop policy if exists "users can read their own clients" on public.clients;
create policy "users can read their own clients"
on public.clients for select
to authenticated
using (owner_user_id = (select auth.uid()));

drop policy if exists "users can read telemetry for owned clients" on public.telemetry_logs;
create policy "users can read telemetry for owned clients"
on public.telemetry_logs for select
to authenticated
using (public.user_owns_client(client_id));

drop policy if exists "users can read action logs for owned clients" on public.action_logs;
create policy "users can read action logs for owned clients"
on public.action_logs for select
to authenticated
using (client_id is not null and public.user_owns_client(client_id));

drop policy if exists "users can read health for owned clients" on public.system_health;
create policy "users can read health for owned clients"
on public.system_health for select
to authenticated
using (public.user_owns_client(client_id));

drop policy if exists "users can read remote commands for owned clients" on public.remote_commands;
create policy "users can read remote commands for owned clients"
on public.remote_commands for select
to authenticated
using (public.user_owns_client(client_id));

drop policy if exists "integrity manifests are readable by authenticated users" on public.integrity_manifests;
create policy "integrity manifests are readable by authenticated users"
on public.integrity_manifests for select
to authenticated
using (true);

do $$
begin
    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'telemetry_logs'
    ) then
        alter publication supabase_realtime add table public.telemetry_logs;
    end if;

    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'action_logs'
    ) then
        alter publication supabase_realtime add table public.action_logs;
    end if;

    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'system_health'
    ) then
        alter publication supabase_realtime add table public.system_health;
    end if;

    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'remote_commands'
    ) then
        alter publication supabase_realtime add table public.remote_commands;
    end if;
end $$;
