# Reusable github workflows 

- Frontends use `.github\workflows\frontend-*.y(a)ml` files
- Backends use `.github\workflows\backend-*.y(a)ml` files

## Usage
In the consuming repository add this to your workflow:

```yaml
jobs:
  call-build-workflow:
    uses: Nordea-Direct/devops/.github/workflows/backend-build.yaml@master
    secrets:
      ACCESS_PACKAGES_USERNAME: ${{ secrets.ACCESS_PACKAGES_USERNAME }}
      ACCESS_PACKAGES_GLOBAL_PAT: ${{ secrets.ACCESS_PACKAGES_GLOBAL_PAT }}
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN}}
``` 
Remember to change the *uses* line to the correct workflow (`frontend/backend, build, pre-release, release`)

# Setting up your dev environment in a jiffy

- [install](https://chocolatey.org/install) chocolatey
- go to the **_chocolatey_** folder in this repo
- as **admin**, run `choco install packages.config`
  - you will get:
    - java
    - maven
    - node/npm
    - intellij
    - vscode
    - cmder
    - and more
- Everything will be installed in `C:\ProgramData\chocolatey\lib`
    
# Maven settings.xml

- copy [settings.xml](maven/settings.xml) to your home area
  - Replace username and password (with your PAT)


# Node/npm .npmrc

- copy [.npmrc](npm/.npmrc) to your home area
    - Replace _authToken (with your PAT)
