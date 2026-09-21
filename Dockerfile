# Evently PWA preview (Vinext). Target по SPEC §5: FastAPI + Vite + Postgres + nginx —
# api/db/nginx докрутятся отдельными сервисами в compose.yaml.
FROM node:22-slim
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build
EXPOSE 5173
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://localhost:5173/').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0", "--port", "5173"]
