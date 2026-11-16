// Busca de endereços na base de terrenos. Usado pela página e pelo teste (node test.js).
const TIPOS = "RUA|R|AVENIDA|AV|AVN|ALAMEDA|AL|ESTRADA|ESTR|EST|ES|TRAVESSA|TV|TRV|PRACA|PC|PCA|RODOVIA|ROD|VIA|LARGO|LGO|LG|VIELA|VL|VIADUTO|VD|PASSAGEM|PSG|PARQUE|PQ|PRAIA|PR|BECO|BC|PONTE|PTE|VILA|JARDIM|JD|CAMINHO|CAM|TRAV|ESTRADA MUNICIPAL";
const TIPO_RE = new RegExp(`^(${TIPOS})\\b\\s*`);
const VAZIAS = new Set("DE DA DO DOS DAS E D".split(" "));
// Títulos abreviados em um lado e por extenso no outro; removidos para comparar.
const TITULOS = new Set("DR DOUTOR PROF PROFESSOR PROFA PROFESSORA ENG ENGENHEIRO CEL CORONEL GAL GEN GENERAL PRES PRESIDENTE SEN SENADOR DEP DEPUTADO MAL MARECHAL CAP CAPITAO TEN TENENTE STA SANTA STO SANTO S SAO CONS CONSELHEIRO BRIG BRIGADEIRO DQ DUQUE COM COMENDADOR VER VEREADOR DES DESEMBARGADOR PE PADRE FR FREI MONS MONSENHOR D DOM DONA ALM ALMIRANTE MAJ MAJOR GOV GOVERNADOR VISC VISCONDE BARAO BR".split(" "));

function norm(s) {
  return String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase()
    .replace(/[º°ª]/g, " ").replace(/[^A-Z0-9 ]/g, " ").replace(/\s+/g, " ").trim();
}
function ruaKey(nome) {
  let n = norm(nome);
  for (let i = 0; i < 2; i++) n = n.replace(TIPO_RE, ""); // "R AV" etc.
  n = n.replace(/( (N|NO|NUM|NUMERO))+$/, ""); // "nº" antes do número
  return n.split(" ").filter(t => t && !VAZIAS.has(t) && !TITULOS.has(t)).join(" ");
}

// d = { cols:[...], rows:[[...]] } gerado por prep.py
function buildIndex(d) {
  const c = Object.fromEntries(d.cols.map((k, i) => [k, i]));
  const ruas = new Map();
  for (const r of d.rows) {
    const h = { sql: r[c.sql], end: `${r[c.logradouro]}, ${r[c.numero]}${r[c.complemento] ? " " + r[c.complemento] : ""}`,
      bairro: r[c.bairro], cep: r[c.cep], num: +r[c.numero] || 0, area: r[c.area], ac: r[c.ac], vm2: r[c.vm2], n: r[c.n] };
    const k = ruaKey(r[c.logradouro]);
    if (!ruas.has(k)) ruas.set(k, []);
    ruas.get(k).push(h);
  }
  return { ruas, keys: [...ruas.keys()] };
}

function findRuas(idx, nome) {
  const k = ruaKey(nome);
  if (!k) return [];
  if (idx.ruas.has(k)) return [k];
  // Palavras batem se iguais ou com 1 letra de diferença (LUIS/LUIZ); exige ≥ 75% das palavras dos dois lados.
  const q = k.split(" ");
  let best = 0, out = [];
  for (const key of idx.keys) {
    const t = key.split(" ");
    const hit = q.filter(w => t.some(x => x === w || (w.length >= 4 && x.length >= 4 && lev1(w, x)))).length;
    const s = hit / Math.max(q.length, t.length);
    if (s > best) { best = s; out = [key]; } else if (s === best) out.push(key);
  }
  return best >= 0.75 && out.length <= 5 ? out : [];
}

function lev1(a, b) { // distância de edição ≤ 1
  if (Math.abs(a.length - b.length) > 1) return false;
  let i = 0, j = 0, d = 0;
  while (i < a.length && j < b.length) {
    if (a[i] === b[j]) { i++; j++; continue; }
    if (++d > 1) return false;
    if (a.length > b.length) i++; else if (b.length > a.length) j++; else { i++; j++; }
  }
  return d + (a.length - i) + (b.length - j) <= 1;
}

function lookup(idx, query) {
  // Endereço por km (rodovias): o cadastro usa outra numeração, então lista os terrenos da via.
  const q = String(query).replace(/\bkm\b.*$/i, "");
  // Tenta cada número do texto como "número do imóvel" (ruas como "25 de Março" têm número no nome).
  const nums = [...q.matchAll(/\d{1,6}/g)];
  let ruas = [], num = null;
  for (const m of nums) {
    const r = findRuas(idx, q.slice(0, m.index));
    if (r.length) { ruas = r; num = +m[0]; break; }
  }
  if (!ruas.length) { ruas = findRuas(idx, q.replace(/\d.*$/, "")); num = null; }
  if (!ruas.length) return { status: "Não encontrado", hits: [] };
  const all = ruas.flatMap(k => idx.ruas.get(k));
  if (num == null) return { status: "Sem número — terrenos da rua", hits: all.slice(0, 10) };
  const exact = all.filter(h => h.num === num);
  if (exact.length) return { status: "Encontrado", hits: exact };
  // Terrenos grandes ocupam vários números; aceita o cadastrado mais próximo até 100.
  const near = all.map(h => [Math.abs(h.num - num), h]).filter(([d]) => d <= 100).sort((a, b) => a[0] - b[0]);
  if (near.length) return { status: `Aproximado (nº ${near[0][1].num})`, hits: near.filter(([d]) => d === near[0][0]).map(([, h]) => h) };
  return { status: "Rua encontrada, número não — conferir", hits: [] };
}

const END_RE = new RegExp(`\\b(RUA|R\\.|AV\\.?|AVENIDA|ALAMEDA|AL\\.|ESTRADA|ESTR\\.|TRAVESSA|TV\\.|PRA[ÇC]A|P[ÇC]A\\.?|RODOVIA|ROD\\.|LARGO|VIELA)\\s[^\\n]{2,150}`, "gi"); // até o fim da linha; lookup() acha o número
function extractAddresses(text) {
  const out = new Set();
  for (const m of String(text).matchAll(END_RE)) if (/\d/.test(m[0])) out.add(m[0].replace(/\s+/g, " ").trim());
  if (!out.size) String(text).split(/\n/).map(s => s.trim()).filter(Boolean).forEach(s => out.add(s));
  return [...out];
}

if (typeof module !== "undefined") module.exports = { norm, ruaKey, buildIndex, lookup, extractAddresses };
