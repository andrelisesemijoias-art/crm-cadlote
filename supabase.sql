-- =====================================================================
-- CRM Abordagem Fria — esquema do Supabase
-- Como usar: Supabase > SQL Editor > New query > cole tudo > Run.
-- Pode rodar de novo sem medo (usa "if not exists" / "drop ... if exists").
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- LEADS ----------
create table if not exists public.leads (
  id                uuid primary key default gen_random_uuid(),
  nome_original     text,
  nome              text,                       -- "nome tratado", usado nos templates
  telefone          text not null unique,       -- só dígitos, com 55 e 9º dígito
  segmento          text,
  cidade            text,
  instagram         text,
  origem            text,
  tags              text[] not null default '{}',
  etapa             text not null default 'novo'
                    check (etapa in ('novo','abordado','respondeu','interessado','teste','proposta','assinante','perdido')),
  etapa_desde       timestamptz not null default now(),
  motivo_perda      text,
  tentativas        int not null default 0,
  ultimo_contato    timestamptz,
  proximo_followup  date,
  plano             text,
  valor_mensal      numeric(10,2),
  inicio_assinatura date,
  fim_trial         date,
  status_pagamento  text,
  observacoes       text,
  deleted_at        timestamptz,                -- lixeira (exclusão reversível)
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists leads_etapa_idx     on public.leads (etapa) where deleted_at is null;
create index if not exists leads_followup_idx  on public.leads (proximo_followup) where deleted_at is null;
create index if not exists leads_deleted_idx   on public.leads (deleted_at);
create index if not exists leads_tags_idx      on public.leads using gin (tags);

-- ---------- TEMPLATES ----------
create table if not exists public.templates (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null,
  tipo        text not null default 'geral'
              check (tipo in ('primeiro_contato','followup_1','followup_2','followup_3','oferta_teste','reativacao','geral')),
  texto       text not null,
  ativo       boolean not null default true,
  created_at  timestamptz not null default now()
);

-- ---------- INTERAÇÕES (histórico) ----------
create table if not exists public.interacoes (
  id           uuid primary key default gen_random_uuid(),
  lead_id      uuid not null references public.leads(id) on delete cascade,
  tipo         text not null,                   -- whatsapp | resposta | etapa | nota
  template_id  uuid references public.templates(id) on delete set null,
  resultado    text,                            -- primeiro | enviado | respondeu
  texto        text,
  created_at   timestamptz not null default now()
);

create index if not exists interacoes_lead_idx on public.interacoes (lead_id, created_at desc);
create index if not exists interacoes_tipo_idx on public.interacoes (tipo, created_at desc);
create index if not exists interacoes_tpl_idx  on public.interacoes (template_id);

-- ---------- BLOQUEADOS (nunca mais contatar / reimportar) ----------
create table if not exists public.bloqueados (
  telefone    text primary key,
  motivo      text,
  created_at  timestamptz not null default now()
);

-- ---------- CONFIG (uma linha, JSON) ----------
create table if not exists public.config (
  id    int primary key default 1 check (id = 1),
  data  jsonb not null default '{}'::jsonb
);
insert into public.config (id, data) values (1, '{}') on conflict (id) do nothing;

-- ---------- updated_at automático ----------
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists leads_updated_at on public.leads;
create trigger leads_updated_at before update on public.leads
  for each row execute function public.set_updated_at();

-- ---------- RLS: só usuário autenticado lê e escreve ----------
alter table public.leads       enable row level security;
alter table public.templates   enable row level security;
alter table public.interacoes  enable row level security;
alter table public.bloqueados  enable row level security;
alter table public.config      enable row level security;

do $$
declare t text;
begin
  foreach t in array array['leads','templates','interacoes','bloqueados','config'] loop
    execute format('drop policy if exists "auth_all" on public.%I', t);
    execute format(
      'create policy "auth_all" on public.%I for all to authenticated using (true) with check (true)', t);
  end loop;
end $$;

-- Garante que o papel anônimo não enxerga nada
revoke all on public.leads, public.templates, public.interacoes, public.bloqueados, public.config from anon;
grant all on public.leads, public.templates, public.interacoes, public.bloqueados, public.config to authenticated;

-- ---------- Migração: grupos em que o contato aparece (importação repetida) ----------
alter table public.leads add column if not exists grupos text[] not null default '{}';
update public.leads set grupos = array[origem] where origem is not null and grupos = '{}';
create index if not exists leads_grupos_idx on public.leads using gin (grupos);

-- ---------- Migração 2: quem fez cada interação ----------
alter table public.interacoes add column if not exists usuario text;

-- ---------- Templates iniciais (só se a tabela estiver vazia) ----------
-- Variáveis: {nome} {grupo} {segmento} {cidade} {meu_nome}
-- Primeiro contato: pergunta curta, SEM link. Várias versões para o sistema sortear.
insert into public.templates (nome, tipo, texto)
select * from (values
  ('Primeiro contato A', 'primeiro_contato',
   'Oi {nome}! Te vi no {grupo}. Você trabalha com vendas de revenda por lá?'),
  ('Primeiro contato B', 'primeiro_contato',
   'Olá {nome}, tudo bem? Também estou no {grupo}. Posso te fazer uma pergunta rápida sobre como você organiza suas vendas?'),
  ('Primeiro contato C', 'primeiro_contato',
   'Oi {nome}, tudo certo? Vi que você está no {grupo}. Você controla seus clientes e pedidos em caderno, planilha ou algum app?'),
  ('Follow-up 1', 'followup_1',
   'Oi {nome}, passando só pra saber se você viu minha mensagem de antes. Posso te explicar rapidinho?'),
  ('Follow-up 2', 'followup_2',
   '{nome}, sei que a correria de loja é grande! Se não fizer sentido pra você agora, é só me avisar que eu não incomodo mais.'),
  ('Follow-up 3 (último)', 'followup_3',
   'Oi {nome}, última mensagem por aqui: se um dia quiser organizar melhor suas vendas, é só me chamar. Sucesso nas vendas!'),
  ('Oferta de teste', 'oferta_teste',
   'Que bom, {nome}! Posso liberar um teste grátis pra você ver na prática. Quer que eu te mande o acesso?'),
  ('Reativação', 'reativacao',
   'Oi {nome}, aqui é {meu_nome}. Faz um tempinho que conversamos. Ainda faz sentido organizar suas vendas? Posso te mostrar as novidades.')
) as v(nome, tipo, texto)
where not exists (select 1 from public.templates);

-- =====================================================================
-- Depois de rodar:
-- 1) Authentication > Users > Add user (seu e-mail e senha).
-- 2) Authentication > Sign In / Providers > Email: DESLIGUE "Allow new users to sign up",
--    senão qualquer pessoa com a URL pode criar conta e ler a base.
-- 3) Abra o index.html, cole a Project URL e a anon key (Project Settings > API) e entre.
-- =====================================================================
