# k8s
A collection of Kubernetes objects for my home setup

## Notes
### kubeadm
```bash
kubeadm init --config kubeadm-init.conf --upload-certs
# run control plane join command printed by kubeadm on additional masters
```

### CNI: Cilium
```bash
cilium install --helm-values=cilium-values.yaml
```

### Untaint master/control-plane
```bash
kubectl taint nodes --all node-role.kubernetes.io/master-
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

### Wait for coredns/control plane running
```bash
kubectl get pod --all-namespaces -owide --watch
```

# metallb
```bash
kubectl apply -f 00-namespace.yaml -f metallb-system
```

### Sealed secrets
```bash
kubectl apply -f /path/to/kubeseal-secret-key
kubectl apply -f kube-system/kubeseal
```

### flux
```bash
kubectl apply -f flux
fluxctl --k8s-fwd-ns flux identity  # add key to GitHub with write access
# wait a bit for repo clone
fluxctl --k8s-fwd-ns flux sync
```

#### Un/ignoring resources with flux
```bash
# Ignore
kubectl annotate <resource> "flux.weave.works/ignore"

# Unignore
kubectl annotate <resource> "flux.weave.works/ignore"-

# Ignore all in namespace
# (doesn't seem like there is --all-namespaces for this.)
kubectl -n default annotate all --all "flux.weave.works/ignore"

# Unignore all in namespace
kubectl -n default annotate all --all "flux.weave.works/ignore"-
```
See https://github.com/fluxcd/flux/issues/1211 for more

## TODO
- [ ] Translate notes section into a bootstrap shell script
- [ ] Update bootstrap for Cilium CNI
- [ ] Cilium [kubeproxy-free](https://docs.cilium.io/en/stable/gettingstarted/kubeproxy-free/) setup to preserve source IPs coming in via metallb ([more on DSR](https://cilium.io/blog/2020/02/18/cilium-17#kubeproxy-removal))
- [ ] Use Flux/HelmRelease CRDs better

## Thanks
*  Lots of inspiration drawn from [nicolerenee/k8s-state](https://github.com/nicolerenee/k8s-state). Particularly: iscsi, [flux](https://github.com/weaveworks/flux), and [sealed secrets](https://github.com/bitnami-labs/sealed-secrets).
