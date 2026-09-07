# NPC Scene — delay entre loops e correções

Base recebida: `16c4039` (`Fix hl2 loast coast incorrectly referenced`).
Branch de trabalho: `patches/loop-delay-and-bugfixes`.

## Escopo

Foram revisados os nove arquivos Lua originais, o README e o manifesto do addon.
Os seis catálogos foram carregados integralmente e tiveram sua estrutura auditada:
23.264 entradas no total. Nenhum desses catálogos foi reescrito ou modificado.
O leitor experimental `scenes.image_reader.lua` também permanece idêntico ao original.

As alterações de runtime se concentram em dois arquivos:

| Arquivo | Alterações |
| --- | --- |
| `lua/weapons/gmod_tool/stools/npc_scene.lua` | Delay, ciclo de reprodução, reload, tecla/rede, HUD e descoberta de cenas. |
| `lua/autorun/npc_scene_init.lua` | Distribuição dos catálogos sem executá-los no servidor e preservação do namespace no reload. |

A suíte em `tests/` é independente do addon e não é carregada pelo jogo.
Não foram adicionadas dependências de runtime nem alterada a organização do addon.
O mecanismo original de recriação do NPC no reload foi mantido, com verificações de falha e limpeza.

## Delay entre loops

Novo controle: **Loop delay (seconds)**.
Nova convar: **`npc_scene_loop_delay`**.

O intervalo aceito é de **0 a 60 segundos**, incluindo valores fracionários.
O controle mostra duas casas decimais. O padrão é **0**, sem pausa adicional.

```text
npc_scene_loop 2
npc_scene_loop_delay 1.5
```

Depois de configurar, aplique a ferramenta no NPC. Esse exemplo executa a cena três vezes:
a execução inicial e duas repetições, com uma pausa de 1,5 segundo entre elas.
Não há pausa antes da primeira execução nem após a última.
`Loop = 0` continua significando uma única execução.

Cada sequência captura seu caminho, número de repetições e delay ao iniciar.
Alterar os controles não muda uma sequência já em execução. Reaplicar a ferramenta
configura a próxima sequência, inclusive quando o modo de múltiplas aplicações está habilitado.
O estado ativo permanece ligado durante os intervalos, até terminar a última execução.

A duração de cada execução é obtida novamente por `Entity:PlayScene`; trata-se da
estimativa fornecida pelo motor, não de um evento de conclusão exata. O agendamento
usa timers do jogo, sujeitos aos ticks e ao relógio de simulação. [1][2]

## Commits de implementação

| Commit | Correção ou adição |
| --- | --- |
| `74929cd` | Harness Lua isolado e auditoria dos seis catálogos. |
| `27d7c7d` | Finalização dos loops; contador configurado preservado; execuções sobrepostas isoladas; validação de duração; limpeza de timers e entidades de cena. |
| `1a5e5ff` | Delay configurável em segundos, valor fracionário na rede e controle no painel. |
| `d2fb175` | Opção de reload lida do jogador; remoção efetiva do nome; preservação do NPC e dos timers quando a duplicação falha; bloqueio de jogadores/mundo como alvos. |
| `1008126` | Validação de mensagens, jogador e NPC; autorização de vínculo de tecla no servidor; limitação de frequência; uma mensagem por pressão de botão; espera pela replicação do NPC. |
| `21e31c7` | Remoção somente da extensão final `.vcd`; rejeição de caminho vazio; uso do índice real da entidade; retorno de falha na reprodução. |
| `c9c567e` | Um hook de HUD por entidade; tolerância à replicação tardia, convar ausente e osso sem posição; remoção de variável global acidental. |
| `b94753a` | União dos catálogos sem sobrescrever listas numéricas; busca no conteúdo montado; filtro de backups; reconstrução de janela removida. |
| `f186d8c` | Catálogos executados somente no cliente; namespace preservado ao recarregar o inicializador. |
| `1134e8c` | Reaplicação da mesma cena no modo múltiplo passa a respeitar os novos ajustes de delay e a opção Start On. |

O commit final documenta a entrega. A relação completa, com seu hash, está no `COMMITS.txt`
da entrega e em `git log`. Os patches devem ser aplicados na ordem; existem dependências
entre correções do ciclo de reprodução e a funcionalidade de delay.

### Comportamentos corrigidos

O contador de loops não é mais decrementado na variável de configuração do NPC.
Ao terminar, o NPC deixa de ficar permanentemente marcado como ativo. Durações inválidas
não geram timers nem deixam uma reprodução travada. A conclusão de uma cena sobreposta
não encerra prematuramente o estado ativo das demais. A remoção ou o reload do NPC cancela
as sequências associadas; callbacks antigos não alteram uma sequência nova.

O reload consulta `Tool:GetClientNumber`, em vez de procurar a convar do cliente como uma
convar global do servidor. A opção padrão mantém o nome; a opção de remoção limpa tanto o
estado do addon quanto o nome da entidade recriada. O NPC original só é removido após a
criação válida do substituto. [3]

A tecla dispara uma vez por pressão, em vez de enviar mensagens em todos os ticks enquanto
fica pressionada. A entrada é ignorada enquanto há foco de teclado em um painel ou o menu
do jogo está aberto. O servidor aceita o comando apenas do jogador que configurou o vínculo
no NPC e aplica um intervalo mínimo de 0,1 segundo por NPC. Vários NPCs continuam podendo
usar a mesma tecla. O clique da ferramenta não está sujeito a esse limitador.

A união das seis listas preserva todos os 23.260 caminhos distintos presentes nelas.
As duas entradas `friendlyfire01.vcd.bak` e `friendlyfire02.vcd.bak` do catálogo de L4D2
permanecem nos dados originais, mas não são exibidas como cenas selecionáveis.
A varredura de arquivos usa `GAME`, que inclui addons e jogos montados, em vez de restringir
a busca a `MOD`. [4]

## Testes executados

Resultado final: **66 testes passaram; nenhuma falha**.

```sh
python3 tests/run.py
```

O runner procura Lua/LuaJIT instalado. Na falta de um executável, pode usar a biblioteca
compartilhada Lua 5.3/5.4 por `ctypes`, sem pacotes Python externos. É necessário Python 3.8+
para o runner. Também é possível executar diretamente, na raiz do repositório:

```sh
lua tests/run.lua
```

Nesta entrega, os testes foram executados com **Lua 5.4** e APIs do Garry's Mod simuladas.
O loader normaliza o operador GLua `!=` para `~=` apenas em memória, durante o teste.
As funções reais do addon são carregadas; não são substituídas por outra implementação.
O relógio simulado permite validar os instantes dos loops e as condições de corrida de callbacks.

A suíte cobre configuração, atraso fracionário, repetição e reexecução, sobreposição,
falhas de reprodução/duplicação, cancelamento, remoção de entidades, mensagens indevidas,
autorização, limitação de frequência, entrada de teclado, HUD, união de todos os catálogos,
busca por arquivos, recriação da janela e inicialização nos dois realms.

Além dos testes, foram verificados os diffs com `git diff --check`, a integridade do
repositório com `git fsck --full` e a identidade byte a byte dos catálogos e do leitor
experimental em relação ao commit recebido. As chaves de diretórios dos catálogos também
foram auditadas para detectar sobrescritas silenciosas por chaves duplicadas.

## Limites da validação e teste no jogo

**O Garry's Mod não foi executado neste ambiente.** Os testes não substituem uma sessão real
com o motor Source, as entidades concretas de cena e os conteúdos montados. A presença de
cada arquivo/voz/animação de um jogo instalado não foi verificada. O mapeamento original de
jogos montados para os catálogos estáticos foi preservado.

Antes de publicar, execute no jogo esta verificação de integração:

| Cenário | Resultado esperado |
| --- | --- |
| Loop 2 e delay 1,5 | Três execuções, com pausa somente entre elas, e término sem ficar ativo. |
| Loop 0 e delay 10 | Uma execução, sem aguardar dez segundos para terminar. |
| Tecla configurada e Start On desmarcado | Apenas configura; cada nova pressão inicia uma sequência. Segurar a tecla não cria spam. |
| Múltiplas aplicações e mudança de delay | Nova sequência usa o novo ajuste; a anterior conserva seu intervalo. |
| Reload durante cena e durante pausa | Nenhuma repetição posterior; opção de manter/remover nome respeitada. |
| Nome em NPC e prop, com renomeações repetidas | Um rótulo por entidade, sem erros de HUD. |
| Dois jogadores e vínculos distintos | Um jogador não aciona por rede o vínculo configurado pelo outro. |
| Cena local junto a cenas dos jogos montados | Todas permanecem na lista; os dois backups não aparecem. |
| NPC customizado, duplicador e addons de proteção | Conferir permissões e estado da entidade recriada no ambiente real. |

O arquivo `lua/autorun/client/scenes.image_reader.lua` começa com `do return end` e está
explicitamente marcado como experimental/abandonado no original. Ele foi revisado, mas
continua desativado e não foi reescrito: há problemas de restauração binária, leitura de
bytes, tabelas não inicializadas e referências a `buf` não definido no trecho inativo.
Este patch não habilita esse leitor nem afirma torná-lo funcional; a listagem ativa usa
os catálogos existentes e a descoberta de arquivos.

## Referências de API consultadas

[1] Facepunch — Entity:PlayScene: https://wiki.facepunch.com/gmod/Entity:PlayScene

[2] Facepunch — timer.Create: https://wiki.facepunch.com/gmod/timer.Create

[3] Facepunch — Tool:GetClientNumber: https://wiki.facepunch.com/gmod/Tool:GetClientNumber

[4] Facepunch — File Search Paths: https://wiki.facepunch.com/gmod/File_Search_Paths

[5] Facepunch — Entity:CallOnRemove: https://wiki.facepunch.com/gmod/Entity:CallOnRemove

[6] Facepunch — DForm:NumSlider: https://wiki.facepunch.com/gmod/DForm:NumSlider

[7] Facepunch — input.IsButtonDown: https://wiki.facepunch.com/gmod/input.IsButtonDown
