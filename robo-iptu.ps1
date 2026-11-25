# Robô do IPTU: roda só em 15 e 28 de fevereiro (ou assim que o computador ligar depois disso).
# Confere se a Prefeitura publicou o cadastro do IPTU do ano, avisa, espera o zip chegar em Downloads
# e atualiza a base, testa, faz commit, push e publica o site sozinho.
#   Instalar (uma vez):  powershell -ExecutionPolicy Bypass -File robo-iptu.ps1 -Instalar
#   Rodar na mão:        powershell -ExecutionPolicy Bypass -File robo-iptu.ps1 -Forcar
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
$Tarefa = "Robo IPTU - Conferencia de Areas"

if ($Instalar) {
  # conhost --headless: roda sem janela nenhuma, para ninguém fechar o robô sem querer no meio.
  $acao = New-ScheduledTaskAction -Execute "conhost.exe" -WorkingDirectory $Repo `
    -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  $cfg = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 4)
  # Os comandos do PowerShell não criam gatilho anual: monta a tarefa e troca o gatilho no XML.
  $tmp = New-ScheduledTask -Action $acao -Settings $cfg -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date))
  $xml = (Export-ScheduledTask -InputObject $tmp) -replace '(?s)<Triggers>.*</Triggers>', @"
<Triggers><CalendarTrigger><StartBoundary>2027-02-15T10:00:00</StartBoundary><Enabled>true</Enabled>
<ScheduleByMonth><DaysOfMonth><Day>15</Day><Day>28</Day></DaysOfMonth><Months><February /></Months></ScheduleByMonth>
</CalendarTrigger></Triggers>
"@
  Register-ScheduledTask -TaskName $Tarefa -Xml $xml -Force | Out-Null
  Write-Output "Robô instalado: roda em 15 e 28 de fevereiro às 10h (ou ao ligar o computador, se estiver desligado). Registro em $Log"
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
$downloads = (New-Object -ComObject Shell.Application).NameSpace("shell:Downloads").Self.Path

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

# Zip mais novo que a base em Downloads (ignora o que ainda está baixando e o que já deu erro, salvo -Forcar).
function AchaZip {
  $z = Get-ChildItem $downloads -Filter "IPTU_*.zip" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^IPTU_(\d{4})\.zip$' -and [int]$Matches[1] -gt $anoBase -and $_.LastWriteTime -lt (Get-Date).AddMinutes(-1) } |
    Sort-Object Name -Descending | Select-Object -First 1
  if ($z -and ($Forcar -or (Le "tentado.txt") -ne "$($z.Name)|$($z.Length)|$($z.LastWriteTime.Ticks)")) { $z }
}
function Processa($z) {
  Atualiza $z ([int]($z.Name -replace '\D', ''))
  # Marca só no fim: se o computador desligar no meio, tenta de novo na próxima vez; se deu erro, não repete (use -Forcar).
  Grava "tentado.txt" "$($z.Name)|$($z.Length)|$($z.LastWriteTime.Ticks)"
}

# 1) Um zip mais novo que a base já está em Downloads? Atualiza na hora, seja qual for a data.
$zip = AchaZip
if ($zip) { Processa $zip; exit }

$alvo = (Get-Date).Year
if ($anoBase -ge $alvo) { Registra "A base já é do IPTU $anoBase. Nada a fazer."; exit }

# 2) Saiu o cadastro do ano? Confere a ficha oficial do IPTU no GeoSampa (serviço público, sem bloqueio).
$anoSaiu = 0
try {
  $xml = (Invoke-WebRequest $Ficha -UseBasicParsing -Headers @{ Accept = "application/xml" } -TimeoutSec 60).Content
  # A data de "revisão" da ficha muda quando a Prefeitura publica o IPTU do ano (2026: zip em 11/02, revisão em 19/02).
  $m = [regex]::Match($xml, '<gco:Date>(\d{4})-\d\d-\d\d</gco:Date>\s*</gmd:date>\s*<gmd:dateType>\s*<gmd:CI_DateTypeCode[^>]*codeListValue="revision"')
  if ($m.Success) { $anoSaiu = [int]$m.Groups[1].Value } else { Registra "Não achei a data de revisão na ficha do IPTU." }
} catch { Registra "Falha ao consultar a ficha do IPTU: $_" }

# Na rodada do fim do mês (ou rodando na mão) avisa mesmo que a ficha não tenha mudado: o IPTU costuma sair em fevereiro.
$fimDoMes = (Get-Date).Month -gt 2 -or (Get-Date).Day -ge 25
if ($anoSaiu -lt $alvo -and -not $fimDoMes -and -not $Forcar) { Registra "IPTU $alvo ainda não saiu (ficha: $anoSaiu)."; exit }

$txt = if ($anoSaiu -ge $alvo) { "A Prefeitura publicou o cadastro do IPTU $alvo." } else { "O cadastro do IPTU $alvo já deve ter saído." }
$r = Aviso "Robô do IPTU" "$txt`n`nNo GeoSampa: Camadas > pesquise ""Lote"" > ícone (i) > botão IPTU > pasta XLS CSV > baixe IPTU_$alvo.zip.`nDeixe o arquivo em Downloads: nas próximas 3 horas o robô percebe e faz o resto sozinho.`n`nAbrir o GeoSampa agora?" "YesNo"
Registra "Avisou sobre o IPTU $alvo (resposta: $r)."
if ("$r" -ne "Yes") { exit }
Start-Process $GeoSampa

# 3) Espera o download por até 3 horas, olhando a pasta a cada 30 segundos.
$limite = (Get-Date).AddHours(3)
while ((Get-Date) -lt $limite) {
  Start-Sleep -Seconds 30
  $zip = AchaZip
  if ($zip) { Processa $zip; exit }
}
Registra "O zip do IPTU $alvo não apareceu em Downloads em 3 horas."
Aviso "Robô do IPTU" "O arquivo IPTU_$alvo.zip não apareceu em Downloads nas últimas 3 horas.`n`nQuando baixar, rode o robô na mão (veja o README) ou espere a próxima rodada."
