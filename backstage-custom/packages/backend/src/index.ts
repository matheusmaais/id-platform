/*
 * Backstage Backend with OIDC Support
 * Based on official Backstage template
 */

import { createBackend } from '@backstage/backend-defaults';

const backend = createBackend();

// Proxy backend
backend.add(import('@backstage/plugin-proxy-backend'));

// Auth plugin with OIDC provider (replaces guest provider)
backend.add(import('@backstage/plugin-auth-backend'));
backend.add(import('@backstage/plugin-auth-backend-module-oidc-provider'));

// Catalog plugin with scaffolder entity model
backend.add(import('@backstage/plugin-catalog-backend'));
backend.add(
  import('@backstage/plugin-catalog-backend-module-scaffolder-entity-model'),
);

// Permission plugin
backend.add(import('@backstage/plugin-permission-backend'));
backend.add(
  import('@backstage/plugin-permission-backend-module-allow-all-policy'),
);

backend.start();
