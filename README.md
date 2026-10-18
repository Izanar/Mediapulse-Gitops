# Mediapulse GitOps Deployment

<div align="center">

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.30+-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-red?style=for-the-badge&logo=argo&logoColor=white)](https://argoproj.github.io/)
[![Helm](https://img.shields.io/badge/Helm-Charts%20%7C%20v3-0F1689?style=for-the-badge&logo=helm&logoColor=white)](https://helm.sh/)
[![Traefik](https://img.shields.io/badge/Traefik-Ingress%20Controller-24A1C1?style=for-the-badge&logo=traefikproxy&logoColor=white)](https://doc.traefik.io/traefik/)
[![License](https://img.shields.io/badge/License-MPL%202.0-blue?style=for-the-badge)](LICENSE.md)

</div>

Декларативный деплой приложений Mediapulse через **ArgoCD (App of Apps) + Helm**.
Этот репозиторий содержит Helm-чарты (`backend`, `databases`) и ArgoCD
`Application`-манифесты, которые регистрируют их в кластере.

> ⚠️ **Сам ArgoCD здесь НЕ устанавливается.** ArgoCD, Traefik и кластер
> разворачиваются в репозитории [`Mediapulse-Infra`](../Mediapulse-Infra)
> (`make all-up`). Этот репозиторий только добавляет поверх ArgoCD приложения
> Mediapulse.

## Архитектура

```
Mediapulse-Infra            Mediapulse-Gitops (этот репо)
  make all-up                 ArgoCD Applications
  ├─ Kind cluster       ──▶    ├─ MetalLB → Traefik
  ├─ ArgoCD (Helm)             ├─ databases → backend
  └─ dashboard setup           ├─ Kubernetes Dashboard
                               └─ argocd/root.yaml (root-app adopts these Applications)
```

`root-app` следит за Application-манифестами в папке `argocd/` и управляет
инфраструктурой и приложениями Mediapulse. Собственный манифест `root.yaml`
исключён из отслеживаемых ресурсов, чтобы Argo CD не пытался создавать и
удалять самого себя. `make all-up` сначала разворачивает приложения по
зависимостям, затем применяет `root-app`, чтобы он принял эти Application
под управление (`automated.prune` + `selfHeal`).

## Требования

- Работающий кластер с уже установленным **ArgoCD** и **Traefik**
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
make all-up        # кластер + MetalLB + Traefik + ArgoCD + приложения
```

### 2. Зарегистрировать приложения Mediapulse в ArgoCD

```bash
cd Mediapulse-Gitops
make bootstrap     # применяет argocd/root.yaml (App of Apps)
```

Argo CD подхватит `root-app` и будет автоматически синхронизировать приложения.
Отслеживать синхронизацию можно в UI (`https://argocd.local:8443/`) или так:

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
| ArgoCD UI           | `https://argocd.local:8443/` |
| Mediapulse app (UI/API) | `https://mediapulse.local:8443/` |

UI обслуживается контейнером API. Hostname `mediapulse.local` задан в
[`local/charts/backend/values.yaml`](./local/charts/backend/values.yaml) и
используется Traefik для маршрутизации HTTP/HTTPS. Имя должно разрешаться на
адрес, ведущий к Traefik: при port-forward это `127.0.0.1` в WSL или IP WSL2
в Windows (см. инструкцию ниже). В Argo CD приложение зарегистрировано как
`mediapulse-app`; его манифест находится в
[`local/argocd/mediapulse-app.yaml`](./local/argocd/mediapulse-app.yaml).

Для доступа из Windows через WSL2 запустите `make traefik-port-forward` в
репозитории `Mediapulse-Infra` и добавьте в `hosts` IP WSL2, который выводит
`make all-up`:

```
<WSL2_IP> argocd.local traefik.local k8s.local mediapulse.local
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
│   ├── mediapulse-app.yaml      #   -> charts/backend
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

## ⚠️ Секреты и конфиденциальные данные

В файле `charts/backend/values.yaml` сейчас указаны **примерные/заглушечные**
значения паролей и ключей (parallely к `.env.example`):

```yaml
database:
  password: mediapulse_secret   # ← заменить перед запуском в прод
storage:
  secretAccessKey: "..."        # ← заменить перед запуском в прод
```

**Не коммитьте реальные секреты в Git.** Порядок действий перед развёртыванием
в production:

1. Склонируйте репозиторий.
2. Отредактируйте `charts/backend/values.yaml`, вставив настоящие значения из
   вашего секрет-хранилища (HashiCorp Vault, AWS Secrets Manager, Yandex Lockbox и т.д.).
3. Либо передайте их при установке через `--set` / отдельный `values.prod.yaml`:
   ```bash
   helm upgrade --install backend charts/backend \
     --set database.password=$(vault read -field=password secret/mediapulse/db) \
     --set storage.secretAccessKey=$(vault read -field=key secret/mediapulse/s3)
   ```
4. Сделайте `git push` только с несекретными изменениями. Файл с реальными
   паролями не должен попадать в коммит.

Для локального Kind-окружения примерные значения из `values.yaml` подходят —
достаточно для разработки и тестирования.
