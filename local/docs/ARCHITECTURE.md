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
| ArgoCD обёртка + values | `local/charts/argocd/` | **Своё** | — | Umbrella-чарт: values для argo/argo-cd + шаблон Traefik IngressRoute (`templates/ingress.yaml`) |
| IngressRoute Traefik UI | `local/manifests/traefik/templates/traefik-dashboard-ingress.yaml` | **Своё** | — | Traefik IngressRoute для traefik.local |
| IngressRoute K8s Dashboard | `local/manifests/kubernetes-dashboard/k8s-dashboard-ingress.yaml` | **Своё** | — | Traefik IngressRoute + ServersTransport для k8s.local |
| IngressRoute backend | `local/charts/backend/templates/ingress.yaml` | **Своё** | — | Traefik IngressRoute для mediapulse.local |
| Helm-репозиторий | `local/helm-repo/` | **Своё** | — | Упакованные чарт'ы backend, databases, argocd + index.yaml |

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

---

## Bootstrap: как устанавливается Argo CD

Argo CD устанавливается **императивно** — через Helm CLI до того, как сам появится в кластере. Это решает проблему «курица и яйцо»: Argo CD не может установить себя сам через собственный Application, потому что для этого он уже должен быть запущен.

Цепочка запуска (`Mediapulse-Infra/local/Makefile`):

1. `make cluster-up` — создаёт Kind-кластер.
2. `make argocd-up` — ставит Argo CD через Helm (локальный umbrella-чарт `local/charts/argocd/`; upstream `argo-cd` запакован внутрь чарта, сеть не нужна):
   ```bash
   helm upgrade --install argocd ../../Mediapulse-Gitops/local/charts/argocd --namespace argocd
   ```
   Внутри чарта: `values.yaml` с переопределениями (`server.insecure: true`, RBAC для группы `admins`, upstream-ingress выключен) и `templates/ingress.yaml` с Traefik IngressRoute для `argocd.local`.
3. `kubectl apply -f local/argocd/root.yaml` — создаёт `root-app` (App-of-Apps), который забирает все остальные Application из папки `local/argocd/`.

После этого Argo CD сам управляет всем остальным (MetalLB, Traefik, backend, databases, kubernetes-dashboard, ingress-маршруты).

**В продакшене** установка самого Argo CD обычно делается один раз извне (Helm, Argo CD Operator, или официальные манифесты), а затем через Argo CD Application может управляться его собственная конфигурация (с осторожностью — чтобы не удалить самого себя по ошибке).

---

## Распределение Ingress-маршрутов

Каждый `IngressRoute` Traefik лежит в папке своего компонента и управляется соответствующим Argo CD Application:

| Маршрут | Путь | Управляет Application |
|---------|------|----------------------|
| `argocd.local` → `argocd-server` | `local/charts/argocd/templates/ingress.yaml` | императивный bootstrap (`make argocd-up`, вне Argo CD) |
| `traefik.local/dashboard` | `local/manifests/traefik/templates/traefik-dashboard-ingress.yaml` | `traefik-app` (через Helm chart) |
| `k8s.local` → `kubernetes-dashboard` | `local/manifests/kubernetes-dashboard/k8s-dashboard-ingress.yaml` | `kubernetes-dashboard-app` |
| `mediapulse.local` → `mediapulse-api-service` | `local/charts/backend/templates/ingress.yaml` | `backend-app` (через Helm chart) |

Таким образом, отдельный Application для всех IngressRoute не нужен — каждый компонент отвечает за свой маршрут.

---

## Helm-репозиторий проекта

Упакованные чарт'ы проекта хранятся в `local/helm-repo/`:

- `backend-0.1.0.tgz` — собственный чарт API и Worker
- `databases-0.1.0.tgz` — собственный чарт PostgreSQL + Redis
- `argocd-0.2.0.tgz` — обёртка над `argo/argo-cd` (values проекта + Traefik IngressRoute)
- `index.yaml` — индекс репозитория

**Подключение:**
```bash
helm repo add mediapulse https://izanar.github.io/Mediapulse-Gitops
helm repo update
```

**Установка:**
```bash
helm install mediapulse-backend mediapulse/backend -n default
helm install mediapulse-databases mediapulse/databases -n default
helm install argocd mediapulse/argocd -n argocd
```

**Публикация:** содержимое `local/helm-repo/` автоматически выкладывается на GitHub Pages через workflow `.github/workflows/helm-pages.yml` (при пуше в `main`, затрагивающем `local/helm-repo/`). Сайт: https://izanar.github.io/Mediapulse-Gitops

**Важно:** Argo CD Application'ы в этом репозитории ссылаются на локальные пути Git (`path: local/charts/backend` и т.д.), а не на удалённый Helm-репозиторий. Helm-репозиторий нужен для распространения чартов в другие окружения или через CI/CD.