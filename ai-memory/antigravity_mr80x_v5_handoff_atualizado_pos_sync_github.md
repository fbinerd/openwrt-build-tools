# Handoff atualizado para Antigravity — Mercusys MR80X v5 / RTL8367S

## Objetivo

Continuar o diagnóstico da Ethernet do **Mercusys MR80X v5** no OpenWrt, comparando:

- boot por **initramfs**, no qual o RTL8367S inicializa e a Ethernet funciona;
- boot pelo **sysupgrade instalado em NAND/UBI**, no qual o acesso ao RTL8367S falha e o DHCP client não consegue operar normalmente.

Este documento substitui o handoff anterior.

**Importante:** o repositório foi sincronizado depois dos últimos testes. A branch atual já contém várias correções feitas pelo Codex que ainda não aparecem no comportamento dos logs fornecidos anteriormente.

Portanto, a primeira tarefa não é implementar novamente essas correções. A primeira tarefa é confirmar que uma nova imagem foi realmente compilada e está executando o código atualmente presente no GitHub.

---

# Repositório

```text
https://github.com/fbinerd/openwrt
```

Branch:

```text
codex-mr80x-v5-ethernet-debug
```

Arquivos principais:

```text
target/linux/mediatek/files/drivers/net/phy/rtk/rtl8367s_mdio.c
target/linux/mediatek/files/drivers/net/phy/rtk/rtl8367s.c
target/linux/qualcommax/dts/ipq5018-mr80x-v5.dts
package/kernel/rtl8367s-vendor/Makefile
```

O arquivo principal do driver consultado no estado sincronizado atual apresentou o blob SHA:

```text
7ff6a0c4985379c7174bd43ce5723b3adef26f5a
```

Use o estado atual da branch como fonte de verdade. Antes de modificar qualquer coisa, faça:

```sh
git status
git log -1 --oneline
git diff
```

e examine os arquivos atuais.

---

# Estado observado nos últimos logs

Os últimos logs comparados eram de imagens com:

```text
Linux 6.12.94
OpenWrt r35275+1-273b186ac3
build Sun Jul 12 16:03:57 2026
Machine model: Mercusys MR80X v5
```

O DTB reportado também era o mesmo entre initramfs e sysupgrade:

```text
Description: ARM64 OpenWrt mercusys_mr80x-v5 device tree blob
Data Size:   24361 Bytes
CRC32:       5e4bbf80
SHA1:        fe67a5fdf69ecde234e7a12081f40d76b7389796
```

Portanto, nos logs analisados:

```text
mesmo kernel
mesmo build ID
mesmo DTB
mesmo modelo
```

Apesar disso, o comportamento do RTL8367S era diferente.

---

# Initramfs — comportamento funcional

No initramfs, o driver consegue executar o protocolo indireto do RTL8367S sobre o barramento MDIO.

Exemplos de valores válidos:

```text
rtl8367s-mdio read phy=29 reg=25 data=0x6642
rtl8367s-mdio read phy=29 reg=25 data=0x0010
rtl8367s-mdio read phy=29 reg=25 data=0x0300
rtl8367s-mdio read phy=29 reg=25 data=0x0338
```

A inicialização termina com sucesso:

```text
rtl8367s rtk_switch_init ret=0
rtl8367s rtk_vlan_reset ret=0
rtl8367s rtk_vlan_init ret=0
```

As interfaces externas também são configuradas:

```text
rtl8367s ext0 sgmii nway off ret=0
rtl8367s ext0 hsgmii force ret=0
rtl8367s phy enable all ret=0
rtl8367s ext1 rgmii force ret=0
rtl8367s ext1 rgmii delay ret=0
```

O datapath depois apresenta link:

```text
nss-dp 39d00000.dp2 eth1: PHY Link up speed: 1000
```

O initramfs recebe tráfego e o DHCP client funciona.

---

# Sysupgrade — comportamento problemático dos logs anteriores

No sysupgrade, as operações de escrita no PHY MDIO 29 aparentavam sucesso:

```text
rtl8367s-mdio write phy=29 reg=31 data=0x000e ret=0
rtl8367s-mdio write phy=29 reg=23 data=0x13c2 ret=0
rtl8367s-mdio write phy=29 reg=24 data=0x0249 ret=0
rtl8367s-mdio write phy=29 reg=21 data=0x0003 ret=0
```

Mas a leitura indireta retornava:

```text
rtl8367s-mdio read phy=29 reg=25 data=0xffff
```

e então:

```text
rtl8367s rtk_switch_init ret=-1
```

Nos logs antigos, o driver ainda continuava:

```text
rtl8367s ext0 sgmii nway off ret=15
rtl8367s ext0 hsgmii force ret=15
rtl8367s phy enable all ret=15
rtl8367s ext1 rgmii force ret=15
rtl8367s ext1 rgmii delay ret=15
```

Também apareciam operações posteriores de VLAN/PVID.

---

# Descoberta crítica após revisar o GitHub atual

## Os logs anteriores não correspondem ao fluxo do código atualmente sincronizado

O código atual contém mudanças que deveriam produzir um log diferente.

No estado atual, `rtk_switch_init()` é executado em até cinco tentativas:

```c
for (attempt = 1; attempt <= 5; attempt++) {
    rtl8367s_hw_reset();

    ret = rtk_switch_init();
    pr_info("rtl8367s rtk_switch_init attempt=%d ret=%d\n",
            attempt, ret);

    if (!ret)
        break;

    msleep(200);
}

if (ret)
    return rtl8367s_api_to_errno(ret);
```

Portanto, uma imagem realmente compilada com o código atual deve imprimir:

```text
rtl8367s rtk_switch_init attempt=1 ret=...
```

e, em caso de falha:

```text
attempt=2
attempt=3
attempt=4
attempt=5
```

Os logs anteriores mostravam apenas:

```text
rtl8367s rtk_switch_init ret=-1
```

sem o campo:

```text
attempt=N
```

Isso é forte evidência de que os logs anteriores foram produzidos por um módulo/artefato anterior às correções atualmente presentes na branch.

---

# Correções que JÁ existem no código atual

## 1. Erros de leitura MDIO são propagados

O wrapper atual faz:

```c
ret = bus->read(bus, phy_addr, phy_register);

if (ret < 0) {
    *read_data = 0xffff;

    pr_info("rtl8367s-mdio read phy=%u reg=%u failed ret=%d\n",
            phy_addr, phy_register, ret);

    ret = RT_ERR_SMI;
} else {
    *read_data = ret & 0xffff;

    pr_info("rtl8367s-mdio read phy=%u reg=%u data=0x%04x\n",
            phy_addr, phy_register, *read_data);

    ret = RT_ERR_OK;
}

return ret;
```

Isso significa:

- erro negativo de `bus->read()` não deve mais ser escondido como sucesso;
- o log deve mostrar `failed ret=<erro>`;
- a API vendor recebe `RT_ERR_SMI`.

Não implementar novamente essa correção sem primeiro verificar o código atual.

---

## 2. Erros de escrita MDIO são propagados

O código atual retorna:

```c
return ret < 0 ? RT_ERR_SMI : RT_ERR_OK;
```

Portanto, falhas reais de `bus->write()` também não são mais ignoradas.

---

## 3. O reset já foi reforçado

A sequência atual é aproximadamente:

```c
gpiod_set_value_cansleep(gsw->reset_gpiod, 1);
usleep_range(10000, 11000);

gpiod_set_value_cansleep(gsw->reset_gpiod, 0);
msleep(700);
```

Isto representa:

```text
assert reset: aproximadamente 10 ms
wait após deassert: 700 ms
```

Portanto, não começar simplesmente adicionando mais delay.

---

## 4. Já existem cinco tentativas completas

Cada tentativa executa novamente:

```text
hardware reset
700 ms de espera
rtk_switch_init
```

e há ainda:

```text
200 ms
```

entre tentativas malsucedidas.

Se todas as cinco falharem, o driver retorna erro.

---

## 5. `init_gsw()` já propaga erro

O código atual segue a lógica:

```c
ret = rtl8367s_hw_init();
if (ret)
    return ret;

ret = set_rtl8367s_sgmii();
if (ret)
    return ret;

return set_rtl8367s_rgmii();
```

Portanto:

```text
rtl8367s_hw_init falhou
    ↓
não configurar SGMII
    ↓
não configurar RGMII
```

---

## 6. O probe já deve falhar corretamente

O probe atual faz:

```c
ret = init_gsw();

if (ret)
    return dev_err_probe(&pdev->dev, ret,
                         "failed to initialize RTL8367S\n");
```

Logo, se as cinco tentativas falharem, o driver não deveria continuar normalmente para registrar o switch e configurar VLAN.

---

# Consequência

Antes de qualquer nova alteração no driver:

> CONFIRMAR QUE O NOVO SYSUPGRADE REALMENTE CONTÉM O CÓDIGO ATUAL.

Os logs anteriores não são suficientes para avaliar as correções atuais porque aparentemente foram produzidos por um módulo antigo.

---

# Primeira tarefa para o Antigravity

## Confirmar árvore e artefatos

Executar:

```sh
cd /home/fabiano/opw/openwrt

git status
git branch --show-current
git log -1 --oneline
```

Confirmar:

```text
branch codex-mr80x-v5-ethernet-debug
```

Depois:

```sh
grep -R -n 'rtk_switch_init attempt=' \
target/linux/mediatek/files/drivers/net/phy/rtk/
```

Deve encontrar a string no código atual.

---

# Forçar recompilação do driver

Não confiar apenas em:

```sh
make
```

porque um artefato antigo pode permanecer no `build_dir`.

Executar primeiro uma limpeza específica do pacote:

```sh
make package/kernel/rtl8367s-vendor/clean V=s
```

Depois:

```sh
make package/kernel/rtl8367s-vendor/compile V=s -j1
```

E então reconstruir as imagens:

```sh
make -j"$(nproc)"
```

Se houver suspeita de cache adicional:

```sh
make target/linux/clean
make -j"$(nproc)"
```

Evitar `make clean` completo inicialmente, a menos que seja necessário.

---

# Verificar se o artefato compilado contém a string nova

No host de build:

```sh
grep -R -a -n 'rtk_switch_init attempt=' \
build_dir/ staging_dir/ 2>/dev/null
```

Também procurar:

```sh
grep -R -a -n 'failed to initialize RTL8367S' \
build_dir/ staging_dir/ 2>/dev/null
```

Depois de iniciar o roteador com a nova imagem:

```sh
grep -R -a 'rtk_switch_init attempt=' \
/lib/modules/$(uname -r)/ 2>/dev/null
```

ou:

```sh
strings /lib/modules/$(uname -r)/*.ko 2>/dev/null |
grep 'rtk_switch_init attempt='
```

Adaptar o caminho ao nome real do `.ko`.

---

# Critério para saber se o novo código está realmente rodando

O boot deve mostrar algo como:

```text
rtl8367s reset assert
rtl8367s reset deassert
rtl8367s rtk_switch_init attempt=1 ret=...
```

Se falhar:

```text
rtl8367s reset assert
rtl8367s reset deassert
rtl8367s rtk_switch_init attempt=2 ret=...
```

até no máximo:

```text
attempt=5
```

Se continuar aparecendo apenas:

```text
rtl8367s rtk_switch_init ret=-1
```

a imagem não está executando a versão atual do driver.

---

# Como interpretar o próximo log

## Caso A — sysupgrade funciona com o código atual

Se aparecer:

```text
attempt=1 ret=0
```

ou uma tentativa posterior retornar 0:

```text
attempt=N ret=0
```

então as correções do Codex resolveram ou mitigaram a divergência.

Registrar qual tentativa funcionou.

Se apenas tentativas posteriores funcionarem, existe evidência de:

```text
reset/timing/estado inicial
```

---

## Caso B — `bus->read()` retorna erro negativo

Exemplo:

```text
rtl8367s-mdio read phy=29 reg=25 failed ret=-110
```

Então investigar o controlador MDIO e o significado exato do errno.

Possibilidades:

```text
-ETIMEDOUT
-EIO
-EBUSY
```

Nesse caso, `0xffff` dos logs antigos era apenas o valor substituto do wrapper.

---

## Caso C — `bus->read()` retorna `0xffff` como dado real

Exemplo:

```text
rtl8367s-mdio read phy=29 reg=25 data=0xffff
```

sem:

```text
failed ret=...
```

Então o `mii_bus` considera a transação bem-sucedida, mas o acesso indireto do RTL8367S não está devolvendo conteúdo válido.

Esse cenário aponta mais fortemente para:

```text
estado do switch
reset
protocolo indireto
pinctrl
linha MDIO
estado herdado
```

---

## Caso D — cinco tentativas falham

O esperado será:

```text
attempt=1 ret=...
attempt=2 ret=...
attempt=3 ret=...
attempt=4 ret=...
attempt=5 ret=...
failed to initialize RTL8367S
```

Nesse caso, não continuar corrigindo VLAN.

A próxima etapa deve ser instrumentar:

```text
GPIO 39
estado antes do reset
estado depois do reset
teste MDIO antes do reset
teste MDIO depois do reset
```

---

# Próxima instrumentação, somente se o código atual ainda falhar

## Registrar estado lógico e raw do GPIO de reset

O DTS usa:

```text
reset-gpios = <&tlmm 39 GPIO_ACTIVE_LOW>
```

Adicionar logs:

```c
dev_info(gsw->dev,
         "reset gpio before logical=%d raw=%d\n",
         gpiod_get_value_cansleep(gsw->reset_gpiod),
         gpiod_get_raw_value_cansleep(gsw->reset_gpiod));
```

Depois do assert:

```c
gpiod_set_value_cansleep(gsw->reset_gpiod, 1);

dev_info(gsw->dev,
         "reset gpio asserted logical=%d raw=%d\n",
         gpiod_get_value_cansleep(gsw->reset_gpiod),
         gpiod_get_raw_value_cansleep(gsw->reset_gpiod));
```

Depois do deassert:

```c
gpiod_set_value_cansleep(gsw->reset_gpiod, 0);

dev_info(gsw->dev,
         "reset gpio deasserted logical=%d raw=%d\n",
         gpiod_get_value_cansleep(gsw->reset_gpiod),
         gpiod_get_raw_value_cansleep(gsw->reset_gpiod));
```

Objetivo:

Comparar diretamente:

```text
initramfs
vs
sysupgrade
```

---

# Teste antes e depois do reset

Se as cinco tentativas atuais continuarem falhando no sysupgrade, adicionar um sanity check controlado:

```text
1. tentar acesso indireto antes de tocar no reset;
2. registrar resultado;
3. executar reset;
4. esperar 700 ms;
5. repetir exatamente o mesmo acesso;
6. registrar resultado.
```

Pergunta principal:

```text
O switch responde antes do reset e deixa de responder depois?
```

Se sim, a sequência de reset é a principal suspeita.

---

# Teste temporário sem hardware reset

Somente se necessário, criar um mecanismo de teste:

```text
mediatek,skip-hw-reset
```

ou parâmetro equivalente.

Comparar:

```text
initramfs com reset
initramfs sem reset
sysupgrade com reset
sysupgrade sem reset
```

Não transformar “skip reset” em solução definitiva antes de entender o resultado.

---

# Diferença temporal já conhecida

Nos logs anteriores:

## Initramfs

```text
QCA SSDK pronto: aproximadamente 4.132 s
RTL8367S probe: aproximadamente 4.334 s
```

## Sysupgrade

```text
QCA SSDK pronto: aproximadamente 5.492 s
RTL8367S probe: aproximadamente 5.736 s
```

O sysupgrade chegava ao probe aproximadamente 1,4 segundo mais tarde em tempo absoluto.

Portanto:

> A hipótese simples de que o sysupgrade acessa o RTL8367S cedo demais desde o power-on é fraca.

Além disso, nos logs antigos havia novas tentativas muito mais tarde que continuavam falhando.

O problema ainda pode ser timing **relativo ao reset**, mas não parece ser simplesmente falta de tempo total desde a energização.

---

# Fallback de VLAN que ainda existe

O código atual de `rtl8367s.c` ainda possui fallback:

```c
ret = rtk_vlan_set(vid, &vlan_cfg);

if (ret == RT_ERR_OK)
    return 0;

pr_warn("rtl8367s: rtk_vlan_set failed ret=%d, using direct vlan4k fallback\n",
        ret);

return rtl8367c_set_vlan_asic(vid, mbr, untag, fid);
```

Esse fallback não deve ser removido automaticamente.

Com o fluxo atual:

```text
init_gsw falha
    ↓
probe falha
    ↓
swconfig não deveria ser registrado
```

Portanto, o fallback de VLAN só deve ser avaliado depois que a inicialização principal do RTL8367S estiver funcionando.

Ele pode ser útil para uma incompatibilidade específica da API de VLAN, mas:

> não é solução para `rtk_switch_init()` falhando.

---

# Possível ponto secundário ainda existente

O callback:

```c
static void reset_gsw(void)
{
    init_gsw();
}
```

continua ignorando o retorno de `init_gsw()` porque a interface de callback aparentemente usa `void`.

Isso não afeta o probe inicial, que agora trata o erro corretamente.

Mas, em um reset solicitado posteriormente via swconfig, uma falha pode ficar apenas nos logs.

Se necessário, melhorar o log:

```c
static void reset_gsw(void)
{
    int ret;

    ret = init_gsw();
    if (ret)
        pr_err("rtl8367s: reset/reinit failed ret=%d\n", ret);
}
```

Não é a prioridade principal.

---

# O que NÃO implementar novamente

O código atual já possui:

```text
propagação de erro de MDIO
erro de write MDIO
reset de 10 ms
espera de 700 ms
5 tentativas
propagação de erro de rtl8367s_hw_init
propagação de erro de SGMII
propagação de erro de RGMII
falha do platform probe
```

Não duplicar essas mudanças.

---

# Ordem exata recomendada para o Antigravity

## Etapa 1

Inspecionar a branch atual e confirmar as correções existentes.

## Etapa 2

Forçar recompilação limpa do pacote `rtl8367s-vendor`.

## Etapa 3

Verificar que o `.ko` compilado contém:

```text
rtk_switch_init attempt=
```

## Etapa 4

Gerar novos:

```text
initramfs
sysupgrade
```

a partir da mesma árvore.

## Etapa 5

Capturar novos logs completos.

## Etapa 6

Comparar especificamente:

```text
attempt=N
failed ret=-errno
data=0xffff
failed to initialize RTL8367S
```

## Etapa 7

Somente se ainda falhar, adicionar instrumentação de GPIO raw/logical e sanity check antes/depois do reset.

---

# Resultado esperado do próximo teste

## Initramfs

Esperado:

```text
rtl8367s reset assert
rtl8367s reset deassert
rtl8367s rtk_switch_init attempt=1 ret=0
```

## Sysupgrade

Uma das seguintes respostas será extremamente informativa:

### Sucesso imediato

```text
attempt=1 ret=0
```

### Sucesso após retry

```text
attempt=1 ret=-...
attempt=2 ret=0
```

### Erro real de MDIO

```text
rtl8367s-mdio read ... failed ret=-...
```

### `0xffff` real

```text
rtl8367s-mdio read ... data=0xffff
```

### Falha definitiva

```text
attempt=1 ...
attempt=2 ...
attempt=3 ...
attempt=4 ...
attempt=5 ...
failed to initialize RTL8367S
```

Cada caso direciona a investigação de forma diferente.

---

# Conclusão atualizada

A conclusão sobre o sintoma principal permanece:

```text
INITRAMFS
    RTL8367S acessível
    rtk_switch_init funciona
    Ethernet funciona

SYSUPGRADE DOS LOGS ANTERIORES
    acesso indireto retorna 0xffff
    rtk_switch_init falha
    Ethernet não funciona corretamente
```

Porém, a conclusão sobre o próximo trabalho mudou.

O repositório atual já contém as principais correções estruturais anteriormente recomendadas:

```text
tratamento de erro
retry
reset maior
interrupção da inicialização
falha correta do probe
```

Os logs anteriores não apresentam as mensagens que o código atual obrigatoriamente deveria gerar.

A hipótese mais provável é:

> os últimos logs foram produzidos por imagens ou módulos compilados antes do estado atual sincronizado da branch, ou por artefatos incrementais antigos.

Portanto, a prioridade absoluta é:

```text
FORÇAR REBUILD DO DRIVER
↓
CONFIRMAR STRING NOVA NO .KO
↓
GERAR NOVAS IMAGENS
↓
CAPTURAR NOVOS LOGS
```

Somente os novos logs devem ser usados para decidir a próxima alteração no código.

Se o sysupgrade continuar falhando com o driver atual confirmado, a investigação seguinte deve se concentrar em:

```text
retorno real do MDIO
GPIO 39 lógico/raw
estado antes/depois do reset
protocolo indireto do RTL8367S
diferença de estado físico entre initramfs e sysupgrade
```