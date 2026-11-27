-- ---------- Migração: grupos em que o contato aparece (importação repetida) ----------
alter table public.leads add column if not exists grupos text[] not null default '{}';
update public.leads set grupos = array[origem] where origem is not null and grupos = '{}';
create index if not exists leads_grupos_idx on public.leads using gin (grupos);

