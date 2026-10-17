# Чарты проекта Mediapulse

Исходники Helm-чартов:

- `backend/` — API и Worker Mediapulse
- `databases/` — PostgreSQL + Redis
- `argocd/` — обёртка над upstream-чартом `argo/argo-cd` (значения проекта + Traefik IngressRoute)

## Как чарты попадают в кластер

**Git — единственный источник правды.** Кластерные установки идут только из этого репозитория:

1. **Argo CD (основной путь).** Application'ы в `local/argocd/` ссылаются на пути в этом репозитории (`path: local/charts/backend` и т.д.). При пуше изменений чарта Argo CD сам перерендеривает шаблоны из git-чекаута и синкает — никакого helm-реестра в цепочке нет.
2. **Локальная установка (bootstrap).** Чарт `argocd` ставится напрямую с диска, без сети и реестров:
   ```bash
   helm upgrade --install argocd ../../Mediapulse-Gitops/local/charts/argocd -n argocd
   ```
   (это делает `make argocd-up` в Mediapulse-Infra). Upstream-чарт argo-cd запакован внутрь обёртки, поэтому установка офлайн-совместима.

Дополнительно существует **публикуемая копия** чартов в отдельном репозитории [Izanar/helm-charts](https://github.com/Izanar/helm-charts) — для внешних потребителей (см. «Публикация чартов» ниже). На кластерные установки она не влияет.

## Изменение чарта

```bash
# 1. правка templates/ или values.yaml
# 2. опционально: bump версии в Chart.yaml (для Argo CD не влияет,
#    но обязателен для публикации в helm-charts — см. ниже)
# 3. проверка и публикация в git
helm template test local/charts/<имя>          # локальный рендер
git add -A && git commit -m "chart(<имя>): ..." && git push
```

Для чарта `argocd` (bootstrap) после пуша повторите `make argocd-up` в Mediapulse-Infra — Argo CD ещё не управляет собственной установкой.

Если чарт должен уйти и во внешнюю публикацию — скопируйте его в `Izanar/helm-charts` (см. README там):

```bash
cp -a local/charts/<имя> ../helm-charts/charts/
cd ../helm-charts && git add charts/<имя> && git commit -m "release: <имя> <версия>" && git push
```

## Справочно: внутренний вид чарта

`helm package local/charts/argocd` собирает каталог чарта в tar.gz с префиксом `имя-версия`. Внутри `argocd-0.2.0.tgz`:

```
argocd/Chart.yaml              <- манифест обёртки (name: argocd, version: 0.2.0)
argocd/values.yaml             <- значения, включая ключ argo-cd.* для субчарта
argocd/templates/ingress.yaml  <- собственный шаблон IngressRoute
argocd/charts/argo-cd/...      <- upstream-чарт argo-cd 7.0.0, запакованный внутрь
```

Благодаря каталогу `charts/` внутри пакета `helm install` ничего не качает с `argoproj.github.io` — весь argo-cd уже внутри. При обновлении зависимости: `helm dependency update local/charts/argocd`.

## Публикация чартов (отдельный репозиторий)

Для **внешних** потребителей (чужие окружения и команды без доступа к этому git-репозиторию) чарты публикуются в [Izanar/helm-charts](https://github.com/Izanar/helm-charts) через [chart-releaser-action](https://github.com/helm/chart-releaser-action):

```bash
helm repo add mediapulse https://izanar.github.io/helm-charts
helm repo update
helm search repo mediapulse/
```

- Исходники чартов остаются здесь; в helm-charts лежит **копия**, которую нужно синхронизировать вручную (команда выше).
- Публикацию запускает push в `main` helm-charts с изменениями в `charts/**`: chart-releaser создаёт GitHub Release с `.tgz` для каждой новой версии и обновляет `index.yaml` в ветке `gh-pages` (GitHub Pages).
- **Версия в `Chart.yaml` обязана расти** при каждом изменении чарта — релизы иммутабельны, повторный пуш той же версии не перезапишет артефакт.
- Кластер по-прежнему синкает Argo CD из этого git-репозитория — публикация ничего не меняет в GitOps-цепочке.
