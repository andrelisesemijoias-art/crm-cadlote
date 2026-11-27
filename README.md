# CRM Cadlote

CRM de abordagem fria por WhatsApp: um `index.html` (sem build) + Supabase.

## Subir

1. Crie o projeto no Supabase (conta própria deste CRM).
2. SQL Editor > cole `supabase.sql` > Run.
3. Authentication > Users > Add user (e-mail e senha, marque Auto Confirm).
4. Authentication > Sign In / Providers > Email: desligue "Allow new users to sign up".
5. Em `index.html`, preencha `SUPABASE_URL` e `SUPABASE_KEY` (Project Settings > API: Project URL e chave **anon public**; nunca a `service_role`).
6. Abra `index.html` e entre com o usuário do passo 3.

Sem o passo 5 a tela pede URL e chave e guarda só no navegador.
