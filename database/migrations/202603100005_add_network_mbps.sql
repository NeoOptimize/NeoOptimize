-- Add network telemetry
alter table if exists public.telemetry_logs
    add column if not exists network_mbps numeric(10,2);
