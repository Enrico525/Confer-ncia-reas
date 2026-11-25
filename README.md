# Conferência de Áreas — São Paulo

**🔗 Acesse o site: https://conferencia-areas.pages.dev/**

Página que recebe um PDF, Word ou lista de endereços e devolve, para cada terreno, o **SQL**, a **área do terreno** e o **zoneamento**, com exportação para Excel.

Dados: Cadastro Imobiliário Fiscal (IPTU) da Prefeitura de São Paulo, publicado no [GeoSampa](https://novogeosampa.prefeitura.sp.gov.br) — só terrenos com 500 m² ou mais. Zoneamento: mapa da Lei 18.081/24 (GeoSampa), cruzado com o desenho de cada lote.

## Atualizar a base (uma vez por ano)

**Automático (robô):** `robo-iptu.ps1` roda a cada 30 minutos pelo Agendador de Tarefas do Windows (instale uma vez com `powershell -ExecutionPolicy Bypass -File robo-iptu.ps1 -Instalar`).
- A cada 6 horas ele confere a ficha oficial do IPTU no GeoSampa. Quando a data de revisão muda de ano, ou a partir de 1º de março, avisa na tela e abre o GeoSampa.
- Você só baixa o `IPTU_<ano>.zip` (o GeoSampa bloqueia downloads por programa). Quando o zip aparece em Downloads, o robô faz os passos 2 a 5 abaixo, confere se a base nova não encolheu mais de 10%, testa e avisa se deu certo ou errado.
- Registro: `%LOCALAPPDATA%\robo-iptu\robo.log`. Para tentar de novo depois de um erro: `powershell -ExecutionPolicy Bypass -File robo-iptu.ps1 -Forcar`.

**Na mão:**

1. No GeoSampa: Camadas → pesquise "Lote" → ícone (i) → botão **IPTU** → pasta XLS CSV → baixe `IPTU_<ano>.zip`.
2. Rode `uv run --no-project --with shapely python zona.py` (baixa lotes e zonas do GeoSampa e gera `zonas.json`; leva alguns minutos).
3. Rode `python prep.py IPTU_<ano>.zip 500` (gera `terrenos.json` já com o zoneamento).
4. Faça commit e push do novo `terrenos.json`.
5. Publique no Cloudflare Pages (projeto `conferencia-areas`, separado do financeiro) com `bash deploy.sh`. Ele envia só os arquivos do site e gera o aviso de novidade.

Teste da busca: `node test.js`.

Aviso de novidade: sai sozinho a cada publicação com `bash deploy.sh`. O texto é a mensagem do último commit, então escreva-a pensando em quem usa o site. Cada pessoa vê o aviso uma vez, até clicar em "Entendi".

Quando o lote fica em mais de uma zona, aparecem as que cobrem ao menos 10% dele, a maior primeiro.
