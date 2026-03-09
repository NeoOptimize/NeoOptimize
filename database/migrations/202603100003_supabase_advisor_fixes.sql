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

create index if not exists idx_action_logs_requested_by_user_id
on public.action_logs (requested_by_user_id);

create index if not exists idx_remote_commands_requested_by_user_id
on public.remote_commands (requested_by_user_id);

do $$
begin
    if exists (
        select 1
        from information_schema.tables
        where table_schema = 'public' and table_name = 'feedback'
    ) then
        execute 'create index if not exists idx_feedback_message_id on public.feedback (message_id)';
        execute 'alter table public.feedback enable row level security';
        execute 'drop policy if exists "users can read feedback for owned memory" on public.feedback';
        execute $policy$
            create policy "users can read feedback for owned memory"
            on public.feedback for select
            to authenticated
            using (
                exists (
                    select 1
                    from public.memory m
                    where m.id = feedback.message_id
                      and m.client_id is not null
                      and public.user_owns_client(m.client_id)
                )
            )
        $policy$;
    end if;

    if exists (
        select 1
        from information_schema.tables
        where table_schema = 'public' and table_name = 'memory'
    ) then
        execute 'create index if not exists idx_memory_client_id on public.memory (client_id)';
        execute 'alter table public.memory enable row level security';
        execute 'drop policy if exists "users can read memory for owned clients" on public.memory';
        execute $policy$
            create policy "users can read memory for owned clients"
            on public.memory for select
            to authenticated
            using (
                client_id is not null
                and public.user_owns_client(client_id)
            )
        $policy$;
    end if;
end $$;

drop function if exists public.match_memory(vector, double precision, integer);

drop function if exists public.match_memory(vector, double precision, integer, uuid);

create or replace function public.match_memory(
    query_embedding vector,
    match_threshold double precision,
    match_count integer,
    client_id_filter uuid default null
)
returns table(id uuid, user_message text, ai_response text, similarity double precision)
language plpgsql
set search_path = public, extensions
as $$
begin
    return query
    select
        public.memory.id,
        public.memory.user_message,
        public.memory.ai_response,
        1 - (public.memory.embedding <=> query_embedding) as similarity
    from public.memory
    where (client_id_filter is null or public.memory.client_id = client_id_filter)
      and 1 - (public.memory.embedding <=> query_embedding) > match_threshold
    order by public.memory.embedding <=> query_embedding
    limit match_count;
end;
$$;
