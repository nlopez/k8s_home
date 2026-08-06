# k8s

<!-- hy-mt2-i18n:start -->
[English](./README.md) | [中文](./README_zh-CN.md) | **日本語** | [Español](./README_es.md)
<!-- hy-mt2-i18n:end -->

私の個人インフラ向け Kubernetes gitops

## 備考
### kubeadm

```bash
sudo kubeadm init --config kubeadm-init.conf --upload-certs
```

追加のノードでコントロールプレーンのジョインコマンドを実行します。

### master/control-plane のタインを解除する
```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane=
```

### CSRの承認
kubeadmで`serverTLSBootstrap: true`を使用しているため、これは[必須](https://github.com/kubernetes/kubeadm/issues/591#issuecomment-1257061416)なのです。

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

### corednsおよびコントロールプレーンの起動を待機する
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

### Argo AppSetの起動
```bash
kubectl apply --server-side -Rf bootstrap
```

### Renovate

ワーキングツリー上でローカルにRenovateを実行する（GitHubトークンは不要）：

```bash
docker run --rm \
  -v $(pwd):/usr/src/app \
  -e RENOVATE_PLATFORM=local \
  -e LOG_LEVEL=debug \
  ghcr.io/renovatebot/renovate \
  --dry-run=full
```

GitHub上で実際のPRを開くには、`RENOVATE_TOKEN` を `repo` スコープを持つGitHub PATに設定し、`--dry-run=full` を削除してください。

```bash
RENOVATE_TOKEN=<github-pat> docker run --rm \
  -e RENOVATE_TOKEN \
  -e LOG_LEVEL=debug \
  ghcr.io/renovatebot/renovate \
  nlopez/k8s_home
```

## お礼
* [nicolerenee/k8s-state](https://github.com/nicolerenee/k8s-state) から多くのインスピレーションを得ました。
