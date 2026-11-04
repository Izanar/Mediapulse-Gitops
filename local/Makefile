.PHONY: help bootstrap argopassword sync status clean

# --- GitOps: деплой приложений Mediapulse через ArgoCD (App of Apps) ---
#
# ВАЖНО: сам ArgoCD здесь НЕ устанавливается. Он разворачивается в репозитории
# Mediapulse-Infra (make all-up / make argocd-up). Этот репозиторий только
# регистрирует в ArgoCD приложения Mediapulse (backend, databases).

help: ## Показать список доступных команд
	@echo "Доступные команды в mediapulse-gitops:"
	@echo "  make bootstrap      - Применить корневой App of Apps (root-app)"
	@echo "  make argopassword   - Показать начальный пароль admin в ArgoCD"
	@echo "  make sync           - Принудительно синхронизировать root-app (нужен argocd CLI)"
	@echo "  make status         - Показать список приложений ArgoCD (нужен argocd CLI)"
	@echo "  make clean          - Удалить приложения Mediapulse из кластера"

# Предусловие: ArgoCD должен быть уже развёрнут (это делает Mediapulse-Infra).
define require_argocd
@kubectl get ns argocd >/dev/null 2>&1 || { echo "❌ Namespace argocd не найден — ArgoCD разворачивается в Mediapulse-Infra (make all-up)"; exit 1; }
endef

bootstrap: ## Применить корневой App of Apps (регистрирует backend и databases)
	$(require_argocd)
	@echo "🚀 Применение корневого приложения (App of Apps)..."
	kubectl apply -f argocd/root.yaml
	@echo "✅ root-app применён. ArgoCD автоматически поднимет backend и databases."
	@echo "   Статус: kubectl -n argocd get applications"

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

clean: ## Удалить приложения Mediapulse (backend, databases) из кластера
	$(require_argocd)
	@echo "🧹 Удаление root-app (каскадом уберёт backend и databases)..."
	-kubectl delete -f argocd/root.yaml --ignore-not-found
	@echo "ℹ️  Namespace argocd остаётся — им управляет Mediapulse-Infra."
