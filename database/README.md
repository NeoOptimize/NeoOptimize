# Supabase Database

Struktur database NeoOptimasi disimpan dalam dua bentuk:

- `supabase_schema.sql`: schema kanonik yang mudah dibaca.
- `migrations/202603100001_initial_neooptimasi.sql`: migrasi siap eksekusi untuk Supabase CLI atau SQL Editor.

## Cara apply via Supabase SQL Editor

1. Buka project Supabase Anda.
2. Masuk ke SQL Editor.
3. Paste isi file `migrations/202603100001_initial_neooptimasi.sql`.
4. Jalankan query.

## Cara apply via Python helper

Siapkan `SUPABASE_DB_URL` dalam format PostgreSQL, lalu jalankan:

```bash
python scripts/apply_supabase_schema.py --db-url "$SUPABASE_DB_URL"
```

Atau gunakan file migrasi tertentu:

```bash
python scripts/apply_supabase_schema.py --db-url "$SUPABASE_DB_URL" --schema-file database/migrations/202603100001_initial_neooptimasi.sql
```
