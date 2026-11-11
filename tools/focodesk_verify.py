#!/usr/bin/env python3
"""
FocoDesk - verificacao pre-build (teste rapido, roda em segundos no CI).

Confere que o codigo-fonte ainda casa com o que os passos "FocoDesk" do
.github/workflows/flutter-build.yml vao procurar (embed do servidor/chave e a
marca). Se qualquer ancora sumiu ou duplicou -- tipico depois de um `git merge`
de uma versao nova do RustDesk -- este teste falha em segundos, em vez de o
build de ~1h falhar la na frente (ou, pior, gerar um binario sem a marca).

Mantenha as ancoras abaixo em sincronia com os passos FocoDesk do workflow.
Uso:
    python3 tools/focodesk_verify.py
Sai com codigo 0 se tudo certo, 1 se algo divergiu.
"""
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
errors = []


def must_exist(rel):
    p = ROOT / rel
    if not p.exists():
        errors.append(f"[arquivo ausente] {rel}")
        return None
    return p


def count_substr(rel, needle, expected=1):
    p = must_exist(rel)
    if p is None:
        return
    s = p.read_text(encoding="utf-8")
    n = s.count(needle)
    if n != expected:
        errors.append(f"[ancora x{n}, esperado x{expected}] {rel}: {needle!r}")


def count_regex(rel, pattern, expected=1, flags=0):
    p = must_exist(rel)
    if p is None:
        return
    s = p.read_text(encoding="utf-8")
    n = len(re.findall(pattern, s, flags))
    if n != expected:
        errors.append(f"[regex x{n}, esperado x{expected}] {rel}: /{pattern}/")


def count_bytes_regex(rel, pattern, expected=1):
    p = must_exist(rel)
    if p is None:
        return
    b = p.read_bytes()
    n = len(re.findall(pattern, b))
    if n != expected:
        errors.append(f"[regex-bytes x{n}, esperado x{expected}] {rel}: {pattern!r}")


# --- 1) Embed do servidor + chave (passo "embutir servidor e chave") ---
count_regex("libs/hbb_common/src/config.rs",
            r'pub const RENDEZVOUS_SERVERS: &\[&str\] = &\[[^\]]*\];')
count_regex("libs/hbb_common/src/config.rs",
            r'pub const RS_PUB_KEY: &str = "[^"]*";')

# --- 2) Nome do app (janela, bandeja, servico, pastas) ---
count_substr("libs/hbb_common/src/config.rs",
             'pub static ref APP_NAME: RwLock<String> = RwLock::new("RustDesk".to_owned());')

# --- 3) Bloqueio do auto-update do RustDesk oficial ---
count_substr("src/updater.rs",
             "    if !(manually || config::Config::get_bool_option(keys::OPTION_ALLOW_AUTO_UPDATE)) {")
count_substr("src/common.rs",
             "pub fn check_software_update() {\n    if is_custom_client() {")

# --- 4) Identidade do .exe (Runner.rc, 64-bit) ---
for key in (b"CompanyName", b"FileDescription", b"ProductName", b"LegalCopyright"):
    count_bytes_regex("flutter/windows/runner/Runner.rc",
                      rb'VALUE "' + key + rb'", "[^"]*"')

# --- 5) Metadados do exe 32-bit (Sciter) via Cargo.toml ---
count_substr("Cargo.toml", "[package.metadata.winres]\n")
count_regex("Cargo.toml", r'LegalCopyright = "[^"]*"')
count_substr("Cargo.toml", 'ProductName = "RustDesk"')
count_substr("Cargo.toml", 'FileDescription = "RustDesk Remote Desktop"')

# --- 6) Rodape de atribuicao (AGPL) ---
count_substr("src/lang/pt_BR.rs", '("powered_by_me", "Desenvolvido por RustDesk"),')
count_substr("src/lang/en.rs", '("powered_by_me", "Powered by RustDesk"),')

# --- 7) Assets de marca presentes no repo ---
for asset in ("branding/icon.ico", "branding/icon.png", "branding/tray-icon.ico"):
    must_exist(asset)

if errors:
    print("FocoDesk verify: FALHOU\n")
    for e in errors:
        print("  -", e)
    print("\nAlguma ancora do workflow nao casa mais com o codigo.")
    print("Provavel causa: merge de uma versao nova do RustDesk moveu/alterou a linha.")
    print("Ajuste o passo FocoDesk em .github/workflows/flutter-build.yml e este script juntos.")
    sys.exit(1)

print("FocoDesk verify: OK - todas as ancoras de embed e marca batem com o codigo.")
sys.exit(0)
