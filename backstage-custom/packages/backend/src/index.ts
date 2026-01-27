import { createBackend } from '@backstage/backend-defaults';

const backend = createBackend();

// Auth - CRITICAL: OIDC provider for Cognito
backend.add(import('@backstage/plugin-auth-backend'));
backend.add(import('@backstage/plugin-auth-backend-module-oidc-provider'));

// Permission (must be before catalog)
backend.add(import('@backstage/plugin-permission-backend/alpha'));
backend.add(
  import('@backstage/plugin-permission-backend-module-allow-all-policy'),
);

// Catalog
backend.add(import('@backstage/plugin-catalog-backend/alpha'));

backend.start();
