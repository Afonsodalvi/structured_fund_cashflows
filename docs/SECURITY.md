# Segurança: modelo de ameaças e revisão

## Propriedades protegidas

O modelo trata investidor, operador revogado, caller sem papel e callbacks do asset como potencialmente hostis. As propriedades verificadas são autorização dos direitos, conservação de supply/principal, financiamento das obrigações e isolamento das reservas. NAV e alocação de cashflows continuam sendo afirmações de administradores autorizados.

| Ameaça | Controle implementado | Evidência executável |
| --- | --- | --- |
| Reentrância ao receber ou enviar asset | Guards nas operações financeiras e nas transferências de cotas; efeitos antes de claims | Security: callbacks em deposit, redeem, cashflow e valuation |
| Claim repetido ou por terceiro | Direitos decrementados, booleano de consumo e autorização por controlador/operador | Security: double claim, revogação de operador, roubo de direito |
| Resgatar sem ter cotas ou sem allowance | Verificação de saldo; allowance ou operador sobre o owner | Unit/security: allowances finitas/infinitas e request sem autorização |
| Transferir cotas ignorando compliance | Verificação no ERC-20, inclusive via `transferFrom` | Security: receiver bloqueado, owner congelado, rollback de allowance |
| Usar reservas para novos créditos | `deployCredit` limitado a `managedCash` | Security: reserva de resgate não pode ser alocada |
| Token que entrega menos ou desconta taxa extra | Verificação dos deltas de remetente e destinatário; rollback integral | Security: fee-on-transfer em entrada e claim |
| Manipulação de preço por doação | NAV contabilizado separadamente do saldo do token | Unit: donation não altera shares da próxima entrada |
| Mistura de principal em escrow | Principal capturado por controlador; não agregado economicamente no ERC-20 da custódia | Unit/invariant: cancelamento restaura o principal capturado |
| Principal ou supply persistente após resgate | Queima/aposentadoria no fulfillment e reserva fora do NAV | Unit/invariant: conservação e aposentadoria |
| Repetição de cashflow/NAV | Id permanente e nonce sequencial de valuation | Security: replay, duplicidade, período sobreposto |
| Reclassificar principal como retenção | `withheld <= grossYield`; principal e rendimento explícitos | Unit/security: líquido e limites |
| Contar yield como NAV e como pagamento reservado | Baixa explícita de NAV entre principal e pagamento bruto | Unit: yield reconhecido, parcial e não reconhecido; ghost NAV invariant |
| Quantização USDC / cotas | Mint de shares exatas, ceil de assets, virtual shares | Unit/fuzz: mint de um wei e previews |
| Loop de investidores bloqueando operação | Operações individuais O(1); lote limitado a 64, sem enumeração global | Revisão de código; handlers com várias carteiras |
| Serviço de elegibilidade indisponível | Views retornam zero e mutações rejeitam | Security: política que reverte |

Não há `tx.origin`, delegatecall, proxy, DiamondCut, upgrade, arbitrária execução de calldata, chave embutida ou transferência ETH no núcleo. Isso reduz a superfície da referência; esses riscos continuam relevantes nos módulos atuais e em uma futura integração.

## Hipóteses de confiança

**Avaliador.** Pode declarar NAV de crédito incorreto dentro do cap, alterando a distribuição econômica entre entradas e saídas. Evidence hash e nonce tornam a ação identificável, mas não tornam verdadeira a avaliação. Recomenda-se separação de papéis, política de preço, revisão independente e controle operacional de entradas durante reavaliações.

**Settler.** Pode escolher o momento e a ordem dos fulfillments e a alocação de principal/rendimento/retencão aos beneficiários. Informa também a baixa `navRelease` correspondente ao valor já reconhecido: uma informação errada dentro dos limites pode superestimar ou subestimar o NAV. O contrato exige financiamento e respeita principal livre, NAV de crédito e períodos, mas não comprova entitlement por snapshot, waterfall ou cálculo externo. Também pode reter fulfillment de cancelamentos. Estes poderes precisam de termos claros, controle de acesso e responsabilização institucional.

**Tesouraria.** Recebe o caixa alocado. O contrato não comprova que dinheiro enviado se converteu num recebível real ou que o credor terá recuperação. O endereço é imutável; essa propriedade evita redirecionamento, mas torna erro de configuração irrecuperável sem migração.

**Administrador.** Concede/revoga papéis e pode reconstituir os poderes acima. O delay de dois dias protege a transferência do administrador padrão; ele não cria timelock para cada concessão de papel. O administrador antigo conserva papéis operacionais até revogação explícita.

**Compliance.** Pode impedir entradas, transferências e saídas de qualquer titular. A política do vault é imutável, mas o estado dessa política é controlado pelo responsável de compliance. Uma política arbitrária ou incompatível pode ser lenta, reverter ou aprovar todos. A referência não tem recovery ou forced transfer da suíte ERC-3643.

**Asset.** A implementação selecionada precisa oferecer transferência exata e saldos estáveis. Rebasing, taxas, token upgradeable comprometido, pausas e blacklist do próprio asset podem quebrar disponibilidade ou solvência. Checagem de deltas protege a transação, não o saldo entre transações. Os mocks cobrem falhas específicas, não todas as implementações ERC-20 possíveis.

## Invariantes de estado

A suíte percorre 20 tipos de ação: entrada, mint exato, transferência, request, fulfillment, claims por shares/assets, cancelamento e claim, deploy, repay, valuation, cashflow e claim, pausa, congelamento, batches, doações e transferências por allowance. Há três investidores e ghost counters independentes das variáveis de produção. `fail_on_revert = true` torna revert inesperado uma falha. O handler evita chamadas sabidamente inválidas; ataques e guardas rejeitados são cobertos separadamente na suíte security.

1. Supply = cotas livres + escrow; saldo do vault = requests pending + cancelamentos claimable.
2. Principal outstanding = principal livre + principal bloqueado. Principal captado = outstanding + amortizado + aposentado em resgate.
3. Saldo exato de asset = caixa gerido + reservas + doações rastreadas separadamente; NAV = caixa gerido + NAV de crédito e respeita o cap. Um ghost ledger independente reconcilia aportes, variações de valuation, baixas de cashflow e resgates.
4. Reservas de resgate = soma das obrigações por controlador; valor fulfilled = valor pago + reserva.
5. Reservas de cashflow = soma dos registros não consumidos; líquido registrado = líquido pago + reserva.

6. Campos de cada cashflow permanecem idênticos ao compromisso original; `claimed` acompanha o ghost ledger de consumo.
7. Limites de entrada e saída respeitam pausa, elegibilidade, cap e direitos claimable.

Esses testes são exploração aleatória com limites finitos. Não são demonstração matemática de todos os estados nem prova formal.

## Análise estática

Slither analisa os contratos próprios. A separação do deployer introduziu uma chamada externa na factory; a revisão acrescentou `nonReentrant` à criação. O gate rejeita High/Medium incondicionalmente e qualquer achado novo que não tenha revisão explícita.

As exceções examinadas estão em `scripts/slither-reviewed.json`, com descrição completa normalizada, fingerprint e justificativa individual. São: comparação de timestamp para período encerrado; consultas de saldo/elegibilidade no lote; e escritas de contabilidade no lote. O batch é restrito ao settler, protegido contra reentrância e limitado a 64 registros. Não se desativa globalmente nenhum detector. Tokens/políticas hostis podem bloquear disponibilidade; o limite de iterações não garante um custo de gas universal em toda rede ou com todo asset. Um beneficiário bloqueado reverte o lote inteiro; o settler deve conferir a política antes de submetê-lo.

## Operação, incidente e auditoria

Antes de produção, obter uma revisão independente da versão e do manifesto de fontes, configurar papéis em multisigs separados, verificar endereços imutáveis e fazer uma simulação de migração. Preservar documentação legal do crédito e evidências de cada valuation/cashflow. Não há destinatário privado de divulgação presumido: definir o canal de segurança com a governança antes de publicar endereços de produção.

Em incidente, o pauser bloqueia novas entradas, transferências e resgates; o compliance pode congelar contas específicas. Cancelamentos, repayments e claims de cashflow ficam disponíveis para minimizar aprisionamento durante pausa; todos os claims continuam sujeitos à elegibilidade. Se o próprio asset ou a política estiver comprometido, a pausa não assegura recuperação. Nova instância e plano de migração podem ser necessários.

O pacote não apresenta o protocolo como “sem riscos” ou “perfeito”. Os riscos administrativos, de crédito, legais, de liquidez, de asset e de migração são materialmente relevantes para uma revisão séria.

## Revisão de composição de 02/10/2026

Os testes adicionais verificam a descoberta ERC-7575 do share, o orçamento de 30.000 gas de ERC-165 e a atomicidade de lotes: registro tardio inválido, funding insuficiente e callback privilegiado. O batch não comprova completude ou fairness. Divisões de uma distribuição econômica entre transações precisam de bloqueio de operações sensíveis ao preço ou de um mecanismo próprio de epoch; esse mecanismo não faz parte da referência. Não anunciar suporte ao ERC-7943 ou ao ERC-3643 completo a partir da allowlist simples.

O achado informativo `too-many-digits` corresponde a `type(StructuredFundVault).creationCode`, bytecode produzido pelo compilador para CREATE2. Foi revisado como código de criação, não como constante financeira escrita manualmente. O gate de tamanho continua ativo.

## Atualização de 03/10/2026

O vault e a factory usam `ReentrancyGuardTransient` da OpenZeppelin 5.7.0, compilados com Solidity 0.8.37 para Osaka. A release final da biblioteca está no canal `dev`, ainda distinto do `latest` auditado. A [revisão da toolchain](TOOLCHAIN.md) detalha compatibilidade, custo e testes de callbacks, rollback e composição na mesma transação. Os [diagramas](SECURITY_DIAGRAMS.md) foram derivados dos printers do Slither e revisados contra o código.
