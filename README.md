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

### CNI: Cilium
```bash
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --version 1.18.1 --namespace kube-system --values apps-helm/cilium/values.yaml
cilium status --wait
kubectl apply -Rf apps-helm/cilium/manifests
```

### Wait for coredns/control plane running
```bash
kubectl get pod --all-namespaces -owide --watch
```

### ArgoCD
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
argocd login --core
argocd admin initial-password -n argocd
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
export ARGOCD_SVC_IP="$(kubectl get svc -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[*].spec.clusterIP}')"
argocd login "$ARGOCD_SVC_IP" --insecure --username admin
argocd account update-password
```

### 1Password Connect
```bash
helm repo add 1password https://1password.github.io/connect-helm-charts/
helm install --create-namespace --namespace 1password connect 1password/connect --set-file connect.credentials=1password-credentials.json --set operator.create=true --set operator.token.value=$(op item get yju2wqlsz3uep7mvzivfrs3fvm --fields=token --reveal)
```

## Thanks
*  Lots of inspiration drawn from [nicolerenee/k8s-state](https://github.com/nicolerenee/k8s-state). Particularly: iscsi, [flux](https://github.com/weaveworks/flux), and [sealed secrets](https://github.com/bitnami-labs/sealed-secrets).
