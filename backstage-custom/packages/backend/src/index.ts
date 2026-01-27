import { createBackend } from '@backstage/backend-defaults';

const backend = createBackend();

// Auth - CRITICAL: OIDC provider for Cognito
backend.add(import('@backstage/plugin-auth-backend'));
backend.add(import('@backstage/plugin-auth-backend-module-oidc-provider'));

// Catalog - with all required dependencies
backend.add(import('@backstage/plugin-catalog-backend'));

// Permission
backend.add(import('@backstage/plugin-permission-backend'));
backend.add(
  import('@backstage/plugin-permission-backend-module-allow-all-policy'),
);

backend.start();
