# Deploying NVIDIA NIM with Helm

The local Helm chart was removed from this repository. Use the [official NIM LLM Helm chart on NGC](https://catalog.ngc.nvidia.com/orgs/nim/helm-charts/nim-llm) and follow the [NVIDIA Helm deployment documentation](https://docs.nvidia.com/nim/large-language-models/latest/deploy-helm.html).

## OpenShift Container Platform permissions

For deployments that require the `anyuid` SecurityContextConstraints (SCC), a cluster administrator or a user with permission to grant the SCC must grant it to the service account that runs the NIM pods. Follow the security requirements for your selected chart and image; `anyuid` is not required for every deployment.

Create the `nim` namespace before running the following command. Set `SERVICE_ACCOUNT_NAME` to the service account used by your Helm release:

```bash
export SERVICE_ACCOUNT_NAME=default
oc adm policy add-scc-to-user anyuid -z "$SERVICE_ACCOUNT_NAME" -n nim
```

If you use a custom service account, configure the chart to use that account. For charts exposing `serviceAccount.name` and `serviceAccount.create`, set `serviceAccount.name` to the same name and set `serviceAccount.create=true` if Helm should create it, or `false` if it already exists.

See [Red Hat's SCC permission guidance](https://access.redhat.com/solutions/5529581) and [NVIDIA's OpenShift deployment guide](https://docs.nvidia.com/ai-enterprise/deployment/red-hat-ai-factory/latest/deploy-ai-workloads-nim-operator.html) for platform-specific details.
