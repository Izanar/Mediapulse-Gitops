# MetalLB — локальная установка и разработка

## Назначение

MetalLB提供т **LoadBalancer** для кластеров, где нет облачного балансировщика (в том числе для Kind). В этом проекте MetalLB закрепляет фиксированный IP `172.18.255.10` за сервисом Traefik, чтобы после пересоздания кластера адрес не менялся.

---

## Где хранятся файлы

| Компонент | Путь в репозитории | Авторство |
|-----------|-------------------|-----------|
| ArgoCD Application | `local/argocd/metallb-app.yaml` | **Своё** (написано для проекта) |
| Native манифест MetalLB | `local/manifests/metallb/metallb-native.yaml` | **Скачано** (официальный манифест MetalLB v0.14.5) |
| IPAddressPool + L2Advertisement | `local/manifests/metallb/ipaddresspool.yaml` | **Своё** (написано для проекта) |

---

## Почему MetalLB — 2 файла, а не целый репозиторий (в отличие от Traefik)

MetalLB поставляется как **один всевключающий манифест** (`metallb-native.yaml`, ~1900 строк), который содержит сразу всё: CRD, RBAC, ServiceAccount, Deployment контроллера, DaemonSet speaker. Этот файл скачан как есть — править его нет смысла, это upstream-артефакт.

Наша конфигурация MetalLB минимальна и живет в отдельном файле `ipaddresspool.yaml`:
- два `IPAddressPool` (фиксированный IP для Traefik + диапазон для остальных сервисов)
- один `L2Advertisement` (режим L2/ARP для Kind)

Traefik же — сложный Helm chart со множеством шаблонов, CRD, значений по умолчанию. Его проще скачать целиком и управлять через `values` в `traefik-app.yaml`, чем пытаться собрать вручную из отдельных YAML-файлов.

---

## Архитектура

1. **Установка через манифест, не через Helm** — `metallb-native.yaml` (официальный манифест MetalLB v0.14.5, **скачано**) содержит все CRD, RBAC, Deployment controller и speaker.
2. **IPAddressPool + L2Advertisement** — `ipaddresspool.yaml` (**своё**) содержит:
   - `traefik-pool` — `172.18.255.10-172.18.255.10` (один фиксированный IP для Traefik)
   - `services-pool` — `172.18.255.11-172.18.255.250` (остальные сервисы)
   - `L2Advertisement` — режим L2 (ARP), подходит для Kind/локальных кластеров без BGP.
3. **ArgoCD Application** — `metallb-app.yaml` (**своё**) с `sync-wave: -2` (устанавливается **до** Traefik, которая имеет `sync-wave: -1`).
4. **Аннотация сервиса Traefik** — `metallb.universe.tf/address-pool: traefik-pool` (**своё**, в `traefik-app.yaml`) связывает сервис с пулом.

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