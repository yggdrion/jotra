# The lobby: no dependencies beyond Bun itself.
FROM oven/bun:1.4.4-alpine
WORKDIR /app
COPY package.json ./
COPY src ./src
USER bun
EXPOSE 8080
CMD ["bun", "src/server.ts"]
