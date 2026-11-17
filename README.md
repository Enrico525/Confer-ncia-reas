# Conferência de Áreas — São Paulo

**🔗 Acesse o site: https://conferencia-areas.pages.dev/**

Página que recebe um PDF, Word ou lista de endereços e devolve, para cada terreno, o **SQL**, a **área do terreno**, a área construída e um **IPTU estimado**, com exportação para Excel.

Dados: Cadastro Imobiliário Fiscal (IPTU) da Prefeitura de São Paulo, publicado no [GeoSampa](https://novogeosampa.prefeitura.sp.gov.br) — só terrenos com 500 m² ou mais.

## Atualizar a base (uma vez por ano)

1. No GeoSampa: Camadas → pesquise "Lote" → ícone (i) → botão **IPTU** → pasta XLS CSV → baixe `IPTU_<ano>.zip`.
2. Rode `python prep.py IPTU_<ano>.zip 500` (gera `terrenos.json`).
3. Faça commit e push do novo `terrenos.json`.
4. Publique no Cloudflare Pages (projeto `conferencia-areas`, separado do financeiro), enviando só os arquivos do site:
   `mkdir dist && cp index.html match.js terrenos.json dist/ && npx wrangler pages deploy dist --project-name conferencia-areas --branch main`

Teste da busca: `node test.js`.

O IPTU estimado é área × valor do m² do terreno × 1,5% — aproximação; o valor exato depende de descontos, isenções e da trava anual de reajuste.
