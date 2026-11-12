# ============================================================
#  FocoDesk - deploy por maquina (senha UNICA por maquina)
#
#  O que faz:
#   1. instala o FocoDesk como servico (inicia com o Windows)
#   2. gera uma senha aleatoria (criptograficamente segura) so desta maquina
#   3. define essa senha para acesso nao supervisionado
#   4. le o ID da maquina e registra {id, senha, hostname, cliente} na API da Foco
#
#  Pode ser executado de novo na mesma maquina: gera uma senha nova e atualiza a API.
#
#  Como usar (PowerShell como ADMINISTRADOR), na pasta extraida do artifact
#  "focodesk-windows-..." (onde esta o FocoDesk.exe e as DLLs):
#     powershell -ExecutionPolicy Bypass -File .\deploy-focodesk.ps1 -Cnpj "11.222.333/0001-81" -ClientRef "Loja Centro"
#
#  -Cnpj       obrigatorio: CNPJ do cliente (com ou sem mascara). E o vinculo com o sistema de gestao.
#              Use o CNPJ da unidade onde a maquina esta (filial = CNPJ da filial).
#  -ClientRef  opcional: nome livre so para exibicao (ex.: "Loja Centro").
#
#  Codigos de saida: 0 ok | 1 falha na instalacao/ID/senha | 2 falha ao registrar na API
#                    3 API recusou (device_secret nao confere - peca ao admin para liberar o ID)
#
#  IMPORTANTE: o arquivo FocoDesk.exe precisa se chamar exatamente FocoDesk.exe
#  (o instalador do RustDesk nao renomeia o executavel na instalacao).
# ============================================================
param(
  [string]$Cnpj = "",
  [string]$ClientRef = "",
  [string]$DeployToken = "",
  [switch]$ValidateOnly
)

# CNPJ e token tambem podem vir por variavel de ambiente (usado pelo instalador FocoDesk-Setup.exe,
# assim nada fica na linha de comando nem escrito dentro deste arquivo).
if (-not $Cnpj)        { $Cnpj        = $env:FOCODESK_CNPJ }
if (-not $DeployToken) { $DeployToken = $env:FOCODESK_DEPLOY_TOKEN }

# --- CONFIG (ajuste) ---
$ApiUrl      = "https://api.focodesk.focosistemas.com.br/focodesk/register"
$DeployTokenDefault = "TROQUE_PELO_TOKEN_DE_DEPLOY"   # prefira passar -DeployToken ou FOCODESK_DEPLOY_TOKEN; nunca suba este arquivo preenchido
# -----------------------

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$DataDir = Join-Path $env:ProgramData "FocoDesk"
$LogFile = Join-Path $DataDir "deploy.log"
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

function Log([string]$msg) {
  $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
  Write-Host "[FocoDesk] $msg"
  Add-Content -Path $LogFile -Value $line
}

# --- CNPJ: normaliza e valida os digitos verificadores (aceita CNPJ alfanumerico) ---
function Get-CnpjDv([string]$base, [int[]]$weights) {
  $sum = 0
  for ($i = 0; $i -lt $base.Length; $i++) { $sum += ([int][char]$base[$i] - 48) * $weights[$i] }
  $r = $sum % 11
  if ($r -lt 2) { return 0 } else { return (11 - $r) }
}
function ConvertTo-Cnpj([string]$v) {
  $c = ($v -replace '[^0-9A-Za-z]', '').ToUpper()
  if ($c -notmatch '^[0-9A-Z]{12}[0-9]{2}$') { return $null }
  if ($c -match '^(\d)\1{13}$') { return $null }
  $w1 = @(5,4,3,2,9,8,7,6,5,4,3,2)
  $w2 = @(6,5,4,3,2,9,8,7,6,5,4,3,2)
  $base = $c.Substring(0, 12)
  $d1 = Get-CnpjDv -base $base -weights $w1
  $d2 = Get-CnpjDv -base ($base + [string]$d1) -weights $w2
  $dvs = "$d1$d2"
  if ($c.EndsWith($dvs)) { return $c } else { return $null }
}
$CnpjN = ConvertTo-Cnpj $Cnpj
if (-not $CnpjN) {
  Write-Host "[FocoDesk] ERRO: informe um CNPJ valido com -Cnpj (ex.: -Cnpj ""11.222.333/0001-81"")."
  exit 1
}

if ($ValidateOnly) { exit 0 }

# --- precisa ser administrador ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host "[FocoDesk] ERRO: execute o PowerShell como Administrador."
  exit 1
}

if (-not $DeployToken) { $DeployToken = $DeployTokenDefault }
if ($DeployToken -like "TROQUE_*") {
  Write-Host "[FocoDesk] ERRO: informe o token com -DeployToken (ou a variavel FOCODESK_DEPLOY_TOKEN)."
  exit 1
}

$Src = Join-Path $PSScriptRoot "FocoDesk.exe"
if (-not (Test-Path $Src)) {
  Log "ERRO: FocoDesk.exe nao encontrado em $PSScriptRoot (o executavel precisa se chamar FocoDesk.exe)."
  exit 1
}

# Pasta de instalacao (mesmo se o PowerShell for de 32 bits)
$PF = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$Installed = Join-Path $PF "FocoDesk\FocoDesk.exe"

# ---------- 1) instalar ----------
$svc = Get-Service -Name "FocoDesk" -ErrorAction SilentlyContinue
if ((-not $svc) -or (-not (Test-Path $Installed))) {
  Log "Instalando (servico + inicia com o Windows)..."
  # NAO usar "& exe | Out-Null": o FocoDesk deixa processos filhos vivos que herdam o pipe e o
  # PowerShell ficaria esperando para sempre. Start-Process nao herda o pipe; esperamos pelo servico.
  Start-Process -FilePath $Src -ArgumentList "--silent-install" -WindowStyle Hidden | Out-Null
} else {
  Log "FocoDesk ja instalado; pulando a instalacao."
}

# espera o servico existir e ficar em execucao (ate 90s)
$ok = $false
for ($i = 0; $i -lt 45; $i++) {
  $svc = Get-Service -Name "FocoDesk" -ErrorAction SilentlyContinue
  if ($svc -and $svc.Status -eq "Running" -and (Test-Path $Installed)) { $ok = $true; break }
  if ($svc -and $svc.Status -ne "Running") { try { Start-Service -Name "FocoDesk" } catch { } }
  Start-Sleep -Seconds 2
}
if (-not $ok) {
  Log "ERRO: o servico FocoDesk nao ficou em execucao (ou $Installed nao existe)."
  exit 1
}
Start-Sleep -Seconds 5   # deixa o instalador terminar atalhos e registro antes de definir a senha

# ---------- 2) senha aleatoria ----------
function New-RandomPassword([int]$Length = 24) {
  # alfabeto sem caracteres ambiguos (0/O, 1/l/I)
  $alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789".ToCharArray()
  $limit = 256 - (256 % $alphabet.Length)   # descarta bytes enviesados
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  $sb = New-Object System.Text.StringBuilder
  $buf = New-Object byte[] 1
  while ($sb.Length -lt $Length) {
    $rng.GetBytes($buf)
    if ($buf[0] -lt $limit) { [void]$sb.Append($alphabet[$buf[0] % $alphabet.Length]) }
  }
  $rng.Dispose()
  return $sb.ToString()
}

# ---------- 3) device_secret (prova de que e a mesma maquina nas proximas atualizacoes) ----------
$SecretFile = Join-Path $DataDir "device.secret"
if (-not (Test-Path $SecretFile)) {
  $b = New-Object byte[] 32
  $r = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  $r.GetBytes($b); $r.Dispose()
  Set-Content -Path $SecretFile -Value (($b | ForEach-Object { $_.ToString("x2") }) -join "") -NoNewline
}
# so SYSTEM e Administradores leem (SIDs, funciona em qualquer idioma do Windows)
& icacls.exe $DataDir /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" | Out-Null
$DeviceSecret = (Get-Content -Path $SecretFile -Raw).Trim()

# ---------- 4) definir senha ----------
$Senha = New-RandomPassword 24
Log "Definindo a senha unica desta maquina..."
& $Installed --password $Senha | Out-Null
Start-Sleep -Seconds 3

# ---------- 5) ler o ID ----------
$Id = ""
for ($i = 0; $i -lt 20; $i++) {
  $out = (& $Installed --get-id | Out-String)
  if ($out -match "(\d{6,12})") { $Id = $Matches[1]; break }
  Start-Sleep -Seconds 3
}
if (-not $Id) {
  Log "ERRO: nao consegui ler o ID desta maquina."
  exit 1
}
Log "ID da maquina: $Id"

# ---------- 6) registrar na API (com tentativas) ----------
$Body = @{
  id            = $Id
  password      = $Senha
  hostname      = $env:COMPUTERNAME
  cnpj          = $CnpjN
  device_secret = $DeviceSecret
}
if ($ClientRef) { $Body["client_ref"] = $ClientRef }
$Json = $Body | ConvertTo-Json -Compress
$Bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)

$delay = 5
for ($try = 1; $try -le 5; $try++) {
  try {
    Invoke-RestMethod -Uri $ApiUrl -Method Post `
      -Headers @{ Authorization = "Bearer $DeployToken" } `
      -ContentType "application/json; charset=utf-8" -Body $Bytes | Out-Null
    Log "OK: maquina registrada na Foco. ID=$Id Hostname=$($env:COMPUTERNAME) CNPJ=$CnpjN"
    $Senha = $null
    exit 0
  } catch {
    $status = $null
    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
    if ($status -eq 403) {
      Log "ERRO: a API recusou (403). Este ID ja esta registrado com outro device_secret. Peca ao admin para liberar o ID $Id e rode de novo."
      exit 3
    }
    if ($status -eq 401) {
      Log "ERRO: DeployToken invalido (401)."
      exit 2
    }
    Log "Tentativa $try/5 falhou (HTTP $status). Aguardando $delay s..."
    Start-Sleep -Seconds $delay
    $delay = $delay * 2
  }
}

# A senha so existe na memoria deste script: se nao registrou, rode o script de novo (gera outra senha).
Log "ERRO: instalou e definiu a senha, mas nao conseguiu registrar na API. Rode o script novamente."
exit 2
