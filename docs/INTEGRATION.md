# API e integração

## Instanciação

`StructuredFundFactory.createVault` recebe fundo, série, classe, asset, política, administrador, tesouraria, destinatário tributário, cap e metadados ERC-20. O evento `VaultCreated` e `vaultForScope` estabelecem a associação. O criador precisa de `CREATOR_ROLE`; a factory não recebe automaticamente papéis no vault.

Antes de oferecer uma instância a um investidor, verificar endereço da factory, chainId, scopeId, asset/decimals, cap, política, tesouraria, taxReceiver, administrador e papéis operacionais. Nome e símbolo devem refletir o asset, por exemplo `Structured Fund Cashflows USDC Senior / sfcUSDC-S`; metadados não provam identidade do fundo.

## Entrada e cotas

| Método | Uso |
| --- | --- |
| `asset`, `share`, `decimals` | Asset nativo, token de cotas próprio e 18 casas |
| `totalAssets` | NAV de caixa gerido e crédito; exclui reservas e doações |
| `convertToShares`, `convertToAssets` | Conversões ideais arredondadas para baixo |
| `previewDeposit`, `previewMint` | Previsão sem os limites comerciais; mint usa arredondamento para cima |
| `maxDeposit`, `maxMint` | Limites conservadores por cap, supply, pausa e elegibilidade do receiver |
| `deposit(assets, receiver)` | Entrada exata de assets; payer e receiver precisam ser elegíveis |
| `mint(shares, receiver)` | Quantidade exata de shares; payer aprova os assets arredondados |
| `deposit(assets, receiver, controller)`, `mint(shares, receiver, controller)` | Overloads ERC-7540 de entrada síncrona; controller financia e autoriza caller/operator |
| `depositWithMinShares` | Extensão com mínimo de shares e rollback integral se não atingido |
| `transfer`, `transferFrom` | Movimento de shares e principal livre, com compliance |

Max views não consultam o saldo nem allowance do payer. A aprovação do token e a elegibilidade do payer devem ser verificadas pelo integrador. Falha no serviço externo de elegibilidade resulta em zero nos limites e rejeição das mutações.

```solidity
IERC20(vault.asset()).approve(address(vault), assets);
uint256 shares = vault.depositWithMinShares(assets, receiver, minShares);
```

Um NAV administrativo pode mudar entre a cotação e a execução. Use limite de slippage em deposit e um router com limite máximo de assets em mint; o ERC-4626 básico não tem esse parâmetro.

## Saída e autorização

```solidity
uint256 requestId = vault.requestRedeem(shares, controller, owner); // sempre zero
uint256 waiting = vault.pendingRedeemRequest(requestId, controller); // shares
uint256 ready = vault.claimableRedeemRequest(requestId, controller); // shares
uint256 assetsReady = vault.maxWithdraw(controller);                // asset native
// Após fulfillment pelo settler:
uint256 assets = vault.redeem(ready, receiver, controller);
```

`isOperator(controller, operator)` e `setOperator(operator, approved)` controlam claims e requests. Na solicitação de resgate, allowance do **owner** também autoriza terceiros. No claim, allowance não substitui a autorização do **controller**. O controlador autoriza o operador a escolher um receiver elegível; o produto deve explicar esse poder ao obter a aprovação.

O operador também pode executar os overloads síncronos de deposit/mint, usando assets do controller previamente aprovados ao vault e atribuindo as cotas a um receiver elegível. Essa capacidade deve estar explícita na tela de concessão de operador; revogar a aprovação do asset impede esse financiamento adicional.

`withdraw(assets, receiver, controller)` é claim de assets exatos, com consumo de shares claimable arredondado para cima. Para extinguir todos os direitos, inclusive zero assets por perda, usar `redeem(maxRedeem(controller), receiver, controller)`.

As duas funções `previewRedeem` e `previewWithdraw` revertem para qualquer entrada, inclusive zero. Não interprete o revert como falha do vault; é a semântica assíncrona.

## Cancelamento

`cancelRedeemRequest(0, controller)` solicita cancelamento. Consultar `pendingCancelRedeemRequest` e `claimableCancelRedeemRequest`. Após `fulfillCancel` pelo settler, `claimCancelRedeemRequest(0, receiver, controller)` devolve todas as cotas de cancelamento claimable e seu principal. O terceiro argumento identifica o controlador, independentemente do nome `owner` encontrado no ABI textual do Draft atual.

## Pagamentos e reconciliação

`cashflow(id)` retorna `beneficiary`, `principal`, `grossYield`, `withheld`, `periodStart`, `periodEnd`, `evidenceHash`, `claimed`. Um id inexistente retorna uma struct zero. Seu líquido é `principal + grossYield - withheld`. `claimCashflow(id, receiver)` devolve exatamente esse líquido e marca o direito como consumido.

IDs são únicos no contrato, incluindo registros já consumidos. O domínio externo correto é `(chainId, vaultAddress, scopeId, cashflowId)`. O evidence hash deve comprometer o arquivo canônico ou o pacote de evidências que a governança realmente consegue disponibilizar. Guardar somente o hash sem preservar sua origem dificulta auditoria.

O método de mutação da referência é `recordCashflow(id, payment, navRelease)`. O settler precisa informar quanto de principal e rendimento já estava no NAV: `payment.principal <= navRelease <= payment.principal + payment.grossYield`, limitado ao NAV de crédito. Registrar rendimento já reconhecido com baixa apenas de principal superestima o patrimônio restante; consultar ARCHITECTURE para os três casos de reconhecimento. Essa obrigação faz parte da reconciliação operacional.

Indexar os eventos `Deposit`, `Transfer`, `RedeemRequest`, `RedeemFulfilled`, `Withdraw`, `CancelRedeemRequest`, `CancelFulfilled`, `CancelRedeemClaim`, `PrincipalMoved`, `PrincipalRetired`, `CashflowRecorded`, `CashflowNAVReleased` e `CashflowClaimed`. Eventos auxiliares informam alocação de crédito, recebimento de caixa e atualização de NAV.

`principalOf` mede principal livre; `lockedPrincipalOf` mede principal pending ou de cancelamento daquele controlador. Não somar claimableRedemption shares ao supply: elas já foram queimadas no fulfillment. O principal aposentado em resgate e o principal pago em amortização são grandezas diferentes.

## Administração

| Papel | Poder |
| --- | --- |
| `DEFAULT_ADMIN_ROLE` | Concede/revoga papéis; transfere administração com delay e aceitação |
| `VALUER_ROLE` | Declara NAV de crédito, sujeito a nonce/cap/evidência |
| `TREASURY_ROLE` | Aloca caixa gerido para a tesouraria imutável |
| `SETTLER_ROLE` | Cumpre resgates/cancelamentos, recebe repayments e registra cashflows financiados |
| `PAUSER_ROLE` | Pausa/despausa entradas, transferências, liquidação de resgates e novas alocações |
| Política: `COMPLIANCE_ROLE` | Altera allowlist e congelamento |

Claims de cashflow, cancelamentos e repayments continuam disponíveis durante pausa. A pausa bloqueia redeem/withdraw; despausar exige intervenção do pauser. Transferência do administrador padrão não revoga automaticamente os outros papéis que o administrador antigo possuía: o runbook deve revogá-los explicitamente.

O código não oferece deploy automático com chaves, scripts de transmissão, upgrade, sweep de asset ou ponte. Uma implantação de produção exige revisão dos endereços e assinatura da governança fora desta referência.

## Descoberta e lotes

`vault(asset)` devolve esta instância para seu asset e zero para outro endereço. `supportsInterface(0xf815c03d)` identifica o lado share de ERC-7575, além do identificador de vault já anunciado. Isso não transforma a instância em multi-asset.

`recordCashflowBatch(ids, payments, navReleases)` registra entre 1 e 64 obrigações na mesma transação. Arrays precisam ter comprimentos iguais; qualquer registro inválido ou falta de funding reverte o lote inteiro, inclusive retenções já transferidas durante sua execução. Use para beneficiários de uma distribuição conjunta dentro desse limite. O settler continua responsável pela completude da lista e pela justiça da alocação. Uma distribuição maior exige projeto adicional de snapshot/epoch; dividi-la em chamadas comuns pode expor preços intermediários.

## Toolchain update — 2026-10-03

The reference now targets Osaka with Solidity 0.8.37 and OpenZeppelin 5.7.0. Vault/factory reentrancy guards use transient storage. See [TOOLCHAIN](TOOLCHAIN.md) for network compatibility, the final-release versus audited-channel distinction, storage/CREATE2 changes and expanded validation. The six-method SFC interface identifier is unchanged.
