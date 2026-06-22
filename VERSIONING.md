# RetroShine Versioning Policy

## Semantic Versioning 2.0.0

RetroShine uses [SemVer](https://semver.org/) for all releases: `vMAJOR.MINOR.PATCH`

### Version Components

| Component | When to Bump | Examples |
|-----------|-------------|----------|
| **MAJOR** | Breaking changes — image base OS swap, core architecture rewrite, incompatible config changes | v1.0.0 → v2.0.0 |
| **MINOR** | New features — additional libretro cores, new systems, new config capabilities | v1.0.0 → v1.1.0 |
| **PATCH** | Bug fixes — config tweaks, documentation, build optimizations, dependency updates | v1.0.0 → v1.0.1 |

### Release Process

1. Update `VERSION` file with new version number
2. Commit: `chore: bump version to vX.Y.Z`
3. Tag: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`
4. Push: `git push origin master --tags`
5. The GitHub Actions workflow automatically:
   - Builds the Docker image with version + latest tags
   - Deploys to the production server
   - Creates a GitHub Release with auto-generated notes

### Docker Image Tags

| Tag | Meaning |
|-----|---------|
| `retroshine:latest` | Latest stable release |
| `retroshine:vX.Y.Z` | Specific version (pinned) |

### Version File

The `VERSION` file at the repository root always contains the current version without the `v` prefix.
Example: `1.0.0`

### Branch Strategy

- `master` — stable branch, receives all releases
- Tags are created from `master` only
- No development branches (single-maintainer project)
