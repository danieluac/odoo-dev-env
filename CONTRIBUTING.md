# Contribuir

Obrigado pelo interesse em melhorar este setup. Este documento explica como o
repositório está organizado e o que esperamos de uma contribuição.

## Princípios do projecto

Antes de propor uma alteração, confirma que ela respeita estas regras — são o
que torna o setup previsível para quem o usa:

1. **Toda a configuração vem do `.env`.** Nenhuma porta, credencial, versão
   ou caminho fica fixo noutro ficheiro. Uma variável nova entra no
   `.env.example` (com comentário), é lida no `Makefile` com `$(call env,…)`
   e, se for obrigatória, é validada no alvo `check-env`.
2. **O utilizador nunca precisa de editar ficheiros versionados.** Módulos,
   repositórios externos, Enterprise, portas: tudo se configura no `.env` ou
   em pastas ignoradas pelo git (`repos/`, `config/`, `backups/`). Se a tua
   alteração obriga alguém a tocar no `Makefile` ou no compose para usar o
   setup, está mal desenhada.
3. **`make` é a única interface.** Quem não sabe Docker tem de conseguir usar
   qualquer funcionalidade nova só com `make <comando>` e a ajuda do
   `make help`. Comandos novos levam o comentário `## descrição` para
   aparecerem na ajuda.
4. **Um único código para todas as versões suportadas** (`SUPPORTED_VERSIONS`
   no `Makefile`: 16.0 a 20.0). Diferenças entre versões ficam dentro do
   `Makefile`/`Dockerfile`, decididas pela versão em uso (`ODOO_MAJOR`) —
   nunca em cópias do código. Uma correcção específica de uma versão é
   escrita de forma condicional.
5. **Exemplos genéricos.** README, `.env.example` e mensagens não mencionam
   projectos, empresas, caminhos ou nomes reais.

## Organização do repositório

- Há **uma única branch**, `main`, que serve todas as versões do Odoo. A
  versão de cada ambiente vive no `.env` de quem o usa, não no código.
- **Ninguém faz push directo** para `main`. Tudo entra por pull request,
  integrado com **"Squash and merge"**: o GitHub cria um único commit por
  PR, com a autoria de quem o abriu e assinado pelo GitHub (aparece como
  *Verified*).
- Acrescentar suporte a uma versão nova do Odoo é: pô-la em
  `SUPPORTED_VERSIONS`, rever os defaults que dependem da versão
  (`PG_DEFAULT`, flags de demo, ajustes do `Dockerfile`), actualizar a
  tabela de versões do README e cortar uma release (que publica a imagem
  base dessa versão).

## Fluxo de uma contribuição

1. Abre um **issue** primeiro se a alteração for grande ou mudar
   comportamento existente, para alinhar a abordagem antes de investir tempo.
2. Cria uma branch a partir de `main` com um nome descritivo:
   `feat/<assunto>`, `fix/<assunto>` ou `docs/<assunto>`.
3. Faz commits pequenos, com mensagens em português que expliquem **o
   porquê** da alteração, não só o quê. O autor do commit é a pessoa que o
   escreveu.
4. Valida antes de abrir o pull request (ver abaixo).
5. Abre o pull request contra `main`. Na descrição indica: o problema, a
   solução, como validaste e, se a alteração depende da versão do Odoo, em
   que versões testaste.
6. O pull request é integrado com "Squash and merge".

## Validação mínima antes de um pull request

Numa máquina com Docker:

```bash
make help                           # a ajuda continua a renderizar e inclui o teu comando
make up ODOO_VERSION=18.0           # arranca do zero (num clone limpo, com .env novo)
make backup && make restore FILE=backups/<ficheiro>.zip   # se tocaste em backups/restore
make down
```

Se alteraste o `Dockerfile` ou algo que dependa da versão, constrói pelo
menos a imagem de uma versão com base Debian (16) e uma com base Ubuntu (18
ou superior), porque diferem em Python e em política de instalação de
pacotes (`BASE_IMAGE=local` no `.env` força o build completo).

Se alteraste receitas do `Makefile` e não tens Docker à mão, verifica ao
menos a sintaxe bash de cada receita:

```bash
cat > /tmp/checksh <<'EOF'
#!/bin/bash
bash -n -c "$2"
EOF
chmod +x /tmp/checksh
make SHELL=/tmp/checksh up      # repete para cada alvo alterado
```

Se alteraste os ficheiros compose, confirma que renderizam:

```bash
docker compose -f docker-compose.yml config
```

## Documentação

- Qualquer funcionalidade ou variável nova entra no README (secção
  correspondente e tabela de variáveis do `.env`).
- O README é um **manual de utilização**: descreve como as coisas funcionam
  e o que fazer, não o histórico de problemas resolvidos.
- Ficheiros gerados pelo `make` levam no topo um aviso de que não devem ser
  editados à mão e a indicação de onde vem o seu conteúdo.

## Releases

- O número de versão é o do **setup**, em `MAJOR.MINOR.PATCH`. Sobe o
  `PATCH` para correcções, o `MINOR` para funcionalidades novas e o `MAJOR`
  quando algo deixa de ser compatível (ex.: uma variável do `.env` muda de
  nome).
- Há **uma release por versão do setup**, com a tag `v<versão>` (ex.:
  `v1.0.0`), a apontar para `main`. Uma release cobre todas as versões do
  Odoo suportadas.
- Antes de cortar uma release: actualiza o `CHANGELOG.md` (secção nova com
  a versão e a data) através do fluxo normal de pull requests.
- A release é criada no GitHub (Releases → *Draft a new release*): `main`
  como *target*, escreve a tag nova e deixa o GitHub criá-la ao publicar
  (*Create new tag on publish*), para a tag ficar assinada pelo GitHub. As
  notas são a secção do `CHANGELOG.md` mais a tabela das versões do Odoo
  (imagem base, Python, PostgreSQL por omissão, estado de cada versão).
- Publicar a release (push da tag) dispara o workflow **"Publicar imagens
  base"** (`.github/workflows/publish-images.yml`), que constrói a fase
  `base` do `Dockerfile` para cada versão em `SUPPORTED_VERSIONS` e a
  publica no GHCR como `ghcr.io/<dono>/<repo>:<odoo>-v<setup>` e `:<odoo>`
  (tag móvel). Confirma em *Actions* que correu com sucesso; na primeira
  vez, confirma em *Packages* que o pacote é **público** e tem *Workflow
  permissions* de escrita em *Settings → Actions*. O workflow também pode
  ser corrido à mão (*Run workflow*) para republicar uma ou várias versões
  a partir de `main`.

## Reportar problemas

Ao abrir um issue, inclui:

- a versão do Odoo (`ODOO_VERSION` no `.env`), a versão do setup (release
  ou commit) e o sistema operativo;
- o comando executado e a **saída completa** (do `make up`, por exemplo);
- o teu `.env` **sem credenciais**;
- a saída de `make status`.

## Licença

Ao contribuir, aceitas que o teu código seja distribuído sob a licença do
projecto (MIT — ver `LICENSE`).
