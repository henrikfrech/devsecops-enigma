apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: wiz-app
type: Opaque
stringData:
  MONGO_URI: mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${MONGO_PRIVATE_IP}:27017/${MONGO_DB}?authSource=admin
