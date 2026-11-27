-- ---------- Migração 2: quem fez cada interação ----------
alter table public.interacoes add column if not exists usuario text;

