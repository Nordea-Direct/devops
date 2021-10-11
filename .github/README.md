# Reusable github workflows 

- Frontends use `.github\workflows\frontend-*.yaml` files
- Backends use `.github\workflows\backend-*.yaml` files

## Usage
In the consuming repository add this to your workflow:

```yaml
jobs:
  call-build-workflow:
    uses: Nordea-Direct/devops/.github/workflows/backend-pr-change.yaml@master
    secrets:
      ACCESS_PACKAGES_USERNAME: ${{ secrets.ACCESS_PACKAGES_USERNAME }}
      ACCESS_PACKAGES_GLOBAL_PAT: ${{ secrets.ACCESS_PACKAGES_GLOBAL_PAT }}
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN}}
``` 

> Remember to reference the correct workflow (`frontend/backend, pr-change, pr-merge, release`) from `uses` 
