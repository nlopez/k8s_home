# k8s
A collection of Kubernetes objects for my home setup

## Notes
### kubeadm
```bash
kubeadm init --pod-network-cidr 10.11.0.0/16
```

### kuberouter
```bash
kubectl apply -f kube-system/kubeadm-kuberouter-all-features-dsr.yaml 
kubectl delete daemonset kube-proxy -n kube-system 
```

On each node:

```bash
docker run --privileged --net=host gcr.io/google_containers/kube-proxy-amd64:v1.13.1 kube-proxy --cleanup
```

### sealed-secrets
kubectl apply/replace master key from backup

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
