#!/bin/sh
set -e

# Extract Backstage bundle if not already extracted
if [ ! -f "/app/packages/backend/dist/index.cjs.js" ]; then
    echo "Extracting Backstage bundle..."
    cd /app
    tar -xzf packages/backend/dist/bundle.tar.gz
    echo "Bundle extracted successfully"
fi

# Execute the command passed to the container
exec "$@"
