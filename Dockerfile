FROM node:20-alpine
WORKDIR /app
COPY package.json server.js ./
ARG APP_VERSION=dev
ENV NODE_ENV=production APP_VERSION=$APP_VERSION
EXPOSE 3000
CMD ["node", "server.js"]
