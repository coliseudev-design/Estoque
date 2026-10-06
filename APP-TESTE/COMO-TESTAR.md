# Coliseu Estoque — App Android (teste)

`ColiseuEstoque-1.1.0.apk` — instale no celular ou coletor Android (Android 7+).
Telas do teste feito no emulador estão em [`telas/`](telas/).

> O APK está assinado com chave de **teste** (debug). Para publicar na Play Store ou
> distribuir em produção, gere uma chave própria (`android/app/build.gradle.kts`).

---

## Como o app conversa com o sistema

```
 PAINEL WEB (supervisor)            API DO ESTOQUE (servidor)                 APP ANDROID
 ─────────────────────────          ─────────────────────────                 ───────────
 Cadastros → Aparelhos
 → "Conectar aparelho"   ──POST /v1/devices/pairing──►  cria código XXXX-XXXX
                                                       (vale 10 min, 1 vez)
 mostra QR Code:
 COLISEU-ESTOQUE|<endereço>|<código>  · · · câmera · · ·  ►  1. "Ler QR do painel"
                                                                (ou digita endereço + código)
                                    ◄──POST /v1/auth/pair { código, modelo }──
                                    gera credencial do aparelho
                                    (id + segredo; só o hash fica no banco) ──►  guarda no aparelho

                                    ◄──POST /v1/auth/app-login──────────────  2. operador: usuário + PIN
                                       X-Device-Key + usuário + PIN
                                    token da sessão (12 h) ─────────────────►

                                    ◄──GET  /v1/documents?flow=entrada|saida   3. fila Entradas / Saídas
                                    ◄──GET  /v1/documents/lookup?code=…         bipa DANFE / pedido
                                    ◄──POST /v1/documents/:id/claim             abre (reserva) o documento
                                    ◄──POST /v1/documents/:id/scans             cada bipagem (fila offline)
                                    ◄──POST /v1/documents/:id/finalize          4. finaliza → OK / recontar /
                                                                                   supervisor
 tela atualiza sozinha  ◄──tempo real (SSE)── document.updated
 Aparelhos → "Desvincular" ──POST /v1/devices/:id/revoke──►  app perde o acesso em até 30 s
```

- O app **nunca recebe a quantidade esperada** (conferência cega). Quem compara é o servidor.
- Toda bipagem vai primeiro para o banco do celular e depois para a API: sem internet
  o operador continua a conferência que já tinha aberto; nada se perde, nada duplica.
- A chave de ativação do painel de licenças (Coliseu.Identity) continua funcionando
  ("Tenho uma chave de ativação…" na primeira tela) para quem já usa esse caminho.

---

## Passo a passo do teste

**1. API publicada com as atualizações.** O servidor precisa estar com esta versão
(migrations `003_entradas.sql` e `004_aparelhos.sql` rodam sozinhas no start).

**2. Cadastre o operador.** Painel → Cadastros → Usuários → Novo usuário → perfil
*Operador* com **PIN** (4 a 8 dígitos).

**3. Gere o QR.** Painel → Cadastros → **Aparelhos** → **Conectar aparelho**.
Confira o *Endereço da API que o celular vai usar*:
- servidor publicado: o próprio domínio do painel (`https://…`) — já vem preenchido;
- teste na rede local: `http://IP-DO-COMPUTADOR:3100` (o painel avisa se estiver `localhost`,
  que não funciona no celular). Celular e computador na mesma rede Wi-Fi.

**4. Instale e conecte.** Copie o APK para o celular (WhatsApp, cabo, Drive), toque
para instalar (permita "instalar apps desconhecidos"). Abra → **Ler QR do painel**.
O painel mostra "Aparelho conectado!" sozinho.

**5. Entre e confira.** Usuário + PIN → escolha **Entradas** ou **Saídas** →
toque no documento (ou bipe o DANFE / nº do pedido) → bipe os itens → **Finalizar**.

| Situação | O que acontece |
|---|---|
| Contou certo | "Nota recebida" / "Separação concluída" |
| Faltou ou sobrou | Pede recontagem só dos produtos divergentes |
| Divergiu de novo | Vai para o supervisor aprovar no painel |
| Sem internet | Continua bipando; envia quando a conexão voltar |
| Aparelho desvinculado | App pede para parear de novo |

**Coletor Zebra/Honeywell:** configure o leitor para "teclado" com **Enter** no final
(Zebra DataWedge: *Keystroke output* + *Send ENTER*; Honeywell: *Suffix = Enter*).
O gatilho funciona direto na fila e na conferência — sem tocar na tela.

---

## O que foi testado (emulador Android, API local)

- Pareamento por endereço + código, teste de conexão, login do operador com PIN.
- Fila separada Entradas / Saídas com contadores e críticas (SLA, faturado antes de conferir).
- Entrada: conferência da NF importada pelo XML, recontagem, "Nota recebida".
- Saída: lista de separação, 6 + 2 bipagens pelo "coletor", "Separação concluída".
- Código de pareamento usado duas vezes → recusado; aparelho desvinculado → sessão cortada.
- QR gerado no painel decodificado = `COLISEU-ESTOQUE|<endereço>|<código>`.
