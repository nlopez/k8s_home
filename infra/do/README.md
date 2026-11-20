# infra/do

OpenTofu/Terraform for the DigitalOcean bootstrap cluster (VPC + DOKS).

```bash
export DIGITALOCEAN_TOKEN=$(op read 'op://<vault>/<item>/credential')
tofu init
tofu plan
tofu apply
doctl kubernetes cluster kubeconfig save bootstrap-do
```

This was written without being run: `tofu validate` / `tofu plan` first, and confirm DO
accepts the custom `cluster_subnet` / `service_subnet` for your region.

Next: follow [`clusters/do/README.md`](../../clusters/do/README.md).
