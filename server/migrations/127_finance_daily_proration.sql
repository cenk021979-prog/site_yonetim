-- 127: Aylık Aidat günlük paylarının değişmez anlık görüntüsü. Eski borçlar topluca değiştirilmez.
ALTER TABLE ledger_entries ADD COLUMN IF NOT EXISTS proration JSONB;
