FROM node:18-alpine
WORKDIR /usr/src/app
COPY app/package*.json ./
RUN npm install --only=production
COPY app/ .
EXPOSE 3000
CMD ["node", "index.js"]