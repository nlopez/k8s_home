# k8s
A collection of Kubernetes objects for my home setup

## Notes
### kubeadm
```bash
kubeadm init --pod-network-cidr 10.11.0.0/16
```

### kuberouter
```bash
kubectl apply -f kubeadm-kuberouter-all-features-dsr.yaml 
kubectl delete daemonset kube-proxy -n kube-system 
```

On each node:

```bash
docker run --privileged --net=host gcr.io/google_containers/kube-proxy-amd64:v1.11.2 kube-proxy --cleanup
```

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