# Архитектура проекта Mediapulse — обзор компонентов и авторства

## Общая схема

```text
sync-wave: -2   → metallb         (LoadBalancer для Kind)
sync-wave: -1   → traefik         (Ingress Controller + TLS)
sync-wave:  0   → kubernetes-dashboard (Веб-UI кластера)
                → backend         (API + Worker + Миграции)
                → databases       (PostgreSQL + Redis)
```

Все компоненты управляются через **ArgoCD App-of-Apps** (`local/argocd/root.yaml`).

---

## Таблица авторства (Своё vs Скачано)

| Компонент | Файл/путь | Авторство | Откуда взято | Для чего |
|-----------|-----------|-----------|--------------|----------|
| ArgoCD root-app | `local/argocd/root.yaml` | **Своё** | — | Точка входа App-of-Apps |
| ArgoCD metallb-app | `local/argocd/metallb-app.yaml` | **Своё** | — | ArgoCD Application для MetalLB |
| MetalLB манифест | `local/manifests/metallb/metallb-native.yaml` | **Скачано** | https://github.com/metallb/metallb (v0.14.5) | Установка MetalLB (CRD, RBAC, controller, speaker) |
| IPAddressPool + L2Ad | `local/manifests/metallb/ipaddresspool.yaml` | **Своё** | — | Пулы IP и режим L2 для Kind |
| ArgoCD traefik-app | `local/argocd/traefik-app.yaml` | **Своё** | — | ArgoCD Application для Traefik + свои values |
| Traefik chart | `local/manifests/traefik/` | **Скачано** | https://github.com/traefik/traefik-helm-chart (v42.0.0) | Весь Helm chart Traefik (шаблоны, CRD, values по умолчанию) |
| ArgoCD k8s-dashboard-app | `local/argocd/kubernetes-dashboard-app.yaml` | **Своё** | — | ArgoCD Application для K8s Dashboard |
| K8s Dashboard RBAC | `local/manifests/kubernetes-dashboard/rbac.yaml` | **Своё** | — | ServiceAccount admin-user + cluster-admin |
| K8s Dashboard манифест | `local/manifests/kubernetes-dashboard/recommended.yaml` | **Скачано** | https://github.com/kubernetes/dashboard (v2.7.0) | Официальный релиз Dashboard |
| Backend chart | `local/charts/backend/` | **Своё** | — | Собственный Helm chart бэкенда |
| Databases chart | `local/charts/databases/` | **Своё** | — | Собственный Helm chart БД |
| Makefile | `Mediapulse-Infra/local/Makefile` | **Своё** | — | Автоматизация кластера (Kind, Helm, ArgoCD) |
| dev-dashboard.sh | `Mediapulse-Infra/local/dev-dashboard.sh` | **Своё** | — | Настройка Ingress-маршрутов и вывод учетных данных |
| Ingress-маршруты | `Mediapulse-Infra/local/routes/*.yaml` | **Своё** | — | Traefik IngressRoute для ArgoCD, Dashboard, Traefik UI, backend |

---

## Почему у разных компонентов разный подход к доставке манифестов

### MetalLB — 2 файла (не весь репозиторий)
MetalLB поставляется как **один всевключающий YAML-манифест** (~1900 строк), который содержит всё необходимое: CRD, RBAC, Deployment контроллера, DaemonSet speaker. Скачиваем его как есть в `metallb-native.yaml`. Наша конфигурация (пулы IP, L2Advertisement) минимальна — живёт в отдельном `ipaddresspool.yaml`.

### Traefik — весь Helm chart
Traefik — сложный Ingress Controller с огромным количеством шаблонов, CRD, значений по умолчанию. Собирать вручную из отдельных YAML нецелесообразно. Качаем **весь chart** в `local/manifests/traefik/` и управляет им через `helm.values` в `traefik-app.yaml` (реплики, LoadBalancer IP, порты, провайдеры).

### Kubernetes Dashboard — манифест + RBAC
Официальный релиз Dashboard (`recommended.yaml`) качаем как есть. Наша часть — только RBAC (`rbac.yaml` для пользователя `admin-user`) и ArgoCD Application.

### Backend / Databases — собственные chart'ы
Это наши приложения, chart'ы написаны с нуля в `local/charts/`.

---

## Как добавить новый компонент

1. Создать ArgoCD Application в `local/argocd/<имя>-app.yaml` (с `sync-wave` и `finalizers`).
2. Если компонент upstream — скачать манифест/chart в `local/manifests/<имя>/`.
3. Если компонент свой — создать chart в `local/charts/<имя>/`.
4. Добавить RBAC/конфигурацию при необходимости.
5. Application автоматически подхватится `root-app` (App-of-Apps).

---

## Документация по компонентам

| Компонент | Документация |
|-----------|-------------|
| MetalLB | `docs/metallb.md` |
| Traefik | `docs/traefik.md` |
| K8s Dashboard | `docs/kubernetes-dashboard.md` |
| Backend | *(в разработке)* |
| Databases | *(в разработке)* |