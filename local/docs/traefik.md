# Traefik — локальная установка и разработка

## Назначение

Traefik работает как **Ingress Controller** и **обратный прокси** для локального Kind-кластера. Принимает внешний трафик через LoadBalancer (MetalLB) на фиксированный IP `172.18.255.10` и маршрутизирует запросы к сервисам (ArgoCD, K8s Dashboard, backend, и т.д.).

---

## Где хранятся файлы

| Компонент | Путь в репозитории |
|-----------|-------------------|
| ArgoCD Application | `local/argocd/traefik-app.yaml` |
| Локальный Helm chart | `local/manifests/traefik/` |
| CRD Traefik | `local/manifests/traefik/crds/` |
| Шаблоны chart'а | `local/manifests/traefik/templates/` |
| Значения по умолчанию | `local/manifests/traefik/values.yaml` |

---

## Архитектура

1. **Локальный chart** — весь Traefik chart 42.0.0 скачан и лежит в `local/manifests/traefik/`. Внешний Helm-репозиторий не нужен.
2. **ArgoCD Application** — `traefik-app.yaml` ссылается на локальный chart через `path: local/manifests/traefik`.
3. **sync-wave: -1** — Traefik устанавливается после MetalLB (которая имеет `sync-wave: -2`).
4. **LoadBalancer IP** — зафиксирован `loadBalancerIP: 172.18.255.10` в значениях chart'а.
5. **Replicas** — 4 под Traefik для отказоустойчивости.
6. **Тип развёртывания** — `Deployment` (не DaemonSet), без `hostPort`. Внешний трафик идёт через MetalLB.
7. **Ports**:
   - `web` → 8000 (exposed 80)
   - `websecure` → 8443 (exposed 443)

---

## Как применяется

Traefik устанавливается автоматически через ArgoCD App-of-Apps (`root.yaml`). Применяется вручную:

```bash
kubectl apply -f local/argocd/traefik-app.yaml
```

Проверить синхронизацию:

```bash
kubectl -n argocd get application traefik
kubectl -n argocd wait --for=condition=Synced application/traefik --timeout=120s
```

Проверить поды и сервис:

```bash
kubectl get pods -n traefik
kubectl get svc -n traefik
```

Ожидается `EXTERNAL-IP: 172.18.255.10` (присваивается MetalLB).

---

## Доступ из Windows

Kind-сеть изолирована, Windows не может напрямую дойти до MetalLB IP. Рабочий путь:

1. **Port-forward** (запускать в отдельном терминале):

```bash
kubectl port-forward --address 0.0.0.0 service/traefik 8443:443 -n traefik
```

Или через Makefile:

```bash
cd ../Mediapulse-Infra/local
make traefik-port-forward
```

2. **Windows hosts** — добавить строку с **WSL2 IP** (не MetalLB IP):

```
<WSL2_IP>  argocd.local traefik.local k8s.local mediapulse.local
```

Актуальный WSL2 IP можно получить из вывода `dev-dashboard.sh` или командой:

```bash
ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'
```

3. **Открыть в браузере Windows**:

```
https://argocd.local:8443/          # ArgoCD
https://traefik.local:8443/dashboard/  # Traefik Dashboard
https://k8s.local:8443/          # Kubernetes Dashboard
```

---

## Traefik Dashboard

Для доступа к собственному веб-интерфейсу Traefik используется `IngressRoute`:

```yaml
# local/manifests/traefik/templates/ingressroute.yaml (или отдельный файл в routes/)
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
  namespace: traefik
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`traefik.local`) && PathPrefix(`/dashboard/`)
      kind: Rule
      services:
        - name: api@internal
          kind: TraefikService
```

Файл `routes/traefik-ingress.yaml` в `Mediapulse-Infra/local/routes/` применяется скриптом `dev-dashboard.sh`.

---

## При изменении chart'а

Если нужно обновить версию Traefik chart'а:

1. Скачать новый chart в `local/manifests/traefik/`
2. Зафиксировать нужные значения в `traefik-app.yaml` (replicas, loadBalancerIP, ports)
3. Закоммитить и запушить — ArgoCD подхватит изменения автоматически

---

## Проверка состояния

```bash
# Статус Application в ArgoCD
kubectl -n argocd describe application traefik

# Поды Traefik
kubectl get pods -n traefik -w

# Сервис Traefik (EXTERNAL-IP должен быть 172.18.255.10)
kubectl get svc -n traefik traefik

# Логи Traefik
kubectl logs -n traefik deploy/traefik
```

---

## Ограничения

- Доступ к Traefik из Windows возможен только через `kubectl port-forward` + WSL2 IP в hosts.
- Прямой доступ к MetalLB IP `172.18.255.10` из Windows не работает (Kind-сеть изолирована).