## Live Demo

The `attacks/` directory contains executable scripts for each step
of the attack chain. Run against the deployed lab only.
```bash
# Full chain — internet to cluster-admin in ~5 minutes
MONGO_IP=x.x.x.x BUCKET_NAME=your-bucket just attack
```

> These scripts target intentional misconfigurations in this lab only.
> Do not run against systems you do not own.
