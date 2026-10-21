# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom
# (o aviso acima é esperado: ODOO_VERSION não tem valor por omissão de
#  propósito — ver abaixo — e por isso os FROM só ficam válidos com o build arg)
#
# Imagem Odoo do ambiente, em duas fases:
#
#   base  — imagem oficial odoo:<versão> + toolchain + dependências do
#           requirements.txt + ajustes por versão. É a imagem que o GitHub
#           Actions publica no GHCR a cada release (ver .github/workflows/
#           publish-images.yml), uma por versão do Odoo suportada.
#   final — parte da base (por omissão a publicada no GHCR, já pronta; ou
#           a fase "base" construída aqui, se a publicada não estiver
#           acessível) e acrescenta só as dependências dos repos de módulos.
#
# O mesmo Dockerfile serve todas as versões: a versão vem SEMPRE do build arg
# ODOO_VERSION (o compose passa-o a partir do .env; o workflow, da matriz).
# Sem valor por omissão de propósito — construir sem versão deve falhar.
ARG ODOO_VERSION
# Imagem base da fase final. Por omissão a publicada no GHCR para esta versão;
# "base" constrói tudo localmente a partir da imagem oficial. O Makefile
# escolhe sozinho (BASE_IMAGE no .env para forçar).
ARG BASE_IMAGE=ghcr.io/danieluac/odoo-dev-env:${ODOO_VERSION}

# ═════════════════════════════════════════════════════════════════════
# Fase base — publicada no GHCR; também usada como fallback local
# ═════════════════════════════════════════════════════════════════════
FROM odoo:${ODOO_VERSION} AS base

LABEL org.opencontainers.image.source="https://github.com/danieluac/odoo-dev-env" \
      org.opencontainers.image.description="Imagem base do Ambiente Odoo em Docker: odoo oficial + dependências de desenvolvimento" \
      org.opencontainers.image.licenses="MIT"

USER root

# toolchain para compilar wheels (pyodbc precisa de unixodbc-dev, etc.);
# git: necessário para instalar a openupgradelib e para o make migrate-module
#
# Odoo 16: a imagem oficial assenta em Debian 11 "bullseye", cujo suporte
# terminou em 2026-08-31 — os seus pacotes já não estão nos repositórios
# correntes do Debian. Em bullseye, as fontes apt são por isso fixadas num
# snapshot datado do arquivo histórico (snapshot.debian.org). Os ficheiros
# Release desse arquivo já expiraram (daí Check-Valid-Until=false) e o
# serviço limita o débito (daí os retries). As imagens Ubuntu (Odoo 17+)
# não são tocadas. A data vem do .env (DEBIAN_SNAPSHOT) via build arg.
ARG DEBIAN_SNAPSHOT=20260901T000000Z
RUN set -eux; \
    if grep -q '^VERSION_CODENAME=bullseye' /etc/os-release; then \
        SNAP="http://snapshot.debian.org/archive"; \
        printf '%s\n' \
            "deb ${SNAP}/debian/${DEBIAN_SNAPSHOT} bullseye main" \
            "deb ${SNAP}/debian/${DEBIAN_SNAPSHOT} bullseye-updates main" \
            "deb ${SNAP}/debian-security/${DEBIAN_SNAPSHOT} bullseye-security main" \
            > /etc/apt/sources.list; \
        rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; \
        printf '%s\n' \
            'Acquire::Check-Valid-Until "false";' \
            'Acquire::Retries "5";' \
            > /etc/apt/apt.conf.d/99-bullseye-snapshot; \
    fi; \
    apt-get update; \
    apt-get install -y --no-install-recommends build-essential python3-dev unixodbc-dev git; \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt

# PIP_BREAK_SYSTEM_PACKAGES: necessário nas imagens Ubuntu 24.04 (Odoo 18+),
# cujo pip aplica a PEP 668; ignorado pelo pip mais antigo das outras imagens.
ENV PIP_BREAK_SYSTEM_PACKAGES=1 PIP_ROOT_USER_ACTION=ignore

# deps instaladas com uv (rápido e resolução previsível);
# watchdog: necessário para o auto-reload (--dev=reload);
# openupgradelib (master, como a OCA recomenda): necessária ao make migrate (OpenUpgrade).
#
# Nota: o uv não considera os pacotes Python que a imagem oficial traz via
# apt (/usr/lib/python3/dist-packages) — qualquer dependência sem versão
# (ex.: o lxml exigido pela openupgradelib) é instalada de novo, na versão
# mais recente, em /usr/local, e passa a ser essa que o Odoo importa.
# lxml-html-clean: a partir do lxml 5.2 o módulo lxml.html.clean (usado pelo
# Odoo) vive neste pacote separado — é obrigatório em todas as versões.
RUN pip3 install --no-cache-dir uv \
    && uv pip install --system --break-system-packages --no-cache \
        -r /tmp/requirements.txt watchdog lxml-html-clean \
        "openupgradelib @ git+https://github.com/OCA/openupgradelib.git@master"

# Todas as versões: o requirements arrasta um cryptography recente, com o
# qual o pyOpenSSL que a imagem oficial traz via apt (20.0 em bullseye, 21.0
# em jammy, 24.1 em noble) deixa de importar ("module 'lib' has no attribute
# GEN_EMAIL"). Instala-se um pyOpenSSL compatível em /usr/local, que precede
# o do sistema no sys.path; o uv ajusta o cryptography se for preciso.
# Odoo 16: também urllib3<2 (o 16 importa urllib3.contrib.pyopenssl,
# removido na 2.x) e lxml<6 (o 16 só está validado até ao lxml 5.x).
ARG ODOO_VERSION
RUN uv pip install --system --break-system-packages --no-cache "pyOpenSSL>=24.2" \
    && if [ "${ODOO_VERSION%%.*}" = "16" ]; then \
        uv pip install --system --break-system-packages --no-cache \
            "urllib3>=1.26.16,<2" "lxml>=5.2,<6"; \
    fi

# Verificação da base: importa o Odoo e as bibliotecas sensíveis a versões.
# Garante que a imagem publicada arranca antes de ir para o registo.
RUN python3 -c "import importlib, sys; \
    [importlib.import_module(m) for m in 'OpenSSL cryptography urllib3 requests psycopg2 lxml lxml.html.clean pandas pyodbc debugpy watchdog odoo odoo.tools.mail odoo.release'.split()]; \
    import odoo.release as r; print('OK (base): Odoo', r.version, '| Python', sys.version.split()[0])"

USER odoo

# ═════════════════════════════════════════════════════════════════════
# Fase final — a imagem local odoo-custom:<versão>
# ═════════════════════════════════════════════════════════════════════
FROM ${BASE_IMAGE} AS final

USER root
ENV PIP_BREAK_SYSTEM_PACKAGES=1 PIP_ROOT_USER_ACTION=ignore

# Dependências python dos repos de módulos: o make junta os requirements.txt
# que encontra em addons/, repos/ e ADDONS_PATHS em config/requirements.addons.txt
# (gerado sempre, mesmo vazio). Camada própria: muda sem refazer a base.
# Tolerante: tenta resolver tudo em conjunto; se falhar (pacote inexistente,
# versão impossível…), instala linha a linha e IGNORA o que não der, listando
# no fim do build o que ficou de fora (também em /etc/odoo/requirements.ignorados.txt
# dentro da imagem). A verificação de importação no fim continua a garantir
# que o Odoo e as bibliotecas críticas ficaram íntegros.
COPY config/requirements.addons.txt /tmp/requirements.addons.txt
RUN set -u; R=/tmp/requirements.addons.txt; UV="uv pip install --system --break-system-packages --no-cache"; \
    if grep -qvE '^[[:space:]]*(#|$)' "$R"; then \
        if ! $UV -r "$R"; then \
            echo "### resolução conjunta falhou — a instalar linha a linha (o que não resolver é ignorado)"; \
            : > /tmp/requirements.ignorados; \
            grep -vE '^[[:space:]]*(#|$)' "$R" | while IFS= read -r line; do \
                $UV --quiet "$line" >/dev/null 2>&1 || echo "$line" >> /tmp/requirements.ignorados; \
            done; \
            mkdir -p /etc/odoo && cp /tmp/requirements.ignorados /etc/odoo/requirements.ignorados.txt; \
            echo "### IGNORADOS (não existem no PyPI ou não instalam nesta imagem) — $(wc -l < /tmp/requirements.ignorados) linha(s):"; \
            cat /tmp/requirements.ignorados; \
        fi; \
    fi

# As dependências dos repos podem voltar a mexer nestas bibliotecas;
# repõe-se o que a fase base garante (pyOpenSSL compatível com o
# cryptography instalado; no Odoo 16 também urllib3<2 e lxml<6).
ARG ODOO_VERSION
RUN uv pip install --system --break-system-packages --no-cache "pyOpenSSL>=24.2" \
    && if [ "${ODOO_VERSION%%.*}" = "16" ]; then \
        uv pip install --system --break-system-packages --no-cache \
            "urllib3>=1.26.16,<2" "lxml>=5.2,<6"; \
    fi

# Verificação no fim do build: se alguma combinação tiver ficado
# inconsistente, o build falha AQUI com o erro de import, em vez de o
# servidor falhar a arrancar mais tarde.
RUN python3 -c "import importlib, sys; \
    [importlib.import_module(m) for m in 'OpenSSL cryptography urllib3 requests psycopg2 lxml lxml.html.clean pandas pyodbc debugpy watchdog odoo odoo.tools.mail odoo.release'.split()]; \
    import odoo.release as r; print('OK: Odoo', r.version, '| Python', sys.version.split()[0])"

USER odoo
