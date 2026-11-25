# Robô do IPTU: avisa quando a Prefeitura publica o cadastro novo e, quando o zip aparece em Downloads,
# atualiza a base, testa, faz commit, push e publica o site sozinho.
#   Instalar (uma vez):  powershell -ExecutionPolicy Bypass -File robo-iptu.ps1 -Instalar
#   Rodar na mão:        powershell -ExecutionPolicy Bypass -File robo-iptu.ps1 [-Forcar]
param([switch]$Instalar, [switch]$Forcar)
$ErrorActionPreference = "Stop"
$Repo = $PSScriptRoot
$Estado = Join-Path $env:LOCALAPPDATA "robo-iptu"
New-Item -ItemType Directory -Force $Estado | Out-Null
$Log = Join-Path $Estado "robo.log"
$Uv = Join-Path $env:USERPROFILE ".local\bin\uv.exe"
$Bash = "C:\Program Files\Git\bin\bash.exe"
$Ficha = "https://metadados.geosampa.prefeitura.sp.gov.br/geonetwork/srv/api/records/b971efa1-aad5-42f3-ad28-18f1f4efe270"
$GeoSampa = "https://geosampa.prefeitura.sp.gov.br/"

if ($Instalar) {
  $acao = New-ScheduledTaskAction -Execute "powershell.exe" -WorkingDirectory $Repo `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  $gatilhos = @(
    (New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME),
    (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 30))
  )
  $cfg = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)
  Register-ScheduledTask -TaskName "Robo IPTU - Conferencia de Areas" -Action $acao -Trigger $gatilhos -Settings $cfg -Force | Out-Null
  Write-Output "Robô instalado: roda a cada 30 minutos e ao entrar no Windows. Registro em $Log"
  exit
}

function Registra($m) { Add-Content $Log "$(Get-Date -Format s) $m" -Encoding utf8 }
function Aviso($titulo, $texto, $botoes = "OK") {
  Add-Type -AssemblyName System.Windows.Forms
  $dono = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }  # para a janela não ficar escondida atrás das outras
  [System.Windows.Forms.MessageBox]::Show($dono, $texto, $titulo, $botoes, "Information")
}
# Roda um comando, guardando a saída no registro; para tudo se ele falhar.
function Roda($cmd) {
  Registra "> $cmd"
  cmd /c "$cmd >> `"$Log`" 2>&1"
  if ($LASTEXITCODE) { throw "O passo falhou: $cmd" }
}
function Le($nome) { $f = Join-Path $Estado $nome; if (Test-Path $f) { (Get-Content $f -Raw).Trim() } else { "" } }
function Grava($nome, $valor) { Set-Content (Join-Path $Estado $nome) $valor -Encoding utf8 }

Set-Location $Repo
# terrenos.json tem uma linha só de 13 MB: lê só o começo para achar o ano.
$fs = [IO.File]::OpenRead((Join-Path $Repo "terrenos.json"))
$buf = New-Object byte[] 100; [void]$fs.Read($buf, 0, 100); $fs.Close()
$anoBase = [int]([regex]::Match([Text.Encoding]::UTF8.GetString($buf), '"ano":"(\d{4})"').Groups[1].Value)

function Atualiza($zip, $ano) {
  Registra "Atualizando com $($zip.FullName)"
  $antes = [int](node -e "console.log(require('./terrenos.json').rows.length)")
  try {
    Roda "`"$Uv`" run --no-project --with shapely python zona.py"
    Roda "`"$Uv`" run --no-project python prep.py `"$($zip.FullName)`" 500"
    $info = node -e "const d=require('./terrenos.json');console.log(d.ano+' '+d.rows.length)"
    $anoNovo, $depois = $info -split " "
    if ($anoNovo -ne "$ano") { throw "O arquivo gerado diz exercício $anoNovo, mas o zip é de $ano." }
    # Proteção contra base quebrada: a cidade não perde 10% dos terrenos grandes de um ano para outro.
    if ([int]$depois -lt $antes * 0.9) { throw "A base nova tem $depois terrenos, bem menos que os $antes atuais." }
    Roda "node test.js"
    $msg = Join-Path $Estado "commit.txt"
    [IO.File]::WriteAllText($msg, "A base agora usa o cadastro do IPTU $ano, com áreas e zoneamento atualizados", (New-Object Text.UTF8Encoding $false))
    Roda "git add terrenos.json zonas.json"
    Roda "git commit -F `"$msg`""
    Roda "git push"
    Roda "`"$Bash`" deploy.sh"
  } catch {
    Registra "ERRO: $_"
    if (-not (git log -1 --format=%s | Select-String "IPTU $ano")) { cmd /c "git checkout -- terrenos.json zonas.json 2>nul" }
    Aviso "Robô do IPTU: deu erro" "Não consegui atualizar o site com o IPTU $ano.`n`n$_`n`nDetalhes em: $Log"
    return
  }
  Registra "Site atualizado com o IPTU $ano ($depois terrenos)."
  Aviso "Robô do IPTU" "Pronto! O site agora usa o cadastro do IPTU $ano ($depois terrenos). Quem abrir o site vai ver o aviso de novidade."
}

# 1) Zip novo em Downloads? Atualiza na hora.
$downloads = (New-Object -ComObject Shell.Application).NameSpace("shell:Downloads").Self.Path
$zip = Get-ChildItem $downloads -Filter "IPTU_*.zip" -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match '^IPTU_(\d{4})\.zip$' -and [int]$Matches[1] -gt $anoBase -and $_.LastWriteTime -lt (Get-Date).AddMinutes(-1) } |
  Sort-Object Name -Descending | Select-Object -First 1
if ($zip) {
  $ano = [int]($zip.Name -replace '\D', '')
  $marca = "$($zip.Name)|$($zip.Length)|$($zip.LastWriteTime.Ticks)"
  if ($Forcar -or (Le "tentado.txt") -ne $marca) {
    Grava "tentado.txt" $marca  # não repete a cada 30 min se der erro; use -Forcar para tentar de novo
    Atualiza $zip $ano
  }
  exit
}

# 2) Saiu o cadastro novo? Confere a ficha oficial do IPTU no GeoSampa a cada 6 horas.
$ultima = Le "ultima-checagem.txt"
if (-not $Forcar -and $ultima -and ((Get-Date) - [datetime]$ultima).TotalHours -lt 6) { exit }
Grava "ultima-checagem.txt" (Get-Date -Format s)
$anoSaiu = 0
try {
  $xml = (Invoke-WebRequest $Ficha -UseBasicParsing -Headers @{ Accept = "application/xml" } -TimeoutSec 60).Content
  # A data de "revisão" da ficha muda quando a Prefeitura publica o IPTU do ano (2026: zip em 11/02, revisão em 19/02).
  $m = [regex]::Match($xml, '<gco:Date>(\d{4})-\d\d-\d\d</gco:Date>\s*</gmd:date>\s*<gmd:dateType>\s*<gmd:CI_DateTypeCode[^>]*codeListValue="revision"')
  if ($m.Success) { $anoSaiu = [int]$m.Groups[1].Value } else { Registra "Não achei a data de revisão na ficha do IPTU." }
} catch { Registra "Falha ao consultar a ficha do IPTU: $_" }

$proximo = $anoBase + 1
# Se a ficha não mudar, avisa mesmo assim a partir de março (o IPTU costuma sair em fevereiro).
$prazo = (Get-Date) -ge (Get-Date -Year $proximo -Month 3 -Day 1)
if (($anoSaiu -ge $proximo -or $prazo) -and (Le "avisado.txt") -ne "$proximo") {
  Grava "avisado.txt" "$proximo"
  $txt = if ($anoSaiu -ge $proximo) { "Parece que a Prefeitura publicou o cadastro do IPTU $proximo." } else { "Já é março: o cadastro do IPTU $proximo deve ter saído." }
  $r = Aviso "Robô do IPTU" "$txt`n`nNo GeoSampa: Camadas > pesquise ""Lote"" > ícone (i) > botão IPTU > pasta XLS CSV > baixe IPTU_$proximo.zip.`nDeixe o arquivo em Downloads: o robô faz o resto sozinho.`n`nAbrir o GeoSampa agora?" "YesNo"
  if ("$r" -eq "Yes") { Start-Process $GeoSampa }
  Registra "Avisou sobre o IPTU $proximo."
}
