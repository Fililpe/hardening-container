# Imagem oficial do Node: versao LTS fixada e base Alpine (pequena)
FROM node:22-alpine

# Modo producao
ENV NODE_ENV=production

WORKDIR /app

# Copia so o codigo da aplicacao, ja com o dono certo
COPY --chown=node:node app/ ./

# A aplicacao nao tem dependencias, entao nao precisa de npm install.
# Se passar a ter: RUN npm ci --omit=dev

# Usuario sem privilegios que ja vem na imagem oficial
USER node

EXPOSE 3000

CMD ["node", "server.js"]
