select ui.relname as table_name, i.relname as index_name, coalesce(psui.idx_scan, 0) as idx_scan
from pg_class ui
join pg_namespace ns on ns.oid = ui.relnamespace
join pg_index ix on ix.indrelid = ui.oid
join pg_class i on i.oid = ix.indexrelid
left join pg_stat_user_indexes psui on psui.indexrelid = i.oid
where ns.nspname = 'public'
order by coalesce(psui.idx_scan, 0), ui.relname, i.relname;

select relname, seq_scan, idx_scan, n_live_tup
from pg_stat_user_tables
where schemaname = 'public'
order by relname;

-- Replace QUERY_VECTOR_LITERAL with a real 384-dimension vector literal from your embedding pipeline
-- before running this EXPLAIN.
-- example shape: '[0.001,0.002,...,0.384]'
--
-- explain analyze
-- select id, user_message, ai_response, 1 - (embedding <=> 'QUERY_VECTOR_LITERAL') as similarity
-- from public.memory
-- order by embedding <=> 'QUERY_VECTOR_LITERAL'
-- limit 3;
