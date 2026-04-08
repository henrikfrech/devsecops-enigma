---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wiz-app
  namespace: wiz-app
  annotations:
    kubernetes.io/ingress.class: "gce"
    kubernetes.io/ingress.allow-http: "true"
spec:
  defaultBackend:
    service:
      name: wiz-app
      port:
        number: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: "gce"
    kubernetes.io/ingress.allow-http: "true"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
spec:
  defaultBackend:
    service:
      name: argocd-server
      port:
        number: 80
