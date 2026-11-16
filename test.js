// node test.js — checa a busca de endereços com uma base de exemplo.
const assert = require("assert");
const { buildIndex, lookup, extractAddresses } = require("./match.js");

const idx = buildIndex({
  cols: ["sql", "logradouro", "numero", "complemento", "bairro", "cep", "area", "ac", "vm2", "n"],
  rows: [
    ["085.123.0001-1", "AV DAS NACOES UNIDAS", "12901", "", "BROOKLIN", "04578-000", 25000, 0, 3000, 1],
    ["010.020.0030-4", "R VINTE E CINCO DE MARCO", "100", "", "SE", "01021-000", 1200, 800, 5000, 1],
    ["020.030.0040-5", "R 25 DE MARCO", "300", "", "SE", "01021-000", 1500, 0, 5000, 1],
    ["030.040.0050-6", "R DR ARNALDO", "455", "", "CERQUEIRA CESAR", "01246-903", 9000, 5000, 4000, 1],
  ],
});

assert.strictEqual(lookup(idx, "Avenida das Nações Unidas, 12901").status, "Encontrado");
assert.strictEqual(lookup(idx, "Av. Nações Unidas nº 12901 - Brooklin").hits[0].sql, "085.123.0001-1");
assert.strictEqual(lookup(idx, "Rua 25 de Março, 300").hits[0].sql, "020.030.0040-5"); // número no nome da rua
assert.strictEqual(lookup(idx, "Rua Doutor Arnaldo 455").status, "Encontrado");      // título abreviado x por extenso
assert.match(lookup(idx, "Av Nacoes Unidas 12950").status, /^Aproximado/);
assert.strictEqual(lookup(idx, "Rua Inexistente 10").status, "Não encontrado");
assert.match(lookup(idx, "Av Nacoes Unidas 99999").status, /número não/);
assert.strictEqual(lookup(idx, "Rua Doutor Arnaldo Silva 455").status, "Não encontrado"); // só parte das palavras não basta
assert.strictEqual(lookup(idx, "Rua Dr Arnaldu 455").status, "Encontrado");             // 1 letra de diferença
assert.match(lookup(idx, "Av Nacoes Unidas km 12").status, /Sem número/);

const ext = extractAddresses("Imóvel 1: Avenida das Nações Unidas, 12901 - Área 25.000 m²\nTexto qualquer sobre a rua sem número\nR. Dr. Arnaldo, 455");
assert.strictEqual(ext.length, 2, ext);
console.log("ok");
