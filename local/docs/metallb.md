# MetalLB — локальная установка и разработка

## Назначение

MetalLB提供т **LoadBalancer** для кластеров, где нет облачного балансировщика (в том числе для Kind). В этом проекте MetalLB закрепляет фиксированный IP `172.18.255.10` за сервисом Traefik, чтобы после пересоздания кластера адрес не менялся.

---

## Где хранятся файлы

| Компонент | Путь в репозитории |
|-----------|-------------------|
| ArgoCD Application | `local/argocd/metallb-app.yaml` |
| Native манифест MetalLB | `local/manifests/metallb/metallb-native.yaml` |
| IPAddressPool | `local/manifests/metallb/ipaddresspool.yaml` |

---

## Архитектура

1. **Установка через манифест, не через Helm** — `metallb-native.yaml` (официальный манифест MetalLB v0.14.5, ~1900 строк) содержит все CRD, RBAC, Deployments controller и speaker.
2. **ArgoCD Application** — `metallb-app.yaml` с `sync-wave: -2` (устанавливается **до** Traefik, которая имеет `sync-wave: -1`).
3. **IPAddressPool** — два пула:
   - `traefik-pool` — `172.18.255.10-172.18.255.10` (один фиксированный IP для Traefik)
   - `services-pool` — `172.18.255.11-172.18.255.250` (остальные сервисы)
4. **L2Advertisement** — режим L2 (ARP), подходит для Kind/локальных кластеров без BGP.
5. **Аннотация сервиса Traefik** — `metallb.universe.tf/address-pool: traefik-pool` связывает сервис с пулом.

---

## Как применяется

MetalLB устанавливается автоматически через ArgoCD App-of-Apps (`root.yaml`). Применяется вручную:

```bash
kubectl apply -f local/argocd/metallb-app.yaml
```

Проверить синхронизацию:

```bash
kubectl -n argocd get application metallb
kubectl -n argocd wait --for=condition=Synced application/metallb --timeout=120s
```

Проверить поды и namespace:

```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
```

---

## Связь с Traefik

Сервис Traefik в `traefik-app.yaml` имеет аннотацию:

```yaml
service:
  annotations:
    metallb.universe.tf/address-pool: traefik-pool
  spec:
    loadBalancerIP: 172.18.255.10
```

После установки MetalLB и Traefik сервис `traefik` в namespace `traefik` получит `EXTERNAL-IP: 172.18.255.10`.

---

## Порядок установки (App-of-Apps)

```text
sync-wave: -2   → metallb        (сначала балансировщик)
sync-wave: -1   → traefik        (потом Ingress Controller)
                → backend, databases (после Traefik)
```

Благодаря `sync-wave` ArgoCD устанавливает компоненты в правильной последовательности.

---

## Проверка состояния

```bash
# Статус Application в ArgoCD
kubectl -n argocd describe application metallb

# Поды MetalLB
kubectl get pods -n metallb-system

# IPAddressPools
kubectl get ipaddresspool -n metallb-system

# L2Advertisement
kubectl get l2advertisement -n metallb-system

# Сервис Traefik с внешним IP
kubectl get svc -n traefik traefik
```

---

## Ограничения

- Kind-сеть изолирована: Windows **не может напрямую** дойти до MetalLB IP `172.18.255.10`. Для доступа из Windows используется `kubectl port-forward` + WSL2 IP в hosts (см. `local/docs/traefik.md`).
- L2-режим работает только внутри одной L2-сети (Kind удовлетворяет этому условию).