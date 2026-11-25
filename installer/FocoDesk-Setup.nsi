; ============================================================
;  FocoDesk - instalador unico (NSIS)
;
;  Uso:
;    duplo clique                      -> pede o CPF ou CNPJ do cliente e o nome da maquina (alias)
;    FocoDesk-Setup.exe /S /DOC=11222333000181 /ALIAS="Caixa01"   -> silencioso (/CNPJ= continua valendo)
;    FocoDesk-Setup-11222333000181.exe -> le o CPF/CNPJ (11 ou 14 caracteres) do nome do arquivo
;    Alias em branco: a API usa o nome do computador (e mantem o alias ja cadastrado numa reinstalacao).
;
;  Por baixo executa deploy-focodesk.ps1 (instala o servico, define senha aleatoria
;  e registra na API). Codigos de saida: 0 ok | 1 falha de instalacao/ID | 2 falha na API
;  | 3 CPF/CNPJ ausente/invalido | 4 token de deploy invalido (nao deveria ocorrer).
;
;  Build (defines obrigatorios):
;    makensis /DDEPLOY_TOKEN=... /DDIST_DIR=C:\caminho\focodesk-dist /DICON=C:\caminho\icon.ico /DOUTFILE=C:\caminho\FocoDesk-Setup.exe FocoDesk-Setup.nsi
;  DIST_DIR = pasta com FocoDesk.exe + DLLs + deploy-focodesk.ps1
; ============================================================
Unicode true
!include "MUI2.nsh"
!include "nsDialogs.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "x64.nsh"

!ifndef DEPLOY_TOKEN
  !error "Defina /DDEPLOY_TOKEN=..."
!endif
!ifndef DIST_DIR
  !error "Defina /DDIST_DIR=..."
!endif
!ifndef OUTFILE
  !define OUTFILE "FocoDesk-Setup.exe"
!endif

Name "FocoDesk"
OutFile "${OUTFILE}"
BrandingText "Foco Sistemas"
RequestExecutionLevel admin
InstallDir "$TEMP\focodesk-setup"
ShowInstDetails show
SetCompressor /SOLID lzma

!ifdef ICON
  !define MUI_ICON "${ICON}"
!endif
!define MUI_FINISHPAGE_TITLE "FocoDesk instalado"
!define MUI_FINISHPAGE_TEXT "O acesso remoto da Foco Sistemas foi instalado e registrado nesta maquina.$\r$\n$\r$\nO suporte ja pode se conectar."

Var DocNum
Var MachineAlias
Var DocEdit
Var AliasEdit
Var Dlg

; --- paginas ---
Page custom DocPageCreate DocPageLeave
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_LANGUAGE "PortugueseBR"

; Valida $DocNum (CPF ou CNPJ) com o proprio deploy-focodesk.ps1 (-ValidateOnly). Resultado em $0 (0 = valido).
; O documento vai por variavel de ambiente: nada digitado pelo usuario chega a linha de comando.
Function RunValidate
  ; entrada: $DocNum ; saida: $0 = codigo de saida do PowerShell
  System::Call 'kernel32::SetEnvironmentVariable(t "FOCODESK_DOC", t "$DocNum")'
  ${If} ${RunningX64}
    StrCpy $1 "$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
  ${Else}
    StrCpy $1 "$SYSDIR\WindowsPowerShell\v1.0\powershell.exe"
  ${EndIf}
  nsExec::ExecToStack '"$1" -NoProfile -ExecutionPolicy Bypass -File "$PLUGINSDIR\deploy.ps1" -ValidateOnly'
  Pop $0
  Pop $2
FunctionEnd

Function DocFromFileName
  ; FocoDesk-Setup-<11 ou 14 caracteres>.exe -> pega o trecho depois do ultimo "-" (sem a extensao).
  ; Qualquer outro tamanho (ex.: "FocoDesk-Setup (1).exe") e ignorado e cai na pergunta.
  System::Call 'kernel32::GetModuleFileName(p 0, t .r1, i ${NSIS_MAX_STRLEN})'
  ${GetFileName} $1 $2
  StrLen $3 $2
  IntOp $3 $3 - 4
  ${If} $3 > 0
    StrCpy $2 $2 $3
    StrCpy $4 $3
    ${DoWhile} $4 > 0
      IntOp $4 $4 - 1
      StrCpy $5 $2 1 $4
      ${If} $5 == "-"
        IntOp $4 $4 + 1
        StrCpy $6 $2 "" $4
        StrLen $7 $6
        ${If} $7 == 11
        ${OrIf} $7 == 14
          StrCpy $DocNum $6
        ${EndIf}
        ${Break}
      ${EndIf}
    ${Loop}
  ${EndIf}
FunctionEnd

Function .onInit
  InitPluginsDir
  File "/oname=$PLUGINSDIR\deploy.ps1" "${DIST_DIR}\deploy-focodesk.ps1"

  ${GetParameters} $R0
  ClearErrors
  ${GetOptions} $R0 "/DOC=" $DocNum
  ${If} ${Errors}
    ClearErrors
    ${GetOptions} $R0 "/CNPJ=" $DocNum
    ${If} ${Errors}
      StrCpy $DocNum ""
    ${EndIf}
  ${EndIf}
  ClearErrors
  ${GetOptions} $R0 "/ALIAS=" $MachineAlias
  ${If} ${Errors}
    StrCpy $MachineAlias ""
  ${EndIf}
  ${If} $DocNum == ""
    Call DocFromFileName
  ${EndIf}

  ${If} $DocNum != ""
    Call RunValidate
    ${If} $0 != 0
      StrCpy $DocNum ""      ; invalido: cai para a pergunta (modo normal) ou erro (silencioso)
    ${EndIf}
  ${EndIf}

  ${If} $DocNum == ""
  ${AndIf} ${Silent}
    SetErrorLevel 3
    Abort
  ${EndIf}
FunctionEnd

Function DocPageCreate
  ${If} ${Silent}
    Abort                  ; modo silencioso nunca pergunta
  ${EndIf}
  ${If} $DocNum != ""
  ${AndIf} $MachineAlias != ""
    Abort                  ; documento e alias ja vieram por parametro: nao mostra a pagina
  ${EndIf}
  !insertmacro MUI_HEADER_TEXT "FocoDesk - Acesso remoto" "Identifique o cliente e esta maquina"
  nsDialogs::Create 1018
  Pop $Dlg
  ${NSD_CreateLabel} 0 0 100% 20u "CPF ou CNPJ do cliente onde este computador esta instalado (com ou sem pontuacao). Ele liga esta maquina ao cadastro do cliente."
  Pop $0
  ${NSD_CreateText} 0 22u 60% 12u "$DocNum"
  Pop $DocEdit
  SendMessage $DocEdit ${EM_SETLIMITTEXT} 18 0
  ${NSD_CreateLabel} 0 36u 100% 10u "Exemplo: 529.982.247-25 ou 11.222.333/0001-81"
  Pop $0
  ${NSD_CreateLabel} 0 54u 100% 10u "Nome desta maquina (opcional):"
  Pop $0
  ${NSD_CreateText} 0 66u 60% 12u "$MachineAlias"
  Pop $AliasEdit
  SendMessage $AliasEdit ${EM_SETLIMITTEXT} 40 0
  ${NSD_CreateLabel} 0 80u 100% 20u "Ex.: Servidor, Caixa01, Caixa02. Ajuda o suporte a saber qual computador acessar. Em branco, usa o nome do computador."
  Pop $0
  nsDialogs::Show
FunctionEnd

Function DocPageLeave
  ${NSD_GetText} $DocEdit $DocNum
  Call RunValidate
  ${If} $0 != 0
    StrCpy $DocNum ""
    MessageBox MB_ICONEXCLAMATION|MB_OK "CPF ou CNPJ invalido. Confira os numeros e tente de novo."
    Abort                  ; permanece na pagina
  ${EndIf}
  ${NSD_GetText} $AliasEdit $MachineAlias
FunctionEnd

Section "Instalar"
  SetOutPath "$INSTDIR"
  File /r "${DIST_DIR}\*.*"

  ; documento, alias e token por variavel de ambiente (nao ficam na linha de comando)
  System::Call 'kernel32::SetEnvironmentVariable(t "FOCODESK_DOC", t "$DocNum")'
  System::Call 'kernel32::SetEnvironmentVariable(t "FOCODESK_ALIAS", t "$MachineAlias")'
  System::Call 'kernel32::SetEnvironmentVariable(t "FOCODESK_DEPLOY_TOKEN", t "${DEPLOY_TOKEN}")'

  ${If} ${RunningX64}
    StrCpy $1 "$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
  ${Else}
    StrCpy $1 "$SYSDIR\WindowsPowerShell\v1.0\powershell.exe"
  ${EndIf}

  DetailPrint "Instalando o FocoDesk e registrando esta maquina..."
  nsExec::ExecToLog '"$1" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\deploy-focodesk.ps1"'
  Pop $0

  ${If} $0 != 0
    SetErrorLevel $0
    MessageBox MB_ICONSTOP|MB_OK "A instalacao nao foi concluida (codigo $0).$\r$\nVeja o arquivo C:\ProgramData\FocoDesk\deploy.log e avise o suporte da Foco." /SD IDOK
    Abort
  ${EndIf}

  SetOutPath "$TEMP"
  RMDir /r "$INSTDIR"
SectionEnd
