# Conformidade e fronteiras entre padrões

As referências oficiais são [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626), [ERC-7540](https://eips.ethereum.org/EIPS/eip-7540), [ERC-7575](https://eips.ethereum.org/EIPS/eip-7575), [Draft ERC-7887](https://eips.ethereum.org/EIPS/eip-7887) e [ERC-3643](https://eips.ethereum.org/EIPS/eip-3643). Revisão em 02/10/2026. Esta matriz é uma avaliação interna sustentada por testes, não certificação externa de conformidade.

| Requisito | Implementação | Evidência |
| --- | --- | --- |
| ERC-20 e metadata de shares | O próprio vault é o ERC-20; 18 casas; nome/símbolo configuráveis | Metadata e transferências |
| Asset único ERC-4626 | Asset imutável com 0–18 casas | Decimals 0/6/18 e rejeição de 19 |
| `totalAssets` como patrimônio gerido | managedCash + creditNAV; reservas fora do patrimônio disponível | NAV, deploy/repay, invariantes |
| `convertTo*` independentes de caller e arredondando para baixo | Implementação OpenZeppelin com termos virtuais | Fuzz e modelos descritos |
| `previewDeposit` e `previewMint` sem limites comerciais | Herança ERC-4626; floor/ceil respectivos | Mint exato e previews |
| `deposit` assets exatos e `mint` shares exatas | Transferência exata; mint não passa por token intermediário | Mint um wei com seis casas |
| Max views sem saldo/allowance de payer | Cap e supply, pausa e elegibilidade de receiver | Cap, full impairment, policy failure |
| Fluxo de saída assíncrono ERC-7540 | Request → fulfillment → claim ERC-4626 | Ciclos completos e parciais |
| `previewRedeem/Withdraw` sempre revertendo | Overrides incondicionais | Zero e chamadas usuais |
| `requestRedeem` retira cotas do owner | Custódia explícita no vault | Supply/escrow invariant |
| Queima até o claim | Queima já no fulfillment | Aposentadoria integral e perda total |
| Operador **ou** allowance no request | Alternativas de autorização; operador não gasta allowance | Testes de finita, infinita, operador |
| Overloads `deposit/mint` com controller | Entrada síncrona financiada pelo controller, ou por operador autorizado com allowance de asset do controller | Eventos, mint exato e autorização |
| Pending/claimable views em shares | Consultas por id zero e controller | Agregação e caller independente |
| Claims `redeem/withdraw` por controller | Assinaturas ERC-4626 com semântica ERC-7540, sem id no claim | Claims parciais e autorização |
| Limites de claim refletem claimable | `maxRedeem` shares, `maxWithdraw` assets | Estados/pausa/freeze |
| ERC-165 operadores/asynchronous redeem | `0xe3bc4e65` e `0x620ee8e4` | Teste de interface |
| ERC-7575 vault e share | Próprio vault; `share()`, `vault(asset)`; IDs `0x2f0a18c5` e `0xf815c03d` | Interface, lookup e orçamento ERC-165 |
| ERC-7887 cancelamento sem push | Estados e claim separados; bloqueio enquanto cancelamento pending | Cancelamentos e invariantes |
| ERC-7887 interface de cancelamento | `0xe76cffc7`; asset deposit continua síncrono | Teste de interface |
| Nova interface de cashflows | Consultas/claim/eventos; ERC-165 calculado da interface Solidity | Eventos e estado financeiro |

Esta instância implementa somente resgate assíncrono; deposit/mint permanecem síncronos, incluindo os overloads de três argumentos com controller previstos pelo ERC-7540. Nesses overloads, o controller financia a entrada e aparece como sender do evento Deposit; operador aprovado pode executar, mas o allowance de asset do controller para o vault continua necessário. Não anuncia a interface de depósito assíncrono `0xce3bbe50`, não oferece requestDeposit e não deve ser integrada como vault completamente assíncrono.

O Draft ERC-7887 ainda pode mudar. O texto consultado tem inconsistências editoriais: uma passagem de claim de cancelamento menciona assets enquanto seu fluxo de resgate devolve shares, e o nome do evento no parágrafo difere da tabela. A referência usa shares e o evento `CancelRedeemClaim` da tabela, com identificação por controlador e assinatura verificada. Isso deve ser conferido novamente antes de publicar alegação de aderência ao Draft.

## Relação com ERC-3643

`StructuredFundEligibility` faz allowlist/freeze; o vault verifica a política nas movimentações relevantes. Não implementa identity registry/storage, ONCHAINID, claim topics, trusted issuers, modular compliance, recovery, forced transfer, partial freeze ou batches da suíte ERC-3643. Não anuncia uma interface fictícia de ERC-3643.

`IStructuredFundEligibility` é a fronteira de integração. Uma política futura pode consultar `isVerified` de um Identity Registry ERC-3643, mas isso sozinho não cobre regras de montante, número de holders, lockup ou residência específicas da transferência. Para suportar essas regras, deve-se evoluir a fronteira para validar `(from, to, amount)` e notificar as mudanças ao módulo de compliance, preservando os fluxos especiais de escrow e queima. Essa implementação exigirá nova revisão e novos testes.

## Conformidade econômica e implementação alternativa

Compatibilidade de ABI não torna verdadeiras as avaliações ou os pagamentos. O vault contabiliza cashflows explicitamente atestados; não prova a alocação por série/classe de uma carteira compartilhada. Essa alocação é um contrato entre o motor de carteira do produto e cada instância.

O ERC proposto exige semântica interoperável de principal/cashflow; não exige a factory, a política de referência, nomes Structured Fund Cashflows, AccessControl, o asset cap escolhido, a tesouraria imutável ou estes algoritmos de crédito. Outras implementações podem mudar essas decisões mantendo as obrigações normativas.

## Perfil e limites adicionais

A proposta exige ERC-4626 e ERC-165 e define composição condicional com ERC-7540; o `requires` inclui 7540 por suas regras de ciclo de vida. A referência implementa somente depósitos síncronos. A regra normativa para principal em depósitos assíncronos exige crédito apenas quando o claim entrega shares, mas esse fluxo não é implementado nem anunciado aqui.

A descoberta ERC-7575 desta instância não comprova suporte a share externo ou entradas em várias moedas. O perfil SFC atual mantém o próprio vault como share e um único asset. ERC-7943 é trabalho complementar; suas funções de transferência forçada, congelamento parcial e permissões contextuais não estão implementadas pela referência.

## Toolchain update — 2026-10-03

The reference now targets Osaka with Solidity 0.8.37 and OpenZeppelin 5.7.0. Vault/factory reentrancy guards use transient storage. See [TOOLCHAIN](TOOLCHAIN.md) for network compatibility, the final-release versus audited-channel distinction, storage/CREATE2 changes and expanded validation. The six-method SFC interface identifier is unchanged.
