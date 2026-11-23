#!/usr/bin/env bash
# Publica o site no Cloudflare Pages. O aviso de novidade sai sozinho do último commit:
# a página mostra a mensagem dele uma vez para cada pessoa.
set -euo pipefail
cd "$(dirname "$0")"

SITE="index.html match.js terrenos.json logo.svg"
if [ -n "$(git status --porcelain -- $SITE)" ]; then
  echo "Há mudanças sem commit em: $SITE. Faça o commit antes (a mensagem vira o aviso do site)." >&2
  exit 1
fi

D=$(mktemp -d)
cp $SITE "$D"/
node -e 'require("fs").writeFileSync(process.argv[1], JSON.stringify({ id: process.argv[2], txt: process.argv[3] }))' \
  "$D/versao.json" "$(git rev-parse --short HEAD)" "$(git log -1 --format=%s)"
npx wrangler pages deploy "$D" --project-name conferencia-areas --branch main
