# Helm-репозиторий проекта Mediapulse

Здесь хранятся упакованные Helm-чарты проекта:
- `backend` — API и Worker Mediapulse
- `databases` — PostgreSQL и Redis
- `argocd` — локальная обёртка над upstream-чартом `argo/argo-cd` (значения проекта)

## Подключение репозитория

```bash
helm repo add mediapulse https://izanar.github.io/Mediapulse-Gitops
helm repo update
```

## Установка чартов

```bash
# Бэкенд
helm install mediapulse-backend mediapulse/backend -n default

# Базы данных
helm install mediapulse-databases mediapulse/databases -n default

# Argo CD (через обёртку со значениями проекта)
helm install argocd mediapulse/argocd -n argocd
# или напрямую из upstream:
helm upgrade --install argocd argo/argo-cd -n argocd -f charts/argocd/values.yaml
```

## Сборка репозитория локально

```bash
cd local/
helm package charts/backend --destination helm-repo/
helm package charts/databases --destination helm-repo/
helm package charts/argocd --destination helm-repo/
helm repo index helm-repo --url https://izanar.github.io/Mediapulse-Gitops
```

Чарт `argocd` является обёрткой (umbrella) над `argo/argo-cd`. При установке через этот чарт убедитесь, что подключён репозиторий `https://argoproj.github.io/argo-helm`, либо выполните `helm dependency build charts/argocd` перед упаковкой.

## Связь с Argo CD

Argo CD Application'ы в `local/argocd/` по-прежнему ссылаются на локальные пути в Git-репозитории (`path: local/charts/backend` и т.д.), а не на удалённый Helm-репозиторий. Helm-репозиторий нужен для распространения чартов вне этого репозитория (например, для установки в другие окружения или через CI/CD).