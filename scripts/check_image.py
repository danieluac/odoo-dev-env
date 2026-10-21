#!/usr/bin/env python3
"""Verificação no fim do build da imagem (fase base e fase final).

Corre dentro da imagem, pelo Dockerfile. Se alguma coisa estiver inconsistente
o build falha AQUI, com uma mensagem legível, em vez de o servidor falhar a
arrancar mais tarde.

1. Importa o Odoo e as bibliotecas sensíveis a versões (cryptography/pyOpenSSL,
   urllib3, lxml, pandas, pyodbc, debugpy, watchdog…).
2. Fusos horários: o Odoo (18+) percorre zoneinfo.available_timezones() e
   abre cada nome com pytz, que nas imagens Debian/Ubuntu lê os ficheiros de
   /usr/share/zoneinfo. Um nome que exista num lado e não no outro (por
   exemplo o pacote PyPI "tzdata", arrastado pelo pandas, que inclui nomes
   legados como Canada/Saskatchewan que o tzdata do Ubuntu 24.04 só tem no
   pacote tzdata-legacy) faz o servidor cair ao arrancar com FileNotFoundError.
   Aqui confirma-se que TODOS os nomes conhecidos abrem.

Uso: python3 check_image.py <fase>   (fase = "base" ou "final", só para a mensagem)
"""
import importlib
import sys
import zoneinfo

MODULES = (
    "OpenSSL cryptography urllib3 requests psycopg2 lxml lxml.html.clean "
    "pandas pyodbc debugpy watchdog odoo odoo.tools.mail odoo.release"
).split()

stage = sys.argv[1] if len(sys.argv) > 1 else "imagem"

for name in MODULES:
    importlib.import_module(name)

import pytz  # noqa: E402  (vem com a imagem oficial)
import odoo.release  # noqa: E402

names = set(pytz.all_timezones) | zoneinfo.available_timezones()
missing = []
for tz in sorted(names):
    try:
        pytz.timezone(tz)
    except LookupError:
        # nome desconhecido do pytz (UnknownTimeZoneError): o Odoo ignora-o
        pass
    except OSError:
        # o pytz do Debian/Ubuntu conhece o nome mas o ficheiro não existe em
        # /usr/share/zoneinfo — é isto que derruba o Odoo ao arrancar
        missing.append(tz)
if missing:
    sys.exit(
        f"ERRO ({stage}): {len(missing)} fuso(s) horário(s) conhecido(s) pelo Python "
        f"sem ficheiro em /usr/share/zoneinfo, ex.: {', '.join(missing[:5])}. "
        "O Odoo não arrancaria. Causas habituais: pacote PyPI 'tzdata' instalado "
        "por uma dependência (deve ser removido no Dockerfile) ou falta o pacote "
        "de sistema tzdata-legacy."
    )

try:
    import tzdata  # noqa: F401
    print(f"AVISO ({stage}): o pacote PyPI 'tzdata' está instalado; os fusos "
          "horários batem certo com o sistema por agora, mas uma versão mais "
          "recente dele pode voltar a desalinhar")
except ImportError:
    pass

print(
    f"OK ({stage}): Odoo {odoo.release.version} | Python {sys.version.split()[0]} "
    f"| {len(names)} fusos horários"
)
