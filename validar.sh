#!/usr/bin/env bash
# Valida as medidas de hardening. Uso: bash validar.sh

echo "== 1. Usuario que executa a aplicacao"
docker compose run --rm -T app id

echo; echo "== 2. Sistema de arquivos somente leitura"
docker compose run --rm -T app sh -c 'touch /app/teste 2>&1 || true'

echo; echo "== 3. Variaveis recebidas do .env (sem mostrar a senha)"
docker compose run --rm -T app sh -c 'echo "DB_HOST=$DB_HOST DB_USER=$DB_USER DB_NAME=$DB_NAME DB_PASSWORD=(${#DB_PASSWORD} caracteres)"'

echo; echo "== 4. App alcanca o banco pela rede interna"
docker compose run --rm -T app node -e "require('net').connect(3306,'banco').on('connect',()=>{console.log('conectou em banco:3306');process.exit(0)}).on('error',e=>{console.log('falhou: '+e.message);process.exit(1)})"

echo; echo "== 5. Banco sem porta publicada no host"
docker compose ps banco
(exec 3<>/dev/tcp/127.0.0.1/3306) 2>/dev/null && echo "porta 3306 ABERTA no host" || echo "porta 3306 fechada no host"

echo; echo "== 6. Banco sem saida para a internet (rede interna)"
docker compose exec -T banco bash -c '(exec 3<>/dev/tcp/1.1.1.1/443) 2>/dev/null && echo "saiu para a internet" || echo "sem saida para a internet"'

echo; echo "== 7. Limites e restricoes aplicados"
docker inspect "$(docker compose ps -aq app)" --format 'app:   memoria={{.HostConfig.Memory}} nanocpus={{.HostConfig.NanoCpus}} pids={{.HostConfig.PidsLimit}} read_only={{.HostConfig.ReadonlyRootfs}} cap_drop={{.HostConfig.CapDrop}} security_opt={{.HostConfig.SecurityOpt}}'
docker inspect "$(docker compose ps -aq banco)" --format 'banco: memoria={{.HostConfig.Memory}} nanocpus={{.HostConfig.NanoCpus}} security_opt={{.HostConfig.SecurityOpt}}'

echo; echo "== 8. Imagem: tamanho, conteudo e nenhuma senha nas camadas"
docker images hardening-app:1.0 --format '{{.Repository}}:{{.Tag}}  {{.Size}}'
docker run --rm hardening-app:1.0 ls -la /app
echo "ocorrencias de PASSWORD no historico da imagem: $(docker history --no-trunc hardening-app:1.0 | grep -ci password)"

echo; echo "== 9. .env fora do Git"
git check-ignore -v .env
git status --short
