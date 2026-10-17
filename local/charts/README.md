# Чарты проекта Mediapulse

Исходники Helm-чартов:

- `backend/` — API и Worker Mediapulse
- `databases/` — PostgreSQL + Redis
- `argocd/` — обёртка над upstream-чартом `argo/argo-cd` (значения проекта + Traefik IngressRoute)

## Как чарты попадают в кластер

Отдельный Helm-репозиторий (GitHub Pages, OCI-реестр, ArtifactHub) **не используется**: git — единственный источник правды.

1. **Argo CD (основной путь).** Application'ы в `local/argocd/` ссылаются на пути в этом репозитории (`path: local/charts/backend` и т.д.). При пуше изменений чарта Argo CD сам перерендеривает шаблоны из git-чекаута и синкает — никакого helm-реестра в цепочке нет.
2. **Локальная установка (bootstrap).** Чарт `argocd` ставится напрямую с диска, без сети и реестров:
   ```bash
   helm upgrade --install argocd ../../Mediapulse-Gitops/local/charts/argocd -n argocd
   ```
   (это делает `make argocd-up` в Mediapulse-Infra). Upstream-чарт argo-cd запакован внутрь обёртки, поэтому установка офлайн-совместима.

## Изменение чарта

```bash
# 1. правка templates/ или values.yaml
# 2. опционально: bump версии в Chart.yaml (нужен только для нумерации релизов,
#    на синк через Argo CD не влияет)
# 3. проверка и публикация в git
helm template test local/charts/<имя>          # локальный рендер
git add -A && git commit -m "chart(<имя>): ..." && git push
```

Для чарта `argocd` (bootstrap) после пуша повторите `make argocd-up` в Mediapulse-Infra — Argo CD ещё не управляет собственной установкой.

## Справочно: внутренний вид чарта

`helm package local/charts/argocd` собирает каталог чарта в tar.gz с префиксом `имя-версия`. Внутри `argocd-0.2.0.tgz`:

```
argocd/Chart.yaml              <- манифест обёртки (name: argocd, version: 0.2.0)
argocd/values.yaml             <- значения, включая ключ argo-cd.* для субчарта
argocd/templates/ingress.yaml  <- собственный шаблон IngressRoute
argocd/charts/argo-cd/...      <- upstream-чарт argo-cd 7.0.0, запакованный внутрь
```

Благодаря каталогу `charts/` внутри пакета `helm install` ничего не качает с `argoproj.github.io` — весь argo-cd уже внутри. При обновлении зависимости: `helm dependency update local/charts/argocd`.

## Почему чарты не публикуются в реестр

Публикация чартов в helm-репозиторий (OCI/Pages/ArtifactHub) нужна, когда их ставят **внешние** потребители — чужие окружения или команды без доступа к этому git-репозиторию. Такого кейса у проекта нет: один кластер, GitOps-контур, все потребители читают git. Реестр дублировал бы git и добавлял CI, версионирование тегов и digest-дисциплину без реальной пользы. Если кейс появится — чарты публикуются одной командой `helm push oci://ghcr.io/<орг>/<чарты>` из workflow, ничего переизобретать не придётся.
