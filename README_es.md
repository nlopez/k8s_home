# k8s

<!-- hy-mt2-i18n:start -->
[English](./README.md) | [中文](./README_zh-CN.md) | [日本語](./README_ja.md) | **Español**
<!-- hy-mt2-i18n:end -->

GitOps para Kubernetes en mi infraestructura personal

## Notas
### kubeadm

```bash
sudo kubeadm init --config kubeadm-init.conf --upload-certs
```

Ejecute la orden de unión al plano de control en los nodos adicionales.

### Marcar como no aptas las nodos master/control-plane
```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

### Aprobar solicitudes de certificado
Esto es [necesario](https://github.com/kubernetes/kubeadm/issues/591#issuecomment-1257061416) porque estamos utilizando `serverTLSBootstrap: true` en kubeadm.

```bash
for csr in $(kubectl get csr --sort-by=.metadata.creationTimestamp -o name); do kubectl certificate approve $csr; done
```

### CNI: Cilium
```bash
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --version 1.19.2 --namespace kube-system --values apps-helm/cilium/values.yaml
cilium status --wait
kubectl apply --server-side -Rf apps-helm/cilium/manifests
```

### Esperar a que coredns y el plano de control estén en ejecución
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
op read 'op://bamv726zv6zbcfke3cnbwjtnuu/lkbaozihk6xqhrtlcq6vycu2ua/1password-credentials.json' --no-newline > 1password-credentials.json
kubectl create secret generic op-credentials -n 1password --from-file=1password-credentials.json --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic onepassword-token -n 1password --from-literal=token="$(op read op://bamv726zv6zbcfke3cnbwjtnuu/lshy7xejhopza2xq6qpjqlcw5y/credential --no-newline)" --dry-run=client -o yaml | kubectl apply -f -
```

### Inicializar Argo AppSets
```bash
kubectl apply --server-side -Rf bootstrap
```

### Renovate

Ejecutar renovate localmente sobre el árbol de trabajo (no se requiere token de GitHub):

```bash
docker run --rm \
  -v $(pwd):/usr/src/app \
  -e RENOVATE_PLATFORM=local \
  -e LOG_LEVEL=debug \
  ghcr.io/renovatebot/renovate \
  --dry-run=full
```

Para abrir las PR reales en GitHub, establezca `RENOVATE_TOKEN` como un PAT de GitHub con alcance `repo` y elimine `--dry-run=full`:

```bash
RENOVATE_TOKEN=<github-pat> docker run --rm \
  -e RENOVATE_TOKEN \
  -e LOG_LEVEL=debug \
  ghcr.io/renovatebot/renovate \
  nlopez/k8s_home
```

## Agradecimientos
* Gran parte de la inspiración proviene de [nicolerenee/k8s-state](https://github.com/nicolerenee/k8s-state).
