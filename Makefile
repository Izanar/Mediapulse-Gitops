.PHONY: argocd-install argocd-upgrade bootstrap clean

# Установка/обновление самого ArgoCD через Helm
argocd-install:
	cd charts/argocd && helm upgrade --install argocd argo/argo-cd --namespace argocd --create-namespace -f values.yaml

# Первый запуск (bootstrap): применение корневого App of Apps
bootstrap: argocd-install
	@echo "Applying root application..."
	kubectl apply -f argocd/root.yaml

argopassword:
	@echo "ArgoCD initial password:"
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo ""
# Принудительная синхронизация через CLI (если нужно без вебки)
sync:
	argocd app sync root-app

# Очистка кластера
clean:
	kubectl delete namespace argocd --ignore-not-found