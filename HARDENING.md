# Hardening do ambiente Docker

Atividade prática de hardening de containers (FAP DevOps, Turma 5).
Fork de carlhenriquex/hardening-container. Aluno: Luiz Filipe.

## Como executar

    cp .env.example .env        # preencher os valores
    docker compose up --build -d
    bash validar.sh             # roda as verificações da seção 4

## 1. Problemas encontrados

| Nº | Onde | O que estava errado | Risco |
|----|------|---------------------|-------|
| 0 | Dockerfile e app/package.json | O projeto não buildava. O `RUN npm install` roda em `/app`, mas o `package.json` fica em `/app/app`, e ele estava vazio (0 bytes). | Não é falha de segurança, mas sem corrigir não dava para executar nem validar nada. |
| 1 | Dockerfile | `FROM ubuntu:latest` | Imagem grande, cheia de pacotes que a aplicação não usa, e `latest` muda com o tempo. Cada build pode gerar uma imagem diferente. |
| 2 | Dockerfile | `apt-get install nodejs npm` sem versão e sem limpeza | A versão do Node fica por conta do repositório do Ubuntu, e o npm com todas as dependências dele fica na imagem final sem necessidade. |
| 3 | Dockerfile | `COPY . .` | Copia docs, compose, a pasta .git e qualquer `.env` que existir para dentro da imagem. |
| 4 | Dockerfile | Sem instrução `USER` | A aplicação roda como root dentro do container. |
| 5 | Dockerfile | `ENV DB_PASSWORD=123456` | A senha fica gravada nas camadas da imagem e no Git. Quem tiver a imagem lê com `docker history` ou `docker inspect`. |
| 6 | docker-compose.yml | `mysql:latest` | Versão imprevisível, pode mudar de uma hora para outra. |
| 7 | docker-compose.yml | `MYSQL_ROOT_PASSWORD: root` escrito no arquivo | Senha fraca e pública, versionada junto com o projeto. |
| 8 | docker-compose.yml | Porta 3306 publicada em todas as interfaces | Qualquer máquina que alcance o host consegue tentar entrar no banco, e a senha do root era `root`. |
| 9 | docker-compose.yml | Porta 3000 publicada em todas as interfaces | A aplicação fica exposta para toda a rede sem necessidade. |
| 10 | docker-compose.yml | Sem limite de CPU, memória e processos | Um container com problema ou comprometido pode consumir todo o host. |
| 11 | docker-compose.yml | Uma rede só, com saída para a internet | O banco consegue falar com a internet, o que facilita tirar dados de lá em caso de invasão. |
| 12 | docker-compose.yml | Só existia o usuário root do banco | A aplicação teria que usar o root do banco para tudo. |
| 13 | docker-compose.yml | Nenhuma restrição no container | Sistema de arquivos gravável, capabilities padrão do Docker e possibilidade de escalar privilégio. |

O erro do item 0 está salvo em `evidencias/01-antes-build-falha.txt`.

## 2. Medidas aplicadas

| Medida | Onde | Objetivo | Risco reduzido |
|--------|------|----------|----------------|
| `package.json` válido e remoção do `npm install` (a aplicação não tem dependências) | app/package.json, Dockerfile | Fazer o projeto buildar e executar | Item 0 |
| Imagem base `node:22-alpine` | Dockerfile | Imagem oficial, pequena e com versão fixa | Itens 1 e 2 |
| `COPY --chown=node:node app/ ./` e `.dockerignore` | Dockerfile, .dockerignore | Levar para a imagem só o código da aplicação | Item 3 |
| `USER node` | Dockerfile | Rodar sem privilégios de administrador | Item 4 |
| Remoção do `ENV DB_PASSWORD` | Dockerfile | Nenhum segredo nas camadas da imagem | Item 5 |
| `mysql:8.4` (versão LTS) | docker-compose.yml | Versão previsível | Item 6 |
| Senhas no `.env`, lidas como `${VARIAVEL}` | docker-compose.yml, .env, .env.example, .gitignore | Tirar os segredos dos arquivos versionados | Itens 5 e 7 |
| Senhas aleatórias de 32 caracteres | .env | Acabar com senha fraca | Item 7 |
| Banco sem `ports` | docker-compose.yml | Banco acessível só pela aplicação | Item 8 |
| Porta 3000 publicada só em `127.0.0.1` | docker-compose.yml | Expor só o necessário | Item 9 |
| `mem_limit`, `cpus` e `pids_limit` | docker-compose.yml | Limitar o consumo de recursos | Item 10 |
| Rede `interna` com `internal: true` para app e banco | docker-compose.yml | Banco isolado e sem saída para a internet | Item 11 |
| Usuário comum do banco (`MYSQL_USER`) para a aplicação | docker-compose.yml | A aplicação não usa o root do banco | Item 12 |
| `read_only`, `cap_drop: ALL` e `no-new-privileges` | docker-compose.yml | Container só com o acesso que precisa | Item 13 |
| Healthcheck no banco e `depends_on` com `service_healthy` | docker-compose.yml | A aplicação só sobe com o banco pronto | Disponibilidade |

Também usei `${VARIAVEL:?mensagem}` no compose. Se alguém subir o projeto sem o `.env`, o Docker para com uma mensagem clara em vez de subir o banco com senha vazia.

## 3. Respostas das etapas

**Etapa 2. Por que uma imagem menor reduz a superfície de ataque?**
Cada pacote instalado é um código a mais que pode ter falha. Com menos coisa na imagem, sobram menos vulnerabilidades para corrigir e menos ferramentas prontas (shell completo, gerenciador de pacotes, compiladores) para um invasor usar depois de entrar.

**Etapa 3. Qual o impacto de um atacante controlar uma aplicação que roda como administrador no container?**
Ele vira root dentro do container: instala ferramentas, altera arquivos, lê tudo que estiver lá (inclusive senhas) e usa as capabilities do root, por exemplo para varrer a rede. Se houver uma falha no kernel ou no Docker, ou uma configuração frouxa, ele sai do container já como root do host, porque sem user namespace o root do container é o mesmo usuário 0 do host.

**Etapa 4.1. Por que senha no Dockerfile é risco mesmo com a aplicação funcionando?**
Porque funcionar não tem relação com estar protegido. A senha fica gravada na imagem e no histórico do Git para sempre, e vai junto para todo lugar onde a imagem ou o repositório forem parar.

**Etapa 4.2. Por que o `.env` não deve ir para o repositório?**
Porque ele guarda os valores reais. No repositório, qualquer pessoa com acesso (ou todo mundo, se for público) passa a ter as senhas, e apagar depois não resolve, porque o histórico guarda.

**Etapa 4.3. Qual a finalidade do `.env.example`?**
Mostrar quais variáveis o projeto precisa, sem os valores. Quem clona copia o arquivo para `.env` e preenche.

**Etapa 4.4. Qual a diferença entre senha direto no compose e variável vinda do `.env`?**
Com a senha no compose, ela é versionada e todo mundo que recebe o projeto recebe a senha. Com a variável, o compose só tem o nome, e o valor fica fora do Git, em cada ambiente. Dá para ter senhas diferentes em desenvolvimento e produção e trocar a senha sem mexer no código. O `.env` continua sendo texto puro no disco, então ele protege o repositório, não a máquina.

**Etapa 5. O banco precisa ter a porta disponível para o host?**
Não. Só a aplicação fala com o banco, e ela faz isso pela rede interna do Docker, usando o nome do serviço (`banco:3306`). Publicar a porta só serve para abrir mais um ponto de ataque.

**Etapa 6. O que acontece se um container consumir toda a CPU ou memória?**
Os outros serviços do host ficam lentos ou param. Sem memória, o sistema começa a matar processos, e pode matar justamente um serviço que não tinha nada a ver com o problema. Na prática é uma negação de serviço.

**Etapa 7. Isolamento e exposição.**
Não encontrei `privileged`, montagem do `docker.sock`, `network_mode: host` nem volumes do host. O que faltava eram as restrições, que entraram na seção 2.

## 4. Validação

Saída completa em `evidencias/02-validacao.txt`, gerada por `bash validar.sh`.

| Verificação | Resultado |
|-------------|-----------|
| Usuário da aplicação | `uid=1000(node) gid=1000(node)` |
| Escrita em `/app` | `touch: /app/teste: Read-only file system` |
| Variáveis recebidas do `.env` | `DB_HOST=banco DB_USER=app_user DB_NAME=sistema DB_PASSWORD=(32 caracteres)` |
| Aplicação alcança o banco | `conectou em banco:3306` |
| Porta do banco no host | `3306/tcp` sem publicação, porta 3306 fechada no host |
| Banco com saída para a internet | `sem saida para a internet` |
| Limites da aplicação | 128 MB de memória, 0,5 CPU, 50 processos, `read_only=true`, `cap_drop=[ALL]`, `no-new-privileges` |
| Limites do banco | 1 GB de memória, 1 CPU, `no-new-privileges` |
| Conteúdo da imagem | Só `package.json` e `server.js` em `/app`, imagem com 236 MB |
| Senha no histórico da imagem | 0 ocorrências de PASSWORD |
| `.env` no Git | Ignorado pela linha 1 do `.gitignore`, fora do `git status` |

Não tenho o tamanho da imagem original para comparar, porque ela não chegou a ser construída.

## 5. Análise final

**1. Qual era o principal risco?**
As senhas escritas nos arquivos versionados, somadas ao banco aberto para a rede. Qualquer pessoa com o repositório e acesso de rede ao host entrava no MySQL como root usando a senha `root`.

**2. Qual alteração foi mais importante?**
Tirar os segredos do Dockerfile e do compose. As outras medidas diminuem o estrago de uma invasão, mas essa fecha o caminho mais direto. E senha que vaza em imagem ou em histórico do Git não tem como recolher, só trocando.

**3. O que poderia acontecer se o container da aplicação fosse comprometido?**
Antes: o invasor seria root, leria a senha, instalaria ferramentas, usaria o container para atacar a rede e poderia travar o host consumindo recursos. Agora: ele é o usuário `node`, não grava no disco, não tem capabilities, não escala privilégio e esbarra nos limites de CPU, memória e processos. Ele ainda leria a senha que a aplicação recebe e acessaria o banco `sistema` como `app_user`. O hardening limita o dano, não zera.

**4. Como o menor privilégio foi aplicado?**
Usuário `node` em vez de root, `cap_drop: ALL`, `no-new-privileges`, sistema de arquivos somente leitura, usuário comum no banco em vez do root, banco sem porta publicada e rede interna sem saída para a internet.

**5. Por que o `.env` não deve ir para o repositório?**
Porque tem os valores reais das senhas, e o Git guarda o histórico. Uma vez enviado, tem que considerar a senha vazada e trocar.

**6. Qual a função do `.env.example`?**
Documentar os nomes das variáveis necessárias, sem os valores, para quem for rodar o projeto criar o próprio `.env`.

**7. Como receber verificações de segurança automáticas em uma pipeline?**
Com um workflow do GitHub Actions rodando a cada push: Hadolint para o Dockerfile, Trivy para vulnerabilidades e erros de configuração na imagem, e Gitleaks para segredos no código. A pipeline falha quando aparece algo de severidade alta, e o Dependabot avisa quando a imagem base tem atualização.

**8. Que medidas adicionais caberiam no Kubernetes?**
Secrets (ou um cofre externo) no lugar do `.env`, `securityContext` com `runAsNonRoot`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false` e `capabilities: drop: ALL`, `requests` e `limits` de recursos, NetworkPolicy liberando só a aplicação para o banco, Pod Security Standards no nível restricted e RBAC mínimo para a ServiceAccount.

## 6. O que ainda dá para melhorar

- As senhas chegam como variáveis de ambiente, então aparecem em `docker inspect`. O passo seguinte seria usar Docker secrets com `MYSQL_ROOT_PASSWORD_FILE`.
- As imagens estão fixadas por tag (`node:22-alpine`, `mysql:8.4`). Fixar pelo digest garantiria exatamente o mesmo conteúdo em todo build.
- No banco não removi as capabilities, porque a imagem oficial do MySQL precisa de algumas na inicialização (ajustar o dono dos arquivos e trocar para o usuário `mysql`). Não testei qual é o conjunto mínimo.
- A aplicação é só um `console.log` e encerra. A porta 3000 ficou mapeada em `127.0.0.1` para quando ela virar um servidor web.
