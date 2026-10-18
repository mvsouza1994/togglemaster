#!/usr/bin/env python3
"""Gerador de carga HTTP — substituto do `hey` (nao ha Go nesta maquina).

Usa somente a biblioteca padrao. Imprime vazao ao vivo e, no final, um resumo
com percentis de latencia, no mesmo espirito do `hey`.

Uso:
    python scripts/carga.py "http://<NLB>/evaluate?user_id=u1&flag_name=enable-new-dashboard"
    python scripts/carga.py "<URL>" -c 50 -z 120
"""
import argparse
import statistics
import sys
import threading
import time
import urllib.error
import urllib.request
from collections import Counter

p = argparse.ArgumentParser()
p.add_argument("url")
p.add_argument("-c", type=int, default=50, help="conexoes concorrentes (padrao 50)")
p.add_argument("-z", type=int, default=120, help="duracao em segundos (padrao 120)")
args = p.parse_args()

fim = time.time() + args.z
lat = []
codigos = Counter()
trava = threading.Lock()
parar = threading.Event()


def worker():
    local_lat, local_cod = [], Counter()
    while not parar.is_set() and time.time() < fim:
        t0 = time.perf_counter()
        try:
            with urllib.request.urlopen(args.url, timeout=10) as r:
                r.read()
                local_cod[r.status] += 1
        except urllib.error.HTTPError as e:
            local_cod[e.code] += 1
        except Exception:
            local_cod["erro"] += 1
        local_lat.append((time.perf_counter() - t0) * 1000)
        if len(local_lat) >= 100:
            with trava:
                lat.extend(local_lat)
                codigos.update(local_cod)
            local_lat, local_cod = [], Counter()
    with trava:
        lat.extend(local_lat)
        codigos.update(local_cod)


print(f"alvo:        {args.url}")
print(f"concorrencia {args.c}  |  duracao {args.z}s")
print("-" * 62)

inicio = time.time()
threads = [threading.Thread(target=worker, daemon=True) for _ in range(args.c)]
for t in threads:
    t.start()

try:
    ultimo = 0
    while time.time() < fim:
        time.sleep(2)
        with trava:
            n = len(lat)
        agora = time.time() - inicio
        rps = (n - ultimo) / 2
        print(f"  {agora:6.0f}s   total {n:>8,}   {rps:>7,.0f} req/s")
        ultimo = n
except KeyboardInterrupt:
    parar.set()
    print("\ninterrompido")

for t in threads:
    t.join(timeout=15)

dur = time.time() - inicio
print("-" * 62)
if not lat:
    print("nenhuma requisicao concluida")
    sys.exit(1)

lat.sort()
pct = lambda q: lat[min(int(len(lat) * q), len(lat) - 1)]
print(f"  requisicoes  {len(lat):,}")
print(f"  duracao      {dur:.1f}s")
print(f"  vazao        {len(lat)/dur:,.0f} req/s")
print(f"  latencia     media {statistics.mean(lat):.0f} ms   "
      f"p50 {pct(.50):.0f}   p95 {pct(.95):.0f}   p99 {pct(.99):.0f}")
print(f"  respostas    {dict(codigos)}")
