#!/usr/bin/env python3
"""Actualização automática de módulos (AUTO_UPDATE no .env).

Corre DENTRO do container odoo, lançado pelo make (make up / restart / watch):
observa as pastas dos módulos indicados e, quando um ficheiro muda (XML, CSV,
Python, JS, SCSS, traduções…), corre `odoo -u <módulos> --stop-after-init`
sobre a base de dados activa, num processo à parte. O servidor em execução
apanha a alteração do registo no pedido seguinte (sinalização do Odoo), por
isso não é preciso reiniciá-lo.

As alterações são agrupadas (debounce) para uma gravação em vários ficheiros
dar origem a uma única actualização; se chegarem mais durante uma
actualização, corre outra no fim.

Uso (feito pelo Makefile, não à mão):
    watch_update.py --db <bd> [--foreground] modulo_a modulo_b …

Registo: em segundo plano escreve no stdout do processo 1 do container, ou
seja, aparece em `make logs`; com --foreground escreve no terminal.
"""
import argparse
import configparser
import os
import signal
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer

ODOO_RC = os.environ.get("ODOO_RC", "/etc/odoo/odoo.conf")
PIDFILE = Path(os.environ.get("WATCH_UPDATE_PIDFILE", "/var/lib/odoo/.watch_update.pid"))
DEBOUNCE = 1.5  # segundos sem alterações antes de actualizar
IGNORE_DIRS = {"__pycache__", ".git", "node_modules", ".idea", ".vscode", ".mypy_cache", ".pytest_cache"}
IGNORE_SUFFIXES = (".pyc", ".pyo", ".swp", ".swx", ".swo", "~", ".tmp", ".orig", ".rej", ".bak")

_out = None


def log(msg):
    line = f"[auto-update {datetime.now():%H:%M:%S}] {msg}\n"
    for stream in {_out, sys.stdout}:
        if stream is None:
            continue
        try:
            stream.write(line)
            stream.flush()
        except OSError:
            pass


def ignored(path):
    p = Path(path)
    if any(part in IGNORE_DIRS for part in p.parts):
        return True
    name = p.name
    if name.startswith((".#", ".~", ".goutputstream")) or name == "4913":  # editores (emacs, gedit, vim)
        return True
    return name.endswith(IGNORE_SUFFIXES)


def addons_dirs():
    cfg = configparser.ConfigParser()
    cfg.read(ODOO_RC)
    raw = cfg.get("options", "addons_path", fallback="")
    return [d.strip() for d in raw.split(",") if d.strip()]


def find_module(name, dirs):
    for d in dirs:
        candidate = Path(d) / name
        if (candidate / "__manifest__.py").exists():
            return candidate
    return None


class Handler(FileSystemEventHandler):
    def __init__(self, module, mark):
        self.module = module
        self.mark = mark

    def on_any_event(self, event):
        if event.event_type == "opened" or event.event_type == "closed_no_write":
            return
        if event.is_directory and event.event_type == "modified":
            return
        # dest_path só é relevante em renomeações (nas outras versões do
        # watchdog vem vazio) — nunca o deixar contar como "não ignorado"
        paths = [p for p in (event.src_path, getattr(event, "dest_path", None)) if p]
        if not paths or all(ignored(p) for p in paths):
            return
        self.mark(self.module, paths[0])


def main():
    global _out
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", required=True)
    ap.add_argument("--foreground", action="store_true")
    ap.add_argument("modules", nargs="+")
    args = ap.parse_args()
    modules = sorted({m for arg in args.modules for m in arg.split(",") if m})

    if not args.foreground:
        try:
            _out = open("/proc/1/fd/1", "w")  # stdout do container → make logs
        except OSError:
            _out = None

    # só uma instância por container
    try:
        old = int(PIDFILE.read_text().strip())
        if old != os.getpid() and Path(f"/proc/{old}").exists():
            os.kill(old, signal.SIGTERM)
            time.sleep(0.5)
    except (OSError, ValueError):
        pass
    PIDFILE.write_text(str(os.getpid()))

    dirs = addons_dirs()
    watched = {}
    for m in modules:
        path = find_module(m, dirs)
        if path is None:
            log(f"AVISO: módulo '{m}' não encontrado em nenhuma pasta de addons — ignorado")
            continue
        watched[m] = path
    if not watched:
        log("nenhum módulo para observar — a terminar")
        PIDFILE.unlink(missing_ok=True)
        return 1

    pending = set()
    last_change = [0.0]
    lock = threading.Lock()

    def mark(module, path):
        with lock:
            pending.add(module)
            last_change[0] = time.monotonic()

    observer = Observer()
    for m, path in watched.items():
        observer.schedule(Handler(m, mark), str(path), recursive=True)
    observer.start()
    log(f"a observar {', '.join(f'{m} ({p})' for m, p in watched.items())} — BD {args.db}")

    stop = threading.Event()

    def on_signal(signum, frame):
        stop.set()

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)

    try:
        while not stop.is_set():
            time.sleep(0.3)
            with lock:
                ready = pending and (time.monotonic() - last_change[0]) >= DEBOUNCE
                mods = sorted(pending) if ready else None
                if ready:
                    pending.clear()
            if not mods:
                continue
            log(f"alterações em {', '.join(mods)} — a actualizar na BD {args.db}…")
            started = time.monotonic()
            cmd = ["odoo", "-d", args.db, "-u", ",".join(mods), "--stop-after-init", "--no-http", "--log-level", "warn"]
            proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            elapsed = time.monotonic() - started
            if proc.returncode == 0:
                log(f"✓ {', '.join(mods)} actualizado(s) em {elapsed:.0f}s")
            else:
                tail = "\n".join(proc.stdout.strip().splitlines()[-30:])
                log(f"✗ a actualização de {', '.join(mods)} FALHOU (código {proc.returncode}) — últimas linhas:\n{tail}")
    finally:
        observer.stop()
        observer.join(timeout=5)
        try:
            if PIDFILE.read_text().strip() == str(os.getpid()):
                PIDFILE.unlink()
        except OSError:
            pass
        log("parado")
    return 0


if __name__ == "__main__":
    sys.exit(main())
