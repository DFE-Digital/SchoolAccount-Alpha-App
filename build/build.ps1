<#
.SYNOPSIS
    Docker build automation script with functions for CI/CD and local development.

.DESCRIPTION
    This script provides functions for building Docker images using Docker Buildx Bake.
    It can be used both locally and in CI/CD pipelines to ensure consistent builds.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("Build", "DetermineMetadata", "PrintConfig", "TagImage", "ShowSummary")]
    [string]$Command = "Build",

    [Parameter()]
    [string]$Registry = "ghcr.io",

    [Parameter()]
    [string]$ImageName = "webapi",

    [Parameter()]
    [string]$Tag = "local",

    [Parameter()]
    [ValidateSet("webapi", "webapi-dev", "webapi-ci", "webapi-prod", "webapi-local-cached", "webapi-multi")]
    [string]$Target = "webapi",

    [Parameter()]
    [switch]$Push,

    [Parameter()]
    [switch]$NoCache,

    [Parameter()]
    [string]$CacheFrom = "",

    [Parameter()]
    [string]$CacheTo = "",

    [Parameter()]
    [string]$Version = "dev",

    [Parameter()]
    [ValidateSet("Debug", "Release")]
    [string]$BuildConfiguration = "Release",

# CI-specific parameters
    [Parameter()]
    [string]$GitRef = "",

    [Parameter()]
    [string]$GitRefName = "",

    [Parameter()]
    [string]$GitSha = "",

    [Parameter()]
    [string]$PullRequestNumber = "",

    [Parameter()]
    [string]$AdditionalTag = ""
)

$ErrorActionPreference = "Stop"

# Get the repository root
$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:BakeFile = Join-Path $script:RepoRoot "build" "docker-bake.hcl"

#region Helper Functions

function Write-ColorOutput {
    param(
        [string]$Message,
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White
    )
    Write-Host $Message -ForegroundColor $ForegroundColor
}

function Write-Header {
    param([string]$Title)
    Write-ColorOutput "=====================================" -ForegroundColor Cyan
    Write-ColorOutput $Title -ForegroundColor Cyan
    Write-ColorOutput "=====================================" -ForegroundColor Cyan
    Write-Host ""
}

function Test-DockerBuildx {
    try {
        $null = docker buildx version 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Docker buildx not available"
        }
        return $true
    } catch {
        Write-Error "Docker buildx is not available. Please install Docker Desktop or Docker with buildx plugin."
        return $false
    }
}

function Get-GitRevision {
    try {
        if ($GitSha) {
            return $GitSha.Substring(0, [Math]::Min(7, $GitSha.Length))
        }
        $revision = git rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -ne 0) { return "unknown" }
        return $revision
    } catch {
        return "unknown"
    }
}

function Get-BuildDate {
    return (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

#endregion

#region Core Functions

function Get-DockerMetadata {
    <#
    .SYNOPSIS
        Determines version and tag metadata for Docker builds (CI-compatible).
    
    .DESCRIPTION
        Calculates version, tag, revision, and build date based on Git context.
        Compatible with GitHub Actions environment.
    
    .EXAMPLE
        $metadata = Get-DockerMetadata -GitRef "refs/heads/main" -GitSha "abc123"
    #>
    [CmdletBinding()]
    param(
        [string]$GitRef = $script:GitRef,
        [string]$GitRefName = $script:GitRefName,
        [string]$GitSha = $script:GitSha,
        [string]$PullRequestNumber = $script:PullRequestNumber
    )

    $metadata = @{
        Version = "dev"
        Tag = "local"
        Revision = Get-GitRevision
        BuildDate = Get-BuildDate
    }

    # Determine version
    if ($GitRef -match '^refs/tags/v(.+)$') {
        $metadata.Version = $Matches[1]
    } elseif ($GitSha) {
        $metadata.Version = $GitSha
    }

    # Determine tag
    if ($GitRef -eq "refs/heads/main") {
        $metadata.Tag = "latest"
    } elseif ($GitRef -match '^refs/pull/') {
        $metadata.Tag = "pr-$PullRequestNumber"
    } elseif ($GitRefName) {
        # Sanitize branch name for Docker tag
        $metadata.Tag = $GitRefName -replace '[^a-zA-Z0-9]', '-'
    }

    return $metadata
}

function Show-BakeConfiguration {
    <#
    .SYNOPSIS
        Prints the Docker Buildx Bake configuration without building.
    
    .DESCRIPTION
        Shows the resolved bake file configuration for verification.
    
    .EXAMPLE
        Show-BakeConfiguration -Target "webapi-ci" -Registry "ghcr.io" -ImageName "myapp" -Tag "latest"
    #>
    [CmdletBinding()]
    param(
        [string]$Target = "webapi",
        [string]$Registry = "ghcr.io",
        [string]$ImageName = "webapi",
        [string]$Tag = "local",
        [string]$Version = "dev",
        [string]$Revision = "",
        [string]$BuildDate = "",
        [string]$BuildConfiguration = "Release",
        [bool]$Push = $false
    )

    if (-not $Revision) { $Revision = Get-GitRevision }
    if (-not $BuildDate) { $BuildDate = Get-BuildDate }

    $env:REGISTRY = $Registry
    $env:IMAGE_NAME = $ImageName
    $env:TAG = $Tag
    $env:BUILD_CONFIGURATION = $BuildConfiguration
    $env:PUSH = if ($Push) { "true" } else { "false" }
    $env:VERSION = $Version
    $env:REVISION = $Revision
    $env:BUILD_DATE = $BuildDate

    Write-ColorOutput "Bake Configuration:" -ForegroundColor Yellow
    & docker buildx bake -f $script:BakeFile --print $Target

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to print bake configuration"
    }
}

function Invoke-DockerBuild {
    <#
    .SYNOPSIS
        Builds Docker image using Docker Buildx Bake.
    
    .DESCRIPTION
        Executes docker buildx bake with the specified parameters.
    
    .EXAMPLE
        Invoke-DockerBuild -Target "webapi-ci" -Registry "ghcr.io" -ImageName "myapp" -Tag "1.0.0" -Push
    #>
    [CmdletBinding()]
    param(
        [string]$Target = "webapi",
        [string]$Registry = "ghcr.io",
        [string]$ImageName = "webapi",
        [string]$Tag = "local",
        [string]$Version = "dev",
        [string]$Revision = "",
        [string]$BuildDate = "",
        [string]$BuildConfiguration = "Release",
        [bool]$Push = $false,
        [bool]$NoCache = $false,
        [string]$CacheFrom = "",
        [string]$CacheTo = ""
    )

    if (-not (Test-DockerBuildx)) {
        throw "Docker Buildx is not available"
    }

    if (-not (Test-Path $script:BakeFile)) {
        throw "Docker bake file not found at: $script:BakeFile"
    }

    if (-not $Revision) { $Revision = Get-GitRevision }
    if (-not $BuildDate) { $BuildDate = Get-BuildDate }

    $fullImageName = "$Registry/$ImageName`:$Tag"

    Write-Header "Docker Buildx Bake Build"

    Write-ColorOutput "Configuration:" -ForegroundColor Yellow
    Write-ColorOutput "  Repository Root: $script:RepoRoot" -ForegroundColor Gray
    Write-ColorOutput "  Bake File: $script:BakeFile" -ForegroundColor Gray
    Write-ColorOutput "  Target: $Target" -ForegroundColor Gray
    Write-ColorOutput "  Image Name: $fullImageName" -ForegroundColor Gray
    Write-ColorOutput "  Version: $Version" -ForegroundColor Gray
    Write-ColorOutput "  Revision: $Revision" -ForegroundColor Gray
    Write-ColorOutput "  Build Configuration: $BuildConfiguration" -ForegroundColor Gray
    Write-ColorOutput "  Push to Registry: $Push" -ForegroundColor Gray
    Write-ColorOutput "  No Cache: $NoCache" -ForegroundColor Gray
    if ($CacheFrom) { Write-ColorOutput "  Cache From: $CacheFrom" -ForegroundColor Gray }
    if ($CacheTo) { Write-ColorOutput "  Cache To: $CacheTo" -ForegroundColor Gray }
    Write-Host ""

    Push-Location $script:RepoRoot

    try {
        # Set environment variables for bake
        $env:REGISTRY = $Registry
        $env:IMAGE_NAME = $ImageName
        $env:TAG = $Tag
        $env:BUILD_CONFIGURATION = $BuildConfiguration
        $env:PUSH = if ($Push) { "true" } else { "false" }
        $env:VERSION = $Version
        $env:REVISION = $Revision
        $env:BUILD_DATE = $BuildDate

        if ($CacheFrom) { $env:CACHE_FROM = $CacheFrom }
        if ($CacheTo) { $env:CACHE_TO = $CacheTo }

        # Build command arguments
        $bakeArgs = @("buildx", "bake", "-f", $script:BakeFile)

        if ($NoCache) {
            $bakeArgs += "--no-cache"
        }

        $bakeArgs += $Target

        Write-ColorOutput "Building Docker image with buildx bake..." -ForegroundColor Yellow
        Write-ColorOutput "Command: docker $($bakeArgs -join ' ')" -ForegroundColor Gray
        Write-Host ""

        # Execute Docker buildx bake
        & docker $bakeArgs

        if ($LASTEXITCODE -ne 0) {
            throw "Docker buildx bake failed with exit code: $LASTEXITCODE"
        }

        Write-Host ""
        Write-ColorOutput "✓ Docker image built successfully: $fullImageName" -ForegroundColor Green
        Write-Host ""

        # Display image info (only for local builds)
        if ($Target -notin @("webapi-multi", "webapi-ci") -and -not $Push) {
            Write-ColorOutput "Image Details:" -ForegroundColor Yellow
            docker images $fullImageName --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
            Write-Host ""
        }

        return @{
            Success = $true
            ImageName = $fullImageName
            Tag = $Tag
            Version = $Version
            Revision = $Revision
        }

    } finally {
        Pop-Location
    }
}

function Add-DockerImageTag {
    <#
    .SYNOPSIS
        Tags an existing Docker image with an additional tag.
    
    .DESCRIPTION
        Uses docker buildx imagetools to create additional tags for an existing image.
        This is useful for adding SHA-based tags or other alternative tags.
    
    .EXAMPLE
        Add-DockerImageTag -SourceImage "ghcr.io/myapp:latest" -TargetTag "ghcr.io/myapp:sha-abc123"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceImage,

        [Parameter(Mandatory)]
        [string]$TargetTag
    )

    Write-ColorOutput "Tagging image with additional tag..." -ForegroundColor Yellow
    Write-ColorOutput "  Source: $SourceImage" -ForegroundColor Gray
    Write-ColorOutput "  Target: $TargetTag" -ForegroundColor Gray

    & docker buildx imagetools create $SourceImage --tag $TargetTag

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to tag image with exit code: $LASTEXITCODE"
    }

    Write-ColorOutput "✓ Image tagged successfully" -ForegroundColor Green
}

function Write-BuildSummary {
    <#
    .SYNOPSIS
        Writes a build summary to console and optionally to GitHub Actions summary.
    
    .DESCRIPTION
        Outputs a formatted summary of the Docker build including image details and pull commands.
    
    .EXAMPLE
        Write-BuildSummary -Registry "ghcr.io" -ImageName "myapp" -Tag "1.0.0" -Version "1.0.0" -Revision "abc123"
    #>
    [CmdletBinding()]
    param(
        [string]$Registry,
        [string]$ImageName,
        [string]$Tag,
        [string]$Version,
        [string]$Revision,
        [string]$GitHubStepSummary = $env:GITHUB_STEP_SUMMARY
    )

    $fullImageName = "$Registry/$ImageName`:$Tag"

    Write-Header "Build Complete!"

    Write-ColorOutput "Image: $fullImageName" -ForegroundColor Green
    Write-ColorOutput "Version: $Version" -ForegroundColor Green
    Write-ColorOutput "Revision: $Revision" -ForegroundColor Green
    Write-Host ""
    Write-ColorOutput "Pull command:" -ForegroundColor Yellow
    Write-ColorOutput "  docker pull $fullImageName" -ForegroundColor Gray
    Write-Host ""

    # Write to GitHub Actions summary if available
    if ($GitHubStepSummary -and (Test-Path $GitHubStepSummary -IsValid)) {
        $summary = @"
### Docker Build Summary :rocket:

**Image:** ``$fullImageName``
**Version:** ``$Version``
**Revision:** ``$Revision``

**Pull command:**
``````bash
docker pull $fullImageName
``````
"@
        Add-Content -Path $GitHubStepSummary -Value $summary
    }
}

#endregion

#region Main Execution

# Execute the specified command
switch ($Command) {
    "DetermineMetadata" {
        $metadata = Get-DockerMetadata -GitRef $GitRef -GitRefName $GitRefName -GitSha $GitSha -PullRequestNumber $PullRequestNumber

        # Output in GitHub Actions format if running in CI
        if ($env:GITHUB_OUTPUT) {
            Add-Content -Path $env:GITHUB_OUTPUT -Value "version=$($metadata.Version)"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "tag=$($metadata.Tag)"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "revision=$($metadata.Revision)"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "build_date=$($metadata.BuildDate)"
        }

        # Also output to console
        Write-ColorOutput "Metadata determined:" -ForegroundColor Yellow
        $metadata.GetEnumerator() | ForEach-Object {
            Write-ColorOutput "  $($_.Key): $($_.Value)" -ForegroundColor Gray
        }

        return $metadata
    }

    "PrintConfig" {
        Show-BakeConfiguration -Target $Target -Registry $Registry -ImageName $ImageName -Tag $Tag `
            -Version $Version -BuildConfiguration $BuildConfiguration -Push:$Push
    }

    "TagImage" {
        if (-not $AdditionalTag) {
            throw "AdditionalTag parameter is required for TagImage command"
        }
        $sourceImage = "$Registry/$ImageName`:$Tag"
        Add-DockerImageTag -SourceImage $sourceImage -TargetTag $AdditionalTag
    }

    "ShowSummary" {
        Write-BuildSummary -Registry $Registry -ImageName $ImageName -Tag $Tag -Version $Version -Revision (Get-GitRevision)
    }

    "Build" {
        $result = Invoke-DockerBuild -Target $Target -Registry $Registry -ImageName $ImageName -Tag $Tag `
            -Version $Version -BuildConfiguration $BuildConfiguration -Push:$Push -NoCache:$NoCache `
            -CacheFrom $CacheFrom -CacheTo $CacheTo

        if ($result.Success) {
            Write-BuildSummary -Registry $Registry -ImageName $ImageName -Tag $result.Tag `
                -Version $result.Version -Revision $result.Revision
        }
    }
}

#endregion