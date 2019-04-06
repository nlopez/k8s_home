# k8s
A collection of Kubernetes objects for my home setup

## Notes
### kubeadm
```bash
kubeadm init --config kubeadm-init.yaml
```

### Weave
```bash
kubectl apply -f kubectl apply -f kube-system/weave-net*.yaml 
```

### Untaint master
```bash
kubectl taint nodes --all node-role.kubernetes.io/master-
```

### Wait for coredns/control plane running
```bash
kubectl get pod --all-namespaces -owide --watch
```

# metallb
```bash
kubectl apply -f metallb-system
```

### Sealed secrets
```bash
kubectl apply -f kube-system/kubeseal
kubectl apply -f /path/to/kubeseal-secret-key
```

### flux
```bash
kubectl apply -f default/flux
fluxctl identity # add key to GitHub with write access
# wait a bit for repo clone
fluxctl sync
```

## TODO
- [ ] Translate notes section into a bootstrap shell script

## Thanks
*  Lots of inspiration drawn from [nicolerenee/k8s-state](https://github.com/nicolerenee/k8s-state). Particularly: iscsi, [flux](https://github.com/weaveworks/flux), and [sealed secrets](https://github.com/bitnami-labs/sealed-secrets).
