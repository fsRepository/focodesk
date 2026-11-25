# Pester 5 (Windows PowerShell 5.1):  Invoke-Pester installer\tests\deploy-focodesk.Tests.ps1
BeforeAll {
  $script:Deploy = Join-Path $PSScriptRoot "..\deploy-focodesk.ps1"
  $script:PS = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"

  # carrega so as funcoes do script (sem executar a instalacao)
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Deploy, [ref]$null, [ref]$null)
  $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
    ForEach-Object { . ([scriptblock]::Create($_.Extent.Text)) }

  function Invoke-Validate([string]$Doc, [string]$EnvName = "FOCODESK_DOC") {
    $old = @{ DOC = $env:FOCODESK_DOC; CNPJ = $env:FOCODESK_CNPJ }
    $env:FOCODESK_DOC = $null; $env:FOCODESK_CNPJ = $null
    Set-Item -Path "Env:$EnvName" -Value $Doc
    try {
      & $script:PS -NoProfile -ExecutionPolicy Bypass -File $script:Deploy -ValidateOnly | Out-Null
      return $LASTEXITCODE
    } finally {
      $env:FOCODESK_DOC = $old.DOC; $env:FOCODESK_CNPJ = $old.CNPJ
    }
  }
}

Describe "documento (CPF ou CNPJ)" {
  It "aceita CPF com e sem mascara" {
    Invoke-Validate "529.982.247-25" | Should -Be 0
    Invoke-Validate "52998224725" | Should -Be 0
  }
  It "recusa CPF com digito verificador errado" {
    Invoke-Validate "529.982.247-24" | Should -Be 1
  }
  It "recusa CPF com todos os digitos iguais" {
    Invoke-Validate "111.111.111-11" | Should -Be 1
  }
  It "aceita CNPJ" {
    Invoke-Validate "11.222.333/0001-81" | Should -Be 0
  }
  It "aceita o documento pela variavel antiga FOCODESK_CNPJ" {
    Invoke-Validate "11222333000181" "FOCODESK_CNPJ" | Should -Be 0
  }
  It "recusa documento vazio" {
    Invoke-Validate "" | Should -Be 1
  }
  It "ConvertTo-Documento normaliza e devolve CPF de 11 digitos" {
    ConvertTo-Documento "529.982.247-25" | Should -Be "52998224725"
  }
}

Describe "alias" {
  It "tira espacos das pontas" {
    ConvertTo-Alias "  Caixa 01  " | Should -Be "Caixa 01"
  }
  It "limita a 40 caracteres" {
    (ConvertTo-Alias ("a" * 41)).Length | Should -Be 40
  }
  It "texto so com espacos vira vazio" {
    ConvertTo-Alias "    " | Should -Be ""
  }
  It "remove caracteres de controle" {
    ConvertTo-Alias "Cai`nxa" | Should -Be "Caixa"
  }
  It "mantem acentos" {
    ConvertTo-Alias "Padaria São João" | Should -Be "Padaria São João"
  }
}
