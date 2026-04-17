FROM node:20-alpine

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY index.js ./
RUN echo "Henrik Frech hello" > /app/wizexercise.txt

EXPOSE 3000
CMD ["npm", "start"]
