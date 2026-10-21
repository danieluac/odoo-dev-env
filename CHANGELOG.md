# Changelog

Todas as alterações relevantes do setup ficam registadas aqui. O número de
versão é o do **setup** (não o do Odoo). Cada release tem a tag `v<versão>`
(ex.: `v1.0.0`) e publica as imagens base de todas as versões do Odoo
suportadas. Ver a secção "Releases" do `CONTRIBUTING.md`.

## 1.0.1 — 2026-10-21

- Correcção: no Odoo 18, 19 e 20 o servidor não arrancava
  (`FileNotFoundError: …/pytz/zoneinfo/Canada/Saskatchewan`). O pacote PyPI
  `tzdata`, arrastado pelo pandas, acrescentava ao Python nomes legados de
  fusos horários que o `tzdata` do Ubuntu 24.04 só tem no pacote
  `tzdata-legacy`, e o Odoo tenta abrir todos ao carregar o módulo `base`.
  A imagem passa a ter o `tzdata` do sistema actualizado e o `tzdata-legacy`,
  e deixa de incluir o pacote PyPI; a verificação no fim do build
  (`scripts/check_image.py`) confirma que todos os fusos horários abrem.
- O `make up` mostra o progresso da descarga da imagem base (antes
  descarregava em silêncio e parecia parado durante minutos) e só a
  descarrega quando a publicada é diferente da que já existe localmente.
- Build sem avisos: o `Dockerfile` declara que o aviso
  `InvalidDefaultArgInFrom` é esperado (a versão vem sempre do build arg) e
  deixa de mostrar o aviso do `pip` a correr como root; o workflow passa a
  usar as versões das actions que correm em Node.js 24.

## 1.0.0 — 2026-10-21

Primeira release.

### Ambiente

- Odoo + PostgreSQL (imagem `pgvector`) geridos inteiramente por `make`;
  quem não sabe Docker usa só `make <comando>` e `make help`.
- Toda a configuração vem do `.env`, criado automaticamente a partir do
  `.env.example` na primeira execução e nunca sobrescrito.
- Um único código para o Odoo 16.0, 17.0, 18.0, 19.0 e 20.0: a versão é
  escolhida no primeiro `make up` (pergunta, ou `make up ODOO_VERSION=18.0`)
  e gravada no `.env`; a versão do PostgreSQL por omissão é derivada dela.
  Cada versão tem projecto Docker, volumes e bases de dados isolados; vários
  ambientes em simultâneo na mesma máquina com `INSTANCE` e portas distintas.
- Imagem base pré-construída, publicada no GitHub Container Registry a cada
  release (`ghcr.io/danieluac/odoo-dev-env:<odoo>-v<setup>` e `:<odoo>`),
  para `linux/amd64` e `linux/arm64`. O `make up` parte dela e só acrescenta
  as dependências dos repos de módulos; sem acesso ao registo, constrói tudo
  localmente a partir da imagem oficial. Variável `BASE_IMAGE` no `.env`
  (vazio = publicada; `local` = build local; ou outra imagem).
- `Dockerfile` em duas fases (`base` e `final`), com as dependências do
  `requirements.txt`, `pyOpenSSL` compatível com o `cryptography` recente em
  todas as versões e verificação de importação no fim do build; alvo
  `make build`.
- Odoo 16: pacotes Debian obtidos do arquivo histórico (snapshot datado,
  configurável em `DEBIAN_SNAPSHOT`).
- `make status` com versão, imagem, edição, demo, pastas de addons e
  dependências em uso.

### Bases de dados

- `make backup` em formato zip do Odoo (com ou sem filestore) e
  `make restore` de `.zip`, `.sql` ou `.dump`, com neutralização de crons e
  servidores de email; a base de dados restaurada fica activa.
- `db-list`, `db-use`, `db-drop`, `psql`, `neutralize`, `shell`.
- Bases de dados novas sem dados de demonstração por omissão (`ODOO_DEMO`).
- Modo Enterprise automático quando o módulo `web_enterprise` existe em
  `ENTERPRISE_DIR` ou numa pasta de addons.

### Módulos

- `make scaffold MODULE=<nome> [IN=<pasta>]` cria a estrutura de um módulo
  com autor, website e contribuidores do `.env` no manifesto.
- Pasta `repos/` (ignorada pelo git) para clonar repositórios de módulos
  com qualquer estrutura; as pastas com módulos são descobertas sozinhas.
- `ADDONS_PATHS` no `.env` para pastas de addons fora do setup.
- `requirements.txt` dos repositórios de módulos instalados na imagem, com
  filtro de pacotes de sistema e instalação tolerante a linhas que não
  resolvem (`ADDONS_REQUIREMENTS_IGNORE`).
- `make install` / `make update` em qualquer pasta de addons.

### Depuração

- `make debug` arranca o servidor sob debugpy; `.vscode/launch.json`
  gerado com um mapeamento por pasta de addons.
- `.vscode/settings.json` para o VS Code detectar os repositórios em
  `repos/`.

### Migração de versão

- `make migrate DB=<bd> TO=<versão>` via OpenUpgrade, uma versão de cada
  vez, com backup e log por passo.
- `make migrate-module MODULE=<m> TO=<versão>` via odoo-module-migrator.
- `make migrate-odoo` pelo serviço oficial da Odoo (Enterprise).

### Documentação e projecto

- README como manual (requisitos, versões, portas, backups, restauro,
  dia-a-dia, vários ambientes, migração, variáveis, perguntas frequentes).
- Licença MIT e guia de contribuição.
- Workflow `publish-images.yml` (dispara na publicação de uma release ou à
  mão).
