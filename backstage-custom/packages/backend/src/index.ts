/*
 * Hi!
 *
 * Note that this is an EXAMPLE Backstage backend. Please check the README.
 *
 * Happy hacking!
 */

import { createBackend } from '@backstage/backend-defaults';
import { coreServices, createBackendModule } from '@backstage/backend-plugin-api';
import { DEFAULT_NAMESPACE, stringifyEntityRef } from '@backstage/catalog-model';
import {
  authProvidersExtensionPoint,
  createOAuthProviderFactory,
} from '@backstage/plugin-auth-node';
import { oidcAuthenticator } from '@backstage/plugin-auth-backend-module-oidc-provider';

const backend = createBackend();

backend.add(import('@backstage/plugin-app-backend'));
backend.add(import('@backstage/plugin-proxy-backend'));

// scaffolder plugin
backend.add(import('@backstage/plugin-scaffolder-backend'));
backend.add(import('@backstage/plugin-scaffolder-backend-module-github'));
backend.add(
  import('@backstage/plugin-scaffolder-backend-module-notifications'),
);

// techdocs plugin
backend.add(import('@backstage/plugin-techdocs-backend'));

// auth plugin
backend.add(import('@backstage/plugin-auth-backend'));
// Custom OIDC provider registration with file-driven identity policy.
// - Avoids hardcoding email domains in code
// - Allows sign-in without requiring User entities in the catalog (Phase 0)
//
// Config source of truth:
// - `config/platform-params.yaml` (via Terraform ConfigMap `platform-params`)
// - exposed to Backstage as: `identity.allowedEmailDomains: ${AUTH_ALLOWED_EMAIL_DOMAINS}`
const customOidcSignIn = createBackendModule({
  pluginId: 'auth',
  moduleId: 'oidc-signin-policy',
  register(reg) {
    reg.registerInit({
      deps: { providers: authProvidersExtensionPoint, config: coreServices.rootConfig },
      async init({ providers, config }) {
        const allowedDomains = (
          config.getOptionalString('identity.allowedEmailDomains') ?? ''
        )
          .split(',')
          .map(s => s.trim().toLowerCase())
          .filter(Boolean);

        providers.registerProvider({
          providerId: 'oidc',
          factory: createOAuthProviderFactory({
            authenticator: oidcAuthenticator,
            async signInResolver({ profile }, ctx) {
              const email = profile.email?.toLowerCase();
              if (!email) {
                throw new Error('Login failed, user profile does not contain an email');
              }

              const [localPart, domain] = email.split('@');
              if (!localPart || !domain) {
                throw new Error(`Login failed, invalid email '${email}'`);
              }

              if (allowedDomains.length > 0 && !allowedDomains.includes(domain)) {
                throw new Error(
                  `Login failed, '${email}' does not belong to an allowed domain`,
                );
              }

              const safeName = localPart.replace(/[^a-z0-9]/gi, '-').toLowerCase();
              const userEntityRef = stringifyEntityRef({
                kind: 'User',
                namespace: DEFAULT_NAMESPACE,
                name: safeName,
              });

              return ctx.issueToken({
                claims: { sub: userEntityRef, ent: [userEntityRef] },
              });
            },
          }),
        });
      },
    });
  },
});
backend.add(customOidcSignIn);

// catalog plugin
backend.add(import('@backstage/plugin-catalog-backend'));
backend.add(
  import('@backstage/plugin-catalog-backend-module-scaffolder-entity-model'),
);

// See https://backstage.io/docs/features/software-catalog/configuration#subscribing-to-catalog-errors
backend.add(import('@backstage/plugin-catalog-backend-module-logs'));

// permission plugin
backend.add(import('@backstage/plugin-permission-backend'));
// See https://backstage.io/docs/permissions/getting-started for how to create your own permission policy
backend.add(
  import('@backstage/plugin-permission-backend-module-allow-all-policy'),
);

// search plugin
backend.add(import('@backstage/plugin-search-backend'));

// search engine
// See https://backstage.io/docs/features/search/search-engines
backend.add(import('@backstage/plugin-search-backend-module-pg'));

// search collators
backend.add(import('@backstage/plugin-search-backend-module-catalog'));
backend.add(import('@backstage/plugin-search-backend-module-techdocs'));

// kubernetes plugin
backend.add(import('@backstage/plugin-kubernetes-backend'));

// notifications and signals plugins
backend.add(import('@backstage/plugin-notifications-backend'));
backend.add(import('@backstage/plugin-signals-backend'));

backend.start();
