# Publicação do repositório e submissão ERC

Verificado em **02/10/2026** contra o [repositório oficial ERCs](https://github.com/ethereum/ERCs), seu [template](https://github.com/ethereum/ERCs/blob/master/erc-template.md), [configuração editorial](https://github.com/ethereum/ERCs/blob/master/config/eipw.toml) e [EIP-1](https://eips.ethereum.org/EIPS/eip-1). O commit consultado está em `upstream.lock.json`.

## Dois repositórios, duas funções

O repositório **structured-fund-cashflows** contém especificação, implementação, testes, discussão preparada e evidências. O **fork de ethereum/ERCs** contém o PR editorial da proposta. O primeiro pode ser apresentado na discussão pública; o segundo é necessário para um PR com histórico compatível com o upstream. Criar nosso repositório não registra automaticamente um ERC.

O upstream usa **`ERCS/erc-*.md`**, e não `EIPS/eip-*.md`. Seu template ainda contém uma referência textual antiga a `eip-draft_*`; a árvore e o linter atuais usam `erc-*`. Confirmar eventual ajuste solicitado pelos editores. O texto usa links relativos `./eip-N.md` porque o site e o CI oficial normalizam o corpus combinado de EIPs/ERCs. A cópia legível deste repositório resolve esses links para URLs canônicas.

## 1. Publicar o repositório independente

Crie no GitHub um repositório vazio chamado `structured-fund-cashflows`, sem README/licença iniciais. Na pasta local deste projeto, use a URL mostrada pelo GitHub como `origin`, por exemplo, se ele for criado na conta confirmada do autor:

```sh
git remote add origin git@github.com:Afonsodalvi/structured-fund-cashflows.git
git push -u origin main
```

O endereço acima é o destino sugerido para criação; este pacote não afirma que ele já existe. A configuração do CI acompanha o repositório. Quem clonar deve usar `--recurse-submodules` ou executar `git submodule update --init --recursive`.

## 2. Discutir a ideia publicamente

Revise e publique o [texto preparado](MAGICIANS_POST.md) em Ethereum Magicians. Acrescente o link real do repositório após sua publicação. Buscar feedback de implementadores de vaults, administradores de fundos e mantenedores de padrões relacionados é parte do trabalho de padronização.

O autor precisa especialmente defender por que principal remanescente e obrigações financiadas merecem uma interface comum, reconhecer fundos de distribuição e dividendos como trabalho anterior, e discutir as fronteiras de multi-asset, external shares e alocação por data-base. A discussão ainda não foi publicada por este pacote.

## 3. Gerar o arquivo para o fork oficial

Depois de existir a URL real do tópico:

```sh
python3 scripts/check_candidate.py --discussion "$DISCUSSION_URL" --export /tmp/sfc-erc-submission
```

Defina `DISCUSSION_URL` com a URL canônica do tópico real. O exportador rejeita ausência de URL, formatos incorretos e destinos existentes. Ele valida o formato, não a identidade dos participantes nem consenso. O resultado contém somente `ERCS/erc-draft_structured_fund_cashflows.md`.

Faça um fork de `ethereum/ERCs` na sua conta, clone esse fork e crie uma branch. Copie o arquivo exportado para `ERCS/`. Abra um PR contra `ethereum/ERCs:master`, usando [o corpo preparado](ERC_PR_BODY.md). Não envie o código inteiro de referência, relatórios ou dados de produto para o PR editorial.

A proposta possui interface e vetores essenciais no próprio texto. A seção de referência descreve as decisões sem um link externo proibido. Se os editores solicitarem assets, coloque somente os artefatos relevantes no diretório que eles indicarem, com links e licenças revisados.

## 4. Numeração e validação editorial

Não escolha um número. Ajuste `eip`, nome `erc-N.md`, data e referências conforme a atribuição/instrução editorial. As duas informações externas ainda pendentes são o número atribuído e a URL pública de discussão.

O checker local executa **eipw 0.11.0 com a configuração real e imutável do upstream**. Na versão sem número, quatro verificações de metadados estão explicitamente dispensadas: número, nome de arquivo correspondente e duas validações da URL. As demais regras de conteúdo são executadas. `coverage/editorial.json` identifica as exceções e não apresenta o resultado como CI oficial. Após atribuição editorial, o PR oficial deverá passar sem essas dispensas.

Admissão como Draft é o começo da revisão formal. O avanço para Review, Last Call e Final depende do processo e da estabilidade técnica; não é garantido por testes, cobertura ou marca. O README oficial também distingue working papers externos de propostas já publicadas.

## Situação desta entrega

| Item | Situação |
| --- | --- |
| Repositório local independente | Preparado |
| Especificação e autoria | Preparadas |
| Comparação, revisão e evidências | Incluídas |
| Publicação no GitHub do autor | A executar pelo autor |
| Discussão em Ethereum Magicians | A criar |
| PR e CI no ethereum/ERCs | A executar após preparação pública |
| Número e aceitação editorial | Pendentes |
| Auditoria independente | Não realizada |
