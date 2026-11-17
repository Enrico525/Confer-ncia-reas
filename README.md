# Conferência de Áreas — São Paulo

**🔗 Acesse o site: https://conferencia-areas.pages.dev/**

Página que recebe um PDF, Word ou lista de endereços e devolve, para cada terreno, o **SQL**, a **área do terreno** e o **zoneamento**, com exportação para Excel.

Dados: Cadastro Imobiliário Fiscal (IPTU) da Prefeitura de São Paulo, publicado no [GeoSampa](https://novogeosampa.prefeitura.sp.gov.br) — só terrenos com 500 m² ou mais. Zoneamento: mapa da Lei 18.081/24 (GeoSampa), cruzado com o desenho de cada lote.

## Atualizar a base (uma vez por ano)

1. No GeoSampa: Camadas → pesquise "Lote" → ícone (i) → botão **IPTU** → pasta XLS CSV → baixe `IPTU_<ano>.zip`.
2. Rode `uv run --no-project --with shapely python zona.py` (baixa lotes e zonas do GeoSampa e gera `zonas.json`; leva alguns minutos).
3. Rode `python prep.py IPTU_<ano>.zip 500` (gera `terrenos.json` já com o zoneamento).
4. Faça commit e push do novo `terrenos.json`.
5. Publique no Cloudflare Pages (projeto `conferencia-areas`, separado do financeiro), enviando só os arquivos do site:
   `mkdir dist && cp index.html match.js terrenos.json dist/ && npx wrangler pages deploy dist --project-name conferencia-areas --branch main`

Teste da busca: `node test.js`.

Quando o lote fica em mais de uma zona, aparecem as que cobrem ao menos 10% dele, a maior primeiro.
