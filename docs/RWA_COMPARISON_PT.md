# Structured Fund Cashflows: comparação de padrões RWA e revisão crítica

**Data da revisão: 02/10/2026. Autor da proposta: Afonso Dalvi (@Afonsodalvi).**

A conclusão técnica é que SFC tem uma hipótese de padronização defensável: tornar interoperável a conciliação entre principal remanescente, patrimônio gerido e obrigações de pagamento financiadas. Essa hipótese precisa ser validada por integradores e pela comunidade. Não se sustenta afirmar que SFC inventa dividendos, classes, amortização, retenção ou resgate assíncrono.

## Método e força da evidência

A seleção considera padrões com uso documentado por implementadores de RWA, padrões próximos da proposta e antecedentes capazes de questionar sua originalidade. Ela não é um ranking quantitativo dos mais usados: TVL de um produto, quantidade de contratos e adoção de uma interface são métricas diferentes. Uma carteira que exibe ERC-20 não prova que o motor do emissor implementa ERC-4626, ERC-7540 ou ERC-3643.

O status formal foi conferido nos arquivos do repositório oficial `ethereum/ERCs`, no commit fixado em [upstream.lock.json](../upstream.lock.json). As evidências de produto vêm dos próprios projetos e não são tratadas como auditoria independente de sua operação. A ausência de uma regra em um ERC não significa que protocolos construídos sobre ele sejam incapazes de implementá-la.

## Onde esses padrões aparecem no mercado

| Implementador e fonte primária | O que a evidência permite afirmar | Limite da comparação |
| --- | --- | --- |
| [Centrifuge: visão do protocolo](https://docs.centrifuge.io/developer/protocol/overview/) | Documenta ERC-20, vaults ERC-4626/7540 e múltiplas entradas ERC-7575; também mantém sua própria contabilidade de carteira | Contabilidade não é uma novidade de SFC. A arquitetura multi-asset/external-share não é compatível automaticamente com o perfil inicial SFC |
| [Tokeny: soluções](https://docs.tokeny.com/docs/solutions-overview-1) e [suíte ERC-3643](https://docs.erc3643.org/erc-3643) | Implementação e ferramentas para tokens permissionados e sua identidade/compliance | Uma política booleana de elegibilidade não equivale à suíte completa |
| [Securitize: integração do Vault Registrar](https://labs.securitize.io/docs/integration-guide) | Documenta DS Tokens, registro de investidores e integração com contratos de vault | O material consultado é um sandbox; não comprova que cada produto da empresa use todo o mesmo conjunto de interfaces |
| [Ondo: relatório de auditoria publicado pelo projeto](https://docs.ondo.finance/pdf/Ondo-Cyfrin-Audit-April-2024.pdf) | Evidência histórica de OUSG/rOUSG como ERC-20 permissionados, com emissão/resgate geridos por contratos específicos | É um recorte de 2024, não um inventário completo dos deployments de 2026 |
| [Solv: referência ERC-3525](https://github.com/solv-finance/erc-3525) | Implementação de posições semi-fungíveis com identificação, slot e valor | A presença da referência não mede participação atual de mercado de cada produto Solv |

O [sandbox da Securitize](https://labs.securitize.io/docs/vault-registrar-sandbox/overview) também menciona uma interface de registrar como ERC-8245. Esse número não estava no corpus oficial fixado nesta revisão; por isso não recebe aqui um status formal de Draft ou Final. Registro de vaults e autorização de custódia são assuntos complementares, diferentes da conciliação de cashflows.

## Matriz técnica dos padrões

| Padrão / situação conferida | Função principal | Relação com SFC e limite relevante |
| --- | --- | --- |
| [ERC-20 — Final](https://eips.ethereum.org/EIPS/eip-20) | Saldos fungíveis, transferências e allowances | É a base das cotas. Uma transferência do asset não informa se houve principal, rendimento ou retenção |
| [ERC-4626 — Final](https://eips.ethereum.org/EIPS/eip-4626) | Interface de vault: assets, shares, conversão, entrada e saída | SFC acrescenta um ledger de principal e pagamentos individualizados. Não redefine o arredondamento nem permite ignorar a semântica de `totalAssets` |
| [ERC-7540 — Final](https://eips.ethereum.org/EIPS/eip-7540) | Pedidos assíncronos, controladores, operadores e claims | Resolve a espera entre solicitação e liquidação. SFC acompanha o principal desses estados; não reivindica a criação da fila |
| [ERC-7575 — Final](https://eips.ethereum.org/EIPS/eip-7575) | Share separado, descoberta e múltiplas entradas em assets | Referência SFC fornece descoberta para seu próprio share. Um share externo compartilhado precisa de contabilidade adicional de denominação e baixa |
| [ERC-7887 — Draft](https://eips.ethereum.org/EIPS/eip-7887) | Cancelamento de solicitações ERC-7540 | A referência preserva principal capturado e devolve shares por claim. A especificação 7887 ainda tem inconsistências editoriais de nomes/eventos documentadas em CONFORMANCE |
| [ERC-3643 — Final](https://eips.ethereum.org/EIPS/eip-3643) | Identidade, elegibilidade, controles de transferência e operações de agente | SFC não substitui essas funções. Transferência forçada/recovery de shares também precisa manter o ledger; não transfere automaticamente cashflows antigos |
| [ERC-7943 — Final](https://eips.ethereum.org/EIPS/eip-7943) | Interface comum de restrições, congelamento e enforcement de RWA | Complementar e mais estreito que uma suíte completa de identidade. SFC não anuncia essa interface sem implementá-la |
| [Família ERC-1400 — proposta histórica](https://github.com/SecurityTokenStandard/EIP-Spec) | Partições, documentos, emissão/resgate, restrições e controladores | Demonstra que classes e direitos diferenciados têm antecedentes. Os textos dos autores não são apresentados como ERCs Final publicados no corpus atual |
| [ERC-1404 — interface histórica](https://github.com/simple-restricted-token/ERC-1404) | Detecção e explicação de restrição de transferência | É observado, por exemplo, na [documentação de compliance da Centrifuge](https://docs.centrifuge.io/developer/protocol/features/token-compliance/). Não é um ledger de amortização |
| [ERC-3525 — Final](https://eips.ethereum.org/EIPS/eip-3525) | Posições semi-fungíveis por ID, slot e valor | Pode ser mais adequado para títulos/lotes com termos distintos. SFC escolhe cotas fungíveis por escopo, perdendo essa expressividade |
| [ERC-3475 — Final](https://eips.ethereum.org/EIPS/eip-3475) | Obrigações com classes, nonces, metadados e condições de resgate | É uma representação de obrigações diferente. Não precisa ser substituído para padronizar o pagamento de um vault |
| [ERC-7518 — Review](https://eips.ethereum.org/EIPS/eip-7518) | Partições ERC-1155, compliance dinâmico, locking, operações forçadas e payouts | Sobreposição maior que um simples token. Seu payout e controles não devem ser omitidos numa defesa de originalidade de SFC |
| [ERC-7776 — Review](https://eips.ethereum.org/EIPS/eip-7776) | Publicação de demonstrações financeiras e indicadores por período | Uma demonstração não constitui, por si, um direito individual financiado e consumível; SFC também não substitui demonstrações financeiras |
| [Dividend-paying / ERC-1726 — discussão histórica](https://github.com/Roger-Wu/erc1726-dividend-paying-token) | Dividendos e preservação de recebimentos acumulados | Antecedente direto de direitos que sobrevivem a transferências; não há justificativa para vender isso como mecanismo novo |
| [Funds Distribution Token / ERC-2222 — proposta histórica](https://github.com/atpar/funds-distribution-token/blob/master/EIP-DRAFT.md) | Claims sobre dividendos, pagamentos de empréstimos, receitas e taxas | Antecedente mais próximo. Já trata cashflows e mantém direitos anteriores. O argumento de SFC precisa estar na decomposição e conservação do principal/NAV/reservas |

Status formal, maturidade de uma implementação e uso comercial são eixos distintos. Um padrão Final pode ter pouca adoção num segmento; uma interface histórica pode ser usada sem nunca ter chegado a Final.

## O diferencial que é possível defender

A proposta reúne seis operações observáveis e suas regras econômicas: escopo, principal livre, principal bloqueado, principal total, registro de cashflow e claim. O valor está no contrato de integração: duas implementações diferentes devem atribuir o mesmo significado a esses campos e transições.

Uma posição com principal 100 e NAV 70 representa perda, não amortização de 30. Se ela for integralmente resgatada por 70, o ledger baixa os 100 associados à posição e registra a saída de 70. Se, em vez disso, houver uma amortização financiada de 20, o principal outstanding cai para 80 e surge uma obrigação de pagamento. Essas operações não podem aparecer como o mesmo movimento econômico.

A segunda distinção é entre valor gerido e valor já comprometido. Uma obrigação líquida registrada precisa estar financiada e separada de novos investimentos e resgates. Ela não pode continuar elevando o valor das cotas remanescentes. A terceira distinção é entre direito da cota e direito de pagamento já registrado: transferir a cota transfere seu principal restante, mas não reatribui silenciosamente um pagamento anterior.

Essas regras são implementáveis em protocolos existentes. A justificativa para um ERC depende de eliminar interpretações incompatíveis entre eles, e não de provar que nenhum concorrente consegue construir o mesmo recurso.

## Exemplos que revelam os problemas

### Pagamento líquido sem classificação

Com principal inicial de R$ 100 mil, uma amortização de R$ 20 mil, rendimento bruto de R$ 5 mil e retenção de R$ 1 mil produzem um claim de R$ 24 mil e principal restante de R$ 80 mil. O pagamento líquido sozinho não permite reconstruir esses componentes.

SFC expõe a decomposição e preserva o registro após o claim. A decisão sobre natureza tributária, alíquota ou documentação legal permanece fora do padrão; o campo `withheld` não calcula imposto.

### Rendimento contado duas vezes

Se os R$ 5 mil já estavam no NAV de R$ 105 mil, comprometer R$ 25 mil brutos na distribuição precisa deixar R$ 80 mil vinculados às cotas. Se apenas o principal de R$ 20 mil fosse baixado, o contrato manteria R$ 5 mil simultaneamente na cota e no pagamento.

A referência recebe `navRelease` para retirar também o rendimento reconhecido. O valor é limitado, mas sua exatidão depende do settler. Testes cobrem yield totalmente reconhecido, parcialmente reconhecido e não reconhecido anteriormente. A revisão tornou explícita essa regra no texto normativo.

### Transferência e principal residual

Alice possui 100 cotas e principal 100. Transferindo 40, passa a ter principal 60; Bruno recebe 40. Um recebimento já registrado para Alice continua com ela. Esse mecanismo é útil para evitar divergência entre token e posição, mas a preservação do recebimento anterior tem precedentes em dividendos/FDT.

O arredondamento proporcional para baixo conserva o total e carrega o resíduo na transferência integral. Ele não conserva uma identidade de lote: muitas transferências pequenas podem distribuir o resíduo de forma diferente de uma única transferência grande. Portanto esse principal não é preço pago no mercado secundário nem custo fiscal por lote.

### Distribuição parcial e preço intermediário

Se Alice e Bruno têm direitos sobre o mesmo NAV e o fundo registra apenas Alice numa primeira transação, o preço da cota pode refletir uma distribuição incompleta antes do registro de Bruno. Uma entrada ou resgate entre as duas transações pode transferir valor entre participantes.

A revisão acrescentou registro atômico de até 64 cashflows. Todos são contabilizados na mesma transação ou todos revertem. Isso resolve a atomicidade desse lote, mas não prova que o operador incluiu todos os titulares devidos. Distribuições maiores precisam de epoch/snapshot e bloqueio de operações sensíveis ao preço; esses mecanismos estão fora desta implementação de referência.

### Escrow não é estoque de cotas não emitidas

Um pedido de resgate move shares para custódia, mantendo a emissão até a baixa definitiva. O principal correspondente é capturado por controlador. Se houver cancelamento, restaura-se exatamente o que foi capturado; se houver resgate, o principal é aposentado independentemente da recuperação.

A política de rendimento enquanto o pedido aguarda não é universal. Pendências continuam afetando o supply até o fulfillment. A alocação de cupons e a mudança no NAV precisam respeitar os termos do produto; o núcleo não impõe uma waterfall que resolva todas as políticas de fundo.

## Vantagens e custos frente às alternativas

| Escolha SFC | Benefício | Custo ou limitação |
| --- | --- | --- |
| Uma classe/asset por escopo | Evita somar direitos e moedas incompatíveis | Mais instâncias; não resolve multi-asset nem FX |
| Principal explícito por titular/controlador | Facilita conciliação de transferências, amortização e resgate | Escritas adicionais; exige hooks em todos os caminhos que movem shares |
| Registro individual imutável | Componentes e beneficiário ficam verificáveis por id | Storage e operações crescem com registros; accumulators globais podem ser mais baratos para dividendos homogêneos |
| Reserva financiada antes do claim | Não usa o mesmo caixa em duas obrigações | Exige liquidez no momento do registro; não tokeniza uma promessa sem funding como se fosse claim liquidável |
| Direitos antigos fixados ao beneficiário | Elimina ambiguidade após transferência | Recovery de shares não recupera automaticamente cashflows de uma chave perdida |
| Retenção explícita | Expõe bruto/líquido de maneira uniforme | Não modela bases fiscais, lotes ou regras jurisdicionais |
| Valuation e entitlement externos | Mantém o ERC pequeno e adaptável | Operadores podem informar NAV ou alocação errados; hashes não provam fatos externos |
| Referência imutável | Elimina superfície de upgrade dessa instância | Parâmetro imutável errado ou evolução de requisitos pode exigir migração |
| Self-share ERC-4626 | Acoplamento inequívoco entre movimento de cotas e principal | Não é substituição direta de uma arquitetura com share externo, como entradas multi-asset |

Não foi demonstrada vantagem universal de gas, liquidez, compliance ou segurança frente aos projetos citados. Métricas de cobertura e análise estática avaliam esta referência sob suas hipóteses; não são comparação de qualidade com sistemas de terceiros.

## O que mudou nesta revisão

1. O texto passou a reconhecer explicitamente os antecedentes de dividendos e distribuição de fundos. Links quebrados para propostas históricas foram retirados do arquivo destinado ao corpus oficial.
2. A unidade, o asset e o endereço do domínio ficaram mais claros, inclusive para uma futura implementação em proxy.
3. O crédito de principal em depósito assíncrono foi definido no claim que entrega shares; pendências reembolsáveis não criam principal. A referência continua implementando somente entrada síncrona.
4. A regra de baixa de NAV cobre também rendimento já reconhecido. A imutabilidade do registro foi separada da transição `claimed`.
5. A descoberta ERC-7575 recebeu o identificador do share e lookup por asset, com teste dentro do orçamento de ERC-165.
6. A referência ganhou lote atômico limitado e testes de rollback, funding, callbacks e conservação.
7. O verificador compara toda a interface textual, incluindo struct, retorno e eventos, além de calcular o identificador.
8. A extração removeu dependência de diretórios e workflows do produto original. O novo pacote usa submódulos e ferramentas fixados, licenças claras e CI próprio.
9. O destino editorial, o texto CC0 e o linter passaram a corresponder ao upstream atual. Número e discussão continuam explicitamente pendentes.

## Avaliação de prontidão e decisão recomendada

O material está preparado para ser publicado como working paper acompanhado de uma referência verificável e para abrir discussão técnica. A defesa mais forte é um perfil pequeno, com conservação contábil demonstrável e hipóteses explícitas. A defesa mais fraca seria apresentá-lo como substituto universal dos padrões RWA ou como invenção de todo o ciclo financeiro.

Antes de buscar avanço editorial, precisamos de feedback de pelo menos implementadores e consumidores da interface sobre os campos que realmente usarão. Isso é uma recomendação prática de adoção, não uma regra inventada de quantidade mínima de apoiadores. Os pontos a discutir estão em [MAGICIANS_POST](MAGICIANS_POST.md): share externo, data-base, evidência obrigatória, intervalos de amortização e operadores.

O caminho de submissão está em [SUBMISSION](SUBMISSION.md); os achados e limites materiais estão em [REVIEW](REVIEW.md). Revisão comunitária e auditoria independente continuam sendo etapas diferentes, e nenhuma delas é substituída pelo fato de a referência passar nos testes.
