# Backend image: Node.js 24 LTS (alpine = chhota Linux)
FROM node:24-alpine

WORKDIR /app

# Pehle sirf package files copy karo -> Docker layer cache use hoga
COPY package*.json ./
RUN npm install --omit=dev

# Ab asal code copy karo
COPY app.js ./

# Root ke bajaye kam ikhtiyar wale user se chalao (security best practice)
USER node

EXPOSE 3000
CMD ["node", "app.js"]
