# k8s
A collection of Kubernetes objects for my home setup

## Notes
### Helm
[RBAC Helm install](https://github.com/kubernetes/helm/blob/master/docs/rbac.md)

```bash
kubectl apply -f kube-system/tiller
helm init --service-account tiller
```

### cert-manager
`cert-manager` is installed via its [Helm chart](https://github.com/kubernetes/charts/tree/master/stable/cert-manager)

```
helm install \
    --name cert-manager \
    --namespace kube-system \
    stable/cert-manager
```