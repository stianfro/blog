# Build stage - Hugo extended (required for SCSS)
FROM hugomods/hugo:exts AS builder

WORKDIR /src

# Copy source files
COPY . .

# Build the site
RUN hugo --gc --minify

# Production stage - nginx
FROM nginx:1.27-alpine

# Copy custom nginx config
COPY <<EOF /etc/nginx/conf.d/default.conf
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    # Gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript image/svg+xml;

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Serve files or fall back to index.html for SPA-like behavior
    location / {
        try_files \$uri \$uri/ \$uri.html /index.html;
    }

    # Health check endpoint
    location /healthz {
        return 200 'ok';
        add_header Content-Type text/plain;
    }
}
EOF

# Copy built assets from builder
COPY --from=builder /src/public /usr/share/nginx/html

# Run as non-root user
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html

USER nginx

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
