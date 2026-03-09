# Supabase Database

Struktur database NeoOptimasi disimpan dalam dua bentuk:

- `supabase_schema.sql`: schema kanonik yang mudah dibaca.
- `migrations/202603100001_initial_neooptimasi.sql`: migrasi siap eksekusi untuk Supabase CLI, SQL Editor, PostgreSQL, atau Supabase Management API.

## Cara apply via Supabase SQL Editor

1. Buka project Supabase Anda.
2. Masuk ke SQL Editor.
3. Paste isi file `migrations/202603100001_initial_neooptimasi.sql`.
4. Jalankan query.

## Cara apply via Python helper dan PostgreSQL

Siapkan `SUPABASE_DB_URL` dalam format PostgreSQL, lalu jalankan:

```bash
python scripts/apply_supabase_schema.py --db-url "$SUPABASE_DB_URL"
```

Atau gunakan file migrasi tertentu:

```bash
python scripts/apply_supabase_schema.py --db-url "$SUPABASE_DB_URL" --schema-file database/migrations/202603100001_initial_neooptimasi.sql
```

## Cara apply via Python helper dan Supabase Management API

Siapkan:

- `SUPABASE_ACCESS_TOKEN`: Supabase Personal Access Token.
- `SUPABASE_PROJECT_REF`: project ref Supabase, atau cukup `SUPABASE_URL` agar project ref bisa diinfer otomatis.

Lalu jalankan:

```bash
python scripts/apply_supabase_schema.py --mode management
```

Atau eksplisit:

```bash
python scripts/apply_supabase_schema.py --mode management --management-token "$SUPABASE_ACCESS_TOKEN" --project-ref "$SUPABASE_PROJECT_REF"
```

Catatan:

- `service_role` JWT tidak bisa dipakai untuk endpoint Management API ini.
- Jika `--mode` tidak diisi, helper akan otomatis memilih `db` saat `SUPABASE_DB_URL` tersedia, lalu fallback ke `management` saat PAT tersedia.
