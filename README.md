# hellnet-gitops

Fonte da verdade do que roda no cluster Talos `hellnet`: manifestos [Kustomize](https://kustomize.io) lidos pelo
Argo CD. Os repositórios dos serviços (`fast-platform`, `fast-listeners`, `fast-sockets`) só produzem código e
imagem no GHCR; **nenhum manifesto de deploy vive neles**.

## Estrutura

```text
apps/<serviço>/        kustomization.yaml, deployment.yaml (e service.yaml quando o serviço recebe tráfego)
components/hardened/   baseline de segurança aplicado a todo Deployment (Pod Security restricted)
bootstrap/             ApplicationSet que cria uma Application por pasta de apps/
```

| Serviço | Imagem | Acesso |
|---|---|---|
| `fast-platform` | `ghcr.io/guilhermelinosp/fast-platform` | `port-forward` (`localhost:18080`) |
| `fast-listeners` | `ghcr.io/guilhermelinosp/fast-listeners` | nenhuma (publica o outbox no Kafka) |
| `fast-sockets` | `ghcr.io/guilhermelinosp/fast-sockets` | `port-forward` (`localhost:18081`) |

Os serviços **não têm `HTTPRoute`**: nada fica exposto no Gateway. Por enquanto o acesso é por `kubectl
port-forward` (`make forward` em `~/.talos/cluster` abre `localhost:18080` e `localhost:18081`). Um gateway proxy
próprio entra depois, e é nele que as rotas voltam.

## Atualizar a versão de um serviço

A versão é o `newTag` em `images:` do `kustomization.yaml` do serviço:

```bash
cd apps/fast-listeners && kustomize edit set image ghcr.io/guilhermelinosp/fast-listeners=ghcr.io/guilhermelinosp/fast-listeners:v1.3.0
```

Abra um PR com a mudança; depois do merge, sincronize no Argo CD:

```bash
argocd app sync fast-listeners
```

Voltar uma versão é um `git revert` do commit e um novo sync. A sincronização é manual de propósito: para o deploy
automático, adicione `automated: {prune: true, selfHeal: true}` em `syncPolicy` no `bootstrap/applicationset.yaml`.

## Configuração

As variáveis de ambiente de cada serviço ficam em `configMapGenerator` no `kustomization.yaml`. O Kustomize acrescenta
um hash ao nome do ConfigMap, então **alterar a configuração reinicia o pod** sozinho. O usuário e a senha do banco
vêm do Secret `fast-database`, que **não** está no git (`make fast-secrets` em `~/.talos/cluster`).

## Validar localmente

```bash
kubectl kustomize apps/fast-platform | kubeconform -strict -ignore-missing-schemas -summary -
```

O workflow `validate` faz o mesmo para todas as pastas de `apps/` em cada pull request (`pr-gate`).

## Bootstrap (uma vez)

```bash
kubectl apply -f bootstrap/applicationset.yaml
```

Para adicionar um serviço, crie `apps/<nome>/` com um `kustomization.yaml`; o ApplicationSet cria a Application.
