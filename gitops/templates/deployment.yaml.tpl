apiVersion: apps/v1
kind: Deployment
metadata:
  name: wiz-app
  namespace: wiz-app
  labels:
    app: wiz-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wiz-app
  template:
    metadata:
      labels:
        app: wiz-app
    spec:
      serviceAccountName: wiz-app
      containers:
        - name: app
          image: ${IMAGE}
          imagePullPolicy: Always
          ports:
            - containerPort: 3000
          env:
            - name: MONGO_URI
              valueFrom:
                secretKeyRef:
                  name: app-secrets
                  key: MONGO_URI
