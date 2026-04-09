global:
  domain: localhost:8080

dex:
  enabled: true

configs:
  params:
    server.insecure: "true"
  cm:
    url: http://localhost:8080
    dex.config: |
      connectors:
        - type: oidc
          id: google
          name: Google
          config:
            issuer: https://accounts.google.com
            clientID: ${GOOGLE_OIDC_CLIENT_ID}
            clientSecret: ${GOOGLE_OIDC_CLIENT_SECRET}
            redirectURI: http://localhost:8080/api/dex/callback
  rbac:
    policy.default: role:admin

server:
  service:
    type: ClusterIP
