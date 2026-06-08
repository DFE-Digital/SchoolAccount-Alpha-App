# School Account Alpha App

An ASP.NET Core Web App (MVC) serving as a placeholder application while the pipeline for the School Account Alpha project is built out.

## Getting Started

### Build

```sh
dotnet build --project src/Web.Mvc
```

### Run

```sh
dotnet run --project src/Web.Mvc
```

The app is available at http://localhost:5000.

### Docker Compose

```sh
docker compose up -d
```

## Package Management

NuGet package versions are managed centrally via [`Directory.Packages.props`](Directory.Packages.props). All projects reference packages without version numbers in their `.csproj` files — versions are declared once in `Directory.Packages.props` and apply solution-wide. To add or update a package, edit that file.

Shared build settings (target framework, nullable reference types, analyser configuration, etc.) are defined in [`Directory.Build.props`](Directory.Build.props) and inherited by every project automatically.

## Dependabot

[GitHub Dependabot](https://github.com/DFE-Digital/SchoolAccount-Alpha-App/security/dependabot) is configured to check NuGet dependencies daily and raise pull requests automatically when newer package versions are available. Dependabot PRs target the `main` branch and should be reviewed and merged in the normal way.

Configuration: [`.github/dependabot.yml`](.github/dependabot.yml).

## CI Pipeline

A GitHub Actions workflow ([`.github/workflows/build.yml`](.github/workflows/build.yml)) runs on every push to `main` and on every pull request targeting `main`. The pipeline:

- Builds the Docker image from [`src/Web.Mvc/Dockerfile`](src/Web.Mvc/Dockerfile).
- Pushes the image to the [GitHub Container Registry](https://ghcr.io) (`ghcr.io/dfe-digital/schoolaccount-alpha-app`) on merges to `main`.
- Tags images with the commit SHA, branch name, and `latest` (for `main` only).

The workflow uses the built-in `GITHUB_TOKEN` for registry authentication — no additional secrets are required.

## Contributing

Contributions are made via pull requests targeting the `main` branch on [DFE-Digital/SchoolAccount-Alpha-App](https://github.com/DFE-Digital/SchoolAccount-Alpha-App).

1. Fork or branch from `main`.
2. Make your changes.
3. Open a pull request against `main` at [github.com/DFE-Digital/SchoolAccount-Alpha-App](https://github.com/DFE-Digital/SchoolAccount-Alpha-App/pulls).
4. The CI pipeline will run automatically — all checks must pass before merge.
