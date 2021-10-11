# Reusable github workflows 

[Readme for reusable workflows](.github/README.md)

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
