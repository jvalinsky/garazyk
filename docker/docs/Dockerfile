# Dockerfile for VitePress documentation deployment
FROM nginx:alpine

# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/docs.conf

# Copy built documentation
COPY dist/ /var/www/docs/

# Expose port 80
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost/docs/ || exit 1

# Run nginx
CMD ["nginx", "-g", "daemon off;"]
