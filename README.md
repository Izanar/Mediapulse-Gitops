# Mediapulse GitOps Deployment

Декларативный деплой приложений Mediapulse через **ArgoCD (App of Apps) + Helm**.
Этот репозиторий содержит Helm-чарты (`backend`, `databases`) и ArgoCD
`Application`-манифесты, которые регистрируют их в кластере.

> ⚠️ **Сам ArgoCD здесь НЕ устанавливается.** ArgoCD, ingress-nginx и кластер
> разворачиваются в репозитории [`Mediapulse-Infra`](../Mediapulse-Infra)
> (`make all-up`). Этот репозиторий только добавляет поверх ArgoCD приложения
> Mediapulse.

## Архитектура

```
Mediapulse-Infra            Mediapulse-Gitops (этот репо)
  make all-up                 make bootstrap
  ├─ Kind cluster       ──▶    └─ argocd/root.yaml  (root-app, App of Apps)
  ├─ ingress-nginx              └─ argocd/
  └─ ArgoCD (Helm)                 ├─ backend-app.yaml   ──▶ charts/backend  (api, worker, migration)
                                   └─ databases-app.yaml ──▶ charts/databases (postgres, redis)
```

`root-app` следит за папкой `argocd/` и автоматически создаёт `backend-app` и
`databases-app` (`automated.prune` + `selfHeal` — правки в git применяются сами).

## Требования

- Работающий кластер с уже установленным **ArgoCD** и **ingress-nginx**
  (см. `Mediapulse-Infra`)
- `kubectl` в `PATH`
- `helm` (для локального рендеринга/отладки чартов)
- ArgoCD CLI `argocd` — **опционально**, только для целей `sync`/`status`
- Доступ к git-репозиторию, на который ссылаются `repoURL` в манифестах
  (по умолчанию `https://github.com/Izanar/Mediapulse-Gitops.git`)

## Быстрый старт

### 1. Поднять инфраструктуру (если ещё не поднята)

```bash
cd ../Mediapulse-Infra/local
make all-up        # кластер + ingress-nginx + ArgoCD
```

### 2. Зарегистрировать приложения Mediapulse в ArgoCD

```bash
cd Mediapulse-Gitops
make bootstrap     # применяет argocd/root.yaml (App of Apps)
```

ArgoCD подхватит `root-app` и автоматически развернёт `backend` и `databases`.
Отслеживать синхронизацию можно в UI (`https://argocd.local`) или так:

```bash
kubectl -n argocd get applications
```

### 3. Получить пароль администратора ArgoCD

```bash
make argopassword
# или вручную:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Доступ к UI и приложению

| Сервис              | URL                          |
| ------------------- | ---------------------------- |
| ArgoCD UI           | `https://argocd.local`       |
| Mediapulse backend  | `https://mediapulse.local`   |

В `/etc/hosts` должны быть строки (для локального Kind — IP = `127.0.0.1`):

```
127.0.0.1 argocd.local
127.0.0.1 mediapulse.local
```

## Команды Makefile

| Команда             | Что делает                                                        |
| ------------------- | ----------------------------------------------------------------- |
| `make bootstrap`    | Применяет `argocd/root.yaml` (App of Apps) — регистрирует backend и databases |
| `make argopassword` | Печатает начальный пароль `admin` ArgoCD                          |
| `make sync`         | Принудительная синхронизация `root-app` (нужен ArgoCD CLI)        |
| `make status`       | Список приложений ArgoCD (нужен ArgoCD CLI)                       |
| `make clean`        | Удаляет `root-app` (каскадом уберёт backend и databases). Namespace `argocd` остаётся |

## Структура репозитория

```
Mediapulse-Gitops/
├── Makefile                     # цели bootstrap/sync/status/clean
├── argocd/                      # ArgoCD Application-манифесты
│   ├── root.yaml                #   App of Apps (следит за этой папкой)
│   ├── backend-app.yaml         #   -> charts/backend
│   └── databases-app.yaml       #   -> charts/databases
└── charts/
    ├── backend/                 # API + Worker + миграции Alembic
    │   └── templates/           #   api, worker, migration-job, secret, ingress
    └── databases/               # PostgreSQL + Redis
        └── templates/           #   postgres, redis
```

## Конфигурация значений

Все значения (образы, реплики, креды БД, ключи S3/R2) задаются в
`charts/*/values.yaml`. После правки достаточно сделать `git push` — ArgoCD
подтянет изменения сам (`targetRevision: HEAD`, `automated`).
