global:
  domain: ${ARGOCD_HOSTNAME}

configs:
  params:
    server:
      insecure: true
  cm:
    url: https://${ARGOCD_HOSTNAME}
    dex.config: |
      connectors:
        - type: oidc
          id: google
          name: Google
          config:
            issuer: https://accounts.google.com
            clientID: ${GOOGLE_OIDC_CLIENT_ID}
            clientSecret: ${GOOGLE_OIDC_CLIENT_SECRET}
            hostedDomains:
              - ${GOOGLE_WORKSPACE_DOMAIN}

  rbac:
    policy.default: role:readonly
    policy.csv: |
      g, ${ARGOCD_ADMIN_GROUP}, role:admin

server:
  service:
    type: ClusterIP
