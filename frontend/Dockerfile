FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html
COPY styles.css /usr/share/nginx/html/styles.css
COPY jomelai.css /usr/share/nginx/html/jomelai.css
COPY jomelai.js /usr/share/nginx/html/jomelai.js
COPY app.js /usr/share/nginx/html/app.js
COPY tech-routes.js /usr/share/nginx/html/tech-routes.js
COPY favicon.ico /usr/share/nginx/html/favicon.ico
EXPOSE 80
