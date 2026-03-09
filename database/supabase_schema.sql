-- Enable vector extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgvector";

-- USERS TABLE
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- CLIENTS TABLE
CREATE TABLE IF NOT EXISTS clients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id VARCHAR(255) UNIQUE NOT NULL,
    hardware_id VARCHAR(255) UNIQUE,
    status VARCHAR(50) DEFAULT 'active',
    last_heartbeat TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- COMMANDS TABLE
CREATE TABLE IF NOT EXISTS commands (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id VARCHAR(255),
    tool_name VARCHAR(100) NOT NULL,
    params JSONB,
    status VARCHAR(50) DEFAULT 'pending',
    result TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- TELEMETRY LOGS
CREATE TABLE IF NOT EXISTS telemetry_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id VARCHAR(255),
    cpu_percent NUMERIC,
    ram_percent NUMERIC,
    disk_percent NUMERIC,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- MEMORY FOR LLM
CREATE TABLE IF NOT EXISTS memory (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_message TEXT,
    ai_response TEXT,
    embedding VECTOR(384),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- CREATE INDEXES
CREATE INDEX idx_memory_embedding ON memory USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
CREATE INDEX idx_commands_status ON commands(status);
CREATE INDEX idx_telemetry_created ON telemetry_logs(created_at DESC);

-- VECTOR SEARCH FUNCTION
CREATE OR REPLACE FUNCTION match_memory(
    query_embedding VECTOR(384),
    match_threshold FLOAT,
    match_count INTEGER
) RETURNS TABLE (
    id UUID,
    user_message TEXT,
    ai_response TEXT,
    similarity FLOAT,
    created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT m.id, m.user_message, m.ai_response, 
           1 - (m.embedding <=> query_embedding) AS similarity, m.created_at
    FROM memory m
    WHERE 1 - (m.embedding <=> query_embedding) > match_threshold
    ORDER BY similarity DESC LIMIT match_count;
END;
$$ LANGUAGE plpgsql;