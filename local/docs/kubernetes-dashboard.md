# Kubernetes Dashboard — установка через ArgoCD

## Назначение

Кubernetes Dashboard — веб-интерфейс для управления кластером Kubernetes. Позволяет просматривать поды, сервисы, Deployments, логи, события и другие ресурсы через браузер.

В этом проекте Dashboard устанавливается **через ArgoCD Application** (App-of-Apps pattern) и доступен по адресу `https://k8s.local:8443/` (через Traefik + port-forward из Windows).

---

## Где хранятся файлы

| Компонент | Путь в репозитории | Авторство | Назначение |
|-----------|-------------------|-----------|------------|
| ArgoCD Application | `local/argocd/kubernetes-dashboard-app.yaml` | **Своё** | Описывает Application для ArgoCD: откуда брать манифесты, в какой namespace устанавливать, политика синхронизации |
| RBAC (ServiceAccount + ClusterRoleBinding) | `local/manifests/kubernetes-dashboard/rbac.yaml` | **Своё** | Создаёт пользователя `admin-user` с правами `cluster-admin` для входа в Dashboard |
| Официальный манифест Dashboard | `local/manifests/kubernetes-dashboard/recommended.yaml` | **Скачано** | Официальный релиз kubernetes-dashboard v2.7.0 (все Deployment, Service, CRD, RBAC upstream) |
| IngressRoute (Traefik) | `Mediapulse-Infra/local/routes/k8s-dashboard-ingress.yaml` | **Своё** | Маршрутизация трафика Traefik → k8s.local → сервис Dashboard |

---

## Архитектура

1. **ArgoCD Application** — `kubernetes-dashboard-app.yaml` с `syncOptions: CreateNamespace=true`. ArgoCD автоматически создаёт namespace `kubernetes-dashboard` и применяет все манифесты из папки `local/manifests/kubernetes-dashboard/`.
2. **Официальный манифест** — `recommended.yaml` (**скачано**, kubernetes-dashboard v2.7.0) содержит все ресурсы upstream: Deployment Dashboard, Service, Scraper, CRD и т.д. Править не нужно.
3. **RBAC** — `rbac.yaml` (**своё**) создаёт ServiceAccount `admin-user` и привязывает его к `ClusterRole cluster-admin`, чтобы можно было войти в Dashboard с полными правами.
4. **IngressRoute** — `k8s-dashboard-ingress.yaml` (**своё**, в `Mediapulse-Infra`) направляет трафик по хосту `k8s.local` на сервис `kubernetes-dashboard:443` с `serversTransport` (отключение проверки сертификатов).

Порядок установки (App-of-Apps, через `root.yaml`):

```text
sync-wave: -2   → metallb        (сначала балансировщик)
sync-wave: -1   → traefik        (потом Ingress Controller)
sync-wave:  0   → kubernetes-dashboard (Дашборд после Traefik)
                → backend, databases
```

---

## Как применяется

Dashboard устанавливается автоматически через ArgoCD App-of-Apps (`root.yaml`). Применение вручную:

```bash
kubectl apply -f local/argocd/kubernetes-dashboard-app.yaml
```

Проверить синхронизацию:

```bash
kubectl -n argocd get application kubernetes-dashboard
kubectl -n argocd wait --for=condition=Synced application/kubernetes-dashboard --timeout=120s
```

Проверить поды и namespace:

```bash
kubectl get pods -n kubernetes-dashboard
kubectl get svc -n kubernetes-dashboard
kubectl get serviceaccount -n kubernetes-dashboard admin-user
```

---

## Как получить токен для входа

Dashboard не использует пароль — вход через **Bearer Token** ServiceAccount `admin-user`.

Создать токен:

```bash
kubectl -n kubernetes-dashboard create token admin-user
```

Токен действителен ограниченное время (по умолчанию 24 часа). После истечения создать новый.

Также токен выводит скрипт `dev-dashboard.sh` в конце работы (секция "K8s Dashboard токен").

---

## Как открыть Dashboard

### Изнутри кластера (kubectl proxy)

```bash
kubectl proxy --port=8001
# затем открыть:
# http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

### Через Traefik + port-forward (рекомендуется для Windows)

1. Убедиться, что Traefik запущен и имеет `EXTERNAL-IP: 172.18.255.10` (MetalLB).
2. Запустить port-forward:

```bash
kubectl port-forward --address 0.0.0.0 service/traefik 8443:443 -n traefik
# или: cd ../Mediapulse-Infra/local && make traefik-port-forward
```

3. Добавить в `C:\Windows\System32\drivers\etc\hosts` (от имени администратора):

```
<WSL2_IP>  argocd.local traefik.local k8s.local mediapulse.local
```

4. Открыть в браузере Windows:

```
https://k8s.local:8443/
```

5. На экране входа выбрать **Token** и вставить токен из шага "Как получить токен".

---

## Связь с другими компонентами

- **Traefik** — Ingress Controller, принимает трафик на `k8s.local` и проксирует в сервис Dashboard.
- **MetalLB** — предоставляет фиксированный IP `172.18.255.10` для сервиса Traefik.
- **dev-dashboard.sh** — применяет IngressRoute для `k8s.local`, ждёт создания namespace Dashboard, выводит токен и инструкции.

---

## Ограничения

- Kind-сеть изолирована: Windows **не может напрямую** дойти до MetalLB IP. Доступ только через `kubectl port-forward` + WSL2 IP в hosts.
- Токен ServiceAccount истекает — при истечении нужно создать новый (`create token admin-user`).
- self-signed сертификаты Traefik — браузер покажет предупреждение, нужно подтвердить исключение безопасности.