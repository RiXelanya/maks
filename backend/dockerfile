FROM node:20-alpine
# ENV NODE_ENV production
ENV PORT 3000
WORKDir /app
COPY package*.json ./
RUN npm install 
COPY . .
EXPOSE 3000
CMD ["npm", "start"]