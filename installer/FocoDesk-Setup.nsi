; ============================================================
;  FocoDesk - instalador unico (NSIS)
;
;  Uso:
;    duplo clique                      -> pede o CNPJ do cliente
;    FocoDesk-Setup.exe /S /CNPJ=11222333000181        -> silencioso
;    FocoDesk-Setup-11222333000181.exe -> le o CNPJ do proprio nome do arquivo (sem perguntar)
;
;  Por baixo executa deploy-focodesk.ps1 (instala o servico, define senha aleatoria
;  e registra na API). Codigos de saida: 0 ok | 1 falha de instalacao/ID | 2 falha na API
;  | 3 CNPJ ausente/invalido | 4 token de deploy invalido (nao deveria ocorrer).
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

Var CNPJ
Var CnpjEdit
Var Dlg

; --- paginas ---
Page custom CnpjPageCreate CnpjPageLeave
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_LANGUAGE "PortugueseBR"

; Valida $CNPJ com o proprio deploy-focodesk.ps1 (-ValidateOnly). Resultado em $0 (0 = valido).
; O CNPJ vai por variavel de ambiente: nada digitado pelo usuario chega a linha de comando.
Function RunValidate
  ; entrada: $CNPJ ; saida: $0 = codigo de saida do PowerShell
  System::Call 'kernel32::SetEnvironmentVariable(t "FOCODESK_CNPJ", t "$CNPJ")'
  ${If} ${RunningX64}
    StrCpy $1 "$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
  ${Else}
    StrCpy $1 "$SYSDIR\WindowsPowerShell\v1.0\powershell.exe"
  ${EndIf}
  nsExec::ExecToStack '"$1" -NoProfile -ExecutionPolicy Bypass -File "$PLUGINSDIR\deploy.ps1" -ValidateOnly'
  Pop $0
  Pop $2
FunctionEnd

Function CnpjFromFileName
  ; FocoDesk-Setup-<14 caracteres>.exe -> pega os 14 ultimos antes da extensao
  System::Call 'kernel32::GetModuleFileName(p 0, t .r1, i ${NSIS_MAX_STRLEN})'
  ${GetFileName} $1 $2
  StrLen $3 $2
  IntOp $3 $3 - 4
  ${If} $3 > 14
    StrCpy $2 $2 $3
    StrCpy $CNPJ $2 14 -14
  ${EndIf}
FunctionEnd

Function .onInit
  InitPluginsDir
  File "/oname=$PLUGINSDIR\deploy.ps1" "${DIST_DIR}\deploy-focodesk.ps1"

  ${GetParameters} $R0
  ClearErrors
  ${GetOptions} $R0 "/CNPJ=" $CNPJ
  ${If} ${Errors}
    StrCpy $CNPJ ""
  ${EndIf}
  ${If} $CNPJ == ""
    Call CnpjFromFileName
  ${EndIf}

  ${If} $CNPJ != ""
    Call RunValidate
    ${If} $0 != 0
      StrCpy $CNPJ ""      ; invalido: cai para a pergunta (modo normal) ou erro (silencioso)
    ${EndIf}
  ${EndIf}

  ${If} $CNPJ == ""
  ${AndIf} ${Silent}
    SetErrorLevel 3
    Abort
  ${EndIf}
FunctionEnd

Function CnpjPageCreate
  ${If} $CNPJ != ""
    Abort                  ; ja temos um CNPJ valido: nao mostra a pagina
  ${EndIf}
  !insertmacro MUI_HEADER_TEXT "FocoDesk - Acesso remoto" "Informe o CNPJ do cliente"
  nsDialogs::Create 1018
  Pop $Dlg
  ${NSD_CreateLabel} 0 0 100% 24u "Digite o CNPJ da empresa onde este computador esta instalado (com ou sem pontuacao). Ele liga esta maquina ao cadastro do cliente."
  Pop $0
  ${NSD_CreateText} 0 34u 60% 12u ""
  Pop $CnpjEdit
  SendMessage $CnpjEdit ${EM_SETLIMITTEXT} 18 0
  ${NSD_CreateLabel} 0 52u 100% 12u "Exemplo: 11.222.333/0001-81"
  Pop $0
  nsDialogs::Show
FunctionEnd

Function CnpjPageLeave
  ${NSD_GetText} $CnpjEdit $CNPJ
  Call RunValidate
  ${If} $0 != 0
    StrCpy $CNPJ ""
    MessageBox MB_ICONEXCLAMATION|MB_OK "CNPJ invalido. Confira os numeros e tente de novo."
    Abort                  ; permanece na pagina
  ${EndIf}
FunctionEnd

Section "Instalar"
  SetOutPath "$INSTDIR"
  File /r "${DIST_DIR}\*.*"

  ; CNPJ e token por variavel de ambiente (nao ficam na linha de comando)
  System::Call 'kernel32::SetEnvironmentVariable(t "FOCODESK_CNPJ", t "$CNPJ")'
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
