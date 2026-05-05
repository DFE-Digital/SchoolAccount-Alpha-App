# build.ps1
# Simple Docker build and tag script

param(
    [Parameter(Mandatory=$false)]
    [string]$ImageName = "schoolaccount-alpha-app",

    [Parameter(Mandatory=$false)]
    [string]$Tag = "latest",

    [Parameter(Mandatory=$false)]
    [string]$DockerfilePath = "",

    [Parameter(Mandatory=$false)]
    [string]$DockerBuildContext = "",

    [Parameter(Mandatory=$false)]
    [string]$BuildConfiguration = "Release"
)

# Get the script's directory and calculate repository root
$ScriptRoot = $PSScriptRoot
$RepositoryRoot = Split-Path -Parent $ScriptRoot

# Set default paths relative to repository root if not provided
if ([string]::IsNullOrEmpty($DockerfilePath)) {
    $DockerfilePath = Join-Path $RepositoryRoot "src/Web.Mvc"
}

if ([string]::IsNullOrEmpty($DockerBuildContext)) {
    $DockerBuildContext = $RepositoryRoot
}

# Resolve to absolute paths
$DockerfilePath = Resolve-Path $DockerfilePath -ErrorAction Stop
$DockerBuildContext = Resolve-Path $DockerBuildContext -ErrorAction Stop

# Full image name with tag
$FullImageName = "${ImageName}:${Tag}"

Write-Host "Building Docker image: $FullImageName" -ForegroundColor Green
Write-Host "Repository root: $RepositoryRoot" -ForegroundColor Cyan
Write-Host "Dockerfile location: $DockerfilePath" -ForegroundColor Cyan
Write-Host "Build context: $DockerBuildContext" -ForegroundColor Cyan
Write-Host "Build configuration: $BuildConfiguration" -ForegroundColor Cyan
Write-Host ""

# Build the Docker image
docker build `
    --build-arg BUILD_CONFIGURATION=$BuildConfiguration `
    -t $FullImageName `
    -f "$DockerfilePath/Dockerfile" `
    $DockerBuildContext

# Check if build was successful
if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Docker image built successfully: $FullImageName" -ForegroundColor Green

    # Display the image info
    Write-Host ""
    Write-Host "Image details:" -ForegroundColor Cyan
    docker images $ImageName
} else {
    Write-Host ""
    Write-Host "Docker build failed with exit code: $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}