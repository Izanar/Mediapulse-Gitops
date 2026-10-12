# Mediapulse GitOps Deployment

Проект полностью переведен на декларативный подход GitOps (ArgoCD + Helm + App of Apps). Ручные скрипты деплоя больше не используются.

## Требования
- Kubernetes кластер (Minikube / Kind / Production)
- Установленный `helm` и `kubectl`
- Настроенный age-ключ для SOPS (в секрете `sops-age` в пространстве имен `argocd`)

## Быстрый старт (Первый запуск)

1. **Клонируйте репозиторий** и перейдите в его корень.
2. **Выполните bootstrap-команду** (она установит ArgoCD через Helm и поднимет корневое приложение):
   ```bash
   make bootstrap

   Получите пароль администратора ArgoCD:

```Bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

Настройте доступ к UI:
Добавьте в /etc/hosts строку с IP вашего кластера:
Plaintext
<IP-кластера> argocd.local
И открывайте в браузере: https://argocd.local