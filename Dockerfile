FROM     node:8.14.0-slim as builder
WORKDIR  /app
COPY     . /app/
RUN      npm run dist &&\
         mkdir /pkg &&\
         mv dist node_modules package.json .nvmrc /pkg/


FROM     node:8.14.0-slim
RUN      useradd -m -U -d /app -s /bin/bash app
WORKDIR  /app
COPY     --chown=app:app --from=builder /pkg /app/
USER     app
CMD      ["node", "dist/index.js"]
