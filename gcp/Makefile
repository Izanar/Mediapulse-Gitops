.PHONY: help bootstrap argopassword sync status clean

# --- GitOps: деплой инфраструктуры и приложений Mediapulse в GCP через ArgoCD ---

help: ## Показать список доступных команд
	@echo "Доступные команды в Mediapulse-Gitops (GCP):"
	@echo "  make bootstrap      - Применить корневой App of Apps для GCP"
	@echo "  make argopassword   - Показать начальный пароль admin в ArgoCD"
	@echo "  make sync           - Принудительно синхронизировать root-app (нужен argocd CLI)"
	@echo "  make status         - Показать статус приложений ArgoCD (нужен argocd CLI)"
	@echo "  make clean          - Удалить приложения из GCP кластера"

# Проверка наличия ArgoCD в кластере GKE
define require_argocd
@kubectl get ns argocd >/null 2>&1 || { echo "❌ Namespace argocd не найден — установите ArgoCD перед бутстрапом"; exit 1; }
endef

bootstrap: ## Применить корневой App of Apps для GCP
	$(require_argocd)
	@echo "🚀 Применение корневого приложения для GCP (Traefik, Backend и др.)..."
	kubectl apply -f gcp/argocd/root.yaml
	@echo "✅ root-app применён. ArgoCD начинает развертывание инфраструктуры."
	@echo "   Проверка статуса: kubectl -n argocd get applications"

argopassword: ## Вывести начальный пароль администратора ArgoCD
	$(require_argocd)
	@echo "ArgoCD initial password:"
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo ""

sync: ## Принудительная синхронизация root-app (требуется argocd CLI)
	@command -v argocd >/dev/null 2>&1 || { echo "❌ ArgoCD CLI не найден: https://argo-cd.readthedocs.io/en/stable/cli_installation/"; exit 1; }
	argocd app sync root-app

status: ## Показать статус приложений ArgoCD (требуется argocd CLI)
	@command -v argocd >/dev/null 2>&1 || { echo "❌ ArgoCD CLI не найден: https://argo-cd.readthedocs.io/en/stable/cli_installation/"; exit 1; }
	argocd app list

clean: ## Удалить приложения Mediapulse из GCP кластера
	$(require_argocd)
	@echo "🧹 Удаление root-app для GCP..."
	-kubectl delete -f gcp/dev/argocd/root.yaml --ignore-not-found
	@echo "ℹ️  Namespace argocd остаётся в кластере."