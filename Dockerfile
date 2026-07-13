# Build stage - Hugo extended (required for SCSS)
FROM hugomods/hugo:exts AS builder

WORKDIR /src

# Build argument for environment-specific baseURL
ARG BASE_URL=https://blog.froystein.jp/

# Copy source files
COPY . .

# Build the site with the specified baseURL
RUN hugo --gc --minify --baseURL=${BASE_URL}

# Production stage - nginx
FROM nginx:1.27-alpine

# Copy custom nginx config
COPY <<EOF /etc/nginx/conf.d/default.conf
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    # Hugo places the only language under /en/. Use an HTTP redirect instead
    # of serving Hugo's generated meta-refresh page at the root.
    location = / {
        return 301 /en/;
    }

    # Gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript image/svg+xml;

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    error_page 404 /en/404.html;

    location = /en/404.html {
        internal;
    }

    # This is a static site. Missing files must remain real 404 responses so
    # crawlers do not treat arbitrary URLs as duplicate homepages.
    location / {
        try_files \$uri \$uri/ \$uri.html =404;
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
