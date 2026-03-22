# k8s
A collection of Kubernetes objects for my home setup

## Notes
### kubeadm
```bash
kubeadm init --config kubeadm-init.conf --upload-certs --skip-phases=addon/kube-proxy
# run control plane join command printed by kubeadm on additional nodes
```

### Untaint master/control-plane
```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

### Approve CSRs
This is [necessary](https://github.com/kubernetes/kubeadm/issues/591#issuecomment-1257061416) because we're using `serverTLSBootstrap: true` in kubeadm.

```bash
for csr in $(k get csr --sort-by=.metadata.creationTimestamp -o name); do kubectl certificate approve $csr; done
```

### CNI: Cilium
```bash
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --version 1.18.1 --namespace kube-system --values apps-helm/cilium/values.yaml
cilium status --wait
kubectl apply --server-side -Rf apps-helm/cilium/manifests
```

### Wait for coredns/control plane running
```bash
kubectl get pod --all-namespaces -owide --watch
```

### ArgoCD
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install --create-namespace --namespace argocd --version 9.0.1 argocd argo/argo-cd --values apps-helm/argocd/values.yaml
argocd login --core
argocd admin initial-password -n argocd
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
export ARGOCD_SVC_IP="$(kubectl get svc -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[*].spec.clusterIP}')"
argocd login "$ARGOCD_SVC_IP" --insecure --username admin
argocd account update-password
```

### 1Password Connect
```bash
kubectl create namespace 1password --dry-run=client -o yaml | kubectl apply -f -
op read 'op://bamv726zv6zbcfke3cnbwjtnuu/asl5wh3w3nu2edr6pkj5ntylvu/1password-credentials.json' > 1password-credentials.json
kubectl create secret generic op-credentials -n 1password --from-file=1password-credentials.json --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic onepassword-token -n 1password --from-literal=token="$(op item get yju2wqlsz3uep7mvzivfrs3fvm --fields=token --reveal)" --dry-run=client -o yaml | kubectl apply -f -
argocd app sync onepassword-connect
```

### Bootstrap Argo AppSets
```bash
kubectl apply --server-side -Rf bootstrap
```

## Thanks
*  Lots of inspiration drawn from [nicolerenee/k8s-state](https://github.com/nicolerenee/k8s-state).
